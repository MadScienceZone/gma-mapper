# GMA Mapper (`v5.0`) — Remaining Main Window To-Do List

## 1. Play Menu Additions
- [ ] **"Specify What Character You're Playing..." (`AKA`)**: Dialog allowing players to select or enter which character(s) they control and send `ProtocolSession.aka()` to the server.
- [ ] **Die-Roll Preset Editor**:
  - [ ] *"Edit Die Roll Presets..."* and *"Edit System Die Roll Presets..."* (in-app CRUD editor synced via `DD=`, `DD+`, `DD/`).
- [ ] **Die-Roll Preset Delegation**:
  - [ ] *"Manage Die-Roll Preset Delegates..."* (`DDD`).
  - [ ] *"Access Die Rolls For..."* and *"Refresh Die-Roll and Delegate Data from Server"* (`DD?`).
- [ ] **Quick Server Profile Switcher**: Submenu in the Play menu to switch between saved server profiles or reconnect without opening `PreferencesDialog`.

## 2. Tools Menu (Cache, Chat & Diagnostics)
- [ ] **Image Cache Management**:
  - [ ] *"Clear Image Cache"* and *"Clear Image Cache (over 60 days)"* on `AssetCache`.
  - [ ] *"Retry Failed Image Retrievals"*.
- [ ] **Chat History Management**:
  - [ ] *"Clear Chat History"* and *"Clear Pinned Chat Messages"*.
  - [ ] *"Reset Chat History (load 50 / 100 / 500 / all)"* (sending `CC` to the server).
- [ ] **Server Ping Test**:
  - [ ] *"Test Server Response Time..."* using `MARCO` / `POLO` round-trip timing.

## 3. View Menu Dock Toggles
- [ ] Add `clock_dock.toggleViewAction()` (`Alt+C`), `combat_dock.toggleViewAction()`, and `chat_dock.toggleViewAction()` (`Alt+D`) to the **View** menu so closed dock panels can be easily reopened.

## 4. Help Menu Reference Dialogs
- [ ] *"About GMA Mapper..."* (`F1`)
- [ ] *"Die Roller Syntax..."* (`?`)
- [ ] *"Die Modifiers and Conditions..."*
- [ ] *"Text Markup Syntax..."* (`Alt+?`)

