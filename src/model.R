# Aggregated-binomial GAM for a stacked monthly crime decomposition.

rtci_model_formula <- function(time_k = 20, year_k = 6, agency_time_k = 5,
                               include_overdispersion = TRUE) {
  terms <- c(
    "0 + crime_type",
    sprintf("s(time_index, by = crime_type, k = %d)", time_k),
    sprintf("s(year, by = crime_type, k = %d)", year_k),
    "s(month_index, by = crime_type, bs = 'cc', k = 12)",
    "s(agency_id, bs = 're')",
    "s(agency_crime, bs = 're')",
    "s(agency_crime, by = time_index, bs = 're')"
  )
  if (include_overdispersion) terms <- c(terms, "s(row_id, bs = 're')")
  stats::as.formula(paste("cbind(count, trials - count) ~", paste(terms, collapse = " + ")))
}

rtci_fit_model <- function(data,
                           time_k = 12,
                           year_k = 5,
                           agency_time_k = 5,
                           include_overdispersion = TRUE,
                           nthreads = 2) {
  formula <- rtci_model_formula(time_k, year_k, agency_time_k, include_overdispersion)
  mgcv::bam(
    formula,
    data = data,
    family = stats::binomial(link = "logit"),
    method = "fREML",
    discrete = TRUE,
    nthreads = nthreads,
    gamma = 1.2,
    knots = list(month_index = c(0.5, 12.5))
  )
}

rtci_prediction_exclusions <- function(model) {
  labels <- vapply(model$smooth, function(x) x$label, character(1))
  list(
    agency = labels[grepl("agency", labels)],
    row = labels[grepl("row_id", labels)],
    global = labels[grepl("agency|row_id", labels)]
  )
}

rtci_clamp_probability <- function(x, eps = 1e-8) pmin(pmax(x, eps), 1 - eps)

rtci_add_predictions <- function(model, data, outlier_threshold = 3) {
  exclusions <- rtci_prediction_exclusions(model)
  full_p <- stats::predict(model, newdata = data, type = "response",
                           exclude = exclusions$row)
  global_p <- stats::predict(model, newdata = data, type = "response",
                             exclude = exclusions$global)
  full_p <- rtci_clamp_probability(full_p)
  global_p <- rtci_clamp_probability(global_p)

  fitted_logit <- stats::qlogis(full_p)
  global_logit <- stats::qlogis(global_p)
  observed_p <- rtci_clamp_probability(data$count / data$trials)
  pearson <- (data$count - data$trials * full_p) /
    sqrt(pmax(data$trials * full_p * (1 - full_p), 1e-8))

  data |>
    dplyr::mutate(
      fitted_rate = full_p * 100000,
      global_rate = global_p * 100000,
      deviation_logit = fitted_logit - global_logit,
      logit_residual = stats::qlogis(observed_p) - fitted_logit,
      pearson_residual = pearson,
      outlier_flag = abs(pearson_residual) >= outlier_threshold
    )
}

rtci_model_metadata <- function(model, data, include_overdispersion) {
  list(
    formula = paste(deparse(stats::formula(model)), collapse = " "),
    rows = nrow(data),
    agencies = dplyr::n_distinct(data$agency_id),
    crime_types = levels(data$crime_type),
    include_overdispersion = include_overdispersion,
    smooths = vapply(model$smooth, function(x) x$label, character(1)),
    generated_at = format(Sys.time(), tz = "UTC")
  )
}
