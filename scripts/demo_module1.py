#!/usr/bin/env python3
import json
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
API_URL = "http://localhost:8000"


def run_curl(endpoint: str, payload_file: str | None = None, method: str = "GET") -> dict:
    cmd = ["curl", "-sf"]
    if method == "POST":
        cmd.extend(["-X", "POST"])
        if payload_file:
            cmd.extend(["-H", "Content-Type: application/json", "-d", f"@{payload_file}"])
    cmd.append(f"{API_URL}{endpoint}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error calling {endpoint}: {result.stderr}", file=sys.stderr)
        return {}
    return json.loads(result.stdout) if result.stdout else {}


def fmt(data: dict, fmt_type: str) -> None:
    proc = subprocess.run(
        [sys.executable, str(REPO_ROOT / "scripts" / "fmt.py"), "--type", fmt_type],
        input=json.dumps(data),
        text=True,
    )
    if proc.returncode != 0:
        print(json.dumps(data, indent=2))


def main():
    print("Module 1 Demo: Enriching e-commerce feedback with FastAPI, DuckDB, and pgvector\n")

    # Preflight
    health = run_curl("/health")
    if not health:
        print("Server not running. Start with: module1/scripts/demo_up.sh")
        sys.exit(1)
    print("[ok] Server healthy\n")

    # Reset
    run_curl("/admin/reset-metrics", method="POST")
    run_curl("/admin/seed-knowledge-base", method="POST")

    # Step 1
    print("=" * 60)
    print("Step 1: DuckDB raw feedback input")
    print("=" * 60)
    subprocess.run(
        ["duckdb", str(REPO_ROOT / "data" / "northwind.duckdb"),
         "SELECT count(*) as row_count FROM raw.feedback"],
    )
    print()
    time.sleep(1)

    # Step 2
    print("=" * 60)
    print("Step 2: Enrich feedback via FastAPI")
    print("=" * 60)
    payload = str(REPO_ROOT / "data" / "payloads" / "feedback_enrich.json")
    result = run_curl("/enrich/feedback", payload_file=payload, method="POST")
    fmt(result, "feedback")
    print()
    time.sleep(1)

    # Step 3
    print("=" * 60)
    print("Step 3: PostgreSQL llm_decisions")
    print("=" * 60)
    subprocess.run([
        "docker", "exec", "northwind-postgres", "psql", "-U", "northwind", "-c",
        "SELECT request_id, endpoint, category, confidence, validation_status, decision "
        "FROM llm_decisions ORDER BY created_at DESC LIMIT 3",
    ])
    print()
    time.sleep(1)

    # Step 4
    print("=" * 60)
    print("Step 4: DuckDB trusted output")
    print("=" * 60)
    subprocess.run(
        ["duckdb", str(REPO_ROOT / "data" / "northwind.duckdb"),
         "SELECT count(*) as row_count FROM trusted.feedback_enriched"],
    )
    subprocess.run(
        ["duckdb", str(REPO_ROOT / "data" / "northwind.duckdb"),
         "SELECT request_id, category, confidence, validation_status "
         "FROM trusted.feedback_enriched ORDER BY enriched_at DESC LIMIT 3"],
    )
    print()
    print("Demo complete.")


if __name__ == "__main__":
    main()
