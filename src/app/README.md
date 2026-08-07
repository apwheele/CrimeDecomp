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
then fetches the selected crime's partitioned decomposition and all-city curve
CSVs on demand from `src/data/app/`. City detail uses state-first filtering. The
detail view compares city and US-wide trend, season, and residual components in
the same order and on the same logit component scale as the paper example. The
all-city tab overlays faint city-specific trend and seasonal curves, provides
hover labels, and displays the middle 80% envelope around the global curve.
