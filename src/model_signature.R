rtci_model_signature <- function(
    input = "src/data/raw/rtci_crime_trends.csv",
    metadata_path = "src/data/raw/agency_metadata.csv",
    sample_only = TRUE,
    min_population = NULL,
    include_city_effects = TRUE,
    include_city_smooths = TRUE,
    time_k = 10,
    trend_df = 5,
    season_harmonics = 3,
    include_cell_overdispersion = TRUE) {
  signature_files <- c(input, metadata_path, "src/model.R", "src/data_prep.R")
  missing_files <- signature_files[!file.exists(signature_files)]
  if (length(missing_files)) {
    stop("Cannot compute the model signature; missing: ",
         paste(missing_files, collapse = ", "))
  }
  input_hashes <- unname(tools::md5sum(signature_files))
  paste(
    input_hashes,
    paste("sample_only", sample_only, sep = "="),
    paste("min_population", if (is.null(min_population)) "none" else min_population,
          sep = "="),
    paste("city_effects", include_city_effects, sep = "="),
    paste("city_smooths", include_city_smooths, sep = "="),
    paste("time_k", time_k, sep = "="),
    paste("trend_df", trend_df, sep = "="),
    paste("season_harmonics", season_harmonics, sep = "="),
    "model_spec=2026-08-07-glmmtmb-hierarchical-v1",
    "model_backend=glmmTMB",
    "time_period_effect=true",
    paste("overdispersion", include_cell_overdispersion, sep = "="),
    sep = "|"
  )
}

rtci_output_status <- function(expected_signature = rtci_model_signature()) {
  crimes <- c("murder", "rape", "robbery", "assault", "burglary", "theft", "motor")
  part_paths <- file.path("src", "data", "model", "parts", paste0(crimes, ".rds"))
  model_paths <- file.path(
    "src", "data", "model", "models", paste0(crimes, "_glmmtmb.rds")
  )
  merged_paths <- c(
    "src/data/model/decomposition.csv",
    "src/data/model/global_stl.csv",
    "src/data/model/city_summary.csv",
    "src/data/model/cities.csv",
    "src/data/model/model_metadata.json",
    "src/data/model/city_component_examples.csv",
    "src/data/model/latest_residual_se.csv"
  )
  required_paths <- c(part_paths, model_paths, merged_paths)
  missing_paths <- required_paths[!file.exists(required_paths)]
  if (length(missing_paths)) {
    return(list(
      current = FALSE,
      reason = paste("missing required outputs:", paste(missing_paths, collapse = ", "))
    ))
  }

  matching_checkpoints <- vapply(part_paths, function(path) {
    checkpoint <- tryCatch(readRDS(path), error = function(e) NULL)
    if (is.null(checkpoint) || is.null(checkpoint$run_signature)) {
      return(FALSE)
    }
    identical(checkpoint$run_signature, expected_signature)
  }, logical(1))
  if (!all(matching_checkpoints)) {
    return(list(current = FALSE, reason = "input or model signature changed"))
  }
  list(current = TRUE, reason = "all checkpoint signatures match")
}
