source("src/model_signature.R")

rtci_as_bool <- function(value) {
  tolower(value) %in% c("1", "true", "yes", "y")
}

rtci_update_check_due <- function(
    metadata_path = "src/data/model/upstream_check.json",
    max_age_seconds = as.numeric(Sys.getenv("RTCI_UPDATE_MAX_AGE_SECONDS", "300"))) {
  if (!file.exists(metadata_path) || !is.finite(max_age_seconds) || max_age_seconds <= 0) {
    return(TRUE)
  }
  metadata <- tryCatch(
    jsonlite::read_json(metadata_path, simplifyVector = TRUE),
    error = function(e) NULL
  )
  if (is.null(metadata$checked_at_utc)) {
    return(TRUE)
  }
  checked <- as.POSIXct(metadata$checked_at_utc, tz = "UTC")
  is.na(checked) || as.numeric(difftime(Sys.time(), checked, units = "secs")) >= max_age_seconds
}

rtci_assert_sequential_runner_idle <- function(root = getwd()) {
  if (.Platform$OS.type == "windows") {
    wsl_root <- rtci_wsl_repository_path(root)
    command <- paste(
      "cd", shQuote(wsl_root), "&& mkdir -p src/data/model &&",
      "exec 8>src/data/model/sequential-run.lock && flock -n 8"
    )
    status <- system2(
      "wsl",
      c("-d", "Ubuntu", "--", "bash", "--noprofile", "--norc", "-c", shQuote(command))
    )
  } else {
    status <- system2(
      "bash",
      c("-c", shQuote(paste(
        "mkdir -p src/data/model &&",
        "exec 8>src/data/model/sequential-run.lock && flock -n 8"
      )))
    )
  }
  if (!identical(status, 0L)) {
    stop("A sequential model workflow is already running; source files were not changed.")
  }
  invisible(TRUE)
}

rtci_refresh_source <- function() {
  if (rtci_as_bool(Sys.getenv("RTCI_SKIP_UPDATE_CHECK", "false"))) {
    message("Skipping the upstream RTCI update check because RTCI_SKIP_UPDATE_CHECK is set.")
    return(invisible(FALSE))
  }
  if (!rtci_update_check_due()) {
    message("The upstream RTCI update check is still fresh; skipping a duplicate check.")
    return(invisible(FALSE))
  }
  rtci_assert_sequential_runner_idle()
  rscript <- file.path(R.home("bin"), "Rscript")
  status <- system2(rscript, c("src/sync_latest_data.R", "--ref=main"))
  if (!identical(status, 0L)) {
    stop("The upstream RTCI update check failed with status ", status, ".")
  }
  invisible(TRUE)
}

rtci_wsl_repository_path <- function(root) {
  windows_root <- normalizePath(root, winslash = "\\", mustWork = TRUE)
  if (grepl("^[A-Za-z]:\\\\", windows_root)) {
    drive <- tolower(substr(windows_root, 1, 1))
    remainder <- gsub("\\\\", "/", substr(windows_root, 4, nchar(windows_root)))
    return(paste0("/mnt/", drive, "/", remainder))
  }
  result <- system2("wsl", c("-d", "Ubuntu", "--", "wslpath", "-a", shQuote(windows_root)),
                    stdout = TRUE)
  status <- attr(result, "status")
  if (!is.null(status) && status != 0L) {
    stop("Could not translate the repository path for WSL: ", paste(result, collapse = "\n"))
  }
  trimws(result[[1]])
}

rtci_run_sequential_workflow <- function(root = getwd()) {
  if (.Platform$OS.type == "windows") {
    wsl_root <- rtci_wsl_repository_path(root)
    command <- paste(
      "cd", shQuote(wsl_root), "&&",
      "export RUN_LOG=src/data/model/sequential-glmmtmb-run.log",
      "FAILURE_LOG=src/data/model/sequential-glmmtmb-failure.log", "&&",
      "exec bash src/run_models_sequential.sh"
    )
    status <- system2(
      "wsl",
      c("-d", "Ubuntu", "--", "bash", "--noprofile", "--norc", "-c", shQuote(command))
    )
  } else {
    status <- system2("bash", "src/run_models_sequential.sh")
  }
  if (!identical(status, 0L)) {
    stop("The sequential model workflow failed with status ", status, ".")
  }
  invisible(TRUE)
}

rtci_ensure_outputs_current <- function(refresh_source = TRUE, rebuild = TRUE) {
  if (refresh_source) {
    rtci_refresh_source()
  }
  expected_signature <- rtci_model_signature()
  status <- rtci_output_status(expected_signature)
  if (isTRUE(status$current)) {
    message("Model outputs are current; no crime models need to be fitted.")
    return(invisible(status))
  }
  if (!rebuild) {
    return(invisible(status))
  }
  message("Model outputs are stale (", status$reason, ").")
  message("Starting the locked, sequential model workflow; crime fits will not overlap.")
  rtci_run_sequential_workflow()
  rebuilt_status <- rtci_output_status(rtci_model_signature())
  if (!isTRUE(rebuilt_status$current)) {
    stop("The sequential workflow completed, but outputs are still stale: ",
         rebuilt_status$reason)
  }
  invisible(rebuilt_status)
}
