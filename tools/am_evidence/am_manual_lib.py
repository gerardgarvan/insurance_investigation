#!/usr/bin/env python3
"""
am_manual_lib.py — Shared OOXML helpers for Phase 193 (produce updated manual).

Pure helper module: no side effects on import, no DOCX edits, lxml only (no python-docx).
Used by am_manual_insert.py (Plan 02) and verification scripts (Plan 03).

Functions:
  NS / qn()           — namespace constants and Clark-notation helper
  sha256()            — hex SHA-256 of a file
  unpack_docx()       — read all parts of a .docx into {name: bytes}
  repack_docx()       — write {name: bytes} to a .docx atomically
  AnchorFailed        — exception raised by find_anchor_para on 0 or >1 matches
  get_para_text()     — concatenate all w:t text in a w:p element
  find_anchor_para()  — locate exactly one paragraph containing anchor_text
  scan_id_space()     — enumerate w:id, w14:paraId, and w16cid:durableId across all XML parts

Pinned SHA-256 for the original source document (from
.planning/phases/190-evidence-map/am_source_hashes.txt, generated 2026-10-27):
  2e119764b63cf9e491decc1177ff38ea49335cd2f15673b9e92b68a127a1517d
"""

import hashlib
import re
import sys
import zipfile
from pathlib import Path

from lxml import etree

# ---------------------------------------------------------------------------
# Namespace constants (Pattern 2 from 193-RESEARCH.md — verbatim)
# ---------------------------------------------------------------------------

NS = {
    "w":      "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
    "w14":    "http://schemas.microsoft.com/office/word/2010/wordml",
    "w15":    "http://schemas.microsoft.com/office/word/2012/wordml",
    "w16cid": "http://schemas.microsoft.com/office/word/2016/wordml/cid",
    "r":      "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
    "xml":    "http://www.w3.org/XML/1998/namespace",
}


def qn(ns_key: str, local: str) -> str:
    """Return the Clark-notation qualified name: '{uri}local'."""
    return f"{{{NS[ns_key]}}}{local}"


# ---------------------------------------------------------------------------
# Pinned SHA-256 of the original source document
# Source: .planning/phases/190-evidence-map/am_source_hashes.txt (2026-10-27)
# ---------------------------------------------------------------------------

PINNED_ORIGINAL_SHA256 = (
    "2e119764b63cf9e491decc1177ff38ea49335cd2f15673b9e92b68a127a1517d"
)


# ---------------------------------------------------------------------------
# SHA-256 helper
# ---------------------------------------------------------------------------

def sha256(path) -> str:
    """Return the hex SHA-256 digest of the file at *path*."""
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


# ---------------------------------------------------------------------------
# DOCX unpack / repack (Pattern 1 from 193-RESEARCH.md)
# ---------------------------------------------------------------------------

def unpack_docx(path) -> dict:
    """
    Read all parts of the .docx at *path* into memory.

    Returns {part_name: bytes} for every entry in the zip archive.
    Read-only: never writes to the source file.
    """
    parts = {}
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            parts[name] = z.read(name)
    return parts


def repack_docx(parts: dict, out_path) -> None:
    """
    Write *parts* ({name: bytes}) to *out_path* as a ZIP_DEFLATED archive.

    Atomic: writes to <out_path>.tmp first, then replaces out_path.
    Part order in the zip follows the insertion order of *parts*.
    """
    out_path = Path(out_path)
    tmp = out_path.with_suffix(".tmp")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in parts.items():
            z.writestr(name, data)
    tmp.replace(out_path)


# ---------------------------------------------------------------------------
# Exception
# ---------------------------------------------------------------------------

class AnchorFailed(Exception):
    """Raised when find_anchor_para cannot locate exactly one matching paragraph."""


# ---------------------------------------------------------------------------
# Paragraph text helpers (Pattern 7 from 193-RESEARCH.md — verbatim)
# ---------------------------------------------------------------------------

def get_para_text(para_el) -> str:
    """Concatenate all w:t values in a paragraph element."""
    parts = []
    for t in para_el.iter(qn("w", "t")):
        parts.append(t.text or "")
    return "".join(parts)


def find_anchor_para(doc_tree, anchor_text: str):
    """
    Return the single paragraph element whose concatenated run text contains anchor_text.

    Raises AnchorFailed if 0 or >1 paragraphs match.
    *doc_tree* must be an lxml element (e.g. from etree.fromstring(parts['word/document.xml'])).
    """
    matches = []
    for p in doc_tree.iter(qn("w", "p")):
        if anchor_text in get_para_text(p):
            matches.append(p)
    if len(matches) != 1:
        raise AnchorFailed(
            f"anchor {anchor_text!r} matched {len(matches)} paragraphs"
        )
    return matches[0]


# ---------------------------------------------------------------------------
# ID space scanner (Pattern 9 from 193-RESEARCH.md)
# ---------------------------------------------------------------------------

# Attribute names whose values contribute to the shared w:id space.
_W_ID_TAGS = {
    qn("w", "ins"),
    qn("w", "del"),
    qn("w", "comment"),
    qn("w", "commentRangeStart"),
    qn("w", "commentRangeEnd"),
    qn("w", "commentReference"),
}
_W_ID_ATTR = qn("w", "id")
_W14_PARA_ID_ATTR = qn("w14", "paraId")
_W16CID_DURABLE_ID_ATTR = qn("w16cid", "durableId")


def scan_id_space(parts: dict) -> dict:
    """
    Enumerate all existing ID values across every XML part in *parts*.

    Returns a dict:
      {
        "w_ids":      set[int]   — existing w:id values on revision/comment elements,
        "para_ids":   set[str]   — existing w14:paraId values (uppercase hex strings),
        "durable_ids": set[str]  — existing w16cid:durableId values,
      }

    Non-XML parts (images, fonts, etc.) are silently skipped.
    """
    w_ids: set = set()
    para_ids: set = set()
    durable_ids: set = set()

    for name, data in parts.items():
        if not name.endswith(".xml"):
            continue
        try:
            root = etree.fromstring(data)
        except etree.XMLSyntaxError:
            continue

        for el in root.iter():
            tag = el.tag

            # Collect w:id from tracked-change and comment elements
            if tag in _W_ID_TAGS:
                val = el.get(_W_ID_ATTR)
                if val is not None:
                    try:
                        w_ids.add(int(val))
                    except ValueError:
                        pass

            # Collect w14:paraId from any element that carries it
            pid = el.get(_W14_PARA_ID_ATTR)
            if pid is not None:
                para_ids.add(pid.upper())

            # Collect w16cid:durableId from any element that carries it
            did = el.get(_W16CID_DURABLE_ID_ATTR)
            if did is not None:
                durable_ids.add(did.upper())

    return {
        "w_ids": w_ids,
        "para_ids": para_ids,
        "durable_ids": durable_ids,
    }


# ---------------------------------------------------------------------------
# D-34 stripping helpers
# ---------------------------------------------------------------------------

_S4_TAG_RE = re.compile(r"\[S[AB]?\d{1,2}-[A-Z]{2,6}-\d{2}\]\s*")
_STATUS_LINE_RE = re.compile(r"^\s*STATUS:\s*.+$", re.MULTILINE)
_CITE_LINE_RE = re.compile(r"^\s*CITE:\s*.+$", re.MULTILINE)


def _strip_draft_metadata(text: str) -> str:
    """
    Remove draft-control metadata from insert_text per D-34:
      - [S4-…] / [S0-…] / [S1-…] etc. map-ID tags
      - STATUS: lines
      - CITE: lines
    Substantive references (decision IDs, section numbers, dates) are retained.
    """
    if not text:
        return text
    text = _S4_TAG_RE.sub("", text)
    text = _STATUS_LINE_RE.sub("", text)
    text = _CITE_LINE_RE.sub("", text)
    # Collapse multiple blank lines to one
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def _strip_table_row_metadata(cells: list) -> list:
    """
    Strip trailing Map ID / Status / Cite columns from a draft table row.
    Draft tables append these as the last 3 columns; they go to the workbook, not the body.
    Returns cells with those columns removed when the trailing columns match the draft pattern.
    """
    if len(cells) < 3:
        return cells
    # Heuristic: last col is a cite-like string, second-to-last is a status flag,
    # third-to-last looks like a map ID.
    _STATUS_FLAGS = {
        "DRAFTED", "TEAM-INPUT-NEEDED", "OPEN-QUESTION-SEE-§8", "CORRECTION",
    }
    status_candidate = cells[-2].strip()
    map_id_candidate = cells[-3].strip()
    if status_candidate in _STATUS_FLAGS and re.match(
        r"^S[AB]?\d{1,2}-[A-Z]{2,6}-\d{2}$", map_id_candidate
    ):
        return cells[:-3]
    return cells


# ---------------------------------------------------------------------------
# CORRECTION replacement-text extractor
# (reads raw_lines from _parse_draft since _parse_draft discards Replacement:)
# ---------------------------------------------------------------------------

def _extract_replacement(raw_lines: list, start_line_num: int) -> str:
    """
    Given a CORRECTION block starting at *start_line_num* (1-based), scan forward
    to find the '- Replacement:' line and return its value.
    """
    # start_line_num is 1-based index of the '#### CORRECTION' line
    for idx in range(start_line_num - 1, min(start_line_num + 20, len(raw_lines))):
        stripped = raw_lines[idx].strip()
        if stripped.startswith("- Replacement:"):
            return stripped[len("- Replacement:"):].strip()
    return ""


# ---------------------------------------------------------------------------
# build_operations() — D-13 manifest classifier
# ---------------------------------------------------------------------------

# Parent paraIds for c0 and c1 from 193-PREFLIGHT.md
_C0_PARENT_PARA_ID = "4AFA1B64"   # c0 body-paragraph paraId
_C1_PARENT_PARA_ID = "0EC496CC"   # c1 body-paragraph paraId

# Anchor texts for c0 and c1 from 193-PREFLIGHT.md
_C0_ANCHOR_TEXT = "4. Data Cleaning and Harmonization Rules"
_C1_ANCHOR_TEXT = "Use diagnosis date from Tumor Registry as default."

# Reply texts from D-14 and AM-VERDICTS.md (S4-CMNT-02 is PARTIAL → "see §8")
_C0_REPLY_TEXT = (
    "OneFLquestions document not received; listed as open in §8 (D-190-01)."
)
_C1_REPLY_TEXT = (
    "Confirmed: get_hl_any_dx_ids() uses the earliest HL diagnosis code date from "
    "DIAGNOSIS (DX_DATE with ADMIT_DATE as fallback); the Tumor Registry date is not "
    "consulted in the production anchor function (D-191-02, D-191-03). See §8."
)

# Section label for each map-ID prefix (used for target.section assignment)
_SECTION_MAP = {
    "S0": "§0",
    "S1": "§1",
    "S2": "§2",
    "S3": "§3",
    "S4": "§4",
    "S5": "§5",
    "S6": "§6",
    "S7": "§7",
    "S8": "§8",
    "S9": "§9",
    "S10": "§10",
    "S11": "§11",
    "SA1": "A1",
    "SA2": "A2",
    "SA3": "A3",
    "SA4": "A4",
}

# Table sections — units in these go to INSERT-ROW
_TABLE_SECTIONS = {"§1", "§3", "A1", "A3"}

# Repo-only domain block prefix: detected via draft["repo_only_blocks"]
_REPO_ONLY_SECTION = "§4"

# Preflight-derived: §8 has no existing table, so all §8 rows → one INSERT-TABLE op
_S8_SECTION = "§8"

# §0 front-matter map IDs for the two REPLACE ops (Document version, Date last updated)
_FM_VERSION_MAP_ID = "S0-FM-07"
_FM_DATE_MAP_ID = "S0-FM-08"

# Preflight target locators (from 193-PREFLIGHT.md §5)
_FM_VERSION_PARA_IDX = 7     # "Document version: "
_FM_DATE_PARA_IDX = 8        # "Date last updated: 9/3/2026"


def _section_from_id_tags(id_tags: list) -> str:
    """Return the §-label for a unit based on its first map ID."""
    for tag in id_tags:
        for prefix, section in _SECTION_MAP.items():
            if tag.startswith(prefix + "-"):
                return section
    return "unknown"


def build_operations(draft_path, preflight) -> list:
    """
    Classify every AM-DRAFT.md unit into exactly one operation dict (D-13).

    Parameters
    ----------
    draft_path : str or Path
        Path to AM-DRAFT.md.  The verify command passes
        '../../docs/analytic_manual/AM-DRAFT.md'; if that file does not exist,
        this function tries the canonical location
        '.planning/phases/192-draft-new-content/AM-DRAFT.md' relative to the
        repo root (two levels up from tools/am_evidence/).
    preflight : ignored (reserved for future use; pass None from tests)

    Returns
    -------
    list[dict]  — one operation per logical edit, op_ids OP-001, OP-002, …
    """
    # Resolve draft path with fallback
    draft_path = Path(draft_path)
    if not draft_path.exists():
        # Try canonical location relative to this file (tools/am_evidence/)
        here = Path(__file__).parent
        repo_root = here.parent.parent
        fallback = repo_root / ".planning" / "phases" / "192-draft-new-content" / "AM-DRAFT.md"
        if fallback.exists():
            draft_path = fallback
        else:
            raise FileNotFoundError(
                f"AM-DRAFT.md not found at {draft_path} or {fallback}"
            )

    # Import _parse_draft from sibling module
    # We use a local import to keep am_manual_lib free of circular deps
    import importlib
    import sys as _sys

    _here = Path(__file__).parent
    if str(_here) not in _sys.path:
        _sys.path.insert(0, str(_here))

    am_em = importlib.import_module("am_evidence_map")
    parse_draft = getattr(am_em, "_parse_draft")

    draft = parse_draft(draft_path)
    units = draft["units"]
    s8_rows = draft["s8_rows"]
    s1_rows = draft["s1_rows"]
    s3_rows = draft["s3_rows"]
    a1_rows = draft["a1_rows"]
    a3_rows = draft["a3_rows"]
    repo_only_blocks = set(draft.get("repo_only_blocks", []))
    raw_lines = draft.get("raw_lines", [])

    ops = []

    # ------------------------------------------------------------------
    # Pass 1: enumerate units from _parse_draft (bullets, table_rows,
    # corrections) sorted by line_num for deterministic ordering
    # ------------------------------------------------------------------
    for unit in sorted(units, key=lambda u: u["line_num"]):
        status = (unit.get("status") or "").strip()
        id_tags = unit.get("id_tags", [])
        cites = unit.get("cites", [])
        section = _section_from_id_tags(id_tags)
        unit_type = unit.get("type", "bullet")

        # ----- Table rows (§1, §3, A1, A3) -----
        if unit_type == "table_row" and section in _TABLE_SECTIONS:
            if status in ("DRAFTED", "TEAM-INPUT-NEEDED", "OPEN-QUESTION-SEE-§8"):
                cells = []
                # raw contains the stripped pipe row; strip trailing metadata
                raw_cells = [c.strip() for c in re.split(r"(?<!\\)\|", unit["raw"].strip().strip("|"))]
                cells = _strip_table_row_metadata(raw_cells)
                insert_text = " | ".join(cells)
                action = "INSERT-ROW" if status in ("DRAFTED", "OPEN-QUESTION-SEE-§8") else "INSERT-PARA"
                if status == "TEAM-INPUT-NEEDED":
                    insert_text = "[TEAM INPUT NEEDED]"
                    action = "INSERT-ROW"
                ops.append({
                    "source_unit_map_ids": id_tags,
                    "status": status,
                    "action": action,
                    "section": section,
                    "insert_text": insert_text,
                    "anchor_text": None,
                    "citations": cites,
                    "decision_id": None,
                    "verdict": None,
                    "comment_text": None,
                    "anchor_resolution": "OK",
                    "line_num": unit["line_num"],
                })
            continue

        # ----- Corrections -----
        if unit_type == "correction" or status == "CORRECTION":
            anchor = unit.get("anchor", "")
            target_label = unit.get("target", "")
            replacement = _extract_replacement(raw_lines, unit["line_num"])
            # Decision ID: look for D-NNN-NN in cites or raw
            decision_ids = re.findall(r"D-\d{3}-\d{2}", " ".join(cites) + " " + unit.get("raw", ""))
            decision_id = decision_ids[0] if decision_ids else None
            ops.append({
                "source_unit_map_ids": id_tags,
                "status": status,
                "action": "REPLACE",
                "section": section,
                "insert_text": replacement,
                "anchor_text": anchor,
                "citations": cites,
                "decision_id": decision_id,
                "verdict": "MISMATCH",
                "comment_text": (
                    f"Correction per {decision_id or 'see citations'}. "
                    f"Evidence: {'; '.join(cites)}"
                ) if cites else None,
                "anchor_resolution": "PENDING",
                "line_num": unit["line_num"],
            })
            continue

        # ----- OPEN-QUESTION-SEE-§8 bullet units -----
        if status == "OPEN-QUESTION-SEE-§8" and unit_type == "bullet":
            # Determine target from raw bullet text — look for a field label
            raw_text = unit.get("raw", "")
            # Strip map-ID tag and leading dash to get the content text
            content = re.sub(r"^\s*-\s*", "", raw_text)
            content = _S4_TAG_RE.sub("", content).strip()
            # Decision IDs from cites
            decision_ids = re.findall(r"D-\d{3}-\d{2}", " ".join(cites))
            decision_id = decision_ids[0] if decision_ids else None
            # Emit a COMMENT-ONLY op (existing text unchanged, comment points to §8)
            ops.append({
                "source_unit_map_ids": id_tags,
                "status": status,
                "action": "COMMENT-ONLY",
                "section": section,
                "insert_text": None,
                "anchor_text": content[:80] if content else None,
                "citations": cites,
                "decision_id": decision_id,
                "verdict": "MISMATCH",
                "comment_text": (
                    f"Open question — see §8. {decision_id or ''}"
                ).strip(),
                "anchor_resolution": "PENDING",
                "line_num": unit["line_num"],
            })
            continue

        # ----- TEAM-INPUT-NEEDED bullet -----
        if status == "TEAM-INPUT-NEEDED" and unit_type == "bullet":
            raw_text = unit.get("raw", "")
            content = re.sub(r"^\s*-\s*", "", raw_text)
            content = _S4_TAG_RE.sub("", content).strip()
            ops.append({
                "source_unit_map_ids": id_tags,
                "status": status,
                "action": "PLACEHOLDER",
                "section": section,
                "insert_text": "[TEAM INPUT NEEDED]",
                "anchor_text": None,
                "citations": cites,
                "decision_id": None,
                "verdict": None,
                "comment_text": None,
                "anchor_resolution": "OK",
                "line_num": unit["line_num"],
            })
            continue

        # ----- DRAFTED bullet (plain insert) -----
        if status == "DRAFTED" and unit_type == "bullet":
            raw_text = unit.get("raw", "")
            # Strip map-ID tags and leading dash
            content = re.sub(r"^\s*-\s*", "", raw_text)
            content = _strip_draft_metadata(content).strip()
            # Determine if this is a repo-only domain unit
            is_repo_only = any(
                any(tag.startswith(f"S4-{code}-") for code in repo_only_blocks)
                for tag in id_tags
            ) or any(
                any(f"S4-{code}" in tag for code in repo_only_blocks)
                for tag in id_tags
            )
            # Also check if any tag's subdomain matches repo_only_blocks
            is_repo_only = is_repo_only or any(
                re.match(r"S4-([A-Z]+)-\d{2}", tag) and
                re.match(r"S4-([A-Z]+)-\d{2}", tag).group(1) in repo_only_blocks
                for tag in id_tags
            )
            kind = "new_subsection" if is_repo_only else "field"
            ops.append({
                "source_unit_map_ids": id_tags,
                "status": status,
                "action": "INSERT-PARA",
                "section": section,
                "insert_text": content,
                "anchor_text": None,
                "citations": cites,
                "decision_id": None,
                "verdict": None,
                "comment_text": None,
                "target_kind": kind,
                "anchor_resolution": "OK",
                "line_num": unit["line_num"],
            })
            continue

    # ------------------------------------------------------------------
    # Pass 2: §8 table → one INSERT-TABLE op carrying all s8_rows
    # §8 has no existing table (Pitfall 3); a new tracked table is created.
    # D-34: strip Map ID / Status / Cite columns → keep Item | Notes | Date added
    # ------------------------------------------------------------------
    if s8_rows:
        # Determine line_num: use line_num of first table-row unit that is in §8
        # (s8_rows don't carry line_num; use a sentinel that sorts after bullet ops
        # but before the REPLY ops which we'll emit last)
        s8_line = max((u["line_num"] for u in units), default=0) + 1

        # Build stripped rows: cells are (item, notes_cleaned, date_added)
        stripped_rows = []
        for row in s8_rows:
            item = row.get("item", "")
            # raw_notes may contain decision IDs — keep them (substantive per D-34)
            # but strip STATUS: prefixes if any
            notes = row.get("raw_notes", "")
            # Remove trailing Map ID / Status / Cite from notes if formatted as such
            # (they're separate cells in s8_rows, not embedded in raw_notes)
            date_added = ""  # date is the third column in the §8 table
            stripped_rows.append([item, notes, date_added])

        ops.append({
            "source_unit_map_ids": ["S8-ALL"],
            "status": "DRAFTED",
            "action": "INSERT-TABLE",
            "section": "§8",
            "insert_text": None,
            "anchor_text": None,
            "citations": [],
            "decision_id": None,
            "verdict": None,
            "comment_text": None,
            "table_columns": ["Item", "Notes", "Date added"],
            "table_rows": stripped_rows,
            "anchor_resolution": "OK",
            "line_num": s8_line,
        })

    # ------------------------------------------------------------------
    # Pass 3: §0 front-matter REPLACE ops for Document version and Date last updated
    # These are TEAM-INPUT-NEEDED in the draft (S0-FM-07, S0-FM-08) but are
    # classified as REPLACE ops targeting the preflight-identified paragraphs.
    # ------------------------------------------------------------------
    # They appear in the units list as TEAM-INPUT-NEEDED; we override them here
    # with REPLACE pointing to the known preflight para_index values.
    # Remove any PLACEHOLDER ops emitted for S0-FM-07 and S0-FM-08 (they were
    # already emitted in Pass 1 — we'll reassign action here via post-processing).
    # We handle them by looking for already-emitted ops with those map IDs:
    for op in ops:
        if _FM_VERSION_MAP_ID in op.get("source_unit_map_ids", []):
            op["action"] = "REPLACE"
            op["anchor_text"] = "Document version: "
            op["insert_text"] = "[Set in Phase 193]"
            op["anchor_resolution"] = "PENDING"
            op["target"] = {
                "section": "§0",
                "kind": "frontmatter",
                "para_index": _FM_VERSION_PARA_IDX,
                "table_index": None,
                "row_index": None,
                "cell_index": None,
            }
        if _FM_DATE_MAP_ID in op.get("source_unit_map_ids", []):
            op["action"] = "REPLACE"
            op["anchor_text"] = "Date last updated: 9/3/2026"
            op["insert_text"] = "[Set in Phase 193]"
            op["anchor_resolution"] = "PENDING"
            op["target"] = {
                "section": "§0",
                "kind": "frontmatter",
                "para_index": _FM_DATE_PARA_IDX,
                "table_index": None,
                "row_index": None,
                "cell_index": None,
            }

    # ------------------------------------------------------------------
    # Pass 4: c0 and c1 REPLY ops (always last two, after all units)
    # ------------------------------------------------------------------
    max_line = max((op["line_num"] for op in ops), default=0)

    ops.append({
        "source_unit_map_ids": ["C0-REPLY"],
        "status": "REPLY",
        "action": "REPLY",
        "section": "§4",
        "insert_text": None,
        "anchor_text": _C0_ANCHOR_TEXT,
        "citations": [],
        "decision_id": "D-190-01",
        "verdict": "BLOCKED",
        "comment_text": _C0_REPLY_TEXT,
        "parent_para_id": _C0_PARENT_PARA_ID,
        "anchor_resolution": "PENDING",
        "line_num": max_line + 1,
    })

    ops.append({
        "source_unit_map_ids": ["C1-REPLY"],
        "status": "REPLY",
        "action": "REPLY",
        "section": "§4",
        "insert_text": None,
        "anchor_text": _C1_ANCHOR_TEXT,
        "citations": ["R/utils/utils_treatment.R:get_hl_any_dx_ids():L310-345"],
        "decision_id": "D-191-02",
        "verdict": "PARTIAL",
        "comment_text": _C1_REPLY_TEXT,
        "parent_para_id": _C1_PARENT_PARA_ID,
        "anchor_resolution": "PENDING",
        "line_num": max_line + 2,
    })

    # ------------------------------------------------------------------
    # Assign op_id in deterministic order (sort by line_num, stable)
    # ------------------------------------------------------------------
    ops.sort(key=lambda o: o["line_num"])

    result = []
    for idx, op in enumerate(ops, start=1):
        op_id = f"OP-{idx:03d}"
        # Build the final op dict in schema order
        final_op = {
            "op_id": op_id,
            "source_unit_map_ids": op.get("source_unit_map_ids", []),
            "status": op.get("status", ""),
            "action": op.get("action", ""),
            "target": op.get("target", {
                "section": op.get("section", ""),
                "kind": op.get("target_kind", "field"),
                "para_index": None,
                "table_index": None,
                "row_index": None,
                "cell_index": None,
            }),
            "insert_text": op.get("insert_text"),
            "anchor_text": op.get("anchor_text"),
            "citations": op.get("citations", []),
            "decision_id": op.get("decision_id"),
            "verdict": op.get("verdict"),
            "comment_text": op.get("comment_text"),
            "anchor_resolution": op.get("anchor_resolution", "OK"),
            "revision_ids": [],
            "comment_ids": [],
        }
        # Carry optional fields
        if "parent_para_id" in op:
            final_op["parent_para_id"] = op["parent_para_id"]
        if "table_columns" in op:
            final_op["table_columns"] = op["table_columns"]
        if "table_rows" in op:
            final_op["table_rows"] = op["table_rows"]
        result.append(final_op)

    return result
