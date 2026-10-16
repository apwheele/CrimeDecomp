source("rtci_source.R")

# Every RTCI sample adds a month, revises past months, and changes which
# agencies are in the sample. These use small made-up files.

rtci_test_rows <- function(id, first, last, sample = 1, size = "all") {
  dates <- seq(as.Date(paste0(first, "-01")), as.Date(paste0(last, "-01")), by = "month")
  rows <- data.frame(
    id = id, size = size,
    year = as.integer(format(dates, "%Y")), month = as.integer(format(dates, "%m")),
    population = 100000, agencies = 1, sample = sample
  )
  for (crime in c("murder", "rape", "robbery", "assault", "burglary", "theft", "motor")) {
    rows[[paste0(crime, "_total")]] <- 10L + seq_along(dates) %% 5L
  }
  rows
}

rtci_test_csv <- function(rows) {
  path <- tempfile(fileext = ".csv")
  readr::write_csv(rows, path, na = "")
  path
}

testthat::test_that("the newest crime sample is found among the download links", {
  s3 <- "https://crimeindex-data.s3.us-east-1.amazonaws.com/downloads"
  links <- c("archive/crime_202606.csv", "archive/crime_202608_1792092221.csv",
             "archive/crime_202607_1789575398.csv", "archive/clearance_202609_1792092877.csv",
             "historical_crime_1930_2025_1790092670.csv", "archive/crime_202608_1792092221.csv")
  html <- paste0('<a href="', s3, "/", links, '">', collapse = " ")
  testthat::expect_identical(
    rtci_latest_crime_sample(html), paste0(s3, "/archive/crime_202608_1792092221.csv")
  )
  testthat::expect_error(rtci_latest_crime_sample("<html></html>"), "No monthly crime sample")
  testthat::expect_error(
    rtci_latest_crime_sample(paste(paste0(s3, "/archive/crime_202608_", 1:2, ".csv"), collapse = " ")),
    "one crime sample for 202608"
  )
})

testthat::test_that("a new crime file must keep the history and add to it", {
  current <- rtci_test_csv(rtci_test_rows("A", "2017-01", "2026-08"))
  later <- rtci_test_csv(rbind(
    rtci_test_rows("A", "2017-01", "2026-09"),
    rtci_test_rows("B", "2017-01", "2026-08", sample = 0)
  ))
  testthat::expect_identical(
    rtci_check_crime_history(later, current), c(first = "2017-01", last = "2026-09")
  )
  # A revision of the same months is fine
  testthat::expect_identical(rtci_check_crime_history(current, current)[["last"]], "2026-08")
  testthat::expect_error(
    rtci_check_crime_history(rtci_test_csv(rtci_test_rows("A", "2017-01", "2026-07")), current),
    "ends in 2026-07"
  )
  testthat::expect_error(
    rtci_check_crime_history(rtci_test_csv(rtci_test_rows("A", "2020-01", "2026-09")), current),
    "starts in 2020-01"
  )
  testthat::expect_error(
    rtci_check_crime_history(rtci_test_csv(rtci_test_rows("A", "2017-01", "2026-09", sample = 0)), current),
    "no sample agencies"
  )
  no_motor <- rtci_test_rows("A", "2017-01", "2026-09")
  no_motor$motor_total <- NULL
  testthat::expect_error(rtci_check_crime_history(rtci_test_csv(no_motor), current),
                         "missing columns motor_total")
})

testthat::test_that("sample agencies exclude size groups, state totals and agencies out of the sample", {
  path <- rtci_test_csv(rbind(
    rtci_test_rows("A", "2026-01", "2026-02"),
    rtci_test_rows("B", "2026-01", "2026-02", sample = 0),
    rtci_test_rows("A", "2026-01", "2026-02", size = "lg"),
    rtci_test_rows("tx", "2026-01", "2026-02", sample = NA)
  ))
  testthat::expect_identical(rtci_sample_agencies(path), "A")
})

testthat::test_that("FBI agency names become city names", {
  testthat::expect_identical(
    rtci_clean_agency_name(c(
      "Hoover Police Department", "Dunwoody  Police Department",
      "Kent County Sheriff's Office", "St. Louis County Police Department",
      "Jacksonville Sheriff's Office"
    )),
    c("Hoover", "Dunwoody", "Kent County", "St. Louis County", "Jacksonville Sheriff's Office")
  )
})

testthat::test_that("agencies that join the sample are named from the FBI agency list", {
  root <- tempfile("rtci-metadata-test-")
  dir.create(file.path(root, "src", "data", "raw"), recursive = TRUE)
  file.copy("rtci_source.R", file.path(root, "src"))
  build_metadata <- normalizePath("build_metadata.R")
  old_working_directory <- setwd(root)
  on.exit(setwd(old_working_directory), add = TRUE)
  on.exit(unlink(root, recursive = TRUE, force = TRUE), add = TRUE)

  readr::write_csv(rbind(
    rtci_test_rows("TX0000001", "2026-01", "2026-02"),
    rtci_test_rows("TX0000003", "2026-01", "2026-02"),  # joined; not in pre_processed.csv
    rtci_test_rows("TX0000004", "2026-01", "2026-02")   # joined; no name anywhere
  ), "src/data/raw/rtci_crime_trends.csv")
  readr::write_csv(data.frame(
    ori.x = "TX0000001", `Agency Name` = "Oldtown", city_state = "Oldtown,TX", state_abbr = "TX",
    Latitude = 30, Longitude = -97, population = 100000, Type = "City", check.names = FALSE
  ), "src/data/raw/rtci_pre_processed.csv")
  readr::write_csv(data.frame(
    ori = c("TX0000001", "TX0000003"), agency_name = c("Oldtown Police", "Newtown Police Department"),
    state = "TX", population = c(100000, 50000)
  ), "src/data/raw/cde_agency_names.csv")

  testthat::expect_message(source(build_metadata), "Named 1 agencies.*TX0000003")
  metadata <- readr::read_csv("src/data/raw/agency_metadata.csv", show_col_types = FALSE)
  testthat::expect_setequal(metadata$city_id, c("TX0000001", "TX0000003"))
  testthat::expect_identical(metadata$city_name[metadata$city_id == "TX0000001"], "Oldtown")
  testthat::expect_identical(metadata$city_name[metadata$city_id == "TX0000003"], "Newtown")
  testthat::expect_true(is.na(metadata$latitude[metadata$city_id == "TX0000003"]))
})
