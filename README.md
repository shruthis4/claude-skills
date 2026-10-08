# Claude Code Skills

Personal collection of Claude Code skills for development workflows.

## Skills

### upstream-sync
Sync upstream repo into midstream with config-driven conflict resolution and LLM-assisted reconciliation of risky files.

**Usage:** `/upstream-sync [run|dry-run|reconcile|status]`

**Location:** `upstream-sync/`

### dev-flow
Full development lifecycle workflow - create ticket, branch, PR, monitor reviews. Orchestrates git ops and Jira ops.

**Usage:** `/dev-flow`

**Location:** `dev-flow/`

### repo-digest
Generate audience-tailored monthly digests of a public GitHub repo's changes using bash data gathering, LLM digest writing, and verdict-based quality checks.

**Usage:** `/repo-digest`

**Location:** `repo-digest/`

### fix-by-example
Learn from a reference PR/commit and apply the pattern to fix a new error.

**Usage:** `/fix-by-example`

**Location:** `fix-by-example.md`

## Installation

```bash
# Clone this repo
git clone https://github.com/shruthis4/claude-skills.git ~/claude-skills

# Symlink individual skills to Claude's skills directory
ln -s ~/claude-skills/upstream-sync ~/.claude/skills/
ln -s ~/claude-skills/dev-flow ~/.claude/skills/
ln -s ~/claude-skills/repo-digest ~/.claude/skills/
ln -s ~/claude-skills/fix-by-example.md ~/.claude/skills/
```

## Adding New Skills

1. Create a new directory or `.md` file in this repo
2. For directory-based skills: create `SKILL.md` with frontmatter
3. For single-file skills: just create the `.md` file
4. Commit and push
5. Symlink to `~/.claude/skills/`

## Structure

```
claude-skills/
├── README.md
├── upstream-sync/
│   ├── SKILL.md          # Skill definition
│   └── scripts/          # Helper scripts
├── dev-flow/
│   ├── SKILL.md
│   └── scripts/
├── repo-digest/
│   ├── SKILL.md
│   ├── prompts/          # LLM prompts
│   └── scripts/          # Data gathering scripts
└── fix-by-example.md     # Single-file skill
```

## Contributing

Feel free to contribute improvements or new skills via PR!

## License

MIT
