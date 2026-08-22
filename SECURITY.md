# Security and privacy

Please report a credential, private hardware identifier, or unsafe privileged
operation privately to the repository owner through GitHub before opening a
public issue.

The NVIDIA patch manager modifies `/usr/src`, rebuilds DKMS modules, and
refreshes the boot image only after an explicit `apply` action. It validates
the complete series on temporary copies first, saves source backups under
`/var/backups/reverb-g2-nvidia`, never reboots automatically, and refuses
untested driver families. Review the script and have a bootable fallback kernel
before using it.

Before a public push, maintainers should create the gitignored
`scripts/.private-patterns` file with local serials, addresses, account names,
and other sensitive literals, then run `./scripts/check-publishable.py`. The
checker scans every reachable Git blob, gzip data, and the current checkout.
