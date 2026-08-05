# Crime decomposition app

Run the model from the repository root first:

```powershell
conda run -n r2026 Rscript src/run_model.R
```

Then serve the repository root:

```powershell
python -m http.server 8000
```

Open <http://localhost:8000/src/app/>. The app loads its generated CSV files
from `src/data/app/`.
