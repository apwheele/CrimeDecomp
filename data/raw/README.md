# Data snapshot

`rtci_crime_trends.csv` is a one-time snapshot of the component monthly data
published by the [Real-Time Crime Index repository](https://github.com/AH-Datalytics/rtci).
The source commit and local file checksum are recorded in `source_metadata.json`.

The download script is intentionally idempotent: it will not replace the local
snapshot unless the file is removed first.

