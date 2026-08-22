# Project-VR Basalt patch series

Base: `mateosss/basalt` commit
`df6e970c8da7636eb401a09e3317fbeaaf829b9a`.

`0001-runtime-landmark-recall-mode.patch` exposes the experimental
`BASALT_FEATURE_RECALL=off|front|all` runtime control used by the G2 session
settings. The default is `off`, so upstream behavior is retained unless the
user opts in.

The patch modifies Basalt source and remains subject to Basalt's upstream
BSD-3-Clause license; see `LICENSES/README.md` at the repository root.
