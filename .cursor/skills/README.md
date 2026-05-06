# Project Skills

Cursor agent skills that ship with this repository. Any contributor (human or AI) opening this project gets these auto-applied based on the task.

These are **project skills**, not personal skills — they live in `.cursor/skills/` so they're versioned with the codebase and apply to anyone, anywhere, working on Stock-Back-Test-System.

## The five C++ skills

| Skill | Auto-triggers when… | Enforces |
|---|---|---|
| [`cpp-modern-style`](cpp-modern-style/SKILL.md) | editing any `.h`/`.cpp`, refactoring, naming questions | Modern C++20 idioms, identifier casing, **UpperCamelCase C++ file names**, `UnitTest_<Thing>.cpp` tests, ban on C-style `new`/`malloc`/`NULL`/C arrays/`sprintf`/output params |
| [`cpp-thread-safety`](cpp-thread-safety/SKILL.md) | code touches threads, mutexes, atomics, raw pointers, callbacks across threads, Qt cross-thread signals | RAII for every resource, immutable cross-thread snapshots, `std::jthread` + `std::stop_token`, scoped locks, no leaks under sanitizers |
| [`cpp-performance`](cpp-performance/SKILL.md) | hot-path code, benchmark regressions, indicators, engine bar loop, replay tick | Detect `O(n²)`, copies, allocations, `std::map` misuse, `std::function` in hot paths, virtual calls per tick; require `nanobench` numbers for any perf claim |
| [`cpp-oop-design`](cpp-oop-design/SKILL.md) | new module, new class/interface, refactoring duplication, design questions | SOLID, composition over inheritance, narrow public headers, named design patterns (Strategy, Factory, Observer, Adapter, Builder, Pimpl, Visitor, Chain, Command, Decorator) |
| [`cpp-static-analysis`](cpp-static-analysis/SKILL.md) | static analysis, lint, format, sanitizers, scan-build, IWYU questions | clang-format, clang-tidy (with project naming rules), cppcheck, IWYU, scan-build, ASan/UBSan/LSan/TSan; zero new warnings on touched files |

## How they layer with the spec docs

The skills are the **always-on** day-to-day rules. The detailed long-form decisions live in [`Docs/Specs/`](../../Docs/Specs/README.md). Skills reference the specs by section number when a fuller treatment is needed.

| Question | Look in |
|---|---|
| "How do I write this loop in modern C++?" | `cpp-modern-style` |
| "What does the architecture say about modules?" | `Docs/Specs/01_Architecture.md` |
| "How do I make this strategy class plug-in?" | `Docs/Specs/05_Strategy_Authoring.md` + `cpp-oop-design` |
| "What are the CI gates?" | `Docs/Specs/10_CI_Dev_Flow.md` |
| "Is this code thread-safe?" | `cpp-thread-safety` |
| "Does this allocation matter?" | `cpp-performance` |
| "What does this clang-tidy warning mean?" | `cpp-static-analysis` |

## Auto-invocation

Each `SKILL.md` here omits `disable-model-invocation`, so the agent decides automatically when to apply them based on the description in the YAML frontmatter. You don't have to invoke them explicitly — opening a `.cpp` file or asking about threads is enough.

## Maintenance

- Skills evolve with the codebase. PRs that change conventions must update the relevant skill in the same PR.
- Each skill is < 500 lines (per the create-skill guidelines) so the context cost is bounded.
- A skill that's grown too long should be split: keep the day-to-day rules in `SKILL.md`, move the long catalog into a sibling `reference.md` and link to it.

## Adding a new project skill

```bash
mkdir -p .cursor/skills/<skill-name>
edit .cursor/skills/<skill-name>/SKILL.md
```

Follow the format in [`~/.cursor/skills-cursor/create-skill/SKILL.md`](file:///Users/shaohsua/.cursor/skills-cursor/create-skill/SKILL.md). The `description` in the frontmatter is what makes the agent pick the skill — make it specific and include trigger terms a developer or AI would actually mention.
