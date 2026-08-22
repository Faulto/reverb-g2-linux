# Windows capture policy

Only the sanitized USB state-transition CSV is retained. It contains timestamps,
functional device labels, and state changes—not PnP instance IDs or user paths.

The raw PowerShell console transcript, system-information export, and benchmark
screenshots were used during the investigation but are intentionally excluded
from the public release. Their relevant measurements are transcribed in
`docs/60-windows-usb-storm-control.md` and `docs/pruebas.jsonl`.
