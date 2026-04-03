-- GOLD TRANSFORM: Populate aircraft_risk_profile from silver
TRUNCATE gold.aircraft_risk_profile;
-- CTE 1: Base incident counts per model family
WITH base AS (
    SELECT
        model_family,
        MAX(make_clean)                         AS make,
        STRING_AGG(DISTINCT model_clean, ', ' ORDER BY model_clean) AS model_variants,
        MAX(aircraft_category)                  AS aircraft_category,
        COUNT(*)                                AS total_incidents,
        MIN(event_year)                         AS first_incident_year,
        MAX(event_year)                         AS last_incident_year,
        GREATEST(MAX(event_year) - MIN(event_year) + 1, 1) AS years_in_record,
        ROUND(COUNT(*)::NUMERIC /
              GREATEST(MAX(event_year) - MIN(event_year) + 1, 1), 2)
                                                AS incidents_per_year
    FROM silver.incidents
    WHERE model_family IS NOT NULL
      AND model_family != ' '
    GROUP BY model_family
    HAVING COUNT(*) >= 2  
),
-- CTE 2: Damage breakdown
damage AS (
    SELECT
        model_family,
        COUNT(*) FILTER (WHERE aircraft_damage = 'Destroyed')   AS destroyed_count,
        COUNT(*) FILTER (WHERE aircraft_damage = 'Substantial') AS substantial_count,
        COUNT(*) FILTER (WHERE aircraft_damage = 'Minor')       AS minor_damage_count
    FROM silver.incidents
    WHERE model_family IS NOT NULL
    GROUP BY model_family
),
-- CTE 3: Injury breakdown
injuries AS (
    SELECT
        model_family,
        COUNT(*) FILTER (WHERE fatal_count > 0)      AS total_fatal_incidents,
        COALESCE(SUM(fatal_count),   0)               AS total_fatal_injuries,
        COALESCE(SUM(serious_count), 0)               AS total_serious_injuries,
        COALESCE(SUM(minor_count),   0)               AS total_minor_injuries,
        CASE
            WHEN SUM(fatal_count) > 0 AND COUNT(*) FILTER (WHERE fatal_count > 0) > 0
            THEN ROUND(SUM(fatal_count)::NUMERIC /
                       COUNT(*) FILTER (WHERE fatal_count > 0), 2)
            ELSE 0
        END AS avg_fatals_per_fatal_incident
    FROM silver.incidents
    WHERE model_family IS NOT NULL
    GROUP BY model_family
),
-- CTE 4: Weather conditions
weather AS (
    SELECT
        model_family,
        COUNT(*) FILTER (WHERE weather_condition = 'IMC') AS imc_incidents,
        COUNT(*) FILTER (WHERE weather_condition = 'VMC') AS vmc_incidents
    FROM silver.incidents
    WHERE model_family IS NOT NULL
    GROUP BY model_family
),
-- CTE 5: Keyword / NLP feature percentages
keywords AS (
    SELECT
        model_family,
        ROUND(100.0 * AVG(kw_engine_failure::INT),   1) AS kw_engine_failure_pct,
        ROUND(100.0 * AVG(kw_fuel_exhaustion::INT),  1) AS kw_fuel_exhaustion_pct,
        ROUND(100.0 * AVG(kw_loss_of_control::INT),  1) AS kw_loss_of_control_pct,
        ROUND(100.0 * AVG(kw_weather_factor::INT),   1) AS kw_weather_factor_pct,
        ROUND(100.0 * AVG(kw_mechanical::INT),       1) AS kw_mechanical_pct,
        ROUND(100.0 * AVG(kw_pilot_error::INT),      1) AS kw_pilot_error_pct,
        ROUND(100.0 * AVG(kw_runway_excursion::INT), 1) AS kw_runway_excursion_pct,
        ROUND(100.0 * AVG(kw_fire::INT),             1) AS kw_fire_pct,
        ROUND(100.0 * AVG(kw_structural::INT),       1) AS kw_structural_pct,
        ROUND(100.0 * AVG(kw_bird_strike::INT),      1) AS kw_bird_strike_pct
    FROM silver.incidents
    WHERE model_family IS NOT NULL
    GROUP BY model_family
),
-- CTE 6: Severity — all-time and recent 3-year window
severity AS (
    SELECT
        model_family,
        ROUND(AVG(severity_score), 2) AS avg_severity_all_time,
        ROUND(AVG(severity_score) FILTER (
            WHERE event_year >= (SELECT MAX(event_year) FROM silver.incidents) - 2
        ), 2)                         AS avg_severity_recent3yr
    FROM silver.incidents
    WHERE model_family IS NOT NULL
    GROUP BY model_family
),
-- CTE 7: Engine profile (most common engine type + count)
engine AS (
    SELECT DISTINCT ON (model_family)
        model_family,
        engine_type         AS typical_engine_type,
        number_of_engines   AS typical_engine_count
    FROM silver.incidents
    WHERE model_family IS NOT NULL
      AND engine_type IS NOT NULL
    GROUP BY model_family, engine_type, number_of_engines
    ORDER BY model_family, COUNT(*) DESC
),
-- CTE 8: Top SOE group and flight phase from incident_events
top_soe AS (
    SELECT DISTINCT ON (iv.model_family)
        iv.model_family,
        ie.soe_group   AS top_soe_group,
        ie.phase_group AS top_phase
    FROM silver.incident_events ie
    JOIN silver.incident_vehicles iv USING (mkey)
    WHERE ie.is_defining_event = TRUE
      AND iv.model_family IS NOT NULL
      AND ie.soe_group IS NOT NULL
    GROUP BY iv.model_family, ie.soe_group, ie.phase_group
    ORDER BY iv.model_family, COUNT(*) DESC
),
-- CTE 9: Top finding text from incident_findings
top_finding AS (
    SELECT DISTINCT ON (iv.model_family)
        iv.model_family,
        f.finding_report_text AS top_finding
    FROM silver.incident_findings f
    JOIN silver.incident_vehicles iv USING (mkey)
    WHERE iv.model_family IS NOT NULL
      AND f.in_probable_cause = TRUE
      AND f.finding_report_text IS NOT NULL
    GROUP BY iv.model_family, f.finding_report_text
    ORDER BY iv.model_family, COUNT(*) DESC
),
-- CTE 10: Sample narratives for underwriter context
sample_narratives AS (
    SELECT DISTINCT ON (model_family)
        model_family,
        probable_cause   AS sample_probable_cause,
        findings_text    AS sample_finding
    FROM silver.incidents
    WHERE model_family IS NOT NULL
      AND probable_cause IS NOT NULL
    ORDER BY model_family, severity_score DESC NULLS LAST
),
-- CTE 11: Incident mkey list for traceability
mkey_list AS (
    SELECT
        model_family,
        STRING_AGG(mkey, '|' ORDER BY event_date DESC) AS incident_mkeys
    FROM silver.incidents
    WHERE model_family IS NOT NULL
    GROUP BY model_family
)
-- FINAL INSERT
INSERT INTO gold.aircraft_risk_profile (
    model_family, make, model_variants, aircraft_category,
    typical_engine_type, typical_engine_count,
    total_incidents, first_incident_year, last_incident_year,
    years_in_record, incidents_per_year,
    destroyed_count, substantial_count, minor_damage_count,
    pct_destroyed, pct_substantial, pct_minor,
    total_fatal_incidents, total_fatal_injuries,
    total_serious_injuries, total_minor_injuries,
    pct_fatal_incidents, avg_fatals_per_fatal_incident,
    imc_incidents, vmc_incidents, pct_imc,
    top_soe_group, top_finding, top_phase,
    kw_engine_failure_pct, kw_fuel_exhaustion_pct,
    kw_loss_of_control_pct, kw_weather_factor_pct,
    kw_mechanical_pct, kw_pilot_error_pct,
    kw_runway_excursion_pct, kw_fire_pct,
    kw_structural_pct, kw_bird_strike_pct,
    avg_severity_score_all_time, avg_severity_score_recent3yr,
    severity_trend, trend_delta,
    risk_score, risk_tier, risk_rationale,
    sample_probable_cause, sample_finding,
    incident_mkeys
)
SELECT
    b.model_family,
    b.make,
    b.model_variants,
    b.aircraft_category,
    e.typical_engine_type,
    e.typical_engine_count,
    b.total_incidents,
    b.first_incident_year,
    b.last_incident_year,
    b.years_in_record,
    b.incidents_per_year,
    COALESCE(d.destroyed_count,   0) AS destroyed_count,
    COALESCE(d.substantial_count, 0) AS substantial_count,
    COALESCE(d.minor_damage_count,0) AS minor_damage_count,
    ROUND(100.0 * COALESCE(d.destroyed_count,   0) / NULLIF(b.total_incidents,0), 1) AS pct_destroyed,
    ROUND(100.0 * COALESCE(d.substantial_count, 0) / NULLIF(b.total_incidents,0), 1) AS pct_substantial,
    ROUND(100.0 * COALESCE(d.minor_damage_count,0) / NULLIF(b.total_incidents,0), 1) AS pct_minor,
    COALESCE(i.total_fatal_incidents,  0),
    COALESCE(i.total_fatal_injuries,   0),
    COALESCE(i.total_serious_injuries, 0),
    COALESCE(i.total_minor_injuries,   0),
    ROUND(100.0 * COALESCE(i.total_fatal_incidents, 0) / NULLIF(b.total_incidents,0), 1),
    COALESCE(i.avg_fatals_per_fatal_incident, 0),
    COALESCE(w.imc_incidents, 0),
    COALESCE(w.vmc_incidents, 0),
    ROUND(100.0 * COALESCE(w.imc_incidents,0) /
          NULLIF(COALESCE(w.imc_incidents,0) + COALESCE(w.vmc_incidents,0), 0), 1),
    ts.top_soe_group,
    tf.top_finding,
    ts.top_phase,
    COALESCE(k.kw_engine_failure_pct,   0),
    COALESCE(k.kw_fuel_exhaustion_pct,  0),
    COALESCE(k.kw_loss_of_control_pct,  0),
    COALESCE(k.kw_weather_factor_pct,   0),
    COALESCE(k.kw_mechanical_pct,       0),
    COALESCE(k.kw_pilot_error_pct,      0),
    COALESCE(k.kw_runway_excursion_pct, 0),
    COALESCE(k.kw_fire_pct,             0),
    COALESCE(k.kw_structural_pct,       0),
    COALESCE(k.kw_bird_strike_pct,      0),
    COALESCE(sv.avg_severity_all_time,  0),
    COALESCE(sv.avg_severity_recent3yr, 0),
    CASE
        WHEN sv.avg_severity_recent3yr IS NULL OR sv.avg_severity_all_time IS NULL
            THEN 'Insufficient Data'
        WHEN sv.avg_severity_recent3yr < sv.avg_severity_all_time - 2
            THEN 'Improving'
        WHEN sv.avg_severity_recent3yr > sv.avg_severity_all_time + 2
            THEN 'Deteriorating'
        ELSE 'Stable'
    END AS severity_trend,
    ROUND(COALESCE(sv.avg_severity_recent3yr,0) - COALESCE(sv.avg_severity_all_time,0), 2)
        AS trend_delta,
LEAST(100, ROUND(
        (COALESCE(sv.avg_severity_all_time, 0) * 0.35)
        + (ROUND(100.0 * COALESCE(i.total_fatal_incidents,0) / NULLIF(b.total_incidents,0),1) * 0.25)
        + (ROUND(100.0 * COALESCE(d.destroyed_count,0)      / NULLIF(b.total_incidents,0),1) * 0.20)
        + (ROUND(100.0 * COALESCE(w.imc_incidents,0) /
                NULLIF(COALESCE(w.imc_incidents,0)+COALESCE(w.vmc_incidents,0),0),1) * 0.10)
        + (LEAST(b.incidents_per_year * 2, 10))
    , 2)) AS risk_score,
    CASE
        WHEN LEAST(100, ROUND(
            (COALESCE(sv.avg_severity_all_time,0) * 0.35)
            + (ROUND(100.0*COALESCE(i.total_fatal_incidents,0)/NULLIF(b.total_incidents,0),1)*0.25)
            + (ROUND(100.0*COALESCE(d.destroyed_count,0)/NULLIF(b.total_incidents,0),1)*0.20)
            + (ROUND(100.0*COALESCE(w.imc_incidents,0)/NULLIF(COALESCE(w.imc_incidents,0)+COALESCE(w.vmc_incidents,0),0),1)*0.10)
            + LEAST(b.incidents_per_year*2,10), 2)) >= 40 THEN 'High'
        WHEN LEAST(100, ROUND(
            (COALESCE(sv.avg_severity_all_time,0) * 0.35)
            + (ROUND(100.0*COALESCE(i.total_fatal_incidents,0)/NULLIF(b.total_incidents,0),1)*0.25)
            + (ROUND(100.0*COALESCE(d.destroyed_count,0)/NULLIF(b.total_incidents,0),1)*0.20)
            + (ROUND(100.0*COALESCE(w.imc_incidents,0)/NULLIF(COALESCE(w.imc_incidents,0)+COALESCE(w.vmc_incidents,0),0),1)*0.10)
            + LEAST(b.incidents_per_year*2,10), 2)) >= 25 THEN 'Elevated'
        WHEN LEAST(100, ROUND(
            (COALESCE(sv.avg_severity_all_time,0) * 0.35)
            + (ROUND(100.0*COALESCE(i.total_fatal_incidents,0)/NULLIF(b.total_incidents,0),1)*0.25)
            + (ROUND(100.0*COALESCE(d.destroyed_count,0)/NULLIF(b.total_incidents,0),1)*0.20)
            + (ROUND(100.0*COALESCE(w.imc_incidents,0)/NULLIF(COALESCE(w.imc_incidents,0)+COALESCE(w.vmc_incidents,0),0),1)*0.10)
            + LEAST(b.incidents_per_year*2,10), 2)) >= 12 THEN 'Moderate'
        ELSE 'Low'
    END AS risk_tier,
    'Incidents: ' || b.total_incidents
    || ' | Fatals: '    || COALESCE(i.total_fatal_injuries, 0)
    || ' | Destroyed: ' || COALESCE(d.destroyed_count, 0)
    || ' | Avg severity: ' || COALESCE(sv.avg_severity_all_time, 0)
    || ' | Top cause: '  || COALESCE(ts.top_soe_group, 'Unknown')
    || ' | Trend: '
    || CASE
           WHEN sv.avg_severity_recent3yr IS NULL THEN 'Insufficient Data'
           WHEN sv.avg_severity_recent3yr < sv.avg_severity_all_time - 2 THEN 'Improving'
           WHEN sv.avg_severity_recent3yr > sv.avg_severity_all_time + 2 THEN 'Deteriorating'
           ELSE 'Stable'
       END
    AS risk_rationale,
    sn.sample_probable_cause,
    sn.sample_finding,
    ml.incident_mkeys
FROM base b
LEFT JOIN damage            d  ON b.model_family = d.model_family
LEFT JOIN injuries          i  ON b.model_family = i.model_family
LEFT JOIN weather           w  ON b.model_family = w.model_family
LEFT JOIN keywords          k  ON b.model_family = k.model_family
LEFT JOIN severity          sv ON b.model_family = sv.model_family
LEFT JOIN engine            e  ON b.model_family = e.model_family
LEFT JOIN top_soe           ts ON b.model_family = ts.model_family
LEFT JOIN top_finding       tf ON b.model_family = tf.model_family
LEFT JOIN sample_narratives sn ON b.model_family = sn.model_family
LEFT JOIN mkey_list         ml ON b.model_family = ml.model_family
ORDER BY risk_score DESC NULLS LAST;