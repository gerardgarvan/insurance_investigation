# Phase 204: QC table helper + supportive-care exclusion (synthetic data only)
test_that("build_p204_name_qc keeps only name rows and suppresses small cells", {
  ma <- dplyr::tibble(
    ID = c(rep(paste0("p", 1:12), 1), "p1", "p2"),
    treatment_date = as.Date("2020-01-01") + seq_len(14),
    triggering_code = c(rep("NAME:Doxorubicin", 12), "NAME:Rituximab", "NAME:Rituximab"),
    raw_med_name = c(rep("ADRIAMYCIN 50 MG", 12), "RITUXAN", "RITUXAN"),
    source = c(rep("MED_ADMIN_NAME", 14))
  )
  ma <- dplyr::bind_rows(ma, dplyr::tibble(
    ID = "p99", treatment_date = as.Date("2020-02-01"), triggering_code = "123",
    raw_med_name = "X", source = "MED_ADMIN (RX)"))
  qc <- build_p204_name_qc(ma)
  expect_equal(nrow(qc), 2)
  expect_equal(qc$n_records_disp[qc$canonical == "Doxorubicin"], "12")
  expect_equal(qc$n_records_disp[qc$canonical == "Rituximab"], "<11")
  expect_equal(qc$n_patients_disp[qc$canonical == "Rituximab"], "<11")
})

test_that("supportive-care names are defined and include G-CSF", {
  skip_if_not(exists("SUPPORTIVE_CARE_NAMES"), "config not sourced")
  expect_true(all(c("pegfilgrastim", "filgrastim") %in% SUPPORTIVE_CARE_NAMES))
  expect_false(any(c("doxorubicin", "rituximab", "methotrexate") %in% SUPPORTIVE_CARE_NAMES))
})
