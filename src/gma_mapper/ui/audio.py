"""Audio manager for GMA Mapper turn-notification cues (`ondeck0.wav` - `ondeck2.wav`) and protocol stubs."""

from __future__ import annotations

from pathlib import Path
from typing import Any

try:
    from PySide6.QtCore import QUrl
    from PySide6.QtMultimedia import QSoundEffect
    HAS_QT_AUDIO = True
except ImportError:
    HAS_QT_AUDIO = False


def default_sounds_dir() -> Path:
    """Locate the repository or packaged ``sounds`` directory (`ondeck0.wav` - `ondeck2.wav`)."""
    repo_root = Path(__file__).resolve().parents[3]
    for candidate in (
        repo_root / "lib" / "MadScienceZone" / "GMA" / "Mapper" / "sounds",
        repo_root / "lib" / "sounds",
        Path.cwd() / "lib" / "MadScienceZone" / "GMA" / "Mapper" / "sounds",
        Path.cwd() / "lib" / "sounds",
    ):
        if candidate.is_dir():
            return candidate
    return repo_root / "lib" / "MadScienceZone" / "GMA" / "Mapper" / "sounds"


class AudioManager:
    """Manages local ``ondeck0.wav`` - ``ondeck2.wav`` cues and ``AA``/``AA?``/``SOUND`` stubs."""

    def __init__(
        self,
        sounds_dir: str | Path | None = None,
        enabled: bool = True,
        mute_level: int = 0,
    ) -> None:
        self.sounds_dir = Path(sounds_dir) if sounds_dir else default_sounds_dir()
        self.enabled = bool(enabled)
        self.mute_level = int(mute_level)
        self.audio_catalog: dict[str, dict[str, Any]] = {}
        self._effects: dict[int, Any] = {}
        self.last_played_cue: int | None = None

    def cue_path(self, level: int) -> Path:
        """Return the filesystem path for ``ondeck{level}.wav`` (0, 1, or 2)."""
        clamped = max(0, min(2, int(level)))
        return self.sounds_dir / f"ondeck{clamped}.wav"

    def play_ondeck(self, level: int = 0) -> bool:
        """Play turn-notification sound ``ondeck{level}.wav`` if enabled and not muted.

        Returns ``True`` if playback was triggered (or simulated in headless tests).
        """
        clamped = max(0, min(2, int(level)))
        if not self.enabled or self.mute_level > clamped:
            return False

        wav_path = self.cue_path(clamped)
        if not wav_path.is_file():
            return False

        self.last_played_cue = clamped
        if HAS_QT_AUDIO:
            effect = self._effects.get(clamped)
            if effect is None:
                effect = QSoundEffect()
                effect.setSource(QUrl.fromLocalFile(str(wav_path)))
                self._effects[clamped] = effect
            effect.play()
        return True

    # Protocol stubs for AA / AA? / SOUND
    def register_audio_asset(self, payload: dict[str, Any]) -> None:
        """Protocol stub for ``AA`` (Add Audio)."""
        name = str(payload.get("Name", ""))
        if name:
            self.audio_catalog[name] = dict(payload)

    def handle_play_sound(self, payload: dict[str, Any]) -> None:
        """Protocol stub for ``SOUND`` command."""
        pass
