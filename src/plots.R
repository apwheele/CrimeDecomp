theme_andy <- function() {
  ggplot2::theme_bw() %+replace% ggplot2::theme(
    text = ggplot2::element_text(size = 16),
    panel.grid.major = ggplot2::element_line(linetype = "longdash"),
    panel.grid.minor = ggplot2::element_blank()
  )
}

plot_global_stl <- function(global) {
  ggplot2::ggplot(global, ggplot2::aes(x = date)) +
    ggplot2::geom_line(ggplot2::aes(y = observed_rate, colour = "Observed"), linewidth = .45, alpha = .55) +
    ggplot2::geom_line(ggplot2::aes(y = trend_rate, colour = "Trend"), linewidth = 1) +
    ggplot2::geom_line(ggplot2::aes(y = global_rate, colour = "Trend + season"), linewidth = 1) +
    ggplot2::facet_wrap(~crime_type, scales = "free_y", ncol = 2) +
    ggplot2::scale_colour_manual(values = c(Observed = "#999999", Trend = "#1a657c", `Trend + season` = "#d77942")) +
    ggplot2::labs(title = "Global STL-style decomposition", x = NULL, y = "Annualized rate per 100,000", colour = NULL) +
    theme_andy()
}

plot_seasonal <- function(global) {
  ggplot2::ggplot(global, ggplot2::aes(x = date, y = seasonal_rate_delta)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey50") +
    ggplot2::geom_line(colour = "#d77942", linewidth = .8) +
    ggplot2::facet_wrap(~crime_type, scales = "free_y", ncol = 2) +
    ggplot2::labs(title = "Seasonal component", x = NULL, y = "Annualized rate change from trend") +
    theme_andy()
}

plot_city_detail <- function(decomposition, city_id, crime_type) {
  d <- decomposition[decomposition$city_id == city_id & decomposition$crime_type == crime_type, ]
  ggplot2::ggplot(d, ggplot2::aes(x = date)) +
    ggplot2::geom_line(ggplot2::aes(y = observed_rate, colour = "Observed"), alpha = .55) +
    ggplot2::geom_line(ggplot2::aes(y = global_rate, colour = "Global baseline"), linewidth = 1) +
    ggplot2::scale_colour_manual(values = c(Observed = "#999999", `Global baseline` = "#1a657c")) +
    ggplot2::labs(title = paste0(unique(d$city_label), " — ", crime_type), x = NULL, y = "Annualized rate per 100,000", colour = NULL) +
    theme_andy()
}

plot_city_overdispersion <- function(decomposition, city_id, crime_type) {
  d <- decomposition[decomposition$city_id == city_id & decomposition$crime_type == crime_type, ]
  ggplot2::ggplot(d, ggplot2::aes(x = date, y = overdispersion_logit)) +
    ggplot2::geom_hline(yintercept = 0, colour = "grey50") +
    ggplot2::geom_line(colour = "#ae3e3e", linewidth = .8) +
    ggplot2::labs(title = "City × crime × month overdispersion", x = NULL, y = "Logit overdispersion term") +
    theme_andy()
}

