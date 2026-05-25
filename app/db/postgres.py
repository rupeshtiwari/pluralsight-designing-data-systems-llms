"""PostgreSQL client stub for NorthWind Markets.

In production this would use asyncpg or SQLAlchemy async sessions.
For the course demo we simulate queries with in-memory state.
"""
from __future__ import annotations

import datetime as _dt
from typing import Any
from uuid import uuid4

import structlog

log = structlog.get_logger(__name__)

# ---------------------------------------------------------------------------
# In-memory stores (stand-in for real PostgreSQL tables)
# ---------------------------------------------------------------------------
_llm_decisions: list[dict[str, Any]] = []
_agent_decisions: list[dict[str, Any]] = []
_agent_tool_calls: list[dict[str, Any]] = []
_pipeline_runs: list[dict[str, Any]] = []
_agent_states: dict[str, dict[str, Any]] = {}


# ---------------------------------------------------------------------------
# llm_decisions
# ---------------------------------------------------------------------------

async def insert_llm_decision(record: dict[str, Any]) -> dict[str, Any]:
    record.setdefault("id", str(uuid4()))
    record.setdefault("created_at", _dt.datetime.utcnow().isoformat())
    _llm_decisions.append(record)
    log.info("pg.insert_llm_decision", record_id=record["id"])
    return record


async def get_llm_decisions(limit: int = 50) -> list[dict[str, Any]]:
    return list(reversed(_llm_decisions[-limit:]))


# ---------------------------------------------------------------------------
# agent_decisions
# ---------------------------------------------------------------------------

async def insert_agent_decision(record: dict[str, Any]) -> dict[str, Any]:
    record.setdefault("id", str(uuid4()))
    record.setdefault("created_at", _dt.datetime.utcnow().isoformat())
    _agent_decisions.append(record)
    log.info("pg.insert_agent_decision", record_id=record["id"])
    return record


async def get_agent_decisions(limit: int = 50) -> list[dict[str, Any]]:
    return list(reversed(_agent_decisions[-limit:]))


# ---------------------------------------------------------------------------
# agent_tool_calls
# ---------------------------------------------------------------------------

async def insert_agent_tool_call(record: dict[str, Any]) -> dict[str, Any]:
    record.setdefault("id", str(uuid4()))
    record.setdefault("created_at", _dt.datetime.utcnow().isoformat())
    _agent_tool_calls.append(record)
    log.info("pg.insert_agent_tool_call", record_id=record["id"])
    return record


async def get_agent_tool_calls(incident_id: str) -> list[dict[str, Any]]:
    return [r for r in _agent_tool_calls if r.get("incident_id") == incident_id]


# ---------------------------------------------------------------------------
# agent_states (keyed by incident_id)
# ---------------------------------------------------------------------------

async def upsert_agent_state(incident_id: str, state: dict[str, Any]) -> None:
    _agent_states[incident_id] = state
    log.info("pg.upsert_agent_state", incident_id=incident_id)


async def get_agent_state(incident_id: str) -> dict[str, Any] | None:
    return _agent_states.get(incident_id)


# ---------------------------------------------------------------------------
# pipeline_runs
# ---------------------------------------------------------------------------

async def insert_pipeline_run(record: dict[str, Any]) -> dict[str, Any]:
    record.setdefault("id", str(uuid4()))
    record.setdefault("created_at", _dt.datetime.utcnow().isoformat())
    _pipeline_runs.append(record)
    log.info("pg.insert_pipeline_run", record_id=record["id"])
    return record


async def get_pipeline_runs(limit: int = 50) -> list[dict[str, Any]]:
    return list(reversed(_pipeline_runs[-limit:]))


async def get_pipeline_run(batch_id: str) -> dict[str, Any] | None:
    for run in _pipeline_runs:
        if run.get("batch_id") == batch_id:
            return run
    return None


async def update_pipeline_run(batch_id: str, updates: dict[str, Any]) -> None:
    for run in _pipeline_runs:
        if run.get("batch_id") == batch_id:
            run.update(updates)
            break


# ---------------------------------------------------------------------------
# Reference-doc / metadata lookups (simulated PG queries)
# ---------------------------------------------------------------------------

async def get_product_metadata(product_id: int) -> dict[str, Any]:
    """Simulate fetching product metadata from PostgreSQL."""
    return {
        "product_id": product_id,
        "product_name": f"NorthWind Product #{product_id}",
        "category": "Beverages",
        "supplier": "NorthWind Traders",
        "unit_price": 18.00,
    }


async def get_customer_metadata(customer_id: int) -> dict[str, Any]:
    """Simulate fetching customer metadata from PostgreSQL."""
    return {
        "customer_id": customer_id,
        "company_name": f"Customer Corp #{customer_id}",
        "contact_name": "Jane Doe",
        "region": "North America",
    }


async def get_incident_metadata(incident_id: str) -> dict[str, Any]:
    """Simulate fetching incident/anomaly metadata."""
    return {
        "incident_id": incident_id,
        "system": "order_pipeline",
        "first_seen": _dt.datetime.utcnow().isoformat(),
        "affected_tables": ["orders", "order_details"],
    }
