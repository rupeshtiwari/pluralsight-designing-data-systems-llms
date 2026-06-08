"""Agent router for NorthWind Markets.

Prefix: /agent

Invokes a real compiled `langgraph.graph.StateGraph` whose topology is the
single source of truth for the Mermaid diagram returned by `GET /agent/graph`.

Endpoints:
    POST /agent/triage              - Run the full LangGraph workflow
    GET  /agent/state/{incident_id} - Return the latest agent state
    GET  /agent/decisions            - List recent agent decisions
    GET  /agent/graph                - Return Mermaid source + nodes + edges
"""
from __future__ import annotations

from typing import Any

import structlog
from fastapi import APIRouter, HTTPException

from app.db import postgres
from app.models.schemas import (
    AgentState,
    AnomalyTriageRequest,
    AnomalyTriageResponse,
)
from app.services import agent_graph

log = structlog.get_logger(__name__)

router = APIRouter(prefix="/agent", tags=["agent"])


# ------------------------------------------------------------------
# POST /agent/triage
# ------------------------------------------------------------------
@router.post("/triage", response_model=AnomalyTriageResponse)
async def triage_anomaly(req: AnomalyTriageRequest) -> AnomalyTriageResponse:
    incident_id = req.incident_id
    log.info("agent.triage.start", incident_id=incident_id, metric_name=req.metric_name)

    compiled = agent_graph.get_graph()
    initial_state: dict[str, Any] = {
        "incident_id": incident_id,
        "metric_name": req.metric_name,
        "expected_value": float(req.expected_value),
        "actual_value": float(req.actual_value),
        "context": dict(req.context or {}),
        "tool_calls": [],
        "current_node": "START",
    }
    final_state = await compiled.ainvoke(initial_state)

    # Persist a flat view of the agent state so GET /agent/state still works.
    snapshot = {
        "incident_id": incident_id,
        "current_node": final_state.get("current_node", "END"),
        "evidence": [
            {"step": "inspect_metadata", "data": final_state.get("metadata", {})},
            {"step": "retrieve_runbook", "docs": final_state.get("runbook_docs", [])},
            {"step": "classify_severity", "result": {
                "severity": final_state.get("severity"),
                "evidence_summary": final_state.get("evidence_summary"),
            }},
            {"step": "recommend_action", "result": {
                "recommended_action": final_state.get("recommended_action"),
                "decision_reason": final_state.get("decision_reason"),
            }},
        ],
        "decisions": [
            {
                "incident_id": incident_id,
                "severity": final_state.get("severity"),
                "recommended_action": final_state.get("recommended_action"),
                "evidence_summary": final_state.get("evidence_summary"),
                "decision_reason": final_state.get("decision_reason"),
                "selected_edge": final_state.get("selected_edge"),
                "review_required": bool(final_state.get("review_required")),
            }
        ],
        "tool_calls": final_state.get("tool_calls", []),
        "review_required": bool(final_state.get("review_required")),
    }
    await postgres.upsert_agent_state(incident_id, snapshot)

    return AnomalyTriageResponse(
        incident_id=incident_id,
        severity=final_state.get("severity", "low"),
        root_cause_hypothesis=final_state.get("decision_reason", "") or "",
        recommended_action=final_state.get("recommended_action", "") or "",
        evidence_summary=final_state.get("evidence_summary", "") or "",
        review_required=bool(final_state.get("review_required")),
    )


# ------------------------------------------------------------------
# GET /agent/graph
# ------------------------------------------------------------------
@router.get("/graph")
async def get_graph_topology() -> dict[str, Any]:
    """Return the LangGraph topology (Mermaid + nodes + edges)."""
    return agent_graph.graph_topology()


# ------------------------------------------------------------------
# GET /agent/state/{incident_id}
# ------------------------------------------------------------------
@router.get("/state/{incident_id}", response_model=AgentState)
async def get_agent_state(incident_id: str) -> AgentState:
    log.info("agent.state.get", incident_id=incident_id)
    state = await postgres.get_agent_state(incident_id)
    if state is None:
        raise HTTPException(status_code=404, detail=f"No state for incident {incident_id}")
    return AgentState(**state)


# ------------------------------------------------------------------
# GET /agent/decisions
# ------------------------------------------------------------------
@router.get("/decisions")
async def list_agent_decisions(limit: int = 50) -> list[dict[str, Any]]:
    log.info("agent.decisions.list", limit=limit)
    return await postgres.get_agent_decisions(limit=limit)
