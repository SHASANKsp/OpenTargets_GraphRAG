# Super-Ontology Architecture for an Open Targets Knowledge Graph

A semantic backbone designed so that target-identification, biomarker-discovery, and
safety-assessment data all attach to one shared, queryable structure. The principle:
**adopt the ontologies Open Targets already commits to, then add a thin upper schema and
an explicit alignment layer that glues them together.**

---

## The layered model

Think of the graph as four layers. You build them top-down, then load data bottom-up.

```
Layer 0  Upper schema (your spine)        — entity classes + canonical relations
Layer 1  Source ontologies (skeletons)    — imported reference hierarchies + IDs
Layer 2  Alignment / bridge layer (glue)  — cross-ontology mappings + relation predicates
Layer 3  Instance / data layer            — Open Targets evidence, added later
```

The "semantic" payoff lives in Layer 2 — that is what turns a pile of ontologies into a
*connected* one.

---

## Layer 0 — Upper schema (the spine you own)

A small set of core classes and canonical relations under your own namespace. Everything
else hangs off these. Mirror Open Targets' three entities, then extend for biomarkers and
safety.

**Core classes**

| Class | Backing reference | Notes |
|---|---|---|
| Target | Ensembl gene (ENSG) → UniProt | gene/protein |
| Disease / Phenotype | EFO (imports MONDO, HPO, Orphanet) | OT's core entity |
| Drug / Molecule | ChEMBL + ChEBI | small molecule + biologic |
| Variant | dbSNP (rs) + Sequence Ontology (SO) | germline/somatic |
| Pathway | Reactome | systems biology |
| MolecularFunction / BiologicalProcess / CellularComponent | Gene Ontology (GO) | target annotation |
| Anatomy / Tissue | UBERON | expression localization |
| CellType | Cell Ontology (CL) | single-cell expression |
| Biomarker / Measurement | OBA (Ontology of Biological Attributes) | quantitative traits |
| AdverseEvent | MedDRA (licensed) | pharmacovigilance |
| SafetyLiability | OT target-safety + MP (mouse phenotype) | tissue/animal safety |
| Evidence | reified — carries score + provenance | the heart of OT |
| Study / Publication | PMID / Europe PMC | text-mining provenance |

**Canonical relations** (name them once, reuse everywhere)

- `Target —associated_with→ Disease` (scored, reified as Evidence)
- `Target —has_evidence→ Evidence`
- `Drug —has_mechanism_of_action→ Target`
- `Drug —indicated_for→ Disease`
- `Drug —has_adverse_event→ AdverseEvent`
- `Target —participates_in→ Pathway`
- `Target —has_function→ GO term`
- `Target —expressed_in→ Anatomy / CellType`
- `Target —has_safety_liability→ SafetyLiability`
- `Variant —located_in→ Target`, `Variant —associated_with→ Disease`
- `Biomarker —measures→ Target | Disease | Anatomy`
- `Disease —has_phenotype→ HPO term`

---

## Layer 1 — Source ontologies (the imported skeletons)

Adopt these as-is so your nodes inherit a ready-made hierarchy and a canonical, resolvable
ID. **Do not import the full giant ontologies** — extract only the modules you need
(see tooling below).

| Domain | Ontology | ID prefix | Why |
|---|---|---|---|
| Disease / phenotype | **EFO** (core) | `EFO:` | exactly what OT uses; pulls in the rest |
| Disease | MONDO | `MONDO:` | merged disease ontology, inside EFO |
| Human phenotype | HPO | `HP:` | disease→phenotype links |
| Rare disease | Orphanet | `Orphanet:` | rare-disease genetics |
| Gene | Ensembl | `ENSG` | OT target identifier |
| Protein | UniProt | `UniProtKB:` | protein-level annotation |
| Gene function | Gene Ontology | `GO:` | MF / BP / CC |
| Pathways | Reactome | `R-HSA-` | pathway membership |
| Anatomy | UBERON | `UBERON:` | expression / tissue safety |
| Cell type | Cell Ontology | `CL:` | single-cell expression |
| Chemistry | ChEBI | `CHEBI:` | molecule structure/class |
| Drug | ChEMBL | `CHEMBL` | OT drug identifier |
| Drug class | ATC | `ATC:` | therapeutic classification |
| Adverse events | MedDRA | `MedDRA:` | FAERS pharmacovigilance (⚠ licensed) |
| Mouse phenotype | Mammalian Phenotype | `MP:` | animal-model safety |
| Measurements / traits | OBA | `OBA:` | biomarkers, quantitative traits |
| Variant consequence | Sequence Ontology | `SO:` | variant typing |
| Evidence type | Evidence & Conclusion Ontology | `ECO:` | provenance/quality of evidence |
| Literature | MeSH / Europe PMC | `MeSH:`, `PMID:` | text-mining sources |

⚠ **MedDRA is not open** — it requires a license. If that is a blocker, you can lean on the
FAERS adverse-event strings OT exposes and map them yourself, but plan for this early.

---

## Layer 2 — Alignment / bridge layer (the glue)

This is what makes it a *super* ontology. Three mechanisms:

1. **Cross-reference mappings.** EFO already xrefs to MONDO, HPO, OMIM, ICD-10, SNOMED, and
   UMLS. Capture these as first-class mapping records using **SSSOM** (Simple Standard for
   Sharing Ontological Mappings) so every equivalence carries provenance and a confidence,
   instead of silent string-matching.

2. **Standard predicates, not bespoke edges.** Use:
   - `skos:exactMatch / closeMatch / broadMatch` for cross-ontology identity links
   - **RO** (Relation Ontology) for biology: `RO:0002331 involved_in`, `RO:0000056 participates_in`,
     `BFO:0000050 part_of`, `RO:0002162 in_taxon`
   - **PROV-O** for "where did this come from"

   Reusing RO/SKOS/PROV is the single biggest lever for interoperability — other tools and
   LLM agents already understand these.

3. **Backbone bridges between domains:**
   - `Ensembl gene → UniProt protein → GO function / Reactome pathway`
   - `Target → UBERON anatomy` via expression data
   - `EFO/MONDO disease → HPO phenotype` (OT ingests these via Monarch)
   - `Drug (ChEMBL) → ChEBI structure` and `→ ATC class`
   - `Variant (SO) → Target` and `→ Disease`

---

## Layer 3 — Instance / data layer (Open Targets, added later)

OT ships datasets as **Parquet** (target, disease, drug/molecule, evidence, association,
known-drug, expression, target-safety, mouse-phenotype, etc.). Each becomes either edges or
reified nodes that *reference* Layer 0 classes and Layer 1 IDs. Because the IDs already match
(EFO, ENSG, ChEMBL), ingestion becomes a mapping exercise, not a reconciliation nightmare —
which is the entire point of building the backbone first.

---

## The one decision that shapes everything: reify the evidence

Open Targets is fundamentally about **scored, provenanced** target–disease evidence. A plain
edge cannot carry a score, a datasource, an ECO evidence type, and a publication list. So:

- **Property-graph route (Neo4j etc.):** make `Evidence` and `Association` their own nodes,
  with `score`, `datasourceId`, `datatypeId`, `ecoId` as properties, linked to Target/Disease.
- **RDF route:** reify via **RDF-star**, named graphs, or an explicit `Evidence` class +
  PROV-O. Use SHACL to validate.

Get this right up front; retrofitting provenance later is painful.

---

## Use-case → backbone mapping

**Target identification** — Target ⇄ Association ⇄ Disease, decorated with GO function,
Reactome pathways, tractability, and genetic evidence. This is the core OT graph.

**Biomarker discovery** — lean on **OBA** (measurements/quantitative traits) + expression
(UBERON/CL) + genetics (variant→trait). Biomarker nodes link a measurable attribute to a
Target/Disease/Tissue. This is why EFO's move to OBA matters.

**Safety assessment** — `Target —has_safety_liability→` (OT target-safety, organ systems via
UBERON), `Drug —has_adverse_event→` (FAERS/MedDRA), and mouse phenotypes (MP). Tissue
expression doubles as an on-target-safety signal.

---

## Tooling

| Need | Tool |
|---|---|
| Extract ontology modules (don't load the whole thing) | **ROBOT** (`extract`, SLME) |
| Programmatic ontology access / traversal | **OAK** (Ontology Access Kit) |
| Canonical prefixes / ID resolution | **Bioregistry** |
| Mappings with provenance | **SSSOM** toolkit |
| RDF stores | Apache Jena / GraphDB / Oxigraph / Blazegraph |
| Property graph | Neo4j (+ **n10s/neosemantics** to bridge RDF) / Memgraph |
| Validation | SHACL (RDF) or schema constraints (LPG) |
| Agentic / LLM retrieval | graph schema as the agent's tool surface; add a vector index over node text for hybrid GraphRAG |

---

## Recommended build order

1. Stand up Layer 0 upper schema (classes + relations + your namespace).
2. Import **EFO** first (it transitively brings MONDO/HPO/UBERON/CL/ChEBI), then add GO,
   Reactome, OBA, MP, SO, ECO as extracted modules.
3. Materialize Layer 2 mappings (SSSOM) and wire in RO/SKOS/PROV predicates.
4. Validate the empty backbone (SHACL / constraints) before any data touches it.
5. Ingest Open Targets Parquet datasets, mapping columns → schema.
6. Layer on a vector index for hybrid retrieval by your agents.

---

## Foundational principles to bake in

- **One canonical ID per node**, native CURIEs preserved (`EFO:0000400`, `ENSG...`, `CHEMBL...`).
- **Reuse OBO Foundry + RO + BFO** as your upper-ontology grammar — free interoperability.
- **Provenance is not optional** — every edge/association should answer "which datasource,
  which evidence type, which paper, what score."
- **Modules over monoliths** — extract relevant slices; full ontologies will bloat the graph.
- **Mappings are data** — store them (SSSOM), version them, don't hardcode string joins.
