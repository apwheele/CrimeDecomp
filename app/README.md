# Local explorer

Run the model first so that `app/data/` contains the generated CSVs. Then
serve this directory over HTTP:

```powershell
python -m http.server 8000 --directory app
```

Open <http://localhost:8000>. A local server is needed because browsers block
`fetch()` for local files. The charts are native SVG; no Plotly or other chart
library is used.

