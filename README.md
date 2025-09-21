# GraphRAG for Target Prioritisation

This repository provides code and schema for building a **Knowledge Graph (KG)** from the [Open Targets](https://www.opentargets.org/) **target\_prioritisation** dataset, and integrating it with **GraphRAG**.

The aim is to support **AI-powered target prioritisation** — enabling researchers to query drug targets using natural language and get grounded, evidence-backed answers from a graph database (Neo4j) and an optional vector store for long-text evidence.

---

## Dataset

We use the **target\_prioritisation** dataset from Open Targets.

**Schema:**

| Column                             | Type  | Description                           |
| ---------------------------------- | ----- | ------------------------------------- |
| targetId                           | Text  | Ensembl gene ID (unique)              |
| isInMembrane                       | Int   | 1 if target is membrane protein       |
| isSecreted                         | Int   | 1 if target is secreted               |
| hasSafetyEvent                     | Int   | 1 if safety events are reported       |
| hasPocket                          | Int   | 1 if predicted binding pocket present |
| hasLigand                          | Int   | 1 if binds at least one ligand        |
| hasSmallMoleculeBinder             | Int   | 1 if small molecule binder exists     |
| geneticConstraint                  | Float | Intolerance to variation              |
| paralogMaxIdentityPercentage       | Float | Max paralogue identity (%)            |
| mouseOrthologMaxIdentityPercentage | Float | Mouse ortholog identity (%)           |
| isCancerDriverGene                 | Int   | 1 if cancer driver gene               |
| hasTEP                             | Int   | 1 if Target Enabling Package exists   |
| mouseKOScore                       | Float | Phenotypic score from knockout        |
| hasHighQualityChemicalProbes       | Int   | 1 if probes available                 |
| maxClinicalTrialPhase              | Float | Highest clinical trial phase          |
| tissueSpecificity                  | Float | Expression specificity                |
| tissueDistribution                 | Float | Expression distribution               |

---

## Knowledge Graph Schema

**Nodes**

* `Target` — core entity (properties: numeric and boolean attributes)
* `Feature` — represents binary features (e.g., `Secreted`, `HasPocket`)
* *(optional)* `TissueProfile`, `Document` — for future extensions

**Relationships**

* `(:Target)-[:HAS_FEATURE]->(:Feature)` for boolean flags (true values only)
* Future expansion: connect to `ClinicalTrial`, `Ligand`, or external vector DB documents

---

## Pipeline

1. **Input**: Parquet file (`target_prioritisation.parquet`)
2. **Transform**: Python scripts process data into Neo4j import format or push directly into Neo4j
3. **Load**:

   * Option A: Export CSVs for **neo4j-admin import**
   * Option B: Use Python **Neo4j driver** to push data directly
4. **Query**: Run Cypher queries or GraphRAG-powered LLM queries over the graph

---

## 📂 Repository Structure

```
.
├── README.md                 
├── mapping_target_prioritisation.json  
├── save_as_csv_for_neo4j.py  
├── push_to_neo4j.py          
└── examples/                 
```

---

## 🚀 Usage

### 1. Install dependencies

```bash
pip install pandas pyarrow tqdm neo4j
```

### 2. Export to CSVs for Neo4j bulk import

```bash
python save_as_csv_for_neo4j.py
```

This creates:

* `targets_nodes.csv`
* `features_nodes.csv`
* `target_has_feature_rels.csv`

### 3. Import into Neo4j

```bash
neo4j-admin import \
  --nodes=Target=targets_nodes.csv \
  --nodes=Feature=features_nodes.csv \
  --relationships=target_has_feature_rels.csv
```

### 4. Direct push into Neo4j

If you want incremental loading:

```bash
python push_to_neo4j.py
```

Configure your Neo4j URI, username, and password in the script.

---

## Example Queries

**Find membrane proteins with binding pockets and no safety events:**

```cypher
MATCH (t:Target)
WHERE t.isInMembrane = 1 AND t.hasPocket = 1 AND (t.hasSafetyEvent = 0 OR t.hasSafetyEvent IS NULL)
RETURN t.targetId, t.geneticConstraint, t.maxClinicalTrialPhase
ORDER BY t.maxClinicalTrialPhase DESC
LIMIT 50;
```

**Rank targets by druggability score:**

```cypher
MATCH (t:Target)
WITH t,
     (coalesce(t.hasPocket,0)*2 + coalesce(t.hasLigand,0)*1.5 + coalesce(t.hasTEP,0)*1.2
      - coalesce(t.hasSafetyEvent,0)*2) AS score
RETURN t.targetId, score
ORDER BY score DESC
LIMIT 20;
```

---

## 💡 Applications

* **Target discovery**: rank by druggability, safety, or trial evidence
* **Safety triage**: filter out high-risk targets
* **Repurposing**: find high-trial-phase targets without probes
* **Comparisons**: side-by-side analysis of target attributes
* **GraphRAG assistant**: natural language queries over the KG


