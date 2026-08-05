#!/usr/bin/env Rscript

# Create the small city-name/coordinate crosswalk used by the model and app.
# The source RTCI repository keeps this information in pre_processed.csv.

source_path <- if (file.exists("src/data/raw/rtci_pre_processed.csv")) {
  "src/data/raw/rtci_pre_processed.csv"
} else {
  "src/data/raw/rtci_pre_processed.csv"
}

if (!file.exists(source_path)) stop("Metadata source does not exist: ", source_path)

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
  dplyr::mutate(priority = ifelse(source_type == "City", 0, 1)) |>
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
    dplyr::filter(!isTRUE(is_county)) |>
    dplyr::transmute(
      city_name = as.character(agency_name),
      state_full = as.character(state_name),
      latitude = as.numeric(lat),
      longitude = as.numeric(long)
    ) |>
    dplyr::distinct(city_name, state_full, .keep_all = TRUE)
  metadata <- metadata |>
    dplyr::mutate(state_full = state.name[match(state, state.abb)]) |>
    dplyr::left_join(coords, by = c("city_name", "state_full"), suffix = c("", "_coords")) |>
    dplyr::mutate(
      latitude = dplyr::coalesce(latitude_coords, latitude),
      longitude = dplyr::coalesce(longitude_coords, longitude)
    ) |>
    dplyr::select(-state_full, -latitude_coords, -longitude_coords)
}

dir.create("src/data/raw", recursive = TRUE, showWarnings = FALSE)
readr::write_csv(metadata, "src/data/raw/agency_metadata.csv", na = "")
message("Wrote ", nrow(metadata), " city metadata rows.")
