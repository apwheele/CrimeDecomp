# CrimeDecomp agent notes

## Current state

The seven production crime models and merged outputs completed successfully on
2026-08-07. No model process should normally be running. Do not start duplicate
fits, and never fit crime types in parallel.

Production contains 458,392 city-month-offense rows from 586 cities. All 586
cities have finite cached coordinates. `src/validate_outputs.R` independently
reloads every saved model and verifies convergence, the Hessian, run signatures,
finite components, and equality between the reconstructed linear predictor and
`predict(fit, type = "link")`.

## Production model

Each crime is an ordinary aggregated-binomial `glmmTMB` model. Zeros are valid;
there is no beta-binomial response, continuity correction, or constructed
stabilized probability. The fixed portion is a global intercept, a five-column
natural cubic spline trend, and three sine/cosine harmonic pairs for annual
seasonality. Random terms are:

- `(1 | city_id)`: city intercept;
- `(1 | time_period)`: one common effect for all cities in a calendar month;
- `homdiag(... | city_trend_group)`: city-varying coefficients on the same five
  trend basis columns;
- `homdiag(... | city_season_group)`: city-varying coefficients on the same six
  seasonal basis columns;
- `(1 | cell_id)`: observation-level city/offense/month effect for
  extra-binomial variation.

The deterministic spline knots, boundary knots, and harmonic count are stored
in the `rtci_basis_spec` attribute of every fitted object. Preserve that
attribute when doing intervals, new predictions, or forecasts.

## Observed production resources

The validated WSL production fits ran strictly one crime at a time. Individual
wall times were 2:53--3:43 and peak resident memory was 4.36--4.45 GB. All seven
fits took about 24 minutes, followed by a 1:14 merge. The complete models are
about 131--133 MB each. These observed values supersede the old `gamm4`
estimates that required more than 20 GB.

## Starting or resuming under WSL

From the repository root in PowerShell, first check that no duplicate is active:

```powershell
wsl -d Ubuntu -- bash --noprofile --norc -c "ps -eo pid,ppid,etimes,time,pcpu,pmem,rss,stat,cmd | grep -E '[R]script|[/ ]R |run_models_sequential' || true"
```

Then run the instrumented sequential workflow:

```powershell
wsl -d Ubuntu -- bash -lc "cd '/mnt/d/Dropbox/Dropbox/PublicCode_Git/CrimeDecomp' && export RUN_LOG=src/data/model/sequential-glmmtmb-run.log FAILURE_LOG=src/data/model/sequential-glmmtmb-failure.log && exec bash src/run_models_sequential.sh"
```

The runner processes murder, rape, robbery, assault, burglary, theft, then
motor. Valid checkpoints are reused automatically. Each fit is atomically
saved and reload-verified before the next process starts. The final WSL merge
uses `--render-report=false`; render the paper with Windows Quarto afterward.

Useful progress checks are:

```powershell
Get-Content src/data/model/sequential-glmmtmb-run.log -Tail 50
Get-ChildItem src/data/model/models,src/data/model/parts -Filter '*.rds' -File
wsl -d Ubuntu -- bash -lc "cd '/mnt/d/Dropbox/Dropbox/PublicCode_Git/CrimeDecomp' && Rscript src/validate_outputs.R"
```

## Authoritative outputs

- Models: `src/data/model/models/<crime>_glmmtmb.rds`
- Reload-verified checkpoints: `src/data/model/parts/<crime>.rds`
- Merged decomposition: `src/data/model/decomposition.csv`
- App partitions: `src/data/app/decomposition_<crime>.csv`
- Global/city summaries: `src/data/model/` and `src/data/app/`
- Metadata and exact formulas: `src/data/model/model_metadata.json`
- Exact paper comparison components and approximate conditional interval bounds:
  `src/data/model/city_component_examples.csv`
- City trend ranking: `src/data/model/city_trend_deviations.csv`
- City seasonal ranking: `src/data/model/city_seasonal_deviations.csv`
- All-city app curves: `src/data/app/city_trends_<crime>.csv` and
  `src/data/app/city_seasons_<crime>.csv`
- Paper source: `paper.qmd`
- Final paper: `paper.pdf` and `output/pdf/paper.pdf`

The model/output directories are Git-ignored because the fitted objects and
generated CSVs are large. Do not add them to Git.

## Paper and app workflow

Render both PDF and Markdown with:

```powershell
conda run --no-capture-output -n r2026 quarto render paper.qmd
Copy-Item paper.pdf output/pdf/paper.pdf -Force
```

The paper uses the exact theme stored in `ggplot_theme.txt`. Small-multiple
plots have no plot-level title and occupy one page each. The final PDF must be
rasterized and visually checked after any paper or plotting change.
`src/build_city_examples.R` regenerates the Philadelphia trend/season/residual
comparison, the within-offense trend and seasonal outlier rankings, their paper
examples, and the all-city curve files used by the app.
The paper example CSV includes `city_trend_se`, `city_season_se`, and lower/upper
95% pointwise bounds. These propagate the diagonal conditional coefficient
variances returned by `ranef(..., condVar = TRUE)` through centered bases. They
condition on the global curve and variance parameters and are not simultaneous
bands.
The main non-stacked merge invokes it automatically before rendering.

Start the app directly from the repository root:

```powershell
python src/serve_app.py
```

The helper serves `src/` and opens `http://localhost:8000/`, which redirects to
`/app/` so the UI can load its sibling data directory. The app also supports
`#overview`, `#city`, and `#all-cities`. City detail filters cities by state;
its component panels compare city and US-wide trend, season, and residuals in
the same form as the paper's Philadelphia example. The residual comparison is
`time_effect_logit` versus `time_effect_logit + overdispersion_logit`.
The all-city page loads crime-specific trend and seasonal curve files generated
by `src/build_city_examples.R`. The redirect is implemented by the server, so
a root `index.html` is unnecessary.

## Known issues and history

- The original full `mgcv`/`gamm4` factor-smooth model worked on reduced data,
  but Linux exceeded 20 GB and Windows repeatedly crashed in `Matrix.dll`.
  The paper documents this attempt. The production low-rank random-coefficient
  representation retains global and city-varying trend/season terms while
  avoiding that computational failure.
- Windows Quarto renders the PDF successfully, but MiKTeX prints nonfatal
  `pdfcrop` warnings because Perl is not installed. Confirm the Quarto exit code
  and inspect the PDF; do not treat those warnings alone as a failed render.
- WSL may print `Failed to translate 'G:\CrimScraper'` because of a stale Windows
  PATH entry. It did not affect any validated fit.
- Do not request `predict(..., cov.fit = TRUE)` for city/global contrasts on a
  full saved model. `glmmTMB` attempts covariance calculations over the complete
  random-effect system and exhausted the WSL session in testing. The saved
  `ranef(..., condVar = TRUE)` output provides diagonal conditional variances;
  use clearly labeled diagonal pointwise bands or a parametric bootstrap instead.
- Model coordinates remain cached in `src/data/raw/agency_metadata.csv`, with
  manual overrides in `src/data/raw/agency_coordinate_overrides.csv`, although
  the current app no longer has a map page.
- Serve the app over HTTP. Opening `src/app/index.html` directly will not allow
  the browser to fetch its CSV files reliably.

## Repository safety

The worktree contains user and task changes. Preserve unrelated modifications,
especially the user-owned deletion of `Prompt.txt`. Do not use destructive Git
commands, and do not commit or push unless the user explicitly requests it.


## Other info

Google scholar profile https://scholar.google.com/citations?user=iNNqtgwAAAAJ&hl=en
