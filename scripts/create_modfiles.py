#!/usr/bin/env python3
"""
Generate the modification notices required when redistributing a modified
version of ONLYOFFICE.

For the top-level repository and every (recursive) submodule, this writes one
plain-text file listing the changes made on the Euro-Office branch relative to
the mirrored upstream branch, with dates, authors, commit links and the files
each change touched.  All files are collected into a gzipped tarball.

Assumed repository layout:
    origin/master   mirror of the corresponding ONLYOFFICE repository
    HEAD            the Euro-Office branch (or the commit a submodule is
                    pinned to, which is what actually ships)

Usage:
    git fetch origin
    git submodule foreach --recursive 'git fetch -q origin'
    python3 create_modfile.py
"""

import re
import subprocess
import sys
import tarfile
from collections import defaultdict
from os.path import basename, dirname
from pathlib import Path

# --- configuration ---------------------------------------------------------

BASELINE = "origin/master"          # ref tracking unmodified ONLYOFFICE
OUTDIR = Path("modifications")      # per-component notices are written here
ARCHIVE = "MODIFICATIONS.tar.gz"    # final deliverable
SEP = "\x01"                        # record separator; never valid in a path
ABBREV = "12"                       # commit id length (collision-safe, short)


# --- git helpers -----------------------------------------------------------


def git(repo, *args, check=True):
    """Run git in `repo` and return stdout; abort with git's own error text."""
    r = subprocess.run(["git", "-C", repo, *args],
                       capture_output=True, text=True)
    if check and r.returncode:
        sys.exit(f"git -C {repo} {' '.join(args)}:\n{r.stderr.strip()}")
    return r.stdout


def repo_paths():
    """Every submodule, top-relative."""
    out = git(".", "submodule", "foreach", "--recursive", "--quiet",
              "echo $displaypath")
    for line in out.splitlines():
        if line.strip():
            yield line.strip()


def has_baseline(repo):
    return subprocess.run(["git", "-C", repo, "rev-parse", "--verify", "-q",
                           BASELINE], capture_output=True).returncode == 0


def browse_url(repo):
    """Normalise origin's URL into something a browser can open."""
    url = git(repo, "remote", "get-url", "origin").strip()
    url = re.sub(r"^git@([^:]+):", r"https://\1/", url)
    return re.sub(r"\.git$", "", url)

def identity(repo):
    """Repositories with the same origin and same range have the same notice."""
    return (browse_url(repo),
            git(repo, "rev-parse", BASELINE).strip(),
            git(repo, "rev-parse", "HEAD").strip())


# --- report ----------------------------------------------------------------


def collect(repo):
    """Parse `git log` into a list of commits with their file changes.

    --cherry-pick --right-only drops commits that are patch-identical to
    something on the baseline side, so backported upstream fixes are not
    claimed as our own.

    --diff-merges=combined makes a merge report only the files that differ
    from *every* parent, i.e. edits made during conflict resolution.  Routine
    merges of the upstream mirror therefore contribute nothing, instead of
    dragging in the whole upstream delta.
    """
    out = git(repo,
              "-c", "core.quotePath=false",
              "-c", f"core.abbrev={ABBREV}",
              "log",
              "--cherry-pick", "--right-only", "--reverse",
              "--date=short", "--name-status", "-M",
              "--diff-merges=combined",
              f"--pretty=format:{SEP}%ad\t%h\t%an\t%s",
              f"{BASELINE}...HEAD")

    commits = []
    for line in out.splitlines():
        if line.startswith(SEP):
            date, sha, author, subject = line[1:].split("\t", 3)
            commits.append({"date": date, "hash": sha, "author": author,
                            "subj": subject, "files": []})
        elif line.strip() and commits:
            parts = line.split("\t")
            commits[-1]["files"].append(
                (parts[0], parts[1], parts[2] if len(parts) > 2 else None))
    return commits


def compress_refs(numbers):
    """[3,4,5,9] -> '3-5,9'.  Change numbers are mostly consecutive runs."""
    ns = sorted(set(numbers))
    out, i = [], 0
    while i < len(ns):
        j = i
        while j + 1 < len(ns) and ns[j + 1] == ns[j] + 1:
            j += 1
        out.append(str(ns[i]) if j == i else f"{ns[i]}-{ns[j]}")
        i = j + 1
    return ",".join(out)


def render(paths, commits):
    repo = paths[0]
    base = browse_url(repo)
    label = "(top level)" if repo == "." else repo

    authors = {}
    for c in commits:
        authors.setdefault(c["author"], f"a{len(authors) + 1}")

    files = defaultdict(lambda: defaultdict(list))
    for i, c in enumerate(commits, 1):
        for status, p1, p2 in c["files"]:
            path = p2 if (status.startswith("R") and p2) else p1
            files[path][status[0]].append(i)

    L = [
        f"Component:   {base.rsplit('/', 1)[-1]}",
        f"Repository:  {base}",
        f"Baseline:    {BASELINE} (unmodified ONLYOFFICE upstream)",
        "Located at:  " + "\n             ".join(paths),
        "",
        "Changes made to the original ONLYOFFICE software by Euro-Office and",
        "contributors.  Section 1 lists every change with its date, commit id",
        "and author.  Section 2 lists every affected file and the numbers of",
        "the changes that touched it.",
        "",
        "Merges of the upstream branch bring in unmodified ONLYOFFICE code and",
        "are listed only where code was altered while resolving conflicts.",
        "",
        f"Full commit:  {base}/commit/<id>",
        "Authors:      " + ("  ".join(f"{k} {n}" for n, k in authors.items())
                            or "-"),
        "Status codes: A added   M modified   D deleted   R renamed",
        "",
    ]

    if not commits:
        L.append("No changes against the baseline.")
        return "\n".join(L) + "\n"

    L += ["== 1. CHANGES", ""]
    for i, c in enumerate(commits, 1):
        L.append(f"{i} {c['date']} {c['hash']} "
                 f"{authors[c['author']]} {c['subj']}")
        for status, p1, p2 in c["files"]:
            if status.startswith("R") and p2:
                L.append(f"    R {p1} -> {p2}")

    L += ["", "== 2. FILES", ""]
    bydir = defaultdict(list)
    for path in files:
        bydir[dirname(path)].append(path)
    for d in sorted(bydir):
        L.append(f"{d}/" if d else "(root)")
        for path in sorted(bydir[d]):
            st = files[path]
            if set(st) == {"M"}:                       # the common case
                refs = compress_refs(st["M"])
            else:
                refs = "  ".join(f"{k}:{compress_refs(v)}"
                                 for k, v in sorted(st.items()))
            L.append(f"  {basename(path)}  {refs}")

    return "\n".join(L) + "\n"


# --- main ------------------------------------------------------------------


def main():
    paths = list(repo_paths())
    missing = [p for p in paths if not has_baseline(p)]
    if missing:
        sys.exit(f"{BASELINE} not found in:\n  " + "\n  ".join(missing) +
                 "\n\nRun 'git fetch origin' there, or check the branch name.")

    OUTDIR.mkdir(exist_ok=True)

    groups = {}
    for p in paths:
        groups.setdefault(identity(p), []).append(p)

    index, used = [], set()
    for (url, _, _), mounts in groups.items():
        commits = collect(mounts[0])
        if not commits:
            continue
        stem = url.rstrip("/").rsplit("/", 1)[-1]
        name, n = stem, 2
        while name in used:
            name, n = f"{stem}-{n}", n + 1
        used.add(name)
        (OUTDIR / f"{name}.txt").write_text(render(mounts, commits),
                                            encoding="utf-8")
        index.append((name, len(commits), mounts))

    index.sort(key=lambda e: -e[1])
    width = max(len(n) for n, _, _ in index)
    idx = ["Modifications to ONLYOFFICE, by component.",
           "",
           "One file per repository.  Each lists the changes made to that",
           "component with their dates, authors and affected files.",
           ""]
    for name, count, mounts in index:
        idx.append(f"  {name:<{width}}  {count:>5} changes  {name}.txt")
        for m in mounts:
            idx.append(f"  {'':<{width}}  {'':>5}          at {m}")
    (OUTDIR / "INDEX.txt").write_text("\n".join(idx) + "\n", encoding="utf-8")


    with tarfile.open(ARCHIVE, "w:gz") as tf:
        tf.add(OUTDIR / "INDEX.txt", arcname=f"{OUTDIR.name}/INDEX.txt")
        for name, _, _ in index:
            tf.add(OUTDIR / f"{name}.txt", arcname=f"{OUTDIR.name}/{name}.txt")

    total = sum(n for _, n, _ in index)
    print(f"{len(index)} components, {total} changes -> {ARCHIVE}")


if __name__ == "__main__":
    main()