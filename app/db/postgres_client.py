import json
from contextlib import contextmanager
from typing import Generator, Optional

import psycopg2
import psycopg2.extras
import structlog

from app.config import POSTGRES_URL
from app.services.retrieval import pseudo_embed

logger = structlog.get_logger(__name__)

_connection: Optional[psycopg2.extensions.connection] = None


def get_connection() -> psycopg2.extensions.connection:
    global _connection
    if _connection is None or _connection.closed:
        _connection = psycopg2.connect(POSTGRES_URL)
        _connection.autocommit = True
        logger.info("postgres_connected")
    return _connection


def close_connection() -> None:
    global _connection
    if _connection is not None and not _connection.closed:
        _connection.close()
        _connection = None
        logger.info("postgres_disconnected")


@contextmanager
def cursor() -> Generator[psycopg2.extensions.cursor, None, None]:
    conn = get_connection()
    cur = conn.cursor()
    try:
        yield cur
        conn.commit()
    except Exception:
        conn.rollback()
        logger.exception("postgres_query_error")
        raise
    finally:
        cur.close()


def init_tables() -> None:
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute("CREATE EXTENSION IF NOT EXISTS vector")
        conn.commit()

    with conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS reference_docs (
                id SERIAL PRIMARY KEY,
                doc_type VARCHAR(100),
                title VARCHAR(500),
                content TEXT,
                embedding vector(384),
                source_url VARCHAR(1000),
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS llm_decisions (
                id SERIAL PRIMARY KEY,
                request_id VARCHAR(100),
                endpoint VARCHAR(200),
                input_hash VARCHAR(64),
                output_hash VARCHAR(64),
                category VARCHAR(100),
                confidence DOUBLE PRECISION,
                validation_status VARCHAR(50),
                decision TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS agent_tool_calls (
                id SERIAL PRIMARY KEY,
                incident_id VARCHAR(100),
                tool_name VARCHAR(200),
                input_hash VARCHAR(64),
                output_status VARCHAR(50),
                output_summary TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS agent_decisions (
                id SERIAL PRIMARY KEY,
                incident_id VARCHAR(100),
                severity VARCHAR(20),
                recommended_action TEXT,
                decision_reason TEXT,
                review_required BOOLEAN DEFAULT FALSE,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        cur.execute("""
            CREATE TABLE IF NOT EXISTS pipeline_runs (
                id SERIAL PRIMARY KEY,
                batch_id VARCHAR(100),
                dag_id VARCHAR(200),
                accepted_count INTEGER DEFAULT 0,
                rejected_count INTEGER DEFAULT 0,
                validation_summary JSONB,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)

        conn.commit()

    logger.info("postgres_tables_initialized")


SEED_REFERENCE_DOCS = [
    {
        "doc_type": "product_policy",
        "title": "Product Quality Standards",
        "content": "NorthWind Markets requires all vendors to meet quality standards. Products must pass inspection before listing. Defective items must be reported within 30 days of purchase.",
        "source_url": "https://docs.northwind.example/policies/product-quality",
    },
    {
        "doc_type": "return_policy",
        "title": "Return and Refund Policy",
        "content": "Customers may return products within 30 days of delivery for a full refund. Items must be in original condition. Refunds are processed within 5-7 business days.",
        "source_url": "https://docs.northwind.example/policies/returns",
    },
    {
        "doc_type": "merchant_guidelines",
        "title": "Merchant Onboarding Guidelines",
        "content": "New merchants must complete identity verification and agree to marketplace terms. Transaction fees are 2.5% per sale. Payouts occur weekly on Fridays.",
        "source_url": "https://docs.northwind.example/merchants/onboarding",
    },
    {
        "doc_type": "shipping_policy",
        "title": "Shipping and Delivery Standards",
        "content": "Standard shipping is 5-7 business days. Express shipping is 2-3 business days. Merchants must ship within 48 hours of order placement. Late shipments incur penalties.",
        "source_url": "https://docs.northwind.example/policies/shipping",
    },
    {
        "doc_type": "customer_service",
        "title": "Customer Service Escalation Procedures",
        "content": "Tier 1 agents handle general inquiries. Escalate to Tier 2 for refund disputes over $100. Tier 3 handles legal and compliance issues. Response SLA is 24 hours.",
        "source_url": "https://docs.northwind.example/support/escalation",
    },
    {
        "doc_type": "pricing_policy",
        "title": "Marketplace Pricing Guidelines",
        "content": "Vendors set their own prices but must not exceed MSRP by more than 20%. Price gouging during high-demand events is prohibited. Dynamic pricing must be disclosed.",
        "source_url": "https://docs.northwind.example/policies/pricing",
    },
]


def seed_reference_docs() -> int:
    conn = get_connection()
    count = 0

    with conn.cursor() as cur:
        cur.execute("SELECT COUNT(*) FROM reference_docs")
        existing = cur.fetchone()[0]
        if existing > 0:
            logger.info("reference_docs_already_seeded", count=existing)
            return existing

        for doc in SEED_REFERENCE_DOCS:
            embedding = pseudo_embed(doc["content"])
            vector_literal = "[" + ",".join(f"{v:.6f}" for v in embedding) + "]"
            cur.execute(
                """
                INSERT INTO reference_docs (doc_type, title, content, embedding, source_url)
                VALUES (%s, %s, %s, %s::vector, %s)
                """,
                (doc["doc_type"], doc["title"], doc["content"], vector_literal, doc["source_url"]),
            )
            count += 1

        conn.commit()

    logger.info("reference_docs_seeded", count=count)
    return count


def insert_llm_decision(data: dict) -> None:
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO llm_decisions (request_id, endpoint, input_hash, output_hash, category, confidence, validation_status, decision)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                data["request_id"],
                data["endpoint"],
                data["input_hash"],
                data["output_hash"],
                data.get("category"),
                data.get("confidence"),
                data.get("validation_status"),
                json.dumps(data.get("decision", {})),
            ),
        )
        conn.commit()


def insert_agent_tool_call(data: dict) -> None:
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO agent_tool_calls (incident_id, tool_name, input_hash, output_status, output_summary)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (
                data["incident_id"],
                data["tool_name"],
                data["input_hash"],
                data["output_status"],
                data.get("output_summary", ""),
            ),
        )
        conn.commit()


def insert_agent_decision(data: dict) -> None:
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO agent_decisions (incident_id, severity, recommended_action, decision_reason, review_required)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (
                data["incident_id"],
                data["severity"],
                data["recommended_action"],
                data["decision_reason"],
                data.get("review_required", False),
            ),
        )
        conn.commit()


def insert_pipeline_run(data: dict) -> None:
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO pipeline_runs (batch_id, dag_id, accepted_count, rejected_count, validation_summary)
            VALUES (%s, %s, %s, %s, %s)
            """,
            (
                data["batch_id"],
                data["dag_id"],
                data.get("accepted_count", 0),
                data.get("rejected_count", 0),
                json.dumps(data.get("validation_summary", {})),
            ),
        )
        conn.commit()


def get_reference_doc_ids() -> list[int]:
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute("SELECT id FROM reference_docs ORDER BY id")
        return [row[0] for row in cur.fetchall()]


def get_reference_doc(doc_id: int) -> Optional[dict]:
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute("SELECT id, doc_type, title, content, source_url FROM reference_docs WHERE id = %s", (doc_id,))
        row = cur.fetchone()
        if row is None:
            return None
        return {
            "id": row[0],
            "doc_type": row[1],
            "title": row[2],
            "content": row[3],
            "source_url": row[4],
        }


def get_table_count(table: str) -> int:
    conn = get_connection()
    with conn.cursor() as cur:
        cur.execute(f"SELECT COUNT(*) FROM {table}")
        result = cur.fetchone()
        return result[0] if result else 0
