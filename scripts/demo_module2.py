#!/usr/bin/env python3
"""Automated Module 2 demo runner.

Walks the same 6 steps as module2/README.md in order, piping each curl
response through scripts/fmt.py with the right --type, --title, and --why
so the on-screen output matches the README. Used by the author to
double-check the demo end-to-end before recording.
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
PAYLOAD_HIGH = REPO_ROOT / "data" / "payloads" / "agent_triage.json"
PAYLOAD_LOW = REPO_ROOT / "data" / "payloads" / "agent_triage_low.json"
INCIDENT_HIGH = "INC-2024-FIN-001"
INCIDENT_LOW = "INC-2024-FIN-003"


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
    print("Module 2 demo: LangGraph agent triage with PostgreSQL and API tools\n")

    health = http_get("/health")
    if not health or health.get("status") != "healthy":
        print("Server not healthy. Start with: ./scripts/module2-demo-reset.sh")
        sys.exit(1)
    print("[ok] Server healthy\n")

    # Step 1 — LangGraph topology
    graph = http_get("/agent/graph")
    show(
        graph, "mermaid",
        "LangGraph topology (compiled, not hand-drawn)",
        "The Mermaid source comes from compiled.get_graph().draw_mermaid()",
    )
    time.sleep(1)

    # Step 2 — Run triage on high-severity incident
    triage_high = http_post("/agent/triage", PAYLOAD_HIGH)
    show(
        triage_high, "triage",
        f"Agent state — {INCIDENT_HIGH} (merchant_revenue_total)",
        "Structured agent state JSON, not free-form scrolling logs",
    )
    time.sleep(1)

    # Step 2b — Active path on Mermaid (post-run)
    graph_active = http_get(f"/agent/graph?incident_id={INCIDENT_HIGH}")
    show(
        graph_active, "mermaid",
        "LangGraph topology with active path highlighted",
        "Mermaid classDef styles the nodes that executed during the run",
    )
    time.sleep(1)

    # Step 3 — agent_tool_calls receipts in Postgres
    tool_calls = http_get(f"/admin/agent-tool-calls?incident_id={INCIDENT_HIGH}")
    show(
        tool_calls, "tool-calls",
        "agent_tool_calls receipts (PostgreSQL)",
        "Every node call: tool_name, input_hash, output_status, timestamp",
    )
    time.sleep(1)

    # Step 4 — agent_decisions (approval gate)
    decisions = http_get("/admin/agent-decisions?limit=1")
    show(
        decisions, "agent-decisions",
        "agent_decisions (latest)",
        "Approval gate writes review_required — no automatic production write",
    )
    time.sleep(1)

    # Step 5 — Conditional edge on low-severity incident
    triage_low = http_post("/agent/triage", PAYLOAD_LOW)
    show(
        triage_low, "triage",
        f"Agent state — {INCIDENT_LOW} (low-severity branch)",
        "Conditional edge: low severity ⇒ auto_log, not approval_gate",
    )

    print("Demo complete. See module2/preflight_log.txt for the captured log.")


if __name__ == "__main__":
    main()
