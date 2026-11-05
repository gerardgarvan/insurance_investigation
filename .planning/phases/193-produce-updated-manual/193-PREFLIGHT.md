# 193-PREFLIGHT.md — Phase 193 Preflight Inventory (D-11)

**Generated:** 2026-11-05  
**Source:** AnalyticManual_2026.01.30.docx (READ-ONLY)  
**All values come from live inspection, not copied from RESEARCH.md.**

## 1. Original Integrity

- **SHA-256 (live):** `2e119764b63cf9e491decc1177ff38ea49335cd2f15673b9e92b68a127a1517d`
- **SHA-256 (pinned from am_source_hashes.txt):** `2e119764b63cf9e491decc1177ff38ea49335cd2f15673b9e92b68a127a1517d`
- **Match:** YES — file is unchanged

## 2. Package Parts and Relationships

### All parts in zip:

- `[Content_Types].xml`
- `_rels/.rels`
- `customXml/_rels/item1.xml.rels`
- `customXml/item1.xml`
- `customXml/itemProps1.xml`
- `docProps/app.xml`
- `docProps/core.xml`
- `word/_rels/document.xml.rels`
- `word/comments.xml`
- `word/commentsExtended.xml`
- `word/commentsExtensible.xml`
- `word/commentsIds.xml`
- `word/document.xml`
- `word/fontTable.xml`
- `word/numbering.xml`
- `word/people.xml`
- `word/settings.xml`
- `word/styles.xml`
- `word/theme/theme1.xml`
- `word/webSettings.xml`

### Parts of interest:

- `word/comments.xml`: PRESENT
- `word/commentsExtended.xml`: PRESENT
- `word/commentsIds.xml`: PRESENT
- `word/commentsExtensible.xml`: PRESENT
- `word/people.xml`: PRESENT
- `word/settings.xml`: PRESENT
- Headers/footers: NONE present

- `word/settings.xml` contains `<w:trackChanges>`: NO — not present (must be added before writing revisions)

## 3. ID Space

- **Existing `w:id` values:** `[0, 1]`
- **Max `w14:paraId` (hex):** `7FF8A73E`
- **Total `w14:paraId` count:** 517
- **Existing `w16cid:durableId` values:** `['1001813816', '1154645863', '1247760374', '1451781163', '1666546038', '1671905087', '1905950468', '1926912532', '1956598289', '2043168099', '2057316383', '2120835157', '22875503', '243882112', '2A01C95F', '326054703', '432866374', '465199464', '47799969', '551817431', '556548087', '57CE3336', '65688781', '66389628', '793520472', '80762383', '999113106']`

### Safe starting values for new IDs:

- **w:id start:** 2 (= max existing + 1; existing max is 1)
- **w14:paraId counter start:** `7FF8A73F` (= hex max + 1 above `7FF8A73E`)
- **w16cid:durableId:** must avoid `['1001813816', '1154645863', '1247760374', '1451781163', '1666546038', '1671905087', '1905950468', '1926912532', '1956598289', '2043168099', '2057316383', '2120835157', '22875503', '243882112', '2A01C95F', '326054703', '432866374', '465199464', '47799969', '551817431', '556548087', '57CE3336', '65688781', '66389628', '793520472', '80762383', '999113106']`; use a random 8-hex value not in that set

## 4. Existing Comments (c0, c1)

Comments identified by AUTHOR and TEXT (not by assumed numeric ID).

### Comment w:id=0 — c0 (by anchor paraId 7AA45245)

- **Author:** Crisp, Amy
- **Initials:** CA
- **Date:** 2026-10-23T13:35:00Z
- **Body paragraph paraId:** `4AFA1B64`
- **Body text (truncated to 120 chars):** 'Reference OneFLquestions document to ensure everything has made it into here.'
- **Anchored document paragraph paraId:** `7AA45245`
- **Anchor text (concatenated runs, first 120 chars):** '4. Data Cleaning and Harmonization Rules'

### Comment w:id=1 — c1 (by anchor paraId 106EBCC1)

- **Author:** Crisp, Amy
- **Initials:** CA
- **Date:** 2026-10-23T13:31:00Z
- **Body paragraph paraId:** `0EC496CC`
- **Body text (truncated to 120 chars):** 'Gerard to confirm this is what’s in the code.'
- **Anchored document paragraph paraId:** `106EBCC1`
- **Anchor text (concatenated runs, first 120 chars):** 'Use diagnosis date from Tumor Registry as default.'

### Comment paraId mapping (key values for threading):

| Label | w:id | Body paraId | Anchor paraId |
|-------|------|-------------|---------------|
| (see above) | 0 | `4AFA1B64` | `7AA45245` |
| (see above) | 1 | `0EC496CC` | `106EBCC1` |

Note: live body-paragraph paraIds are `4AFA1B64`, `0EC496CC`. RESEARCH.md expected `4AFA1B64` and `0EC496CC`.
  - `4AFA1B64` matches RESEARCH.md expected value. ✓
  - `0EC496CC` matches RESEARCH.md expected value. ✓

## 5. Target Locations

### 5a. Section Headings

| para_idx | Style | Text (first 80 chars) |
|----------|-------|-----------------------|
| 0 | Heading1 | Analytic Manual (AM): Blood Cancer United Hodgkin Lymphoma Study |
| 1 | Heading2 | 0. Front Matter (Update with Each Data Freeze) |
| 15 | Heading2 | 1. Data Ingest & Change Log |
| 43 | Heading2 | 2. Cohort Construction History |
| 76 | Heading2 | 3. Variable and Phenotype Decision Log |
| 115 | Heading2 | 4. Data Cleaning and Harmonization Rules |
| 229 | Heading2 | 5. Cross-System Reconciliation (EHR vs Claims) |
| 241 | Heading2 | 6. Quality Assurance and Validation Checklist |
| 250 | Heading2 | 7. Analysis Status Tracker |
| 272 | Heading2 | 8. Open Questions and Decision Parking Lot |
| 279 | Heading2 | 9. How to Use This Living Analytic Manual (Team Guidance) |
| 296 | Heading2 | 10. Optional Enhancements and Companion Materials |
| 304 | Heading2 | 11. Known Data Limitations and Implications |
| 324 | Heading2 | APPENDIX A. Embedded Working Tables |
| 452 | Heading2 | APPENDIX B. One-Page SOP: Using the Analytic Manual |

### 5b. §4 Domain Fields

| para_idx | Style | Label | Populated? |
|----------|-------|-------|------------|
| 117 | Normal | Domain: Cancer Diagnosis Date | populated |
| 127 | Normal | Domain: Source | check context |
| 137 | Normal | Domain: Cancer Diagnosis | populated |
| 146 | Normal | Domain: Insurance | check context |
| 162 | Normal | Domain: ADI | check context |
| 173 | Normal | Domain: Treatment Window (in order to define survivorship) | populated |
| 183 | Normal | Domain: Initial treatment vs. relapse | populated |
| 193 | Normal | Domain: Death | check context |
| 206 | Normal | Domain: Survivorship encounters | populated |
| 217 | Normal | Domain: Distance from patient to encounter location | populated |

### 5c. §0 Front-Matter Fields (Document version and Date last updated)

- **Document version** — para_idx=7, style='Normal', location=body, text: 'Document version: '

- **Date last updated** — para_idx=8, style='Normal', location=body, text: 'Date last updated: 9/3/2026'

Note: These fields are in the body (word/document.xml). No headers or footers exist in this document.

### 5d. §8 Structure

- **§8 heading at para_idx:** 272
- **§8 has existing table:** NO — has no existing table; a new tracked table must be inserted (Pitfall 3)

ListParagraph / xxmsolistparagraph items found in §8:

  - para_idx=273: 'Questions requiring MPI input: '
  - para_idx=274: ''
  - para_idx=275: 'Deferred decisions: '
  - para_idx=276: ''
  - para_idx=277: 'Known limitations to document for manuscripts: '
  - para_idx=278: ''

## 6. Styles Available

Styles observed in body paragraphs (live read):

- `Heading1`
- `Heading2`
- `ListParagraph`
- `xxmsolistparagraph`

Paragraphs with no explicit style (blank pStyle) render as `Normal`.

Constraint (M1/M2): new subsections must reuse existing styles only (Heading1, Heading2, Normal, ListParagraph, xxmsolistparagraph). No new styles.

## 7. Safe ID Allocation Summary (for Plan 02 insertion engine)

| ID type | Safe start | Avoid |
|---------|-----------|-------|
| `w:id` | 2 | `[0, 1]` |
| `w14:paraId` | `7FF8A73F` | all 517 existing values; max was `7FF8A73E` |
| `w16cid:durableId` | random 8-hex | `['1001813816', '1154645863', '1247760374', '1451781163', '1666546038', '1671905087', '1905950468', '1926912532', '1956598289', '2043168099', '2057316383', '2120835157', '22875503', '243882112', '2A01C95F', '326054703', '432866374', '465199464', '47799969', '551817431', '556548087', '57CE3336', '65688781', '66389628', '793520472', '80762383', '999113106']` |
