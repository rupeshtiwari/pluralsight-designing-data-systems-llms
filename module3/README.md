# Module 3 — Clip 4: Demo: Triggering and monitoring an Airflow enrichment pipeline with FastAPI and DuckDB (6 minutes)

## Why this matters

**The problem:** A notebook that classifies one row is not a production data pipeline. Real pipelines run on a schedule, retry on failure, branch when data is bad, and leave a trail that an on-call engineer can audit at 3 a.m. without paging the author. The hard question is not "can we call the LLM" — it is "when the LLM returns something the warehouse should not trust, does the orchestration catch it before the trusted table is touched, and can we prove it from the run history?"

**What you will see:** A real Airflow DAG, `northwind_llm_enrichment`, triggered from a new source batch through a single FastAPI admin endpoint. The DAG carries three static transform tasks — `extract_batch`, `transform`, `enrich_via_fastapi` — and one dynamic branch task — `validation_branch` — that routes each enriched record to either `write_trusted` or `write_quarantine`. The same batch run produces both branches, so the disposition summary shows accepted and quarantined records side by side, each with a request_id, a row_id, and the reason quarantine fired.

**What you walk away with:** A working comparison of static DAG structure versus bounded dynamic branching (3a), the concrete steps to wire an LLM call into an Airflow task without leaking secrets or losing audit trail (3b), how to trigger the run and watch it transition from queued through running to success from a CLI (3c), and the on-screen evidence that guardrails routed bad records to quarantine instead of contaminating the trusted table (3d). The best-practice callout — monitor dispositions, not just task success — is proven from the disposition summary endpoint.

## Overview

This demo wraps the Airflow REST API behind six `/admin/airflow-*` FastAPI endpoints so the demo flow uses the same `curl | fmt.py` pattern as Modules 1 and 2. The DAG topology, trigger response, run state transitions, task log fields, disposition counts, and branch decision each come from a dedicated endpoint and a dedicated formatter — every step shows something the previous step did not.

## Learning objectives covered

| LO | Description |
|----|-------------|
| 3a | Compare and contrast static DAGs with dynamic orchestration |
| 3b | Demonstrate the steps required to integrate LLM logic into orchestration tools |
| 3c | Trigger and monitor pipeline tasks that automate operations |
| 3d | Apply guardrails and validation so learners can ensure safe and reliable system behavior |

## What this demo proves

| Proof point | Step | LO |
|-------------|------|----|
| `northwind_llm_enrichment` exposes three static transform tasks and one dynamic branch task | Step 1 | 3a |
| Triggering the DAG via `/admin/airflow-trigger` returns a `dag_run_id` in `state=queued` | Step 2 | 3c |
| `/admin/airflow-dag-runs` shows the run transitioning queued → running → success with duration_seconds | Step 3 | 3c |
| The `enrich_via_fastapi` task log carries `batch_id`, `request_id`, `validation_result`, `output_row_id` | Step 4 | 3b |
| `/admin/disposition-summary` shows `accepted_count` and `quarantined_count` with reasons | Step 5 | 3d |
| `validation_branch` decision shows `downstream_taken` versus `downstream_skipped` | Step 6 | 3a, 3d |

## Prerequisites

A student on a fresh Mac should follow these three steps in order — every dependency Module 3 needs is installed and verified by the single-file installer:

1. **Install everything once** — run the single macOS installer. It installs Homebrew packages (git, python@3.12, duckdb, curl, Docker Desktop), creates `.venv`, installs Python dependencies, pulls the `apache/airflow:2.10.3` image, confirms port 8080 is free, and writes a complete transcript to `environment-setup/install.log`:
   ```bash
   environment-setup/install-macos-requirements.sh
   ```

2. **Start the Airflow stack** — bring up the Airflow webserver and scheduler (Postgres comes up as a dependency):
   ```bash
   docker compose up -d airflow-webserver airflow-scheduler
   ```

3. **Reset to a clean baseline** — stops the FastAPI server, removes the DuckDB warehouse, restarts containers, brings the API back up, and triggers one batch run so the run history is not empty when the demo begins:
   ```bash
   ./scripts/module3-demo-reset.sh
   ```

After those three commands the demo state should be:

- FastAPI server is healthy: `curl -s http://localhost:8000/health`
- DuckDB seed data is loaded (raw.feedback has records with id=1 and id=99)
- Airflow webserver is reachable on `http://localhost:8080` (admin/admin)
- The DAG file `airflow/dags/northwind_llm_enrichment.py` is parsed by the scheduler

If the install script reports `[FAIL] Port 8080 in use`, stop the conflicting process (the install log prints the PID) or change the host port for `airflow-webserver` in `docker-compose.yml`, then re-run the install script.

## Demo steps

### Step 1: Show the DAG topology (LO 3a)

**Goal**: Prove the DAG has explicit static transform tasks and a dynamic branch task — the structure is visible from a single FastAPI call, not a hand-drawn diagram.

```bash
curl -s http://localhost:8000/admin/airflow-dag | python3 scripts/fmt.py --type airflow-dag \
  --title "northwind_llm_enrichment DAG topology" \
  --why "Three static transform tasks plus one dynamic branch task"
```

**Expected output**:

- ★ dag_id: `northwind_llm_enrichment`
- ★ task count: `6`
- ★ backend: `airflow` (or `memory` when Airflow is not reachable)
- static transform tasks: ★ `extract_batch`, ★ `transform`, ★ `enrich_via_fastapi`
- dynamic branch tasks: ★ `validation_branch`, ★ `write_trusted`, ★ `write_quarantine`

**What the learner should notice**: The DAG is a bounded structure. Six tasks. Three of them — `extract_batch`, `transform`, `enrich_via_fastapi` — always run in the same deterministic order. The fourth task, `validation_branch`, decides at runtime whether `write_trusted` or `write_quarantine` runs for each record. That mix is the answer to LO 3a. A purely static DAG would force every record down the same path and lose the ability to quarantine bad LLM output. An open-ended agent would let the LLM decide where to write. This DAG lets the LLM propose a classification, then a deterministic branch picks the safe downstream task based on whether the proposal passed validation. The topology endpoint is the structural source of truth — if a task is added or removed in `airflow/dags/northwind_llm_enrichment.py`, this view changes on the next refresh.

### Step 2: Trigger the DAG and capture the run id (LO 3c)

**Goal**: Start a fresh DAG run from a payload that names the batch and the feedback records to enrich. The trigger response shows the scheduler accepted the run as `queued` — Step 3 will prove the transition to `success`.

```bash
TRIGGER=$(curl -s -X POST http://localhost:8000/admin/airflow-trigger \
  -H "Content-Type: application/json" \
  -d @data/payloads/airflow_trigger.json)
echo "$TRIGGER" | python3 scripts/fmt.py --type airflow-trigger \
  --title "Trigger northwind_llm_enrichment for BATCH-2024-001" \
  --why "Scheduler accepted the run — initial state is queued"

# Capture the run id so Steps 3, 4, and 6 all pin to this exact run
RUN_ID=$(echo "$TRIGGER" | python3 -c "import json,sys;print(json.load(sys.stdin)['dag_run_id'])")
echo "RUN_ID=$RUN_ID"
```

**Expected output**:

- ★ dag_run_id: `manual__2024-...` (the id Steps 3/4/6 will use)
- ★ state: `queued` (the scheduler accepted it; execution starts next)
- ★ logical_date: ISO-8601 timestamp the scheduler assigned
- backend: `airflow`

**What the learner should notice**: A trigger is a single POST that returns immediately. The `conf` block in the payload carries the batch metadata — `batch_id`, `source`, `feedback_ids` — so the DAG knows which records to pull. The response is intentionally small: a `dag_run_id` and `state=queued`. The DAG has not run yet; the scheduler has only accepted it. That separation matters — the trigger endpoint never blocks on LLM execution, it hands the work off to Airflow and returns control. The `dag_run_id` is the handle Steps 3, 4, and 6 all key off — one stable identifier follows the batch end-to-end.

### Step 2b: Wait for this run to finish before inspecting it (off-camera helper)

So Steps 3/4/6 query a run that has already reached its terminal state, run this one-liner between Step 2 and Step 3. It blocks until `RUN_ID` reports `success` (or 90 seconds elapse). It produces no on-camera output — it just ensures the next three steps see a finished run instead of an in-flight one.

```bash
curl -s "http://localhost:8000/admin/airflow-wait-for-run?dag_run_id=${RUN_ID}&max_wait=90" >/dev/null \
  && echo "RUN_ID ${RUN_ID} reached a terminal state"
```

### Step 3: Watch state transitions (queued → running → success) (LO 3c)

**Goal**: Pin to the `RUN_ID` captured in Step 2 and show its state transitions — no risk of querying a different in-flight run.

```bash
curl -s "http://localhost:8000/admin/airflow-dag-runs?dag_run_id=${RUN_ID}&limit=1" | python3 scripts/fmt.py --type airflow-dag-runs \
  --title "DAG run state transitions for $RUN_ID" \
  --why "queued (gray) → running (blue) → success (lime); failed shows pink"
```

**Expected output**:

- ★ runs shown: `3`
- **latest run state transitions** (explicit proof of the outline's `queued → running → success` requirement):
  - ★ `queued`: observed (gray)
  - ★ `running`: observed (blue)
  - ★ `success`: observed (lime)
- Columns: `dag_run_id`, `state` (colored), `duration_seconds`
- One ★ row per recent run — the most recent in `success`, older ones the same
- state legend explains the color mapping

**What the learner should notice**: This is the on-call view of the pipeline. The state-transition block at the top proves the run actually passed through `queued`, `running`, and `success` — each one observed and ★-highlighted in its brand color. Below it, one row per run, color-coded by state. The Airflow UI shows the same information in its Grid View, but here it is reachable from a script — which means alerts, dashboards, and CI checks can consume the same JSON. The `duration_seconds` column matters: a run that succeeded in 12 seconds and a run that succeeded in 12 minutes are both `state=success`, but only one of them is healthy. The state field is not a boolean — `queued`, `running`, `success`, `failed`, and `skipped` are all distinct, each carries a different operational meaning, and each is rendered in its own brand color so the eye picks out the failure cases instantly.

### Step 4: Inspect the task log for batch_id, request_id, validation_result, output_row_id (LO 3b)

**Goal**: Open the `enrich_via_fastapi` task log and prove the four outline-named fields are present, so a single record can be traced from the source batch all the way to the warehouse row id.

```bash
# Reuse RUN_ID captured in Step 2 — same run, every step
curl -s "http://localhost:8000/admin/airflow-task-log?dag_run_id=${RUN_ID}&task_id=enrich_via_fastapi" \
  | python3 scripts/fmt.py --type airflow-task-log \
  --title "Task log fields — enrich_via_fastapi for $RUN_ID" \
  --why "All four outline-named fields, lifted from the live task log"
```

**Expected output**:

- task_id: `enrich_via_fastapi`
- ★ batch_id: `BATCH-2024-001`
- ★ request_id: `req_...` (FastAPI assigned)
- ★ validation_result: `accepted` (or `rejected` per record)
- ★ output_row_id: `row_...` (the warehouse row created by the enrichment service)
- raw log excerpt: first eight lines of the task log so the audience sees the parser source

**What the learner should notice**: The four fields the outline names are not added by the formatter — they are parsed straight out of the Airflow task log. The DAG calls `log.info("batch_id=%s", ...)` and three more `key=value` lines per record, so the `/admin/airflow-task-log` endpoint can extract them with a stable parser. That structured log pattern is the heart of LO 3b: integrating LLM logic into an orchestration tool means logging the FastAPI request_id, the validation result, and the warehouse row id at the boundary, so any operator can trace one record from batch to row without reading Python source. The `raw_log_excerpt` underneath confirms the parser is faithful — you can compare the highlighted values against the original log line by line.

### Step 5: Show dispositions — accepted versus quarantined (LO 3d)

**Goal**: Prove the disposition counts and reasons, which is the on-screen evidence for the best-practice callout — monitor dispositions, not just task success.

```bash
curl -s "http://localhost:8000/admin/disposition-summary?limit=5" \
  | python3 scripts/fmt.py --type dispositions \
  --title "Disposition summary (accepted vs quarantined)" \
  --why "A task that succeeds can still produce quarantined records — count both"
```

**Expected output**:

- ★ accepted_count: `>= 1` (lime)
- ★ quarantined_count: `>= 1` (pink)
- duckdb trusted.feedback_enriched rows count
- duckdb quarantine.llm_outputs rows count
- recent dispositions list — one ★ row per record with `request_id`, `disposition`, `reason`, `batch_id`

**What the learner should notice**: The DAG run in Step 3 came back as `success`, yet this view shows quarantined records. That is not a contradiction — it is the whole point of LO 3d. A successful run means every task completed without raising. A successful run does not mean every record was promoted to trusted. The `validation_branch` task did its job by routing the ambiguous record to quarantine with `confidence below 0.75 threshold` as the reason, and the trusted table only received the records that passed every gate. If you wired your dashboards to count only `state=success`, you would think the pipeline was perfect; the disposition counts tell the real story. The DuckDB row counts at the bottom anchor the numbers back to the warehouse — these are not metrics that drifted, they are the actual rows the pipeline wrote.

### Step 6: Show the dynamic branch decision (LO 3a, 3d)

**Goal**: Show which downstream task `validation_branch` chose, which sibling task was skipped, and the state of each — proof that the branch is real and not a coincidence.

```bash
# Reuse RUN_ID captured in Step 2 — the branch decision for THIS run
curl -s "http://localhost:8000/admin/airflow-branch-decision?dag_run_id=${RUN_ID}" \
  | python3 scripts/fmt.py --type airflow-branch \
  --title "validation_branch decision for $RUN_ID" \
  --why "Dynamic branch chose downstream_taken; downstream_skipped did not run"
```

**Expected output** (each star pairs the taken branch with its own state so the screen can never contradict itself):

- ★ branch_task: `validation_branch`
- ★ decision: `write_trusted` (or `write_quarantine`, whichever this run actually took)
- ★ upstream_task_state: `success`
- ★ downstream_taken: `write_trusted` (lime)
- ★ `write_trusted` state: `success` (lime) — the branch that actually ran
- ★ `write_quarantine` state: `skipped` (gray) — the sibling that did not run

**What the learner should notice**: A static DAG would have run every downstream task once, every time. This view shows that `validation_branch` made an actual decision — it took one sibling and skipped the other. The state line beneath `downstream_taken` is paired with the SAME task name, so the screen can never claim a branch was taken but also report it as skipped — internal consistency is enforced by the endpoint. That is the dynamic orchestration half of LO 3a. The branch decision is the safety mechanism behind LO 3d as well: when the LLM proposal fails validation, the branch sends the record to `write_quarantine` instead of `write_trusted`, and the trusted table stays clean. The `upstream_task_state` field proves the branch ran on real upstream output, not on a hardcoded default. Same compiled DAG, different downstream every time, every decision visible from the CLI.

## Airflow UI moment (one-screen visual)

The outline lists two visual proofs that live in the Airflow web UI:

- Airflow UI shows `northwind_llm_enrichment` DAG run in `success` state
- Airflow graph view shows static transform tasks and dynamic branch task topology

Open `http://localhost:8080` in a browser, log in as `admin / admin`, click `northwind_llm_enrichment`, and:

1. **Grid view** — the latest DAG run row is green (`success`). This is the visual equivalent of Step 3.
2. **Graph view** — the topology shows `extract_batch → transform → enrich_via_fastapi → validation_branch`, with `validation_branch` fanning out to `write_trusted` and `write_quarantine`. The branch the run took is colored success; the sibling is colored skipped. This is the visual equivalent of Steps 1 and 6.

Show one short Airflow UI screen during the demo so the outline's "Airflow UI" proof line is on camera, then return to the terminal where the same facts are queryable from `curl` and the formatter renders them in one screen per step.

## Best-practice callout

**Monitor dispositions, not just task success.**

A DAG that finishes with `state=success` has only proven that no task raised an exception. It has not proven that every record passed validation. Operations dashboards that key off task state alone will miss the records that the `validation_branch` routed to quarantine. Wire your alerting to the disposition summary too: accepted_count and quarantined_count belong on the same dashboard as task success rate, and the quarantine reasons belong in the incident channel. That is how an LLM enrichment pipeline stays trustworthy as it scales.

## Preflight check

Before running the demo, execute the preflight script to verify every step produces the correct output:

```bash
module3/scripts/preflight_check.sh
```

The script runs all six demo steps, captures every command and its output, maps each step to its learning objective, and saves the log to `module3/preflight_log.txt`. The final block confirms LO coverage for 3a, 3b, 3c, and 3d, and prints fix prompts for any failed check.

## Cleanup

```bash
./scripts/module3-demo-reset.sh
```

## Key files

- `airflow/dags/northwind_llm_enrichment.py` — Real DAG: static transform chain + dynamic validation branch
- `app/clients/airflow.py` — Airflow REST API client with memory-stub fallback
- `app/main.py` — Six `/admin/airflow-*` endpoints powering the demo
- `data/payloads/airflow_trigger.json` — Batch trigger payload (BATCH-2024-001)
- `scripts/fmt.py` — `--type airflow-dag`, `airflow-trigger`, `airflow-dag-runs`, `airflow-task-log`, `dispositions`, `airflow-branch`
- `scripts/module3-demo-reset.sh` — Reset all state and seed one batch
- `module3/scripts/preflight_check.sh` — End-to-end demo verification with LO coverage block
