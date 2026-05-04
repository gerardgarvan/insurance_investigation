# Phase 39: Investigate Unmatched Codes - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-04
**Phase:** 39-investigate-unmatched-codes
**Areas discussed:** Code systems scope, Investigation method, Resolution action, Drug landscape (NDC)

---

## Code Systems Scope

| Option | Description | Selected |
|--------|-------------|----------|
| CPT/HCPCS only | Focus on codes Phase 38 already flagged via heuristic ranges. Tightest scope, fastest results. | ✓ |
| CPT/HCPCS + ICD-10-PCS | Add ICD-10-PCS prefix-based detection. Two most structured code systems. | |
| All procedure codes | CPT/HCPCS + ICD-10-PCS + ICD-9 + DRG + revenue codes. Most comprehensive. | |

**User's choice:** CPT/HCPCS only
**Notes:** None

### Follow-up: Heuristic Range Width

| Option | Description | Selected |
|--------|-------------|----------|
| Existing ranges | Investigate only J9xxx, 774xx, 382xx, XW0xx codes Phase 38 already flags. | |
| Widen ranges slightly | Broaden to adjacent code families (J-codes beyond J9, 77xxx beyond 774xx, legacy CPT). | ✓ |
| You decide | Claude reviews actual output first and recommends. | |

**User's choice:** Widen ranges slightly
**Notes:** None

### Follow-up: J-Code Range

| Option | Description | Selected |
|--------|-------------|----------|
| J9 only | Stick to J9xxx — definitively antineoplastic agents. | |
| J0-J9 full range | Scan all J-codes. Surfaces supportive care alongside chemo. | |
| J9 + curated J0-J8 | J9xxx full range plus targeted list of known supportive care J-codes. | ✓ |

**User's choice:** J9 + curated J0-J8
**Notes:** None

### Follow-up: Radiation Range

| Option | Description | Selected |
|--------|-------------|----------|
| Delivery only (774xx) | Keep focused on treatment delivery codes. | |
| Full radiation range (772xx-779xx) | Include simulation, planning, and delivery. | |
| Delivery + planning | 774xx delivery plus 773xx treatment planning. Skip simulation. | ✓ |

**User's choice:** Delivery + planning
**Notes:** None

---

## Investigation Method

| Option | Description | Selected |
|--------|-------------|----------|
| Automated lookup | Build code-to-description mappings from CMS HCPCS/CPT reference files. Each code gets a human-readable name automatically. | ✓ |
| Manual review of output | Export unmatched codes to xlsx, user reviews manually. | |
| Hybrid | Automated lookup for codes with known descriptions, flag remaining unknowns for manual review. | |

**User's choice:** Automated lookup
**Notes:** None

### Follow-up: Lookup Source

| Option | Description | Selected |
|--------|-------------|----------|
| Embed in script | Hardcode descriptions for codes found in data directly in R. No external file dependency. | |
| CMS reference CSV | Download CMS HCPCS quarterly update files to HiPerGator, load as lookup table. | ✓ |
| You decide | Claude picks approach fitting codebase patterns. | |

**User's choice:** CMS reference CSV
**Notes:** None

### Follow-up: Classification

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-classify + flag uncertain | Script assigns suggested category, flags uncertain ones. | |
| Description only | Just provide code + CMS description + patient count. No classification. | |
| Auto-classify all | Script assigns definitive category to every code. No uncertainty flags. | ✓ |

**User's choice:** Auto-classify all
**Notes:** None

---

## Resolution Action

| Option | Description | Selected |
|--------|-------------|----------|
| Report only | Produce xlsx report. User decides later whether to update TREATMENT_CODES. | |
| Report + update config | Produce report AND automatically add confirmed codes to TREATMENT_CODES in R/00_config.R. | ✓ |
| Report + recommendations | Report with 'recommended action' column. No automatic config changes. | |

**User's choice:** Report + update config
**Notes:** None

### Follow-up: Threshold

| Option | Description | Selected |
|--------|-------------|----------|
| All classified codes | Any code auto-classified as treatment category gets added. Maximum coverage. | ✓ |
| Patient count threshold | Only add codes appearing in N+ patients. Filters rare codes. | |
| You decide | Claude picks reasonable threshold based on data distribution. | |

**User's choice:** All classified codes
**Notes:** None

---

## Drug Landscape (NDC)

| Option | Description | Selected |
|--------|-------------|----------|
| Skip NDC this phase | NDC mapping is a large effort. Keep focused on CPT/HCPCS. | ✓ |
| NDC for known chemo only | Map NDC codes to 4 known ABVD drugs using FDA NDC directory. | |
| Full NDC mapping | Build comprehensive NDC-to-treatment mappings. May warrant its own phase. | |

**User's choice:** Skip NDC this phase
**Notes:** None

---

## Claude's Discretion

- Choice of specific CMS reference file format and download approach
- Classification heuristic rules (keyword matching on descriptions, code family patterns)
- xlsx report layout and styling
- Which specific J0-J8 codes to include in curated supportive care list

## Deferred Ideas

- NDC-to-treatment mapping — large scope, potentially its own phase
- ICD-10-PCS broader range detection
- ICD-9/DRG/revenue code gap analysis
