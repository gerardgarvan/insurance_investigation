# Phase 107: Gap Resolution Report & Delivery - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-06-15
**Phase:** 107-gap-resolution-report-delivery
**Areas discussed:** Report structure, Presentation quality, Meeting notes update, Delivery manifest

---

## Report Structure

### Section Organization

| Option | Description | Selected |
|--------|-------------|----------|
| By gap number | Sections mapped to G1-G15 gap items from meeting notes -- directly ties findings to the questions the team originally asked | :heavy_check_mark: |
| By investigation phase | Grouped by Phase 104/105/106 -- follows the order work was done | |
| By topic area | Grouped thematically: Treatment Timing, Code Quality, Overlap Analysis, Tableau Tables -- readable narrative flow | |

**User's choice:** By gap number
**Notes:** None

### Section Content

| Option | Description | Selected |
|--------|-------------|----------|
| Finding + key table | 1-2 paragraph summary per gap, plus the most important table from the investigation xlsx -- concise for meeting review | :heavy_check_mark: |
| Full data tables | Pull in all tables from investigation xlsx files -- comprehensive but longer | |
| Narrative only | Text summaries with no embedded tables -- reference the xlsx files for data detail | |

**User's choice:** Finding + key table
**Notes:** None

### Data Source

| Option | Description | Selected |
|--------|-------------|----------|
| Read xlsx files | readxl::read_excel() to pull key tables from existing output xlsx files -- simpler, no re-execution needed, report is a presentation layer | :heavy_check_mark: |
| Source R scripts | source() the investigation scripts so data is always fresh -- slower, but guarantees report matches current data | |
| Read RDS artifacts | Load intermediate .rds files from cache -- faster than xlsx but requires pipeline to have run | |

**User's choice:** Read xlsx files
**Notes:** None

### Gap Scope

| Option | Description | Selected |
|--------|-------------|----------|
| v3.2 resolved gaps only | G1, G2, G3, G4, G5, G8, G10, G11, G15, plus TABLE-1/TABLE-2 | :heavy_check_mark: |
| All gaps with status | Include ALL G1-G15 with status for each (resolved, pending external, deferred) | |
| You decide | Claude decides the right scope | |

**User's choice:** v3.2 resolved gaps only
**Notes:** None

---

## Presentation Quality

### Formatting Level

| Option | Description | Selected |
|--------|-------------|----------|
| Clean internal report | Professional but not publication-quality -- clean tables, section headers, TOC, readable fonts | :heavy_check_mark: |
| Minimal/plain | Default rmarkdown::html_document with no extra styling | |
| Polished with branding | Custom CSS, UF/project branding, formatted title page | |

**User's choice:** Clean internal report
**Notes:** None

### Executive Summary

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, with key findings | Brief executive summary listing each gap investigated and its one-line resolution | :heavy_check_mark: |
| No summary | Jump straight into gap-by-gap sections | |
| You decide | Claude decides based on report length and content | |

**User's choice:** Yes, with key findings
**Notes:** None

### Table Rendering

| Option | Description | Selected |
|--------|-------------|----------|
| kableExtra static tables | Static HTML tables -- renders cleanly in self-contained HTML, no JavaScript dependencies, prints well | :heavy_check_mark: |
| DT interactive tables | Interactive searchable/sortable tables via DT::datatable -- more interactive but requires JavaScript | |
| You decide | Claude picks the best approach per table | |

**User's choice:** kableExtra static tables
**Notes:** None

---

## Meeting Notes Update

### Gap Marking Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Inline resolution notes | Add resolution line below each resolved gap -- original text preserved with phase reference and key finding | :heavy_check_mark: |
| Strikethrough + note | Strikethrough original gap text and add resolution note | |
| Move to resolved section | Create 'Resolved Gaps' section and move resolved items there | |

**User's choice:** Inline resolution notes
**Notes:** None

### Stale Item Definition

| Option | Description | Selected |
|--------|-------------|----------|
| Completed action items only | Remove Gerard's completed action items from v3.1/v3.2 work. Leave other people's items untouched | :heavy_check_mark: |
| All completed items across all people | Remove completed action items for everyone | |
| Don't remove, just mark | Mark completed items with checkmarks but don't remove anything | |

**User's choice:** Completed Gerard action items only
**Notes:** None

---

## Delivery Manifest

### Format

| Option | Description | Selected |
|--------|-------------|----------|
| R script generating xlsx | R script scans output/ for v3.1+v3.2 files, generates xlsx with filename, description, phase, date modified, size | :heavy_check_mark: |
| Static markdown file | Hand-written markdown listing | |
| Console-only inventory | R script prints to console/log only | |

**User's choice:** R script generating xlsx listing
**Notes:** None

### Validation

| Option | Description | Selected |
|--------|-------------|----------|
| List + validate | Generate listing AND check each expected file exists, flagging missing files | :heavy_check_mark: |
| List only | Just produce the listing with descriptions | |
| You decide | Claude decides based on implementation simplicity | |

**User's choice:** List + validate
**Notes:** None

### Scope

| Option | Description | Selected |
|--------|-------------|----------|
| v3.1 + v3.2 new outputs | All new outputs from v3.1 (Phases 100-103) and v3.2 (Phases 104-107) | :heavy_check_mark: |
| v3.2 only | Just Phase 104-107 outputs | |
| All output files | Everything in output/ regardless of milestone | |

**User's choice:** v3.1 + v3.2 new outputs
**Notes:** None

---

## Claude's Discretion

- Script numbering, RMarkdown YAML details, kableExtra styling, column selection, resolution note wording, R/88 smoke test sections

## Deferred Ideas

None -- discussion stayed within phase scope
