-- SILVER LAYER: Cleansed, typed, and enriched incident data
CREATE SCHEMA IF NOT EXISTS silver;

DROP TABLE IF EXISTS silver.incidents CASCADE;
CREATE TABLE silver.incidents (
    incident_key            BIGSERIAL PRIMARY KEY,
    mkey                    TEXT UNIQUE NOT NULL,  
    ntsb_no                 TEXT,
    event_date              DATE,
    event_year              SMALLINT GENERATED ALWAYS AS (EXTRACT(YEAR  FROM event_date)::SMALLINT) STORED,
    event_month             SMALLINT GENERATED ALWAYS AS (EXTRACT(MONTH FROM event_date)::SMALLINT) STORED,
    city                    TEXT,
    state                   TEXT,
    country                 TEXT,
    latitude                NUMERIC,
    longitude               NUMERIC,
    airport_id              TEXT,
    airport_name            TEXT,
    make_raw                TEXT,
    model_raw               TEXT,
    make_clean              TEXT,
    model_clean             TEXT,
    model_family            TEXT,
    aircraft_category       TEXT,
    n_number                TEXT,
    serial_number           TEXT,
    amateur_built           BOOLEAN,
    number_of_engines       SMALLINT,
    engine_type             TEXT,
    far_part                TEXT,
    scheduled               TEXT,
    purpose_of_flight       TEXT,
    operator                TEXT,
    aircraft_damage         TEXT,
    damage_severity_score   SMALLINT,
    highest_injury_level    TEXT,
    fatal_count             SMALLINT,
    serious_count           SMALLINT,
    minor_count             SMALLINT,
    total_onboard           SMALLINT,
    weather_condition       TEXT,   
    accident_site_condition TEXT,  
    has_safety_rec          BOOLEAN,
    report_type             TEXT,
    report_status           TEXT,
    factual_narrative       TEXT,
    analysis_narrative      TEXT,
    probable_cause          TEXT,
    findings_text           TEXT,
    narrative_combined      TEXT,
    kw_engine_failure       BOOLEAN DEFAULT FALSE,
    kw_fuel_exhaustion      BOOLEAN DEFAULT FALSE,
    kw_loss_of_control      BOOLEAN DEFAULT FALSE,
    kw_weather_factor       BOOLEAN DEFAULT FALSE,
    kw_mechanical           BOOLEAN DEFAULT FALSE,
    kw_pilot_error          BOOLEAN DEFAULT FALSE,
    kw_runway_excursion     BOOLEAN DEFAULT FALSE,
    kw_fire                 BOOLEAN DEFAULT FALSE,
    kw_structural           BOOLEAN DEFAULT FALSE,
    kw_bird_strike          BOOLEAN DEFAULT FALSE,
    severity_score          NUMERIC(5,2),
    source_csv_ingestion_id BIGINT,
    source_json_ingestion_id BIGINT,
    silver_loaded_at        TIMESTAMPTZ DEFAULT NOW()
);

-- Vehicles / aircraft per incident (from JSON cm_vehicles)
DROP TABLE IF EXISTS silver.incident_vehicles CASCADE;
CREATE TABLE silver.incident_vehicles (
    vehicle_key         BIGSERIAL PRIMARY KEY,
    mkey                TEXT NOT NULL,
    vehicle_num         SMALLINT,
    make                TEXT,
    model               TEXT,
    model_family        TEXT,
    aircraft_category   TEXT,
    serial_number       TEXT,
    registration_number TEXT,
    damage_level        TEXT,
    fire_type           TEXT,
    explosion_type      TEXT,
    number_of_engines   SMALLINT,
    engine_type         TEXT,
    ga_flight           BOOLEAN,
    amateur_built       BOOLEAN,
    operator_name       TEXT,
    far_part            TEXT,
    flight_operation_type TEXT,
    silver_loaded_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Events / SOE (Sequence of Events) per vehicle
DROP TABLE IF EXISTS silver.incident_events CASCADE;
CREATE TABLE silver.incident_events (
    event_key           BIGSERIAL PRIMARY KEY,
    mkey                TEXT NOT NULL,
    vehicle_num         SMALLINT,
    event_num           SMALLINT,
    event_code          TEXT,
    is_defining_event   BOOLEAN,
    tier1_name          TEXT,
    tier1_num           TEXT,
    tier2_name          TEXT,
    tier2_num           TEXT,
    soe_group           TEXT,
    phase_group         TEXT,
    silver_loaded_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Findings per vehicle
DROP TABLE IF EXISTS silver.incident_findings CASCADE;
CREATE TABLE silver.incident_findings (
    finding_key         BIGSERIAL PRIMARY KEY,
    mkey                TEXT NOT NULL,
    vehicle_num         SMALLINT,
    finding_num         SMALLINT,
    finding_code        TEXT,
    finding_text        TEXT,
    finding_report_text TEXT,
    in_probable_cause   BOOLEAN,
    silver_loaded_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for join performance
CREATE INDEX IF NOT EXISTS idx_silver_incidents_mkey        ON silver.incidents(mkey);
CREATE INDEX IF NOT EXISTS idx_silver_incidents_model_family ON silver.incidents(model_family);
CREATE INDEX IF NOT EXISTS idx_silver_incidents_event_year  ON silver.incidents(event_year);
CREATE INDEX IF NOT EXISTS idx_silver_incidents_far_part    ON silver.incidents(far_part);
CREATE INDEX IF NOT EXISTS idx_silver_vehicles_mkey         ON silver.incident_vehicles(mkey);
CREATE INDEX IF NOT EXISTS idx_silver_vehicles_model_family ON silver.incident_vehicles(model_family);
CREATE INDEX IF NOT EXISTS idx_silver_events_mkey           ON silver.incident_events(mkey);
CREATE INDEX IF NOT EXISTS idx_silver_findings_mkey         ON silver.incident_findings(mkey);