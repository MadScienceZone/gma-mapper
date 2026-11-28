# GMA Mapper (Python / PySide6 Port) — Agent Guidelines

## Environment & Test Execution
- **Virtual Environment**: Always use `c:\Users\mbutry\Documents\GMA\gma-mapper\.venv\Scripts\python.exe` (and `gma-mapper.exe` in `.venv\Scripts\` or `bin/py_mapper.py`).
- **Unit Test Suite**: Run all tests via:
  ```powershell
  .\.venv\Scripts\python.exe -m unittest discover -s tests -v
  ```
- **Pylint Cleanliness**: Verify changes across both packages with `.\.venv\Scripts\python.exe -m pylint src/gma_mapper src/py_dieroller` and maintain a `10.00/10` score.
- **PowerShell Command Chaining**: Use `;` (or `if ($LASTEXITCODE -eq 0)`) instead of `&&` when running commands in Windows PowerShell 5.1.
- **Pure-Python Testability**: Keep core logic, protocol state machines (`ProtocolSession`), controllers (`MapperController`), and canvas geometry/menu helpers testable without requiring a visible display server.
- **Headless Qt UI Test Isolation**: Run GUI tests with `QT_QPA_PLATFORM=offscreen`, patch `Path.home` / use `tempfile.TemporaryDirectory()` so tests never read or mutate real user files (`~/.dieroller/`, `~/.gma/mapper/`), avoid code paths that open blocking `QMessageBox` / `QFileDialog` modals, and derive floating widget test geometries from `minimumSizeHint()` rather than hardcoded small sizes.

## Windows GUI Launching Constraint
- Processes started via the agent's `run_command` tool on Windows run inside a non-interactive session/window station; Qt (`PySide6`) windows created there **will not be visible** on the user's desktop even when `BypassSandbox: true` is used.
- Do not attempt to pop up the interactive `gma-mapper` GUI window for the user via `run_command`. Instead, verify behavior with headless unit tests and provide the exact command line for the user to run in their own interactive terminal, e.g.:
  ```powershell
  c:\Users\mbutry\Documents\GMA\gma-mapper\bin\py_mapper.py -h gma.kwycstix.org -p 2325
  ```
  (or `c:\Users\mbutry\Documents\GMA\gma-mapper\.venv\Scripts\gma-mapper.exe -h gma.kwycstix.org -p 2325`).

## Legacy Tcl/Tk (`bin/mapper.tcl`) Parity Conventions
- **Grid Coordinate Origin (`A1`)**: Grid `(0, 0)` corresponds to column `A`, row `1` (`A1`). While `BattleMapScene` supports negative scene coordinates for panning, `BattleMapView` must align scene `(0, 0)` (`A1`) at the top-left corner of the viewport on startup and on `reset_to_origin()` (`Home` / `Ctrl+0`), and only draw positive grid coordinate labels (`col >= 0`, `row >= 0`).
- **Creature Token Fallback Geometry**: Both player (`PCR` / `CreatureType == 1`) and monster (`MCR` / `CreatureType == 2`) fallback tokens (when no raster skin is loaded) render as circles with a contrasting inner ring and creature-type fill color (`#0000ff` for players, `#ff0000` for monsters), matching `draw_creature` in `bin/mapper.tcl`.
- **Spell AoE (`LS-SAOE`)**: Support both standalone canvas AoE items and creature-attached `AoE` / `_AoE` emanations, using perimeter/spread BFS rules (`AOE_GLOBAL_BOUND = 40`) matching `bin/mapper.tcl`.

## Legacy Configuration Compatibility
- **Preserve `preferences.json` Schema**: Never write Python-port-only keys into `~/.gma/mapper/preferences.json` so `bin/mapper.tcl` retains full backwards compatibility. Persist Python main-window/dock layout separately in `window_layout.json` and keep standalone `py_dieroller` config/presets separate in `~/.dieroller/`.

## PySide6 Architecture & Launcher Conventions
- **Package-Shadowing Launchers**: Any `bin/<name>.py` launcher whose filename matches a package in `src/` must remove its `bin/` directory from `sys.path` and insert `src/` at index `0` before importing the package, preventing `ModuleNotFoundError: '<name>' is not a package` under editable `.venv` installs.
- **Independent Modeless Windows & Dock Cleanup**: Modeless utility windows (`PlayerClockWindow`, `DelegatedDieRollerDialog`, `DiagnosticWindow`, `DistanceDialog`) should use `parent=None` + `detach_window_owner()` so Windows Z-order lets users layer the main map window in front, and must be closed cleanly in `GMAMapperMainWindow.closeEvent()`.
- **Qt `bool` Signal Payload Trap**: Never connect `QAction.triggered(bool)` or `QAbstractButton.clicked(bool)` directly to slots whose first optional parameter expects a string or domain value; wrap them with `lambda _c=False: ...`.

## Network & Threading Guardrails (`src/gma_mapper/net`)
- **Never Block the Qt Event Loop**: Never perform synchronous HTTP/asset downloads (`urllib.request`) on the main Qt GUI thread during protocol dispatch (`AI`, `L`, `SYNC`). Always dispatch downloads to a background thread pool and marshal UI updates back via Qt signals.
- **Schema Consistency**: Keep `MESSAGE_PAYLOAD["Health"]` unified with `_HEALTH_PAYLOAD` so `OA` attribute updates (`_attribute_encode("Health", ...)`) include `TmpHP`, `TmpDamage`, `AC`, `FlatFootedAC`, `TouchAC`, and `CMD`.
- **Protocol Framing & Batching**:
  - Sanitize `\r` and `\n` in outgoing protocol lines (`_raw_send`).
  - Slice and reassemble `BATCH` payloads as raw UTF-8 `bytes` before decoding to `str` so multi-byte UTF-8 code points split across fragment boundaries never fail.

## Code Quality, Performance & Documentation Conventions
- **Benchmark Before Optimizing**: Before applying performance optimizations, establish a reproducible baseline benchmark (e.g., using `time.perf_counter()` in a scratch script), then re-run the benchmark after the changes to verify and report the actual speedup.
- **Explanatory Comments on Security & Architectural Changes**: Add clear inline comments explaining *why* security guards (atomic temp-file + `os.replace` writes, identifier regex allowlists, `shlex.quote`, archive entry size limits) and architectural optimizations exist.
- **SMF Forum BBCode Exports**: When formatting RFCs or reviews in BBCode for Simple Machines Forum (SMF):
  - Use `[font=courier new]...[/font]` for inline monospace text (SMF does not parse `[tt]`).
  - Use `[list]` and `[list type=decimal]` with `[li]...[/li]` items (rather than `[list=1]` or `[*]`).


