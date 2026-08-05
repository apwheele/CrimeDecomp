theme_andy <- function() {
  ggplot2::theme_bw(base_size = 11) %+replace% ggplot2::theme(
    plot.title = ggplot2::element_text(size = 14, face = "bold"),
    strip.text = ggplot2::element_text(size = 11, face = "bold"),
    axis.title = ggplot2::element_text(size = 10),
    axis.text = ggplot2::element_text(size = 8),
    panel.grid.minor = ggplot2::element_blank(),
    panel.grid.major = ggplot2::element_line(colour = "grey85")
  )
}

plot_global_trend <- function(global) {
  ggplot2::ggplot(global, ggplot2::aes(x = date, y = trend_rate)) +
    ggplot2::geom_line(colour = "#1a657c", linewidth = .7) +
    ggplot2::facet_wrap(~crime_type, scales = "free_y", ncol = 2) +
    ggplot2::labs(title = "Global trend by crime type", x = NULL,
                  y = "Annualized rate per 100,000") +
    theme_andy()
}

plot_global_seasonal <- function(global) {
  ggplot2::ggplot(global, ggplot2::aes(x = date, y = seasonal_rate_delta)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey55") +
    ggplot2::geom_line(colour = "#d77942", linewidth = .7) +
    ggplot2::facet_wrap(~crime_type, scales = "free_y", ncol = 2) +
    ggplot2::labs(title = "Global seasonal component by crime type", x = NULL,
                  y = "Annualized change from trend") +
    theme_andy()
}

plot_global_residual <- function(global) {
  ggplot2::ggplot(global, ggplot2::aes(x = date, y = global_residual_logit)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey55") +
    ggplot2::geom_line(colour = "#ae3e3e", linewidth = .7) +
    ggplot2::facet_wrap(~crime_type, scales = "free_y", ncol = 2) +
    ggplot2::labs(title = "Centered global residual by crime type", x = NULL,
                  y = "Centered residual (logit scale)") +
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
    ggplot2::labs(title = "Centered city x crime x month overdispersion", x = NULL,
                  y = "Centered overdispersion (logit scale)") +
    theme_andy()
}
