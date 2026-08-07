# Source and data workflow

Everything needed to reproduce the project lives here.

## Run the model

From the repository root:

```powershell
wsl -d Ubuntu -- bash -lc "cd '/mnt/d/Dropbox/Dropbox/PublicCode_Git/CrimeDecomp' && export RUN_LOG=src/data/model/sequential-glmmtmb-run.log FAILURE_LOG=src/data/model/sequential-glmmtmb-failure.log && exec bash src/run_models_sequential.sh"
```

The default run uses all reporting cities in the RTCI sample, with no
population threshold. It writes model outputs to `src/data/model/` and the
files used by the app to `src/data/app/`.
Completed crime fits are checkpointed in `src/data/model/parts/`; rerunning the
same command resumes them. Run `conda run --no-capture-output -n r2026 Rscript
src/model_status.R` in another terminal to see which fits are running or done.
Full fitted objects are stored in `src/data/model/models/` as one compressed RDS
file per crime and are excluded from Git.
Successful completion also renders `paper.qmd` to `paper.pdf` and `paper.md`;
use `--render-report=false` to suppress that step.
The WSL wrapper suppresses rendering and builds the paper's exact city trend,
seasonal, and residual comparison files after merging. Render with Windows
Quarto afterward.

## Refresh the pinned data snapshot

```powershell
conda run -n r2026 Rscript src/download_data.R
conda run -n r2026 Rscript src/build_metadata.R
wsl -d Ubuntu -- bash -lc "cd '/mnt/d/Dropbox/Dropbox/PublicCode_Git/CrimeDecomp' && exec bash src/run_models_sequential.sh"
```

`download_data.R` retrieves the pinned crime snapshot, the processed agency
metadata, and the city-coordinate crosswalk into `src/data/raw/`. The
crosswalk supplies city names, states, and map coordinates for the ORI ids.

## Run the test

```powershell
conda run -n r2026 Rscript -e "source('src/data_prep.R'); testthat::test_file('src/test-data-prep.R')"
```

The default runner fits one sparse aggregated-binomial `glmmTMB` model at a
time per crime type. Each model has a global intercept, a five-column natural
cubic spline trend, a three-harmonic cyclic Fourier season, a mean-zero city
random intercept, and partially pooled city coefficients on both bases. The
default adds a common `(1 | time_period)` monthly effect and a
`(1 | cell_id)` city-by-month observation-level effect. Set
`--overdispersion=false` only to omit the latter for a
faster sensitivity run. Global predictions omit all city and row
terms. City fitted curves include the city intercept and deviation curves but
omit the row effect. No continuity-corrected or "stabilized" probability is
constructed.

The alternative `--stacked=true` path retains the `mgcv::bam` specification
for a high-memory machine. At the default bases, plan on 96--128 GB RAM and use
`--overdispersion=false`; the observation-level effect belongs in the sparse
crime-specific backend.
