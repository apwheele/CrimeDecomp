# Source and data workflow

Everything needed to reproduce the project lives here.

## Run the model

From the repository root:

```powershell
conda run -n r2026 Rscript src/run_model.R
```

The default run uses all reporting cities in the RTCI sample, with no
population threshold. It writes model outputs to `src/data/model/` and the
files used by the app to `src/data/app/`.

## Refresh the pinned data snapshot

```powershell
conda run -n r2026 Rscript src/download_data.R
conda run -n r2026 Rscript src/build_metadata.R
conda run -n r2026 Rscript src/run_model.R
```

`download_data.R` retrieves the pinned crime snapshot, the processed agency
metadata, and the city-coordinate crosswalk into `src/data/raw/`. The
crosswalk supplies city names, states, and map coordinates for the ORI ids.

## Run the test

```powershell
conda run -n r2026 Rscript -e "source('src/data_prep.R'); testthat::test_file('src/test-data-prep.R')"
```

The model is a binomial smooth decomposition with a crime-specific smooth time
trend and cyclic month effect. City detail adds population-weighted city and
city-by-crime logit intercepts after the global fit. Rates are annualized from
monthly counts. The global residual is centered at zero within crime type; the
city-by-crime-by-month overdispersion term is the observed cell departure from
the fitted city terms, centered at zero within each city and crime type.
Neither is a Pearson residual.
