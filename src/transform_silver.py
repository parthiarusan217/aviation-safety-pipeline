import logging

from db import execute_sql_file, get_conn, query_to_dicts

logger = logging.getLogger(__name__)


def _row_count(conn, schema: str, table: str) -> int:
    rows = query_to_dicts(conn, f"SELECT COUNT(*) AS n FROM {schema}.{table}")
    return rows[0]["n"] if rows else 0


def run_silver() -> dict:
    logger.info("Silver transformation started")

    with get_conn() as conn:
        logger.info("Creating silver schema and tables...")
        execute_sql_file(conn, "silver/01_create_silver.sql")
        logger.info("Transforming silver.incidents...")
        execute_sql_file(conn, "silver/02_transform_silver.sql")
        inc_count = _row_count(conn, "silver", "incidents")
        logger.info("silver.incidents: %d rows loaded", inc_count)
        logger.info("Transforming vehicles, events, findings...")
        execute_sql_file(conn, "silver/03_transform_vehicles_events.sql")
        veh_count = _row_count(conn, "silver", "incident_vehicles")
        evt_count = _row_count(conn, "silver", "incident_events")
        fnd_count = _row_count(conn, "silver", "incident_findings")
        logger.info(
            "silver.incident_vehicles: %d | incident_events: %d | incident_findings: %d",
            veh_count, evt_count, fnd_count,
        )
    summary = {
        "incidents":         inc_count,
        "incident_vehicles": veh_count,
        "incident_events":   evt_count,
        "incident_findings": fnd_count,
    }
    logger.info("Silver complete: %s", summary)
    return summary