# Phase 193: Produce Updated Manual - Research

**Researched:** 2026-10-28
**Domain:** OOXML tracked changes, comment threading, lxml XML editing, python-docx, evidence workbook (openpyxl)
**Confidence:** HIGH (all findings verified directly against the live DOCX package and source code)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Unpack `.docx`, edit XML with lxml, repack. python-docx for reading only.
- **D-04:** Write only to the new versioned copy in `docs/analytic_manual/`. Stop if filename exists unless `--overwrite`. Record build ID (timestamp + git commit). Verify original SHA-256 at start and end.
- **D-06/D-07:** If threading cannot be produced reliably, fall back to new comment on same anchor prefixed "Re: Amy's comment —". Record outcome as `THREADED-REPLY` or `FALLBACK-COMMENT` in manifest and workbook.
- **D-08:** New subcommand `manual-export` (not a change to `export`). Existing `export` output unchanged; regression check before and after.
- **D-09/D-17:** Workbook sheets: KEY (leftmost), Operations, Open Items, Reconciliation.
- **D-10:** UF colours `#0021A5` / `#FA4616`; KEY leftmost; no patient IDs; count suppression for patient/result counts only.
- **D-11:** Write `193-PREFLIGHT.md` recording original SHA-256, package parts, existing tracked changes, comments, bookmarks, content controls, fields, and paragraph/table location of every target.
- **D-12:** Tracked-change construction rules for INSERT-PARA, w:ins runs, w:del runs, inserted table rows (w:trPr/w:ins), unique w:id, author="Gerard Garvan", build timestamp, formatting from surrounding paragraph. Set `w:trackRevisions` in `settings.xml`.
- **D-12a:** Anchor matching against DOCX XML (not markdown). Exactly one match per paragraph or cell. ANCHOR-FAILED if zero, multiple, or span across boundaries. Build fails unless every failure resolved.
- **D-13:** Build `193-OPERATIONS.json` deterministically before writing XML. One operation per logical edit. Record physical IDs after writing.
- **D-14:** Threaded replies: new comment in `comments.xml` + new `w14:paraId` + `w15:commentEx` with `w15:paraIdParent` in `commentsExtended.xml` + update `commentsIds.xml` and `people.xml`. Same anchor range as original. Original comments unchanged.
- **D-15:** Verification: well-formed XML, uniqueness checks, reject-all == original text, accept-all contains inserted text, untouched content byte-identical, pandoc cross-check, LibreOffice PDF render, human Word review.
- **D-16:** Phase completion states: `ARTIFACTS-GENERATED` → `AUTOMATED-QA-PASSED` → `WORD-REVIEW-APPROVED`.
- **D-34:** Strip only draft-control metadata (`[S4-…]` tags, `STATUS:`, `CITE:` lines, trailing Map ID/Status/Cite table columns). Substantive references stay in body text.
- **M1/M2:** Classify every unit by destination: empty field (fill), populated field (insert after last existing paragraph), new subsection (repo-only domains, existing heading styles only), table row, front-matter field.

### Claude's Discretion

- Insertion code as standalone script in `tools/am_evidence/` or a subcommand, provided `manual-export` stays separate from `export`.
- Exact column order within the Operations sheet.

### Deferred Ideas (OUT OF SCOPE)

None.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| AM-DOC-01 | New versioned manual copy with all Phase 192 content as Word tracked changes authored "Gerard Garvan", each with a comment citing evidence; original untouched | Sections: Tracked-change construction, ID uniqueness, anchor matching, document structure inventory |
| AM-DOC-02 | Amy's existing comments replied to with Phase 191 answers; document version and "Date last updated" field updated | Sections: Comment threading, existing comments inventory, front matter structure |
| AM-DOC-03 | Evidence workbook `am_evidence_<date>.xlsx` (KEY leftmost; columns per D-09/D-17; no suppressed counts; no patient IDs) | Sections: openpyxl reuse patterns, workbook schema, manual-export subcommand |
</phase_requirements>

---

## Summary

Phase 193 produces a versioned DOCX by editing raw OOXML with lxml, then repacking the zip. The source document (`AnalyticManual_2026.01.30.docx`) has been fully inspected: SHA-256 is known, it contains no existing tracked changes, two comments from Amy (IDs 0 and 1, paraIds `4AFA1B64` and `0EC496CC`), and all four threading parts (`commentsExtended.xml`, `commentsIds.xml`, `commentsExtensible.xml`, `people.xml`) are already present in the package. No headers or footers exist (word/document.xml only), which simplifies front-matter targeting. The document has 473 paragraphs across 8 tables, 42 rows, with max `w14:paraId` of `7FF8A73E` and max `w:id` of `1` (only the two Amy comments).

AM-DRAFT.md contains 138 units: 95 DRAFTED, 33 TEAM-INPUT-NEEDED, 8 OPEN-QUESTION-SEE-§8, and 2 CORRECTION blocks. §8 has 41 data rows. These numbers feed the expected-operation count in the manifest — not all units produce revisions (TEAM-INPUT-NEEDED produces a `[TEAM INPUT NEEDED]` placeholder as a tracked insertion; OPEN-QUESTION-SEE-§8 produces a comment only if it fills an empty field).

The `_parse_draft()` function in `tools/am_evidence/am_evidence_map.py` returns a dict with keys `units` (list of dicts with `type`, `status`, `id_tags`, `cites`, `line_num`, `raw`), `s8_rows`, `repo_only_blocks`, `s1_rows`, `s3_rows`, `a1_rows`, `a3_rows`. CORRECTION directives carry additional fields `anchor`, `anchor_line`, `action`, `target`. The `cmd_export` function (openpyxl, UF colours already implemented) is directly reusable as a template for `cmd_manual_export`.

**Primary recommendation:** Build the insertion script as a new `cmd_manual_export` subcommand in `tools/am_evidence/am_evidence_map.py`, calling `_parse_draft()` for unit enumeration, doing all XML editing with lxml, and producing the workbook with openpyxl following the existing `cmd_export` pattern.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| python-docx | 1.2.0 | Read DOCX structure (paragraph text, table layout) before editing | Already installed; used only for reading per D-01 |
| lxml | 6.0.2 | Parse, edit, and serialize OOXML XML trees | Only way to construct `w:ins`/`w:del`/`w:trPr/w:ins` with correct namespaces |
| openpyxl | 3.1.5 | Write evidence workbook | Already used by `cmd_export`; UF colour patterns already coded |
| zipfile (stdlib) | — | Unpack / repack `.docx` | Standard approach; `shutil.copy2` preserves original |
| hashlib (stdlib) | — | SHA-256 verification of original at start and end | Required by D-04 |
| json (stdlib) | — | Write `193-OPERATIONS.json` manifest | D-13 |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| pandoc | 3.13 (Windows) | Cross-check insertion/deletion/comment markers against manifest | Verification step D-15 only; not in Windows PATH in Bash, must use full path or `subprocess` with Windows path |
| LibreOffice | check install | Headless PDF render for layout check | Verification step D-15 only; may not be installed, skip with recorded reason |
| xlsxwriter | 3.2.9 | Alternative xlsx writer | Not needed; openpyxl already used by the tool |

**Installation:** No new installs required. All core libraries confirmed present locally.

---

## Architecture Patterns

### Recommended Project Structure

```
tools/am_evidence/
├── am_evidence_map.py          # add cmd_manual_export subcommand here
├── am_manual_insert.py         # (alternative) standalone script — Claude's discretion
.planning/phases/193-produce-updated-manual/
├── 193-PREFLIGHT.md            # D-11: produced by Wave 0 preflight task
├── 193-OPERATIONS.json         # D-13: produced before XML editing
docs/analytic_manual/
├── AnalyticManual_2026.01.30.docx   # original — never modified
└── AnalyticManual_2026.10.28.docx   # versioned output
output/
└── am_evidence_20261028.xlsx        # workbook — also copied to phase folder at closeout
```

### Pattern 1: DOCX Unpack / Edit / Repack

```python
import zipfile, shutil, hashlib
from pathlib import Path
from lxml import etree

def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

# 1. Verify original
orig = Path("docs/analytic_manual/AnalyticManual_2026.01.30.docx")
assert sha256(orig) == KNOWN_SHA256, "Original modified — abort"

# 2. Copy to versioned output
out = Path("docs/analytic_manual/AnalyticManual_2026.10.28.docx")
if out.exists() and not args.overwrite:
    raise SystemExit("Output exists; use --overwrite")
shutil.copy2(orig, out)

# 3. Read parts into memory
parts = {}
with zipfile.ZipFile(out) as z:
    for name in z.namelist():
        parts[name] = z.read(name)

# 4. Edit XML parts with lxml (see patterns below)
doc_tree = etree.fromstring(parts["word/document.xml"])
# ... mutations ...
parts["word/document.xml"] = etree.tostring(doc_tree, xml_declaration=True,
                                             encoding="UTF-8", standalone=True)

# 5. Repack atomically
tmp = out.with_suffix(".tmp")
with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
    for name, data in parts.items():
        z.writestr(name, data)
tmp.replace(out)

# 6. Verify original still unchanged
assert sha256(orig) == KNOWN_SHA256, "Original SHA-256 changed — ABORT"
```

### Pattern 2: OOXML Namespace Constants

```python
# All namespaces in use in this DOCX (verified from package XML)
NS = {
    "w":    "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "w14":  "http://schemas.microsoft.com/office/word/2010/wordml",
    "w15":  "http://schemas.microsoft.com/office/word/2012/wordml",
    "w16cid": "http://schemas.microsoft.com/office/word/2016/wordml/cid",
    "r":    "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "xml":  "http://www.w3.org/XML/1998/namespace",
}

def qn(ns_key, local):
    return f"{{{NS[ns_key]}}}{local}"

# Example: build w:ins element
def make_ins(rev_id: int, author: str, date: str) -> etree._Element:
    el = etree.Element(qn("w", "ins"))
    el.set(qn("w", "id"), str(rev_id))
    el.set(qn("w", "author"), author)
    el.set(qn("w", "date"), date)   # ISO 8601: "2026-10-28T00:00:00Z"
    return el
```

### Pattern 3: Tracked Insertion of a New Paragraph

A new paragraph inserted as a tracked change requires:
1. The paragraph element (`w:p`) with a new `w14:paraId` attribute.
2. `w:pPr/w:rPr/w:ins` — the paragraph-mark insertion marker (so accept/reject applies to the whole paragraph).
3. `w:ins` wrapping each `w:r` run inside the paragraph.
4. `xml:space="preserve"` on `w:t` when the text begins or ends with a space.

```python
def make_tracked_paragraph(text: str, rev_id: int, author: str, date: str,
                            para_id: str, pPr_source=None) -> etree._Element:
    """
    Returns a w:p element that, when accepted, inserts `text` as a new paragraph.
    para_id: unique 8-hex-char string.
    pPr_source: optional lxml element to copy formatting from (the preceding paragraph's w:pPr).
    """
    W = NS["w"]
    p = etree.Element(qn("w", "p"))
    p.set(qn("w14", "paraId"), para_id)

    # Paragraph properties with mark-insertion
    pPr = etree.SubElement(p, qn("w", "pPr"))
    if pPr_source is not None:
        for child in pPr_source:
            pPr.append(copy.deepcopy(child))
    rPr_in_pPr = etree.SubElement(pPr, qn("w", "rPr"))
    ins_mark = etree.SubElement(rPr_in_pPr, qn("w", "ins"))
    ins_mark.set(qn("w", "id"), str(rev_id))
    ins_mark.set(qn("w", "author"), author)
    ins_mark.set(qn("w", "date"), date)

    # Run wrapped in w:ins
    ins = etree.SubElement(p, qn("w", "ins"))
    ins.set(qn("w", "id"), str(rev_id + 1))   # each w:ins needs a unique w:id
    ins.set(qn("w", "author"), author)
    ins.set(qn("w", "date"), date)
    r = etree.SubElement(ins, qn("w", "r"))
    t = etree.SubElement(r, qn("w", "t"))
    t.text = text
    if text.startswith(" ") or text.endswith(" "):
        t.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")

    return p
```

### Pattern 4: Tracked Deletion

```python
def make_tracked_deletion(run_el, rev_id: int, author: str, date: str) -> etree._Element:
    """
    Wraps an existing w:r element in w:del, converting w:t to w:delText.
    `run_el` is a deep copy of the original run.
    """
    w_del = etree.Element(qn("w", "del"))
    w_del.set(qn("w", "id"), str(rev_id))
    w_del.set(qn("w", "author"), author)
    w_del.set(qn("w", "date"), date)
    # Rename w:t → w:delText in the run copy
    for t_el in run_el.findall(qn("w", "t")):
        t_el.tag = qn("w", "delText")
        if (t_el.text or "").startswith(" ") or (t_el.text or "").endswith(" "):
            t_el.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
    w_del.append(run_el)
    return w_del
```

### Pattern 5: Inserted Table Row

```python
# w:trPr/w:ins on the row; w:ins runs in each cell; cell properties copied from existing row
def make_tracked_row(cells_text: list[str], template_row, rev_id: int,
                     author: str, date: str, para_id_factory) -> etree._Element:
    import copy
    row = copy.deepcopy(template_row)
    # Add w:trPr/w:ins
    trPr = row.find(qn("w", "trPr"))
    if trPr is None:
        trPr = etree.SubElement(row, qn("w", "trPr"))
        row.insert(0, trPr)
    ins_trPr = etree.SubElement(trPr, qn("w", "ins"))
    ins_trPr.set(qn("w", "id"), str(rev_id))
    ins_trPr.set(qn("w", "author"), author)
    ins_trPr.set(qn("w", "date"), date)
    # Fill each cell with tracked insertions
    for tc, text in zip(row.findall(qn("w", "tc")), cells_text):
        for p in tc.findall(qn("w", "p")):
            tc.remove(p)
        p_new = make_tracked_paragraph(text, rev_id + 1, author, date,
                                        para_id_factory())
        tc.append(p_new)
    return row
```

### Pattern 6: Comment Threading (threaded reply)

Existing comments:
- c0: `w:id="0"`, author="Crisp, Amy", paraId in comment body = `4AFA1B64`, anchor paragraph paraId = `7AA45245`
- c1: `w:id="1"`, author="Crisp, Amy", paraId in comment body = `0EC496CC`, anchor paragraph paraId = `106EBCC1`

To produce a threaded reply to c0 (reply to c1 is analogous):

**In `word/comments.xml`:** Add a new `w:comment` element with a new `w:id` (e.g., 2), `w:author="Gerard Garvan"`, `w:initials="GG"`, `w:date`. Give its internal `w:p` a new unique `w14:paraId` (e.g., `7FF8A73F`).

**In `word/commentsExtended.xml`:** Add a `w15:commentEx` element:
```xml
<w15:commentEx w15:paraId="7FF8A73F" w15:paraIdParent="4AFA1B64" w15:done="0"/>
```
`w15:paraIdParent` = the paraId of c0's body paragraph (`4AFA1B64`). This is the threading mechanism. Word uses this to render the reply nested under Amy's comment.

**In `word/commentsIds.xml`:** Add a `w16cid:commentId` for the new comment paragraph:
```xml
<w16cid:commentId w16cid:paraId="7FF8A73F" w16cid:durableId="XXXXXXXX"/>
```
durableId is a random 8-hex-char value not colliding with existing ones (`57CE3336`, `2A01C95F`).

**In `word/document.xml`:** The reply shares the same `w:commentRangeStart`/`w:commentRangeEnd` markers as the original (ids 0 and 1). Add a new `w:commentReference` with the new comment's `w:id` in the same run position as the original `commentReference`. This ensures the reply is anchored at the same location.

**`people.xml`:** Add an entry for "Gerard Garvan" if not already present.

```python
# Threading XML construction example
def make_reply_comment(new_id: int, new_para_id: str, parent_para_id: str,
                        author: str, initials: str, date: str, text: str) -> etree._Element:
    cmt = etree.Element(qn("w", "comment"))
    cmt.set(qn("w", "id"), str(new_id))
    cmt.set(qn("w", "author"), author)
    cmt.set(qn("w", "initials"), initials)
    cmt.set(qn("w", "date"), date)
    p = etree.SubElement(cmt, qn("w", "p"))
    p.set(qn("w14", "paraId"), new_para_id)
    r = etree.SubElement(p, qn("w", "r"))
    t = etree.SubElement(r, qn("w", "t"))
    t.text = text
    return cmt

def make_commentEx(para_id: str, parent_para_id: str) -> etree._Element:
    el = etree.Element(qn("w15", "commentEx"))
    el.set(qn("w15", "paraId"), para_id)
    el.set(qn("w15", "paraIdParent"), parent_para_id)
    el.set(qn("w15", "done"), "0")
    return el
```

### Pattern 7: Anchor Matching (Run-text concatenation)

The anchor text from a CORRECTION directive must be matched against the concatenated `w:t` text of candidate paragraphs, not against raw XML.

```python
def get_para_text(para_el) -> str:
    """Concatenate all w:t values in a paragraph element."""
    parts = []
    for t in para_el.iter(qn("w", "t")):
        parts.append(t.text or "")
    return "".join(parts)

def find_anchor_para(doc_tree, anchor_text: str):
    """
    Returns the single paragraph element whose concatenated run text contains anchor_text.
    Raises AnchorFailed if 0 or >1 matches.
    """
    matches = []
    for p in doc_tree.iter(qn("w", "p")):
        if anchor_text in get_para_text(p):
            matches.append(p)
    if len(matches) != 1:
        raise AnchorFailed(f"anchor '{anchor_text}' matched {len(matches)} paragraphs")
    return matches[0]
```

For a CORRECTION (replace anchor text within a paragraph), the algorithm must:
1. Find the exact runs whose concatenated text spans the anchor.
2. Split boundary runs at the anchor boundary, preserving their `w:rPr`.
3. Wrap the anchor runs in `w:del`, preserving `w:rPr` with `w:delText`.
4. Insert a `w:ins` run with the replacement text using surrounding `w:rPr`.

### Pattern 8: Reject-all and Accept-all Algorithms

**Reject-all (must reproduce original text exactly):**
- Find every `w:ins` element created by this build (identified by `w:author="Gerard Garvan"` and matching rev IDs in the manifest).
- Remove each `w:ins` and all its content from its parent.
- Find every `w:del` created by this build.
- Remove the `w:del` wrapper, moving the runs inside back to the parent (converting `w:delText` → `w:t`).
- The resulting text of every paragraph must equal the original paragraph text (verified by pre-collecting original paragraph texts).

**Accept-all:**
- Find every `w:ins` created by this build.
- Remove the `w:ins` wrapper, keeping the runs inside in place.
- Find every `w:del` created by this build.
- Remove the `w:del` and all its content.
- Verify each operation's inserted text appears once in the resulting document text.

```python
BUILD_AUTHOR = "Gerard Garvan"

def reject_all(doc_tree, build_rev_ids: set[int]):
    """Simulate reject-all for this build's revisions. Mutates doc_tree in place."""
    import copy
    W = NS["w"]
    # Remove w:ins content (inserted text disappears on reject)
    for ins in doc_tree.findall(f".//{qn('w','ins')}"):
        if ins.get(qn("w","author")) == BUILD_AUTHOR:
            parent = ins.getparent()
            idx = list(parent).index(ins)
            parent.remove(ins)
    # Unwrap w:del (deleted text reappears on reject)
    for del_el in doc_tree.findall(f".//{qn('w','del')}"):
        if del_el.get(qn("w","author")) == BUILD_AUTHOR:
            parent = del_el.getparent()
            idx = list(parent).index(del_el)
            for i, child in enumerate(del_el):
                # Convert w:delText back to w:t
                for dt in child.findall(qn("w","delText")):
                    dt.tag = qn("w","t")
                parent.insert(idx + i, child)
            parent.remove(del_el)
    # Also remove paragraph-mark insertions (w:pPr/w:rPr/w:ins) for inserted paragraphs
    for ins in doc_tree.findall(f".//{qn('w','pPr')}/{qn('w','rPr')}/{qn('w','ins')}"):
        if ins.get(qn("w","author")) == BUILD_AUTHOR:
            ins.getparent().remove(ins)
```

### Pattern 9: ID Uniqueness

All of the following must be globally unique across the entire DOCX package:
- `w:id` on `w:ins`, `w:del`, `w:commentRangeStart`, `w:commentRangeEnd`, `w:commentReference`, `w:comment` — these share one namespace and must not collide.
- `w14:paraId` — 8-hex-char values; must not collide with any existing value across `document.xml`, `comments.xml`, and the threading parts.

**Known existing IDs:**
- `w:id` values in document.xml: `{0, 1}` (the two comment references)
- Max `w14:paraId` in document.xml: `7FF8A73E` — new paraIds must be > `7FF8A73E` or in a range guaranteed not to collide (e.g., increment from `7FF8A73F`).
- `w16cid:durableId` values: `57CE3336`, `2A01C95F` — new ones must not collide.

### Pattern 10: Enable Track Revisions in settings.xml

```python
def enable_track_revisions(settings_xml: bytes) -> bytes:
    tree = etree.fromstring(settings_xml)
    W = NS["w"]
    existing = tree.find(qn("w","trackChanges"))
    if existing is None:
        el = etree.SubElement(tree, qn("w","trackChanges"))
    return etree.tostring(tree, xml_declaration=True, encoding="UTF-8", standalone=True)
```

### Anti-Patterns to Avoid

- **Editing document.xml as a string:** OOXML namespaces are complex; string replacement corrupts namespace declarations. Always parse with lxml.
- **Reusing `w:id` values:** The existing `w:id` space contains `{0, 1}`; start new IDs at 2. Never assume "there are no revisions so IDs start at 0."
- **Re-using a `w14:paraId` above `7FF8A73E`:** The document has 515 existing paraIds; the max is `7FF8A73E`. New paraIds must not collide. A safe strategy is a counter starting at `7FF8A740`.
- **Modifying the original `.docx`:** Always write to the copy. Verify SHA-256 both before and after editing.
- **Trusting `w:author` string matching alone for reject-all:** Track rev IDs in the manifest and filter by both author and ID set to avoid touching any pre-existing revisions (there are none in this document, but the algorithm must be robust).
- **Closing `w:commentRangeStart` without a matching `w:commentRangeEnd` and `w:commentReference`:** Word will prompt for repair on open. Each comment needs all three markers.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| DOCX ZIP manipulation | Custom archive reader | `zipfile` stdlib + `shutil.copy2` | Correct ZIP64 handling, atomic replace via tmp file |
| XML namespace management | String substitution | lxml `etree` with `qn()` helper | Namespace prefixes vary between files; lxml handles xmlns declarations correctly |
| XLSX writing with UF colours | Custom formatter | openpyxl following existing `cmd_export` pattern | Pattern already coded, tested, and used in the tool |
| Draft unit enumeration | Re-parse AM-DRAFT.md | `_parse_draft()` from `am_evidence_map.py` | Already handles bullet/table-row/CORRECTION grammar, STATUS: and CITE: extraction |

---

## Existing Document Inventory (from live DOCX inspection)

### Package Parts Present
All four threading parts are already present — no new parts need to be added:
- `word/comments.xml` — 2 existing comments (IDs 0 and 1)
- `word/commentsExtended.xml` — 2 `w15:commentEx` entries (paraIds `4AFA1B64`, `0EC496CC`)
- `word/commentsIds.xml` — 2 `w16cid:commentId` entries (durableIds `57CE3336`, `2A01C95F`)
- `word/commentsExtensible.xml` — present
- `word/people.xml` — present (contains Amy Crisp; Gerard Garvan must be added)
- `word/settings.xml` — present; `<w:trackChanges>` element NOT present (must be added)
- No headers or footers — all content is in `word/document.xml`

### Existing Comments (c0 and c1)
| ID | Author | initials | Date | ParaId in body | Anchor para paraId | Anchor text |
|----|--------|----------|------|----------------|--------------------|-------------|
| 0 (c0) | Crisp, Amy | CA | 2026-10-23T13:35:00Z | `4AFA1B64` | `7AA45245` | "Data Cleaning and Harmonization Rules" |
| 1 (c1) | Crisp, Amy | CA | 2026-10-23T13:31:00Z | `0EC496CC` | `106EBCC1` | "Use diagnosis date from Tumor Registry as default. If no diagnosis date: use first date with HL diagnosis code" |

### ID Space Summary
| ID type | Existing values | Safe start for new |
|---------|----------------|-------------------|
| `w:id` (revisions + comment refs) | {0, 1} | 2 |
| `w14:paraId` (hex) | max = `7FF8A73E`, 515 total | `7FF8A740` |
| `w16cid:durableId` | `57CE3336`, `2A01C95F` | random 8-hex, avoid these two |

### Document Structure
- 473 paragraphs, 8 tables, 42 rows
- Heading styles in use: `Heading1`, `Heading2` (no Heading3/4)
- Paragraph styles: `Normal` (unlabelled), `ListParagraph`, `xxmsolistparagraph`, `Heading1`, `Heading2`
- §0 fields live in Normal-style paragraphs in the body (not headers/footers): "Document version:" and "Date last updated: 9/3/2026" confirmed in body
- §8 has NO table — it contains three `ListParagraph` paragraphs ("Questions requiring MPI input:", "Deferred decisions:", "Known limitations..."). The §8 table from AM-DRAFT.md must be **inserted** as a new tracked table, not rows added to an existing table.
- §4 subsections use `Normal` style for "Domain: X" labels and `ListParagraph` for content bullets

### AM-DRAFT.md Unit Inventory
| Status | Count |
|--------|-------|
| DRAFTED | 95 |
| TEAM-INPUT-NEEDED | 33 |
| OPEN-QUESTION-SEE-§8 | 8 |
| CORRECTION | 2 |
| §8 table data rows | 41 |

---

## Common Pitfalls

### Pitfall 1: paraId Collision
**What goes wrong:** New `w14:paraId` values collide with existing ones, causing Word to repair the document on open.
**Why it happens:** IDs are scattered across document.xml and comments.xml; the max must be taken across all parts.
**How to avoid:** Collect all existing paraIds from every XML part before allocating new ones. Use a counter starting at `7FF8A740`.

### Pitfall 2: w:id collides with comment reference IDs
**What goes wrong:** New `w:ins`/`w:del` IDs conflict with the existing `w:commentRangeStart`/`w:commentRangeEnd`/`w:commentReference` IDs (0 and 1).
**Why it happens:** The ID space is shared: revision markers and comment markers all use `w:id` in the same namespace.
**How to avoid:** Start all new `w:id` values at 2. Keep a monotonically increasing counter for the entire build.

### Pitfall 3: §8 has no existing table
**What goes wrong:** Plan assumes §8 already has a table and tries to insert rows into it.
**Why it happens:** The AM-DRAFT.md §8 section is formatted as a table, but the live DOCX §8 currently has only three list paragraphs.
**How to avoid:** Detect at preflight time. The §8 table must be constructed from scratch and inserted as a new tracked table element.

### Pitfall 4: Anchor match across split runs
**What goes wrong:** The anchor text spans multiple `w:r` elements (Word splits runs for many reasons: formatting, spellcheck, rsid changes), so a simple `w:t` text search fails.
**Why it happens:** "Data s ource" might be stored as three runs in the XML (observed: "Data ", "s", "ource").
**How to avoid:** Concatenate all `w:t` text in the paragraph to produce a single string for searching, then map the character offsets back to individual runs. Split boundary runs at the anchor start/end character offsets.

### Pitfall 5: Namespace prefix inconsistency on repack
**What goes wrong:** lxml may emit namespace prefixes differently from the original (e.g., `ns0:ins` instead of `w:ins`), causing Word to refuse the file.
**Why it happens:** lxml's default serialization may not preserve the original prefix bindings.
**How to avoid:** Use `etree.tostring(tree, xml_declaration=True, encoding="UTF-8", standalone=True)` and confirm prefixes match. Register namespaces with `etree.register_namespace` or use `nsmap` when constructing elements. Test the round-trip on a no-op edit (parse and reserialize without changes) before adding any mutations.

### Pitfall 6: pandoc not in Bash PATH
**What goes wrong:** `which pandoc` returns nothing in the Bash shell; the verification step silently skips.
**Why it happens:** pandoc is installed on Windows but not on the Bash PATH used by Claude.
**How to avoid:** Use `subprocess.run(["pandoc", ...])` from Python — Python's PATH includes the Windows PATH. Or locate pandoc via `shutil.which("pandoc")` from Python. If not found, record the skip reason in the manifest.

### Pitfall 7: Reject-all changes pPr paragraph-mark insertion
**What goes wrong:** The reject-all pass drops `w:ins` runs but leaves the paragraph-mark insertion `w:pPr/w:rPr/w:ins` intact, so a new empty paragraph remains after rejection — making the text differ from the original.
**Why it happens:** `w:pPr/w:rPr/w:ins` is a separate element from the run-level `w:ins`.
**How to avoid:** The reject-all algorithm must also remove `w:pPr/w:rPr/w:ins` elements from inserted paragraphs, and remove the entire inserted `w:p` if it was a paragraph-level insertion.

### Pitfall 8: Comment reference missing for reply
**What goes wrong:** The new reply comment is added to `comments.xml` and `commentsExtended.xml` but no `w:commentReference` is added in `document.xml`, so Word shows the reply comment in the panel but it is not anchored.
**Why it happens:** The threading mechanism requires: comment in `comments.xml` + `commentEx` in `commentsExtended.xml` + `commentReference` in `document.xml`. Missing any one silently breaks the display.
**How to avoid:** For each reply, add a `w:commentReference` with the new ID in the same run as the original comment's `w:commentReference`, immediately after it.

---

## _parse_draft() Return Structure

The function returns a dict. Fields relevant to Phase 193:

| Key | Type | Contents |
|-----|------|----------|
| `units` | `list[dict]` | All bullet and correction units. Each has: `type` ("bullet"/"table_row"/"correction"), `id_tags` (list of map IDs like `["S0-FM-01"]`), `status` ("DRAFTED"/"TEAM-INPUT-NEEDED"/"OPEN-QUESTION-SEE-§8"/"CORRECTION"), `cites` (list of cite strings), `line_num`, `raw` (original markdown line) |
| `s8_rows` | `list[dict]` | §8 table rows: `item`, `notes_tag`, `decision_ids`, `raw_notes`, `status`, `cite`, `row_map_ids` |
| `s1_rows` | `list[list[str]]` | §1 table data rows (cells as strings) |
| `s3_rows` | `list[list[str]]` | §3 table data rows |
| `a1_rows` | `list[list[str]]` | Appendix A1 table rows |
| `a3_rows` | `list[list[str]]` | Appendix A3 table rows |
| `repo_only_blocks` | `list[str]` | Domain short codes inside REPO-ONLY markers (e.g., `"CBC"`, `"RUCA"`) |
| `not_drafted_ids` | `set[str]` | Map IDs appearing in the "Not drafted" section |

CORRECTION units additionally carry: `anchor` (quoted anchor text), `anchor_line` (line number in source markdown, for reference), `action` (`"REPLACE"`), `target` (section label string).

**Unit counts from live parse:** 95 DRAFTED, 33 TEAM-INPUT-NEEDED, 8 OPEN-QUESTION-SEE-§8, 2 CORRECTION, 41 §8 rows.

---

## Operation Classification Logic (D-13 / M1/M2)

The manifest must classify each unit before writing XML:

| Draft status | Destination type | Action | XML produced |
|-------------|-----------------|--------|-------------|
| DRAFTED → empty field | Fill an empty field | INSERT-PARA | `w:ins` paragraphs |
| DRAFTED → populated field | Insert after last existing paragraph of field | INSERT-PARA | `w:ins` paragraphs |
| DRAFTED → new subsection (repo-only domain) | New `Heading2`-style section + paragraphs | INSERT-PARA | `w:ins` heading + content paras |
| DRAFTED → §1/§3/A1/A3 table row | Table row insertion | INSERT-ROW | `w:trPr/w:ins` row |
| DRAFTED → §8 table | §8 table creation (no existing table) | INSERT-TABLE | New tracked table element |
| TEAM-INPUT-NEEDED | Same destination as DRAFTED | INSERT-PARA with `[TEAM INPUT NEEDED]` | `w:ins` para |
| OPEN-QUESTION-SEE-§8 → empty field | Fill field + comment pointing to §8 row | INSERT-PARA + COMMENT-ONLY | `w:ins` para + comment |
| OPEN-QUESTION-SEE-§8 → existing text | No text change, add comment only | COMMENT-ONLY | Comment element |
| CORRECTION | Replace anchor text | REPLACE | `w:del` old + `w:ins` new + COMMENT-ONLY with decision ID |
| c0/c1 reply | Threaded reply on existing comment | REPLY | New comment + `commentEx` |
| Front matter date/version | "Date last updated" and "Document version" fields | REPLACE | `w:del` old + `w:ins` new |

---

## Evidence Workbook (manual-export subcommand)

### Reuse from cmd_export
- openpyxl import block
- `UF_BLUE = "0021A5"`, `UF_ORANGE = "FA4616"` colour constants
- `style_header()`, `write_row()`, `cap_widths()` helpers
- `_safe_cell()` helper (prevents openpyxl from choking on long strings)
- KEY sheet construction pattern

### New in manual-export
- Output path: `output/am_evidence_<YYYYMMDD>.xlsx` (not `.planning/phases/…`)
- KEY sheet: build ID, original SHA-256, output SHA-256, column definitions, reply outcomes, reference to `am_verdicts_<date>.xlsx`
- Operations sheet: one row per op_id — op_id, section, map ID(s), action, inserted text, anchor text, revision IDs created, comment IDs created, citation(s), verdict/status (APPLIED/ANCHOR-FAILED), decision ID
- Open Items sheet: §8 rows as inserted
- Reconciliation sheet: every `w:ins`/`w:del`/comment created belongs to exactly one op; every APPLIED operation's IDs exist in output XML; mismatches fail the export
- Regression check: run `cmd_export` before and after and compare output file SHA-256

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| python-docx | Reading DOCX structure | Yes | 1.2.0 | — |
| lxml | XML editing | Yes | 6.0.2 | — |
| openpyxl | Workbook output | Yes | 3.1.5 | — |
| xlsxwriter | Workbook output (alt) | Yes | 3.2.9 | Not needed |
| zipfile (stdlib) | DOCX unpack/repack | Yes | stdlib | — |
| hashlib (stdlib) | SHA-256 verification | Yes | stdlib | — |
| pandoc | Verification cross-check | Not in Bash PATH; available via Python `subprocess` on Windows PATH | 3.13 | Skip with recorded reason if `shutil.which("pandoc")` returns None |
| LibreOffice | PDF render check | Unknown — not checked in Bash | — | Skip with recorded reason; note in manifest |

**Missing dependencies with no fallback:** None that block core functionality.

**Missing dependencies with fallback:**
- pandoc: use `subprocess` from Python (Windows PATH). If still not found, record skip.
- LibreOffice: check `soffice` on PATH. If not found, record skip in manifest.

---

## Validation Architecture

The phase does not use the R/pytest test framework (it is a Python tool). Verification is defined by D-15:

### Automated Checks (all in the build script itself)
| Check | Command | Automated |
|-------|---------|-----------|
| XML well-formedness of all edited parts | `etree.fromstring(part_bytes)` on each part after editing | Yes |
| Relationship and content-type resolution | Verify all parts named in `_rels/*.rels` exist in the zip | Yes |
| `w:id` uniqueness | Assert all `w:id` values in document.xml and comments.xml are distinct | Yes |
| `w14:paraId` uniqueness | Assert across document.xml and comments.xml | Yes |
| `commentRangeStart`/`End`/`Reference` parity | For each new comment ID, all three markers present | Yes |
| Reject-all == original text | See Pattern 8; must pass for every paragraph | Yes |
| Accept-all contains inserted text | See Pattern 8 | Yes |
| Untouched content byte-identical | After reject-all pass, existing paragraphs outside targeted locations match pre-build snapshots | Yes |
| Workbook reconciliation | Every build rev ID in manifest maps to an XML element; every APPLIED op's IDs found in output | Yes |
| pandoc cross-check | `pandoc --track-changes=all output.docx -o /dev/null` and count markers | Yes, if pandoc available |
| LibreOffice PDF render | `soffice --headless --convert-to pdf output.docx` | Yes, if LibreOffice available |

### Human Checkpoint (D-16)
File opens without repair prompt; tracked changes visible and attributed to Gerard Garvan; accept/reject works on a sample; c0/c1 replies show under Amy's comments (or fallback labelled); no layout damage.

---

## Open Questions

1. **Whether all OPEN-QUESTION-SEE-§8 units target empty fields or existing text**
   - What we know: 8 units with this status; some fill empty fields (e.g., S2-COH-03 index date), some annotate existing text.
   - What's unclear: The exact paragraph in the DOCX that each targets must be identified in the preflight.
   - Recommendation: Resolve at preflight time (Wave 0, task 1).

2. **§8 table structure to create**
   - What we know: §8 currently has no table; AM-DRAFT.md has a table with columns (Item | Notes | Date added | Map ID | Status | Cite); 41 data rows.
   - What's unclear: Which columns survive after stripping draft-control metadata (D-34 says Map ID, Status, Cite are stripped from body text but go to workbook).
   - Recommendation: The manual §8 table should have columns (Item | Notes | Date added) only; Map ID/Status/Cite go to the workbook Operations sheet.

3. **LibreOffice installation on local Windows machine**
   - What we know: Not confirmed available. CONTEXT.md says pandoc 3.13 is installed; LibreOffice not mentioned.
   - Recommendation: Check at build time with `shutil.which("soffice")`; skip and record if absent.

---

## Sources

### Primary (HIGH confidence)
- Live DOCX inspection via Python `zipfile` + lxml — SHA-256, parts inventory, comment IDs, paraIds, document structure, heading styles, §8 structure, §0 field locations all verified directly.
- `tools/am_evidence/am_evidence_map.py` source read — `_parse_draft()` return structure, `cmd_export` pattern, openpyxl usage all verified.
- `AM-DRAFT.md` — unit counts verified by script.
- `193-CONTEXT.md` — all decisions locked.

### Secondary (MEDIUM confidence)
- OOXML Ecma-376 specification (from training knowledge, verified against live XML): `w:ins`, `w:del`, `w:trPr/w:ins` element structure; `w15:commentEx`/`w15:paraIdParent` threading mechanism; `w14:paraId` uniqueness requirement.

### Tertiary (LOW confidence)
- None.

---

## Metadata

**Confidence breakdown:**
- Document structure inventory: HIGH — verified against live DOCX bytes
- OOXML tracked-change construction: HIGH — patterns verified against spec and live namespace declarations in the package
- Comment threading: HIGH — live `commentsExtended.xml` shows the exact structure (`w15:paraId`, `w15:paraIdParent`) used by Word
- `_parse_draft()` return fields: HIGH — read from source code
- §8 has no existing table: HIGH — verified by inspection
- pandoc Windows PATH: MEDIUM — confirmed not in Bash PATH; Python subprocess should find it

**Research date:** 2026-10-28
**Valid until:** 2026-11-28 (stable OOXML spec; no external API dependencies)
