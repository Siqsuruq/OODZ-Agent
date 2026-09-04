# Built-in skills

This directory contains optional workflows that are useful to every OODZ Agent
installation. A skill is a directory containing a `SKILL.md` file with `name`
and `description` frontmatter followed by its instructions.

Application-, company-, or framework-specific skills should not be added here.
Keep them in a personal directory, such as `.oodz/skills`, and configure it:

```ini
[Skills]
directories = .oodz/skills
```

Only skill names and trigger descriptions are included in the normal model
context. Complete instructions are loaded on demand through `load_skill`.

## Included example

- `debug-failing-test` provides a language-independent workflow for reproducing,
  diagnosing, fixing, and verifying a failing automated test.

Its `SKILL.md` is intentionally small so it can also serve as a template for new
public skills.
