---
name: upstream-sync
description: Sync upstream repo into midstream with config-driven conflict resolution and LLM-assisted reconciliation of risky files.
allowed-tools: Bash Read Edit Write Grep Glob
user-invocable: true
---

# upstream-sync

Syncs upstream changes into a midstream fork. The deterministic path (shell script) handles fetching, merging, conflict resolution, and validation. The LLM handles what the script can't: reconciling risky files where both sides have legitimate changes.

## How It Works

Two layers work together:

1. **Script** (`examples/openshift/upstream-sync/sync-v2.sh`) — deterministic git operations, merge drivers, go mod tidy, build validation, state tracking
2. **LLM (you)** — reads the script's output and reconciles risky files the script flagged but couldn't merge

## Invocation

The user says `/upstream-sync` optionally followed by a subcommand:

- `/upstream-sync run` — full sync: script + LLM reconciliation + PR
- `/upstream-sync dry-run` — run script in dry-run, show report, suggest reconciliations but don't apply
- `/upstream-sync reconcile <PR>` — check out an existing sync PR branch, audit risky files, reconcile, push back
- `/upstream-sync update-config` — scan for uncovered midstream-only paths and update sync-config.yaml
- `/upstream-sync status` — show current sync state
- `/upstream-sync resume` — resume a failed or paused sync from local state

## Subcommand: reconcile

This is the primary workflow for CI-created PRs. The user provides a PR number or URL.

### Step 1: Fetch PR info and check out the branch

```bash
# Accept PR number or URL — extract the number
PR_NUMBER=<extracted>

# Get branch name and repo info
gh pr view "$PR_NUMBER" --repo opendatahub-io/spark-operator --json headRefName,baseRefName,body,url
```

Check out the PR branch locally:
```bash
# Detect the midstream remote
MIDSTREAM_REMOTE=$(git remote -v | grep 'opendatahub-io/spark-operator' | grep fetch | head -1 | cut -f1)
git fetch "$MIDSTREAM_REMOTE"
git checkout "$MIDSTREAM_REMOTE/<branch>" -b <branch> 2>/dev/null || git checkout <branch>
git reset --hard "$MIDSTREAM_REMOTE/<branch>"
```

### Step 2: Audit risky files against upstream

The CI-created PR already has the merge done. Re-run the risky file audit locally by reading `sync-config.yaml` and comparing each risky file against upstream:

```bash
# Ensure upstream is available
git fetch upstream 2>/dev/null || git remote add -f upstream https://github.com/kubeflow/spark-operator

# For each risky-ignore file in the config, check if upstream differs
MERGE_BASE=$(git merge-base "$MIDSTREAM_REMOTE/main" upstream/master)
```

For each risky file from `examples/openshift/upstream-sync/sync-config.yaml`:
1. `yq '.risky-ignore[]' examples/openshift/upstream-sync/sync-config.yaml` — get the list
2. `git diff "$MERGE_BASE..upstream/master" -- <file>` — what upstream changed
3. `git show HEAD:<file>` vs `git show upstream/master:<file>` — do they differ?

Build a local risky report from this audit.

### Step 3: Reconcile each flagged file

For each risky file where upstream made changes that aren't in the merged version:

1. Read the upstream diff to understand what changed and why
2. Read the current file on the PR branch (midstream's version after merge)
3. Read the upstream version: `git show upstream/master:<file>`
4. **Decide** whether midstream needs the change:
   - New RBAC permission for a new feature → **YES**, add it
   - New test helpers / utilities → **YES**, adopt (additive)
   - Changed image tag or version → **YES**, adopt unless midstream pins differently
   - Restructured code that midstream restructured differently → **NO**, midstream's structure is intentional
   - Changes to file sections midstream doesn't use (e.g., Helm-only config) → **SKIP**
5. If YES: Edit the file to incorporate upstream's change while preserving midstream-specific content
6. Explain the decision to the user

### Step 4: Validate

After all reconciliations:
```bash
go mod tidy
make build-operator
```

If validation fails, diagnose and fix before proceeding.

### Step 5: Commit and push

```bash
git add <reconciled-files>
git commit -m "chore: reconcile upstream changes in risky files

<list what was reconciled and why>

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"

# Push to the same PR branch
git push "$MIDSTREAM_REMOTE" <branch>
```

### Step 6: Update PR

Add a comment to the PR summarizing what was reconciled:
```bash
gh pr comment "$PR_NUMBER" --repo opendatahub-io/spark-operator --body "<reconciliation summary>"
```

## Subcommand: run

Full sync from scratch — script handles merge, LLM handles reconciliation.

### Step 1: Run the script

```bash
MIDSTREAM_REMOTE="${MIDSTREAM_REMOTE:-midstream}" bash examples/openshift/upstream-sync/sync-v2.sh --dry-run 2>&1
```

The script produces:
- `.sync-state/current.state` — state machine position
- `.sync-state/sync.log` — full log
- `.sync-state/pr-report.md` — PR report with risky file diffs
- `.sync-state/risky-report.md` — detailed upstream diffs for risky files

### Step 2: Parse results

Read the state file and report:
```bash
cat .sync-state/current.state
cat .sync-state/pr-report.md
```

| State | Action |
|---|---|
| `UP_TO_DATE` | Tell user: "Already synced, nothing to do." |
| `VALIDATED` | Proceed to reconcile risky files |
| `FAILED` | Read `.sync-state/sync.log`, diagnose, attempt LLM resolution |
| `VALIDATION_FAILED` | Read log, diagnose build failure, attempt fix |

### Step 3: Reconcile risky files

Same as reconcile Step 3 above — read `.sync-state/risky-report.md` for the diffs, then edit files.

### Step 4: Validate, commit, create PR

```bash
go mod tidy && make build-operator
git add <files> && git commit -m "chore: reconcile upstream changes in risky files"
git push "$MIDSTREAM_REMOTE" "$BRANCH_NAME"
gh pr create --base main --head "$BRANCH_NAME" \
  --title "Upstream sync $(date +%Y-%m-%d)" \
  --body-file .sync-state/pr-report.md
```

## Subcommand: resume

Resume from a failed state. Read `.sync-state/current.state` to determine where it stopped:

- `FAILED` with `REASON=unresolved_conflicts`: Read `.sync-state/unresolved.txt`, resolve conflicts with LLM, then continue
- `VALIDATION_FAILED`: Read log, fix the build, re-validate
- `MERGED`: Run the resolve step manually

After fixing, re-run:
```bash
MIDSTREAM_REMOTE=midstream bash examples/openshift/upstream-sync/sync-v2.sh --resume 2>&1
```

## Subcommand: update-config

Scans for midstream-only paths not covered by sync-config.yaml and offers to add them.

### Step 1: Detect the midstream remote and fetch upstream

```bash
MIDSTREAM_REMOTE=$(git remote -v | grep 'opendatahub-io/spark-operator' | grep fetch | head -1 | cut -f1)
git fetch upstream 2>/dev/null || git remote add -f upstream https://github.com/kubeflow/spark-operator
git fetch "$MIDSTREAM_REMOTE"
```

### Step 2: Find midstream-only files not in the config

Compare what exists in midstream but not upstream:

```bash
git diff --name-only --diff-filter=A "upstream/master..${MIDSTREAM_REMOTE}/main"
```

For each file, check if it matches any pattern in `safe-ignore` or `risky-ignore` from `examples/openshift/upstream-sync/sync-config.yaml`.

### Step 3: Report and offer to update

For each uncovered path:
1. Show the file/directory to the user
2. Determine if it's truly midstream-only (no upstream equivalent) → suggest `safe-ignore`
3. If upstream has something similar at the same path → suggest `risky-ignore`
4. Ask the user to confirm before adding

Group by directory when possible — if 5 files under `newdir/` are uncovered, suggest `"newdir/**"` rather than 5 individual entries.

### Step 4: Apply changes

Edit `examples/openshift/upstream-sync/sync-config.yaml` to add the confirmed patterns to the appropriate category.

## Key Guidelines

- **Script first, LLM second.** Always run the script (or use an existing PR) before doing anything. Don't attempt manual merges.
- **Don't guess at reconciliation.** Read both versions fully before deciding. When unsure, flag it in the PR and let the human decide.
- **Preserve midstream intent.** Midstream files differ for a reason (OpenShift, Kustomize, TLS). Never blindly take upstream's version.
- **Validate after every change.** Always run `go mod tidy` and `make build-operator` after edits.
- **Show your work.** Explain what upstream changed, why midstream needs it (or doesn't), and what you did.

## Config

File classification rules in `examples/openshift/upstream-sync/sync-config.yaml`:
- `safe-ignore` — midstream-only files, no review needed
- `risky-ignore` — files that exist in both repos, auto-resolved with ours on conflict, flagged in audit for review

Use `/upstream-sync update-config` to detect uncovered midstream-only paths.

## Remote Detection

```bash
MIDSTREAM_REMOTE=$(git remote -v | grep 'opendatahub-io/spark-operator' | grep fetch | head -1 | cut -f1)
```

Defaults to `origin` in CI, typically `midstream` locally.
