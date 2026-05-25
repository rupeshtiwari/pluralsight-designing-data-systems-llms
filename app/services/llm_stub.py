import hashlib
import re

import structlog

logger = structlog.get_logger(__name__)

CATEGORY_KEYWORDS: dict[str, list[str]] = {
    "product_quality": ["broken", "defective", "damaged", "poor quality", "faulty", "doesn't work", "not working"],
    "shipping_delay": ["late", "delayed", "slow shipping", "never arrived", "wrong address", "lost package"],
    "customer_service": ["rude", "unhelpful", "no response", "bad support", "ignored", "terrible service"],
    "pricing_concern": ["overpriced", "expensive", "price increase", "cheaper", "not worth", "overcharged"],
    "return_request": ["return", "refund", "exchange", "send back", "money back", "replacement"],
    "general_praise": ["great", "excellent", "amazing", "love it", "perfect", "highly recommend", "fantastic"],
}


def _classify_feedback(text: str) -> tuple[str, float]:
    text_lower = text.lower()
    best_category = "general_praise"
    best_score = 0.0

    for category, keywords in CATEGORY_KEYWORDS.items():
        matches = sum(1 for kw in keywords if kw in text_lower)
        if matches > best_score:
            best_score = matches
            best_category = category

    confidence = min(0.95, 0.6 + (best_score * 0.1))
    if best_score == 0:
        confidence = 0.5

    return best_category, round(confidence, 2)


def _summarize_text(text: str) -> str:
    sentences = re.split(r'[.!?]+', text.strip())
    sentences = [s.strip() for s in sentences if s.strip()]
    if not sentences:
        return "No content to summarize."
    key_phrase = sentences[0][:120]
    if len(sentences) > 1:
        return f"{key_phrase}. Customer also mentions: {sentences[1][:80].strip()}."
    return f"{key_phrase}."


def _triage_anomaly(expected: float, actual: float) -> tuple[str, str, str]:
    if expected == 0:
        deviation = abs(actual) * 100
    else:
        deviation = abs(actual - expected) / abs(expected) * 100

    if deviation >= 100:
        severity = "critical"
        hypothesis = "Severe deviation detected; possible system failure or data corruption."
        action = "Immediate investigation required. Escalate to on-call engineer."
    elif deviation >= 50:
        severity = "high"
        hypothesis = "Significant deviation suggests upstream data pipeline issue or config change."
        action = "Investigate upstream data sources and recent deployments."
    elif deviation >= 20:
        severity = "medium"
        hypothesis = "Moderate deviation may indicate seasonal variation or gradual drift."
        action = "Monitor trend over next 24 hours. Review recent changes."
    else:
        severity = "low"
        hypothesis = "Minor deviation within expected noise range."
        action = "Log for trend analysis. No immediate action needed."

    return severity, hypothesis, action


def _count_tokens(text: str) -> int:
    return len(text.split())


def generate(prompt: str, task: str = "classify", **kwargs) -> dict:
    if not prompt or not prompt.strip():
        logger.warning("llm_stub_empty_prompt", task=task)
        return {
            "response": {},
            "tokens": {"prompt": 0, "completion": 0, "total": 0},
            "model_info": {"name": "northwind-stub-v1", "version": "1.0", "stub": True},
        }

    prompt_tokens = _count_tokens(prompt)

    if task == "classify":
        category, confidence = _classify_feedback(prompt)
        summary = _summarize_text(prompt)
        response = {
            "category": category,
            "confidence": confidence,
            "summary": summary,
        }

    elif task == "summarize":
        summary = _summarize_text(prompt)
        response = {
            "summary": summary,
            "key_factors": [s.strip() for s in re.split(r'[.!?]+', prompt) if s.strip()][:3],
            "risk_level": "medium",
            "confidence": 0.82,
        }

    elif task == "triage":
        expected = kwargs.get("expected_value", 0.0)
        actual = kwargs.get("actual_value", 0.0)
        severity, hypothesis, action = _triage_anomaly(expected, actual)
        response = {
            "severity": severity,
            "root_cause_hypothesis": hypothesis,
            "recommended_action": action,
            "evidence_summary": f"Expected={expected}, Actual={actual}",
            "review_required": severity in ("high", "critical"),
        }

    elif task == "enrich_catalog":
        response = {
            "enhanced_description": f"Premium quality product. {_summarize_text(prompt)}",
            "extracted_attributes": {
                "keywords": list(set(re.findall(r'\b[a-z]{4,}\b', prompt.lower())))[:5],
                "word_count": len(prompt.split()),
            },
            "confidence": 0.85,
        }

    else:
        response = {"raw": _summarize_text(prompt)}

    completion_text = str(response)
    completion_tokens = _count_tokens(completion_text)

    logger.info("llm_stub_generate", task=task, prompt_tokens=prompt_tokens, completion_tokens=completion_tokens)

    return {
        "response": response,
        "tokens": {
            "prompt": prompt_tokens,
            "completion": completion_tokens,
            "total": prompt_tokens + completion_tokens,
        },
        "model_info": {"name": "northwind-stub-v1", "version": "1.0", "stub": True},
    }
