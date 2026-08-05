# Paper plots. The theme is intentionally kept close to the supplied theme.

theme_andy <- function() {
  ggplot2::theme_bw() %+replace% ggplot2::theme(
    text = ggplot2::element_text(size = 16),
    panel.grid.major = ggplot2::element_line(linetype = "longdash"),
    panel.grid.minor = ggplot2::element_blank()
  )
}

plot_global_trends <- function(global) {
  ggplot2::ggplot(global, ggplot2::aes(x = date)) +
    ggplot2::geom_line(ggplot2::aes(y = observed_rate), alpha = 0.35, linewidth = 0.4) +
    ggplot2::geom_line(ggplot2::aes(y = global_rate), linewidth = 1.05, colour = "#1b5e75") +
    ggplot2::facet_wrap(~crime_type, scales = "free_y", ncol = 2) +
    ggplot2::labs(
      title = "Global monthly trends",
      subtitle = "Thin: observed rate; thick: global spline",
      x = NULL, y = "Rate per 100,000"
    ) +
    theme_andy()
}

plot_agency_deviations <- function(decomposition, agency_summary, n = 12) {
  chosen <- agency_summary |>
    dplyr::group_by(crime_type) |>
    dplyr::slice_max(max_abs_deviation, n = max(1, ceiling(n / 7)), with_ties = FALSE) |>
    dplyr::ungroup()
  selected <- decomposition |>
    dplyr::semi_join(chosen, by = c("agency_id", "crime_type"))

  ggplot2::ggplot(selected, ggplot2::aes(x = date, y = deviation_logit, group = agency_id)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey50") +
    ggplot2::geom_line(ggplot2::aes(colour = agency_id), alpha = 0.8) +
    ggplot2::facet_wrap(~crime_type, scales = "free_y", ncol = 2) +
    ggplot2::guides(colour = "none") +
    ggplot2::labs(
      title = "Agency departures from global spline",
      x = NULL, y = "Fitted logit departure"
    ) +
    theme_andy()
}

plot_residuals <- function(decomposition) {
  ggplot2::ggplot(decomposition, ggplot2::aes(x = date, y = pearson_residual)) +
    ggplot2::geom_hline(yintercept = -3, linetype = "dashed", colour = "#b33a3a") +
    ggplot2::geom_hline(yintercept = 0, linetype = "solid", colour = "grey50") +
    ggplot2::geom_hline(yintercept = 3, linetype = "dashed", colour = "#b33a3a") +
    ggplot2::geom_point(ggplot2::aes(colour = outlier_flag), alpha = 0.35, size = 0.55) +
    ggplot2::facet_wrap(~crime_type, ncol = 2) +
    ggplot2::scale_colour_manual(values = c(`FALSE` = "#555555", `TRUE` = "#b33a3a")) +
    ggplot2::labs(
      title = "Monthly residual diagnostics",
      subtitle = "Red: |Pearson residual| >= 3",
      x = NULL, y = "Pearson residual", colour = "Outlier"
    ) +
    theme_andy()
}
