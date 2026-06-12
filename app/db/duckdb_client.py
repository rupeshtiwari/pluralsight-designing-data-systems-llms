import csv
import json
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Generator, Optional

import duckdb
import structlog

from app.config import DUCKDB_PATH

logger = structlog.get_logger(__name__)

_connection: Optional[duckdb.DuckDBPyConnection] = None


def get_connection() -> duckdb.DuckDBPyConnection:
    global _connection
    if _connection is None:
        Path(DUCKDB_PATH).parent.mkdir(parents=True, exist_ok=True)
        _connection = duckdb.connect(DUCKDB_PATH)
        logger.info("duckdb_connected", path=DUCKDB_PATH)
    return _connection


def close_connection() -> None:
    global _connection
    if _connection is not None:
        _connection.close()
        _connection = None
        logger.info("duckdb_disconnected")


@contextmanager
def cursor() -> Generator[duckdb.DuckDBPyConnection, None, None]:
    conn = get_connection()
    try:
        yield conn
    except Exception:
        logger.exception("duckdb_query_error")
        raise


def init_tables() -> None:
    conn = get_connection()

    for schema in ("raw", "trusted", "quarantine"):
        conn.execute(f"CREATE SCHEMA IF NOT EXISTS {schema}")

    conn.execute("""
        CREATE TABLE IF NOT EXISTS raw.feedback (
            id INTEGER,
            customer_id VARCHAR,
            product_id VARCHAR,
            feedback_text VARCHAR,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS raw.orders (
            order_id VARCHAR,
            customer_id VARCHAR,
            product_id VARCHAR,
            amount DOUBLE,
            status VARCHAR,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS raw.refunds (
            refund_id VARCHAR,
            order_id VARCHAR,
            reason VARCHAR,
            amount DOUBLE,
            status VARCHAR,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS raw.merchant_transactions (
            txn_id VARCHAR,
            merchant_id VARCHAR,
            amount DOUBLE,
            type VARCHAR,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS trusted.feedback_enriched (
            id VARCHAR,
            request_id VARCHAR,
            customer_id VARCHAR,
            product_id VARCHAR,
            feedback_text VARCHAR,
            category VARCHAR,
            summary VARCHAR,
            confidence DOUBLE,
            source_doc_ids VARCHAR,
            validation_status VARCHAR,
            enriched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS quarantine.llm_outputs (
            id INTEGER,
            request_id VARCHAR,
            input_text VARCHAR,
            raw_output VARCHAR,
            validation_errors VARCHAR,
            quarantined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)

    logger.info("duckdb_tables_initialized")


def _load_json_or_csv(file_path: str) -> list[dict]:
    path = Path(file_path)
    if not path.exists():
        logger.warning("seed_file_not_found", path=str(path))
        return []
    if path.suffix == ".json":
        data = json.loads(path.read_text())
        return data if isinstance(data, list) else list(data.values())[0] if data else []
    if path.suffix == ".csv":
        with open(path, newline="") as f:
            return list(csv.DictReader(f))
    return []


def seed_feedback(file_path: str) -> int:
    rows = _load_json_or_csv(file_path)
    if not rows:
        return 0
    conn = get_connection()
    existing = conn.execute("SELECT count(*) FROM raw.feedback").fetchone()[0]
    if existing > 0:
        return existing
    for row in rows:
        conn.execute(
            "INSERT INTO raw.feedback (id, customer_id, product_id, feedback_text, created_at) VALUES (?, ?, ?, ?, ?)",
            [row["id"], row["customer_id"], row["product_id"], row["feedback_text"],
             row.get("created_at", datetime.now(timezone.utc).isoformat())],
        )
    logger.info("seed_feedback_loaded", count=len(rows), source=file_path)
    return len(rows)


def seed_orders(file_path: str) -> int:
    rows = _load_json_or_csv(file_path)
    if not rows:
        return 0
    conn = get_connection()
    existing = conn.execute("SELECT count(*) FROM raw.orders").fetchone()[0]
    if existing > 0:
        return existing
    for row in rows:
        conn.execute(
            "INSERT INTO raw.orders (order_id, customer_id, product_id, amount, status, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            [row["order_id"], row["customer_id"], row["product_id"], float(row["amount"]),
             row["status"], row.get("created_at", datetime.now(timezone.utc).isoformat())],
        )
    logger.info("seed_orders_loaded", count=len(rows), source=file_path)
    return len(rows)


def seed_refunds(file_path: str) -> int:
    rows = _load_json_or_csv(file_path)
    if not rows:
        return 0
    conn = get_connection()
    existing = conn.execute("SELECT count(*) FROM raw.refunds").fetchone()[0]
    if existing > 0:
        return existing
    for row in rows:
        conn.execute(
            "INSERT INTO raw.refunds (refund_id, order_id, reason, amount, status, created_at) VALUES (?, ?, ?, ?, ?, ?)",
            [row["refund_id"], row["order_id"], row["reason"], float(row["amount"]),
             row["status"], row.get("created_at", datetime.now(timezone.utc).isoformat())],
        )
    logger.info("seed_refunds_loaded", count=len(rows), source=file_path)
    return len(rows)


def seed_merchant_transactions(file_path: str) -> int:
    rows = _load_json_or_csv(file_path)
    if not rows:
        return 0
    conn = get_connection()
    existing = conn.execute("SELECT count(*) FROM raw.merchant_transactions").fetchone()[0]
    if existing > 0:
        return existing
    for row in rows:
        conn.execute(
            "INSERT INTO raw.merchant_transactions (txn_id, merchant_id, amount, type, created_at) VALUES (?, ?, ?, ?, ?)",
            [row["txn_id"], row["merchant_id"], float(row["amount"]),
             row["type"], row.get("created_at", datetime.now(timezone.utc).isoformat())],
        )
    logger.info("seed_merchant_transactions_loaded", count=len(rows), source=file_path)
    return len(rows)


def get_table_count(schema: str, table: str) -> int:
    conn = get_connection()
    result = conn.execute(f"SELECT COUNT(*) FROM {schema}.{table}").fetchone()
    return result[0] if result else 0


def insert_enriched_feedback(data: dict) -> None:
    conn = get_connection()
    conn.execute(
        """
        INSERT INTO trusted.feedback_enriched
            (id, request_id, customer_id, product_id, feedback_text, category,
             summary, confidence, source_doc_ids, validation_status, enriched_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        [
            data["id"],
            data["request_id"],
            data["customer_id"],
            data["product_id"],
            data["feedback_text"],
            data["category"],
            data["summary"],
            data["confidence"],
            json.dumps(data.get("source_doc_ids", [])),
            data["validation_status"],
            datetime.now(timezone.utc).isoformat(),
        ],
    )


def insert_quarantine(data: dict) -> None:
    conn = get_connection()
    conn.execute(
        """
        INSERT INTO quarantine.llm_outputs
            (id, request_id, input_text, raw_output, validation_errors, quarantined_at)
        VALUES (?, ?, ?, ?, ?, ?)
        """,
        [
            data.get("id", 0),
            data["request_id"],
            data["input_text"],
            json.dumps(data["raw_output"]),
            json.dumps(data.get("validation_errors", [])),
            datetime.now(timezone.utc).isoformat(),
        ],
    )


def fetch_feedback(feedback_id: int) -> Optional[dict]:
    conn = get_connection()
    result = conn.execute(
        "SELECT id, customer_id, product_id, feedback_text, created_at FROM raw.feedback WHERE id = ?",
        [feedback_id],
    ).fetchone()
    if result is None:
        return None
    return {
        "id": result[0],
        "customer_id": result[1],
        "product_id": result[2],
        "feedback_text": result[3],
        "created_at": str(result[4]),
    }


def fetch_all_feedback(limit: int = 100) -> list[dict]:
    conn = get_connection()
    results = conn.execute(
        "SELECT id, customer_id, product_id, feedback_text, created_at FROM raw.feedback LIMIT ?",
        [limit],
    ).fetchall()
    return [
        {
            "id": r[0],
            "customer_id": r[1],
            "product_id": r[2],
            "feedback_text": r[3],
            "created_at": str(r[4]),
        }
        for r in results
    ]


def fetch_trusted_rows(limit: int = 3) -> list[dict]:
    """Return sample rows from trusted.feedback_enriched for on-screen proof."""
    conn = get_connection()
    results = conn.execute(
        """
        SELECT id, request_id, customer_id, product_id, category,
               confidence, source_doc_ids, validation_status, enriched_at
        FROM trusted.feedback_enriched
        ORDER BY enriched_at DESC
        LIMIT ?
        """,
        [limit],
    ).fetchall()
    return [
        {
            "id": r[0],
            "request_id": r[1],
            "customer_id": r[2],
            "product_id": r[3],
            "category": r[4],
            "confidence": r[5],
            "source_doc_ids": r[6],
            "validation_status": r[7],
            "enriched_at": str(r[8]),
        }
        for r in results
    ]


def fetch_quarantine_rows(limit: int = 3) -> list[dict]:
    """Return sample rows from quarantine.llm_outputs for on-screen proof."""
    conn = get_connection()
    results = conn.execute(
        """
        SELECT id, request_id, input_text, raw_output, validation_errors,
               quarantined_at
        FROM quarantine.llm_outputs
        ORDER BY quarantined_at DESC
        LIMIT ?
        """,
        [limit],
    ).fetchall()
    out: list[dict] = []
    for r in results:
        raw_output = r[3]
        validation_errors = r[4]
        if isinstance(raw_output, str):
            try:
                raw_output = json.loads(raw_output)
            except Exception:
                pass
        if isinstance(validation_errors, str):
            try:
                validation_errors = json.loads(validation_errors)
            except Exception:
                pass
        out.append({
            "id": r[0],
            "request_id": r[1],
            "input_text": r[2],
            "raw_output": raw_output,
            "validation_errors": validation_errors,
            "quarantined_at": str(r[5]),
        })
    return out


def customer_exists(customer_id: int) -> bool:
    conn = get_connection()
    result = conn.execute(
        "SELECT 1 FROM raw.feedback WHERE customer_id = ? "
        "UNION SELECT 1 FROM raw.orders WHERE customer_id = ? LIMIT 1",
        [customer_id, customer_id],
    ).fetchone()
    return result is not None


def product_exists(product_id: int) -> bool:
    conn = get_connection()
    result = conn.execute(
        "SELECT 1 FROM raw.feedback WHERE product_id = ? "
        "UNION SELECT 1 FROM raw.orders WHERE product_id = ? LIMIT 1",
        [product_id, product_id],
    ).fetchone()
    return result is not None
