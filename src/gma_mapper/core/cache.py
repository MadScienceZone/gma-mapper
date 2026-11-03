"""Asset cache management, HTTP downloads (If-Modified-Since), and GM SSH/SCP/SFTP uploads.

Ported from bin/mapper.tcl.
"""

from __future__ import annotations

import base64
import email.utils
import hashlib
import os
import re
import shutil
import ssl
import subprocess
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

from gma_mapper.net.protocol import json_from_dict, new_dict_from_json

DEFAULT_CACHE_DIR: Path = Path.home() / ".gma" / "mapper" / "cache"
DEFAULT_CURL_SERVER: str = "https://www.rag.com/gma/map"
CACHE_TOO_OLD_DAYS: int = 2


def normalize_zoom(z: float | int | str) -> str:
    """Format zoom level to 2 decimal places (`%.2f`)."""
    return f"{float(z):.2f}"


def tile_id(name: str, zoom: float | int | str) -> str:
    """Return canonical tile identifier `name:zoom`."""
    return f"{name}:{normalize_zoom(zoom)}"


def cache_map_id(filename: str | Path, module_id: str = "") -> str:
    """Generate server-side map ID from filename and optional `module_id`.

    Matches Tcl:
    `string map {+ _ / - = {}} [base64::encode [md5::md5 [concat $ModuleID [file rootname [file tail $filename]]]]]`
    """
    stem = Path(filename).stem
    mod = module_id.strip()
    text = f"{mod} {stem}" if mod else stem
    digest = hashlib.md5(text.encode("utf-8")).digest()
    b64 = base64.b64encode(digest).decode("ascii")
    return b64.replace("+", "_").replace("/", "-").replace("=", "")


class AssetCache:
    """Manages local image/map cache files, HTTP fetching, and GM server uploads."""

    def __init__(
        self,
        cache_dir: str | Path | None = None,
        image_format: str = "png",
        cache_too_old_days: int = CACHE_TOO_OLD_DAYS,
        curl_server: str = DEFAULT_CURL_SERVER,
        curl_insecure: bool = False,
        curl_proxy: str = "",
        scp_server: str = "",
        scp_dest: str = "",
        scp_proxy: str = "",
        ssh_path: str = "ssh",
        scp_path: str = "scp",
        nc_path: str = "nc",
        server_mkdir: str = "mkdir",
    ) -> None:
        self.cache_dir = Path(cache_dir) if cache_dir else DEFAULT_CACHE_DIR
        self.image_format = image_format
        self.cache_too_old_days = cache_too_old_days
        self.curl_server = curl_server.rstrip("/")
        self.curl_insecure = curl_insecure
        self.curl_proxy = curl_proxy
        self.scp_server = scp_server
        self.scp_dest = scp_dest.rstrip("/")
        self.scp_proxy = scp_proxy
        self.ssh_path = ssh_path or "ssh"
        self.scp_path = scp_path or "scp"
        self.nc_path = nc_path or "nc"
        self.server_mkdir = server_mkdir or "mkdir"
        self.forbidden_urls: set[str] = set()

    def _bucket_char(self, name: str) -> str:
        return name[4:5] if len(name) >= 5 else ""

    def cache_file_dir(
        self, name: str, zoom: float | int | str = 1.0, frameno: int = -1
    ) -> Path:
        """Return directory path for cached image `name`."""
        bucket = f"_{self._bucket_char(name)}"
        base = self.cache_dir / bucket
        if frameno >= 0:
            return base / f"{name}@{normalize_zoom(zoom)}"
        return base

    def cache_filename(
        self, name: str, zoom: float | int | str, frameno: int = -1, ensure_dir: bool = True
    ) -> Path:
        """Return full path to cached image or animation frame."""
        z_str = normalize_zoom(zoom)
        parent = self.cache_file_dir(name, zoom, frameno)
        if ensure_dir:
            parent.mkdir(parents=True, exist_ok=True)
        if frameno >= 0:
            sep = ";" if os.name == "nt" else ":"
            return parent / f"{sep}{frameno}{sep}{name}@{z_str}.{self.image_format}"
        return parent / f"{name}@{z_str}.{self.image_format}"

    def cache_map_file_dir(self, map_id: str) -> Path:
        """Return directory path for cached map `map_id`."""
        prefix = map_id[0:1] if map_id else "_"
        return self.cache_dir / prefix

    def cache_map_filename(self, map_id: str, ensure_dir: bool = True) -> Path:
        """Return full path to cached map file."""
        parent = self.cache_map_file_dir(map_id)
        if ensure_dir:
            parent.mkdir(parents=True, exist_ok=True)
        return parent / f"{map_id}.map"

    def cache_info(self, cache_path: str | Path) -> tuple[bool, int, str, str, str]:
        """Return `(exists, age_days, name_or_id, zoom, frame_or_dir)` for a cache path."""
        p = Path(cache_path)
        posix_str = p.as_posix()

        img_pat = rf"/([:;][0-9]+[:;])?([^/]+)@([0-9.]+)\.{re.escape(self.image_format)}$"
        m = re.search(img_pat, posix_str)
        if m:
            image_frame = (m.group(1) or "").replace(";", ":")
            image_name = m.group(2)
            image_zoom = m.group(3)
            if p.exists():
                age = max(0, int(time.time() - p.stat().st_mtime) // 86400)
                return (True, age, image_name, image_zoom, image_frame)
            return (False, 0, image_name, image_zoom, image_frame)

        m_dir = re.search(r"/([^/]+)@([0-9.]+)$", posix_str)
        if m_dir and p.is_dir():
            return (True, 0, m_dir.group(1), m_dir.group(2), "-dir")

        m_map = re.search(r"/([^/]+)\.map$", posix_str)
        if m_map:
            map_name = m_map.group(1)
            if p.exists():
                age = max(0, int(time.time() - p.stat().st_mtime) // 86400)
                return (True, age, map_name, "", "")
            return (False, 0, map_name, "", "")

        return (False, 0, "", "", "")

    def cleanup_image_cache(
        self, days_old: int | str = 0
    ) -> tuple[int, int, list[tuple[str, float]]]:
        """Clean up cached images older than `days_old` (or `"-update"` to refresh).

        Returns `(deleted_count, total_count, refreshed_queries)`.
        """
        deleted = 0
        total = 0
        queries: list[tuple[str, float]] = []

        if not self.cache_dir.exists():
            return (0, 0, queries)

        for cache_subdir in sorted(self.cache_dir.glob("_*")):
            if not cache_subdir.is_dir():
                continue
            for entry in sorted(cache_subdir.iterdir()):
                if entry.is_dir() and "@" in entry.name:
                    total += 1
                    del_all = False
                    for frame_file in sorted(entry.glob(f"*.{self.image_format}")):
                        total += 1
                        _, frame_age, _, _, _ = self.cache_info(frame_file)
                        if days_old == "-update":
                            if frame_age <= self.cache_too_old_days:
                                frame_file.unlink(missing_ok=True)
                                deleted += 1
                        elif isinstance(days_old, int) and frame_age >= days_old:
                            del_all = True
                            break
                    if del_all:
                        shutil.rmtree(entry, ignore_errors=True)
                        deleted += 1
                elif entry.suffix == f".{self.image_format}":
                    total += 1
                    _, img_age, img_name, img_zoom, _ = self.cache_info(entry)
                    if days_old == "-update":
                        if img_age <= self.cache_too_old_days:
                            entry.unlink(missing_ok=True)
                            deleted += 1
                        if img_name and img_zoom:
                            queries.append((img_name, float(img_zoom)))
                    elif isinstance(days_old, int) and img_age >= days_old:
                        entry.unlink(missing_ok=True)
                        deleted += 1

        return (deleted, total, queries)

    def _download_to_file(self, url: str, dest: Path, newer_than_mtime: float = 0.0) -> bool:
        """Download `url` to `dest` with optional `If-Modified-Since` check.

        Returns True if downloaded or 304 Not Modified, False if 404.
        """
        headers: dict[str, str] = {"User-Agent": "GMA-Mapper/5.0"}
        if newer_than_mtime > 0:
            headers["If-Modified-Since"] = email.utils.formatdate(
                newer_than_mtime, usegmt=True
            )

        ctx = None
        if self.curl_insecure:
            ctx = ssl.create_default_context()
            ctx.check_hostname = False
            ctx.verify_mode = ssl.CERT_NONE

        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
                data = resp.read()
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(data)
                now = time.time()
                os.utime(dest, (now, now))
                return True
        except urllib.error.HTTPError as err:
            if err.code == 304:
                if dest.exists():
                    now = time.time()
                    os.utime(dest, (now, now))
                return True
            if err.code == 404:
                return False
            raise

    def fetch_map_file(self, map_id: str) -> Path:
        """Fetch map file `map_id` from cache or `curl_server`."""
        cfile = self.cache_map_filename(map_id)
        exists, age, _, _, _ = self.cache_info(cfile)
        newer_than = 0.0
        if exists:
            if age < self.cache_too_old_days:
                return cfile
            newer_than = cfile.stat().st_mtime

        url = f"{self.curl_server}/{map_id[0:1]}/{map_id[0:2]}/{map_id}.map"
        ok = self._download_to_file(url, cfile, newer_than)
        if not ok:
            raise FileNotFoundError(f"NOSUCH: Map {map_id} not found at {url}")
        return cfile

    def fetch_image(self, name: str, zoom: float, image_id: str) -> Path | None:
        """Fetch image `name` at `zoom` from cache or `curl_server`."""
        cfile = self.cache_filename(name, zoom)
        exists, age, _, _, _ = self.cache_info(cfile)
        newer_than = 0.0
        if exists:
            if age < self.cache_too_old_days:
                return cfile
            newer_than = cfile.stat().st_mtime

        url = f"{self.curl_server}/{image_id[0:1]}/{image_id[0:2]}/{image_id}.{self.image_format}"
        if url in self.forbidden_urls:
            return cfile if cfile.exists() else None

        ok = self._download_to_file(url, cfile, newer_than)
        if not ok:
            self.forbidden_urls.add(url)
            self.forbidden_urls.add(f"{name}:{normalize_zoom(zoom)}")
            return cfile if cfile.exists() else None
        return cfile

    def fetch_animated_image(
        self,
        name: str,
        zoom: float,
        image_id: str,
        frames: int,
        speed: int,
        loops: int,
    ) -> list[Path]:
        """Fetch all frames of an animated image and write its `.meta` file."""
        cache_dirname = self.cache_file_dir(name, zoom, 0)
        cache_dirname.mkdir(parents=True, exist_ok=True)
        frame_paths: list[Path] = []

        for n in range(frames):
            cfile = self.cache_filename(name, zoom, n)
            exists, age, _, _, _ = self.cache_info(cfile)
            newer_than = 0.0
            if exists and age < self.cache_too_old_days:
                frame_paths.append(cfile)
                continue
            if exists:
                newer_than = cfile.stat().st_mtime

            url = f"{self.curl_server}/{image_id[0:1]}/{image_id[0:2]}/:{n}:{image_id}.{self.image_format}"
            self._download_to_file(url, cfile, newer_than)
            if cfile.exists():
                frame_paths.append(cfile)

        meta_path = cache_dirname / f"{name}@{normalize_zoom(zoom)}.meta"
        meta_json = json_from_dict(
            "AI",
            {
                "Name": name,
                "Sizes": [
                    {
                        "File": str(cache_dirname),
                        "Zoom": float(zoom),
                        "IsLocalFile": True,
                    }
                ],
                "Animation": {
                    "Frames": frames,
                    "FrameSpeed": speed,
                    "Loops": loops,
                },
            },
        )
        meta_path.write_text(meta_json + "\n", encoding="utf-8")
        return frame_paths

    def animation_read_metadata(
        self, cachedir: str | Path, name: str, zoom: float | str
    ) -> dict[str, Any]:
        """Read cached animation metadata file (`name@zoom.meta`)."""
        meta_path = Path(cachedir) / f"{name}@{normalize_zoom(zoom)}.meta"
        data = meta_path.read_text(encoding="utf-8")
        return new_dict_from_json("AI", data)

    def send_file_to_server(
        self, file_id: str, local_file: str | Path, use_paramiko: bool = False
    ) -> None:
        """Upload `local_file` to the configured GM server via SSH/SCP or Paramiko SFTP."""
        if not self.scp_dest or not self.scp_server:
            raise ValueError("No upload server has been configured.")

        local_path = Path(local_file)
        destdir = f"{self.scp_dest}/{file_id[0:1]}/{file_id[0:2]}"
        destfile = f"{destdir}/{file_id}.map"

        if use_paramiko:
            try:
                import paramiko  # type: ignore[import-untyped]

                user, _, host = self.scp_server.rpartition("@")
                if not host:
                    host = self.scp_server
                    user = ""
                ssh = paramiko.SSHClient()
                ssh.load_system_host_keys()
                ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
                ssh.connect(host, username=user or None)
                try:
                    _, stdout, stderr = ssh.exec_command(f"{self.server_mkdir} -p {destdir}")
                    stdout.channel.recv_exit_status()
                    sftp = ssh.open_sftp()
                    try:
                        sftp.put(str(local_path), destfile)
                        sftp.chmod(destfile, 0o644)
                    finally:
                        sftp.close()
                finally:
                    ssh.close()
                return
            except ImportError:
                pass

        destpath = f"{self.scp_server}:{destfile}"
        if self.scp_proxy:
            proxy_opt = f"ProxyCommand {self.nc_path} -X 5 -x {self.scp_proxy} %h %p"
            subprocess.run(
                [self.ssh_path, "-o", proxy_opt, self.scp_server, self.server_mkdir, "-p", destdir],
                check=True,
            )
            subprocess.run(
                [self.scp_path, "-p", "-q", "-o", proxy_opt, str(local_path), destpath],
                check=True,
            )
        else:
            subprocess.run(
                [self.ssh_path, self.scp_server, self.server_mkdir, "-p", destdir],
                check=True,
            )
            subprocess.run(
                [self.scp_path, str(local_path), destpath],
                check=True,
            )
