"""Real LangGraph StateGraph for Module 2 Clip 4.

Compiles a real `langgraph.graph.StateGraph` so the Mermaid diagram returned
by `GET /agent/graph` is generated from the actual topology — not a
hand-written string. Every node also writes a row into the real Postgres
`agent_tool_calls` table (with in-memory fallback) so the workflow is
end-to-end auditable.

Topology:

    START -> inspect_metadata -> retrieve_runbook -> classify_severity
                                                          |
                                            +-------------+--------------+
                                            |                            |
                              (high/critical: recommend_action)   (low: auto_log)
                                            |                            |
                                     approval_gate                      END
                                            |
                                           END

`approval_gate` sets `review_required=True` and writes an `agent_decisions`
row with status="review_required". `auto_log` writes an `agent_decisions`
row with status="auto_logged" — proving the conditional edge protects
trusted tables.
"""
from __future__ import annotations

import hashlib
import json
from typing import Annotated, Any, TypedDict

import structlog
from langgraph.graph import END, START, StateGraph

from app.db import pgvector, postgres
from app.services import llm

log = structlog.get_logger(__name__)


# ---------------------------------------------------------------------------
# State definition
# ---------------------------------------------------------------------------

def _merge_lists(left: list, right: list) -> list:
    """Reducer that appends to a list field across node returns."""
    return (left or []) + (right or [])


class AgentState(TypedDict, total=False):
    incident_id: str
    metric_name: str
    expected_value: float
    actual_value: float
    metadata: dict
    runbook_docs: list
    severity: str
    recommended_action: str
    evidence_summary: str
    decision_reason: str
    selected_edge: str
    review_required: bool
    tool_calls: Annotated[list, _merge_lists]
    current_node: str
    context: dict


# ---------------------------------------------------------------------------
# Tool-call audit helper
# ---------------------------------------------------------------------------

def _input_hash(payload: Any) -> str:
    """sha256 of canonicalized JSON input — durable across runs."""
    blob = json.dumps(payload, sort_keys=True, default=str).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


async def _record_tool_call(
    incident_id: str,
    tool_name: str,
    tool_input: Any,
    output: Any,
    status: str = "success",
) -> dict[str, Any]:
    record = {
        "incident_id": incident_id,
        "tool_name": tool_name,
        "input_hash": _input_hash(tool_input),
        "output_status": status,
        "output": output if isinstance(output, dict) else {"value": output},
    }
    await postgres.insert_agent_tool_call(record)
    # The state-side copy carries the same shape but omits PG-only fields
    return {
        "tool_name": tool_name,
        "input_hash": record["input_hash"],
        "output_status": status,
    }


# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------

async def inspect_metadata(state: AgentState) -> dict[str, Any]:
    incident_id = state["incident_id"]
    log.info("agent.node", node="inspect_metadata", incident_id=incident_id)
    try:
        metadata = await postgres.get_incident_metadata(incident_id)
        status = "success"
    except Exception as exc:  # noqa: BLE001
        log.warning("agent.node.error", node="inspect_metadata", error=str(exc))
        metadata = {"incident_id": incident_id, "error": str(exc)}
        status = "error"
    tc = await _record_tool_call(
        incident_id, "inspect_metadata", {"incident_id": incident_id}, metadata, status
    )
    return {"metadata": metadata, "tool_calls": [tc], "current_node": "inspect_metadata"}


async def retrieve_runbook(state: AgentState) -> dict[str, Any]:
    incident_id = state["incident_id"]
    metric = state.get("metric_name", "")
    log.info("agent.node", node="retrieve_runbook", incident_id=incident_id)
    try:
        docs = await pgvector.retrieve_similar_docs(metric, top_k=2, doc_type="runbook")
        status = "success"
    except Exception as exc:  # noqa: BLE001
        log.warning("agent.node.error", node="retrieve_runbook", error=str(exc))
        docs = []
        status = "error"
    tc = await _record_tool_call(
        incident_id,
        "retrieve_runbook",
        {"query": metric, "doc_type": "runbook"},
        {"doc_count": len(docs), "doc_ids": [d.get("doc_id") for d in docs]},
        status,
    )
    return {"runbook_docs": docs, "tool_calls": [tc], "current_node": "retrieve_runbook"}


async def classify_severity(state: AgentState) -> dict[str, Any]:
    incident_id = state["incident_id"]
    log.info("agent.node", node="classify_severity", incident_id=incident_id)
    # Deterministic severity rule (also matches the LLM stub):
    #   abs(actual-expected)/expected > 0.2 -> high, else low
    expected = float(state.get("expected_value") or 0)
    actual = float(state.get("actual_value") or 0)
    if expected > 0:
        deviation = abs(expected - actual) / expected
    else:
        deviation = 0.0
    severity = "high" if deviation > 0.2 else "low"

    incident_context = {
        "incident_id": incident_id,
        "metric_name": state.get("metric_name"),
        "expected_value": expected,
        "actual_value": actual,
        "metadata": state.get("metadata", {}),
        **(state.get("context") or {}),
    }
    llm_result = await llm.classify_severity(incident_context, state.get("runbook_docs", []))
    # Override the LLM stub's severity with the deterministic >0.2 rule
    # required by the outline so INC-001 routes to recommend_action and
    # INC-003 routes to auto_log without surprises.
    llm_result["severity"] = severity
    evidence_summary = llm_result.get("evidence_summary", "")

    tc = await _record_tool_call(
        incident_id,
        "classify_severity",
        {"expected": expected, "actual": actual, "deviation_pct": round(deviation * 100, 2)},
        {"severity": severity, "deviation_pct": round(deviation * 100, 2)},
    )
    return {
        "severity": severity,
        "evidence_summary": evidence_summary,
        "tool_calls": [tc],
        "current_node": "classify_severity",
    }


async def recommend_action(state: AgentState) -> dict[str, Any]:
    incident_id = state["incident_id"]
    severity = state.get("severity", "low")
    log.info("agent.node", node="recommend_action", incident_id=incident_id, severity=severity)
    incident_context = {
        "incident_id": incident_id,
        "metric_name": state.get("metric_name"),
        "expected_value": state.get("expected_value"),
        "actual_value": state.get("actual_value"),
        "metadata": state.get("metadata", {}),
    }
    result = await llm.recommend_action(incident_context, severity, state.get("runbook_docs", []))
    action = result.get("recommended_action", "")
    hypothesis = result.get("root_cause_hypothesis", "")
    tc = await _record_tool_call(
        incident_id,
        "recommend_action",
        {"severity": severity},
        {"recommended_action": action, "root_cause_hypothesis": hypothesis},
    )
    return {
        "recommended_action": action,
        "decision_reason": hypothesis,
        "selected_edge": "recommend_action",
        "tool_calls": [tc],
        "current_node": "recommend_action",
    }


async def approval_gate(state: AgentState) -> dict[str, Any]:
    incident_id = state["incident_id"]
    log.info("agent.node", node="approval_gate", incident_id=incident_id)
    decision = {
        "incident_id": incident_id,
        "status": "review_required",
        "severity": state.get("severity"),
        "recommended_action": state.get("recommended_action"),
        "evidence_summary": state.get("evidence_summary"),
        "decision_reason": state.get("decision_reason"),
        "selected_edge": "recommend_action",
        "state": {
            "incident_id": incident_id,
            "metric_name": state.get("metric_name"),
            "severity": state.get("severity"),
            "recommended_action": state.get("recommended_action"),
            "review_required": True,
        },
    }
    await postgres.insert_agent_decision(decision)
    tc = await _record_tool_call(
        incident_id,
        "approval_gate",
        {"review_required": True},
        {"status": "review_required"},
    )
    return {
        "review_required": True,
        "tool_calls": [tc],
        "current_node": "approval_gate",
    }


async def auto_log(state: AgentState) -> dict[str, Any]:
    """Terminal low-severity branch — logs without writing to trusted tables."""
    incident_id = state["incident_id"]
    log.info("agent.node", node="auto_log", incident_id=incident_id)
    reason = "Deviation below 20% threshold — auto-logged for trend analysis only."
    decision = {
        "incident_id": incident_id,
        "status": "auto_logged",
        "severity": state.get("severity"),
        "recommended_action": "Monitor; no action required.",
        "evidence_summary": state.get("evidence_summary"),
        "decision_reason": reason,
        "selected_edge": "auto_log",
        "state": {
            "incident_id": incident_id,
            "metric_name": state.get("metric_name"),
            "severity": state.get("severity"),
            "review_required": False,
        },
    }
    await postgres.insert_agent_decision(decision)
    tc = await _record_tool_call(
        incident_id,
        "auto_log",
        {"severity": state.get("severity")},
        {"status": "auto_logged"},
    )
    return {
        "recommended_action": "Monitor; no action required.",
        "decision_reason": reason,
        "selected_edge": "auto_log",
        "review_required": False,
        "tool_calls": [tc],
        "current_node": "auto_log",
    }


# ---------------------------------------------------------------------------
# Conditional edge
# ---------------------------------------------------------------------------

def _route_after_severity(state: AgentState) -> str:
    """Conditional edge: high/critical -> recommend_action, else auto_log."""
    sev = (state.get("severity") or "").lower()
    if sev in ("high", "critical"):
        return "recommend_action"
    return "auto_log"


# ---------------------------------------------------------------------------
# Compile graph (once, cached)
# ---------------------------------------------------------------------------

_COMPILED = None


def get_graph():
    """Return the compiled LangGraph workflow — cached after first build."""
    global _COMPILED
    if _COMPILED is not None:
        return _COMPILED

    g = StateGraph(AgentState)
    g.add_node("inspect_metadata", inspect_metadata)
    g.add_node("retrieve_runbook", retrieve_runbook)
    g.add_node("classify_severity", classify_severity)
    g.add_node("recommend_action", recommend_action)
    g.add_node("approval_gate", approval_gate)
    g.add_node("auto_log", auto_log)

    g.add_edge(START, "inspect_metadata")
    g.add_edge("inspect_metadata", "retrieve_runbook")
    g.add_edge("retrieve_runbook", "classify_severity")
    g.add_conditional_edges(
        "classify_severity",
        _route_after_severity,
        {"recommend_action": "recommend_action", "auto_log": "auto_log"},
    )
    g.add_edge("recommend_action", "approval_gate")
    g.add_edge("approval_gate", END)
    g.add_edge("auto_log", END)

    _COMPILED = g.compile()
    return _COMPILED


def graph_topology() -> dict[str, Any]:
    """Return mermaid source + node/edge metadata derived from the compiled graph."""
    compiled = get_graph()
    graph_view = compiled.get_graph()
    mermaid = graph_view.draw_mermaid()
    nodes = [n.id for n in graph_view.nodes.values()]
    edges = [
        {"source": e.source, "target": e.target, "conditional": bool(e.conditional)}
        for e in graph_view.edges
    ]
    return {"mermaid": mermaid, "nodes": nodes, "edges": edges}
