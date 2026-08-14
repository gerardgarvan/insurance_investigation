# Phase 142 Pre-Flight Discovery

Run on HiPerGator before executing 142-01-PLAN.md. Record all outputs below.
No code edits in this step — this is an observation-only checklist.

---

## §0a — Actual `drug_name` strings reaching `treatment_episode_detail.rds`

Run in RStudio on HiPerGator:
```r
source("R/00_config.R")
det <- readRDS(file.path(CONFIG$cache$outputs_dir, "treatment_episode_detail.rds"))
vb  <- sort(unique(det$drug_name))
print(vb[grepl("vinbl", vb, ignore.case = TRUE)])
cat("\nfull distinct drug_name list:\n"); print(vb)
```

**Output (paste here):**
```
[FILL IN]
```

**Alias key to use in DRUG_NAME_ALIASES:**
```
[FILL IN — must be tolower(trimws(...)) of the exact string above]
```

**Notes:**
- If the long RxNorm form (e.g. "vinblastine sulfate 1 MG/ML Injectable S") appears,
  an exact alias in DRUG_NAME_ALIASES cannot fix it. The normalization must happen in
  R/26 where the RxNorm string is resolved (strip the strength/dose-form tail before
  canonicalize_drug_name sees it). Flag this before executing Task 1.

---

## §0b — All `canonicalize_drug_name` call sites

Run in bash on HiPerGator:
```bash
grep -rn "canonicalize_drug_name" R/ --include=*.R
```

**Output (paste here):**
```
[FILL IN]
```

**Interpretation:**
- [ ] `canonicalize_drug_name` appears in **R/26** as well as `R/00_config.R`
      → The fix in R/00_config.R is sufficient; R/26 already canonicalizes on the resolution path.
- [ ] `canonicalize_drug_name` appears **only in R/00_config.R**
      → Must add `dplyr::mutate(drug_name = canonicalize_drug_name(drug_name))` to R/26
        at the point the three-tier lookup produces its final `drug_name` value.
        Update `files_modified` in 142-01-PLAN.md frontmatter accordingly.

---

## §0c — Episode rule discrimination

Run in RStudio on HiPerGator (requires `calculate_episodes_detailed` to be in scope,
i.e. after sourcing R/26 or the function definition):

```r
tst <- tibble::tibble(
  ID              = "TEST001",
  treatment_date  = as.Date("2020-01-01") + c(0, 50, 100, 150),
  triggering_code = "J9360",
  ENCOUNTERID     = paste0("E", 1:4),
  source_hint     = "test",
  drug_name       = "Vinblastine"
)
calculate_episodes_detailed(tst, gap_threshold = 90L)
```

**Output (paste here):**
```
[FILL IN]
```

**Interpretation:**
- [ ] **2 episodes** (starts at day 0 and day 100)
      → Window-from-start rule. Matches D-01 as stated. Proceed with 142-01.
- [ ] **1 episode**
      → Gap-between-dates rule. Contradicts D-01 and the colleague's stated request
        ("6-month/180 day episodes"). **Flag to colleague before executing the plan.**
        Under the gap rule, an episode can span years — the 180-day file may not be
        what was asked for.

---

## Resolution Sign-off

- [ ] §0a alias key confirmed: `_________________________`
- [ ] §0b: canonicalize_drug_name IS / IS NOT called in R/26 (circle one)
- [ ] §0c: episode rule is window-from-start / gap-between-dates (circle one)
- [ ] Ready to execute 142-01-PLAN.md Task 1: YES / NO (flag any blockers above)

Date completed: ___________
