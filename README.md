# Monthly crime decomposition

This project estimates a global STL-style decomposition of monthly crime rates
for every city in the RTCI national sample. It also writes the complete
city-by-crime-by-month overdispersion term for inspection in the app.

## Run it

The only command needed after the pinned data snapshot is available is:

```powershell
conda run -n r2026 Rscript scripts/run_model.R
```

The script uses every `size == all`, `sample == 1` city. There is no population
threshold. Rates are annualized from monthly counts by multiplying by 12.

Outputs are written to `app/data/` and `output/model/`:

- `global_stl.csv`: observed, trend, seasonal, and global rates
- `decomposition.csv`: every city × crime × month, including `overdispersion_logit`
- `cities.csv`: city names and coordinates

Open the app locally:

```powershell
python -m http.server 8000 --directory app
```

Then visit <http://localhost:8000>. It has three views: Global STL, City
detail, and City map. The controls only select crime type and city; the full
date range is always shown.

## Optional focused model terms

For smaller exploratory samples, `--city-effects=true --city-slopes=true`
adds pooled city effects and city-by-crime time slopes. The explicit cell-level
random effect can be requested with `--overdispersion=true`, but the default
deliverable retains the complete city × crime × month overdispersion term as
an interpretable logit departure without an arbitrary threshold.

## Paper

The rendered paper is [output/paper/paper.pdf](G:\CrimeDecomp\output\paper\paper.pdf)
and [output/paper/paper.md](G:\CrimeDecomp\output\paper\paper.md). Render it
again with Quarto from the project-specific R environment.

