#!/usr/bin/env Rscript

local_r_library <- file.path("src", "data", "model", "rlib")
if (.Platform$OS.type == "windows" && dir.exists(local_r_library)) {
  .libPaths(c(normalizePath(local_r_library), .libPaths()))
}

source("src/data_prep.R")
source("src/model.R")
source("src/model_signature.R")
source("src/city_catalog.R")

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
include_city_effects <- as_bool(get_arg("city-effects", "true"))
include_city_smooths <- as_bool(get_arg("city-smooths", "true"))
include_cell_overdispersion <- as_bool(get_arg("overdispersion", "true"))
stacked_model <- as_bool(get_arg("stacked", "false"))
nthreads <- as.integer(get_arg("nthreads", "4"))
resume <- as_bool(get_arg("resume", "true"))
render_report <- as_bool(get_arg("render-report", "true"))
crime_arg <- get_arg("crime", "")
fit_only <- as_bool(get_arg("fit-only", "false"))
time_k <- as.integer(get_arg("time-k", "10"))
city_time_k <- as.integer(get_arg("city-time-k", "5"))
city_season_k <- as.integer(get_arg("city-season-k", "6"))
trend_df <- as.integer(get_arg("trend-df", "5"))
season_harmonics <- as.integer(get_arg("season-harmonics", "3"))

dir.create("src/data/model", recursive = TRUE, showWarnings = FALSE)
dir.create("src/data/model/models", recursive = TRUE, showWarnings = FALSE)
dir.create("src/data/app", recursive = TRUE, showWarnings = FALSE)

raw <- rtci_read_raw(input)
metadata <- rtci_read_metadata(metadata_path)
data <- rtci_prepare_stacked(raw, metadata, sample_only, min_population)
validation <- rtci_validate_stacked(data)
message("Prepared ", validation$rows, " observations from ", validation$cities, " cities.")

if (stacked_model) {
  model <- rtci_fit_model(
    data,
    time_k = time_k,
    city_time_k = city_time_k,
    city_season_k = city_season_k,
    include_city_effects = include_city_effects,
    include_city_smooths = include_city_smooths,
    include_cell_overdispersion = include_cell_overdispersion,
    nthreads = nthreads
  )
  results <- rtci_add_predictions(model, data)
  formulas <- list(stacked = paste(deparse(stats::formula(model)), collapse = " "))
  summary_text <- c("===== stacked =====", capture.output(summary(model)), "")
} else {
  basis_spec <- rtci_make_basis_spec(data, trend_df, season_harmonics)
  all_crime_names <- levels(data$crime_type)
  if (crime_arg != "" && !crime_arg %in% all_crime_names) {
    stop("Unknown --crime value: ", crime_arg, ". Expected one of: ",
         paste(all_crime_names, collapse = ", "))
  }
  crime_names <- if (crime_arg == "") all_crime_names else crime_arg
  part_dir <- normalizePath(file.path("src", "data", "model", "parts"),
                            winslash = "/", mustWork = FALSE)
  model_dir <- normalizePath(file.path("src", "data", "model", "models"),
                             winslash = "/", mustWork = FALSE)
  dir.create(part_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)
  run_signature <- rtci_model_signature(
    input = input,
    metadata_path = metadata_path,
    sample_only = sample_only,
    min_population = min_population,
    include_city_effects = include_city_effects,
    include_city_smooths = include_city_smooths,
    time_k = time_k,
    trend_df = trend_df,
    season_harmonics = season_harmonics,
    include_cell_overdispersion = include_cell_overdispersion
  )
  valid_tmb_model <- function(fit) {
    inherits(fit, "glmmTMB") &&
      !is.null(attr(fit, "rtci_basis_spec")) &&
      identical(attr(fit, "run_signature"), run_signature) &&
      isTRUE(fit$fit$convergence == 0) && isTRUE(fit$sdr$pdHess)
  }
  fit_one_crime <- function(crime) {
    part_path <- file.path(part_dir, paste0(crime, ".rds"))
    model_path <- file.path(model_dir, paste0(crime, "_glmmtmb.rds"))
    log_path <- file.path(part_dir, paste0(crime, ".log"))
    append_log <- function(...) {
      cat(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), " ", ...,
          "\n", file = log_path, append = TRUE, sep = "")
    }
    if (resume && file.exists(part_path)) {
      saved <- tryCatch(readRDS(part_path), error = function(e) NULL)
      saved_model <- if (file.exists(model_path)) {
        tryCatch(readRDS(model_path), error = function(e) NULL)
      } else {
        NULL
      }
      if (!is.null(saved) && identical(saved$run_signature, run_signature) &&
          !is.null(saved_model) &&
          valid_tmb_model(saved_model)) {
        rm(saved_model)
        append_log("checkpoint reused")
        return(list(ok = TRUE, crime = crime, path = part_path, reused = TRUE))
      }
      rm(saved_model)
    }
    saved_fit <- NULL
    if (resume && file.exists(model_path)) {
      saved_fit <- tryCatch(readRDS(model_path), error = function(e) NULL)
      if (is.null(saved_fit) || !valid_tmb_model(saved_fit)) {
        saved_fit <- NULL
      }
    }
    if (is.null(saved_fit) && file.exists(model_path)) {
      unlink(model_path)
      if (file.exists(model_path)) {
        stop("Could not remove an invalid prior model object: ", model_path)
      }
    }
    writeLines(paste(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
                     if (is.null(saved_fit)) "fit started" else
                       "saved model object reloaded; rebuilding checkpoint"),
               log_path)
    tryCatch({
      crime_data <- droplevels(data[data$crime_type == crime, , drop = FALSE])
      if (is.null(saved_fit)) {
        fit <- rtci_fit_crime_model_tmb(
          crime_data,
          basis_spec,
          include_cell_overdispersion = include_cell_overdispersion
        )
        attr(fit, "run_signature") <- run_signature
        temporary_model_path <- paste0(model_path, ".", Sys.getpid(), ".tmp")
        saveRDS(fit, temporary_model_path, compress = "gzip")
        rm(fit)
        invisible(gc())
        verified_fit <- readRDS(temporary_model_path)
        if (!valid_tmb_model(verified_fit)) {
          stop("Temporary fitted model failed reload verification: ",
               temporary_model_path)
        }
        verified_predictions <- rtci_add_predictions(verified_fit, crime_data)
        if (nrow(verified_predictions) != nrow(crime_data) ||
            any(!is.finite(verified_predictions$city_time_fitted_rate))) {
          stop("Temporary fitted model failed finite prediction verification: ",
               temporary_model_path)
        }
        rm(verified_predictions)
        if (!file.rename(temporary_model_path, model_path)) {
          stop("Could not move fitted model object into place: ", model_path)
        }
        fit <- verified_fit
        rm(verified_fit)
        if (!valid_tmb_model(fit)) {
          stop("Saved fitted model failed reload verification: ", model_path)
        }
        append_log("fitted model object saved and reload-verified")
      } else {
        fit <- saved_fit
        rm(saved_fit)
      }
      record <- list(
        run_signature = run_signature,
        crime = crime,
        completed_at = format(Sys.time(), tz = "UTC"),
        model_path = model_path,
        results = rtci_add_predictions(fit, crime_data),
        formula = paste(deparse(stats::formula(fit)), collapse = " "),
        summary = capture.output(summary(fit))
      )
      temporary_path <- paste0(part_path, ".", Sys.getpid(), ".tmp")
      saveRDS(record, temporary_path, compress = "xz")
      if (!file.rename(temporary_path, part_path)) {
        stop("Could not move completed checkpoint into place: ", part_path)
      }
      append_log("fit completed and checkpoint saved")
      list(ok = TRUE, crime = crime, path = part_path, reused = FALSE)
    }, error = function(e) {
      append_log("ERROR: ", conditionMessage(e))
      list(ok = FALSE, crime = crime, path = part_path,
           message = conditionMessage(e))
    })
  }
  for (crime in crime_names) {
    part_path <- file.path(part_dir, paste0(crime, ".rds"))
    valid_checkpoint <- FALSE
    if (resume && file.exists(part_path)) {
      saved <- tryCatch(readRDS(part_path), error = function(e) NULL)
      expected_model_path <- file.path(model_dir, paste0(crime, "_glmmtmb.rds"))
      saved_model <- if (file.exists(expected_model_path)) {
        tryCatch(readRDS(expected_model_path), error = function(e) NULL)
      } else {
        NULL
      }
      valid_checkpoint <- !is.null(saved) &&
        identical(saved$run_signature, run_signature) &&
        !is.null(saved_model) &&
        valid_tmb_model(saved_model)
      rm(saved_model)
    }
    if (!valid_checkpoint) {
      writeLines(paste(format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
                       "queued for current run"),
                 file.path(part_dir, paste0(crime, ".log")))
    }
  }
  message("Fitting ", length(crime_names), " crime models sequentially...")
  message("Progress is checkpointed in ", part_dir)
  statuses <- lapply(crime_names, fit_one_crime)
  failures <- statuses[!vapply(statuses, `[[`, logical(1), "ok")]
  if (length(failures)) {
    details <- vapply(failures, function(x) paste0(x$crime, ": ", x$message), character(1))
    stop("One or more crime models failed; completed checkpoints were retained.\n",
         paste(details, collapse = "\n"))
  }
  if (fit_only) {
    message("Requested crime model(s) completed and reload-verified; fit-only run finished.")
    quit(save = "no", status = 0)
  }
  records <- lapply(statuses, function(x) readRDS(x$path))
  names(records) <- crime_names
  results <- dplyr::bind_rows(lapply(records, `[[`, "results"))
  formulas <- lapply(records, `[[`, "formula")
  model_files <- stats::setNames(lapply(records, `[[`, "model_path"), crime_names)
  summary_text <- unlist(lapply(names(records), function(x) {
    c(paste0("===== ", x, " ====="), records[[x]]$summary, "")
  }))
}
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
    city_fitted_rate, global_time_rate, city_time_fitted_rate,
    seasonal_rate_delta, city_minus_global_logit, time_effect_logit,
    time_effect_rate_delta, global_residual_rate, observed_minus_global_rate,
    overdispersion_logit, row_effect_rate_delta, overdispersion_rate_delta
  )

agency_types <- rtci_read_agency_types()
cities <- rtci_build_city_catalog(
  raw, metadata, agency_types, sample_only, min_population
)

readr::write_csv(decomposition, "src/data/model/decomposition.csv")
readr::write_csv(global, "src/data/model/global_stl.csv")
readr::write_csv(city_summary |> dplyr::mutate(city_id = as.character(city_id)),
                 "src/data/model/city_summary.csv")
rtci_write_city_catalog(cities)
readr::write_csv(decomposition, "src/data/app/decomposition.csv")
readr::write_csv(global, "src/data/app/global_stl.csv")
readr::write_csv(city_summary |> dplyr::mutate(city_id = as.character(city_id)), "src/data/app/city_summary.csv")
for (crime in unique(decomposition$crime_type)) {
  readr::write_csv(
    decomposition[decomposition$crime_type == crime, , drop = FALSE],
    file.path("src/data/app", paste0("decomposition_", crime, ".csv"))
  )
}

model_metadata <- list(
  formulas = formulas,
  model_strategy = if (stacked_model) "single stacked bam model" else
    "one standard-binomial hierarchical glmmTMB model per crime type",
  model_backend = if (stacked_model) "mgcv::bam" else "glmmTMB::glmmTMB",
  saved_model_files = if (stacked_model) NULL else model_files,
  rows = nrow(data),
  cities = dplyr::n_distinct(data$city_id),
  crime_types = levels(data$crime_type),
  min_population = min_population,
  annualization = rtci_annualization,
  include_city_effects = include_city_effects,
  include_city_smooths = include_city_smooths,
  include_cell_overdispersion = include_cell_overdispersion,
  include_time_period_effect = TRUE,
  city_terms = paste(
    "city random intercept plus shared-variance natural-spline trend",
    "and cyclic Fourier seasonal deviations"
  ),
  trend_basis = if (stacked_model) NULL else basis_spec,
  generated_at = format(Sys.time(), tz = "UTC")
)
jsonlite::write_json(model_metadata, "src/data/model/model_metadata.json", pretty = TRUE, auto_unbox = TRUE)
writeLines(summary_text, "src/data/model/model_summary.txt")
message("Wrote global_stl.csv, decomposition.csv, city_summary.csv, and cities.csv.")

if (!stacked_model) {
  message("Building exact city trend, seasonal, and residual comparison files...")
  source("src/build_city_examples.R")
}

if (render_report) {
  message("Rendering paper.qmd to PDF and GitHub-flavored Markdown...")
  render_status <- system2("quarto", c("render", "paper.qmd", "--to", "all"))
  if (!identical(render_status, 0L)) {
    stop("Model outputs were written, but Quarto report rendering failed with status ",
         render_status, ".")
  }
  markdown_images <- list.files(
    file.path("output", "markdown", "images"),
    pattern = "[.]png$",
    full.names = TRUE
  )
  if (!file.exists("paper.pdf") || !file.exists("paper.md") ||
      length(markdown_images) == 0L) {
    stop("Quarto completed without producing paper.pdf, paper.md, and Markdown images.")
  }
  message("Rendered paper.pdf, paper.md, and the Markdown images.")
}
