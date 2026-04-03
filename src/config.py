import os
from pathlib import Path
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(PROJECT_ROOT / ".env")

def _require(key: str) -> str:
    val = os.getenv(key)
    if not val:
        raise EnvironmentError(
            f"Required environment variable '{key}' is not set. "
            f"Copy .env.example to .env and fill in values."
        )
    return val

class Config:
    """Single source of truth for pipeline settings."""
    PG_HOST: str     = os.getenv("POSTGRES_HOST", "localhost")
    PG_PORT: int     = int(os.getenv("POSTGRES_PORT", "5432"))
    PG_DB: str       = _require("POSTGRES_DB")
    PG_USER: str     = _require("POSTGRES_USER")
    PG_PASSWORD: str = _require("POSTGRES_PASSWORD")

    @classmethod
    def pg_dsn(cls) -> str:
        return (
            f"postgresql://{cls.PG_USER}:{cls.PG_PASSWORD}"
            f"@{cls.PG_HOST}:{cls.PG_PORT}/{cls.PG_DB}"
        )

    # ── Paths ─────────────────────────────────────────────────
    DATA_DIR: Path   = PROJECT_ROOT / os.getenv("DATA_DIR", "data/raw")
    OUTPUT_DIR: Path = PROJECT_ROOT / os.getenv("OUTPUT_DIR", "outputs")
    SQL_DIR: Path    = PROJECT_ROOT / "sql"

    # ── Pipeline behaviour ───────────────────────────────────
    LOG_LEVEL: str   = os.getenv("LOG_LEVEL", "INFO")
    BATCH_SIZE: int  = int(os.getenv("BATCH_SIZE", "500"))
