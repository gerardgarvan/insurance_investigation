# ADI-RECOLLATE-PATCH.md — Re-collate the Neighborhood Atlas ZIP9 downloads

Applies to `insurance_investigation`. Produces
`data/reference/neighborhood_atlas_zip9_adi.csv`, the input `R/118_build_zip5_adi_summary.R`
expects at `ADI_INPUT_PATH`.

---

## Why this exists

The Neighborhood Atlas offers a **national** bulk download for the 12-digit census block-group FIPS
linkage only. The **9-digit ZIP** linkage — the one this project joins on — is available
**state-by-state only**. So the reference file is a hand-assembled collation, and every additional
state means another download.

23 states were collated previously. The `zip5_no_zip9` residue (11,843 encounters across 153 ZIP5s)
is dominated by states absent from that set: **Arkansas, Louisiana, Oklahoma, Texas, Mississippi,
Puerto Rico**, plus whatever the 61 non-prefix-7 ZIP5s turn out to need.

Because the downloads arrive through a browser, they land as `adi-download.zip`,
`adi-download (2).zip`, `adi-download (3).zip` … — **the filename records download order, not
state**. That is the whole problem this patch addresses.

---

## Step 0 — Determine the complete state list before downloading

Do not download six states, rebuild, and then discover stragglers. Get the full list once:

```r
new  <- readRDS(Sys.glob("output/encounter_ses_index_*.rds") |> sort() |> tail(1))
need <- new |> dplyr::filter(zip9_source == "zip5_no_zip9")

need |>
  dplyr::count(ZIP5, sort = TRUE) |>
  dplyr::mutate(p3 = substr(ZIP5, 1, 3)) |>
  dplyr::arrange(p3) |>
  print(n = Inf)
```

Map each `p3` to a state (USPS 3-digit prefix ranges), and record the resulting list in
`149-DISCOVERY.md` §2 **before** opening the portal. The 61 ZIP5s with prefixes `0`, `2`, `3`, `4`
and `6` are unaccounted for by the six states named above and will add several more.

---

## Step 1 — Rename each zip at the moment of download

`adi-download (7).zip` is unidentifiable an hour later. The Atlas download form does not encode the
state in the filename, so **rename immediately after each download, before starting the next**:

```
adi_zip9_AR_2024_v401.zip
adi_zip9_LA_2024_v401.zip
adi_zip9_OK_2024_v401.zip
...
```

Pattern: `adi_zip9_<STATE>_<VINTAGE-YEAR>_<VERSION>.zip`.

**Version must match `R/118`'s `VINTAGE` constant**, currently:

```r
VINTAGE <- "Neighborhood Atlas 2024 v4.0.1"
```

The Atlas publishes 2015, 2018, 2019 (v3.0/v3.1), 2020 (v3.2, later v4/v4.0.1), 2021, 2022 and 2024.
Mixing vintages inside one collated file is silently wrong — block-group boundaries were redrawn for
2020, and the changelog states that comparison across that boundary is impossible. Select the same
version for every state, including the 23 already collated. **If the existing 23 are a different
vintage, re-download those too** — a 29-state file spanning two vintages is worse than a 23-state
file spanning one.

If a rename was missed, recover the state from the file's own contents rather than guessing:

```bash
for z in adi-download*.zip; do
  echo "--- $z"
  unzip -p "$z" '*.txt' '*.csv' 2>/dev/null | head -3
done
```

The first data rows carry ZIP9s whose 3-digit prefix identifies the state.

---

## Step 2 — Inventory before extracting

```bash
cd ~/adi_downloads          # wherever the zips landed
ls -la *.zip | wc -l
for z in *.zip; do
  printf '%-40s %s\n' "$z" "$(unzip -l "$z" | tail -3 | head -1)"
done
```

Record the count in `149-DISCOVERY.md` §2. It must equal (23 already held) + (states from Step 0),
with no duplicates. A browser that resumed a download can leave both `adi-download (4).zip` and
`adi-download (5).zip` holding the same state — Step 4's duplicate check catches that, but knowing
the expected count first makes the check meaningful.

---

## Step 3 — Extract

```bash
mkdir -p extracted
for z in *.zip; do
  base="${z%.zip}"
  mkdir -p "extracted/$base"
  unzip -o -q "$z" -d "extracted/$base"
done

find extracted -type f \( -name '*.txt' -o -name '*.csv' \) | sort
```

Check the delimiter and header before assuming CSV — the Atlas has shipped both comma- and
tab-delimited text depending on version:

```bash
head -2 "$(find extracted -type f \( -name '*.txt' -o -name '*.csv' \) | head -1)"
```

If the columns are tab-separated, use `vroom(delim = "\t")` in Step 4 rather than `vroom_csv`.

---

## Step 4 — Collate

Write `R/119_collate_adi_zip9.R`. Next free script number after `R/118`; check first with
`ls R/119* 2>/dev/null`.

```r
# ==============================================================================
# R/119_collate_adi_zip9.R
# Collate per-state Neighborhood Atlas ZIP9 ADI downloads into one reference file.
#
# The Atlas offers national bulk download for the 12-digit block-group FIPS linkage
# ONLY. The 9-digit ZIP linkage is state-by-state, so this file is hand-assembled
# and must be rebuilt whenever a cohort gains out-of-state patients.
#
# Output: data/reference/neighborhood_atlas_zip9_adi.csv  (ADI_INPUT_PATH in R/118)
# ==============================================================================

library(here); library(dplyr); library(vroom); library(readr); library(glue)

EXTRACT_DIR <- here::here("data", "raw", "adi_downloads", "extracted")
OUT_PATH    <- here::here("data", "reference", "neighborhood_atlas_zip9_adi.csv")
EXPECTED_VINTAGE <- "2024 v4.0.1"   # must match R/118's VINTAGE constant

files <- list.files(EXTRACT_DIR, pattern = "\\.(txt|csv)$",
                    recursive = TRUE, full.names = TRUE)
stopifnot("no extracted ADI files found" = length(files) > 0)
message(glue("Found {length(files)} extracted file(s)"))

# Read every file as character. ZIP9 MUST be character -- a numeric read drops
# leading zeros and silently corrupts every ZIP beginning 0 (all of New England
# and Puerto Rico).
adi_raw <- vroom::vroom(files, col_types = vroom::cols(.default = "c"),
                        id = "source_file", progress = FALSE)
message(glue("Combined rows: {format(nrow(adi_raw), big.mark = ',')}"))

# --- Column naming: the Atlas has shipped GISJOIN / FIPS / ZIPID / ZIP9 and
#     ADI_NATRANK / adi_natrank across versions. Normalise, do not assume.
names(adi_raw) <- toupper(names(adi_raw))
zip_col <- intersect(c("ZIP9", "ZIPID", "BENE_ZIP_CD", "ZIP_4"), names(adi_raw))[1]
adi_col <- intersect(c("ADI_NATRANK", "ADI_NATIONAL"), names(adi_raw))[1]
stopifnot(
  "no recognisable ZIP9 column" = !is.na(zip_col),
  "no recognisable ADI_NATRANK column" = !is.na(adi_col)
)
message(glue("Using ZIP column '{zip_col}', ADI column '{adi_col}'"))

adi <- adi_raw %>%
  dplyr::transmute(
    ZIP9        = gsub("[^0-9]", "", .data[[zip_col]]),
    ADI_NATRANK = .data[[adi_col]],
    source_file = basename(source_file)
  ) %>%
  dplyr::filter(nchar(ZIP9) == 9L)

# --- Duplicate check. A browser-resumed download can leave the same state in two
#     zips; that shows up here as exact-duplicate ZIP9s, not as a filename clash.
dupes <- adi %>% dplyr::count(ZIP9) %>% dplyr::filter(n > 1)
if (nrow(dupes) > 0) {
  by_file <- adi %>%
    dplyr::semi_join(dupes, by = "ZIP9") %>%
    dplyr::count(source_file, sort = TRUE)
  print(by_file)
  stop(glue(
    "{format(nrow(dupes), big.mark=',')} ZIP9s appear more than once. Two files ",
    "almost certainly contain the same state -- see the counts above, remove the ",
    "redundant zip, and re-run. Do NOT distinct() this away: it would hide a ",
    "vintage mismatch between two downloads of the same state."
  ))
}

# --- State coverage, from ZIP prefixes actually present
cover <- adi %>%
  dplyr::mutate(p3 = substr(ZIP9, 1, 3)) %>%
  dplyr::distinct(p3) %>%
  dplyr::arrange(p3)
message(glue("Distinct 3-digit ZIP prefixes: {nrow(cover)}"))

# The states this collation was rebuilt to add (Step 0 list)
target_p3 <- c(sprintf("%03d", 700:714),   # Louisiana
               sprintf("%03d", 716:729),   # Arkansas
               sprintf("%03d", 730:731), sprintf("%03d", 734:741),  # Oklahoma
               "733", sprintf("%03d", 750:799),                     # Texas
               sprintf("%03d", 386:397),   # Mississippi
               sprintf("%03d", 6:9))       # Puerto Rico
missing <- setdiff(target_p3, cover$p3)
if (length(missing) > 0) {
  message(glue("NOTE: {length(missing)} target prefixes absent -- some are simply ",
               "unassigned by USPS. Absent: {paste(head(missing, 20), collapse=', ')}"))
}

readr::write_csv(dplyr::select(adi, ZIP9, ADI_NATRANK), OUT_PATH)
message(glue("Wrote {format(nrow(adi), big.mark=',')} rows to {OUT_PATH}"))
message(glue("Size: {round(file.size(OUT_PATH)/1024^2, 1)} MB"))
```

**`distinct()` is deliberately not used on duplicates.** Two downloads of the same state from
different vintages would produce the same ZIP9 with different ADI values, and de-duplicating would
silently keep whichever sorted first. The build stops instead.

---

## Step 5 — Verify before transferring

```r
adi <- vroom::vroom("data/reference/neighborhood_atlas_zip9_adi.csv",
                    col_types = vroom::cols(.default = "c"))

cat("rows:", format(nrow(adi), big.mark = ","), "\n")
cat("all ZIP9 are 9 chars:", all(nchar(adi$ZIP9) == 9L), "\n")
cat("distinct ZIP9 == nrow:", dplyr::n_distinct(adi$ZIP9) == nrow(adi), "\n")

# leading zeros survived? Puerto Rico and New England depend on this
cat("ZIP9s starting '00':", sum(substr(adi$ZIP9, 1, 2) == "00"), "\n")

# do the residue ZIP5s now resolve?
new  <- readRDS(Sys.glob("output/encounter_ses_index_*.rds") |> sort() |> tail(1))
need <- unique(new$ZIP5[new$zip9_source == "zip5_no_zip9"])
cat("residue ZIP5s now covered:",
    sum(need %in% substr(adi$ZIP9, 1, 5)), "of", length(need), "\n")
```

That last figure is the one that matters. If it is not close to 153, a state is still missing and
Step 0's list was incomplete — go back rather than rebuilding.

`ZIP9s starting '00'` being zero would mean leading zeros were lost somewhere despite the character
read; Puerto Rico (`006`–`009`) makes that immediately visible.

---

## Step 6 — Transfer and rebuild

The reference file is gitignored, so it does not reach HiPerGator by commit:

```bash
scp data/reference/neighborhood_atlas_zip9_adi.csv \
    {user}@hpg.rc.ufl.edu:/blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/
```

Confirm it arrived **before** running anything — an absent file makes ADI report 0% and reads as a
join failure:

```bash
ssh {user}@hpg.rc.ufl.edu \
  "ls -lh /blue/erin.mobley-hl.bcu/insurance_investigation/data/reference/neighborhood_atlas_zip9_adi.csv"
```

Then on HiPerGator, archiving first — dated filenames overwrite in place:

```bash
cd output
for f in encounter_ses_index_*.rds encounter_ses_index_summary_*.xlsx zip_stability_counts_*.xlsx; do
  [ -e "$f" ] || continue
  case "$f" in *_pre*.*) continue;; esac
  mv "$f" "${f%.*}_preadi.${f##*.}" && echo "archived $f"
done
cd ..

module load R/4.4.2
Rscript R/118_build_zip5_adi_summary.R
Rscript R/116_encounter_ses_index.R
Rscript R/88_smoke_test_comprehensive.R
```

---

## Step 7 — Record

In `149-DISCOVERY.md` §2:

- **The structural finding:** the Atlas offers national bulk download for the block-group FIPS
  linkage only; the ZIP9 linkage is state-by-state. This is why the reference file is a manual
  collation, and it makes ADI coverage a standing maintenance item — every extract with new
  out-of-state patients needs another download. Put this in `data/reference/README.md` too, beside
  the ADI entry.
- States already held (23), states added, and the vintage of every one.
- Row count and file size before and after.
- Residue ZIP5s covered, from Step 5.

Expected in the re-run, per `149-03`'s magnitude table:

| | before | expected after |
|---|---|---|
| `zip5_no_zip9` | 11,843 | ~900 |
| `zip5_representative` | 47,036 | ~58,000 |
| `zip9_observed` | 1,516,469 | **unchanged** |
| `none` | 158,699 | **unchanged** |
| total | 1,950,696 | **exactly 1,950,696** |

---

## Do not

| | Because |
|---|---|
| Keep `adi-download (n).zip` names | The number is download order, not state; unidentifiable within the hour |
| Mix vintages across states | Block groups were redrawn for 2020; the Atlas states cross-boundary comparison is impossible |
| Read ZIP9 as numeric | Leading zeros vanish — all of New England and Puerto Rico |
| `distinct()` away duplicate ZIP9s | Two vintages of one state would silently resolve to whichever sorted first |
| Assume the file is comma-delimited | The Atlas has shipped tab-delimited text; check `head -2` |
| Assume the ZIP column is named `ZIP9` | `ZIPID`, `BENE_ZIP_CD` and `ZIP_4` have all appeared; normalise |
| Rebuild before confirming the Step 0 state list is complete | 61 residue ZIP5s are outside the six named states |
| Run R/118 before confirming the file reached HiPerGator | `.gitignore` does not move a file; ADI reports 0% and looks like a join bug |
