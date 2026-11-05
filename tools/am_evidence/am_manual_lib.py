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
