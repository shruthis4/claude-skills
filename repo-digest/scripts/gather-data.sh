#!/usr/bin/env bash
set -euo pipefail

REPO="${1:?Usage: gather-data.sh OWNER/REPO [SINCE_DATE]}"
SINCE_DATE="${2:-$(date -d '1 month ago' +%Y-%m-%dT00:00:00Z)}"
OUTPUT_DIR="tmp/repo-digest/raw"

if ! gh api "repos/$REPO" --jq '.full_name' >/dev/null 2>&1; then
    echo "ERROR: Repository '$REPO' not found or not accessible." >&2
    echo "Ensure the repo is public and the name is correct (e.g., facebook/react)." >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

gather_commits() {
    local repo="$1" since="$2" outdir="$3"
    local tmpfile
    tmpfile=$(mktemp)
    trap "rm -f '$tmpfile'" RETURN

    for page in 1 2 3 4 5; do
        local page_data
        page_data=$(gh api "repos/$repo/commits?since=$since&per_page=100&page=$page" 2>/dev/null) || break

        local count
        count=$(echo "$page_data" | jq 'length')
        [ "$count" = "0" ] && break

        echo "$page_data" | jq '[.[] | {
            sha: .sha[0:7],
            message: (.commit.message | split("\n")[0]),
            author: .commit.author.name,
            date: .commit.author.date
        }]' >> "$tmpfile"

        [ "$count" -lt 100 ] && break
    done

    if [ ! -s "$tmpfile" ]; then
        echo '[]' > "$tmpfile"
    fi

    jq -s --arg repo "$repo" --arg since "$since" '
        add |
        def category:
            .message | ascii_downcase |
            if test("^docs?[/:(]") then "Documentation"
            elif test("^fix[:(]|^bugfix") then "Bug Fixes"
            elif test("^feat[:(]") then "Features"
            elif test("^refactor[:(]") then "Refactoring"
            elif test("^tests?[/:(]") then "Testing"
            elif test("^ci[:(]|\\.github/") then "CI/CD"
            elif test("^deps[:(]|^chore\\(deps\\)|dependabot") then "Dependencies"
            else "Other"
            end;
        {
            repo: $repo,
            since: $since,
            total_count: length,
            by_area: (reduce .[] as $c ({};
                ($c | category) as $cat |
                .[$cat] = (.[$cat] // []) + [$c]
            )),
            top_contributors: (
                if length == 0 then []
                else group_by(.author) | map({name: .[0].author, count: length}) | sort_by(-.count)
                end
            )
        }
    ' "$tmpfile" > "$outdir/commits.json"

    local total
    total=$(jq '.total_count' "$outdir/commits.json")
    echo "Commits: $total found"
}

gather_prs() {
    local repo="$1" since="$2" outdir="$3"
    local tmpfile
    tmpfile=$(mktemp)
    trap "rm -f '$tmpfile'" RETURN

    for page in 1 2 3 4 5; do
        local page_data
        page_data=$(gh api "repos/$repo/pulls?state=closed&sort=updated&direction=desc&per_page=100&page=$page" 2>/dev/null) || break

        local count
        count=$(echo "$page_data" | jq 'length')
        [ "$count" = "0" ] && break

        echo "$page_data" | jq --arg since "$since" '[.[] |
            select(.merged_at != null and .merged_at >= $since) |
            {
                number,
                title,
                body: ((.body // "")[0:300]),
                labels: [.labels[].name],
                author: .user.login,
                merged_at: .merged_at
            }
        ]' >> "$tmpfile"

        [ "$count" -lt 100 ] && break
    done

    if [ ! -s "$tmpfile" ]; then
        echo '[]' > "$tmpfile"
    fi

    jq -s --arg repo "$repo" --arg since "$since" '
        add |
        def pr_category:
            (.labels | map(ascii_downcase)) as $ll |
            if ($ll | any(. == "bug" or . == "fix" or . == "bugfix")) then "Bug Fixes"
            elif ($ll | any(. == "feature" or . == "enhancement")) then "Features"
            elif ($ll | any(. == "breaking" or . == "breaking-change")) then "Breaking Changes"
            elif ($ll | any(. == "documentation" or . == "docs")) then "Documentation"
            elif ($ll | any(. == "dependencies" or . == "deps")) or (.author == "dependabot[bot]") then "Dependencies"
            elif ($ll | any(. == "performance" or . == "perf")) then "Performance"
            else
                (.title | ascii_downcase) as $tl |
                if ($tl | test("^(\\[.*\\] )?fix[:(]|^bugfix")) then "Bug Fixes"
                elif ($tl | test("^(\\[.*\\] )?feat[:(]")) then "Features"
                elif ($tl | test("^docs?[:(]")) then "Documentation"
                elif ($tl | test("^chore\\(deps\\)|^deps[:(]")) then "Dependencies"
                elif ($tl | test("^perf[:(]")) then "Performance"
                elif ($tl | test("^break")) then "Breaking Changes"
                elif ($tl | test("^tests?[:(]")) then "Testing"
                else "Other"
                end
            end;
        def notable_reason:
            (.labels | map(ascii_downcase)) as $ll |
            if ($ll | any(. == "breaking" or . == "breaking-change")) then "breaking change"
            elif ($ll | any(test("^size/(xxl|xl)$"))) then
                "large PR (" + ($ll | map(select(test("^size/(xxl|xl)$"))) | .[0]) + ")"
            elif (.title | test("^(\\[.*\\] )?feat[:(]"; "i")) then "new feature"
            else null
            end;
        {
            repo: $repo,
            since: $since,
            total_merged: length,
            by_category: (reduce .[] as $pr ({};
                ($pr | pr_category) as $cat |
                .[$cat] = (.[$cat] // []) + [$pr | {number, title, author, labels, merged_at}]
            )),
            notable: [.[] | notable_reason as $r | select($r != null) | {number, title, reason: $r}]
        }
    ' "$tmpfile" > "$outdir/prs.json"

    local total
    total=$(jq '.total_merged' "$outdir/prs.json")
    echo "PRs: $total merged"
}

gather_releases() {
    local repo="$1" since="$2" outdir="$3"

    local release_data
    release_data=$(gh api "repos/$repo/releases?per_page=30" --jq \
        --arg since "$since" \
        '[.[] | select(.published_at >= $since) | {
            tag: .tag_name,
            name: .name,
            date: .published_at,
            prerelease: .prerelease,
            body: ((.body // "")[0:500])
        }]' 2>/dev/null) || release_data="[]"

    local release_count
    release_count=$(echo "$release_data" | jq 'length')

    if [ "$release_count" -gt 0 ]; then
        echo "$release_data" | jq --arg repo "$repo" --arg since "$since" '{
            repo: $repo,
            since: $since,
            releases: [.[] | {
                tag,
                name,
                date,
                prerelease,
                highlights: (
                    (.body // "") | split("\n") |
                    map(select(length > 0) | select(test("feat|feature|add|new|support"; "i"))) |
                    map(gsub("^[\\s*#-]+"; "")) | .[0:5]
                ),
                breaking_changes: (
                    (.body // "") | split("\n") |
                    map(select(length > 0) | select(test("break"; "i"))) |
                    map(gsub("^[\\s*#-]+"; "")) | .[0:5]
                ),
                deprecations: (
                    (.body // "") | split("\n") |
                    map(select(length > 0) | select(test("deprecat"; "i"))) |
                    map(gsub("^[\\s*#-]+"; "")) | .[0:5]
                )
            }],
            has_releases: true
        }' > "$outdir/releases.json"
    else
        local tag_data
        tag_data=$(gh api "repos/$repo/tags?per_page=20" --jq \
            '[.[] | {tag: .name, sha: .commit.sha[0:7]}]' 2>/dev/null) || tag_data="[]"

        local note=""
        local tag_count
        tag_count=$(echo "$tag_data" | jq 'length')
        if [ "$tag_count" -gt 0 ]; then
            local latest_tag
            latest_tag=$(echo "$tag_data" | jq -r '.[0].tag')
            note="No releases in window. Latest tag: $latest_tag"
        else
            note="No releases or tags found."
        fi

        jq -n --arg repo "$repo" --arg since "$since" --arg note "$note" '{
            repo: $repo,
            since: $since,
            releases: [],
            has_releases: false,
            note: $note
        }' > "$outdir/releases.json"
    fi

    echo "Releases: $release_count found"
}

echo "Gathering data for $REPO (since $SINCE_DATE)..."

gather_commits "$REPO" "$SINCE_DATE" "$OUTPUT_DIR" &
PID_COMMITS=$!

gather_prs "$REPO" "$SINCE_DATE" "$OUTPUT_DIR" &
PID_PRS=$!

gather_releases "$REPO" "$SINCE_DATE" "$OUTPUT_DIR" &
PID_RELEASES=$!

ERRORS=0
wait "$PID_COMMITS"  || { echo "WARNING: commit gathering failed" >&2; ERRORS=$((ERRORS+1)); }
wait "$PID_PRS"       || { echo "WARNING: PR gathering failed" >&2; ERRORS=$((ERRORS+1)); }
wait "$PID_RELEASES"  || { echo "WARNING: release gathering failed" >&2; ERRORS=$((ERRORS+1)); }

if [ "$ERRORS" -eq 3 ]; then
    echo "ERROR: All data gathering failed." >&2
    exit 1
fi

echo "Done. Output in $OUTPUT_DIR/"
