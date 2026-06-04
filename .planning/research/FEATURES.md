# Feature Landscape: Local Testing Infrastructure for R Clinical Data Pipelines

**Domain:** Local testing infrastructure for R data pipelines (clinical research, PCORnet CDM)
**Researched:** 2026-06-03
**Context:** Adding local testing capability to existing 75+ script pipeline with DuckDB backend

## Table Stakes

Features users expect. Missing = product feels incomplete.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Environment auto-detection | Can't manually configure every script — detection must be automatic and reliable | Low | `Sys.info()["nodename"]` + env var override pattern is standard R practice |
| Path abstraction layer | Hard-coded paths break immediately on different systems | Low | `here` package already in stack (STACK.md); extend R/00_config.R CONFIG list |
| Minimal test fixtures (~20 patients) | Can't test clinical edge cases without data; production data too large/sensitive for local dev | Medium | Hand-crafted CSVs covering known edge cases (dual-eligible, NLPHL, SCT, multiple cancers, orphan dx) |
| DuckDB ingest works with fixtures | Existing R/03 ingest script must handle fixture CSVs without modification | Low | DuckDB ingest already generic; just needs fixture path in CONFIG |
| Existing smoke test (R/88) runs locally | 28-section structural validation must work against fixtures to verify pipeline logic | Medium | Smoke test validates structure + basic row counts; needs fixture-aware assertions |
| Local output directory | Can't write to `/blue/erin.mobley-hl.bcu/` on Windows — need local equivalent | Low | Extend CONFIG with local-specific output/cache/duckdb paths |

## Differentiators

Features that set product apart. Not expected, but valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Fixture generation script (R/fixtures/) | Reproducible fixture creation with documented clinical edge cases | Low | R script that builds CSVs with glue() for readability; versionable in git |
| Clinical edge case coverage matrix | Explicit documentation of which patients cover which edge cases | Low | Markdown table: patient 001 = dual-eligible + NLPHL, 002 = SCT + post-death activity, etc. |
| Validation report comparing fixture → production | Confidence that local tests predict production behavior | Medium | After fixture run, compare structure/distributions to production run artifacts |
| Environment-specific tuning (threads, memory) | Local = 4 threads, HiPerGator = 16 threads; auto-configured | Low | CONFIG$performance$num_threads based on environment detection |
| Fast feedback loop (<2 min end-to-end) | Instant validation vs 10+ min production run on HPC | Medium (depends on fixture size) | DuckDB in-memory mode + 20-patient fixtures should be <2 min |
| Git-tracked fixture CSVs | Version control for test data; fixture evolution visible in diffs | Low | CSVs are text; ~20 patients = manageable file sizes (<1MB per table likely) |
| Seed data helper functions | `generate_enrollment()`, `generate_diagnosis()` with realistic defaults | Medium | Reduces fixture script boilerplate; ensures PCORnet CDM column consistency |

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| Full synthetic data generation (Synthea, etc.) | Over-engineered for v1; hard to guarantee specific edge cases appear in synthetic cohort | Hand-craft 20 patients with documented edge cases |
| testthat formal unit test suite | Pipeline is exploratory analysis, not package; smoke test pattern already works | Extend existing R/88 smoke test with fixture-aware checks |
| Docker/containerization for local env | Adds complexity without proportional value; R + DuckDB install easily on Windows | Document install steps; rely on renv for package reproducibility |
| Automatic fixture refresh from production | HIPAA risk (PHI leakage), complexity of safe sampling/anonymization outweighs benefit | Manual fixture updates when new edge cases discovered |
| Mocking external dependencies | No external APIs/services in pipeline (all local CSV → DuckDB) | Not applicable; skip mocking infrastructure entirely |
| Multi-environment CI/CD testing | Not shipping software; exploratory pipeline for single research team | Local + HiPerGator only; no CI/CD infrastructure needed |
| Data masking/anonymization tooling | Fixtures are hand-crafted fictional patients, not derived from real PHI | Use obviously fake patient IDs (PT001, PT002), synthetic names if needed |

## Feature Dependencies

```
Environment auto-detection → Path abstraction (detection must precede path selection)
Path abstraction → Local output directory (paths depend on environment)
Minimal test fixtures → Fixture generation script (fixtures need creation tooling)
DuckDB ingest works with fixtures → Path abstraction (ingest reads from CONFIG paths)
Smoke test runs locally → DuckDB ingest works with fixtures (smoke test needs data loaded)
Clinical edge case coverage matrix → Minimal test fixtures (documents what fixtures contain)
```

## MVP Recommendation

**Prioritize (must-have for basic local testing):**
1. Environment auto-detection (foundational for all other features)
2. Path abstraction layer in R/00_config.R
3. Local output/cache/DuckDB paths
4. Minimal test fixtures (hand-crafted CSVs, 20 patients, 5-7 edge cases)
5. DuckDB ingest compatibility with fixtures
6. R/88 smoke test runs locally with fixture-aware assertions

**Defer to v2.3 or later:**
- Fixture generation script (can hand-edit CSVs for v2.2, script for maintainability later)
- Clinical edge case coverage matrix (implicit in v2.2, formalize when fixtures stabilize)
- Validation report comparing fixture → production (valuable but not blocking)
- Seed data helper functions (only if fixture generation becomes painful)
- Git-tracked fixture CSVs (YES track them, but not a feature — just normal workflow)
- Environment-specific tuning (start with safe defaults, optimize later if needed)
- Fast feedback loop (natural outcome of small fixtures, not a feature to build)

## Implementation Notes

### Environment Auto-Detection Pattern

Standard R approach (from search results):
```r
detect_environment <- function() {
  # Check env var override first
  if (Sys.getenv("R_ENV") != "") {
    return(Sys.getenv("R_ENV"))
  }

  # Hostname detection
  hostname <- Sys.info()["nodename"]
  if (grepl("hipergator|ufhpc", hostname, ignore.case = TRUE)) {
    return("hipergator")
  }

  # OS detection fallback
  if (.Platform$OS.type == "windows") {
    return("local")
  }

  # Default
  return("unknown")
}
```

### Path Abstraction Strategy

Extend R/00_config.R with environment-specific paths:
```r
ENV <- detect_environment()

CONFIG <- if (ENV == "hipergator") {
  list(
    data_dir = "/orange/erin.mobley-hl.bcu/Mailhot_V1_20250915",
    cache_dir = "/blue/erin.mobley-hl.bcu/clean/rds",
    duckdb_path = "/blue/erin.mobley-hl.bcu/clean/duckdb/pcornet.duckdb",
    performance = list(num_threads = 16)
  )
} else if (ENV == "local") {
  list(
    data_dir = here::here("test_fixtures"),
    cache_dir = here::here("output", "cache"),
    duckdb_path = here::here("output", "test.duckdb"),
    performance = list(num_threads = 4)
  )
} else {
  stop("Unknown environment. Set R_ENV to 'hipergator' or 'local'.")
}
```

### Fixture Design Principles (from research)

**Minimal representative sample (Medium confidence):**
- 20 patients sufficient to cover 5-7 clinical edge cases
- Each patient should represent 1-3 edge cases (documented in comments or separate matrix)
- CSVs should match PCORnet CDM schema exactly (column names, data types)

**Clinical edge cases to cover:**
- Dual-eligible (Medicare + Medicaid on same date)
- NLPHL subtype (C81.0x codes, 4-char prefix match logic)
- SCT (procedure code 0362) with/without other SCT codes in same encounter
- Multiple cancers (HL + solid tumor, test encounter-level cancer linkage)
- Orphan diagnosis codes (dx code without matching encounter)
- Post-death activity (claims after validated death date)
- Treatment gaps (7-day separation for cancer category confirmation)
- Regimen detection (ABVD, BV+AVD, Nivo+AVD for first-line therapy logic)

**Static fixture files pattern (testthat guidance, HIGH confidence):**
- Store in `test_fixtures/` directory at project root
- One CSV per PCORnet table (ENROLLMENT_Mailhot_V1.csv, DIAGNOSIS_Mailhot_V1.csv, etc.)
- Version control in git (text files, small size ~20 patients)
- Companion R script `test_fixtures/README.md` documents edge case coverage
- Optional: `test_fixtures/generate_fixtures.R` for reproducible creation (defer to v2.3)

### DuckDB In-Memory Testing (Medium confidence from search results)

DuckDB supports in-memory mode ideal for fast CI/local testing:
```r
# In-memory DuckDB (not persisted after R session)
con <- dbConnect(duckdb::duckdb(), dbdir = ":memory:")

# Or file-based but gitignored
con <- dbConnect(duckdb::duckdb(), dbdir = CONFIG$duckdb_path)
```

For v2.2, file-based is safer (less refactoring of existing R/03 ingest script). In-memory optimization can come later if speed becomes issue.

### Smoke Test Fixture-Aware Assertions

R/88 currently checks:
- Utils modules load
- Config constants defined
- Functions available
- Source() cross-references valid

For fixture mode, ADD:
- Row count checks with fixture thresholds (e.g., ENROLLMENT: 20 patients, not 60K)
- Edge case validation (patient PT001 has dual-eligible record, PT002 has NLPHL dx)
- Output file existence (cohort snapshots, Gantt CSVs exist in local output dir)

Pattern:
```r
if (ENV == "local") {
  check("ENROLLMENT has 20 patients (fixture mode)", nrow(enrollment) == 20)
  check("Patient PT001 is dual-eligible", PT001_has_dual_eligible_record)
} else {
  check("ENROLLMENT has >50K patients (production mode)", nrow(enrollment) > 50000)
}
```

## Complexity Assessment

| Feature Category | Overall Complexity | Rationale |
|------------------|-------------------|-----------|
| Environment detection | Low | Standard R pattern (Sys.info, env vars); ~20 lines of code |
| Path abstraction | Low | Conditional CONFIG list; already have `here` package |
| Test fixtures (hand-crafted) | Medium | Tedious but straightforward; must match PCORnet schema exactly across 13 tables |
| Fixture generation script | Medium | Reduces tedium but requires PCORnet schema knowledge + edge case encoding |
| DuckDB compatibility | Low | R/03 already generic; just needs CONFIG path updates |
| Smoke test adaptation | Medium | Must add fixture-aware assertions without breaking production mode |
| Edge case matrix | Low | Documentation task, not code |
| Validation report | Medium | Requires production run artifacts for comparison; scripting + interpretation |

## Dependencies on Existing Architecture

| Existing Component | Dependency Type | Impact |
|--------------------|----------------|---------|
| R/00_config.R | MUST MODIFY | Add environment detection, conditional CONFIG paths |
| R/03_duckdb_ingest.R | MUST VERIFY | Confirm works with fixture CSVs (likely no changes needed) |
| R/88_smoke_test_comprehensive.R | MUST MODIFY | Add fixture-aware assertions, conditional thresholds |
| `here` package (STACK.md) | MUST USE | Already in stack; use for project-relative paths |
| DuckDB backend (Phase 32) | MUST ALIGN | Fixtures must support DuckDB ingest path |
| PCORnet CDM schema | MUST MATCH | Fixture CSVs must have exact column names/types as production |
| Existing output artifacts | NICE TO HAVE | Validation report compares against these if available |

## Open Questions for Implementation

1. **Fixture size trade-off:** 20 patients sufficient? Or need 50+ for realistic distributions in stratified analyses?
   - **Recommendation:** Start with 20, expand if smoke test reveals gaps

2. **Edge case completeness:** Are 5-7 edge cases enough to validate core pipeline logic?
   - **Recommendation:** Cover critical filter predicates (dual-eligible, NLPHL, SCT, orphan dx, regimen matching); add more as bugs discovered

3. **Fixture update frequency:** When/how to update fixtures when pipeline logic changes?
   - **Recommendation:** Update fixtures when new edge case discovered or filter logic added; document in test_fixtures/CHANGELOG.md

4. **DuckDB file location:** Gitignore local DuckDB file? Or commit for test reproducibility?
   - **Recommendation:** Gitignore (binary file, ~10MB likely); fixtures are source of truth, DuckDB rebuilds from CSVs

5. **Performance threshold for "fast feedback":** What's acceptable for local smoke test runtime?
   - **Recommendation:** <2 min end-to-end (load CSVs → DuckDB ingest → cohort filter → smoke test); if >2 min, reduce fixture size

6. **Validation report scope:** Compare what? Row counts? Column distributions? Specific patient outcomes?
   - **Recommendation:** Defer to v2.3; focus on "does it run without error" for v2.2

## Sources

### General Data Pipeline Testing (MEDIUM-HIGH confidence)
- [Test Data Management Strategy 2026: Framework & Best Practices | Total Shift Left](https://totalshiftleft.com/blog/test-data-management-strategy)
- [Testing Data Pipelines: A Complete Guide for 2025 | Atlan](https://atlan.com/testing-data-pipelines/)
- [Building Trust in Data II: A Guide to Effective Data Testing Tactics | Databricks](https://community.databricks.com/t5/technical-blog/building-trust-in-data-ii-a-guide-to-effective-data-testing/ba-p/114316)
- [Data Quality Testing: Methods and Best Practices for 2026 | OvalEdge](https://www.ovaledge.com/blog/data-quality-testing-guide)

### Clinical Data & Synthetic Data (MEDIUM confidence)
- [What synthetic patient data quietly breaks in clinical AI | Talby.com](https://www.talby.com/p/what-synthetic-patient-data-quietly)
- [Synthetic data in the clinical laboratory: methods, applications, and future prospects | ScienceDirect](https://www.sciencedirect.com/science/article/pii/S0009898126000604)
- [PCORnet Data Resources](https://pcornet.org/news/category/domain/data/)
- [Tailoring Rule-Based Data Quality Assessment to PCORnet CDM | PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC10148276/)

### R Testing Frameworks (HIGH confidence)
- [Test fixtures • testthat](https://testthat.r-lib.org/articles/test-fixtures.html)
- [15 Advanced testing techniques – R Packages (2e)](https://r-pkgs.org/testing-advanced.html)
- [Self-cleaning test fixtures - Tidyverse](https://tidyverse.org/blog/2020/04/self-cleaning-test-fixtures/)
- [Package 'testthat' May 8, 2026 (v3.3.2)](https://cran.r-project.org/web/packages/testthat/testthat.pdf)

### DuckDB Testing Patterns (MEDIUM-HIGH confidence)
- [DuckDB + dbplyr: When Your Pipeline Gives Different Results Every Time It Runs | R-bloggers](https://www.r-bloggers.com/2026/03/duckdb-dbplyr-when-your-pipeline-gives-different-results-every-time-it-runs/)
- [dbt + DuckDB for Reproducible Analytics (Jan 2026) | Medium](https://medium.com/@sendoamoronta/dbt-duckdb-for-reproducible-analytics-runtime-engineering-and-advanced-performance-patterns-3fab4e596f75)
- [Creating Data Analysis Pipelines using DuckDB and RStudio | Fedora Magazine](https://fedoramagazine.org/creating-data-analysis-pipelines-using-duckdb-and-rstudio/)
- [Querying Data with DuckDB from R | RGuides](https://rguides.dev/guides/r-duckdb/)

### Environment Detection (HIGH confidence)
- [Sys.info: Extract System and User Information | R Documentation](https://rdrr.io/r/base/Sys.info.html)
- [getHostname.System: Retrieves the computer name of the current host | R.utils](https://rdrr.io/cran/R.utils/man/getHostname.System.html)
- [rprojroot: Finding Files in Project Subdirectories](https://rprojroot.r-lib.org/reference/rprojroot-package.html)

### Smoke Testing for Data Pipelines (MEDIUM-HIGH confidence)
- [Smoke Testing: Complete Guide for Developers [2026] | Keploy Blog](https://keploy.io/blog/community/developers-guide-to-smoke-testing-ensuring-basic-functionality)
- [Smoke Testing for ML Pipelines | Sealos Blog](https://sealos.io/blog/smoke-testing-for-ml-pipelines-catching-data-and-model-errors-before-they-hit-production/)
- [Smoke testing in CI/CD pipelines | CircleCI](https://circleci.com/blog/smoke-tests-in-cicd-pipelines/)

---

**Overall confidence level:** MEDIUM-HIGH

- **Table stakes** (HIGH confidence): Well-established patterns from R testing literature (testthat fixtures, Sys.info() detection, here package)
- **Differentiators** (MEDIUM confidence): Clinical edge case coverage and validation reporting are domain-specific; less established literature
- **Anti-features** (HIGH confidence): Clear consensus against over-engineering for exploratory pipelines (no Docker, no full synthetic data, no mocking)
- **Implementation patterns** (MEDIUM-HIGH confidence): testthat fixtures + DuckDB in-memory testing well-documented; clinical edge cases require domain knowledge

**Verification notes:**
- testthat fixture patterns verified from official documentation (HIGH confidence)
- DuckDB testing patterns verified from recent 2026 blog posts and official guides (MEDIUM-HIGH confidence)
- Clinical edge case strategies inferred from PCORnet research and synthetic data literature (MEDIUM confidence)
- Environment detection patterns verified from R base documentation (HIGH confidence)
