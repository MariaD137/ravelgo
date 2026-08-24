# Repository Maintenance

## Branch Strategy

```
main        = Production (protected, deploy on push)
develop     = Integration (PRs merge here first)
feature/*   = New functionality
fix/*       = Bug fixes
hotfix/*    = Emergency production repairs
```

## Common Commands

### Start a New Feature

```bash
git checkout develop
git pull --ff-only origin develop
git checkout -b feature/<name>
# Example: git checkout -b feature/ride-scheduling
```

### Start a Bug Fix

```bash
git checkout develop
git pull --ff-only origin develop
git checkout -b fix/<name>
# Example: git checkout -b fix/driver-matching-timeout
```

### Start an Emergency Production Fix

```bash
git checkout main
git pull --ff-only origin main
git checkout -b hotfix/<name>
# Example: git checkout -b hotfix/payment-webhook-crash
```

### Update Your Branch with Latest Changes

```bash
git fetch origin
git pull --ff-only
```

### Push Your Branch

```bash
git push -u origin <branch-name>
```

### View All Branches

```bash
git branch -a
```

### View Current Status

```bash
git status
```

### View Uncommitted Changes

```bash
git diff
```

### Undo Uncommitted Changes to a File

```bash
git restore <file>
```

**Warning:** This permanently discards uncommitted changes to that file.

## Commit Message Convention

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add ride scheduling
fix: resolve driver matching timeout
refactor: extract pricing calculation
test: add trip lifecycle integration tests
docs: update deployment guide
chore: update dependencies
ci: add develop branch to CI triggers
build: optimize Docker image size
perf: add database connection pooling
```

## Pull Request Flow

1. Push your branch
2. Open PR targeting `develop` (or `main` for hotfixes)
3. CI runs automatically (lint, typecheck, test, build)
4. Get code review
5. Merge when CI passes and review approved
6. For production: open PR from `develop` to `main`

## After Merging a Hotfix

Always bring the hotfix into develop:

```bash
git checkout develop
git pull --ff-only origin develop
git merge --no-ff hotfix/<name>
git push origin develop
```
