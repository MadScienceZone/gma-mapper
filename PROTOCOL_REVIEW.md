# GMA Mapper Protocol 428 Specification & Implementation Review

**Date**: November 2, 2026  
**Scope**: Comparison of `man/man7/gma-mapper-protocol.7` (Protocol Version 428), legacy `bin/gmaproto.tcl` (`v1.4.3`), and the Python 3.11+ / PySide6 implementation in `src/gma_mapper/net/protocol.py` and `src/gma_mapper/net/client.py`.

---

## 1. Executive Summary

A line-by-line audit was conducted comparing the authoritative protocol specification (`man/man7/gma-mapper-protocol.7`, version `428`) against both the legacy Tcl reference implementation (`bin/gmaproto.tcl`) and the new Python implementation (`src/gma_mapper/net/*`).

The audit covered:
1. **Protocol 428 Specification Conformance**: Message schemas, field types, zero-value suppression, enumeration tables, authentication digest computation, `BATCH` fragmentation, and session state-machine transitions.
2. **Upstream Tcl (`bin/gmaproto.tcl`) vs. Man Page Discrepancies**: Areas where `bin/gmaproto.tcl` diverged from `gma-mapper-protocol.7` (which may also be useful to backport to the Tcl codebase or clarify in the man page).
3. **Security, Stability, and Performance Hardening**: Improvements made in the Python network layer (`src/gma_mapper/net/*`).

---

## 2. Specification Conformance Matrix (`gma-mapper-protocol.7` vs. `src/gma_mapper/net/*`)

| Protocol Area | Commands Covered | Conformance Status |
| :--- | :--- | :--- |
| **Framing & Greeting** | `PROTOCOL`, `//`, `// notice:`, `OK`, `AUTH`, `GRANTED`, `DENIED`, `READY`, `REDIRECT`, `UPDATES`, `WORLD`, `Y2` | **Compliant** (with notes in Section 3 below) |
| **Keepalive & Sync** | `MARCO`, `POLO`, `ECHO`, `SYNC`, `SYNC-CHAT`, `ACCEPT`, `ALLOW`, `TB`, `/CONN`, `CONN` | **Compliant** (see `ECHO` & `MARCO` notes in Section 3) |
| **Batch Continuation** | `BATCH` (`ID`, `Command`, `Part`, `Of`, `Data`, `Error`, 60 KiB max line length `61440`) | **Compliant** |
| **Creatures & Tokens** | `AC`, `PS`, `OA`, `OA+`, `OA-`, `CLR`, `DSM` (including v428 `TargetedModifiers` `Limit` & `EndAtDeath`, `CustomReach`, `Health`, `SkinSize`) | **Compliant** |
| **Map Canvas Elements** | `L`, `CLR@`, `AV`, `MARK`, `LS-ARC`, `LS-CIRC`, `LS-LINE`, `LS-POLY`, `LS-RECT`, `LS-SAOE`, `LS-TEXT`, `LS-TILE` | **Compliant** |
| **Initiative, Clock & Timers** | `CO`, `CS`, `I`, `IL`, `PROGRESS`, `TMRQ`, `TMACK`, `HPREQ`, `HPACK`, `FAILED`, `PRIV` | **Compliant** (see `CS` type note in Section 3) |
| **Chat, Dice & Presets** | `TO`, `D`, `ROLL`, `CC`, `DD`, `DD+`, `DD/`, `DD=`, `DDD`, `DR`, `AKA` | **Compliant** |
| **Multimedia & Core SRD DB** | `AA`, `AA?`, `AA/`, `AI`, `AI?`, `AI/`, `SOUND`, `CORE`, `CORE=`, `CORE/`, `COREIDX`, `COREIDX=` | **See `AA/` & `AI/` note in Section 3** |

---

## 3. Specification vs. Implementation Discrepancies

The following discrepancies were identified when comparing `man/man7/gma-mapper-protocol.7` against `bin/gmaproto.tcl` and `src/gma_mapper/net/*`. Most originated in `bin/gmaproto.tcl` and were carried over during the initial port.

### 3.1. `Health` Schema Mismatch on `OA` Updates (Fixed in Python Port; Present in `bin/gmaproto.tcl`)
- **Specification (`gma-mapper-protocol.7` lines 4249–4317)**:
  - Defines `Health` with 14 fields: `MaxHP`, `TmpHP`, `TmpDamage`, `LethalDamage`, `NonLethalDamage`, `Con`, `IsFlatFooted`, `IsStable`, `Condition`, `HPBlur`, `AC`, `FlatFootedAC`, `TouchAC`, and `CMD`.
- **Legacy Tcl (`bin/gmaproto.tcl` lines 133, 189 vs. 205)**:
  - In `_message_payload`, `AC` and `PS` include all 14 `Health` fields, but the standalone `Health` entry at line 205 (used by `_attribute_encode` when encoding `OA` updates to `Health`) only lists 8 fields:
    ```tcl
    Health {MaxHP i LethalDamage i NonLethalDamage i Con i IsFlatFooted ? IsStable ? Condition s HPBlur i}
    ```
  - **Impact**: Sending a full `Health` dictionary via `OA` (`update_obj_attributes`) silently strips `TmpHP`, `TmpDamage`, `AC`, `FlatFootedAC`, `TouchAC`, and `CMD`.
  - **Status**: Fixed in `src/gma_mapper/net/protocol.py` (`MESSAGE_PAYLOAD["Health"] = dict(_HEALTH_PAYLOAD)`). Recommended for backport to `bin/gmaproto.tcl` line 205.

### 3.2. Missing `AA/` (`FilterAudio`) and `AI/` (`FilterImages`) in `_message_payload`
- **Specification (`gma-mapper-protocol.7` lines 496–515, 749–768)**:
  - Defines `AA/` and `AI/` with payload:
    ```json
    {"Filter": "<regex>", "KeepMatching": false}
    ```
- **Legacy Tcl (`bin/gmaproto.tcl` lines 132–208)**:
  - `AA/` and `AI/` are not listed in `_message_payload` or `_message_map`.
  - **Impact**: Attempting to encode or parse `AA/` or `AI/` raises `undefined protocol message`.
- **Status**: Fixed in `src/gma_mapper/net/protocol.py` (`MESSAGE_MAP` and `MESSAGE_PAYLOAD`) and `src/gma_mapper/net/client.py` (`filter_audio()`, `filter_images()`). Recommended for backport to `bin/gmaproto.tcl`.

### 3.3. Missing `b` (Boolean) Field in `ECHO` Payload Definition
- **Specification (`gma-mapper-protocol.7` lines 3205–3228)**:
  - Defines `ECHO` payload fields: `s` (string), `i` (int), `b` (bool), `o` (object), `ReceivedTime` (string), and `SentTime` (string).
- **Legacy Tcl (`bin/gmaproto.tcl` line 164)**:
  - Defines `ECHO` as `{s s i i o d ReceivedTime s SentTime s}`, omitting `b ?`.
- **Status**: Fixed in `src/gma_mapper/net/protocol.py` (`"ECHO": {"s": "s", "i": "i", "b": "?", "o": "d", "ReceivedTime": "s", "SentTime": "s"}`).

### 3.4. Missing `Global` Field in `DR` Payload in `bin/gmaproto.tcl`
- **Specification (`gma-mapper-protocol.7` lines 2968–2988)**:
  - Defines `DR` (`QueryDicePresets`) with `For` (`s`) and `Global` (`?`).
- **Legacy Tcl (`bin/gmaproto.tcl` line 162)**:
  - Defines `DR {For s}` (missing `Global ?`), even though `::gmaproto::query_dice_presets` sends `Global true` when `-global` is passed, which causes `_encode_payload_dict` in Tcl to silently drop `Global`!
- **Status**: Fixed in `src/gma_mapper/net/protocol.py` (`"DR": {"For": "s", "Global": "?"}`). Recommended for backport to `bin/gmaproto.tcl`.

### 3.5. `AUTH` Fallback Pass Count Endianness (`>H` vs. `<H`)
- **Specification (`gma-mapper-protocol.7` lines 949–956)**:
  - *"If no value for `i` was provided by the server, obtain `i` by extracting the first two bytes from `C` as an unsigned, big-endian, 16-bit integer value."*
  - `bin/gmaproto.tcl` line 2324 uses `binary scan $challenge S passes` (where uppercase `S` in Tcl `binary scan` is big-endian 16-bit).
- **Status**: Fixed in `src/gma_mapper/net/protocol.py` (`struct.unpack(">H", challenge[:2])[0] & 0xFFFF`).

### 3.6. Mid-Session `DENIED` (Protocol `>= 414`), `REDIRECT`, and Login-Phase `MARCO`
- **Specification**:
  - **`DENIED` (`gma-mapper-protocol.7` lines 150–157, 2951–2966)**: Starting in protocol 414, servers may send `DENIED` *after* `READY` to terminate the client's session immediately, and the client *"MUST not continue to communicate with the server."*
  - **`REDIRECT` (`gma-mapper-protocol.7` lines 4606–4614)**: *"The server SHOULD send this during the initial stage of client interaction... but MAY be sent at any point. The client SHOULD disconnect immediately upon receiving this command."*
  - **`MARCO` (`gma-mapper-protocol.7` lines 3938–3955)**: *"Status check. If received, reply with a `POLO` command... It is important that your client not ignore these occasional ping messages."*
- **Status**: Fixed in `src/gma_mapper/net/client.py`:
  - `MARCO` during login now replies with `POLO` instead of being ignored.
  - `DENIED` and `REDIRECT` are now handled both before and after `READY` (`_handle_login_packet` and `_dispatch_packet`).

### 3.7. `CS` (`UpdateClock`) `Absolute` and `Relative` Field Types
- **Specification (`gma-mapper-protocol.7` lines 2414–2420)**:
  - Specifies `Absolute (int64)` and `Relative (int64)` (in tenths of seconds).
- **Legacy Tcl (`bin/gmaproto.tcl` line 154)**:
  - Defines `CS {Absolute f Relative f Running ?}` as float (`f`) rather than integer (`i`).
- **Status**: Fixed in `src/gma_mapper/net/protocol.py` (`"CS": {"Absolute": "i", "Relative": "i", "Running": "?"}`) and `src/gma_mapper/net/client.py` (`update_clock()`).

---

## 4. Minor Documentation Errata Noted in `man/man7/gma-mapper-protocol.7`

While auditing `man/man7/gma-mapper-protocol.7`, a few minor typographical issues were spotted in the man page itself:
1. **Line 3357 (`HPREQ` section)**: `.BI Healh " (object)"` — missing `"t"` in `Health`.
2. **Line 3407 (`HPREQ` section)**: References `.B TMREQ` instead of `.B TMRQ`.
3. **Lines 1104–1113 (Commented `BATCH` example)**: Uses `"Batch"` and `"Total"` field names instead of `"Part"` and `"Of"`.
4. **Line 1675 (`CORE=` `bestiary` section)**: `.B AgeCagetory` — typo for `AgeCategory`.
5. **Line 816 (`ALLOW` section)**: *"Currently, the following one features are recognized:"* followed by three features (`DICE-COLOR-BOXES`, `DICE-COLOR-LABELS`, `GMA-MARKUP`).

---

## 5. Security, Stability, and Performance Improvements Applied in `src/gma_mapper/net/*`

In addition to the protocol comparison above, the Python networking stack in `src/gma_mapper/net/protocol.py` and `src/gma_mapper/net/client.py` was hardened against several security, stability, and performance issues:

1. **Multi-Byte UTF-8 Safety in `BATCH` Splitting & Reassembly**:
   - `encode_with_batching()` now slices raw UTF-8 `bytes` rather than Python `str` code points, and `BatchCollector.process_batch()` concatenates raw decoded `bytes` across all parts `0..Of-1` before decoding UTF-8 once. Previously, a multi-byte UTF-8 character split across a `BATCH` boundary raised `UnicodeDecodeError` when each chunk was decoded individually.
2. **Bounded TCP Line Buffer & $O(N)$ Line Framing**:
   - Replaced repeated `bytes.split(b"\n", 1)` buffer slicing ($O(N^2)$ during large `SYNC` bursts) with a `bytearray` and single-pass `split(b"\n")`, capped at `MAX_LINE_BUFFER_BYTES = 4 MiB` to prevent memory exhaustion if a peer streams data without newlines.
3. **Bounded `BatchCollector` Storage**:
   - Added `MAX_BATCH_PARTS = 2048` and `MAX_CONCURRENT_BATCHES = 64` (evicting the oldest incomplete batch group) so malformed or abandoned `BATCH` streams cannot leak memory.
4. **Authentication Iteration Cap**:
   - Added `MAX_AUTH_ITERATIONS = 1_000_000` in `auth_response()` so an excessive `OK.Iterations` value cannot lock up the client CPU thread.
5. **Protocol Line Newline Sanitization**:
   - `_raw_send()` strips embedded `\r` and `\n` characters so user-supplied strings (e.g., in `//` comments) cannot inject extra newline-delimited protocol commands onto the wire.
6. **Redirect Validation & Loop Protection**:
   - Validated `REDIRECT` `Host` and `Port` (`1..65535`) and capped consecutive redirects at `MAX_REDIRECTS = 5`.
7. **Suppression of Auto-Redial on `DENIED` / Auth Failure**:
   - When login fails with `PermissionError` (`DENIED` or missing password), `GMANetworkClient` now suppresses its auto-redial timer rather than re-hammering the server in a loop.
8. **Strict Finite JSON Floats**:
   - `_construct()` and `_encode_payload()` now reject `NaN` and `Infinity` (`allow_nan=False`, `math.isfinite`) so non-standard JSON tokens are never emitted or accepted as coordinates.

