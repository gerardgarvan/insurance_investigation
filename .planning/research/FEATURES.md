# Feature Research: Rituximab/Methotrexate Non-Malignant Diagnoses of Interest

**Domain:** Clinical ICD code set — non-malignant conditions treated by rituximab and/or methotrexate
**Researched:** 2026-07-15
**Milestone:** v3.3 Rituximab/Methotrexate-Associated Diagnoses of Interest
**Confidence:** HIGH for table-stakes codes (established FDA indications with published ICD mappings); MEDIUM for edge/off-label codes (documented in literature but less standardized in claims)

---

## Purpose and Scope

This document defines the complete, verified ICD-9-CM and ICD-10-CM code set for NON-MALIGNANT conditions treated by rituximab and/or methotrexate. The pipeline needs this to flag when a Hodgkin Lymphoma cohort patient's rituximab or MTX administration is likely being given for a non-lymphoma condition (autoimmune, inflammatory, or hematologic) rather than for their cancer.

**Explicit exclusion:** HL/NHL/cancer codes remain in the existing `classify_codes()` / `utils_cancer.R` cascade. Every code in this document must be verified as absent from `CANCER_SITE_MAP` and `ICD9_CANCER_SITE_MAP` in R/00_config.R.

**Drug detection dependency:** Rituximab is already detected in `DRUG_GROUPINGS` via HCPCS J9310 (Rituximab IV), J9311 (Rituximab/Hyaluronidase SC), J9312 (Rituximab — Truxima biosimilar), all classified as "Chemotherapy" in the current pipeline (clinically reasonable for lymphoma context, but those same codes may appear in RA/vasculitis encounters). Methotrexate is detected via multiple RxNorm codes (6851, 105585, 105586, 105587, 1544388, 1544390, 1544398, 1441411, 1655956, 1655959, 1655960, 1655968, 1946772, 311625, 311627, 283510, 283511, 287734, 105604, 1921592) and HCPCS J9390 (not shown in file, verify at implementation). No new drug codes are needed — the v3.3 feature adds diagnosis codes only.

---

## Cancer Cascade Overlap Verification

The following code families from the cancer cascade must NOT appear in the new map. This section documents which cancer codes border the non-malignant code space and require active exclusion.

| Boundary | Cancer Cascade Codes | Non-Malignant Neighbor | Status |
|----------|---------------------|------------------------|--------|
| D69 family | CANCER_SITE_MAP has NO D69 entry | D69.2 (IgA vasculitis), D69.3 (ITP), D69.4x (other thrombocytopenia) | SAFE — D69 not in cancer map |
| D59 family | CANCER_SITE_MAP has NO D59 entry | D59.0/D59.1 (AIHA) | SAFE — D59 not in cancer map |
| M05/M06 family | Not in cancer map (M-block = musculoskeletal) | M05.x, M06.x (RA) | SAFE |
| M30/M31 family | Not in cancer map | M30.0, M31.0, M31.30/M31.31 (vasculitis) | SAFE |
| M32/M33/M35 family | Not in cancer map | M32.x (SLE), M33.x (dermatomyositis), M35.0x (Sjögren's) | SAFE |
| L10/L12/L40/L95 family | Not in cancer map | Pemphigus, pemphigoid, psoriasis, skin vasculitis | SAFE |
| G36/G37/G70/H46 family | Not in cancer map | Neurological autoimmune conditions | SAFE |
| K50/K51 family | Not in cancer map | Crohn's/IBD | SAFE |
| L10.81 (paraneoplastic pemphigus) | Not in cancer map itself, but condition is associated with malignancy | L10.81 | FLAG — see note below |

**L10.81 paraneoplastic pemphigus note:** This code represents pemphigus arising in the context of an underlying neoplasm (commonly lymphoma, thymoma, Castleman disease). In an HL cohort, L10.81 may appear legitimately as a paraneoplastic syndrome rather than a primary autoimmune condition. Recommendation: include L10.81 in the code set but flag it as "high overlap risk" in the implementation — encounters with L10.81 plus a concurrent cancer code should be treated with caution in attribution logic.

---

## Complete Code Set by Condition

### Legend

- **Drug(s):** RTX = rituximab; MTX = methotrexate; RTX+MTX = co-prescribed (combination)
- **Tier:** TABLE-STAKES = primary well-established indication; EDGE = less common / off-label but documented
- **Confidence:** HIGH = FDA-approved or major guideline-supported; MEDIUM = published evidence, not FDA-approved; LOW = case series or emerging

---

## 1. Rheumatoid Arthritis (RA)

**Drug(s):** RTX+MTX (combination; rituximab is FDA-approved for RA alongside background MTX; MTX is also used as monotherapy)
**Tier:** TABLE-STAKES
**Confidence:** HIGH — rituximab FDA-approved for moderate-to-severe RA in adults with inadequate response to TNF inhibitors (2006 approval); methotrexate is the anchor DMARD for RA globally

**Drug-condition note:** In RA, RTX is almost always co-prescribed with MTX. A patient receiving both drugs is a strong signal of RA (or another RTX+MTX-treated autoimmune disease) when lymphoma-specific codes are absent.

### ICD-10-CM Codes

The M05 family (RA with rheumatoid factor) and M06 family (seronegative RA) each have a site digit (0=unspecified, 1=shoulder, 2=elbow, 3=wrist, 4=hand, 5=hip, 6=knee, 7=ankle/foot, 8=other, 9=multiple). Only clinically relevant 4-character prefixes are listed; the 5th digit is the site and all are valid. For R config map purposes, 3-character prefix matching on M05 and M06 captures the full families cleanly.

| ICD-10 Code | Description | Notes |
|-------------|-------------|-------|
| M05.0x | Felty's syndrome (RA with splenomegaly + neutropenia) | Include — rare but well-defined |
| M05.1x | Rheumatoid lung disease with RA | Include |
| M05.2x | Rheumatoid vasculitis with RA | Include — note vasculitis in RA context |
| M05.3x | Rheumatoid heart disease with RA | Include |
| M05.4x | Rheumatoid myopathy with RA | Include |
| M05.5x | Rheumatoid polyneuropathy with RA | Include |
| M05.6x | RA with involvement of other organs (NOS) | Include |
| M05.7x | RA with rheumatoid factor, without organ involvement | Include — common |
| M05.8x | Other RA with rheumatoid factor | Include |
| M05.9 | RA with rheumatoid factor, unspecified | Include — common |
| M06.00–M06.09 | RA without rheumatoid factor, by site | Include — seronegative RA |
| M06.1 | Adult-onset Still's disease | Include — RTX used off-label; MTX standard |
| M06.20–M06.29 | Rheumatoid bursitis, by site | Include |
| M06.30–M06.39 | Rheumatoid nodule, by site | Include |
| M06.4 | Inflammatory polyarthropathy | Include |
| M06.80–M06.89 | Other specified RA, by site | Include |
| M06.9 | RA, unspecified | Include — most common unspecified code |

**Prefix-level capture (recommended for R config):** M05 (all subcodes) and M06 (all subcodes) as 3-character prefix entries. This captures the entire seropositive and seronegative RA families with a two-entry map rather than 40+ individual entries.

### ICD-9-CM Codes

| ICD-9 Code | Description | Notes |
|------------|-------------|-------|
| 714.0 | Rheumatoid arthritis | Primary code; used before Oct 2015 |
| 714.1 | Felty's syndrome | Include |
| 714.2 | Other RA with visceral/systemic involvement | Include |
| 714.30 | Polyarticular juvenile RA, chronic or unspecified | Include (if age-relevant) |
| 714.31 | Polyarticular JRA, acute | Include |
| 714.32 | Pauciarticular juvenile RA | Include |
| 714.33 | Monoarticular juvenile RA | Include |
| 714.4 | Chronic post-rheumatic arthropathy (Jaccoud's) | EDGE — rare sequel of RA |
| 714.81 | Rheumatoid lung | Include |
| 714.89 | Other RA syndromes | Include |
| 714.9 | Unspecified inflammatory polyarthropathy | Include |

**ICD-9 prefix-level capture:** 714 (3-character prefix) captures the full RA family. Note: 714.x does not include osteoarthritis (715) or psoriatic arthritis (696.0/L40.5x) — no overlap risk.

---

## 2. ANCA-Associated Vasculitis (AAV): GPA and MPA

**Drug(s):** RTX (FDA-approved for GPA and MPA, 2011); MTX is used for remission maintenance in GPA (off-label but guideline-supported)
**Tier:** TABLE-STAKES
**Confidence:** HIGH — rituximab FDA-approved for GPA/MPA (RAVE trial evidence); widely used as first-line alongside cyclophosphamide

### GPA (Granulomatosis with Polyangiitis, formerly Wegener's)

| ICD-10 Code | Description | Notes |
|-------------|-------------|-------|
| M31.30 | Wegener's granulomatosis without renal involvement | Include |
| M31.31 | Wegener's granulomatosis with renal involvement | Include — most common severe form |
| M31.39 | Other Wegener's granulomatosis | Include |

**Note on seed gap:** The ritdis_seed_codes.md correctly flagged that M31.3x codes were not enumerated. These are the correct GPA codes per ICD-10-CM 2025. GPA is coded under M31.3 (not M31.2 which is lethal midline granuloma).

### MPA (Microscopic Polyangiitis)

| ICD-10 Code | Description | Notes |
|-------------|-------------|-------|
| M31.7 | Microscopic polyangiitis | Include — primary MPA code |

### Additional vasculitis codes in the seed (verified)

| ICD-10 Code | Description | Drug | Notes |
|-------------|-------------|------|-------|
| M30.0 | Polyarteritis nodosa | RTX (off-label, EDGE) | PAN is ANCA-negative; RTX used in refractory cases. Included as EDGE |
| M31.0 | Hypersensitivity angiitis | RTX (EDGE) | Leukocytoclastic vasculitis; usually drug-induced or infection-related; RTX rare |
| I77.82 | Dissection of artery — CORRECTION NEEDED | See note | I77.82 is "Dissection of artery" in ICD-10-CM, NOT "ANCA-positive vasculitis" |
| L95.8 | Other skin-limited vasculitis | RTX (off-label, EDGE) | Refractory leukocytoclastic vasculitis |
| L95.9 | Vasculitis limited to skin, unspecified | RTX (off-label, EDGE) | |
| D69.2 | IgA vasculitis (Henoch-Schönlein purpura) | RTX (off-label, EDGE) | Used in severe/refractory HSP nephritis |

**CRITICAL CORRECTION — I77.82:** The seed code I77.82 is cited as "ANCA-positive vasculitis" but this is INCORRECT in ICD-10-CM. I77.82 = "Dissection of artery" (a non-inflammatory vascular condition unrelated to ANCA disease). The correct ANCA-positive vasculitis codes are M31.30/M31.31/M31.39 (GPA) and M31.7 (MPA) as listed above. There is no single ICD-10-CM code that encodes "ANCA-positive vasculitis" as a standalone concept. **Recommendation: EXCLUDE I77.82 from the code map — it is the wrong code and would falsely flag vascular injury cases.**

### ICD-9-CM Vasculitis Codes

| ICD-9 Code | Description | Notes |
|------------|-------------|-------|
| 446.0 | Polyarteritis nodosa | Maps to M30.0 |
| 446.4 | Wegener's granulomatosis | Maps to M31.3x — primary ICD-9 GPA code |
| 446.20 | Hypersensitivity angiitis, unspecified | Maps to M31.0 |
| 446.29 | Other hypersensitivity angiitis | Maps to M31.0 |
| 287.0 | Allergic purpura (Henoch-Schönlein) | Maps to D69.2 |
| 447.8 | Other specified disorders of arteries | Includes microscopic polyangiitis; no direct 446.x equivalent for MPA in ICD-9 |
| 709.1 | Vascular disorders of skin | Closest ICD-9 for skin-limited vasculitis (L95.x analog) |

---

## 3. Pemphigus and Mucous Membrane Pemphigoid

**Drug(s):** RTX (FDA-approved for moderate-to-severe pemphigus vulgaris, 2018); MTX used as steroid-sparing agent in pemphigoid (off-label)
**Tier:** TABLE-STAKES for RTX; EDGE for MTX
**Confidence:** HIGH (RTX/pemphigus vulgaris FDA-approved); MEDIUM (MTX/pemphigoid off-label)

### ICD-10-CM Pemphigus Codes

| ICD-10 Code | Description | Drug | Tier | Notes |
|-------------|-------------|------|------|-------|
| L10.0 | Pemphigus vulgaris | RTX | TABLE-STAKES | **This was the explicit gap in seed — L10.0 is the primary FDA-approved indication** |
| L10.1 | Pemphigus vegetans | RTX | TABLE-STAKES | Variant of PV; same treatment approach |
| L10.2 | Pemphigus foliaceus | RTX | TABLE-STAKES | Superficial pemphigus; RTX effective |
| L10.3 | Brazilian pemphigus (fogo selvagem) | RTX | EDGE | Geographic/endemic; rarely seen in FL cohort |
| L10.4 | Pemphigus erythematosus | RTX | EDGE | Overlap syndrome |
| L10.5 | Drug-induced pemphigus | RTX | EDGE | Treat if persistent after drug removal |
| L10.81 | Paraneoplastic pemphigus | RTX | EDGE + HIGH OVERLAP RISK | See note in cancer cascade section above |
| L10.89 | Other pemphigus | RTX | TABLE-STAKES | Include |
| L10.9 | Pemphigus, unspecified | RTX | TABLE-STAKES | Include |
| L12.0 | Bullous pemphigoid | RTX (EDGE), MTX (EDGE) | EDGE | RTX used in refractory BP; MTX as steroid-sparer |
| L12.1 | Cicatricial pemphigoid (mucous membrane pemphigoid) | RTX | TABLE-STAKES | FDA-approved indication (2018 label covers MMP) |
| L12.2 | Chronic bullous disease of childhood | RTX (EDGE) | EDGE | Pediatric; rare in adult HL cohort |
| L12.30 | Acquired epidermolysis bullosa, unspecified | RTX (EDGE) | EDGE | Refractory cases |
| L12.31 | Epidermolysis bullosa due to drug | RTX (EDGE) | EDGE | |
| L12.35 | Other acquired epidermolysis bullosa | RTX (EDGE) | EDGE | |
| L12.8 | Other pemphigoid | RTX | TABLE-STAKES | Include |
| L12.9 | Pemphigoid, unspecified | RTX | TABLE-STAKES | Include |

**Seed gap filled:** L10.0 (pemphigus vulgaris) was explicitly missing from the RTF despite being the primary FDA-approved rituximab indication for pemphigus. This is the single most important gap correction.

### ICD-9-CM Pemphigus/Pemphigoid Codes

| ICD-9 Code | Description | Notes |
|------------|-------------|-------|
| 694.4 | Pemphigus | Primary ICD-9 code; maps to L10.x family |
| 694.5 | Pemphigoid | Maps to L12.x family |
| 694.60 | Benign mucous membrane pemphigoid without eye involvement | Maps to L12.1 |
| 694.61 | Benign mucous membrane pemphigoid with eye involvement | Maps to L12.1 |
| 694.8 | Other specified bullous dermatoses | |
| 694.9 | Unspecified bullous dermatosis | |

---

## 4. Dermatomyositis and Polymyositis

**Drug(s):** RTX (off-label but guideline-supported for refractory DM/PM); MTX (standard steroid-sparing agent, TABLE-STAKES for MTX)
**Tier:** RTX = EDGE (not FDA-approved but ACR-endorsed for refractory); MTX = TABLE-STAKES
**Confidence:** MEDIUM for RTX (major randomized evidence from RIM trial); HIGH for MTX (standard of care)

### ICD-10-CM Codes

The M33 block has a 5th character for involvement type (see seed codes). The seed correctly enumerated M33.10–M33.19 (dermatomyositis) and M33.00–M33.03 (juvenile dermatomyositis). Complete enumeration:

| ICD-10 Code | Description | Notes |
|-------------|-------------|-------|
| M33.00 | Juvenile dermatomyositis, organ involvement unspecified | Include |
| M33.01 | Juvenile dermatomyositis with respiratory involvement | Include |
| M33.02 | Juvenile dermatomyositis with myopathy | Include |
| M33.03 | Juvenile dermatomyositis without myopathy | Include |
| M33.09 | Juvenile dermatomyositis with other organ involvement | Include |
| M33.10 | Other dermatomyositis, organ involvement unspecified | Include — most common adult DM code |
| M33.11 | Other dermatomyositis with respiratory involvement | Include |
| M33.12 | Other dermatomyositis with myopathy | Include |
| M33.13 | Other dermatomyositis without myopathy (amyopathic) | Include |
| M33.19 | Other dermatomyositis with other organ involvement | Include |
| M33.20 | Polymyositis, organ involvement unspecified | Include — RTX used in refractory PM |
| M33.21 | Polymyositis with respiratory involvement | Include |
| M33.22 | Polymyositis with myopathy | Include |
| M33.29 | Polymyositis with other organ involvement | Include |
| M33.90 | Dermatopolymyositis, unspecified, organ involvement unspecified | Include |
| M33.91 | Dermatopolymyositis, unspecified with respiratory involvement | Include |
| M33.92 | Dermatopolymyositis, unspecified with myopathy | Include |
| M33.93 | Dermatopolymyositis, unspecified without myopathy | Include |
| M33.99 | Dermatopolymyositis, unspecified with other organ involvement | Include |

**Prefix-level capture:** M33 (3-character prefix) captures all dermatomyositis and polymyositis variants cleanly.

### ICD-9-CM Codes

| ICD-9 Code | Description | Notes |
|------------|-------------|-------|
| 710.3 | Dermatomyositis | Primary ICD-9 code |
| 710.4 | Polymyositis | Include |

---

## 5. Neurological Autoimmune Conditions

**Drug(s):** RTX (off-label for NMO — now standard of care despite no FDA approval until 2019 for inebilizumab; rituximab used widely); MTX (not standard for NMO/MG)
**Tier:** RTX = TABLE-STAKES for NMO (guideline-supported); EDGE for MG, optic neuritis, transverse myelitis
**Confidence:** HIGH for NMO/RTX; MEDIUM for other neurological indications

### Neuromyelitis Optica Spectrum Disorder (NMOSD)

| ICD-10 Code | Description | Drug | Tier | Notes |
|-------------|-------------|------|------|-------|
| G36.0 | Neuromyelitis optica [Devic] | RTX | TABLE-STAKES | Standard RTX indication; inebilizumab and satralizumab now FDA-approved but RTX still widely used |
| G37.3 | Acute transverse myelitis in demyelinating disease of CNS | RTX (EDGE) | EDGE | Sometimes treated with RTX in NMO context; also occurs in non-NMO |

### Myasthenia Gravis

The seed explicitly flagged G70.0x codes as not enumerated. Complete code set:

| ICD-10 Code | Description | Drug | Tier | Notes |
|-------------|-------------|------|------|-------|
| G70.00 | Myasthenia gravis without (acute) exacerbation | RTX | EDGE | Off-label RTX for refractory MG; increasing evidence |
| G70.01 | Myasthenia gravis with (acute) exacerbation | RTX | EDGE | RTX used in crisis/refractory MG |
| G70.09 | Other myasthenia gravis | RTX | EDGE | |

**Gap filled:** G70.00 and G70.01 were the enumerated codes missing from the RTF for myasthenia gravis.

### Optic Neuritis

| ICD-10 Code | Description | Drug | Tier | Notes |
|-------------|-------------|------|------|-------|
| H46.0 | Optic papillitis | RTX (EDGE) | EDGE | Typically corticosteroid-treated; RTX if NMO-related |
| H46.00 | Optic papillitis, unspecified eye | RTX (EDGE) | EDGE | |
| H46.01 | Optic papillitis, right eye | RTX (EDGE) | EDGE | |
| H46.02 | Optic papillitis, left eye | RTX (EDGE) | EDGE | |
| H46.03 | Optic papillitis, bilateral | RTX (EDGE) | EDGE | |
| H46.1 | Retrobulbar neuritis | RTX (EDGE) | EDGE | If NMO-associated |
| H46.10 | Retrobulbar neuritis, unspecified eye | RTX (EDGE) | EDGE | |
| H46.11 | Retrobulbar neuritis, right eye | RTX (EDGE) | EDGE | |
| H46.12 | Retrobulbar neuritis, left eye | RTX (EDGE) | EDGE | |
| H46.13 | Retrobulbar neuritis, bilateral | RTX (EDGE) | EDGE | |
| H46.2 | Nutritional optic neuropathy | EXCLUDE | — | Not autoimmune; not treated with RTX/MTX |
| H46.3 | Toxic optic neuropathy | EXCLUDE | — | Drug/toxin cause; not autoimmune |
| H46.8 | Other optic neuritis | RTX (EDGE) | EDGE | Include |
| H46.9 | Unspecified optic neuritis | RTX (EDGE) | EDGE | Include |

**Prefix-level note:** H46 prefix would capture H46.2 (nutritional) and H46.3 (toxic) which should be excluded. Prefer 4-character prefix entries (H460, H461, H468, H469) or enumerate H46.0x/H46.1x/H46.8/H46.9 individually.

### ICD-9-CM Neurological Codes

| ICD-9 Code | Description | Notes |
|------------|-------------|-------|
| 341.0 | Neuromyelitis optica | Maps to G36.0 |
| 323.9 | Unspecified causes of encephalitis — use with caution | Transverse myelitis often coded here in ICD-9 |
| 341.22 | Acute transverse myelitis NOS | Maps to G37.3 |
| 341.3 | Acute transverse myelitis (in conditions classified elsewhere) | Include |
| 358.00 | Myasthenia gravis without (acute) exacerbation | Maps to G70.00 |
| 358.01 | Myasthenia gravis with (acute) exacerbation | Maps to G70.01 |
| 377.30 | Optic neuritis, unspecified | Maps to H46.9 |
| 377.31 | Optic papillitis | Maps to H46.0x |
| 377.32 | Retrobulbar neuritis (acute) | Maps to H46.1x |
| 377.39 | Other optic neuritis | Maps to H46.8 |

---

## 6. Hematologic Autoimmune Conditions

**This entire section was a gap in the seed RTF — codes not listed.**

### Immune Thrombocytopenic Purpura (ITP)

**Drug(s):** RTX (off-label but widely used, FDA approval pending; second-line after corticosteroids); MTX (not standard for ITP)
**Tier:** RTX = TABLE-STAKES (major ITP treatment guideline); MTX = not indicated
**Confidence:** HIGH for RTX/ITP (major randomized trials; ASH guidelines support RTX)

| ICD-10 Code | Description | Notes |
|-------------|-------------|-------|
| D69.3 | Immune thrombocytopenic purpura | Primary ITP code — include |
| D69.41 | Evans syndrome (immune thrombocytopenia + AIHA) | Include — RTX used |
| D69.49 | Other primary thrombocytopenia | Include |

**Note on D69.x vs cancer cascade:** Verify — D69.2 (IgA vasculitis) and D69.3 (ITP) are NOT in CANCER_SITE_MAP. D69 as a prefix is not mapped in the cancer cascade. SAFE to use.

**ICD-9 Equivalent:**

| ICD-9 Code | Description | Notes |
|------------|-------------|-------|
| 287.31 | Immune thrombocytopenic purpura | Maps to D69.3 |
| 287.32 | Evans syndrome | Maps to D69.41 |
| 287.33 | Congenital and hereditary thrombocytopenic purpura | Exclude — not autoimmune |
| 287.39 | Other primary thrombocytopenia | Include |

### Autoimmune Hemolytic Anemia (AIHA)

**Drug(s):** RTX (off-label; used for warm-antibody AIHA and cold agglutinin disease); MTX (not standard)
**Tier:** RTX = TABLE-STAKES for warm-AIHA (ASH 2021 guidelines); EDGE for cold agglutinin disease
**Confidence:** HIGH for warm-AIHA; MEDIUM for cold agglutinin disease

| ICD-10 Code | Description | Drug | Tier | Notes |
|-------------|-------------|------|------|-------|
| D59.0 | Drug-induced autoimmune hemolytic anemia | RTX (EDGE) | EDGE | May be drug-induced; verify context |
| D59.1 | Other autoimmune hemolytic anemias | RTX | TABLE-STAKES | Primary warm-AIHA code |
| D59.12 | Cold agglutinin disease | RTX | TABLE-STAKES | RTX is first-line for cold agglutinin disease (2021 evidence) |
| D59.13 | Mixed type autoimmune hemolytic anemia | RTX | TABLE-STAKES | Include |
| D59.19 | Other autoimmune hemolytic anemia | RTX | TABLE-STAKES | Include |

**Note on D59 granularity:** ICD-10-CM FY2023 expanded D59.1 into D59.11 (warm-type), D59.12 (cold agglutinin disease), D59.13 (mixed), D59.19 (other). Older data may only have D59.1. Include both D59.1 (legacy) and D59.1x (FY2023+) via 4-character prefix matching on D591.

**ICD-9 Equivalent:**

| ICD-9 Code | Description | Notes |
|------------|-------------|-------|
| 283.0 | Autoimmune hemolytic anemias | Primary ICD-9 code for AIHA |
| 283.10 | Non-autoimmune hemolytic anemia, unspecified | EXCLUDE — not autoimmune |
| 283.11 | Hemolytic-uremic syndrome | EXCLUDE |
| 283.19 | Other non-autoimmune hemolytic anemias | EXCLUDE |

---

## 7. Systemic Lupus Erythematosus (SLE)

**This section was a gap in the seed RTF — codes not listed.**

**Drug(s):** RTX (off-label; commonly used for renal lupus and cytopenias despite failed EXPLORER/LUNAR trials); MTX (standard for non-renal SLE — skin, joints, serositis)
**Tier:** RTX = TABLE-STAKES (ACR/EULAR guidelines recommend RTX for refractory SLE despite no FDA approval); MTX = TABLE-STAKES for non-renal manifestations
**Confidence:** HIGH for clinical use (extensively documented); MEDIUM for FDA regulatory status (not FDA-approved for SLE)

### ICD-10-CM Codes

| ICD-10 Code | Description | Notes |
|-------------|-------------|-------|
| M32.0 | Drug-induced systemic lupus erythematosus | Include — RTX/MTX-induced SLE is rare but possible; flag as context-dependent |
| M32.10 | Systemic lupus erythematosus, organ or system involvement unspecified | Include |
| M32.11 | Endocarditis in SLE | Include |
| M32.12 | Pericarditis in SLE | Include |
| M32.13 | Lung involvement in SLE | Include |
| M32.14 | Glomerular disease in SLE (lupus nephritis) | Include — common RTX target |
| M32.15 | Tubulo-interstitial nephropathy in SLE | Include |
| M32.19 | Other organ or system involvement in SLE | Include |
| M32.8 | Other forms of SLE | Include |
| M32.9 | SLE, unspecified | Include — most common code |

**Prefix-level capture:** M32 (3-character prefix) captures the entire SLE family. No oncology overlap risk.

### ICD-9-CM Codes

| ICD-9 Code | Description | Notes |
|------------|-------------|-------|
| 710.0 | Systemic lupus erythematosus | Primary ICD-9 SLE code |

---

## 8. Sjögren's Syndrome

**This section was a gap in the seed RTF — codes not listed.**

**Drug(s):** RTX (off-label; used for systemic/extraglandular manifestations — vasculitis, peripheral neuropathy, cryoglobulinemia, B-cell lymphoma risk reduction); MTX (limited use; not standard)
**Tier:** RTX = EDGE (used for systemic manifestations; TEARS trial failed for sicca symptoms); MTX = EDGE
**Confidence:** MEDIUM for RTX (guideline-listed as option for systemic disease); LOW for MTX

### ICD-10-CM Codes

| ICD-10 Code | Description | Notes |
|-------------|-------------|-------|
| M35.00 | Sjögren's syndrome, unspecified | Include |
| M35.01 | Sjögren's syndrome with keratoconjunctivitis | Include |
| M35.02 | Sjögren's syndrome with lung involvement | Include |
| M35.03 | Sjögren's syndrome with myopathy | Include |
| M35.04 | Sjögren's syndrome with tubulo-interstitial nephropathy | Include |
| M35.05 | Sjögren's syndrome with inflammatory arthritis | Include — RTX active in this manifestation |
| M35.06 | Sjögren's syndrome with peripheral nervous system involvement | Include — RTX used |
| M35.07 | Sjögren's syndrome with central nervous system involvement | Include |
| M35.08 | Sjögren's syndrome with gastrointestinal involvement | Include |
| M35.09 | Sjögren's syndrome with other organ involvement | Include |

**Prefix-level capture:** M35.0 (4-character prefix) captures all Sjögren's codes within M35. Note that M35 without the .0 subcategory would capture other connective tissue disorders — use M350 as the 4-character prefix key.

### ICD-9-CM Codes

| ICD-9 Code | Description | Notes |
|------------|-------------|-------|
| 710.2 | Sicca syndrome (Sjögren's disease) | Primary ICD-9 code |

---

## 9. Methotrexate-Specific Indications

Conditions for which MTX is clinically standard but rituximab is generally NOT indicated (or only EDGE). These are the MTX-only additions to the code set.

### Psoriasis and Psoriatic Arthritis

**Drug(s):** MTX (TABLE-STAKES — first-line systemic for plaque psoriasis and psoriatic arthritis); RTX (EDGE — not preferred; biologics like TNFi and IL-17i are preferred)
**Tier:** MTX = TABLE-STAKES; RTX = EDGE (psoriatic arthritis only)
**Confidence:** HIGH for MTX/psoriasis

#### ICD-10-CM Psoriasis Codes

| ICD-10 Code | Description | MTX | RTX | Notes |
|-------------|-------------|-----|-----|-------|
| L40.0 | Psoriasis vulgaris | TABLE-STAKES | EDGE | Classic plaque psoriasis; MTX standard |
| L40.1 | Generalized pustular psoriasis | TABLE-STAKES | EDGE | Severe form; MTX used |
| L40.2 | Acrodermatitis continua | TABLE-STAKES | EDGE | |
| L40.3 | Pustulosis palmaris et plantaris | TABLE-STAKES | EDGE | |
| L40.4 | Guttate psoriasis | EDGE | No | Usually self-limiting; MTX for severe |
| L40.5x | Arthropathic psoriasis (psoriatic arthritis) | TABLE-STAKES | EDGE | MTX anchor DMARD; RTX off-label |
| L40.50 | Arthropathic psoriasis, unspecified | TABLE-STAKES | EDGE | |
| L40.51 | Distal interphalangeal psoriatic arthropathy | TABLE-STAKES | EDGE | |
| L40.52 | Psoriatic arthritis mutilans | TABLE-STAKES | EDGE | |
| L40.53 | Psoriatic spondylitis | TABLE-STAKES | No | Axial disease; MTX less effective |
| L40.54 | Psoriatic juvenile arthropathy | TABLE-STAKES | EDGE | |
| L40.59 | Other psoriatic arthropathy | TABLE-STAKES | EDGE | |
| L40.8 | Other psoriasis | TABLE-STAKES | EDGE | |
| L40.9 | Psoriasis, unspecified | TABLE-STAKES | EDGE | Most common unspecified code |

**Prefix-level capture:** L40 (3-character prefix) captures all psoriasis codes.

#### ICD-9-CM Psoriasis Codes

| ICD-9 Code | Description | Notes |
|------------|-------------|-------|
| 696.0 | Psoriatic arthropathy | Maps to L40.5x |
| 696.1 | Other psoriasis | Maps to L40.0/L40.9 |

### Crohn's Disease / Inflammatory Bowel Disease

**Drug(s):** MTX (TABLE-STAKES for Crohn's — used when thiopurines fail or as combination; STRIDE guidelines include MTX); RTX (EDGE — rarely used in IBD; some case reports in refractory Crohn's)
**Tier:** MTX = TABLE-STAKES for Crohn's; EDGE for UC; RTX = EDGE for both
**Confidence:** HIGH for MTX/Crohn's (ECCO guidelines recommend MTX as second-line immunomodulator)

#### ICD-10-CM IBD Codes

| ICD-10 Code | Description | MTX | Notes |
|-------------|-------------|-----|-------|
| K50.00 | Crohn's disease of small intestine without complications | TABLE-STAKES | Include |
| K50.011 | Crohn's disease of small intestine with rectal bleeding | TABLE-STAKES | Include |
| K50.012 | Crohn's disease of small intestine with intestinal obstruction | TABLE-STAKES | Include |
| K50.013 | Crohn's disease of small intestine with fistula | TABLE-STAKES | Include |
| K50.014 | Crohn's disease of small intestine with abscess | TABLE-STAKES | Include |
| K50.018 | Crohn's disease of small intestine with other complication | TABLE-STAKES | Include |
| K50.019 | Crohn's disease of small intestine with unspecified complications | TABLE-STAKES | Include |
| K50.10 | Crohn's disease of large intestine without complications | TABLE-STAKES | Include |
| K50.111–K50.119 | Crohn's disease of large intestine with complications | TABLE-STAKES | Include |
| K50.80 | Other Crohn's disease without complications | TABLE-STAKES | Include |
| K50.811–K50.819 | Other Crohn's disease with complications | TABLE-STAKES | Include |
| K50.90 | Crohn's disease, unspecified, without complications | TABLE-STAKES | Most common code |
| K50.911–K50.919 | Crohn's disease, unspecified, with complications | TABLE-STAKES | Include |
| K51.0x | Ulcerative (chronic) pancolitis | EDGE | MTX less evidence in UC vs Crohn's |
| K51.2x | Ulcerative (chronic) proctitis | EDGE | |
| K51.3x | Ulcerative (chronic) rectosigmoiditis | EDGE | |
| K51.4x | Inflammatory polyps of colon (UC-related) | EDGE | |
| K51.5x | Left-sided colitis | EDGE | |
| K51.8x | Other ulcerative colitis | EDGE | |
| K51.90 | Ulcerative colitis, unspecified | EDGE | |

**Prefix-level capture:** K50 (3-character prefix) for Crohn's; K51 (3-character prefix) for UC (EDGE tier).

#### ICD-9-CM IBD Codes

| ICD-9 Code | Description | Notes |
|------------|-------------|-------|
| 555.0 | Regional enteritis of small intestine | Maps to K50.0x |
| 555.1 | Regional enteritis of large intestine | Maps to K50.1x |
| 555.2 | Regional enteritis of small intestine with large intestine | Maps to K50.8x |
| 555.9 | Regional enteritis of unspecified site | Maps to K50.9x — most common |
| 556.0 | Ulcerative (chronic) enterocolitis | Maps to K51.0x |
| 556.1 | Ulcerative (chronic) ileocolitis | Maps to K51.1x |
| 556.2 | Ulcerative (chronic) proctitis | Maps to K51.2x |
| 556.3 | Ulcerative (chronic) proctosigmoiditis | Maps to K51.3x |
| 556.6 | Universal ulcerative (chronic) colitis | Maps to K51.0x |
| 556.9 | Ulcerative colitis, unspecified | Maps to K51.9x |

### Other MTX-Specific Indications (Clinically Standard)

| Condition | ICD-10 | ICD-9 | Drug | Tier | Notes |
|-----------|--------|-------|------|------|-------|
| Juvenile idiopathic arthritis (JIA) | M08.00–M08.99 | 714.30–714.33 | MTX | TABLE-STAKES | MTX is the anchor DMARD for polyarticular JIA; RTX used in RTX-resistant cases |
| Reactive arthritis (Reiter's) | M02.30–M02.39 | 099.3 | MTX | EDGE | MTX used in chronic reactive arthritis |
| Primary Sjögren's with arthritis (captured in M35.05 above) | — | — | MTX+RTX | — | Already covered |
| Eosinophilic granulomatosis with polyangiitis (EGPA / Churg-Strauss) | M30.1 | 446.4 (see note) | RTX | EDGE | EGPA now treated with mepolizumab (FDA-approved) but RTX used off-label |
| Anti-MBM glomerulonephritis (Goodpasture-like) | M31.0 | 446.21 | RTX | EDGE | See M31.0 in vasculitis section |
| Cryoglobulinemic vasculitis | D89.1 | 273.2 | RTX | TABLE-STAKES | RTX is preferred for HCV-associated and non-HCV cryoglobulinemia; MTX not standard |
| Relapsing polychondritis | M94.1 | 733.99 | MTX+RTX | EDGE | RTX and MTX both used in refractory cases |
| Inflammatory myopathy (anti-synthetase syndrome) | M60.9 | 729.1 | MTX+RTX | EDGE | MTX standard; RTX for refractory |
| Multicentric Castleman disease (MCD) | D47.Z2 | — | RTX | EDGE + HIGH OVERLAP RISK | Castleman disease is classified in CANCER_SITE_MAP under D47 = "MDS/Myeloproliferative." RTX is primary treatment but DO NOT include — D47 is already cancer-classified |
| Primary CNS vasculitis | I67.7 | 437.4 | RTX | EDGE | Rare; RTX used in some centers |

**Critical overlap alert — D47.Z2 (Castleman disease):** The cancer cascade maps D47 to "MDS/Myeloproliferative." D47.Z2 (multicentric Castleman disease) would be captured by the 3-character D47 prefix and classified as a malignancy/near-malignancy. Do NOT add D47.Z2 to the non-malignant code set — it is already in the cancer cascade and would create double-classification.

---

## Feature Landscape Summary

### Table Stakes (Strongly Drug-Associated, Well-Established Indications)

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| RA code family (M05/M06, ICD-9 714) | Primary FDA-approved RTX non-malignant indication; RTX+MTX combination standard of care | LOW | 3-char prefix capture: M05, M06, 714 |
| GPA/MPA codes (M31.30/M31.31/M31.7) | FDA-approved RTX indication (2011 RAVE trial) | LOW | 4-char prefix M313 + M317 |
| Pemphigus vulgaris and variants (L10.x) | FDA-approved RTX indication (2018); L10.0 was missing from seed | LOW | 3-char prefix L10 |
| Pemphigoid (L12.x) | RTX used; MTX as steroid-sparer | LOW | 3-char prefix L12 |
| SLE (M32.x, ICD-9 710.0) | RTX and MTX both widely used despite no FDA approval | LOW | 3-char prefix M32 |
| ITP (D69.3, D69.41) | RTX standard second-line per ASH guidelines | LOW | Specific codes, not prefix match (D69 also has non-autoimmune codes) |
| Warm-AIHA (D59.1x, ICD-9 283.0) | RTX standard per ASH 2021 guidelines | LOW | 4-char prefix D591 |
| NMO/Devic (G36.0, ICD-9 341.0) | RTX widely used as prophylaxis despite inebilizumab FDA approval | LOW | Specific code G36.0 |
| Psoriasis/PsA (L40.x, ICD-9 696.0/696.1) | MTX first-line systemic therapy | LOW | 3-char prefix L40 |
| Crohn's disease (K50.x, ICD-9 555.x) | MTX second-line immunomodulator per ECCO guidelines | LOW | 3-char prefix K50 |
| Dermatomyositis/PM (M33.x, ICD-9 710.3/710.4) | MTX standard; RTX for refractory | LOW | 3-char prefix M33 |

### Differentiators (Edge/Off-Label Indications)

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Cold agglutinin disease (D59.12) | RTX is first-line; FY2023 granular code worth capturing | LOW | Distinct from warm-AIHA |
| Myasthenia gravis (G70.00/G70.01) | RTX increasingly used; gap in most payer databases | LOW | Specific codes |
| Sjögren's syndrome (M35.0x) | RTX for systemic manifestations; important attribution signal | LOW | 4-char prefix M350 |
| Skin-limited vasculitis (L95.8/L95.9) | RTX in refractory leukocytoclastic vasculitis | LOW | Specific codes |
| Ulcerative colitis (K51.x) | MTX less evidence than Crohn's; EDGE tier | LOW | 3-char prefix K51 |
| Cryoglobulinemic vasculitis (D89.1) | RTX preferred treatment; often missed in code sets | LOW | Specific code D89.1 |
| IgA vasculitis (D69.2) | RTX in severe nephritis; HSP in adult HL cohort is unusual | LOW | Specific code D69.2 |

### Anti-Features (Codes to Explicitly Exclude)

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| I77.82 (Dissection of artery) | Seed cited this as "ANCA vasculitis" but it is WRONG — I77.82 = arterial dissection | Use M31.30/M31.31/M31.7 for GPA/MPA |
| D47.Z2 (Castleman disease) | Already in cancer cascade under D47 = MDS/Myeloproliferative | Exclude; cannot appear in both maps |
| L10.81 (Paraneoplastic pemphigus) without cancer context | In HL cohort, paraneoplastic pemphigus often IS cancer-related | Include code but add high-overlap flag in attribution logic |
| H46.2 (Nutritional optic neuropathy) | Not autoimmune; not treated with RTX/MTX | Exclude; use H46.0x/H46.1x instead |
| H46.3 (Toxic optic neuropathy) | Drug/toxin etiology; not autoimmune | Exclude |
| M30.1 (EGPA/Churg-Strauss) without verification | Now primarily treated with mepolizumab; RTX only off-label | Include as EDGE with low confidence flag |
| ICD-9 446.4 (used for both GPA and EGPA in ICD-9) | ICD-9 446.4 = "Wegener's granulomatosis" only; EGPA has no clean ICD-9 code | Use 446.4 for GPA only; note EGPA limitation |

---

## Drug-to-Condition Mapping Matrix

| Condition | RTX | MTX | Co-prescribed | Attribution Signal Strength |
|-----------|-----|-----|---------------|----------------------------|
| Rheumatoid arthritis (M05, M06) | TABLE-STAKES | TABLE-STAKES | Yes — standard combination | VERY HIGH: RTX+MTX together + RA code = near-certain non-lymphoma |
| GPA/Wegener's (M31.30/M31.31) | TABLE-STAKES | EDGE (maintenance) | Sometimes | HIGH: RTX alone + GPA code |
| MPA (M31.7) | TABLE-STAKES | No | No | HIGH: RTX alone + MPA code |
| Pemphigus vulgaris (L10.0) | TABLE-STAKES | No standard | No | HIGH: RTX alone + L10.0 |
| Pemphigoid (L12.x) | EDGE | EDGE | Sometimes | MEDIUM: either drug alone is common for other conditions |
| Dermatomyositis (M33.1x) | EDGE | TABLE-STAKES | Sometimes | HIGH for MTX+DM code; MEDIUM for RTX alone |
| SLE (M32.x) | EDGE | TABLE-STAKES | Sometimes | HIGH for MTX+SLE; MEDIUM for RTX+SLE |
| ITP (D69.3) | TABLE-STAKES | No | No | HIGH: RTX + ITP code |
| Warm-AIHA (D59.1x) | TABLE-STAKES | No | No | HIGH: RTX + AIHA code |
| NMO (G36.0) | TABLE-STAKES | No | No | HIGH: RTX + NMO code |
| Myasthenia gravis (G70.0x) | EDGE | No | No | MEDIUM: RTX + MG code |
| Psoriasis/PsA (L40.x) | EDGE | TABLE-STAKES | Rarely | HIGH for MTX alone + psoriasis code; MEDIUM for RTX |
| Crohn's disease (K50.x) | EDGE | TABLE-STAKES | Rarely | HIGH for MTX + Crohn's code |
| Ulcerative colitis (K51.x) | EDGE | EDGE | No | LOW: insufficient evidence for confident attribution |
| Sjögren's (M35.0x) | EDGE | EDGE | Sometimes | MEDIUM |

---

## Feature Dependencies

```
ICD-10 code set definition
    └──required by──> classify_noncancer_dx() classification function
    └──required by──> encounter-level diagnosis-of-interest flag
    └──required by──> treatment-attribution linkage

Treatment-attribution linkage
    └──requires──> drug detection already in DRUG_GROUPINGS (J9310/J9311/J9312 = RTX; 6851 etc. = MTX)
    └──requires──> encounter-level non-malignant diagnosis flag
    └──requires──> temporal window logic (existing +/-30 day pattern from Phase 8)

Non-overlapping classification
    └──requires──> is_cancer_code() exclusion check from utils_cancer.R
    └──conflicts with──> CANCER_SITE_MAP entries (D47.Z2 must be excluded from this set)
```

---

## Implementation Notes for R/00_config.R

The new code map should mirror the structure of `CANCER_SITE_MAP` (named character vector, prefix keys). Recommended structure uses a mix of 3-character and 4-character prefix keys:

**3-character prefix entries (capture entire ICD-10 family):**
M05, M06, M32, M33, L10, L12, L40, K50, K51

**4-character prefix entries (subcategory specificity needed):**
M313 (GPA = M31.30/M31.31/M31.39; avoids M31.0 hypersensitivity angiitis if desired separately)
M317 (MPA = M31.7x)
M350 (Sjögren's only within M35)
D591 (AIHA = D59.1x, capturing both legacy D59.1 and granular D59.1x)

**Individual code entries (no prefix-level capture appropriate):**
D69.2, D69.3, D69.41 (ITP/IgA vasculitis — D69 prefix would capture benign/unrelated)
D89.1 (cryoglobulinemia — D89 prefix too broad)
G36.0 (NMO — G36 prefix too broad; G36.8/G36.9 are unrelated)
G37.3 (transverse myelitis — G37 prefix too broad)
G70.00, G70.01 (myasthenia gravis — G70 prefix too broad)
H46.0x, H46.1x, H46.8, H46.9 (optic neuritis — exclude H46.2/H46.3)
L95.8, L95.9 (skin vasculitis — L95 prefix OK; no oncology neighbors)
M30.0 (PAN — 3-char M30 also includes M30.1 EGPA; use 4-char M300 or specific code)
M31.0 (hypersensitivity angiitis — use specific code)
I77.89 (if systemic vasculitis needs a code; I77.82 is EXCLUDED)

**ICD-9 entries:** Use the 3-character prefix where safe (714 for RA, 710 for SLE/DM/PM/Sjögren's); individual codes for D-group analogs.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| RA codes (M05/M06, 714.x) | HIGH | FDA-approved RTX indication; ICD codes verified against ICD-10-CM 2025 tabular |
| GPA/MPA codes (M31.30/M31.31/M31.7) | HIGH | FDA-approved RTX indication; ICD-10-CM code structure verified |
| I77.82 exclusion | HIGH | Confirmed I77.82 = arterial dissection, NOT ANCA vasculitis in ICD-10-CM — seed error |
| Pemphigus (L10.x) | HIGH | FDA-approved RTX indication; L10.0 gap in seed confirmed and filled |
| Pemphigoid (L12.x) | HIGH | RTX FDA-approved for cicatricial pemphigoid; ICD codes verified |
| SLE (M32.x) | HIGH | Codes correct; RTX/MTX clinical use well-documented despite no FDA SLE approval |
| ITP (D69.3) | HIGH | Codes correct; RTX standard per ASH guidelines |
| AIHA (D59.1x) | HIGH | Codes correct; D59.1x granularity FY2023 expansion noted |
| NMO (G36.0) | HIGH | Correct code; RTX widely used as prophylaxis |
| Myasthenia gravis (G70.0x) | HIGH | Gap in seed filled; codes correct per ICD-10-CM |
| Psoriasis/PsA (L40.x) | HIGH | MTX FDA-approved for psoriasis; ICD codes verified |
| Crohn's (K50.x) | HIGH | MTX ECCO guideline-recommended; ICD codes verified |
| Dermatomyositis (M33.x) | HIGH | MTX standard; RTX for refractory; codes correct |
| Sjögren's (M35.0x) | MEDIUM | RTX for systemic disease; FY2022 expansion of M35.0x codes verified |
| Cold agglutinin disease (D59.12) | MEDIUM | FY2023 ICD-10-CM code; may appear as D59.1 in older data |
| Cryoglobulinemia (D89.1) | MEDIUM | Code correct; RTX evidence strong but less systematically captured in claims |
| Optic neuritis H46.x exclusions | MEDIUM | H46.2/H46.3 exclusion logic requires 4-char prefix implementation |
| EGPA (M30.1) | LOW | Code correct; RTX only off-label; mepolizumab now preferred |
| ICD-9 equivalents | MEDIUM | Pre-2015 codes; standard mapping verified against GEMS crosswalk patterns |

---

## Sources

Clinical indications:
- FDA rituximab (Rituxan) prescribing information — approved indications: RA (2006), GPA/MPA (2011), pemphigus vulgaris (2018), CLL, NHL
- ACR guidelines for biologic and targeted synthetic DMARDs in RA (2022)
- EULAR recommendations for management of ANCA-associated vasculitis (2022)
- ASH guidelines on ITP (2019, updated 2021) — RTX as second-line
- ASH guidelines on AIHA (2021) — RTX first-line for warm-AIHA; RTX first-line for cold agglutinin disease
- ECCO guidelines on Crohn's disease medical management (2023) — MTX as second-line immunomodulator
- ACR guidelines on inflammatory myopathies (2023) — MTX standard; RTX for refractory
- International Pemphigus and Pemphigoid Foundation treatment guidelines (2023) — RTX first-line option

ICD code verification:
- ICD-10-CM FY2025 Tabular List (CMS, effective Oct 2024) — M05/M06/M30-M36/D59/D69/G36/G37/G70/H46/L10/L12/L40/K50/K51
- ICD-10-CM FY2023 expansion of D59.1 into D59.11/D59.12/D59.13/D59.19
- ICD-10-CM FY2022 expansion of M35.0 into M35.00–M35.09
- ICD-9-CM tabular (pre-Oct 2015) — 714.x/710.x/696.x/555.x/556.x/694.x/287.x/283.x/446.x
- CANCER_SITE_MAP and ICD9_CANCER_SITE_MAP in R/00_config.R — verified no overlap with D69, D59, M05, M06, M30-M36, L10, L12, L40, K50, K51, G36, G37, G70, H46, L95 families
- D47 prefix confirmed in cancer cascade — D47.Z2 (Castleman) excluded from this code set

Gap corrections:
- ritdis_seed_codes.md — gap inventory reviewed; all 5 named gaps filled: L10.0 (PV), M31.3x (GPA), G70.0x (MG), D69.3+D59.x (hematologic), M32.x+M35.0x (connective tissue)
- I77.82 correction: seed cited as "ANCA-positive vasculitis" — verified in ICD-10-CM 2025 as "Dissection of artery"; excluded

---

*Feature research for: v3.3 Rituximab/Methotrexate Non-Malignant Diagnoses of Interest*
*Researched: 2026-07-15*
