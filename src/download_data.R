#!/usr/bin/env Rscript

# One-time, pinned snapshot download. Delete the output file only when a new
# source snapshot is deliberately desired.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit) == 0) default else sub(paste0("^--", name, "="), "", hit[[1]])
}

output <- get_arg("output", "src/data/raw/rtci_crime_trends.csv")
metadata_path <- get_arg("metadata", "src/data/raw/source_metadata.json")
source_commit <- get_arg("commit", "1d5a1ebfdc8ea641eca2b5112d21b4e76aa82964")
source_url <- paste0(
  "https://raw.githubusercontent.com/AH-Datalytics/rtci/",
  source_commit,
  "/data/Crime_Index_Reported_Crime_Trends_Jan17_May26.csv"
)

dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(metadata_path), recursive = TRUE, showWarnings = FALSE)

snapshot_exists <- file.exists(output) && file.exists(metadata_path)
if (snapshot_exists) {
  message("Snapshot already exists; leaving it unchanged: ", output)
} else {
  if (!file.exists(output)) download.file(source_url, output, mode = "wb", quiet = FALSE)
}

metadata <- list(
  source_repository = "https://github.com/AH-Datalytics/rtci",
  source_commit = source_commit,
  source_url = source_url,
  downloaded_at_utc = format(Sys.time(), tz = "UTC"),
  file_size_bytes = file.info(output)$size,
  md5 = unname(tools::md5sum(output))
)
if (!file.exists(metadata_path)) {
  jsonlite::write_json(metadata, metadata_path, pretty = TRUE, auto_unbox = TRUE)
  message("Wrote metadata: ", metadata_path)
}

metadata_source <- "src/data/raw/rtci_pre_processed.csv"
metadata_url <- paste0(
  "https://raw.githubusercontent.com/AH-Datalytics/rtci/", source_commit,
  "/data/deprecated/pre_processed.csv"
)
coords_source <- "src/data/raw/rtci_city_coords.csv"
coords_url <- paste0(
  "https://raw.githubusercontent.com/AH-Datalytics/rtci/", source_commit,
  "/docs/app_data/unique_cities_coords.csv"
)
if (!file.exists(metadata_source)) download.file(metadata_url, metadata_source, mode = "wb", quiet = FALSE)
if (!file.exists(coords_source)) download.file(coords_url, coords_source, mode = "wb", quiet = FALSE)
source("src/build_metadata.R")
