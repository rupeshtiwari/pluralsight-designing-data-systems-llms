#!/usr/bin/env python3
"""Automated Module 3 demo runner.

Walks the same 6 steps as module3/README.md in order, piping each curl
response through scripts/fmt.py with the right --type, --title, and --why
so the on-screen output matches the README. Used to double-check the
demo end-to-end before recording.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
API_URL = "http://localhost:8000"
FMT = str(REPO_ROOT / "scripts" / "fmt.py")
PAYLOAD = REPO_ROOT / "data" / "payloads" / "airflow_trigger.json"


def http_get(path: str) -> dict | list:
    out = subprocess.run(
        ["curl", "-sf", f"{API_URL}{path}"], capture_output=True, text=True
    )
    if out.returncode != 0:
        print(f"GET {path} failed: {out.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(out.stdout) if out.stdout else {}


def http_post(path: str, payload_file: Path) -> dict:
    out = subprocess.run(
        [
            "curl", "-sf", "-X", "POST",
            "-H", "Content-Type: application/json",
            "-d", f"@{payload_file}",
            f"{API_URL}{path}",
        ],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        print(f"POST {path} failed: {out.stderr}", file=sys.stderr)
        sys.exit(1)
    return json.loads(out.stdout) if out.stdout else {}


def show(data, fmt_type: str, title: str, why: str) -> None:
    subprocess.run(
        [sys.executable, FMT, "--type", fmt_type, "--title", title, "--why", why],
        input=json.dumps(data), text=True,
    )
    print()


def main() -> None:
    print("Module 3 demo: Triggering and monitoring an Airflow enrichment pipeline\n")

    health = http_get("/health")
    if not health or health.get("status") != "healthy":
        print("Server not healthy. Start with: ./scripts/module3-demo-reset.sh")
        sys.exit(1)
    print("[ok] Server healthy\n")

    # Step 1 — DAG topology
    dag = http_get("/admin/airflow-dag")
    show(
        dag, "airflow-dag",
        "northwind_llm_enrichment DAG topology",
        "Three static transform tasks plus one dynamic branch task",
    )
    time.sleep(1)

    # Step 2 — Trigger
    trigger = http_post("/admin/airflow-trigger", PAYLOAD)
    show(
        trigger, "airflow-trigger",
        "Trigger northwind_llm_enrichment for BATCH-2024-001",
        "Returns dag_run_id and the initial queued state",
    )
    time.sleep(1)

    # Step 3 — State transitions
    runs = http_get("/admin/airflow-dag-runs?limit=3")
    show(
        runs, "airflow-dag-runs",
        "DAG run state transitions (last 3 runs)",
        "queued (gray) → running (blue) → success (lime); failed shows pink",
    )
    time.sleep(1)

    # Step 4 — Task log fields — pull the most recent run id
    dag_runs = runs.get("dag_runs", []) if isinstance(runs, dict) else []
    run_id = dag_runs[0].get("dag_run_id", "") if dag_runs else ""
    task_log = http_get(
        f"/admin/airflow-task-log?dag_run_id={run_id}&task_id=enrich_via_fastapi"
    )
    show(
        task_log, "airflow-task-log",
        "Task log fields — enrich_via_fastapi",
        "All four outline-named fields, lifted from the live task log",
    )
    time.sleep(1)

    # Step 5 — Dispositions
    disp = http_get("/admin/disposition-summary?limit=5")
    show(
        disp, "dispositions",
        "Disposition summary (accepted vs quarantined)",
        "A task that succeeds can still produce quarantined records — count both",
    )
    time.sleep(1)

    # Step 6 — Branch decision
    branch = http_get(f"/admin/airflow-branch-decision?dag_run_id={run_id}")
    show(
        branch, "airflow-branch",
        "validation_branch decision for this run",
        "Dynamic branch chose downstream_taken; downstream_skipped did not run",
    )

    print("Demo complete. See module3/preflight_log.txt for the captured log.")


if __name__ == "__main__":
    main()
