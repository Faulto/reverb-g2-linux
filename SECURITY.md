# Security and privacy

Report credentials, private hardware identifiers, or unsafe privileged behavior privately
to the repository owner before opening a public issue.

The NVIDIA patch manager edits `/usr/src`, rebuilds DKMS modules, and refreshes the boot
image only after an explicit `apply` command. It validates the full patch series on
temporary copies first, saves source backups under `/var/backups/reverb-g2-nvidia`, refuses
untested driver families, and never reboots automatically. Review the script and keep a
bootable fallback kernel or boot entry.

Maintainers should copy `scripts/.private-patterns.example` to the gitignored
`scripts/.private-patterns`, add local sensitive literals, and run
`./scripts/check-publishable.py` before publishing. The checker scans the current tree,
commit metadata, reachable Git blobs, gzip content, and UTF-16 reports.
