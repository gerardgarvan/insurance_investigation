# Patch: Plan 132-04 (R/88 Section 15y regression guard)

**Target:** `13204PLAN.md` (Phase 132, Plan 04\) **Reason:** Three corrections from the soundness review — a real regex bug plus two robustness fixes. The rest of Plan 04 is sound and unchanged.

---

## Summary of changes

1. **\[BUG\] `grepl()` parens.** R's `grepl()` defaults to extended regex, where `(` and `)` are grouping metacharacters — `grepl("library(purrr)", "library(purrr)")` returns `FALSE` (it searches for `librarypurrr`). Every R-level literal-with-parens check must use `fixed = TRUE`. (The shell verifies with basic `grep` are unaffected — parens are literal there — and stay as-is.)  
2. **\[POLARITY\] Check 1 must negate.** The interface examples show positive form `check(desc, grepl(pattern, text))`, but Check 1 passes when the artifact is *absent*, so the condition is `!grepl(...)`. Making this explicit prevents an always-PASS inversion.  
3. **\[ROBUSTNESS\] Loosen the walk count.** Change R/85's guard from exactly `== 2` to `>= 2` so a benign future addition of a legitimate `purrr::walk` doesn't trip a false alarm, while removal/destyling is still caught. Also count over `readLines()` line-by-line rather than a collapsed string.

Check count becomes **8** (6 per-script bare-`n` \+ 1 `library(purrr)` \+ 1 walk-count), so the `SMOKE-132-01` line and `N checks` reference update to `8`.

---

## Replace: Task 1 action, step 2 (the Section 15y block)

Use this exact R implementation for the inserted block. It mirrors the Section 15x `if (file.exists(...)) paste(readLines(...), collapse = "\n") else ""` guard, but factored into a helper, and fixes the three issues above.

\# \==============================================================================

\# SECTION 15y: CRASH FIX REGRESSION GUARD \-- BARE n / MISSING purrr (Phase 132\) \----

\# \==============================================================================

\#

\# Guards CRASH-01 (stray bare \`n\` editor artifact glued onto section-divider

\# comments in R/74, R/81, R/82, R/83, R/84, R/85) and CRASH-02 (R/84's

\# unqualified walk() needing library(purrr) attached) against reintroduction.

\# Pure readLines() \+ grepl() structural checks \-- no data / DuckDB / execution

\# dependency, consistent with every other Section 15x-style guard.

\#

\# NOTE: all literal-with-parens patterns below use fixed \= TRUE. R's grepl()

\# default is extended regex, where "(purrr)" is a capture group, not literal

\# text \-- grepl("library(purrr)", x) would silently never match.

message("\\n\[Phase 132\] Crash fix regression guard (bare n \+ purrr)...")

phase132\_scripts \<- c(

  "R/74\_generate\_documentation.R",

  "R/81\_parity\_test\_cohort.R",

  "R/82\_benchmark\_cohort.R",

  "R/83\_generate\_speedup\_report.R",

  "R/84\_test\_durations.R",

  "R/85\_test\_episodes.R"

)

phase132\_text \<- function(path) {

  if (file.exists(path)) paste(readLines(path, warn \= FALSE), collapse \= "\\n") else ""

}

\# Check 1 (one per script, so a regression is attributable to a specific file):

\# no line begins with a bare \`n \` immediately followed by \`\#\`.

\# POLARITY: PASS when the artifact is ABSENT \-\> condition is negated.

\# perl \= TRUE \+ (?m) so ^ anchors per line inside the collapsed text.

\# nzchar(txt) guard: a missing/empty file degrades to a clean FAIL, not a false PASS.

for (scr in phase132\_scripts) {

  txt \<- phase132\_text(scr)

  check(

    glue("{scr} has no bare 'n' editor-artifact line (Phase 132)"),

    nzchar(txt) && \!grepl("(?m)^n \#", txt, perl \= TRUE)

  )

}

\# Check 2: R/84 attaches library(purrr) (CRASH-02 fix). fixed \= TRUE \-\> literal parens.

r84\_text \<- phase132\_text("R/84\_test\_durations.R")

check(

  "R/84 attaches library(purrr) for walk() (Phase 132)",

  grepl("library(purrr)", r84\_text, fixed \= TRUE)

)

\# Check 3: R/85 retains its purrr::walk(message) call sites (\>= 2, style unchanged).

\# fixed \= TRUE for literal parens; \>= 2 rather than \== 2 tolerates benign additions

\# while still catching removal or a "fix" that destyles them to bare walk().

r85\_lines  \<- if (file.exists("R/85\_test\_episodes.R")) readLines("R/85\_test\_episodes.R", warn \= FALSE) else character(0)

r85\_walk\_n \<- sum(grepl("purrr::walk(message)", r85\_lines, fixed \= TRUE))

check(

  glue("R/85 retains \>= 2 purrr::walk(message) call sites (found {r85\_walk\_n}) (Phase 132)"),

  r85\_walk\_n \>= 2

)

---

## Replace: Task 1 action, step 3 (summary line)

message("  \* SMOKE-132-01: R/88 validates Phase 132 bare-n crash fix \+ R/84 purrr attachment structural integrity (Section 15y, 8 checks)")

(`8` \= 6 per-script bare-`n` checks \+ 1 `library(purrr)` check \+ 1 walk-count check. If you keep Check 1 as a single combined check instead of 6, adjust to `3`.)

---

## Replace: Task 1 `<verify>` automated (unchanged in intent, count made explicit)

cd "C:/Users/ggarv/OneDrive/Documents/insurance\_investigation" \\

  && grep \-c "SECTION 15y" R/88\_smoke\_test\_comprehensive.R \\

  && grep \-c "SMOKE-132-01" R/88\_smoke\_test\_comprehensive.R \\

  && test "$(grep \-c 'check(.\*Phase 132' R/88\_smoke\_test\_comprehensive.R)" \= "8"

---

## Amend: Task 2 negative-control scope

The existing negative control (reintroduce a bare `n` into a throwaway copy, confirm FAIL) covers **Check 1 only**. Because Checks 2 and 3 previously had no backstop — and the paren bug above would have made them silently mis-fire — extend the sanity check to prove they are non-tautological too:

- **Check 2 negative control:** on a throwaway copy of `R/84` with the `library(purrr)` line deleted, re-run just the Check 2 logic and confirm it reports **FAIL**.  
- **Check 3 negative control:** on a throwaway copy of `R/85` with one `purrr::walk(message)` removed (leaving one), confirm the `>= 2` check reports **FAIL**.

Discard all throwaway copies — leave no scratch files in the repo.

Updated `<done>` for Task 2:

> Running `R/88_smoke_test_comprehensive.R` shows all 8 Phase-132 checks (Section 15y) as PASS, with zero Phase-132-tagged FAIL lines. Three negative-control tests confirm the guards are genuine: reintroducing a bare `n`, removing `library(purrr)` from R/84, and dropping an R/85 `purrr::walk(message)` each independently flip their check to FAIL.

---

## Not changed

Wave/dependency ordering (wave 2, depends\_on 01/02/03), the insertion point after Section 15x, the `readLines` \+ `check()` pattern, and Task 2's overall run-and-grep flow are all sound and remain as written. Task 2's `! grep -c "FAIL.*Phase 132" ... | grep -qv "^0$"` verify is correct as-is (it succeeds only when the count is `0`).  
