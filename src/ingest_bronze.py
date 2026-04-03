from __future__ import annotations

import json
import logging
import uuid
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

from config import Config
from db import bulk_insert, execute_sql_file, get_conn

logger = logging.getLogger(__name__)

# Column name mappings: CSV header → bronze table column
CSV_COL_MAP = {
    "NtsbNo":                        "ntsb_no",
    "EventType":                     "event_type",
    "Mkey":                          "mkey",
    "EventDate":                     "event_date",
    "City":                          "city",
    "State":                         "state",
    "Country":                       "country",
    "ReportNo":                      "report_no",
    "N#":                            "n_number",
    "SerialNumber":                  "serial_number",
    "HasSafetyRec":                  "has_safety_rec",
    "Mode":                          "mode",
    "ReportType":                    "report_type",
    "OriginalPublishedDate":         "original_published_date",
    "DocketOriginalPublishedDate":   "docket_original_published_date",
    "HighestInjuryLevel":            "highest_injury_level",
    "FatalInjuryCount":              "fatal_injury_count",
    "SeriousInjuryCount":            "serious_injury_count",
    "MinorInjuryCount":              "minor_injury_count",
    "OnboardInjuryCount":            "onboard_injury_count",
    "OnGroundInjuryCount":           "onground_injury_count",
    "ProbableCause":                 "probable_cause",
    "Findings":                      "findings",
    "EventID":                       "event_id",
    "Latitude":                      "latitude",
    "Longitude ":                    "longitude",
    "Make":                          "make",
    "Model":                         "model",
    "AirCraftCategory":              "aircraft_category",
    "AirportID":                     "airport_id",
    "AirportName":                   "airport_name",
    "AmateurBuilt":                  "amateur_built",
    "NumberOfEngines":               "number_of_engines",
    "EngineType":                    "engine_type",
    "Scheduled":                     "scheduled",
    "PurposeOfFlight":               "purpose_of_flight",
    "FAR":                           "far_part",
    "AirCraftDamage":                "aircraft_damage",
    "WeatherCondition":              "weather_condition",
    "Operator":                      "operator",
    "ReportStatus":                  "report_status",
    "RepGenFlag":                    "rep_gen_flag",
    "MostRecentReportType":          "most_recent_report_type",
    "DocketUrl":                     "docket_url",
    "ReportUrl":                     "report_url",
}

BRONZE_CSV_COLS = [
    "source_file", "ingested_at",
    "ntsb_no", "event_type", "mkey", "event_id", "report_no",
    "report_status", "report_type", "most_recent_report_type", "rep_gen_flag",
    "event_date", "city", "state", "country", "latitude", "longitude",
    "airport_id", "airport_name",
    "n_number", "serial_number", "make", "model", "aircraft_category",
    "amateur_built", "number_of_engines", "engine_type",
    "far_part", "scheduled", "purpose_of_flight", "operator",
    "aircraft_damage", "highest_injury_level",
    "fatal_injury_count", "serious_injury_count", "minor_injury_count",
    "onboard_injury_count", "onground_injury_count",
    "weather_condition", "probable_cause", "findings",
    "original_published_date", "docket_original_published_date",
    "has_safety_rec", "mode", "docket_url", "report_url",
]

def _log_ingestion(
    run_id: str,
    source_file: str,
    file_type: str,
    started_at: datetime,
    rows: int = 0,
    status: str = "success",
    error: str = None,
) -> None:

    record = {
        "run_id":        run_id,
        "source_file":   source_file,
        "file_type":     file_type,
        "rows_loaded":   rows,
        "started_at":    started_at,
        "finished_at":   datetime.now(timezone.utc),
        "status":        status,
        "error_message": error,
    }
    try:
        with get_conn() as conn:
            bulk_insert(conn, "bronze.ingestion_log", [record])
    except Exception as log_exc:
        logger.warning("Could not write ingestion log: %s", log_exc)


def ingest_csv_file(file_path: Path, run_id: str) -> int:
    logger.info("Ingesting CSV: %s", file_path.name)
    started_at = datetime.now(timezone.utc)

    df = pd.read_csv(file_path, dtype=str, keep_default_na=False)
    df.columns = df.columns.str.strip()
    df.rename(columns=CSV_COL_MAP, inplace=True)

    df["source_file"] = file_path.name
    df["ingested_at"] = started_at.isoformat()

    df = df.where(df != "", other=None)

    available = [c for c in BRONZE_CSV_COLS if c in df.columns]
    records = df[available].to_dict(orient="records")

    try:
        with get_conn() as conn:
            rows = bulk_insert(conn, "bronze.raw_incidents_csv", records)
        logger.info("CSV loaded: %d rows from %s", rows, file_path.name)
        _log_ingestion(run_id, file_path.name, "csv", started_at, rows)
        return rows
    except Exception as exc:
        logger.error("CSV ingestion failed for %s: %s", file_path.name, exc)
        _log_ingestion(run_id, file_path.name, "csv", started_at, 0, "error", str(exc))
        raise


def _parse_json_record(record: dict, source_file: str, ingested_at: str) -> dict:
    vehicles = record.get("cm_vehicles", [])
    return {
        "source_file":               source_file,
        "ingested_at":               ingested_at,
        "mkey":                      str(record.get("cm_mkey", "") or ""),
        "ntsb_num":                  record.get("cm_ntsbNum"),
        "event_date":                record.get("cm_eventDate"),
        "event_type":                record.get("cm_eventType"),
        "city":                      record.get("cm_city"),
        "state":                     record.get("cm_state"),
        "country":                   record.get("cm_country"),
        "latitude":                  str(record.get("cm_Latitude") or ""),
        "longitude":                 str(record.get("cm_Longitude") or ""),
        "airport_id":                record.get("airportId"),
        "airport_name":              record.get("airportName"),
        "report_type":               record.get("cm_reportType"),
        "report_num":                record.get("cm_reportNum"),
        "most_recent_report_type":   record.get("cm_mostRecentReportType"),
        "highest_injury":            record.get("cm_highestInjury"),
        "fatal_injury_count":        str(record.get("cm_fatalInjuryCount") or "0"),
        "minor_injury_count":        str(record.get("cm_minorInjuryCount") or "0"),
        "serious_injury_count":      str(record.get("cm_seriousInjuryCount") or "0"),
        "onboard_injury_count":      str(record.get("cm_injuryOnboardCount") or "0"),
        "onground_injury_count":     str(record.get("cm_injuryOngroundCount") or "0"),
        "completion_status":         record.get("cm_completionStatus"),
        "has_safety_rec":            str(record.get("cm_hasSafetyRec") or ""),
        "hazmat_involved":           str(record.get("cm_HazmatInvolved") or ""),
        "is_study":                  str(record.get("cm_isStudy") or ""),
        "mode":                      record.get("cm_mode"),
        "topic_mode":                record.get("cm_topicMode"),
        "accident_site_condition":   record.get("accidentSiteCondition"),
        "factual_narrative":         record.get("factualNarrative"),
        "analysis_narrative":        record.get("analysisNarrative"),
        "prelim_narrative":          record.get("prelimNarrative"),
        "vehicles_json":             json.dumps(vehicles) if vehicles else None,
        "original_published_date":   record.get("cm_originalPublishedDate"),
        "docket_date":               record.get("cm_docketDate"),
        "report_date":               record.get("cm_reportDate"),
        "board_meeting_date":        record.get("cm_boardMeetingDate"),
    }


def ingest_json_file(file_path: Path, run_id: str) -> int:
    logger.info("Ingesting JSON: %s", file_path.name)
    started_at = datetime.now(timezone.utc)

    with file_path.open(encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, list):
        raise ValueError(f"Expected JSON array in {file_path.name}, got {type(data)}")

    ts = started_at.isoformat()
    records = [_parse_json_record(r, file_path.name, ts) for r in data]

    try:
        with get_conn() as conn:
            rows = bulk_insert(conn, "bronze.raw_incidents_json", records,
                               page_size=Config.BATCH_SIZE)
        logger.info("JSON loaded: %d rows from %s", rows, file_path.name)
        _log_ingestion(run_id, file_path.name, "json", started_at, rows)
        return rows
    except Exception as exc:
        logger.error("JSON ingestion failed for %s: %s", file_path.name, exc)
        _log_ingestion(run_id, file_path.name, "json", started_at, 0, "error", str(exc))
        raise


def run_bronze(run_id: str = None) -> dict:
    run_id = run_id or str(uuid.uuid4())
    data_dir = Config.DATA_DIR

    if not data_dir.exists():
        raise FileNotFoundError(f"DATA_DIR not found: {data_dir}")

    csv_files  = sorted(data_dir.glob("*.csv"))
    json_files = sorted(data_dir.glob("*.json"))

    if not csv_files and not json_files:
        raise FileNotFoundError(f"No CSV or JSON files found in {data_dir}")

    logger.info("Bronze ingestion started | run_id=%s", run_id)
    logger.info("Found %d CSV, %d JSON files", len(csv_files), len(json_files))

    # Create bronze schema and tables
    with get_conn() as conn:
        execute_sql_file(conn, "bronze/01_create_bronze.sql")

    total_csv  = sum(ingest_csv_file(f, run_id)  for f in csv_files)
    total_json = sum(ingest_json_file(f, run_id) for f in json_files)

    summary = {
        "run_id":     run_id,
        "csv_files":  len(csv_files),
        "json_files": len(json_files),
        "csv_rows":   total_csv,
        "json_rows":  total_json,
    }
    logger.info("Bronze complete: %s", summary)
    return summary
