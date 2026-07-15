# Seed Code Set — Rituximab/Methotrexate Non-Malignant Diagnoses of Interest

Extracted from `ritdis.rtf` (user-supplied clinical reference, 2026-07-15). This is the
**seed** for milestone v3.3. It is rituximab-centric and has gaps (hematologic and
connective-tissue codes named but not enumerated; methotrexate-specific indications not
covered). Research should COMPLETE and VERIFY this set, not treat it as final.

**Scope rule:** These are NON-malignant diagnoses only. HL/NHL/cancer codes remain in the
existing `classify_codes()` / `utils_cancer.R` cancer cascade and must NOT be duplicated here.

## Rheumatoid Arthritis (RA)
Primary FDA-approved non-malignant indication; rituximab prescribed alongside methotrexate
for moderate-to-severe active RA.
- **M06.9** — Rheumatoid arthritis, unspecified (most common)
- **M05.9** — RA with rheumatoid factor, unspecified
- **M05.x** (various) — RA with rheumatoid factor (joint sites / organ involvement)
- **M06.0x** (various) — RA without rheumatoid factor (joint sites)
- **M06.8x** (various) — Other specified RA
- **ICD-9 714.0** — Rheumatoid arthritis (valid prior to Oct 2015)

## Vasculitis
Highly effective for ANCA-associated vasculitis — Granulomatosis with Polyangiitis
(GPA/Wegener's) and Microscopic Polyangiitis (MPA).
- **L95.9** — Skin-limited vasculitis, unspecified
- **L95.8** — Other skin-limited vasculitis (e.g. leukocytoclastic)
- **I77.82** — ANCA-positive vasculitis
- **M30.0** — Polyarteritis nodosa
- **M31.0** — Hypersensitivity angiitis
- **D69.2** — IgA vasculitis (formerly Henoch-Schönlein purpura)
- *(GAP: GPA/Wegener's and MPA named but their specific M31.3x codes not enumerated — verify)*

## Dermatologic Conditions
Blistering / severe skin disease — notably Pemphigus Vulgaris, mucous membrane pemphigoid,
dermatomyositis.
- **L10.1** — Pemphigus vegetans
- **L10.5** — Drug-induced pemphigus
- **L10.81** — Paraneoplastic pemphigus
- **L10.9** — Pemphigus, unspecified
- **L12.0** — Bullous pemphigoid *(label inferred; verify)*
- **M33.10 / M33.11 / M33.12 / M33.13 / M33.19** — Dermatomyositis (organ involvement variants)
- **M33.00 / M33.02 / M33.03** — Juvenile dermatomyositis variants
- *(GAP: Pemphigus vulgaris L10.0 itself not listed though named — verify)*

## Neurological Disorders
Off-label for autoimmune neuromyelitis optica and myasthenia gravis.
- **G36.0** — Neuromyelitis optica [Devic]
- **ICD-9 341.0** — (prior NMO code)
- **H46.0** — Optic neuritis / optic papillitis
- **H46.1** — Retrobulbar neuritis
- **G37.3** — Acute transverse myelitis
- *(GAP: myasthenia gravis named but G70.0x codes not enumerated — verify)*

## Hematologic Disorders
Benign immune-mediated blood disorders — Immune Thrombocytopenic Purpura (ITP) and
Autoimmune Hemolytic Anemia (AIHA).
- *(GAP: codes NOT listed in RTF — research should supply, e.g. D69.3 ITP, D59.x AIHA)*

## Connective Tissue & Others
Systemic lupus erythematosus (SLE) and Sjögren's syndrome.
- *(GAP: codes NOT listed in RTF — research should supply, e.g. M32.x SLE, M35.0x Sjögren's)*

## Methotrexate-Specific (NOT covered by the rituximab-centric RTF)
Milestone scope includes methotrexate. Research should supply MTX non-malignant indications
NOT already covered above, e.g.:
- Psoriasis / psoriatic arthritis (L40.x)
- Crohn's disease / IBD (K50.x)
- *(and any others clinically standard for MTX)*
