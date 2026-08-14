source("model_signature.R")

testthat::test_that("output freshness follows content signatures", {
  root <- tempfile("rtci-signature-test-")
  dir.create(file.path(root, "src", "data", "raw"), recursive = TRUE)
  dir.create(file.path(root, "src", "data", "model", "parts"), recursive = TRUE)
  dir.create(file.path(root, "src", "data", "model", "models"), recursive = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)
  old_working_directory <- setwd(root)
  on.exit(setwd(old_working_directory), add = TRUE)

  writeLines("raw-v1", "src/data/raw/rtci_crime_trends.csv")
  writeLines("metadata-v1", "src/data/raw/agency_metadata.csv")
  writeLines("model-v1", "src/model.R")
  writeLines("prep-v1", "src/data_prep.R")
  signature <- rtci_model_signature()

  crimes <- c("murder", "rape", "robbery", "assault", "burglary", "theft", "motor")
  for (crime in crimes) {
    saveRDS(
      list(run_signature = signature),
      file.path("src/data/model/parts", paste0(crime, ".rds"))
    )
    writeLines(
      "model-placeholder",
      file.path("src/data/model/models", paste0(crime, "_glmmtmb.rds"))
    )
  }
  merged_paths <- c(
    "decomposition.csv", "global_stl.csv", "city_summary.csv", "cities.csv",
    "model_metadata.json", "city_component_examples.csv", "latest_residual_se.csv"
  )
  for (path in merged_paths) {
    writeLines("output-placeholder", file.path("src/data/model", path))
  }

  testthat::expect_true(rtci_output_status(signature)$current)
  writeLines("raw-v2", "src/data/raw/rtci_crime_trends.csv")
  changed_signature <- rtci_model_signature()
  testthat::expect_false(rtci_output_status(changed_signature)$current)
  testthat::expect_identical(
    rtci_output_status(changed_signature)$reason,
    "input or model signature changed"
  )
})
