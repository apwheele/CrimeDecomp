rtci_extract_city_components <- function(model, results, city_id, crime_type,
                                         random_effects = NULL) {
  if (!requireNamespace("glmmTMB", quietly = TRUE)) {
    stop("City component extraction requires glmmTMB.")
  }
  basis <- attr(model, "rtci_basis_spec")
  if (is.null(basis)) stop("Model has no cached RTCI basis specification.")
  d <- results |>
    dplyr::filter(.data$city_id == .env$city_id,
                  as.character(.data$crime_type) == .env$crime_type) |>
    dplyr::arrange(date)
  if (!nrow(d)) stop("No model rows for ", city_id, " and ", crime_type, ".")

  fixed <- glmmTMB::fixef(model)$cond
  fixed_part <- function(columns) {
    coefficients <- stats::setNames(rep(0, length(columns)), columns)
    retained <- intersect(columns, names(fixed))
    coefficients[retained] <- fixed[retained]
    as.numeric(as.matrix(d[, columns, drop = FALSE]) %*% coefficients)
  }
  random <- if (is.null(random_effects)) {
    glmmTMB::ranef(model, condVar = TRUE)$cond
  } else {
    random_effects
  }
  random_intercept <- function(group, values) {
    table <- random[[group]]
    unname(table[match(as.character(values), rownames(table)), "(Intercept)"])
  }
  random_slopes <- function(group, values, columns) {
    table <- random[[group]]
    coefficients <- as.matrix(table[
      match(as.character(values), rownames(table)), columns, drop = FALSE
    ])
    rowSums(as.matrix(d[, columns, drop = FALSE]) * coefficients)
  }
  random_slope_se <- function(group, values, columns) {
    table <- random[[group]]
    levels <- unique(as.character(values))
    if (length(levels) != 1) {
      stop("Expected one ", group, " level for a city component example.")
    }
    index <- match(levels, rownames(table))
    conditional_variance <- attr(table, "condVar")
    if (is.null(conditional_variance) || is.na(index)) {
      stop("Conditional variances are unavailable for ", group, ".")
    }
    coefficient_variances <- diag(conditional_variance[, , index])
    if (any(!is.finite(coefficient_variances)) ||
        any(coefficient_variances < 0)) {
      stop("Invalid conditional coefficient variances for ", group, ".")
    }
    centered_basis <- sweep(
      as.matrix(d[, columns, drop = FALSE]), 2,
      colMeans(as.matrix(d[, columns, drop = FALSE])), "-"
    )
    sqrt(rowSums(sweep(
      centered_basis^2, 2, coefficient_variances, "*"
    )))
  }

  global_trend <- unname(fixed[["(Intercept)"]]) + fixed_part(basis$trend_columns)
  global_season <- fixed_part(basis$season_columns)
  city_trend <- global_trend + random_slopes(
    "city_trend_group", d$city_trend_group, basis$trend_columns
  )
  city_season <- global_season + random_slopes(
    "city_season_group", d$city_season_group, basis$season_columns
  )
  city_trend_se <- random_slope_se(
    "city_trend_group", d$city_trend_group, basis$trend_columns
  )
  city_season_se <- random_slope_se(
    "city_season_group", d$city_season_group, basis$season_columns
  )
  shared_residual <- random_intercept("time_period", d$time_period)
  city_month_residual <- shared_residual + random_intercept("cell_id", d$cell_id)

  interval_multiplier <- stats::qnorm(0.975)
  result <- dplyr::tibble(
    date = as.Date(d$date),
    city_id = as.character(d$city_id),
    city_label = d$city_label,
    crime_type = as.character(d$crime_type),
    global_trend_centered = global_trend - mean(global_trend),
    city_trend_centered = city_trend - mean(city_trend),
    global_season_centered = global_season - mean(global_season),
    city_season_centered = city_season - mean(city_season),
    city_trend_se = city_trend_se,
    city_season_se = city_season_se,
    global_residual = shared_residual,
    city_residual = city_month_residual
  )
  result |>
    dplyr::mutate(
      city_trend_lower = city_trend_centered -
        interval_multiplier * city_trend_se,
      city_trend_upper = city_trend_centered +
        interval_multiplier * city_trend_se,
      city_season_lower = city_season_centered -
        interval_multiplier * city_season_se,
      city_season_upper = city_season_centered +
        interval_multiplier * city_season_se
    )
}

rtci_write_city_component_examples <- function(requests,
                                               output = "src/data/model/city_component_examples.csv") {
  requests <- requests |>
    dplyr::mutate(
      city_id = as.character(city_id),
      crime_type = as.character(crime_type)
    ) |>
    dplyr::distinct(city_id, crime_type)
  pieces <- lapply(unique(requests$crime_type), function(crime) {
    model <- readRDS(file.path(
      "src/data/model/models", paste0(crime, "_glmmtmb.rds")
    ))
    record <- readRDS(file.path("src/data/model/parts", paste0(crime, ".rds")))
    random_effects <- glmmTMB::ranef(model, condVar = TRUE)$cond
    crime_requests <- requests |>
      dplyr::filter(.data$crime_type == .env$crime)
    result <- dplyr::bind_rows(lapply(crime_requests$city_id, function(city) {
      rtci_extract_city_components(
        model, record$results, city, crime, random_effects = random_effects
      )
    }))
    rm(model, record, random_effects)
    invisible(gc())
    result
  })
  combined <- dplyr::bind_rows(pieces)
  readr::write_csv(combined, output)
  combined
}

rtci_trend_deviation_summary <- function(model, results, crime_type) {
  basis <- attr(model, "rtci_basis_spec")
  if (is.null(basis)) stop("Model has no cached RTCI basis specification.")
  columns <- basis$trend_columns
  random <- glmmTMB::ranef(model, condVar = FALSE)$cond$city_trend_group
  coefficients <- as.matrix(random[, columns, drop = FALSE])
  city_rows <- match(as.character(results$city_trend_group), rownames(coefficients))
  if (anyNA(city_rows)) stop("Could not match all city trend groups to coefficients.")
  deviations <- rowSums(
    as.matrix(results[, columns, drop = FALSE]) * coefficients[city_rows, , drop = FALSE]
  )
  dplyr::tibble(
    city_id = as.character(results$city_id),
    city_label = results$city_label,
    crime_type = crime_type,
    trend_deviation = deviations
  ) |>
    dplyr::group_by(city_id, city_label, crime_type) |>
    dplyr::summarise(
      months = dplyr::n(),
      trend_rms = sqrt(mean(
        (trend_deviation - mean(trend_deviation, na.rm = TRUE))^2,
        na.rm = TRUE
      )),
      trend_qrange = stats::quantile(trend_deviation, .95, na.rm = TRUE) -
        stats::quantile(trend_deviation, .05, na.rm = TRUE),
      .groups = "drop"
    )
}

rtci_write_trend_outliers <- function(
    crimes,
    output = "src/data/model/city_trend_deviations.csv") {
  pieces <- lapply(crimes, function(crime) {
    model <- readRDS(file.path(
      "src/data/model/models", paste0(crime, "_glmmtmb.rds")
    ))
    record <- readRDS(file.path("src/data/model/parts", paste0(crime, ".rds")))
    result <- rtci_trend_deviation_summary(model, record$results, crime)
    rm(model, record)
    invisible(gc())
    result
  })
  combined <- dplyr::bind_rows(pieces) |>
    dplyr::filter(months >= 60, is.finite(trend_rms), trend_rms > 0) |>
    dplyr::group_by(crime_type) |>
    dplyr::mutate(
      log_trend_rms = log(trend_rms),
      robust_z = (log_trend_rms - stats::median(log_trend_rms)) /
        stats::mad(log_trend_rms, constant = 1)
    ) |>
    dplyr::ungroup() |>
    dplyr::arrange(crime_type, dplyr::desc(robust_z))
  readr::write_csv(combined, output)
  combined
}

rtci_extract_all_city_trends <- function(model, results, crime_type) {
  basis <- attr(model, "rtci_basis_spec")
  columns <- basis$trend_columns
  fixed <- glmmTMB::fixef(model)$cond
  fixed_coefficients <- stats::setNames(rep(0, length(columns)), columns)
  retained <- intersect(columns, names(fixed))
  fixed_coefficients[retained] <- fixed[retained]
  trend_matrix <- as.matrix(results[, columns, drop = FALSE])
  global_trend <- unname(fixed[["(Intercept)"]]) +
    as.numeric(trend_matrix %*% fixed_coefficients)
  random <- glmmTMB::ranef(model, condVar = FALSE)$cond$city_trend_group
  coefficients <- as.matrix(random[, columns, drop = FALSE])
  city_rows <- match(as.character(results$city_trend_group), rownames(coefficients))
  city_trend <- global_trend + rowSums(
    trend_matrix * coefficients[city_rows, , drop = FALSE]
  )
  global_center <- mean(dplyr::distinct(
    dplyr::tibble(date = as.Date(results$date), value = global_trend), date,
    .keep_all = TRUE
  )$value)
  dplyr::tibble(
    date = as.Date(results$date),
    city_id = as.character(results$city_id),
    city_label = results$city_label,
    crime_type = crime_type,
    global_trend_centered = global_trend - global_center,
    city_trend = city_trend
  ) |>
    dplyr::group_by(city_id, city_label, crime_type) |>
    dplyr::mutate(city_trend_centered = city_trend - mean(city_trend)) |>
    dplyr::ungroup() |>
    dplyr::select(-city_trend)
}

rtci_extract_all_city_seasons <- function(model, crime_type, city_labels) {
  basis <- attr(model, "rtci_basis_spec")
  angle <- 2 * pi * (0:11) / 12
  seasonal_basis <- do.call(cbind, lapply(
    seq_len(basis$season_harmonics),
    function(harmonic) cbind(
      sin(harmonic * angle), cos(harmonic * angle)
    )
  ))
  colnames(seasonal_basis) <- basis$season_columns
  fixed <- glmmTMB::fixef(model)$cond
  fixed_coefficients <- stats::setNames(
    rep(0, length(basis$season_columns)), basis$season_columns
  )
  retained <- intersect(basis$season_columns, names(fixed))
  fixed_coefficients[retained] <- fixed[retained]
  global_season <- as.numeric(seasonal_basis %*% fixed_coefficients)
  global_season <- global_season - mean(global_season)
  random <- glmmTMB::ranef(model, condVar = FALSE)$cond$city_season_group
  coefficients <- as.matrix(
    random[, basis$season_columns, drop = FALSE]
  )
  city_seasons <- seasonal_basis %*% t(coefficients) + global_season
  city_seasons <- sweep(city_seasons, 2, colMeans(city_seasons), "-")
  labels <- city_labels |>
    dplyr::filter(city_id %in% colnames(city_seasons)) |>
    dplyr::mutate(city_id = factor(city_id, levels = colnames(city_seasons))) |>
    dplyr::arrange(city_id) |>
    dplyr::mutate(city_id = as.character(city_id))
  dplyr::tibble(
    month = rep(1:12, times = ncol(city_seasons)),
    city_id = rep(colnames(city_seasons), each = 12),
    crime_type = crime_type,
    global_season_centered = rep(global_season, times = ncol(city_seasons)),
    city_season_centered = as.vector(city_seasons)
  ) |>
    dplyr::left_join(labels, by = "city_id") |>
    dplyr::select(month, city_id, city_label, crime_type,
                  global_season_centered, city_season_centered)
}

rtci_write_all_city_curves <- function(
    crimes,
    output_directory = "src/data/app") {
  dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)
  for (crime in crimes) {
    model <- readRDS(file.path(
      "src/data/model/models", paste0(crime, "_glmmtmb.rds")
    ))
    record <- readRDS(file.path("src/data/model/parts", paste0(crime, ".rds")))
    labels <- record$results |>
      dplyr::transmute(
        city_id = as.character(city_id), city_label = city_label
      ) |>
      dplyr::distinct()
    trends <- rtci_extract_all_city_trends(model, record$results, crime)
    seasons <- rtci_extract_all_city_seasons(model, crime, labels)
    readr::write_csv(
      trends, file.path(output_directory, paste0("city_trends_", crime, ".csv"))
    )
    readr::write_csv(
      seasons, file.path(output_directory, paste0("city_seasons_", crime, ".csv"))
    )
    rm(model, record, trends, seasons)
    invisible(gc())
  }
  invisible(TRUE)
}

rtci_seasonal_deviation_summary <- function(model, crime_type, city_labels) {
  basis <- attr(model, "rtci_basis_spec")
  random <- glmmTMB::ranef(model, condVar = FALSE)$cond$city_season_group
  angle <- 2 * pi * (0:11) / 12
  seasonal_basis <- do.call(cbind, lapply(
    seq_len(basis$season_harmonics),
    function(harmonic) cbind(
      sin(harmonic * angle), cos(harmonic * angle)
    )
  ))
  colnames(seasonal_basis) <- basis$season_columns
  coefficients <- as.matrix(random[, basis$season_columns, drop = FALSE])
  deviations <- seasonal_basis %*% t(coefficients)
  summary <- dplyr::tibble(
    city_id = rownames(coefficients),
    crime_type = crime_type,
    seasonal_rms = sqrt(colMeans(deviations^2)),
    seasonal_range = apply(deviations, 2, function(x) max(x) - min(x))
  ) |>
    dplyr::left_join(city_labels, by = "city_id")
  summary
}

rtci_write_seasonal_outliers <- function(
    crimes,
    output = "src/data/model/city_seasonal_deviations.csv") {
  pieces <- lapply(crimes, function(crime) {
    model <- readRDS(file.path(
      "src/data/model/models", paste0(crime, "_glmmtmb.rds")
    ))
    record <- readRDS(file.path("src/data/model/parts", paste0(crime, ".rds")))
    labels <- record$results |>
      dplyr::transmute(
        city_id = as.character(city_id), city_label = city_label
      ) |>
      dplyr::distinct()
    result <- rtci_seasonal_deviation_summary(model, crime, labels)
    rm(model, record)
    invisible(gc())
    result
  })
  combined <- dplyr::bind_rows(pieces) |>
    dplyr::filter(is.finite(seasonal_rms), seasonal_rms > 0) |>
    dplyr::group_by(crime_type) |>
    dplyr::mutate(
      log_seasonal_rms = log(seasonal_rms),
      robust_z = (log_seasonal_rms - stats::median(log_seasonal_rms)) /
        stats::mad(log_seasonal_rms, constant = 1)
    ) |>
    dplyr::ungroup() |>
    dplyr::arrange(dplyr::desc(robust_z))
  readr::write_csv(combined, output)
  combined
}
