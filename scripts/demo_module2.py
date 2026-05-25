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
    subprocess.run(
        [sys.executable, str(REPO_ROOT / "scripts" / "fmt.py"), "--type", fmt_type],
        input=json.dumps(data),
        text=True,
    )


def main():
    print("Module 2 Demo: LangGraph agent triage with PostgreSQL and API tools\n")

    health = run_curl("/health")
    if not health:
        print("Server not running. Start with: module2/scripts/demo_up.sh")
        sys.exit(1)
    print("[ok] Server healthy\n")

    run_curl("/admin/reset-metrics", method="POST")
    run_curl("/admin/seed-knowledge-base", method="POST")

    # Step 1
    print("=" * 60)
    print("Step 1: LangGraph state diagram")
    print("=" * 60)
    graph = run_curl("/agent/graph")
    fmt(graph, "raw")
    print()
    time.sleep(1)

    # Step 2
    print("=" * 60)
    print("Step 2: Run triage workflow")
    print("=" * 60)
    payload = str(REPO_ROOT / "data" / "payloads" / "anomaly_triage.json")
    result = run_curl("/agent/triage", payload_file=payload, method="POST")
    fmt(result, "triage")
    print()
    time.sleep(1)

    # Step 3
    print("=" * 60)
    print("Step 3: PostgreSQL agent_tool_calls")
    print("=" * 60)
    subprocess.run([
        "docker", "exec", "northwind-postgres", "psql", "-U", "northwind", "-c",
        "SELECT tool_name, output_status, created_at "
        "FROM agent_tool_calls WHERE incident_id='INC-3001' ORDER BY created_at",
    ])
    print()
    time.sleep(1)

    # Step 4
    print("=" * 60)
    print("Step 4: PostgreSQL agent_decisions (approval gate)")
    print("=" * 60)
    subprocess.run([
        "docker", "exec", "northwind-postgres", "psql", "-U", "northwind", "-c",
        "SELECT incident_id, severity, recommended_action, review_required "
        "FROM agent_decisions WHERE incident_id='INC-3001'",
    ])
    print()
    print("Demo complete.")


if __name__ == "__main__":
    main()
