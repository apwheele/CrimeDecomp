source("data_prep.R")

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
  testthat::expect_equal(nrow(out), 18)
  testthat::expect_setequal(as.character(unique(out$crime_type)), rtci_component_crimes)
  testthat::expect_true(all(out$count <= out$trials))
  testthat::expect_equal(out$observed_rate[[1]], 24)

  violent_month1 <- out$count[out$crime_type == "violent" & out$date == out$date[[1]]]
  property_month1 <- out$count[out$crime_type == "property" & out$date == out$date[[1]]]
  testthat::expect_equal(violent_month1, 2 + 4 + 6 + 8)
  testthat::expect_equal(property_month1, 10 + 12 + 14)
})

testthat::test_that("agencies joining or leaving the sample and new months are handled", {
  rows <- function(id, months, sample = 1) {
    data.frame(
      id = id, size = "all", year = 2026, month = months, population = 100000,
      sample = sample, murder_total = 1, rape_total = 2, robbery_total = 3,
      assault_total = 4, burglary_total = 5, theft_total = 6, motor_total = 7
    )
  }
  raw <- rbind(
    rows("A", 1:3),              # in the sample, with a newly appended month
    rows("B", 1:2, sample = 0),  # left the sample: its latest month is late
    rows("C", 2:3)               # joined, with no name or coordinates yet
  )
  metadata <- data.frame(
    city_id = c("A", "B"), city_name = c("Alpha", "Beta"),
    city_state = c("Alpha,TT", "Beta,TT"), state = "TT", latitude = 1, longitude = 2
  )
  out <- rtci_prepare_stacked(raw, metadata)
  testthat::expect_setequal(as.character(unique(out$city_id)), c("A", "C"))
  testthat::expect_equal(max(out$date), as.Date("2026-03-01"))
  testthat::expect_identical(unique(out$city_label[out$city_id == "C"]), "Unknown agency (C)")
  testthat::expect_warning(rtci_validate_stacked(out), "1 modeled cities have no coordinates")
  checks <- suppressWarnings(rtci_validate_stacked(out))
  testthat::expect_equal(checks$cities, 2)
  testthat::expect_equal(checks$cities_missing_coordinates, 1)
})
