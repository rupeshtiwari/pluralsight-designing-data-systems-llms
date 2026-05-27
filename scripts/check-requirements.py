#!/usr/bin/env python3
"""Post-setup validation for Designing Data Systems with LLMs.

Checks that all required tools, files, and directories are present.
Called automatically at the end of setup.sh / setup.ps1, but can also
be run standalone:

    python scripts/check-requirements.py
"""
import shutil
import subprocess
import sys
from pathlib import Path

PASS = "\033[32m[PASS]\033[0m"
FAIL = "\033[31m[FAIL]\033[0m"
WARN = "\033[33m[WARN]\033[0m"
errors = 0


def run(command: str) -> tuple[int, str, str]:
    result = subprocess.run(
        command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, shell=True,
    )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


def check(condition: bool, label: str, fix: str = "") -> None:
    global errors
    if condition:
        print(f"  {PASS} {label}")
    else:
        print(f"  {FAIL} {label}")
        if fix:
            print(f"         Fix: {fix}")
        errors += 1


def warn(condition: bool, label: str, note: str = "") -> None:
    if condition:
        print(f"  {PASS} {label}")
    else:
        print(f"  {WARN} {label}")
        if note:
            print(f"         Note: {note}")


def main() -> None:
    global errors
    root = Path(__file__).resolve().parents[1]

    print("Validating local setup...\n")

    # ── Python version ──────────────────────────────────────────────────────
    print("Python:")
    check(
        sys.version_info >= (3, 12),
        f"Python {sys.version_info.major}.{sys.version_info.minor}",
        "Install Python 3.12+ from https://www.python.org/downloads/",
    )

    # ── Python packages ─────────────────────────────────────────────────────
    print("\nPython packages:")
    for pkg in ["fastapi", "uvicorn", "duckdb", "pydantic", "httpx", "structlog"]:
        try:
            __import__(pkg)
            check(True, pkg)
        except ImportError:
            check(False, pkg, f"pip install {pkg}")

    # ── CLI tools ───────────────────────────────────────────────────────────
    print("\nCLI tools:")
    check(
        shutil.which("docker") is not None,
        "docker",
        "Install Docker Desktop: https://www.docker.com/products/docker-desktop/",
    )
    check(
        shutil.which("duckdb") is not None,
        "duckdb CLI",
        "Install from https://duckdb.org/docs/installation/",
    )
    warn(
        shutil.which("tmux") is not None,
        "tmux (optional — author recording only)",
        "Not required for students. Authors: brew install tmux",
    )

    # ── Docker state ────────────────────────────────────────────────────────
    print("\nDocker:")
    code, _, _ = run("docker info")
    check(code == 0, "Docker daemon is running", "Start Docker Desktop or Docker Engine")

    code, _, _ = run("docker compose version")
    check(code == 0, "Docker Compose is available", "Install Docker Compose")

    # ── Compose file ────────────────────────────────────────────────────────
    has_compose = (root / "docker-compose.yml").exists() or (root / "compose.yml").exists()
    check(has_compose, "docker-compose.yml or compose.yml", "File missing from project root")

    # ── Required files ──────────────────────────────────────────────────────
    print("\nRequired files:")
    for fname in ["requirements.txt", "Dockerfile", ".env"]:
        check((root / fname).exists(), fname, f"Run ./setup.sh to create {fname}")

    # ── Required directories ────────────────────────────────────────────────
    print("\nRequired directories:")
    for dname in ["data", "logs", "tmp", ".run", "app", "scripts",
                   "data/payloads", "data/seed"]:
        check((root / dname).exists(), f"{dname}/", f"mkdir -p {dname}")

    # ── Seed data ───────────────────────────────────────────────────────────
    print("\nSeed data:")
    for fname in ["feedback.json", "orders.json", "refunds.json",
                   "merchant_transactions.json", "reference_docs.json",
                   "customers.json", "products.json"]:
        check((root / "data" / "seed" / fname).exists(), f"data/seed/{fname}")

    # ── Demo payloads ───────────────────────────────────────────────────────
    print("\nDemo payloads:")
    for fname in ["feedback_enrich.json", "feedback_positive.json",
                   "anomaly_triage.json", "dispute_summary.json",
                   "catalog_enrich.json", "batch_feedback.json",
                   "batch_validation_test.json"]:
        check((root / "data" / "payloads" / fname).exists(), f"data/payloads/{fname}")

    # ── DuckDB database ─────────────────────────────────────────────────────
    print("\nDuckDB:")
    db_path = root / "data" / "northwind.duckdb"
    check(db_path.exists(), "data/northwind.duckdb", "Run: python scripts/seed-data.py")

    # ── Summary ─────────────────────────────────────────────────────────────
    print()
    if errors == 0:
        print("\033[32mAll checks passed.\033[0m")
    else:
        print(f"\033[31m{errors} check(s) failed. Fix the issues above and rerun.\033[0m")
        sys.exit(1)


if __name__ == "__main__":
    main()
