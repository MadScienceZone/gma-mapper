# GMA Mapper (Python / PySide6 Port) — Performance Changes & Benchmarks

This document tracks the performance optimizations implemented during the Python 3.12 / PySide6 port of **GMA Mapper**, why each change was made, and the measured impact.

---

## 1. Measurement Methodology

- **Timer**: `time.perf_counter()` in isolated single-process runs on Python 3.12.4 (Windows).
- **Sampling**: 5 interleaved trials per comparison after warm-up (reporting **median** elapsed time in milliseconds `ms`).
- **Cached vs. Uncached**: For `@functools.lru_cache` optimizations, current cached calls are measured directly against their underlying uncached `.__wrapped__` implementations or pre-cache baseline commits.
- **Full Suite / Regression**: Multi-commit comparison across `ca46ba0` (initial optimization baseline), `72520b3` (feature-complete before Pylint cleanups), `c74db24` (post-Pylint `10.00/10` cleanups), and the working tree (`search_in_path` caching).

---

## 2. Summary of Performance Optimizations

| Optimization | Files | Reason & Brief Description | Before | After | Measured Change |
| :--- | :--- | :--- | ---: | ---: | :--- |
| **Executable `PATH` lookup cache** (`search_in_path`, impacting `fix_missing`) | `src/gma_mapper/core/util.py`, `src/gma_mapper/core/profile.py` | `default_preferences()`, `empty_server_profile()`, and `fix_missing()` call `search_in_path()` repeatedly for `curl`, `nc`, `scp`, and `ssh`; uncached `shutil.which()` scanned every OS `PATH` directory on every call. Added `@functools.lru_cache(maxsize=32)`. | `3,832.84 ms` *(400 path lookups)*<br>`87,259.33 ms` *(1,000 `fix_missing` calls)*<br>`4.365 s` *(86-test suite)* | `0.0200 ms`<br>`540.94 ms`<br>`3.110 s` | **191,643× faster** (-99.999%)<br>**161.3× faster** (-99.4%)<br>**-28.8%** (-1.255 s) |
| **Creature size & threat/reach matrix cache** (`creature_size_params`, `parse_size_code`, `reach_matrix`, `computed_reach_matrix`) | `src/gma_mapper/core/zones.py` *(commit `ca46ba0`)* | Battle-map token rendering, hit-testing, tooltips, and threat-zone overlays repeatedly query the same size descriptors (`M`, `L`, `H10->15`, etc.). Added `@functools.lru_cache` (`maxsize=512` / `128` / `256`) and standard aliases (`4`/`G`, `6`/`C`) to avoid repeated regex parsing and 2D matrix rebuilds. | `1,283.09 ms` *(160,000 calls)* | `8.76 ms` | **146.5× faster** (-99.3%) |
| **MiniMarkup & HTML cache + regex consolidation** (`_render_cached`, `render_html`, `_FRACTION_RE`) | `src/gma_mapper/core/minimarkup.py` *(commit `ca46ba0`)* | Chat re-renders, pinned logs, and notes repeatedly process the same markup strings. Consolidated 6 separate fraction regexes into a single `_FRACTION_RE` pass and cached immutable span tuples and HTML output with `@functools.lru_cache(maxsize=256)`. | `123.87 ms` *(18,000 calls)* | `0.94 ms` | **131.4× faster** (-99.2%) |
| **Color parsing & contrast cache** (`parse_color_rgb`, `color_to_hex`, `contrasting_color`) | `src/gma_mapper/core/colors.py` *(commit `ca46ba0`)* | Grid lines, shapes, tokens, markers, and die-roll color blocks resolve the same X11 names and hex strings on every paint event. Added `@functools.lru_cache(maxsize=512)`. | `112.36 ms` *(300,000 calls)* | `13.08 ms` | **8.6× faster** (-88.4%) |
| **Controller dispatch & token sync refactoring** (`MapperController`, `CreatureTokenItem.sync_position`) | `src/gma_mapper/ui/main_window.py`, `src/gma_mapper/ui/canvas/items.py` *(commit `c74db24`)* | Moved `build_token_tooltip()` into `items.py` (removing repeated lazy circular import), extracted `_handle_conn_command()`, `_handle_ai_command()`, and unified `_handle_oa_list_delta()`, and replaced 18 pass-through signal lambdas with direct bound methods. | `153.33 ms` *(1,500 `CONN`/`OA±` dispatches)* | `146.50 ms` | **4.5% faster** (-6.83 ms) |
| **Async background downloads & streaming USTAR extraction** (`_download_pool`, `ustar_extract`) | `src/gma_mapper/ui/main_window.py`, `src/gma_mapper/core/cache.py`, `src/gma_mapper/core/util.py` *(commit `ca46ba0`)* | Offloaded `AI`/`L` HTTP fetches (`urllib.request.urlopen(..., timeout=30)`) to a 4-worker `ThreadPoolExecutor` marshaled via Qt signals so network I/O never blocks the GUI event loop; streamed 512-byte blocks into `bytearray` with `MAX_USTAR_ENTRY_SIZE` guard instead of `b"".join(chunks)`. | Synchronous GUI-thread HTTP waits (up to 30 s socket timeout) + full chunk-list buffering | Off-thread `ThreadPoolExecutor(max_workers=4)` + streaming `bytearray` | Eliminates GUI-thread network stalls and intermediate block-list copies *(architectural; not microbenchmarked)* |

---

## 3. Detailed Change Notes & Rationale

### 3.1 Executable `PATH` Lookup Caching (`search_in_path` & `fix_missing`)
- **Files**: [`src/gma_mapper/core/util.py`](src/gma_mapper/core/util.py), [`src/gma_mapper/core/profile.py`](src/gma_mapper/core/profile.py)
- **What Changed & Why**: Added `@functools.lru_cache(maxsize=32)` on `search_in_path(cmd)`. Whenever `default_preferences()`, `empty_server_profile()`, or `fix_missing()` runs (on startup, preference normalization, profile cloning, or dialog open), it looks up `curl`, `nc`, `scp`, and `ssh` (7+ calls per `fix_missing()`). Without caching, `shutil.which()` walked every directory in the OS `PATH` each time (~87 ms per `fix_missing()` call on Windows).
- **Amount of Change**:
  - `search_in_path()` (400 calls across `curl`, `nc`, `scp`, `ssh`): **`3,832.84 ms` → `0.0200 ms`** (**191,643× speedup**).
  - `fix_missing()` (1,000 calls): **`87,259.33 ms` → `540.94 ms`** (**161.3× speedup**, reducing per-call cost from **87.26 ms** to **0.54 ms**).
  - Entire 86-test `unittest` suite: **`4.365 s` → `3.110 s`** (**28.8% faster**).

### 3.2 Creature Size & Threat/Reach Matrix Caching (`core.zones`)
- **File**: [`src/gma_mapper/core/zones.py`](src/gma_mapper/core/zones.py) (commit `ca46ba0`)
- **What Changed & Why**: Decorated `creature_size_params()`, `parse_size_code()`, `reach_matrix()`, and `computed_reach_matrix()` with `@functools.lru_cache` (`maxsize=512`, `512`, `128`, `256`), and mapped `"4"` → `"G"` and `"6"` → `"C"` directly in `_STANDARD_MATRICES`. Token `boundingRect()`, `shape()`, `paint()`, AoE placement, and threat arrows invoke these helpers repeatedly across unchanged creature sizes.
- **Amount of Change**:
  - 160,000 calls (5,000 iterations × 8 size strings × 4 functions): **`1,283.09 ms` → `8.76 ms`** (**146.5× speedup**).

### 3.3 MiniMarkup Caching & Fraction Regex Consolidation (`core.minimarkup`)
- **File**: [`src/gma_mapper/core/minimarkup.py`](src/gma_mapper/core/minimarkup.py) (commit `ca46ba0`)
- **What Changed & Why**: Replaced 6 individual regex passes (`\b1/2\b`, `\b1/4\b`, `\b3/4\b`, and `\b(\d+)_...`) with a single compiled `_FRACTION_RE` lookup pass, and cached immutable span tuples (`_render_cached`) plus `render_html()` (`maxsize=256`).
- **Amount of Change**:
  - 18,000 calls (3,000 iterations × 3 sample strings × 2 functions): **`123.87 ms` → `0.94 ms`** (**131.4× speedup**).

### 3.4 Color Resolution & Contrast Caching (`core.colors`)
- **File**: [`src/gma_mapper/core/colors.py`](src/gma_mapper/core/colors.py) (commit `ca46ba0`)
- **What Changed & Why**: Added `@functools.lru_cache(maxsize=512)` to `parse_color_rgb()`, `color_to_hex()`, and `contrasting_color()`. Since return values are immutable tuples and strings, caching eliminates repeated regex/dict normalization and luminance arithmetic across canvas repaints and chat rendering.
- **Amount of Change**:
  - 300,000 calls (10,000 iterations × 10 colors × 3 functions): **`112.36 ms` → `13.08 ms`** (**8.6× speedup**).

### 3.5 Controller Dispatch & Token Sync Refactoring
- **Files**: [`src/gma_mapper/ui/main_window.py`](src/gma_mapper/ui/main_window.py), [`src/gma_mapper/ui/canvas/items.py`](src/gma_mapper/ui/canvas/items.py), [`src/gma_mapper/net/client.py`](src/gma_mapper/net/client.py), [`src/gma_mapper/ui/canvas/view.py`](src/gma_mapper/ui/canvas/view.py) (commit `c74db24`)
- **What Changed & Why**: Resolved Pylint cyclic import (`R0401`), deep nesting (`R1702`), and unnecessary lambdas (`W0108`) by moving `build_token_tooltip()` alongside `CreatureTokenItem` (removing a lazy cross-module import on every `sync_position()`), extracting dedicated `CONN`, `AI`, and unified `OA±` handlers in `MapperController`, and binding Qt signals directly to methods.
- **Amount of Change**:
  - `MapperController.dispatch_command()` (1,500 `CONN`/`OA+`/`OA-` commands): **`153.33 ms` → `146.50 ms`** (**4.5% faster**).

### 3.6 Non-Blocking Downloads & Streaming USTAR Extraction
- **Files**: [`src/gma_mapper/ui/main_window.py`](src/gma_mapper/ui/main_window.py), [`src/gma_mapper/core/cache.py`](src/gma_mapper/core/cache.py), [`src/gma_mapper/core/util.py`](src/gma_mapper/core/util.py)
- **What Changed & Why**:
  - Moved blocking `AssetCache.fetch_image()` and `fetch_map_file()` calls (`urllib.request.urlopen(..., timeout=30)`) off the Qt event loop into `self._download_pool = ThreadPoolExecutor(max_workers=4)`, delivering completed paths via `_image_downloaded` and `_map_downloaded` Qt signals.
  - Updated `ustar_extract()` to stream 512-byte blocks into a single `bytearray` and enforce a per-entry size ceiling (`max_entry_size`), removing the intermediate list of 512-byte `bytes` objects prior to `b"".join(chunks)`.

---

## 4. Multi-Commit Feature & Lint Regression Comparison

To verify that newly ported features (`9d24562`..`72520b3`) and Pylint `10.00/10` cleanups (`c74db24`) did not degrade existing performance, all shared hot paths were benchmarked across commits using 5 interleaved trials (median `ms`):

| Benchmark Workload | `ca46ba0` (ms) | `72520b3` (ms) | `c74db24` (ms) | Current (`search_in_path` cached) | Change vs `ca46ba0` |
| :--- | ---: | ---: | ---: | ---: | ---: |
| Colors (`lru_cache` hit, 300k calls) | 17.25 | 17.15 | 16.95 | 16.95 | **-1.8%** |
| Colors (uncached `__wrapped__`, 100k calls) | 46.26 | 46.29 | 46.53 | 46.53 | +0.6% |
| Creature Zones & Reach (200k calls) | 97.41 | 97.50 | 97.58 | 97.58 | +0.2% |
| MiniMarkup (`render` + HTML + `strip`, 90k calls) | 18.99 | 19.33 | 19.20 | 19.20 | +1.1% |
| Profile `fix_missing()` (1,000 calls) | 81,383.21 | 84,691.82 | 87,259.33 | **540.94** | **-99.3% (150.4× faster vs `ca46ba0`)** |
| File I/O `parse_tcl_list()` (8,000 calls) | 96.75 | 86.45 | 89.26 | 89.26 | **-7.7%** |
| Protocol Parse & Batch Encode (18,000 cmds) | 193.40 | 176.35 | 178.03 | 178.03 | **-7.9%** |
| Spell AoE Geometry (1,800 calls) | 553.03 | 476.90 | 484.16 | 484.16 | **-12.5%** |
| Die Roller Presets & `prepare_die_roll()` (1,500 calls) | N/A | 24.90 | 25.95 | 25.95 | +4.2% *(vs `72520b3`)* |
| Combat Threat Arrows (12 tokens × 1,000) | N/A | 228.49 | 238.31 | 238.31 | +4.3% *(vs `72520b3`)* |
| Token Tooltip `build_token_tooltip()` (12,000 calls) | N/A | 37.38 | 37.19 | 37.19 | **-0.5%** *(vs `72520b3`)* |
| `MapperController.dispatch_command()` (1,500 cmds) | N/A | 153.33 | 146.50 | 146.50 | **-4.5%** *(vs `72520b3`)* |
