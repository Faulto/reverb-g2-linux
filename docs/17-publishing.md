# 17 — Publishing safely

The public release boundary is the complete Git object graph, not just the
files visible at `HEAD`. Deleting a serial, capture, or generated binary in a
later commit does not remove the earlier blob from a clone.

## Current state

The maintained checkout has been scrubbed of the reference rig's known private
hardware identifiers. The inherited history is **not** release-clean: when the
maintainer's gitignored `scripts/.private-patterns` file is present,
`scripts/check-publishable.py` finds reachable historical blobs containing
those values. The existing GitHub repository has already been public, so this
is an inherited exposure rather than a reason to copy the values into another
repository.

Do not force-push a rewritten history from an ordinary working clone. The two
safe publication choices are:

1. publish a clean, history-free snapshot under a new repository or new
   release boundary; or
2. perform a coordinated rewrite in a disposable mirror, verify it, replace
   the public history, and follow the hosting provider's sensitive-data purge
   procedure.

The first choice is simpler and is the recommended initial public release.

## Required local privacy file

Copy the template and add every literal that must not ship:

```bash
cp scripts/.private-patterns.example scripts/.private-patterns
```

Use one literal per line. Include usernames, absolute home directories,
headset/controller/cable serials, MAC addresses, machine IDs, and account
identifiers. Lines beginning with `#` are ignored. The real file is gitignored;
never paste its contents into an issue or commit.

## Release checks

Run from the repository root:

```bash
./scripts/check-publishable.py
shellcheck scripts/setup-index-controllers.sh scripts/beat-saber-index.sh \
  scripts/g2-preflight.sh scripts/g2-control-panel.sh \
  scripts/install-control-panel.sh scripts/nvidia-g2-patch-manager.sh \
  scripts/sync-nvidia-initramfs.sh scripts/bootstrap-lab.sh
./scripts/setup-index-controllers.sh verify
./scripts/nvidia-g2-patch-manager.sh validate
```

The checker scans every reachable Git blob, decompresses gzip blobs for its
content scan, checks the current publishable checkout, rejects GitHub-sized
blobs over 100 MB, and verifies the public project files and script syntax.
Multiple contributor identities are normal and are not rewritten.

Also inspect the staged file list and the rendered README on a private test
remote. Raw USB captures, NVIDIA bug reports, firmware, build trees, and
third-party Windows binaries are deliberately excluded.

Set the GitHub Actions repository secret `G2_PRIVATE_PATTERNS` to the same
newline-separated literals. The workflow writes it only into the ephemeral
runner's gitignored file. Pull requests from forks do not receive repository
secrets, so the maintainer's local pre-push scan remains the authoritative
privacy gate.

## Recommended clean-snapshot release

After the audit branch is committed and reviewed, export the committed tree
into a new empty directory, initialize a new repository there, and run the
privacy checker again before adding any public remote. `git archive HEAD`
exports tracked content only and transfers no earlier Git objects.

Keep the original investigation repository as an archive. Link to it only if
its historical privacy status is acceptable; it is not required to build the
supported profile.

This approach deliberately trades commit-by-commit archaeology for a clear
privacy and reproducibility boundary. The retained documentation and research
patch archive still explain how the result was reached.

## If history must be retained

Treat a history rewrite as a separate migration:

- work only in a disposable mirror clone;
- use reviewed replacement rules stored outside the repository;
- remove or separately regenerate compressed reports, because ordinary text
  replacement does not inspect their decompressed contents;
- rescan all rewritten objects with `check-publishable.py` and the local
  pattern file;
- have collaborators stop pushing and reclone afterward; and
- coordinate the force-push and cached-view cleanup with the hosting provider.

Never use a list of matching blob IDs to delete whole blobs blindly: a match
may be an otherwise valuable source or documentation revision that should be
redacted rather than removed.

## Why the checks are strict

The original investigation once carried multi-hundred-megabyte USB captures,
compiled artifacts, and a compressed NVIDIA report. GitHub size limits apply
to historical blobs, and binary-aware searches can miss compressed private
data. The separate local pattern file also avoids the self-defeating mistake
of publishing the exact secret literals inside the script intended to find
them.
