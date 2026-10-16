#!/usr/bin/env Rscript

source("src/data_prep.R")
source("src/city_component_analysis.R")

trends <- rtci_write_trend_outliers(rtci_component_crimes)
trend_top <- trends |>
  dplyr::group_by(crime_type) |>
  dplyr::slice_max(robust_z, n = 2, with_ties = FALSE) |>
  dplyr::ungroup() |>
  dplyr::select(city_id, crime_type)
seasonal <- rtci_write_seasonal_outliers(rtci_component_crimes)
seasonal_top <- seasonal |>
  dplyr::group_by(crime_type) |>
  dplyr::slice_max(robust_z, n = 2, with_ties = FALSE) |>
  dplyr::ungroup() |>
  dplyr::select(city_id, crime_type)
# The paper's worked example. Agencies leave the RTCI sample in months when
# their latest data are late, so it is only requested when it was modeled.
paper_example <- data.frame(
  city_id = "PAPEP0000",
  crime_type = c("robbery", "burglary")
)
if (!all(paper_example$city_id %in% trends$city_id)) {
  message("Philadelphia (PAPEP0000) is not in the current RTCI sample; ",
          "skipping the paper's worked example.")
  paper_example <- paper_example[0, ]
}
requests <- dplyr::bind_rows(
  paper_example,
  trend_top,
  seasonal_top
) |>
  dplyr::distinct()
examples <- rtci_write_city_component_examples(requests)
latest_residual_se <- rtci_write_latest_residual_se(rtci_component_crimes)
rtci_write_all_city_curves(rtci_component_crimes)
message("Wrote ", nrow(examples), " city-component rows.")
message("Wrote ", nrow(latest_residual_se), " latest residual standard errors.")
