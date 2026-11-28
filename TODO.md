# GMA Mapper (`v5.0`) — Remaining Main Window To-Do List

## 1. Play Menu Additions
- [x] **"Specify What Character You're Playing..." (`AKA`)**: Dialog allowing players to select or enter which character(s) they control and send `ProtocolSession.aka()` to the server.
- [x] **Die-Roll Preset Editor**:
  - [x] *"Edit Die Roll Presets..."* and *"Edit System Die Roll Presets..."* (in-app CRUD editor synced via `DD`, `DD+`, `DR`/`DD=`).
- [x] **Die-Roll Preset Delegation**:
  - [x] *"Manage Die-Roll Preset Delegates..."* (`DDD`).
  - [x] *"Access Die Rolls For..."* and *"Refresh Die-Roll and Delegate Data from Server"* (`DR`).
- [x] **Quick Server Profile Switcher**: Submenu in the Play menu to switch between saved server profiles or reconnect without opening `PreferencesDialog`.

## 2. Tools Menu (Cache, Chat & Diagnostics)
- [x] **Top-level Tools Menu**: Add `&Tools` menu to `GMAMapperMainWindow` (including *"Check for Updates..."* currently under Help, if moving/mirroring to match legacy).
- [x] **Image Cache Management**:
  - [x] *"Clear Image Cache"* (`cleanup_image_cache(0)`), *"Clear Image Cache (over 60 days)"* (`cleanup_image_cache(60)`), and *"Update Cached Images from Server"* (`cleanup_image_cache("-update")` + `AI?` re-queries).
  - [x] *"Retry Failed Image Retrievals"* (clear `forbidden_urls` on `AssetCache` and `ProtocolSession`).
- [x] **Chat History Management**:
  - [x] *"Clear Chat History"* and *"Clear Pinned Chat Messages"*.
  - [x] *"Reset Chat History"* submenu (*"...and load 50 / 100 / 500 / all messages"*, clearing local chat and sending `SYNC-CHAT` via `ProtocolSession.sync_chat()`).
- [x] **Server Ping Test**:
  - [x] *"Test Server Response Time..."* dialog (`ServerPingTest`) using periodic `ECHO` round-trip timing (In Transit / In Server / Round-Trip).
- [x] **Diagnostic Logging**:
  - [x] *"Save Diagnostic Messages As..."* (`SaveDebugText` — capture diagnostic log buffer and export to `.txt`).

## 3. View Menu Dock Toggles
- [x] Add `clock_dock.toggleViewAction()` (`Alt+Shift+C`; `Alt+C` remains on Play -> Show Initiative Clock), `combat_dock.toggleViewAction()`, and `chat_dock.toggleViewAction()` (`Alt+D`) to the **View** menu so closed dock panels can be easily reopened.

## 4. Help Menu Reference Dialogs
- [x] *"About GMA Mapper..."* (`F1`)
- [x] *"Die Roller Syntax..."* (`?`)
- [x] *"Die Modifiers and Conditions..."*
- [x] *"Text Markup Syntax..."* (`Alt+?`)

## 5. Chat & Die Roller Window Improvements
- [x] **Load Chat History When Opening Chat / Die Roller Window**: Automatically request/load chat history from the server (e.g., via `SYNC-CHAT` respecting profile `chat_limit` / `suppress_chat`) when connecting or opening the Chat & Dice Roller window.
- [x] **Better Default Colors in Chat History Window**: Improve default light/dark theme colors and contrast in the chat history window for messages, sender labels, timestamps, and die-roll results.
- [x] **Load Server Dice Presets When Starting Chat / Die Roller**: If the PC or GM has die-roll presets stored on the server, automatically request/load them (e.g., via `DR`) when connecting or opening the Chat & Dice Roller window.

## 6. Window Layout Persistence
- [x] **Save Window Layout Feature**: Persist and restore main window and dock panel layout across sessions (docked vs. undocked/floating state, docked area/position, floating window geometry, and dock sizes).

## 7. Standalone Die Roller Port (`src/py_dieroller`)
- [x] **Port Standalone Die Roller from `gma/extras/dieroller` to `src/py_dieroller`**: Copy the standalone die roller code from `gma/extras/dieroller` into `src/py_dieroller` and port its GUI to PySide6 while keeping it operable as a standalone die roller application.

## 8. Debug / Diagnostic Message Window
- [x] **Spawn Debug Window for Errors and Diagnostic Messages**: Match legacy mapper behavior by spawning/displaying a dedicated debug/diagnostic window to show errors, protocol traces, and diagnostic messages as they occur (with support for saving/clearing diagnostic messages).

## 9. Distance Measurement Features
- [x] **Distance from Icon**: Measure/display distance from a selected icon/creature matching legacy `bin/mapper.tcl` behavior.
- [x] **Distance from Cell**: Measure/display distance from a chosen grid cell matching legacy `bin/mapper.tcl` behavior.

## 10. Standalone Die Roller Enhancements (`src/py_dieroller`)
- [x] **Pinned Chat Messages**: Port pinned chat message support from the legacy die roller / mapper into `src/py_dieroller`.

## 11. Die Roller Tables
- [x] **Port Legacy Die Roller Tables**: Port legacy die roller table support (`#table` / random lookup tables) to the Python port (`src/gma_mapper` and `src/py_dieroller`).

