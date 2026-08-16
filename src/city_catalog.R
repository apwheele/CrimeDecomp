rtci_read_agency_types <- function(
    path = "src/data/raw/rtci_pre_processed.csv") {
  if (!file.exists(path)) {
    return(dplyr::tibble(
      city_id = character(), agency_type = character()
    ))
  }
  readr::read_csv(
    path, col_select = c("ori.x", "Type"), show_col_types = FALSE
  ) |>
    dplyr::transmute(
      city_id = as.character(`ori.x`),
      agency_type = as.character(Type),
      priority = ifelse(agency_type == "City", 0, 1)
    ) |>
    dplyr::filter(!is.na(city_id), city_id != "") |>
    dplyr::arrange(city_id, priority) |>
    dplyr::distinct(city_id, .keep_all = TRUE) |>
    dplyr::select(-priority)
}

rtci_build_city_catalog <- function(raw, metadata, agency_types,
                                    sample_only = TRUE,
                                    min_population = NULL) {
  raw |>
    dplyr::filter(
      size == "all", !is.na(population), population > 0,
      if (sample_only) !is.na(sample) & sample == 1 else TRUE,
      if (is.null(min_population)) TRUE else population >= min_population
    ) |>
    dplyr::transmute(
      city_id = as.character(id), population = as.numeric(population)
    ) |>
    dplyr::distinct(city_id, .keep_all = TRUE) |>
    dplyr::left_join(
      metadata |>
        dplyr::select(city_id, city_name, state, latitude, longitude),
      by = "city_id"
    ) |>
    dplyr::left_join(agency_types, by = "city_id") |>
    dplyr::mutate(
      city_name = dplyr::coalesce(city_name, ""),
      city_name = ifelse(
        city_name == "" | city_name == city_id,
        paste0("Unknown agency (", city_id, ")"), city_name
      ),
      state = dplyr::coalesce(state, ""),
      agency_type = dplyr::coalesce(agency_type, "City"),
      city_label = ifelse(
        state == "", city_name, paste0(city_name, ", ", state)
      )
    ) |>
    dplyr::select(
      city_id, city_name, state, city_label, agency_type,
      latitude, longitude, population
    )
}

rtci_write_city_catalog <- function(cities) {
  readr::write_csv(cities, "src/data/model/cities.csv")
  readr::write_csv(cities, "src/data/app/cities.csv")
  invisible(cities)
}
