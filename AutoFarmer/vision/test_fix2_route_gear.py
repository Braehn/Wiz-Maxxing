"""test_fix2_route_gear.py - the 2026-11-27 review's gear-model and route fixes: python -m unittest test_fix2_route_gear
(from AutoFarmer\\vision). No game, no zone files.

Pins: the gear score's baseline (a total /gear isn't sent is at least the worn piece's own - a power-pip loss counts;
health not sent isn't counted - a +20 health piece no longer beats -8 damage), a slot with nothing worn gets the best
backpack piece (not the first), a run's start notes the worn pieces too (one taken off mid-run isn't a drop), a lift's
stacked nav nodes are a teleport even with every sample on one floor, the route memory keeps the ZONES_HEAT zones last
asked for, and a zone file whose heat isn't kept (routeheat off) is still cut back to KEEP legs."""
import json
import os
import sys
import tempfile
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gearrank as G  # noqa: E402
import navroute as R  # noqa: E402
import routemem as M  # noqa: E402


def stat(name, v):
    return {"type": "StatisticEffectInfo", "fields": {"m_effectName": name, "m_value": v}}


def lvl(n):
    return {"op": 0, "not": False, "list": [{"type": "ReqMagicLevel", "fields": {"m_numericValue": n}}]}


def piece(gid, name, slot, level, *effects):
    return {"gid": gid, "tid": gid, "name": name, "slot": slot, "reqs": lvl(level), "effects": list(effects)}


class GearScore(unittest.TestCase):
    def test_health_unknown_isnt_everything(self):
        # (mem-misc-1: hp not sent - a hat with 8 less damage and 20 more health was "better" by +144)
        worn = [piece(1, "Hat-A", "hat", 5, stat("CanonicalFireDamage", 10), stat("CanonicalMaxHealth", 300))]
        bag = [piece(2, "Hat-B", "hat", 5, stat("CanonicalFireDamage", 2), stat("CanonicalMaxHealth", 320))]
        for hp in (0, 3000):
            j = G.swap_plan(worn, bag, {"damage": 60, "hp": hp}, "fire", 100)["judged"][0]
            self.assertEqual(j["verdict"], "not better", hp)
            self.assertLess(j["delta"], 0, hp)

    def test_health_unknown_note(self):
        lines = G.answer({"worn": [], "bag": [], "bag_gids": []}, "", {"school": "fire"})
        self.assertFalse(any("count for little" in ln for ln in lines))
        self.assertTrue(any("health isn't counted" in ln for ln in lines))

    def test_power_pip_loss_counts(self):
        # (mem-misc-2: pp is never sent - a +15% power pip ring swapped for +4 damage was "better" by 2.47)
        worn = [piece(1, "Ring-PP", "ring", 5, stat("CanonicalPowerPip", 15))]
        bag = [piece(2, "Ring-D", "ring", 5, stat("CanonicalFireDamage", 4))]
        for pp in (0, 40):
            j = G.swap_plan(worn, bag, {"damage": 60, "hp": 3000, "pp": pp}, "fire", 100)["judged"][0]
            self.assertEqual(j["verdict"], "not better", pp)

    def test_baseline(self):
        t, wd, cd = G.baseline({"pp": 0, "hp": 0, "crit": 300}, {"pp": 15, "hp": 200, "crit": 50}, {"hp": 400})
        self.assertEqual(t["pp"], 15)            # at least the worn piece's own
        self.assertEqual(t["crit"], 300)         # a total sent higher kept
        self.assertEqual((wd["hp"], cd["hp"]), (0, 0))   # health not known: not counted

    def test_known_totals_unchanged(self):
        # (totals that hold the worn piece: the baseline changes nothing)
        worn = [piece(1, "Hat-A", "hat", 5, stat("CanonicalFireDamage", 10), stat("CanonicalMaxHealth", 300))]
        bag = [piece(2, "Hat-B", "hat", 5, stat("CanonicalFireDamage", 14), stat("CanonicalMaxHealth", 300))]
        totals = {"damage": 60, "hp": 3000}
        w, c = G._prep(worn[0], "fire"), G._prep(bag[0], "fire")
        s0 = G.score(totals, "hitter", "fire", 100)
        s1 = G.score(G.swapped(totals, w["delta"], c["delta"]), "hitter", "fire", 100)
        self.assertEqual(G.compare(w, c, totals, "hitter", "fire", 100)[0], round((s1 - s0) * 100, 2))

    def test_empty_slot_best_piece(self):
        # (mem-misc-3: nothing worn - every piece was "empty" 100 and the first in the backpack was planned)
        worn = [piece(1, "Hat", "hat", 5)]
        bag = [piece(2, "Ring-Weak", "ring", 5, stat("CanonicalMaxHealth", 5)),
               piece(3, "Ring-Strong", "ring", 60, stat("CanonicalFireDamage", 9), stat("CanonicalMaxHealth", 200))]
        for hp in (0, 3000):
            plan = G.swap_plan(worn, bag, {"damage": 60, "hp": hp}, "fire", 100)["plan"]
            self.assertEqual([(p["name"], p["basis"]) for p in plan], [("Ring-Strong", "empty")], hp)
        # (sizes not known: the higher level requirement)
        bag = [piece(2, "Ring-Low", "ring", 5, {"type": "StatisticEffectInfo", "fields": {
                   "m_effectName": "CanonicalFireDamage", "m_lookupIndex": 3}}),
               piece(3, "Ring-High", "ring", 60, {"type": "StatisticEffectInfo", "fields": {
                   "m_effectName": "CanonicalFireDamage", "m_lookupIndex": 3}})]
        plan = G.swap_plan(worn, bag, {"damage": 60, "hp": 3000}, "fire", 100)["plan"]
        self.assertEqual([p["name"] for p in plan], ["Ring-High"])


class DropStart(unittest.TestCase):
    def test_worn_piece_taken_off_isnt_a_drop(self):
        # (mem-misc-4: before= held only the backpack's ids)
        d = tempfile.mkdtemp()
        book = G.DropBook(d)
        hat_a = {"gid": 0xA, "tid": 100, "name": "Hat-A", "slot": "hat"}
        hat_b = {"gid": 0xB, "tid": 101, "name": "Hat-B", "slot": "hat"}
        st = book.mark("Run", {"worn": [hat_a], "bag": [hat_b], "bag_gids": [0xB]}, "t0")
        self.assertEqual(sorted(st["before"]), [0xA, 0xB])
        out = book.run_end("Run", {"worn": [hat_b], "bag": [hat_a], "bag_gids": [0xA]}, [], ["hat"], 30, "t1")
        self.assertEqual(out["new"], [])
        self.assertFalse(os.path.exists(book.path("Run", ".txt")))
        self.assertEqual(sorted(book.load_state("Run")["before"]), [0xA, 0xB])
        # (a real drop still is one)
        drop = {"gid": 0xC, "tid": 102, "name": "Hat-C", "slot": "hat"}
        out = book.run_end("Run", {"worn": [hat_b], "bag": [hat_a, drop], "bag_gids": [0xA, 0xC]}, [], ["hat"], 30,
                           "t2")
        self.assertEqual([it["gid"] for it in out["new"]], [0xC])

    def test_owned_gids(self):
        self.assertEqual(G.owned_gids({"bag_gids": [1, 2], "worn": [{"gid": 2}, {"gid": 3}, {"gid": None}, {}]}),
                         [1, 2, 3])
        self.assertEqual(G.owned_gids(None), [])


class OneFloor:
    """a stand-in for ZoneGeo's grids: floor everywhere, at height floor(x) (the square's middle)"""

    def __init__(self, floor):
        self.floor = floor

    def grids(self, x0, y0, nx, ny, ref):
        X = x0 + (np.arange(nx) + 0.5) * R.CELL
        H = np.tile(np.array([self.floor(x) for x in X], dtype=float), (ny, 1))
        return np.ones((ny, nx), dtype=int), H, np.zeros((ny, nx), dtype=bool)


def geo(floor):
    g = R.ZoneGeo.__new__(R.ZoneGeo)
    g._jcache = {}
    g.grids = OneFloor(floor).grids
    return g


class LiftJump(unittest.TestCase):
    def test_stacked_nodes_are_a_teleport(self):
        # (navroute-2: Arcanum's hub lift, h 7.7 and dz 1157 - every sample in one square on the ground floor)
        a, b = (0.0, 0.0, 1170.0), (5.0, 6.0, 13.0)
        self.assertTrue(R.is_jump(a, b))
        g = geo(lambda x: 13.3)
        self.assertTrue(g.is_jump(a, b))
        self.assertTrue(geo(lambda x: 13.3).is_jump(b, a))
        self.assertTrue(geo(lambda x: 1170.0).is_jump(a, b))

    def test_steep_ramp_still_walked(self):
        a, b = (0.0, 0.0, 0.0), (500.0, 0.0, 450.0)
        self.assertTrue(R.is_jump(a, b))
        self.assertFalse(geo(lambda x: min(450.0, max(0.0, 0.9 * x))).is_jump(a, b))

    def test_long_flat_link_still_walked(self):
        a, b = (0.0, 0.0, 0.0), (2600.0, 0.0, 30.0)
        self.assertTrue(R.is_jump(a, b))
        self.assertFalse(geo(lambda x: 0.0).is_jump(a, b))


def leg(t, x=0.0):
    return {"t": t, "goal": "g", "from": [x, 0], "to": [x + 400, 0], "s": 10, "len": 400, "ahead": 400, "eff": 0.9,
            "pts": [[x + k * 40.0, 0.0] for k in range(11)]}


class HeatZones(unittest.TestCase):
    def test_zones_kept_last_asked(self):
        # (navroute-1: every zone asked for stayed in memory for the helper's life)
        d = tempfile.mkdtemp()
        now = 1_800_000_000.0
        zones = ["W/Z%02d" % k for k in range(M.ZONES_HEAT + 4)]
        for z in zones:
            with open(M.zone_file(d, z), "w", encoding="utf-8", newline="\n") as f:
                f.write(json.dumps(leg(now - 60)) + "\n")
        rm = M.RouteMem(d, log=lambda *a: None, clock=lambda: now)
        self.assertIsNotNone(rm.zone_heat(zones[0]))
        for z in zones[1:]:
            self.assertIsNotNone(rm.zone_heat(z))
            rm.zone_heat(zones[0])                      # (asked for again and again: kept)
        self.assertLessEqual(len(rm.zones), M.ZONES_HEAT)
        self.assertIn(zones[0], rm.zones)
        self.assertIn(zones[-1], rm.zones)
        self.assertNotIn(zones[1], rm.zones)
        # (one let go is read again when next asked for)
        self.assertIsNotNone(rm.zone_heat(zones[1]))
        self.assertIn(zones[1], rm.zones)

    def test_file_cut_with_heat_not_kept(self):
        # (x-helperrt-10: routeheat off - nothing asks for the heat - the file grew for ever)
        d = tempfile.mkdtemp()
        now = 1_800_000_000.0
        z = "W/Busy"
        path = M.zone_file(d, z)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            for k in range(2 * M.KEEP):
                f.write(json.dumps(leg(now - 1000 + k, k)) + "\n")
        rm = M.RouteMem(d, log=lambda *a: None, clock=lambda: now)
        rm._keep(z, leg(now, 9999.0))
        with open(path, "rb") as f:
            lines = [ln for ln in f.read().split(b"\n") if ln.strip()]
        self.assertEqual(len(lines), M.KEEP)
        self.assertEqual(json.loads(lines[-1])["from"], [9999.0, 0])
        self.assertNotIn(z, rm.zones)
        # (a short one is only appended to)
        z2 = "W/Quiet"
        rm._keep(z2, leg(now))
        rm._keep(z2, leg(now + 1))
        with open(M.zone_file(d, z2), "rb") as f:
            self.assertEqual(len([ln for ln in f.read().split(b"\n") if ln.strip()]), 2)


if __name__ == "__main__":
    unittest.main()
