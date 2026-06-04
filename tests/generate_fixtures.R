# ==============================================================================
# Generate PCORnet CDM test fixture CSVs for local testing
# ==============================================================================
#
# Purpose:
#   Single source of truth for fixture data. Defines 20 synthetic patients
#   covering 11 clinical edge cases, then writes 15 PCORnet CDM table CSVs to
#   tests/fixtures/ directory.
#
# Usage:
#   source("tests/generate_fixtures.R")
#   # Writes 15 CSVs to tests/fixtures/
#
# To update fixtures:
#   1. Edit this script
#   2. Re-run: source("tests/generate_fixtures.R")
#   3. Git commit both this script and regenerated CSVs
#
# Edge cases covered (D-10):
#   1. Dual-eligible (PT002) - payer code "14"
#   2. NLPHL (PT003) - C81.00 diagnosis
#   3. SCT (PT004) - CPT 38241 procedure
#   4. Multiple cancers (PT005) - C81.40 + C50.911
#   5. Death dates (PT006) - DEATH table record
#   6. Orphan dx codes (PT007) - Z51.11 without paired procedure
#   7. Same-day multi-payer (PT008) - 2 encounters same date
#   8. 1900 sentinel dates (PT009) - ENR_START_DATE = 1900-01-01
#   9. ICD-9/ICD-10 cross-system (PT010) - 201.90 + C81.90 (10-day gap)
#   10. Missing payer (PT011) - PAYER_TYPE_PRIMARY = "NI"
#   11. ABVD regimen (PT012) - RXNORM_CUIs 3639, 11213, 67228, 3946
#   Baseline happy path (PT001, PT020)
#   Variation patients (PT013-PT019)
#
# ==============================================================================

source("R/00_config.R") # Loads PCORNET_TABLES, PCORNET_PATHS, ICD_CODES, AMC_PAYER_LOOKUP, TREATMENT_CODES

library(tibble)
library(dplyr)
library(readr)
library(glue)
library(purrr)

message("\n", strrep("=", 60))
message("PCORnet Test Fixture Generator")
message(strrep("=", 60))

# ==============================================================================
# SECTION 1: PATIENT ROSTER ----
# ==============================================================================
# 20 patients: 2 baseline, 11 edge cases (some patients = 2 cases), 7 variations

PATIENT_IDS <- sprintf("PT%03d", 1:20)

# ==============================================================================
# SECTION 2: TABLE GENERATORS ----
# ==============================================================================

generate_enrollment <- function() {
  tribble(
    ~ID,      ~ENR_START_DATE, ~ENR_END_DATE, ~CHART, ~ENR_BASIS, ~SOURCE,
    # PT001: Baseline happy path
    "PT001",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UFH",
    # PT002: Dual-eligible (will have payer code 14 in ENCOUNTER)
    "PT002",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "AMS",
    # PT003: NLPHL
    "PT003",  "2011-06-01",    "2015-12-31",  "Y",    "I",        "FLM",
    # PT004: SCT
    "PT004",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "VRT",
    # PT005: Multiple cancers
    "PT005",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UMI",
    # PT006: Death date
    "PT006",  "2010-01-01",    "2014-06-30",  "Y",    "I",        "UFH",
    # PT007: Orphan dx codes
    "PT007",  "2011-01-01",    "2015-12-31",  "Y",    "I",        "AMS",
    # PT008: Same-day multi-payer
    "PT008",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "FLM",
    # PT009: 1900 sentinel dates (bad enrollment dates to filter)
    "PT009",  "1900-01-01",    "2015-12-31",  "Y",    "I",        "VRT",
    # PT010: ICD-9/ICD-10 cross-system
    "PT010",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UMI",
    # PT011: Missing payer (will have NI in ENCOUNTER)
    "PT011",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UFH",
    # PT012: ABVD regimen (will have 4 drugs in PRESCRIBING)
    "PT012",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "AMS",
    # PT013-PT019: Additional variation patients
    "PT013",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "FLM",
    "PT014",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "VRT",
    "PT015",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UMI",
    "PT016",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UFH",
    "PT017",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "AMS",
    "PT018",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "FLM",
    "PT019",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "VRT",
    # PT020: Baseline happy path #2
    "PT020",  "2010-01-01",    "2015-12-31",  "Y",    "I",        "UMI"
  )
}

generate_diagnosis <- function() {
  tribble(
    ~DIAGNOSISID, ~ID,     ~ENCOUNTERID, ~ENC_TYPE, ~ADMIT_DATE,  ~PROVIDERID, ~DX,      ~DX_TYPE, ~DX_DATE,     ~DX_SOURCE, ~DX_ORIGIN, ~PDX, ~DX_POA, ~SOURCE,
    # PT001: Baseline — standard ICD-10 HL
    "DX001",      "PT001", "ENC001_01",  "IP",      "2013-03-15", "PROV001",   "C81.10", "10",     "2013-03-15", "AD",       "OD",       "P",  "Y",     "UFH",
    # PT002: Dual-eligible
    "DX002",      "PT002", "ENC002_01",  "IP",      "2013-06-20", "PROV001",   "C81.20", "10",     "2013-06-20", "AD",       "OD",       "P",  "Y",     "AMS",
    # PT003: NLPHL — C81.0x
    "DX003",      "PT003", "ENC003_01",  "IP",      "2013-09-10", "PROV001",   "C81.00", "10",     "2013-09-10", "AD",       "OD",       "P",  "Y",     "FLM",
    # PT004: SCT (diagnosis, procedure in PROCEDURES)
    "DX004",      "PT004", "ENC004_01",  "IP",      "2012-05-12", "PROV001",   "C81.30", "10",     "2012-05-12", "AD",       "OD",       "P",  "Y",     "VRT",
    # PT005: Multiple cancers — HL + breast cancer
    "DX005A",     "PT005", "ENC005_01",  "IP",      "2013-01-20", "PROV001",   "C81.40", "10",     "2013-01-20", "AD",       "OD",       "P",  "Y",     "UMI",
    "DX005B",     "PT005", "ENC005_02",  "AV",      "2013-02-10", "PROV001",   "C50.911","10",     "2013-02-10", "AD",       "OD",       "S",  NA,      "UMI",
    # PT006: Death date (diagnosis, death in DEATH)
    "DX006",      "PT006", "ENC006_01",  "IP",      "2013-11-05", "PROV001",   "C81.70", "10",     "2013-11-05", "AD",       "OD",       "P",  "Y",     "UFH",
    # PT007: Orphan dx codes — Z51.11 without paired chemo procedure
    "DX007A",     "PT007", "ENC007_01",  "AV",      "2013-04-15", "PROV001",   "C81.90", "10",     "2013-04-15", "AD",       "OD",       "P",  "Y",     "AMS",
    "DX007B",     "PT007", "ENC007_02",  "AV",      "2013-05-20", "PROV001",   "Z51.11", "10",     "2013-05-20", "AD",       "OD",       "S",  NA,      "AMS",
    # PT008: Same-day multi-payer (two encounters same date, different payers in ENCOUNTER)
    "DX008",      "PT008", "ENC008_01",  "AV",      "2013-07-10", "PROV001",   "C81.90", "10",     "2013-07-10", "AD",       "OD",       "P",  "Y",     "FLM",
    # PT009: 1900 sentinel dates (enrollment table has bad date, DX is normal)
    "DX009",      "PT009", "ENC009_01",  "IP",      "2012-12-01", "PROV001",   "C81.90", "10",     "2012-12-01", "AD",       "OD",       "P",  "Y",     "VRT",
    # PT010: ICD-9/ICD-10 cross-system — diagnoses 10 days apart (satisfies 7-day gap)
    "DX010A",     "PT010", "ENC010_01",  "IP",      "2012-11-05", "PROV001",   "201.90", "09",     "2012-11-05", "AD",       "OD",       "P",  "Y",     "UMI",
    "DX010B",     "PT010", "ENC010_02",  "AV",      "2012-11-15", "PROV001",   "C81.90", "10",     "2012-11-15", "AD",       "OD",       "P",  "Y",     "UMI",
    # PT011: Missing payer (diagnosis, payer NI in ENCOUNTER)
    "DX011",      "PT011", "ENC011_01",  "IP",      "2013-08-22", "PROV001",   "C81.90", "10",     "2013-08-22", "AD",       "OD",       "P",  "Y",     "UFH",
    # PT012: ABVD regimen (diagnosis, drugs in PRESCRIBING)
    "DX012",      "PT012", "ENC012_01",  "IP",      "2013-02-14", "PROV001",   "C81.90", "10",     "2013-02-14", "AD",       "OD",       "P",  "Y",     "AMS",
    # PT013-PT019: Variation patients
    "DX013",      "PT013", "ENC013_01",  "IP",      "2013-05-10", "PROV001",   "C81.20", "10",     "2013-05-10", "AD",       "OD",       "P",  "Y",     "FLM",
    "DX014",      "PT014", "ENC014_01",  "IP",      "2012-08-15", "PROV001",   "C81.30", "10",     "2012-08-15", "AD",       "OD",       "P",  "Y",     "VRT",
    "DX015",      "PT015", "ENC015_01",  "AV",      "2013-12-20", "PROV001",   "C81.40", "10",     "2013-12-20", "AD",       "OD",       "P",  "Y",     "UMI",
    "DX016",      "PT016", "ENC016_01",  "IP",      "2012-10-25", "PROV001",   "C81.70", "10",     "2012-10-25", "AD",       "OD",       "P",  "Y",     "UFH",
    "DX017",      "PT017", "ENC017_01",  "IP",      "2013-03-30", "PROV001",   "C81.90", "10",     "2013-03-30", "AD",       "OD",       "P",  "Y",     "AMS",
    "DX018",      "PT018", "ENC018_01",  "AV",      "2012-11-12", "PROV001",   "C81.10", "10",     "2012-11-12", "AD",       "OD",       "P",  "Y",     "FLM",
    "DX019",      "PT019", "ENC019_01",  "IP",      "2013-07-18", "PROV001",   "C81.20", "10",     "2013-07-18", "AD",       "OD",       "P",  "Y",     "VRT",
    # PT020: Baseline #2
    "DX020",      "PT020", "ENC020_01",  "IP",      "2013-10-05", "PROV001",   "C81.90", "10",     "2013-10-05", "AD",       "OD",       "P",  "Y",     "UMI"
  )
}

generate_encounter <- function() {
  tribble(
    ~ENCOUNTERID, ~ID,     ~ADMIT_DATE,  ~ADMIT_TIME, ~DISCHARGE_DATE, ~DISCHARGE_TIME, ~PROVIDERID, ~FACILITY_LOCATION, ~ENC_TYPE, ~FACILITYID, ~DISCHARGE_DISPOSITION, ~DISCHARGE_STATUS, ~DRG, ~DRG_TYPE, ~ADMITTING_SOURCE, ~PAYER_TYPE_PRIMARY, ~PAYER_TYPE_SECONDARY, ~FACILITY_TYPE, ~SOURCE,
    # PT001: Baseline — private insurance
    "ENC001_01",  "PT001", "2013-03-15", "08:00",     "2013-03-20",    "14:00",         "PROV001",   "FL",               "IP",      "FAC001",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "UFH",
    # PT002: Dual-eligible — payer code 14
    "ENC002_01",  "PT002", "2013-06-20", "09:30",     "2013-06-25",    "11:00",         "PROV001",   "FL",               "IP",      "FAC002",    "A",                    "01",               "840","MS",      "1",               "14",                NA,                    "HOSPITAL",     "AMS",
    # PT003: NLPHL
    "ENC003_01",  "PT003", "2013-09-10", "10:00",     "2013-09-15",    "12:00",         "PROV001",   "FL",               "IP",      "FAC003",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "FLM",
    # PT004: SCT
    "ENC004_01",  "PT004", "2012-05-12", "07:00",     "2012-05-22",    "16:00",         "PROV001",   "FL",               "IP",      "FAC004",    "A",                    "01",               "840","MS",      "1",               "111",               NA,                    "HOSPITAL",     "VRT",
    # PT005: Multiple cancers — two encounters
    "ENC005_01",  "PT005", "2013-01-20", "08:00",     "2013-01-25",    "14:00",         "PROV001",   "FL",               "IP",      "FAC005",    "A",                    "01",               "840","MS",      "1",               "211",               NA,                    "HOSPITAL",     "UMI",
    "ENC005_02",  "PT005", "2013-02-10", "09:00",     NA,              NA,              "PROV001",   "FL",               "AV",      "FAC005",    NA,                     NA,                 NA,   NA,        NA,                "211",               NA,                    "CLINIC",       "UMI",
    # PT006: Death date
    "ENC006_01",  "PT006", "2013-11-05", "08:00",     "2013-11-10",    "14:00",         "PROV001",   "FL",               "IP",      "FAC001",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "UFH",
    # PT007: Orphan dx codes — two encounters, Z51.11 in second
    "ENC007_01",  "PT007", "2013-04-15", "08:00",     NA,              NA,              "PROV001",   "FL",               "AV",      "FAC002",    NA,                     NA,                 NA,   NA,        NA,                "512",               NA,                    "CLINIC",       "AMS",
    "ENC007_02",  "PT007", "2013-05-20", "09:00",     NA,              NA,              "PROV001",   "FL",               "AV",      "FAC002",    NA,                     NA,                 NA,   NA,        NA,                "512",               NA,                    "CLINIC",       "AMS",
    # PT008: Same-day multi-payer — two encounters same ADMIT_DATE, different payers
    "ENC008_01",  "PT008", "2013-07-10", "08:00",     NA,              NA,              "PROV001",   "FL",               "AV",      "FAC003",    NA,                     NA,                 NA,   NA,        NA,                "1",                 NA,                    "CLINIC",       "FLM",
    "ENC008_02",  "PT008", "2013-07-10", "14:00",     NA,              NA,              "PROV002",   "FL",               "AV",      "FAC003",    NA,                     NA,                 NA,   NA,        NA,                "512",               NA,                    "CLINIC",       "FLM",
    # PT009: 1900 sentinel dates
    "ENC009_01",  "PT009", "2012-12-01", "08:00",     "2012-12-06",    "14:00",         "PROV001",   "FL",               "IP",      "FAC004",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "VRT",
    # PT010: ICD-9/ICD-10 cross-system — two encounters 10 days apart
    "ENC010_01",  "PT010", "2012-11-05", "08:00",     "2012-11-10",    "14:00",         "PROV001",   "FL",               "IP",      "FAC005",    "A",                    "01",               "840","MS",      "1",               "111",               NA,                    "HOSPITAL",     "UMI",
    "ENC010_02",  "PT010", "2012-11-15", "09:00",     NA,              NA,              "PROV001",   "FL",               "AV",      "FAC005",    NA,                     NA,                 NA,   NA,        NA,                "111",               NA,                    "CLINIC",       "UMI",
    # PT011: Missing payer — PAYER_TYPE_PRIMARY = "NI"
    "ENC011_01",  "PT011", "2013-08-22", "08:00",     "2013-08-27",    "14:00",         "PROV001",   "FL",               "IP",      "FAC001",    "A",                    "01",               "840","MS",      "1",               "NI",                NA,                    "HOSPITAL",     "UFH",
    # PT012: ABVD regimen
    "ENC012_01",  "PT012", "2013-02-14", "08:00",     "2013-02-19",    "14:00",         "PROV001",   "FL",               "IP",      "FAC002",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "AMS",
    # PT013-PT019: Variation patients
    "ENC013_01",  "PT013", "2013-05-10", "08:00",     "2013-05-15",    "14:00",         "PROV001",   "FL",               "IP",      "FAC003",    "A",                    "01",               "840","MS",      "1",               "111",               NA,                    "HOSPITAL",     "FLM",
    "ENC014_01",  "PT014", "2012-08-15", "08:00",     "2012-08-20",    "14:00",         "PROV001",   "FL",               "IP",      "FAC004",    "A",                    "01",               "840","MS",      "1",               "211",               NA,                    "HOSPITAL",     "VRT",
    "ENC015_01",  "PT015", "2013-12-20", "09:00",     NA,              NA,              "PROV001",   "FL",               "AV",      "FAC005",    NA,                     NA,                 NA,   NA,        NA,                "512",               NA,                    "CLINIC",       "UMI",
    "ENC016_01",  "PT016", "2012-10-25", "08:00",     "2012-10-30",    "14:00",         "PROV001",   "FL",               "IP",      "FAC001",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "UFH",
    "ENC017_01",  "PT017", "2013-03-30", "08:00",     "2013-04-04",    "14:00",         "PROV001",   "FL",               "IP",      "FAC002",    "A",                    "01",               "840","MS",      "1",               "111",               NA,                    "HOSPITAL",     "AMS",
    "ENC018_01",  "PT018", "2012-11-12", "09:00",     NA,              NA,              "PROV001",   "FL",               "AV",      "FAC003",    NA,                     NA,                 NA,   NA,        NA,                "211",               NA,                    "CLINIC",       "FLM",
    "ENC019_01",  "PT019", "2013-07-18", "08:00",     "2013-07-23",    "14:00",         "PROV001",   "FL",               "IP",      "FAC004",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "VRT",
    # PT020: Baseline #2
    "ENC020_01",  "PT020", "2013-10-05", "08:00",     "2013-10-10",    "14:00",         "PROV001",   "FL",               "IP",      "FAC005",    "A",                    "01",               "840","MS",      "1",               "512",               NA,                    "HOSPITAL",     "UMI"
  )
}

generate_demographic <- function() {
  tribble(
    ~ID,      ~BIRTH_DATE,  ~BIRTH_TIME, ~SEX, ~SEXUAL_ORIENTATION, ~GENDER_IDENTITY, ~HISPANIC, ~RACE, ~BIOBANK_FLAG, ~PAT_PREF_LANGUAGE_SPOKEN, ~ZIP_CODE, ~SOURCE,
    "PT001",  "1975-06-15", "12:00",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "32611",   "UFH",
    "PT002",  "1940-03-20", "08:00",     "F",  NA,                  NA,               "N",       "03",  NA,            "eng",                     "33101",   "AMS",
    "PT003",  "1982-11-10", "14:30",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "32301",   "FLM",
    "PT004",  "1968-07-22", "10:00",     "F",  NA,                  NA,               "Y",       "04",  NA,            "spa",                     "32801",   "VRT",
    "PT005",  "1955-01-15", "11:00",     "F",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "33140",   "UMI",
    "PT006",  "1950-08-30", "09:00",     "M",  NA,                  NA,               "N",       "03",  NA,            "eng",                     "32611",   "UFH",
    "PT007",  "1978-04-12", "13:00",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "33101",   "AMS",
    "PT008",  "1985-09-05", "15:00",     "F",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "32301",   "FLM",
    "PT009",  "1972-12-20", "08:30",     "M",  NA,                  NA,               "N",       "03",  NA,            "eng",                     "32801",   "VRT",
    "PT010",  "1960-05-18", "10:30",     "F",  NA,                  NA,               "Y",       "04",  NA,            "spa",                     "33140",   "UMI",
    "PT011",  "1980-02-28", "12:30",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "32611",   "UFH",
    "PT012",  "1970-11-11", "14:00",     "F",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "33101",   "AMS",
    "PT013",  "1988-03-03", "11:30",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "32301",   "FLM",
    "PT014",  "1965-07-07", "09:30",     "F",  NA,                  NA,               "N",       "03",  NA,            "eng",                     "32801",   "VRT",
    "PT015",  "1992-10-10", "13:30",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "33140",   "UMI",
    "PT016",  "1958-12-25", "10:00",     "F",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "32611",   "UFH",
    "PT017",  "1974-06-06", "14:30",     "M",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "33101",   "AMS",
    "PT018",  "1983-08-08", "12:00",     "F",  NA,                  NA,               "Y",       "04",  NA,            "spa",                     "32301",   "FLM",
    "PT019",  "1966-02-14", "09:00",     "M",  NA,                  NA,               "N",       "03",  NA,            "eng",                     "32801",   "VRT",
    "PT020",  "1979-09-09", "11:00",     "F",  NA,                  NA,               "N",       "05",  NA,            "eng",                     "33140",   "UMI"
  )
}

generate_procedures <- function() {
  tribble(
    ~PROCEDURESID, ~ID,     ~ENCOUNTERID, ~ENC_TYPE, ~ADMIT_DATE,  ~PROVIDERID, ~PX_DATE,     ~PX,     ~PX_TYPE, ~PX_SOURCE, ~PPX, ~SOURCE,
    # PT004: SCT — autologous stem cell transplant
    "PX004",       "PT004", "ENC004_01",  "IP",      "2012-05-12", "PROV001",   "2012-05-18", "38241", "CH",     "OD",       NA,   "VRT"
  )
}

generate_prescribing <- function() {
  tribble(
    ~PRESCRIBINGID, ~ID,     ~ENCOUNTERID, ~RX_PROVIDERID, ~RX_ORDER_DATE, ~RX_ORDER_TIME, ~RX_START_DATE, ~RX_END_DATE, ~RX_DOSE_ORDERED, ~RX_DOSE_ORDERED_UNIT, ~RX_QUANTITY, ~RX_DOSE_FORM, ~RX_REFILLS, ~RX_DAYS_SUPPLY, ~RX_FREQUENCY, ~RX_PRN_FLAG, ~RX_ROUTE, ~RX_BASIS, ~RXNORM_CUI, ~RX_SOURCE, ~RX_DISPENSE_AS_WRITTEN, ~RAW_RX_MED_NAME,           ~RAW_RXNORM_CUI, ~SOURCE,
    # PT012: ABVD regimen — all 4 drugs on same date
    "RX012_01",     "PT012", "ENC012_01",  "PROV001",      "2013-02-15",   "08:00",        "2013-02-15",   "2013-02-15", 50,               "mg",                  NA,           "INJ",         0L,          1L,              "Q1D",         "N",         "IV",      "P",       "3639",      "OD",       NA,                         "Doxorubicin 50mg IV",      "3639",          "AMS",
    "RX012_02",     "PT012", "ENC012_01",  "PROV001",      "2013-02-15",   "08:15",        "2013-02-15",   "2013-02-15", 10,               "units",               NA,           "INJ",         0L,          1L,              "Q1D",         "N",         "IV",      "P",       "11213",     "OD",       NA,                         "Bleomycin 10 units IV",    "11213",         "AMS",
    "RX012_03",     "PT012", "ENC012_01",  "PROV001",      "2013-02-15",   "08:30",        "2013-02-15",   "2013-02-15", 6,                "mg",                  NA,           "INJ",         0L,          1L,              "Q1D",         "N",         "IV",      "P",       "67228",     "OD",       NA,                         "Vinblastine 6mg IV",       "67228",         "AMS",
    "RX012_04",     "PT012", "ENC012_01",  "PROV001",      "2013-02-15",   "08:45",        "2013-02-15",   "2013-02-15", 375,              "mg",                  NA,           "INJ",         0L,          1L,              "Q1D",         "N",         "IV",      "P",       "3946",      "OD",       NA,                         "Dacarbazine 375mg IV",     "3946",          "AMS"
  )
}

generate_condition <- function() {
  tribble(
    ~CONDITIONID, ~ID,     ~ENCOUNTERID, ~CONDITION, ~CONDITION_TYPE, ~CONDITION_SOURCE, ~CONDITION_STATUS, ~ONSET_DATE, ~REPORT_DATE, ~RESOLVE_DATE, ~RAW_CONDITION_TYPE, ~RAW_CONDITION_SOURCE,
    # Minimal row for DuckDB ingest
    "COND001",    "PT001", "ENC001_01",  "E11.9",    "10",            "HC",              "AC",              NA,          NA,           NA,            NA,                  NA,                   "UFH"
  )
}

generate_death <- function() {
  tribble(
    ~ID,     ~DEATH_DATE,   ~DEATH_DATE_IMPUTE, ~DEATH_SOURCE, ~DEATH_MATCH_CONFIDENCE, ~SOURCE,
    # PT006: Death date edge case
    "PT006", "2014-06-15",  "N",                "L",           NA,                       "UFH"
  )
}

generate_dispensing <- function() {
  # Empty table with correct schema
  tibble(
    DISPENSINGID = character(),
    PRESCRIBINGID = character(),
    ID = character(),
    DISPENSE_DATE = character(),
    NDC = character(),
    DISPENSE_SUP = integer(),
    DISPENSE_AMT = double(),
    DISPENSE_DOSE_DISP = double(),
    DISPENSE_DOSE_DISP_UNIT = character(),
    DISPENSE_ROUTE = character(),
    RAW_NDC = character(),
    RXNORM_CUI = character(),
    DISPENSE_SOURCE = character(),
    RAW_DISPENSE_MED_NAME = character(),
    SOURCE = character()
  )
}

generate_med_admin <- function() {
  # Empty table with correct schema
  tibble(
    MEDADMINID = character(),
    ID = character(),
    ENCOUNTERID = character(),
    PRESCRIBINGID = character(),
    MEDADMIN_CODE = character(),
    MEDADMIN_TYPE = character(),
    MEDADMIN_START_DATE = character(),
    MEDADMIN_STOP_DATE = character(),
    MEDADMIN_ROUTE = character(),
    RXNORM_CUI = character(),
    RAW_MEDADMIN_MED_NAME = character(),
    SOURCE = character()
  )
}

generate_lab_result_cm <- function() {
  # Empty table with correct schema (key columns only)
  tibble(
    LAB_RESULTID = character(),
    ID = character(),
    ENCOUNTERID = character(),
    LAB_ORDER_DATE = character(),
    RESULT_DATE = character(),
    SPECIMEN_DATE = character(),
    LAB_LOINC = character(),
    LAB_LOINC_SOURCE = character(),
    LAB_PX = character(),
    LAB_PX_TYPE = character(),
    RESULT_NUM = double(),
    RESULT_UNIT = character(),
    RESULT_QUAL = character(),
    RESULT_MODIFIER = character(),
    SPECIMEN_SOURCE = character(),
    ABN_IND = character(),
    NORM_RANGE_HIGH = character(),
    NORM_RANGE_LOW = character(),
    RAW_LAB_CODE = character(),
    RAW_LAB_NAME = character(),
    RAW_RESULT = character(),
    SOURCE = character()
  )
}

generate_provider <- function() {
  tribble(
    ~PROVIDERID, ~PROVIDER_SEX, ~PROVIDER_SPECIALTY_PRIMARY, ~SOURCE,
    # Provider 1: Hematology/Oncology specialist
    "PROV001",   "M",            "207RH0003X",                 "UFH",
    # Provider 2: Additional provider for multi-encounter patients
    "PROV002",   "F",            "207RH0003X",                 "FLM"
  )
}

generate_tumor_registry1 <- function() {
  # Empty table with pipeline-used columns only
  tibble(
    ID = character(),
    SOURCE = character(),
    SITE_CODE = character(),
    HISTOLOGICAL_TYPE = character(),
    HISTOLOGICAL_TYPE_DESCRIPTION = character(),
    BEHAVIOR_CODE = character(),
    GRADE = character(),
    AGE_AT_DIAGNOSIS = integer(),
    TUMOR_SIZE_SUMMARY = double(),
    DX_DATE_TR = character()
  )
}

generate_tumor_registry2 <- function() {
  # Empty table with pipeline-used columns only
  tibble(
    ID = character(),
    SOURCE = character(),
    SITE = character(),
    MORPH = character(),
    DXAGE = integer(),
    DX_DATE_TR = character()
  )
}

generate_tumor_registry3 <- function() {
  # Empty table with pipeline-used columns only
  tibble(
    ID = character(),
    SOURCE = character(),
    SITE = character(),
    MORPH = character(),
    DXAGE = integer(),
    DX_DATE_TR = character()
  )
}

# ==============================================================================
# SECTION 3: ASSEMBLE AND WRITE FIXTURES ----
# ==============================================================================

fixture_tables <- list(
  ENROLLMENT = generate_enrollment(),
  DIAGNOSIS = generate_diagnosis(),
  CONDITION = generate_condition(),
  PROCEDURES = generate_procedures(),
  PRESCRIBING = generate_prescribing(),
  ENCOUNTER = generate_encounter(),
  DEMOGRAPHIC = generate_demographic(),
  TUMOR_REGISTRY1 = generate_tumor_registry1(),
  TUMOR_REGISTRY2 = generate_tumor_registry2(),
  TUMOR_REGISTRY3 = generate_tumor_registry3(),
  DISPENSING = generate_dispensing(),
  MED_ADMIN = generate_med_admin(),
  LAB_RESULT_CM = generate_lab_result_cm(),
  PROVIDER = generate_provider(),
  DEATH = generate_death()
)

# Write all CSVs using PCORNET_PATHS for consistent naming (handles LAB_RESULT_CM override)
walk2(names(fixture_tables), fixture_tables, function(table_name, table_data) {
  output_path <- PCORNET_PATHS[[table_name]]
  write_csv(table_data, output_path, na = "")
  message(glue("Wrote {nrow(table_data)} rows to {basename(output_path)}"))
})

message("\n", strrep("=", 60))
message("Fixture generation complete!")
message(glue("Generated {length(fixture_tables)} CSV files"))
message("Next: commit tests/generate_fixtures.R and tests/fixtures/*.csv")
message(strrep("=", 60))
