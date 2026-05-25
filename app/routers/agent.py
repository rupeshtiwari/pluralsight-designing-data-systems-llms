"""Agent router for NorthWind Markets.

Prefix: /agent

Implements a LangGraph-style triage workflow for anomaly incidents:
    inspect_metadata -> retrieve_runbook -> classify_severity
        -> recommend_action -> approval_gate

Endpoints:
    POST /agent/triage              - Run the full triage workflow
    GET  /agent/state/{incident_id} - Return current agent state
    GET  /agent/decisions            - List recent agent decisions
"""
from __future__ import annotations

import datetime as _dt
from typing import Any
from uuid import uuid4

import structlog
from fastapi import APIRouter, HTTPException

from app.db import pgvector, postgres
from app.models.schemas import AgentState, AnomalyTriageRequest, AnomalyTriageResponse
from app.services import llm

log = structlog.get_logger(__name__)

router = APIRouter(prefix="/agent", tags=["agent"])


# ------------------------------------------------------------------
# Helpers – LangGraph-style step runner
# ------------------------------------------------------------------

async def _record_tool_call(
    incident_id: str,
    step_name: str,
    input_data: dict[str, Any],
    output_data: dict[str, Any],
    tokens: dict[str, int] | None = None,
) -> dict[str, Any]:
    """Persist a tool_call record and return it."""
    record = {
        "incident_id": incident_id,
        "step": step_name,
        "input": input_data,
        "output": output_data,
        "prompt_tokens": (tokens or {}).get("prompt_tokens", 0),
        "completion_tokens": (tokens or {}).get("completion_tokens", 0),
        "total_tokens": (tokens or {}).get("total_tokens", 0),
        "timestamp": _dt.datetime.utcnow().isoformat(),
    }
    await postgres.insert_agent_tool_call(record)
    return record


# ------------------------------------------------------------------
# POST /agent/triage
# ------------------------------------------------------------------
@router.post("/triage", response_model=AnomalyTriageResponse)
async def triage_anomaly(req: AnomalyTriageRequest) -> AnomalyTriageResponse:
    incident_id = req.incident_id
    log.info(
        "agent.triage.start",
        incident_id=incident_id,
        metric_name=req.metric_name,
    )

    # Accumulate state as we move through the graph
    state = AgentState(incident_id=incident_id, current_node="inspect_metadata")
    tool_calls: list[dict[str, Any]] = []

    # ---- Step 1: inspect_metadata (query PG) --------------------------
    log.info("agent.triage.step", step="inspect_metadata", incident_id=incident_id)
    metadata = await postgres.get_incident_metadata(incident_id)
    tc = await _record_tool_call(
        incident_id,
        "inspect_metadata",
        {"incident_id": incident_id},
        metadata,
    )
    tool_calls.append(tc)
    state.current_node = "retrieve_runbook"
    state.evidence.append({"step": "inspect_metadata", "data": metadata})

    # ---- Step 2: retrieve_runbook (query reference_docs via pgvector) --
    log.info("agent.triage.step", step="retrieve_runbook", incident_id=incident_id)
    runbook_docs = await pgvector.retrieve_similar_docs(
        req.metric_name, top_k=2, doc_type="runbook"
    )
    tc = await _record_tool_call(
        incident_id,
        "retrieve_runbook",
        {"query": req.metric_name, "doc_type": "runbook"},
        {"docs": runbook_docs},
    )
    tool_calls.append(tc)
    state.current_node = "classify_severity"
    state.evidence.append({"step": "retrieve_runbook", "docs": runbook_docs})

    # ---- Step 3: classify_severity (LLM stub) -------------------------
    log.info("agent.triage.step", step="classify_severity", incident_id=incident_id)
    incident_context = {
        "incident_id": incident_id,
        "metric_name": req.metric_name,
        "expected_value": req.expected_value,
        "actual_value": req.actual_value,
        "metadata": metadata,
        **req.context,
    }
    severity_result = await llm.classify_severity(incident_context, runbook_docs)

    severity_tokens = {
        "prompt_tokens": severity_result.pop("prompt_tokens", 0),
        "completion_tokens": severity_result.pop("completion_tokens", 0),
        "total_tokens": severity_result.pop("total_tokens", 0),
    }
    log.info(
        "agent.triage.tokens",
        step="classify_severity",
        incident_id=incident_id,
        **severity_tokens,
    )
    tc = await _record_tool_call(
        incident_id,
        "classify_severity",
        incident_context,
        severity_result,
        tokens=severity_tokens,
    )
    tool_calls.append(tc)
    state.current_node = "recommend_action"
    state.evidence.append({"step": "classify_severity", "result": severity_result})

    severity = severity_result["severity"]
    evidence_summary = severity_result["evidence_summary"]

    # ---- Step 4: recommend_action (LLM stub) --------------------------
    log.info("agent.triage.step", step="recommend_action", incident_id=incident_id)
    action_result = await llm.recommend_action(
        incident_context, severity, runbook_docs
    )

    action_tokens = {
        "prompt_tokens": action_result.pop("prompt_tokens", 0),
        "completion_tokens": action_result.pop("completion_tokens", 0),
        "total_tokens": action_result.pop("total_tokens", 0),
    }
    log.info(
        "agent.triage.tokens",
        step="recommend_action",
        incident_id=incident_id,
        **action_tokens,
    )
    tc = await _record_tool_call(
        incident_id,
        "recommend_action",
        {"severity": severity},
        action_result,
        tokens=action_tokens,
    )
    tool_calls.append(tc)
    state.current_node = "approval_gate"
    state.evidence.append({"step": "recommend_action", "result": action_result})

    recommended_action = action_result["recommended_action"]
    root_cause_hypothesis = action_result["root_cause_hypothesis"]

    # ---- Step 5: approval_gate ----------------------------------------
    log.info("agent.triage.step", step="approval_gate", incident_id=incident_id)
    state.review_required = True
    state.current_node = "completed"

    decision_record = {
        "incident_id": incident_id,
        "severity": severity,
        "root_cause_hypothesis": root_cause_hypothesis,
        "recommended_action": recommended_action,
        "evidence_summary": evidence_summary,
        "review_required": True,
        "tool_calls_count": len(tool_calls),
        "total_prompt_tokens": severity_tokens["prompt_tokens"] + action_tokens["prompt_tokens"],
        "total_completion_tokens": severity_tokens["completion_tokens"] + action_tokens["completion_tokens"],
        "total_tokens": severity_tokens["total_tokens"] + action_tokens["total_tokens"],
    }

    tc = await _record_tool_call(
        incident_id,
        "approval_gate",
        {"review_required": True},
        decision_record,
    )
    tool_calls.append(tc)
    state.decisions.append(decision_record)

    # Persist decision and state
    await postgres.insert_agent_decision(decision_record)
    state.tool_calls = tool_calls
    await postgres.upsert_agent_state(incident_id, state.model_dump())

    log.info(
        "agent.triage.done",
        incident_id=incident_id,
        severity=severity,
        review_required=True,
    )

    return AnomalyTriageResponse(
        incident_id=incident_id,
        severity=severity,
        root_cause_hypothesis=root_cause_hypothesis,
        recommended_action=recommended_action,
        evidence_summary=evidence_summary,
        review_required=True,
    )


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
