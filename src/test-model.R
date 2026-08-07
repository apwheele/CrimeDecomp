source("data_prep.R")
source("model.R")

testthat::test_that("formula contains global and city-varying smooth components", {
  txt <- paste(deparse(rtci_model_formula()), collapse = " ")
  compact_txt <- gsub("[[:space:]]+", "", txt)
  testthat::expect_match(txt, "~ crime_type")
  testthat::expect_match(txt, "by = crime_type")
  testthat::expect_match(txt, "s\\(city_id, bs = \"re\"\\)")
  testthat::expect_match(txt, "time_period, crime_type, bs = \"re\"")
  testthat::expect_match(txt, "time_index, city_crime, bs = \"sz\"")
  testthat::expect_true(grepl("month_index,city_crime,bs=\"sz\"", compact_txt,
                              fixed = TRUE))
  testthat::expect_false(grepl("cell_id", txt, fixed = TRUE))

  row_txt <- paste(deparse(rtci_model_formula(include_cell_overdispersion = TRUE)),
                   collapse = " ")
  compact_row_txt <- gsub("[[:space:]]+", "", row_txt)
  testthat::expect_true(grepl("s(cell_id,bs=\"re\")", compact_row_txt,
                              fixed = TRUE))

  sparse_txt <- paste(deparse(rtci_gamm4_crime_formula()), collapse = " ")
  testthat::expect_match(sparse_txt, "~ 1")
  testthat::expect_match(sparse_txt, "time_index, city_id, bs = \"fs\"")
  testthat::expect_match(sparse_txt, "month_index, city_id, bs = \"fs\"")
})

testthat::test_that("production TMB basis and formula are deterministic and complete", {
  d <- data.frame(time_index = 0:59, month_index = rep(1:12, 5),
                  city_id = factor(rep(c("A", "B"), each = 30)))
  spec <- rtci_make_basis_spec(d, trend_df = 5, season_harmonics = 3)
  first <- rtci_add_hierarchical_basis(d, spec)
  second <- rtci_add_hierarchical_basis(d, spec)
  testthat::expect_equal(first[spec$trend_columns], second[spec$trend_columns])
  testthat::expect_equal(length(spec$trend_columns), 5)
  testthat::expect_equal(length(spec$season_columns), 6)

  formula_text <- paste(deparse(rtci_glmmtmb_crime_formula(spec, TRUE)),
                        collapse = " ")
  compact_formula <- gsub("[[:space:]]+", "", formula_text)
  testthat::expect_match(formula_text, "cbind\\(count, trials - count\\) ~ 1")
  testthat::expect_match(formula_text, "homdiag")
  testthat::expect_match(formula_text, "city_trend_group")
  testthat::expect_match(formula_text, "city_season_group")
  testthat::expect_true(grepl("(1|city_id)", compact_formula, fixed = TRUE))
  testthat::expect_true(grepl("(1|time_period)", compact_formula, fixed = TRUE))
  testthat::expect_true(grepl("(1|cell_id)", compact_formula, fixed = TRUE))
  no_cell <- paste(deparse(rtci_glmmtmb_crime_formula(spec, FALSE)), collapse = " ")
  testthat::expect_false(grepl("cell_id", no_cell, fixed = TRUE))
})

testthat::test_that("TMB decomposition exactly reconstructs stored-data predictions", {
  testthat::skip_if_not_installed("glmmTMB")
  set.seed(20260807)
  d <- expand.grid(
    city_id = factor(sprintf("C%02d", 1:12)),
    time_index = 0:35
  )
  d$month_index <- d$time_index %% 12 + 1
  d$time_period <- factor(d$time_index)
  d$cell_id <- factor(seq_len(nrow(d)))
  d$trials <- 200
  eta <- -2 + 0.012 * d$time_index +
    0.18 * sin(2 * pi * (d$month_index - 1) / 12) +
    rep(stats::rnorm(12, 0, 0.2), each = 36)
  d$count <- stats::rbinom(nrow(d), d$trials, stats::plogis(eta))
  d$observed_rate <- d$count / d$trials * 100000 * rtci_annualization
  spec <- rtci_make_basis_spec(d, trend_df = 5, season_harmonics = 3)
  fit <- suppressWarnings(rtci_fit_crime_model_tmb(
    d, spec, include_cell_overdispersion = TRUE
  ))
  groups <- names(glmmTMB::ranef(fit, condVar = FALSE)$cond)
  testthat::expect_true(all(c("city_id", "time_period", "city_trend_group",
                              "city_season_group", "cell_id") %in% groups))
  components <- rtci_tmb_components(fit, d)
  direct <- stats::predict(fit, type = "link")
  testthat::expect_true(all(vapply(
    components[c("trend_eta", "global_eta", "city_eta", "time_eta",
                 "cell_eta", "full_eta")],
    function(x) all(is.finite(x)), logical(1)
  )))
  testthat::expect_equal(components$full_eta, unname(direct), tolerance = 1e-7)
})

testthat::test_that("factor smooth model fits and separates prediction terms", {
  set.seed(42)
  d <- expand.grid(
    month_index = 1:12,
    year = 2017:2024,
    city_id = factor(LETTERS[1:4]),
    crime_type = factor(c("murder", "robbery"))
  )
  d$time_index <- with(d, (year - min(year)) * 12 + month_index)
  d$time_period <- factor(with(d, paste(year, month_index, sep = "-")))
  d$city_crime <- interaction(d$city_id, d$crime_type, drop = TRUE)
  d$cell_id <- factor(seq_len(nrow(d)))
  d$trials <- 10000
  eta <- with(d, -7 + 0.3 * (crime_type == "robbery") +
                sin(month_index / 12 * 2 * pi) + as.numeric(city_id) / 20)
  d$count <- stats::rbinom(nrow(d), d$trials, stats::plogis(eta))
  d$observed_rate <- d$count / d$trials * 100000 * rtci_annualization

  fit <- rtci_fit_model(
    d, time_k = 5, city_time_k = 4, city_season_k = 5,
    include_cell_overdispersion = FALSE, nthreads = 1
  )
  labels <- rtci_prediction_labels(fit)
  testthat::expect_length(labels$city_deviation, 2)
  testthat::expect_true("s(city_id)" %in% labels$city)

  predicted <- rtci_add_predictions(fit, d)
  testthat::expect_equal(nrow(predicted), nrow(d))
  testthat::expect_true(all(is.finite(predicted$global_rate)))
  testthat::expect_true(all(is.finite(predicted$city_fitted_rate)))
  testthat::expect_true(all(is.finite(predicted$time_effect_logit)))
  testthat::expect_true(all(is.finite(predicted$time_effect_rate_delta)))
  testthat::expect_true(all(is.na(predicted$overdispersion_logit)))
})
