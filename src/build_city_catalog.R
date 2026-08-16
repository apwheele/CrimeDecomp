#!/usr/bin/env Rscript

source("src/data_prep.R")
source("src/city_catalog.R")

raw <- rtci_read_raw("src/data/raw/rtci_crime_trends.csv")
metadata <- rtci_read_metadata("src/data/raw/agency_metadata.csv")
agency_types <- rtci_read_agency_types()
cities <- rtci_build_city_catalog(raw, metadata, agency_types)
rtci_write_city_catalog(cities)
message("Wrote ", nrow(cities), " city catalog rows.")
