#!/usr/bin/env Rscript

source("src/data_prep.R")
source("src/model.R")

crimes <- rtci_component_crimes
raw <- rtci_read_raw("src/data/raw/rtci_crime_trends.csv")
metadata <- rtci_read_metadata("src/data/raw/agency_metadata.csv")
data <- rtci_prepare_stacked(raw, metadata, sample_only = TRUE)

for (crime in crimes) {
  model_path <- file.path("src/data/model/models", paste0(crime, "_glmmtmb.rds"))
  part_path <- file.path("src/data/model/parts", paste0(crime, ".rds"))
  stopifnot(file.exists(model_path), file.exists(part_path))
  fit <- readRDS(model_path)
  part <- readRDS(part_path)
  crime_data <- droplevels(data[data$crime_type == crime, , drop = FALSE])
  stopifnot(
    inherits(fit, "glmmTMB"),
    fit$fit$convergence == 0,
    isTRUE(fit$sdr$pdHess),
    !is.null(attr(fit, "rtci_basis_spec")),
    identical(attr(fit, "run_signature"), part$run_signature),
    nrow(part$results) == nrow(crime_data)
  )
  components <- rtci_tmb_components(fit, crime_data)
  direct <- stats::predict(fit, type = "link")
  stopifnot(
    length(direct) == nrow(crime_data),
    all(is.finite(direct)),
    max(abs(unname(direct) - components$full_eta)) < 1e-7,
    all(is.finite(part$results$trend_rate)),
    all(is.finite(part$results$global_rate)),
    all(is.finite(part$results$city_fitted_rate)),
    all(is.finite(part$results$time_effect_logit)),
    all(is.finite(part$results$overdispersion_logit))
  )
  cat(sprintf("%-10s OK: %s rows, %.1f MB\n", crime,
              format(nrow(crime_data), big.mark = ","),
              file.info(model_path)$size / 1024^2))
  rm(fit, part, crime_data, components, direct)
  invisible(gc())
}

required_outputs <- c(
  "src/data/model/decomposition.csv",
  "src/data/model/global_stl.csv",
  "src/data/model/city_summary.csv",
  "src/data/model/cities.csv",
  "src/data/model/model_metadata.json",
  "src/data/model/city_component_examples.csv",
  "src/data/model/city_trend_deviations.csv",
  "src/data/model/city_seasonal_deviations.csv"
)
stopifnot(all(file.exists(required_outputs)))
decomposition <- readr::read_csv(required_outputs[[1]], show_col_types = FALSE)
cities <- readr::read_csv(required_outputs[[4]], show_col_types = FALSE)
stopifnot(
  nrow(decomposition) == nrow(data),
  setequal(unique(decomposition$crime_type), crimes),
  nrow(cities) == dplyr::n_distinct(data$city_id),
  all(cities$agency_type %in% c("City", "County")),
  all(is.finite(cities$latitude)),
  all(is.finite(cities$longitude))
)
for (crime in crimes) {
  app_path <- file.path("src/data/app", paste0("decomposition_", crime, ".csv"))
  trend_path <- file.path("src/data/app", paste0("city_trends_", crime, ".csv"))
  season_path <- file.path("src/data/app", paste0("city_seasons_", crime, ".csv"))
  residual_se_path <- file.path(
    "src/data/app", paste0("residual_se_", crime, ".csv")
  )
  stopifnot(
    file.exists(app_path), file.info(app_path)$size > 0,
    file.exists(trend_path), file.info(trend_path)$size > 0,
    file.exists(season_path), file.info(season_path)$size > 0,
    file.exists(residual_se_path), file.info(residual_se_path)$size > 0
  )
  trends <- readr::read_csv(trend_path, show_col_types = FALSE)
  seasons <- readr::read_csv(season_path, show_col_types = FALSE)
  residual_se <- readr::read_csv(residual_se_path, show_col_types = FALSE)
  expected_cities <- dplyr::n_distinct(data$city_id[data$crime_type == crime])
  stopifnot(
    nrow(trends) == sum(data$crime_type == crime),
    dplyr::n_distinct(trends$city_id) == expected_cities,
    dplyr::n_distinct(seasons$city_id) == expected_cities,
    nrow(seasons) == 12 * expected_cities,
    nrow(residual_se) == sum(data$crime_type == crime),
    all(is.finite(trends$global_trend_centered)),
    all(is.finite(trends$city_trend_centered)),
    all(is.finite(trends$city_trend_se)),
    all(trends$city_trend_se >= 0),
    all(is.finite(seasons$global_season_centered)),
    all(is.finite(seasons$city_season_centered)),
    all(is.finite(seasons$city_season_se)),
    all(seasons$city_season_se >= 0),
    all(is.finite(residual_se$overdispersion_logit_se)),
    all(residual_se$overdispersion_logit_se >= 0),
    max(abs(trends |>
      dplyr::group_by(city_id) |>
      dplyr::summarise(value = mean(city_trend_centered), .groups = "drop") |>
      dplyr::pull(value))) < 1e-10,
    max(abs(seasons |>
      dplyr::group_by(city_id) |>
      dplyr::summarise(value = mean(city_season_centered), .groups = "drop") |>
      dplyr::pull(value))) < 1e-10
  )
  rm(trends, seasons, residual_se)
}
trend_rankings <- readr::read_csv(required_outputs[[7]], show_col_types = FALSE)
season_rankings <- readr::read_csv(required_outputs[[8]], show_col_types = FALSE)
component_examples <- readr::read_csv(required_outputs[[6]], show_col_types = FALSE)
stopifnot(
  all(vapply(crimes, function(crime) sum(trend_rankings$crime_type == crime) >= 2,
             logical(1))),
  all(vapply(crimes, function(crime) sum(season_rankings$crime_type == crime) >= 2,
             logical(1))),
  all(is.finite(component_examples$city_trend_se)),
  all(is.finite(component_examples$city_season_se)),
  all(component_examples$city_trend_se >= 0),
  all(component_examples$city_season_se >= 0),
  all(component_examples$city_trend_lower <=
        component_examples$city_trend_centered),
  all(component_examples$city_trend_centered <=
        component_examples$city_trend_upper),
  all(component_examples$city_season_lower <=
        component_examples$city_season_centered),
  all(component_examples$city_season_centered <=
        component_examples$city_season_upper)
)
cat(sprintf("Merged outputs OK: %s rows, %s cities, all coordinates finite.\n",
            format(nrow(decomposition), big.mark = ","), nrow(cities)))
