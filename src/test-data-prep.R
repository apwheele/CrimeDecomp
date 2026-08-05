testthat::test_that("stacked preparation creates one row per component crime", {
  raw <- data.frame(
    id = c("A", "A"), size = "all", year = c(2020, 2020), month = c(1, 2),
    population = c(100000, 100000), sample = 1,
    murder_total = c(2, 3), rape_total = c(4, 5), robbery_total = c(6, 7),
    assault_total = c(8, 9), burglary_total = c(10, 11), theft_total = c(12, 13),
    motor_total = c(14, 15)
  )
  metadata <- data.frame(
    city_id = "A", city_name = "Test City", city_state = "Test City, TT",
    state = "TT", latitude = 1, longitude = 2
  )
  out <- rtci_prepare_stacked(raw, metadata, min_population = 0)
  testthat::expect_equal(nrow(out), 14)
  testthat::expect_setequal(as.character(unique(out$crime_type)), rtci_component_crimes)
  testthat::expect_true(all(out$count <= out$trials))
  testthat::expect_equal(out$observed_rate[[1]], 24)
})
