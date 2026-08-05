# Data preparation for the monthly crime decomposition.

rtci_component_crimes <- c(
  "murder", "rape", "robbery", "assault", "burglary", "theft", "motor"
)

rtci_read_raw <- function(path) {
  if (!file.exists(path)) stop("Data file does not exist: ", path)
  readr::read_csv(path, show_col_types = FALSE, name_repair = "unique")
}

rtci_prepare_stacked <- function(raw,
                                  min_population = 100000,
                                  sample_only = TRUE) {
  required <- c("id", "size", "year", "month", "population", "sample",
                paste0(rtci_component_crimes, "_total"))
  missing <- setdiff(required, names(raw))
  if (length(missing) > 0) {
    stop("The source data is missing columns: ", paste(missing, collapse = ", "))
  }

  keep_sample <- if (sample_only) !is.na(raw$sample) & raw$sample == 1 else TRUE
  monthly <- raw[raw$size == "all" & keep_sample &
                   !is.na(raw$population) & raw$population >= min_population, , drop = FALSE]
  if (nrow(monthly) == 0) stop("No rows remain after the population/sample filters.")

  monthly$date <- as.Date(sprintf("%04d-%02d-01", monthly$year, monthly$month))
  monthly <- monthly[order(monthly$date, monthly$id), , drop = FALSE]

  count_cols <- paste0(rtci_component_crimes, "_total")
  stacked <- tidyr::pivot_longer(
    monthly,
    cols = tidyselect::all_of(count_cols),
    names_to = "crime_type",
    values_to = "count",
    names_pattern = "(.*)_total$"
  )

  stacked <- stacked |>
    dplyr::transmute(
      agency_id = as.character(id),
      date,
      year = as.numeric(year),
      month_index = as.numeric(month),
      population = as.numeric(population),
      crime_type = factor(as.character(crime_type), levels = rtci_component_crimes),
      count = as.numeric(count)
    ) |>
    dplyr::filter(
      !is.na(count), is.finite(count), count >= 0,
      !is.na(population), population > 0,
      count <= population
    ) |>
    dplyr::mutate(
      trials = population,
      observed_rate = count / trials * 100000,
      time_index = as.numeric(date - min(date)) / 30.4375,
      agency_id = factor(agency_id),
      agency_crime = interaction(agency_id, crime_type, drop = TRUE),
      # One overdispersion shock per agency-month, shared across crimes in
      # the stacked row. This avoids seven residual parameters for one month.
      row_id = interaction(agency_id, date, drop = TRUE)
    )

  if (nrow(stacked) == 0) stop("No valid count observations remain after preparation.")
  stacked
}

rtci_validate_stacked <- function(data) {
  checks <- list(
    rows = nrow(data),
    agencies = dplyr::n_distinct(data$agency_id),
    crime_types = dplyr::n_distinct(data$crime_type),
    date_min = min(data$date),
    date_max = max(data$date),
    invalid_counts = sum(data$count < 0 | data$count > data$trials | is.na(data$count)),
    missing_population = sum(is.na(data$population) | data$population <= 0)
  )
  if (checks$invalid_counts > 0 || checks$missing_population > 0) {
    stop("Prepared data failed validation.")
  }
  checks
}

rtci_global_summary <- function(results) {
  results |>
    dplyr::group_by(date, crime_type) |>
    dplyr::summarise(
      global_rate = stats::weighted.mean(global_rate, population, na.rm = TRUE),
      fitted_rate = stats::weighted.mean(fitted_rate, population, na.rm = TRUE),
      mean_pearson_residual = stats::weighted.mean(pearson_residual, population, na.rm = TRUE),
      count = sum(count, na.rm = TRUE),
      population = sum(population, na.rm = TRUE),
      observed_rate = count / population * 100000,
      .groups = "drop"
    ) |>
    dplyr::arrange(crime_type, date)
}
