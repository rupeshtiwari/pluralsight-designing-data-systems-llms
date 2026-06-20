# Module 3 Clip 4 — Learning Objective coverage

Maps every demo step in `module3/README.md` to the Learning Objective
sub-elements the clip is approved to cover. Used to verify the demo
stays inside the approved scope.

## Approved LOs for Module 3 Clip 4

| LO | Description |
|----|-------------|
| 3a | Compare and contrast static DAGs with dynamic orchestration |
| 3b | Demonstrate the steps required to integrate LLM logic into orchestration tools |
| 3c | Trigger and monitor pipeline tasks that automate operations |
| 3d | Apply guardrails and validation so learners can ensure safe and reliable system behavior |

## Step-to-LO mapping

| Step | Title | LO | Proof emitted on screen |
|------|-------|----|-------------------------|
| 1 | Show the DAG topology | 3a | `GET /admin/airflow-dag` returns `dag_id`, `task count`, `static_tasks` (`extract_batch`, `transform`, `enrich_via_fastapi`) and `dynamic_branches` (`validation_branch`, `write_trusted`, `write_quarantine`) |
| 2 | Trigger the DAG from a new source batch | 3c | `POST /admin/airflow-trigger` returns `dag_run_id`, `state=queued`, `logical_date` |
| 3 | Watch state transitions | 3c | `GET /admin/airflow-dag-runs` returns run rows with `state` color-coded queued/running/success/failed plus `duration_seconds` |
| 4 | Inspect task log fields | 3b | `GET /admin/airflow-task-log` extracts `batch_id`, `request_id`, `validation_result`, `output_row_id` from the live `enrich_via_fastapi` task log |
| 5 | Show dispositions | 3d | `GET /admin/disposition-summary` returns `accepted_count`, `quarantined_count`, recent rows with `reason`, plus DuckDB row counts for `trusted.feedback_enriched` and `quarantine.llm_outputs` |
| 6 | Show the dynamic branch decision | 3a, 3d | `GET /admin/airflow-branch-decision` returns `branch_task=validation_branch`, `decision`, `downstream_taken`, `downstream_skipped` |

## Tech stack used in this clip

| Component | Where it is exercised |
|-----------|-----------------------|
| Apache Airflow | Real DAG `northwind_llm_enrichment` parsed by the scheduler, triggered via `POST /api/v1/dags/.../dagRuns`, runs queried via `/api/v1/dags/.../dagRuns`, task logs read via `/api/v1/.../taskInstances/.../logs/1` |
| FastAPI | Six new admin endpoints: `/admin/airflow-dag`, `/admin/airflow-trigger`, `/admin/airflow-dag-runs`, `/admin/airflow-task-log`, `/admin/airflow-branch-decision`, `/admin/disposition-summary` |
| DuckDB | `trusted.feedback_enriched` and `quarantine.llm_outputs` row counts surface in the disposition summary so the audit ties back to the warehouse |
| PostgreSQL | Airflow metadata store and the existing `llm_decisions` table both live in the same Postgres instance used by Modules 1 and 2 |
| Deterministic LLM stub | `enrich_via_fastapi` task calls `/enrich/feedback`, which uses the same stub the rest of the course relies on |
| Docker Compose | `apache/airflow:2.10.3-python3.12` webserver and scheduler services started alongside Postgres |

## Out-of-scope items (intentionally not in the demo)

- Live agent reasoning, open-ended LLM tool access, or unrestricted SQL — outline forbids these
- References to other clips — every step stands on its own
- Optional or "advanced" steps — every step in the README is required

## Verifying coverage

Run the preflight; the log at `module3/preflight_log.txt` ends with the LO
coverage block. If every check passes, the demo is aligned with the
outline as approved.

```bash
module3/scripts/preflight_check.sh
```
