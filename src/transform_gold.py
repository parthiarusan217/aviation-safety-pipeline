import logging
from pathlib import Path

import pandas as pd

from config import Config
from db import execute_sql_file, get_conn, query_to_dicts

logger = logging.getLogger(__name__)


def _export_csv(conn, schema: str, table: str, output_path: Path) -> int:
    rows = query_to_dicts(conn, f"SELECT * FROM {schema}.{table}")
    if not rows:
        logger.warning("No rows in %s.%s — CSV will be empty", schema, table)
        pd.DataFrame().to_csv(output_path, index=False)
        return 0
    df = pd.DataFrame(rows)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(output_path, index=False)
    logger.info("Exported %d rows → %s", len(df), output_path)
    return len(df)

def run_gold() -> dict:
    logger.info("Gold transformation started")

    with get_conn() as conn:
        logger.info("Creating gold schema and tables...")
        execute_sql_file(conn, "gold/01_create_gold.sql")

        logger.info("Populating gold.aircraft_risk_profile...")
        execute_sql_file(conn, "gold/02_transform_gold.sql")

        rows = query_to_dicts(
            conn,
            "SELECT COUNT(*) AS n FROM gold.aircraft_risk_profile"
        )
        gold_count = rows[0]["n"] if rows else 0
        logger.info("gold.aircraft_risk_profile: %d model profiles generated", gold_count)

        out = Config.OUTPUT_DIR

        _export_csv(conn, "bronze", "raw_incidents_csv",
                    out / "bronze_incidents_csv.csv")
        _export_csv(conn, "bronze", "raw_incidents_json",
                    out / "bronze_incidents_json.csv")
        _export_csv(conn, "silver", "incidents",
                    out / "silver_incidents.csv")
        _export_csv(conn, "silver", "incident_vehicles",
                    out / "silver_incident_vehicles.csv")
        _export_csv(conn, "silver", "incident_events",
                    out / "silver_incident_events.csv")
        _export_csv(conn, "silver", "incident_findings",
                    out / "silver_incident_findings.csv")
        gold_rows = _export_csv(conn, "gold", "aircraft_risk_profile",
                                out / "gold_aircraft_risk_profile.csv")

    summary = {
        "gold_profiles": gold_count,
        "gold_csv_rows": gold_rows,
        "outputs_dir":   str(out),
    }
    logger.info("Gold complete: %s", summary)
    return summary