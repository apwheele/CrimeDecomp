# Helpers for src/sync_latest_data.R and src/build_metadata.R, kept separate
# so src/test-rtci-source.R can test them without network access.
#
# Every monthly RTCI sample carries the full history from January 2017,
# revised, with the newest month appended. It also changes which agencies are
# in the sample: agencies whose latest month is late drop out until they catch
# up, and new agencies join.

rtci_crime_sample_pattern <- paste0(
  "https://crimeindex-data[.]s3[.a-z0-9-]*amazonaws[.]com/downloads/archive/",
  "crime_[0-9]{6}(_[0-9]+)?[.]csv"
)

rtci_required_columns <- c(
  "id", "size", "year", "month", "population", "sample",
  paste0(c("murder", "rape", "robbery", "assault", "burglary", "theft", "motor"), "_total")
)

# URL of the newest monthly crime sample linked from the download page.
rtci_latest_crime_sample <- function(html) {
  links <- unique(regmatches(html, gregexpr(rtci_crime_sample_pattern, html))[[1]])
  if (length(links) == 0L) stop("No monthly crime sample links were found.")
  sample_month <- sub("^crime_([0-9]{6}).*$", "\\1", basename(links))
  latest <- links[sample_month == max(sample_month)]
  if (length(latest) != 1L) {
    stop("Expected one crime sample for ", max(sample_month), "; found ", length(latest), ".")
  }
  latest
}

# First and last month (YYYY-MM) of the sample agencies in a crime file.
rtci_sample_months <- function(path) {
  header <- names(readr::read_csv(path, n_max = 0, show_col_types = FALSE))
  missing <- setdiff(rtci_required_columns, header)
  if (length(missing)) stop("missing columns ", paste(missing, collapse = ", "))
  rows <- readr::read_csv(path, col_select = c("size", "sample", "year", "month"),
                          show_col_types = FALSE)
  rows <- rows[rows$size == "all" & !is.na(rows$sample) & rows$sample == 1, ]
  if (!nrow(rows)) stop("no sample agencies (size 'all', sample 1)")
  months <- sprintf("%04d-%02d", as.integer(rows$year), as.integer(rows$month))
  c(first = min(months), last = max(months))
}

# A new crime file replaces the current one, so it must keep the history:
# start no later and end no earlier than the current file.
rtci_check_crime_history <- function(path, current_path = NULL) {
  new <- rtci_sample_months(path)
  if (!is.null(current_path) && file.exists(current_path)) {
    current <- rtci_sample_months(current_path)
    if (new[["first"]] > current[["first"]]) {
      stop("starts in ", new[["first"]], ", after the current data's first month ",
           current[["first"]])
    }
    if (new[["last"]] < current[["last"]]) {
      stop("ends in ", new[["last"]], ", before the current data's last month ",
           current[["last"]])
    }
  }
  new
}

# Sample agencies (size "all", sample 1) in a crime file.
rtci_sample_agencies <- function(path) {
  rows <- readr::read_csv(path, col_select = c("id", "size", "sample"), show_col_types = FALSE)
  sort(unique(as.character(rows$id[rows$size == "all" & !is.na(rows$sample) & rows$sample == 1])))
}

# City names from FBI agency names, for agencies missing from RTCI's agency
# file: "Hoover Police Department" -> "Hoover", "Kent County Sheriff's
# Office" -> "Kent County"; other names are kept as they are.
rtci_clean_agency_name <- function(name) {
  name <- gsub("[[:space:]]+", " ", trimws(name))
  county <- "^(.*?) County (Sheriff'?s? (Office|Department)|Police Department|Police)$"
  city <- paste0("^(.*?) (Police Department|Police Dept[.]?|Department of Public Safety|",
                 "Public Safety Department|Police)$")
  is_county <- grepl(county, name, ignore.case = TRUE, perl = TRUE)
  is_city <- !is_county & grepl(city, name, ignore.case = TRUE, perl = TRUE)
  ifelse(is_county, paste(sub(county, "\\1", name, ignore.case = TRUE, perl = TRUE), "County"),
         ifelse(is_city, sub(city, "\\1", name, ignore.case = TRUE, perl = TRUE), name))
}
