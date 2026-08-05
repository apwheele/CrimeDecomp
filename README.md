# Crime decomposition

This project estimates a stacked, aggregated-binomial spline decomposition of
monthly crime counts. It separates crime-specific global trends, cyclic monthly
seasonality, agency-level departures, and unusually large monthly residuals.

The initial snapshot uses the Real-Time Crime Index component data published at
<https://github.com/AH-Datalytics/rtci>. The source commit is pinned in
`data/raw/source_metadata.json`.

## Quick start

Create the conda environment from `environment.yml` if it is not available:

```powershell
conda env create -f environment.yml
conda activate crime-decomp
```

The one-time data snapshot is already in this workspace. To recreate it from
the pinned source commit, delete the local CSV and run:

```powershell
conda run -n crime-decomp Rscript scripts/download_data.R
```

Run the initial model for agencies with populations of at least 250,000:

```powershell
conda run -n crime-decomp Rscript scripts/run_model.R
```

Useful options include `--min-population=100000`, `--min-population=0`,
`--overdispersion=true`, `--outlier-threshold=3`, and `--nthreads=2`. The
deliverable fit leaves the agency-month random effect off for runtime; enable
it on a focused sample with `--overdispersion=true` as the practical stacked-
data analogue of the `(1|Row)` term in the motivating model.

Render the paper to both formats:

```powershell
quarto render paper/paper.qmd --to pdf --output-dir output/paper
quarto render paper/paper.qmd --to gfm --output-dir output/paper
```

Start the local visualization app after running the model:

```powershell
python -m http.server 8000 --directory app
```

Open <http://localhost:8000>. The app uses native SVG and browser controls;
there is no Plotly dependency.

## Model

For agency `i`, crime type `c`, and month `t`, the response is modeled as
`Y_ict ~ Binomial(N_it, p_ict)` with a logit link. The linear predictor
contains crime-specific smooths of the continuous month index and year, a
cyclic smooth of month, agency and agency-by-crime random effects, and a
regularized agency-by-crime random time slope. The optional agency-month random
effect is the overdispersion/residual term. Predictions excluding agency terms
provide the global baseline, while predictions retaining agency terms provide
the agency departure from that baseline.
