# GMA Mapper (Python / PySide6 Port) — Agent Guidelines

## Environment & Test Execution
- **Virtual Environment**: Always use `c:\Users\mbutry\Documents\GMA\gma-mapper\.venv\Scripts\python.exe` (and `gma-mapper.exe` in `.venv\Scripts\`).
- **Unit Test Suite**: Run all tests via:
  ```powershell
  .\gma-mapper\.venv\Scripts\python.exe -m unittest discover -s gma-mapper\tests -v
  ```
- **Pure-Python Testability**: Keep core logic, protocol state machines (`ProtocolSession`), controllers (`MapperController`), and canvas geometry/menu helpers testable without requiring a visible display server.

## Windows GUI Launching Constraint
- Processes started via the agent's `run_command` tool on Windows run inside a non-interactive session/window station; Qt (`PySide6`) windows created there **will not be visible** on the user's desktop even when `BypassSandbox: true` is used.
- Do not attempt to pop up the interactive `gma-mapper` GUI window for the user via `run_command`. Instead, verify behavior with headless unit tests and provide the exact command line for the user to run in their own interactive terminal, e.g.:
  ```powershell
  c:\Users\mbutry\Documents\GMA\gma-mapper\.venv\Scripts\gma-mapper.exe -h gma.kwycstix.org -p 2325
  ```

## Legacy Tcl/Tk (`bin/mapper_legacy.tcl`) Parity Conventions
- **Grid Coordinate Origin (`A1`)**: Grid `(0, 0)` corresponds to column `A`, row `1` (`A1`). While `BattleMapScene` supports negative scene coordinates for panning, `BattleMapView` must align scene `(0, 0)` (`A1`) at the top-left corner of the viewport on startup and on `reset_to_origin()` (`Home` / `Ctrl+0`), and only draw positive grid coordinate labels (`col >= 0`, `row >= 0`).
- **Creature Token Fallback Geometry**: Both player (`PCR` / `CreatureType == 1`) and monster (`MCR` / `CreatureType == 2`) fallback tokens (when no raster skin is loaded) render as circles with a contrasting inner ring and creature-type fill color (`#0000ff` for players, `#ff0000` for monsters), matching `draw_creature` in `bin/mapper_legacy.tcl`.
- **Spell AoE (`LS-SAOE`)**: Support both standalone canvas AoE items and creature-attached `AoE` / `_AoE` emanations, using perimeter/spread BFS rules (`AOE_GLOBAL_BOUND = 40`) matching `bin/mapper_legacy.tcl`.

## Network & Threading Guardrails (`src/gma_mapper/net`)
- **Never Block the Qt Event Loop**: Never perform synchronous HTTP/asset downloads (`urllib.request`) on the main Qt GUI thread during protocol dispatch (`AI`, `L`, `SYNC`). Always dispatch downloads to a background thread pool and marshal UI updates back via Qt signals.
- **Schema Consistency**: Keep `MESSAGE_PAYLOAD["Health"]` unified with `_HEALTH_PAYLOAD` so `OA` attribute updates (`_attribute_encode("Health", ...)`) include `TmpHP`, `TmpDamage`, `AC`, `FlatFootedAC`, `TouchAC`, and `CMD`.
- **Protocol Framing & Batching**:
  - Sanitize `\r` and `\n` in outgoing protocol lines (`_raw_send`).
  - Slice and reassemble `BATCH` payloads as raw UTF-8 `bytes` before decoding to `str` so multi-byte UTF-8 code points split across fragment boundaries never fail.

