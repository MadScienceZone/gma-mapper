"""Animated tile/token frame controller and MARK ping / placement animations.

Ported from bin/mapper.tcl.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable


@dataclass
class AnimatedTileRecord:
    """Metadata and frame state for an animated tile or creature token."""

    tile_id: str
    frames: int
    frame_speed_ms: int
    loops: int
    current_frame: int = 0
    current_loop: int = 0
    running: bool = False
    frame_pixmaps: dict[int, Any] = field(default_factory=dict)

    def advance_frame(self) -> bool:
        """Advance to the next frame; return True if still running, False if loop limit reached."""
        if self.frames <= 1:
            self.running = False
            return False
        next_f = self.current_frame + 1
        if next_f >= self.frames:
            next_f = 0
            self.current_loop += 1
            if self.loops > 0 and self.current_loop >= self.loops:
                self.running = False
                return False
        self.current_frame = next_f
        return True


class AnimationRegistry:
    """Manages all registered animated images (`TILE_ANIMATION`)."""

    def __init__(self, on_frame_changed: Callable[[str, int], None] | None = None) -> None:
        self.animations: dict[str, AnimatedTileRecord] = {}
        self.on_frame_changed = on_frame_changed
        self.never_animate: bool = False

    def init_animation(
        self, tile_id: str, frames: int, speed_ms: int, loops: int = 0
    ) -> AnimatedTileRecord:
        rec = AnimatedTileRecord(
            tile_id=tile_id,
            frames=int(frames),
            frame_speed_ms=max(20, int(speed_ms or 100)),
            loops=int(loops),
        )
        self.animations[tile_id] = rec
        return rec

    def add_frame(self, tile_id: str, frameno: int, pixmap: Any) -> None:
        if tile_id in self.animations:
            self.animations[tile_id].frame_pixmaps[int(frameno)] = pixmap

    def current_pixmap(self, tile_id: str) -> Any | None:
        rec = self.animations.get(tile_id)
        if not rec:
            return None
        return rec.frame_pixmaps.get(rec.current_frame) or rec.frame_pixmaps.get(0)

    def step_tile(self, tile_id: str) -> bool:
        if self.never_animate:
            return False
        rec = self.animations.get(tile_id)
        if not rec or not rec.running:
            return False
        still_running = rec.advance_frame()
        if self.on_frame_changed:
            self.on_frame_changed(tile_id, rec.current_frame)
        return still_running

