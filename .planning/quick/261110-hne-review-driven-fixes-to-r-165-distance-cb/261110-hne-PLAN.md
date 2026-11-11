---
phase: quick-261110-hne
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - R/165_distance_cbc_association.R
  - R/utils/utils_distance_cbc.R
  - R/165_validate_workbook.R
autonomous: true
requirements: [HNE-P1, HNE-P2, HNE-P3, HNE-P4, HNE-P5]
must_haves:
  truths:
    - "SOURCE_REASSIGN_QC shows all four methods with address > 0 FLM encounters reassigned"
    - "Each _addr BY_SOURCE sheet differs from its _flm counterpart"
    - "Patient-level MH_POOLED is computed on patient-level data (stratum totals sum to patient N)"
    - "Sensitivity model drops zero-CBC SOURCE levels and relevels to largest site (no |log-OR| > 5)"
    - "No visible row combination can back-calculate a suppressed cell"
    - "Workbook archive has no dangling drawing relationships"
    - "KEY is sheet 1, SUMMARY is sheet 2; validator passes all checks"
  artifacts:
    - path: "R/165_distance_cbc_association.R"
      provides: "All fixes P1-P5, workbook build, decision log D-165-04..08"
    - path: "R/utils/utils_distance_cbc.R"
      provides: "Fixed assign_analytic_source() address reassignment + suppression/stats helpers"
    - path: "R/165_validate_workbook.R"
      provides: "Standalone workbook validator with PASS/FAIL per check"
  key_links:
    - from: "R/165_distance_cbc_association.R"
      to: "assign_analytic_source()"
      via: "address-step reassignment"
      pattern: "source_reassign_method.*address"
    - from: "R/165_validate_workbook.R"
      to: "output/distance_cbc_association_*.xlsx"
      via: "unzip archive + sheet checks"
      pattern: "unzip.*list"
---

<objective>
Apply Gerard's review-driven fixes to R/165_distance_cbc_association.R and its workbook, in priority order. Fix three correctness bugs (address reassignment yields 0, patient-level MH computed on encounter data, sensitivity quasi-separation), close a small-cell disclosure hole, correct statistical presentation (clustering-aware per-site tests, heterogeneity reporting, sensitivity formatting, exploratory excl-FLM sheet), rebuild the workbook cleanly (no dangling drawing parts, numeric cells, formatting), add a baseline-reset path for the regression check, append decision entries D-165-04..08, and ship a standalone validator.

Purpose: The 20261110 workbook is both wrong (reassignment no-op, mis-sourced MH, separated sensitivity) and discloses suppressed small cells. These are blocking defects before the distance x CBC analysis can be shared.
Output: Edited R/165_distance_cbc_association.R and R/utils/utils_distance_cbc.R; new R/165_validate_workbook.R; HiPerGator run commands for Gerard.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@./CLAUDE.md

Key code locations (verified by grep; read the surrounding ranges before editing):
- R/utils/utils_distance_cbc.R — `assign_analytic_source()` (address interval-match + recency fallback + modal fallback), `build_by_source_sheet()`, `build_by_source_pat_sheet()`, `compute_mh_breslow()`, `build_flm_sensitivity_set()`, `suppress_small_vec()`, `suppress_display()`, `apply_complementary_suppression()` (also partially in main script, lines 314-390), `naive_or_se()`, `collapse_to_other()`, `modal_source_fn()`.
- R/165 lines 106-131: address file pin + enc_all_1923 modal fallback input.
- R/165 lines 277-290: enc_full assembly, missing-rurality / missing-payer QC counts.
- R/165 lines 369-653: analyse_window() — primary Rao-Scott (svychisq lines 484-531) and sensitivity svyglm (lines 548-653); NOTE the "use SOURCE_raw not SOURCE_analytic" Phase 192.3 constraint applies to A_crosstab/B_test/C_sensitivity ONLY, not the BY_SOURCE sheets.
- R/165 lines 685-765: createWorkbook(), KEY sheet (key_df, uf_header_style, section_style, bold_style, fmt_p, suppress_display).
- R/165 lines 765-921: A_crosstab (write_crosstab_block), B_test, C_sensitivity writers.
- R/165 lines 925-945: QC sheet.
- R/165 lines 970-1210: BY_SOURCE_enc (build loop ~1017-1053), BY_SOURCE_pat (build loop ~1053-1110), compute_mh_breslow / Breslow-Day (1174-1214).
- R/165 lines 1211-1380: enc_whole/post, _addr and _flm sensitivity sets, six BY_SOURCE sheet writers, SOURCE_REASSIGN_QC (1302-1348).
- R/165 lines 1381-1414: KEY Phase 192.3 notes, decision log rows D-165-01..03 are in the KEY key_df around lines 696-752.
- R/165 lines 1416-1501: save + regression check (PRIOR_WB_PATH default `distance_cbc_association_20261110.xlsx`, sheet-by-sheet cell compare).

CONFIG: `CONFIG$claims_source_codes <- c("FLM")` (R/00_config.R:238). `CONFIG$distance_assoc_method` is D-165-01.

Decision log D-165-01..03 live as KEY rows (grep `D-165-0` in R/165). New entries D-165-04..08 go in the same key_df block, same format.
</context>

<constraints>
- R runs ONLY on HiPerGator. Do NOT run Rscript locally. Static verification only: Node brace-balance script for syntax.
- Make a `.bak` of every file before the first edit to it (cp file file.bak).
- Edit in place; find functions with grep -n, read only the needed range (CLAUDE.md large-file rule).
- Never open data/parquet/RDS/xlsx. Work from code + Gerard's pasted summaries.
- Honor the Phase 192.3 constraint: A_crosstab/B_test/C_sensitivity use raw SOURCE; BY_SOURCE sheets use SOURCE_analytic.
- Suppression is DISPLAY-ONLY: MH and all stats use true counts; only displayed cells are blanked/tokenized.
- If any diagnosis in the spec turns out wrong when reading the code, STOP and report rather than forcing the described fix.
- Show full diffs at the end.
</constraints>

<tasks>

<task type="auto">
  <name>Task 1 (P1 bugs): Fix address reassignment, patient-level MH source, and sensitivity quasi-separation</name>
  <files>R/utils/utils_distance_cbc.R, R/165_distance_cbc_association.R</files>
  <action>
  .bak both files first.

  1.1 Address reassignment yields 0 (utils_distance_cbc.R::assign_analytic_source):
  - Read the full function. Diagnose why FLM encounters get 0 address matches. Check in this order and report which is the actual cause: (a) ID type mismatch between encounters and LDS_ADDRESS_HISTORY (chr vs num/int64) at the join key; (b) date class mismatch (ADMIT_DATE vs ADDRESS_PERIOD_START/END — Date vs POSIXct vs character); (c) interval condition direction (START <= ADMIT_DATE & ADMIT_DATE <= END); (d) whether the address SOURCE column is filtered to non-claims (not in CONFIG$claims_source_codes) BEFORE vs AFTER the join. If the diagnosis differs from the spec, STOP and report.
  - Fix the root cause. Keep interval-match first, recency fallback second, modal-encounter fallback third, then Claims_unresolved.
  - Add message(): n FLM encounters matched by interval, by recency fallback, by modal fallback, and unmatched (Claims_unresolved).
  - Add stop() if 0 FLM encounters are address-reassigned while address history has rows for >0 FLM patients.

  1.1b SOURCE_REASSIGN_QC always emits all four methods (R/165 ~1302-1326): build qc_method_df from a fixed factor of methods c("address","modal_encounter","unresolved","not_reassigned") so every method appears with 0 when empty (complete/tidyr::complete or factor + count then fill 0). source_reassign_method values from assign_analytic_source must map to exactly these four labels.

  1.2 Patient-level MH on encounter data (R/165 BY_SOURCE_pat build ~1053-1110 and compute_mh_breslow call for pat sheets):
  - Find where MH_POOLED is appended for the pat sheets. The pat sheets currently reuse the encounter-level MH. Make compute_mh_breslow (or a pat variant) operate on the patient-level 2x2 table (one row per patient per stratum) for pat sheets.
  - Emit MH_POOLED on ALL SIX BY_SOURCE sheets (enc, pat, enc_addr, pat_addr, enc_flm, pat_flm) — pat_addr/pat_flm currently have none.
  - Add stopifnot: in each pat sheet, sum of stratum (n_far + n_not_far) equals the patient N used for its MH (per window).

  1.3 Sensitivity svyglm quasi-separation (R/165 analyse_window ~548-653):
  - Before fitting the sensitivity svyglm, drop SOURCE levels (raw SOURCE — keep raw per Phase 192.3) with zero CBC events in the model data. Report which levels dropped and N encounters dropped as rows in C_sensitivity.
  - droplevels(), then relevel SOURCE to the level with the most encounters (expect UMI). Note in KEY that sensitivity uses raw SOURCE releveled to largest site.
  </action>
  <verify>
    <automated>node brace-balance script on both edited files; grep confirms message()/stop() added in assign_analytic_source, four-method factor in QC build, droplevels+relevel in sensitivity, stopifnot in pat MH</automated>
  </verify>
  <done>assign_analytic_source reports per-method counts and stops on 0-address paradox; QC always emits four methods; pat MH uses patient data on all six sheets; sensitivity drops zero-CBC levels and relevels to largest site.</done>
</task>

<task type="auto">
  <name>Task 2 (P2 disclosure): Centralize display suppression with complementary-recovery guard</name>
  <files>R/utils/utils_distance_cbc.R, R/165_distance_cbc_association.R</files>
  <action>
  Add one helper (utils_distance_cbc.R), e.g. suppress_by_source_row(), applied to every BY_SOURCE row AFTER all stats computed:
  - Any stratum with a suppressed count cell (interior n_far/n_not_far/n_cbc_far/n_cbc_not_far is "<11") -> blank OR, CI_lo, CI_hi, chi_stat/F_stat, p_value; set test_method = "suppressed".
  - Blank pct_* when its numerator or denominator is suppressed, OR when pct is exactly 0% / 100% and the denominator < 11, OR whenever showing it would reveal a suppressed cell.
  - Re-check complementary suppression: no suppressed cell recoverable from the row's other visible cells (mirror apply_complementary_suppression logic over the row's 2x2 + margins).
  - Suppression is display-only: MH and all stats still use true counts.
  Apply this helper in both BY_SOURCE build loops (enc ~1017-1053, pat ~1053-1110) before rbind.
  Add a check function assert_no_back_calculable(row) that stop()s if any visible cell combination determines a suppressed one; call it per BY_SOURCE row during build.
  </action>
  <verify>
    <automated>node brace-balance; grep confirms suppress_by_source_row + assert_no_back_calculable defined and called in both BY_SOURCE loops</automated>
  </verify>
  <done>Every BY_SOURCE row with any suppressed cell has blanked stats and non-recoverable cells; build stops on a back-calculable violation.</done>
</task>

<task type="auto">
  <name>Task 3 (P3 stats): Clustering-aware per-site tests, heterogeneity, sensitivity formatting, excl-FLM sheet</name>
  <files>R/165_distance_cbc_association.R, R/utils/utils_distance_cbc.R</files>
  <action>
  3.1 Per-site clustering (BY_SOURCE_enc* only): replace per-stratum naive chi2/Fisher with svychisq (Rao-Scott F, ids = ~ID) + svyglm quasibinomial OR + CI within each stratum (same approach as B_test, lines 484-531). Strata where svyglm fails or has zero cells: blank stats, test_method = "not estimable". Rename columns F_stat, p_value, OR, CI_lo, CI_hi, test_method. Keep Fisher/chi2 for pat sheets (one row per patient; no clustering). Add KEY note: MH on enc sheets ignores clustering, descriptive only.
  3.2 Heterogeneity: on each MH_POOLED row add separate columns BD_chi2 and BD_p (Breslow-Day Tarone — already computed ~1174-1203, currently only "BD_df=11"). If BD_p < 0.05 set pooled_valid = FALSE; add KEY note pooling not appropriate under heterogeneity.
  3.3 C_sensitivity presentation (~857-921): present exp(coef) OR + 95% CI (3 dp) and p (<0.001 or 3 dp); drop or hide raw estimate/SE. Label drop rows "N dropped, sequential: missing rurality" / "... then missing payer" / "... then missing SOURCE". Payer: recode unmatched IDs (not in payer_summary) to "Missing" so missing payer is one category; report N recoded; update QC N_missing_payer; note in KEY. Replace "X" placeholder cells with block titles "Whole record" / "Post-anchor".
  3.4 KEY "Why Rao-Scott": build the DEFF text from computed DEFF values in B_test (and SE ratio) instead of hard-coded "DEFF = 130".
  3.5 New sheet D_excl_FLM right after C_sensitivity: run the primary Rao-Scott analysis (same function as B_test, both windows) on encounters with SOURCE_raw NOT in CONFIG$claims_source_codes. Columns: 2x2 counts, row %, F, p, OR, CI, DEFF, N_enc, N_pat. KEY mark: "Exploratory -- pending decision with Amy/Erin (D-165-07); not a replacement for the primary analysis."
  </action>
  <verify>
    <automated>node brace-balance; grep confirms svychisq/svyglm in BY_SOURCE_enc build, BD_chi2/BD_p/pooled_valid columns, D_excl_FLM worksheet added after C_sensitivity, payer Missing recode, DEFF-derived KEY text</automated>
  </verify>
  <done>enc sheets use Rao-Scott/svyglm per stratum; MH rows carry BD_chi2/BD_p/pooled_valid; C_sensitivity shows OR/CI/p with block titles and Missing payer; D_excl_FLM present and labelled exploratory.</done>
</task>

<task type="auto">
  <name>Task 4 (P4 build/format): Clean workbook build, numeric cells, formatting, SUMMARY sheet</name>
  <files>R/165_distance_cbc_association.R</files>
  <action>
  4.1 Dangling drawing parts: find the cause (writeComment / insertImage / loadWorkbook on a template / removeComment). Ensure workbook is built fresh via createWorkbook() (already line 685) with NO drawing relationships unless an image is inserted. After saveWorkbook, add a check: utils::unzip(out_path, list=TRUE) and stop() if any worksheet _rels target a drawing/vmlDrawing part not present in the archive. If the root cause differs from the spec list, report it.
  4.2 Numeric cells: write numeric columns as numeric with number formats — counts "#,##0", percents "0.0%" (store proportions), OR/CI "0.000", F/chi2 "0.00", DEFF "0.0". Keep DF values numeric; write only "<11" / "<0.001" / "" tokens as text. Apply to A_crosstab, B_test, BY_SOURCE_* (openxlsx::createStyle numFmt + addStyle, or writeData numeric + style pass).
  4.3 A_crosstab (write_crosstab_block ~765-817): remove "X" placeholders and blank header row. Each window block: title row ("Whole record"/"Post-anchor"), headers "Distance | CBC: No | CBC: Yes | Total", row labels "<100 mi"/">=100 mi"/"Total"; percent block headers "Distance | % no CBC | % with CBC | Row N".
  4.4 KEY: remove duplicated "Field | Value" header row. Add rows: payer input file name + mtime, N and % cohort IDs matched to payer, R/165 git short hash (system2("git", c("rev-parse","--short","HEAD")) or "not under git"), BY_SOURCE excluded-strata rule (Claims_unresolved excluded from MH; list in each MH_POOLED excluded= cell). KEY stays leftmost.
  4.5 SOURCE_REASSIGN_QC: pct_of_claims_enc only for claims methods (address/modal_encounter/unresolved); blank for not_reassigned; add pct_of_all_enc for every row. Remove the stray "Label" row (~1340-1342) and give the second table its own title row.
  4.6 Non-informative strata: blank OR/CI/p instead of 0.000/Inf; eliminate leading-space " Inf".
  4.7 All tabular sheets: freezePane firstActiveRow (header row(s) frozen), autofilters, keep UF header styling (#0021A5 fill/white bold; #FA4616 accent).
  4.8 SUMMARY sheet immediately after KEY (sheet 2): one table, both windows — primary OR (B_test), adjusted OR (C_sensitivity), excl-FLM OR (D_excl_FLM), and MH pooled OR + BD_p for each reassignment scheme (modal, addr, flm) at enc and pat level. Each row cites its source sheet. Insert worksheet so order is KEY, SUMMARY, then the rest (openxlsx::addWorksheet after KEY, or worksheetOrder).
  </action>
  <verify>
    <automated>node brace-balance; grep confirms unzip post-save check, numFmt styles, SUMMARY worksheet as sheet 2, freezePane/filter calls, git-hash KEY row, pct_of_all_enc</automated>
  </verify>
  <done>Workbook built fresh with no dangling drawing rels (checked post-save); numeric cells formatted; A_crosstab/KEY/QC cleaned; SUMMARY is sheet 2; freeze panes + autofilters applied.</done>
</task>

<task type="auto">
  <name>Task 5 (P5): Baseline-reset flag, decision log D-165-04..08, validator script</name>
  <files>R/165_distance_cbc_association.R, R/00_config.R, R/165_validate_workbook.R</files>
  <action>
  5.1 Regression check (R/165 ~1428-1501): do NOT add a silent bypass. In SUMMARY/report explain how it picks the prior workbook (PRIOR_WB_PATH env R1923_PRIOR_DIST_CBC_WB, default distance_cbc_association_20261110.xlsx) and sheet-by-sheet cell compare. Add CONFIG$r165_accept_new_baseline <- FALSE (R/00_config.R, default FALSE). When TRUE: skip the comparison, message() the reason, and write a KEY row "Baseline reset: <reason>". Change the comparison to match sheet-by-sheet by name and treat sheets present in new but not prior (new sheets) as informational, not failures (only compare the intersection; list new sheets).
  5.2 Append decision entries in the same KEY key_df format as D-165-01..03 (grep D-165-0 in R/165 to find the block ~696-752). Add D-165-04 (address-step reassignment fixed; previously 0 FLM reassigned, _addr==_flm; fill counts after fix), D-165-05 (pat MH now patient-level; MH on all six sheets; BD stat+p), D-165-06 (enc per-site tests -> Rao-Scott/svyglm; sensitivity releveled to largest site, zero-event levels dropped; payer unmatched -> Missing), D-165-07 (D_excl_FLM exploratory; primary choice pending Amy/Erin), D-165-08 (disclosure: stats blanked for any stratum with a suppressed cell). Mirror each into KEY (they are KEY rows).
  5.3 New file R/165_validate_workbook.R (standalone; arg = workbook path, default newest output/distance_cbc_association_*.xlsx via list.files + pin note). stop() with clear message unless, and print PASS/FAIL per check:
    - no dangling drawing rels in archive (unzip list)
    - KEY is sheet 1, SUMMARY is sheet 2
    - A_crosstab cells numeric; whole Total == B_test whole N_enc; post likewise
    - SOURCE_REASSIGN_QC has all four methods and address > 0
    - each _addr sheet differs from its _flm sheet
    - every BY_SOURCE sheet has an MH_POOLED row per window with BD_chi2 and BD_p
    - pat-sheet stratum totals sum to patient N per window
    - no row with a "<11" cell has a non-blank OR/CI/p; no visible pct 0%/100% next to a suppressed count
    - no C_sensitivity SOURCE coefficient |log-OR| > 5
  </action>
  <verify>
    <automated>node brace-balance on R/165, R/00_config.R, R/165_validate_workbook.R; grep confirms r165_accept_new_baseline flag, D-165-04..08 rows, intersection-only sheet compare, validator defines all nine checks with PASS/FAIL prints</automated>
  </verify>
  <done>Baseline-reset flag present (default FALSE) with KEY row + new-sheet-as-informational compare; D-165-04..08 appended and mirrored to KEY; R/165_validate_workbook.R runs standalone with PASS/FAIL per check.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <what-built>All P1-P5 edits to R/165 + utils_distance_cbc.R + R/00_config.R, new R/165_validate_workbook.R, syntax-checked locally via brace-balance.</what-built>
  <how-to-verify>
  On HiPerGator from repo root:
  ```
  module load R/4.5
  R --no-save
  source("R/165_distance_cbc_association.R", local = new.env(parent = globalenv()))
  ```
  Paste back: the assign_analytic_source per-method message (interval / recency / modal / unresolved counts), any stop() error + ~20 lines, the regression-check line, and "Workbook saved". Then validate:
  ```
  source("R/165_validate_workbook.R", local = new.env(parent = globalenv()))
  ```
  Paste back the PASS/FAIL line per check. If a check FAILs, paste its message + ~20 surrounding lines.
  </how-to-verify>
  <resume-signal>Type "approved" with pasted counts, or describe the failure.</resume-signal>
</task>

</tasks>

<verification>
- Node brace-balance passes on R/165_distance_cbc_association.R, R/utils/utils_distance_cbc.R, R/00_config.R, R/165_validate_workbook.R.
- Full diffs shown; .bak exists for every edited file.
- Root cause reported for 1.1 (address reassignment), 1.2 (pat MH), 4.1 (drawing parts); explanation of 5.1 regression picker; list of anything not doable statically.
- HiPerGator run + validator PASS/FAIL pasted back by Gerard (checkpoint).
</verification>

<success_criteria>
- address > 0 in SOURCE_REASSIGN_QC; each _addr sheet differs from its _flm sheet.
- pat MH stratum totals sum to patient N; MH_POOLED with BD_chi2/BD_p on all six BY_SOURCE sheets.
- no C_sensitivity SOURCE |log-OR| > 5.
- validator passes all nine checks.
- D-165-04..08 in KEY; baseline-reset flag default FALSE.
</success_criteria>

<output>
After completion, create `.planning/quick/261110-hne-review-driven-fixes-to-r-165-distance-cb/261110-hne-SUMMARY.md` with: root causes (1.1/1.2/4.1), how 5.1 works, full diffs reference, HiPerGator commands, and anything not statically verifiable. Fill decision-log counts (D-165-04) after Gerard's run.
</output>
