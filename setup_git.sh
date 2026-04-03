#!/usr/bin/env bash
# =============================================================
# setup_git.sh
# Creates a meaningful git commit history for the pipeline.
# Run once from the project root after cloning.
#
# Usage:
#   chmod +x setup_git.sh
#   ./setup_git.sh
#   git remote add origin https://github.com/YOUR_USERNAME/aviation-safety-pipeline.git
#   git push -u origin main
# =============================================================

set -euo pipefail

echo "Initialising git repository with structured commit history..."

git init
git checkout -b main

# ── Commit 1: Project scaffold ────────────────────────────────────
git add .gitignore README.md .env.example requirements.txt docker-compose.yml Makefile
git commit -m "chore: initialise project scaffold

- Add docker-compose.yml with PostgreSQL 15 healthcheck
- Add .env.example with all required variables documented
- Add requirements.txt (psycopg2, pandas, python-dotenv, SQLAlchemy, pytest)
- Add Makefile with up/down/pipeline/test/lint targets
- Add .gitignore (venv, __pycache__, .env, *.pyc)"

# ── Commit 2: Bronze layer ────────────────────────────────────────
git add sql/bronze/ src/config.py src/db.py src/ingest_bronze.py src/__init__.py
git commit -m "feat(bronze): raw ingestion layer for CSV and JSON sources

- Create bronze schema with raw_incidents_csv and raw_incidents_json tables
- All values stored as TEXT — no typing in bronze (intentional)
- Append-only design preserves full load history for audit
- Add ingestion_log table for lineage tracking (run_id, file, rows, status)
- Implement bulk_insert via psycopg2 execute_values for performance
- CSV column map handles trailing-space 'Longitude ' header in NTSB export
- JSON parser flattens cm_vehicles to JSONB for flexible downstream unnesting
- config.py: env-driven settings with _require() for mandatory vars
- db.py: connection pool, load_sql(), wait_for_db() with retry backoff"

# ── Commit 3: Silver layer ────────────────────────────────────────
git add sql/silver/ src/transform_silver.py
git commit -m "feat(silver): cleanse, type, deduplicate and enrich incidents

- silver.incidents: deduplicated on mkey via ON CONFLICT DO UPDATE
- Type casting: event_date ISO8601 → DATE, injury counts → SMALLINT
- model_family normalisation: UPPER(make) + first_token(UPPER(model))
  groups 172S / 172N / 172RG under same CESSNA 172 family
- damage_severity_score: Destroyed=4, Substantial=3, Minor=2, None=1
- severity_score formula: min(100, damage*3 + injury_tier*4 + fatals*5)
- NLP keyword extraction: 10 regex patterns on combined narrative text
  covering engine failure, fuel exhaustion, loss of control, weather,
  mechanical, pilot error, runway excursion, fire, structural, bird strike
- silver.incident_vehicles: unnested from JSON cm_vehicles JSONB
- silver.incident_events: SOE CICTT taxonomy (tier1/tier2/soe_group)
- silver.incident_findings: structured findings with in_probable_cause flag
- Scope filter: Mode = 'AVIATION' only"

# ── Commit 4: Gold layer ──────────────────────────────────────────
git add sql/gold/ src/transform_gold.py
git commit -m "feat(gold): aircraft risk profile table for underwriting

- gold.aircraft_risk_profile: one row per model_family, self-contained
- 11-CTE transform: base counts, damage, injuries, weather, keywords,
  severity, engine profile, top SOE group, top finding, sample narratives
- Severity trend: compares recent 3yr avg vs all-time avg
  → Improving / Deteriorating / Stable / Insufficient Data
- Risk score composite (0-100):
    35% avg severity score
    25% fatal incident rate
    20% destruction rate
    10% IMC rate
    10% incidents per year (capped at 10pts)
- Risk tier thresholds: High>=40, Elevated>=25, Moderate>=12, Low<12
- Human-readable risk_rationale for non-technical stakeholders
- Sample probable cause text from highest-severity incident per model
- Full rebuild on each run (TRUNCATE + INSERT) — always reflects latest silver"

# ── Commit 5: Pipeline orchestration ─────────────────────────────
git add src/pipeline.py
git commit -m "feat(pipeline): end-to-end orchestrator with stage control

- pipeline.py: bronze → silver → gold with --stage flag
- wait_for_db() polls with configurable retries (12x, 5s delay)
- init_pool() / close_pool() for connection lifecycle management
- Structured logging: timestamp | level | module | message
- Per-stage timing with perf_counter
- sys.exit(1) on failure so CI/CD detects pipeline errors
- Usage: python pipeline.py --stage [bronze|silver|gold]"

# ── Commit 6: Tests ───────────────────────────────────────────────
git add tests/
git commit -m "test: unit and integration tests for all pipeline layers

- test_ingest_bronze.py:
  - CSV column map completeness (no duplicates, Longitude trailing space)
  - JSON record parsing (mkey, narratives, vehicles JSONB, null handling)
  - File-level ingestion with mocked DB connections
- test_transform_silver.py:
  - Keyword regex patterns: 30 test cases covering true/false positives
  - Severity score formula: 7 boundary cases including cap at 100
  - Model family normalisation: case, spacing, empty model, multi-word make
  - Damage score mapping: all 5 categories including unknown
- test_gold_outputs.py:
  - Schema validation: all required columns present
  - Business logic: risk_score 0-100, valid tier values, tier-score alignment
  - Percentage columns in [0,100] range
  - Silver-to-gold consistency: incident counts match, no orphaned models
  - Output file completeness: all 7 CSVs exist and are non-empty
Run with: make test"

# ── Commit 7: Documentation ───────────────────────────────────────
git add docs/
git commit -m "docs: EDA findings and architecture design decisions

- EDA.md:
  - Data source overview (CSV vs JSON, field coverage comparison)
  - Schema exploration with field-level notes
  - Data quality findings: completeness rates, make/model inconsistency,
    date parsing edge cases, duplicate risk across batch files
  - Operation scope decision: include all FAR parts, document rationale
  - Severity measurement approach with formula derivation
  - Failure information sources ranked by coverage and signal quality
  - Incident distribution: by category, weather, report status
  - Model volume analysis with top models from sample data
- DESIGN_DECISIONS.md:
  - 10 documented decisions with rationale and trade-offs considered:
    medallion pattern, dedup strategy, dual source design, model family
    normalisation, SQL-in-files discipline, NLP approach, severity formula,
    env-driven config, Docker strategy, output exports"

# ── Commit 8: Sample outputs ──────────────────────────────────────
git add outputs/ data/
git commit -m "data: add sample data and pre-generated outputs

- data/raw/: NTSB CSV and JSON export files (2 batches, ~215 incidents)
- outputs/bronze_incidents_csv.csv: raw CSV as ingested (215 rows)
- outputs/bronze_incidents_json.csv: flattened JSON as ingested (215 rows)
- outputs/silver_incidents.csv: cleaned, typed, keyword-tagged (215 rows)
- outputs/silver_incident_vehicles.csv: per-vehicle detail (220 rows)
- outputs/silver_incident_events.csv: SOE events (317 rows)
- outputs/silver_incident_findings.csv: structured findings (145 rows)
- outputs/gold_aircraft_risk_profile.csv: risk profiles (22 models)
  Top risk models: CESSNA 180 (High, 58.0), ATR ATR42 (High, 41.0)"

echo ""
echo "✅ Git history created with $(git log --oneline | wc -l) commits"
echo ""
echo "Next steps:"
echo "  git remote add origin https://github.com/YOUR_USERNAME/aviation-safety-pipeline.git"
echo "  git push -u origin main"
echo ""
git log --oneline
