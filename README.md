# Monthly crime decomposition

The three deliverables are in the repository root:

- `paper.pdf`
- `paper.qmd`
- `paper.md`

All runnable code, tests, app files, and data are under `src/`.

From the repository root, rerun the all-city sample model with:

```powershell
conda run -n r2026 Rscript src/run_model.R
```

This uses every `size == "all"`, `sample == 1` city and applies no population
threshold. Monthly counts are annualized to rates per 100,000. The output is
written to `src/data/model/` and `src/data/app/`.

Serve the app from the repository root:

```powershell
python -m http.server 8000
```

Open <http://localhost:8000/src/app/>. The root `index.html` redirects there,
but this exact URL is the documented app address. It has global trend,
seasonal, and centered residual charts, city/crime detail, and a Leaflet city
map. The full date range is always shown.

To refresh the pinned input data and rebuild the city-name crosswalk, read
`src/README.md`.
