import argparse
import logging
import sys
import time
import uuid
from datetime import datetime, timezone

from config import Config
from db import close_pool, init_pool, wait_for_db
from ingest_bronze import run_bronze
from transform_gold import run_gold
from transform_silver import run_silver


def setup_logging() -> None:
    logging.basicConfig(
        level=getattr(logging, Config.LOG_LEVEL, logging.INFO),
        format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
        handlers=[
            logging.StreamHandler(sys.stdout),
        ],
    )


def run_pipeline(stage: str = "gold") -> dict:
    run_id = str(uuid.uuid4())
    started = datetime.now(timezone.utc)
    logger = logging.getLogger(__name__)
    logger.info("=" * 60)
    logger.info("Aviation Safety Pipeline | run_id=%s", run_id)
    logger.info("Stage target: %s | Config: %s@%s:%s/%s",
                stage, Config.PG_USER, Config.PG_HOST,
                Config.PG_PORT, Config.PG_DB)
    logger.info("=" * 60)
    results: dict = {"run_id": run_id, "stage": stage}

    try:
        wait_for_db()
        init_pool()
        t0 = time.perf_counter()
        bronze_summary = run_bronze(run_id=run_id)
        results["bronze"] = bronze_summary
        results["bronze_elapsed_s"] = round(time.perf_counter() - t0, 2)
        logger.info("Bronze stage completed in %.2fs", results["bronze_elapsed_s"])
        if stage == "bronze":
            return _finish(results, started, logger)
        t0 = time.perf_counter()
        silver_summary = run_silver()
        results["silver"] = silver_summary
        results["silver_elapsed_s"] = round(time.perf_counter() - t0, 2)
        logger.info("Silver stage completed in %.2fs", results["silver_elapsed_s"])
        if stage == "silver":
            return _finish(results, started, logger)
        t0 = time.perf_counter()
        gold_summary = run_gold()
        results["gold"] = gold_summary
        results["gold_elapsed_s"] = round(time.perf_counter() - t0, 2)
        logger.info("Gold stage completed in %.2fs", results["gold_elapsed_s"])
        return _finish(results, started, logger)
    except Exception as exc:
        logger.exception("Pipeline failed: %s", exc)
        results["error"] = str(exc)
        sys.exit(1)
    finally:
        close_pool()

def _finish(results: dict, started: datetime, logger: logging.Logger) -> dict:
    elapsed = (datetime.now(timezone.utc) - started).total_seconds()
    results["total_elapsed_s"] = round(elapsed, 2)
    logger.info("=" * 60)
    logger.info("Pipeline finished in %.2fs", elapsed)
    logger.info("=" * 60)
    return results

def main() -> None:
    setup_logging()
    parser = argparse.ArgumentParser(
        description="Aviation Safety Medallion Pipeline"
    )
    parser.add_argument(
        "--stage",
        choices=["bronze", "silver", "gold"],
        default="gold",
        help="Run up to and including this stage (default: gold = full pipeline)",
    )
    args = parser.parse_args()
    run_pipeline(stage=args.stage)

if __name__ == "__main__":
    main()
