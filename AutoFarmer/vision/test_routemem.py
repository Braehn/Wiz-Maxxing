"""test_routemem.py - the walker's route memory (routemem.py): legs of a quest walked well kept per zone, the heat they
make, the planner's discount on it (navroute.HEAT), and the vision helper's /nav wiring. No game, no zone files:
python -m unittest test_routemem  (from AutoFarmer\\vision)

2026-11-22 (the user): "everytime a success quest start to quest end occurs successfully we add a value to that route
and create a sort of data heatmap of what're the most efficient routes throughout the map". Pins: a leg is kept only
when the wizard got where the quest's path led and the goal (or the zone) moved on - clean (mob avoidance on, you not
playing), not too long, no teleport or knockout in it; its weight is how well it went (detours, waits and battles
lower it); the heat is each leg's weight once per square it passed, older legs weighing less; the planner takes the
warm way of two about as long, with the mobs' costs added on top as dear."""
import json
import math
import os
import re
import sys
import tempfile
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import routemem as M  # noqa: E402
import navroute as R  # noqa: E402

Z = 'Wysteria/PA_Z01_Pegasus'
GOAL = 'Talk to Groundskeeper Verne in Pegasus Place'


class Clock:
    def __init__(self, t=1_800_000_000.0):
        self.t = t

    def __call__(self):
        return self.t


def walk(rm, clock, a, b, speed=1000.0, dt=0.25, goal=GOAL, target=None, zone=Z, clean=True, upto=1.0):
    """readings walking straight from a to b (x, y) - up to `upto` of the way - with the quest's path leading to target
    (b by default); the clock moved on. The log lines said"""
    target = target or (b[0], b[1], 0.0)
    said = []
    n = max(1, int(math.ceil(math.hypot(b[0] - a[0], b[1] - a[1]) / (speed * dt))))
    for k in range(int(n * upto) + 1):
        f = k / n
        s = rm.see(zone, (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, 0.0), goal, target, clean=clean)
        if s:
            said.append(s)
        clock.t += dt
    return said


def legs(folder, zone=Z):
    p = M.zone_file(folder, zone)
    if not os.path.exists(p):
        return []
    with open(p, encoding='utf-8') as f:
        return [json.loads(line) for line in f]


class Legs(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.clock = Clock()
        self.logs = []
        self.rm = M.RouteMem(self.dir, log=self.logs.append, clock=self.clock)

    def test_kept_when_the_goal_moves_on_there(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000))
        said = self.rm.see(Z, (0.0, 3000.0, 0.0), 'Collect Pegasus Chow in Pegasus Place (0 of 5)', (900.0, 0.0, 0.0))
        self.assertIn('kept the leg in ' + Z, said)
        got = legs(self.dir)
        self.assertEqual(len(got), 1)
        leg = got[0]
        self.assertEqual(leg['goal'], GOAL)
        self.assertEqual(leg['from'], [0, 0])
        self.assertAlmostEqual(leg['eff'], 1.0, delta=0.05)
        self.assertAlmostEqual(leg['s'], 2.6, delta=0.5)      # (to ARRIVE of the goal, not to the goal moving on)
        self.assertTrue(all(math.hypot(q[0] - p[0], q[1] - p[1]) >= M.STEP - 1 for p, q in zip(leg['pts'], leg['pts'][1:])))
        # (a new leg begun at once for the next goal)
        self.assertEqual(self.rm.leg['key'], 'collect pegasus chow in pegasus place')

    def test_the_count_isnt_another_goal(self):
        walk(self.rm, self.clock, (0, 0), (0, 1500), goal='Collect Pegasus Chow in Pegasus Place (3 of 5)', upto=0.5)
        walk(self.rm, self.clock, (0, 750), (0, 1500), goal='Collect Pegasus Chow in Pegasus Place (4 of 5)')
        self.assertEqual(legs(self.dir), [])
        self.assertIsNotNone(self.rm.leg)
        self.assertEqual(self.rm.leg['pts'][0], (0.0, 0.0))
        self.assertEqual(M.goal_key('Collect  X (3 of 5)'), M.goal_key('collect x (4 OF 5)'))

    def test_dropped_when_not_there(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000), upto=0.5)
        said = self.rm.see(Z, (0.0, 1500.0, 0.0), 'Another goal', (0.0, 5000.0, 0.0))
        self.assertIn('dropped', said)
        self.assertIn('not there', said)
        self.assertEqual(legs(self.dir), [])

    def test_zone_change_at_the_way_out(self):
        walk(self.rm, self.clock, (0, 0), (2000, 0), target=(2100.0, 0.0, 0.0))
        said = self.rm.see('Wysteria/PA_Hub', (50.0, 50.0, 0.0), GOAL, (4000.0, 0.0, 0.0))
        self.assertIn('kept', said)
        self.assertEqual(len(legs(self.dir)), 1)
        self.assertEqual(self.rm.leg['zone'], 'Wysteria/PA_Hub')
        # (into another zone far from the way out: a knockout, a recall - dropped)
        walk(self.rm, self.clock, (50, 50), (3000, 50), target=(4000.0, 0.0, 0.0), zone='Wysteria/PA_Hub', upto=0.5)
        said = self.rm.see('WizardCity/WC_Hub', (0.0, 0.0, 0.0), GOAL, (100.0, 0.0, 0.0))
        self.assertIn('dropped', said)
        self.assertEqual(legs(self.dir, 'Wysteria/PA_Hub'), [])

    def test_knockout_respawn_dropped(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000), upto=0.6)
        self.clock.t += 90                                   # (a battle lost)
        said = self.rm.see(Z, (-4000.0, -4000.0, 0.0), GOAL, (0.0, 3000.0, 0.0))
        self.assertIn('a teleport, a knockout', said)
        # (a quick jump while "walking" - faster than any walk: the same)
        walk(self.rm, self.clock, (-4000, -4000), (-4000, -3000), target=(0.0, 3000.0, 0.0), upto=0.5)
        said = self.rm.see(Z, (2000.0, 2000.0, 0.0), GOAL, (0.0, 3000.0, 0.0))
        self.assertIn('a teleport', said)
        self.assertEqual(legs(self.dir), [])

    def test_not_clean_dropped(self):
        walk(self.rm, self.clock, (0, 0), (0, 1500), upto=0.5)
        walk(self.rm, self.clock, (0, 750), (0, 3000), clean=False, upto=0.2)
        walk(self.rm, self.clock, (0, 1200), (0, 3000))
        said = self.rm.see(Z, (0.0, 3000.0, 0.0), 'Next', (0.0, 9000.0, 0.0))
        self.assertIn('you were playing, or mob avoidance was off', said)
        self.assertEqual(legs(self.dir), [])

    def test_too_long_and_gaps_dropped(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000), upto=0.3)
        self.clock.t += M.GAP_MAX + 1
        said = self.rm.see(Z, (0.0, 900.0, 0.0), GOAL, (0.0, 3000.0, 0.0))
        self.assertIn('nothing read for', said)
        # (standing stuck for 15 minutes: dropped)
        for _ in range(int(M.LEG_MAX / 60) + 2):
            self.clock.t += 60
            said = self.rm.see(Z, (0.0, 900.0, 0.0), GOAL, (0.0, 3000.0, 0.0)) or said
        self.assertIn('longer than', said)
        self.assertEqual(legs(self.dir), [])

    def test_short_legs_not_kept(self):
        walk(self.rm, self.clock, (0, 0), (0, 200), target=(0.0, 250.0, 0.0))
        self.assertIsNone(self.rm.see(Z, (0.0, 200.0, 0.0), 'Next', (0.0, 9000.0, 0.0)))
        self.assertEqual(legs(self.dir), [])

    def test_no_ids_same_goal(self):
        # (a reading without the game's ids for the goal: the same goal - no leg ended, none begun)
        self.assertIsNone(self.rm.see(Z, (0.0, 0.0, 0.0), '', (0.0, 3000.0, 0.0)))
        self.assertIsNone(self.rm.leg)
        walk(self.rm, self.clock, (0, 0), (0, 3000), goal='ids 1 2', upto=0.5)
        walk(self.rm, self.clock, (0, 1500), (0, 3000), goal='')
        self.assertEqual(self.rm.leg['key'], 'ids 1 2')
        self.assertIn('kept', self.rm.see(Z, (0.0, 3000.0, 0.0), 'ids 1 3', (0.0, 9000.0, 0.0)))

    def test_no_target_no_leg(self):
        self.assertIsNone(self.rm.see(Z, (0.0, 0.0, 0.0), GOAL, None))
        self.assertIsNone(self.rm.leg)
        self.assertIsNone(self.rm.see(Z, None, GOAL, (0.0, 1.0, 0.0)))
        self.assertIsNone(self.rm.see('', (0.0, 0.0, 0.0), GOAL, (0.0, 1.0, 0.0)))

    def test_a_battle_on_the_way_weighs_less(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000), upto=0.5)
        self.clock.t += 60                                   # (caught: a minute's battle, no readings)
        walk(self.rm, self.clock, (0, 1500), (0, 3000))
        self.rm.see(Z, (0.0, 3000.0, 0.0), 'Next', (0.0, 9000.0, 0.0))
        eff = legs(self.dir)[0]['eff']
        self.assertLess(eff, 0.1)
        self.assertGreater(eff, 0.0)
        # (and a detour: the straight line over the length walked)
        rm2 = M.RouteMem(tempfile.mkdtemp(), clock=self.clock)
        walk(rm2, self.clock, (0, 0), (1500, 1500), target=(0.0, 3000.0, 0.0))
        walk(rm2, self.clock, (1500, 1500), (0, 3000), target=(0.0, 3000.0, 0.0))
        rm2.see(Z, (0.0, 3000.0, 0.0), 'Next', (0.0, 9000.0, 0.0))
        self.assertAlmostEqual(legs(rm2.folder)[0]['eff'], 3000 / (2 * math.hypot(1500, 1500)), delta=0.05)

    def test_file_kept_short_and_bad_lines_skipped(self):
        p = M.zone_file(self.dir, Z)
        self.assertTrue(p.endswith('Wysteria_PA_Z01_Pegasus.jsonl'))
        with open(p, 'w', encoding='utf-8') as f:
            f.write('not json\n{"no": "pts"}\n')
            for k in range(2 * M.KEEP):
                f.write(json.dumps({'t': self.clock.t, 'eff': 1.0, 'pts': [[0, k], [0, k + 40]]}) + '\n')
        walk(self.rm, self.clock, (0, 0), (0, 3000))
        self.rm.see(Z, (0.0, 3000.0, 0.0), 'Next', (0.0, 9000.0, 0.0))
        got = legs(self.dir)
        self.assertEqual(len(got), M.KEEP)
        self.assertEqual(got[-1]['goal'], GOAL)
        with open(p, 'rb') as f:
            self.assertNotIn(b'\r\n', f.read())


class Heat(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.clock = Clock()
        self.rm = M.RouteMem(self.dir, clock=self.clock)

    def kept(self, n, a=(0, 0), b=(0, 3000)):
        for _ in range(n):
            walk(self.rm, self.clock, a, b)
            self.rm.see(Z, (float(b[0]), float(b[1]), 0.0), 'Next', (0.0, 9000.0, 0.0))
            self.rm.leg = None

    def test_heat_on_the_trail_only(self):
        self.assertIsNone(self.rm.heat01(Z, 0, 0, 10, 10, 20.0))
        self.kept(3)
        h = self.rm.heat01(Z, -400.0, 0.0, 40, 150, 20.0)    # (x -400..400, y 0..3000 by 20s)
        self.assertEqual(h.shape, (150, 40))
        col = lambda x: int((x + 400) / 20)                  # noqa: E731
        self.assertAlmostEqual(h[75, col(0)], 1.0, delta=0.02)      # (3 legs of eff ~1: FULL)
        self.assertAlmostEqual(h[75, col(50)], 1.0, delta=0.02)     # (a square beside it: WIDE)
        self.assertEqual(h[75, col(200)], 0.0)
        self.assertEqual(h[75, col(-200)], 0.0)
        self.assertLessEqual(h.max(), 1.0)

    def test_each_leg_once_per_square(self):
        # (a leg standing about in one square doesn't heat it more than one walking through)
        walk(self.rm, self.clock, (0, 0), (0, 3000))
        for _ in range(20):
            self.rm.see(Z, (0.0, 3000.0, 0.0), GOAL, (0.0, 3000.0, 0.0))
        self.rm.see(Z, (0.0, 3000.0, 0.0), 'Next', (0.0, 9000.0, 0.0))
        grid, x0, y0 = self.rm.zone_grid(Z)
        self.assertLessEqual(grid.max(), 1.0 + 1e-9)

    def test_old_legs_weigh_less(self):
        self.kept(3)
        h = self.rm.heat01(Z, -20.0, 1500.0, 1, 1, 40.0)[0, 0]
        self.clock.t += M.HALF_LIFE * 86400 + 3601           # (a half-life on - the grid made again after an hour)
        h2 = self.rm.heat01(Z, -20.0, 1500.0, 1, 1, 40.0)[0, 0]
        self.assertAlmostEqual(h2, h / 2, delta=0.02)
        self.assertAlmostEqual(M.leg_weight({'t': 0, 'eff': 0.0}, 0), M.EFF_MIN)
        self.assertEqual(M.leg_weight({'t': 'x', 'eff': 1}, 0), 0.0)

    def test_read_again_from_the_file(self):
        self.kept(2)
        rm2 = M.RouteMem(self.dir, clock=self.clock)
        self.assertAlmostEqual(rm2.heat01(Z, -20.0, 1500.0, 1, 1, 40.0)[0, 0], 2 / M.FULL, delta=0.02)


class Planner(unittest.TestCase):
    """the planner takes the warm way of two about as long; walls stay walls and mobs as dear"""

    def setUp(self):
        import test_navroute as T
        self.T = T
        self.was = R.HEAT

    def tearDown(self):
        R.HEAT = self.was

    def side(self, heat):
        R.HEAT = heat
        T = self.T
        f = T.field(geo=T.FlatGeo(walls=[(-150.0, 800.0, 150.0, 1200.0)]))
        return T.crossing(T.route_pts(f, (0.0, 0.0)), 1000.0), f

    @staticmethod
    def warm(sign):
        def heat(zone, x0, y0, nx, ny, cell):
            X = x0 + (np.arange(nx) + 0.5) * cell
            return np.repeat(((X * sign > 150) & (X * sign < 400)).astype(float)[None, :], ny, axis=0)
        return heat

    def test_warm_side_taken(self):
        x_none, _ = self.side(None)
        self.assertIsNotNone(x_none)
        x_right, _ = self.side(self.warm(1))
        x_left, _ = self.side(self.warm(-1))
        self.assertGreater(x_right, 150.0)
        self.assertLess(x_left, -150.0)

    def test_discount_and_mobs_on_top(self):
        R.HEAT = lambda zone, x0, y0, nx, ny, cell: np.ones((ny, nx))
        f = self.T.field([(0.0, 1000.0, 0.0, None, True)], mob_near=300.0)
        self.assertAlmostEqual(f.cost[f.cell((0.0, 1000.0))], 1.0 - R.HEAT_DISCOUNT + R.MOB_COST)
        self.assertAlmostEqual(f.cost[f.cell((0.0, 1700.0))], 1.0 - R.HEAT_DISCOUNT)
        # (a heat of the wrong shape, or one that fails: no discount)
        R.HEAT = lambda zone, x0, y0, nx, ny, cell: np.ones((2, 2))
        self.assertAlmostEqual(self.T.field().cost[0, 0], 1.0)
        R.HEAT = lambda *a: 1 / 0
        self.assertAlmostEqual(self.T.field().cost[0, 0], 1.0)
        # (walls stay walls)
        R.HEAT = lambda zone, x0, y0, nx, ny, cell: np.ones((ny, nx))
        f = self.T.field(geo=self.T.FlatGeo(walls=[(-150.0, 800.0, 150.0, 1200.0)]))
        self.assertTrue(np.isinf(f.cost[f.cell((0.0, 1000.0))]))

    def test_with_routemem(self):
        d, clock = tempfile.mkdtemp(), Clock()
        rm = M.RouteMem(d, clock=clock)
        for _ in range(3):
            walk(rm, clock, (300, -500), (300, 2500), target=(300.0, 2500.0, 0.0))
            rm.see('Test/Flat', (300.0, 2500.0, 0.0), 'Next', (0.0, 9000.0, 0.0))
            rm.leg = None
        R.HEAT = rm.heat01
        x, _ = self.side(rm.heat01)
        self.assertGreater(x, 150.0)


class HelperWiring(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(HERE, 'vision.py'), encoding='utf-8') as f:
            cls.src = f.read()

    def test_nav_reading_kept_before_the_route(self):
        s = self.src
        i = s.index('                    route_heat(q, r, goal)\n')
        self.assertLess(s.index("if q.get('avoid', '0') not in ('', '0'):\n                        near, cone = mob_avoid(q)"), i)
        self.assertLess(i, s.index('                    lines += route_lines(r, nm.game_dir, avoid, near, cone, arc_r, duels,'))

    def test_route_heat(self):
        m = re.search(r"^def route_heat\(q, r, goal\):\n(.*?)\n\n\n", self.src, re.M | re.S)
        self.assertIsNotNone(m)
        body = m.group(1)
        self.assertIn("navroute.HEAT = rm.heat01 if q.get('heat', '0') not in ('', '0') else None", body)
        self.assertIn("clean = q.get('avoid', '0') not in ('', '0') and q.get('user', '0') in ('', '0')", body)
        self.assertIn("rm.see(r.get('zone'), r.get('pos'), key, r.get('goal'), clean=clean, label=text)", body)
        self.assertIn('except Exception as e:', body)
        self.assertIn("os.path.join(ROOT, 'routes', 'heat')", self.src)

    def test_route_heat_runs(self):
        # (the function itself, on a stand-in memory: a reading kept, the planner's heat set with heat=1 only)
        m = re.search(r"^def route_heat\(q, r, goal\):\n.*?\n\n\n", self.src, re.M | re.S)
        seen, logs = [], []

        class RM:
            heat01 = 'H'

            def see(self, *a, **k):
                seen.append((a, k))
                return 'said'
        ns = {'route_mem': RM, 'log': logs.append}
        exec(m.group(0), ns)
        was = R.HEAT
        try:
            r = {'zone': Z, 'pos': (1.0, 2.0, 3.0), 'goal': (4.0, 5.0, 6.0), 'quest': 7, 'goalid': 8}
            ns['route_heat']({'heat': '1', 'avoid': '1', 'goal': 'screen line'}, r, {'text': 'memory line'})
            self.assertEqual(R.HEAT, RM.heat01)
            self.assertEqual(seen[-1], ((Z, (1.0, 2.0, 3.0), 'ids 7 8', (4.0, 5.0, 6.0)), {'clean': True, 'label': 'memory line'}))
            self.assertEqual(logs, ['said'])
            ns['route_heat']({'avoid': '1', 'user': '1', 'goal': 'screen line'}, dict(r, goalid=None), None)
            self.assertIsNone(R.HEAT)
            self.assertEqual(seen[-1], ((Z, (1.0, 2.0, 3.0), '', (4.0, 5.0, 6.0)), {'clean': False, 'label': 'screen line'}))
        finally:
            R.HEAT = was


if __name__ == '__main__':
    unittest.main()
