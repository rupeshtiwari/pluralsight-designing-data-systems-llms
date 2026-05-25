"""
NorthWind Markets — LLM Enrichment Pipeline DAG

This DAG demonstrates a *dynamic* pipeline where an LLM enriches raw customer
feedback records.  It contrasts with the fully-static reconciliation DAG to
illustrate Module 3 concepts around non-deterministic data transformations.

Flow:
  check_source_data -> extract_batch -> call_llm_enrichment -> validate_outputs
    -> route_accepted
        ├─ (accepted) -> write_trusted   -> log_pipeline_run
        └─ (rejected) -> write_quarantine -> log_pipeline_run
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timedelta

import httpx
from airflow import DAG
from airflow.operators.python import BranchPythonOperator, PythonOperator

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
API_URL = os.environ.get("NORTHWIND_API_URL", "http://api:8000")
HTTP_TIMEOUT = 120.0  # seconds — LLM calls can be slow

default_args = {
    "owner": "northwind",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 2,
    "retry_delay": timedelta(minutes=5),
}


# ---------------------------------------------------------------------------
# Task callables
# ---------------------------------------------------------------------------
def _check_source_data(**context):
    """Verify that new unprocessed feedback exists in DuckDB raw.feedback."""
    with httpx.Client(base_url=API_URL, timeout=HTTP_TIMEOUT) as client:
        resp = client.get("/data/raw/feedback/pending-count")
        resp.raise_for_status()
        count = resp.json().get("count", 0)

    if count == 0:
        raise ValueError("No new feedback records to process — skipping run.")

    context["ti"].xcom_push(key="pending_count", value=count)
    return count


def _extract_batch(**context):
    """Pull unprocessed feedback records from the raw layer."""
    with httpx.Client(base_url=API_URL, timeout=HTTP_TIMEOUT) as client:
        resp = client.post("/data/raw/feedback/extract-batch", json={"limit": 500})
        resp.raise_for_status()
        batch = resp.json()

    record_ids = [r["id"] for r in batch.get("records", [])]
    context["ti"].xcom_push(key="batch_record_ids", value=record_ids)
    context["ti"].xcom_push(key="batch_size", value=len(record_ids))
    return len(record_ids)


def _call_llm_enrichment(**context):
    """Send the extracted batch to the FastAPI /pipeline/batch-enrich endpoint.

    The API orchestrates the LLM calls (or stub responses when LLM_STUB_MODE
    is true) and returns enriched records with sentiment, categories, and
    extracted entities.
    """
    record_ids = context["ti"].xcom_pull(
        task_ids="extract_batch", key="batch_record_ids"
    )
    with httpx.Client(base_url=API_URL, timeout=HTTP_TIMEOUT) as client:
        resp = client.post(
            "/pipeline/batch-enrich",
            json={"record_ids": record_ids},
        )
        resp.raise_for_status()
        enriched = resp.json()

    context["ti"].xcom_push(key="enriched_records", value=enriched.get("records", []))
    return len(enriched.get("records", []))


def _validate_outputs(**context):
    """Call the FastAPI /validate/batch-report endpoint.

    Returns a validation report splitting records into accepted vs. rejected
    (quarantine) based on schema conformance, hallucination checks, and
    business-rule guards.
    """
    enriched = context["ti"].xcom_pull(
        task_ids="call_llm_enrichment", key="enriched_records"
    )
    with httpx.Client(base_url=API_URL, timeout=HTTP_TIMEOUT) as client:
        resp = client.post(
            "/validate/batch-report",
            json={"records": enriched},
        )
        resp.raise_for_status()
        report = resp.json()

    context["ti"].xcom_push(key="accepted_ids", value=report.get("accepted_ids", []))
    context["ti"].xcom_push(key="rejected_ids", value=report.get("rejected_ids", []))
    context["ti"].xcom_push(key="validation_report", value=report)
    return report


def _route_accepted(**context):
    """Branch: if there are accepted records go to write_trusted, otherwise
    only quarantine the rejected ones.  Both paths converge at log_pipeline_run.
    """
    accepted = context["ti"].xcom_pull(
        task_ids="validate_outputs", key="accepted_ids"
    ) or []
    rejected = context["ti"].xcom_pull(
        task_ids="validate_outputs", key="rejected_ids"
    ) or []

    downstream = []
    if accepted:
        downstream.append("write_trusted")
    if rejected:
        downstream.append("write_quarantine")

    # Guarantee at least one branch runs so logging always executes.
    if not downstream:
        downstream.append("write_trusted")

    return downstream


def _write_trusted(**context):
    """Persist accepted (validated) enriched records to the trusted layer."""
    accepted_ids = context["ti"].xcom_pull(
        task_ids="validate_outputs", key="accepted_ids"
    ) or []
    enriched = context["ti"].xcom_pull(
        task_ids="call_llm_enrichment", key="enriched_records"
    ) or []

    trusted_records = [r for r in enriched if r.get("id") in accepted_ids]

    with httpx.Client(base_url=API_URL, timeout=HTTP_TIMEOUT) as client:
        resp = client.post(
            "/data/trusted/feedback/write",
            json={"records": trusted_records},
        )
        resp.raise_for_status()

    return len(trusted_records)


def _write_quarantine(**context):
    """Move rejected records to quarantine with rejection reasons attached."""
    rejected_ids = context["ti"].xcom_pull(
        task_ids="validate_outputs", key="rejected_ids"
    ) or []
    report = context["ti"].xcom_pull(
        task_ids="validate_outputs", key="validation_report"
    ) or {}

    with httpx.Client(base_url=API_URL, timeout=HTTP_TIMEOUT) as client:
        resp = client.post(
            "/data/quarantine/feedback/write",
            json={
                "record_ids": rejected_ids,
                "reasons": report.get("rejection_reasons", {}),
            },
        )
        resp.raise_for_status()

    return len(rejected_ids)


def _log_pipeline_run(**context):
    """Write a summary row to PostgreSQL pipeline_runs for observability."""
    report = context["ti"].xcom_pull(
        task_ids="validate_outputs", key="validation_report"
    ) or {}
    batch_size = context["ti"].xcom_pull(
        task_ids="extract_batch", key="batch_size"
    ) or 0

    summary = {
        "dag_id": "northwind_llm_enrichment",
        "run_id": context["run_id"],
        "batch_size": batch_size,
        "accepted": len(report.get("accepted_ids", [])),
        "rejected": len(report.get("rejected_ids", [])),
        "execution_date": str(context["execution_date"]),
    }

    with httpx.Client(base_url=API_URL, timeout=HTTP_TIMEOUT) as client:
        resp = client.post("/pipeline/log-run", json=summary)
        resp.raise_for_status()

    return summary


# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------
with DAG(
    dag_id="northwind_llm_enrichment",
    default_args=default_args,
    description="Enrich NorthWind customer feedback via LLM, validate, and route to trusted/quarantine layers.",
    schedule="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["northwind", "llm", "enrichment", "module3"],
) as dag:

    check_source_data = PythonOperator(
        task_id="check_source_data",
        python_callable=_check_source_data,
    )

    extract_batch = PythonOperator(
        task_id="extract_batch",
        python_callable=_extract_batch,
    )

    call_llm_enrichment = PythonOperator(
        task_id="call_llm_enrichment",
        python_callable=_call_llm_enrichment,
    )

    validate_outputs = PythonOperator(
        task_id="validate_outputs",
        python_callable=_validate_outputs,
    )

    route_accepted = BranchPythonOperator(
        task_id="route_accepted",
        python_callable=_route_accepted,
    )

    write_trusted = PythonOperator(
        task_id="write_trusted",
        python_callable=_write_trusted,
    )

    write_quarantine = PythonOperator(
        task_id="write_quarantine",
        python_callable=_write_quarantine,
    )

    log_pipeline_run = PythonOperator(
        task_id="log_pipeline_run",
        python_callable=_log_pipeline_run,
        trigger_rule="none_failed_min_one_success",
    )

    # ── Task dependencies ─────────────────────────────────────────────────
    # Linear chain through validation, then branch into trusted / quarantine,
    # both converging on the logging task.
    (
        check_source_data
        >> extract_batch
        >> call_llm_enrichment
        >> validate_outputs
        >> route_accepted
    )
    route_accepted >> write_trusted >> log_pipeline_run
    route_accepted >> write_quarantine >> log_pipeline_run
