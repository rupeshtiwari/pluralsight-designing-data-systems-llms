from pydantic import BaseModel, Field


class FeedbackEnrichRequest(BaseModel):
    feedback_id: int
    customer_id: int
    product_id: int
    feedback_text: str


class FeedbackEnrichResponse(BaseModel):
    request_id: str
    category: str
    summary: str
    confidence: float
    source_doc_ids: list[int]
    validation_status: str


class DisputeSummaryRequest(BaseModel):
    refund_id: int
    order_id: int
    reason: str
    customer_history: list[dict] = Field(default_factory=list)


class DisputeSummaryResponse(BaseModel):
    request_id: str
    summary: str
    risk_level: str
    key_factors: list[str]
    confidence: float
    source_doc_ids: list[int]


class AnomalyTriageRequest(BaseModel):
    incident_id: str
    metric_name: str
    expected_value: float
    actual_value: float
    context: dict = Field(default_factory=dict)


class AnomalyTriageResponse(BaseModel):
    incident_id: str
    severity: str
    root_cause_hypothesis: str
    recommended_action: str
    evidence_summary: str
    review_required: bool


class CatalogEnrichRequest(BaseModel):
    product_id: int
    raw_description: str
    existing_metadata: dict = Field(default_factory=dict)


class CatalogEnrichResponse(BaseModel):
    request_id: str
    enhanced_description: str
    extracted_attributes: dict
    confidence: float
    source_doc_ids: list[int]
    validation_status: str


class ValidationResult(BaseModel):
    is_valid: bool
    checks: dict
    errors: list[str] = Field(default_factory=list)


class AgentState(BaseModel):
    incident_id: str
    current_node: str
    evidence: list[dict] = Field(default_factory=list)
    decisions: list[dict] = Field(default_factory=list)
    tool_calls: list[dict] = Field(default_factory=list)
    review_required: bool = False


class BatchResult(BaseModel):
    batch_id: str
    total: int
    accepted: int
    rejected: int
    quarantined: int
    details: list[dict] = Field(default_factory=list)
