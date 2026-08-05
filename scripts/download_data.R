#!/usr/bin/env Rscript

# One-time, pinned snapshot download. Delete the output file only when a new
# source snapshot is deliberately desired.

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit) == 0) default else sub(paste0("^--", name, "="), "", hit[[1]])
}

output <- get_arg("output", "data/raw/rtci_crime_trends.csv")
metadata_path <- get_arg("metadata", "data/raw/source_metadata.json")
source_commit <- get_arg("commit", "1d5a1ebfdc8ea641eca2b5112d21b4e76aa82964")
source_url <- paste0(
  "https://raw.githubusercontent.com/AH-Datalytics/rtci/",
  source_commit,
  "/data/Crime_Index_Reported_Crime_Trends_Jan17_May26.csv"
)

dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
dir.create(dirname(metadata_path), recursive = TRUE, showWarnings = FALSE)

if (file.exists(output) && file.exists(metadata_path)) {
  message("Snapshot already exists; leaving it unchanged: ", output)
  quit(save = "no", status = 0)
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
jsonlite::write_json(metadata, metadata_path, pretty = TRUE, auto_unbox = TRUE)
message("Wrote metadata: ", metadata_path)
