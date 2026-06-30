// =============================================================
// 01_constraints_indexes.cypher
// Run FIRST. Establishes uniqueness constraints (which also create
// backing indexes) + extra lookup/full-text indexes.
// Syntax targets Neo4j 5.x. Uniqueness works on Community Edition;
// node-key & existence constraints require Enterprise (noted below).
// =============================================================

// ---- n10s / neosemantics requirement (for ontology import in step 02) ----
CREATE CONSTRAINT n10s_unique_uri IF NOT EXISTS
FOR (r:Resource) REQUIRE r.uri IS UNIQUE;

// ---------------- DATA NODES ----------------
CREATE CONSTRAINT target_id   IF NOT EXISTS FOR (t:Target)      REQUIRE t.ensemblId IS UNIQUE;
CREATE CONSTRAINT drug_id     IF NOT EXISTS FOR (d:Drug)        REQUIRE d.chemblId  IS UNIQUE;
CREATE CONSTRAINT variant_id  IF NOT EXISTS FOR (v:Variant)     REQUIRE v.variantId IS UNIQUE;
CREATE CONSTRAINT assoc_id    IF NOT EXISTS FOR (a:Association) REQUIRE a.id        IS UNIQUE;
CREATE CONSTRAINT evidence_id IF NOT EXISTS FOR (e:Evidence)    REQUIRE e.id        IS UNIQUE;
CREATE CONSTRAINT pub_id      IF NOT EXISTS FOR (p:Publication) REQUIRE p.pmid      IS UNIQUE;
CREATE CONSTRAINT source_id   IF NOT EXISTS FOR (s:DataSource)  REQUIRE s.id        IS UNIQUE;

// ---------------- BACKBONE (ONTOLOGY) NODES ----------------
CREATE CONSTRAINT disease_id  IF NOT EXISTS FOR (n:Disease)        REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT pheno_id    IF NOT EXISTS FOR (n:Phenotype)      REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT go_id       IF NOT EXISTS FOR (n:GOTerm)         REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT pathway_id  IF NOT EXISTS FOR (n:Pathway)        REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT anatomy_id  IF NOT EXISTS FOR (n:Anatomy)        REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT cell_id     IF NOT EXISTS FOR (n:CellType)       REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT biomarker_id IF NOT EXISTS FOR (n:Biomarker)     REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT ae_id       IF NOT EXISTS FOR (n:AdverseEvent)   REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT mp_id       IF NOT EXISTS FOR (n:MousePhenotype) REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT so_id       IF NOT EXISTS FOR (n:SOTerm)         REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT eco_id      IF NOT EXISTS FOR (n:ECOTerm)        REQUIRE n.id   IS UNIQUE;
CREATE CONSTRAINT atc_code    IF NOT EXISTS FOR (n:ATCClass)       REQUIRE n.code IS UNIQUE;

// ---------------- LOOKUP INDEXES ----------------
CREATE INDEX target_symbol IF NOT EXISTS FOR (t:Target)  ON (t.symbol);
CREATE INDEX drug_name     IF NOT EXISTS FOR (d:Drug)    ON (d.name);
CREATE INDEX disease_name  IF NOT EXISTS FOR (n:Disease) ON (n.name);

// ---------------- FULL-TEXT (entity resolution for agents) ----------------
// Lets an LLM map free text ("Alzheimer's", "p53") to canonical IDs before traversal.
CREATE FULLTEXT INDEX entityNameSearch IF NOT EXISTS
FOR (n:Target|Disease|Drug|Phenotype|Biomarker|AdverseEvent)
ON EACH [n.name, n.symbol];

// ---------------- ENTERPRISE-ONLY (uncomment if available) ----------------
// Existence + node-key constraints harden the schema but require Enterprise Edition.
// CREATE CONSTRAINT target_symbol_exists IF NOT EXISTS
//   FOR (t:Target) REQUIRE t.symbol IS NOT NULL;

// Verify:
SHOW CONSTRAINTS;
