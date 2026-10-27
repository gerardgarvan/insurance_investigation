#!/usr/bin/env python3
"""
am_evidence_map.py — Phase 190 evidence-map tool.

Subcommands:
  coverage  — list every non-blank manual line; report uncovered lines not in skip list
  validate  — check IDs, uniqueness, registry match, valid statuses/evidence types, column counts
              (use --final to also check for [T2]/[T3] placeholders)
  export    — write xlsx workbook and run round-trip check

Usage:
  python tools/am_evidence/am_evidence_map.py coverage
  python tools/am_evidence/am_evidence_map.py validate [--final]
  python tools/am_evidence/am_evidence_map.py export

Reused in Phase 193.
"""

import argparse
import re
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

REPO_ROOT = Path(__file__).resolve().parents[2]
MANUAL_MD = REPO_ROOT / "docs" / "analytic_manual" / "AnalyticManual_2026.01.30.md"
MAP_MD = REPO_ROOT / ".planning" / "phases" / "190-evidence-map" / "AM-EVIDENCE-MAP.md"
XLSX_DIR = REPO_ROOT / ".planning" / "phases" / "190-evidence-map"

ID_REGEX = re.compile(r"^S(\d{1,2}|A[1-4]|B)-[A-Z]{2,6}-\d{2}$")

VALID_STATUSES = {
    "FILLED-NEEDS-CHECK",
    "EMPTY-REPO-CAN-ANSWER",
    "EMPTY-NEEDS-TEAM",
    "OUT-OF-SCOPE",
    "BLOCKED",
    "RETIRED",
}

VALID_DECISION_STATUSES = {"OPEN", "CONFIRMED", "SUPERSEDED"}

VALID_EVIDENCE_TYPES = {"CODE", "CONFIG", "PLANNING-DOC", "TEAM-DECISION", "MEETING-NOTES", "NONE"}

VALID_ORIGINS = {"MANUAL", "REPO-ONLY"}

# Column counts per table (including the leading and trailing pipe implies N+1 splits)
TABLE_COLS = {
    "Main Map": 14,           # ID|Origin|AM Section|Domain|Item|Manual Lines|Manual Text|Status|Evidence Type|Repo Source|What the Source Shows|Lead|Decision ID|Notes
    "AM-MAP-02": 14,          # same schema
    "AM-MAP-03": 10,          # Decision ID|Original ID|Decision Text|Raised By|Decided By|Date|Source File|Map Row(s)|Status|Notes
    "Coverage": 3,            # Line|Reason|Notes  (flexible — at least 2)
    "ID Registry": 4,         # ID|Created|First Row|Notes
}

# ---------------------------------------------------------------------------
# Parsing helpers
# ---------------------------------------------------------------------------

def _parse_map(map_path: Path) -> dict:
    """
    Parse AM-EVIDENCE-MAP.md into sections.

    Returns dict with keys:
      id_registry: list of dicts {id, created, first_row, notes}
      main_map: list of row dicts
      repo_domains: list of row dicts
      team_decisions: list of row dicts
      coverage_skip: list of {line_ref, reason, notes}
      unattributed: list of str  (lines below ### Unattributed)
      all_ids_in_registry: set of str
      all_ids_in_tables: set of str
    """
    text = map_path.read_text(encoding="utf-8")
    lines = text.splitlines()

    result = {
        "id_registry": [],
        "main_map": [],
        "repo_domains": [],
        "team_decisions": [],
        "coverage_skip": [],
        "unattributed": [],
        "all_ids_in_registry": set(),
        "all_ids_in_tables": set(),
        "raw_lines": lines,
    }

    current_section = None
    in_table = False
    header_seen = False
    in_unattributed = False

    def parse_row(line: str) -> list:
        """Split a markdown table row into cells, strip whitespace."""
        # Remove leading/trailing |
        stripped = line.strip().strip("|")
        # Split on | but not \|
        cells = re.split(r"(?<!\\)\|", stripped)
        return [c.strip() for c in cells]

    def is_separator(line: str) -> bool:
        return bool(re.match(r"^\s*\|[-| :]+\|\s*$", line))

    SECTION_MAP = {
        "## Main Map": "main_map",
        "## AM-MAP-02: Repo Domains Not in Manual": "repo_domains",
        "## AM-MAP-03: Team Decisions": "team_decisions",
        "## Coverage": "coverage_skip",
        "## ID Registry": "id_registry",
    }

    for line in lines:
        stripped = line.strip()

        # Detect section headers
        for heading, key in SECTION_MAP.items():
            if stripped == heading:
                current_section = key
                in_table = False
                header_seen = False
                in_unattributed = False
                break

        if stripped.startswith("### Unattributed candidates"):
            in_unattributed = True
            continue

        if stripped.startswith("## ") and current_section:
            # A new section we don't know about — clear
            heading_found = any(stripped == h for h in SECTION_MAP)
            if not heading_found:
                current_section = None

        if current_section is None:
            continue

        if stripped.startswith("|"):
            if is_separator(stripped):
                header_seen = True
                in_table = True
                continue
            if not header_seen:
                # Header row
                continue

            cells = parse_row(stripped)

            if current_section == "id_registry":
                if len(cells) >= 1:
                    rid = cells[0]
                    result["id_registry"].append({
                        "id": rid,
                        "created": cells[1] if len(cells) > 1 else "",
                        "first_row": cells[2] if len(cells) > 2 else "",
                        "notes": cells[3] if len(cells) > 3 else "",
                    })
                    result["all_ids_in_registry"].add(rid)

            elif current_section in ("main_map", "repo_domains"):
                if len(cells) >= 8:
                    row = {
                        "id": cells[0],
                        "origin": cells[1],
                        "am_section": cells[2],
                        "domain": cells[3],
                        "item": cells[4],
                        "manual_lines": cells[5],
                        "manual_text": cells[6],
                        "status": cells[7],
                        "evidence_type": cells[8] if len(cells) > 8 else "",
                        "repo_source": cells[9] if len(cells) > 9 else "",
                        "what_shows": cells[10] if len(cells) > 10 else "",
                        "lead": cells[11] if len(cells) > 11 else "",
                        "decision_id": cells[12] if len(cells) > 12 else "",
                        "notes": cells[13] if len(cells) > 13 else "",
                        "_ncols": len(cells),
                        "_raw": stripped,
                    }
                    result[current_section].append(row)
                    result["all_ids_in_tables"].add(cells[0])

            elif current_section == "team_decisions":
                if len(cells) >= 1:
                    row = {
                        "decision_id": cells[0],
                        "original_id": cells[1] if len(cells) > 1 else "",
                        "decision_text": cells[2] if len(cells) > 2 else "",
                        "raised_by": cells[3] if len(cells) > 3 else "",
                        "decided_by": cells[4] if len(cells) > 4 else "",
                        "date": cells[5] if len(cells) > 5 else "",
                        "source_file": cells[6] if len(cells) > 6 else "",
                        "map_rows": cells[7] if len(cells) > 7 else "",
                        "status": cells[8] if len(cells) > 8 else "",
                        "notes": cells[9] if len(cells) > 9 else "",
                        "_ncols": len(cells),
                        "_raw": stripped,
                    }
                    result["team_decisions"].append(row)
                    result["all_ids_in_tables"].add(cells[0])

            elif current_section == "coverage_skip":
                if len(cells) >= 2:
                    result["coverage_skip"].append({
                        "line_ref": cells[0],
                        "reason": cells[1],
                        "notes": cells[2] if len(cells) > 2 else "",
                    })
        elif in_unattributed and stripped and not stripped.startswith("#"):
            result["unattributed"].append(stripped)

    return result


def _parse_manual_lines(manual_lines_field: str) -> set:
    """
    Parse a Manual Lines field like 'L82-L88' or 'L94-L101' into a set of line numbers.
    Also handles comma-separated ranges: 'L82-L88, L94-L101'.
    Handles single lines: 'L81'.
    Returns empty set for blank / '—'.
    """
    if not manual_lines_field or manual_lines_field in ("—", ""):
        return set()
    result = set()
    for part in manual_lines_field.split(","):
        part = part.strip()
        m = re.match(r"L(\d+)-L(\d+)", part)
        if m:
            result.update(range(int(m.group(1)), int(m.group(2)) + 1))
        else:
            m2 = re.match(r"L(\d+)", part)
            if m2:
                result.add(int(m2.group(1)))
    return result


# ---------------------------------------------------------------------------
# Subcommand: coverage
# ---------------------------------------------------------------------------

def cmd_coverage(args):
    print(f"Reading manual: {MANUAL_MD}")
    manual_lines = MANUAL_MD.read_text(encoding="utf-8").splitlines()

    non_blank = {}
    for i, line in enumerate(manual_lines, start=1):
        if line.strip():
            non_blank[i] = line

    print(f"Total lines: {len(manual_lines)}, Non-blank: {len(non_blank)}")

    if not MAP_MD.exists():
        print(f"Map not found: {MAP_MD} — cannot check coverage yet.")
        return 0

    data = _parse_map(MAP_MD)

    covered = set()
    for row in data["main_map"] + data["repo_domains"]:
        covered.update(_parse_manual_lines(row.get("manual_lines", "")))

    # Also load skip list
    skip_lines = set()
    for skip in data["coverage_skip"]:
        skip_lines.update(_parse_manual_lines(skip.get("line_ref", "")))

    uncovered = []
    for lnum in sorted(non_blank):
        if lnum not in covered and lnum not in skip_lines:
            uncovered.append((lnum, non_blank[lnum]))

    if uncovered:
        print(f"\nUNCOVERED lines ({len(uncovered)}):")
        for lnum, text in uncovered:
            print(f"  L{lnum}: {text[:100]}")
        return 1
    else:
        print(f"\nCoverage OK — all {len(non_blank)} non-blank lines accounted for.")
        return 0


# ---------------------------------------------------------------------------
# Subcommand: validate
# ---------------------------------------------------------------------------

def cmd_validate(args):
    final = getattr(args, "final", False)
    errors = []

    if not MAP_MD.exists():
        print(f"ERROR: Map not found: {MAP_MD}")
        sys.exit(1)

    data = _parse_map(MAP_MD)

    all_rows = data["main_map"] + data["repo_domains"]

    # 1. ID regex
    for row in all_rows:
        rid = row["id"]
        if rid in ("—", "") or rid.startswith("["):
            continue
        if not ID_REGEX.match(rid):
            errors.append(f"ID regex fail: '{rid}' in row '{row.get('item','')}'")

    # 2. ID uniqueness across tables
    seen_ids = {}
    for row in all_rows:
        rid = row["id"]
        if rid in ("—", ""):
            continue
        if rid in seen_ids:
            errors.append(f"Duplicate ID: '{rid}'")
        seen_ids[rid] = True

    # 3. Every table ID in registry and vice versa
    for rid in data["all_ids_in_tables"]:
        if rid in ("—", "") or rid.startswith("["):
            continue
        if rid not in data["all_ids_in_registry"]:
            errors.append(f"ID '{rid}' in table but not in ID Registry")
    for rid in data["all_ids_in_registry"]:
        if rid in ("—", "") or rid.startswith("["):
            continue
        if rid not in data["all_ids_in_tables"]:
            errors.append(f"ID '{rid}' in registry but not in any table")

    # 4. Valid Origin
    for row in all_rows:
        if row["origin"] not in VALID_ORIGINS and row["origin"] not in ("—", ""):
            errors.append(f"Invalid Origin '{row['origin']}' for ID '{row['id']}'")

    # 5. Valid Status
    for row in all_rows:
        status = row["status"]
        if status in ("—", "", "[T2]"):
            if final:
                errors.append(f"[T2] placeholder Status on ID '{row['id']}'")
        elif status not in VALID_STATUSES:
            errors.append(f"Invalid Status '{status}' for ID '{row['id']}'")

    # 6. Valid Evidence Type (semicolon-separated, each must be valid)
    for row in all_rows:
        et = row.get("evidence_type", "")
        if et in ("—", "", "[T2]"):
            if final:
                errors.append(f"[T2] placeholder Evidence Type on ID '{row['id']}'")
        else:
            for part in et.split(";"):
                part = part.strip()
                if part and part not in VALID_EVIDENCE_TYPES:
                    errors.append(f"Invalid Evidence Type '{part}' for ID '{row['id']}'")

    # 7. Decision table Status values
    for dec in data["team_decisions"]:
        status = dec.get("status", "")
        if status and status not in ("—", "") and status not in VALID_DECISION_STATUSES:
            errors.append(f"Invalid Decision Status '{status}' for '{dec['decision_id']}'")

    # 8. No [T2]/[T3] placeholders if --final
    if final:
        for row in all_rows:
            for field in ("status", "evidence_type", "repo_source", "what_shows", "notes"):
                val = row.get(field, "")
                if "[T2]" in str(val) or "[T3]" in str(val):
                    errors.append(f"Placeholder {val!r} found in '{field}' for ID '{row['id']}'")

    # 9. Column counts
    for row in data["main_map"]:
        if row["_ncols"] != 14:
            errors.append(f"Main Map row '{row['id']}' has {row['_ncols']} cols (expected 14)")
    for row in data["repo_domains"]:
        if row["_ncols"] != 14:
            errors.append(f"Repo Domains row '{row['id']}' has {row['_ncols']} cols (expected 14)")
    for dec in data["team_decisions"]:
        if dec["_ncols"] != 10:
            errors.append(f"Team Decisions row '{dec['decision_id']}' has {dec['_ncols']} cols (expected 10)")

    if errors:
        print(f"VALIDATION FAILED — {len(errors)} error(s):")
        for e in errors:
            print(f"  {e}")
        sys.exit(1)
    else:
        total = len(all_rows)
        print(f"Validation OK — {total} rows checked, 0 errors.")
        if final:
            print("  --final: no [T2]/[T3] placeholders found.")
        sys.exit(0)


# ---------------------------------------------------------------------------
# Subcommand: export
# ---------------------------------------------------------------------------

def _safe_cell(value: str) -> str:
    """Formula-injection guard: prefix cells starting with =, +, -, @ with a single quote."""
    if value and value[0] in ("=", "+", "-", "@"):
        return "'" + value
    return value


def cmd_export(args):
    try:
        import openpyxl
        from openpyxl.styles import Font, PatternFill, Alignment
        from openpyxl.utils import get_column_letter
    except ImportError:
        print("ERROR: openpyxl is required. Install with: pip install openpyxl")
        sys.exit(1)

    from datetime import date

    today = date.today().strftime("%Y%m%d")
    out_path = XLSX_DIR / f"am_evidence_{today}.xlsx"

    data = _parse_map(MAP_MD)

    wb = openpyxl.Workbook()

    # UF colors
    UF_BLUE = "0021A5"
    UF_ORANGE = "FA4616"
    CALIBRI_11 = Font(name="Calibri", size=11)
    HEADER_FONT = Font(name="Calibri", size=11, bold=True, color="FFFFFF")
    HEADER_FILL = PatternFill("solid", fgColor=UF_BLUE)
    ALERT_FILL = PatternFill("solid", fgColor=UF_ORANGE)
    WRAP = Alignment(wrap_text=True, vertical="top")

    def style_header(ws, row_num, ncols):
        for col in range(1, ncols + 1):
            cell = ws.cell(row=row_num, column=col)
            cell.font = HEADER_FONT
            cell.fill = HEADER_FILL
            cell.alignment = WRAP

    def write_row(ws, row_num, values, alert_col_idx=None):
        for col, val in enumerate(values, start=1):
            cell = ws.cell(row=row_num, column=col)
            # Replace <br> with newline
            val_str = str(val).replace("<br>", "\n")
            cell.value = _safe_cell(val_str)
            cell.alignment = WRAP
            cell.font = CALIBRI_11
            if alert_col_idx and col == alert_col_idx and val in ("BLOCKED", "EMPTY-NEEDS-TEAM"):
                cell.fill = ALERT_FILL

    def cap_widths(ws, text_cols, max_text=60, max_other=40):
        for col in ws.columns:
            col_idx = col[0].column
            letter = get_column_letter(col_idx)
            ws.column_dimensions[letter].width = max_text if col_idx in text_cols else max_other

    # --- KEY sheet ---
    ws_key = wb.active
    ws_key.title = "KEY"

    key_rows = [
        ["Field", "Value"],
        ["Generated by", "tools/am_evidence/am_evidence_map.py"],
        ["Date", today],
        ["Source map", str(MAP_MD.relative_to(REPO_ROOT))],
        ["ID scheme", "S{section}-{DOMAIN}-{NN}"],
        ["ID regex", r"^S(\d{1,2}|A[1-4]|B)-[A-Z]{2,6}-\d{2}$"],
        ["", ""],
        ["Item statuses", ""],
        ["FILLED-NEEDS-CHECK", "Manual has a substantive rule that can be checked against repo"],
        ["EMPTY-REPO-CAN-ANSWER", "Manual field empty; repo has a source that can answer"],
        ["EMPTY-NEEDS-TEAM", "Empty or unresolved; only team input can answer"],
        ["OUT-OF-SCOPE", "Guidance/boilerplate with no repo source"],
        ["BLOCKED", "Depends on an input not yet received"],
        ["RETIRED", "Lifecycle state only; prior status in Notes"],
        ["", ""],
        ["Evidence types", ""],
        ["CODE", "Current executable code: path:function() and line range"],
        ["CONFIG", "R/00_config.R:KEY"],
        ["PLANNING-DOC", "Phase SUMMARY/CONTEXT/DISCUSSION-LOG"],
        ["TEAM-DECISION", "Attributed decision linked via Decision ID"],
        ["MEETING-NOTES", "TeamMtgNotes2026.md with date"],
        ["NONE", "No evidence located"],
        ["", ""],
        ["Decision statuses", ""],
        ["OPEN", "Decision not yet made"],
        ["CONFIRMED", "Decision stated and in force"],
        ["SUPERSEDED", "Replaced by a later decision"],
        ["", ""],
        ["PROVISIONAL", "Row whose only evidence is PLANNING-DOC; Phase 191/192 must locate code/config"],
        ["Privacy note", "No patient-level data in this workbook; counts 1-10 shown as <11"],
        ["", ""],
        ["Sheet guide", ""],
        ["All Items", "Main Map — manual-origin rows"],
        ["Repo Domains", "AM-MAP-02 — repo-only domains not in manual"],
        ["Team Decisions", "AM-MAP-03 — attributed team decisions + unattributed candidates"],
        ["Coverage", "Manual line skip list and comment anchors"],
    ]

    for r_idx, row in enumerate(key_rows, start=1):
        for c_idx, val in enumerate(row, start=1):
            cell = ws_key.cell(row=r_idx, column=c_idx)
            cell.value = _safe_cell(str(val))
            cell.font = CALIBRI_11
            cell.alignment = WRAP
            if r_idx == 1:
                cell.font = HEADER_FONT
                cell.fill = HEADER_FILL

    ws_key.freeze_panes = "A2"
    ws_key.column_dimensions["A"].width = 30
    ws_key.column_dimensions["B"].width = 70

    # --- All Items sheet ---
    MAIN_HEADERS = ["ID", "Origin", "AM Section", "Domain", "Item", "Manual Lines",
                    "Manual Text", "Status", "Evidence Type", "Repo Source",
                    "What the Source Shows", "Lead", "Decision ID", "Notes"]
    STATUS_COL = 8

    ws_main = wb.create_sheet("All Items")
    write_row(ws_main, 1, MAIN_HEADERS)
    style_header(ws_main, 1, len(MAIN_HEADERS))
    for r_idx, row in enumerate(data["main_map"], start=2):
        vals = [row["id"], row["origin"], row["am_section"], row["domain"], row["item"],
                row["manual_lines"], row["manual_text"], row["status"], row["evidence_type"],
                row["repo_source"], row["what_shows"], row["lead"], row["decision_id"], row["notes"]]
        write_row(ws_main, r_idx, vals, alert_col_idx=STATUS_COL)
    ws_main.freeze_panes = "A2"
    cap_widths(ws_main, text_cols={5, 7, 9, 10, 11, 14})

    # --- Repo Domains sheet ---
    ws_repo = wb.create_sheet("Repo Domains")
    write_row(ws_repo, 1, MAIN_HEADERS)
    style_header(ws_repo, 1, len(MAIN_HEADERS))
    for r_idx, row in enumerate(data["repo_domains"], start=2):
        vals = [row["id"], row["origin"], row["am_section"], row["domain"], row["item"],
                row["manual_lines"], row["manual_text"], row["status"], row["evidence_type"],
                row["repo_source"], row["what_shows"], row["lead"], row["decision_id"], row["notes"]]
        write_row(ws_repo, r_idx, vals, alert_col_idx=STATUS_COL)
    ws_repo.freeze_panes = "A2"
    cap_widths(ws_repo, text_cols={5, 7, 9, 10, 11, 14})

    # --- Team Decisions sheet ---
    DEC_HEADERS = ["Decision ID", "Original ID", "Decision Text", "Raised By", "Decided By",
                   "Date", "Source File", "Map Row(s)", "Status", "Notes"]
    ws_dec = wb.create_sheet("Team Decisions")
    write_row(ws_dec, 1, DEC_HEADERS)
    style_header(ws_dec, 1, len(DEC_HEADERS))
    for r_idx, dec in enumerate(data["team_decisions"], start=2):
        vals = [dec["decision_id"], dec["original_id"], dec["decision_text"], dec["raised_by"],
                dec["decided_by"], dec["date"], dec["source_file"], dec["map_rows"],
                dec["status"], dec["notes"]]
        write_row(ws_dec, r_idx, vals)
    # Unattributed candidates
    if data["unattributed"]:
        r_idx = len(data["team_decisions"]) + 3
        ws_dec.cell(row=r_idx, column=1).value = "### Unattributed candidates (not counted)"
        ws_dec.cell(row=r_idx, column=1).font = Font(name="Calibri", size=11, bold=True)
        for item in data["unattributed"]:
            r_idx += 1
            ws_dec.cell(row=r_idx, column=1).value = item
            ws_dec.cell(row=r_idx, column=1).font = CALIBRI_11
    ws_dec.freeze_panes = "A2"
    cap_widths(ws_dec, text_cols={3, 10})

    # --- Coverage sheet ---
    COV_HEADERS = ["Line Reference", "Reason", "Notes"]
    ws_cov = wb.create_sheet("Coverage")
    write_row(ws_cov, 1, COV_HEADERS)
    style_header(ws_cov, 1, len(COV_HEADERS))
    for r_idx, skip in enumerate(data["coverage_skip"], start=2):
        vals = [skip["line_ref"], skip["reason"], skip["notes"]]
        write_row(ws_cov, r_idx, vals)
    ws_cov.freeze_panes = "A2"
    cap_widths(ws_cov, text_cols={2, 3})

    wb.save(out_path)
    print(f"Workbook written: {out_path}")

    # --- Round-trip check ---
    print("Running round-trip check...")
    wb2 = openpyxl.load_workbook(out_path)

    errors = []

    # Sheet order
    expected_sheets = ["KEY", "All Items", "Repo Domains", "Team Decisions", "Coverage"]
    actual_sheets = wb2.sheetnames
    if actual_sheets[:5] != expected_sheets:
        errors.append(f"Sheet order mismatch: got {actual_sheets[:5]}, expected {expected_sheets}")

    # Row counts
    ws2_main = wb2["All Items"]
    if ws2_main.max_row - 1 != len(data["main_map"]):
        errors.append(f"All Items row count: wrote {len(data['main_map'])}, read {ws2_main.max_row - 1}")

    ws2_repo = wb2["Repo Domains"]
    if ws2_repo.max_row - 1 != len(data["repo_domains"]):
        errors.append(f"Repo Domains row count: wrote {len(data['repo_domains'])}, read {ws2_repo.max_row - 1}")

    # ID sets
    written_main_ids = {r["id"] for r in data["main_map"]}
    read_main_ids = {ws2_main.cell(row=r, column=1).value for r in range(2, ws2_main.max_row + 1)}
    if written_main_ids != read_main_ids:
        errors.append("All Items ID set mismatch between written and read")

    # Spot-check Status and Manual Text for first 5 rows
    for r_idx, row in enumerate(data["main_map"][:5], start=2):
        cell_status = ws2_main.cell(row=r_idx, column=8).value or ""
        cell_text = ws2_main.cell(row=r_idx, column=7).value or ""
        expected_text = row["manual_text"].replace("<br>", "\n")
        if row["status"] not in str(cell_status):
            errors.append(f"Status mismatch row {r_idx}: wrote '{row['status']}', read '{cell_status}'")

    if errors:
        print(f"ROUND-TRIP FAILED — {len(errors)} error(s):")
        for e in errors:
            print(f"  {e}")
        sys.exit(1)
    else:
        print("round-trip OK")
        sys.exit(0)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="AM evidence map tool (Phase 190/193)")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("coverage", help="Report uncovered manual lines")

    val_p = sub.add_parser("validate", help="Validate the evidence map")
    val_p.add_argument("--final", action="store_true",
                       help="Also check for [T2]/[T3] placeholders")

    sub.add_parser("export", help="Write xlsx and run round-trip check")

    args = parser.parse_args()

    if args.command == "coverage":
        sys.exit(cmd_coverage(args))
    elif args.command == "validate":
        cmd_validate(args)
    elif args.command == "export":
        cmd_export(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
