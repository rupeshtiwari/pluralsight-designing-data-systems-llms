"""PostgreSQL client for NorthWind Markets.

Prefers a real Postgres connection (via asyncpg) when reachable. Falls back
to in-memory storage with a one-time warning if Postgres is unavailable so
local development without Docker still works.

Module 1 demo requires real PG for the llm_decisions proof. Module 2 adds
agent_tool_calls and agent_decisions to real PG with the same memory
fallback pattern so the LangGraph workflow is fully auditable end-to-end.
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
    # Module 2: agent tool-call audit trail
    await conn.execute("""
        CREATE TABLE IF NOT EXISTS agent_tool_calls (
            id UUID PRIMARY KEY,
            incident_id VARCHAR NOT NULL,
            tool_name VARCHAR NOT NULL,
            input_hash VARCHAR NOT NULL,
            output_status VARCHAR NOT NULL,
            output JSONB,
            created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        )
    """)
    await conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_agent_tool_calls_incident "
        "ON agent_tool_calls(incident_id)"
    )
    # Module 2: agent decision ledger (approval gate writes here)
    await conn.execute("""
        CREATE TABLE IF NOT EXISTS agent_decisions (
            id UUID PRIMARY KEY,
            incident_id VARCHAR NOT NULL,
            status VARCHAR NOT NULL,
            severity VARCHAR,
            recommended_action TEXT,
            evidence_summary TEXT,
            decision_reason TEXT,
            selected_edge VARCHAR,
            state JSONB,
            created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
        )
    """)
    await conn.execute(
        "CREATE INDEX IF NOT EXISTS idx_agent_decisions_incident "
        "ON agent_decisions(incident_id)"
    )


def is_postgres_available() -> bool:
    return _pool_available


# In-memory fallback stores (used only when PG is unreachable)
_mem_llm_decisions: list[dict[str, Any]] = []
_mem_agent_decisions: list[dict[str, Any]] = []
_mem_agent_tool_calls: list[dict[str, Any]] = []
_mem_pipeline_runs: list[dict[str, Any]] = []
_mem_agent_states: dict[str, dict[str, Any]] = {}
_mem_incidents: dict[str, dict[str, Any]] = {}


def seed_incidents(records: list[dict[str, Any]]) -> int:
    """Seed in-memory incident metadata used by the inspect_metadata tool.

    Real Postgres has its own per-table schemas in customer projects; for the
    course demo the incident metadata is a fixed reference catalog read by the
    agent's first tool call, so an in-memory dict keyed by incident_id is the
    simplest accurate model.
    """
    _mem_incidents.clear()
    for rec in records:
        iid = rec.get("incident_id")
        if iid:
            _mem_incidents[iid] = rec
    return len(_mem_incidents)


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


# ── agent_decisions (real PG when available) ────────────────────────────────

async def insert_agent_decision(record: dict[str, Any]) -> dict[str, Any]:
    record.setdefault("id", str(uuid4()))
    record.setdefault("created_at", _dt.datetime.utcnow().isoformat())
    pool = await _get_pool()
    if pool is not None:
        try:
            async with pool.acquire() as conn:
                await conn.execute(
                    """
                    INSERT INTO agent_decisions
                      (id, incident_id, status, severity, recommended_action,
                       evidence_summary, decision_reason, selected_edge, state)
                    VALUES ($1::uuid, $2, $3, $4, $5, $6, $7, $8, $9::jsonb)
                    """,
                    record["id"],
                    record["incident_id"],
                    record.get("status", "review_required"),
                    record.get("severity"),
                    record.get("recommended_action"),
                    record.get("evidence_summary"),
                    record.get("decision_reason"),
                    record.get("selected_edge"),
                    json.dumps(record.get("state", {}), default=str),
                )
            log.info("pg.insert_agent_decision", record_id=record["id"], backend="postgres")
            return record
        except Exception as exc:  # noqa: BLE001
            log.warning("pg.insert_agent_decision_failed", error=str(exc))
    _mem_agent_decisions.append(record)
    log.info("pg.insert_agent_decision", record_id=record["id"], backend="memory")
    return record


async def get_agent_decisions(limit: int = 50) -> list[dict[str, Any]]:
    pool = await _get_pool()
    if pool is not None:
        try:
            async with pool.acquire() as conn:
                rows = await conn.fetch(
                    """
                    SELECT id::text, incident_id, status, severity,
                           recommended_action, evidence_summary,
                           decision_reason, selected_edge, state, created_at
                    FROM agent_decisions
                    ORDER BY created_at DESC
                    LIMIT $1
                    """,
                    limit,
                )
            out = []
            for r in rows:
                d = dict(r)
                if isinstance(d.get("state"), str):
                    try:
                        d["state"] = json.loads(d["state"])
                    except Exception:  # noqa: BLE001
                        pass
                if d.get("created_at") is not None:
                    d["created_at"] = d["created_at"].isoformat()
                out.append(d)
            return out
        except Exception as exc:  # noqa: BLE001
            log.warning("pg.get_agent_decisions_failed", error=str(exc))
    return list(reversed(_mem_agent_decisions[-limit:]))


# ── agent_tool_calls (real PG when available) ───────────────────────────────

async def insert_agent_tool_call(record: dict[str, Any]) -> dict[str, Any]:
    record.setdefault("id", str(uuid4()))
    record.setdefault("created_at", _dt.datetime.utcnow().isoformat())
    pool = await _get_pool()
    if pool is not None:
        try:
            async with pool.acquire() as conn:
                await conn.execute(
                    """
                    INSERT INTO agent_tool_calls
                      (id, incident_id, tool_name, input_hash, output_status, output)
                    VALUES ($1::uuid, $2, $3, $4, $5, $6::jsonb)
                    """,
                    record["id"],
                    record["incident_id"],
                    record["tool_name"],
                    record["input_hash"],
                    record.get("output_status", "success"),
                    json.dumps(record.get("output", {}), default=str),
                )
            log.info("pg.insert_agent_tool_call", record_id=record["id"], backend="postgres")
            return record
        except Exception as exc:  # noqa: BLE001
            log.warning("pg.insert_agent_tool_call_failed", error=str(exc))
    _mem_agent_tool_calls.append(record)
    log.info("pg.insert_agent_tool_call", record_id=record["id"], backend="memory")
    return record


async def get_agent_tool_calls(
    incident_id: str | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    pool = await _get_pool()
    if pool is not None:
        try:
            async with pool.acquire() as conn:
                if incident_id:
                    rows = await conn.fetch(
                        """
                        SELECT id::text, incident_id, tool_name, input_hash,
                               output_status, output, created_at
                        FROM agent_tool_calls
                        WHERE incident_id = $1
                        ORDER BY created_at ASC
                        LIMIT $2
                        """,
                        incident_id, limit,
                    )
                else:
                    rows = await conn.fetch(
                        """
                        SELECT id::text, incident_id, tool_name, input_hash,
                               output_status, output, created_at
                        FROM agent_tool_calls
                        ORDER BY created_at DESC
                        LIMIT $1
                        """,
                        limit,
                    )
            out = []
            for r in rows:
                d = dict(r)
                if isinstance(d.get("output"), str):
                    try:
                        d["output"] = json.loads(d["output"])
                    except Exception:  # noqa: BLE001
                        pass
                if d.get("created_at") is not None:
                    d["created_at"] = d["created_at"].isoformat()
                out.append(d)
            return out
        except Exception as exc:  # noqa: BLE001
            log.warning("pg.get_agent_tool_calls_failed", error=str(exc))
    if incident_id:
        rows = [r for r in _mem_agent_tool_calls if r.get("incident_id") == incident_id]
        return rows[:limit]
    return list(reversed(_mem_agent_tool_calls[-limit:]))


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
    """Return seeded incident metadata for the agent's inspect_metadata tool.

    Looks up the seeded catalog first so demo incidents return their real
    affected tables / system / first_seen fields. Falls back to a generic
    record so the agent never errors on an unknown id.
    """
    rec = _mem_incidents.get(incident_id)
    if rec is not None:
        return {
            "incident_id": incident_id,
            "system": rec.get("system", "finance_pipeline"),
            "first_seen": rec.get("first_seen", _dt.datetime.utcnow().isoformat()),
            "affected_tables": rec.get("affected_tables", []),
            "metric_name": rec.get("metric_name"),
            "expected_value": rec.get("expected_value"),
            "actual_value": rec.get("actual_value"),
            "context": rec.get("context", {}),
        }
    return {
        "incident_id": incident_id,
        "system": "unknown_pipeline",
        "first_seen": _dt.datetime.utcnow().isoformat(),
        "affected_tables": [],
    }


async def close_pool() -> None:
    global _pool
    if _pool is not None:
        try:
            await _pool.close()
        except Exception:  # noqa: BLE001
            pass
        _pool = None
