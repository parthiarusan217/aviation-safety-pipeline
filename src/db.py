from __future__ import annotations

import logging
import time
from contextlib import contextmanager
from typing import Any, Dict, List, Optional

import psycopg2
import psycopg2.extras
from psycopg2.pool import ThreadedConnectionPool

from config import Config

logger = logging.getLogger(__name__)

_pool: Optional[ThreadedConnectionPool] = None


def init_pool(minconn: int = 1, maxconn: int = 5) -> None:
    """Initialise the connection pool. Call once at pipeline start."""
    global _pool
    _pool = ThreadedConnectionPool(
        minconn=minconn,
        maxconn=maxconn,
        dsn=Config.pg_dsn(),
        connect_timeout=10,
    )
    logger.info("DB connection pool initialised (%d-%d connections)", minconn, maxconn)


def close_pool() -> None:
    global _pool
    if _pool:
        _pool.closeall()
        _pool = None
        logger.info("DB connection pool closed")


@contextmanager
def get_conn():
    """Context manager that borrows a connection from the pool."""
    if _pool is None:
        raise RuntimeError("Connection pool not initialised. Call init_pool() first.")
    conn = _pool.getconn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        _pool.putconn(conn)


def wait_for_db(retries: int = 12, delay: float = 5.0) -> None:
    """Block until PostgreSQL is accepting connections (useful after docker-compose up)."""
    for attempt in range(1, retries + 1):
        try:
            conn = psycopg2.connect(dsn=Config.pg_dsn(), connect_timeout=5)
            conn.close()
            logger.info("PostgreSQL is ready.")
            return
        except psycopg2.OperationalError as exc:
            logger.warning(
                "DB not ready (attempt %d/%d): %s", attempt, retries, exc
            )
            time.sleep(delay)
    raise RuntimeError("PostgreSQL did not become ready in time.")


def load_sql(relative_path: str) -> str:
    """
    Load SQL from a file under sql/.
    Example: load_sql("bronze/01_create_bronze.sql")
    """
    path = Config.SQL_DIR / relative_path
    if not path.exists():
        raise FileNotFoundError(f"SQL file not found: {path}")
    return path.read_text(encoding="utf-8")


def execute_sql_file(conn: Any, relative_path: str, params: Optional[Dict] = None) -> None:
    """Execute a complete SQL file against an open connection."""
    sql = load_sql(relative_path)
    logger.debug("Executing SQL file: %s", relative_path)
    with conn.cursor() as cur:
        if params:
            cur.execute(sql, params)
        else:
            cur.execute(sql)
    logger.info("SQL file executed: %s", relative_path)


def bulk_insert(conn: Any, table: str, records: List[Dict], page_size: int = 500) -> int:
    """
    Efficiently insert a list of dicts into *table* using execute_values.
    Returns the number of rows inserted.
    """
    if not records:
        return 0

    columns = list(records[0].keys())
    col_str = ", ".join(columns)
    placeholder = "(" + ", ".join([f"%({c})s" for c in columns]) + ")"

    sql = f"INSERT INTO {table} ({col_str}) VALUES %s"

    with conn.cursor() as cur:
        psycopg2.extras.execute_values(
            cur,
            sql,
            records,
            template=placeholder,
            page_size=page_size,
        )
    inserted = len(records)
    logger.debug("Inserted %d rows into %s", inserted, table)
    return inserted


def query_to_dicts(conn: Any, sql: str, params: Any = None) -> List[Dict]:
    """Run a SELECT and return results as a list of dicts."""
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(sql, params)
        return [dict(row) for row in cur.fetchall()]
