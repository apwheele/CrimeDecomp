# Crime decomposition app

Run the model from the repository root first:

```powershell
wsl -d Ubuntu -- bash -lc "cd '/mnt/d/Dropbox/Dropbox/PublicCode_Git/CrimeDecomp' && exec bash src/run_models_sequential.sh"
```

Then start the app from the repository root:

```powershell
python src/serve_app.py
```

The command serves `src/` so the app can reach `src/data/app/`, then opens
<http://localhost:8000/> and redirects it to the app automatically. Press
`Ctrl+C` in the terminal to stop the server; pass `--port=8080` to use a
different port. The app loads global summaries and the city catalog immediately,
then fetches the selected crime's partitioned decomposition, conditional
standard errors, and all-city curve CSVs on demand from `src/data/app/`. City
detail uses state-first filtering. The city catalog carries the RTCI source's
`Type` field, and county rows are identified as sheriff's offices in city
selectors and labels. The detail view compares city and US-wide
trend, season, and residual components in the same order and on the same logit
component scale as the paper example. Visible pointwise conditional intervals
surround the orange city trend, season, and residual curves. Its monthly table reports observed and expected counts and
rates, the city-month residual and its conditional standard error. The
all-city tab overlays faint city-specific trend, seasonal, and observation-level
monthly residual curves, provides hover labels, and displays the middle 80%
envelope. The residual panel uses zero as its reference because the global,
city, seasonal, trend, and shared time-period terms have been removed.

City and offense selections are directly linkable. For example,
`?crime=robbery&city=PAPEP0000#city` opens Philadelphia robbery, and the app
keeps these query parameters synchronized as the selection changes.
