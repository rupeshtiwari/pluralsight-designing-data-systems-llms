#!/usr/bin/env python3
import json
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
API_URL = "http://localhost:8000"


def run_curl(endpoint: str, payload: str | None = None, method: str = "GET") -> dict:
    cmd = ["curl", "-sf"]
    if method == "POST":
        cmd.extend(["-X", "POST"])
        if payload:
            if payload.startswith("{") or payload.startswith("["):
                cmd.extend(["-H", "Content-Type: application/json", "-d", payload])
            else:
                cmd.extend(["-H", "Content-Type: application/json", "-d", f"@{payload}"])
    cmd.append(f"{API_URL}{endpoint}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error calling {endpoint}: {result.stderr}", file=sys.stderr)
        return {}
    return json.loads(result.stdout) if result.stdout else {}


def fmt(data: dict | list, fmt_type: str) -> None:
    subprocess.run(
        [sys.executable, str(REPO_ROOT / "scripts" / "fmt.py"), "--type", fmt_type],
        input=json.dumps(data),
        text=True,
    )


def main():
    print("Module 3 Demo: Triggering and monitoring an Airflow enrichment pipeline\n")

    health = run_curl("/health")
    if not health:
        print("Server not running. Start with: module3/scripts/demo_up.sh")
        sys.exit(1)
    print("[ok] Server healthy\n")

    run_curl("/admin/reset-metrics", method="POST")
    run_curl("/admin/seed-knowledge-base", method="POST")

    # Step 1
    print("=" * 60)
    print("Step 1: Trigger Airflow DAG")
    print("=" * 60)
    trigger_payload = json.dumps({
        "batch_id": "BATCH-20240318-001",
        "source": "data/payloads/batch_feedback.json",
    })
    result = run_curl("/pipeline/trigger", payload=trigger_payload, method="POST")
    fmt(result, "raw")
    print()
    time.sleep(1)

    # Step 2
    print("=" * 60)
    print("Step 2: Pipeline run results")
    print("=" * 60)
    runs = run_curl("/pipeline/runs")
    fmt(runs, "raw")
    print()
    time.sleep(1)

    # Step 3
    print("=" * 60)
    print("Step 3: Batch enrichment details")
    print("=" * 60)
    batch = run_curl("/pipeline/run/BATCH-20240318-001")
    fmt(batch, "batch")
    print()
    time.sleep(1)

    # Step 4
    print("=" * 60)
    print("Step 4: DuckDB trusted output and quarantine")
    print("=" * 60)
    if subprocess.run(["which", "duckdb"], capture_output=True).returncode == 0:
        db_path = str(REPO_ROOT / "data" / "northwind.duckdb")
        print("Trusted table:")
        subprocess.run(["duckdb", db_path,
            "SELECT request_id, category, confidence, validation_status "
            "FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 5"])
        print("\nQuarantine table:")
        subprocess.run(["duckdb", db_path,
            "SELECT request_id, validation_errors "
            "FROM quarantine.llm_outputs ORDER BY quarantined_at DESC LIMIT 5"])
    else:
        print("duckdb CLI not available")
    print()
    print("Demo complete.")


if __name__ == "__main__":
    main()
