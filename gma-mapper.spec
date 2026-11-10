# -*- mode: python ; coding: utf-8 -*-
"""PyInstaller specification for building standalone GMA Mapper executables."""

import sys
from pathlib import Path

block_cipher = None

repo_root = Path(SPECPATH).resolve()
src_dir = repo_root / "src"

datas = []
sounds_dir = repo_root / "lib" / "MadScienceZone" / "GMA" / "Mapper" / "sounds"
if sounds_dir.is_dir():
    datas.append((str(sounds_dir), "lib/MadScienceZone/GMA/Mapper/sounds"))

icons_dir = repo_root / "lib" / "MadScienceZone" / "GMA" / "Mapper" / "icons"
if icons_dir.is_dir():
    datas.append((str(icons_dir), "lib/MadScienceZone/GMA/Mapper/icons"))

images_dir = repo_root / "images"
if images_dir.is_dir():
    datas.append((str(images_dir), "images"))

a = Analysis(
    [str(src_dir / "gma_mapper" / "__main__.py")],
    pathex=[str(src_dir)],
    binaries=[],
    datas=datas,
    hiddenimports=[
        "PySide6.QtCore",
        "PySide6.QtGui",
        "PySide6.QtWidgets",
        "PySide6.QtNetwork",
        "PySide6.QtMultimedia",
        "paramiko",
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name="gma-mapper",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=(sys.platform == "darwin"),
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)

if sys.platform == "darwin":
    app = BUNDLE(
        exe,
        name="GMA Mapper.app",
        icon=None,
        bundle_identifier="org.madsciencezone.gma.mapper",
    )

