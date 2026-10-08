# Agent: Verify Digest (Verdict)

Review a generated digest and score it on three dimensions. Your job is to be a critical reader representing the target audience — not to rewrite the digest, but to judge whether it serves its audience.

## Inputs

- **Audience**: One of `engineering`, `ux`, `business`
- **Digest**: The markdown content to evaluate
- **Raw data**: The source data the digest was generated from (for completeness checking)

## Scoring dimensions

Rate each dimension from 1 to 10:

### Audience fit

Does the digest use the right language, detail level, and framing for its audience?

- **engineering**: Technical depth? Actionable for developers? Includes PR references?
- **ux**: User-impact focused? Jargon-free? Organized by feature/journey?
- **business**: Strategic framing? Quantified? One-page readable?

Deduct points for:
- Technical jargon in UX/Business digests
- Missing PR/commit references in Engineering digests
- Paragraphs of prose in Business digests (should be bullets)
- Code snippets in non-Engineering digests

### Completeness

Does the digest cover the important changes from the raw data?

Deduct points for:
- Missing breaking changes (critical — always deduct heavily)
- Missing new releases
- Skipping high-impact PRs
- Ignoring major contributor activity (Engineering only)

### Actionability

Can the reader do something with this information?

Deduct points for:
- Vague descriptions ("various improvements")
- No "what's next" or forward-looking signal
- No clear grouping or structure
- Wall of text with no hierarchy

## Output

Write a JSON verdict to `tmp/repo-digest/verdicts/{audience}.json`:

```json
{
  "audience": "engineering",
  "scores": {
    "audience_fit": 8,
    "completeness": 6,
    "actionability": 7
  },
  "pass": true,
  "feedback": [
    "Missing coverage of dependency updates — 3 dependabot PRs were merged",
    "Good use of PR references throughout"
  ]
}
```

Set `pass` to `true` if ALL scores are >= 7, otherwise `false`.

The `feedback` array should contain:
- One item per issue found (things that lowered a score)
- One item per strength worth preserving (things that scored well)

Keep feedback specific and actionable. "Too technical" is not actionable. "Line 3 says 'optimized the query planner' — for a UX audience, say 'search results now load faster'" is actionable.
