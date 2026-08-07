# Prepare every city in the RTCI national sample for the decomposition.

rtci_component_crimes <- c(
  "murder", "rape", "robbery", "assault", "burglary", "theft", "motor"
)
rtci_annualization <- 12

rtci_read_raw <- function(path = "src/data/raw/rtci_crime_trends.csv") {
  if (!file.exists(path)) stop("Data file does not exist: ", path)
  readr::read_csv(path, show_col_types = FALSE, name_repair = "unique")
}

rtci_read_metadata <- function(path = "src/data/raw/agency_metadata.csv") {
  if (!file.exists(path)) stop("City metadata does not exist: ", path)
  readr::read_csv(path, show_col_types = FALSE)
}

rtci_prepare_stacked <- function(raw,
                                 metadata,
                                 sample_only = TRUE,
                                 min_population = NULL) {
  count_cols <- paste0(rtci_component_crimes, "_total")
  required <- c("id", "size", "year", "month", "population", "sample", count_cols)
  missing <- setdiff(required, names(raw))
  if (length(missing) > 0) stop("Source data missing: ", paste(missing, collapse = ", "))

  keep <- raw$size == "all" & !is.na(raw$population) & raw$population > 0
  if (sample_only) keep <- keep & !is.na(raw$sample) & raw$sample == 1
  if (!is.null(min_population)) keep <- keep & raw$population >= min_population
  monthly <- raw[keep, , drop = FALSE]
  if (nrow(monthly) == 0) stop("No city rows remain after the sample filters.")
  monthly$date <- as.Date(sprintf("%04d-%02d-01", monthly$year, monthly$month))

  stacked <- tidyr::pivot_longer(
    monthly,
    cols = tidyselect::all_of(count_cols),
    names_to = "crime_type",
    values_to = "count",
    names_pattern = "(.*)_total$"
  ) |>
    dplyr::transmute(
      city_id = as.character(id),
      date,
      year = as.numeric(year),
      month_index = as.numeric(month),
      population = as.numeric(population),
      crime_type = factor(as.character(crime_type), levels = rtci_component_crimes),
      count = as.numeric(count)
    ) |>
    dplyr::filter(!is.na(count), is.finite(count), count >= 0, count <= population) |>
    dplyr::left_join(
      metadata |>
        dplyr::select(city_id, city_name, city_state, state, latitude, longitude),
      by = "city_id"
    ) |>
    dplyr::mutate(
      city_name = dplyr::coalesce(city_name, ""),
      city_name = ifelse(city_name == "" | city_name == city_id,
                         paste0("Unknown agency (", city_id, ")"), city_name),
      state = dplyr::coalesce(state, ""),
      city_label = ifelse(state == "", city_name, paste0(city_name, ", ", state)),
      trials = population,
      observed_rate = count / trials * 100000 * rtci_annualization,
      time_index = as.numeric(date - min(date)) / 30.4375,
      time_period = factor(date),
      city_id = factor(city_id),
      city_crime = interaction(city_id, crime_type, drop = TRUE),
      cell_id = interaction(city_id, crime_type, date, drop = TRUE)
    )

  if (nrow(stacked) == 0) stop("No valid city-month-crime observations remain.")
  stacked
}

rtci_validate_stacked <- function(data) {
  checks <- list(
    rows = nrow(data),
    cities = dplyr::n_distinct(data$city_id),
    crime_types = dplyr::n_distinct(data$crime_type),
    date_min = min(data$date),
    date_max = max(data$date),
    invalid_counts = sum(data$count < 0 | data$count > data$trials | is.na(data$count)),
    missing_names = sum(is.na(data$city_name) | data$city_name == ""),
    cities_missing_coordinates = dplyr::n_distinct(data$city_id[is.na(data$latitude) | is.na(data$longitude)])
  )
  if (checks$invalid_counts > 0 || checks$missing_names > 0) stop("Prepared data failed validation.")
  if (checks$cities_missing_coordinates > 0) {
    stop(checks$cities_missing_coordinates,
         " modeled cities have no cached coordinates; run src/download_data.R and src/build_metadata.R.")
  }
  checks
}

rtci_global_summary <- function(results) {
  results |>
    dplyr::group_by(date, crime_type) |>
    dplyr::summarise(
      trend_rate = stats::weighted.mean(trend_rate, population, na.rm = TRUE),
      global_rate = stats::weighted.mean(global_rate, population, na.rm = TRUE),
      city_fitted_rate = stats::weighted.mean(city_fitted_rate, population, na.rm = TRUE),
      seasonal_rate_delta = stats::weighted.mean(seasonal_rate_delta, population, na.rm = TRUE),
      time_effect_logit = dplyr::first(time_effect_logit),
      time_effect_rate_delta = dplyr::first(time_effect_rate_delta),
      global_time_rate = dplyr::first(global_time_rate),
      count = sum(count, na.rm = TRUE),
      population = sum(population, na.rm = TRUE),
      observed_rate = count / population * 100000 * rtci_annualization,
      observed_minus_global_rate = observed_rate - global_rate,
      global_residual_rate = time_effect_rate_delta,
      remainder_rate = time_effect_rate_delta,
      .groups = "drop"
    ) |>
    dplyr::arrange(crime_type, date)
}
