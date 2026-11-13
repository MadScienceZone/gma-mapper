# GMA Mapper (Python / PySide6 Port) — Local Setup & Execution Guide

This guide walks through creating the virtual environment, installing dependencies, verifying tests, and running the **GMA Mapper** client locally.

---

## 1. Prerequisites

- **Python 3.11 or newer** (Python 3.12 recommended). Verify with:
  ```powershell
  python --version
  ```
- **Git** (to clone or update the repository).

---

## 2. Navigate to the Repository

Open a terminal (PowerShell or Command Prompt) and change into the project root directory:

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

Check that the CLI command is recognized:
```powershell
gma-mapper --help
```

---

## 7. Running the Mapper Locally

> **Important:** Always launch the interactive GUI from your own terminal (PowerShell, Command Prompt, or Windows Terminal). Non-interactive background sessions cannot open desktop windows on Windows.

### Standalone / Offline Mode:
```powershell
gma-mapper
```
Or directly with Python:
```powershell
python -m gma_mapper
```

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

---

## 8. Direct Invocation Shortcut

Once set up, you do not need to activate the virtual environment each time; you can invoke the executable directly:

```powershell
c:\Users\mbutry\Documents\GMA\gma-mapper\.venv\Scripts\gma-mapper.exe
```
