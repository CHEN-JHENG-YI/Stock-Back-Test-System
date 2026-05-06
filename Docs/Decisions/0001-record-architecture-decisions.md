# 0001 — Record architecture decisions

- **Status**: Accepted
- **Date**: 2026-05-06
- **Deciders**: founding team
- **Supersedes**: —
- **Superseded by**: —

## Context

Decisions get made in chat, on calls, in PR comments. Six months later, no one remembers why a class is shaped the way it is, and a new contributor (or AI agent) starts re-litigating settled questions.

The team is small (4–8 people, hybrid sync/async) and AI-heavy in authoring. Both characteristics make implicit knowledge expensive: humans rotate, AI agents have no memory across sessions.

## Decision

Use **Architecture Decision Records (ADRs)** for any design choice that materially shapes the code.

- Stored as numbered Markdown files in `Docs/Decisions/NNNN-short-title.md`.
- Append-only. To change a decision, write a new ADR that supersedes the old.
- One file = one decision.
- Format: Status, Date, Deciders, Context, Decision, Consequences, Alternatives.
- Linked from PRs that implement them.

The threshold for writing one is in `Docs/Decisions/README.md`. The default when in doubt is **write one** — they are cheap.

## Consequences

**Positive:**

- Future contributors can answer "why is this like this?" in one place.
- AI agents can read ADRs and respect prior decisions instead of suggesting changes that violate them.
- Disagreements get resolved on the page, not re-debated each PR.
- The set of ADRs becomes a small, navigable history of the project's reasoning.

**Negative:**

- Slight overhead per non-trivial change (writing 30–80 lines).
- Risk of ADRs going stale if statuses aren't maintained.

**Mitigations:**

- The `cpp-oop-design` skill and [`../Governance/AGENTS.md`](../Governance/AGENTS.md) reference ADRs explicitly so they're discoverable.
- A weekly retro briefly checks if any ADR needs status updates.

## Alternatives considered

1. **Wiki**. Rejected: drifts from code, not version-controlled with changes, AI agents can't read it as easily as in-repo files.
2. **Long-form design docs only**. Rejected: too heavy for small decisions, inhibits writing them down.
3. **Comments in code**. Rejected: don't survive refactors; not a good place for "why we picked X over Y".
4. **Issue tracker only**. Rejected: issues are conversations and tend to lose the "decided" thread; ADRs are a stable artifact.

## References

- Michael Nygard, "Documenting Architecture Decisions" (2011) — original ADR concept.
- This template adapted to fit the project's small-team, AI-heavy context.
