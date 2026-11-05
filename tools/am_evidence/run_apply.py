"""
run_apply.py — Runner for apply_operations() to produce AnalyticManual_2026.10.28.docx.

Usage (from tools/am_evidence/):
  python run_apply.py
"""

import sys
sys.path.insert(0, '.')

import am_manual_lib as m

result = m.apply_operations(
    manifest_path='../../.planning/phases/193-produce-updated-manual/193-OPERATIONS.json',
    orig_path='../../docs/analytic_manual/AnalyticManual_2026.01.30.docx',
    out_path='../../docs/analytic_manual/AnalyticManual_2026.10.28.docx',
    overwrite=True,
)
print("\n=== apply_operations result ===")
print(f"out_path:       {result['out_path']}")
print(f"out_sha256:     {result['out_sha256']}")
print(f"n_revisions:    {result['n_revisions']}")
print(f"n_comments:     {result['n_comments']}")
print(f"reply_outcomes: {result['reply_outcomes']}")
print(f"orig intact:    {m.sha256('../../docs/analytic_manual/AnalyticManual_2026.01.30.docx') == m.PINNED_ORIGINAL_SHA256}")
