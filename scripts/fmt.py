#!/usr/bin/env python3
"""Colored output formatter for Pluralsight course demo curl commands.

Reads JSON from stdin and formats it with ANSI colors using the
Pluralsight brand color palette.  Every demo pipe ends here:

    curl -s ... | python scripts/fmt.py --type feedback
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any

# ---------------------------------------------------------------------------
# Pluralsight brand palette (ANSI true-color sequences)
# ---------------------------------------------------------------------------
PINK = "\033[38;2;255;22;117m"       # Transform Pink  - blocked / unsafe / FAIL
LIME = "\033[38;2;207;255;110m"      # Lime Green      - allowed / safe / PASS / True
LGRN = "\033[38;2;64;255;191m"       # Limited Green   - numbers / tokens / hashes
BLUE = "\033[38;2;42;236;250m"       # Blue            - labels (field names)
ADA  = "\033[38;2;41;130;111m"       # ADA Green       - PII entities / filtered
GRAY = "\033[38;2;191;191;191m"      # Light Gray      - secondary / dim
WHITE = "\033[1;37m"                 # White bold      - section headings
RESET = "\033[0m"
DIM = GRAY  # alias

# ---------------------------------------------------------------------------
# Tiny helpers
# ---------------------------------------------------------------------------

def _heading(text: str) -> str:
    return f"{WHITE}{text}{RESET}"


def _label(text: str) -> str:
    return f"{BLUE}{text}{RESET}"


def _safe(text: str) -> str:
    return f"{LIME}{text}{RESET}"


def _danger(text: str) -> str:
    return f"{PINK}{text}{RESET}"


def _num(value: Any) -> str:
    return f"{LGRN}{value}{RESET}"


def _ada(text: str) -> str:
    return f"{ADA}{text}{RESET}"


def _dim(text: str) -> str:
    return f"{DIM}{text}{RESET}"


def _val(value: Any) -> str:
    """Auto-color a value based on its content."""
    if isinstance(value, bool):
        return _safe(str(value)) if value else _danger(str(value))
    s = str(value)
    sl = s.lower()
    if sl in ("allowed", "safe", "pass", "accepted", "true", "enabled"):
        return _safe(s)
    if sl in ("blocked", "unsafe", "fail", "rejected", "violated", "false",
              "disabled"):
        return _danger(s)
    if isinstance(value, (int, float)):
        return _num(value)
    # Hex-like hashes (32+ hex chars)
    if isinstance(value, str) and len(value) >= 32 and all(
        c in "0123456789abcdef" for c in value.lower()
    ):
        return _num(value)
    return s


def _verdict(passed: bool) -> str:
    if passed:
        return _safe("PASS")
    return _danger("FAIL")


def _tokens(data: dict, *, force_blocked: bool = False) -> str:
    """Render prompt / completion / total tokens on one line."""
    usage = data.get("token_usage") or data.get("usage") or data.get("tokens") or {}
    prompt = usage.get("prompt_tokens", usage.get("prompt", 0))
    completion = usage.get("completion_tokens", usage.get("completion", 0))
    total = usage.get("total_tokens", usage.get("total", prompt + completion))
    if force_blocked or (prompt == 0 and completion == 0 and total == 0):
        return (f"{_label('Tokens')}  "
                f"{_danger('prompt=0')}  "
                f"{_danger('completion=0')}  "
                f"{_danger('total=0')}")
    return (f"{_label('Tokens')}  "
            f"{_num(f'prompt={prompt}')}  "
            f"{_num(f'completion={completion}')}  "
            f"{_num(f'total={total}')}")


def _is_blocked(data: dict) -> bool:
    """Heuristic: is this response blocked by a guardrail?"""
    status = str(data.get("status", "")).lower()
    action = str(data.get("action", "")).lower()
    if status in ("blocked", "rejected", "violated"):
        return True
    if action in ("blocked", "reject"):
        return True
    # Check nested rails
    rails = data.get("rails") or data.get("guardrails") or {}
    if isinstance(rails, dict):
        for v in rails.values():
            if isinstance(v, dict):
                act = str(v.get("action", "")).lower()
                if act in ("blocked", "reject"):
                    return True
            elif isinstance(v, str) and v.lower() in ("blocked", "reject"):
                return True
    return False


def _rails_line(data: dict) -> str | None:
    """Render rail decisions.  Compact when all allow; expanded when any block."""
    rails = data.get("rails") or data.get("guardrails") or {}
    if not isinstance(rails, dict) or not rails:
        return None

    all_allow = True
    names_allow: list[str] = []
    blocked_lines: list[str] = []

    for name, info in rails.items():
        if isinstance(info, dict):
            action = str(info.get("action", "allow")).lower()
        elif isinstance(info, str):
            action = info.lower()
        else:
            action = "allow"

        if action in ("allow", "allowed", "pass"):
            names_allow.append(name)
        else:
            all_allow = False
            detail = ""
            if isinstance(info, dict):
                detail = info.get("detail", info.get("reason", ""))
            blocked_lines.append(
                f"  {_label(name):40s} {_danger(action)}"
                + (f"  {_dim(detail)}" if detail else "")
            )

    if all_allow:
        joined = ", ".join(names_allow)
        return f"{_label('Rails')}  {_safe(f'all allow')} {_dim(f'({joined})')}"

    lines: list[str] = [_heading("Rails")]
    # Show allowed ones compactly first
    if names_allow:
        for n in names_allow:
            lines.append(f"  {_label(n):40s} {_safe('allow')}")
    lines.extend(blocked_lines)
    return "\n".join(lines)


def _kv(key: str, value: Any) -> str:
    """Format a key: value pair."""
    return f"{_label(key)}  {_val(value)}"


def _section(title: str, lines: list[str]) -> str:
    """Section heading + indented lines."""
    parts = [_heading(title)]
    parts.extend(lines)
    return "\n".join(parts)


# ---------------------------------------------------------------------------
# Format: feedback
# ---------------------------------------------------------------------------

def _hi(label: str, value: str) -> str:
    """Highlighted line — ★ marker, blue label, limited-green value."""
    return f"  {PINK}★{RESET} {BLUE}{label}:{RESET} {LGRN}{value}{RESET}"


def _ctx(label: str, value: str) -> str:
    """Context line — dimmed, not narrated."""
    return f"    {GRAY}{label}: {value}{RESET}"


def fmt_feedback(data: dict) -> str:
    lines: list[str] = []
    lines.append(_heading("Feedback Enrichment"))
    lines.append("")

    # ★ highlight the props the author reads aloud; show the rest as context.
    if data.get("category") is not None:
        lines.append(_hi("category", str(data["category"])))
    if data.get("confidence") is not None:
        lines.append(_hi("confidence", str(data["confidence"])))
    if data.get("source_doc_ids") is not None:
        docs = ", ".join(str(d) for d in data["source_doc_ids"])
        lines.append(_hi("source_doc_ids", docs))
    if data.get("validation_status") is not None:
        lines.append(_hi("validation_status", str(data["validation_status"])))
    if data.get("request_id"):
        lines.append(_ctx("request_id", str(data["request_id"])))
    if data.get("summary") is not None:
        lines.append(_ctx("summary", str(data["summary"])))

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: dispute
# ---------------------------------------------------------------------------

def fmt_dispute(data: dict) -> str:
    lines: list[str] = []
    lines.append(_heading("Dispute Summary"))
    lines.append("")

    for field in ("request_id", "risk_level", "confidence"):
        v = data.get(field)
        if v is not None:
            lines.append(_kv(field.replace("_", " ").title(), v))

    summary = data.get("summary")
    if summary:
        lines.append(f"{_label('Summary')}  {summary}")

    factors = data.get("key_factors", [])
    if factors:
        lines.append(f"{_label('Key Factors')}")
        for f in factors:
            lines.append(f"  - {f}")

    doc_ids = data.get("source_doc_ids")
    if doc_ids is not None:
        lines.append(f"{_label('Source Docs')}  {_num(doc_ids)}")

    rails = _rails_line(data)
    if rails:
        lines.append("")
        lines.append(rails)

    tok = data.get("token_usage") or data.get("usage") or data.get("tokens")
    if tok is not None:
        lines.append(_tokens(data, force_blocked=_is_blocked(data)))

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: batch
# ---------------------------------------------------------------------------

def fmt_batch(data: dict) -> str:
    lines: list[str] = []
    lines.append(_heading("Batch Results"))
    lines.append("")

    batch_id = data.get("batch_id")
    if batch_id:
        lines.append(_kv("Batch ID", batch_id))

    total = data.get("total", 0)
    accepted = data.get("accepted", 0)
    rejected = data.get("rejected", 0)
    quarantined = data.get("quarantined", 0)

    lines.append(f"{_label('Total')}  {_num(total)}    "
                 f"{_label('Accepted')}  {_safe(str(accepted))}    "
                 f"{_label('Rejected')}  {_danger(str(rejected))}    "
                 f"{_label('Quarantined')}  {_ada(str(quarantined))}")

    details = data.get("details", [])
    if details:
        lines.append("")
        lines.append(_heading("Details"))
        for item in details:
            item_id = item.get("id", item.get("feedback_id", "?"))
            status = str(item.get("status", "unknown")).lower()
            if status in ("accepted", "allowed", "pass"):
                status_str = _safe(status)
            elif status in ("rejected", "blocked", "fail"):
                status_str = _danger(status)
            elif status in ("quarantined", "flagged"):
                status_str = _ada(status)
            else:
                status_str = _dim(status)
            reason = item.get("reason", "")
            line = f"  {_label('ID')} {_num(item_id)}  {status_str}"
            if reason:
                line += f"  {_dim(reason)}"
            lines.append(line)

    rails = _rails_line(data)
    if rails:
        lines.append("")
        lines.append(rails)

    tok = data.get("token_usage") or data.get("usage") or data.get("tokens")
    if tok is not None:
        lines.append(_tokens(data, force_blocked=_is_blocked(data)))

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: triage (anomaly triage / agent)
# ---------------------------------------------------------------------------

def fmt_triage(data: dict) -> str:
    lines: list[str] = []
    lines.append(_heading("Anomaly Triage"))
    lines.append("")

    for field in ("incident_id", "severity"):
        v = data.get(field)
        if v is not None:
            lines.append(_kv(field.replace("_", " ").title(), v))

    hypothesis = data.get("root_cause_hypothesis")
    if hypothesis:
        lines.append(f"{_label('Root Cause')}  {hypothesis}")

    action = data.get("recommended_action")
    if action:
        lines.append(f"{_label('Action')}  {action}")

    evidence = data.get("evidence_summary")
    if evidence:
        lines.append(f"{_label('Evidence')}  {_dim(evidence)}")

    review = data.get("review_required")
    if review is not None:
        lines.append(_kv("Review Required", review))

    # Agent state extras
    node = data.get("current_node")
    if node:
        lines.append(_kv("Current Node", node))

    decisions = data.get("decisions", [])
    if decisions:
        lines.append("")
        lines.append(_heading("Decisions"))
        for d in decisions:
            node_name = d.get("node", "?")
            result = str(d.get("result", d.get("action", "?"))).lower()
            if result in ("allow", "allowed", "escalate"):
                result_str = _safe(result)
            elif result in ("block", "blocked", "reject"):
                result_str = _danger(result)
            else:
                result_str = _dim(result)
            lines.append(f"  {_label(node_name)}  {result_str}")

    tool_calls = data.get("tool_calls", [])
    if tool_calls:
        lines.append("")
        lines.append(_heading("Tool Calls"))
        for tc in tool_calls:
            tool = tc.get("tool", tc.get("name", "?"))
            status = str(tc.get("status", "done")).lower()
            lines.append(f"  {_label(tool)}  {_dim(status)}")

    rails = _rails_line(data)
    if rails:
        lines.append("")
        lines.append(rails)

    tok = data.get("token_usage") or data.get("usage") or data.get("tokens")
    if tok is not None:
        lines.append(_tokens(data, force_blocked=_is_blocked(data)))

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: catalog
# ---------------------------------------------------------------------------

def fmt_catalog(data: dict) -> str:
    lines: list[str] = []
    lines.append(_heading("Catalog Enrichment"))
    lines.append("")

    req_id = data.get("request_id")
    if req_id:
        lines.append(_kv("Request ID", req_id))

    desc = data.get("enhanced_description")
    if desc:
        lines.append(f"{_label('Description')}  {desc}")

    attrs = data.get("extracted_attributes", {})
    if attrs:
        lines.append(f"{_label('Attributes')}")
        for k, v in attrs.items():
            lines.append(f"  {_label(k)}  {_val(v)}")

    for field in ("confidence", "validation_status"):
        v = data.get(field)
        if v is not None:
            lines.append(_kv(field.replace("_", " ").title(), v))

    doc_ids = data.get("source_doc_ids")
    if doc_ids is not None:
        lines.append(f"{_label('Source Docs')}  {_num(doc_ids)}")

    rails = _rails_line(data)
    if rails:
        lines.append("")
        lines.append(rails)

    tok = data.get("token_usage") or data.get("usage") or data.get("tokens")
    if tok is not None:
        lines.append(_tokens(data, force_blocked=_is_blocked(data)))

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: validation
# ---------------------------------------------------------------------------

def fmt_validation(data: dict) -> str:
    lines: list[str] = []
    lines.append(_heading("Validation Results"))
    lines.append("")

    checks = data.get("checks", {})
    for name, info in checks.items():
        if isinstance(info, dict):
            passed = info.get("passed", False)
            detail = info.get("detail", "")
        else:
            passed = bool(info)
            detail = ""
        tag = _verdict(passed)
        line = f"  {tag}  {_label(name)}"
        if detail:
            line += f"  {_dim(detail)}"
        lines.append(line)

    errors = data.get("errors", [])
    if errors:
        lines.append("")
        for e in errors:
            lines.append(f"  {_danger('!')}  {_dim(e)}")

    is_valid = data.get("is_valid")
    if is_valid is not None:
        lines.append("")
        if is_valid:
            lines.append(f"{_label('VERDICT')}  {_safe('PASS')}")
        else:
            lines.append(f"{_label('VERDICT')}  {_danger('FAIL')}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: dashboard
# ---------------------------------------------------------------------------

def fmt_dashboard(data: dict) -> str:
    lines: list[str] = []
    lines.append(_heading("Governance Dashboard"))
    lines.append("")

    # Top-level counters
    for key in ("total_requests", "allowed", "blocked", "quarantined",
                "avg_latency_ms", "uptime"):
        v = data.get(key)
        if v is not None:
            lines.append(_kv(key.replace("_", " ").title(), v))

    # Policy section
    policies = data.get("policies") or data.get("policy_status") or {}
    if policies:
        lines.append("")
        lines.append(_heading("Policies"))
        if isinstance(policies, dict):
            for name, info in policies.items():
                if isinstance(info, dict):
                    enabled = info.get("enabled", info.get("active", None))
                    if enabled is not None:
                        status = _safe("enabled") if enabled else _danger("disabled")
                    else:
                        status = _dim(str(info))
                    lines.append(f"  {_label(name)}  {status}")
                else:
                    lines.append(f"  {_label(name)}  {_val(info)}")
        elif isinstance(policies, list):
            for p in policies:
                if isinstance(p, dict):
                    pname = p.get("name", "?")
                    enabled = p.get("enabled", True)
                    status = _safe("enabled") if enabled else _danger("disabled")
                    lines.append(f"  {_label(pname)}  {status}")
                else:
                    lines.append(f"  {_val(p)}")

    # Rails summary
    rails = _rails_line(data)
    if rails:
        lines.append("")
        lines.append(rails)

    # Guardrail stats
    stats = data.get("guardrail_stats") or data.get("rail_stats") or {}
    if stats:
        lines.append("")
        lines.append(_heading("Guardrail Stats"))
        for name, info in stats.items():
            if isinstance(info, dict):
                triggered = info.get("triggered", info.get("count", 0))
                lines.append(f"  {_label(name)}  {_num(triggered)} triggered")
            else:
                lines.append(f"  {_label(name)}  {_num(info)}")

    tok = data.get("token_usage") or data.get("usage") or data.get("tokens")
    if tok is not None:
        lines.append("")
        lines.append(_tokens(data, force_blocked=_is_blocked(data)))

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: audit
# ---------------------------------------------------------------------------

def fmt_audit(data: dict) -> str:
    lines: list[str] = []
    lines.append(_heading("Audit Log"))
    lines.append("")

    entries = data.get("entries") or data.get("logs") or data.get("events") or []
    # If the top-level object is a single entry, wrap it
    if not entries and any(k in data for k in ("timestamp", "event", "action")):
        entries = [data]

    for entry in entries:
        ts = entry.get("timestamp", "")
        event = entry.get("event", entry.get("action", ""))
        user = entry.get("user", entry.get("actor", ""))
        status = str(entry.get("status", entry.get("result", ""))).lower()

        if status in ("allowed", "pass", "success", "ok"):
            status_str = _safe(status)
        elif status in ("blocked", "fail", "rejected", "error"):
            status_str = _danger(status)
        else:
            status_str = _dim(status)

        line = f"  {_dim(ts)}  {_label(event)}  {status_str}"
        if user:
            line += f"  {_dim(user)}"
        lines.append(line)

        # PII / entity details
        entities = entry.get("entities") or entry.get("pii_entities") or []
        if entities:
            for ent in entities:
                if isinstance(ent, dict):
                    etype = ent.get("type", ent.get("entity_type", ""))
                    lines.append(f"    {_ada(etype)}")
                else:
                    lines.append(f"    {_ada(ent)}")

        detail = entry.get("detail") or entry.get("reason") or ""
        if detail:
            lines.append(f"    {_dim(detail)}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: health
# ---------------------------------------------------------------------------

def fmt_health(data: dict) -> str:
    lines: list[str] = []
    lines.append(_heading("Health Check"))
    lines.append("")

    status = data.get("status", "unknown")
    sl = status.lower()
    if sl in ("healthy", "ok", "up", "pass"):
        lines.append(f"{_label('Status')}  {_safe(status)}")
    elif sl in ("unhealthy", "down", "fail", "error"):
        lines.append(f"{_label('Status')}  {_danger(status)}")
    else:
        lines.append(f"{_label('Status')}  {_dim(status)}")

    version = data.get("version")
    if version:
        lines.append(_kv("Version", version))

    uptime = data.get("uptime") or data.get("uptime_seconds")
    if uptime is not None:
        lines.append(f"{_label('Uptime')}  {_num(uptime)}")

    # Component checks
    components = data.get("components") or data.get("checks") or data.get("services") or {}
    if isinstance(components, dict) and components:
        lines.append("")
        lines.append(_heading("Components"))
        for name, info in components.items():
            if isinstance(info, dict):
                cstatus = str(info.get("status", "unknown")).lower()
            else:
                cstatus = str(info).lower()
            if cstatus in ("healthy", "ok", "up", "pass", "connected"):
                lines.append(f"  {_label(name)}  {_safe(cstatus)}")
            elif cstatus in ("unhealthy", "down", "fail", "error", "disconnected"):
                lines.append(f"  {_label(name)}  {_danger(cstatus)}")
            else:
                lines.append(f"  {_label(name)}  {_dim(cstatus)}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: metrics
# ---------------------------------------------------------------------------

# DuckDB warehouse counts are the demo proof points — highlight them with ★.
_METRICS_HIGHLIGHT = {"raw_feedback", "trusted_enriched", "quarantine_outputs"}


def fmt_metrics(data: dict) -> str:
    lines: list[str] = []
    lines.append(_heading("Warehouse metrics"))
    lines.append("")

    # Show top-level fields as context, then the duckdb counts with the
    # proof-point fields ★ highlighted.
    for key, value in data.items():
        if not isinstance(value, (dict, list)):
            lines.append(_ctx(key, str(value)))

    duck = data.get("duckdb", {})
    if isinstance(duck, dict) and duck:
        lines.append(f"  {BLUE}duckdb{RESET}")
        for sk, sv in duck.items():
            if sk in _METRICS_HIGHLIGHT:
                lines.append(f"  {PINK}★{RESET} {BLUE}{sk}:{RESET} {LGRN}{sv}{RESET}")
            else:
                lines.append(_ctx(sk, str(sv)))

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: raw (fallback pretty-print with colored keys)
# ---------------------------------------------------------------------------

def _fmt_raw_value(value: Any, indent: int = 0) -> list[str]:
    """Recursively format a JSON value with colored keys."""
    prefix = "  " * indent
    lines: list[str] = []

    if isinstance(value, dict):
        for k, v in value.items():
            if isinstance(v, (dict, list)):
                lines.append(f"{prefix}{_label(k)}")
                lines.extend(_fmt_raw_value(v, indent + 1))
            else:
                lines.append(f"{prefix}{_label(k)}  {_val(v)}")
    elif isinstance(value, list):
        for item in value:
            if isinstance(item, (dict, list)):
                lines.extend(_fmt_raw_value(item, indent + 1))
            else:
                lines.append(f"{prefix}- {_val(item)}")
    else:
        lines.append(f"{prefix}{_val(value)}")

    return lines


def fmt_raw(data: dict) -> str:
    lines = _fmt_raw_value(data)
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Dispatcher
# ---------------------------------------------------------------------------

def fmt_decisions(data: Any) -> str:
    """Highlight the latest llm_decisions record (Step 3 proof point)."""
    record = data[0] if isinstance(data, list) and data else data
    if not isinstance(record, dict):
        return fmt_raw(data)

    lines: list[str] = []
    lines.append(_heading("LLM Decision Record"))
    lines.append("")

    # ★ highlight request_id and status; show the rest as context.
    if record.get("request_id"):
        lines.append(_hi("request_id", str(record["request_id"])))
    if record.get("status"):
        lines.append(_hi("status", str(record["status"])))
    if record.get("endpoint"):
        lines.append(_ctx("endpoint", str(record["endpoint"])))
    p = record.get("prompt_tokens", 0)
    c = record.get("completion_tokens", 0)
    t = record.get("total_tokens", 0)
    lines.append(_ctx("tokens", f"prompt={p} completion={c} total={t}"))

    return "\n".join(lines)


FORMATTERS: dict[str, Any] = {
    "feedback": fmt_feedback,
    "dispute": fmt_dispute,
    "batch": fmt_batch,
    "triage": fmt_triage,
    "catalog": fmt_catalog,
    "validation": fmt_validation,
    "dashboard": fmt_dashboard,
    "audit": fmt_audit,
    "decisions": fmt_decisions,
    "health": fmt_health,
    "metrics": fmt_metrics,
    "raw": fmt_raw,
}


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Colored JSON formatter for Pluralsight demo curl output",
    )
    parser.add_argument(
        "--type",
        choices=sorted(FORMATTERS),
        default="raw",
        help="Formatting mode (default: raw)",
    )
    args = parser.parse_args()

    raw = sys.stdin.read().strip()
    if not raw:
        print(_dim("(empty response)"))
        return

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(_danger(f"JSON parse error: {exc}"))
        print(_dim(raw[:500]))
        return

    # Unwrap single-element lists so formatters always get a dict
    if isinstance(data, list):
        if len(data) == 1 and isinstance(data[0], dict):
            data = data[0]
        elif args.type == "audit":
            # Audit accepts a list of entries directly
            data = {"entries": data}
        elif args.type == "batch":
            data = {"details": data, "total": len(data)}
        else:
            # Fallback: wrap list for raw display
            data = {"items": data}

    if not isinstance(data, dict):
        print(_val(data))
        return

    formatter = FORMATTERS[args.type]
    print(formatter(data))


if __name__ == "__main__":
    main()
