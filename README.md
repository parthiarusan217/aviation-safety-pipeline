Aviation Safety Pipeline

A medallion architecture data pipeline that ingests NTSB aviation incident data into PostgreSQL and produces an aircraft risk profile table for insurance underwriting.

Tech Stack
- Python 3.9+ 
- PostgreSQL 15 
- Docker Compose

Repository Structure

aviation-safety-pipeline/
├── README.md
├── requirements.txt
├── .env.example              
├── .gitignore
├── docker-compose.yml
├── data/
│   └── raw/   
├── docs/
│   ├── EDA.md                
│   └── DESIGN_DECISIONS.md
├── sql/
│   ├── bronze/
│   │   └── 01_create_bronze.sql
│   ├── silver/
│   │   ├── 01_create_silver.sql
│   │   ├── 02_transform_silver.sql
│   │   └── 03_transform_vehicles_events.sql
│   └── gold/
│       ├── 01_create_gold.sql
│       └── 02_transform_gold.sql
├── src/
│   ├── config.py
│   ├── db.py
│   ├── ingest_bronze.py
│   ├── transform_silver.py
│   ├── transform_gold.py
│   └── pipeline.py
└── outputs/


Quick Start

Prerequisites

- Docker and Docker Compose installed
- Python 3.9 or higher
- 'pip' (or a virtual environment manager)

Step 1 — Clone and configure

git clone <your-repo-url>
cd aviation-safety-pipeline

Create your .env from the example
cp .env.example .env - reviewer can put his own credentials 

Step 2 — Add data files

Place your NTSB data files in "data/raw/". The pipeline accepts any number of .csv and .json files in that directory:

data/raw/
├── samplefile1.csv
├── Samplefile1.json
├── samplefile2.csv
└── samplefile2.json


Step 3 — Start PostgreSQL

docker-compose up -d

Wait for 10 sec and do below health check
docker-compose ps   # STATUS should show "healthy"

Step 4 — Install Python dependencies

python -m venv .venv
source .venv/bin/activate  # this is for Mac, for Windows use .venv\Scripts\activate

pip install -r requirements.txt

Step 5 — Run the full pipeline

cd src
python pipeline.py



Key queries:

docker exec -it aviation_db psql -U aviation_user -d aviation_db

\dn

\dt gold.*

Select count(*) from gold.aircraft_risk_profile; 

Select * from gold.aircraft_risk_profile limit 5;


SELECT model_family, risk_tier, risk_score, total_incidents,
       pct_fatal_incidents, pct_destroyed, avg_severity_score_all_time,
       severity_trend, top_soe_group, risk_rationale
FROM gold.aircraft_risk_profile
ORDER BY risk_score DESC;

-- Silver: keyword distribution
SELECT model_family,
       ROUND(100.0 * AVG(kw_engine_failure::int), 1) AS engine_fail_pct,
       ROUND(100.0 * AVG(kw_pilot_error::int), 1)    AS pilot_error_pct,
       ROUND(100.0 * AVG(kw_loss_of_control::int), 1) AS loc_pct
FROM silver.incidents
GROUP BY model_family
ORDER BY COUNT(*) DESC;


SELECT * FROM bronze.ingestion_log ORDER BY finished_at DESC;


CSV outputs
After the pipeline runs, 'outputs/' contains:

| File | Contents |
|---|---|
| bronze_incidents_csv.csv | Raw CSV data as ingested |
| bronze_incidents_json.csv | Flattened JSON data as ingested |
| silver_incidents.csv | Cleansed, typed, keyword-tagged incidents |
| silver_incident_vehicles.csv | Per-vehicle detail from JSON |
| silver_incident_events.csv | SOE (sequence of events) records |
| silver_incident_findings.csv | Structured findings per vehicle |
| gold_aircraft_risk_profile.csv | Primary deliverable — aircraft risk profiles |


Pipeline Architecture

data/raw/
  *.csv ──────────────────────────┐
  *.json ─────────────────────────┤
                                  ▼
                          ┌──────────────┐
                          │    BRONZE    │  raw ingestion, append-only
                          │  (postgres)  │  + lineage audit log
                          └──────┬───────┘
                                 │ deduplicate on mkey
                                 │ type & normalise
                                 │ keyword extraction (NLP-lite)
                                 ▼
                          ┌──────────────┐
                          │    SILVER    │  incidents + vehicles
                          │  (Postgres)  │  + events + findings
                          └──────┬───────┘
                                 │ aggregate by model_family
                                 │ compute risk score + tier
                                 │ trend analysis
                                 ▼
                          ┌──────────────┐
                          │     GOLD     │  aircraft_risk_profile
                          │  (postgres)  │  (self-contained, 1 row/model)
                          └──────┬───────┘
                                 │
                                 ▼
                          outputs/*.csv


Medallion Layer Summary

| Layer | Schema | Tables | Purpose |
|---|---|---|---|
| Bronze | bronze | raw_incidents_csv, raw_incidents_json, ingestion_log | Raw data preserved exactly as received, with lineage metadata |
| Silver | silver | incidents, incident_vehicles, incident_events, incident_findings | Cleansed, typed, deduplicated, enriched with NLP flags |
| Gold | gold | aircraft_risk_profile | Denormalized risk profile per aircraft model — underwriter-ready |


To stop container, run the below:

docker-compose down

To remove containers 

docker-compose down -v
