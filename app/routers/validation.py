"""Validation router for NorthWind Markets.

Prefix: /validate

Endpoints:
    POST /validate/output       - Validate raw LLM output JSON
    GET  /validate/rules        - Return current validation configuration
    POST /validate/batch-report - Return validation summary for a batch
"""
from __future__ import annotations

from typing import Any

import structlog
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.db import postgres
from app.models.schemas import ValidationResult
from app.validators.output_validator import (
    VALIDATION_RULES,
    validate_enrichment_output,
)

log = structlog.get_logger(__name__)

router = APIRouter(prefix="/validate", tags=["validation"])


# ------------------------------------------------------------------
# Request models
# ------------------------------------------------------------------

class ValidateOutputRequest(BaseModel):
    output: dict[str, Any]
    required_fields: list[str] | None = None
    known_doc_ids: list[str | int] | None = None


class BatchReportRequest(BaseModel):
    batch_id: str


class BatchValidationSummary(BaseModel):
    batch_id: str
    total: int
    passed: int
    failed: int
    error_breakdown: dict[str, int] = Field(default_factory=dict)
    details: list[dict[str, Any]] = Field(default_factory=list)


# ------------------------------------------------------------------
# POST /validate/output
# ------------------------------------------------------------------
@router.post("/output", response_model=ValidationResult)
async def validate_output(req: ValidateOutputRequest) -> ValidationResult:
    log.info("validate.output.start", fields=list(req.output.keys()))

    result = validate_enrichment_output(
        req.output,
        required_fields=req.required_fields,
        known_doc_ids=req.known_doc_ids,
    )

    log.info(
        "validate.output.done",
        is_valid=result["is_valid"],
        num_errors=len(result["errors"]),
    )

    return ValidationResult(
        is_valid=result["is_valid"],
        checks=result["checks"],
        errors=result["errors"],
    )


# ------------------------------------------------------------------
# GET /validate/rules
# ------------------------------------------------------------------
@router.get("/rules")
async def get_validation_rules() -> dict[str, Any]:
    log.info("validate.rules.get")
    return VALIDATION_RULES


# ------------------------------------------------------------------
# POST /validate/batch-report
# ------------------------------------------------------------------
@router.post("/batch-report", response_model=BatchValidationSummary)
async def batch_report(req: BatchReportRequest) -> BatchValidationSummary:
    log.info("validate.batch_report.start", batch_id=req.batch_id)

    # Retrieve the pipeline run from PostgreSQL
    run_data = await postgres.get_pipeline_run(req.batch_id)
    if run_data is None:
        raise HTTPException(
            status_code=404,
            detail=f"No batch result found for batch_id {req.batch_id}",
        )
    # The batch_result summary may be embedded in the pipeline run record
    batch_data = run_data.get("batch_result", run_data)

    # Also pull LLM decisions for this batch from PG to build per-item detail
    all_decisions = await postgres.get_llm_decisions(limit=500)
    batch_decisions = [
        d for d in all_decisions if d.get("batch_id") == req.batch_id
    ]

    total = batch_data.get("total", 0)
    passed = batch_data.get("accepted", 0)
    failed = batch_data.get("rejected", 0) + batch_data.get("quarantined", 0)

    # Build error breakdown: count how often each validation error appears
    error_breakdown: dict[str, int] = {}
    details: list[dict[str, Any]] = []
    for decision in batch_decisions:
        validation = decision.get("validation", {})
        errors = validation.get("errors", [])
        for err in errors:
            error_breakdown[err] = error_breakdown.get(err, 0) + 1
        details.append(
            {
                "request_id": decision.get("request_id"),
                "feedback_id": decision.get("feedback_id"),
                "status": decision.get("status"),
                "errors": errors,
            }
        )

    log.info(
        "validate.batch_report.done",
        batch_id=req.batch_id,
        total=total,
        passed=passed,
        failed=failed,
    )

    return BatchValidationSummary(
        batch_id=req.batch_id,
        total=total,
        passed=passed,
        failed=failed,
        error_breakdown=error_breakdown,
        details=details,
    )
