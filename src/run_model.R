#!/usr/bin/env Rscript

source("src/data_prep.R")
source("src/model.R")

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit) == 0) default else sub(paste0("^--", name, "="), "", hit[[1]])
}
as_bool <- function(x) tolower(x) %in% c("1", "true", "yes", "y")

input <- get_arg("input", "src/data/raw/rtci_crime_trends.csv")
metadata_path <- get_arg("metadata", "src/data/raw/agency_metadata.csv")
sample_only <- as_bool(get_arg("sample-only", "true"))
min_population_arg <- get_arg("min-population", "")
min_population <- if (min_population_arg == "") NULL else as.numeric(min_population_arg)
include_city_effects <- as_bool(get_arg("city-effects", "false"))
include_city_slopes <- as_bool(get_arg("city-slopes", "false"))
include_cell_overdispersion <- as_bool(get_arg("overdispersion", "false"))
nthreads <- as.integer(get_arg("nthreads", "4"))
time_k <- as.integer(get_arg("time-k", "8"))
year_k <- as.integer(get_arg("year-k", "5"))

dir.create("src/data/model", recursive = TRUE, showWarnings = FALSE)
dir.create("src/data/app", recursive = TRUE, showWarnings = FALSE)

raw <- rtci_read_raw(input)
metadata <- rtci_read_metadata(metadata_path)
data <- rtci_prepare_stacked(raw, metadata, sample_only, min_population)
validation <- rtci_validate_stacked(data)
message("Prepared ", validation$rows, " observations from ", validation$cities, " cities.")

model <- rtci_fit_model(
  data,
  time_k = time_k,
  year_k = year_k,
  include_city_effects = include_city_effects,
  include_city_slopes = include_city_slopes,
  include_cell_overdispersion = include_cell_overdispersion,
  nthreads = nthreads
)
results <- rtci_add_predictions(model, data)
global <- rtci_global_summary(results)
city_summary <- rtci_city_summary(results)

decomposition <- results |>
  dplyr::mutate(
    city_id = as.character(city_id),
    crime_type = as.character(crime_type),
    date = as.character(date)
  ) |>
  dplyr::select(
    date, city_id, city_name, state, city_label, latitude, longitude,
    crime_type, population, count, observed_rate, trend_rate, global_rate,
    city_fitted_rate, seasonal_rate_delta, city_minus_global_logit,
    city_effect_logit, city_crime_effect_logit,
    global_residual_logit, overdispersion_logit, overdispersion_rate_delta
  )

city_catalog <- raw |>
  dplyr::filter(size == "all", !is.na(population), population > 0,
                if (sample_only) !is.na(sample) & sample == 1 else TRUE,
                if (is.null(min_population)) TRUE else population >= min_population) |>
  dplyr::transmute(city_id = as.character(id), population = as.numeric(population)) |>
  dplyr::distinct(city_id, .keep_all = TRUE) |>
  dplyr::left_join(metadata |>
                     dplyr::select(city_id, city_name, state, latitude, longitude),
                   by = "city_id") |>
  dplyr::mutate(
    city_name = dplyr::coalesce(city_name, ""),
    city_name = ifelse(city_name == "" | city_name == city_id,
                       paste0("Unknown agency (", city_id, ")"), city_name),
    state = dplyr::coalesce(state, ""),
    city_label = ifelse(state == "", city_name, paste0(city_name, ", ", state))
  ) |>
  dplyr::select(city_id, city_name, state, city_label, latitude, longitude, population)
cities <- city_catalog

readr::write_csv(decomposition, "src/data/model/decomposition.csv")
readr::write_csv(global, "src/data/model/global_stl.csv")
readr::write_csv(city_summary |> dplyr::mutate(city_id = as.character(city_id)),
                 "src/data/model/city_summary.csv")
readr::write_csv(cities |> dplyr::mutate(city_id = as.character(city_id)), "src/data/model/cities.csv")
readr::write_csv(decomposition, "src/data/app/decomposition.csv")
readr::write_csv(global, "src/data/app/global_stl.csv")
readr::write_csv(city_summary |> dplyr::mutate(city_id = as.character(city_id)), "src/data/app/city_summary.csv")
readr::write_csv(cities |> dplyr::mutate(city_id = as.character(city_id)), "src/data/app/cities.csv")

model_metadata <- list(
  formula = paste(deparse(stats::formula(model)), collapse = " "),
  rows = nrow(data),
  cities = dplyr::n_distinct(data$city_id),
  crime_types = levels(data$crime_type),
  min_population = min_population,
  annualization = rtci_annualization,
  include_city_effects = include_city_effects,
  include_city_slopes = include_city_slopes,
  include_cell_overdispersion = include_cell_overdispersion,
  city_terms = "weighted city and city-by-crime logit intercepts after global fit",
  generated_at = format(Sys.time(), tz = "UTC")
)
jsonlite::write_json(model_metadata, "src/data/model/model_metadata.json", pretty = TRUE, auto_unbox = TRUE)
writeLines(capture.output(summary(model)), "src/data/model/model_summary.txt")
message("Wrote global_stl.csv, decomposition.csv, city_summary.csv, and cities.csv.")
