"""LLM service stub for NorthWind Markets.

When ``LLM_STUB_MODE`` is True (the default for demos), every call returns
deterministic fake output so the rest of the pipeline can be exercised
without a real model endpoint.
"""
from __future__ import annotations

import random
from typing import Any

import structlog

from app.config import ALLOWED_CATEGORIES, ALLOWED_SEVERITIES, LLM_STUB_MODE

log = structlog.get_logger(__name__)


# ---------------------------------------------------------------------------
# Token-tracking helper
# ---------------------------------------------------------------------------

def _token_counts(prompt_len: int) -> dict[str, int]:
    """Simulate token usage based on prompt character length."""
    prompt_tokens = max(prompt_len // 4, 10)
    completion_tokens = random.randint(40, 120)
    return {
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": prompt_tokens + completion_tokens,
    }


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

async def classify_feedback(
    feedback_text: str,
    reference_docs: list[dict[str, Any]],
) -> dict[str, Any]:
    """Classify and summarise a piece of customer feedback."""
    log.info("llm.classify_feedback", stub=LLM_STUB_MODE, text_len=len(feedback_text))
    tokens = _token_counts(len(feedback_text))
    return {
        "category": random.choice(ALLOWED_CATEGORIES),
        "summary": f"Customer feedback regarding: {feedback_text[:80]}...",
        "confidence": round(random.uniform(0.60, 0.99), 2),
        "source_doc_ids": [d["doc_id"] for d in reference_docs[:3]],
        **tokens,
    }


async def summarise_dispute(
    reason: str,
    customer_history: list[dict[str, Any]],
    reference_docs: list[dict[str, Any]],
) -> dict[str, Any]:
    """Produce a risk-assessed summary for a refund dispute."""
    log.info("llm.summarise_dispute", stub=LLM_STUB_MODE)
    tokens = _token_counts(len(reason))
    risk = random.choice(["low", "medium", "high"])
    return {
        "summary": f"Dispute summary for reason: {reason[:80]}",
        "risk_level": risk,
        "key_factors": [
            "order_history_length",
            "previous_disputes",
            "product_category",
        ],
        "confidence": round(random.uniform(0.65, 0.97), 2),
        "source_doc_ids": [d["doc_id"] for d in reference_docs[:3]],
        **tokens,
    }


async def enrich_catalog(
    raw_description: str,
    existing_metadata: dict[str, Any],
    reference_docs: list[dict[str, Any]],
) -> dict[str, Any]:
    """Enrich product-catalog metadata."""
    log.info("llm.enrich_catalog", stub=LLM_STUB_MODE)
    tokens = _token_counts(len(raw_description))
    return {
        "enhanced_description": (
            f"Premium NorthWind product. {raw_description[:120]}"
        ),
        "extracted_attributes": {
            "material": "organic",
            "origin": "Pacific Northwest",
            "use_case": "retail",
            **existing_metadata,
        },
        "confidence": round(random.uniform(0.70, 0.98), 2),
        "source_doc_ids": [d["doc_id"] for d in reference_docs[:3]],
        **tokens,
    }


async def classify_severity(
    incident_context: dict[str, Any],
    runbook_docs: list[dict[str, Any]],
) -> dict[str, Any]:
    """Classify the severity of an anomaly/incident."""
    log.info("llm.classify_severity", stub=LLM_STUB_MODE)
    tokens = _token_counts(len(str(incident_context)))
    severity = random.choice(ALLOWED_SEVERITIES)
    return {
        "severity": severity,
        "evidence_summary": (
            f"Metric deviated by "
            f"{abs(incident_context.get('actual_value', 0) - incident_context.get('expected_value', 0)):.2f} "
            f"units from expected value."
        ),
        **tokens,
    }


async def recommend_action(
    incident_context: dict[str, Any],
    severity: str,
    runbook_docs: list[dict[str, Any]],
) -> dict[str, Any]:
    """Recommend a remediation action for a triaged anomaly."""
    log.info("llm.recommend_action", stub=LLM_STUB_MODE)
    tokens = _token_counts(len(str(incident_context)))
    actions = {
        "low": "Monitor for the next 24 hours; no immediate action required.",
        "medium": "Investigate upstream data source and verify row counts.",
        "high": "Page on-call engineer; pause downstream consumers.",
        "critical": "Trigger incident response; halt pipeline and notify stakeholders.",
    }
    return {
        "recommended_action": actions.get(severity, actions["medium"]),
        "root_cause_hypothesis": (
            "Potential upstream schema drift or data-source lag detected."
        ),
        **tokens,
    }
