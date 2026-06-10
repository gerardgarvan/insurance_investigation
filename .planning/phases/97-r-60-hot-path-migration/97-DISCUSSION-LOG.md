# Phase 97: R/60 Hot-Path Migration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-10
**Phase:** 97-r-60-hot-path-migration
**Areas discussed:** Migration depth, Benchmarking method, Validation approach

---

## Migration Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Full script (Recommended) | Migrate all 3 sections: classify swap + frequency tables + same-day resolution. Avoids revisiting R/60 later. | ✓ |
| Hot path only | Migrate Section 2 (classify swap) + Section 4 (same-day resolution) only. Leave Section 3 frequency tables as dplyr. | |
| You decide | Claude's discretion based on implementation. | |

**User's choice:** Full script (Recommended)
**Notes:** No additional clarification needed. User agreed to migrate all sections since the file is already being touched.

---

## Benchmarking Method

| Option | Description | Selected |
|--------|-------------|----------|
| Embedded timing (initial proposal) | Add system.time() wrappers around each major section in R/60. Script logs timings every run. | |
| Dedicated benchmark script (Recommended) | Create R/97 benchmark script that runs old vs new side-by-side. One-time proof of speedup. | ✓ |
| Header comment only | Document timings as static comment in script header. No benchmark script. | |
| You decide | Claude's discretion. | |

**User's choice:** Dedicated benchmark script (Recommended)
**Notes:** User rejected the initial "embedded timing" proposal, pointing out that adding per-run timing overhead defeats the purpose of making the script faster. The benchmark is a one-time validation, not a recurring cost. Question was reformulated to remove the embedded timing option and the user selected the dedicated script approach.

---

## Validation Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Combined benchmark+validation script (Recommended) | R/97 benchmark script also diffs 12 CSV outputs. One script proves both speedup AND correctness. | ✓ |
| Separate validation script | R/97_validate_r60_parity.R checks CSV identity independently from benchmarking. | |
| Smoke test only | Rely on existing R/88 Section 15f. No dedicated validation. | |

**User's choice:** Combined benchmark+validation script (Recommended)
**Notes:** Follows Phase 95-96 pattern of dedicated validation but consolidates benchmark and parity checking into a single script.

---

## Claude's Discretion

- Internal data.table patterns (setkey placement, copy semantics, := vs functional style)
- Whether build_frequency_tables() stays as a function or gets inlined
- How the benchmark script structures old-vs-new comparison

## Deferred Ideas

None — discussion stayed within phase scope.
