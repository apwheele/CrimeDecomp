#!/usr/bin/env Rscript

# Create the small city-name/coordinate crosswalk used by the model and app.
# The source RTCI repository keeps this information in pre_processed.csv.

source_path <- if (file.exists("src/data/raw/rtci_pre_processed.csv")) {
  "src/data/raw/rtci_pre_processed.csv"
} else {
  "src/data/raw/rtci_pre_processed.csv"
}

if (!file.exists(source_path)) stop("Metadata source does not exist: ", source_path)

place_key <- function(x) {
  x <- tolower(as.character(x))
  x <- sub(" +(county|parish|borough).*$", "", x)
  gsub("[^a-z0-9]", "", x)
}

metadata <- readr::read_csv(source_path, show_col_types = FALSE) |>
  dplyr::filter(!is.na(ori.x), ori.x != "") |>
  dplyr::transmute(
    city_id = as.character(ori.x),
    city_name = as.character(`Agency Name`),
    city_state = as.character(city_state),
    state = as.character(state_abbr),
    latitude = as.numeric(Latitude),
    longitude = as.numeric(Longitude),
    population = as.numeric(population),
    source_type = as.character(Type)
  ) |>
  dplyr::mutate(
    priority = ifelse(source_type == "City", 0, 1),
    is_county = source_type != "City"
  ) |>
  dplyr::arrange(city_id, priority) |>
  dplyr::distinct(city_id, .keep_all = TRUE) |>
  dplyr::select(-priority, -source_type) |>
  dplyr::arrange(city_name, state, city_id)

coords_path <- if (file.exists("src/data/raw/rtci_city_coords.csv")) {
  "src/data/raw/rtci_city_coords.csv"
} else {
  "src/data/raw/rtci_city_coords.csv"
}
if (file.exists(coords_path)) {
  coords <- readr::read_csv(coords_path, show_col_types = FALSE) |>
    dplyr::transmute(
      place_key = place_key(agency_name),
      state_full = as.character(state_name),
      is_county = as.logical(is_county) |
        grepl(" +(County|Parish|Borough)( |$)", agency_name, ignore.case = TRUE),
      latitude = as.numeric(lat),
      longitude = as.numeric(long)
    ) |>
    dplyr::distinct(place_key, state_full, is_county, .keep_all = TRUE)
  metadata <- metadata |>
    dplyr::mutate(
      state_full = ifelse(state == "DC", "District of Columbia",
                          state.name[match(state, state.abb)]),
      place_key = place_key(city_name)
    ) |>
    dplyr::left_join(coords, by = c("place_key", "state_full", "is_county"),
                     suffix = c("", "_coords")) |>
    dplyr::mutate(
      latitude = dplyr::coalesce(latitude_coords, latitude),
      longitude = dplyr::coalesce(longitude_coords, longitude)
    ) |>
    dplyr::select(-state_full, -place_key, -latitude_coords, -longitude_coords)
}

override_path <- "src/data/raw/agency_coordinate_overrides.csv"
if (file.exists(override_path)) {
  overrides <- readr::read_csv(override_path, show_col_types = FALSE) |>
    dplyr::transmute(
      city_id = as.character(city_id),
      city_name_override = as.character(city_name),
      state_override = as.character(state),
      latitude_override = as.numeric(latitude),
      longitude_override = as.numeric(longitude)
    )
  metadata <- metadata |>
    dplyr::full_join(overrides, by = "city_id") |>
    dplyr::mutate(
      city_name = dplyr::coalesce(city_name_override, city_name),
      state = dplyr::coalesce(state_override, state),
      city_state = ifelse(!is.na(city_name_override),
                          paste(city_name, state, sep = ","), city_state),
      latitude = dplyr::coalesce(latitude_override, latitude),
      longitude = dplyr::coalesce(longitude_override, longitude)
    ) |>
    dplyr::select(-dplyr::ends_with("_override"))
}

metadata <- metadata |> dplyr::select(-is_county)

dir.create("src/data/raw", recursive = TRUE, showWarnings = FALSE)
readr::write_csv(metadata, "src/data/raw/agency_metadata.csv", na = "")
message("Wrote ", nrow(metadata), " city metadata rows.")
