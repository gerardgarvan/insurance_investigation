# data/reference/zip5_centroid_zip9_crosswalk.csv — Derivation Methodology
# Phase 144, D-01
#
# Source: Census Bureau ZCTA 2020 Gazetteer file
#   URL: https://www2.census.gov/geo/docs/maps-data/data/gazetteer/2020_Gazetteer/2020_Gaz_zcta_national.zip
#   File inside zip: 2020_Gaz_zcta_national.txt (tab-delimited, has ZCTA5, INTPTLAT, INTPTLONG)
#
# Derivation steps (run interactively on HiPerGator):
#   1. Download and read the Gazetteer file; column GEOID = 5-digit ZCTA (same as ZIP5 for most ZCTAs)
#   2. Each ZCTA row has internal centroid lat/lon (INTPTLAT, INTPTLONG)
# 3. Map ZCTA5 -> representative ZIP9.
#
#    This step REQUIRES ZIP+4-level coordinates. USPS does not publish them, and the
#    Gazetteer centroid file does not contain them — it gives one centroid per ZCTA, not
#    a location per delivery segment.
#
#    Valid derivations, both requiring a source this repo does not yet have:
#      (a) A licensed ZIP+4 centroid file: for each ZCTA centroid, take the nearest ZIP+4.
#      (b) A geocoder that returns ZIP+4 for a lat/lon (USPS Address Validation API;
#          the Census Geocoder returns ZIP5 only).
#
#    DO NOT synthesise a ZIP9 by appending "0000" or any other constant to the ZIP5.
#    Such a value joins to no ADI record, carries no information, and would be recorded
#    as zip5_centroid — mislabelling a fabricated value as centroid-derived.
#
#    Until (a) or (b) is available, this crosswalk is not producible and the Tier 3
#    probe gate correctly returns input unchanged.
#
# Required output columns (exact names; script reads these by name):
#   ZIP5        character(5)   e.g. "32611"
#   centroid_zip9 character(9) e.g. "326111234"  (no hyphen, 9 digits, left-padded)
#                 The add-on MUST be a real delivery segment. Values ending "0000" are
#                 rejected by the loader guard -- see approximate_zip9() Tier 3.
#
# No other columns required. Rows where ZIP9 cannot be determined: omit the row (not NA).
# Deduplication: one row per ZIP5 (the representative/best ZIP9 for that ZIP5).
# Write with write.csv(x, "data/reference/zip5_centroid_zip9_crosswalk.csv", row.names = FALSE)
#
# Once staged, re-run R/116_encounter_ses_index.R to activate the Tier 3 column in the output.
