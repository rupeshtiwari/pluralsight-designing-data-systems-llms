"""pgvector retrieval for NorthWind Markets reference documents.

Prefers real pgvector when Postgres is reachable. Embeddings are computed
locally with a deterministic SHA-256-based pseudo-embedding so no external
model or API key is required. Falls back to an in-memory list when PG is
unavailable so dev without Docker still works.

Reference documents are seeded from data/seed/reference_docs.json into the
real `reference_docs` table with a vector(384) column.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any

import structlog

log = structlog.get_logger(__name__)

EMBED_DIM = 384


def _hash_embed(text: str) -> list[float]:
    """Deterministic pseudo-embedding from SHA-256 of text. No external model."""
    h = hashlib.sha256(text.lower().encode("utf-8")).digest()
    # Expand 32 bytes into EMBED_DIM floats in [-1, 1]
    vec: list[float] = []
    for i in range(EMBED_DIM):
        b = h[i % len(h)]
        # Mix in position so the vector is not a repeating 32-byte pattern
        mix = (b ^ (i & 0xFF)) & 0xFF
        vec.append((mix / 127.5) - 1.0)
    return vec


def _vec_to_pg_literal(vec: list[float]) -> str:
    """pgvector accepts a string literal '[v1,v2,...]'."""
    return "[" + ",".join(f"{v:.6f}" for v in vec) + "]"


# Fallback in-memory store
_MEM_DOCS: list[dict[str, Any]] = []


async def _get_pg_pool() -> Any:
    from app.db import postgres as pg_module
    return await pg_module._get_pool()


async def seed_from_file(file_path: str) -> int:
    """Load reference_docs.json into the pgvector reference_docs table.

    Idempotent: skips docs whose doc_id already exists.
    Returns the total row count after seeding.
    """
    path = Path(file_path)
    if not path.exists():
        log.warning("pgvector.seed_file_missing", path=str(path))
        return _seed_in_memory(None)

    data = json.loads(path.read_text())
    docs = data if isinstance(data, list) else []
    if not docs:
        return 0

    pool = await _get_pg_pool()
    if pool is None:
        return _seed_in_memory(docs)

    inserted = 0
    try:
        async with pool.acquire() as conn:
            for doc in docs:
                doc_id = doc.get("id") or doc.get("doc_id")
                title = doc.get("title", "")
                content = doc.get("content", "")
                doc_type = doc.get("doc_type", "policy")
                source_url = doc.get("source_url", "")
                embedding = _vec_to_pg_literal(_hash_embed(f"{title}\n{content}"))
                result = await conn.execute(
                    """
                    INSERT INTO reference_docs
                      (doc_id, title, content, doc_type, source_url, embedding)
                    VALUES ($1, $2, $3, $4, $5, $6::vector)
                    ON CONFLICT (doc_id) DO NOTHING
                    """,
                    doc_id, title, content, doc_type, source_url, embedding,
                )
                if result.endswith(" 1"):
                    inserted += 1
            total = await conn.fetchval("SELECT count(*) FROM reference_docs")
        log.info("pgvector.seeded", inserted=inserted, total=total, backend="postgres")
        return int(total)
    except Exception as exc:  # noqa: BLE001
        log.warning("pgvector.seed_failed_fallback_memory", error=str(exc))
        return _seed_in_memory(docs)


def _seed_in_memory(docs: list[dict[str, Any]] | None) -> int:
    if docs is None:
        return len(_MEM_DOCS)
    if docs:
        _MEM_DOCS.clear()
        for doc in docs:
            _MEM_DOCS.append({
                "doc_id": doc.get("id") or doc.get("doc_id"),
                "title": doc.get("title", ""),
                "content": doc.get("content", ""),
                "doc_type": doc.get("doc_type", "policy"),
                "source_url": doc.get("source_url", ""),
            })
    log.info("pgvector.seeded", total=len(_MEM_DOCS), backend="memory")
    return len(_MEM_DOCS)


async def retrieve_similar_docs(
    query_text: str,
    *,
    top_k: int = 3,
    doc_type: str | None = None,
) -> list[dict[str, Any]]:
    """Return the top-k pgvector-similar reference documents.

    Filter rule: if doc_type is provided, match rows whose doc_type CONTAINS
    or IS CONTAINED BY the requested type (so 'policy' matches 'product_policy',
    'return_policy', etc.). Falls back to in-memory if PG unavailable.
    """
    pool = await _get_pg_pool()
    if pool is not None:
        try:
            query_vec = _vec_to_pg_literal(_hash_embed(query_text))
            async with pool.acquire() as conn:
                if doc_type:
                    rows = await conn.fetch(
                        """
                        SELECT doc_id, title, content, doc_type, source_url
                        FROM reference_docs
                        WHERE doc_type ILIKE '%' || $1 || '%'
                           OR $1 ILIKE '%' || doc_type || '%'
                        ORDER BY embedding <=> $2::vector
                        LIMIT $3
                        """,
                        doc_type, query_vec, top_k,
                    )
                else:
                    rows = await conn.fetch(
                        """
                        SELECT doc_id, title, content, doc_type, source_url
                        FROM reference_docs
                        ORDER BY embedding <=> $1::vector
                        LIMIT $2
                        """,
                        query_vec, top_k,
                    )
            return [dict(r) for r in rows]
        except Exception as exc:  # noqa: BLE001
            log.warning("pgvector.retrieve_failed_fallback_memory", error=str(exc))

    # Memory fallback (no real similarity — return matching doc_type or first top_k)
    pool_docs = _MEM_DOCS
    if doc_type:
        pool_docs = [d for d in _MEM_DOCS if doc_type in d["doc_type"] or d["doc_type"] in doc_type]
    return [dict(d) for d in pool_docs[:top_k]]


async def list_reference_docs(limit: int = 50) -> list[dict[str, Any]]:
    """Return all seeded reference docs (without embeddings) for /admin display."""
    pool = await _get_pg_pool()
    if pool is not None:
        try:
            async with pool.acquire() as conn:
                rows = await conn.fetch(
                    """
                    SELECT doc_id, title, doc_type, source_url,
                           (embedding IS NOT NULL) AS has_embedding,
                           length(content) AS content_length
                    FROM reference_docs
                    ORDER BY doc_id
                    LIMIT $1
                    """,
                    limit,
                )
            return [dict(r) for r in rows]
        except Exception as exc:  # noqa: BLE001
            log.warning("pgvector.list_failed_fallback_memory", error=str(exc))
    return [
        {
            "doc_id": d["doc_id"],
            "title": d["title"],
            "doc_type": d["doc_type"],
            "source_url": d.get("source_url", ""),
            "has_embedding": False,
            "content_length": len(d.get("content", "")),
        }
        for d in _MEM_DOCS[:limit]
    ]
