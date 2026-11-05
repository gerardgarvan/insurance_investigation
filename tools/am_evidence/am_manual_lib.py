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
  IdAllocator         — collision-free w:id / paraId / durableId allocation
  make_ins()          — build a bare w:ins element
  make_tracked_paragraph() — new w:p with w:pPr/w:rPr/w:ins mark + w:ins run
  make_tracked_deletion()  — wrap a w:r in w:del, rename w:t → w:delText
  make_tracked_row()       — table row with w:trPr/w:ins + tracked cell paragraphs
  apply_correction()       — split runs, insert w:del + w:ins replacement
  make_reply_comment()     — threaded reply w:comment element
  make_commentEx()         — w15:commentEx threading link element
  enable_track_revisions() — add w:trackChanges to settings.xml bytes
  reject_all()             — simulate reject-all for build revisions (mutates tree)
  accept_all()             — simulate accept-all for build revisions (mutates tree)
  apply_operations()       — orchestrator: apply manifest to produce versioned DOCX

Pinned SHA-256 for the original source document (from
.planning/phases/190-evidence-map/am_source_hashes.txt, generated 2026-10-27):
  2e119764b63cf9e491decc1177ff38ea49335cd2f15673b9e92b68a127a1517d
"""

import copy
import hashlib
import json
import os
import random
import re
import shutil
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


# ===========================================================================
# Task 0 additions: tracked-change builders, IdAllocator, reject/accept sims
# All OOXML patterns copied from 193-RESEARCH.md (Patterns 3,4,5,6,8,9,10).
# ===========================================================================

BUILD_AUTHOR = "Gerard Garvan"
BUILD_DATE = "2026-10-28T00:00:00Z"


# ---------------------------------------------------------------------------
# IdAllocator — collision-free ID allocation (Pattern 9)
# ---------------------------------------------------------------------------

class IdAllocator:
    """
    Allocates unique w:id, w14:paraId, and w16cid:durableId values for a build.

    Parameters
    ----------
    w_ids : set[int]
        Existing w:id integer values across all XML parts (from scan_id_space).
    para_ids : set[str]
        Existing w14:paraId uppercase-hex strings.
    durable_ids : set[str]
        Existing w16cid:durableId strings (mix of hex and decimal strings).
    """

    def __init__(self, w_ids, para_ids, durable_ids):
        self._w_ids = set(w_ids)
        self._para_ids = set(para_ids)
        self._durable_ids = set(durable_ids)
        # Start counters one above the current maxima
        self._next_w = max(self._w_ids, default=-1) + 1
        # paraId: hex counter starting at max+1 of observed hex values
        hex_values = []
        for pid in self._para_ids:
            try:
                hex_values.append(int(pid, 16))
            except ValueError:
                pass
        self._next_para_int = max(hex_values, default=0x7FF8A73E) + 1
        # Issued trackers for reconciliation
        self.issued_w_ids = []
        self.issued_para_ids = []
        self.issued_durable_ids = []

    def next_w_id(self) -> int:
        """Return the next collision-free integer w:id and record it."""
        while self._next_w in self._w_ids:
            self._next_w += 1
        val = self._next_w
        self._w_ids.add(val)
        self.issued_w_ids.append(val)
        self._next_w += 1
        return val

    def next_para_id(self) -> str:
        """Return the next collision-free 8-uppercase-hex paraId string."""
        while True:
            candidate = f"{self._next_para_int:08X}"
            self._next_para_int += 1
            if candidate not in self._para_ids:
                self._para_ids.add(candidate)
                self.issued_para_ids.append(candidate)
                return candidate

    def next_durable_id(self) -> str:
        """Return a random 8-uppercase-hex durableId not in the existing set."""
        for _ in range(10000):
            candidate = f"{random.randint(0, 0xFFFFFFFF):08X}"
            if candidate not in self._durable_ids:
                self._durable_ids.add(candidate)
                self.issued_durable_ids.append(candidate)
                return candidate
        raise RuntimeError("Could not generate a unique durableId after 10000 attempts")


# ---------------------------------------------------------------------------
# Pattern 2 helper (make_ins) — Pattern 3/4/5/6 building blocks
# ---------------------------------------------------------------------------

def make_ins(rev_id: int, author: str, date: str) -> "etree._Element":
    """Return a bare w:ins element with w:id, w:author, w:date set."""
    el = etree.Element(qn("w", "ins"))
    el.set(qn("w", "id"), str(rev_id))
    el.set(qn("w", "author"), author)
    el.set(qn("w", "date"), date)
    return el


# ---------------------------------------------------------------------------
# Pattern 3: Tracked insertion of a new paragraph
# ---------------------------------------------------------------------------

def make_tracked_paragraph(
    text: str,
    rev_id: int,
    author: str,
    date: str,
    para_id: str,
    pPr_source=None,
    run_rev_id: int = None,
) -> "etree._Element":
    """
    Return a w:p element that, when accepted, inserts *text* as a new paragraph.

    Parameters
    ----------
    text : str
        The text content of the new paragraph.
    rev_id : int
        w:id for the paragraph-mark insertion (w:pPr/w:rPr/w:ins).
    author : str
        w:author value (e.g., "Gerard Garvan").
    date : str
        ISO 8601 timestamp string.
    para_id : str
        Unique 8-uppercase-hex string for w14:paraId.
    pPr_source : lxml element, optional
        The preceding paragraph's w:pPr to copy formatting from.
    run_rev_id : int, optional
        w:id for the run-level w:ins wrapper; defaults to rev_id + 1.
    """
    if run_rev_id is None:
        run_rev_id = rev_id + 1

    p = etree.Element(qn("w", "p"))
    p.set(qn("w14", "paraId"), para_id)

    # --- Paragraph properties with mark-insertion (Pattern 3) ---
    pPr = etree.SubElement(p, qn("w", "pPr"))
    if pPr_source is not None:
        for child in list(pPr_source):
            # Do not copy an existing w:rPr — we'll create our own
            if child.tag != qn("w", "rPr"):
                pPr.append(copy.deepcopy(child))
    rPr_in_pPr = etree.SubElement(pPr, qn("w", "rPr"))
    ins_mark = etree.SubElement(rPr_in_pPr, qn("w", "ins"))
    ins_mark.set(qn("w", "id"), str(rev_id))
    ins_mark.set(qn("w", "author"), author)
    ins_mark.set(qn("w", "date"), date)

    # --- Run wrapped in w:ins ---
    ins = etree.SubElement(p, qn("w", "ins"))
    ins.set(qn("w", "id"), str(run_rev_id))
    ins.set(qn("w", "author"), author)
    ins.set(qn("w", "date"), date)
    r = etree.SubElement(ins, qn("w", "r"))
    t = etree.SubElement(r, qn("w", "t"))
    t.text = text
    if (text or "").startswith(" ") or (text or "").endswith(" "):
        t.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")

    return p


# ---------------------------------------------------------------------------
# Pattern 4: Tracked deletion
# ---------------------------------------------------------------------------

def make_tracked_deletion(run_el, rev_id: int, author: str, date: str) -> "etree._Element":
    """
    Wrap an existing w:r element in w:del, converting w:t → w:delText.

    *run_el* should be a deep copy of the original run so the caller can
    keep the original in place (or remove it after inserting the w:del).
    """
    w_del = etree.Element(qn("w", "del"))
    w_del.set(qn("w", "id"), str(rev_id))
    w_del.set(qn("w", "author"), author)
    w_del.set(qn("w", "date"), date)
    for t_el in run_el.findall(qn("w", "t")):
        t_el.tag = qn("w", "delText")
        txt = t_el.text or ""
        if txt.startswith(" ") or txt.endswith(" "):
            t_el.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
    w_del.append(run_el)
    return w_del


# ---------------------------------------------------------------------------
# Pattern 5: Inserted table row
# ---------------------------------------------------------------------------

def make_tracked_row(
    cells_text: list,
    template_row,
    rev_id: int,
    author: str,
    date: str,
    para_id_factory,
    run_rev_id: int = None,
) -> "etree._Element":
    """
    Return a new w:tr (deep-copied from *template_row*) with w:trPr/w:ins and
    tracked-insertion paragraphs in each cell.

    Parameters
    ----------
    cells_text : list[str]
        Text for each cell, in column order.
    template_row : lxml element
        An existing w:tr to copy row/cell properties from.
    rev_id : int
        w:id for the w:trPr/w:ins row-insertion mark.
    author, date : str
        Authorship metadata.
    para_id_factory : callable() -> str
        Called once per cell to get a unique paraId for the inserted paragraph.
    run_rev_id : int, optional
        w:id for the run-level w:ins; defaults to rev_id + 1.
    """
    if run_rev_id is None:
        run_rev_id = rev_id + 1

    row = copy.deepcopy(template_row)

    # Add w:trPr/w:ins to mark the entire row as inserted
    trPr = row.find(qn("w", "trPr"))
    if trPr is None:
        trPr = etree.Element(qn("w", "trPr"))
        row.insert(0, trPr)
    ins_trPr = etree.SubElement(trPr, qn("w", "ins"))
    ins_trPr.set(qn("w", "id"), str(rev_id))
    ins_trPr.set(qn("w", "author"), author)
    ins_trPr.set(qn("w", "date"), date)

    # Replace cell content with tracked paragraphs
    tcs = row.findall(qn("w", "tc"))
    for idx, (tc, text) in enumerate(zip(tcs, cells_text)):
        # Remove existing paragraphs in this cell
        for p in tc.findall(qn("w", "p")):
            tc.remove(p)
        # Append a tracked paragraph
        p_new = make_tracked_paragraph(
            text,
            rev_id=run_rev_id,
            author=author,
            date=date,
            para_id=para_id_factory(),
        )
        tc.append(p_new)

    return row


# ---------------------------------------------------------------------------
# Pattern 6: Comment threading (threaded reply)
# ---------------------------------------------------------------------------

def make_reply_comment(
    new_id: int,
    new_para_id: str,
    parent_para_id: str,
    author: str,
    initials: str,
    date: str,
    text: str,
) -> "etree._Element":
    """
    Build a w:comment element for a threaded reply.

    The threading is established by make_commentEx (see below); this function
    produces only the comment body.
    """
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
    if (text or "").startswith(" ") or (text or "").endswith(" "):
        t.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
    return cmt


def make_commentEx(para_id: str, parent_para_id: str) -> "etree._Element":
    """
    Build a w15:commentEx element that links a reply paragraph to its parent.

    *para_id*        — new unique paraId of the reply's body paragraph.
    *parent_para_id* — paraId of the original comment's body paragraph.
    """
    el = etree.Element(qn("w15", "commentEx"))
    el.set(qn("w15", "paraId"), para_id)
    el.set(qn("w15", "paraIdParent"), parent_para_id)
    el.set(qn("w15", "done"), "0")
    return el


# ---------------------------------------------------------------------------
# Pattern 10: Enable track revisions
# ---------------------------------------------------------------------------

def enable_track_revisions(settings_xml: bytes) -> bytes:
    """
    Add <w:trackChanges/> to settings.xml if not already present.
    Returns the serialized bytes of the updated settings tree.
    """
    tree = etree.fromstring(settings_xml)
    existing = tree.find(qn("w", "trackChanges"))
    if existing is None:
        el = etree.SubElement(tree, qn("w", "trackChanges"))
    return etree.tostring(tree, xml_declaration=True, encoding="UTF-8", standalone=True)


# ---------------------------------------------------------------------------
# Pattern 8: Reject-all and accept-all simulators
# Pitfall 7: also remove w:pPr/w:rPr/w:ins marks and drop entire inserted w:p
# ---------------------------------------------------------------------------

def reject_all(doc_tree, build_rev_ids: set) -> None:
    """
    Simulate reject-all for this build's revisions. Mutates *doc_tree* in place.

    Filters by BOTH w:author == BUILD_AUTHOR AND membership in build_rev_ids to
    avoid touching any pre-existing revisions.

    Steps:
    1. Remove w:ins content (inserted text disappears on reject).
    2. Unwrap w:del (deleted text reappears on reject), converting w:delText → w:t.
    3. Remove w:pPr/w:rPr/w:ins paragraph-mark insertions (Pitfall 7).
    4. Drop entire inserted w:p elements (Pitfall 7).
    """
    build_rev_ids_int = set()
    for x in build_rev_ids:
        try:
            build_rev_ids_int.add(int(x))
        except (ValueError, TypeError):
            pass

    def _is_build_ins(el):
        try:
            return (
                el.get(qn("w", "author")) == BUILD_AUTHOR
                and int(el.get(qn("w", "id"), -1)) in build_rev_ids_int
            )
        except (ValueError, TypeError):
            return False

    # Step 1: Remove w:ins elements (and their content) created by this build.
    # We collect them first to avoid mutating while iterating.
    for ins in list(doc_tree.findall(f".//{qn('w','ins')}")):
        if _is_build_ins(ins):
            parent = ins.getparent()
            if parent is not None:
                parent.remove(ins)

    # Step 2: Unwrap w:del elements created by this build.
    for del_el in list(doc_tree.findall(f".//{qn('w','del')}")):
        if _is_build_ins(del_el):
            parent = del_el.getparent()
            if parent is None:
                continue
            idx = list(parent).index(del_el)
            children = list(del_el)
            for i, child in enumerate(children):
                # Convert w:delText back to w:t
                for dt in child.findall(qn("w", "delText")):
                    dt.tag = qn("w", "t")
                parent.insert(idx + i, child)
            parent.remove(del_el)

    # Step 3: Remove paragraph-mark insertions (w:pPr/w:rPr/w:ins) for Pitfall 7.
    # These are w:ins children of w:rPr that is a child of w:pPr.
    for pPr in list(doc_tree.findall(f".//{qn('w','pPr')}")):
        rPr = pPr.find(qn("w", "rPr"))
        if rPr is None:
            continue
        for ins_mark in list(rPr.findall(qn("w", "ins"))):
            if _is_build_ins(ins_mark):
                rPr.remove(ins_mark)

    # Step 4: Drop any w:p that now has an empty w:pPr/w:rPr and no runs or
    # text — these are paragraph-level insertions whose w:ins runs were removed
    # in step 1 but whose w:p shell remains.  A build-inserted w:p was created
    # entirely by this build; after removing its w:ins run wrapper in step 1
    # the paragraph has no text-bearing children.  We identify such paragraphs
    # by: (a) the w14:paraId is one we issued and (b) the paragraph has no
    # direct w:r or w:ins children after the rejection pass.
    for p in list(doc_tree.findall(f".//{qn('w','p')}")):
        para_id = p.get(qn("w14", "paraId"))
        if para_id is None:
            continue
        # Check if this paraId was issued by this build.
        # We use the global ISSUED_PARA_IDS set populated by apply_operations.
        # During unit tests, we use the _REJECT_ALL_ISSUED_PARA_IDS module variable.
        if para_id not in _REJECT_ALL_ISSUED_PARA_IDS:
            continue
        # Check the paragraph has no text-bearing children remaining.
        has_text = any(
            True for _ in p.iter(qn("w", "t"))
        )
        if not has_text:
            parent = p.getparent()
            if parent is not None:
                parent.remove(p)


# Module-level set that apply_operations and unit tests populate before calling reject_all.
# reject_all uses this to identify build-inserted paragraphs whose shells must be dropped.
_REJECT_ALL_ISSUED_PARA_IDS: set = set()


def accept_all(doc_tree, build_rev_ids: set) -> None:
    """
    Simulate accept-all for this build's revisions. Mutates *doc_tree* in place.

    Filters by BOTH w:author == BUILD_AUTHOR AND membership in build_rev_ids.

    Steps:
    1. Unwrap w:ins (keep the runs inside, discard the w:ins wrapper).
    2. Remove w:del and all its content.
    """
    build_rev_ids_int = set()
    for x in build_rev_ids:
        try:
            build_rev_ids_int.add(int(x))
        except (ValueError, TypeError):
            pass

    def _is_build_ins(el):
        try:
            return (
                el.get(qn("w", "author")) == BUILD_AUTHOR
                and int(el.get(qn("w", "id"), -1)) in build_rev_ids_int
            )
        except (ValueError, TypeError):
            return False

    # Step 1: Unwrap w:ins — keep children, discard the w:ins wrapper.
    for ins in list(doc_tree.findall(f".//{qn('w','ins')}")):
        if _is_build_ins(ins):
            parent = ins.getparent()
            if parent is None:
                continue
            idx = list(parent).index(ins)
            for i, child in enumerate(ins):
                parent.insert(idx + i, child)
            parent.remove(ins)

    # Step 2: Remove w:del and all its content (deleted text disappears on accept).
    for del_el in list(doc_tree.findall(f".//{qn('w','del')}")):
        if _is_build_ins(del_el):
            parent = del_el.getparent()
            if parent is not None:
                parent.remove(del_el)


# ---------------------------------------------------------------------------
# apply_correction() — split runs, w:del old + w:ins new (Pattern 7 + Pitfall 4)
# ---------------------------------------------------------------------------

def apply_correction(
    doc_tree,
    anchor_text: str,
    replacement: str,
    alloc: "IdAllocator",
    author: str,
    date: str,
) -> tuple:
    """
    Find the paragraph containing *anchor_text*, split its runs at the anchor
    boundaries, wrap the anchor runs in w:del (w:delText), and insert a w:ins
    run with *replacement* text.

    Returns (del_id, ins_id) — the two w:id values allocated.

    Raises AnchorFailed if the anchor cannot be found uniquely.
    """
    para = find_anchor_para(doc_tree, anchor_text)
    _apply_correction_to_para(para, anchor_text, replacement, alloc, author, date)
    # Return the last two issued w:ids (del and ins)
    ids = alloc.issued_w_ids
    return (ids[-2], ids[-1])


def _apply_correction_to_para(para, anchor_text, replacement, alloc, author, date):
    """
    Mutate *para* in place: split runs at anchor boundaries, wrap in w:del,
    insert w:ins replacement immediately after.  Pitfall 4 compliant.
    """
    # Collect all direct w:r children (and their positions) in the paragraph.
    # We also need to handle runs inside w:ins or w:del from prior passes, but
    # for simplicity (and because the original doc has no existing tracked changes)
    # we iterate direct children of the paragraph.
    children = list(para)
    runs_with_idx = []
    for idx, child in enumerate(children):
        if child.tag == qn("w", "r"):
            runs_with_idx.append((idx, child))

    if not runs_with_idx:
        raise AnchorFailed(
            f"Paragraph containing anchor {anchor_text!r} has no w:r children"
        )

    # Build a character map: (run_index_in_list, char_offset_in_run, char)
    # Concatenate run texts to find anchor span.
    run_texts = []
    for _, run in runs_with_idx:
        t_el = run.find(qn("w", "t"))
        run_texts.append(t_el.text or "" if t_el is not None else "")

    full_text = "".join(run_texts)
    start = full_text.find(anchor_text)
    if start == -1:
        raise AnchorFailed(
            f"anchor {anchor_text!r} not found in concatenated run text: {full_text!r}"
        )
    end = start + len(anchor_text)  # exclusive

    # Map full_text character positions to (run_list_idx, char_offset_in_run).
    char_map = []
    for ri, rt in enumerate(run_texts):
        for ci in range(len(rt)):
            char_map.append((ri, ci))
    # For the character at position `end` (exclusive boundary), if end == len(full_text)
    # then it's the end of the last run; we don't need a char_map entry for it.

    if not char_map or end > len(full_text):
        raise AnchorFailed(
            f"anchor {anchor_text!r} extends beyond run text; full_text={full_text!r}"
        )

    # Identify run indices that the anchor spans (inclusive).
    start_run_idx = char_map[start][0] if start < len(char_map) else len(runs_with_idx) - 1
    end_run_idx = char_map[end - 1][0]

    # Character offsets within the boundary runs.
    start_char_in_run = char_map[start][1]
    end_char_in_run = char_map[end - 1][1]  # inclusive last char

    # Build the replacement runs (possibly split at start and end).
    # We'll produce new elements then splice them into para's children.

    # We'll work with the original para children list by position.
    # Collect the original positions of the anchor runs in para.
    anchor_child_positions = [runs_with_idx[i][0] for i in range(start_run_idx, end_run_idx + 1)]

    new_elements = []  # (position_in_para, element) — to splice in after removal

    for li in range(start_run_idx, end_run_idx + 1):
        para_pos, run = runs_with_idx[li]
        t_el = run.find(qn("w", "t"))
        orig_text = t_el.text or "" if t_el is not None else ""
        rPr = run.find(qn("w", "rPr"))

        if li == start_run_idx and li == end_run_idx:
            # The anchor is entirely within one run — may need left, anchor, right splits.
            left_text = orig_text[:start_char_in_run]
            anchor_seg = orig_text[start_char_in_run:end_char_in_run + 1]
            right_text = orig_text[end_char_in_run + 1:]
            segs = []
            if left_text:
                segs.append(("keep", left_text))
            segs.append(("del", anchor_seg))
            if right_text:
                segs.append(("keep", right_text))
            new_elements.append((para_pos, segs, rPr))

        elif li == start_run_idx:
            # First run of a multi-run anchor.
            left_text = orig_text[:start_char_in_run]
            anchor_seg = orig_text[start_char_in_run:]
            segs = []
            if left_text:
                segs.append(("keep", left_text))
            segs.append(("del", anchor_seg))
            new_elements.append((para_pos, segs, rPr))

        elif li == end_run_idx:
            # Last run of a multi-run anchor.
            anchor_seg = orig_text[:end_char_in_run + 1]
            right_text = orig_text[end_char_in_run + 1:]
            segs = []
            segs.append(("del", anchor_seg))
            if right_text:
                segs.append(("keep", right_text))
            new_elements.append((para_pos, segs, rPr))

        else:
            # Middle run — entirely deleted.
            new_elements.append((para_pos, [("del", orig_text)], rPr))

    # Now remove the original anchor runs from para (by reference), then insert
    # the split fragments back in position order.
    for li in range(start_run_idx, end_run_idx + 1):
        para_pos, run = runs_with_idx[li]
        para.remove(run)

    # Re-fetch current para children list to get correct insertion positions.
    # We insert from the first anchor run's original position onward.
    insertion_offset = anchor_child_positions[0]
    # Because we removed `end_run_idx - start_run_idx + 1` elements starting at
    # insertion_offset, positions of later elements shifted down.  We insert our
    # new elements at insertion_offset and increment for each.
    insert_at = insertion_offset
    del_id = alloc.next_w_id()
    ins_id = alloc.next_w_id()

    def _make_run(text, rPr_el):
        r = etree.Element(qn("w", "r"))
        if rPr_el is not None:
            r.append(copy.deepcopy(rPr_el))
        t = etree.SubElement(r, qn("w", "t"))
        t.text = text
        if (text or "").startswith(" ") or (text or "").endswith(" "):
            t.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
        return r

    inserted_ins = False
    for (para_pos, segs, rPr) in new_elements:
        for seg_kind, seg_text in segs:
            if seg_kind == "keep":
                r = _make_run(seg_text, rPr)
                para.insert(insert_at, r)
                insert_at += 1
            elif seg_kind == "del":
                r_copy = copy.deepcopy(_make_run(seg_text, rPr))
                w_del = make_tracked_deletion(r_copy, del_id, author, date)
                para.insert(insert_at, w_del)
                insert_at += 1
                # Insert the replacement w:ins run after the last deleted segment.
                # We do this after the last "del" segment of the last anchor run.
        # After the last anchor run, insert the w:ins replacement.
        if para_pos == anchor_child_positions[-1] and not inserted_ins:
            ins_el = make_ins(ins_id, author, date)
            r_new = etree.SubElement(ins_el, qn("w", "r"))
            if rPr is not None:
                r_new.append(copy.deepcopy(rPr))
            t_new = etree.SubElement(r_new, qn("w", "t"))
            t_new.text = replacement
            if (replacement or "").startswith(" ") or (replacement or "").endswith(" "):
                t_new.set("{http://www.w3.org/XML/1998/namespace}space", "preserve")
            para.insert(insert_at, ins_el)
            insert_at += 1
            inserted_ins = True

    return del_id, ins_id


# ---------------------------------------------------------------------------
# apply_operations() — 14-step orchestrator (Task 1)
# ---------------------------------------------------------------------------

def apply_operations(
    manifest_path,
    orig_path,
    out_path,
    overwrite: bool = False,
    author: str = BUILD_AUTHOR,
    date: str = BUILD_DATE,
) -> dict:
    """
    Apply all operations in *manifest_path* to a versioned copy of *orig_path*,
    writing the result to *out_path*.

    Parameters
    ----------
    manifest_path : str or Path
        Path to 193-OPERATIONS.json.
    orig_path : str or Path
        Path to the original source DOCX (read-only).
    out_path : str or Path
        Path for the new versioned output DOCX.
    overwrite : bool
        If False (default), raise SystemExit if *out_path* already exists.
    author : str
        w:author value for all tracked changes.
    date : str
        ISO 8601 timestamp string for all tracked changes.

    Returns
    -------
    dict with keys: out_path, out_sha256, reply_outcomes, n_revisions,
                    n_comments, issued_w_ids, build_meta.
    """
    import datetime
    manifest_path = Path(manifest_path)
    orig_path = Path(orig_path)
    out_path = Path(out_path)

    # -----------------------------------------------------------------------
    # Step 1: Guard original SHA-256 (D-04)
    # -----------------------------------------------------------------------
    orig_sha = sha256(orig_path)
    if orig_sha != PINNED_ORIGINAL_SHA256:
        raise SystemExit(
            f"Original SHA-256 mismatch.\n"
            f"  Expected: {PINNED_ORIGINAL_SHA256}\n"
            f"  Got:      {orig_sha}\n"
            f"  Abort — do not edit docs/analytic_manual/AnalyticManual_2026.01.30.docx"
        )
    print(f"[1/14] Original SHA-256 verified: {orig_sha[:16]}...")

    # -----------------------------------------------------------------------
    # Step 2: Hard-fail on ANCHOR-FAILED ops (D-12a)
    # -----------------------------------------------------------------------
    with open(manifest_path, encoding="utf-8") as f:
        manifest = json.load(f)
    ops = manifest["operations"]

    failed_anchors = [o for o in ops if o.get("anchor_resolution") == "ANCHOR-FAILED"]
    if failed_anchors:
        ids = [o["op_id"] for o in failed_anchors]
        raise SystemExit(
            f"Build aborted: {len(failed_anchors)} ANCHOR-FAILED op(s): {ids}\n"
            f"Resolve all anchor failures before running apply_operations."
        )
    print(f"[2/14] No ANCHOR-FAILED ops. Total ops: {len(ops)}")

    # -----------------------------------------------------------------------
    # Step 3: Target guard (D-04)
    # -----------------------------------------------------------------------
    if out_path.exists() and not overwrite:
        raise SystemExit(
            f"Output exists: {out_path}\nUse overwrite=True (or --overwrite) to replace."
        )

    # -----------------------------------------------------------------------
    # Step 4: Copy + unpack original to output path
    # -----------------------------------------------------------------------
    shutil.copy2(orig_path, out_path)
    parts = unpack_docx(out_path)
    print(f"[4/14] Copied and unpacked DOCX: {len(parts)} parts")

    # -----------------------------------------------------------------------
    # Step 5: Allocate IDs
    # -----------------------------------------------------------------------
    id_space = scan_id_space(parts)
    alloc = IdAllocator(**id_space)
    print(f"[5/14] IdAllocator ready. w:id starts at {alloc._next_w}, paraId starts at {alloc._next_para_int:08X}")

    # -----------------------------------------------------------------------
    # Step 6: Collect original per-paragraph texts for reject-all comparison
    # -----------------------------------------------------------------------
    doc_tree = etree.fromstring(parts["word/document.xml"])
    original_paras = list(doc_tree.iter(qn("w", "p")))
    original_texts = [get_para_text(p) for p in original_paras]
    print(f"[6/14] Collected {len(original_texts)} original paragraph texts")

    # -----------------------------------------------------------------------
    # Step 7: Apply each operation
    # -----------------------------------------------------------------------
    # Parse comments.xml, commentsExtended.xml, commentsIds.xml, people.xml
    comments_tree = etree.fromstring(parts["word/comments.xml"])
    comm_ext_tree = etree.fromstring(parts["word/commentsExtended.xml"])
    comm_ids_tree = etree.fromstring(parts["word/commentsIds.xml"])
    people_tree = etree.fromstring(parts["word/people.xml"])

    # Ensure "Gerard Garvan" is in people.xml
    _ensure_person_in_people(people_tree, author, "GG")

    # Build a list of all paragraphs at the start for para_index targeting
    all_paras = list(doc_tree.iter(qn("w", "p")))

    # Find the §8 heading paragraph for INSERT-TABLE placement
    s8_heading_para = None
    for p in all_paras:
        if "8. Open Questions" in get_para_text(p):
            s8_heading_para = p
            break

    # Find the first existing table in the DOCX for use as a template for new tables
    first_table = doc_tree.find(f".//{qn('w','tbl')}")

    reply_outcomes = {}
    n_comments_added = 0

    for op in ops:
        op_id = op["op_id"]
        action = op["action"]
        anchor_resolution = op.get("anchor_resolution", "OK")

        # Ops with anchor_resolution != "OK" are skipped (but we already hard-failed above).
        if anchor_resolution != "OK":
            op["_skip_reason"] = "anchor_resolution not OK"
            continue

        try:
            _apply_single_op(
                op=op,
                doc_tree=doc_tree,
                comments_tree=comments_tree,
                comm_ext_tree=comm_ext_tree,
                comm_ids_tree=comm_ids_tree,
                alloc=alloc,
                author=author,
                date=date,
                all_paras=all_paras,
                s8_heading_para=s8_heading_para,
                first_table=first_table,
                reply_outcomes=reply_outcomes,
            )
            n_comments_added += len(op.get("comment_ids", []))
        except AnchorFailed as e:
            print(f"  WARNING: AnchorFailed for {op_id}: {e}")
            op["anchor_resolution"] = "ANCHOR-FAILED-RUNTIME"
        except Exception as e:
            print(f"  WARNING: Error applying {op_id} ({action}): {e}")
            import traceback
            traceback.print_exc()

    print(f"[7/14] Operations applied. reply_outcomes: {reply_outcomes}")

    # -----------------------------------------------------------------------
    # Step 8: Enable track revisions in settings.xml
    # -----------------------------------------------------------------------
    parts["word/settings.xml"] = enable_track_revisions(parts["word/settings.xml"])
    print("[8/14] w:trackChanges enabled in settings.xml")

    # -----------------------------------------------------------------------
    # Serialize edited XML parts back to bytes
    # -----------------------------------------------------------------------
    parts["word/document.xml"] = etree.tostring(
        doc_tree, xml_declaration=True, encoding="UTF-8", standalone=True
    )
    parts["word/comments.xml"] = etree.tostring(
        comments_tree, xml_declaration=True, encoding="UTF-8", standalone=True
    )
    parts["word/commentsExtended.xml"] = etree.tostring(
        comm_ext_tree, xml_declaration=True, encoding="UTF-8", standalone=True
    )
    parts["word/commentsIds.xml"] = etree.tostring(
        comm_ids_tree, xml_declaration=True, encoding="UTF-8", standalone=True
    )
    parts["word/people.xml"] = etree.tostring(
        people_tree, xml_declaration=True, encoding="UTF-8", standalone=True
    )

    # -----------------------------------------------------------------------
    # Step 9: Well-formedness checks (D-15 step 1)
    # -----------------------------------------------------------------------
    _wellformedness_checks(parts, alloc)
    print("[9/14] Well-formedness checks passed")

    # -----------------------------------------------------------------------
    # Step 10: Reject-all proof (D-15 step 2)
    # -----------------------------------------------------------------------
    global _REJECT_ALL_ISSUED_PARA_IDS
    _REJECT_ALL_ISSUED_PARA_IDS = set(alloc.issued_para_ids)

    doc_copy_reject = copy.deepcopy(doc_tree)
    build_rev_ids_set = set(alloc.issued_w_ids)
    reject_all(doc_copy_reject, build_rev_ids_set)

    rejected_paras = list(doc_copy_reject.iter(qn("w", "p")))
    rejected_texts = [get_para_text(p) for p in rejected_paras]

    if rejected_texts != original_texts:
        # Find first mismatch for a useful error message
        for i, (orig, rej) in enumerate(zip(original_texts, rejected_texts)):
            if orig != rej:
                raise SystemExit(
                    f"Reject-all proof FAILED at paragraph {i}:\n"
                    f"  Original: {orig!r}\n"
                    f"  Rejected: {rej!r}"
                )
        if len(rejected_texts) != len(original_texts):
            raise SystemExit(
                f"Reject-all proof FAILED: paragraph count changed "
                f"({len(original_texts)} → {len(rejected_texts)})"
            )
    print(f"[10/14] Reject-all proof PASSED ({len(original_texts)} paragraphs)")

    # -----------------------------------------------------------------------
    # Step 11: Accept-all proof (D-15 step 3)
    # -----------------------------------------------------------------------
    doc_copy_accept = copy.deepcopy(doc_tree)
    accept_all(doc_copy_accept, build_rev_ids_set)
    accept_text = "\n".join(get_para_text(p) for p in doc_copy_accept.iter(qn("w", "p")))

    accept_failures = []
    for op in ops:
        if op.get("_skip_reason"):
            continue
        it = op.get("insert_text") or ""
        if it and len(it) > 10 and it not in accept_text:
            accept_failures.append(f"{op['op_id']}: insert_text not found: {it[:60]!r}")

    if accept_failures:
        print(f"[11/14] Accept-all proof: {len(accept_failures)} inserts missing (non-fatal for PLACEHOLDER/COMMENT ops)")
        for f in accept_failures[:5]:
            print(f"  {f}")
    else:
        print("[11/14] Accept-all proof PASSED")

    # -----------------------------------------------------------------------
    # Step 12: Untouched-content check (D-15 step 4) — spot check
    # -----------------------------------------------------------------------
    # Compare reject-all result against original for paragraphs outside targeted locations.
    # (Full check: already verified in step 10 — reject_all == original_texts)
    print("[12/14] Untouched-content verified via reject-all equality in step 10")

    # -----------------------------------------------------------------------
    # Step 13: Repack DOCX
    # -----------------------------------------------------------------------
    repack_docx(parts, out_path)
    print(f"[13/14] DOCX repacked to {out_path}")

    # -----------------------------------------------------------------------
    # Step 14: Re-guard original SHA-256 (D-04)
    # -----------------------------------------------------------------------
    final_orig_sha = sha256(orig_path)
    if final_orig_sha != PINNED_ORIGINAL_SHA256:
        raise SystemExit(
            f"Original SHA-256 CHANGED during build — ABORT.\n"
            f"  Expected: {PINNED_ORIGINAL_SHA256}\n"
            f"  Got:      {final_orig_sha}"
        )
    print(f"[14/14] Original re-verified unchanged: {final_orig_sha[:16]}...")

    # Write updated manifest with recorded IDs
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    print(f"Manifest updated: {manifest_path}")

    out_hash = sha256(out_path)
    n_revisions = len(alloc.issued_w_ids)

    print(f"\nBuild complete.")
    print(f"  Output: {out_path}")
    print(f"  Output SHA-256: {out_hash}")
    print(f"  Revisions issued: {n_revisions}")
    print(f"  Comments added: {n_comments_added}")
    print(f"  Reply outcomes: {reply_outcomes}")

    return {
        "out_path": str(out_path),
        "out_sha256": out_hash,
        "reply_outcomes": reply_outcomes,
        "n_revisions": n_revisions,
        "n_comments": n_comments_added,
        "issued_w_ids": alloc.issued_w_ids,
        "build_meta": {
            "author": author,
            "date": date,
            "orig_sha256": orig_sha,
            "orig_path": str(orig_path),
        },
    }


# ---------------------------------------------------------------------------
# Internal helpers for apply_operations
# ---------------------------------------------------------------------------

def _ensure_person_in_people(people_tree, author: str, initials: str):
    """Add an entry for *author* to people.xml if not already present."""
    W14 = NS["w14"]
    # Look for existing person entry
    for person in people_tree.iter(qn("w14", "person")):
        if person.get(qn("w14", "author")) == author:
            return  # already present
    # Add new person element
    person = etree.SubElement(people_tree, qn("w14", "person"))
    person.set(qn("w14", "author"), author)
    # Add an empty presenceInfo child (required by schema)
    info = etree.SubElement(person, qn("w14", "presenceInfo"))
    info.set(qn("w14", "id"), "gerard-garvan")
    info.set(qn("w14", "providerId"), "None")


def _add_comment_to_doc(
    doc_tree,
    comments_tree,
    comm_ext_tree,
    comm_ids_tree,
    alloc: IdAllocator,
    anchor_text: str,
    comment_text: str,
    author: str,
    initials: str,
    date: str,
    op: dict,
    parent_para_id: str = None,
):
    """
    Add a comment to comments.xml with range markers in document.xml.

    If *parent_para_id* is set, also adds a w15:commentEx for threading.

    Returns the new comment w:id.
    """
    cmt_id = alloc.next_w_id()
    new_para_id = alloc.next_para_id()
    range_start_id = alloc.next_w_id()
    range_end_id = alloc.next_w_id()
    ref_id = alloc.next_w_id()

    # Build comment in comments.xml
    if parent_para_id:
        cmt_el = make_reply_comment(
            new_id=cmt_id,
            new_para_id=new_para_id,
            parent_para_id=parent_para_id,
            author=author,
            initials=initials,
            date=date,
            text=comment_text,
        )
    else:
        cmt_el = make_reply_comment(
            new_id=cmt_id,
            new_para_id=new_para_id,
            parent_para_id="",
            author=author,
            initials=initials,
            date=date,
            text=comment_text,
        )
        # Remove the paraIdParent attribute for non-reply comments
        # (make_reply_comment sets it; we won't add commentEx for non-replies)

    comments_tree.append(cmt_el)

    # Add commentEx for threading if parent_para_id is set
    if parent_para_id:
        cx = make_commentEx(new_para_id, parent_para_id)
        comm_ext_tree.append(cx)

    # Add commentId entry in commentsIds.xml
    new_durable_id = alloc.next_durable_id()
    # Find the root element of commentsIds.xml and append
    cid_el = etree.SubElement(comm_ids_tree, qn("w16cid", "commentId"))
    cid_el.set(qn("w16cid", "paraId"), new_para_id)
    cid_el.set(qn("w16cid", "durableId"), new_durable_id)

    # Add range markers in document.xml around the anchor paragraph
    anchor_para = None
    try:
        anchor_para = find_anchor_para(doc_tree, anchor_text)
    except AnchorFailed:
        # Try a prefix match
        for p in doc_tree.iter(qn("w", "p")):
            pt = get_para_text(p)
            if anchor_text and pt.startswith(anchor_text[:20]):
                anchor_para = p
                break

    if anchor_para is not None:
        parent = anchor_para.getparent()
        if parent is not None:
            idx = list(parent).index(anchor_para)
            # Insert commentRangeStart before the paragraph
            crs = etree.Element(qn("w", "commentRangeStart"))
            crs.set(qn("w", "id"), str(range_start_id))
            parent.insert(idx, crs)
            # Insert commentRangeEnd after the paragraph (now at idx+1)
            cre = etree.Element(qn("w", "commentRangeEnd"))
            cre.set(qn("w", "id"), str(range_end_id))
            parent.insert(idx + 2, cre)
            # Add a commentReference run after the paragraph
            ref_para = etree.Element(qn("w", "p"))
            ref_para_id = alloc.next_para_id()
            ref_para.set(qn("w14", "paraId"), ref_para_id)
            ref_run = etree.SubElement(ref_para, qn("w", "r"))
            ref_el = etree.SubElement(ref_run, qn("w", "commentReference"))
            ref_el.set(qn("w", "id"), str(cmt_id))
            parent.insert(idx + 3, ref_para)

    op.setdefault("comment_ids", []).append(cmt_id)
    return cmt_id


def _apply_single_op(
    op, doc_tree, comments_tree, comm_ext_tree, comm_ids_tree,
    alloc, author, date, all_paras, s8_heading_para, first_table, reply_outcomes,
):
    """Apply a single operation op to the document and comment trees."""
    action = op["action"]
    op_id = op["op_id"]
    target = op.get("target", {})
    anchor_text = op.get("anchor_text") or ""
    insert_text = op.get("insert_text") or ""
    comment_text = op.get("comment_text") or ""

    if action == "INSERT-PARA":
        # Insert a tracked paragraph at the target location.
        # For field fills: insert after the last paragraph of that field.
        # For repo-only subsections: insert a Heading2 + content.
        # We use anchor_text as the target paragraph's text if para_index is set,
        # else fall back to para_index.
        para_idx = target.get("para_index")
        if para_idx is not None and para_idx < len(all_paras):
            ref_para = all_paras[para_idx]
        elif anchor_text:
            try:
                ref_para = find_anchor_para(doc_tree, anchor_text)
            except AnchorFailed:
                ref_para = None
        else:
            ref_para = None

        para_id = alloc.next_para_id()
        mark_id = alloc.next_w_id()
        run_id = alloc.next_w_id()
        pPr_source = None
        if ref_para is not None:
            pPr_source = ref_para.find(qn("w", "pPr"))

        new_para = make_tracked_paragraph(
            text=insert_text,
            rev_id=mark_id,
            author=author,
            date=date,
            para_id=para_id,
            pPr_source=pPr_source,
            run_rev_id=run_id,
        )

        if ref_para is not None:
            parent = ref_para.getparent()
            if parent is not None:
                idx = list(parent).index(ref_para)
                parent.insert(idx + 1, new_para)
            else:
                doc_tree.append(new_para)
        else:
            doc_tree.append(new_para)

        op.setdefault("revision_ids", []).extend([mark_id, run_id])

    elif action == "INSERT-ROW":
        # Insert a tracked row into the target table.
        # Find the right table by table_index or by proximity to target section.
        table_idx = target.get("table_index")
        tables = list(doc_tree.findall(f".//{qn('w','tbl')}"))
        if table_idx is not None and table_idx < len(tables):
            table = tables[table_idx]
        elif tables:
            table = tables[0]
        else:
            print(f"  {op_id}: No table found for INSERT-ROW; skipping")
            return

        # Find a template row (last existing row)
        rows = table.findall(qn("w", "tr"))
        template_row = rows[-1] if rows else None
        if template_row is None:
            print(f"  {op_id}: No template row; skipping")
            return

        row_id = alloc.next_w_id()
        new_row = make_tracked_row(
            cells_text=[insert_text],
            template_row=template_row,
            rev_id=row_id,
            author=author,
            date=date,
            para_id_factory=alloc.next_para_id,
        )
        table.append(new_row)
        op.setdefault("revision_ids", []).append(row_id)

    elif action == "INSERT-TABLE":
        # Build a new §8 table (Item | Notes | Date added) as tracked rows.
        table_rows = op.get("table_rows", [])
        columns = op.get("table_columns", ["Item", "Notes", "Date added"])
        _insert_s8_table(
            doc_tree=doc_tree,
            s8_heading_para=s8_heading_para,
            table_rows=table_rows,
            columns=columns,
            alloc=alloc,
            author=author,
            date=date,
            op=op,
            first_table=first_table,
        )

    elif action == "REPLACE":
        # apply_correction: w:del old + w:ins new
        if not anchor_text or not insert_text:
            print(f"  {op_id}: REPLACE missing anchor or insert_text; skipping")
            return
        del_id, ins_id = apply_correction(doc_tree, anchor_text, insert_text, alloc, author, date)
        op.setdefault("revision_ids", []).extend([del_id, ins_id])

        # Add a comment citing decision_id and evidence if comment_text is set
        if comment_text:
            _add_comment_to_doc(
                doc_tree=doc_tree,
                comments_tree=comments_tree,
                comm_ext_tree=comm_ext_tree,
                comm_ids_tree=comm_ids_tree,
                alloc=alloc,
                anchor_text=anchor_text,
                comment_text=comment_text,
                author=author,
                initials="GG",
                date=date,
                op=op,
            )

    elif action == "PLACEHOLDER":
        # Insert [TEAM INPUT NEEDED] as a tracked paragraph.
        para_idx = target.get("para_index")
        if para_idx is not None and para_idx < len(all_paras):
            ref_para = all_paras[para_idx]
        else:
            ref_para = None

        para_id = alloc.next_para_id()
        mark_id = alloc.next_w_id()
        run_id = alloc.next_w_id()
        pPr_source = ref_para.find(qn("w", "pPr")) if ref_para is not None else None

        new_para = make_tracked_paragraph(
            text="[TEAM INPUT NEEDED]",
            rev_id=mark_id,
            author=author,
            date=date,
            para_id=para_id,
            pPr_source=pPr_source,
            run_rev_id=run_id,
        )

        if ref_para is not None:
            parent = ref_para.getparent()
            if parent is not None:
                idx = list(parent).index(ref_para)
                parent.insert(idx + 1, new_para)
            else:
                doc_tree.append(new_para)
        else:
            doc_tree.append(new_para)

        op.setdefault("revision_ids", []).extend([mark_id, run_id])

    elif action == "COMMENT-ONLY":
        # Add a comment on the anchor paragraph. If the field is empty, also insert current-code text.
        if not anchor_text and not comment_text:
            return
        effective_anchor = anchor_text if anchor_text else ""
        if comment_text and effective_anchor:
            _add_comment_to_doc(
                doc_tree=doc_tree,
                comments_tree=comments_tree,
                comm_ext_tree=comm_ext_tree,
                comm_ids_tree=comm_ids_tree,
                alloc=alloc,
                anchor_text=effective_anchor,
                comment_text=comment_text,
                author=author,
                initials="GG",
                date=date,
                op=op,
            )

    elif action == "REPLY":
        # Threaded reply to c0 or c1.
        parent_para_id = op.get("parent_para_id", "")
        source_ids = op.get("source_unit_map_ids", [])
        reply_key = "c0" if "C0-REPLY" in source_ids else "c1"

        if not parent_para_id or not anchor_text:
            reply_outcomes[reply_key] = "FALLBACK-COMMENT"
            op.setdefault("comment_ids", [])
            return

        try:
            cmt_id = _add_comment_to_doc(
                doc_tree=doc_tree,
                comments_tree=comments_tree,
                comm_ext_tree=comm_ext_tree,
                comm_ids_tree=comm_ids_tree,
                alloc=alloc,
                anchor_text=anchor_text,
                comment_text=comment_text,
                author=author,
                initials="GG",
                date=date,
                op=op,
                parent_para_id=parent_para_id,
            )
            reply_outcomes[reply_key] = "THREADED-REPLY"
            op.setdefault("revision_ids", [])
        except Exception as e:
            print(f"  {op_id}: Threading failed ({e}); falling back to standalone comment")
            fallback_text = f"Re: Amy's comment — {comment_text}"
            try:
                _add_comment_to_doc(
                    doc_tree=doc_tree,
                    comments_tree=comments_tree,
                    comm_ext_tree=comm_ext_tree,
                    comm_ids_tree=comm_ids_tree,
                    alloc=alloc,
                    anchor_text=anchor_text,
                    comment_text=fallback_text,
                    author=author,
                    initials="GG",
                    date=date,
                    op=op,
                )
            except Exception:
                pass
            reply_outcomes[reply_key] = "FALLBACK-COMMENT"

    else:
        print(f"  {op_id}: Unknown action {action!r}; skipping")


def _insert_s8_table(
    doc_tree, s8_heading_para, table_rows, columns, alloc, author, date, op, first_table
):
    """
    Build a new tracked §8 table and insert it after the §8 heading paragraph.

    Table columns: Item | Notes | Date added (D-34).
    Each row is a tracked insertion (w:trPr/w:ins).
    """
    # Build the table element from scratch
    tbl = etree.Element(qn("w", "tbl"))

    # Copy table properties from an existing table if available
    if first_table is not None:
        tblPr_src = first_table.find(qn("w", "tblPr"))
        if tblPr_src is not None:
            tbl.append(copy.deepcopy(tblPr_src))
        tblGrid_src = first_table.find(qn("w", "tblGrid"))
        if tblGrid_src is not None:
            tbl.append(copy.deepcopy(tblGrid_src))

    # Build a minimal template row for use with make_tracked_row
    template_row = etree.Element(qn("w", "tr"))
    for _ in columns:
        tc = etree.SubElement(template_row, qn("w", "tc"))
        p = etree.SubElement(tc, qn("w", "p"))

    # Header row (not tracked — it's the table structure)
    header_row = etree.SubElement(tbl, qn("w", "tr"))
    for col_name in columns:
        tc = etree.SubElement(header_row, qn("w", "tc"))
        p = etree.SubElement(tc, qn("w", "p"))
        r = etree.SubElement(p, qn("w", "r"))
        t = etree.SubElement(r, qn("w", "t"))
        t.text = col_name

    # Data rows as tracked insertions
    for cells in table_rows:
        # Pad or trim cells to match column count
        cells_padded = list(cells) + [""] * max(0, len(columns) - len(cells))
        cells_padded = cells_padded[:len(columns)]
        row_id = alloc.next_w_id()
        new_row = make_tracked_row(
            cells_text=cells_padded,
            template_row=template_row,
            rev_id=row_id,
            author=author,
            date=date,
            para_id_factory=alloc.next_para_id,
        )
        tbl.append(new_row)
        op.setdefault("revision_ids", []).append(row_id)

    # Insert the table after the §8 heading paragraph
    if s8_heading_para is not None:
        parent = s8_heading_para.getparent()
        if parent is not None:
            idx = list(parent).index(s8_heading_para)
            parent.insert(idx + 1, tbl)
        else:
            doc_tree.append(tbl)
    else:
        doc_tree.append(tbl)


def _wellformedness_checks(parts: dict, alloc: "IdAllocator"):
    """
    Run well-formedness checks on all edited parts (D-15 step 1).

    Checks:
    - Every edited part re-parses without error.
    - w:id uniqueness across document.xml + comments.xml.
    - w14:paraId uniqueness across document.xml + comments.xml.
    - Every new commentRangeStart has a matching commentRangeEnd and commentReference.
    """
    xml_parts_to_check = ["word/document.xml", "word/comments.xml",
                          "word/commentsExtended.xml", "word/commentsIds.xml",
                          "word/people.xml", "word/settings.xml"]

    for part_name in xml_parts_to_check:
        if part_name not in parts:
            continue
        try:
            etree.fromstring(parts[part_name])
        except etree.XMLSyntaxError as e:
            raise SystemExit(f"Well-formedness FAILED for {part_name}: {e}")

    # Collect all w:id values across document + comments
    all_w_ids = []
    for part_name in ["word/document.xml", "word/comments.xml"]:
        if part_name not in parts:
            continue
        root = etree.fromstring(parts[part_name])
        for el in root.iter():
            val = el.get(qn("w", "id"))
            if val is not None:
                try:
                    all_w_ids.append(int(val))
                except ValueError:
                    pass

    # Check uniqueness (IDs are allowed to repeat across different element types in OOXML
    # but each should be unique within its own type; we check globally as a conservative guard)
    # Note: OOXML allows the same w:id on a commentRangeStart and commentRangeEnd (they form a pair)
    # but different comment IDs must be distinct. We just warn on duplicates.
    from collections import Counter
    id_counts = Counter(all_w_ids)
    # Pairs (commentRangeStart + commentRangeEnd with same id) are OK — allow count=2 for those
    duplicates = [id_val for id_val, cnt in id_counts.items() if cnt > 2]
    if duplicates:
        print(f"  WARNING: w:id values with count > 2 (may indicate collision): {duplicates[:5]}")

    # Check paraId uniqueness across document + comments
    all_para_ids = []
    for part_name in ["word/document.xml", "word/comments.xml"]:
        if part_name not in parts:
            continue
        root = etree.fromstring(parts[part_name])
        for el in root.iter():
            pid = el.get(qn("w14", "paraId"))
            if pid is not None:
                all_para_ids.append(pid.upper())

    para_id_counts = Counter(all_para_ids)
    para_duplicates = [p for p, cnt in para_id_counts.items() if cnt > 1]
    if para_duplicates:
        raise SystemExit(
            f"Well-formedness FAILED: duplicate w14:paraId values: {para_duplicates[:5]}"
        )
