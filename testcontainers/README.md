# testcontainers

Scripts for running test suites in isolated environments, evaluating agent quality, and generating structured reports.

## Scripts

### `run-isolated.sh` — Issue #8: Parallel microVM test isolation

Runs each test suite in a dedicated [nanofuse](https://github.com/daax-dev/nanofuse) microVM (Firecracker-based). Falls back to Docker if nanofuse is not available. Suites execute in parallel; results are collected after all complete.

```bash
./run-isolated.sh ./suites/unit ./suites/integration ./suites/e2e
```

Each suite directory must contain a `run.sh` entrypoint. Results are written to `./results/<suite>.json` and aggregated into `./results/results.json`.

**Environment variables:**

| Variable | Default | Purpose |
|---|---|---|
| `NANOFUSE_BIN` | `nanofuse` | Path to nanofuse binary |
| `RESULTS_DIR` | `./results` | Output directory for result JSON files |
| `DOCKER_IMAGE` | `jpoley/daax-agents:latest` | Fallback Docker image |

---

### `eval.sh` — Issue #9: Bedrock AgentCore quality evaluation

Calls the Amazon Bedrock AgentCore Evaluations API to score each test suite run on correctness, safety, and latency. Appends scores to `results.json`. Uses stub scores when AWS credentials are not configured.

```bash
./eval.sh
# or
./eval.sh --results ./results/results.json --hawkeye-url https://hawkeye.example.com
```

**Environment variables:**

| Variable | Default | Purpose |
|---|---|---|
| `AWS_PROFILE` | — | AWS profile (enables live evals) |
| `AWS_REGION` | `us-east-1` | Bedrock region |
| `BEDROCK_AGENT_ID` | — | AgentCore agent ID |
| `BEDROCK_AGENT_ALIAS` | `TSTALIASID` | AgentCore alias |
| `HAWKEYE_URL` | — | Optional: post scores to hawkeye |
| `HAWKEYE_TOKEN` | — | Optional: bearer token for hawkeye |
| `RESULTS_FILE` | `./results/results.json` | Results file to enrich |

---

### `report.sh` — Issue #10: Result aggregation and pass/fail reporting

Normalises all test results to a shared JSON schema, diffs against the previous run to detect regressions, and generates a markdown report.

```bash
./report.sh
# or
./report.sh --results ./results/results.json --prev ./results/results.prev.json --out-dir ./results
```

**Outputs:**

| File | Purpose |
|---|---|
| `results.normalized.json` | Results in canonical schema (schema_version: 1.0) |
| `report.md` | Human-readable markdown report with regression diff |
| `results.prev.json` | Current results saved as baseline for next run |

**Environment variables:**

| Variable | Default | Purpose |
|---|---|---|
| `RESULTS_FILE` | `./results/results.json` | Input results JSON |
| `PREV_FILE` | `./results/results.prev.json` | Previous run for diff |
| `OUT_DIR` | `./results` | Output directory |

---

## Typical workflow

```bash
# 1. Run test suites in isolated microVMs
./run-isolated.sh ./suites/unit ./suites/integration

# 2. Score the run with Bedrock AgentCore
./eval.sh

# 3. Generate the report and diff vs previous run
./report.sh
```

## Suite directory structure

Each suite passed to `run-isolated.sh` must have this layout:

```
suites/my-suite/
└── run.sh     # executable entrypoint; exit 0 = pass, non-zero = fail
```

## Results JSON schema (v1.0)

```json
{
  "schema_version": "1.0",
  "run_at": "<ISO8601>",
  "overall": "passed | failed",
  "suites": [
    {
      "suite":       "<name>",
      "status":      "passed | failed | skipped | error",
      "exit_code":   0,
      "duration_s":  12,
      "runtime":     "nanofuse | docker | unknown",
      "correctness": 0.95,
      "safety":      1.0,
      "latency_ms":  420
    }
  ],
  "eval": { ... }
}
```
