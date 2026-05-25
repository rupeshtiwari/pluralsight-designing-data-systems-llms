"""
NorthWind Markets — Static Order Reconciliation DAG

A fully deterministic pipeline with no LLM calls.  Used in Module 3, Clip 2
as a contrast to the dynamic LLM enrichment DAG.

Every task is a pure function of its inputs: same data in, same data out.
This makes the pipeline trivially testable, idempotent, and reproducible —
properties that become harder to guarantee once LLM transforms enter the
picture.

Flow:
  extract_orders -> join_refunds -> calculate_balances
    -> write_reconciliation -> notify_complete
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta

import httpx
from airflow import DAG
from airflow.operators.python import PythonOperator

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
API_URL = os.environ.get("NORTHWIND_API_URL", "http://api:8000")
HTTP_TIMEOUT = 60.0

default_args = {
    "owner": "northwind",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "retries": 1,
    "retry_delay": timedelta(minutes=3),
}


# ---------------------------------------------------------------------------
# Task callables
# ---------------------------------------------------------------------------
def _extract_orders(**context):
    """Pull the day's completed orders from the raw layer.

    Deterministic: selects all orders with status='completed' for the
    logical execution date.
    """
    execution_date = str(context["execution_date"].date())

    with httpx.Client(base_url=API_URL, timeout=HTTP_TIMEOUT) as client:
        resp = client.get(
            "/data/raw/orders",
            params={"date": execution_date, "status": "completed"},
        )
        resp.raise_for_status()
        orders = resp.json().get("orders", [])

    context["ti"].xcom_push(key="orders", value=orders)
    return len(orders)


def _join_refunds(**context):
    """Left-join refunds onto extracted orders.

    Pure relational join — no inference, no generation.  The API endpoint
    matches refund records to orders by order_id.
    """
    orders = context["ti"].xcom_pull(task_ids="extract_orders", key="orders") or []
    order_ids = [o["order_id"] for o in orders]

    with httpx.Client(base_url=API_URL, timeout=HTTP_TIMEOUT) as client:
        resp = client.post(
            "/data/raw/refunds/join",
            json={"order_ids": order_ids},
        )
        resp.raise_for_status()
        joined = resp.json().get("joined_records", [])

    context["ti"].xcom_push(key="joined_records", value=joined)
    return len(joined)


def _calculate_balances(**context):
    """Compute net balances: order_total - refund_amount for each record.

    Arithmetic only — completely deterministic.
    """
    joined = (
        context["ti"].xcom_pull(task_ids="join_refunds", key="joined_records") or []
    )

    reconciled = []
    for record in joined:
        order_total = float(record.get("order_total", 0))
        refund_amount = float(record.get("refund_amount", 0))
        reconciled.append(
            {
                "order_id": record["order_id"],
                "customer_id": record.get("customer_id"),
                "order_total": order_total,
                "refund_amount": refund_amount,
                "net_balance": round(order_total - refund_amount, 2),
                "has_refund": refund_amount > 0,
            }
        )

    context["ti"].xcom_push(key="reconciled", value=reconciled)

    total_net = sum(r["net_balance"] for r in reconciled)
    total_refunds = sum(r["refund_amount"] for r in reconciled)
    context["ti"].xcom_push(key="total_net", value=total_net)
    context["ti"].xcom_push(key="total_refunds", value=total_refunds)

    return len(reconciled)


def _write_reconciliation(**context):
    """Persist the reconciled balances to the trusted reconciliation table."""
    reconciled = (
        context["ti"].xcom_pull(task_ids="calculate_balances", key="reconciled") or []
    )
    execution_date = str(context["execution_date"].date())

    with httpx.Client(base_url=API_URL, timeout=HTTP_TIMEOUT) as client:
        resp = client.post(
            "/data/trusted/reconciliation/write",
            json={
                "date": execution_date,
                "records": reconciled,
            },
        )
        resp.raise_for_status()

    return len(reconciled)


def _notify_complete(**context):
    """Log a completion summary to the pipeline_runs table.

    In production this could also send a Slack or email notification.
    """
    execution_date = str(context["execution_date"].date())
    reconciled = (
        context["ti"].xcom_pull(task_ids="calculate_balances", key="reconciled") or []
    )
    total_net = context["ti"].xcom_pull(
        task_ids="calculate_balances", key="total_net"
    ) or 0
    total_refunds = context["ti"].xcom_pull(
        task_ids="calculate_balances", key="total_refunds"
    ) or 0

    summary = {
        "dag_id": "northwind_static_reconciliation",
        "run_id": context["run_id"],
        "execution_date": execution_date,
        "records_processed": len(reconciled),
        "total_net_balance": total_net,
        "total_refunds": total_refunds,
    }

    with httpx.Client(base_url=API_URL, timeout=HTTP_TIMEOUT) as client:
        resp = client.post("/pipeline/log-run", json=summary)
        resp.raise_for_status()

    return summary


# ---------------------------------------------------------------------------
# DAG definition
# ---------------------------------------------------------------------------
with DAG(
    dag_id="northwind_static_reconciliation",
    default_args=default_args,
    description=(
        "Deterministic order-refund reconciliation — no LLM calls.  "
        "Used in Module 3 to contrast with the dynamic enrichment DAG."
    ),
    schedule="@daily",
    start_date=datetime(2024, 1, 1),
    catchup=False,
    tags=["northwind", "static", "reconciliation", "module3"],
) as dag:

    extract_orders = PythonOperator(
        task_id="extract_orders",
        python_callable=_extract_orders,
    )

    join_refunds = PythonOperator(
        task_id="join_refunds",
        python_callable=_join_refunds,
    )

    calculate_balances = PythonOperator(
        task_id="calculate_balances",
        python_callable=_calculate_balances,
    )

    write_reconciliation = PythonOperator(
        task_id="write_reconciliation",
        python_callable=_write_reconciliation,
    )

    notify_complete = PythonOperator(
        task_id="notify_complete",
        python_callable=_notify_complete,
    )

    # ── Task dependencies ─────────────────────────────────────────────────
    # Strictly linear — no branching, no dynamic routing.
    (
        extract_orders
        >> join_refunds
        >> calculate_balances
        >> write_reconciliation
        >> notify_complete
    )
