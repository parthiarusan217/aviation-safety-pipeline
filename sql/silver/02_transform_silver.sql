-- SILVER TRANSFORM: Populate silver.incidents from bronze
-- STEP 1: Deduplicated base from CSV (structured fields)
INSERT INTO silver.incidents (
    mkey,
    ntsb_no,
    event_date,
    city, state, country,
    latitude, longitude,
    airport_id, airport_name,
    make_raw, model_raw,
    make_clean, model_clean, model_family,
    aircraft_category,
    n_number, serial_number,
    amateur_built, number_of_engines, engine_type,
    far_part, scheduled, purpose_of_flight, operator,
    aircraft_damage, damage_severity_score,
    highest_injury_level,
    fatal_count, serious_count, minor_count, total_onboard,
    weather_condition, has_safety_rec,
    report_type, report_status,
    probable_cause, findings_text,
    source_csv_ingestion_id
)
SELECT DISTINCT ON (c.mkey)
    c.mkey,
    c.ntsb_no,
    CASE
        WHEN c.event_date ~ '^\d{4}-\d{2}-\d{2}'
        THEN (SUBSTRING(c.event_date, 1, 10))::DATE
        ELSE NULL
    END AS event_date,
    INITCAP(TRIM(c.city))       AS city,
    UPPER(TRIM(c.state))        AS state,
    TRIM(c.country)             AS country,
    CASE
        WHEN c.latitude ~ '^-?\d+(\.\d+)?$'
         AND c.latitude::NUMERIC BETWEEN -90 AND 90
        THEN ROUND(c.latitude::NUMERIC, 6)
        ELSE NULL
    END,
    CASE
        WHEN c.longitude ~ '^-?\d+(\.\d+)?$'
         AND c.longitude::NUMERIC BETWEEN -180 AND 180
        THEN ROUND(c.longitude::NUMERIC, 6)
        ELSE NULL
    END,
    NULLIF(TRIM(c.airport_id),   '') AS airport_id,
    NULLIF(TRIM(c.airport_name), '') AS airport_name,
    c.make  AS make_raw,
    c.model AS model_raw,
    UPPER(TRIM(c.make))         AS make_clean,
    TRIM(c.model)               AS model_clean,
    UPPER(TRIM(c.make)) || ' ' || SPLIT_PART(TRIM(UPPER(c.model)), ' ', 1) AS model_family,
    UPPER(TRIM(c.aircraft_category)) AS aircraft_category,
    NULLIF(TRIM(c.n_number),      '') AS n_number,
    NULLIF(TRIM(c.serial_number), '') AS serial_number,
    CASE UPPER(TRIM(c.amateur_built))
        WHEN 'TRUE'  THEN TRUE
        WHEN 'FALSE' THEN FALSE
        ELSE NULL
    END AS amateur_built,
    CASE WHEN c.number_of_engines ~ '^\d+$' THEN c.number_of_engines::SMALLINT ELSE NULL END,
    NULLIF(TRIM(c.engine_type), '') AS engine_type,
    LPAD(REGEXP_REPLACE(TRIM(c.far_part), '\D', '', 'g'), 3, '0') AS far_part,
    NULLIF(TRIM(c.scheduled), '')         AS scheduled,
    NULLIF(TRIM(c.purpose_of_flight), '') AS purpose_of_flight,
    NULLIF(TRIM(c.operator), '')          AS operator,
    INITCAP(TRIM(c.aircraft_damage)) AS aircraft_damage,
    CASE UPPER(TRIM(c.aircraft_damage))
        WHEN 'DESTROYED'    THEN 4
        WHEN 'SUBSTANTIAL'  THEN 3
        WHEN 'MINOR'        THEN 2
        WHEN 'NONE'         THEN 1
        ELSE 0
    END AS damage_severity_score,
    INITCAP(TRIM(c.highest_injury_level)) AS highest_injury_level,
    CASE WHEN c.fatal_injury_count   ~ '^\d+$' THEN c.fatal_injury_count::SMALLINT   ELSE 0 END,
    CASE WHEN c.serious_injury_count ~ '^\d+$' THEN c.serious_injury_count::SMALLINT ELSE 0 END,
    CASE WHEN c.minor_injury_count   ~ '^\d+$' THEN c.minor_injury_count::SMALLINT   ELSE 0 END,
    CASE WHEN c.onboard_injury_count ~ '^\d+$' THEN c.onboard_injury_count::SMALLINT ELSE 0 END,
    UPPER(TRIM(c.weather_condition)) AS weather_condition,
    CASE UPPER(TRIM(c.has_safety_rec))
        WHEN 'TRUE' THEN TRUE ELSE FALSE
    END AS has_safety_rec,
    NULLIF(TRIM(c.report_type),   '') AS report_type,
    NULLIF(TRIM(c.report_status), '') AS report_status,
    NULLIF(TRIM(c.probable_cause), '') AS probable_cause,
    NULLIF(TRIM(c.findings),       '') AS findings_text,
    c.ingestion_id AS source_csv_ingestion_id
FROM bronze.raw_incidents_csv c
WHERE UPPER(TRIM(c.mode)) = 'AVIATION'  
  AND c.mkey IS NOT NULL
  AND c.mkey != ''
ORDER BY c.mkey, c.ingested_at DESC     
ON CONFLICT (mkey) DO UPDATE SET
    ntsb_no                 = EXCLUDED.ntsb_no,
    event_date              = EXCLUDED.event_date,
    make_raw                = EXCLUDED.make_raw,
    model_raw               = EXCLUDED.model_raw,
    make_clean              = EXCLUDED.make_clean,
    model_clean             = EXCLUDED.model_clean,
    model_family            = EXCLUDED.model_family,
    aircraft_damage         = EXCLUDED.aircraft_damage,
    damage_severity_score   = EXCLUDED.damage_severity_score,
    highest_injury_level    = EXCLUDED.highest_injury_level,
    fatal_count             = EXCLUDED.fatal_count,
    serious_count           = EXCLUDED.serious_count,
    minor_count             = EXCLUDED.minor_count,
    total_onboard           = EXCLUDED.total_onboard,
    probable_cause          = EXCLUDED.probable_cause,
    findings_text           = EXCLUDED.findings_text,
    source_csv_ingestion_id = EXCLUDED.source_csv_ingestion_id;

-- STEP 2: Enrich with narrative text from JSON source
UPDATE silver.incidents si
SET
    factual_narrative        = NULLIF(TRIM(j.factual_narrative),  ''),
    analysis_narrative       = NULLIF(TRIM(j.analysis_narrative), ''),
    accident_site_condition  = NULLIF(TRIM(j.accident_site_condition), ''),
    source_json_ingestion_id = j.ingestion_id
FROM bronze.raw_incidents_json j
WHERE si.mkey = j.mkey;
-- STEP 3: Build combined narrative for keyword extraction
UPDATE silver.incidents
SET narrative_combined = COALESCE(factual_narrative,  '') || ' '
                      || COALESCE(analysis_narrative, '') || ' '
                      || COALESCE(probable_cause,     '') || ' '
                      || COALESCE(findings_text,      '');
-- STEP 4: Keyword / pattern extraction (NLP-lite)
UPDATE silver.incidents SET
    kw_engine_failure   = (narrative_combined ~* 'engine.{0,20}fail|power.{0,10}loss|engine.{0,10}stop'),
    kw_fuel_exhaustion  = (narrative_combined ~* 'fuel.{0,10}exhaust|fuel.{0,10}starvat|ran out of fuel|fuel quantity'),
    kw_loss_of_control  = (narrative_combined ~* 'loss of control|uncontrolled|loss.{0,10}aircraft.{0,10}control'),
    kw_weather_factor   = (narrative_combined ~* 'IMC|instrument meteorological|inadvertent IMC|low visib|ceiling'),
    kw_mechanical       = (narrative_combined ~* 'mechanical.{0,15}fail|component.{0,10}fail|malfunction|landing gear|propeller.{0,10}fail'),
    kw_pilot_error      = (narrative_combined ~* 'pilot.{0,20}fail|improper|inadequate|failure to|loss of situational|spatial disorientation'),
    kw_runway_excursion = (narrative_combined ~* 'runway excursion|overrun|veer|off.{0,10}runway|departed.{0,10}runway'),
    kw_fire             = (narrative_combined ~* '\bfire\b|smoke|inflight fire|post.?impact fire'),
    kw_structural       = (narrative_combined ~* 'structural fail|airframe|wing spar|fuselage|flutter|fatigue'),
    kw_bird_strike      = (narrative_combined ~* 'bird strike|wildlife strike|avian');
-- STEP 5: Composite severity score
UPDATE silver.incidents
SET severity_score = LEAST(100, ROUND(
    (damage_severity_score * 3)
    + (CASE highest_injury_level
           WHEN 'Fatal'   THEN 3
           WHEN 'Serious' THEN 2
           WHEN 'Minor'   THEN 1
           ELSE 0
       END * 4)
    + (COALESCE(fatal_count, 0) * 5)
, 2));