"""Pure-Python core modules for GMA Mapper (no Qt GUI dependency required)."""

from gma_mapper.core.cache import AssetCache, cache_map_id, normalize_zoom, tile_id
from gma_mapper.core.colors import (
    color_to_hex,
    contrasting_color,
    darken_color,
    parse_color_rgb,
    rgb_name,
)
from gma_mapper.core.file_io import (
    load_dice_presets_from_file,
    load_from_file,
    save_dice_presets_to_file,
    save_to_file,
)
from gma_mapper.core.minimarkup import (
    render as render_minimarkup,
    render_html as render_minimarkup_html,
    strip as strip_minimarkup,
)
from gma_mapper.core.profile import (
    default_preferences,
    fix_missing,
    load as load_preferences,
    save as save_preferences,
)
from gma_mapper.core.zones import (
    CreatureAreaInfo,
    SizeParams,
    creature_size_params,
    full_creature_area_info,
    monster_size_value,
    reach_matrix,
)

__all__ = [
    "AssetCache",
    "CreatureAreaInfo",
    "SizeParams",
    "cache_map_id",
    "color_to_hex",
    "contrasting_color",
    "creature_size_params",
    "darken_color",
    "default_preferences",
    "fix_missing",
    "full_creature_area_info",
    "load_dice_presets_from_file",
    "load_from_file",
    "load_preferences",
    "monster_size_value",
    "normalize_zoom",
    "parse_color_rgb",
    "reach_matrix",
    "render_minimarkup",
    "render_minimarkup_html",
    "rgb_name",
    "save_dice_presets_to_file",
    "save_preferences",
    "save_to_file",
    "strip_minimarkup",
    "tile_id",
]
