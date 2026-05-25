from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent

DUCKDB_PATH: str = str(BASE_DIR / "data" / "northwind.duckdb")
POSTGRES_URL: str = "postgresql://northwind:northwind@localhost:5432/northwind"

LLM_STUB_MODE: bool = True
CONFIDENCE_THRESHOLD: float = 0.75
LOG_LEVEL: str = "INFO"

ALLOWED_CATEGORIES: list[str] = [
    "product_quality",
    "shipping_delay",
    "customer_service",
    "pricing_concern",
    "return_request",
    "general_praise",
]

ALLOWED_SEVERITIES: list[str] = [
    "low",
    "medium",
    "high",
    "critical",
]
