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

    # Seed pgvector reference docs (real PG when reachable, memory otherwise)
    try:
        from app.db import pgvector
        await pgvector.seed_from_file(str(seed_dir / "reference_docs.json"))
    except Exception:
        logger.warning("pgvector_seed_skipped")

    # Seed incident metadata catalog used by the agent's inspect_metadata tool
    try:
        import json as _json
        from app.db import postgres as _pg
        incidents_path = seed_dir / "incidents.json"
        if incidents_path.exists():
            _pg.seed_incidents(_json.loads(incidents_path.read_text()))
    except Exception:
        logger.warning("incidents_seed_skipped")

    _metrics["startup_at"] = datetime.now(timezone.utc).isoformat()
    logger.info("startup_complete")

    yield

    duckdb_client.close_connection()
    try:
        from app.db import postgres
        await postgres.close_pool()
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
    from app.db import pgvector, postgres
    count = await pgvector.seed_from_file(str(BASE_DIR / "data" / "seed" / "reference_docs.json"))
    return {
        "status": "seeded",
        "documents": count,
        "backend": "postgres" if postgres.is_postgres_available() else "memory",
    }


@app.get("/admin/json-contract")
async def get_json_contract() -> dict:
    """Return the FeedbackEnrichResponse JSON contract introduced in Clip 2.

    The deterministic pipeline never sees free-form LLM text — it only
    sees this shape. The Module 1 demo uses this endpoint to show the
    boundary contract on screen before calling the enrich endpoint.
    """
    from app.models.schemas import FeedbackEnrichResponse, FeedbackEnrichRequest
    return {
        "contract_name": "FeedbackEnrichResponse",
        "purpose": "LLM proposal contract — deterministic pipeline only reads these fields",
        "request_schema": FeedbackEnrichRequest.model_json_schema(),
        "response_schema": FeedbackEnrichResponse.model_json_schema(),
        "validation_gates": [
            "schema (required fields present)",
            "grounding (every source_doc_id in approved set)",
            "confidence (>= 0.75 threshold)",
            "source ID (cited docs exist in reference_docs)",
        ],
    }


@app.get("/admin/reference-docs")
async def list_reference_docs(limit: int = 20) -> dict:
    """List the pgvector-seeded reference documents (Module 1 proof point)."""
    from app.db import pgvector, postgres
    docs = await pgvector.list_reference_docs(limit=limit)
    return {
        "backend": "postgres" if postgres.is_postgres_available() else "memory",
        "count": len(docs),
        "documents": docs,
    }


@app.get("/admin/llm-decisions")
async def list_llm_decisions(limit: int = 10) -> list:
    from app.db import postgres
    return await postgres.get_llm_decisions(limit=limit)


@app.get("/admin/agent-tool-calls")
async def list_agent_tool_calls(
    incident_id: str | None = None,
    limit: int = 20,
) -> dict:
    """List recorded tool calls. The Module 2 Step 3 proof point."""
    from app.db import postgres
    rows = await postgres.get_agent_tool_calls(incident_id=incident_id, limit=limit)
    return {
        "backend": "postgres" if postgres.is_postgres_available() else "memory",
        "incident_id": incident_id,
        "count": len(rows),
        "tool_calls": rows,
    }


@app.get("/admin/agent-decisions")
async def list_admin_agent_decisions(limit: int = 10) -> dict:
    """List agent decision ledger rows. The Module 2 Step 4 proof point."""
    from app.db import postgres
    rows = await postgres.get_agent_decisions(limit=limit)
    return {
        "backend": "postgres" if postgres.is_postgres_available() else "memory",
        "count": len(rows),
        "decisions": rows,
    }


@app.get("/admin/metrics")
async def get_metrics() -> dict:
    from app.db import postgres
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
        "postgres": {
            "available": postgres.is_postgres_available(),
            "url": postgres.POSTGRES_URL.split("@")[-1],
        },
    }
