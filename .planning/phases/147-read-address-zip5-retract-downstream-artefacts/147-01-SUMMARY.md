---
phase: 147-read-address-zip5-retract-downstream-artefacts
plan: 01
status: completed
completed: 2026-08-18
---

# Plan 1 Summary — Discovery Complete

## What was done

- **Task 1:** Wrote `147-DISCOVERY.md` with §0 stub, measured 2×2 (§1), incorrect-comment
  quote (§2), §3 stub, provisional D-02 (§4), and R/116 diagnostic note (§5).
- **Task 2 (HiPerGator checkpoint):** User ran `names()` audit and the 12 prefix-disagreement
  query on the real extract on 2026-08-18.
- **Task 3:** Replaced both stubs in `147-DISCOVERY.md` with real HiPerGator output and
  locked D-02.

## Key findings

- **D-01:** `LDS_ADDRESS_HISTORY_Mailhot_V1.csv` has 13 columns. ZIP-ish columns are exactly
  `ADDRESS_ZIP5` and `ADDRESS_ZIP9`. No third ZIP column. No STOP signal.
- **D-02 LOCKED — ADDRESS_ZIP5 WINS.** The 12 disagreement rows show no systematic pattern
  (scattered IDs, scattered ZIPs, no shared transposition, dates 2009–2023). Data-entry noise.

## Coalesce order for Plan 2

```r
zip5_norm = dplyr::coalesce(
  normalize_zip5(ADDRESS_ZIP5),
  normalize_zip5(zip9_norm)
)
```

## Gate status

Plan 2 is unblocked. D-02 is confirmed on evidence, not provisional.
