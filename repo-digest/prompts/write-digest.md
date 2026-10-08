# Agent: Write Audience-Specific Digest

Given raw data about a repository's recent changes, write a concise digest tailored to a specific audience.

## Inputs

- **Audience**: One of `engineering`, `ux`, `business`
- **Repo**: The repository name
- **Raw data**: Contents of commits.json, prs.json, releases.json

## Audience guidelines

### engineering

Write for software engineers who work with or depend on this repo.

- Lead with breaking changes and deprecations — these block people
- Cover new APIs, configuration changes, and dependency updates
- Include commit volume and contributor stats for a sense of velocity
- Link PR numbers so engineers can dig deeper (`#1234`)
- Use technical language freely — this audience expects it
- Mention performance-relevant changes
- Call out new test coverage or CI changes

### ux

Write for designers and product managers who care about user-facing impact.

- Lead with new features and UI changes users will notice
- Translate technical changes into user impact ("faster load times" not "optimized query batching")
- Flag deprecations that affect user workflows
- Ignore internal refactors, CI changes, and dependency bumps unless they have visible impact
- Use plain language — no code snippets, no API names unless they're user-facing
- Group by user journey or feature area, not by code area

### business

Write for executives and stakeholders who need the strategic view.

- Lead with themes: "This month focused on reliability and performance" 
- Quantify where possible: N features shipped, N bugs fixed, N contributors active
- Highlight anything with adoption, competitive, or risk implications
- Flag breaking changes as migration risk, not technical detail
- Keep it to one page — bullet points over paragraphs
- No code, no PR numbers, no technical jargon

## Output format

Write a markdown document with:

1. A one-line summary (what was the theme of this month?)
2. 3-5 sections grouping the most relevant changes for this audience
3. Each section has 2-5 bullet points
4. A "Looking ahead" line if releases or PRs suggest upcoming work

Write the digest to `tmp/repo-digest/digests/{audience}.md`.

## If retry with feedback

If you receive verdict feedback from a previous attempt, address each piece of feedback explicitly. The feedback will list specific scores and issues — fix those issues while preserving what scored well.
