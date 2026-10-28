# Requirements — v3.13 Analytic Manual Fill-out and Verification

**Milestone goal:** Bring `AnalyticManual_2026.01.30.docx` up to date with the work done in this repo. Every existing statement is checked against code and given a verdict. Every empty section the repo can answer is drafted from code, config, planning decisions, and team meeting notes. The result is a reviewed new version of the manual and an evidence workbook tying each statement to its code source.

---

## v1 Requirements

### Evidence Mapping (Phase 190)

- [x] **AM-MAP-01**: Every manual item (including both Amy comments c0/c1) mapped to repo evidence with a status: `FILLED-NEEDS-CHECK`, `EMPTY-REPO-CAN-ANSWER`, `EMPTY-NEEDS-TEAM`, or `OUT-OF-SCOPE`
- [x] **AM-MAP-02**: Repo domains not yet mentioned in the manual identified for addition — including single-health-system flag, MED_ADMIN/DISPENSING chemo detection with NDC→RxNorm, drug-name normalization, first-line regimens, treatment episodes, anthracycline exposure, CBC definition, rurality (RUCA/RUCC), SDI, diagnoses of interest, HL vs NHL classification, and post-death encounters
- [x] **AM-MAP-03**: Team decisions mined from `TeamMtgNotes2026.docx` and all phase CONTEXT.md files; OneFLquestions document status recorded (D-190-01)

### Verification (Phase 191)

- [x] **AM-VER-01**: Every `FILLED-NEEDS-CHECK` row from Phase 190 has a verdict (`MATCH`, `MISMATCH`, `PARTIAL`, or `CANNOT-VERIFY`) with evidence citation (script + function + line, or CONFIG key, or decision ID)
- [x] **AM-VER-02**: Amy's comments c0 and c1 and the Insurance "Gerard to confirm" item each have an explicit answer
- [x] **AM-VER-03**: Each `MISMATCH` recorded as a team decision row (D-191-NN) — neither code nor manual text changed in this milestone
- [x] **AM-VER-04**: Verification script (`R/NNN_am_verification.R`) runs read-only HiPerGator queries for leads L1–L6; L5/L7/L8/L9 covered by code-reading citations; outputs `am_verification_<date>.xlsx` (KEY leftmost, one sheet per check, QC)

### Draft New Content (Phase 192)

- [ ] **AM-FILL-01**: Front matter (§0), §1 Data Ingest & Change Log, §2 Cohort, §3 Decision Log drafted where the repo has a source; every statement tagged with its source
- [ ] **AM-FILL-02**: New §4 domains drafted in the manual's format (Expected structure / Observed issues / Cleaning rules applied / Unresolved issues) for each `EMPTY-REPO-CAN-ANSWER` domain from Phase 190
- [ ] **AM-FILL-03**: §5 EHR vs Claims, §7 Status Tracker, §8 Parking Lot (parked D-IDs from STATE.md), §11 Known Limitations drafted where repo has a source; §6 technical checks annotated with script evidence, sign-off boxes untouched
- [ ] **AM-FILL-04**: Every Phase 191 `MISMATCH` appears in §8 as an open question, not as resolved text

### Updated Manual (Phase 193)

- [ ] **AM-DOC-01**: New versioned manual copy (`AnalyticManual_<YYYY.MM.DD>.docx`) with all Phase 192 content inserted as Word tracked changes authored "Gerard Garvan", each with a comment citing evidence; original file untouched
- [ ] **AM-DOC-02**: Amy's existing comments replied to with Phase 191 answers; document version and "Date last updated" field updated
- [ ] **AM-DOC-03**: Evidence workbook exported as `am_evidence_<date>.xlsx` (KEY leftmost; columns: AM section, item, manual text, verdict/status, repo source, decision ID, notes); no counts 1–10 unsuppressed; no patient IDs in the document

### Team Review and Close-out (Phase 194)

- [ ] **AM-TEAM-01**: Cover email to Amy (cc Erin, Ray) drafted: what was filled, what was confirmed, each mismatch needing a team decision, items needing MPI input; signed "Best, Gerard"
- [ ] **AM-TEAM-02**: Team-decision rows current (D-190-01, D-190-02, D-193-01, all D-191-NN); code changes if any scheduled for a later milestone
- [ ] **AM-TEAM-03**: Verification script listed in R/SCRIPT_INDEX.md. If added to the pipeline, also registered in R/39 and structural checks added to R/88; R/88 passes on HiPerGator. If kept standalone, no R/39 or R/88 change required.

---

## Future Requirements

- Incorporating team responses and agreed-upon code corrections — once D-191-NN decisions are made, scheduled for a later milestone
- Treatment-window and relapse rules (pending Sharon)
- Sign-off sections (§6 boxes) — filled by biostatistician and MPI, not in scope for this milestone

---

## Out of Scope

- Changing pipeline logic to match the manual or vice versa — mismatch → team decision → later milestone
- Filling grant number, project title, or PI/co-I fields without a source in the repo or meeting notes
- Treatment-window and relapse rules (still pending Sharon's input)
- Statistical modeling or new analysis output
- Any new R scripts beyond the verification script (Phase 191); no new numbered analysis scripts

---

## Traceability

| REQ-ID | Phase | Notes |
|--------|-------|-------|
| AM-MAP-01 | 190 | Manual items → evidence map |
| AM-MAP-02 | 190 | Unlisted repo domains |
| AM-MAP-03 | 190 | Team decisions + meeting notes |
| AM-VER-01 | 191 | Verdicts for all FILLED items |
| AM-VER-02 | 191 | Amy's c0/c1 and Insurance question answered |
| AM-VER-03 | 191 | Mismatches → D-191-NN |
| AM-VER-04 | 191 | Verification script + workbook |
| AM-FILL-01 | 192 | §0/§1/§2/§3 drafted |
| AM-FILL-02 | 192 | New §4 domains |
| AM-FILL-03 | 192 | §5/§6/§7/§8/§11 |
| AM-FILL-04 | 192 | Mismatches in §8 only |
| AM-DOC-01 | 193 | Tracked-change .docx |
| AM-DOC-02 | 193 | Amy comments replied to |
| AM-DOC-03 | 193 | Evidence workbook |
| AM-TEAM-01 | 194 | Cover email |
| AM-TEAM-02 | 194 | Decision rows current |
| AM-TEAM-03 | 194 | SCRIPT_INDEX always; R/39 + R/88 only if pipeline-registered |
