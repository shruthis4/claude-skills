---
name: repo-digest
description: >-
  Generate audience-tailored monthly digests of a public GitHub repo's changes.
  Uses a bash script for data gathering, LLM agents for digest writing, and
  verdict-based quality checks with retry.
allowed-tools: Read Write Bash Agent
user-invocable: true
metadata:
  x-artifacts: "tmp/repo-digest/"
---

# Skill: repo-digest

Generate a monthly change digest for a public GitHub repository, tailored to three audiences: Engineering, UX, and Business. Uses a deterministic bash script for data gathering and LLM agents with verdict-based quality checks for digest synthesis.

## Parse input

Extract `OWNER/REPO` from the user's prompt (e.g. `facebook/react`, `kubernetes/kubernetes`). If no repo is provided, ask the user.

Compute the date window:
```bash
SINCE_DATE=$(date -d '1 month ago' +%Y-%m-%dT00:00:00Z)
REPO="OWNER/REPO"
```

## Initialize

```bash
mkdir -p tmp/repo-digest/raw tmp/repo-digest/digests tmp/repo-digest/verdicts
```

## Phase 1: Gather data (bash script)

Run the data gathering script:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/gather-data.sh" "$REPO" "$SINCE_DATE"
```

This script fetches commits, PRs, and releases from the GitHub API in parallel using `gh` and `jq`. It categorizes commits by conventional-commit prefix and PRs by label, writes structured JSON to `tmp/repo-digest/raw/`, and handles pagination, error recovery, and empty results automatically.

After the script completes, verify that the output files exist:
```bash
ls tmp/repo-digest/raw/commits.json tmp/repo-digest/raw/prs.json tmp/repo-digest/raw/releases.json
```

If any file is missing, note it as unavailable data — do not fail. Proceed with whatever was gathered.

## Phase 2: Synthesize digests

For each audience — `engineering`, `ux`, `business` — do the following:

1. Read `${CLAUDE_SKILL_DIR}/prompts/write-digest.md`
2. Read all available raw data files from `tmp/repo-digest/raw/`
3. Follow the instructions in `write-digest.md`, passing:
   - The audience name
   - The repo name
   - The raw data (commits, PRs, releases)
4. Write the resulting digest to `tmp/repo-digest/digests/{audience}.md`

Process each audience sequentially. The digest agent needs the full raw data in context, and running sequentially keeps each digest focused.

## Phase 3: Verify digests (verdict-based)

For each digest, apply a verdict check:

1. Read `${CLAUDE_SKILL_DIR}/prompts/verify-digest.md`
2. Read the digest from `tmp/repo-digest/digests/{audience}.md`
3. Follow the verify instructions to score the digest on:
   - **Audience fit** (1-10): Is the language and detail level right for this audience?
   - **Completeness** (1-10): Does it cover the important changes?
   - **Actionability** (1-10): Can the reader act on this information?
4. Write the verdict to `tmp/repo-digest/verdicts/{audience}.json`

### Decision: iterate or accept

After each verdict:

- **All scores >= 7**: Accept the digest. Move to the next audience.
- **Any score < 7**: Re-run Phase 2 for this audience, appending the verdict feedback to the write-digest prompt so the agent knows what to fix. Then re-verify.

### Hard cap

Maximum **2 synthesis attempts per audience** (1 initial + 1 retry). If the digest still scores below 7 after retry, accept it as-is and note the low-scoring dimensions in the final output.

## Phase 4: Present output

Read all three digests from `tmp/repo-digest/digests/` and present them to the user in this format:

```
## Monthly Digest: {REPO}
### Period: {SINCE_DATE} to today

---

### Engineering Digest
{content of engineering.md}

---

### UX Digest
{content of ux.md}

---

### Business Digest
{content of business.md}
```

If any digest had a failed verdict (scores < 7 after retry), append a note:
```
> Note: The {audience} digest scored below threshold on {dimensions}. Consider reviewing manually.
```

## Guardrails

- **Script-based fetching.** All data fetching happens through `scripts/gather-data.sh`. The orchestrator does not call `gh api` directly.
- **Public repos only.** Do not attempt authenticated API calls. If the repo is private or returns 404, tell the user.
- **No secrets.** The `gh` CLI handles auth transparently for public repos.
