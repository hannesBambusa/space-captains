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
| Rival corporation | [`rival-corporation.md`](rival-corporation.md) | Ready for review, needs your play test; data sim committed (c4c3778); research stall fix, milestones, escort queue fix uncommitted | — |
| Planet outposts | [`planet-outposts.md`](planet-outposts.md) | Built, raider range fix uncommitted, needs play test | main |
| Shield generator redesign | [`shield-generator-redesign.md`](shield-generator-redesign.md) | Done | main |
| Merc outpost redesign | [`merc-outpost-redesign.md`](merc-outpost-redesign.md) | Done, committed (c4c3778); doc can be deleted | main |
| Tutorial academy and SOLA voice | [`tutorial-academy.md`](tutorial-academy.md) | Built and committed; needs your listen and play test | main |
