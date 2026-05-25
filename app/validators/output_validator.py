from __future__ import annotations

from typing import Any

import structlog

from app.config import ALLOWED_CATEGORIES, ALLOWED_SEVERITIES, CONFIDENCE_THRESHOLD
from app.db import duckdb_client
from app.models.schemas import ValidationResult

logger = structlog.get_logger(__name__)

VALIDATION_RULES: dict[str, Any] = {
    "confidence_threshold": CONFIDENCE_THRESHOLD,
    "allowed_categories": ALLOWED_CATEGORIES,
    "allowed_severities": ALLOWED_SEVERITIES,
    "required_fields_feedback": ["category", "summary", "confidence", "source_doc_ids"],
    "required_fields_catalog": [
        "enhanced_description",
        "extracted_attributes",
        "confidence",
        "source_doc_ids",
    ],
    "max_summary_length": 500,
    "min_source_docs": 1,
}


def validate_schema(output: dict, required_fields: list[str]) -> tuple[bool, str]:
    missing = [f for f in required_fields if f not in output or output[f] is None]
    if missing:
        return False, f"Missing required fields: {', '.join(missing)}"
    return True, "Schema valid"


def validate_grounding(
    output: dict,
    source_doc_ids: list[int],
    available_docs: list[int],
) -> tuple[bool, str]:
    if not source_doc_ids:
        return False, "No source documents referenced"
    invalid = [doc_id for doc_id in source_doc_ids if doc_id not in available_docs]
    if invalid:
        return False, f"Invalid source doc IDs: {invalid}"
    return True, "Grounding valid"


def validate_confidence(output: dict, threshold: float | None = None) -> tuple[bool, str]:
    if threshold is None:
        threshold = CONFIDENCE_THRESHOLD
    confidence = output.get("confidence", 0.0)
    if not isinstance(confidence, (int, float)):
        return False, f"Confidence is not numeric: {confidence}"
    if confidence < threshold:
        return False, f"Confidence {confidence} below threshold {threshold}"
    return True, f"Confidence {confidence} meets threshold"


def validate_category(output: dict, allowed_values: list[str] | None = None) -> tuple[bool, str]:
    if allowed_values is None:
        allowed_values = ALLOWED_CATEGORIES
    category = output.get("category", "")
    if category not in allowed_values:
        return False, f"Category '{category}' not in allowed values: {allowed_values}"
    return True, f"Category '{category}' is valid"


def validate_severity(output: dict) -> tuple[bool, str]:
    sev = output.get("severity")
    if sev is None:
        return True, "No severity field to validate"
    if sev not in ALLOWED_SEVERITIES:
        return False, f"Severity '{sev}' not in allowed list"
    return True, f"Severity '{sev}' is valid"


def validate_referential_integrity(output: dict) -> tuple[bool, str]:
    errors = []

    customer_id = output.get("customer_id")
    if customer_id is not None:
        if not duckdb_client.customer_exists(customer_id):
            errors.append(f"customer_id {customer_id} not found in database")

    product_id = output.get("product_id")
    if product_id is not None:
        if not duckdb_client.product_exists(product_id):
            errors.append(f"product_id {product_id} not found in database")

    if errors:
        return False, "; ".join(errors)
    return True, "Referential integrity valid"


def validate_all(output: dict, context: dict) -> ValidationResult:
    checks: dict[str, str] = {}
    errors: list[str] = []

    required_fields = context.get("required_fields", ["category", "summary", "confidence"])
    ok, msg = validate_schema(output, required_fields)
    checks["schema"] = msg
    if not ok:
        errors.append(msg)

    source_doc_ids = output.get("source_doc_ids", [])
    available_doc_ids = context.get("available_doc_ids", [])
    if available_doc_ids:
        ok, msg = validate_grounding(output, source_doc_ids, available_doc_ids)
        checks["grounding"] = msg
        if not ok:
            errors.append(msg)

    threshold = context.get("confidence_threshold", CONFIDENCE_THRESHOLD)
    ok, msg = validate_confidence(output, threshold)
    checks["confidence"] = msg
    if not ok:
        errors.append(msg)

    allowed_categories = context.get("allowed_categories")
    if allowed_categories or "category" in output:
        ok, msg = validate_category(output, allowed_categories)
        checks["category"] = msg
        if not ok:
            errors.append(msg)

    if "severity" in output:
        ok, msg = validate_severity(output)
        checks["severity"] = msg
        if not ok:
            errors.append(msg)

    if context.get("check_referential_integrity", False):
        ok, msg = validate_referential_integrity(output)
        checks["referential_integrity"] = msg
        if not ok:
            errors.append(msg)

    is_valid = len(errors) == 0
    result = ValidationResult(is_valid=is_valid, checks=checks, errors=errors)

    logger.info("validation_complete", is_valid=is_valid, error_count=len(errors))
    return result


def validate_enrichment_output(
    output: dict[str, Any],
    *,
    required_fields: list[str] | None = None,
    known_doc_ids: list[int] | None = None,
) -> dict[str, Any]:
    if required_fields is None:
        required_fields = VALIDATION_RULES["required_fields_feedback"]
    if known_doc_ids is None:
        known_doc_ids = list(range(1, 100))

    checks: dict[str, Any] = {}
    errors: list[str] = []

    for name, result in [
        ("required_fields", validate_schema(output, required_fields)),
        ("confidence", validate_confidence(output)),
        ("category", validate_category(output)),
        ("severity", validate_severity(output)),
        ("grounding", validate_grounding(output, output.get("source_doc_ids", []), known_doc_ids)),
    ]:
        passed, detail = result
        checks[name] = {"passed": passed, "detail": detail}
        if not passed:
            errors.append(detail)

    is_valid = len(errors) == 0
    logger.info("validate_enrichment_output", is_valid=is_valid, num_errors=len(errors))
    return {"is_valid": is_valid, "checks": checks, "errors": errors}
