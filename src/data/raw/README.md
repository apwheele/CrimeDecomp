# Data snapshot

`rtci_crime_trends.csv` is the local snapshot of the component monthly data
published by the [Real-Time Crime Index repository](https://github.com/AH-Datalytics/rtci).
The upstream file revision and local checksums are recorded in
`source_metadata.json`.

`src/sync_latest_data.R` checks the upstream `main` branch and atomically
replaces only files whose contents changed. `src/download_data.R` is the
separate pinned-snapshot path used for exact historical reproduction.
