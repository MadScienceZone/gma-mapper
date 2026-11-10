"""Unit tests for gma_mapper.ui.canvas pure-Python helpers."""

import unittest

from gma_mapper.ui.canvas.animation import AnimationRegistry
from gma_mapper.ui.canvas.aoe import (
    aoe_grid_hatch_lines,
    compute_aoe_grids,
    compute_creature_aoe_grids,
    cycle_aoe_shape,
    find_creatures_in_aoe_grids,
    grid_intersection_distance,
)
from gma_mapper.ui.canvas.context_menu import (
    allowed_to_polymorph,
    apply_custom_reach_change,
    apply_polymorph,
    apply_size_change,
    build_spawned_creatures,
    build_token_tooltip,
    compute_elevation_change,
    toggle_status_condition,
)
from gma_mapper.ui.canvas.drawing import (
    compute_nudge_z,
    cycle_arc_mode,
    cycle_arrow_style,
    cycle_dash_style,
    cycle_join_style,
    cycle_spline_level,
    cycle_text_anchor,
    describe_element,
    snap_coord,
    snap_point,
    translate_element_coords,
)
from gma_mapper.ui.canvas.items import (
    creature_image_candidates,
    creature_status_conditions,
    creature_status_transparent,
    resolve_condition_markers,
)
from gma_mapper.ui.canvas.scene import (
    BattleMapScene,
    grid_coord_label,
    grid_distance_feet,
    grid_to_scene_xy,
    ping_marker_radius,
    scene_to_grid_xy,
    snap_creature_grid_xy,
    visible_objects_bounds,
)


class TestCanvasHelpers(unittest.TestCase):
    def test_condition_markers_and_transparency(self) -> None:
        creature = {
            "ID": "c1",
            "Name": "Wizard",
            "Color": "blue",
            "Hidden": False,
            "Health": {"Condition": "dying", "IsFlatFooted": True, "IsStable": False},
            "StatusList": ["invisible", "bleed"],
        }
        conds = creature_status_conditions(creature)
        self.assertEqual(conds, ["dying", "flat-footed", "invisible", "bleed"])
        self.assertTrue(creature_status_transparent(creature))

        markers = resolve_condition_markers(creature)
        self.assertEqual(len(markers), 4)
        # dying uses '*' which resolves to creature's Color ('blue' -> '#0000ff')
        self.assertEqual(markers[0], ("/", "#0000ff", ""))
        # invisible uses '..black' -> shape 'O', color '#000000', dash '.'
        self.assertEqual(markers[2], ("O", "#000000", "."))

    def test_animation_registry(self) -> None:
        reg = AnimationRegistry()
        rec = reg.init_animation("fire:1.00", frames=3, speed_ms=50, loops=2)
        rec.running = True
        reg.add_frame("fire:1.00", 0, "F0")
        reg.add_frame("fire:1.00", 1, "F1")
        reg.add_frame("fire:1.00", 2, "F2")
        self.assertEqual(reg.current_pixmap("fire:1.00"), "F0")
        self.assertTrue(reg.step_tile("fire:1.00"))
        self.assertEqual(reg.current_pixmap("fire:1.00"), "F1")
        self.assertTrue(reg.step_tile("fire:1.00"))
        self.assertEqual(reg.current_pixmap("fire:1.00"), "F2")
        # End of loop 1 -> wraps to frame 0
        self.assertTrue(reg.step_tile("fire:1.00"))
        self.assertEqual(reg.current_pixmap("fire:1.00"), "F0")

    def test_grid_coords_and_ruler_distance(self) -> None:
        sx, sy = grid_to_scene_xy(2.0, 3.0)
        self.assertEqual((sx, sy), (100.0, 150.0))
        self.assertEqual(scene_to_grid_xy(100.0, 150.0), (2.0, 3.0))
        self.assertEqual(grid_coord_label(0.2, 0.2), "A1")
        self.assertEqual(grid_coord_label(2.0, 4.0), "C5")

        # 3 squares right, 4 squares down:
        # diag = 3 squares (floor(3*1.5) = 4 squares = 20 ft) + 1 straight (5 ft) = 25 ft PF, 25.0 ft Euclidean
        pf_ft, euc_ft, _ = grid_distance_feet(0.0, 0.0, 150.0, 200.0)
        self.assertEqual(pf_ft, 25.0)
        self.assertAlmostEqual(euc_ft, 25.0)

    def test_context_menu_elevation_and_conditions(self) -> None:
        self.assertEqual(compute_elevation_change(10, "+15"), 25)
        self.assertEqual(compute_elevation_change(25, "-10"), 15)
        self.assertEqual(compute_elevation_change(25, "0"), 0)

        mob = {"ID": "m1", "Name": "Goblin", "StatusList": ["prone"], "Hidden": False}
        diff1 = toggle_status_condition(mob, "shaken")
        self.assertEqual(diff1, {"StatusList": ["prone", "shaken"]})
        diff2 = toggle_status_condition(mob, "prone")
        self.assertEqual(diff2, {"StatusList": ["shaken"]})
        diff3 = toggle_status_condition(mob, "__hide__")
        self.assertEqual(diff3, {"Hidden": True})
        diff4 = toggle_status_condition(mob, "__clear__")
        self.assertEqual(diff4, {"StatusList": []})

    def test_context_menu_reach_size_and_polymorph(self) -> None:
        mob = {"ID": "m2", "Name": "Druid", "Size": "M", "DispSize": "M", "SkinSize": ["M*#human", "L#bear"], "Skin": 0}
        self.assertTrue(allowed_to_polymorph(mob))
        poly_diff = apply_polymorph(mob, 1)
        self.assertEqual(poly_diff["Skin"], 1)
        self.assertEqual(poly_diff["DispSize"], "L#bear")

        r1 = apply_custom_reach_change(mob, "-setnat", 15)
        self.assertTrue(r1["CustomReach"]["Enabled"])
        self.assertEqual(r1["CustomReach"]["Natural"], 15)
        self.assertGreaterEqual(r1["CustomReach"]["Extended"], 15)

        r2 = apply_custom_reach_change(mob, "-incrnat", 1)
        self.assertEqual(r2["CustomReach"]["Natural"], 20)

        sz_diff = apply_size_change(mob, "H")
        self.assertEqual(sz_diff["DispSize"], "H")

    def test_spawn_creatures_and_tooltip(self) -> None:
        batch = build_spawned_creatures(2.0, 3.0, "Goblin #1-4", sizes_str="S", color="red", creature_type="monster")
        self.assertEqual(len(batch), 4)
        self.assertEqual([b["Name"] for b in batch], ["Goblin #1", "Goblin #2", "Goblin #3", "Goblin #4"])
        self.assertEqual([b["Gx"] for b in batch], [2.0, 3.0, 4.0, 5.0])
        self.assertEqual(batch[0]["Size"], "S")

        tip = build_token_tooltip({
            "Name": "Valeros",
            "DispSize": "M",
            "Elev": 15,
            "MoveMode": 3,
            "Note": "Hasted",
            "StatusList": ["shaken"],
            "Health": {"MaxHP": 45, "LethalDamage": 10, "NonLethalDamage": 0, "TmpHP": 5},
            "Targets": ["Goblin #1"],
        })
        self.assertIn("Valeros (Size: M)", tip)
        self.assertIn("Elevation: +15 ft", tip)
        self.assertIn("Movement: Fly", tip)
        self.assertIn("Tag: Hasted", tip)
        self.assertIn("HP: 35/45 (+5 tmp)", tip)
        self.assertIn("Currently targeting: Goblin #1", tip)

        cands_alive = creature_image_candidates({"Name": "Goblin #2", "Skin": 0, "Killed": False})
        self.assertEqual(cands_alive[:2], ["#Goblin", "^0^Goblin"])
        cands_skin1 = creature_image_candidates({"Name": "Druid", "Skin": 1, "Killed": False})
        self.assertEqual(cands_skin1[:2], ["=Druid", "^1^Druid"])
        cands_killed = creature_image_candidates({"Name": "Goblin #2", "Skin": 0, "Killed": True})
        self.assertEqual(cands_killed[:2], ["%Goblin", "%#Goblin"])

    def test_populate_qmenu_if_pyside6_present(self) -> None:
        try:
            from PySide6.QtCore import QPointF
            from PySide6.QtWidgets import QApplication, QMenu
            from gma_mapper.ui.canvas.context_menu import populate_canvas_context_menu
            from gma_mapper.ui.canvas.scene import BattleMapScene
            from gma_mapper.ui.canvas.view import BattleMapView
        except ImportError:
            return

        _app = QApplication.instance() or QApplication([])
        scene = BattleMapScene()
        view = BattleMapView(scene)
        self.assertEqual(scene.sceneRect().left(), 0.0)
        self.assertEqual(scene.sceneRect().top(), 0.0)
        self.assertEqual(view.top_left_grid_label(), "A1")
        scene.place_someone({
            "ID": "p1",
            "Name": "Valeros",
            "Gx": 2.0,
            "Gy": 3.0,
            "Size": "M",
            "DispSize": "M",
            "SkinSize": ["M*#human", "L#enlarged"],
            "Skin": 0,
            "Color": "green",
            "CreatureType": 2,
        })
        pt = QPointF(125.0, 175.0)
        mobs = scene.mobs_at_scene_pos(pt)
        self.assertEqual(mobs, ["p1"])

        menu = QMenu()
        mutated: list[tuple[str, dict]] = []
        populate_canvas_context_menu(
            menu=menu,
            scene=scene,
            view=view,
            scene_pt=pt,
            on_mutate_mob=lambda mid, attrs: mutated.append((mid, attrs)),
            on_remove_mob=lambda _mid: None,
            on_spawn_mob=lambda _d: None,
            pc_templates={"p1": {"ID": "p1", "Name": "Valeros"}},
        )
        action_texts = [a.text() for a in menu.actions() if not a.isSeparator()]
        self.assertTrue(any("Toggle Condition for Valeros" in t for t in action_texts))
        self.assertTrue(any("Set Elevation for Valeros" in t for t in action_texts))
        self.assertTrue(any("Polymorph Valeros" in t for t in action_texts))
        self.assertTrue(any("Add Monster..." in t for t in action_texts))
        self.assertTrue(any("Distance from C4" in t for t in action_texts))

    def test_drawing_snap_style_cyclers_and_nudge(self) -> None:
        # snap_coord with grid_scale=50.0
        self.assertEqual(snap_coord(23.0, 0), 23.0)
        self.assertEqual(snap_coord(23.0, 1), 0.0)
        self.assertEqual(snap_coord(26.0, 1), 50.0)
        self.assertEqual(snap_coord(13.0, 2), 25.0)
        self.assertEqual(snap_point(26.0, 13.0, 2), (25.0, 25.0))

        self.assertEqual(cycle_arrow_style("none"), "first")
        self.assertEqual(cycle_arrow_style("both"), "none")
        self.assertEqual(cycle_dash_style(""), "-")
        self.assertEqual(cycle_join_style("bevel"), "miter")
        self.assertEqual(cycle_arc_mode("pieslice"), "chord")
        self.assertEqual(cycle_text_anchor("center"), "w")
        self.assertEqual(cycle_spline_level(0), 1)
        self.assertEqual(cycle_spline_level(9), 0)

        elem = {"ID": "e1", "X": 100.0, "Y": 200.0, "Points": [{"X": 150.0, "Y": 250.0}]}
        diff = translate_element_coords(elem, -10.0, 25.0)
        self.assertEqual(diff["X"], 90.0)
        self.assertEqual(diff["Y"], 225.0)
        self.assertEqual(diff["Points"], [{"X": 140.0, "Y": 275.0}])

        elems = {
            "e1": {"ID": "e1", "Z": 10},
            "e2": {"ID": "e2", "Z": 20},
        }
        self.assertEqual(compute_nudge_z(elems, "e1", "up"), 11)
        self.assertEqual(compute_nudge_z(elems, "e1", "front"), 21)
        self.assertIsNone(compute_nudge_z(elems, "e1", "front"))
        self.assertEqual(compute_nudge_z(elems, "e1", "back"), 19)

        desc = describe_element("LS-RECT", {"X": 50, "Y": 100, "Z": 10, "Line": "black", "Fill": "red", "Width": 2, "Layer": "walls"})
        self.assertEqual(desc, "rect (black/red) @(50,100,10); w=2; [walls]")

    def test_creature_grid_snap_and_visible_bounds(self) -> None:
        # Medium creature with "nil" (by creature size) snaps to full squares
        self.assertEqual(
            snap_creature_grid_xy(135.0, 185.0, {"Size": "M"}, "nil"),
            (2.0, 3.0),
        )
        # Tiny creature (size 0.5 < 1.0) with "nil" snaps to half squares
        self.assertEqual(
            snap_creature_grid_xy(135.0, 185.0, {"Size": "T"}, "nil"),
            (2.5, 3.5),
        )
        # Explicit quarter-square snap ("0.25")
        self.assertEqual(
            snap_creature_grid_xy(115.0, 165.0, {"Size": "M"}, "0.25"),
            (2.25, 3.25),
        )

        # visible_objects_bounds
        self.assertIsNone(visible_objects_bounds([], []))
        bounds = visible_objects_bounds(
            [{"X": 100.0, "Y": 200.0, "Points": [{"X": 300.0, "Y": 400.0}]}],
            [{"Gx": 2.0, "Gy": 4.0, "Size": "M", "Hidden": False}],
        )
        self.assertEqual(bounds, (100.0, 200.0, 300.0, 400.0))

    def test_spell_aoe_shapes_spread_and_targets(self) -> None:
        self.assertEqual(cycle_aoe_shape("radius"), "cone")
        self.assertEqual(cycle_aoe_shape("cone"), "ray")
        self.assertEqual(cycle_aoe_shape("ray"), "radius")
        self.assertEqual(grid_intersection_distance(0, 0, 3, 4), 5)

        # 5-ft (1-square) radius around intersection (4, 4) -> 4 squares: (3,3), (4,3), (3,4), (4,4)
        r1 = compute_aoe_grids(4, 4, 5, 4, shape="radius")
        self.assertEqual(set(r1), {(3, 3), (4, 3), (3, 4), (4, 4)})

        # 20-ft (4-square) fireball radius around intersection (10, 10) -> 44 squares in d20 template
        r4 = compute_aoe_grids(10, 10, 14, 10, shape="radius")
        self.assertEqual(len(r4), 44)

        # Ray from (2, 2) to (6, 2)
        ray_grids = compute_aoe_grids(2, 2, 6, 2, shape="ray")
        self.assertTrue(len(ray_grids) >= 4)

        # Cone from (5, 5) to (8, 5) (3-square / 15-ft cone east)
        cone_grids = compute_aoe_grids(5, 5, 8, 5, shape="cone")
        self.assertTrue(len(cone_grids) > 0)
        self.assertTrue(all(gx >= 5 for gx, _ in cone_grids))

        # Spread blocked by vertical wall along x = 250.0 (gx = 5)
        unblocked_spread = compute_aoe_grids(4, 4, 6, 4, shape="radius", spread=True)
        wall = [(250.0, 0.0, 250.0, 500.0)]
        blocked_spread = compute_aoe_grids(
            4, 4, 6, 4, shape="radius", spread=True, barrier_segments=wall, grid_scale=50.0
        )
        self.assertTrue(any(gx >= 5 for gx, _ in unblocked_spread))
        self.assertTrue(all(gx < 5 for gx, _ in blocked_spread))

        # Creature perimeter emanation (1-square radius around Medium creature at (4, 4) -> 9 squares (3x3))
        mob = {"ID": "m1", "Name": "Cleric", "Gx": 4.0, "Gy": 4.0, "Size": "M", "DispSize": "M"}
        emanation = compute_creature_aoe_grids(mob, 1)
        self.assertEqual(len(emanation), 9)
        self.assertIn((4, 4), emanation)
        self.assertIn((3, 3), emanation)
        self.assertIn((5, 5), emanation)

        # Target detection inside AoE grids
        creatures = {
            "m1": mob,
            "m2": {"ID": "m2", "Name": "Goblin #1", "Gx": 3.0, "Gy": 3.0, "Size": "S", "Hidden": False},
            "m3": {"ID": "m3", "Name": "Orc #1", "Gx": 9.0, "Gy": 9.0, "Size": "M", "Hidden": False},
        }
        hits = find_creatures_in_aoe_grids(r1, creatures)
        self.assertEqual(hits, ["Cleric", "Goblin #1"])

        # Hatch lines per square: 7 diagonal segments
        self.assertEqual(len(aoe_grid_hatch_lines(2, 3, local_aura=False)), 7)
        self.assertEqual(len(aoe_grid_hatch_lines(2, 3, local_aura=True)), 7)

    def test_ping_marker_and_shift_left_click(self) -> None:
        # 15 steps (0..14): 3 cycles of [40, 30, 20, 10, 0]
        expected_radii = [40.0, 30.0, 20.0, 10.0, 0.0] * 3
        self.assertEqual([ping_marker_radius(s) for s in range(15)], expected_radii)
        self.assertIsNone(ping_marker_radius(-1))
        self.assertIsNone(ping_marker_radius(15))

        try:
            from PySide6.QtCore import QEvent, QPointF, Qt
            from PySide6.QtGui import QMouseEvent
            from PySide6.QtWidgets import QApplication
            from gma_mapper.ui.canvas.view import BattleMapView

            app = QApplication.instance() or QApplication([])
            _ = app
            scene = BattleMapScene()
            view = BattleMapView(scene)
            emitted_marks: list[tuple[float, float]] = []
            view.mark_requested.connect(lambda sx, sy: emitted_marks.append((sx, sy)))

            # Simulate Shift+LeftMouse press at viewport point (120, 160)
            ev = QMouseEvent(
                QEvent.Type.MouseButtonPress,
                QPointF(120.0, 160.0),
                QPointF(120.0, 160.0),
                Qt.MouseButton.LeftButton,
                Qt.MouseButton.LeftButton,
                Qt.KeyboardModifier.ShiftModifier,
            )
            view.mousePressEvent(ev)
            self.assertEqual(len(emitted_marks), 1)
            self.assertEqual(len(scene.marks), 1)
            self.assertEqual(emitted_marks[0], scene.marks[0])
            self.assertEqual(len(scene._active_pings[scene.marks[0]]), 2)

            # Place a creature at (2, 2) -> scene [100, 150) x [100, 150) with reach/AoE margin
            scene.add_or_update_token(
                "p1",
                {
                    "ID": "p1",
                    "Name": "Valeros",
                    "Gx": 2.0,
                    "Gy": 2.0,
                    "Size": "M",
                    "CreatureType": 2,
                    "AoE": {"Radius": 4.0, "Color": "cyan"},
                },
            )
            dragged: list[tuple[str, float, float]] = []
            selected: list[str] = []
            view.token_dragged.connect(lambda cid, gx, gy: dragged.append((cid, gx, gy)))
            view.token_selected.connect(lambda cid: selected.append(cid))

            # Left-clicking empty background at (220, 220) (inside AoE boundingRect, outside token footprint) does nothing
            press_bg = QMouseEvent(
                QEvent.Type.MouseButtonPress,
                QPointF(220.0, 220.0),
                QPointF(220.0, 220.0),
                Qt.MouseButton.LeftButton,
                Qt.MouseButton.LeftButton,
                Qt.KeyboardModifier.NoModifier,
            )
            rel_bg = QMouseEvent(
                QEvent.Type.MouseButtonRelease,
                QPointF(220.0, 220.0),
                QPointF(220.0, 220.0),
                Qt.MouseButton.LeftButton,
                Qt.MouseButton.NoButton,
                Qt.KeyboardModifier.NoModifier,
            )
            view.mousePressEvent(press_bg)
            view.mouseReleaseEvent(rel_bg)
            self.assertEqual(selected, [])
            self.assertEqual(dragged, [])
            self.assertEqual((scene.creatures["p1"].gx, scene.creatures["p1"].gy), (2.0, 2.0))

            # Left-clicking directly on the token at (125, 125) without dragging selects it without moving it
            press_tok = QMouseEvent(
                QEvent.Type.MouseButtonPress,
                QPointF(125.0, 125.0),
                QPointF(125.0, 125.0),
                Qt.MouseButton.LeftButton,
                Qt.MouseButton.LeftButton,
                Qt.KeyboardModifier.NoModifier,
            )
            rel_tok = QMouseEvent(
                QEvent.Type.MouseButtonRelease,
                QPointF(125.0, 125.0),
                QPointF(125.0, 125.0),
                Qt.MouseButton.LeftButton,
                Qt.MouseButton.NoButton,
                Qt.KeyboardModifier.NoModifier,
            )
            view.mousePressEvent(press_tok)
            view.mouseReleaseEvent(rel_tok)
            self.assertEqual(selected, ["p1"])
            self.assertEqual(dragged, [])
            self.assertEqual((scene.creatures["p1"].gx, scene.creatures["p1"].gy), (2.0, 2.0))
        except ImportError:
            scene = BattleMapScene()
            scene.flash_mark(120.0, 160.0)
            self.assertEqual(scene.marks, [(120.0, 160.0)])


if __name__ == "__main__":
    unittest.main()

