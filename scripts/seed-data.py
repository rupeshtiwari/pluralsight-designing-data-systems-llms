#!/usr/bin/env python3
"""Initialize DuckDB tables and load seed data from data/seed/*.json.

Standalone script that can be run outside the FastAPI server to ensure
DuckDB is ready before demos. Safe to run multiple times — skips
tables that already have data.

Usage:
    python scripts/seed-data.py
"""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

try:
    import duckdb
except ImportError:
    print("ERROR: duckdb Python package not installed. Run: pip install duckdb")
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "data" / "northwind.duckdb"
SEED_DIR = ROOT / "data" / "seed"


def load_json(name: str) -> list[dict]:
    path = SEED_DIR / name
    if not path.exists():
        print(f"  WARN: {path} not found, skipping")
        return []
    data = json.loads(path.read_text())
    return data if isinstance(data, list) else []


def main() -> None:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = duckdb.connect(str(DB_PATH))

    for schema in ("raw", "trusted", "quarantine"):
        conn.execute(f"CREATE SCHEMA IF NOT EXISTS {schema}")

    conn.execute("""
        CREATE TABLE IF NOT EXISTS raw.feedback (
            id INTEGER, customer_id VARCHAR, product_id VARCHAR,
            feedback_text VARCHAR, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS raw.orders (
            order_id VARCHAR, customer_id VARCHAR, product_id VARCHAR,
            amount DOUBLE, status VARCHAR, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS raw.refunds (
            refund_id VARCHAR, order_id VARCHAR, reason VARCHAR,
            amount DOUBLE, status VARCHAR, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS raw.merchant_transactions (
            txn_id VARCHAR, merchant_id VARCHAR, amount DOUBLE,
            type VARCHAR, created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS trusted.feedback_enriched (
            id VARCHAR, request_id VARCHAR, customer_id VARCHAR,
            product_id VARCHAR, feedback_text VARCHAR, category VARCHAR,
            summary VARCHAR, confidence DOUBLE, source_doc_ids VARCHAR,
            validation_status VARCHAR, enriched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS quarantine.llm_outputs (
            id VARCHAR, request_id VARCHAR, input_text VARCHAR,
            raw_output VARCHAR, validation_errors VARCHAR,
            quarantined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP)
    """)
    print("  Tables initialized")

    now = datetime.now(timezone.utc).isoformat()

    # Seed feedback
    count = conn.execute("SELECT count(*) FROM raw.feedback").fetchone()[0]
    if count == 0:
        for row in load_json("feedback.json"):
            conn.execute(
                "INSERT INTO raw.feedback VALUES (?,?,?,?,?)",
                [row["id"], row["customer_id"], row["product_id"],
                 row["feedback_text"], row.get("created_at", now)],
            )
        count = conn.execute("SELECT count(*) FROM raw.feedback").fetchone()[0]
    print(f"  raw.feedback: {count} rows")

    # Seed orders
    count = conn.execute("SELECT count(*) FROM raw.orders").fetchone()[0]
    if count == 0:
        for row in load_json("orders.json"):
            conn.execute(
                "INSERT INTO raw.orders VALUES (?,?,?,?,?,?)",
                [row["order_id"], row["customer_id"], row["product_id"],
                 float(row["amount"]), row["status"], row.get("created_at", now)],
            )
        count = conn.execute("SELECT count(*) FROM raw.orders").fetchone()[0]
    print(f"  raw.orders: {count} rows")

    # Seed refunds
    count = conn.execute("SELECT count(*) FROM raw.refunds").fetchone()[0]
    if count == 0:
        for row in load_json("refunds.json"):
            conn.execute(
                "INSERT INTO raw.refunds VALUES (?,?,?,?,?,?)",
                [row["refund_id"], row["order_id"], row["reason"],
                 float(row["amount"]), row["status"], row.get("created_at", now)],
            )
        count = conn.execute("SELECT count(*) FROM raw.refunds").fetchone()[0]
    print(f"  raw.refunds: {count} rows")

    # Seed merchant transactions
    count = conn.execute("SELECT count(*) FROM raw.merchant_transactions").fetchone()[0]
    if count == 0:
        for row in load_json("merchant_transactions.json"):
            conn.execute(
                "INSERT INTO raw.merchant_transactions VALUES (?,?,?,?,?)",
                [row["txn_id"], row["merchant_id"], float(row["amount"]),
                 row["type"], row.get("created_at", now)],
            )
        count = conn.execute("SELECT count(*) FROM raw.merchant_transactions").fetchone()[0]
    print(f"  raw.merchant_transactions: {count} rows")

    conn.close()
    print("  DuckDB seeded successfully")


if __name__ == "__main__":
    main()
