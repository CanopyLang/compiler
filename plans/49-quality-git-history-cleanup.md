# Plan 49: Git History Cleanup (Large Files)

## Priority: HIGH
## Effort: Small (2-4 hours)
## Risk: HIGH — rewrites git history, requires force push

## Problem

The .git directory is 474MB due to historical blobs:
- 281MB zip backup file
- ~45MB compiled binaries (terminal/src/Main, committed 7 times)
- ~30MB .stack-work binaries
- Debug binaries

All are historical (not currently tracked) but inflate clone time and push/pull operations.

## Implementation Plan

### Step 1: Inventory large objects

```bash
git rev-list --objects --all | \
  git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | \
  sed -n 's/^blob //p' | \
  sort -rnk2 | \
  head -20
```

### Step 2: Choose cleanup method

**Option A**: `git filter-repo` (preferred)
```bash
pip install git-filter-repo
git filter-repo --strip-blobs-bigger-than 10M
```

**Option B**: BFG Repo Cleaner
```bash
java -jar bfg.jar --strip-blobs-bigger-than 10M .
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

### Step 3: Verify .gitignore

Ensure the following are in .gitignore:
```
*.dat
*.zip
.stack-work/
canopy-stuff/
elm-stuff/
dist-newstyle/
result
```

### Step 4: Force push (with team coordination)

```bash
git push --force-with-lease origin master
```

**WARNING**: This requires coordination with all contributors. Everyone must re-clone or reset their local copies.

### Step 5: Verify size reduction

```bash
du -sh .git  # Should drop from 474MB to <50MB
```

## Dependencies
- Must coordinate with all contributors before executing
- Must have a backup of the repository

## Risks
- Rewrites ALL commit hashes
- All open PRs will need rebasing
- CI caches based on commit SHAs will be invalidated
