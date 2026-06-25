"""NorthWind LLM Enrichment DAG — Module 3 Clip 4.

Static transform tasks (extract_batch, transform, enrich_via_fastapi)
feed a dynamic branch (validation_branch) that routes each enriched
record to either `write_trusted` or `write_quarantine`. The
enrich_via_fastapi task prints a stable `key=value` line per field so
the FastAPI admin `/admin/airflow-task-log` endpoint can extract:
batch_id, request_id, validation_result, output_row_id.

DAG topology:

    extract_batch  →  transform  →  enrich_via_fastapi  →  validation_branch
                                                                    │
                                          ┌─────────────────────────┴─────────────────────────┐
                                          ▼                                                   ▼
                                  write_trusted                                       write_quarantine
"""
from __future__ import annotations

import json
import logging
import os
import uuid
from datetime import datetime, timezone

import httpx

from airflow.decorators import dag, task
from airflow.operators.python import get_current_context

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
FASTAPI_URL = os.environ.get("NORTHWIND_API_URL", "http://host.docker.internal:8000")
HTTP_TIMEOUT = 30.0

log = logging.getLogger(__name__)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


@dag(
    dag_id="northwind_llm_enrichment",
    schedule=None,
    catchup=False,
    start_date=datetime(2024, 1, 1),
    tags=["northwind", "llm", "enrichment", "module3"],
    description=(
        "Static transform tasks feeding a dynamic validation branch — "
        "routes accepted records to trusted, rejected ones to quarantine."
    ),
)
def northwind_llm_enrichment_dag():
    """Build the DAG using TaskFlow decorators."""

    @task
    def extract_batch(batch_id: str = "BATCH-2024-001",
                      feedback_ids: list[int] | None = None) -> dict:
        """Read one feedback record from raw.feedback for the batch."""
        ctx = get_current_context()
        conf = (ctx.get("dag_run").conf if ctx.get("dag_run") else {}) or {}
        batch_id = conf.get("batch_id", batch_id)
        feedback_ids = conf.get("feedback_ids", feedback_ids or [1, 99])
        log.info("extract_batch batch_id=%s feedback_ids=%s", batch_id, feedback_ids)
        # In the demo, the FastAPI service already holds the raw rows in
        # DuckDB; we forward just the ids and let enrich_via_fastapi do
        # the join.
        return {"batch_id": batch_id, "feedback_ids": feedback_ids}

    @task
    def transform(record: dict) -> dict:
        """Deterministic normalization step (no LLM call)."""
        normalized = {
            "batch_id": record["batch_id"],
            "feedback_ids": [int(i) for i in record["feedback_ids"]],
            "normalized_at": _now(),
        }
        log.info("transform normalized=%s", json.dumps(normalized))
        return normalized

    @task
    def enrich_via_fastapi(record: dict) -> dict:
        """Call the FastAPI /enrich/feedback endpoint for each record.

        Logs `key=value` lines for: batch_id, request_id,
        validation_result, output_row_id — so the admin task-log
        endpoint can extract the four outline-named fields.

        If the triggering conf includes `feedback_texts` (a {id: text}
        map), use those texts instead of the default placeholder. This
        lets Module 4 trigger a deterministically mixed batch so both
        downstream branches (write_trusted + write_quarantine) reach
        state=success in a single Airflow run. Module 3 omits the
        override and keeps its existing all-quarantine behavior.
        """
        ctx = get_current_context()
        conf = (ctx.get("dag_run").conf if ctx.get("dag_run") else {}) or {}
        text_override = conf.get("feedback_texts", {}) or {}
        batch_id = record["batch_id"]
        enriched: list[dict] = []
        with httpx.Client(timeout=HTTP_TIMEOUT) as client:
            for fid in record["feedback_ids"]:
                feedback_text = text_override.get(str(fid)) or text_override.get(fid) \
                    or f"feedback record id={fid}"
                payload = {"feedback_id": str(fid),
                           "feedback_text": feedback_text}
                try:
                    resp = client.post(f"{FASTAPI_URL}/enrich/feedback",
                                       json=payload)
                    body = resp.json() if resp.status_code < 500 else {}
                except Exception as exc:  # noqa: BLE001
                    log.warning("enrich_via_fastapi http error: %s", exc)
                    body = {}
                request_id = body.get("request_id", f"req_{uuid.uuid4().hex[:12]}")
                validation_status = body.get("validation_status", "rejected")
                # The trusted/quarantine row id is set later by the
                # write_* tasks; for the log parser we surface a stable
                # placeholder derived from the request_id.
                output_row_id = f"row_{request_id[-8:]}"
                # Structured log lines for the parser.
                log.info("batch_id=%s", batch_id)
                log.info("request_id=%s", request_id)
                log.info("validation_result=%s", validation_status)
                log.info("output_row_id=%s", output_row_id)
                enriched.append({
                    "feedback_id": fid,
                    "request_id": request_id,
                    "validation_status": validation_status,
                    "output_row_id": output_row_id,
                    "batch_id": batch_id,
                })
        return {"batch_id": batch_id, "records": enriched}

    @task.branch
    def validation_branch(enriched: dict) -> list[str]:
        """Dynamic branch — pick downstream tasks based on validation result."""
        records = enriched.get("records", [])
        any_accepted = any(r.get("validation_status") == "accepted" for r in records)
        any_rejected = any(r.get("validation_status") != "accepted" for r in records)
        downstream: list[str] = []
        if any_accepted:
            downstream.append("write_trusted")
        if any_rejected:
            downstream.append("write_quarantine")
        if not downstream:
            downstream.append("write_trusted")
        log.info("validation_branch decision=%s", downstream)
        return downstream

    @task
    def write_trusted(enriched: dict) -> str:
        """Confirm the accepted records reached trusted.feedback_enriched."""
        accepted = [r for r in enriched.get("records", [])
                    if r.get("validation_status") == "accepted"]
        log.info("write_trusted batch_id=%s accepted_count=%d",
                 enriched.get("batch_id"), len(accepted))
        return f"trusted_rows={len(accepted)}"

    @task(trigger_rule="none_failed_min_one_success")
    def write_quarantine(enriched: dict) -> str:
        """Confirm the rejected records reached quarantine.llm_outputs."""
        rejected = [r for r in enriched.get("records", [])
                    if r.get("validation_status") != "accepted"]
        log.info("write_quarantine batch_id=%s quarantined_count=%d",
                 enriched.get("batch_id"), len(rejected))
        return f"quarantine_rows={len(rejected)}"

    # ── Wire up the static chain and the dynamic branch ──────────────
    batch = extract_batch()
    normalized = transform(batch)
    enriched = enrich_via_fastapi(normalized)
    branch = validation_branch(enriched)
    branch >> [write_trusted(enriched), write_quarantine(enriched)]


dag_instance = northwind_llm_enrichment_dag()
