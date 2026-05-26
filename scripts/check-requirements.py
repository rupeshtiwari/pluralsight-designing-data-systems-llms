#!/usr/bin/env python3
"""Post-setup validation for Designing Data Systems with LLMs.

Checks that all required tools, files, and directories are present
after running setup.sh or setup.ps1. Called automatically at the end
of setup, but can also be run standalone:

    python scripts/check-requirements.py
"""
import shutil
import subprocess
import sys
from pathlib import Path


def run(command: str) -> tuple[int, str, str]:
    result = subprocess.run(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        shell=True,
    )
    return result.returncode, result.stdout.strip(), result.stderr.strip()


PASS = "\033[32m[PASS]\033[0m"
FAIL = "\033[31m[FAIL]\033[0m"
errors = 0


def check(condition: bool, label: str, fix: str = "") -> None:
    global errors
    if condition:
        print(f"  {PASS} {label}")
    else:
        print(f"  {FAIL} {label}")
        if fix:
            print(f"         Fix: {fix}")
        errors += 1


def main() -> None:
    global errors
    root = Path(__file__).resolve().parents[1]

    print("Validating local setup...\n")

    # Python version
    print("Python:")
    check(
        sys.version_info >= (3, 12),
        f"Python {sys.version_info.major}.{sys.version_info.minor}",
        "Install Python 3.12+ from https://www.python.org/downloads/",
    )

    # Key Python packages
    print("\nPython packages:")
    for pkg in ["fastapi", "uvicorn", "duckdb", "pydantic", "httpx", "structlog"]:
        try:
            __import__(pkg)
            check(True, pkg)
        except ImportError:
            check(False, pkg, f"pip install {pkg}")

    # CLI tools
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

    # Docker running
    print("\nDocker:")
    code, _, _ = run("docker info")
    check(code == 0, "Docker daemon is running", "Start Docker Desktop or Docker Engine")

    code, _, _ = run("docker compose version")
    check(code == 0, "Docker Compose is available", "Install Docker Compose")

    # Required files
    print("\nRequired files:")
    for fname in ["requirements.txt", "docker-compose.yml", "Dockerfile", ".env"]:
        check((root / fname).exists(), fname, f"Run setup.sh to create {fname}")

    # Required directories
    print("\nRequired directories:")
    for dname in ["data", "logs", "tmp", "app", "scripts", "data/payloads", "data/seed"]:
        check((root / dname).exists(), f"{dname}/", f"mkdir -p {dname}")

    # Seed data files
    print("\nSeed data:")
    for fname in ["feedback.json", "orders.json", "refunds.json", "reference_docs.json"]:
        check(
            (root / "data" / "seed" / fname).exists(),
            f"data/seed/{fname}",
        )

    # Demo payload files
    print("\nDemo payloads:")
    for fname in [
        "feedback_enrich.json",
        "anomaly_triage.json",
        "batch_feedback.json",
        "batch_validation_test.json",
    ]:
        check(
            (root / "data" / "payloads" / fname).exists(),
            f"data/payloads/{fname}",
        )

    # Summary
    print()
    if errors == 0:
        print(f"\033[32mAll checks passed.\033[0m")
    else:
        print(f"\033[31m{errors} check(s) failed. Fix the issues above and rerun.\033[0m")
        sys.exit(1)


if __name__ == "__main__":
    main()
