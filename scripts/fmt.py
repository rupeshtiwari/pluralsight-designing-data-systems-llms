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

# Fields to mark with ★, set from --highlight. Empty means use defaults.
HIGHLIGHT: set[str] = set()

# True once a --title panel is printed, so formatters skip their own heading.
PANEL_SHOWN = False


def _maybe_heading(text: str) -> list[str]:
    """Return the formatter's own heading lines, unless a panel was shown."""
    if PANEL_SHOWN:
        return []
    return [f"{WHITE}{text}{RESET}", ""]


def _should_star(field: str, default: bool) -> bool:
    """Whether a field gets the ★ highlight.

    If --highlight was passed, only those fields are starred. Otherwise
    fall back to the formatter's default choice.
    """
    if HIGHLIGHT:
        return field in HIGHLIGHT
    return default

# ---------------------------------------------------------------------------
# Tiny helpers
# ---------------------------------------------------------------------------

def _panel(title: str, why: str) -> str:
    """A bordered header explaining what this output shows and why.

    Title in White bold, the 'why' line in Blue, inside a box so it reads
    like a table header on camera. Long text wraps onto extra lines — never
    truncated (per course rule: keep full content).
    """
    width = 72
    inner = width - 4
    top = "┌" + "─" * (width - 2) + "┐"
    bot = "└" + "─" * (width - 2) + "┘"

    def wrap(text: str) -> list[str]:
        # Word-wrap to fit inside the box; preserve every character.
        words = text.split()
        out: list[str] = []
        cur = ""
        for w in words:
            if not cur:
                cur = w
            elif len(cur) + 1 + len(w) <= inner:
                cur = f"{cur} {w}"
            else:
                out.append(cur)
                cur = w
        if cur:
            out.append(cur)
        return out or [""]

    def row(text: str, color: str) -> str:
        return f"│ {color}{text}{RESET}{' ' * (inner - len(text))} │"

    lines = [top]
    for line in wrap(title):
        lines.append(row(line, WHITE))
    if why:
        for line in wrap(why):
            lines.append(row(line, BLUE))
    lines.append(bot)
    return "\n".join(lines)


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
    lines.extend(_maybe_heading("Feedback Enrichment"))

    # Outline names these 5 fields explicitly as on-screen proof, plus the
    # status which proves the contract. All 6 default to ★ highlighted.
    order = ["request_id", "category", "summary", "confidence",
             "source_doc_ids", "validation_status"]
    defaults = set(order)
    for field in order:
        if data.get(field) is None:
            continue
        if field == "source_doc_ids":
            value = ", ".join(str(d) for d in data[field])
        else:
            value = str(data[field])
        if _should_star(field, field in defaults):
            lines.append(_hi(field, value))
        else:
            lines.append(_ctx(field, value))

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: dispute
# ---------------------------------------------------------------------------

def fmt_dispute(data: dict) -> str:
    lines: list[str] = []
    lines.extend(_maybe_heading("Dispute Summary"))

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
    lines.extend(_maybe_heading("Batch Results"))

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
    """Module 2 Step 2 — compact agent-state JSON view.

    ★ on the outline-named fields: incident_id, selected_edge, severity,
    recommended_action, evidence_summary, decision_reason, review_required.
    Plus the canonical node path the workflow traversed.
    """
    lines: list[str] = []
    lines.extend(_maybe_heading("Agent triage state"))

    defaults = {
        "incident_id", "selected_edge", "severity", "recommended_action",
        "evidence_summary", "decision_reason", "review_required",
    }
    # Display order matches narration order
    order = [
        "incident_id", "severity", "selected_edge",
        "recommended_action", "evidence_summary", "decision_reason",
        "review_required",
    ]
    # Map AnomalyTriageResponse field "root_cause_hypothesis" onto decision_reason
    if "decision_reason" not in data and data.get("root_cause_hypothesis"):
        data = {**data, "decision_reason": data["root_cause_hypothesis"]}
    # If selected_edge missing (triage response), infer from review_required
    if "selected_edge" not in data:
        data = {**data, "selected_edge": (
            "recommend_action" if data.get("review_required") else "auto_log"
        )}

    for field in order:
        if data.get(field) is None:
            continue
        value = str(data[field])
        if _should_star(field, field in defaults):
            lines.append(_hi(field, value))
        else:
            lines.append(_ctx(field, value))

    # Canonical node path so the author can read the traversal aloud
    path_high = (
        "inspect_metadata → retrieve_runbook → classify_severity → "
        "recommend_action → approval_gate"
    )
    path_low = (
        "inspect_metadata → retrieve_runbook → classify_severity → auto_log"
    )
    selected = data.get("selected_edge", "")
    path = path_high if selected == "recommend_action" else path_low
    lines.append("")
    lines.append(f"  {PINK}★{RESET} {BLUE}path:{RESET} {LGRN}{path}{RESET}")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: mermaid (Module 2 Step 1 — show LangGraph topology source)
# ---------------------------------------------------------------------------

def fmt_mermaid(data: dict) -> str:
    """Print the Mermaid source verbatim plus a star-highlighted active node.

    Outline asks the four named nodes (inspect_metadata, retrieve_runbook,
    recommend_action, approval_gate) to be highlighted; we star each one
    in a dedicated legend block so the diagram source stays raw and copy-
    pasteable.
    """
    lines: list[str] = []
    lines.extend(_maybe_heading("LangGraph topology (Mermaid)"))

    mermaid_src = data.get("mermaid", "")
    active = data.get("active_node", "")

    # The raw mermaid source — printed verbatim so it can be pasted into
    # any Mermaid renderer to produce the on-screen diagram.
    if mermaid_src:
        lines.append(f"{DIM}--- mermaid source ---{RESET}")
        for line in mermaid_src.splitlines():
            lines.append(f"  {DIM}{line}{RESET}")
        lines.append(f"{DIM}--- end ---{RESET}")
        lines.append("")

    nodes = data.get("nodes", []) or []
    if nodes:
        lines.append(f"  {BLUE}nodes:{RESET}")
        # The four nodes the outline names must be starred
        outline = {"inspect_metadata", "retrieve_runbook", "recommend_action", "approval_gate"}
        for n in nodes:
            if _should_star(n, n in outline):
                lines.append(f"  {PINK}★{RESET} {LGRN}{n}{RESET}")
            else:
                lines.append(f"    {GRAY}{n}{RESET}")

    if active:
        lines.append("")
        lines.append(f"  {PINK}★ active node:{RESET} {LGRN}{active}{RESET}")

    active_path = data.get("active_path") or []
    if active_path:
        lines.append("")
        path_str = " → ".join(active_path)
        lines.append(f"  {PINK}★ active path:{RESET} {LGRN}{path_str}{RESET}")
        lines.append(
            f"  {DIM}(classDef 'active' in the Mermaid source above "
            f"highlights these nodes in green){RESET}"
        )

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: tool-calls (Module 2 Step 3 — agent_tool_calls table)
# ---------------------------------------------------------------------------

def fmt_tool_calls(data: dict) -> str:
    """Compact one-screen view of agent_tool_calls.

    ★ on every row across: tool_name, input_hash (12 char prefix),
    output_status, created_at. Limits to 7 rows max so the table fits
    on screen during the demo.
    """
    lines: list[str] = []
    lines.extend(_maybe_heading("agent_tool_calls (Postgres)"))

    backend = data.get("backend")
    if backend:
        lines.append(_hi("backend", str(backend)) if _should_star("backend", False)
                     else _ctx("backend", str(backend)))
    incident = data.get("incident_id")
    if incident:
        lines.append(_ctx("incident_id", str(incident)))
    count = data.get("count")
    if count is not None:
        lines.append(_ctx("count", str(count)))

    rows = data.get("tool_calls", []) or []
    rows = rows[:7]
    lines.append("")
    # Column header
    lines.append(
        f"  {BLUE}{'tool_name':<22}{RESET} "
        f"{BLUE}{'input_hash':<14}{RESET} "
        f"{BLUE}{'output_status':<15}{RESET} "
        f"{BLUE}created_at{RESET}"
    )
    for r in rows:
        tool = str(r.get("tool_name", "?"))
        h = str(r.get("input_hash", ""))[:12]
        status = str(r.get("output_status", ""))
        ts = str(r.get("created_at", ""))[:19]
        status_color = LIME if status == "success" else PINK
        lines.append(
            f"  {PINK}★{RESET} {LGRN}{tool:<20}{RESET} "
            f"{LGRN}{h:<12}{RESET}   "
            f"{status_color}{status:<13}{RESET}   "
            f"{LGRN}{ts}{RESET}"
        )
    if not rows:
        lines.append(f"  {DIM}(no tool calls recorded){RESET}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: agent-decisions (Module 2 Step 4 — agent_decisions table)
# ---------------------------------------------------------------------------

def fmt_agent_decisions(data: Any) -> str:
    """Show the latest agent_decisions row with ★ on the outline fields."""
    lines: list[str] = []
    lines.extend(_maybe_heading("agent_decisions (latest)"))

    # Accept either the /admin/agent-decisions wrapper or /agent/decisions list
    if isinstance(data, dict) and "decisions" in data:
        backend = data.get("backend")
        if backend:
            lines.append(_ctx("backend", str(backend)))
        rows = data.get("decisions", []) or []
    elif isinstance(data, list):
        rows = data
    elif isinstance(data, dict):
        rows = [data]
    else:
        return fmt_raw({"value": data})

    if not rows:
        lines.append(f"  {DIM}(no decisions recorded){RESET}")
        return "\n".join(lines)

    record = rows[0]
    defaults = {
        "incident_id", "status", "severity", "recommended_action",
        "selected_edge", "decision_reason",
    }
    order = [
        "incident_id", "status", "severity", "selected_edge",
        "recommended_action", "decision_reason", "evidence_summary",
    ]
    for field in order:
        if record.get(field) is None:
            continue
        value = str(record[field])
        if _should_star(field, field in defaults):
            lines.append(_hi(field, value))
        else:
            lines.append(_ctx(field, value))

    # review_required is implicit in status == 'review_required' — show it
    # explicitly so the proof point is unmistakable on screen.
    review_required = (str(record.get("status", "")).lower() == "review_required")
    lines.append("")
    rr_val = "true" if review_required else "false"
    rr_color = LIME if review_required else GRAY
    lines.append(
        f"  {PINK}★{RESET} {BLUE}review_required:{RESET} {rr_color}{rr_val}{RESET}"
    )
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Format: catalog
# ---------------------------------------------------------------------------

def fmt_catalog(data: dict) -> str:
    lines: list[str] = []
    lines.extend(_maybe_heading("Catalog Enrichment"))

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
    lines.extend(_maybe_heading("Validation Results"))

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
    lines.extend(_maybe_heading("Governance Dashboard"))

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
    lines.extend(_maybe_heading("Audit Log"))

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
    lines.extend(_maybe_heading("Health Check"))

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

# Default starred metric fields. Override per step with --highlight.
_METRICS_HIGHLIGHT = {"raw_feedback", "trusted_enriched"}


def fmt_metrics(data: dict) -> str:
    lines: list[str] = []
    lines.extend(_maybe_heading("Warehouse metrics"))

    # Top-level fields as context; --highlight can star any of them.
    for key, value in data.items():
        if not isinstance(value, (dict, list)):
            if _should_star(key, False):
                lines.append(_hi(key, str(value)))
            else:
                lines.append(_ctx(key, str(value)))

    duck = data.get("duckdb", {})
    if isinstance(duck, dict) and duck:
        lines.append(f"  {BLUE}duckdb{RESET}")
        for sk, sv in duck.items():
            if _should_star(sk, sk in _METRICS_HIGHLIGHT):
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


def fmt_refdocs(data: dict) -> str:
    """Compact one-screen view of pgvector reference docs (Module 1 Step 1b).

    Shows: backend, count, all-embedded summary, then one row per doc with
    the two fields the narration reads aloud — doc_id and title.
    """
    lines: list[str] = []
    lines.extend(_maybe_heading("pgvector reference documents"))

    backend = data.get("backend", "?")
    docs = data.get("documents", []) or []
    count = data.get("count", len(docs))
    all_embedded = bool(docs) and all(d.get("has_embedding") for d in docs)

    lines.append(_hi("backend", backend))
    lines.append(_hi("count", str(count)))
    embed_val = "true (all 384-dim)" if all_embedded else "MISSING"
    lines.append(_hi("all_embedded", embed_val))
    lines.append("")
    lines.append(f"  {BLUE}documents (doc_id → title):{RESET}")
    for d in docs:
        doc_id = str(d.get("doc_id", "?"))
        title = str(d.get("title", ""))
        lines.append(f"  {PINK}★{RESET} {LGRN}{doc_id}{RESET}  {title}")

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
    lines.extend(_maybe_heading("LLM Decision Record"))

    # Default starred fields for decisions; --highlight can override.
    defaults = {"request_id", "status"}
    if record.get("request_id"):
        rid, val = "request_id", str(record["request_id"])
        lines.append(_hi(rid, val) if _should_star(rid, rid in defaults) else _ctx(rid, val))
    if record.get("status"):
        st, val = "status", str(record["status"])
        lines.append(_hi(st, val) if _should_star(st, st in defaults) else _ctx(st, val))
    if record.get("endpoint"):
        ep, val = "endpoint", str(record["endpoint"])
        lines.append(_hi(ep, val) if _should_star(ep, False) else _ctx(ep, val))
    p = record.get("prompt_tokens", 0)
    c = record.get("completion_tokens", 0)
    t = record.get("total_tokens", 0)
    tok_val = f"prompt={p} completion={c} total={t}"
    lines.append(_hi("tokens", tok_val) if _should_star("tokens", False) else _ctx("tokens", tok_val))

    # Validation checks (schema, grounding, confidence, source ID) — outline
    # requires proving each one passes.
    validation = record.get("validation") or {}
    checks = validation.get("checks") if isinstance(validation, dict) else None
    if isinstance(checks, dict) and checks:
        # Map internal check names to the names the outline uses
        outline_names = {
            "required_fields": "schema",
            "grounding": "grounding",
            "confidence": "confidence",
            "category": "source ID",
        }
        lines.append("")
        lines.append(f"  {BLUE}validation checks:{RESET}")
        for internal, display in outline_names.items():
            info = checks.get(internal)
            if not isinstance(info, dict):
                continue
            passed = bool(info.get("passed"))
            mark = f"{LIME}✓ PASS{RESET}" if passed else f"{PINK}✗ FAIL{RESET}"
            lines.append(f"  {PINK}★{RESET} {display:<12} {mark}")

    return "\n".join(lines)


FORMATTERS: dict[str, Any] = {
    "feedback": fmt_feedback,
    "dispute": fmt_dispute,
    "batch": fmt_batch,
    "triage": fmt_triage,
    "mermaid": fmt_mermaid,
    "tool-calls": fmt_tool_calls,
    "agent-decisions": fmt_agent_decisions,
    "catalog": fmt_catalog,
    "validation": fmt_validation,
    "dashboard": fmt_dashboard,
    "audit": fmt_audit,
    "decisions": fmt_decisions,
    "health": fmt_health,
    "metrics": fmt_metrics,
    "raw": fmt_raw,
    "refdocs": fmt_refdocs,
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
    parser.add_argument(
        "--highlight",
        default="",
        help="Comma-separated field names to mark with ★ (overrides defaults)",
    )
    parser.add_argument(
        "--title",
        default="",
        help="Header title — what this output shows",
    )
    parser.add_argument(
        "--why",
        default="",
        help="Header subtitle — why we are showing it",
    )
    args = parser.parse_args()

    global HIGHLIGHT
    if args.highlight:
        HIGHLIGHT = {f.strip() for f in args.highlight.split(",") if f.strip()}

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
        if args.type == "agent-decisions":
            # The /agent/decisions endpoint returns a bare list of rows
            data = {"decisions": data, "count": len(data)}
        elif args.type == "tool-calls":
            data = {"tool_calls": data, "count": len(data)}
        elif len(data) == 1 and isinstance(data[0], dict):
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

    global PANEL_SHOWN
    if args.title:
        print(_panel(args.title, args.why))
        print()
        PANEL_SHOWN = True

    formatter = FORMATTERS[args.type]
    print(formatter(data))


if __name__ == "__main__":
    main()
