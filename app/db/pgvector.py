"""pgvector retrieval stub for NorthWind Markets.

In production this would call a pgvector-enabled PostgreSQL instance to
perform similarity search over reference documents.  For the course demo
we return deterministic fake results.
"""
from __future__ import annotations

from typing import Any

import structlog

log = structlog.get_logger(__name__)


# ---------------------------------------------------------------------------
# Simulated reference-document store
# ---------------------------------------------------------------------------
_REFERENCE_DOCS: list[dict[str, Any]] = [
    {
        "doc_id": 1,
        "title": "Product Quality Standards",
        "content": "All NorthWind products must meet ISO-9001 quality standards...",
        "doc_type": "policy",
    },
    {
        "doc_id": 2,
        "title": "Shipping SLA Guidelines",
        "content": "Standard shipping within 5 business days; expedited within 2...",
        "doc_type": "policy",
    },
    {
        "doc_id": 3,
        "title": "Return & Refund Policy",
        "content": "Customers may return items within 30 days for a full refund...",
        "doc_type": "policy",
    },
    {
        "doc_id": 4,
        "title": "Anomaly Runbook - Order Pipeline",
        "content": (
            "Step 1: Check data freshness. Step 2: Verify upstream source. "
            "Step 3: Compare row counts. Step 4: Escalate if delta > 10%."
        ),
        "doc_type": "runbook",
    },
    {
        "doc_id": 5,
        "title": "Anomaly Runbook - Inventory Drift",
        "content": (
            "Step 1: Reconcile warehouse counts. Step 2: Check recent shipments. "
            "Step 3: Flag discrepancies > 5 units."
        ),
        "doc_type": "runbook",
    },
    {
        "doc_id": 6,
        "title": "Catalog Enrichment Guidelines",
        "content": (
            "Product descriptions should include material, origin, and use-case. "
            "Attributes must conform to the NorthWind product taxonomy."
        ),
        "doc_type": "guideline",
    },
]


async def retrieve_similar_docs(
    query_text: str,
    *,
    top_k: int = 3,
    doc_type: str | None = None,
) -> list[dict[str, Any]]:
    """Return the top-k most 'similar' reference documents (stubbed).

    In production this would embed *query_text* and perform a cosine-similarity
    search against the ``reference_docs`` table via pgvector.
    """
    pool = _REFERENCE_DOCS
    if doc_type:
        pool = [d for d in pool if d["doc_type"] == doc_type]
    results = pool[:top_k]
    log.info(
        "pgvector.retrieve_similar_docs",
        query_text_len=len(query_text),
        doc_type=doc_type,
        num_results=len(results),
    )
    return results
