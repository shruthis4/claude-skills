# Claude Code Skills

Personal collection of Claude Code skills for various workflows.

## Skills

### upstream-sync
Sync upstream repo into midstream with config-driven conflict resolution and LLM-assisted reconciliation of risky files.

**Usage:** `/upstream-sync [run|dry-run|reconcile|status]`

### dev-flow
Full development lifecycle workflow - create ticket, branch, PR, monitor reviews.

### repo-digest
Generate audience-tailored monthly digests of a public GitHub repo's changes.

### fix-by-example
Learn from a reference PR/commit and apply the pattern to fix a new error.

## Installation

```bash
# Clone this repo
git clone https://github.com/YOUR_USERNAME/claude-skills.git

# Symlink to Claude's skills directory
ln -s $(pwd)/claude-skills/* ~/.claude/skills/
```

## Contributing

Feel free to contribute improvements or new skills via PR!
