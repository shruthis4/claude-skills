#!/bin/bash
# dev-flow: Pure git operations + state file management
# All Jira operations are handled by the agent via MCP (see SKILL.md)
# State files stored per-ticket in ~/.claude/dev-flow/

set -e

SUBCOMMAND="${1:-}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
info()  { echo -e "${GREEN}$1${NC}"; }
warn()  { echo -e "${YELLOW}$1${NC}"; }
label() { echo -e "${CYAN}$1${NC}"; }

# --- State directory ---

STATE_DIR="${HOME}/.claude/dev-flow"
mkdir -p "$STATE_DIR"

# --- Git helpers ---

find_git_root() {
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        [[ -d "$dir/.git" ]] && echo "$dir" && return 0
        dir="$(dirname "$dir")"
    done
    error "Not in a git repository"
}

get_default_branch() {
    git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main"
}

get_repo_url() {
    git remote get-url origin 2>/dev/null || echo ""
}

# --- State file: ~/.claude/dev-flow/<JIRAKEY>.state ---

state_file_for() {
    echo "${STATE_DIR}/${1}.state"
}

read_state() {
    local file="$1"
    JIRA_KEY="" BRANCH="" STATE="" PR_URL="" PR_NUMBER="" REPO_URL="" REPO_PATH=""
    [[ -f "$file" ]] && source "$file" || true
}

write_state() {
    local file="$1"
    cat > "$file" <<EOF
JIRA_KEY=${JIRA_KEY:-}
BRANCH=${BRANCH:-}
STATE=${STATE:-}
PR_URL=${PR_URL:-}
PR_NUMBER=${PR_NUMBER:-}
REPO_URL=${REPO_URL:-}
REPO_PATH=${REPO_PATH:-}
EOF
}

# --- Resolve which ticket we're working on ---
# Priority: 1) explicit arg  2) current branch name  3) error with list

resolve_jira_key() {
    local explicit_key="$1"

    if [[ -n "$explicit_key" ]]; then
        echo "$explicit_key"
        return 0
    fi

    local branch
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    if [[ "$branch" =~ ^([A-Z]+-[0-9]+) ]]; then
        local key="${BASH_REMATCH[1]}"
        if [[ -f "$(state_file_for "$key")" ]]; then
            echo "$key"
            return 0
        fi
    fi

    local active_files=("${STATE_DIR}"/*.state)
    if [[ -e "${active_files[0]}" ]]; then
        warn "Cannot determine ticket from current branch. Active tickets:"
        for f in "${active_files[@]}"; do
            source "$f"
            echo "  ${JIRA_KEY}  (state: ${STATE}, branch: ${BRANCH})"
        done
        error "Specify a ticket: /dev-flow <command> JIRAKEY"
    fi

    error "No active tickets. Run '/dev-flow create' or '/dev-flow start JIRAKEY' first."
}

# --- Validation ---

validate_jira_key_format() {
    local key="$1"
    [[ -z "$key" ]] && error "JIRA key required"
    [[ "$key" =~ ^[A-Z]+-[0-9]+$ ]] || error "Invalid JIRA key format. Expected: PROJECT-123, got: $key"
}

validate_allowed_states() {
    local command="$1"
    local current="$2"
    shift 2
    local allowed_states=("$@")

    for s in "${allowed_states[@]}"; do
        [[ "$current" == "$s" ]] && return 0
    done

    error "Cannot run '${command}' in state '${current}'. Allowed states: ${allowed_states[*]}"
}

validate_repo() {
    local expected_path="$1"
    local git_root
    git_root=$(find_git_root)
    if [[ "$git_root" != "$expected_path" ]]; then
        error "Ticket belongs to repo at ${expected_path}\n       You're in: ${git_root}\n       cd to the right repo first."
    fi
}

# --- Subcommands ---

cmd_create() {
    echo "REPO_PATH=$(find_git_root)"
    echo "REPO_URL=$(cd "$(find_git_root)" && get_repo_url)"
    echo "AGENT_TAKEOVER: create"
}

cmd_start() {
    local jira_key="$1"
    local description="${2:-}"

    validate_jira_key_format "$jira_key"

    local sf
    sf=$(state_file_for "$jira_key")
    if [[ -f "$sf" ]]; then
        read_state "$sf"
        if [[ "$STATE" != "created" ]]; then
            error "Ticket ${jira_key} already in state '${STATE}'. Run '/dev-flow status ${jira_key}' to see details."
        fi
    fi

    local git_root
    git_root=$(find_git_root)
    cd "$git_root"

    if git rev-parse HEAD &>/dev/null && ! git diff-index --quiet HEAD 2>/dev/null; then
        warn "You have uncommitted changes. Stash or commit them first."
        git status --short
        exit 1
    fi

    info "Fetching latest from origin..."
    git fetch origin

    local default_branch
    default_branch=$(get_default_branch)

    info "Updating ${default_branch}..."
    git checkout "$default_branch"
    git pull origin "$default_branch"

    local branch_name
    if [[ -n "$description" ]]; then
        local sanitized
        sanitized=$(echo "$description" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//')
        branch_name="${jira_key}-${sanitized}"
    else
        branch_name="${jira_key}"
    fi

    info "Creating branch: ${branch_name}"
    git checkout -b "$branch_name"

    JIRA_KEY="$jira_key"
    BRANCH="$branch_name"
    STATE="started"
    PR_URL=""
    PR_NUMBER=""
    REPO_URL=$(get_repo_url)
    REPO_PATH="$git_root"
    write_state "$sf"

    echo ""
    label "Branch: ${branch_name}"
    label "Ticket: ${jira_key}"
    echo "AGENT_ACTION: transition_jira_in_progress ${jira_key}"
}

cmd_pr() {
    local jira_key
    jira_key=$(resolve_jira_key "${2:-}")

    local sf
    sf=$(state_file_for "$jira_key")
    read_state "$sf"
    validate_allowed_states "pr" "$STATE" "started"
    validate_repo "$REPO_PATH"

    cd "$REPO_PATH"

    local current_branch
    current_branch=$(git rev-parse --abbrev-ref HEAD)
    if [[ "$current_branch" != "$BRANCH" ]]; then
        error "Expected branch '${BRANCH}' but on '${current_branch}'"
    fi

    local default_branch
    default_branch=$(get_default_branch)

    local ahead
    ahead=$(git rev-list --count "origin/${default_branch}..HEAD" 2>/dev/null || echo "0")
    if [[ "$ahead" == "0" ]]; then
        error "No commits on this branch beyond ${default_branch}. Commit your changes first."
    fi

    info "Pushing to origin..."
    git push -u origin "$BRANCH"

    if ! command -v gh &>/dev/null; then
        error "gh CLI not found. Install it: https://cli.github.com/"
    fi

    info "Creating pull request..."
    local pr_body=""
    if [[ -n "$JIRA_KEY" ]]; then
        pr_body="Related JIRA: ${JIRA_URL:-https://redhat.atlassian.net}/browse/${JIRA_KEY}"
    fi

    local pr_output
    pr_output=$(gh pr create --base "$default_branch" --head "$BRANCH" --fill --body "$pr_body" 2>&1) || {
        warn "Failed to create PR:"
        echo "$pr_output"
        exit 1
    }

    local pr_url
    pr_url=$(echo "$pr_output" | grep -oE 'https://github\.com/[^ ]+/pull/[0-9]+' | head -1)
    local pr_number
    pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')

    PR_URL="$pr_url"
    PR_NUMBER="$pr_number"
    STATE="pr-created"
    write_state "$sf"

    echo ""
    info "PR created: ${pr_url}"
    echo "AGENT_ACTION: link_pr_and_transition_review ${JIRA_KEY} ${pr_url}"
}

cmd_status() {
    local explicit_key="${2:-}"

    # No arg + no active tickets = show merge-ready PRs
    if [[ -z "$explicit_key" ]]; then
        local active_files=("${STATE_DIR}"/*.state)
        if [[ ! -e "${active_files[0]}" ]]; then
            label "No active dev-flow tickets."
            echo ""
            label "Merge-ready PRs:"
            if command -v gh &>/dev/null; then
                local approved
                approved=$(gh pr list --author @me --json number,title,reviewDecision,url \
                    --jq '.[] | select(.reviewDecision == "APPROVED") | "  #\(.number) \(.title)\n    \(.url)"' 2>/dev/null || echo "")
                if [[ -n "$approved" ]]; then
                    echo "$approved"
                else
                    echo "  (none)"
                fi
            fi
            return
        fi

        # Show all active tickets
        label "=== Active tickets ==="
        for f in "${active_files[@]}"; do
            read_state "$f"
            echo "  ${JIRA_KEY}  state=${STATE}  branch=${BRANCH}"
        done

        # Try to resolve from branch
        local branch
        branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [[ "$branch" =~ ^([A-Z]+-[0-9]+) ]]; then
            explicit_key="${BASH_REMATCH[1]}"
        else
            return
        fi
    fi

    local sf
    sf=$(state_file_for "$explicit_key")
    if [[ ! -f "$sf" ]]; then
        error "No state file for ${explicit_key}"
    fi
    read_state "$sf"

    echo ""
    label "=== ${JIRA_KEY} ==="
    echo "State:   ${STATE}"
    echo "Branch:  ${BRANCH}"
    echo "Repo:    ${REPO_PATH}"

    if [[ -n "$REPO_PATH" && -d "$REPO_PATH" ]]; then
        cd "$REPO_PATH"
        local current_branch
        current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        echo "Current: ${current_branch}"

        if [[ "$current_branch" == "$BRANCH" ]]; then
            local default_branch
            default_branch=$(get_default_branch)
            echo ""
            label "Changes:"
            git diff --stat "origin/${default_branch}..HEAD" 2>/dev/null || echo "  (unable to diff)"
        fi
    fi

    if [[ -n "$PR_URL" && -n "$PR_NUMBER" ]]; then
        echo ""
        label "PR #${PR_NUMBER}:"
        echo "  URL: ${PR_URL}"
        if command -v gh &>/dev/null; then
            cd "$REPO_PATH" 2>/dev/null
            local pr_json
            pr_json=$(gh pr view "$PR_NUMBER" --json state,reviewDecision,reviews,comments 2>/dev/null || echo "{}")
            local pr_state review_decision comment_count
            pr_state=$(echo "$pr_json" | jq -r '.state // "unknown"')
            review_decision=$(echo "$pr_json" | jq -r '.reviewDecision // "none"')
            comment_count=$(echo "$pr_json" | jq '.comments | length // 0')
            echo "  State: ${pr_state}"
            echo "  Review: ${review_decision}"
            echo "  Comments: ${comment_count}"
        fi
    fi

    echo ""
    echo "AGENT_ACTION: show_jira_status ${JIRA_KEY}"
}

cmd_plan() {
    local jira_key
    jira_key=$(resolve_jira_key "${2:-}")

    local sf
    sf=$(state_file_for "$jira_key")
    read_state "$sf"
    validate_allowed_states "plan" "$STATE" "started" "created"

    echo "JIRA_KEY=${JIRA_KEY}"
    echo "REPO_PATH=${REPO_PATH}"
    echo "AGENT_TAKEOVER: plan"
}

cmd_monitor() {
    local jira_key
    jira_key=$(resolve_jira_key "${2:-}")

    local sf
    sf=$(state_file_for "$jira_key")
    read_state "$sf"
    validate_allowed_states "monitor" "$STATE" "pr-created" "in-review"

    echo "JIRA_KEY=${JIRA_KEY}"
    echo "PR_NUMBER=${PR_NUMBER}"
    echo "PR_URL=${PR_URL}"
    echo "REPO_PATH=${REPO_PATH}"
    echo "AGENT_TAKEOVER: monitor"
}

# --- No-args: suggest next step ---

cmd_next() {
    local active_files=("${STATE_DIR}"/*.state)
    if [[ ! -e "${active_files[0]}" ]]; then
        echo "AGENT_TAKEOVER: suggest_next"
        return
    fi

    label "Active tickets:"
    for f in "${active_files[@]}"; do
        read_state "$f"
        local next_hint=""
        case "$STATE" in
            created)  next_hint="→ /dev-flow start ${JIRA_KEY}" ;;
            started)  next_hint="→ /dev-flow plan or /dev-flow pr" ;;
            pr-created|in-review) next_hint="→ /dev-flow monitor ${JIRA_KEY}" ;;
            merged)   next_hint="(complete)" ;;
        esac
        echo "  ${JIRA_KEY}  [${STATE}]  ${next_hint}"
    done
}

# --- Main dispatcher ---

case "$SUBCOMMAND" in
    start)   shift; cmd_start "$@" ;;
    pr)      cmd_pr "$@" ;;
    status)  cmd_status "$@" ;;
    create)  cmd_create ;;
    plan)    cmd_plan "$@" ;;
    monitor) cmd_monitor "$@" ;;
    "")      cmd_next ;;
    *)
        echo "Usage: /dev-flow <command> [JIRAKEY]"
        echo ""
        echo "Commands:"
        echo "  create                        Create a new Jira ticket"
        echo "  start JIRAKEY [description]   Start work (sync, branch, Jira → In Progress)"
        echo "  plan   [JIRAKEY]              Scope the work from Jira details"
        echo "  pr     [JIRAKEY]              Push and create PR (auto-links Jira)"
        echo "  monitor [JIRAKEY]             Check PR review feedback"
        echo "  status  [JIRAKEY]             Show current state"
        echo ""
        echo "JIRAKEY is optional for most commands — inferred from current branch."
        echo "Run with no args to see all active tickets and next steps."
        exit 1
        ;;
esac
