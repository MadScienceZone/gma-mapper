# ########################################################################################
# #  _______  _______  _______                ___          ___    _______                #
# # (  ____ \(       )(  ___  ) Game         /   )        /   )  / ___   )               #
# # | (    \/| () () || (   ) | Master's    / /) |       / /) |  \/   )  |               #
# # | |      | || || || (___) | Assistant  / (_) (_     / (_) (_     /   )               #
# # | | ____ | |(_)| ||  ___  |           (____   _)   (____   _)  _/   /                #
# # | | \_  )| |   | || (   ) | VTT            ) (          ) (   /   _/                 #
# # | (___) || )   ( || )   ( | Mapper         | |   _      | |  (   (__/\               #
# # (_______)|/     \||/     \| Client         (_)  (_)     (_)  \_______/               #
# #                                                                                      #
# ########################################################################################
#
# General utility, version comparison, grid coordinate labels, and USTAR archive functions.
# Ported from bin/gmautil.tcl, bin/ustar.tcl, and bin/letterlabel.tcl.

from __future__ import annotations

import base64
import gzip
import hashlib
import hmac
import io
import os
import platform
import re
import shutil
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, BinaryIO, Callable

PUBLIC_KEY_PEM = """\
-----BEGIN PUBLIC KEY-----
MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAljm0271r46IM1W3KsNko
Koq++ysns6Gnp5nZLGLqzuhV8ifF3uml12nfO3UPS6vEzD5j//j0iEmchQEeHzuy
jZUDyox4fM4lJ5oQBw2/UU3RBtoR3t/HlyULKvfJf46TRKehKcuTJYqC4FXn7CzS
77OXka2Z/0flwGN/iGFZoG3hH77bLhu5i61hSx4NkTPd0gWfVcNOUI8pbQHngV0x
dwsnoRkiKTnwyPolQn43eUKP/ErM3QmkUdztsRdGoMdC6ukLDXCXOBEVnu4VJCQ+
i/2iUa06anlVPcOy/HrUra/0+KUdXHn/zu9IaD9z6Ll5XRoujSGKVcEiPeZFiPd1
tgvsz1eZiN6wTKqxqU43LG7eNGO2ggaoLtF2ABOpC/91wtQ1/8px5qvenQIBJAqR
PJ7+Af7eyUcQ3neske8I/PfphutOXP0Zj5ypNXDiSxw2qJ3u8erXmRZ4Ph0c9c9m
6KL3+9KYYoQ4nQ/CiBwjf6GKMz3NEXQQF9IMtbAcKEp2lRtVNZ/AyFficx6W3GRk
Z0bSBVrgel+iZQjjKJ2osOoyhAQQp/P5RQQPupgmxkvndc/9gWYE6JX1YJUXCOqL
U64greY1BqGzvJuY4UzIy+1/+4ZPjhYzxBwkbrsW6dZNvsq8zQyK+KxLQiueGzKI
7dPxqfF/kEZTWVPJMOX07OUCAwEAAQ==
-----END PUBLIC KEY-----
"""

# ASN.1 DigestInfo prefixes for EMSA-PKCS1-v1_5 (RFC 8017)
_PKCS1_DIGEST_INFO: dict[str, bytes] = {
    "sha256": bytes.fromhex("3031300d060960864801650304020105000420"),
    "sha1": bytes.fromhex("3021300906052b0e03021a05000414"),
    "sha384": bytes.fromhex("3041300d060960864801650304020205000430"),
    "sha512": bytes.fromhex("3051300d060960864801650304020305000440"),
}


def _read_asn1_der_element(data: bytes, offset: int) -> tuple[int, bytes, int]:
    """Minimal ASN.1 DER element reader returning (tag, content_bytes, next_offset)."""
    if offset >= len(data):
        raise ValueError("Unexpected EOF in ASN.1 DER")
    tag = data[offset]
    offset += 1
    if offset >= len(data):
        raise ValueError("Unexpected EOF reading ASN.1 length")
    first_len = data[offset]
    offset += 1
    if first_len & 0x80:
        num_bytes = first_len & 0x7F
        if num_bytes == 0 or offset + num_bytes > len(data):
            raise ValueError("Invalid ASN.1 long-form length")
        length = int.from_bytes(data[offset : offset + num_bytes], "big")
        offset += num_bytes
    else:
        length = first_len
    if offset + length > len(data):
        raise ValueError("ASN.1 element extends past buffer")
    return tag, data[offset : offset + length], offset + length


def _parse_rsa_public_key_pem(pem: str) -> tuple[int, int, int]:
    """Extract (n, e, key_byte_length) from a SubjectPublicKeyInfo RSA PEM key."""
    lines = [
        line.strip()
        for line in pem.strip().splitlines()
        if line.strip() and not line.strip().startswith("-----")
    ]
    der = base64.b64decode("".join(lines))
    # SubjectPublicKeyInfo ::= SEQUENCE { algorithm AlgorithmIdentifier, subjectPublicKey BIT STRING }
    tag, spki_body, _ = _read_asn1_der_element(der, 0)
    if tag != 0x30:
        raise ValueError("Expected ASN.1 SEQUENCE for SubjectPublicKeyInfo")
    tag, _alg_id, next_off = _read_asn1_der_element(spki_body, 0)
    tag, bit_string, _ = _read_asn1_der_element(spki_body, next_off)
    if tag != 0x03 or len(bit_string) < 2:
        raise ValueError("Expected ASN.1 BIT STRING for subjectPublicKey")
    # Skip leading unused-bits byte (0x00)
    rsa_pubkey_der = bit_string[1:]
    tag, rsa_seq, _ = _read_asn1_der_element(rsa_pubkey_der, 0)
    if tag != 0x30:
        raise ValueError("Expected ASN.1 SEQUENCE for RSAPublicKey")
    tag_n, n_bytes, next_off = _read_asn1_der_element(rsa_seq, 0)
    tag_e, e_bytes, _ = _read_asn1_der_element(rsa_seq, next_off)
    if tag_n != 0x02 or tag_e != 0x02:
        raise ValueError("Expected ASN.1 INTEGERs for RSA (n, e)")
    n = int.from_bytes(n_bytes, "big")
    e = int.from_bytes(e_bytes, "big")
    key_len = (n.bit_length() + 7) // 8
    return n, e, key_len


def verify(data: bytes, signature: bytes, public_key_pem: str = PUBLIC_KEY_PEM) -> bool:
    """Verify RSA PKCS#1 v1.5 cryptographic signature over `data`.

    Matches `::gmautil::verify` in `bin/gmautil.tcl`.
    """
    try:
        n, e, k = _parse_rsa_public_key_pem(public_key_pem)
        if len(signature) != k:
            return False
        s = int.from_bytes(signature, "big")
        if s <= 0 or s >= n:
            return False
        m = pow(s, e, n)
        em = m.to_bytes(k, "big")
        for hash_name, digest_info_prefix in _PKCS1_DIGEST_INFO.items():
            digest = hashlib.new(hash_name, data).digest()
            t = digest_info_prefix + digest
            if k < len(t) + 11:
                continue
            ps = b"\xff" * (k - len(t) - 3)
            expected_em = b"\x00\x01" + ps + b"\x00" + t
            if hmac.compare_digest(em, expected_em):
                return True
        return False
    except Exception:
        return False


def is_git(path: str | os.PathLike[str]) -> bool:
    """Return True if `path` is a directory inside a Git working tree.

    Matches `::gmautil::is_git` in `bin/gmautil.tcl`.
    """
    p = Path(path)
    if not p.is_dir():
        return False
    try:
        res = subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            cwd=str(p),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        return res.returncode == 0
    except OSError:
        return False


_SEMVER_RE = re.compile(r"^([^+-]+)([^-]+)?(?:-(.+))?$")


def _vc_part_cmp(a: str, b: str) -> int:
    """Compare two dot-separated version tokens using Tcl's numeric-else-string comparison."""
    try:
        na = int(a)
        nb = int(b)
        if na != nb:
            return -1 if na < nb else 1
        return 0
    except ValueError:
        if a != b:
            return -1 if a < b else 1
        return 0


def _vc(v1: str, v2: str) -> int:
    """Compare two dot-separated version strings, padding the shorter with '0'."""
    l1 = v1.split(".")
    l2 = v2.split(".")
    while len(l2) != len(l1):
        if len(l2) < len(l1):
            l2.append("0")
        else:
            l1.append("0")
    for p1, p2 in zip(l1, l2):
        c = _vc_part_cmp(p1, p2)
        if c != 0:
            return c
    return 0


def version_compare(v1: str, v2: str) -> int:
    """Compare two SemVer version strings.

    Returns:
        -1 if v1 < v2
         0 if v1 == v2
        +1 if v1 > v2

    Matches `::gmautil::version_compare` in `bin/gmautil.tcl`.
    """
    if v1 == v2:
        return 0
    m1 = _SEMVER_RE.match(v1)
    if not m1:
        raise ValueError(f"version {v1} does not conform to semver standard")
    m2 = _SEMVER_RE.match(v2)
    if not m2:
        raise ValueError(f"version {v2} does not conform to semver standard")

    v1base, _v1build, v1pre = m1.group(1), m1.group(2) or "", m1.group(3) or ""
    v2base, _v2build, v2pre = m2.group(1), m2.group(2) or "", m2.group(3) or ""

    # Strip any trailing +build metadata if present after prerelease
    if "+" in v1pre:
        v1pre = v1pre.split("+", 1)[0]
    if "+" in v2pre:
        v2pre = v2pre.split("+", 1)[0]

    cmp_base = _vc(v1base, v2base)
    if cmp_base == 0:
        if not v1pre and not v2pre:
            return 0
        if not v1pre:
            return 1
        if not v2pre:
            return -1
        return _vc(v1pre, v2pre)
    return cmp_base


def letter_label(x: int) -> str:
    """Convert 0-based grid column index `x` to spreadsheet-style column label (A, B, ..., Z, AA, AB...).

    Matches `LetterLabel` in `bin/letterlabel.tcl` and `bin/mapper.tcl`.
    """
    if x < 0:
        return "-" + letter_label(-x - 1)
    alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    label = alphabet[x % 26]
    x //= 26
    while x > 0:
        x -= 1
        label = alphabet[x % 26] + label
        x //= 26
    return label


_LOCATOR_RE = re.compile(r"^([A-Z]+)([0-9]+)$")


def letter_label_to_grid_xy(label: str) -> tuple[int, int]:
    """Convert a map grid locator string (e.g., 'A0', 'AB12') to `(grid_x, grid_y)`.

    Matches `LetterLabelToGridXY` in `bin/letterlabel.tcl` and `bin/mapper.tcl`.
    """
    m = _LOCATOR_RE.match(label.upper())
    if not m:
        raise ValueError(f"{label} is not a valid map locator value")
    xlabel, ylabel = m.group(1), m.group(2)
    x = -1
    for ch in xlabel:
        x += 1
        x = x * 26 + (ord(ch) - 65)
    return (x, int(ylabel))


def my_os() -> str:
    """Return standardized OS name ('darwin', 'linux', 'freebsd', 'windows', etc.).

    Matches `::gmautil::my_os`.
    """
    sys_name = platform.system()
    if sys_name == "Darwin":
        return "darwin"
    if sys_name == "Linux":
        return "linux"
    if sys_name == "FreeBSD":
        return "freebsd"
    if sys_name == "Windows":
        return "windows"
    return sys_name.lower()


def my_arch() -> str:
    """Return standardized machine architecture ('amd64', 'arm64', etc.).

    Matches `::gmautil::my_arch`.
    """
    mach = platform.machine().lower()
    if mach in ("x86_64", "amd64"):
        return "amd64"
    return mach


def my_platform() -> list[str]:
    """Return `[os, osVersion, machine]` matching `::gmautil::my_platform`."""
    return [
        platform.system() or "-",
        platform.release() or "-",
        platform.machine() or "-",
    ]


def search_in_path(cmd: str) -> str:
    """Search for an executable command in the user's PATH.

    Matches `::gmautil::searchInPath`.
    """
    return shutil.which(cmd) or ""


def dassign(dictval: dict[str, Any], *keys: str | list[str] | tuple[str, ...]) -> list[Any]:
    """Extract nested or top-level keys from `dictval` (port of `::gmautil::dassign`)."""
    results: list[Any] = []
    for k in keys:
        path = k.split() if isinstance(k, str) else list(k)
        cur: Any = dictval
        for part in path:
            cur = cur[part]
        results.append(cur)
    return results


def dassigndef(
    dictval: dict[str, Any],
    *specs: tuple[str | list[str] | tuple[str, ...], Any],
) -> list[Any]:
    """Extract nested or top-level keys with defaults from `dictval` (port of `::gmautil::dassigndef`)."""
    results: list[Any] = []
    for k, default in specs:
        path = k.split() if isinstance(k, str) else list(k)
        cur: Any = dictval
        found = True
        for part in path:
            if isinstance(cur, dict) and part in cur:
                cur = cur[part]
            else:
                found = False
                break
        results.append(cur if found else default)
    return results


# ---------------------------------------------------------------------------
# USTAR archive reader (ported from bin/ustar.tcl)
# ---------------------------------------------------------------------------

_NULL_BLOCK = b"\x00" * 512


@dataclass
class UstarEntry:
    """Parsed USTAR header entry matching the 13-element list from `::ustar::_parse_header`."""

    size: int
    type: str
    name: str
    mode: int
    uid: int
    uname: str
    gid: int
    gname: str
    mtime: float
    lname: str
    major: int
    minor: int
    meta: dict[str, Any] = field(default_factory=dict)

    def to_list(self) -> list[Any]:
        """Return the 13-element list representation used by Tcl `::ustar`."""
        return [
            self.size,
            self.type,
            self.name,
            self.mode,
            self.uid,
            self.uname,
            self.gid,
            self.gname,
            self.mtime,
            self.lname,
            self.major,
            self.minor,
            self.meta,
        ]


def _ustar_getblock(stream: BinaryIO) -> bytes:
    block = stream.read(512)
    if len(block) != 512:
        raise EOFError(
            f"ustar._getblock: unexpected EOF / short read of {len(block)} while reading stream"
        )
    return block


def _ustar_string(block: bytes, start: int, length: int) -> str:
    data = block[start : start + length]
    nul = data.find(b"\x00")
    if nul >= 0:
        data = data[:nul]
    return data.decode("utf-8", errors="surrogateescape")


def _ustar_octal(block: bytes, start: int, length: int) -> int:
    s = _ustar_string(block, start, length).strip()
    if not s:
        return 0
    try:
        return int(s, 8)
    except ValueError:
        return 0


def _ustar_parse_header(stream: BinaryIO) -> UstarEntry | None:
    block = _ustar_getblock(stream)
    if block == _NULL_BLOCK:
        block2 = _ustar_getblock(stream)
        if block2 == _NULL_BLOCK:
            return None
        raise ValueError("ustar._parse_header: unexpected null header block encountered")

    name = _ustar_string(block, 0, 100)
    mode = _ustar_octal(block, 100, 8)
    uid = _ustar_octal(block, 108, 8)
    gid = _ustar_octal(block, 116, 8)
    size = _ustar_octal(block, 124, 12)
    mtime = float(_ustar_octal(block, 136, 12))
    chk = _ustar_octal(block, 148, 8)
    ftype = _ustar_string(block, 156, 1)
    lname = _ustar_string(block, 157, 100)
    magic = _ustar_string(block, 257, 6)

    cblock = block[:148] + b"        " + block[156:]
    usum = sum(cblock)
    ssum = sum((b - 256 if b >= 128 else b) for b in cblock)
    if usum != chk and ssum != chk:
        raise ValueError(f"ustar._parse_header: bad checksum ({chk} in header; u={usum} s={ssum})")

    if magic == "ustar":
        uname = _ustar_string(block, 265, 32)
        gname = _ustar_string(block, 297, 32)
        major = _ustar_octal(block, 329, 8)
        minor = _ustar_octal(block, 337, 8)
        prefix = _ustar_string(block, 345, 155)
        if prefix:
            name = f"{prefix}/{name}"
    else:
        uname = ""
        gname = ""
        major = 0
        minor = 0

    if ftype == "g":
        raise ValueError("ustar._parse_header: global metadata records not supported.")

    if ftype == "x":
        # PAX extended header
        meta_blocks: list[bytes] = []
        rsize = size
        while rsize > 0:
            meta_blocks.append(_ustar_getblock(stream))
            rsize -= 512
        meta_raw = b"".join(meta_blocks)[:size].decode("utf-8", errors="replace")
        meta_values: dict[str, Any] = {}
        pos = 0
        rem = size
        while rem > 0 and pos < len(meta_raw):
            sp = meta_raw.find(" ", pos)
            if sp < 0:
                raise ValueError(f"ustar._parse_header: unable to interpret extended header {name}")
            this_length = int(meta_raw[pos:sp])
            record = meta_raw[sp + 1 : pos + this_length - 1]
            if meta_raw[pos + this_length - 1 : pos + this_length] != "\n":
                raise ValueError(
                    f"ustar._parse_header: extended header field {record} for {name} not newline-terminated"
                )
            eq = record.find("=")
            if eq < 0:
                raise ValueError(
                    f"ustar._parse_header: extended header field {record} for {name} has no equals sign"
                )
            key = record[:eq]
            val = record[eq + 1 :]
            if key in ("atime", "mtime", "ctime"):
                meta_values[key] = float(val)
            elif key in ("size", "uid", "gid"):
                meta_values[key] = int(val)
            elif key in ("linkpath", "path", "uname", "gname"):
                meta_values[key] = val
            rem -= this_length
            pos += this_length

        actual = _ustar_parse_header(stream)
        if actual is None:
            raise ValueError(
                "ustar._parse_header: unexpected end of archive after extended attribute header"
            )
        if "size" in meta_values:
            actual.size = meta_values["size"]
        if "path" in meta_values:
            actual.name = meta_values["path"]
        if "uid" in meta_values:
            actual.uid = meta_values["uid"]
        if "uname" in meta_values:
            actual.uname = meta_values["uname"]
        if "gid" in meta_values:
            actual.gid = meta_values["gid"]
        if "gname" in meta_values:
            actual.gname = meta_values["gname"]
        if "mtime" in meta_values:
            actual.mtime = meta_values["mtime"]
        if "linkpath" in meta_values:
            actual.lname = meta_values["linkpath"]
        actual.meta = meta_values
        return actual

    return UstarEntry(
        size=size,
        type=ftype,
        name=name,
        mode=mode,
        uid=uid,
        uname=uname,
        gid=gid,
        gname=gname,
        mtime=mtime,
        lname=lname,
        major=major,
        minor=minor,
    )


def ustar_contents(stream: BinaryIO) -> list[UstarEntry]:
    """Read a USTAR archive from `stream` and return a list of `UstarEntry` headers."""
    entries: list[UstarEntry] = []
    while True:
        hdr = _ustar_parse_header(stream)
        if hdr is None:
            break
        entries.append(hdr)
        skip_blocks = (hdr.size + 511) // 512
        for _ in range(skip_blocks):
            _ustar_getblock(stream)
    return entries


def ustar_file_contents(path: str | os.PathLike[str]) -> list[UstarEntry]:
    """Read a USTAR `.tar` archive from `path` and return its `UstarEntry` headers."""
    with open(path, "rb") as f:
        return ustar_contents(f)


def ustar_gzip_contents(path: str | os.PathLike[str]) -> list[UstarEntry]:
    """Read a gzip-compressed USTAR `.tar.gz` archive from `path` and return its headers."""
    with gzip.open(path, "rb") as f:
        return ustar_contents(f)  # type: ignore[arg-type]


def ustar_extract(
    stream: BinaryIO,
    callback: Callable[[UstarEntry, bytes], None],
) -> None:
    """Read a USTAR archive from `stream`, invoking `callback(header, data)` for each entry."""
    while True:
        hdr = _ustar_parse_header(stream)
        if hdr is None:
            break
        data_blocks = (hdr.size + 511) // 512
        chunks = [_ustar_getblock(stream) for _ in range(data_blocks)]
        data = b"".join(chunks)[: hdr.size]
        callback(hdr, data)


def ustar_file_extract(
    path: str | os.PathLike[str],
    callback: Callable[[UstarEntry, bytes], None],
) -> None:
    """Extract a `.tar` file via `callback(header, data)`."""
    with open(path, "rb") as f:
        ustar_extract(f, callback)


def ustar_gzip_extract(
    path: str | os.PathLike[str],
    callback: Callable[[UstarEntry, bytes], None],
) -> None:
    """Extract a `.tar.gz` file via `callback(header, data)`."""
    with gzip.open(path, "rb") as f:
        ustar_extract(f, callback)  # type: ignore[arg-type]


def ustar_format_contents(contents: list[UstarEntry]) -> str:
    """Format a list of `UstarEntry` headers into a human-readable table (`::ustar::format_contents`)."""
    type_map = {
        "0": "-",
        "": "-",
        "\x00": "-",
        "1": "L",
        "2": "l",
        "3": "c",
        "4": "b",
        "5": "d",
        "6": "f",
    }
    lines: list[str] = []
    for item in contents:
        tchar = type_map.get(item.type, "-")
        m = item.mode
        mode_str = (
            tchar
            + ("r" if m & 0o400 else "-")
            + ("w" if m & 0o200 else "-")
            + (("s" if m & 0o100 else "S") if m & 0o4000 else ("x" if m & 0o100 else "-"))
            + ("r" if m & 0o040 else "-")
            + ("w" if m & 0o020 else "-")
            + (("s" if m & 0o010 else "S") if m & 0o2000 else ("x" if m & 0o010 else "-"))
            + ("r" if m & 0o004 else "-")
            + ("w" if m & 0o002 else "-")
            + (("t" if m & 0o001 else "T") if m & 0o1000 else ("x" if m & 0o001 else "-"))
        )
        uname = item.uname or str(item.uid)
        gname = item.gname or str(item.gid)
        name = item.name
        if item.lname:
            name += f" -> {item.lname}"
        if tchar in ("b", "c"):
            name += f" <{item.major},{item.minor}>"
        mtime_str = time.ctime(int(item.mtime))
        lines.append(f"{mode_str} {uname} {gname} {item.size} {mtime_str} {name}")
    return "\n".join(lines) + ("\n" if lines else "")

