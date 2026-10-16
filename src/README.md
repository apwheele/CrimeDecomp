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
Successful completion also renders `paper.qmd` to `paper.pdf` and `paper.md`.
The Markdown figures are exported at 192 DPI, and its display equations are
written in GitHub's fenced `math` format. Use `--render-report=false` to suppress
that step.
The WSL wrapper suppresses rendering and builds the paper's exact city trend,
seasonal, and residual comparison files after merging. Render with Windows
Quarto afterward.

## Refresh the latest data snapshot

```powershell
conda run -n r2026 Rscript src/sync_latest_data.R
wsl -d Ubuntu -- bash -lc "cd '/mnt/d/Dropbox/Dropbox/PublicCode_Git/CrimeDecomp' && exec bash src/run_models_sequential.sh"
```

`sync_latest_data.R` finds the newest monthly crime sample linked from
<https://crimeindex.org/download> (the RTCI moved there from GitHub after the
June 2026 sample) and reads the agency name and coordinate files from the
`main` branch of <https://github.com/AH-Datalytics/rtci>. It compares upstream
revisions (the S3 ETag for the crime sample, Git blob SHAs for the GitHub
files) and local checksums, and atomically replaces only changed inputs.

Each monthly sample is the full history from January 2017, revised, with the
newest month appended. A new crime file is only used if it starts no later and
ends no earlier than the current one; otherwise the refresh stops and keeps the
current file. The modeled cities are the current sample (`sample == 1`), which
changes every month: agencies whose latest month is late drop out until they
catch up, and new agencies join (between 445 and 590 agencies per sample from
August 2025 to August 2026). The RTCI agency file (`pre_processed.csv`) is no
longer updated, so agencies that joined since are named from AH Datalytics'
copy of the FBI agency list (`cde_populations.csv` in
<https://github.com/AH-Datalytics/cde-population>). Coordinates for them come
from the RTCI city coordinate file when the name matches, or from
`src/data/raw/agency_coordinate_overrides.csv`; cities without coordinates are
reported but still modeled, since the app has no map. If Philadelphia, the
paper's worked example, is not in a month's sample, `build_city_examples.R`
skips it and the paper render stops with a message saying so. It rebuilds agency metadata when its upstream inputs
change. The QMD calls this check automatically and runs the sequential workflow
only when the resulting model signature differs. `download_data.R` remains
available for intentionally reproducing the older pinned snapshot.

## Run the test

```powershell
conda run -n r2026 Rscript -e "source('src/data_prep.R'); testthat::test_file('src/test-data-prep.R')"
```

Run the whole suite from `src/` with `conda run -n r2026 Rscript run_tests.R`
(from PowerShell: under Git Bash, its own DLLs on `PATH` stop `readr` and
`testthat` from loading).

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
