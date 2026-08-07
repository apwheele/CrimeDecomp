#!/usr/bin/env Rscript

part_dir <- file.path("src", "data", "model", "parts")
crime_names <- c("murder", "rape", "robbery", "assault", "burglary", "theft", "motor")

cat("Crime model checkpoint status\n")
cat("Checked:", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"), "\n\n")
for (crime in crime_names) {
  part_path <- file.path(part_dir, paste0(crime, ".rds"))
  log_path <- file.path(part_dir, paste0(crime, ".log"))
  if (file.exists(part_path)) {
    record <- tryCatch(readRDS(part_path), error = function(e) NULL)
    status <- if (is.null(record)) "INVALID CHECKPOINT" else
      paste("COMPLETE", record$completed_at)
  } else if (file.exists(log_path)) {
    lines <- readLines(log_path, warn = FALSE)
    status <- if (length(lines)) tail(lines, 1) else "log exists"
  } else {
    status <- "NOT STARTED"
  }
  cat(sprintf("%-22s %s\n", crime, status))
}
