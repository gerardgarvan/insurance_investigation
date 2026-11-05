#!/usr/bin/env python3
"""
build_operations_json.py — Task 1 of Phase 193 Plan 02.

Calls build_operations(), resolves anchors against the original DOCX (dry-run),
and writes 193-OPERATIONS.json.

Run from repo root:
  python tools/am_evidence/build_operations_json.py
"""

import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).parent
REPO_ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))

import am_manual_lib as m
from lxml import etree

DRAFT_PATH = REPO_ROOT / ".planning" / "phases" / "192-draft-new-content" / "AM-DRAFT.md"
DOCX_PATH = REPO_ROOT / "docs" / "analytic_manual" / "AnalyticManual_2026.01.30.docx"
OUT_PATH = (
    REPO_ROOT
    / ".planning"
    / "phases"
    / "193-produce-updated-manual"
    / "193-OPERATIONS.json"
)

ACTIONS_WITH_ANCHOR = {"REPLACE", "COMMENT-ONLY", "REPLY"}


def get_git_commit() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True,
            text=True,
            cwd=str(REPO_ROOT),
        )
        return result.stdout.strip()
    except Exception:
        return "unknown"


def resolve_anchors(ops: list, parts: dict) -> list:
    """
    For every op with anchor_text, dry-run the D-12a anchor match.
    Sets anchor_resolution to 'OK' or 'ANCHOR-FAILED'.
    For OK anchors, records para_index into op['target'].
    """
    doc_tree = etree.fromstring(parts["word/document.xml"])
    all_paras = list(doc_tree.iter(m.qn("w", "p")))
    para_index_map = {id(p): i for i, p in enumerate(all_paras)}

    for op in ops:
        if op.get("anchor_text") is None or op["action"] not in ACTIONS_WITH_ANCHOR:
            continue
        anchor = op["anchor_text"]
        if not anchor:
            op["anchor_resolution"] = "OK"
            continue
        try:
            matched_para = m.find_anchor_para(doc_tree, anchor)
            # Unique match — record para_index
            idx = para_index_map.get(id(matched_para))
            if isinstance(op.get("target"), dict):
                op["target"]["para_index"] = idx
            else:
                op["target"] = {
                    "section": op.get("target", {}).get("section", "")
                    if isinstance(op.get("target"), dict)
                    else "",
                    "kind": "comment_anchor"
                    if op["action"] == "REPLY"
                    else "field",
                    "para_index": idx,
                    "table_index": None,
                    "row_index": None,
                    "cell_index": None,
                }
            op["anchor_resolution"] = "OK"
        except m.AnchorFailed as exc:
            op["anchor_resolution"] = "ANCHOR-FAILED"
            op["anchor_failure_reason"] = str(exc)

    # Any remaining PENDING → ANCHOR-FAILED (should not happen, but guard)
    for op in ops:
        if op.get("anchor_resolution") == "PENDING":
            op["anchor_resolution"] = "ANCHOR-FAILED"
            op["anchor_failure_reason"] = "anchor_resolution never resolved"

    return ops


def main():
    # --- Build operations ---
    ops = m.build_operations(str(DRAFT_PATH), None)
    print(f"build_operations() returned {len(ops)} ops", file=sys.stderr)

    # --- Load DOCX for anchor dry-run ---
    if not DOCX_PATH.exists():
        print(f"ERROR: DOCX not found at {DOCX_PATH}", file=sys.stderr)
        sys.exit(1)
    actual_sha = m.sha256(DOCX_PATH)
    if actual_sha != m.PINNED_ORIGINAL_SHA256:
        print(
            f"WARNING: DOCX SHA-256 mismatch.\n"
            f"  expected: {m.PINNED_ORIGINAL_SHA256}\n"
            f"  actual:   {actual_sha}",
            file=sys.stderr,
        )

    parts = m.unpack_docx(DOCX_PATH)
    ops = resolve_anchors(ops, parts)

    # --- Tally expected counts ---
    action_counts = {}
    for op in ops:
        a = op["action"]
        action_counts[a] = action_counts.get(a, 0) + 1

    n_anchor_failed = sum(
        1 for op in ops if op.get("anchor_resolution") == "ANCHOR-FAILED"
    )

    expected_counts = {
        "n_operations": len(ops),
        "n_insert_para": action_counts.get("INSERT-PARA", 0),
        "n_insert_row": action_counts.get("INSERT-ROW", 0),
        "n_insert_table": action_counts.get("INSERT-TABLE", 0),
        "n_replace": action_counts.get("REPLACE", 0),
        "n_comment_only": action_counts.get("COMMENT-ONLY", 0),
        "n_placeholder": action_counts.get("PLACEHOLDER", 0),
        "n_reply": action_counts.get("REPLY", 0),
        "n_anchor_failed": n_anchor_failed,
    }

    build_meta = {
        "original_sha256": actual_sha,
        "pinned_sha256": m.PINNED_ORIGINAL_SHA256,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "git_commit": get_git_commit(),
    }

    manifest = {
        "build_meta": build_meta,
        "expected_counts": expected_counts,
        "operations": ops,
    }

    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    print(f"Written: {OUT_PATH}", file=sys.stderr)
    print(
        f"ops={len(ops)} INSERT-TABLE={action_counts.get('INSERT-TABLE',0)} "
        f"REPLY={action_counts.get('REPLY',0)} ANCHOR-FAILED={n_anchor_failed}",
        file=sys.stderr,
    )

    if n_anchor_failed > 0:
        failed = [op["op_id"] for op in ops if op.get("anchor_resolution") == "ANCHOR-FAILED"]
        print(f"ANCHOR-FAILED: {n_anchor_failed} — {failed}", file=sys.stderr)

    # Print histogram to stdout for caller
    print(json.dumps(action_counts))


if __name__ == "__main__":
    main()
