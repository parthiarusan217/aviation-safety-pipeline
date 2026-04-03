# Design Decisions

1. Architecture - Medallion Pattern

The objective of this project is to build 3 layer medallion (Bronze -> Silver -> Gold) in a PostgreSQL instance that runs in the docker container.

Unable to use the API from the source data set and the avail.mdb is not csv or json file, its Microsoft Access DB file and unable to use it in the Mac book. So decided to use the CAROL query tool and manually downloaded csv and json files for data 2026 and 2025.
In production environment, this has to be properly channelling from correct source API.

Bronze preserves raw data exactly as received from NTSB data and it is Append-only in bronze because we can always recreate silver and gold from scratch without depending on source system (i.e NTSB).
Silver is the true version of source data but it will be deduped.
Gold is where we apply the joins between tables and create the final curated table for business use and materialized view can be created from gold if needed to enable the self service for the data owners or business teams.
All these layers should be properly encrypted at rest and in transit and should always follow the principle of least privileges.

For a small project like this python pipeline and SQL should be enough, but for production system with larger volume and complex business logics, I would suggest Apache Spark. I would suggest below modern solutions
A. Build data lakehouse in Databricks and leverage Lakeflow Spark Declarative Pipelines(LSDP previously know as DLT), unity catalog, delta tables and can enable Genie and AI/BI feature from Databricks
B. Can use dbt and snowflake
c. Or can be used AWS/Azure native services to build this kind of application for more stable and easy to manage and monitor 


2. Deduplication Strategy

Bronze is append-only from two file types (CSV & Json)
Silver deduplicates on "mkey" (NTSB internal key) using "INSERT ... ON CONFLICT (mkey) DO UPDATE".
NTSB re-publishes updated reports as investigations progress. By deduplicating in silver using "ON CONFLICT DO UPDATE", we always keep the most complete version of each incident while preserving the full load history in bronze for audit purposes. 
The ingestion_log table will tracks every file load in to the bronze table, it is kind of old school batch history table.
Dedup is not adviceable in bronze because we will be losing the ability to track how data got changed and in future if we need to look for complete life cycle of an incident then we don't have history to track it.


3. Dual Source Design (CSV and JSON)

Load both CSV and JSON into separate bronze tables and join on "mkey" during silver transformation.
CSV has straight forward structured fields (make, model, FAR, damage, injury counts) with consistent column naming.
JSON has complex nested data (vehicle-level detail, SOE codes, findings, engine data) and fuller narratives.
Neither source alone is sufficient and CSV lacks narratives and structured findings and JSON lacks some flat fields.
Storing "cm_vehicles" as JSONB in bronze gives flexibility PostgreSQL's JSONB operators let silver unnest any depth of nesting without schema changes when NTSB adds new vehicle fields.


4. Model Family Normalization

model_family = UPPER(make) || ' ' || SPLIT_PART(UPPER(model), ' ', 1)

Aircraft model naming in NTSB data is inconsistent. A Cessna 172 can appear as as example:
Make: 'CESSNA', Model: '172S'
Make: 'CESSNA', Model: '172N'
Make: 'Cessna Aircraft', Model: '172'

Grouping by 'UPPER(make) + first model token' groups all 172 variants together while keeping the 172 and 182 distinct. This is intentionally coarse it's a grouping key for risk aggregation not an exact identifier.

Two aircraft with the same first model token but different models example "PA-28" vs "PA-28-181" will be grouped. For production like environment a curated make/model mapping table may be needed.


5. SQL in Files, Not Python Strings

All SQL statements should be in .sql files under the folder "sql/". Python only orchestrates execution ("execute_sql_file()" in "db.py").
SQL files are diffable, reviewable and syntax-highlightable in any editor.
SQL tools like EXPLAIN, psql, DBeaver can run them directly for debugging.
Prevents the "long string in f-string" antipattern that makes complex SQL unmaintainable.
Separates concerns clearly that data engineers own .sql files and Python/platform engineers own .py.


6. NLP: Keyword Regex

Used Keyword/regex extraction in silver
The pipeline must run entirely in Docker with no external API dependencies.
Regex patterns on 10 failure categories cover ~80% of actionable signal (engine failure, LOC, fuel exhaustion, etc.) with zero latency and full reproducibility.
Silver's "narrative_combined" column is purpose-built for a follow-on NLP enrichment step. A separate enrichment job could call an embedding model or LLM API and write results back to silver without touching the core pipeline.


7. Severity Scoring Formula

Composite "severity_score = min(100, damage×3 + injury_tier×4 + fatals×5)"

Fatalities receive the heaviest weight (×5) because they represent irreversible loss and maximum insurance exposure.
Damage receives a moderate weight (×3) because airframe write-offs drive hull claim costs.
The score is capped at 100 to prevent extreme fatal incidents from distorting model averages.

Gold risk score formula:
risk_score = severity×0.35 + fatal_rate×0.25 + destroy_rate×0.20 + imc_rate×0.10 + incident_rate×0.10

These weights are illustrative. In production, they would be calibrated against historical claim data provided by Meridian Aero Underwriters.


8. Configuration: .env-Driven

All credentials and paths in .env (loaded by python-dotenv). No hardcoded values anywhere.

The assignment spec states the pipeline must run on the reviewer's infrastructure by swapping .env credentials only. "Config" class in "config.py" fails ('_require()') if mandatory variables are missing, rather than using wrong defaults values.

9. Docker Strategy

"docker-compose.yml" runs PostgreSQL only. The pipeline Python runs on the host.
Keeps the reviewer's workflow simple. "docker-compose up -d" then "python src/pipeline.py"
Adding the pipeline to Docker would require rebuilding the image on every code change during development.
PostgreSQL port is exposed (default 5432) so the reviewer can also connect with any SQL client (DBeaver, psql) to inspect results directly.

10. Output Exports

As per the requirement, exported CSVs from every layer (bronze, silver, gold) to outputs/ folder.
In production, I may store these output in a table or can build some reports out of it.

The assignment requires sample outputs from each layer.
CSVs let reviewers inspect data without a running database.
Bronze CSVs demonstrate that raw data is preserved as-is.
Gold CSV is the primary deliverable — should be openable in Excel by an underwriter.
In production, underwrites can automatically receive these output files to whatever destination that they like or expose in to a secure API as well