// =============================================================
// 03_ingest_opentargets.cypher
// Run THIRD. Loads Open Targets data onto the ontology backbone.
//
// INPUT: OT ships Parquet. Either (a) run a Python ETL that reads Parquet,
// explodes nested arrays, and batches UNWIND...MERGE via the neo4j driver,
// or (b) flatten to CSV/JSON first and use the patterns below.
// These examples assume flattened CSVs in the import/ folder.
//
// GOLDEN RULE: always MERGE on the canonical key, never CREATE — so
// re-ingestion is idempotent and data snaps onto existing backbone nodes.
// =============================================================

// ---------------- TARGETS ----------------
LOAD CSV WITH HEADERS FROM 'file:///targets.csv' AS row
MERGE (t:Target {ensemblId: row.id})
SET t.symbol  = row.approvedSymbol,
    t.name    = row.approvedName,
    t.biotype = row.biotype;

// target -> GO function (one flattened row per target/GO pair)
LOAD CSV WITH HEADERS FROM 'file:///target_go.csv' AS row
MATCH (t:Target {ensemblId: row.targetId})
MATCH (g:GOTerm {id: row.goId})
MERGE (t)-[r:HAS_FUNCTION]->(g)
SET r.evidence = row.evidence, r.aspect = row.aspect;

// target -> Reactome pathway
LOAD CSV WITH HEADERS FROM 'file:///target_pathway.csv' AS row
MATCH (t:Target {ensemblId: row.targetId})
MATCH (p:Pathway {id: row.pathwayId})
MERGE (t)-[:PARTICIPATES_IN]->(p);

// ---------------- DISEASES ----------------
// Disease nodes already exist from the ontology load (02). This enriches
// them with OT-specific annotation (e.g. therapeutic areas) and backfills
// any disease referenced by evidence but absent from the extracted module.
LOAD CSV WITH HEADERS FROM 'file:///diseases.csv' AS row
MERGE (d:Disease:Concept {id: row.id})
SET d.name = coalesce(d.name, row.name),
    d.therapeuticAreas = split(row.therapeuticAreas, '|');

// ---------------- DRUGS ----------------
LOAD CSV WITH HEADERS FROM 'file:///drugs.csv' AS row
MERGE (d:Drug {chemblId: row.id})
SET d.name       = row.name,
    d.drugType   = row.drugType,
    d.maxPhase   = toInteger(row.maximumClinicalTrialPhase),
    d.isApproved = (row.isApproved = 'true');

// mechanism of action: Drug -> Target
LOAD CSV WITH HEADERS FROM 'file:///mechanism_of_action.csv' AS row
MATCH (dr:Drug {chemblId: row.drugId})
MATCH (t:Target {ensemblId: row.targetId})
MERGE (dr)-[r:TARGETS]->(t)
SET r.actionType = row.actionType;

// indications: Drug -> Disease
LOAD CSV WITH HEADERS FROM 'file:///indications.csv' AS row
MATCH (dr:Drug {chemblId: row.drugId})
MATCH (d:Disease {id: row.diseaseId})
MERGE (dr)-[r:INDICATED_FOR]->(d)
SET r.maxPhase = toInteger(row.maxPhaseForIndication);

// ---------------- ASSOCIATIONS (aggregated, scored) ----------------
LOAD CSV WITH HEADERS FROM 'file:///association_overall.csv' AS row
MATCH (t:Target {ensemblId: row.targetId})
MATCH (d:Disease {id: row.diseaseId})
MERGE (a:Association {id: row.targetId + '|' + row.diseaseId})
SET a.overallScore = toFloat(row.score)
MERGE (t)-[:HAS_ASSOCIATION]->(a)
MERGE (a)-[:WITH_DISEASE]->(d);

// ---------------- EVIDENCE (reified, with provenance) ----------------
LOAD CSV WITH HEADERS FROM 'file:///evidence.csv' AS row
MATCH (t:Target {ensemblId: row.targetId})
MATCH (d:Disease {id: row.diseaseId})
MERGE (s:DataSource {id: row.datasourceId})
  SET s.datatype = row.datatypeId
MERGE (a:Association {id: row.targetId + '|' + row.diseaseId})
MERGE (t)-[:HAS_ASSOCIATION]->(a)
MERGE (a)-[:WITH_DISEASE]->(d)
MERGE (e:Evidence {id: row.id})
  SET e.score = toFloat(row.score), e.datatypeId = row.datatypeId
MERGE (e)-[:SUPPORTS]->(a)
MERGE (e)-[:FROM_SOURCE]->(s);

// link evidence -> publications (one row per evidence/pmid pair)
LOAD CSV WITH HEADERS FROM 'file:///evidence_publications.csv' AS row
MATCH (e:Evidence {id: row.evidenceId})
MERGE (p:Publication {pmid: row.pmid})
MERGE (e)-[:CITES]->(p);

// ---------------- EXPRESSION (baseline, tissue) ----------------
LOAD CSV WITH HEADERS FROM 'file:///baseline_expression.csv' AS row
MATCH (t:Target {ensemblId: row.targetId})
MATCH (an:Anatomy {id: row.uberonId})
MERGE (t)-[r:EXPRESSED_IN]->(an)
SET r.tpm = toFloat(row.tpm), r.level = row.level;

// ---------------- TARGET SAFETY ----------------
LOAD CSV WITH HEADERS FROM 'file:///target_safety.csv' AS row
MATCH (t:Target {ensemblId: row.targetId})
MATCH (an:Anatomy {id: row.uberonId})
MERGE (t)-[r:HAS_SAFETY_LIABILITY]->(an)
SET r.effect = row.effect, r.source = row.datasource;

// ---------------- MOUSE PHENOTYPES ----------------
LOAD CSV WITH HEADERS FROM 'file:///mouse_phenotypes.csv' AS row
MATCH (t:Target {ensemblId: row.targetId})
MATCH (mp:MousePhenotype {id: row.mpId})
MERGE (t)-[:HAS_MOUSE_PHENOTYPE]->(mp);

// ---------------- DRUG ADVERSE EVENTS (FAERS pharmacovigilance) ----------------
LOAD CSV WITH HEADERS FROM 'file:///drug_adverse_events.csv' AS row
MATCH (dr:Drug {chemblId: row.drugId})
MATCH (ae:AdverseEvent {id: row.meddraId})
MERGE (dr)-[r:HAS_ADVERSE_EVENT]->(ae)
SET r.llr = toFloat(row.logLR), r.count = toInteger(row.count);

// ---------------- PROTEIN-PROTEIN INTERACTIONS ----------------
LOAD CSV WITH HEADERS FROM 'file:///interactions.csv' AS row
MATCH (a:Target {ensemblId: row.targetA})
MATCH (b:Target {ensemblId: row.targetB})
MERGE (a)-[r:INTERACTS_WITH]->(b)
SET r.score = toFloat(row.score), r.source = row.sourceDatabase;

// =============================================================
// SANITY CHECKS
// =============================================================
// Node counts by label:
//   CALL db.labels() YIELD label
//   CALL apoc.cypher.run('MATCH (:`'+label+'`) RETURN count(*) AS c',{}) YIELD value
//   RETURN label, value.c ORDER BY value.c DESC;
//
// Example cross-domain query (target-ID + safety, one hop each):
//   MATCH (t:Target)-[:HAS_ASSOCIATION]->(a:Association)-[:WITH_DISEASE]->(d:Disease {id:'EFO:0000249'})
//   OPTIONAL MATCH (t)-[:HAS_SAFETY_LIABILITY]->(organ:Anatomy)
//   RETURN t.symbol, a.overallScore, collect(organ.name) AS safetyFlags
//   ORDER BY a.overallScore DESC LIMIT 25;
