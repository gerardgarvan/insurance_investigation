---
quick_id: 261008-sp4
description: Fix R/88 Check 17 alias_keys parsing — strip quotes from parsed keys so setdiff finds the required dox aliases
date: 2026-10-09
commit: 765f183
tasks_completed: 1
tasks_total: 1
---

# Quick Task 261008-sp4: Summary

## What Changed

**File:** `R/88_smoke_test_comprehensive.R` — line 1860

**Before:**
```r
alias_keys <- trimws(ifelse(grepl("=", alias_code), sub("=.*$", "", alias_code), ""))
```

**After:**
```r
alias_keys <- gsub('"', '', trimws(ifelse(grepl("=", alias_code), sub("=.*$", "", alias_code), "")))
```

## Root Cause

The alias block parser split on `=` then trimmed whitespace, leaving R source-level
quote characters in the key tokens (e.g. `"adriamycin"` with actual `"` chars).
`setdiff(required_dox_keys, tolower(alias_keys))` compared these against bare
strings (`adriamycin`), found no match, and reported all 6 required keys missing —
so Check 17 always FAILed even though Phase 164 had correctly added all keys.

## Outcome

Check 17 (`DRUG_NAME_ALIASES has adriamycin + liposomal dox keys -> Doxorubicin`)
will now PASS on HiPerGator, clearing the pre-existing R/88 failure flagged in
Phase 169.

## Self-Check: PASSED

- Fix applied at R/88 line 1860 ✓
- Commit 765f183 present ✓
- No other files changed ✓
