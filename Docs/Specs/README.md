# Specs — Stock Back-Test System (C++ Desktop App)

This folder is the design source of truth for the C++/Qt desktop backtester being built on top of the existing Python data pipeline ([`../../DataFetcher/`](../../DataFetcher/README.md), `../../StockData/`).

Read **`00_Overview.md` first**. It sets scope, draws the architecture diagram, and tells you which detailed spec covers what. Each subsequent file goes one level deeper on a single subsystem.

| File | One-line summary |
|---|---|
| [`00_Overview.md`](00_Overview.md) | Purpose, end-to-end flow, repo layout, NFRs |
| [`01_Architecture.md`](01_Architecture.md) | Module dependency graph, threading, error model, build presets |
| [`02_Frontend_Qt.md`](02_Frontend_Qt.md) | Qt UI structure, chart-library choice (with rationale), MVVM |
| [`03_Backend_Core.md`](03_Backend_Core.md) | `Bar`, `Order`, `Trade`, `Portfolio`, `Result<T,Error>`, naming |
| [`04_Data_Layer.md`](04_Data_Layer.md) | DuckDB + CSV adapters, `BarStream`, prefetch, caching |
| [`05_Strategy_Authoring.md`](05_Strategy_Authoring.md) | Rule DSL (JSON) + Lua sandbox, both compile to `IStrategy` |
| [`06_Indicators.md`](06_Indicators.md) | Streaming TA library, full Phase-1 catalog |
| [`07_Engine_Replay_PnL.md`](07_Engine_Replay_PnL.md) | Backtest loop, broker simulator, replay clock, metrics |
| [`08_Plugin_System.md`](08_Plugin_System.md) | Native C++ plugin ABI + Lua, SDK packaging, trust model |
| [`09_Build_Distribution_Launcher.md`](09_Build_Distribution_Launcher.md) | CMake, vcpkg, CI matrix, per-OS packaging, **Launcher** |
| [`10_CI_Dev_Flow.md`](10_CI_Dev_Flow.md) | PR gates, mandatory tests for every symbol, **anti-cheat audit**, mutation testing |

## Decisions baked in

These were chosen up-front to keep the rest of the design simple:

- **Qt 6 LTS, Widgets + Qt Charts** for the UI (`02` explains why over QCustomPlot or custom QPainter).
- **Hybrid strategy authoring**: rule-based JSON for the form-driven editor, Lua 5.4 (sandboxed, via sol2) for advanced scripts. Both compile to one `IStrategy` interface (`05`).
- **DuckDB read-only** from C++; the existing Python pipeline keeps owning writes (`04`).
- **Launcher app** for version management — users install once, then any number of app versions live side-by-side under `<userData>/versions/`. `active.json` selects the current one (`09`).
- **Determinism is mandatory** for engine output across OSes and runs (`07`).
- **Native plugins** are full-trust, but each load is hash-confirmed by the user (`08`).
- **Naming**: `lowerCamelCase` for variables/methods, `UpperCamelCase` for types, per the user's project rule.
- **CI is the merge gate, not the reviewer** — every public symbol must have a test, every test is checked against a defined "no-cheating" rulebook, and mutation testing forces tests to actually catch bugs (`10`).

## What's intentionally not in here yet

- The **full** CMake/vcpkg/Qt tree from [`09`](09_Build_Distribution_Launcher.md). A minimal bootstrap (Core + tests) lives at repo root; see [`../BUILD.md`](../BUILD.md).
- Full database migration story for breaking schema changes — Python pipeline owns that, and current schema is stable.
- Live trading. The whole system is designed assuming historical bars only. Live feeds would extend the `BarStream` interface but are out of scope until backtest + replay land.
- Cloud sync. Strategies and settings are local-only by design.

## How to evolve these specs

- One PR = one spec change. Comment trail lives on the PR.
- Update `00_Overview.md` if scope or flow changes; update the relevant detail spec for everything else.
- Numbers (perf targets, defaults) are non-binding suggestions — adjust as we measure.
- Anything in **`07`** that changes engine semantics needs a determinism-fixture refresh in CI.
