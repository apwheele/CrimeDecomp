# Monthly crime decomposition

The three deliverables are in the repository root:

- `paper.pdf`
- `paper.qmd`
- `paper.md`

All runnable code, tests, app files, and data are under `src/`.

The deployed application is available at
<https://apwheele.github.io/CrimeDecomp/>. GitHub Pages serves the generated
app CSVs from a dedicated `gh-pages` branch; fitted model objects remain local
and are not published.

From the repository root, rerun the validated all-city workflow under WSL with:

```powershell
wsl -d Ubuntu -- bash -lc "cd '/mnt/d/Dropbox/Dropbox/PublicCode_Git/CrimeDecomp' && export RUN_LOG=src/data/model/sequential-glmmtmb-run.log FAILURE_LOG=src/data/model/sequential-glmmtmb-failure.log && exec bash src/run_models_sequential.sh"
```

This uses every `size == "all"`, `sample == 1` city and applies no population
threshold. A sparse `glmmTMB` model is fit separately for each crime type. Each
contains a global intercept, a global natural-spline trend, a global cyclic
Fourier season, a city random intercept, and shared-variance city trend and
seasonal deviations. A `(1 | time_period)` effect captures
monthly departures shared by all cities. The default also includes the
observation-level `(1 | cell_id)` random effect; use `--overdispersion=false` only
for a faster sensitivity run.
Monthly counts are annualized to rates per 100,000. The output is written to
`src/data/model/` and `src/data/app/`.

Each crime is saved atomically under `src/data/model/parts/` as soon as it
finishes. Interrupted runs resume valid checkpoints by default. Check progress
from another terminal with:

```powershell
conda run --no-capture-output -n r2026 Rscript src/model_status.R
```

Use `--resume=false` only when intentionally refitting every crime. A changed
input file or model setting automatically invalidates an old checkpoint.
The complete fitted `glmmTMB` objects, including their deterministic spline
basis specification, are saved separately as
`src/data/model/models/<crime>_glmmtmb.rds`. For example, reload the murder model
with `readRDS("src/data/model/models/murder_glmmtmb.rds")`. This directory is
excluded from Git because fitted objects can be large.
After all model outputs are assembled, the runner renders both `paper.pdf` and
`paper.md` automatically and copies the PDF to `output/pdf/paper.pdf`. Pass
`--render-report=false` only when a data-only run is intended.
The WSL sequential wrapper intentionally performs a data-only merge because
Quarto is installed on Windows; afterward run
`conda run --no-capture-output -n r2026 quarto render paper.qmd` and copy the
PDF to `output/pdf/paper.pdf`.

Start the app from the repository root:

```powershell
python src/serve_app.py
```

This serves the application and its sibling model-data directory, then opens
<http://localhost:8000/> in the default browser automatically; the server
redirects that address to `/app/`. Press
`Ctrl+C` in the terminal to stop the
server. Use `--port=8080` if port 8000 is occupied. The app has global trend,
seasonal, and time-period-effect charts; state-filtered city detail; and an
interactive all-city view with centered trend and seasonal curves. Hovering an
all-city curve identifies the city, while a shaded band summarizes the middle
80% of city curves. City detail mirrors the paper example with observed/global/
city rates followed by city-versus-US-wide trend, season, and residual panels.
The full date range is always shown.

## Model scaling

The default fits seven sparse crime-specific models sequentially with `glmmTMB`.
Only one crime is held in the sparse optimizer at a time, and each successful
fit is saved and reload-verified before the next crime starts. A single
stacked `mgcv::bam` fit can be requested with `--stacked=true`, but the two
city-by-crime smooth blocks contain roughly 45,000 coefficients at the default
basis sizes. Allow 96--128 GB RAM for that dense fit; 64 GB is a risky minimum.
Do not add the 458,392-level row random effect to the dense `bam` version. The
default TMB backend is the appropriate implementation of `(1 | cell_id)`.

To refresh the pinned input data and rebuild the city-name crosswalk, read
`src/README.md`.

## Acknowledgment

The code, initial paper, and web application were created in OpenAI Codex using
Luna and Sol, with substantive review and direction from Andrew P. Wheeler.
The paper's package and methods references are maintained in `references.bib`.
