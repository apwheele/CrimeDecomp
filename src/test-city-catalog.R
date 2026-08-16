source("city_catalog.R")

testthat::test_that("RTCI county type is preserved in the city catalog", {
  raw <- data.frame(
    id = c("COUNTY", "CITY"), size = "all", population = c(100, 200),
    sample = 1
  )
  metadata <- data.frame(
    city_id = c("COUNTY", "CITY"), city_name = c("Example", "Example"),
    state = "TT", latitude = 1:2, longitude = 3:4
  )
  agency_types <- data.frame(
    city_id = c("COUNTY", "CITY"), agency_type = c("County", "City")
  )
  cities <- rtci_build_city_catalog(raw, metadata, agency_types)
  testthat::expect_identical(cities$agency_type, c("County", "City"))
})
