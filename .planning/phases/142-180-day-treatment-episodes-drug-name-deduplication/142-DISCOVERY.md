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
[1] "Vinblastine"         "Vinblastine Sulfate"
```

Full distinct drug_name list (86 entries): Adcetris, Ado-Trastuzumab Emtansine, Adriamycin,
Arsenic Trioxide, Asparaginase, Atezolizumab, Azacitidine, Bcg Live Intravesical Instillation,
Bendamustine, Bevacizumab, Bleomycin, Blinatumomab, Bortezomib, Brentuximab Vedotin,
Cabazitaxel, Calaspargase Pegol-Mknl, Carboplatin, Carfilzomib, Carmustine, Cemiplimab-Rwlc,
Cetuximab, Cisplatin, Cladribine, Copanlisib, Cyclophosphamide, Cytarabine, Dacarbazine,
Daratumumab, Daunorubicin, Docetaxel, Doxorubicin Hydrochloride, Durvalumab,
Epcoritamab-Bysp, Epirubicin, Eribulin Mesylate, Etoposide, Fam-Trastuzumab Deruxtecan-Nxki,
Floxuridine, Fludarabine Phosphate, Fluorouracil, Fulvestrant, Gemcitabine, Glofitamab-Gxbm,
Goserelin Acetate, Ifosfamide, Ipilimumab, Irinotecan, Ixabepilone, Leuprolide Acetate,
Loncastuximab Tesirine-Lpyl, Lurbinectedin, Mechlorethamine, Melphalan, Mesna, Methotrexate,
Mitomycin, Mitoxantrone, Mogamulizumab-Kpkc, Nelarabine, Nivolumab,
Not Otherwise Classified Antineoplastic Drugs, Obinutuzumab, Ofatumumab, Oxaliplatin,
Paclitaxel, Pegaspargase, Pembrolizumab, Pemetrexed, Pentostatin, Pertuzumab,
Polatuzumab Vedotin-Piiq, Pralatrexate, Procarbazine, Ramucirumab, Rituximab, Romidepsin,
Sacituzumab Govitecan-Hziy, Tafasitamab-Cxix, Temsirolimus, Thiotepa, Topotecan,
Trastuzumab, Vinblastine, Vinblastine Sulfate, Vincristine Sulfate, Vinorelbine Tartrate

**Alias key to use in DRUG_NAME_ALIASES:**
```
"vinblastine sulfate" = "Vinblastine"
```
(tolower(trimws("Vinblastine Sulfate")) == "vinblastine sulfate")

**Notes:**
- Short form "Vinblastine Sulfate" appears — NOT the long RxNorm form. An exact alias
  in DRUG_NAME_ALIASES is sufficient; no R/26 stripping needed.
- Audit: only vinblastine has a duplicate pair in the output. Vincristine Sulfate,
  Vinorelbine Tartrate, Fludarabine Phosphate, Bleomycin, Dacarbazine all appear as
  single tokens — no aliases needed for those.

---

## §0b — All `canonicalize_drug_name` call sites

Run in bash on HiPerGator:
```bash
grep -rn "canonicalize_drug_name" R/ --include=*.R
```

**Output (paste here):**
```
R/00_config.R:2668:# canonicalize_drug_name(): vectorized, NA-safe, case-insensitive alias lookup.
R/00_config.R:2672:canonicalize_drug_name <- function(x) {
R/00_config.R:2682:MEDICATION_LOOKUP <- setNames(canonicalize_drug_name(unname(MEDICATION_LOOKUP)), names(MEDICATION_LOOKUP))
R/00_config.R:2727:    extracted <- canonicalize_drug_name(extracted)
R/00_config.R:2781:    s <- canonicalize_drug_name(s)
R/26_treatment_episodes.R:779:# Tier 2 (Phase 124): raw MED_ADMIN free-text names, canonicalized via canonicalize_drug_name()
R/26_treatment_episodes.R:793:  mutate(raw_med_name_canonical = canonicalize_drug_name(toupper(trimws(raw_med_name))))
R/26_treatment_episodes.R:813:# raw_med_name_canonical is NEVER written verbatim — always passes through canonicalize_drug_name() (D-07)
R/27_drug_name_resolution.R:480:# canonicalize_drug_name() / DRUG_NAME_ALIASES come from R/00_config.R (sourced above).
R/27_drug_name_resolution.R:482:  mutate(drug_name = canonicalize_drug_name(drug_name))
... (plus R/109, R/110, R/105, R/88 references)
```

**Interpretation:**
- [x] `canonicalize_drug_name` appears in **R/26** (line 793) as well as `R/00_config.R`
      → The fix in R/00_config.R is sufficient; R/26 and R/27 already canonicalize on
        the resolution path. No additional mutate() call needed.

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
# A tibble: 2 × 10
  patient_id episode_number episode_start episode_stop
  <chr>               <int> <date>        <date>      
1 TEST001                 1 2020-01-01    2020-02-20  
2 TEST001                 2 2020-04-10    2020-05-30  
# ℹ 6 more variables: episode_length_days <dbl>,
#   distinct_dates_in_episode <int>, historical_flag <lgl>,
#   triggering_codes <chr>, source_hints <chr>, encounter_ids <chr>
```

**Interpretation:**
- [x] **2 episodes** (starts at day 0 and day 100)
      → Window-from-start rule. Matches D-01 as stated. Proceed with Wave 2 (142-02).

---

## Resolution Sign-off

- [x] §0a alias key confirmed: `"vinblastine sulfate"` → `"Vinblastine"`
- [x] §0b: canonicalize_drug_name IS called in R/26 (line 793) — alias fix is sufficient
- [x] §0c: episode rule is window-from-start (2 episodes returned)
- [x] Ready to execute 142-01-PLAN.md Task 1: YES

Date completed: 2026-08-14
