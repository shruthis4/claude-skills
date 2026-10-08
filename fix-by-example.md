---
name: fix-by-example
description: Learn from a reference PR/commit and apply the fix pattern to solve a new error. Automatically creates JIRA and PR.
---

# Fix By Example

Generalized error-fixing skill that learns from a reference fix and applies the same pattern to a new problem.

## When to Use

- You have an error/test failure and found a similar fix in another PR
- You want to automate repetitive fix patterns (e.g., adding mirror images, updating versions, fixing RBAC)
- You need to create JIRA ticket + PR for the fix

## Usage

```bash
# Natural language (conversational)
/fix-by-example \
  Fix this error: Pod/spark-pi: BackOff pulling image "quay.io/..." \
  using this example: https://github.com/org/repo/pull/88

# Structured (explicit args)
/fix-by-example \
  --reference "https://github.com/red-hat-data-services/rhoai-additional-images/pull/88" \
  --error "ImagePullBackOff: quay.io/opendatahub/data-processing:Spark-v4.0.1" \
  --jira "RHOAI-1234"

# From file
/fix-by-example \
  --reference "https://github.com/org/repo/pull/123" \
  --error "$(cat error-logs.txt)"
```

## How It Works

1. **Analyze Reference**: Fetches the reference PR/commit and extracts:
   - What problem it solved
   - What changes were made
   - The semantic pattern (e.g., "add entry to list", "update version")

2. **Understand Error**: Parses your error to extract:
   - Error type and root cause
   - Affected components
   - Key facts (image names, versions, file paths)

3. **Map Pattern**: Determines if the reference fix applies to your error:
   - Matches problem types
   - Maps reference values to your values
   - Adapts file paths and operations

4. **Apply Fix**: Implements the fix:
   - Clones target repo in isolated worktree
   - Makes changes following the learned pattern
   - Creates branch and commits

5. **JIRA & PR**: 
   - Creates JIRA ticket if not provided
   - Pushes branch and creates PR
   - Links PR to JIRA

## Arguments

- `--reference`: URL to PR or commit showing example fix (required)
- `--error`: Error description, logs, or stack trace (required)
- `--jira`: Existing JIRA ticket key (optional, creates if missing)

## Examples

### Example 1: Mirror Image Fix
```bash
/fix-by-example \
  --reference "https://github.com/red-hat-data-services/rhoai-additional-images/pull/88" \
  --error "Failed to pull quay.io/opendatahub/data-processing:Spark-v4.0.1: registry blocked"
```

**What happens:**
- Learns: "Add image to additional-images.txt"
- Extracts: `quay.io/opendatahub/data-processing:Spark-v4.0.1`
- Creates PR adding that image to the mirror list

### Example 2: Version Bump
```bash
/fix-by-example \
  --reference "https://github.com/org/repo/commit/abc123" \
  --error "Build fails: kserve v0.11.0 incompatible with controller-runtime v0.16"
```

**What happens:**
- Learns: "Update dependency version in go.mod"
- Maps: kserve version → your component version
- Creates PR with version update

### Example 3: RBAC Fix
```bash
/fix-by-example \
  --reference "https://github.com/org/repo/pull/456" \
  --error "controller forbidden: cannot create resource 'routes' in API group 'route.openshift.io'"
```

**What happens:**
- Learns: "Add RBAC rule for missing resource"
- Extracts: resource=routes, apiGroup=route.openshift.io
- Creates PR with new RBAC marker

## Confidence Levels

- **High**: Reference pattern clearly matches, direct mapping
- **Medium**: Pattern applies but may need adaptation
- **Low**: Uncertain match, manual review recommended

Low confidence fixes are still applied but flagged for review.

## Limitations

- Works best for **structural fixes** (config changes, additions to lists, version updates)
- Less effective for **complex logic changes** (multi-file refactors, algorithm changes)
- Requires reference fix to be in a public GitHub repo (or accessible via your auth)

## Output

Returns:
```json
{
  "success": true,
  "jira_ticket": "RHOAI-1234",
  "pr_url": "https://github.com/org/repo/pull/999",
  "pr_number": 999,
  "branch": "fix/image-pull-sparkoperator",
  "confidence": "high",
  "fix_summary": ["Add quay.io/opendatahub/data-processing:Spark-v4.0.1 to additional-images.txt"],
  "validation_needed": ["Verify image exists in source registry", "Wait for mirror sync"]
}
```

## Tips

1. **Choose good references**: Pick PRs that are simple, well-described, and similar to your error
2. **Provide context in --error**: Include relevant logs, not just error message
3. **Review low-confidence fixes**: Check the PR diff before merging
4. **Iterate on pattern**: If first reference doesn't work, try a different one

## Integration with Other Skills

Combine with:
- `/diagnose` - Find root cause, then fix-by-example
- `/ticket` - Use ticket's error logs as input
- `/code-review` - Review the generated fix PR
