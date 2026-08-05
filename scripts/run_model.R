#!/usr/bin/env Rscript

source("src/data_prep.R")
source("src/model.R")

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit) == 0) default else sub(paste0("^--", name, "="), "", hit[[1]])
}
as_bool <- function(x) tolower(x) %in% c("1", "true", "yes", "y")

input <- get_arg("input", "data/raw/rtci_crime_trends.csv")
min_population <- as.numeric(get_arg("min-population", "250000"))
sample_only <- as_bool(get_arg("sample-only", "true"))
include_overdispersion <- as_bool(get_arg("overdispersion", "true"))
outlier_threshold <- as.numeric(get_arg("outlier-threshold", "3"))
nthreads <- as.integer(get_arg("nthreads", "2"))
time_k <- as.integer(get_arg("time-k", "12"))
year_k <- as.integer(get_arg("year-k", "5"))

dir.create("output/model", recursive = TRUE, showWarnings = FALSE)
dir.create("app/data", recursive = TRUE, showWarnings = FALSE)

raw <- rtci_read_raw(input)
data <- rtci_prepare_stacked(raw, min_population = min_population, sample_only = sample_only)
validation <- rtci_validate_stacked(data)
message("Prepared ", validation$rows, " stacked observations from ",
        validation$agencies, " agencies.")

model <- rtci_fit_model(
  data,
  time_k = time_k,
  year_k = year_k,
  include_overdispersion = include_overdispersion,
  nthreads = nthreads
)
results <- rtci_add_predictions(model, data, outlier_threshold = outlier_threshold)

global <- rtci_global_summary(results)
agency_summary <- results |>
  dplyr::group_by(agency_id, crime_type) |>
  dplyr::summarise(
    n_months = dplyr::n(),
    mean_deviation = mean(deviation_logit, na.rm = TRUE),
    max_abs_deviation = max(abs(deviation_logit), na.rm = TRUE),
    outlier_months = sum(outlier_flag, na.rm = TRUE),
    mean_abs_residual = mean(abs(pearson_residual), na.rm = TRUE),
    .groups = "drop"
  ) |>
  dplyr::arrange(crime_type, dplyr::desc(max_abs_deviation))

decomposition <- results |>
  dplyr::mutate(
    agency_id = as.character(agency_id),
    crime_type = as.character(crime_type),
    date = as.character(date)
  ) |>
  dplyr::select(
    date, agency_id, crime_type, population, count, observed_rate,
    global_rate, fitted_rate, deviation_logit, logit_residual,
    pearson_residual, outlier_flag
  )

readr::write_csv(decomposition, "output/model/decomposition.csv")
readr::write_csv(global, "output/model/global_trends.csv")
readr::write_csv(agency_summary |> dplyr::mutate(agency_id = as.character(agency_id)),
                 "output/model/agency_summary.csv")
readr::write_csv(decomposition, "app/data/decomposition.csv")
readr::write_csv(global, "app/data/global_trends.csv")
readr::write_csv(agency_summary |> dplyr::mutate(agency_id = as.character(agency_id)),
                 "app/data/agency_summary.csv")

metadata <- rtci_model_metadata(model, data, include_overdispersion)
metadata$min_population <- min_population
metadata$outlier_threshold <- outlier_threshold
jsonlite::write_json(metadata, "output/model/model_metadata.json", pretty = TRUE, auto_unbox = TRUE)
writeLines(capture.output(summary(model)), "output/model/model_summary.txt")
saveRDS(list(global = global, agency_summary = agency_summary),
        "output/model/analysis_results.rds")

message("Model outputs written to output/model and app/data.")
