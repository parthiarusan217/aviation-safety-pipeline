-- BRONZE LAYER: Raw ingestion tables with lineage metadata
-- All data lands here as-is
-- no transformations applied.

CREATE SCHEMA IF NOT EXISTS bronze;
-- Raw CSV incidents table
DROP TABLE IF EXISTS bronze.raw_incidents_csv CASCADE;
CREATE TABLE bronze.raw_incidents_csv (
    ingestion_id        BIGSERIAL PRIMARY KEY,
    source_file         TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ntsb_no             TEXT,
    event_type          TEXT,
    mkey                TEXT,
    event_id            TEXT,
    report_no           TEXT,
    report_status       TEXT,
    report_type         TEXT,
    most_recent_report_type TEXT,
    rep_gen_flag        TEXT,
    event_date          TEXT,
    city                TEXT,
    state               TEXT,
    country             TEXT,
    latitude            TEXT,
    longitude           TEXT,
    airport_id          TEXT,
    airport_name        TEXT,
    n_number            TEXT,
    serial_number       TEXT,
    make                TEXT,
    model               TEXT,
    aircraft_category   TEXT,
    amateur_built       TEXT,
    number_of_engines   TEXT,
    engine_type         TEXT,
    far_part            TEXT,
    scheduled           TEXT,
    purpose_of_flight   TEXT,
    operator            TEXT,
    aircraft_damage     TEXT,
    highest_injury_level TEXT,
    fatal_injury_count  TEXT,
    serious_injury_count TEXT,
    minor_injury_count  TEXT,
    onboard_injury_count TEXT,
    onground_injury_count TEXT,
    weather_condition   TEXT,
    probable_cause      TEXT,
    findings            TEXT,
    original_published_date TEXT,
    docket_original_published_date TEXT,
    has_safety_rec      TEXT,
    mode                TEXT,
    docket_url          TEXT,
    report_url          TEXT
);

-- Raw JSON incidents table
DROP TABLE IF EXISTS bronze.raw_incidents_json CASCADE;
CREATE TABLE bronze.raw_incidents_json (
    ingestion_id        BIGSERIAL PRIMARY KEY,
    source_file         TEXT NOT NULL,
    ingested_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    mkey                TEXT,
    ntsb_num            TEXT,
    event_date          TEXT,
    event_type          TEXT,
    city                TEXT,
    state               TEXT,
    country             TEXT,
    latitude            TEXT,
    longitude           TEXT,
    airport_id          TEXT,
    airport_name        TEXT,
    report_type         TEXT,
    report_num          TEXT,
    most_recent_report_type TEXT,
    highest_injury      TEXT,
    fatal_injury_count  TEXT,
    minor_injury_count  TEXT,
    serious_injury_count TEXT,
    onboard_injury_count TEXT,
    onground_injury_count TEXT,
    completion_status   TEXT,
    has_safety_rec      TEXT,
    hazmat_involved     TEXT,
    is_study            TEXT,
    mode                TEXT,
    topic_mode          TEXT,
    accident_site_condition TEXT,
    factual_narrative   TEXT,
    analysis_narrative  TEXT,
    prelim_narrative    TEXT,
    vehicles_json       JSONB,
    original_published_date TEXT,
    docket_date         TEXT,
    report_date         TEXT,
    board_meeting_date  TEXT
);

-- Lineage audit log
DROP TABLE IF EXISTS bronze.ingestion_log CASCADE;
CREATE TABLE bronze.ingestion_log (
    log_id          BIGSERIAL PRIMARY KEY,
    run_id          TEXT NOT NULL,
    source_file     TEXT NOT NULL,
    file_type       TEXT NOT NULL,  
    rows_loaded     INTEGER,
    started_at      TIMESTAMPTZ,
    finished_at     TIMESTAMPTZ,
    status          TEXT,           
    error_message   TEXT
);