"""pgvector retrieval stub for NorthWind Markets.

In production this would call a pgvector-enabled PostgreSQL instance to
perform similarity search over reference documents.  For the course demo
we return deterministic fake results.
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import structlog

log = structlog.get_logger(__name__)


# ---------------------------------------------------------------------------
# Simulated reference-document store
# ---------------------------------------------------------------------------
_REFERENCE_DOCS: list[dict[str, Any]] = [
    {
        "doc_id": "DOC-001",
        "title": "Product quality standards and defect classification",
        "content": "NorthWind Markets requires all vendors to meet quality tier standards. Defective products are classified as: cosmetic damage (tier 1), functional impairment (tier 2), or safety hazard (tier 3).",
        "doc_type": "policy",
    },
    {
        "doc_id": "DOC-002",
        "title": "Return and refund processing guidelines",
        "content": "Returns are accepted within 30 days of delivery. Refunds are processed within 5 business days of return receipt.",
        "doc_type": "policy",
    },
    {
        "doc_id": "DOC-003",
        "title": "Shipping SLA and delay escalation procedures",
        "content": "Standard shipping SLA is 3-5 business days. Delays exceeding 2 business days beyond SLA trigger automatic customer notification.",
        "doc_type": "policy",
    },
    {
        "doc_id": "DOC-004",
        "title": "Merchant transaction monitoring and risk assessment",
        "content": "Merchant transactions are monitored for anomalies including chargeback rates exceeding 2 percent.",
        "doc_type": "policy",
    },
    {
        "doc_id": "DOC-005",
        "title": "Data quality incident triage runbook",
        "content": "When a data quality alert fires: 1. Check source system health. 2. Query metadata for last successful load. 3. Compare expected versus actual row counts. 4. If deviation exceeds 10 percent, classify as high severity.",
        "doc_type": "runbook",
    },
    {
        "doc_id": "DOC-006",
        "title": "Product catalog metadata standards",
        "content": "Every product listing must include: product name, category, subcategory, price, weight, dimensions, material, color options, and vendor ID.",
        "doc_type": "guideline",
    },
    {
        "doc_id": "DOC-007",
        "title": "Customer feedback classification taxonomy",
        "content": "Feedback is classified into: product_quality, shipping_delay, customer_service, pricing_concern, return_request, general_praise. Each classification requires confidence above 0.75.",
        "doc_type": "policy",
    },
    {
        "doc_id": "DOC-008",
        "title": "Pipeline anomaly detection and response procedures",
        "content": "Anomaly detection monitors: row count deviations, schema drift, null rate spikes, value distribution shifts, and freshness violations.",
        "doc_type": "runbook",
    },
]


def seed_from_file(file_path: str) -> int:
    path = Path(file_path)
    if not path.exists():
        log.warning("seed_file_not_found", path=str(path))
        return len(_REFERENCE_DOCS)
    data = json.loads(path.read_text())
    docs = data if isinstance(data, list) else []
    if docs:
        _REFERENCE_DOCS.clear()
        for doc in docs:
            _REFERENCE_DOCS.append({
                "doc_id": doc.get("id", doc.get("doc_id")),
                "title": doc.get("title", ""),
                "content": doc.get("content", ""),
                "doc_type": doc.get("doc_type", "policy"),
            })
    log.info("pgvector.seeded", count=len(_REFERENCE_DOCS))
    return len(_REFERENCE_DOCS)


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
