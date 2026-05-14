# 09 — Build, Distribution, and the Launcher

How the whole thing is built once, packaged per OS, hosted on GitHub, and how a local user installs and switches between versions painlessly.

---

## 1. Build system

**CMake 3.24+** with **`CMakePresets.json`** and **vcpkg manifest mode** for third-party deps.

Why:
- CMake is the de-facto C++/Qt build system; Qt 6 ships first-class CMake support (`qt_add_executable`, `qt_add_translations`, `windeployqt`/`macdeployqt` targets).
- `CMakePresets.json` standardizes invocations across IDEs (CLion, VS, Qt Creator) and CI.
- vcpkg manifest (`vcpkg.json` checked into the repo) pins exact versions of DuckDB, spdlog, fmt, sol2, Lua, and friends — reproducible builds.

### 1.1 Toplevel `CMakeLists.txt` (sketch)

```cmake
cmake_minimum_required(VERSION 3.24)

project(stockBacktester
        VERSION 0.1.0
        LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set_property(GLOBAL PROPERTY USE_FOLDERS ON)

include(Cmake/CompilerWarnings.cmake)
include(Cmake/Sanitizers.cmake)
include(Cmake/Versioning.cmake)        # writes Src/App/version.h

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Widgets Charts Test LinguistTools)
find_package(spdlog CONFIG REQUIRED)
find_package(fmt    CONFIG REQUIRED)
find_package(duckdb CONFIG REQUIRED)
find_package(Lua    CONFIG REQUIRED)
# sol2 is header-only; vcpkg port available

qt_standard_project_setup()

add_subdirectory(Src/Backend/Core)
add_subdirectory(Src/Backend/Data)
add_subdirectory(Src/Backend/Indicators)
add_subdirectory(Src/Backend/Strategy)
add_subdirectory(Src/Backend/Engine)
add_subdirectory(Src/Backend/Metrics)
add_subdirectory(Src/Backend/Bindings)
add_subdirectory(Src/Frontend)
add_subdirectory(Src/App)
add_subdirectory(Src/Launcher)
add_subdirectory(Src/Plugins)

if (BTE_BUILD_TESTS)
    enable_testing()
    add_subdirectory(Tests)
endif()

include(Cmake/Packaging.cmake)         # CPack config per OS
```

### 1.2 `CMakePresets.json` highlights

```json
{
  "version": 6,
  "configurePresets": [
    {
      "name": "windows-msvc-x64",
      "generator": "Visual Studio 17 2022",
      "architecture": "x64",
      "toolchainFile": "$env{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake",
      "cacheVariables": { "VCPKG_TARGET_TRIPLET": "x64-windows-static-md" }
    },
    { "name": "macos-arm64", "generator": "Xcode",
      "cacheVariables": { "CMAKE_OSX_ARCHITECTURES": "arm64",
                          "CMAKE_OSX_DEPLOYMENT_TARGET": "12.0" } },
    { "name": "macos-x64", "generator": "Xcode",
      "cacheVariables": { "CMAKE_OSX_ARCHITECTURES": "x86_64",
                          "CMAKE_OSX_DEPLOYMENT_TARGET": "12.0" } },
    { "name": "linux-clang-x64", "generator": "Ninja",
      "cacheVariables": { "CMAKE_C_COMPILER": "clang",
                          "CMAKE_CXX_COMPILER": "clang++" } },
    { "name": "dev", "inherits": "linux-clang-x64",
      "cacheVariables": { "BTE_SANITIZERS": "address,undefined",
                          "BTE_BUILD_TESTS": "ON" } }
  ]
}
```

### 1.3 vcpkg manifest (`vcpkg.json`)

```json
{
  "name": "stock-backtester",
  "version": "0.1.0",
  "dependencies": [
    { "name": "qt6-base",     "features": ["widgets", "concurrent"] },
    { "name": "qt6-charts" },
    { "name": "qt6-tools" },
    "duckdb",
    "spdlog",
    "fmt",
    "lua",
    "sol2",
    "nlohmann-json"
  ]
}
```

CI overrides `VCPKG_ROOT` per runner. Local devs run `git submodule update --init` to fetch vcpkg pinned to a known commit.

---

## 2. CI pipeline (GitHub Actions)

`.github/workflows/build.yml` runs three matrix jobs on every PR:

| Job | Runner | Steps |
|---|---|---|
| Windows | `windows-2022` | configure → build → ctest → `windeployqt` → upload artifact |
| macOS arm64 | `macos-14` | configure → build → ctest → `macdeployqt` → codesign → upload |
| macOS x64 | `macos-13` | same |
| Linux x64 | `ubuntu-22.04` | configure → build → ctest → AppImage → upload |

Each job uploads the built artifact and the SDK zip. A separate **release** workflow (`release.yml`) triggers on a `v*.*.*` git tag:

1. Re-runs all matrix jobs.
2. Generates checksums (`sha256sum`).
3. Codesigns macOS bundle with `codesign --options runtime --timestamp` then `xcrun notarytool submit`.
4. Codesigns Windows EXE with `signtool` (SignPath / certificate from secrets).
5. Creates GitHub Release with body from `Docs/Governance/CHANGELOG.md`.
6. Uploads:
   - `stockBacktester-<ver>-windows-x64.zip` and `.msi`
   - `stockBacktester-<ver>-macos-arm64.dmg` and `.tgz`
   - `stockBacktester-<ver>-macos-x64.dmg` and `.tgz`
   - `stockBacktester-<ver>-linux-x64.AppImage` and `.tar.gz`
   - `bte-plugin-sdk-<ver>-<os>-<arch>.zip` (for each OS/arch)
   - `release-manifest.json` (machine-readable index — see §4)

---

## 3. Per-OS packaging

We ship **portable archives** + **native installers**, side by side. The Launcher prefers the portable forms (zip / tarball / .app) so it can manage many versions in one folder.

### 3.1 Windows

- **MSI installer** built with [WiX 4](https://wixtoolset.org/) for first-time users. Installs to `%LOCALAPPDATA%\stockBacktester\`. Does **not** require admin.
- **Portable zip** with the result of `windeployqt`: `stockBacktester.exe`, all Qt DLLs, plugins folder, `qt.conf`. Unzip-and-run.
- All binaries codesigned.

### 3.2 macOS

- **`.app` bundle** produced by `macdeployqt`, signed and notarized.
- **`.dmg`** installer drag-to-Applications.
- **Portable `.tgz`** of the `.app` bundle for the Launcher.
- Hardened runtime; entitlements file allows JIT (Lua doesn't need it but future plugins might).

### 3.3 Linux

- **AppImage** (`linuxdeploy --plugin qt`). Single executable file; users `chmod +x` and run. Works on most distros with glibc 2.31+.
- **`.tar.gz`** of the same payload (Launcher uses this).
- We don't ship `.deb`/`.rpm` until there's demand — AppImage covers the "works everywhere" promise.

### 3.4 Plugin SDK (cross-cutting)

For each OS/arch we also build the SDK zip described in `08`. Same release, separate asset.

---

## 4. Release manifest

To make the Launcher's job trivial, every Release uploads a **`release-manifest.json`** alongside the binaries:

```json
{
  "version": "0.3.0",
  "released": "2026-08-01T12:00:00Z",
  "channel": "stable",
  "minLauncherVersion": "0.1.0",
  "abi": { "plugin": 1, "luaApi": 1 },
  "assets": [
    {
      "platform": "windows",
      "arch": "x64",
      "kind": "portable",
      "url": "https://github.com/<owner>/<repo>/releases/download/v0.3.0/stockBacktester-0.3.0-windows-x64.zip",
      "size": 84211324,
      "sha256": "abcd..."
    },
    {
      "platform": "macos",
      "arch": "arm64",
      "kind": "portable",
      "url": ".../stockBacktester-0.3.0-macos-arm64.tgz",
      "size": 78901234,
      "sha256": "..."
    },
    {
      "platform": "linux",
      "arch": "x64",
      "kind": "appimage",
      "url": ".../stockBacktester-0.3.0-linux-x64.AppImage",
      "size": 92314444,
      "sha256": "..."
    }
  ],
  "changelog": "https://github.com/<owner>/<repo>/releases/tag/v0.3.0"
}
```

The Launcher fetches `https://api.github.com/repos/<owner>/<repo>/releases` (no auth — we only need public data) and reads the manifest for each release.

---

## 5. The Launcher (`stockBacktesterLauncher`)

A small Qt app that is the user's **single install point**. Downloaded once via the OS installer; manages all versions thereafter.

### 5.1 What it does

1. **Lists installed versions** (each is a folder under the version root — see §5.3).
2. **Lists available versions** from GitHub Releases (cached for 10 min).
3. **Installs** a version by downloading its archive, verifying SHA-256, and extracting to `<versionRoot>/<ver>/`.
4. **Switches** the active version by updating `<versionRoot>/active` (a config file or symlink — see §5.4).
5. **Launches** the active version (or any version on demand).
6. **Removes** old versions (with a confirm).
7. **Shows** changelog and ABI info per release so users see what changed.

### 5.2 UI

A single window, list-on-left + detail-on-right:

```
┌─ Stock Backtester Launcher ─────────────────────────────────────┐
│ Installed                          │  v0.3.0 (active)            │
│  ● v0.3.0    [active]              │  Released: 2026-08-01       │
│    v0.2.4                          │  Plugin ABI: 1              │
│    v0.2.0                          │                             │
│ ─────────────────                  │  Changelog:                 │
│ Available                          │  - replay scrubbing fast    │
│    v0.3.1   (new)   [Install]      │  - new ATR indicator        │
│    v0.4.0-beta      [Install]      │                             │
│                                    │  [ Launch ]  [ Set Active ] │
│                                    │  [ Remove ]  [ Open Folder ]│
└─────────────────────────────────────────────────────────────────┘
```

A "Channels" filter lets the user opt into pre-releases (read from GitHub's `prerelease` flag).

### 5.3 Disk layout

| OS | `<versionRoot>` |
|---|---|
| Windows | `%LOCALAPPDATA%\stockBacktester\versions\` |
| macOS | `~/Library/Application Support/stockBacktester/versions/` |
| Linux | `~/.local/share/stockBacktester/versions/` |

```
versions/
├── 0.2.0/
│   └── (extracted portable bundle)
├── 0.2.4/
├── 0.3.0/
└── active.json     # { "version": "0.3.0", "executable": "..." }
```

User data (`<userData>` from `01`) is **shared across all versions**. Settings, strategies, plugins persist when the user upgrades or downgrades. Schema migrations live in the app and are forward-compatible (we never break older saved strategies on minor upgrades).

### 5.4 "Active" handling

Cross-platform compatible without admin rights:

- **All OSes (default)**: `active.json` plus a small launcher shim. The shim is what users put on their PATH / Dock. It reads `active.json` and `exec`s the right executable.
- **macOS bonus**: optionally maintain a symlink at `~/Applications/stockBacktester.app -> versions/<active>/stockBacktester.app` so Spotlight finds it. Falls back to the shim.
- **Linux bonus**: optionally write a `.desktop` file pointing at the active version.

Default user flow: **double-click the Launcher**, click **Launch**, the app opens. The user never deals with `active.json` directly.

### 5.5 Update logic

Pseudocode:

```cpp
auto manifest = github.fetchReleaseManifest("v0.3.1");
auto asset    = pickAssetForHost(manifest);     // matches OS + arch + kind

auto temp = downloadWithProgress(asset.url, /*toDir*/ tempDir);
if (sha256(temp) != asset.sha256) return error("checksum mismatch");

extract(temp, versionRoot / "0.3.1");
removeFile(temp);

if (userClickedSetActive) writeActive("0.3.1");
```

Resumable downloads via HTTP `Range`; partial files in `tempDir` are reused on retry.

### 5.6 Minimum-version field

`release-manifest.json` carries `minLauncherVersion`. If a release targets a Launcher feature the user doesn't have (e.g. new download protocol), the Launcher prompts the user to update the Launcher first. The Launcher itself updates by writing the new launcher to a side file, then atomically renaming on next start (Windows: pending-rename, macOS/Linux: rename-over-exe).

---

## 6. Versioning policy

- **Backtester app**: semver. Major break means strategies / plugins built before may not work without a port.
- **Plugin ABI**: independent integer. Major bump only on layout/signature change. Multiple app majors can share one plugin major.
- **Lua API** (`bte.apiVersion`): independent integer (`08` §8).
- **Python strategy API** (`pythonApiVersion`): independent integer once the Python host ships (`05`, `08` §8).
- **Data schema**: owned by the Python pipeline; the C++ side reports what it expects and warns on drift (`04`).

These **independent version tracks** are surfaced in **Help → About** (and the Plugins tab) so users know what script and native extensions must target.

---

## 7. Code signing & notarization

- **macOS**: Developer ID Application certificate, hardened runtime, `notarytool` notarization with stapling. Without these, Gatekeeper blocks first-launch.
- **Windows**: EV or OV code-signing certificate (we recommend [SignPath](https://signpath.io/) for OSS — free for verified projects). Without signing, SmartScreen scares users for weeks.
- **Linux**: AppImages signed with `gpg --detach-sign`; the Launcher verifies the GPG signature when configured to do so.

Signing keys live in GitHub Actions secrets, never in the repo.

---

## 8. Local "from-source" path

For developers, the Launcher is unnecessary:

```bash
git clone https://github.com/<owner>/Stock-Back-Test-System.git
cd Stock-Back-Test-System
git submodule update --init
cmake --preset dev
cmake --build --preset dev
ctest --preset dev
./Output/dev/Src/App/stockBacktester
```

A single `Cmake/Versioning.cmake` generates `version.h` from `git describe --tags --dirty` so dev builds clearly say `0.3.0-12-gabcdef-dirty` in About.

---

## 9. Telemetry

**None by default.** No phone-home. The Launcher contacts only `api.github.com` and the asset URLs the user explicitly chose to download. We may add opt-in crash reporting later (Sentry); not Phase 1.

---

## 10. Tests / CI gates

- Build matrix green is a hard gate for merging to main.
- Smoke test per OS: launch app, open each tab (**Strategies, Backtest, Replay, Screener, Plugins, Logs** per `02`), close cleanly. Performed by Qt Test in headless mode (`QT_QPA_PLATFORM=offscreen` on Linux, `-platform offscreen` everywhere).
- Launcher integration test (Linux only — sufficient): with a fake GitHub server, install two versions, set active, launch each, remove one. Asserts `active.json` correctness.
- Reproducibility: backtest a fixture run on each OS; compare `metrics.json` byte-for-byte (we already promised determinism in `07`). Drift across OS = release blocker.
