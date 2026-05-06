# 00 — Overview & Flow

This document is the entry point for the C++ desktop backtester specs. It describes **what** the system is, **who** uses it, and **how** the pieces talk to each other. Detailed module specs (`01`–`10`) link off this one.

---

## 1. Purpose

A cross-platform (Windows / macOS / Linux) desktop application that lets a single local user:

1. **Author** a trading strategy (rules in the UI, or Lua script for advanced cases).
2. **Backtest** that strategy over historical OHLCV bars stored in DuckDB.
3. **Replay** the same strategy bar-by-bar against a candlestick chart, with live buy/sell markers, cash, holdings, and running P&L.
4. **Inspect** results — equity curve, trade log, summary metrics.
5. **Extend** the system through plugins (C++ shared libraries) and Lua scripts.
6. **Stay current** through a small Launcher app that downloads new releases from GitHub and lets the user switch between installed versions.

The Python pipeline already in this repo (`DataFetcher/`) is the **only** writer to the DuckDB file. The C++ app is a **read-only** consumer of `StockData/MarketData.duckdb` and the `StockData/Extracted/*.csv` snapshots.

---

## 2. High-level architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Desktop Application                         │
│                                                                     │
│  ┌──────────────────────────┐        ┌───────────────────────────┐  │
│  │     Qt Frontend (UI)     │        │      Launcher (Qt)        │  │
│  │  - Strategy editor       │        │  - List installed         │  │
│  │  - Backtest view         │        │  - Download from GitHub   │  │
│  │  - Replay view           │        │  - Switch active version  │  │
│  │  - Metrics dashboard     │        └───────────────────────────┘  │
│  └────────────┬─────────────┘                                       │
│               │  Q_OBJECT bindings  (signals/slots)                 │
│  ┌────────────▼────────────────────────────────────────────────┐    │
│  │                    Backend Core (pure C++)                  │    │
│  │                                                             │    │
│  │  data/  ──►  indicators/  ──►  strategy/  ──►  engine/      │    │
│  │   ▲              ▲                ▲              │          │    │
│  │   │              │                │              ▼          │    │
│  │   │              │                │          metrics/       │    │
│  │   │              │                │              │          │    │
│  │   │              │                │              ▼          │    │
│  │   │              │                │      ┌───────────────┐  │    │
│  │   │              │                │      │  Portfolio /  │  │    │
│  │   │              │                │      │  Broker sim   │  │    │
│  │   │              │                │      └───────────────┘  │    │
│  │   │                                                         │    │
│  │   │              plugins/   ◄── Lua / dynamic .so/.dll ──┐  │    │
│  └───┼─────────────────────────────────────────────────────┼──┘    │
│      │                                                     │       │
└──────┼─────────────────────────────────────────────────────┼───────┘
       │                                                     │
       ▼                                                     ▼
  ┌─────────────────────┐                       ┌──────────────────────┐
  │ StockData/          │                       │  ~/.stockBacktester/ │
  │  MarketData.duckdb  │  (read-only)          │   plugins/  configs/ │
  │                     │                       │   strategies/        │
  └─────────────────────┘                       └──────────────────────┘
```

The arrows in `data → indicators → strategy → engine → metrics` show the **bar-event flow**, not a build dependency. Each module exposes a stable C++ interface (header) so it can be unit-tested independently and so the Qt layer never reaches into engine internals directly.

---

## 3. End-to-end flow (typical session)

1. **Launch.** Launcher (`09`) verifies the active version, then starts `stockBacktester` from that version's folder.
2. **Load data.** UI lets the user pick a symbol or basket from DuckDB. The `data/` layer (`04`) opens `MarketData.duckdb` read-only and exposes a `BarStream` per symbol.
3. **Author strategy.** User picks rule mode or Lua mode (`05`):
   - **Rule mode** — fills a form: "buy when SMA(20) crosses above SMA(50), sell when RSI(14) > 70, position size = 10% of equity".
   - **Lua mode** — writes a script implementing `onBar(ctx, bar)` etc.
     The editor compiles/validates immediately and reports errors inline.
4. **Backtest.** User clicks **Run**. The `engine/` (`07`) iterates the `BarStream`, hands each bar to `indicators/` (`06`) and the strategy, the strategy emits orders, the broker simulator fills them on the **next bar's open** (configurable), and a `Portfolio` updates cash/holdings.
5. **Inspect.** Equity curve, drawdown, Sharpe, win-rate, trade list — all rendered in the dashboard.
6. **Replay.** User opens the **Replay view**: same engine, same strategy, but driven by a `ReplayClock` that emits bars at user-controlled speed. The chart animates candles left→right; buy/sell triangles, cash, holdings, and running P&L update with each tick. Pause / step / 1× / 5× / 10× / max.
7. **Save.** Strategies, replay sessions, and result snapshots persist to `~/.stockBacktester/` (per-user, OS-appropriate path — see `09`).

---

## 4. Key non-functional requirements

| Concern          | Target                                                                                                                                                                               |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Platforms**    | Windows 10+ (x64), macOS 12+ (arm64 + x64), Linux glibc 2.31+ (x64). Single CMake build per OS/arch.                                                                                 |
| **Languages**    | C++20 (backend, Qt UI), Lua 5.4 (strategy scripting), Python 3.11+ (data pipeline, already exists).                                                                                  |
| **UI framework** | Qt 6 LTS (Widgets + Qt Charts). Rationale in `02`.                                                                                                                                   |
| **Build**        | CMake 3.24+, vcpkg or Conan for third-party deps. One `CMakeLists.txt` tree, presets per OS.                                                                                         |
| **Naming**       | C++ identifiers: **lowerCamelCase** for variables, methods, free functions; **UpperCamelCase** for classes, structs, enums. **Files:** UpperCamelCase stems for new C++ headers/sources; unit tests `UnitTest_<Thing>.cpp`. **Dirs:** UpperCamelCase for repo roots (`Src/`, `Docs/`, `Docs/Governance/`, `Tests/`, `Output/` for CMake binaries). **`*.md`:** no prescribed naming. |
| **Testing**      | GoogleTest (C++), Qt Test (UI), pytest (Python). Every public symbol must have a test; PRs gate on diff coverage, anti-cheat audit, and mutation testing. See `10`.                  |
| **Performance**  | Backtest 10 years of `ohlcv-1h` (~25k bars × 500 symbols) in < 30 s on a modern laptop. Replay can pump 60 bars/s without UI lag.                                                    |
| **Memory**       | Streaming-first. Never load the full DuckDB into RAM; always windowed reads.                                                                                                         |
| **Threading**    | Engine/data run on a worker thread; Qt UI is the only thread allowed to touch widgets. Cross-thread comms via `QMetaObject::invokeMethod` / signals.                                 |
| **Distribution** | Self-contained release per OS, signed where possible. GitHub Releases is the source of truth. Launcher manages installs. See `09`.                                                   |
| **Errors**       | All public backend APIs return `Result<T, Error>` (no exceptions across module boundaries). Logging via `spdlog`.                                                                    |

---

## 5. Repository layout (target)

```
Stock-Back-Test-System/
├── DataFetcher/              # existing Python pipeline (unchanged)
├── StockData/                # existing DuckDB + extracted CSVs
├── Docs/                     # all human-facing docs
│   ├── Specs/                # this folder
│   ├── Decisions/            # ADRs
│   └── Governance/           # AGENTS, CONTRIBUTING, LICENSE, CHANGELOG
├── Src/                      # all C++ source
│   ├── App/                  # Qt main app entry + QML/Widgets composition
│   ├── Launcher/             # version manager / updater
│   ├── Frontend/             # Qt views, view-models, charts
│   ├── Backend/
│   │   ├── Core/             # Bar, Order, Trade, Portfolio, Time, Result
│   │   ├── Data/             # DuckDB / CSV adapters, BarStream
│   │   ├── Indicators/       # SMA, EMA, RSI, MACD, BB, ATR, ...
│   │   ├── Strategy/         # rule engine, Lua engine, plugin loader
│   │   ├── Engine/           # backtest + replay engines, broker sim
│   │   └── Metrics/          # PnL, Sharpe, drawdown, trade stats
│   └── Plugins/              # built-in plugins (sample strategies, etc.)
├── Tests/                    # gtest + qtest
├── Output/                   # CMake binary dir (gitignored); e.g. Output/dev, Output/release
├── ThirdParty/               # vendored single-header libs (or via vcpkg)
├── Resources/                # icons, QSS themes, default Lua scripts
├── Cmake/                    # toolchain files, helper modules
├── Packaging/                # NSIS, .desktop, Info.plist, AppImage recipe
└── CMakeLists.txt
```

---

## 6. How to read the rest of the specs

Read in order if you're new:

| #   | File                                | What it answers                                                |
| --- | ----------------------------------- | -------------------------------------------------------------- |
| 01  | `01_Architecture.md`                | Module boundaries, dependency graph, threading model           |
| 02  | `02_Frontend_Qt.md`                 | Qt UI structure, chart library choice, view-model pattern      |
| 03  | `03_Backend_Core.md`                | Core types (`Bar`, `Order`, `Trade`, `Portfolio`), error model |
| 04  | `04_Data_Layer.md`                  | DuckDB / CSV adapters, `BarStream`, schema discovery           |
| 05  | `05_Strategy_Authoring.md`          | Rule DSL + Lua API, validation, persistence                    |
| 06  | `06_Indicators.md`                  | Streaming indicator API, full built-in catalog                 |
| 07  | `07_Engine_Replay_PnL.md`           | Backtest loop, broker model, replay clock, metrics             |
| 08  | `08_Plugin_System.md`               | C++ shared-library plugins, Lua scripts, ABI rules             |
| 09  | `09_Build_Distribution_Launcher.md` | CMake, packaging per OS, the version-switching Launcher        |
| 10  | `10_CI_Dev_Flow.md`                 | Automated PR pipeline, mandatory tests per symbol, anti-cheat  |

When in doubt about scope, this Overview wins; deeper docs refine, they don't override.
