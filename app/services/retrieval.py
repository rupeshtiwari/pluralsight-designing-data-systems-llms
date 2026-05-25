import hashlib
from typing import Optional

import structlog

from app.db.postgres_client import get_connection

logger = structlog.get_logger(__name__)

EMBEDDING_DIM = 384


def pseudo_embed(text: str) -> list[float]:
    digest = hashlib.sha384(text.encode("utf-8")).digest()
    raw = [b / 255.0 for b in digest]

    chunks = []
    full_rounds = EMBEDDING_DIM // len(raw)
    remainder = EMBEDDING_DIM % len(raw)

    for i in range(full_rounds):
        salt = hashlib.sha384(f"{text}::{i}".encode("utf-8")).digest()
        chunks.extend([b / 255.0 for b in salt])
    if remainder:
        salt = hashlib.sha384(f"{text}::{full_rounds}".encode("utf-8")).digest()
        chunks.extend([b / 255.0 for b in salt[:remainder]])

    norm = sum(v * v for v in chunks) ** 0.5
    if norm > 0:
        chunks = [v / norm for v in chunks]

    return chunks


def search_reference_docs(
    query: str,
    doc_type: Optional[str] = None,
    top_k: int = 3,
) -> list[dict]:
    embedding = pseudo_embed(query)
    vector_literal = "[" + ",".join(f"{v:.6f}" for v in embedding) + "]"

    where_clause = ""
    params: list = []
    if doc_type:
        where_clause = "WHERE doc_type = %s"
        params.append(doc_type)

    sql = f"""
        SELECT id, doc_type, title, content,
               1 - (embedding <=> %s::vector) AS relevance
        FROM reference_docs
        {where_clause}
        ORDER BY embedding <=> %s::vector
        LIMIT %s
    """
    params = [vector_literal] + params + [vector_literal, top_k]

    try:
        conn = get_connection()
        with conn.cursor() as cur:
            if doc_type:
                cur.execute(
                    f"""
                    SELECT id, doc_type, title, content,
                           1 - (embedding <=> %s::vector) AS relevance
                    FROM reference_docs
                    WHERE doc_type = %s
                    ORDER BY embedding <=> %s::vector
                    LIMIT %s
                    """,
                    (vector_literal, doc_type, vector_literal, top_k),
                )
            else:
                cur.execute(
                    """
                    SELECT id, doc_type, title, content,
                           1 - (embedding <=> %s::vector) AS relevance
                    FROM reference_docs
                    ORDER BY embedding <=> %s::vector
                    LIMIT %s
                    """,
                    (vector_literal, vector_literal, top_k),
                )
            rows = cur.fetchall()

        results = []
        for row in rows:
            results.append({
                "id": row[0],
                "doc_type": row[1],
                "title": row[2],
                "content": row[3][:200],
                "relevance": round(float(row[4]), 4),
            })

        logger.info("retrieval_search", query_length=len(query), doc_type=doc_type, results_count=len(results))
        return results

    except Exception:
        logger.exception("retrieval_search_failed")
        return []
