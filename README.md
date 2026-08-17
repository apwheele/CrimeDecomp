# Monthly crime decomposition

The four deliverables are in the repository root:

- `paper.pdf`
- `paper.docx`
- `paper.qmd`
- `paper.md`

All runnable code, tests, app files, and data are under `src/`.

The deployed application is available at
<https://apwheele.github.io/CrimeDecomp/>. GitHub Pages serves the generated
app CSVs from a dedicated `gh-pages` branch; fitted model objects remain local
and are not published.

Deployment is controlled by a script committed on `main`. After committing and
pushing `main`, deploy the complete browser app and its 30 required CSV files
with:

```powershell
powershell -ExecutionPolicy Bypass -File src/deploy_github_pages.ps1
```

To check without changing or pushing anything, run:

```powershell
powershell -ExecutionPolicy Bypass -File src/deploy_github_pages.ps1 -CheckOnly
```

The script requires local `main` to match `origin/main`, builds the site in an
isolated temporary worktree, and records the deployed main commit plus SHA-256
file hashes in `deployment.json`. It replaces only the published app bundle;
the fitted models and the unused 164 MB combined decomposition CSV are not
published. A failed or interrupted push cannot silently report a successful
deployment.

Build a self-contained Markdown package for CrimRxiv/PubPub with:

```powershell
powershell -ExecutionPolicy Bypass -File src/build_crimrxiv_package.ps1
```

This creates `crimrxiv/paper.md` and preserves its relative media paths under
`crimrxiv/output/markdown/images/`. The three web-app GIFs are downloaded into
that image directory and changed to local references in the packaged Markdown.

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
After all model outputs are assembled, the runner renders `paper.pdf`,
`paper.docx`, and `paper.md` automatically, and saves the Markdown PNGs under
`output/markdown/images/`. The Word document embeds its figures so it can be
uploaded as a single file. The Word and Markdown builds use 192 DPI figures,
the Markdown build uses GitHub-compatible fenced display-math blocks, and the
PDF continues to use vector figures. Pass
`--render-report=false` only when a data-only run is intended.
The WSL sequential wrapper intentionally performs a data-only merge because
Quarto is installed on Windows; afterward run
`conda run --no-capture-output -n r2026 quarto render paper.qmd --to all`.
Before loading any results, the paper checks the current upstream RTCI files.
If their content or a local model input changed, the render automatically runs
the locked WSL workflow one crime at a time, validates all rebuilt outputs, and
then continues. Matching checkpoints are reused without fitting. Set
`RTCI_SKIP_UPDATE_CHECK=true` only when an intentional offline render should use
the current local snapshot; local signature checks still run.

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
80% of city curves. The all-city view also plots each city's observation-level
monthly residual around a zero reference line. City detail mirrors the paper example with observed/global/
city rates followed by city-versus-US-wide trend, season, and residual panels.
The full date range is always shown.

## Monthly Windows release

To refresh the upstream RTCI snapshot, rebuild stale models sequentially,
render and validate all paper formats, commit and push changed tracked outputs,
and deploy and verify GitHub Pages, run:

```powershell
powershell -ExecutionPolicy Bypass -File src/run_monthly_release.ps1
```

The release refuses to run outside `main`, with a dirty worktree, when local
`main` is ahead of `origin/main`, or while another model/release process is
active. Logs are written to the ignored
`src/data/model/monthly-release.log`. A preflight without rendering, committing,
or deploying is available with `-PreflightOnly`.

Install the current-user Windows Task Scheduler entry (first day of every
month at 9:00 AM by default) with:

```powershell
powershell -ExecutionPolicy Bypass -File src/install_monthly_release_task.ps1
```

The installer accepts `-DayOfMonth`, `-At`, and `-TaskName`. The scheduled task
runs only while the installing user is logged on so it can use that user's Git
credentials, requires a network connection, starts when possible after a missed
run, ignores overlapping starts, and has an eight-hour execution limit. Remove
it with `-Uninstall`.

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
