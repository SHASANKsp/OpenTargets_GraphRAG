# Neo4j Graph Model — Open Targets Super-Ontology Backbone

A domain-complete (life science / pharma / healthcare) property-graph schema. It is **not**
tied to any single application: target ID, biomarker discovery, safety, MoA, repurposing, and
genetics all read off the same backbone. Build it in the order below.

```
01_constraints_indexes.cypher   → schema: uniqueness, indexes, full-text search
02_load_ontologies.cypher       → skeleton: import OBO ontologies, normalize to domain nodes
03_ingest_opentargets.cypher    → data: load OT datasets onto the backbone
```

Everything **MERGEs on a canonical ID**, so ingestion is idempotent and every new dataset
attaches to existing nodes instead of duplicating them.

---

## Two kinds of node

**Backbone nodes** come from ontologies and carry an `IS_A` / `PART_OF` hierarchy:
`Disease`, `Phenotype`, `GOTerm`, `Pathway`, `Anatomy`, `CellType`, `Biomarker`,
`AdverseEvent`, `MousePhenotype`, `SOTerm`, `ECOTerm`, `ATCClass`.

**Data nodes** come from Open Targets and link *into* the backbone:
`Target`, `Drug`, `Variant`, `Association`, `Evidence`, `Publication`, `DataSource`.

Every node also gets a shared `:Concept` label (backbone) or stays bare (data), and every node
carries a canonical `id` property in CURIE form (`EFO:0000400`, `GO:0006915`) or native key
(`ENSG00000141510`, `CHEMBL25`).

---

## Node catalog

| Label | Key property | Source | Key extra props |
|---|---|---|---|
| `Target` | `ensemblId` | OT target | `symbol`, `name`, `biotype`, `uniprotIds` |
| `Disease` | `id` (EFO) | EFO/MONDO | `name`, `therapeuticAreas` |
| `Phenotype` | `id` (HP) | HPO | `name` |
| `Drug` | `chemblId` | ChEMBL | `name`, `drugType`, `maxPhase`, `isApproved` |
| `Variant` | `variantId` | OT genetics | `rsId`, `chrom`, `pos`, `ref`, `alt` |
| `GOTerm` | `id` (GO) | Gene Ontology | `name`, `aspect` (P/F/C) |
| `Pathway` | `id` (R-HSA) | Reactome | `name` |
| `Anatomy` | `id` (UBERON) | UBERON | `name` |
| `CellType` | `id` (CL) | Cell Ontology | `name` |
| `Biomarker` | `id` (OBA) | OBA | `name` |
| `AdverseEvent` | `id` (MedDRA) | MedDRA | `name`, `level` (PT/SOC) |
| `MousePhenotype` | `id` (MP) | Mammalian Phenotype | `name` |
| `SOTerm` | `id` (SO) | Sequence Ontology | `name` |
| `ECOTerm` | `id` (ECO) | Evidence & Conclusion | `name` |
| `ATCClass` | `code` | ATC | `name`, `level` |
| `Association` | `id` (`target|disease`) | OT association | `overallScore` |
| `Evidence` | `id` | OT evidence | `score`, `datatypeId` |
| `Publication` | `pmid` | Europe PMC | `year` |
| `DataSource` | `id` | OT | `name`, `datatype` |

---

## Relationship catalog

**Backbone hierarchy & mappings**
```
(:Disease)-[:IS_A]->(:Disease)
(:Disease)-[:HAS_PHENOTYPE]->(:Phenotype)
(:GOTerm)-[:IS_A]->(:GOTerm)
(:Pathway)-[:PART_OF]->(:Pathway)
(:Anatomy)-[:PART_OF]->(:Anatomy)
(:CellType)-[:IS_A]->(:CellType)
(:Biomarker)-[:IS_A]->(:Biomarker)
(:AdverseEvent)-[:IS_A]->(:AdverseEvent)        // PT -> SOC
(:MousePhenotype)-[:IS_A]->(:MousePhenotype)
(c)-[:EXACT_MATCH|CLOSE_MATCH|BROAD_MATCH {source, confidence}]->(c2)   // SSSOM cross-refs
```

**Target annotation**
```
(:Target)-[:HAS_FUNCTION {evidence}]->(:GOTerm)
(:Target)-[:PARTICIPATES_IN]->(:Pathway)
(:Target)-[:EXPRESSED_IN {tpm, level}]->(:Anatomy)
(:Target)-[:HAS_SAFETY_LIABILITY {effect, source}]->(:Anatomy|:AdverseEvent)
(:Target)-[:HAS_MOUSE_PHENOTYPE]->(:MousePhenotype)
(:Target)-[:INTERACTS_WITH {score, source}]->(:Target)
```

**Reified target–disease evidence** (the heart of Open Targets)
```
(:Target)-[:HAS_ASSOCIATION]->(:Association)-[:WITH_DISEASE]->(:Disease)
(:Evidence)-[:SUPPORTS]->(:Association)
(:Evidence)-[:FROM_SOURCE]->(:DataSource)
(:Evidence)-[:EVIDENCE_TYPE]->(:ECOTerm)
(:Evidence)-[:CITES]->(:Publication)
```

**Drug**
```
(:Drug)-[:TARGETS {actionType}]->(:Target)        // mechanism of action
(:Drug)-[:INDICATED_FOR {maxPhase}]->(:Disease)
(:Drug)-[:HAS_ADVERSE_EVENT {llr, count}]->(:AdverseEvent)   // FAERS pharmacovigilance
(:Drug)-[:HAS_ATC]->(:ATCClass)
```

**Variant / genetics**
```
(:Variant)-[:IN_TARGET]->(:Target)
(:Variant)-[:ASSOCIATED_WITH {beta, pval}]->(:Disease)
(:Variant)-[:HAS_CONSEQUENCE]->(:SOTerm)
```

**Biomarker**
```
(:Biomarker)-[:MEASURES]->(:Target|:Disease|:Anatomy)
```

---

## Why evidence is reified

A plain `(:Target)-[:ASSOCIATED_WITH]->(:Disease)` edge can't hold a score, a datasource, an
evidence type, and a citation list at the same time — and OT associations are aggregates of
many scored evidence pieces. So `Association` (the aggregate) and `Evidence` (each piece) are
**nodes**. This lets an agent ask "show me the genetic evidence above score 0.5, with papers"
without losing provenance. Don't shortcut this.

---

## Open Targets dataset → graph mapping

OT ships Parquet. Stable join keys: `targetId` (ENSG), `diseaseId` (EFO), `drugId` (ChEMBL).

| OT dataset | Becomes |
|---|---|
| `target` | `Target` nodes + `HAS_FUNCTION`→GO, `PARTICIPATES_IN`→Reactome |
| `disease` | `Disease` nodes + `IS_A` hierarchy (also from ontology load) |
| `molecule` (drug) | `Drug` nodes |
| `mechanismOfAction` | `Drug -[:TARGETS]-> Target` |
| `indication` | `Drug -[:INDICATED_FOR]-> Disease` |
| `evidence` (per source) | `Evidence` nodes + `SUPPORTS`/`FROM_SOURCE`/`CITES` |
| `associationByOverall*` | `Association` nodes + `HAS_ASSOCIATION`/`WITH_DISEASE` |
| `baselineExpression` | `Target -[:EXPRESSED_IN]-> Anatomy` |
| `targetSafety` | `Target -[:HAS_SAFETY_LIABILITY]-> Anatomy/AdverseEvent` |
| `mousePhenotypes` | `Target -[:HAS_MOUSE_PHENOTYPE]-> MousePhenotype` |
| `drugWarnings` / FAERS | `Drug -[:HAS_ADVERSE_EVENT]-> AdverseEvent` |
| `interaction` | `Target -[:INTERACTS_WITH]-> Target` |
| variant / L2G / credibleSet | `Variant` nodes + genetics edges |

⚠ Exact nested field names shift per release — inspect the Parquet schema for your version
(`evd.printSchema()` in Spark) before mapping. The IDs above are stable.

---

## Loading mechanics

Neo4j can't read Parquet directly. Two paths:

1. **Python ETL (recommended for nested OT data):** read Parquet with `pyarrow`/`pandas`,
   explode nested arrays, write via the official `neo4j` driver in batched `UNWIND ... MERGE`
   transactions. Handles OT's nested structures cleanly.
2. **Flatten → CSV/JSON, then `LOAD CSV` / `apoc.load.json`:** simpler, good for a first pass.
   `03_ingest_opentargets.cypher` shows this pattern.

Always `MERGE` on the canonical key, never `CREATE`, so re-runs are idempotent.

---

## Run order

1. `01_constraints_indexes.cypher` — must run first; MERGE is slow without the unique indexes.
2. `02_load_ontologies.cypher` — load EFO/GO/etc. via n10s, normalize to clean domain nodes.
3. `03_ingest_opentargets.cypher` — load OT data onto the backbone.
4. Add a vector index over node `name`/`description` for hybrid GraphRAG by your agents.

---

## Notes for the agentic / LLM layer

- The relationship catalog above *is* your agent's tool surface — expose parameterized Cypher
  templates (e.g. `targets_for_disease(efoId)`, `safety_profile(ensemblId)`) rather than letting
  the model free-write Cypher.
- Keep human-readable `name` on every node so retrieved subgraphs are self-describing in a prompt.
- A full-text + vector index lets agents resolve "Alzheimer's" → `EFO:...` before traversing.
