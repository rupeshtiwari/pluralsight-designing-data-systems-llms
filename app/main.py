from contextlib import asynccontextmanager
from datetime import datetime, timezone
from typing import AsyncGenerator

import structlog
from fastapi import FastAPI

from app.config import BASE_DIR, LOG_LEVEL
from app.db import duckdb_client
from app.routers import agent, enrichment, pipeline, validation

structlog.configure(
    wrapper_class=structlog.make_filtering_bound_logger(
        getattr(structlog, LOG_LEVEL, structlog.INFO)
    ),
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
        duckdb_client.seed_feedback(str(seed_dir / "feedback.csv"))
        duckdb_client.seed_orders(str(seed_dir / "orders.csv"))
        duckdb_client.seed_refunds(str(seed_dir / "refunds.csv"))
        duckdb_client.seed_merchant_transactions(str(seed_dir / "merchant_transactions.csv"))

    try:
        from app.db import postgres_client
        postgres_client.init_tables()
        postgres_client.seed_reference_docs()
    except Exception:
        logger.warning("postgres_init_skipped", reason="connection unavailable")

    _metrics["startup_at"] = datetime.now(timezone.utc).isoformat()
    logger.info("startup_complete")

    yield

    duckdb_client.close_connection()
    try:
        from app.db import postgres_client
        postgres_client.close_connection()
    except Exception:
        pass
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
    try:
        from app.db import postgres_client
        count = postgres_client.seed_reference_docs()
        return {"status": "seeded", "documents": count}
    except Exception:
        logger.exception("seed_knowledge_base_failed")
        return {"status": "error", "documents": 0}


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

    pg_counts = {}
    try:
        from app.db import postgres_client
        pg_counts = {
            "reference_docs": postgres_client.get_table_count("reference_docs"),
            "llm_decisions": postgres_client.get_table_count("llm_decisions"),
            "agent_decisions": postgres_client.get_table_count("agent_decisions"),
            "pipeline_runs": postgres_client.get_table_count("pipeline_runs"),
        }
    except Exception:
        logger.warning("metrics_postgres_unavailable")

    return {
        **_metrics,
        "duckdb": duckdb_counts,
        "postgres": pg_counts,
    }
