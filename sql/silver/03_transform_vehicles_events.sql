-- SILVER TRANSFORM: Vehicles, Events, Findings from JSON
-- Vehicles
INSERT INTO silver.incident_vehicles (
    mkey, vehicle_num, make, model, model_family,
    aircraft_category, serial_number, registration_number,
    damage_level, fire_type, explosion_type,
    number_of_engines, engine_type, ga_flight, amateur_built,
    operator_name, far_part, flight_operation_type
)
SELECT
    j.mkey,
    (v->>'cm_vehicleNum')::SMALLINT                         AS vehicle_num,
    UPPER(TRIM(v->>'make'))                                  AS make,
    TRIM(v->>'model')                                        AS model,
    UPPER(TRIM(v->>'make')) || ' '
        || SPLIT_PART(TRIM(UPPER(v->>'model')), ' ', 1)     AS model_family,
    UPPER(TRIM(v->>'aircraftCategory'))                      AS aircraft_category,
    NULLIF(TRIM(v->>'serialNumber'), '')                     AS serial_number,
    NULLIF(TRIM(v->>'registrationNumber'), '')               AS registration_number,
    INITCAP(TRIM(v->>'DamageLevel'))                        AS damage_level,
    NULLIF(TRIM(v->>'FireType'), '')                         AS fire_type,
    NULLIF(TRIM(v->>'ExplosionType'), '')                    AS explosion_type,
    NULLIF(v->>'numberOfEngines', '')::SMALLINT              AS number_of_engines,
    -- Engine type from first engine in cm_engines array
    NULLIF(TRIM((v->'cm_engines'->0)->>'engineType'), '')   AS engine_type,
    (v->>'gaFlight')::BOOLEAN                               AS ga_flight,
    (v->>'amateurBuilt')::BOOLEAN                           AS amateur_built,
    NULLIF(TRIM(v->>'operatorName'), '')                     AS operator_name,
    LPAD(REGEXP_REPLACE(
        TRIM(COALESCE(v->>'regulationFlightConductedUnder', '')),
        '\D', '', 'g'), 3, '0')                             AS far_part,
    NULLIF(TRIM(v->>'flightOperationType'), '')              AS flight_operation_type
FROM bronze.raw_incidents_json j,
     JSONB_ARRAY_ELEMENTS(j.vehicles_json) AS v
WHERE j.vehicles_json IS NOT NULL
  AND j.mkey IS NOT NULL
ON CONFLICT DO NOTHING;
-- Events (Sequence of Events per vehicle)
INSERT INTO silver.incident_events (
    mkey, vehicle_num, event_num,
    event_code, is_defining_event,
    tier1_name, tier1_num, tier2_name, tier2_num,
    soe_group, phase_group
)
SELECT
    j.mkey,
    (v->>'cm_vehicleNum')::SMALLINT         AS vehicle_num,
    (e->>'cm_eventNum')::SMALLINT           AS event_num,
    TRIM(e->>'cm_eventCode')                AS event_code,
    (e->>'cm_isDefiningEvent')::BOOLEAN     AS is_defining_event,
    TRIM(e->>'cm_tier1Name')               AS tier1_name,
    TRIM(e->>'cm_tier1Num')                AS tier1_num,
    TRIM(e->>'cm_tier2Name')               AS tier2_name,
    TRIM(e->>'cm_tier2Num')                AS tier2_num,
    TRIM(e->>'cicttEventSOEGroup')         AS soe_group,
    TRIM(e->>'cicttPhaseSOEGroup')         AS phase_group
FROM bronze.raw_incidents_json j,
     JSONB_ARRAY_ELEMENTS(j.vehicles_json)       AS v,
     JSONB_ARRAY_ELEMENTS(v->'cm_events')        AS e
WHERE j.vehicles_json IS NOT NULL
  AND j.mkey IS NOT NULL
ON CONFLICT DO NOTHING;
-- Findings
INSERT INTO silver.incident_findings (
    mkey, vehicle_num, finding_num,
    finding_code, finding_text, finding_report_text, in_probable_cause
)
SELECT
    j.mkey,
    (v->>'cm_vehicleNum')::SMALLINT             AS vehicle_num,
    (f->>'cm_findingNum')::SMALLINT             AS finding_num,
    TRIM(f->>'cm_findingCode')                  AS finding_code,
    TRIM(f->>'cm_findingText')                  AS finding_text,
    TRIM(f->>'cm_findingReportText')            AS finding_report_text,
    (f->>'cm_inPc')::BOOLEAN                    AS in_probable_cause
FROM bronze.raw_incidents_json j,
     JSONB_ARRAY_ELEMENTS(j.vehicles_json)      AS v,
     JSONB_ARRAY_ELEMENTS(v->'cm_findings')     AS f
WHERE j.vehicles_json IS NOT NULL
  AND j.mkey IS NOT NULL
ON CONFLICT DO NOTHING;