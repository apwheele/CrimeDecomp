# Local explorer

Run the model first so that `app/data/` contains the generated CSVs. Then
serve this directory over HTTP:

```powershell
python -m http.server 8000 --directory app
```

Open <http://localhost:8000>. The app shows the full date range, named cities,
global STL components, city detail, the city × crime × month overdispersion
term, and a clickable latitude/longitude map. The charts are native SVG; no
Plotly or other chart library is used.
