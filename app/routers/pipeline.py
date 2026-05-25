"""Pipeline router for NorthWind Markets.

Prefix: /pipeline

Endpoints:
    POST /pipeline/batch-enrich  - Process a batch of feedback items through enrichment
    GET  /pipeline/runs          - List recent pipeline runs
    GET  /pipeline/run/{batch_id} - Get details for a specific pipeline run
    POST /pipeline/trigger       - Simulate triggering an Airflow DAG run
"""
from __future__ import annotations

import datetime as _dt
from typing import Any
from uuid import uuid4

import structlog
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.db import duckdb_client, pgvector, postgres
from app.models.schemas import BatchResult, FeedbackEnrichRequest
from app.services import llm
from app.validators.output_validator import validate_enrichment_output, VALIDATION_RULES

log = structlog.get_logger(__name__)

router = APIRouter(prefix="/pipeline", tags=["pipeline"])


# ------------------------------------------------------------------
# Request / helper models
# ------------------------------------------------------------------

class BatchEnrichRequest(BaseModel):
    items: list[FeedbackEnrichRequest]


class TriggerRequest(BaseModel):
    dag_id: str = "northwind_enrich_dag"
    conf: dict[str, Any] = Field(default_factory=dict)


# ------------------------------------------------------------------
# POST /pipeline/batch-enrich
# ------------------------------------------------------------------
@router.post("/batch-enrich", response_model=BatchResult)
async def batch_enrich(req: BatchEnrichRequest) -> BatchResult:
    batch_id = str(uuid4())
    log.info("pipeline.batch_enrich.start", batch_id=batch_id, total=len(req.items))

    # Create pipeline run record
    run_record = await postgres.insert_pipeline_run(
        {
            "batch_id": batch_id,
            "status": "running",
            "total": len(req.items),
            "accepted": 0,
            "rejected": 0,
            "quarantined": 0,
            "started_at": _dt.datetime.utcnow().isoformat(),
        }
    )

    accepted = 0
    rejected = 0
    quarantined = 0
    details: list[dict[str, Any]] = []
    total_prompt_tokens = 0
    total_completion_tokens = 0
    total_all_tokens = 0

    for item in req.items:
        request_id = str(uuid4())
        log.info(
            "pipeline.batch_enrich.item",
            batch_id=batch_id,
            request_id=request_id,
            feedback_id=item.feedback_id,
        )

        # 1. Retrieve reference docs
        ref_docs = await pgvector.retrieve_similar_docs(
            item.feedback_text, top_k=3, doc_type="policy"
        )

        # 2. Call LLM stub
        llm_output = await llm.classify_feedback(item.feedback_text, ref_docs)

        # Track tokens
        prompt_tokens = llm_output.pop("prompt_tokens", 0)
        completion_tokens = llm_output.pop("completion_tokens", 0)
        item_total_tokens = llm_output.pop("total_tokens", 0)
        total_prompt_tokens += prompt_tokens
        total_completion_tokens += completion_tokens
        total_all_tokens += item_total_tokens

        # 3. Validate
        known_doc_ids = [d["doc_id"] for d in ref_docs]
        validation = validate_enrichment_output(
            llm_output,
            required_fields=VALIDATION_RULES["required_fields_feedback"],
            known_doc_ids=known_doc_ids,
        )

        # 4. Route to trusted or quarantine (DuckDB - synchronous calls)
        if validation["is_valid"]:
            duckdb_client.insert_enriched_feedback(
                {
                    "id": item.feedback_id,
                    "request_id": request_id,
                    "customer_id": item.customer_id,
                    "product_id": item.product_id,
                    "feedback_text": item.feedback_text,
                    "category": llm_output.get("category", "unknown"),
                    "summary": llm_output.get("summary", ""),
                    "confidence": llm_output.get("confidence", 0.0),
                    "source_doc_ids": llm_output.get("source_doc_ids", []),
                    "validation_status": "accepted",
                }
            )
            accepted += 1
            status = "accepted"
        else:
            duckdb_client.insert_quarantine(
                {
                    "id": item.feedback_id,
                    "request_id": request_id,
                    "input_text": item.feedback_text,
                    "raw_output": llm_output,
                    "validation_errors": validation["errors"],
                }
            )
            quarantined += 1
            rejected += 1
            status = "quarantined"

        # 5. Store decision in PG
        await postgres.insert_llm_decision(
            {
                "request_id": request_id,
                "batch_id": batch_id,
                "endpoint": "batch_feedback",
                "feedback_id": item.feedback_id,
                "llm_output": llm_output,
                "validation": validation,
                "status": status,
                "prompt_tokens": prompt_tokens,
                "completion_tokens": completion_tokens,
                "total_tokens": item_total_tokens,
            }
        )

        details.append(
            {
                "request_id": request_id,
                "feedback_id": item.feedback_id,
                "status": status,
                "category": llm_output.get("category", "unknown"),
                "confidence": llm_output.get("confidence", 0.0),
                "errors": validation["errors"],
            }
        )

    # Update pipeline run
    await postgres.update_pipeline_run(
        batch_id,
        {
            "status": "completed",
            "accepted": accepted,
            "rejected": rejected,
            "quarantined": quarantined,
            "completed_at": _dt.datetime.utcnow().isoformat(),
            "total_prompt_tokens": total_prompt_tokens,
            "total_completion_tokens": total_completion_tokens,
            "total_tokens": total_all_tokens,
        },
    )

    # Store batch result summary in PG pipeline run for later retrieval
    batch_result = BatchResult(
        batch_id=batch_id,
        total=len(req.items),
        accepted=accepted,
        rejected=rejected,
        quarantined=quarantined,
        details=details,
    )
    await postgres.update_pipeline_run(
        batch_id,
        {"batch_result": batch_result.model_dump()},
    )

    log.info(
        "pipeline.batch_enrich.done",
        batch_id=batch_id,
        accepted=accepted,
        rejected=rejected,
        quarantined=quarantined,
        total_tokens=total_all_tokens,
    )

    return batch_result


# ------------------------------------------------------------------
# GET /pipeline/runs
# ------------------------------------------------------------------
@router.get("/runs")
async def list_pipeline_runs(limit: int = 50) -> list[dict[str, Any]]:
    log.info("pipeline.runs.list", limit=limit)
    return await postgres.get_pipeline_runs(limit=limit)


# ------------------------------------------------------------------
# GET /pipeline/run/{batch_id}
# ------------------------------------------------------------------
@router.get("/run/{batch_id}")
async def get_pipeline_run(batch_id: str) -> dict[str, Any]:
    log.info("pipeline.run.get", batch_id=batch_id)
    run = await postgres.get_pipeline_run(batch_id)
    if run is None:
        raise HTTPException(status_code=404, detail=f"No pipeline run with batch_id {batch_id}")
    return run


# ------------------------------------------------------------------
# POST /pipeline/trigger
# ------------------------------------------------------------------
@router.post("/trigger")
async def trigger_dag(req: TriggerRequest) -> dict[str, Any]:
    """Simulate triggering an Airflow DAG run."""
    batch_id = str(uuid4())
    log.info(
        "pipeline.trigger",
        batch_id=batch_id,
        dag_id=req.dag_id,
        conf=req.conf,
    )

    run_record = await postgres.insert_pipeline_run(
        {
            "batch_id": batch_id,
            "dag_id": req.dag_id,
            "status": "triggered",
            "conf": req.conf,
            "triggered_at": _dt.datetime.utcnow().isoformat(),
            "total": 0,
            "accepted": 0,
            "rejected": 0,
            "quarantined": 0,
        }
    )

    log.info("pipeline.trigger.done", batch_id=batch_id)

    return {
        "batch_id": batch_id,
        "dag_id": req.dag_id,
        "status": "triggered",
        "message": f"Airflow DAG '{req.dag_id}' triggered successfully.",
        "run_id": run_record["id"],
    }
