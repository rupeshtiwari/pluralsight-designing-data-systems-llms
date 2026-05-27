from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import AsyncGenerator

import logging

import structlog
from fastapi import FastAPI

from app.config import BASE_DIR, LOG_LEVEL
from app.db import duckdb_client
from app.routers import agent, enrichment, pipeline, validation

_LOG_LEVELS = {"DEBUG": logging.DEBUG, "INFO": logging.INFO, "WARNING": logging.WARNING, "ERROR": logging.ERROR}

structlog.configure(
    wrapper_class=structlog.make_filtering_bound_logger(_LOG_LEVELS.get(LOG_LEVEL, logging.INFO)),
    processors=[
        structlog.contextvars.merge_contextvars,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.dev.ConsoleRenderer(),
    ],
)

logger = structlog.get_logger(__name__)

_metrics: dict = {
    "requests_total": 0,
    "enrichments_total": 0,
    "quarantined_total": 0,
    "startup_at": None,
}


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    logger.info("startup_begin")

    duckdb_client.init_tables()

    seed_dir = BASE_DIR / "data" / "seed"
    if seed_dir.exists():
        duckdb_client.seed_feedback(str(seed_dir / "feedback.json"))
        duckdb_client.seed_orders(str(seed_dir / "orders.json"))
        duckdb_client.seed_refunds(str(seed_dir / "refunds.json"))
        duckdb_client.seed_merchant_transactions(str(seed_dir / "merchant_transactions.json"))

    _metrics["startup_at"] = datetime.now(timezone.utc).isoformat()
    logger.info("startup_complete")

    yield

    duckdb_client.close_connection()
    logger.info("shutdown_complete")


app = FastAPI(
    title="NorthWind Markets LLM Data Service",
    lifespan=lifespan,
)

app.include_router(enrichment.router)
app.include_router(agent.router)
app.include_router(pipeline.router)
app.include_router(validation.router)


@app.get("/health")
async def health() -> dict:
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.post("/admin/reset-metrics")
async def reset_metrics() -> dict:
    _metrics["requests_total"] = 0
    _metrics["enrichments_total"] = 0
    _metrics["quarantined_total"] = 0
    logger.info("metrics_reset")
    return {"status": "metrics_reset"}


@app.post("/admin/seed-knowledge-base")
async def seed_knowledge_base() -> dict:
    from app.db import pgvector
    count = pgvector.seed_from_file(str(BASE_DIR / "data" / "seed" / "reference_docs.json"))
    return {"status": "seeded", "documents": count}


@app.get("/admin/llm-decisions")
async def list_llm_decisions(limit: int = 10) -> list:
    from app.db import postgres
    return await postgres.get_llm_decisions(limit=limit)


@app.get("/admin/metrics")
async def get_metrics() -> dict:
    duckdb_counts = {}
    try:
        duckdb_counts = {
            "raw_feedback": duckdb_client.get_table_count("raw", "feedback"),
            "raw_orders": duckdb_client.get_table_count("raw", "orders"),
            "trusted_enriched": duckdb_client.get_table_count("trusted", "feedback_enriched"),
            "quarantine_outputs": duckdb_client.get_table_count("quarantine", "llm_outputs"),
        }
    except Exception:
        logger.exception("metrics_duckdb_failed")

    return {
        **_metrics,
        "duckdb": duckdb_counts,
    }
