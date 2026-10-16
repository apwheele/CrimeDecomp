# Data snapshot

`rtci_crime_trends.csv` is the local snapshot of the component monthly data
published by the [Crime Index](https://crimeindex.org/download) (formerly the
Real-Time Crime Index). Samples through June 2026 were published in the
[RTCI repository](https://github.com/AH-Datalytics/rtci), which still supplies
the agency name and coordinate files. The upstream file revisions and local
checksums are recorded in `source_metadata.json`.

`src/sync_latest_data.R` checks the newest monthly sample on the Crime Index
download page and the `main` branch of the RTCI repository, and atomically
replaces only files whose contents changed. `src/download_data.R` is the
separate pinned-snapshot path used for exact historical reproduction.
