# GMA Mapper (Python / PySide6 Port) — Local Setup & Execution Guide

This guide walks through creating the virtual environment, installing dependencies, verifying tests, and running the **GMA Mapper** client locally.

---

## 1. Prerequisites

- **Python 3.11 or newer** (Python 3.12 recommended). Verify with:
  ```powershell
  python --version
  ```
- **Git** (to clone or update the repository).
- **Repository**: https://github.com/MadScienceZone/gma-mapper.git

---

## 2. Clone or Navigate to the Repository

If cloning for the first time, clone the repository and check out the `python-port` branch:

```powershell
git clone -b python-port https://github.com/MadScienceZone/gma-mapper.git
cd gma-mapper
```

Or if you already have the repository cloned locally, change into the project root directory:

```powershell
cd c:\Users\mbutry\Documents\GMA\gma-mapper
```

---

## 3. Create the Virtual Environment

Create a dedicated virtual environment named `.venv` in the repository root:

```powershell
python -m venv .venv
```

---

## 4. Activate the Virtual Environment

### On Windows (PowerShell):
```powershell
.\.venv\Scripts\Activate.ps1
```
> **Note:** If PowerShell blocks script execution with an execution policy error, run:
> ```powershell
> Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
> .\.venv\Scripts\Activate.ps1
> ```

### On Windows (Command Prompt `cmd.exe`):
```cmd
.venv\Scripts\activate.bat
```

### On Linux / macOS (Bash / Zsh):
```bash
source .venv/bin/activate
```

*(Once activated, your command prompt will be prefixed with `(.venv)`).*

---

## 5. Install Dependencies and GMA Mapper

Upgrade core packaging tools and install the package in **editable development mode** (`-e`):

```powershell
python -m pip install --upgrade pip setuptools wheel
```

### Standard installation (Core GUI + networking):
```powershell
pip install -e .
```

### Full installation (includes SFTP upload support and dev/test tools):
```powershell
pip install -e ".[dev,sftp]"
```

This installs:
- **PySide6** (Qt 6 GUI framework)
- **httpx** (HTTP asset downloading & async caching)
- **cryptography** (Release verification)
- **paramiko** *(optional, for SFTP/SSH map uploads to GM server)*
- **pytest / pyinstaller** *(optional dev tools)*
- Console entry point: `gma-mapper`
- Windowed entry point: `gma-mapper-gui`

---

## 6. Verify the Installation

Run the unit test suite to ensure all tests pass:

```powershell
python -m unittest discover -s tests -v
```

Check that the CLI command and repository launcher are recognized:
```powershell
gma-mapper --help
python bin\py_mapper.py --version
```

---

## 7. Running the Mapper Locally

> **Important:** Always launch the interactive GUI from your own terminal (PowerShell, Command Prompt, or Windows Terminal). Non-interactive background sessions cannot open desktop windows on Windows.

### Standalone / Offline Mode:
```powershell
gma-mapper
```
Or via the repository launcher or Python module:
```powershell
python bin\py_mapper.py
```
```powershell
python -m gma_mapper
```
On Linux / macOS:
```bash
./bin/py_mapper
```

### Listing & Selecting Saved Server Profiles:
List the saved server profiles from `preferences.json`:
```powershell
python bin\py_mapper.py --list-profiles
```
*(Short flag `-L` and legacy `-list-profiles` or `gma-mapper --list-profiles` are also supported.)*

Launch directly into a saved server profile:
```powershell
python bin\py_mapper.py --select Liberte
```
*(Also supports `-S`, `--profile`, and legacy `-select` / `-profile`. Pass `-f path\to\preferences.json` or `--config` to use a custom preferences file.)*

### Opening an existing `.map` file:
```powershell
gma-mapper path\to\dungeon.map
```

### Connecting to a GMA Server:
```powershell
gma-mapper -h gma.kwycstix.org -p 2325
```
Or with specific user credentials:
```powershell
gma-mapper -h gma.kwycstix.org -p 2325 -u PlayerName
```

### Windowed Mode (No background console):
You can also launch `gma-mapper-gui.exe`:
```powershell
.\.venv\Scripts\gma-mapper-gui.exe
```

### Running Side-by-Side with the Legacy Tcl/Tk Mapper:
`bin/mapper.tcl` remains the legacy Tcl/Tk client (matching `main`), while `bin/py_mapper.py` (Windows / cross-platform) and `bin/py_mapper` (Linux / macOS) launch the Python/PySide6 port. To run both side-by-side in separate terminals for feature comparison:

- **Legacy Tcl/Tk mapper:**
  ```powershell
  C:\Users\mbutry\Documents\GMA\gma-mapper\bin\mapper.tcl --select Liberte
  ```
- **Python / PySide6 mapper:**
  ```powershell
  C:\Users\mbutry\Documents\GMA\gma-mapper\bin\py_mapper.py --select Liberte
  ```
  *(Use `python bin\py_mapper.py --select Liberte` if `.py` files are not associated with Python, or `./bin/py_mapper --select Liberte` on Linux/macOS.)*

> **Note on shared preferences:** Both clients read the same default `preferences.json`, so your saved server profiles work in both. If you intend to modify Preferences while both clients are open simultaneously, pass `-f path\to\preferences-copy.json` to `py_mapper.py` so they do not overwrite each other's saved settings.

---

## 8. Direct Invocation Shortcut

Once `.venv` is set up, you do not need to activate the virtual environment each time. The repository launchers (`bin\py_mapper.py` on Windows/cross-platform and `bin/py_mapper` on Linux/macOS) automatically detect and delegate to `.venv`, or you can invoke the installed `.venv` executables directly:

```powershell
c:\Users\mbutry\Documents\GMA\gma-mapper\bin\py_mapper.py --select Liberte
```
*(Or `python c:\Users\mbutry\Documents\GMA\gma-mapper\bin\py_mapper.py --select Liberte`.)*

On Linux / macOS:
```bash
./bin/py_mapper --select Liberte
```

Installed `.venv` executables on Windows:
```powershell
c:\Users\mbutry\Documents\GMA\gma-mapper\.venv\Scripts\gma-mapper.exe
c:\Users\mbutry\Documents\GMA\gma-mapper\.venv\Scripts\gma-mapper-gui.exe
```
