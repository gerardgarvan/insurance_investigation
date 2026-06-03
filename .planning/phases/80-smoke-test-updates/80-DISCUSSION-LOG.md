# Phase 80: Smoke Test Updates - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-03
**Phase:** 80-smoke-test-updates
**Areas discussed:** Validation depth, Structural cleanup, Decade list updates

---

## Validation Depth

| Option | Description | Selected |
|--------|-------------|----------|
| Static analysis | Match existing R/88 pattern: check source() dependencies, key column references, output file patterns, and script-specific logic for R/54, R/55, R/56. ~5-8 checks per script, consistent with Phase 76-78 sections. | ✓ |
| Existence only | Just verify R/54, R/55, R/56 exist with correct filenames and proper documentation headers. Faster but less coverage than other v2.1 sections. | |
| You decide | Claude picks appropriate depth per script based on complexity and risk. | |

**User's choice:** Static analysis (Recommended)
**Notes:** Consistent with existing depth for other v2.1 scripts in R/88.

---

## Structural Cleanup

| Option | Description | Selected |
|--------|-------------|----------|
| Renumber all | Update all [N/M] progress labels to reflect the actual total section count. Clean sequential numbering from Section 1 through the final section. | ✓ |
| Append only | Add Phase 79 sections at the end with correct numbering from that point. Leave existing sections unchanged to minimize diff noise. | |

**User's choice:** Renumber all (Recommended)
**Notes:** None.

---

## Decade List Updates

| Option | Description | Selected |
|--------|-------------|----------|
| Expand existing decades | Widen cancer decade to include R/35-56 or add new Investigations decade for 30s scripts. Add R/76 to output decade (70-76). Adjust section headers and counts accordingly. | ✓ |
| Keep current + spot checks | Don't change decade groups. R/35 and R/76 are already validated by their dedicated sections. Just add R/54-56 to cancer decade. | |
| You decide | Claude determines the cleanest decade boundaries based on actual script distribution. | |

**User's choice:** Expand existing decades (Recommended)
**Notes:** None.

---

## Claude's Discretion

- Internal organization of new check sections (group by script vs group by requirement)
- Exact static analysis patterns per Phase 79 script
- Whether R/35 gets its own decade group or merges into adjacent one
- Check descriptions and message formatting

## Deferred Ideas

None — discussion stayed within phase scope.
