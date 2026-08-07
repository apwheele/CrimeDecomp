theme_andy <- function() {
  ggplot2::theme_bw() + ggplot2::theme(
    text = ggplot2::element_text(size = 16),
    panel.grid.major = ggplot2::element_line(linetype = "longdash"),
    panel.grid.minor = ggplot2::element_blank()
  )
}

crime_label <- function(x) {
  dplyr::recode(x, motor = "Motor Vehicle Theft", .default = tools::toTitleCase(x))
}

plot_global_trend <- function(global) {
  global <- global |> dplyr::mutate(crime_label = crime_label(as.character(crime_type)))
  ggplot2::ggplot(global, ggplot2::aes(x = date, y = trend_rate)) +
    ggplot2::geom_line(colour = "#1a657c", linewidth = .7) +
    ggplot2::facet_wrap(~crime_label, scales = "free_y", ncol = 2) +
    ggplot2::labs(x = NULL, y = "Annualized rate per 100,000") +
    theme_andy()
}

plot_global_seasonal <- function(global) {
  global <- global |> dplyr::mutate(crime_label = crime_label(as.character(crime_type)))
  ggplot2::ggplot(global, ggplot2::aes(x = date, y = seasonal_rate_delta)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey55") +
    ggplot2::geom_line(colour = "#d77942", linewidth = .7) +
    ggplot2::facet_wrap(~crime_label, scales = "free_y", ncol = 2) +
    ggplot2::labs(x = NULL, y = "Annualized change from trend") +
    theme_andy()
}

plot_global_residual <- function(global) {
  global <- global |> dplyr::mutate(crime_label = crime_label(as.character(crime_type)))
  ggplot2::ggplot(global, ggplot2::aes(x = date, y = global_residual_rate)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey55") +
    ggplot2::geom_line(colour = "#ae3e3e", linewidth = .7) +
    ggplot2::facet_wrap(~crime_label, scales = "free_y", ncol = 2) +
    ggplot2::labs(x = NULL, y = "Shared time period effect on annualized rate") +
    theme_andy()
}

plot_city_detail <- function(decomposition, city_id, crime_type) {
  d <- decomposition[decomposition$city_id == city_id & decomposition$crime_type == crime_type, ]
  ggplot2::ggplot(d, ggplot2::aes(x = date)) +
    ggplot2::geom_line(ggplot2::aes(y = observed_rate, colour = "Observed"), alpha = .55) +
    ggplot2::geom_line(ggplot2::aes(y = global_rate, colour = "Global baseline"), linewidth = .8) +
    ggplot2::scale_colour_manual(values = c(Observed = "#999999", `Global baseline` = "#1a657c")) +
    ggplot2::labs(title = paste0(unique(d$city_label), " - ", crime_type), x = NULL,
                  y = "Annualized rate per 100,000", colour = NULL) +
    theme_andy()
}

plot_city_overdispersion <- function(decomposition, city_id, crime_type) {
  d <- decomposition[decomposition$city_id == city_id & decomposition$crime_type == crime_type, ]
  ggplot2::ggplot(d, ggplot2::aes(x = date, y = overdispersion_logit)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey55") +
    ggplot2::geom_line(colour = "#ae3e3e", linewidth = .7) +
    ggplot2::labs(title = "City x crime x month row random effect", x = NULL,
                  y = "Fitted row effect (logit scale)") +
    theme_andy()
}

plot_city_global_comparison <- function(decomposition, city_id, crime_type) {
  d <- decomposition |>
    dplyr::filter(.data$city_id == .env$city_id,
                  .data$crime_type == .env$crime_type) |>
    dplyr::arrange(date)
  city_curve_label <- paste0(unique(d$city_name), " smooth")
  long <- d |>
    dplyr::select(date, observed_rate, global_rate, city_fitted_rate) |>
    tidyr::pivot_longer(-date, names_to = "series", values_to = "rate") |>
    dplyr::mutate(series = dplyr::recode(
      series,
      observed_rate = "Observed monthly rate",
      global_rate = "Global smooth",
      city_fitted_rate = city_curve_label
    ))
  ggplot2::ggplot(long, ggplot2::aes(date, rate, colour = series,
                                     linewidth = series, alpha = series)) +
    ggplot2::geom_line() +
    ggplot2::scale_colour_manual(values = c(
      "Observed monthly rate" = "grey55",
      "Global smooth" = "#1a657c",
      stats::setNames("#d77942", city_curve_label)
    )) +
    ggplot2::scale_linewidth_manual(values = c(
      "Observed monthly rate" = 0.35,
      "Global smooth" = 0.85,
      stats::setNames(0.85, city_curve_label)
    ), guide = "none") +
    ggplot2::scale_alpha_manual(values = c(
      "Observed monthly rate" = 0.55,
      "Global smooth" = 1,
      stats::setNames(1, city_curve_label)
    ), guide = "none") +
    ggplot2::labs(
      title = paste0(unique(d$city_label), ": global and city ",
                     crime_label(crime_type), " curves"),
      x = NULL, y = "Annualized rate per 100,000", colour = NULL
    ) +
    theme_andy() +
    ggplot2::theme(legend.position = "bottom")
}

plot_city_decomposition <- function(decomposition, city_id, crime_type) {
  d <- decomposition |>
    dplyr::filter(.data$city_id == .env$city_id,
                  .data$crime_type == .env$crime_type) |>
    dplyr::arrange(date) |>
    dplyr::mutate(
      centered_city_shape = city_minus_global_logit -
        mean(city_minus_global_logit, na.rm = TRUE)
    ) |>
    dplyr::transmute(
      date,
      `City-by-month row effect` = overdispersion_logit,
      `Centered city curve minus global curve` = centered_city_shape,
      `Shared time period effect` = time_effect_logit
    ) |>
    tidyr::pivot_longer(-date, names_to = "component", values_to = "value") |>
    dplyr::mutate(component = factor(component, levels = c(
      "City-by-month row effect",
      "Centered city curve minus global curve",
      "Shared time period effect"
    )))
  ggplot2::ggplot(d, ggplot2::aes(date, value)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey55") +
    ggplot2::geom_line(colour = "#7d3c98", linewidth = 0.55) +
    ggplot2::facet_wrap(~component, ncol = 1, scales = "free_y") +
    ggplot2::labs(title = paste0(unique(decomposition$city_label[
      decomposition$city_id == city_id]), " deviations from the global model"),
                  x = NULL, y = "Deviation on logit scale") +
    theme_andy()
}

plot_city_component_comparison <- function(components, city_id, crime_type) {
  d <- components |>
    dplyr::filter(.data$city_id == .env$city_id,
                  .data$crime_type == .env$crime_type) |>
    dplyr::arrange(date)
  city <- unique(d$city_label)
  ribbons <- dplyr::bind_rows(
    d |>
      dplyr::transmute(
        date, component = "Trend (centered; city intercept removed)",
        lower = city_trend_lower, upper = city_trend_upper
      ),
    d |>
      dplyr::transmute(
        date, component = "Season",
        lower = city_season_lower, upper = city_season_upper
      )
  ) |>
    dplyr::mutate(component = factor(component, levels = c(
      "Trend (centered; city intercept removed)",
      "Season",
      "Residual (shared vs. shared + city-month)"
    )))
  long <- dplyr::bind_rows(
    d |>
      dplyr::transmute(
        date, component = "Trend (centered; city intercept removed)",
        `Entire sample` = global_trend_centered,
        !!city := city_trend_centered
      ),
    d |>
      dplyr::transmute(
        date, component = "Season",
        `Entire sample` = global_season_centered,
        !!city := city_season_centered
      ),
    d |>
      dplyr::transmute(
        date, component = "Residual (shared vs. shared + city-month)",
        `Entire sample` = global_residual,
        !!city := city_residual
      )
  ) |>
    dplyr::mutate(component = factor(component, levels = c(
      "Trend (centered; city intercept removed)",
      "Season",
      "Residual (shared vs. shared + city-month)"
    ))) |>
    tidyr::pivot_longer(
      -c(date, component), names_to = "series", values_to = "value"
    )
  ggplot2::ggplot(long, ggplot2::aes(date, value, colour = series,
                                     linewidth = series)) +
    ggplot2::geom_ribbon(
      data = ribbons,
      ggplot2::aes(x = date, ymin = lower, ymax = upper),
      inherit.aes = FALSE, fill = "#d77942", alpha = 0.18
    ) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey70") +
    ggplot2::geom_line() +
    ggplot2::facet_wrap(~component, ncol = 1, scales = "free_y") +
    ggplot2::scale_colour_manual(values = stats::setNames(
      c("#1a657c", "#d77942"), c("Entire sample", city)
    )) +
    ggplot2::scale_linewidth_manual(values = stats::setNames(
      c(0.8, 0.55), c("Entire sample", city)
    ), guide = "none") +
    ggplot2::labs(x = NULL, y = "Model component (logit)", colour = NULL) +
    theme_andy() +
    ggplot2::theme(legend.position = "bottom")
}

plot_seasonal_outlier_comparison <- function(components, outlier_pairs) {
  selected <- outlier_pairs |>
    dplyr::select(city_id, city_label, crime_type)
  panel_levels <- paste0(selected$city_label, " - ",
                         crime_label(selected$crime_type))
  wide <- components |>
    dplyr::inner_join(selected, by = c("city_id", "city_label", "crime_type")) |>
    dplyr::mutate(month = as.integer(format(as.Date(date), "%m"))) |>
    dplyr::group_by(city_id, city_label, crime_type, month) |>
    dplyr::slice_head(n = 1) |>
    dplyr::ungroup() |>
    dplyr::mutate(panel = factor(
      paste0(city_label, " - ", crime_label(crime_type)),
      levels = panel_levels
    )) |>
    dplyr::select(panel, month, global_season_centered,
                  city_season_centered, city_season_lower,
                  city_season_upper)
  ribbons <- wide |>
    dplyr::select(panel, month, lower = city_season_lower,
                  upper = city_season_upper)
  d <- wide |>
    tidyr::pivot_longer(
      c(global_season_centered, city_season_centered),
      names_to = "series", values_to = "value"
    ) |>
    dplyr::mutate(series = dplyr::recode(
      series,
      global_season_centered = "Entire sample",
      city_season_centered = "City"
    ))
  ggplot2::ggplot(d, ggplot2::aes(month, value, colour = series)) +
    ggplot2::geom_ribbon(
      data = ribbons,
      ggplot2::aes(x = month, ymin = lower, ymax = upper),
      inherit.aes = FALSE, fill = "#d77942", alpha = 0.18
    ) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey70") +
    ggplot2::geom_line(linewidth = 0.8) +
    ggplot2::geom_point(size = 1.7) +
    ggplot2::facet_wrap(~panel, ncol = 2, scales = "free_y") +
    ggplot2::scale_x_continuous(
      breaks = c(1, 4, 7, 10), labels = month.abb[c(1, 4, 7, 10)],
      expand = ggplot2::expansion(mult = .02)
    ) +
    ggplot2::scale_colour_manual(values = c(
      "Entire sample" = "#1a657c", "City" = "#d77942"
    )) +
    ggplot2::labs(x = NULL, y = "Seasonal component (logit)", colour = NULL) +
    theme_andy() +
    ggplot2::theme(
      legend.position = "bottom",
      strip.text = ggplot2::element_text(size = 10)
    )
}

plot_outlier_city_trends <- function(components, outlier_pairs) {
  selected <- outlier_pairs |>
    dplyr::select(city_id, city_label, crime_type)
  panel_levels <- paste0(selected$city_label, " - ",
                         crime_label(selected$crime_type))
  wide <- components |>
    dplyr::inner_join(selected, by = c("city_id", "city_label", "crime_type")) |>
    dplyr::mutate(panel = factor(
      paste0(city_label, " - ", crime_label(crime_type)),
      levels = panel_levels
    )) |>
    dplyr::select(panel, date, global_trend_centered, city_trend_centered,
                  city_trend_lower, city_trend_upper)
  ribbons <- wide |>
    dplyr::select(panel, date, lower = city_trend_lower,
                  upper = city_trend_upper)
  d <- wide |>
    tidyr::pivot_longer(
      c(global_trend_centered, city_trend_centered),
      names_to = "series", values_to = "value"
    ) |>
    dplyr::mutate(series = dplyr::recode(
      series,
      global_trend_centered = "Entire sample",
      city_trend_centered = "City"
    ))
  ggplot2::ggplot(d, ggplot2::aes(date, value, colour = series)) +
    ggplot2::geom_ribbon(
      data = ribbons,
      ggplot2::aes(x = date, ymin = lower, ymax = upper),
      inherit.aes = FALSE, fill = "#d77942", alpha = 0.18
    ) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey70") +
    ggplot2::geom_line(linewidth = 0.7) +
    ggplot2::facet_wrap(~panel, ncol = 2, scales = "free_y") +
    ggplot2::scale_colour_manual(values = c(
      "Entire sample" = "#1a657c", "City" = "#d77942"
    )) +
    ggplot2::labs(x = NULL, y = "Centered trend component (logit)", colour = NULL) +
    theme_andy() +
    ggplot2::theme(
      legend.position = "bottom",
      strip.text = ggplot2::element_text(size = 10)
    )
}

plot_residual_outlier_comparison <- function(decomposition, outlier_rows) {
  selected <- outlier_rows |>
    dplyr::select(city_id, city_label, crime_type)
  panel_levels <- paste0(
    selected$city_label, " - ", crime_label(selected$crime_type)
  )
  d <- decomposition |>
    dplyr::inner_join(
      selected, by = c("city_id", "city_label", "crime_type")
    ) |>
    dplyr::mutate(panel = factor(
      paste0(city_label, " - ", crime_label(crime_type)),
      levels = panel_levels
    )) |>
    dplyr::select(panel, date, value = overdispersion_logit)
  bounds <- d |>
    dplyr::group_by(panel) |>
    dplyr::summarise(
      date = min(date), bound = max(abs(value), na.rm = TRUE),
      .groups = "drop"
    ) |>
    tidyr::expand_grid(sign = c(-1, 1)) |>
    dplyr::mutate(value = sign * bound)
  peaks <- outlier_rows |>
    dplyr::mutate(panel = factor(
      paste0(city_label, " - ", crime_label(crime_type)),
      levels = panel_levels
    )) |>
    dplyr::transmute(panel, date, value = overdispersion_logit)
  ggplot2::ggplot(d, ggplot2::aes(date, value)) +
    ggplot2::geom_blank(data = bounds) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey70") +
    ggplot2::geom_line(colour = "#7d3c98", linewidth = 0.55) +
    ggplot2::geom_point(
      data = peaks, colour = "#ae3e3e", size = 2.2
    ) +
    ggplot2::facet_wrap(~panel, ncol = 2, scales = "free_y") +
    ggplot2::labs(
      x = NULL, y = "City-month residual (logit scale)"
    ) +
    theme_andy() +
    ggplot2::theme(
      strip.text = ggplot2::element_text(size = 10),
      plot.margin = ggplot2::margin(5.5, 5.5, 5.5, 18)
    )
}
