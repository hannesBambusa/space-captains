# Ongoing Implementations

Progress docs for features in flight — one `.md` per feature, named after its branch. Each
answers **what is built, what is left, and which files are the feature's**, so work can be
resumed, and committed, without re-reading the source or the session history.

These track work in flight, not history. **When a feature ships, delete its doc.**

## Format

Do not invent a structure. Follow the `ongoing-implementation-docs` skill: it defines the
seven sections, the path rule, the size budget, the update discipline, and how to stage a
commit from a doc. Its `TEMPLATE.md` is the copy-paste skeleton.

Update after each unit of work, the moment you hit a gotcha, when you commit, and before
ending a session. A stale doc is worse than no doc, because it is trusted.

## Current features

| Feature | Doc | Status | Branch |
|---|---|---|---|
| Rival corporation | [`rival-corporation.md`](rival-corporation.md) | Ready for review; data sim for unviewed rival worlds built 2026-11-05; growth tuning open (uncommitted) | — |
| Planet outposts | [`planet-outposts.md`](planet-outposts.md) | Built, follow-ups done (uncommitted), needs play test | main |
| Shield generator redesign | [`shield-generator-redesign.md`](shield-generator-redesign.md) | Done | main |
| Defense turret redesign | [`defense-turret-redesign.md`](defense-turret-redesign.md) | Done (uncommitted; one open question) | main |
| Merc outpost redesign | [`merc-outpost-redesign.md`](merc-outpost-redesign.md) | Done (look fixes built, viewer checked; uncommitted) | main |
| Tutorial academy and SOLA voice | [`tutorial-academy.md`](tutorial-academy.md) | Built, 37 of 37 voice lines, test passes (new lines want a listen) | main |
