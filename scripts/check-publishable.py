#!/usr/bin/env python3
"""Check that the repo can be published without leaking private data or exceeding
GitHub's blob limit. The checker modifies nothing.

    ./scripts/check-publishable.py

Private patterns are read from the gitignored `scripts/.private-patterns` file so the
sensitive values being checked are never embedded in this script.

Format of .private-patterns: one pattern per line, lines starting with # are ignored.

Checks, over ALL objects in the repo and not just HEAD:

  1. that commit author/committer metadata exists (multiple contributors are expected)
  2. that no blob exceeds 100 MB (GitHub rejects them)
  3. that no private pattern appears in the content of any blob,
     **including binaries and compressed files**

`git grep -I` skips binaries, so the checker reads every blob directly and also inspects
gzip and UTF-16 content.

No dependencies: stdlib only.
"""

import ast
from collections import defaultdict
import gzip
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

LIMIT = 100 * 1024 * 1024           # GitHub rejects blobs larger than 100 MB
BOLD, RED, RESET = "\033[1m", "\033[31m", "\033[0m"

failures = 0


def git(*args, binary=False):
    r = subprocess.run(["git", *args], capture_output=True)
    if r.returncode:
        sys.exit(f"git {' '.join(args)} failed: {r.stderr.decode(errors='replace')}")
    return r.stdout if binary else r.stdout.decode(errors="replace")


def say(t):
    print(f"\n{BOLD}== {t}{RESET}")


def ok(t):
    print(f"   ok    {t}")


def bad(t):
    global failures
    failures = 1
    print(f"   {RED}FAIL {RESET} {t}")


def content_bodies(raw):
    """Return byte representations useful for literal privacy scans."""
    bodies = [raw]
    if raw[:2] == b"\x1f\x8b":
        try:
            bodies.append(gzip.decompress(raw))
        except Exception:
            pass
    for body in list(bodies):
        if body.startswith((b"\xff\xfe", b"\xfe\xff")):
            try:
                bodies.append(body.decode("utf-16").encode())
            except UnicodeError:
                pass
    return bodies


root = Path(git("rev-parse", "--show-toplevel").strip())

candidate_paths = []
for raw_path in git(
    "ls-files", "-z", "--cached", "--others", "--exclude-standard", binary=True
).split(b"\0"):
    if raw_path:
        path = Path(raw_path.decode(errors="surrogateescape"))
        # A tracked path deleted in the working tree is not part of the next
        # snapshot. Keep untracked/new files, but do not report staged-later
        # removals as publishable artifacts.
        if (root / path).exists() or (root / path).is_symlink():
            candidate_paths.append(path)

say("current checkout")
for required in ("README.md", "LICENSE", "LICENSES/README.md"):
    if (root / required).is_file():
        ok(f"required public file exists: {required}")
    else:
        bad(f"required public file is missing: {required}")

generated_names = {"Module.symvers", "modules.order"}
generated_suffixes = (".ko", ".o", ".so", ".a", ".mod", ".mod.c")
generated = [
    path for path in candidate_paths
    if path.name in generated_names
    or path.name.endswith(generated_suffixes)
    or (path.name.startswith(".") and path.name.endswith(".cmd"))
]
if generated:
    bad("generated compiler/kernel artifacts are publishable files:")
    for path in generated:
        print(f"        {path}")
else:
    ok("no generated compiler/kernel artifacts would be published")

sensitive_artifacts = [
    path for path in candidate_paths
    if path.name.startswith("nvidia-system-info-")
    or path.name.startswith("nvidia-bug-report")
    or path.suffix.lower() in {".jpg", ".jpeg", ".png", ".heic", ".mp4", ".mov"}
]
if sensitive_artifacts:
    bad("raw host reports, console transcripts, or capture images would be published:")
    for path in sensitive_artifacts:
        print(f"        {path}")
else:
    ok("no raw host reports, console transcripts, or capture images would be published")

# Maintained entry points must not contain a literal personal home directory.
maintained_paths = {
    Path("README.md"),
    Path("CONTRIBUTING.md"),
    Path("SECURITY.md"),
    Path("reverb-g2-control-panel.desktop"),
    Path("scripts/70-wmr-reverb.rules"),
    Path("scripts/beat-saber-index.sh"),
    Path("scripts/g2-control-panel.sh"),
    Path("scripts/g2-preflight.sh"),
    Path("scripts/install-control-panel.sh"),
    Path("scripts/nvidia-g2-patch-manager.sh"),
    Path("scripts/setup-index-controllers.sh"),
    Path("scripts/sync-nvidia-initramfs.sh"),
    Path("scripts/vrserver-memory-guard.sh"),
}
personal_home = re.compile(rb"/home/[A-Za-z0-9._-]+")
personal_paths = []
local_file_links = []
missing_local_links = []
for path in candidate_paths:
    full = root / path
    if not full.is_file() or full.is_symlink():
        continue
    try:
        raw = full.read_bytes()
        if (path in maintained_paths or path.suffix.lower() == ".md") and personal_home.search(raw):
            personal_paths.append(path)
        if path.suffix.lower() == ".md" and b"](file://" in raw:
            local_file_links.append(path)
        if path.suffix.lower() == ".md":
            text = raw.decode(errors="replace")
            for target in re.findall(r"\[[^\]]*\]\(([^)]+)\)", text):
                target = target.strip()
                if target.startswith(("http://", "https://", "mailto:", "#", "file://")):
                    continue
                target = unquote(target.split("#", 1)[0])
                if target and not (full.parent / target).exists():
                    missing_local_links.append((path, target))
    except OSError:
        pass
if personal_paths:
    bad("literal /home/<user> paths remain in maintained public entry points:")
    for path in personal_paths:
        print(f"        {path}")
else:
    ok("no literal personal home-directory paths in maintained public entry points")

if local_file_links:
    bad("local file:// links remain in Markdown and would be broken for readers:")
    for path in local_file_links:
        print(f"        {path}")
else:
    ok("no local file:// links in published Markdown")

if missing_local_links:
    bad("relative Markdown links point to missing local files:")
    for path, target in missing_local_links:
        print(f"        {path} -> {target}")
else:
    ok("all relative Markdown links resolve")

syntax_errors = []
for path in candidate_paths:
    full = root / path
    if not full.is_file() or full.is_symlink():
        continue
    if path.suffix == ".sh":
        result = subprocess.run(["bash", "-n", str(full)], capture_output=True, text=True)
        if result.returncode:
            syntax_errors.append((path, result.stderr.strip()))
    elif path.suffix == ".py":
        try:
            ast.parse(full.read_text(encoding="utf-8"), filename=str(path))
        except (OSError, SyntaxError, UnicodeDecodeError) as error:
            syntax_errors.append((path, str(error)))
if syntax_errors:
    bad("script syntax checks failed:")
    for path, detail in syntax_errors:
        print(f"        {path}: {detail}")
else:
    ok("all publishable Bash and Python files parse")

say("commit identities")
authors = sorted(set(git("log", "--format=%an <%ae>").splitlines()))
for a in authors[:20]:
    print(f"        {a}")
if len(authors) > 20:
    print(f"        ... and {len(authors) - 20} more")
if authors:
    ok(f"{len(authors)} distinct author identity/identities (public contributions may add more)")
else:
    bad("no commit author metadata found")

# blob inventory: sha -> path (the first one that references it)
inventory = {}
for line in git("rev-list", "--objects", "--all").splitlines():
    sha, _, path = line.partition(" ")
    inventory.setdefault(sha, path or "<no path>")

types = git("cat-file", "--batch-check=%(objectname) %(objecttype) %(objectsize)",
            "--batch-all-objects")
blobs = {}
for line in types.splitlines():
    sha, kind, size = line.split()
    if kind == "blob":
        blobs[sha] = int(size)

say("blob sizes")
large = [(s, n) for s, n in blobs.items() if n > LIMIT]
if large:
    bad("blobs over GitHub's 100 MB limit:")
    for s, n in sorted(large, key=lambda x: -x[1]):
        print(f"        {n / 1048576:8.1f} MB  {inventory.get(s, '?')}")
else:
    ok(f"none of the {len(blobs)} blobs exceeds 100 MB")
size = next((l.split(": ", 1)[1] for l in git("count-objects", "-vH").splitlines()
             if l.startswith("size-pack:")), "?")
print(f"   {'.git (size-pack)':<38} {size}")

say("private patterns, across every blob")
patterns_file = root / "scripts" / ".private-patterns"
if not patterns_file.exists():
    print(f"   (no {patterns_file.relative_to(root)}, skipped)")
    print("   Create that file with one pattern per line to check for addresses,")
    print("   serial numbers, MACs or anything else that must not ship. It is gitignored.")
else:
    ignored = subprocess.run(["git", "check-ignore", "-q", str(patterns_file)]).returncode == 0
    ok("the patterns file is gitignored") if ignored else \
        bad("the patterns file is NOT gitignored — it would ship with the repo")

    patterns = [l.strip().encode() for l in patterns_file.read_text().splitlines()
                if l.strip() and not l.startswith("#")]
    metadata = git("log", "--format=%an <%ae>%n%cn <%ce>").encode()
    metadata_dirty = [pat.decode(errors="replace") for pat in patterns if pat in metadata]
    if metadata_dirty:
        bad("private patterns occur in commit author/committer metadata:")
        for pat in metadata_dirty:
            print(f"        {pat}")
    else:
        ok("no private pattern in commit author/committer metadata")
    dirty = []
    for sha in blobs:
        raw = git("cat-file", "blob", sha, binary=True)
        bodies = content_bodies(raw)
        for pat in patterns:
            if any(pat in b for b in bodies):
                dirty.append((sha, inventory.get(sha, "?"), pat.decode()))

    if dirty:
        dirty_blobs = {sha for sha, _, _ in dirty}
        paths = defaultdict(lambda: {"blobs": set(), "patterns": set()})
        for sha, path, pat in dirty:
            paths[path]["blobs"].add(sha)
            paths[path]["patterns"].add(pat)
        bad(f"{len(dirty_blobs)} distinct blob(s) contain private patterns:")
        for path in sorted(paths)[:30]:
            details = paths[path]
            print(
                f"        {path}: {len(details['blobs'])} historical blob(s), "
                f"{len(details['patterns'])} private pattern(s)"
            )
        if len(paths) > 30:
            print(f"        ... and {len(paths) - 30} more path(s)")

        # A blob that no commit references is not in the inventory, so it would never be
        # pushed — but it is still sitting in this clone's object store, typically left
        # behind by an earlier filter-repo. That needs a gc, not another history rewrite,
        # and telling you to force-push would not remove it.
        reachable = sorted({s for s, _, _ in dirty if s in inventory})
        unreachable = sorted({s for s, _, _ in dirty if s not in inventory})

        if unreachable:
            print(f"\n        {len(unreachable)} of these are UNREACHABLE (path '?'): no commit")
            print("        references them, so they would not be pushed. They are local")
            print("        leftovers. Drop them from this clone with:")
            print("            git reflog expire --expire=now --all")
            print("            git gc --prune=now")
        if reachable:
            print(f"\n        {len(reachable)} are reachable and WOULD be published.")
            print("        Safest release path: publish a clean snapshot as a new repository")
            print("        or an explicitly reviewed orphan branch, so these objects are never")
            print("        transferred. If existing history must be retained, rewrite a")
            print("        disposable mirror, review every replacement, handle compressed")
            print("        archives separately, and coordinate before any force-push.")
    else:
        ok(f"no private pattern in any of the {len(blobs)} blobs (binaries and .gz included)")

    current_dirty = []
    for path in candidate_paths:
        full = root / path
        if not full.is_file() or full.is_symlink():
            continue
        try:
            raw = full.read_bytes()
        except OSError:
            continue
        bodies = content_bodies(raw)
        for pat in patterns:
            if any(pat in body for body in bodies):
                current_dirty.append((path, pat.decode(errors="replace")))
    if current_dirty:
        bad(f"{len(current_dirty)} current publishable file(s) contain private patterns:")
        for path, pat in current_dirty:
            print(f"        {path}  <- {pat}")
    else:
        ok("no private pattern in the current publishable checkout")

say("verdict")
if failures:
    print("   DO NOT publish until the above is resolved.")
    print("   Resolve the findings before publishing; see CONTRIBUTING.md and SECURITY.md.")
else:
    print("   Publishable.")
sys.exit(failures)
