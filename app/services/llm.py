"""LLM service stub for NorthWind Markets.

Deterministic keyword-based stub — no GPU, no API key, repeatable output
for every demo run. Category is decided by keyword matching on the
feedback text; confidence, severity, and token counts are derived from
input length so the same input always produces the same output.
"""
from __future__ import annotations

from typing import Any

import structlog

from app.config import LLM_STUB_MODE

log = structlog.get_logger(__name__)

_KEYWORD_MAP: list[tuple[list[str], str]] = [
    (["broken", "defective", "cracked", "damaged product", "malfunction", "stopped working", "snapped", "not working"], "product_quality"),
    (["late", "delayed", "delivery", "shipping", "tracking", "shipped"], "shipping_delay"),
    (["support", "representative", "agent", "help", "service", "unresponsive"], "customer_service"),
    (["price", "expensive", "cost", "increased", "pricing", "value for money"], "pricing_concern"),
    (["return", "refund", "send back", "exchange", "does not match"], "return_request"),
    (["great", "excellent", "love", "amazing", "perfect", "recommend", "praise", "happy", "outstanding"], "general_praise"),
]


def _token_counts(prompt_len: int) -> dict[str, int]:
    prompt_tokens = max(prompt_len // 4, 10)
    completion_tokens = 45 + (prompt_len % 37)
    return {
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": prompt_tokens + completion_tokens,
    }


def _classify_text(text: str) -> tuple[str, float]:
    lower = text.lower()
    for keywords, category in _KEYWORD_MAP:
        hits = sum(1 for kw in keywords if kw in lower)
        if hits > 0:
            confidence = min(0.75 + hits * 0.05, 0.98)
            return category, round(confidence, 2)
    return "general_praise", 0.55


async def classify_feedback(
    feedback_text: str,
    reference_docs: list[dict[str, Any]],
) -> dict[str, Any]:
    log.info("llm.classify_feedback", stub=LLM_STUB_MODE, text_len=len(feedback_text))
    tokens = _token_counts(len(feedback_text))
    category, confidence = _classify_text(feedback_text)
    first_sentence = feedback_text.split(".")[0].strip()
    return {
        "category": category,
        "summary": f"Customer reports: {first_sentence}",
        "confidence": confidence,
        "source_doc_ids": [d["doc_id"] for d in reference_docs[:2]],
        **tokens,
    }


async def summarise_dispute(
    reason: str,
    customer_history: dict[str, Any] | list[dict[str, Any]],
    reference_docs: list[dict[str, Any]],
) -> dict[str, Any]:
    log.info("llm.summarise_dispute", stub=LLM_STUB_MODE)
    tokens = _token_counts(len(reason))
    history = customer_history if isinstance(customer_history, dict) else {}
    prior_returns = history.get("previous_returns", 0)
    risk = "high" if prior_returns >= 3 else "medium" if prior_returns >= 1 else "low"
    return {
        "summary": f"Dispute filed: {reason[:120]}",
        "risk_level": risk,
        "key_factors": ["order_history_length", "previous_disputes", "product_category"],
        "confidence": 0.87,
        "source_doc_ids": [d["doc_id"] for d in reference_docs[:2]],
        **tokens,
    }


async def enrich_catalog(
    raw_description: str,
    existing_metadata: dict[str, Any],
    reference_docs: list[dict[str, Any]],
) -> dict[str, Any]:
    log.info("llm.enrich_catalog", stub=LLM_STUB_MODE)
    tokens = _token_counts(len(raw_description))
    return {
        "enhanced_description": f"Premium NorthWind product. {raw_description[:120]}",
        "extracted_attributes": {
            "material": "stainless steel",
            "origin": "imported",
            "use_case": "daily household",
            **existing_metadata,
        },
        "confidence": 0.91,
        "source_doc_ids": [d["doc_id"] for d in reference_docs[:2]],
        **tokens,
    }


async def classify_severity(
    incident_context: dict[str, Any],
    runbook_docs: list[dict[str, Any]],
) -> dict[str, Any]:
    log.info("llm.classify_severity", stub=LLM_STUB_MODE)
    tokens = _token_counts(len(str(incident_context)))
    expected = incident_context.get("expected_value", 0)
    actual = incident_context.get("actual_value", 0)
    if expected > 0:
        deviation_pct = abs(expected - actual) / expected * 100
    else:
        deviation_pct = 0
    if deviation_pct > 20:
        severity = "high"
    elif deviation_pct > 10:
        severity = "medium"
    elif deviation_pct > 5:
        severity = "low"
    else:
        severity = "low"
    doc_refs = ", ".join(d.get("doc_id", "?") for d in runbook_docs[:2])
    return {
        "severity": severity,
        "evidence_summary": (
            f"Metric deviated by {deviation_pct:.0f} percent from expected value. "
            f"Runbook references: {doc_refs}"
        ),
        **tokens,
    }


async def recommend_action(
    incident_context: dict[str, Any],
    severity: str,
    runbook_docs: list[dict[str, Any]],
) -> dict[str, Any]:
    log.info("llm.recommend_action", stub=LLM_STUB_MODE)
    tokens = _token_counts(len(str(incident_context)))
    actions = {
        "low": "Monitor for the next 24 hours; no immediate action required.",
        "medium": "Investigate upstream data source and verify row counts.",
        "high": "Pause downstream pipeline and investigate source system extraction.",
        "critical": "Trigger incident response; halt pipeline and notify stakeholders.",
    }
    hypotheses = {
        "low": "Minor variance within normal operational range.",
        "medium": "Possible upstream data-source lag or partial extraction.",
        "high": "Source system returned fewer records despite healthy API status; likely extraction filter or upstream schema change.",
        "critical": "Complete data pipeline failure detected.",
    }
    return {
        "recommended_action": actions.get(severity, actions["medium"]),
        "root_cause_hypothesis": hypotheses.get(severity, hypotheses["medium"]),
        **tokens,
    }
