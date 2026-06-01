"""PostgreSQL client for NorthWind Markets.

Prefers a real Postgres connection (via asyncpg) when reachable. Falls back
to in-memory storage with a one-time warning if Postgres is unavailable so
local development without Docker still works.

Module 1 demo specifically requires real PG for the llm_decisions proof.
Other tables (agent_*, pipeline_runs) currently stay in-memory until
phases 2-3 wire them to real PG.
"""
from __future__ import annotations

import datetime as _dt
import json
import os
from typing import Any
from uuid import uuid4

import structlog

log = structlog.get_logger(__name__)

POSTGRES_URL = os.environ.get(
    "POSTGRES_URL",
    "postgresql://northwind:northwind@localhost:5432/northwind",
)

_pool: Any = None
_pool_init_attempted = False
_pool_available = False


async def _get_pool() -> Any:
    global _pool, _pool_init_attempted, _pool_available
    if _pool is not None:
        return _pool
    if _pool_init_attempted:
        return None
    _pool_init_attempted = True
    try:
        import asyncpg  # type: ignore
        _pool = await asyncpg.create_pool(POSTGRES_URL, min_size=1, max_size=5, timeout=5)
        async with _pool.acquire() as conn:
            await _ensure_schema(conn)
        _pool_available = True
        log.info("pg.pool_ready", url=POSTGRES_URL.split("@")[-1])
        return _pool
    except Exception as exc:  # noqa: BLE001
        log.warning(
            "pg.unavailable_fallback_to_memory",
            error=str(exc),
            url=POSTGRES_URL.split("@")[-1],
        )
        _pool = None
        _pool_available = False
        return None


async def _ensure_schema(conn: Any) -> None:
    await conn.execute("CREATE EXTENSION IF NOT EXISTS vector")
    await conn.execute("""
        CREATE TABLE IF NOT EXISTS reference_docs (
            doc_id VARCHAR PRIMARY KEY,
            title VARCHAR,
            content TEXT,
            doc_type VARCHAR,
            source_url VARCHAR,
            embedding vector(384),
            created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        )
    """)
    await conn.execute("""
        CREATE TABLE IF NOT EXISTS llm_decisions (
            id UUID PRIMARY KEY,
            request_id VARCHAR NOT NULL,
            batch_id VARCHAR,
            endpoint VARCHAR,
            feedback_id VARCHAR,
            llm_output JSONB,
            validation JSONB,
            status VARCHAR,
            prompt_tokens INTEGER DEFAULT 0,
            completion_tokens INTEGER DEFAULT 0,
            total_tokens INTEGER DEFAULT 0,
            created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        )
    """)
    await conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_llm_decisions_request_id "
        "ON llm_decisions(request_id)"
    )


def is_postgres_available() -> bool:
    return _pool_available


# In-memory fallback stores (used only when PG is unreachable)
_mem_llm_decisions: list[dict[str, Any]] = []
_mem_agent_decisions: list[dict[str, Any]] = []
_mem_agent_tool_calls: list[dict[str, Any]] = []
_mem_pipeline_runs: list[dict[str, Any]] = []
_mem_agent_states: dict[str, dict[str, Any]] = {}


# ── llm_decisions (real PG when available) ──────────────────────────────────

async def insert_llm_decision(record: dict[str, Any]) -> dict[str, Any]:
    record.setdefault("id", str(uuid4()))
    record.setdefault("created_at", _dt.datetime.utcnow().isoformat())
    pool = await _get_pool()
    if pool is not None:
        try:
            async with pool.acquire() as conn:
                await conn.execute(
                    """
                    INSERT INTO llm_decisions
                      (id, request_id, batch_id, endpoint, feedback_id,
                       llm_output, validation, status,
                       prompt_tokens, completion_tokens, total_tokens)
                    VALUES ($1::uuid, $2, $3, $4, $5, $6::jsonb, $7::jsonb, $8, $9, $10, $11)
                    """,
                    record["id"],
                    record["request_id"],
                    record.get("batch_id"),
                    record.get("endpoint"),
                    str(record.get("feedback_id")) if record.get("feedback_id") is not None else None,
                    json.dumps(record.get("llm_output", {})),
                    json.dumps(record.get("validation", {})),
                    record.get("status"),
                    record.get("prompt_tokens", 0),
                    record.get("completion_tokens", 0),
                    record.get("total_tokens", 0),
                )
            log.info("pg.insert_llm_decision", record_id=record["id"], backend="postgres")
            return record
        except Exception as exc:  # noqa: BLE001
            log.warning("pg.insert_llm_decision_failed", error=str(exc))
    _mem_llm_decisions.append(record)
    log.info("pg.insert_llm_decision", record_id=record["id"], backend="memory")
    return record


async def get_llm_decisions(limit: int = 50) -> list[dict[str, Any]]:
    pool = await _get_pool()
    if pool is not None:
        try:
            async with pool.acquire() as conn:
                rows = await conn.fetch(
                    """
                    SELECT id::text, request_id, batch_id, endpoint, feedback_id,
                           llm_output, validation, status,
                           prompt_tokens, completion_tokens, total_tokens,
                           created_at
                    FROM llm_decisions
                    ORDER BY created_at DESC
                    LIMIT $1
                    """,
                    limit,
                )
            result = []
            for r in rows:
                d = dict(r)
                for k in ("llm_output", "validation"):
                    v = d.get(k)
                    if isinstance(v, str):
                        try:
                            d[k] = json.loads(v)
                        except Exception:  # noqa: BLE001
                            pass
                if d.get("created_at") is not None:
                    d["created_at"] = d["created_at"].isoformat()
                result.append(d)
            return result
        except Exception as exc:  # noqa: BLE001
            log.warning("pg.get_llm_decisions_failed", error=str(exc))
    return list(reversed(_mem_llm_decisions[-limit:]))


# ── Remaining tables stay in-memory until phases 2-3 ────────────────────────

async def insert_agent_decision(record: dict[str, Any]) -> dict[str, Any]:
    record.setdefault("id", str(uuid4()))
    record.setdefault("created_at", _dt.datetime.utcnow().isoformat())
    _mem_agent_decisions.append(record)
    return record


async def get_agent_decisions(limit: int = 50) -> list[dict[str, Any]]:
    return list(reversed(_mem_agent_decisions[-limit:]))


async def insert_agent_tool_call(record: dict[str, Any]) -> dict[str, Any]:
    record.setdefault("id", str(uuid4()))
    record.setdefault("created_at", _dt.datetime.utcnow().isoformat())
    _mem_agent_tool_calls.append(record)
    return record


async def get_agent_tool_calls(incident_id: str) -> list[dict[str, Any]]:
    return [r for r in _mem_agent_tool_calls if r.get("incident_id") == incident_id]


async def upsert_agent_state(incident_id: str, state: dict[str, Any]) -> None:
    _mem_agent_states[incident_id] = state


async def get_agent_state(incident_id: str) -> dict[str, Any] | None:
    return _mem_agent_states.get(incident_id)


async def insert_pipeline_run(record: dict[str, Any]) -> dict[str, Any]:
    record.setdefault("id", str(uuid4()))
    record.setdefault("created_at", _dt.datetime.utcnow().isoformat())
    _mem_pipeline_runs.append(record)
    return record


async def get_pipeline_runs(limit: int = 50) -> list[dict[str, Any]]:
    return list(reversed(_mem_pipeline_runs[-limit:]))


async def get_pipeline_run(batch_id: str) -> dict[str, Any] | None:
    for run in _mem_pipeline_runs:
        if run.get("batch_id") == batch_id:
            return run
    return None


async def update_pipeline_run(batch_id: str, updates: dict[str, Any]) -> None:
    for run in _mem_pipeline_runs:
        if run.get("batch_id") == batch_id:
            run.update(updates)
            break


async def get_product_metadata(product_id: int | str) -> dict[str, Any]:
    return {
        "product_id": product_id,
        "product_name": f"NorthWind Product #{product_id}",
        "category": "Beverages",
        "supplier": "NorthWind Traders",
        "unit_price": 18.00,
    }


async def get_customer_metadata(customer_id: int | str) -> dict[str, Any]:
    return {
        "customer_id": customer_id,
        "company_name": f"Customer Corp #{customer_id}",
        "contact_name": "Jane Doe",
        "region": "North America",
    }


async def get_incident_metadata(incident_id: str) -> dict[str, Any]:
    return {
        "incident_id": incident_id,
        "system": "order_pipeline",
        "first_seen": _dt.datetime.utcnow().isoformat(),
        "affected_tables": ["orders", "order_details"],
    }


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        try:
            await _pool.close()
        except Exception:  # noqa: BLE001
            pass
        _pool = None
