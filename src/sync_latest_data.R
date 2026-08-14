#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name, default) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit) == 0) default else sub(paste0("^--", name, "="), "", hit[[1]])
}

source_ref <- get_arg("ref", "main")
output <- get_arg("output", "src/data/raw/rtci_crime_trends.csv")
metadata_path <- get_arg("metadata", "src/data/raw/source_metadata.json")
check_state_path <- get_arg("check-state", "src/data/model/upstream_check.json")
agency_source_path <- get_arg("agency-source", "src/data/raw/rtci_pre_processed.csv")
coordinate_source_path <- get_arg("coordinate-source", "src/data/raw/rtci_city_coords.csv")
agency_metadata_path <- get_arg("agency-metadata", "src/data/raw/agency_metadata.csv")
build_metadata <- tolower(get_arg("build-metadata", "true")) %in%
  c("1", "true", "yes", "y")
repository <- "AH-Datalytics/rtci"
repository_url <- paste0("https://github.com/", repository)

options(HTTPUserAgent = "CrimeDecomp data updater")

github_contents <- function(path) {
  url <- paste0(
    "https://api.github.com/repos/", repository, "/contents/", path,
    "?ref=", utils::URLencode(source_ref, reserved = TRUE)
  )
  tryCatch(
    jsonlite::fromJSON(url, simplifyVector = TRUE),
    error = function(e) stop("Could not query GitHub for ", path, ": ", conditionMessage(e))
  )
}

atomic_replace <- function(source, destination) {
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  staged <- paste0(destination, ".", Sys.getpid(), ".tmp")
  backup <- paste0(destination, ".", Sys.getpid(), ".bak")
  on.exit(unlink(c(staged, backup), force = TRUE), add = TRUE)
  if (!file.copy(source, staged, overwrite = TRUE)) {
    stop("Could not stage downloaded file for ", destination)
  }
  had_destination <- file.exists(destination)
  if (had_destination && !file.rename(destination, backup)) {
    stop("Could not preserve the prior file before replacing ", destination)
  }
  if (!file.rename(staged, destination)) {
    if (had_destination) file.rename(backup, destination)
    stop("Could not move the downloaded file into place at ", destination)
  }
  if (had_destination) unlink(backup, force = TRUE)
  invisible(TRUE)
}

sync_remote_file <- function(remote, destination) {
  temporary <- tempfile("rtci-download-", fileext = ".tmp")
  on.exit(unlink(temporary, force = TRUE), add = TRUE)
  utils::download.file(remote$download_url, temporary, mode = "wb", quiet = FALSE)
  new_md5 <- unname(tools::md5sum(temporary))
  old_md5 <- if (file.exists(destination)) unname(tools::md5sum(destination)) else NA_character_
  changed <- is.na(old_md5) || !identical(old_md5, new_md5)
  if (changed) {
    atomic_replace(temporary, destination)
    message("Updated ", destination, " from upstream.")
  } else {
    message("Upstream content is unchanged: ", destination)
  }
  list(
    changed = changed,
    name = remote$name,
    repository_path = remote$path,
    blob_sha = remote$sha,
    source_url = remote$download_url,
    file_size_bytes = file.info(destination)$size,
    md5 = unname(tools::md5sum(destination))
  )
}

prior_metadata <- if (file.exists(metadata_path)) {
  tryCatch(jsonlite::read_json(metadata_path, simplifyVector = TRUE),
           error = function(e) NULL)
} else {
  NULL
}
prior_check <- if (file.exists(check_state_path)) {
  tryCatch(jsonlite::read_json(check_state_path, simplifyVector = TRUE),
           error = function(e) NULL)
} else {
  NULL
}

data_directory <- github_contents("data")
crime_candidates <- data_directory[
  data_directory$type == "file" &
    grepl("^Crime_Index_Reported_Crime_Trends_.*[.]csv$", data_directory$name),
  , drop = FALSE
]
if (nrow(crime_candidates) != 1L) {
  stop("Expected exactly one current Crime Index CSV in the upstream data directory; found ",
       nrow(crime_candidates), ".")
}

remote_files <- list(
  crime_data = as.list(crime_candidates[1, , drop = FALSE]),
  agency_source = github_contents("data/deprecated/pre_processed.csv"),
  coordinate_source = github_contents("docs/app_data/unique_cities_coords.csv")
)
destinations <- c(
  crime_data = output,
  agency_source = agency_source_path,
  coordinate_source = coordinate_source_path
)

sync_one <- function(name) {
  remote <- remote_files[[name]]
  prior_sha <- tryCatch(prior_check$files[[name]]$blob_sha, error = function(e) NULL)
  if (is.null(prior_sha)) {
    prior_sha <- tryCatch(prior_metadata$files[[name]]$blob_sha, error = function(e) NULL)
  }
  destination <- destinations[[name]]
  if (!is.null(prior_sha) && identical(prior_sha, remote$sha) && file.exists(destination)) {
    message("Upstream revision is unchanged: ", destination)
    return(list(
      changed = FALSE,
      name = remote$name,
      repository_path = remote$path,
      blob_sha = remote$sha,
      source_url = remote$download_url,
      file_size_bytes = file.info(destination)$size,
      md5 = unname(tools::md5sum(destination))
    ))
  }
  sync_remote_file(remote, destination)
}

file_results <- lapply(names(remote_files), sync_one)
names(file_results) <- names(remote_files)

metadata_inputs_changed <- isTRUE(file_results$agency_source$changed) ||
  isTRUE(file_results$coordinate_source$changed) ||
  (build_metadata && !file.exists(agency_metadata_path))
if (metadata_inputs_changed && build_metadata) {
  if (!identical(agency_source_path, "src/data/raw/rtci_pre_processed.csv") ||
      !identical(coordinate_source_path, "src/data/raw/rtci_city_coords.csv") ||
      !identical(agency_metadata_path, "src/data/raw/agency_metadata.csv")) {
    stop("Custom metadata paths require --build-metadata=false.")
  }
  source("src/build_metadata.R")
}

now <- format(Sys.time(), tz = "UTC")
downloaded_at <- if (any(vapply(file_results, `[[`, logical(1), "changed"))) {
  now
} else if (!is.null(prior_metadata$downloaded_at_utc)) {
  prior_metadata$downloaded_at_utc
} else {
  now
}
metadata <- list(
  source_repository = repository_url,
  source_ref = source_ref,
  downloaded_at_utc = downloaded_at,
  files = lapply(file_results, function(x) x[setdiff(names(x), "changed")]),
  data_changed = isTRUE(file_results$crime_data$changed),
  metadata_inputs_changed = metadata_inputs_changed
)
metadata_temp <- tempfile("rtci-metadata-", fileext = ".json")
on.exit(unlink(metadata_temp, force = TRUE), add = TRUE)
inputs_changed <- any(vapply(file_results, `[[`, logical(1), "changed"))
if (inputs_changed || !file.exists(metadata_path)) {
  jsonlite::write_json(metadata, metadata_temp, pretty = TRUE, auto_unbox = TRUE)
  atomic_replace(metadata_temp, metadata_path)
}

check_state <- list(
  source_repository = repository_url,
  source_ref = source_ref,
  checked_at_utc = now,
  files = lapply(file_results, function(x) x[c("name", "repository_path", "blob_sha")])
)
check_state_temp <- tempfile("rtci-check-", fileext = ".json")
on.exit(unlink(check_state_temp, force = TRUE), add = TRUE)
jsonlite::write_json(check_state, check_state_temp, pretty = TRUE, auto_unbox = TRUE)
atomic_replace(check_state_temp, check_state_path)

if (isTRUE(file_results$crime_data$changed) || metadata_inputs_changed) {
  message("RTCI inputs changed; model signatures will require refreshed outputs.")
} else {
  message("RTCI inputs are unchanged; existing valid model checkpoints remain current.")
}
