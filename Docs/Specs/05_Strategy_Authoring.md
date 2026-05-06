# 05 — Strategy Authoring (Rules + Lua)

How users describe a trading strategy and how the backend turns that description into **buy / sell / hold** actions per bar.

We support **two authoring surfaces**:

1. **Rule mode** — a JSON-backed declarative language editable from the Qt form. Covers ~80% of common strategies (crossovers, threshold, breakouts, % stops).
2. **Lua mode** — a sandboxed Lua 5.4 script for everything else. Same `Context` API as rules, plus arbitrary control flow.

Both compile down to the same `IStrategy` C++ interface that the engine consumes (`07`).

---

## 1. The `IStrategy` interface

```cpp
namespace bte::strategy {

struct Context {
    core::Timestamp now;
    int barIndex;
    const core::Bar& bar;                            // the bar that just closed
    const Indicators& indicators;                    // see 06
    const PortfolioView& portfolio;                  // read-only view
    OrderBuilder& orders;                            // submit orders here
    spdlog::logger& log;
    StrategyConfig config;                           // user params
};

class IStrategy {
public:
    virtual ~IStrategy() = default;

    virtual core::Result<void> onInit(InitContext& ctx) = 0;
    virtual core::Result<void> onBar(Context& ctx) = 0;
    virtual core::Result<void> onFill(const core::Fill& fill, Context& ctx) {
        return {};   // default no-op
    }
    virtual core::Result<void> onShutdown() { return {}; }

    virtual std::string id() const = 0;
    virtual std::string version() const = 0;
};

}  // namespace bte::strategy
```

`InitContext` is similar to `Context` but called once before any bar arrives. It's where the strategy declares which indicators it needs (so the engine can pre-warm them):

```cpp
struct InitContext {
    IndicatorRegistry& registry;     // call registry.require("sma", {20})
    StrategyConfig& config;
    const core::DateRange& range;
    spdlog::logger& log;
};
```

---

## 2. `OrderBuilder`

The strategy never constructs `core::Order` directly. It speaks intent:

```cpp
class OrderBuilder {
public:
    void buy(double qty);                              // market buy
    void sell(double qty);                             // market sell

    void buyAtLimit(double qty, double limitPrice);
    void sellAtLimit(double qty, double limitPrice);

    void buyAtStop(double qty, double stopPrice);
    void sellAtStop(double qty, double stopPrice);

    void closeAll();                                   // flatten current symbol
    void cancelAll();                                  // cancel resting orders

    // sizing helpers
    void buyPctEquity(double pct);                     // buy N shares ≈ pct * equity / price
    void sellPctEquity(double pct);
    void buyShares(int shares);                        // explicit integer shares
};
```

The engine collects builds and produces `core::Order` instances with `createdAt = ctx.now`.

`OrderBuilder` is **per-bar**: cleared at the end of `onBar`. Strategies don't carry rolling order objects.

---

## 3. Rule mode

### 3.1 Schema (`*.rule.json`)

```json
{
  "id": "sma-cross-aapl",
  "name": "SMA 20/50 cross",
  "version": "1.0.0",
  "universe": { "symbols": ["AAPL"], "schemaName": "ohlcv-1h" },
  "params": {
    "fast": 20,
    "slow": 50,
    "positionSizePctEquity": 0.10,
    "stopLossPct": 0.03
  },
  "indicators": [
    { "id": "fastSma", "kind": "sma", "args": { "period": "@fast" } },
    { "id": "slowSma", "kind": "sma", "args": { "period": "@slow" } },
    { "id": "rsi14",   "kind": "rsi", "args": { "period": 14 } }
  ],
  "rules": [
    {
      "name": "long entry",
      "when": [
        { "crosses": { "above": "fastSma", "below_now": "slowSma" } },
        { "rsi14": { "lt": 70 } },
        { "portfolio": { "noPositionIn": "AAPL" } }
      ],
      "do": [
        { "buyPctEquity": "@positionSizePctEquity" }
      ]
    },
    {
      "name": "long exit on cross-down",
      "when": [
        { "crosses": { "below": "fastSma", "above_now": "slowSma" } },
        { "portfolio": { "longIn": "AAPL" } }
      ],
      "do": [{ "closeAll": {} }]
    },
    {
      "name": "stop loss",
      "when": [
        { "portfolio": { "longIn": "AAPL" } },
        { "drawdownPctSinceEntry": { "gte": "@stopLossPct" } }
      ],
      "do": [{ "closeAll": {} }]
    }
  ]
}
```

### 3.2 Operators

| Operator | Args | Meaning |
|---|---|---|
| `crosses.above` | `{ above: <indicator|number>, below_now: <...> }` | true the bar `above` first exceeds `below_now` |
| `crosses.below` | mirror | dual |
| `gt`, `gte`, `lt`, `lte`, `eq` | number / indicator | scalar comparison on indicator value at current bar |
| `between` | `[lo, hi]` | inclusive |
| `slope` | `{ over: N, gt|lt: x }` | change in indicator over N bars |
| `portfolio.longIn` / `shortIn` / `noPositionIn` | symbol | portfolio query |
| `drawdownPctSinceEntry` | `gte: x` | open-position drawdown gate |
| `bar.close.gt` etc. | number / indicator | direct bar-field compares |

### 3.3 Actions

| Action | Args |
|---|---|
| `buy` | `{ qty: N }` |
| `sell` | `{ qty: N }` |
| `buyPctEquity` | number |
| `sellPctEquity` | number |
| `closeAll` | `{}` |
| `cancelAll` | `{}` |
| `log` | `{ level, message }` (templated, useful for debugging) |

### 3.4 Compilation

`bte::strategy::compileRule(json) -> Result<std::unique_ptr<IStrategy>>` walks the JSON, validates every reference (`fastSma`, `@fast`), pre-binds indicators against `InitContext`, and produces a `RuleStrategy` that evaluates each rule per bar using a small AST interpreter — fast enough that the per-bar overhead is < 1 µs.

The Qt rule-mode form generates and consumes this exact JSON; what you see is what's saved to disk.

---

## 4. Lua mode

### 4.1 Engine

We embed **Lua 5.4** (vendored, MIT) and use **sol2** (header-only, MIT) for binding.

Reasoning:
- Lua is small (~250 KB), embedding is one source dir, no build-system pain on any of the three OSes.
- sol2 gives us idiomatic C++ binding without the boilerplate of raw Lua C API.
- Lua 5.4 has `goto`, integer math, and bit ops — enough power without LuaJIT's complications.

LuaJIT is rejected: not available on Apple Silicon without workarounds, and we don't need its raw speed for per-bar decisions.

### 4.2 Sandbox

The Lua state is started with **only safe libs**: `string`, `table`, `math`, `bit32`. Removed: `os`, `io`, `package`, `debug.getregistry`, `loadfile`, `dofile`, `require`. Strategies cannot read or write the filesystem, can't open network sockets, can't `os.execute`.

A debug hook fires every 50,000 instructions and checks `std::stop_token` so cancelling a runaway script is instant.

### 4.3 The Lua API surface

```lua
-- declared globals available to every strategy script:

-- ctx.bar       table  { ts, open, high, low, close, volume }
-- ctx.barIndex  int
-- ctx.now       int    (unix millis, UTC)
-- ctx.portfolio table  read-only view
-- ctx.config    table  user params
-- bte           table  the API surface

local sma   = bte.indicator("sma",  { period = 20 })  -- in onInit
local slow  = bte.indicator("sma",  { period = 50 })

function onInit(ctx)
    ctx.config.fast = ctx.config.fast or 20
end

function onBar(ctx)
    local f = sma:value()
    local s = slow:value()
    if not f or not s then return end       -- still warming up

    if bte.crossesAbove(sma, slow) and ctx.portfolio:positionIn("AAPL") == 0 then
        bte.orders.buyPctEquity(ctx.config.positionSizePctEquity or 0.10)
    elseif bte.crossesBelow(sma, slow) and ctx.portfolio:positionIn("AAPL") > 0 then
        bte.orders.closeAll()
    end
end

function onFill(fill, ctx)
    bte.log.info(("filled %s %.2f x %d at %.2f"):format(
        fill.side, fill.qty, fill.orderId, fill.price))
end
```

### 4.4 Bound C++ surface (sol2)

```cpp
sol::table bte = lua["bte"].get_or_create<sol::table>();

bte["indicator"] = [&](std::string kind, sol::table args) {
    return registry.makeHandle(kind, args);
};
bte["crossesAbove"] = [&](IndicatorHandle a, IndicatorHandle b) {
    return engine.crossesAbove(a, b);
};
bte["orders"] = sol::table{};
bte["orders"]["buy"] = [&](double qty) { ctx.orders.buy(qty); };
// ...
bte["log"]["info"]  = [&](std::string m) { ctx.log.info(m); };

bte["apiVersion"] = std::string("1");   // major version of the Lua API
```

### 4.5 Compilation

```cpp
core::Result<std::unique_ptr<IStrategy>> compileLua(std::string_view source,
                                                    StrategyConfig defaults);
```

Errors during `lua_load` → `ErrorCode::strategyCompileFailed` with the Lua line/message. Runtime errors during `onBar` → `ErrorCode::strategyRuntimeError`; the engine logs and either stops the run (default) or skips the bar (configurable).

---

## 5. Strategy persistence & versioning

| Field | Where stored | Notes |
|---|---|---|
| `id` | inside file | unique within `<userData>/strategies/` |
| `version` | inside file | semver; bumped manually by user |
| `bteApiVersion` | inside file | the `bte.apiVersion` it targets; rejected if app's major != file's major |
| `createdAt`, `updatedAt` | file mtime | also stored inside for portability |
| Source format | `*.rule.json` or `*.lua` + sibling `*.meta.json` | the `.meta.json` carries non-source fields for `.lua` scripts |

The Strategies tab UI lists all files, filterable by tag.

---

## 6. Live validation in the editor

While the user types:
- **Rule mode**: each form change re-renders JSON, calls `compileRule`, displays errors inline (`QLineEdit::setStyleSheet("background: #fee")`).
- **Lua mode**: 500 ms debounce → `compileLua` (only `lua_load`, doesn't run). Errors highlight the offending line via the syntax highlighter.

Both modes show **indicator preview**: pick a symbol, press "Preview", and a thumbnail chart shows the indicator overlaid on recent bars without running a full backtest. Implemented by feeding 500 historical bars through `Indicators` only.

---

## 7. Determinism

Every strategy run with the same `(strategy file, data range, params, engine config)` must produce **byte-identical** trades. Lua randomness (`math.random`) is seeded from the strategy id by default; users can override:

```lua
math.randomseed(123)   -- once in onInit
```

The engine's broker simulator is deterministic by construction (`07`).

---

## 8. Tests

- Rule compiler: every operator round-trips JSON → AST → JSON.
- Lua sandbox escape attempts (load `os`, write a file): all fail.
- A reference strategy (`sma-cross-aapl`) implemented in **both** rule and Lua produces identical trade lists on a fixed dataset — locks in semantic equivalence.
- Cancellation: an infinite-loop Lua script terminates within 50 ms of `stopSource_.request_stop()`.
