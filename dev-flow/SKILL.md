---
name: dev-flow
description: Full dev lifecycle — create ticket, branch, PR, monitor reviews. Orchestrates git ops (script) and Jira ops (MCP).
allowed-tools: Bash Read Grep Glob
user-invocable: true
---

# dev-flow

Orchestrates the full development lifecycle: create ticket → branch → code → PR → review → merge.

Git operations are handled by `scripts/dev-flow.sh`. All Jira operations are handled by you via Atlassian MCP tools.

## Invocation

Run the script and react to its output:

```bash
bash ~/.claude/skills/dev-flow/scripts/dev-flow.sh <subcommand> [args...]
```

## State Files

Per-ticket state files in `~/.claude/dev-flow/<JIRAKEY>.state`. Each contains:
```
JIRA_KEY, BRANCH, STATE, PR_URL, PR_NUMBER, REPO_URL, REPO_PATH
```

States: `created` → `started` → `pr-created` → `in-review` → `merged`

The script resolves which ticket to use: explicit arg > current branch name > error with list.

## Reacting to Script Output

The script emits signals that tell you what to do next:

### `AGENT_TAKEOVER: create`
The script also emits `REPO_PATH` and `REPO_URL` from the current directory.

1. Ask the user for a **summary** and **description**
2. Use these defaults (user can override any):
   - Project: `RHOAIENG`
   - Issue type: `Story`
   - Components: `["Data Processing", "Kubeflow Spark Operator"]`
3. Create the ticket using `createJiraIssue` MCP tool with `cloudId: "redhat.atlassian.net"`
4. After creation, write the state file:
   ```bash
   cat > ~/.claude/dev-flow/<JIRAKEY>.state <<EOF
   JIRA_KEY=<created-key>
   BRANCH=
   STATE=created
   PR_URL=
   PR_NUMBER=
   REPO_URL=<from script output>
   REPO_PATH=<from script output>
   EOF
   ```
5. Tell the user: "Ticket created. Run `/dev-flow start <KEY>` to begin."

### `AGENT_ACTION: transition_jira_in_progress <JIRAKEY>`
After `start` completes git ops:

1. Use `getTransitionsForJiraIssue` with `cloudId: "redhat.atlassian.net"` to find the transition to "In Progress"
2. Use `transitionJiraIssue` to apply it
3. Confirm: "Jira transitioned to In Progress"

### `AGENT_ACTION: link_pr_and_transition_review <JIRAKEY> <PR_URL>`
After `pr` creates the PR:

1. Use `editJiraIssue` to set `customfield_10875` (Git Pull Request) to the PR URL
2. Use `getTransitionsForJiraIssue` to find the transition to "In Review" (or "Code Review" — check available names)
3. Use `transitionJiraIssue` to apply it
4. Update the state file — use `sed` to change `STATE=pr-created` to `STATE=in-review` in `~/.claude/dev-flow/<JIRAKEY>.state`
5. Confirm: "PR linked to Jira, status → In Review"

### `AGENT_ACTION: show_jira_status <JIRAKEY>`
During `status`:

1. Use `getJiraIssue` to fetch current status, assignee, and priority
2. Display alongside the git/PR info the script already printed

### `AGENT_TAKEOVER: plan`
The script provides `JIRA_KEY` and `REPO_PATH`:

1. Use `getJiraIssue` with `cloudId: "redhat.atlassian.net"` to fetch the full ticket (description, acceptance criteria, linked issues)
2. Read the codebase at `REPO_PATH` to understand relevant files
3. Suggest an approach: what to change, which files, any risks
4. Keep it concise — a few bullet points, not a design doc

### `AGENT_TAKEOVER: monitor`
The script provides `JIRA_KEY`, `PR_NUMBER`, `PR_URL`, `REPO_PATH`:

1. `cd` to `REPO_PATH`, then run: `gh pr view <PR_NUMBER> --json comments,reviews,reviewRequests,reviewDecision`
2. Summarize:
   - How many unresolved review comments
   - What the feedback says (group by reviewer)
   - What specific actions are needed
3. If no new feedback: "No new review comments."

### `AGENT_TAKEOVER: suggest_next`
No active tickets. The script already checked:

1. Check if there are any approved PRs: `gh pr list --author @me --json number,title,reviewDecision,url`
2. Suggest: "No active ticket. You can `/dev-flow create` a new one, or `/dev-flow start JIRAKEY` an existing one."
3. If there are approved PRs, mention them.

## Errors

If the script exits with an error, report it to the user. Common cases:
- Invalid Jira key format
- Uncommitted changes blocking `start`
- No commits on branch when running `pr`
- Out-of-order command (e.g., `pr` before `start`)
- Wrong repo (ticket belongs to a different project)
