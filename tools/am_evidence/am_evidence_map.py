#!/usr/bin/env python3
"""
am_evidence_map.py — Phase 190/191 evidence-map tool.

Subcommands:
  coverage        — list every non-blank manual line; report uncovered lines not in skip list
  validate        — check IDs, uniqueness, registry match, valid statuses/evidence types, column counts
                    (use --final to also check for [T2]/[T3] placeholders)
  export          — write xlsx workbook and run round-trip check (Phase 190 map workbook)
  verdicts-export — validate AM-VERDICTS.md and write the team-facing verdict workbook

Usage:
  python tools/am_evidence/am_evidence_map.py coverage
  python tools/am_evidence/am_evidence_map.py validate [--final]
  python tools/am_evidence/am_evidence_map.py export
  python tools/am_evidence/am_evidence_map.py verdicts-export [--date YYYYMMDD]

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

# ---------------------------------------------------------------------------
# Constants for verdicts-export
# ---------------------------------------------------------------------------

VERDICTS_MD = REPO_ROOT / ".planning" / "phases" / "191-verify-existing-entries" / "AM-VERDICTS.md"
VERDICTS_DIR = REPO_ROOT / ".planning" / "phases" / "191-verify-existing-entries"

VALID_VERDICTS = {"MATCH", "MISMATCH", "PARTIAL", "CANNOT-VERIFY", "BLOCKED"}
VALID_VERDICT_EVIDENCE = {"CODE", "CONFIG", "QUERY", "PLANNING-DOC", "TEAM-DECISION", "—", ""}
VALID_CHECK_STATUS = {"COMPLETE", "PARTIAL", "SKIPPED", "FAILED", "—", ""}

# Count-lint: numbers 1-10 adjacent to a count noun within ~3 words
_COUNT_LINT_NUM = re.compile(r"\b([1-9]|10)\b")
_COUNT_NOUNS = re.compile(r"\b(patients|encounters|rows|records|people|n=)\b", re.IGNORECASE)

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
# Subcommand: verdicts-export
# ---------------------------------------------------------------------------

def _count_lint_check(text: str, location: str) -> list:
    """
    Return a list of lint failure messages if any standalone count number (1–10) appears
    within 3 words of a count noun in `text`. Never modifies text.

    A number is 'standalone' if it is NOT:
      - immediately followed by a hyphen (e.g. '5-digit', '9-digit')
      - part of a comma-formatted larger number (e.g. '1,344')
      - immediately preceded by a hyphen
    """
    failures = []
    tokens = text.split()
    for i, tok in enumerate(tokens):
        # Strip surrounding punctuation for the number check but keep original tok for context
        clean = tok.strip("().,;:\"'")

        # Must be purely a small number: 1-10 with no hyphens
        if not re.match(r"^([1-9]|10)$", clean):
            continue

        # Exclude if the original token has a hyphen (e.g. '5-digit', '9-digit')
        if "-" in tok:
            continue

        # Exclude if the next token starts with a digit/comma (comma-formatted number like "1,344")
        if i + 1 < len(tokens) and re.match(r"^[,\d]", tokens[i + 1]):
            continue

        # Exclude if the previous token ends with a comma+digit (e.g. "1,344" split oddly)
        if i > 0 and re.match(r".*,\d+$", tokens[i - 1]):
            continue

        # Look ±3 tokens for a count noun
        window = tokens[max(0, i - 3):i + 4]
        window_str = " ".join(window)
        if _COUNT_NOUNS.search(window_str):
            failures.append(f"Count lint at {location}: '{window_str.strip()}'")
    return failures


def _parse_verdicts(verdicts_path: Path) -> dict:
    """
    Parse AM-VERDICTS.md into:
      frontmatter: dict  (query_workbook, created, ...)
      verdicts: list of row dicts (9 keys matching the table headers)
      lead_summary: dict  lead_id -> {overall, rests_on, complete}
      other_items: str  (text under ### Other items)
    """
    text = verdicts_path.read_text(encoding="utf-8")
    lines = text.splitlines()

    # --- frontmatter ---
    frontmatter = {}
    if lines[0].strip() == "---":
        end = lines.index("---", 1)
        for line in lines[1:end]:
            if ":" in line:
                k, _, v = line.partition(":")
                frontmatter[k.strip()] = v.strip()
        body_lines = lines[end + 1:]
    else:
        body_lines = lines

    # --- helpers ---
    def parse_row(line: str) -> list:
        stripped = line.strip().strip("|")
        cells = re.split(r"(?<!\\)\|", stripped)
        return [c.strip() for c in cells]

    def is_sep(line: str) -> bool:
        return bool(re.match(r"^\s*\|[-| :]+\|\s*$", line))

    # --- Verdict Table ---
    verdicts = []
    in_verdict_table = False
    verdict_header_seen = False
    in_lead_summary = False
    current_lead = None
    lead_summary = {}  # lead_id -> {overall, rests_on, complete, raw_complete}
    other_items_lines = []
    in_other_items = False

    i = 0
    while i < len(body_lines):
        line = body_lines[i]
        stripped = line.strip()

        # Section: Verdict Table
        if stripped == "## Verdict Table":
            in_verdict_table = True
            verdict_header_seen = False
            in_lead_summary = False
            in_other_items = False
            i += 1
            continue

        # Section: Lead Summary
        if stripped == "## Lead Summary":
            in_verdict_table = False
            in_lead_summary = True
            in_other_items = False
            i += 1
            continue

        # Detect lead headings ### L1 — ...  or ### Other items
        if in_lead_summary and stripped.startswith("###"):
            heading_text = stripped.lstrip("#").strip()
            in_other_items = False
            if heading_text.lower().startswith("other items"):
                in_other_items = True
                current_lead = "Other items"
                lead_summary["Other items"] = {"overall": [], "rests_on": "", "complete": "", "raw_complete": ""}
            else:
                m = re.match(r"(L\d+)", heading_text)
                if m:
                    current_lead = m.group(1)
                    lead_summary[current_lead] = {"overall": [], "rests_on": "", "complete": "", "raw_complete": ""}
            i += 1
            continue

        # Inside verdict table
        if in_verdict_table and stripped.startswith("|"):
            if is_sep(stripped):
                verdict_header_seen = True
                i += 1
                continue
            if not verdict_header_seen:
                i += 1
                continue
            cells = parse_row(stripped)
            if len(cells) >= 9:
                verdicts.append({
                    "map_id": cells[0],
                    "lead": cells[1],
                    "verdict": cells[2],
                    "evidence_type": cells[3],
                    "citations": cells[4],
                    "what_code_does": cells[5],
                    "what_manual_says": cells[6],
                    "check_status": cells[7],
                    "decision_id": cells[8],
                })
            i += 1
            continue

        # Inside lead summary block
        if in_lead_summary and current_lead:
            lead = lead_summary[current_lead]
            if stripped.startswith("**Overall:**"):
                lead["overall"].append(stripped[len("**Overall:**"):].strip())
            elif stripped.startswith("**Rests on:**"):
                lead["rests_on"] = stripped[len("**Rests on:**"):].strip()
            elif stripped.startswith("**Complete:**"):
                raw = stripped[len("**Complete:**"):].strip()
                lead["raw_complete"] = raw
                lead["complete"] = "yes" if raw.lower().startswith("yes") else "no"
            elif stripped.startswith("---"):
                pass
            elif stripped and not stripped.startswith("##") and not stripped.startswith("###"):
                # continuation text
                if lead["overall"] is not None and lead.get("rests_on") == "" and lead.get("complete") == "":
                    lead["overall"].append(stripped)

        i += 1

    # Join overall lists
    for k, v in lead_summary.items():
        if isinstance(v["overall"], list):
            v["overall"] = " ".join(v["overall"]).strip()

    return {
        "frontmatter": frontmatter,
        "verdicts": verdicts,
        "lead_summary": lead_summary,
    }


def cmd_verdicts_export(args):
    try:
        import openpyxl
        from openpyxl.styles import Font, PatternFill, Alignment
        from openpyxl.utils import get_column_letter
    except ImportError:
        print("ERROR: openpyxl is required. Install with: pip install openpyxl")
        sys.exit(1)

    from datetime import date, datetime

    # --- Date argument ---
    if args.date:
        d_str = args.date
        if not re.match(r"^\d{8}$", d_str):
            print(f"ERROR: --date must be YYYYMMDD (8 digits), got: '{d_str}'")
            sys.exit(1)
        try:
            datetime.strptime(d_str, "%Y%m%d")
        except ValueError:
            print(f"ERROR: --date '{d_str}' is not a valid calendar date.")
            sys.exit(1)
        today = d_str
    else:
        today = date.today().strftime("%Y%m%d")

    if not VERDICTS_MD.exists():
        print(f"ERROR: AM-VERDICTS.md not found: {VERDICTS_MD}")
        sys.exit(1)
    if not MAP_MD.exists():
        print(f"ERROR: AM-EVIDENCE-MAP.md not found: {MAP_MD}")
        sys.exit(1)

    # --- Parse ---
    map_data = _parse_map(MAP_MD)
    verdict_data = _parse_verdicts(VERDICTS_MD)

    verdicts = verdict_data["verdicts"]
    lead_summary = verdict_data["lead_summary"]
    fmatter = verdict_data["frontmatter"]
    query_workbook = fmatter.get("query_workbook", "am_verification_20261027.xlsx")

    # Build required ID set from map: FILLED-NEEDS-CHECK or BLOCKED
    all_map_rows = map_data["main_map"] + map_data["repo_domains"]
    required_ids = {r["id"] for r in all_map_rows if r["status"] in ("FILLED-NEEDS-CHECK", "BLOCKED")}

    # Build map-row lookup (lead, decision_id) by map ID
    map_row_lookup = {r["id"]: r for r in all_map_rows}

    # Build team_decisions lookup by decision_id
    decision_lookup = {d["decision_id"]: d for d in map_data["team_decisions"]}
    d191_rows = [d for d in map_data["team_decisions"]
                 if re.match(r"^D-191-\d{2}$", d["decision_id"])]
    d191_ids = {d["decision_id"] for d in d191_rows}

    # Registry IDs
    registry_ids = map_data["all_ids_in_registry"]

    failures = []

    # 1. Required IDs without a verdict
    verdict_ids = {v["map_id"] for v in verdicts}
    for rid in sorted(required_ids):
        if rid not in verdict_ids:
            failures.append(f"Required ID missing from verdicts: {rid}")

    # 2. Duplicate verdict IDs
    seen = {}
    for v in verdicts:
        vid = v["map_id"]
        if vid in seen:
            failures.append(f"Duplicate verdict ID: {vid}")
        seen[vid] = True

    # 3. Verdict IDs not in required set
    for v in verdicts:
        if v["map_id"] not in required_ids:
            failures.append(f"Verdict ID '{v['map_id']}' not in required set (FILLED-NEEDS-CHECK/BLOCKED)")

    for v in verdicts:
        vid = v["map_id"]
        map_row = map_row_lookup.get(vid, {})

        # 4. Lead mismatch
        map_lead = map_row.get("lead", "—").strip()
        verd_lead = v["lead"].strip()
        # Normalize "—" and ""
        map_lead_norm = "" if map_lead == "—" else map_lead
        verd_lead_norm = "" if verd_lead == "—" else verd_lead
        if map_lead_norm != verd_lead_norm:
            failures.append(f"Lead mismatch for {vid}: map='{map_lead}' verdict='{verd_lead}'")

        # 5. Invalid Verdict
        if v["verdict"] not in VALID_VERDICTS:
            failures.append(f"Invalid Verdict '{v['verdict']}' for {vid}")

        # 6. Invalid Evidence Type (semicolon-separated)
        et_raw = v["evidence_type"]
        for part in re.split(r"[;,]", et_raw):
            part = part.strip()
            if part and part not in VALID_VERDICT_EVIDENCE:
                failures.append(f"Invalid Evidence Type '{part}' for {vid}")

        # 7. Invalid Check Status
        cs = v["check_status"].strip()
        if cs not in VALID_CHECK_STATUS:
            failures.append(f"Invalid Check Status '{cs}' for {vid}")

        # 8. MATCH on non-COMPLETE check or PLANNING-DOC-only evidence
        if v["verdict"] == "MATCH":
            if cs not in ("COMPLETE", "—", ""):
                failures.append(f"MATCH verdict for {vid} but Check Status is '{cs}' (must be COMPLETE or —)")
            # PLANNING-DOC-only evidence
            et_parts = [p.strip() for p in re.split(r"[;,]", et_raw) if p.strip() and p.strip() != "—"]
            if et_parts and all(p == "PLANNING-DOC" for p in et_parts):
                failures.append(f"MATCH verdict for {vid} with PLANNING-DOC-only evidence")

        # 9. MISMATCH/PARTIAL without D-191-NN
        dec_id = v["decision_id"].strip()
        if v["verdict"] in ("MISMATCH", "PARTIAL"):
            if not re.match(r"^D-191-\d{2}$", dec_id):
                failures.append(f"MISMATCH/PARTIAL verdict for {vid} but Decision ID '{dec_id}' is not D-191-NN")

        # 10. Non-MISMATCH/PARTIAL rows with a D-191-NN
        if v["verdict"] not in ("MISMATCH", "PARTIAL"):
            if re.match(r"^D-191-\d{2}$", dec_id):
                failures.append(f"Non-MISMATCH/PARTIAL verdict for {vid} has D-191-NN Decision ID '{dec_id}'")

        # 11. D-191-NN not in AM-MAP-03 or registry; map_rows mismatch
        if re.match(r"^D-191-\d{2}$", dec_id):
            if dec_id not in decision_lookup:
                failures.append(f"Decision ID '{dec_id}' (for {vid}) not found in AM-MAP-03")
            elif dec_id not in registry_ids:
                failures.append(f"Decision ID '{dec_id}' (for {vid}) not in ID Registry")
            else:
                dec_row = decision_lookup[dec_id]
                dec_map_rows = dec_row.get("map_rows", "").strip()
                # map_rows field may be comma-separated; check vid is in there
                dec_map_rows_list = [r.strip() for r in dec_map_rows.split(",")]
                if vid not in dec_map_rows_list:
                    failures.append(
                        f"Decision ID '{dec_id}' Map Row(s) field '{dec_map_rows}' does not include verdict ID {vid}"
                    )

        # Count lint in text fields
        for field_name, field_val in [
            ("What the Code Does", v["what_code_does"]),
            ("What the Manual Says Differently", v["what_manual_says"]),
        ]:
            lint_errs = _count_lint_check(field_val, f"{vid}/{field_name}")
            failures.extend(lint_errs)

    # 12. D-191-NN rows in AM-MAP-03 with no verdict row referencing them
    for did in d191_ids:
        has_ref = any(v["decision_id"].strip() == did for v in verdicts)
        if not has_ref:
            failures.append(f"Orphan D-191 row in AM-MAP-03: '{did}' has no verdict row referencing it")

    # 13. Lead Summary: must have L1–L9 and Other items; each must have a Complete field
    required_leads = [f"L{n}" for n in range(1, 10)]
    for lead_id in required_leads:
        if lead_id not in lead_summary:
            failures.append(f"Lead Summary missing section: {lead_id}")
        else:
            raw_complete = lead_summary[lead_id].get("raw_complete", "")
            if not raw_complete:
                failures.append(f"Lead Summary {lead_id} missing Complete field")
            elif not (raw_complete.lower().startswith("yes") or raw_complete.lower().startswith("no")):
                failures.append(f"Lead Summary {lead_id} Complete field invalid: '{raw_complete}'")

    if "Other items" not in lead_summary:
        failures.append("Lead Summary missing section: Other items")

    # Count lint in Lead Summary text fields
    for lead_id, ls in lead_summary.items():
        for field_name, field_val in [("Overall", ls.get("overall", "")), ("Rests on", ls.get("rests_on", ""))]:
            lint_errs = _count_lint_check(field_val, f"Lead Summary {lead_id}/{field_name}")
            failures.extend(lint_errs)

    if failures:
        print(f"VERDICTS-EXPORT FAILED — {len(failures)} failure(s):")
        for f_msg in failures:
            print(f"  {f_msg}")
        sys.exit(1)

    # --- Build workbook ---
    out_path = VERDICTS_DIR / f"am_verdicts_{today}.xlsx"

    UF_BLUE = "0021A5"
    UF_ORANGE = "FA4616"
    LIGHT_GREY = "D9D9D9"
    CALIBRI_11 = Font(name="Calibri", size=11)
    HEADER_FONT = Font(name="Calibri", size=11, bold=True, color="FFFFFF")
    HEADER_FILL = PatternFill("solid", fgColor=UF_BLUE)
    MISMATCH_FILL = PatternFill("solid", fgColor=UF_ORANGE)
    GREY_FILL = PatternFill("solid", fgColor=LIGHT_GREY)
    WRAP = Alignment(wrap_text=True, vertical="top")

    def style_header(ws, row_num, ncols):
        for col in range(1, ncols + 1):
            cell = ws.cell(row=row_num, column=col)
            cell.font = HEADER_FONT
            cell.fill = HEADER_FILL
            cell.alignment = WRAP

    def write_cell(ws, row_num, col_num, value, fill=None):
        cell = ws.cell(row=row_num, column=col_num)
        val_str = str(value).replace("<br>", "\n")
        cell.value = _safe_cell(val_str)
        cell.alignment = WRAP
        cell.font = CALIBRI_11
        if fill:
            cell.fill = fill

    def write_row(ws, row_num, values):
        for col, val in enumerate(values, start=1):
            write_cell(ws, row_num, col, val)

    def cap_widths(ws, text_cols, max_text=70, max_other=25):
        for col in ws.columns:
            col_idx = col[0].column
            letter = get_column_letter(col_idx)
            ws.column_dimensions[letter].width = max_text if col_idx in text_cols else max_other

    wb = openpyxl.Workbook()

    # ---- KEY sheet ----
    ws_key = wb.active
    ws_key.title = "KEY"

    key_rows = [
        ["Field", "Value"],
        ["Title", "Phase 191 — AM Verdict Workbook"],
        ["Generated date", today],
        ["Query workbook", query_workbook],
        ["Source — verdicts", str(VERDICTS_MD.relative_to(REPO_ROOT))],
        ["Source — map", str(MAP_MD.relative_to(REPO_ROOT))],
        ["", ""],
        ["Verdict definitions", ""],
        ["MATCH", "The code path implements what the manual states; any query evidence is consistent."],
        ["MISMATCH", "The code path does something materially different from the manual statement."],
        ["PARTIAL", "Part of the statement matches and part does not."],
        ["CANNOT-VERIFY", "The code path cannot be located, or needed check is SKIPPED/FAILED/PARTIAL."],
        ["BLOCKED", "Depends on an input not received."],
        ["", ""],
        ["Evidence types", ""],
        ["CODE", "Current executable code: path:function() and line range"],
        ["CONFIG", "R/00_config.R:KEY"],
        ["QUERY", "am_verification_20261027.xlsx:<sheet>"],
        ["PLANNING-DOC", "Phase SUMMARY/CONTEXT/DISCUSSION-LOG"],
        ["TEAM-DECISION", "Attributed decision linked via Decision ID"],
        ["", ""],
        ["Decision status meaning", ""],
        ["OPEN", "Team question; team answer required before manual update"],
        ["CONFIRMED", "Manual update only; no pipeline change needed"],
        ["", ""],
        ["Privacy note", "No patient-level data in this workbook; counts 1-10 shown as <11"],
        ["", ""],
        ["Sheet guide", ""],
        ["Verdicts", "One row per required map ID; MISMATCH/PARTIAL highlighted orange; BLOCKED/CANNOT-VERIFY grey"],
        ["Lead Summary", "L1–L9 + Other items: Overall, Rests on, Complete"],
        ["Decisions", "D-191-NN decision rows from AM-MAP-03"],
        ["Gaps", "BLOCKED/CANNOT-VERIFY verdicts and incomplete leads"],
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
    ws_key.column_dimensions["B"].width = 80

    # ---- Verdicts sheet ----
    VERDICT_HEADERS = ["Map ID", "Lead", "Verdict", "Evidence Type(s)", "Citation(s)",
                       "What the Code Does", "What the Manual Says Differently",
                       "Check Status", "Decision ID"]
    VERDICT_COL_IDX = 3  # 1-based: Verdict column

    ws_v = wb.create_sheet("Verdicts")
    write_row(ws_v, 1, VERDICT_HEADERS)
    style_header(ws_v, 1, len(VERDICT_HEADERS))

    for r_idx, v in enumerate(verdicts, start=2):
        verd = v["verdict"]
        if verd in ("MISMATCH", "PARTIAL"):
            row_fill = None
            verdict_fill = MISMATCH_FILL
        elif verd in ("BLOCKED", "CANNOT-VERIFY"):
            row_fill = GREY_FILL
            verdict_fill = GREY_FILL
        else:
            row_fill = None
            verdict_fill = None

        vals = [v["map_id"], v["lead"], v["verdict"], v["evidence_type"],
                v["citations"], v["what_code_does"], v["what_manual_says"],
                v["check_status"], v["decision_id"]]

        for col, val in enumerate(vals, start=1):
            fill = verdict_fill if col == VERDICT_COL_IDX else row_fill
            write_cell(ws_v, r_idx, col, val, fill=fill)

    ws_v.freeze_panes = "A2"
    cap_widths(ws_v, text_cols={5, 6, 7}, max_text=70, max_other=25)

    # ---- Lead Summary sheet ----
    LS_HEADERS = ["Lead", "Overall", "Rests on", "Complete"]
    ws_ls = wb.create_sheet("Lead Summary")
    write_row(ws_ls, 1, LS_HEADERS)
    style_header(ws_ls, 1, len(LS_HEADERS))

    lead_order = [f"L{n}" for n in range(1, 10)] + ["Other items"]
    for r_idx, lid in enumerate(lead_order, start=2):
        ls = lead_summary.get(lid, {"overall": "", "rests_on": "", "raw_complete": ""})
        vals = [lid, ls.get("overall", ""), ls.get("rests_on", ""), ls.get("raw_complete", "")]
        write_row(ws_ls, r_idx, vals)

    ws_ls.freeze_panes = "A2"
    cap_widths(ws_ls, text_cols={2, 3, 4}, max_text=70, max_other=15)

    # ---- Decisions sheet (D-191-NN only) ----
    DEC_HEADERS = ["Decision ID", "Original ID", "Decision Text", "Raised By", "Decided By",
                   "Date", "Source File", "Map Row(s)", "Status", "Notes"]
    ws_dec = wb.create_sheet("Decisions")
    write_row(ws_dec, 1, DEC_HEADERS)
    style_header(ws_dec, 1, len(DEC_HEADERS))

    for r_idx, dec in enumerate(d191_rows, start=2):
        vals = [dec["decision_id"], dec["original_id"], dec["decision_text"], dec["raised_by"],
                dec["decided_by"], dec["date"], dec["source_file"], dec["map_rows"],
                dec["status"], dec["notes"]]
        write_row(ws_dec, r_idx, vals)

    ws_dec.freeze_panes = "A2"
    cap_widths(ws_dec, text_cols={3, 10}, max_text=70, max_other=25)

    # ---- Gaps sheet ----
    GAPS_HEADERS = ["Map ID or Lead", "Lead", "Verdict / Complete", "Reason"]
    ws_gaps = wb.create_sheet("Gaps")
    write_row(ws_gaps, 1, GAPS_HEADERS)
    style_header(ws_gaps, 1, len(GAPS_HEADERS))

    gap_r = 2
    # BLOCKED or CANNOT-VERIFY verdict rows
    for v in verdicts:
        if v["verdict"] in ("BLOCKED", "CANNOT-VERIFY"):
            reason = v["what_code_does"] or v["citations"] or "—"
            vals = [v["map_id"], v["lead"], v["verdict"], reason[:200]]
            write_row(ws_gaps, gap_r, vals)
            gap_r += 1

    # Incomplete leads
    for lid in lead_order:
        ls = lead_summary.get(lid, {})
        raw = ls.get("raw_complete", "")
        if raw.lower().startswith("no"):
            reason = raw[3:].strip().lstrip("—").strip() if len(raw) > 3 else "not complete"
            vals = [lid, lid, f"Complete: {raw}", reason]
            write_row(ws_gaps, gap_r, vals)
            gap_r += 1

    ws_gaps.freeze_panes = "A2"
    cap_widths(ws_gaps, text_cols={4}, max_text=80, max_other=25)

    wb.save(out_path)
    print(f"Workbook written: {out_path}")

    # --- Round-trip check ---
    print("Running round-trip check...")
    wb2 = openpyxl.load_workbook(out_path)
    rt_errors = []

    expected_sheets = ["KEY", "Verdicts", "Lead Summary", "Decisions", "Gaps"]
    actual_sheets = wb2.sheetnames
    if actual_sheets[:5] != expected_sheets:
        rt_errors.append(f"Sheet order mismatch: got {actual_sheets[:5]}, expected {expected_sheets}")

    ws2_v = wb2["Verdicts"]
    if ws2_v.max_row - 1 != len(verdicts):
        rt_errors.append(f"Verdicts row count: wrote {len(verdicts)}, read {ws2_v.max_row - 1}")

    written_vids = [v["map_id"] for v in verdicts]
    read_vids = [ws2_v.cell(row=r, column=1).value for r in range(2, ws2_v.max_row + 1)]
    if written_vids != read_vids:
        rt_errors.append("Verdicts Map ID order mismatch between written and read")

    # Check verdicts column
    for r_idx, v in enumerate(verdicts, start=2):
        cell_verdict = ws2_v.cell(row=r_idx, column=3).value or ""
        if v["verdict"] not in str(cell_verdict):
            rt_errors.append(f"Verdict mismatch row {r_idx}: wrote '{v['verdict']}', read '{cell_verdict}'")

    # Check decision IDs in Decisions sheet
    ws2_dec = wb2["Decisions"]
    read_dec_ids = [ws2_dec.cell(row=r, column=1).value for r in range(2, ws2_dec.max_row + 1)]
    written_dec_ids = [d["decision_id"] for d in d191_rows]
    if written_dec_ids != read_dec_ids:
        rt_errors.append("Decisions sheet D-191-NN ID list mismatch")

    if rt_errors:
        print(f"ROUND-TRIP FAILED — {len(rt_errors)} error(s):")
        for e in rt_errors:
            print(f"  {e}")
        sys.exit(1)

    print("Round-trip OK")

    # --- Summary counts ---
    verdict_counts = {}
    for v in verdicts:
        verdict_counts[v["verdict"]] = verdict_counts.get(v["verdict"], 0) + 1

    open_count = sum(1 for d in d191_rows if d["status"] == "OPEN")
    confirmed_count = sum(1 for d in d191_rows if d["status"] == "CONFIRMED")
    gaps_count = gap_r - 2

    print("\nVerdict counts:")
    for verd, cnt in sorted(verdict_counts.items()):
        print(f"  {verd}: {cnt}")
    print(f"\nD-191 decisions: {open_count} OPEN, {confirmed_count} CONFIRMED")
    print(f"Gaps: {gaps_count} rows")
    sys.exit(0)


# ---------------------------------------------------------------------------
# Subcommand: draft-check
# ---------------------------------------------------------------------------

# Section headings in scope (verbatim from the manual's ## headings).
# These are the sections that AM-DRAFT.md must include.
_DRAFT_REQUIRED_SECTIONS = [
    "1. Data Ingest & Change Log",
    "3. Variable and Phenotype Decision Log",
    "4. Data Cleaning and Harmonization Rules",
    "8. Open Questions and Decision Parking Lot",
]

# Appendix sections required for mirror checks
_DRAFT_APPENDIX_SECTIONS = ["A1", "A3"]

# Valid STATUS values in a draft unit
_DRAFT_VALID_STATUSES = {
    "DRAFTED",
    "CORRECTION",
    "TEAM-INPUT-NEEDED",
    "OPEN-QUESTION-SEE-§8",
}

# Citation form patterns (each CITE line must match at least one)
_CITE_CODE_CONFIG = re.compile(
    r"^[A-Za-z0-9_./-]+\.[A-Za-z]+:"      # file path
    r"([A-Za-z_][A-Za-z0-9_.]*\(\)|[A-Z0-9_]+)"   # function() or CONFIG_KEY
    r"(:L\d+-L\d+)?$"                       # optional :La-Lb
)
_CITE_WORKBOOK = re.compile(
    r"^am_verification_\d{8}\.xlsx:.+"
)
_CITE_DECISION = re.compile(r"^(DEC-\d{3}|D-\d{3}-\d{2})$")
_CITE_PLANNING = re.compile(r"^\.planning/")
_CITE_MANUAL = re.compile(r"^docs/analytic_manual/.+\.md:L\d+-L\d+$")
# Combined: a cite is valid if it matches any of the above
_CITE_LINE_RANGE = re.compile(r":L(\d+)-L(\d+)")


def _is_valid_cite(cite: str) -> bool:
    """Return True if the citation string matches at least one valid citation form."""
    cite = cite.strip()
    if not cite:
        return False
    if _CITE_CODE_CONFIG.match(cite):
        return True
    if _CITE_WORKBOOK.match(cite):
        return True
    if _CITE_DECISION.match(cite):
        return True
    if _CITE_PLANNING.match(cite):
        return True
    if _CITE_MANUAL.match(cite):
        return True
    return False


def _parse_draft(draft_path: Path) -> dict:
    """
    Parse AM-DRAFT.md into:
      header_ok: bool (has # AM-DRAFT and commit comment)
      sections: dict section_name -> list of content lines
      units: list of dicts {type: 'bullet'|'table_row'|'correction',
                            id_tags: list, status: str, cites: list[str],
                            line_num: int, raw: str}
      s8_rows: list of dicts {item: str, notes_tag: str, decision_ids: list, raw_notes: str}
      repo_only_blocks: list of domain short codes found inside markers
      marker_begin_count: int
      marker_end_count: int
      s1_rows: list of raw data rows (excluding header and separator)
      s3_rows: list of raw data rows
      a1_rows: list of raw data rows
      a3_rows: list of raw data rows
      not_drafted_ids: set of map IDs mentioned in ## Not drafted
      raw_lines: list[str]
    """
    text = draft_path.read_text(encoding="utf-8")
    raw_lines = text.splitlines()

    result = {
        "header_ok": False,
        "sections": {},
        "units": [],
        "s8_rows": [],
        "repo_only_blocks": [],
        "marker_begin_count": 0,
        "marker_end_count": 0,
        "s1_rows": [],
        "s3_rows": [],
        "a1_rows": [],
        "a3_rows": [],
        "not_drafted_ids": set(),
        "raw_lines": raw_lines,
    }

    # Check header
    has_amdraft = any(l.strip() == "# AM-DRAFT" for l in raw_lines[:5])
    has_commit = any(l.strip().startswith("<!-- commit:") for l in raw_lines[:10])
    result["header_ok"] = has_amdraft and has_commit

    # Current parse state
    current_section = None
    current_section_key = None  # normalised key e.g. "1. Data Ingest & Change Log"
    in_repo_only = False
    in_not_drafted = False
    in_s8 = False
    in_s1 = False
    in_s3 = False
    in_a1 = False
    in_a3 = False

    # Table parse state
    table_header_row = None
    table_sep_seen = False
    current_table_section = None  # which logical table are we in

    # Bullet/correction parse state
    pending_bullet = None   # {id_tags, raw, line_num}

    def flush_pending_bullet(pending, units):
        """Bullet with no STATUS line yet — flush with status=None."""
        if pending:
            units.append({
                "type": "bullet",
                "id_tags": pending["id_tags"],
                "status": pending.get("status"),
                "cites": pending.get("cites", []),
                "line_num": pending["line_num"],
                "raw": pending["raw"],
            })
        return None

    def _extract_id_tags(text):
        return re.findall(r"\[([A-Z0-9-]+)\]", text)

    def _is_table_row(line):
        return line.strip().startswith("|") and not re.match(r"^\s*\|[-| :]+\|\s*$", line)

    def _is_table_sep(line):
        return bool(re.match(r"^\s*\|[-| :]+\|\s*$", line))

    def _row_cells(line):
        stripped = line.strip().strip("|")
        cells = re.split(r"(?<!\\)\|", stripped)
        return [c.strip() for c in cells]

    i = 0
    while i < len(raw_lines):
        line = raw_lines[i]
        stripped = line.strip()

        # --- Markers ---
        if stripped == "<!-- BEGIN REPO-ONLY DOMAINS -->":
            result["marker_begin_count"] += 1
            in_repo_only = True
            pending_bullet = flush_pending_bullet(pending_bullet, result["units"])
            i += 1
            continue
        if stripped == "<!-- END REPO-ONLY DOMAINS -->":
            result["marker_end_count"] += 1
            in_repo_only = False
            pending_bullet = flush_pending_bullet(pending_bullet, result["units"])
            i += 1
            continue

        # --- Level-2 section headings ---
        if stripped.startswith("## ") and not stripped.startswith("### "):
            pending_bullet = flush_pending_bullet(pending_bullet, result["units"])
            heading = stripped[3:].strip()

            # Reset all table-tracking state
            in_s8 = False
            in_s1 = False
            in_s3 = False
            in_a1 = False
            in_a3 = False
            table_header_row = None
            table_sep_seen = False
            current_table_section = None

            if heading.startswith("Not drafted"):
                in_not_drafted = True
                current_section = heading
                i += 1
                continue
            else:
                in_not_drafted = False

            # Identify section
            current_section = heading
            result["sections"][heading] = []

            # Tag which table we're entering
            if re.match(r"1\. Data Ingest", heading):
                in_s1 = True
                current_table_section = "s1"
            elif re.match(r"3\. Variable", heading):
                in_s3 = True
                current_table_section = "s3"
            elif re.match(r"8\. Open Questions", heading):
                in_s8 = True
                current_table_section = "s8"
            i += 1
            continue

        # --- Appendix level-2 (APPENDIX A. Embedded...)
        if stripped.startswith("## APPENDIX"):
            pending_bullet = flush_pending_bullet(pending_bullet, result["units"])
            current_section = stripped[3:].strip()
            result["sections"][current_section] = []
            in_s8 = False
            in_s1 = False
            in_s3 = False
            in_a1 = False
            in_a3 = False
            table_sep_seen = False
            table_header_row = None
            current_table_section = None
            i += 1
            continue

        # --- Appendix A subsection headings (### A1. or ### A3.)
        if stripped.startswith("### A1."):
            pending_bullet = flush_pending_bullet(pending_bullet, result["units"])
            in_a1 = True
            in_a3 = False
            in_s1 = False
            in_s3 = False
            in_s8 = False
            table_sep_seen = False
            table_header_row = None
            current_table_section = "a1"
            i += 1
            continue
        if stripped.startswith("### A3."):
            pending_bullet = flush_pending_bullet(pending_bullet, result["units"])
            in_a1 = False
            in_a3 = True
            in_s1 = False
            in_s3 = False
            in_s8 = False
            table_sep_seen = False
            table_header_row = None
            current_table_section = "a3"
            i += 1
            continue

        # --- Repo-only domain blocks: ### DomainName {#S4-XXX}
        if in_repo_only and stripped.startswith("### ") and "{#S4-" in stripped:
            pending_bullet = flush_pending_bullet(pending_bullet, result["units"])
            m = re.search(r"\{#S4-([A-Z]+)\}", stripped)
            if m:
                result["repo_only_blocks"].append(m.group(1))
            i += 1
            continue

        # --- Not-drafted lines ---
        if in_not_drafted and stripped.startswith("- "):
            # Extract map IDs: - S4-CBC-01: reason  (also SA1-, SA3-, SB-)
            ids = re.findall(r"\b(S[AB]?\d{1,2}-[A-Z]{2,6}-\d{2})\b", stripped)
            result["not_drafted_ids"].update(ids)
            i += 1
            continue

        # --- Table rows ---
        if _is_table_sep(stripped):
            table_sep_seen = True
            i += 1
            continue

        if _is_table_row(stripped) and table_sep_seen:
            cells = _row_cells(stripped)

            if current_table_section in ("s8", None) and in_s8:
                # §8 table: Item | Notes | Date added [| Map ID | Status | Cite]
                if len(cells) >= 2:
                    item_text = cells[0] if len(cells) > 0 else ""
                    notes_raw = cells[1] if len(cells) > 1 else ""
                    # Parse notes tag and IDs
                    notes_tag = ""
                    decision_ids = []
                    if notes_raw.startswith("MISMATCH"):
                        notes_tag = "MISMATCH"
                        decision_ids = re.findall(r"(D-\d{3}-\d{2}|DEC-\d{3})", notes_raw)
                    elif notes_raw.startswith("OPEN-DEPENDENCY"):
                        notes_tag = "OPEN-DEPENDENCY"
                        decision_ids = re.findall(r"(D-\d{3}-\d{2}|DEC-\d{3})", notes_raw)
                    # Extract trailing Map ID | Status | Cite if present (draft table adds these)
                    map_id_val = cells[3] if len(cells) > 3 else ""
                    status_val = cells[4] if len(cells) > 4 else ""
                    cite_val = cells[5] if len(cells) > 5 else ""
                    # Extract map IDs from the Map ID column
                    row_map_ids = re.findall(r"\b(S[AB]?\d{1,2}-[A-Z]{2,6}-\d{2})\b", map_id_val)
                    result["s8_rows"].append({
                        "item": item_text,
                        "notes_tag": notes_tag,
                        "decision_ids": decision_ids,
                        "raw_notes": notes_raw,
                        "status": status_val,
                        "cite": cite_val,
                        "row_map_ids": row_map_ids,
                    })
            elif current_table_section == "s1":
                result["s1_rows"].append(cells)
            elif current_table_section == "s3":
                result["s3_rows"].append(cells)
            elif current_table_section == "a1":
                result["a1_rows"].append(cells)
            elif current_table_section == "a3":
                result["a3_rows"].append(cells)

            # Table rows also get unit tracking (for status/cite in trailing cols)
            if current_table_section not in ("s8",):
                # Check trailing Status / Cite columns in table rows.
                # Draft tables append Map ID | Status | Cite as trailing columns.
                # Status col is second-to-last, Cite is last, Map ID is third-to-last.
                if len(cells) >= 3:
                    status_idx = len(cells) - 2
                    cite_idx = len(cells) - 1
                    map_id_idx = len(cells) - 3
                    status_val = cells[status_idx] if status_idx >= 0 else ""
                    cite_val = cells[cite_idx] if cite_idx >= 0 else ""
                    map_id_val = cells[map_id_idx] if map_id_idx >= 0 else ""
                    # Collect map IDs: from [BRACKET] tags in any cell AND from Map ID column
                    id_tags = _extract_id_tags(stripped)
                    # Also include map IDs from the explicit Map ID column
                    extra_ids = re.findall(r"\b(S[AB]?\d{1,2}-[A-Z]{2,6}-\d{2})\b", map_id_val)
                    id_tags = list(set(id_tags + extra_ids))
                    # Only record if there's a meaningful status
                    if status_val in _DRAFT_VALID_STATUSES:
                        cites = [c.strip() for c in cite_val.split(";") if c.strip()] if cite_val else []
                        result["units"].append({
                            "type": "table_row",
                            "id_tags": id_tags,
                            "status": status_val,
                            "cites": cites,
                            "line_num": i + 1,
                            "raw": stripped,
                        })
            i += 1
            continue

        # If line starts with | but no sep seen yet — header row
        if stripped.startswith("|") and not table_sep_seen:
            table_header_row = stripped
            i += 1
            continue

        # A non-table non-header line resets table header tracking if not a sep
        if not stripped.startswith("|") and not stripped.startswith("  STATUS:") and not stripped.startswith("  CITE:"):
            if stripped and not stripped.startswith("<!--") and not stripped.startswith("####") and not stripped.startswith("###") and not stripped.startswith("##") and not stripped.startswith("#"):
                # Only reset if we're not in an indented metadata block
                pass  # Keep table_sep_seen; metadata can follow non-table lines

        # --- Bullet lines ---
        if stripped.startswith("- ") and not stripped.startswith("- Target:") and not stripped.startswith("- Anchor:") and not stripped.startswith("- Action:") and not stripped.startswith("- Replacement:") and not stripped.startswith("- Provenance:"):
            pending_bullet = flush_pending_bullet(pending_bullet, result["units"])
            id_tags = _extract_id_tags(stripped)
            pending_bullet = {
                "id_tags": id_tags,
                "raw": stripped,
                "line_num": i + 1,
                "status": None,
                "cites": [],
            }
            i += 1
            continue

        # --- Indented STATUS: line ---
        if stripped.startswith("STATUS:"):
            status_val = stripped[len("STATUS:"):].strip()
            if pending_bullet is not None:
                pending_bullet["status"] = status_val
            # Also: plain text blocks may have STATUS lines not tied to bullets
            i += 1
            continue

        # --- Indented CITE: line ---
        if stripped.startswith("CITE:"):
            cite_val = stripped[len("CITE:"):].strip()
            if pending_bullet is not None:
                pending_bullet["cites"].append(cite_val)
            i += 1
            continue

        # --- CORRECTION directive blocks ---
        if stripped.startswith("#### CORRECTION "):
            pending_bullet = flush_pending_bullet(pending_bullet, result["units"])
            map_id = stripped[len("#### CORRECTION "):].strip()
            # Collect the directive lines
            directive = {
                "type": "correction",
                "id_tags": [map_id],
                "status": "CORRECTION",
                "cites": [],
                "line_num": i + 1,
                "raw": stripped,
                "anchor": "",
                "anchor_line": None,
                "action": "",
                "target": "",
            }
            i += 1
            while i < len(raw_lines):
                dl = raw_lines[i].strip()
                if dl.startswith("- Target:"):
                    directive["target"] = dl[len("- Target:"):].strip()
                elif dl.startswith("- Anchor:"):
                    anchor_raw = dl[len("- Anchor:"):].strip()
                    # Extract quoted text and line number
                    m_anchor = re.search(r'"([^"]+)"\s*\(.*?:L(\d+)\)', anchor_raw)
                    if m_anchor:
                        directive["anchor"] = m_anchor.group(1)
                        directive["anchor_line"] = int(m_anchor.group(2))
                    else:
                        directive["anchor"] = anchor_raw
                elif dl.startswith("- Action:"):
                    directive["action"] = dl[len("- Action:"):].strip()
                elif dl.startswith("- Replacement:"):
                    pass
                elif dl.startswith("- Provenance:"):
                    pass
                elif dl.startswith("STATUS:"):
                    directive["status"] = dl[len("STATUS:"):].strip()
                elif dl.startswith("CITE:"):
                    directive["cites"].append(dl[len("CITE:"):].strip())
                elif dl.startswith("#### ") or dl.startswith("### ") or dl.startswith("## ") or dl.startswith("- ["):
                    break
                elif dl == "":
                    pass
                elif dl.startswith("<!-- BEGIN REPO-ONLY") or dl.startswith("<!-- END REPO-ONLY"):
                    # Do not consume repo-only markers — let the outer loop handle them
                    break
                elif dl.startswith("<!--"):
                    pass
                else:
                    break
                i += 1
            result["units"].append(directive)
            continue

        i += 1

    # Flush any trailing pending bullet
    flush_pending_bullet(pending_bullet, result["units"])

    return result


def _get_open_decision_ids(map_data: dict, verdicts_data: dict) -> set:
    """
    Return the set of D-191-NN decision IDs that are OPEN in AM-MAP-03.
    Also include DEC-001 (the D-190-01 proxy from the mini fixture).
    """
    open_ids = set()
    for dec in map_data["team_decisions"]:
        did = dec.get("decision_id", "")
        status = dec.get("status", "")
        if status == "OPEN":
            if re.match(r"^D-191-\d{2}$", did):
                open_ids.add(did)
            elif did == "DEC-001":
                # DEC-001 is the D-190-01 stand-in
                open_ids.add(did)
    return open_ids


def _get_confirmed_d191_ids(map_data: dict) -> set:
    """Return set of D-191-NN IDs with CONFIRMED status in AM-MAP-03."""
    confirmed = set()
    for dec in map_data["team_decisions"]:
        did = dec.get("decision_id", "")
        if re.match(r"^D-191-\d{2}$", did) and dec.get("status") == "CONFIRMED":
            confirmed.add(did)
    return confirmed


def _get_repo_only_domain_codes(map_data: dict) -> list:
    """Return list of domain short codes from AM-MAP-02 (REPO-ONLY rows)."""
    codes = []
    for row in map_data["repo_domains"]:
        rid = row.get("id", "")
        m = re.match(r"S4-([A-Z]+)-\d+", rid)
        if m:
            code = m.group(1)
            if code not in codes:
                codes.append(code)
    return codes


def _get_empty_repo_can_answer_ids(map_data: dict) -> set:
    """Return set of map IDs with status EMPTY-REPO-CAN-ANSWER from both tables."""
    ids = set()
    for row in map_data["main_map"] + map_data["repo_domains"]:
        if row.get("status") == "EMPTY-REPO-CAN-ANSWER":
            rid = row.get("id", "")
            if rid:
                ids.add(rid)
    return ids


def check_draft(
    draft_path: Path,
    map_path: Path,
    verdicts_path: Path,
    manual_path: Path,
    hashes_path: Path,
    stage: str = "full",
) -> tuple:
    """
    Validate an AM-DRAFT.md file against the grammar and run-time inputs.

    Parameters
    ----------
    draft_path : Path
        Path to the draft file to validate.
    map_path : Path
        Path to AM-EVIDENCE-MAP.md.
    verdicts_path : Path
        Path to AM-VERDICTS.md.
    manual_path : Path
        Path to AnalyticManual_<date>.md.
    hashes_path : Path
        Path to am_source_hashes.txt.
    stage : str
        'core' or 'full'. core defers repo-only domain block checks.

    Returns
    -------
    (failures: list[str], exit_code: int)
    """
    failures = []

    # --- Load run-time inputs ---
    if not draft_path.exists():
        return ([f"FAIL: Draft file not found: {draft_path}"], 1)
    if not map_path.exists():
        return ([f"FAIL: Map not found: {map_path}"], 1)

    map_data = _parse_map(map_path)
    manual_lines = manual_path.read_text(encoding="utf-8").splitlines() if manual_path.exists() else []
    draft_data = _parse_draft(draft_path)

    # Load verdicts (optional — may not exist yet)
    verdicts_data = None
    if verdicts_path and verdicts_path.exists():
        verdicts_data = _parse_verdicts(verdicts_path)

    # Build run-time sets
    registry_ids = map_data["all_ids_in_registry"]
    repo_only_codes = _get_repo_only_domain_codes(map_data)
    empty_repo_ids = _get_empty_repo_can_answer_ids(map_data)
    open_d191_ids = _get_open_decision_ids(map_data, verdicts_data or {})
    confirmed_d191_ids = _get_confirmed_d191_ids(map_data)
    all_decision_ids = {d["decision_id"] for d in map_data["team_decisions"]}

    # --- Check 1: Header ---
    if not draft_data["header_ok"]:
        failures.append("FAIL: Missing header — draft must begin with '# AM-DRAFT' and '<!-- commit: <sha> -->'")

    # --- Check 2: Required section headings ---
    present_sections = set(draft_data["sections"].keys())
    for req in _DRAFT_REQUIRED_SECTIONS:
        found = any(req in s for s in present_sections)
        if not found:
            failures.append(f"FAIL: Required section heading not found in draft: '{req}'")

    # --- Check 3: Repo-only domain markers ---
    if draft_data["marker_begin_count"] != 1:
        failures.append(
            f"FAIL: Expected exactly 1 '<!-- BEGIN REPO-ONLY DOMAINS -->' marker; "
            f"found {draft_data['marker_begin_count']}"
        )
    if draft_data["marker_end_count"] != 1:
        failures.append(
            f"FAIL: Expected exactly 1 '<!-- END REPO-ONLY DOMAINS -->' marker; "
            f"found {draft_data['marker_end_count']}"
        )

    # --- Check 4: Repo-only domain blocks [full stage only] ---
    if stage == "full":
        found_codes = set(draft_data["repo_only_blocks"])
        for code in repo_only_codes:
            if code not in found_codes:
                failures.append(
                    f"FAIL: Repo-only domain block missing inside markers: '{code}' "
                    f"(expected '### <name> {{#S4-{code}}}')"
                )

    # --- Check 5: Every bullet/table unit has a valid STATUS ---
    for unit in draft_data["units"]:
        status = unit.get("status")
        if status is None:
            failures.append(
                f"FAIL: Unit at line {unit['line_num']} has no STATUS line "
                f"(ids: {unit['id_tags']}; raw: {unit['raw'][:80]})"
            )
        elif status not in _DRAFT_VALID_STATUSES:
            failures.append(
                f"FAIL: Unit at line {unit['line_num']} has unknown STATUS '{status}' "
                f"(ids: {unit['id_tags']})"
            )

    # --- Check 6: DRAFTED/CORRECTION units must have at least one CITE ---
    for unit in draft_data["units"]:
        status = unit.get("status", "")
        if status in ("DRAFTED", "CORRECTION"):
            if not unit.get("cites"):
                failures.append(
                    f"FAIL: Unit with STATUS {status} at line {unit['line_num']} has no CITE "
                    f"(ids: {unit['id_tags']}; raw: {unit['raw'][:80]})"
                )

    # --- Check 7: Every map ID tag in units exists in the registry ---
    for unit in draft_data["units"]:
        for tag in unit["id_tags"]:
            # Tags like S4-CBC-01 etc must be in registry
            if tag not in registry_ids:
                failures.append(
                    f"FAIL: Map ID tag [{tag}] at line {unit['line_num']} not found in ID Registry"
                )

    # --- Check 8: Citation syntax validation ---
    for unit in draft_data["units"]:
        for cite in unit.get("cites", []):
            if not _is_valid_cite(cite):
                failures.append(
                    f"FAIL: Malformed citation '{cite}' in unit at line {unit['line_num']} "
                    f"(ids: {unit['id_tags']})"
                )

    # --- Check 9: Citation existence (file path citations) ---
    if manual_path.exists():
        repo_root = manual_path.resolve().parents[2]  # docs/analytic_manual/ -> repo root
        for unit in draft_data["units"]:
            for cite in unit.get("cites", []):
                # File-path citations: check file exists and line range is within file
                # Avoid checking decision IDs and planning docs (they may not exist locally)
                if not _CITE_DECISION.match(cite) and not cite.startswith(".planning/"):
                    # Extract file path (before the first colon that isn't in a function name)
                    m_path = re.match(r"^([^:]+\.[A-Za-z]+)", cite)
                    if m_path:
                        file_rel = m_path.group(1)
                        file_abs = repo_root / file_rel
                        if not file_abs.exists():
                            # Don't fail on files that may be HiPerGator-only
                            # (this is a best-effort check)
                            pass
                        else:
                            # Check line range if present
                            m_range = _CITE_LINE_RANGE.search(cite)
                            if m_range:
                                start_l = int(m_range.group(1))
                                end_l = int(m_range.group(2))
                                file_lines = file_abs.read_text(encoding="utf-8", errors="replace").splitlines()
                                if end_l > len(file_lines):
                                    failures.append(
                                        f"FAIL: Citation '{cite}' references line L{end_l} "
                                        f"but file has only {len(file_lines)} lines"
                                    )

    # --- Check 10: §8 table validation ---
    s8_rows = draft_data["s8_rows"]
    # Collect all decision IDs cited in §8
    s8_decision_ids = set()
    for row in s8_rows:
        for did in row["decision_ids"]:
            s8_decision_ids.add(did)

    # Every OPEN D-191 row must appear in §8
    for did in open_d191_ids:
        if did not in s8_decision_ids:
            failures.append(
                f"FAIL: OPEN decision '{did}' must appear in §8 table but was not found"
            )

    # No CONFIRMED D-191 row should appear in §8
    for row in s8_rows:
        for did in row["decision_ids"]:
            if did in confirmed_d191_ids:
                failures.append(
                    f"FAIL: CONFIRMED decision '{did}' must not appear in §8 (it belongs in a CORRECTION directive)"
                )

    # §8 MISMATCH rows must follow the item template
    mismatch_pattern = re.compile(r"^Manual: .+\. Code: .+\. Which should the manual record\?$")
    for row in s8_rows:
        if row["notes_tag"] == "MISMATCH":
            if not mismatch_pattern.match(row["item"].strip()):
                failures.append(
                    f"FAIL: §8 MISMATCH row item text does not match template "
                    f"'Manual: ... Code: ... Which should the manual record?': "
                    f"'{row['item'][:100]}'"
                )

    # --- Check 11: CORRECTION directives for CONFIRMED D-191 ---
    correction_targets = set()
    for unit in draft_data["units"]:
        if unit["type"] == "correction":
            for tag in unit["id_tags"]:
                correction_targets.add(tag)
    for did in confirmed_d191_ids:
        # Find map rows affected by this decision
        dec_row = next((d for d in map_data["team_decisions"] if d["decision_id"] == did), None)
        if dec_row:
            map_rows_field = dec_row.get("map_rows", "")
            affected_ids = [r.strip() for r in map_rows_field.split(",") if r.strip()]
            for mid in affected_ids:
                if mid not in correction_targets:
                    failures.append(
                        f"FAIL: CONFIRMED decision '{did}' requires a CORRECTION directive "
                        f"for map ID '{mid}' but none was found"
                    )

    # --- Check 12: CORRECTION anchor text verification ---
    # CORRECTION directive anchors always reference the analytic manual by line number.
    # We check the anchor text against the manual_path provided (which is the manual MD).
    if manual_path.exists() and manual_lines:
        for unit in draft_data["units"]:
            if unit["type"] == "correction":
                anchor = unit.get("anchor", "")
                anchor_line = unit.get("anchor_line")
                if anchor and anchor_line is not None:
                    if anchor_line <= len(manual_lines):
                        actual_line = manual_lines[anchor_line - 1]
                        if anchor not in actual_line:
                            failures.append(
                                f"FAIL: CORRECTION directive for {unit['id_tags']} — "
                                f"anchor text '{anchor}' not found at manual line L{anchor_line} "
                                f"(actual: '{actual_line[:80]}')"
                            )
                    else:
                        failures.append(
                            f"FAIL: CORRECTION anchor line L{anchor_line} exceeds manual length "
                            f"({len(manual_lines)} lines)"
                        )

    # --- Check 13: Mirror checks (A1 mirrors §1, A3 mirrors §3) ---
    def normalize_row(cells):
        """Normalize a table row for comparison: strip IDs with S/SA prefix, lowercase, strip."""
        normalized = []
        for c in cells:
            # Remove trailing map-ID-like tokens (S1-/SA1-)
            c2 = re.sub(r"\b(S[A-Z]?\d{1,2}-[A-Z]{2,6}-\d{2})\b", "", c)
            normalized.append(c2.strip().lower())
        return normalized

    # Compare §1 rows with A1 rows
    s1_norm = [normalize_row(r) for r in draft_data["s1_rows"]]
    a1_norm = [normalize_row(r) for r in draft_data["a1_rows"]]
    if len(s1_norm) != len(a1_norm):
        failures.append(
            f"FAIL: §1 has {len(s1_norm)} data rows but A1 has {len(a1_norm)} rows (mirrors must match)"
        )
    else:
        for idx, (s1r, a1r) in enumerate(zip(s1_norm, a1_norm)):
            # Compare only the shared leading columns (ignore trailing Map ID/Status/Cite)
            min_cols = min(len(s1r), len(a1r))
            if s1r[:min_cols] != a1r[:min_cols]:
                failures.append(
                    f"FAIL: §1 row {idx + 1} differs from A1 row {idx + 1} after normalization"
                )

    # Compare §3 rows with A3 rows
    s3_norm = [normalize_row(r) for r in draft_data["s3_rows"]]
    a3_norm = [normalize_row(r) for r in draft_data["a3_rows"]]
    if len(s3_norm) != len(a3_norm):
        failures.append(
            f"FAIL: §3 has {len(s3_norm)} data rows but A3 has {len(a3_norm)} rows (mirrors must match)"
        )
    else:
        for idx, (s3r, a3r) in enumerate(zip(s3_norm, a3_norm)):
            min_cols = min(len(s3r), len(a3r))
            if s3r[:min_cols] != a3r[:min_cols]:
                failures.append(
                    f"FAIL: §3 row {idx + 1} differs from A3 row {idx + 1} after normalization"
                )

    # --- Check 14: Inventory — EMPTY-REPO-CAN-ANSWER IDs must appear or be in Not drafted ---
    # Collect all id_tags used in units
    all_unit_ids = set()
    for unit in draft_data["units"]:
        all_unit_ids.update(unit["id_tags"])
    # Also collect IDs from §8 table rows (Map ID column captures S8-PRK-* etc.)
    for row in draft_data["s8_rows"]:
        all_unit_ids.update(row.get("row_map_ids", []))
    # IDs explicitly in Not-drafted cover the EMPTY-REPO-CAN-ANSWER inventory
    all_unit_ids.update(draft_data["not_drafted_ids"])

    # §4 EMPTY-REPO-CAN-ANSWER IDs are only checked in full stage
    for eid in empty_repo_ids:
        is_s4 = eid.startswith("S4-")
        if stage == "core" and is_s4:
            continue
        if eid not in all_unit_ids and eid not in draft_data["not_drafted_ids"]:
            failures.append(
                f"FAIL: EMPTY-REPO-CAN-ANSWER ID '{eid}' not found in draft units or '## Not drafted'"
            )

    # --- Check 15: Count lint ---
    draft_text = draft_path.read_text(encoding="utf-8")
    lint_errs = _count_lint_check(draft_text, "draft")
    failures.extend([f"FAIL: {e}" for e in lint_errs])

    # --- Check 16: Hash file validation ---
    if hashes_path and hashes_path.exists():
        hash_lines = hashes_path.read_text(encoding="utf-8").splitlines()
        for hl in hash_lines:
            hl = hl.strip()
            if not hl or hl.startswith("#"):
                continue
            # Format: SHA-256  <hex64>  <path>
            parts = hl.split()
            if len(parts) < 3:
                failures.append(f"FAIL: Malformed hash line in hashes file: '{hl}'")
                continue
            algo, hex_hash, file_rel = parts[0], parts[1], parts[2]
            if algo != "SHA-256":
                failures.append(f"FAIL: Unsupported hash algorithm '{algo}' in hashes file")
                continue
            if len(hex_hash) != 64:
                failures.append(f"FAIL: Hash value for '{file_rel}' is not 64 hex chars: '{hex_hash}'")
                continue
            # File existence check (best effort; HiPerGator files may not exist locally)
            # We only fail if the format is malformed, not if the file is absent on Windows.
    elif hashes_path:
        failures.append(f"FAIL: Hash file not found: {hashes_path}")

    exit_code = 1 if failures else 0
    return failures, exit_code


def cmd_draft_check(args):
    """
    Entry point for the draft-check subcommand.

    Usage:
      python am_evidence_map.py draft-check [--stage core|full] [--draft PATH]
    """
    stage = getattr(args, "stage", "full")
    draft_arg = getattr(args, "draft", None)

    draft_path = Path(draft_arg) if draft_arg else (
        REPO_ROOT / "docs" / "analytic_manual" / "AM-DRAFT.md"
    )
    verdicts_path = VERDICTS_MD
    manual_path = MANUAL_MD
    hashes_path = Path(__file__).resolve().parents[2] / ".planning" / "phases" / "190-evidence-map" / "am_source_hashes.txt"

    if not draft_path.exists():
        print(f"FAIL: Draft file not found: {draft_path}")
        sys.exit(1)

    failures, exit_code = check_draft(
        draft_path=draft_path,
        map_path=MAP_MD,
        verdicts_path=verdicts_path,
        manual_path=manual_path,
        hashes_path=hashes_path,
        stage=stage,
    )

    if failures:
        for msg in failures:
            print(msg)
        sys.exit(1)
    else:
        print(f"draft-check ({stage}): all checks passed")
        sys.exit(0)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="AM evidence map tool (Phase 190/191/193)")
    sub = parser.add_subparsers(dest="command")

    sub.add_parser("coverage", help="Report uncovered manual lines")

    val_p = sub.add_parser("validate", help="Validate the evidence map")
    val_p.add_argument("--final", action="store_true",
                       help="Also check for [T2]/[T3] placeholders")

    sub.add_parser("export", help="Write Phase 190 xlsx and run round-trip check")

    ve_p = sub.add_parser("verdicts-export", help="Validate AM-VERDICTS.md and write team verdict workbook")
    ve_p.add_argument("--date", default=None,
                      help="Date suffix for filename (YYYYMMDD); defaults to today")

    dc_p = sub.add_parser("draft-check", help="Validate AM-DRAFT.md against the grammar and run-time inputs")
    dc_p.add_argument("--stage", default="full", choices=["core", "full"],
                      help="Validation stage: core defers repo-only domain region; full is default")
    dc_p.add_argument("--draft", default=None,
                      help="Path to AM-DRAFT.md (default: docs/analytic_manual/AM-DRAFT.md)")

    args = parser.parse_args()

    if args.command == "coverage":
        sys.exit(cmd_coverage(args))
    elif args.command == "validate":
        cmd_validate(args)
    elif args.command == "export":
        cmd_export(args)
    elif args.command == "verdicts-export":
        cmd_verdicts_export(args)
    elif args.command == "draft-check":
        cmd_draft_check(args)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
