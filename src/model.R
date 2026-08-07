# Aggregated-binomial hierarchical trend/season models with city and time-period
# random intercepts, city-varying smooth deviations, and an observation-level
# random intercept corresponding to (1 | Row). The production backend is TMB;
# legacy bam/gamm4 helpers remain for sensitivity comparisons.

rtci_model_formula <- function(time_k = 10, city_time_k = 5, city_season_k = 6,
                               include_city_effects = TRUE,
                               include_city_smooths = TRUE,
                               include_cell_overdispersion = FALSE) {
  terms <- c(
    "crime_type",
    sprintf("s(time_index, by = crime_type, k = %d)", time_k),
    "s(month_index, by = crime_type, bs = 'cc', k = 12)"
  )
  if (include_city_effects) terms <- c(terms, "s(city_id, bs = 're')")
  terms <- c(terms, "s(time_period, crime_type, bs = 're')")
  if (include_city_smooths) {
    terms <- c(
      terms,
      sprintf("s(time_index, city_crime, bs = 'sz', k = %d)", city_time_k),
      sprintf(paste0("s(month_index, city_crime, bs = 'sz', k = %d, ",
                     "xt = list(bs = 'cc'))"), city_season_k)
    )
  }
  if (include_cell_overdispersion) terms <- c(terms, "s(cell_id, bs = 're')")
  stats::as.formula(paste("cbind(count, trials - count) ~", paste(terms, collapse = " + ")))
}

rtci_fit_model <- function(data,
                           time_k = 10,
                           city_time_k = 5,
                           city_season_k = 6,
                           include_city_effects = TRUE,
                           include_city_smooths = TRUE,
                           include_cell_overdispersion = FALSE,
                           nthreads = 4) {
  mgcv::bam(
    rtci_model_formula(time_k, city_time_k, city_season_k, include_city_effects,
                       include_city_smooths, include_cell_overdispersion),
    data = data,
    family = stats::binomial(link = "logit"),
    method = "fREML",
    discrete = TRUE,
    nthreads = nthreads,
    chunk.size = 1000,
    gc.level = 2,
    gamma = 1.4,
    knots = list(month_index = c(0.5, 12.5))
  )
}

rtci_crime_model_formula <- function(time_k = 10, city_time_k = 5,
                                     city_season_k = 6,
                                     include_city_effects = TRUE,
                                     include_city_smooths = TRUE,
                                     include_cell_overdispersion = FALSE) {
  terms <- c(
    "1",
    sprintf("s(time_index, k = %d)", time_k),
    "s(month_index, bs = 'cc', k = 12)"
  )
  if (include_city_effects) terms <- c(terms, "s(city_id, bs = 're')")
  terms <- c(terms, "s(time_period, bs = 're')")
  if (include_city_smooths) {
    terms <- c(
      terms,
      sprintf("s(time_index, city_id, bs = 'sz', k = %d)", city_time_k),
      sprintf(paste0("s(month_index, city_id, bs = 'sz', k = %d, ",
                     "xt = list(bs = 'cc'))"), city_season_k)
    )
  }
  if (include_cell_overdispersion) terms <- c(terms, "s(cell_id, bs = 're')")
  stats::as.formula(paste("cbind(count, trials - count) ~", paste(terms, collapse = " + ")))
}

rtci_fit_crime_model <- function(data,
                                 time_k = 10,
                                 city_time_k = 5,
                                 city_season_k = 6,
                                 include_city_effects = TRUE,
                                 include_city_smooths = TRUE,
                                 include_cell_overdispersion = FALSE,
                                 nthreads = 4) {
  mgcv::bam(
    rtci_crime_model_formula(time_k, city_time_k, city_season_k,
                             include_city_effects, include_city_smooths,
                             include_cell_overdispersion),
    data = data,
    family = stats::binomial(link = "logit"),
    method = "fREML",
    discrete = TRUE,
    nthreads = nthreads,
    chunk.size = 1000,
    gc.level = 2,
    gamma = 1.4,
    knots = list(month_index = c(0.5, 12.5))
  )
}

rtci_gamm4_crime_formula <- function(time_k = 10, city_time_k = 5,
                                     city_season_k = 6) {
  stats::as.formula(paste(
    "cbind(count, trials - count) ~ 1",
    sprintf("+ s(time_index, k = %d)", time_k),
    "+ s(month_index, bs = 'cc', k = 12)",
    sprintf("+ s(time_index, city_id, bs = 'fs', k = %d, m = 1)", city_time_k),
    sprintf(paste0("+ s(month_index, city_id, bs = 'fs', k = %d, m = 1, ",
                   "xt = list(bs = 'cc'))"), city_season_k)
  ))
}

rtci_make_basis_spec <- function(data, trend_df = 5, season_harmonics = 3) {
  if (trend_df < 2) stop("trend_df must be at least 2.")
  if (season_harmonics < 1) stop("season_harmonics must be at least 1.")
  reference <- splines::ns(as.numeric(data$time_index), df = trend_df,
                           intercept = FALSE)
  list(
    version = "natural-spline-fourier-v1",
    trend_df = as.integer(trend_df),
    trend_knots = unname(attr(reference, "knots")),
    trend_boundary_knots = unname(attr(reference, "Boundary.knots")),
    season_harmonics = as.integer(season_harmonics),
    trend_columns = paste0("trend_b", seq_len(ncol(reference))),
    season_columns = as.vector(rbind(
      paste0("season_s", seq_len(season_harmonics)),
      paste0("season_c", seq_len(season_harmonics))
    ))
  )
}

rtci_add_hierarchical_basis <- function(data, basis_spec) {
  trend <- splines::ns(
    as.numeric(data$time_index),
    knots = basis_spec$trend_knots,
    Boundary.knots = basis_spec$trend_boundary_knots,
    intercept = FALSE
  )
  if (ncol(trend) != length(basis_spec$trend_columns)) {
    stop("Trend basis does not match the cached basis specification.")
  }
  colnames(trend) <- basis_spec$trend_columns
  result <- cbind(data, trend)
  angle <- 2 * pi * (as.numeric(result$month_index) - 1) / 12
  for (harmonic in seq_len(basis_spec$season_harmonics)) {
    result[[paste0("season_s", harmonic)]] <- sin(harmonic * angle)
    result[[paste0("season_c", harmonic)]] <- cos(harmonic * angle)
  }
  city_levels <- if (is.factor(result$city_id)) levels(result$city_id) else
    sort(unique(as.character(result$city_id)))
  result$city_trend_group <- factor(as.character(result$city_id), levels = city_levels)
  result$city_season_group <- factor(as.character(result$city_id), levels = city_levels)
  result
}

rtci_glmmtmb_crime_formula <- function(basis_spec, include_cell_overdispersion = TRUE) {
  fixed_terms <- c(basis_spec$trend_columns, basis_spec$season_columns)
  terms <- c(
    fixed_terms,
    "(1 | city_id)",
    "(1 | time_period)",
    paste0("homdiag(0 + ", paste(basis_spec$trend_columns, collapse = " + "),
           " | city_trend_group)"),
    paste0("homdiag(0 + ", paste(basis_spec$season_columns, collapse = " + "),
           " | city_season_group)")
  )
  if (include_cell_overdispersion) terms <- c(terms, "(1 | cell_id)")
  stats::as.formula(paste(
    "cbind(count, trials - count) ~ 1 +",
    paste(terms, collapse = " + ")
  ))
}

rtci_fit_crime_model_tmb <- function(data, basis_spec,
                                     include_cell_overdispersion = TRUE) {
  if (!requireNamespace("glmmTMB", quietly = TRUE)) {
    stop("The production crime-by-crime fit requires the R package 'glmmTMB'.")
  }
  model_data <- rtci_add_hierarchical_basis(data, basis_spec)
  fit <- glmmTMB::glmmTMB(
    rtci_glmmtmb_crime_formula(basis_spec, include_cell_overdispersion),
    data = model_data,
    family = stats::binomial(link = "logit"),
    REML = TRUE,
    sparseX = c(cond = TRUE)
  )
  attr(fit, "rtci_basis_spec") <- basis_spec
  attr(fit, "rtci_include_cell") <- include_cell_overdispersion
  fit
}

rtci_tmb_components <- function(model, data) {
  if (!inherits(model, "glmmTMB")) stop("Expected a glmmTMB model.")
  basis_spec <- attr(model, "rtci_basis_spec")
  if (is.null(basis_spec)) stop("Saved model has no cached RTCI basis specification.")
  model_data <- rtci_add_hierarchical_basis(data, basis_spec)
  fixed <- glmmTMB::fixef(model)$cond
  intercept <- unname(fixed[["(Intercept)"]])
  fixed_contribution <- function(columns) {
    coefficients <- stats::setNames(rep(0, length(columns)), columns)
    retained <- intersect(columns, names(fixed))
    coefficients[retained] <- fixed[retained]
    as.numeric(as.matrix(model_data[, columns, drop = FALSE]) %*% coefficients)
  }
  trend_eta <- intercept + fixed_contribution(basis_spec$trend_columns)
  global_eta <- trend_eta + fixed_contribution(basis_spec$season_columns)

  random <- glmmTMB::ranef(model, condVar = FALSE)$cond
  random_intercept <- function(group, values) {
    table <- random[[group]]
    if (is.null(table)) return(rep(0, length(values)))
    unname(table[match(as.character(values), rownames(table)), "(Intercept)"])
  }
  random_slopes <- function(group, values, columns) {
    table <- random[[group]]
    if (is.null(table)) return(rep(0, length(values)))
    coefficients <- as.matrix(table[match(as.character(values), rownames(table)),
                                    columns, drop = FALSE])
    rowSums(as.matrix(model_data[, columns, drop = FALSE]) * coefficients)
  }
  city_intercept <- random_intercept("city_id", model_data$city_id)
  city_trend <- random_slopes("city_trend_group", model_data$city_trend_group,
                              basis_spec$trend_columns)
  city_season <- random_slopes("city_season_group", model_data$city_season_group,
                               basis_spec$season_columns)
  time_eta <- random_intercept("time_period", model_data$time_period)
  cell_eta <- random_intercept("cell_id", model_data$cell_id)
  city_eta <- global_eta + city_intercept + city_trend + city_season
  list(
    data = model_data,
    trend_eta = trend_eta,
    global_eta = global_eta,
    city_eta = city_eta,
    time_eta = time_eta,
    cell_eta = cell_eta,
    full_eta = city_eta + time_eta + cell_eta
  )
}

rtci_fit_crime_model_sparse <- function(data,
                                        time_k = 10,
                                        city_time_k = 5,
                                        city_season_k = 6,
                                        include_cell_overdispersion = TRUE) {
  if (!requireNamespace("gamm4", quietly = TRUE)) {
    stop("The sparse crime-by-crime fit requires the R package 'gamm4'.")
  }
  random_formula <- if (include_cell_overdispersion) {
    stats::as.formula("~ (1 | city_id) + (1 | time_period) + (1 | cell_id)")
  } else {
    stats::as.formula("~ (1 | city_id) + (1 | time_period)")
  }
  fit_control <- lme4::glmerControl(
    optimizer = "nloptwrap",
    calc.derivs = FALSE,
    check.nobs.vs.nlev = "ignore",
    check.nobs.vs.nRE = "ignore"
  )
  gamm4::gamm4(
    rtci_gamm4_crime_formula(time_k, city_time_k, city_season_k),
    random = random_formula,
    data = data,
    family = stats::binomial(link = "logit"),
    control = fit_control,
    knots = list(month_index = c(0.5, 12.5))
  )
}

rtci_gam_component <- function(model) {
  if (is.list(model) && all(c("gam", "mer") %in% names(model))) model$gam else model
}

rtci_prediction_labels <- function(model) {
  model <- rtci_gam_component(model)
  labels <- vapply(model$smooth, function(x) x$label, character(1))
  city_intercept <- labels[labels == "s(city_id)"]
  city_deviation <- labels[
    grepl("city_crime", labels, fixed = TRUE) |
      (grepl("city_id", labels, fixed = TRUE) & labels != "s(city_id)")
  ]
  cell <- labels[labels == "s(cell_id)"]
  time <- labels[grepl("time_period", labels, fixed = TRUE)]
  global_season <- labels[
    grepl("month_index", labels, fixed = TRUE) &
      !(labels %in% city_deviation)
  ]
  city_terms <- unique(c(city_intercept, city_deviation))
  list(
    city = city_terms,
    city_deviation = city_deviation,
    season = global_season,
    time = time,
    cell = cell,
    global = unique(c(city_terms, time, cell)),
    trend = unique(c(global_season, city_terms, time, cell))
  )
}

rtci_add_predictions <- function(model, data) {
  if (inherits(model, "glmmTMB")) {
    components <- rtci_tmb_components(model, data)
    global_p <- stats::plogis(components$global_eta)
    trend_p <- stats::plogis(components$trend_eta)
    city_fitted_p <- stats::plogis(components$city_eta)
    global_time_p <- stats::plogis(components$global_eta + components$time_eta)
    city_time_fitted_p <- stats::plogis(components$city_eta + components$time_eta)
    row_fitted_p <- stats::plogis(components$full_eta)
    annualize <- 100000 * rtci_annualization
    return(components$data |>
      dplyr::mutate(
        city_id = as.character(city_id),
        trend_rate = trend_p * annualize,
        global_rate = global_p * annualize,
        city_fitted_rate = city_fitted_p * annualize,
        global_time_rate = global_time_p * annualize,
        city_time_fitted_rate = city_time_fitted_p * annualize,
        seasonal_rate_delta = (global_p - trend_p) * annualize,
        city_minus_global_logit = components$city_eta - components$global_eta,
        time_effect_logit = components$time_eta,
        time_effect_rate_delta = (global_time_p - global_p) * annualize,
        global_residual_rate = time_effect_rate_delta,
        observed_minus_global_rate = observed_rate - global_rate,
        overdispersion_logit = components$cell_eta,
        row_effect_rate_delta = (row_fitted_p - city_time_fitted_p) * annualize,
        overdispersion_rate_delta = row_effect_rate_delta
      ))
  }
  labels <- rtci_prediction_labels(model)
  gam_model <- rtci_gam_component(model)
  global_eta <- stats::predict(gam_model, newdata = data, type = "link", exclude = labels$global)
  trend_eta <- stats::predict(gam_model, newdata = data, type = "link", exclude = labels$trend)
  city_eta <- stats::predict(gam_model, newdata = data, type = "link",
                             exclude = unique(c(labels$time, labels$cell)))
  time_eta <- rep(0, nrow(data))
  cell_eta <- rep(NA_real_, nrow(data))
  if (is.list(model) && all(c("gam", "mer") %in% names(model))) {
    random_effects <- lme4::ranef(model$mer)
    city_values <- random_effects$city_id[, "(Intercept)"]
    city_eta <- city_eta + unname(city_values[match(as.character(data$city_id), rownames(random_effects$city_id))])
    time_values <- random_effects$time_period[, "(Intercept)"]
    time_eta <- unname(time_values[match(as.character(data$time_period),
                                         rownames(random_effects$time_period))])
    if ("cell_id" %in% names(random_effects)) {
      cell_values <- random_effects$cell_id[, "(Intercept)"]
      cell_eta <- unname(cell_values[match(as.character(data$cell_id), rownames(random_effects$cell_id))])
    }
  } else {
    if (length(labels$time)) {
      time_fitted_eta <- stats::predict(gam_model, newdata = data, type = "link",
                                        exclude = labels$cell)
      time_eta <- time_fitted_eta - city_eta
    }
    if (length(labels$cell)) {
      full_eta <- stats::predict(gam_model, newdata = data, type = "link")
      cell_eta <- full_eta - city_eta - time_eta
    }
  }
  global_p <- stats::plogis(global_eta)
  trend_p <- stats::plogis(trend_eta)
  city_fitted_p <- stats::plogis(city_eta)
  global_time_p <- stats::plogis(global_eta + time_eta)
  city_time_fitted_p <- stats::plogis(city_eta + time_eta)
  row_fitted_p <- stats::plogis(city_eta + time_eta + dplyr::coalesce(cell_eta, 0))
  annualize <- 100000 * rtci_annualization

  data |>
    dplyr::mutate(
      city_id = as.character(city_id),
      trend_rate = trend_p * annualize,
      global_rate = global_p * annualize,
      city_fitted_rate = city_fitted_p * annualize,
      global_time_rate = global_time_p * annualize,
      city_time_fitted_rate = city_time_fitted_p * annualize,
      seasonal_rate_delta = (global_p - trend_p) * annualize,
      city_minus_global_logit = city_eta - global_eta,
      time_effect_logit = time_eta,
      time_effect_rate_delta = (global_time_p - global_p) * annualize,
      global_residual_rate = time_effect_rate_delta,
      observed_minus_global_rate = observed_rate - global_rate,
      overdispersion_logit = cell_eta,
      row_effect_rate_delta = (row_fitted_p - city_time_fitted_p) * annualize,
      overdispersion_rate_delta = row_effect_rate_delta
    )
}

rtci_city_summary <- function(results) {
  results |>
    dplyr::group_by(city_id, city_name, state, city_label, crime_type) |>
    dplyr::summarise(
      mean_city_minus_global_logit = mean(city_minus_global_logit, na.rm = TRUE),
      mean_abs_overdispersion_logit = if (all(is.na(overdispersion_logit))) NA_real_ else
        mean(abs(overdispersion_logit), na.rm = TRUE),
      mean_abs_residual_rate = mean(abs(overdispersion_rate_delta), na.rm = TRUE),
      mean_rate = stats::weighted.mean(city_fitted_rate, population, na.rm = TRUE),
      population = max(population, na.rm = TRUE),
      latitude = dplyr::first(latitude),
      longitude = dplyr::first(longitude),
      .groups = "drop"
    )
}
