Exploratory Data Analysis (EDA)

1. Data Source Overview

Source: NTSB (National Transportation Safety Board) Aviation Accident Database  
Sample files

| File | Format | Records |
|---|---|---|
| cases_batch1.csv | CSV | ~108 rows |
| cases_batch1.json | JSON | ~107 rows |
| cases_batch2.csv | CSV | ~109 rows |
| cases_batch2.json | JSON | ~108 rows |

The CSV and JSON files represent the same incidents from different export endpoints:
The CSV provides flat structured fields (dates, aircraft metadata, injury counts, FAR part, damage level, probable cause text).
The JSON provides the same base fields plus richly nested structures like "cm_vehicles" (per-aircraft damage, findings, sequence-of-events, engine data, crew injuries), and full narrative text ("factualNarrative", "analysisNarrative", "prelimNarrative").
Both formats share "cm_mkey" as the primary incident key, enabling easy joins between these two datasets.

2. Schema Exploration

CSV Key Fields

| Field | Notes |
|---|---|
| 'Mkey' | Internal NTSB key — used as dedup anchor |
| 'NtsbNo' | Public-facing case number (e.g. CEN25LA173) |
| 'EventDate' | ISO8601 with time component and only date portion is reliable |
| 'Mode' | Always 'Aviation' in scope as per the requirement (filter applied in silver) |
| 'FAR' | Regulation part (91, 121, 135, etc.) |
| 'Make' / 'Model' | Inconsistent casing, trailing spaces, variant suffixes |
| 'AirCraftDamage' | Categorical: Destroyed / Substantial / Minor / None |
| 'HighestInjuryLevel' | Fatal / Serious / Minor / None |
| 'ProbableCause' | Free text and present only in finalized reports |
| 'Findings' | Pipe or comma-delimited coded finding texts |
| 'WeatherCondition' | VMC / IMC |

JSON Key Fields

| Field | Notes |
|---|---|
| 'cm_vehicles' | Array of aircraft involved — supports multi-aircraft incidents |
| 'cm_vehicles[].cm_events' | Sequence-of-events (SOE) codes with tier1/tier2 taxonomy |
| 'cm_vehicles[].cm_findings' | Structured findings with 'cm_inPc' (in probable cause) flag |
| 'cm_vehicles[].cm_engines' | Engine type per engine |
| 'factualNarrative' | Detailed investigator narrative (~200–800 words per incident) |
| 'analysisNarrative' | Analytical commentary — highest signal for NLP |
| 'accidentSiteCondition' | VMC / IMC (same as CSV WeatherCondition, used for cross-validation) |

3. Data Quality Findings

3.1 Completeness
ProbableCause (CSV): ~40% NULL — only final/director-brief reports have this field populated. Preliminary reports (status: "In work") have no probable cause yet.
Narratives (JSON): 'factualNarrative' ~55% populated; 'analysisNarrative' ~35%. Preliminary reports have only 'prelimNarrative'.
Latitude/Longitude: ~10% missing — incidents at sea or non-US locations.
FAR part: ~8% NULL — non-commercial operations sometimes omit this.

3.2 Make/Model Inconsistency
Aircraft naming is the biggest data quality challenge:
'CESSNA' vs 'Cessna' vs 'CESSNA AIRCRAFT CO' — same manufacturer
'172S', '172N', '172RG', '172' — variants of same base model
'BELL HELICOPTER TEXTRON CANADA' for manufacturer, '505' for model

In silver, model_family is derived as 'UPPER(make) + first_token(UPPER(model))'. This groups '172S' and '172N' both under 'CESSNA 172', while keeping '182' and '172' distinct. This is the join key for all gold aggregations.

3.3 Date Parsing
EventDate is stored as ISO8601 with time: '2025-04-30T20:50:00Z'. Only the date portion is extracted and cast to 'DATE' in silver. Records with malformed dates receive NULL event_date and are excluded from trend analysis.

3.4 Duplicate Risk
Both CSV files overlap in date range (both exported 2026-04-01). JSON and CSV cover the same incidents with different field depth. Bronze is append-only (intentional — preserves full load history). Silver deduplicates on 'mkey' using 'INSERT ... ON CONFLICT DO UPDATE' keeping the latest ingestion.


4. Scope Decision: Which Operations Are Relevant?

NTSB Operation Categories
The 'Mode' field identifies the transport mode. Values in this dataset: 'Aviation' (100%).

Within aviation, 'FAR' (Federal Aviation Regulation part) determines operation type:

| FAR Part | Operation Type | Underwriting Relevance |
|---|---|---|
| 091 | General Aviation (non-commercial) | Low-moderate — personal/corporate ops |
| 121 | Commercial Air Carrier (scheduled) | High — commercial airline operations |
| 135 | On-Demand / Charter | High — commercial charter/air taxi |
| 137 | Agricultural Operations | Low |
| 091K | Fractional Ownership | Moderate |

Include all FAR parts in this pipeline. The gold layer retains FAR part context so underwriters can filter by operation type. 
Excluding Part 91 would remove most incident volume in this dataset and impair model-level comparisons.

Aircraft Category Filter
'AirCraftCategory' values: AIR (fixed-wing), HELI (helicopter), GYRO, ULTR, BLIMP.  
Included all categories. Helicopter risk profiles (HELI) are kept separate via the 'aircraft_category' field in gold.


5. Severity Measurement

Two complementary severity signals are used:

Structured (silver.incidents.damage_severity_score): Destroyed = 4, Substantial = 3, Minor = 2, None = 1, Unknown = 0

Composite severity_score (0–100):
severity_score = min(100,
    damage_score × 3
  + injury_tier × 4      (Fatal=3, Serious=2, Minor=1, None=0)
  + fatal_count × 5
)

This formula penalizes fatal incidents heavily (×5 per fatality) while still differentiating between airframe write-offs with no injuries vs minor damage with serious injuries.

---

6. Failure Information: Where Is It?

Failure data exists in three places, each with different coverage:

| Source | Coverage | Signal Quality |
|---|---|---|
| 'ProbableCause' (CSV free text) | ~40% of incidents | High — investigator synthesis |
| 'cm_findings' (JSON structured) | ~60% of incidents | High — coded taxonomy |
| 'cm_events' SOE codes (JSON) | ~60% of incidents | Very High — standardized CICTT taxonomy |
| NLP keyword extraction (silver) | 100% of incidents with any text | Moderate — approximation |

The pipeline uses all four sources. 
Silver extracts 10 keyword flags from combined narrative text using regex patterns. 
Gold surfaces the top SOE group and finding from structured codes plus keyword percentages from NLP extraction.

7. Incident Distribution

By Aircraft Category (sample data)
| Category | Count | % |
|---|---|---|
| AIR (fixed-wing) | ~160 | ~73% |
| HELI (helicopter) | ~55 | ~25% |
| Other | ~7 | ~3% |

By Weather Condition
| Condition | Count | % |
|---|---|---|
| VMC (Visual) | ~180 | ~82% |
| IMC (Instrument) | ~30 | ~14% |
| Unknown | ~10 | ~5% |

Most incidents occur in VMC — consistent with GA operation patterns where IMC-rated pilots are proportionally fewer.

By Report Status
| Status | Count |
|---|---|
| Completed (Final) | ~95 |
| In work (Preliminary) | ~120 |

A significant portion are still under investigation, limiting availability of 'ProbableCause' and narrative text.

---

8. Aircraft Models: Volume Analysis

Top models by incident count in sample data (model_family after normalization):

| Model Family | Incidents | Category |
|---|---|---|
| CESSNA 172 | ~18 | AIR |
| CESSNA 182 | ~12 | AIR |
| PIPER PA-28 | ~9 | AIR |
| ROBINSON R44 | ~8 | HELI |
| CESSNA 152 | ~6 | AIR |
| BELL HELICOPTER 505 | ~4 | HELI |

Selected for deep analysis, CESSNA 172 and CESSNA 182 — highest incident volume with sufficient data for trend analysis. ROBINSON R44 selected for helicopter risk profile contrast.

---

9. Model Selection for Gold Profiles

Gold profiles are generated for any 'model_family' with ≥ 2 incidents (configurable threshold in 'sql/gold/02_transform_gold.sql'). With larger NTSB datasets (90,000 records), this threshold should be raised to ≥ 10 or ≥ 20 for statistical reliability.

Key finding: Even with this sample (~215 incidents), the CESSNA 172 profile shows a meaningful mix of engine failures, loss-of-control events, and IMC-involved incidents — enough for a demonstrable risk comparison.
