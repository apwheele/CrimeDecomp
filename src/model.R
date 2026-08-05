# Smooth global decomposition plus empirical city and city-by-crime terms.

rtci_model_formula <- function(time_k = 8, year_k = 5, include_city_effects = FALSE,
                               include_city_slopes = FALSE,
                               include_cell_overdispersion = FALSE) {
  terms <- c(
    "0 + crime_type",
    sprintf("s(time_index, by = crime_type, k = %d)", time_k),
    "s(month_index, by = crime_type, bs = 'cc', k = 12)"
  )
  if (include_city_effects) {
    terms <- c(terms, "s(city_id, bs = 're')", "s(city_crime, bs = 're')")
    if (include_city_slopes) terms <- c(terms, "s(city_crime, by = time_index, bs = 're')")
  }
  if (include_cell_overdispersion) terms <- c(terms, "s(cell_id, bs = 're')")
  stats::as.formula(paste("cbind(count, trials - count) ~", paste(terms, collapse = " + ")))
}

rtci_fit_model <- function(data,
                           time_k = 8,
                           year_k = 5,
                           include_city_effects = FALSE,
                           include_city_slopes = FALSE,
                           include_cell_overdispersion = FALSE,
                           nthreads = 4) {
  mgcv::bam(
    rtci_model_formula(time_k, year_k, include_city_effects, include_city_slopes, include_cell_overdispersion),
    data = data,
    family = stats::binomial(link = "logit"),
    method = "fREML",
    discrete = TRUE,
    nthreads = nthreads,
    gamma = 1.4,
    knots = list(month_index = c(0.5, 12.5))
  )
}

rtci_prediction_labels <- function(model) {
  labels <- vapply(model$smooth, function(x) x$label, character(1))
  list(
    city = labels[grepl("city", labels)],
    season = labels[grepl("month_index", labels)],
    cell = labels[grepl("cell_id", labels)],
    global = labels[grepl("city|cell_id", labels)],
    trend = labels[grepl("month_index|city|cell_id", labels)]
  )
}

rtci_clamp_probability <- function(x, eps = 1e-8) pmin(pmax(x, eps), 1 - eps)

rtci_add_predictions <- function(model, data) {
  labels <- rtci_prediction_labels(model)
  global_p <- stats::predict(model, newdata = data, type = "response", exclude = labels$global)
  trend_p <- stats::predict(model, newdata = data, type = "response", exclude = labels$trend)
  global_p <- rtci_clamp_probability(global_p)
  trend_p <- rtci_clamp_probability(trend_p)
  observed_p <- rtci_clamp_probability((data$count + 0.5) / (data$trials + 1))
  annualize <- 100000 * rtci_annualization

  base <- data |>
    dplyr::mutate(
      city_id = as.character(city_id),
      global_p = global_p,
      trend_p = trend_p,
      observed_p = observed_p,
      global_residual_logit_raw = stats::qlogis(observed_p) - stats::qlogis(global_p)
    )
  city_effects <- base |>
    dplyr::group_by(city_id) |>
    dplyr::summarise(
      city_effect_logit = stats::weighted.mean(global_residual_logit_raw, population, na.rm = TRUE),
      .groups = "drop"
    )
  city_crime_effects <- base |>
    dplyr::left_join(city_effects, by = "city_id") |>
    dplyr::mutate(city_crime_residual = global_residual_logit_raw - city_effect_logit) |>
    dplyr::group_by(city_id, crime_type) |>
    dplyr::summarise(
      city_crime_effect_logit = stats::weighted.mean(city_crime_residual, population, na.rm = TRUE),
      .groups = "drop"
    )

  base |>
    dplyr::left_join(city_effects, by = "city_id") |>
    dplyr::left_join(city_crime_effects, by = c("city_id", "crime_type")) |>
    dplyr::mutate(
      city_fitted_p = rtci_clamp_probability(stats::plogis(
        stats::qlogis(global_p) + city_effect_logit + city_crime_effect_logit
      )),
      overdispersion_logit_raw = stats::qlogis(observed_p) - stats::qlogis(city_fitted_p),
      trend_rate = trend_p * annualize,
      global_rate = global_p * annualize,
      city_fitted_rate = city_fitted_p * annualize,
      seasonal_rate_delta = (global_p - trend_p) * annualize,
      city_minus_global_logit = city_effect_logit + city_crime_effect_logit,
      overdispersion_rate_delta = (observed_p - city_fitted_p) * annualize
    ) |>
    dplyr::group_by(crime_type) |>
    dplyr::mutate(
      global_residual_logit = global_residual_logit_raw -
        stats::weighted.mean(global_residual_logit_raw, population, na.rm = TRUE)
    ) |>
    dplyr::ungroup() |>
    dplyr::group_by(city_id, crime_type) |>
    dplyr::mutate(
      overdispersion_logit = overdispersion_logit_raw -
        stats::weighted.mean(overdispersion_logit_raw, population, na.rm = TRUE)
    ) |>
    dplyr::ungroup()
}

rtci_city_summary <- function(results) {
  results |>
    dplyr::group_by(city_id, city_name, state, city_label, crime_type) |>
    dplyr::summarise(
      mean_city_minus_global_logit = mean(city_minus_global_logit, na.rm = TRUE),
      mean_abs_overdispersion_logit = mean(abs(overdispersion_logit), na.rm = TRUE),
      mean_rate = stats::weighted.mean(city_fitted_rate, population, na.rm = TRUE),
      population = max(population, na.rm = TRUE),
      latitude = dplyr::first(latitude),
      longitude = dplyr::first(longitude),
      .groups = "drop"
    )
}
