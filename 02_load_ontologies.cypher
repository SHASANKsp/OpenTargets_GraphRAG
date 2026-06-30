// =============================================================
// 02_load_ontologies.cypher
// Run SECOND. Loads the OBO ontology skeleton (hierarchy + labels)
// using the neosemantics (n10s) plugin, then NORMALIZES the raw
// imported classes into clean domain nodes (:Disease, :GOTerm, ...).
//
// PREREQUISITES
//   1. Install the neosemantics plugin (n10s) matching your Neo4j version.
//   2. Pre-extract relevant modules with ROBOT so you don't load entire
//      giant ontologies:
//        robot extract --method BOT --input efo.owl --term-file disease_terms.txt \
//              --output efo_module.owl
//      Host the .owl files somewhere fetchable (file:/// or https://).
// =============================================================

// ---------- one-time n10s config ----------
CALL n10s.graphconfig.init({
  handleVocabUris: 'IGNORE',     // strip namespace prefixes from property names
  handleMultival:  'ARRAY',
  keepLangTag:     false,
  applyNeo4jNaming: true
});

// =============================================================
// STAGE 1 — import each ontology module.
// n10s.onto.import creates (:Class {uri, name, label}) nodes linked by
// [:SCO] (subClassOf). Adjust format to your file ('RDF/XML' | 'Turtle').
// =============================================================
CALL n10s.onto.import.fetch('file:///efo_module.owl',      'RDF/XML');
CALL n10s.onto.import.fetch('file:///go_module.owl',       'RDF/XML');
CALL n10s.onto.import.fetch('file:///reactome_module.owl', 'RDF/XML');
CALL n10s.onto.import.fetch('file:///uberon_module.owl',   'RDF/XML');
CALL n10s.onto.import.fetch('file:///cl_module.owl',       'RDF/XML');
CALL n10s.onto.import.fetch('file:///oba_module.owl',      'RDF/XML');
CALL n10s.onto.import.fetch('file:///mp_module.owl',       'RDF/XML');
CALL n10s.onto.import.fetch('file:///hp_module.owl',       'RDF/XML');
CALL n10s.onto.import.fetch('file:///so_module.owl',       'RDF/XML');
CALL n10s.onto.import.fetch('file:///eco_module.owl',      'RDF/XML');

// >>> Before normalizing, INSPECT what landed — n10s property names vary by version:
//     MATCH (c:Class) RETURN c LIMIT 5;
//     Confirm the URI pattern + which property holds the label, then adjust below.

// =============================================================
// STAGE 2 — normalize raw :Class nodes into clean domain nodes.
// Pattern per ontology: filter by URI namespace, mint canonical CURIE id,
// copy the label, attach the IS_A hierarchy. Repeat for each ontology.
// =============================================================

// ---- EFO/MONDO -> :Disease ----
MATCH (c:Class)
WHERE c.uri CONTAINS '/EFO_' OR c.uri CONTAINS '/MONDO_'
WITH c,
     replace(replace(split(c.uri,'/')[-1], 'EFO_', 'EFO:'), 'MONDO_', 'MONDO:') AS cid
MERGE (d:Disease:Concept {id: cid})
SET d.name = c.label, d.uri = c.uri;

MATCH (c:Class)-[:SCO]->(p:Class)
WHERE c.uri CONTAINS '/EFO_' AND p.uri CONTAINS '/EFO_'
MATCH (cd:Disease {uri: c.uri}), (pd:Disease {uri: p.uri})
MERGE (cd)-[:IS_A]->(pd);

// ---- GO -> :GOTerm ----
MATCH (c:Class) WHERE c.uri CONTAINS '/GO_'
WITH c, 'GO:' + split(c.uri,'_')[-1] AS gid
MERGE (g:GOTerm:Concept {id: gid})
SET g.name = c.label, g.uri = c.uri;

MATCH (c:Class)-[:SCO]->(p:Class)
WHERE c.uri CONTAINS '/GO_' AND p.uri CONTAINS '/GO_'
MATCH (cg:GOTerm {uri: c.uri}), (pg:GOTerm {uri: p.uri})
MERGE (cg)-[:IS_A]->(pg);

// ---- HP -> :Phenotype  /  UBERON -> :Anatomy  /  CL -> :CellType
//      OBA -> :Biomarker /  MP -> :MousePhenotype / SO -> :SOTerm
//      ECO -> :ECOTerm.  Same two-step pattern as above, swapping the
//      URI fragment ('/HP_', '/UBERON_', '/CL_', '/OBA_', '/MP_',
//      '/SO_', '/ECO_') and the target label. ----

// =============================================================
// STAGE 3 (optional) — cross-ontology mappings (SSSOM bridge layer).
// Load an SSSOM TSV of equivalences (e.g. EFO<->MONDO, disease<->phenotype)
// and materialize typed match edges with provenance.
// =============================================================
LOAD CSV WITH HEADERS FROM 'file:///mappings.sssom.tsv' AS row FIELDTERMINATOR '\t'
MATCH (a:Concept {id: row.subject_id})
MATCH (b:Concept {id: row.object_id})
CALL apoc.merge.relationship(
  a,
  CASE row.predicate_id
    WHEN 'skos:exactMatch' THEN 'EXACT_MATCH'
    WHEN 'skos:closeMatch' THEN 'CLOSE_MATCH'
    ELSE 'BROAD_MATCH' END,
  {source: row.mapping_source, confidence: toFloat(row.confidence)},
  {}, b
) YIELD rel
RETURN count(rel);

// Tidy up staging once normalization is verified:
// MATCH (c:Class)   DETACH DELETE c;
// MATCH (r:Resource) WHERE NOT r:Concept DETACH DELETE r;
