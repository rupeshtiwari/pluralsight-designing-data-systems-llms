"""Enrichment router for NorthWind Markets.

Prefix: /enrich

Endpoints:
    POST /enrich/feedback  - Classify & summarise customer feedback via LLM
    POST /enrich/dispute   - Summarise a refund dispute
    POST /enrich/catalog   - Enrich product-catalog metadata
"""
from __future__ import annotations

from uuid import uuid4

import structlog
from fastapi import APIRouter

from app.db import duckdb_client, pgvector, postgres
from app.models.schemas import (
    CatalogEnrichRequest,
    CatalogEnrichResponse,
    DisputeSummaryRequest,
    DisputeSummaryResponse,
    FeedbackEnrichRequest,
    FeedbackEnrichResponse,
)
from app.services import llm
from app.validators.output_validator import validate_enrichment_output, VALIDATION_RULES

log = structlog.get_logger(__name__)

router = APIRouter(prefix="/enrich", tags=["enrichment"])


# ------------------------------------------------------------------
# POST /enrich/feedback
# ------------------------------------------------------------------
@router.post("/feedback", response_model=FeedbackEnrichResponse)
async def enrich_feedback(req: FeedbackEnrichRequest) -> FeedbackEnrichResponse:
    request_id = str(uuid4())
    log.info(
        "enrich.feedback.start",
        request_id=request_id,
        feedback_id=req.feedback_id,
        customer_id=req.customer_id,
        product_id=req.product_id,
    )

    # 1. Retrieve relevant reference docs from pgvector
    ref_docs = await pgvector.retrieve_similar_docs(
        req.feedback_text, top_k=3, doc_type="policy"
    )

    # 2. Call LLM stub for classification / summarisation
    llm_output = await llm.classify_feedback(req.feedback_text, ref_docs)

    # 3. Track tokens
    prompt_tokens = llm_output.pop("prompt_tokens", 0)
    completion_tokens = llm_output.pop("completion_tokens", 0)
    total_tokens = llm_output.pop("total_tokens", 0)
    log.info(
        "enrich.feedback.tokens",
        request_id=request_id,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        total_tokens=total_tokens,
    )

    # 4. Validate output
    known_doc_ids = [d["doc_id"] for d in ref_docs]
    validation = validate_enrichment_output(
        llm_output,
        required_fields=VALIDATION_RULES["required_fields_feedback"],
        known_doc_ids=known_doc_ids,
    )

    if validation["is_valid"]:
        validation_status = "accepted"
    else:
        validation_status = "failed"

    # 5. Store decision in llm_decisions
    await postgres.insert_llm_decision(
        {
            "request_id": request_id,
            "endpoint": "feedback",
            "feedback_id": req.feedback_id,
            "llm_output": llm_output,
            "validation": validation,
            "status": validation_status,
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": total_tokens,
        }
    )

    category = llm_output.get("category", "unknown")
    summary = llm_output.get("summary", "")
    confidence = llm_output.get("confidence", 0.0)
    source_doc_ids = llm_output.get("source_doc_ids", [])

    if validation_status == "accepted":
        duckdb_client.insert_enriched_feedback({
            "id": req.feedback_id,
            "request_id": request_id,
            "customer_id": req.customer_id,
            "product_id": req.product_id,
            "feedback_text": req.feedback_text,
            "category": category,
            "summary": summary,
            "confidence": confidence,
            "source_doc_ids": source_doc_ids,
            "validation_status": validation_status,
        })

    log.info(
        "enrich.feedback.done",
        request_id=request_id,
        validation_status=validation_status,
    )

    return FeedbackEnrichResponse(
        request_id=request_id,
        category=category,
        summary=summary,
        confidence=confidence,
        source_doc_ids=source_doc_ids,
        validation_status=validation_status,
    )


# ------------------------------------------------------------------
# POST /enrich/dispute
# ------------------------------------------------------------------
@router.post("/dispute", response_model=DisputeSummaryResponse)
async def enrich_dispute(req: DisputeSummaryRequest) -> DisputeSummaryResponse:
    request_id = str(uuid4())
    log.info(
        "enrich.dispute.start",
        request_id=request_id,
        refund_id=req.refund_id,
        order_id=req.order_id,
    )

    # 1. Retrieve reference docs
    ref_docs = await pgvector.retrieve_similar_docs(
        req.reason, top_k=3, doc_type="policy"
    )

    # 2. Call LLM stub
    llm_output = await llm.summarise_dispute(
        req.reason, req.customer_history, ref_docs
    )

    # 3. Track tokens
    prompt_tokens = llm_output.pop("prompt_tokens", 0)
    completion_tokens = llm_output.pop("completion_tokens", 0)
    total_tokens = llm_output.pop("total_tokens", 0)
    log.info(
        "enrich.dispute.tokens",
        request_id=request_id,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        total_tokens=total_tokens,
    )

    # 4. Store decision
    await postgres.insert_llm_decision(
        {
            "request_id": request_id,
            "endpoint": "dispute",
            "refund_id": req.refund_id,
            "llm_output": llm_output,
            "status": "accepted",
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": total_tokens,
        }
    )

    log.info("enrich.dispute.done", request_id=request_id)

    return DisputeSummaryResponse(
        request_id=request_id,
        summary=llm_output["summary"],
        risk_level=llm_output["risk_level"],
        key_factors=llm_output["key_factors"],
        confidence=llm_output["confidence"],
        source_doc_ids=llm_output["source_doc_ids"],
    )


# ------------------------------------------------------------------
# POST /enrich/catalog
# ------------------------------------------------------------------
@router.post("/catalog", response_model=CatalogEnrichResponse)
async def enrich_catalog(req: CatalogEnrichRequest) -> CatalogEnrichResponse:
    request_id = str(uuid4())
    log.info(
        "enrich.catalog.start",
        request_id=request_id,
        product_id=req.product_id,
    )

    # 1. Retrieve reference docs
    ref_docs = await pgvector.retrieve_similar_docs(
        req.raw_description, top_k=3, doc_type="guideline"
    )

    # 2. Call LLM stub
    llm_output = await llm.enrich_catalog(
        req.raw_description, req.existing_metadata, ref_docs
    )

    # 3. Track tokens
    prompt_tokens = llm_output.pop("prompt_tokens", 0)
    completion_tokens = llm_output.pop("completion_tokens", 0)
    total_tokens = llm_output.pop("total_tokens", 0)
    log.info(
        "enrich.catalog.tokens",
        request_id=request_id,
        prompt_tokens=prompt_tokens,
        completion_tokens=completion_tokens,
        total_tokens=total_tokens,
    )

    # 4. Validate
    known_doc_ids = [d["doc_id"] for d in ref_docs]
    validation = validate_enrichment_output(
        llm_output,
        required_fields=VALIDATION_RULES["required_fields_catalog"],
        known_doc_ids=known_doc_ids,
    )
    validation_status = "accepted" if validation["is_valid"] else "failed"

    # 5. Store decision
    await postgres.insert_llm_decision(
        {
            "request_id": request_id,
            "endpoint": "catalog",
            "product_id": req.product_id,
            "llm_output": llm_output,
            "validation": validation,
            "status": validation_status,
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": total_tokens,
        }
    )

    log.info(
        "enrich.catalog.done",
        request_id=request_id,
        validation_status=validation_status,
    )

    return CatalogEnrichResponse(
        request_id=request_id,
        enhanced_description=llm_output.get("enhanced_description", ""),
        extracted_attributes=llm_output.get("extracted_attributes", {}),
        confidence=llm_output.get("confidence", 0.0),
        source_doc_ids=llm_output.get("source_doc_ids", []),
        validation_status=validation_status,
    )
