"""test_routemem.py - the walker's route memory (routemem.py): walks to quest goals that went well kept per zone, the
heat they make, the planner's discount on it (navroute.HEAT), the quests' lines, and the wiring (vision.py's /nav,
Vision.ahk's route ask). No game, no zone files: python -m unittest test_routemem  (from AutoFarmer\\vision)

2026-11-22 (the user): "everytime a success quest start to quest end occurs successfully we add a value to that route
and create a sort of data heatmap of what're the most efficient routes throughout the map". Pins: a leg is the walk
to where the quest's path leads, frozen there (a fight or a hunt for things at the goal isn't part of it - review:
walks to "Defeat ..." goals were never kept); kept only once the goal (or the zone) moves on, clean on the way (mob
avoidance on; you not playing, the bot and its walking on - review: the flag never reached the helper), not too long,
no teleport or knockout before it got there; its weight is how well it went against the game's own path; a square's
heat is the mean eff of the walks through it (fewer than FULL: less) - review: a few detours locked the planner onto a
lane a fifth longer - and the planner's discount only breaks near-ties; the walker's /nav never waits for a zone's heat
being built (review: a rebuild held its lock past NavRead's 150 ms); a zone's file deleted is forgotten at once."""
import json
import math
import os
import re
import sys
import tempfile
import threading
import time
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import routemem as M  # noqa: E402
import navroute as R  # noqa: E402

Z = 'Wysteria/PA_Z01_Pegasus'
GOAL = 'ids 1 2'
NEXT = 'ids 1 3'


class Clock:
    def __init__(self, t=1_800_000_000.0):
        self.t = t

    def __call__(self):
        return self.t


def walk(rm, clock, a, b, speed=1000.0, dt=0.25, goal=GOAL, target=None, zone=Z, clean=True, upto=1.0, **kw):
    """readings walking straight from a to b (x, y) - up to `upto` of the way - with the quest's path leading to target
    (b by default); the clock moved on. The log lines said"""
    target = target or (b[0], b[1], 0.0)
    said = []
    n = max(1, int(math.ceil(math.hypot(b[0] - a[0], b[1] - a[1]) / (speed * dt))))
    for k in range(int(n * upto) + 1):
        f = k / n
        s = rm.see(zone, (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, 0.0), goal, target, clean=clean, **kw)
        if s:
            said.append(s)
        clock.t += dt
    return said


def legs(rm, zone=Z):
    """the zone's kept legs, as written (the writer thread waited for)"""
    assert rm.flush(5.0)
    p = M.zone_file(rm.folder, zone)
    if not os.path.exists(p):
        return []
    with open(p, encoding='utf-8') as f:
        return [json.loads(line) for line in f]


def done(rm, at=(0.0, 3000.0), goal=NEXT):
    """the goal moving on where the wizard stands (what it kept written)"""
    said = rm.see(Z, (at[0], at[1], 0.0), goal, (0.0, 9000.0, 0.0))
    rm.flush(5.0)
    return said


class Legs(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.clock = Clock()
        self.rm = M.RouteMem(self.dir, log=lambda m: None, clock=self.clock)

    def test_kept_when_the_goal_moves_on_there(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000), label='Talk to Groundskeeper Verne')
        said = done(self.rm)
        self.assertIn('kept the leg in ' + Z + " to 'Talk to Groundskeeper Verne'", said)
        got = legs(self.rm)
        self.assertEqual(len(got), 1)
        leg = got[0]
        self.assertEqual(leg['from'], [0, 0])
        self.assertAlmostEqual(leg['eff'], 1.0, delta=0.05)
        self.assertAlmostEqual(leg['s'], 2.75, delta=0.3)     # (to ARRIVE of the goal, not to the goal moving on)
        self.assertLessEqual(math.hypot(leg['to'][0], leg['to'][1] - 3000), M.ARRIVE)
        self.assertTrue(all(math.hypot(q[0] - p[0], q[1] - p[1]) >= M.STEP - 1 for p, q in zip(leg['pts'][:-1], leg['pts'][1:-1])))
        # (a new leg begun at once for the next goal)
        self.assertEqual(self.rm.leg['key'], NEXT)

    def test_the_count_isnt_another_goal(self):
        self.assertEqual(M.goal_key('Collect  X (3 of 5)'), M.goal_key('collect x (4 OF 5)'))
        walk(self.rm, self.clock, (0, 0), (0, 1500), goal='Collect X (3 of 5)', upto=0.5)
        walk(self.rm, self.clock, (0, 750), (0, 1500), goal='Collect X (4 of 5)')
        self.assertEqual(legs(self.rm), [])
        self.assertEqual(self.rm.leg['pts'][0], (0.0, 0.0))

    def test_no_ids_same_goal(self):
        # (a reading without the game's ids for the goal: the same goal - no leg ended, none begun)
        self.assertIsNone(self.rm.see(Z, (0.0, 0.0, 0.0), '', (0.0, 3000.0, 0.0)))
        self.assertIsNone(self.rm.leg)
        walk(self.rm, self.clock, (0, 0), (0, 3000), upto=0.5)
        walk(self.rm, self.clock, (0, 1500), (0, 3000), goal='')
        self.assertEqual(self.rm.leg['key'], GOAL)
        self.assertIn('kept', done(self.rm))

    def test_dropped_when_not_there(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000), upto=0.5)
        said = done(self.rm, at=(0.0, 1500.0))
        self.assertIn('dropped', said)
        self.assertIn('not there', said)
        self.assertEqual(legs(self.rm), [])

    def test_zone_change_at_the_way_out(self):
        walk(self.rm, self.clock, (0, 0), (2000, 0), target=(2100.0, 0.0, 0.0))
        said = self.rm.see('Wysteria/PA_Hub', (50.0, 50.0, 0.0), GOAL, (4000.0, 0.0, 0.0))
        self.assertIn('kept', said)
        self.assertEqual(len(legs(self.rm)), 1)
        self.assertEqual(self.rm.leg['zone'], 'Wysteria/PA_Hub')
        # (into another zone far from the way out: a knockout, a recall - dropped)
        walk(self.rm, self.clock, (50, 50), (3000, 50), target=(4000.0, 0.0, 0.0), zone='Wysteria/PA_Hub', upto=0.5)
        said = self.rm.see('WizardCity/WC_Hub', (0.0, 0.0, 0.0), GOAL, (100.0, 0.0, 0.0))
        self.assertIn('dropped', said)
        self.assertEqual(legs(self.rm, 'Wysteria/PA_Hub'), [])

    def test_knockout_before_getting_there_dropped(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000), upto=0.6)
        self.clock.t += 90                                   # (a battle lost)
        said = self.rm.see(Z, (-4000.0, -4000.0, 0.0), GOAL, (0.0, 3000.0, 0.0))
        self.assertIn('a teleport, a knockout', said)
        # (a quick jump while "walking" - faster than any walk: the same)
        walk(self.rm, self.clock, (-4000, -4000), (-4000, -3000), target=(0.0, 3000.0, 0.0), upto=0.5)
        said = self.rm.see(Z, (2000.0, 2000.0, 0.0), GOAL, (0.0, 3000.0, 0.0))
        self.assertIn('a teleport', said)
        self.assertEqual(legs(self.rm), [])

    def test_frozen_at_arrival_a_fight_goal(self):
        # (review: "Defeat 4 Lost Souls" - the walk there with avoidance on, then the fight with it off, battles, roaming)
        walk(self.rm, self.clock, (0, 0), (0, 3000))
        for k in range(4):
            walk(self.rm, self.clock, (0, 3000), (1500, 3000 + 300 * k), clean=False, target=(0.0, 3000.0, 0.0))
            self.clock.t += 180
            walk(self.rm, self.clock, (1500, 3000 + 300 * k), (0, 3000), clean=False, target=(0.0, 3000.0, 0.0))
        said = done(self.rm)
        self.assertIn('kept', said)
        leg = legs(self.rm)[0]
        self.assertAlmostEqual(leg['eff'], 1.0, delta=0.05)
        self.assertLess(leg['len'], 3000)
        self.assertLessEqual(max(p[0] for p in leg['pts']), 1)
        self.assertLess(leg['s'], 3.5)

    def test_frozen_at_arrival_things_to_use(self):
        # (review: "Use Strange Plant" - walking to the goal's things afterwards, avoidance on: not part of the walk)
        walk(self.rm, self.clock, (0, 0), (0, 3000))
        walk(self.rm, self.clock, (0, 3000), (2500, 3000), target=(0.0, 3000.0, 0.0))
        walk(self.rm, self.clock, (2500, 3000), (2500, 5000), target=(0.0, 3000.0, 0.0))
        done(self.rm, at=(2500.0, 5000.0))
        leg = legs(self.rm)[0]
        self.assertAlmostEqual(leg['eff'], 1.0, delta=0.05)
        self.assertLessEqual(math.hypot(leg['to'][0], leg['to'][1] - 3000), M.ARRIVE)

    def test_the_arriving_reading_may_have_avoidance_off(self):
        # (the reading that gets there may be the fight's first: it doesn't spoil the walk)
        walk(self.rm, self.clock, (0, 0), (0, 2500), target=(0.0, 3000.0, 0.0))
        self.rm.see(Z, (0.0, 2900.0, 0.0), GOAL, (0.0, 3000.0, 0.0), clean=False)
        self.assertIn('kept', done(self.rm))

    def test_knockout_in_the_goals_fight_kept(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000))
        self.clock.t += 120
        said = self.rm.see(Z, (-5000.0, 0.0, 0.0), GOAL, (0.0, 3000.0, 0.0))     # (respawned)
        self.assertIn('kept', said)
        self.assertEqual(len(legs(self.rm)), 1)

    def test_there_too_long_dropped(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000))
        for _ in range(int(M.AFTER_MAX / 300) + 2):
            self.clock.t += 300
            said = self.rm.see(Z, (0.0, 3000.0, 0.0), GOAL, (0.0, 3000.0, 0.0))
            if said:
                break
        self.assertIn('the goal not moving on', said)
        self.assertEqual(legs(self.rm), [])

    def test_not_clean_on_the_way_dropped(self):
        walk(self.rm, self.clock, (0, 0), (0, 1500), upto=0.5, target=(0.0, 3000.0, 0.0))
        walk(self.rm, self.clock, (0, 750), (0, 3000), clean=False, upto=0.2)
        walk(self.rm, self.clock, (0, 1200), (0, 3000))
        self.assertIn('mob avoidance was off on the way', done(self.rm))
        self.assertEqual(legs(self.rm), [])

    def test_played_on_the_way_dropped(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000), upto=0.5)
        self.clock.t += 20
        said = self.rm.see(Z, (300.0, 1800.0, 0.0), GOAL, (0.0, 3000.0, 0.0), played=True)
        self.assertIn('you played, or the bot or its walking was off on the way', said)
        # (a new leg begun at that reading - the flag's about the time before it)
        self.assertIsNotNone(self.rm.leg)
        self.assertTrue(self.rm.leg['clean'])
        walk(self.rm, self.clock, (300, 1800), (0, 3000), target=(0.0, 3000.0, 0.0))
        self.assertIn('kept', done(self.rm))
        # (the flag on the reading where the goal moved on - you talked to the NPC yourself: dropped too)
        walk(self.rm, self.clock, (0, 3000), (0, 6000), goal='ids 1 4', target=(0.0, 6000.0, 0.0), upto=0.5)
        said = self.rm.see(Z, (0.0, 6000.0, 0.0), 'ids 1 5', (0.0, 9000.0, 0.0), played=True)
        self.assertIn('you played', said)
        self.assertEqual(len(legs(self.rm)), 1)

    def test_played_after_getting_there_kept(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000))
        self.rm.see(Z, (0.0, 3000.0, 0.0), GOAL, (0.0, 3000.0, 0.0), played=True)
        self.assertIn('kept', done(self.rm))

    def test_too_long_and_gaps_dropped(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000), upto=0.3)
        self.clock.t += M.GAP_MAX + 1
        said = self.rm.see(Z, (0.0, 900.0, 0.0), GOAL, (0.0, 3000.0, 0.0))
        self.assertIn('nothing read for', said)
        # (walking on a little, then standing stuck for 15 minutes: dropped)
        walk(self.rm, self.clock, (0, 900), (0, 3000), upto=0.25)
        for _ in range(int(M.LEG_MAX / 60) + 2):
            self.clock.t += 60
            said = self.rm.see(Z, (0.0, 900.0, 0.0), GOAL, (0.0, 3000.0, 0.0)) or said
        self.assertIn('longer than', said)
        self.assertEqual(legs(self.rm), [])

    def test_short_legs_not_kept(self):
        walk(self.rm, self.clock, (0, 0), (0, 200), target=(0.0, 250.0, 0.0))
        self.assertIsNone(done(self.rm, at=(0.0, 200.0)))
        self.assertEqual(legs(self.rm), [])

    def test_no_target_no_leg(self):
        self.assertIsNone(self.rm.see(Z, (0.0, 0.0, 0.0), GOAL, None))
        self.assertIsNone(self.rm.leg)
        self.assertIsNone(self.rm.see(Z, None, GOAL, (0.0, 1.0, 0.0)))
        self.assertIsNone(self.rm.see('', (0.0, 0.0, 0.0), GOAL, (0.0, 1.0, 0.0)))

    def test_a_battle_on_the_way_weighs_less(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000), upto=0.5)
        self.clock.t += 60                                   # (caught: a minute's battle, no readings)
        walk(self.rm, self.clock, (0, 1500), (0, 3000))
        done(self.rm)
        eff = legs(self.rm)[0]['eff']
        self.assertLess(eff, 0.1)
        self.assertGreater(eff, 0.0)

    def lane(self, way, game, goal=(0.0, 3000.0), there_at=None):
        """a kept leg walked along way (points) with the game's own path via game (its corner points) to goal - each
        reading's ahead its path from there (by the next corner still ahead); there_at: the walker takes the goal up
        (avoidance off) from this far out (by its path). The leg kept"""
        rm = M.RouteMem(tempfile.mkdtemp(), clock=self.clock)
        g3 = (goal[0], goal[1], 0.0)
        for a, b in zip(way, way[1:]):
            n = max(1, int(math.ceil(math.hypot(b[0] - a[0], b[1] - a[1]) / 250.0)))
            for k in range(n):
                p = (a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n, 0.0)
                rest = [c for c in game if c[1] > p[1]]
                ahead = M.path_len(p, [(c[0], c[1], 0.0) for c in rest], g3)
                there = there_at is not None and ahead <= there_at
                rm.see(Z, p, GOAL, g3, clean=not there, there=there, ahead=ahead)
                self.clock.t += 0.25
        done(rm, at=goal)
        got = legs(rm)
        self.assertEqual(len(got), 1)
        return got[0]

    def test_eff_against_the_games_path(self):
        # (round a wall the game's path knows of: its length, not the straight line, is what the walk is measured by)
        self.assertAlmostEqual(M.path_len((0.0, 0.0, 0.0), [(1500.0, 1500.0, 0.0)], (0.0, 3000.0, 0.0)),
                               2 * math.hypot(1500, 1500))
        leg = self.lane([(0, 0), (1500, 1500), (0, 3000)], game=[(1500, 1500)])
        self.assertGreater(leg['eff'], 0.95)
        # (review: measured to the goal, a lane 8% longer was perfect - the stretch walked is what counts)
        leg = self.lane([(0, 0), (612, 1500), (0, 3000)], game=[])
        self.assertLess(leg['eff'], 0.95)
        self.assertGreater(leg['eff'], 0.85)
        self.assertGreater(self.lane([(0, 0), (0, 3000)], game=[])['eff'], 0.97)
        self.assertIsNone(M.path_len(None, [], (0, 0, 0)))
        self.assertIsNone(M.path_len((0, 0, 0), [], None))

    def test_there_far_out_a_fight_goal(self):
        # (review 2: collecting a "Defeat ..." goal begins ~1500 out by the path, with mob avoidance off from then on)
        leg = self.lane([(0, 0), (0, 3000)], game=[], there_at=1500.0)
        self.assertAlmostEqual(leg['eff'], 1.0, delta=0.03)
        self.assertLessEqual(abs(leg['to'][1] - 1500), 260)
        self.assertLess(leg['s'], 1.8)
        # (into a mob before getting near: still kept - it got there by the walker's word)
        rm = self.rm
        walk(rm, self.clock, (0, 0), (0, 3000), upto=0.5)
        rm.see(Z, (0.0, 1600.0, 0.0), GOAL, (0.0, 3000.0, 0.0), clean=False, there=True)
        self.clock.t += 180
        self.assertIn('kept', done(rm, at=(0.0, 1700.0)))

    def test_next_leg_after_collecting(self):
        # (review 2: a goal ended collecting, no battle - for a few seconds the walker's still at it, avoidance off, with
        # the next goal's ids: the next leg begins once it walks on clean)
        walk(self.rm, self.clock, (0, 0), (0, 3000))
        for k in range(12):
            self.rm.see(Z, (0.0, 3000.0, 0.0), NEXT, (0.0, 6000.0, 0.0), clean=False, there=True)
            self.clock.t += 0.25
        self.rm.flush()
        self.assertEqual(len(legs(self.rm)), 1)
        walk(self.rm, self.clock, (0, 3000), (0, 6000), goal=NEXT)
        self.assertIn('kept', done(self.rm, at=(0.0, 6000.0), goal='ids 1 9'))
        self.assertEqual(len(legs(self.rm)), 2)

    def test_tiny_drops_not_said(self):
        # (review 2: "Wait while I play" off and you at the mouse - every reading played: no line, no count, each time)
        self.rm.quest(5, 'Q', Z, 'x')
        said = walk(self.rm, self.clock, (0, 0), (0, 3000), played=True)
        self.assertEqual(said, [])
        self.assertEqual(self.rm.qs['dropped'], 0)

    def test_file_kept_short_and_bad_lines_skipped(self):
        p = M.zone_file(self.dir, Z)
        self.assertTrue(p.endswith('Wysteria_PA_Z01_Pegasus.jsonl'))
        with open(p, 'w', encoding='utf-8') as f:
            f.write('not json\n{"no": "pts"}\n')
            for k in range(2 * M.KEEP):
                f.write(json.dumps({'t': self.clock.t, 'eff': 1.0, 'pts': [[0, k], [0, k + 40]]}) + '\n')
        self.assertIsNotNone(self.rm.zone_grid(Z))           # (read - and made shorter: it had over 2 x KEEP lines)
        self.assertEqual(len(legs(self.rm)), M.KEEP)
        walk(self.rm, self.clock, (0, 0), (0, 3000), label='Talk to Groundskeeper Verne')
        self.assertIn('kept', done(self.rm))
        got = legs(self.rm)
        self.assertEqual(len(got), M.KEEP + 1)
        self.assertEqual(got[-1]['goal'], 'Talk to Groundskeeper Verne')
        with open(p, 'rb') as f:
            self.assertNotIn(b'\r\n', f.read())


class Heat(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.clock = Clock()
        self.rm = M.RouteMem(self.dir, log=lambda m: None, clock=self.clock)

    def kept(self, n, a=(0, 0), b=(0, 3000), dt=0.25):
        for _ in range(n):
            walk(self.rm, self.clock, a, b, dt=dt)
            self.rm.see(Z, (float(b[0]), float(b[1]), 0.0), NEXT, (0.0, 9000.0, 0.0))
            self.rm.leg = None
        self.rm.flush(5.0)

    def at(self, x, y):
        return self.rm.heat01(Z, x - 10.0, y - 10.0, 1, 1, 20.0)[0, 0]

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

    def test_mean_eff_not_how_often(self):
        # (one walk: a third; FULL of them: their eff; more of them: still their eff - how well, not how often)
        self.kept(1)
        self.assertAlmostEqual(self.at(0, 1500), 1 / M.FULL, delta=0.02)
        self.kept(9)
        self.assertAlmostEqual(self.at(0, 1500), 1.0, delta=0.02)
        # (walks that went badly that way: lower - a wait in each)
        rm = self.rm = M.RouteMem(tempfile.mkdtemp(), clock=self.clock)
        for _ in range(6):
            walk(rm, self.clock, (0, 0), (0, 1500), upto=0.99, target=(0.0, 3000.0, 0.0))
            self.clock.t += 3.0                              # (stood 3 s: half the time)
            walk(rm, self.clock, (0, 1500), (0, 3000))
            done(rm)
            rm.leg = None
        eff = legs(rm)[0]['eff']
        self.assertLess(eff, 0.6)
        self.assertAlmostEqual(self.at(0, 1500), eff, delta=0.03)

    def test_each_leg_once_per_square(self):
        walk(self.rm, self.clock, (0, 0), (0, 3000))
        walk(self.rm, self.clock, (0, 0), (0, 1500), clean=True, target=(0.0, 9000.0, 0.0), goal=GOAL, upto=0)
        grid, x0, y0 = self.rm.zone_grid(Z) if self.rm.zone_grid(Z) else (np.zeros(1), 0, 0)
        self.assertLessEqual(grid.max(), 1.0 + 1e-9)

    def test_old_legs_weigh_less(self):
        self.kept(3)
        h = self.at(0, 1500)
        self.clock.t += M.HALF_LIFE * 86400                  # (a half-life on: as much less of each - fewer than FULL)
        self.assertAlmostEqual(self.at(0, 1500), h / 2, delta=0.02)
        self.clock.t += 2 * M.REBASE * 86400                 # (built afresh after REBASE: the same answer)
        self.assertAlmostEqual(self.at(0, 1500), h / 2 * 0.5 ** (2 * M.REBASE / M.HALF_LIFE), delta=0.01)
        self.assertEqual(M.leg_age_w({'t': 'x'}, 0), None)
        self.assertEqual(M.leg_eff({'eff': float('nan')}), 0.0)

    def test_read_again_from_the_file(self):
        self.kept(2)
        rm2 = M.RouteMem(self.dir, clock=self.clock)
        self.assertAlmostEqual(rm2.heat01(Z, -20.0, 1500.0, 1, 1, 40.0)[0, 0], 2 / M.FULL, delta=0.02)

    def test_a_kept_leg_added_without_building_again(self):
        self.kept(2)
        self.assertIsNotNone(self.rm.zone_grid(Z))
        zh = self.rm.zones[Z]
        n = zh.n
        calls = []
        was = M.build_heat
        M.build_heat = lambda *a: calls.append(a) or was(*a)
        try:
            self.kept(1)                                     # (inside what's built: added to it)
            self.assertIs(zh.n, n)
            self.assertAlmostEqual(self.at(0, 1500), 1.0, delta=0.02)
            self.assertEqual(calls, [])
            self.kept(1, a=(5000, 0), b=(5000, 3000))        # (outside: built again when next asked for)
            self.assertIsNone(zh.n)
            self.assertAlmostEqual(self.at(5000, 1500), 1 / M.FULL, delta=0.02)
            self.assertEqual(len(calls), 1)
        finally:
            M.build_heat = was

    def test_deleted_file_forgotten_at_once(self):
        # (review: deleting the file did nothing till the helper restarted, and the next rewrite put the legs back)
        self.kept(3)
        self.assertGreater(self.at(0, 1500), 0.9)
        os.remove(M.zone_file(self.dir, Z))
        self.assertIsNone(self.rm.heat01(Z, 0, 0, 2, 2, 20.0))
        self.kept(1, a=(3000, 0), b=(3000, 3000))
        self.assertEqual(len(legs(self.rm)), 1)
        self.assertEqual(self.at(0, 1500), 0.0)
        # (changed by someone else - a line taken out: read again)
        self.kept(1)
        with open(M.zone_file(self.dir, Z), encoding='utf-8') as f:
            first = f.readline()
        with open(M.zone_file(self.dir, Z), 'w', encoding='utf-8') as f:
            f.write(first)
        self.assertEqual(self.at(0, 1500), 0.0)
        self.assertGreater(self.at(3000, 1500), 0.3)

    def test_see_never_waits_for_a_build(self):
        # (review: /nav's see() waited on the lock a zone's heat was being built under - past NavRead's 150 ms)
        self.kept(3)
        rm = M.RouteMem(self.dir, clock=self.clock)
        was = M.build_heat
        started = threading.Event()

        def slow(*a):
            started.set()
            time.sleep(0.6)
            return was(*a)
        M.build_heat = slow
        try:
            t = threading.Thread(target=rm.zone_grid, args=(Z,))
            t.start()
            self.assertTrue(started.wait(2))
            t0 = time.perf_counter()
            walk(rm, self.clock, (0, 0), (0, 3000))
            rm.see(Z, (0.0, 3000.0, 0.0), NEXT, (0.0, 9000.0, 0.0))
            self.assertLess(time.perf_counter() - t0, 0.3)
            t.join()
        finally:
            M.build_heat = was
        self.assertEqual(len(legs(rm)), 4)
        self.assertAlmostEqual(rm.heat01(Z, -10.0, 1490.0, 1, 1, 20.0)[0, 0], 1.0, delta=0.02)

    def test_see_never_waits_for_the_files(self):
        # (review 2: a kept leg was written from /nav's own request, waiting on the files' lock another reader held)
        self.kept(1)
        got = []
        with self.rm.flock:
            t0 = time.perf_counter()
            walk(self.rm, self.clock, (0, 0), (0, 3000))
            got.append(self.rm.see(Z, (0.0, 3000.0, 0.0), NEXT, (0.0, 9000.0, 0.0)))
            self.assertLess(time.perf_counter() - t0, 0.2)
            self.assertIn('kept', got[0])
        self.assertTrue(self.rm.flush(5.0))
        self.assertEqual(len(legs(self.rm)), 2)

    def test_one_read_of_a_zone_at_a_time(self):
        # (review 2: the planner's thread and the Map's both read a zone neither had yet, one after the other)
        self.kept(3)
        rm = M.RouteMem(self.dir, clock=self.clock)
        reads, was = [], rm._read

        def slow(zone):
            reads.append(zone)
            time.sleep(0.3)
            return was(zone)
        rm._read = slow
        out = []
        ts = [threading.Thread(target=lambda: out.append(rm.heat01(Z, -10.0, 1490.0, 1, 1, 20.0))) for _ in range(3)]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
        self.assertEqual(reads, [Z])
        self.assertEqual(len(out), 3)
        self.assertTrue(all(o is not None and abs(o[0, 0] - 1.0) < 0.02 for o in out))

    def test_trail_cells(self):
        # (the squares a trail passes, as a slow walk along it every few units finds them)
        pts = [(13.0, 7.0), (517.0, 233.0), (240.0, 990.0), (241.0, 991.0)]
        got = set(M.trail_cells(pts, -100.0, -100.0, 40, 40).tolist())
        want = set()
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            n = int(math.hypot(bx - ax, by - ay)) + 1
            for k in range(n + 1):
                x, y = ax + (bx - ax) * k / n, ay + (by - ay) * k / n
                i, j = int((x + 100) // 40), int((y + 100) // 40)
                for dj in (-1, 0, 1):
                    for di in (-1, 0, 1):
                        if 0 <= i + di < 40 and 0 <= j + dj < 40:
                            want.add((j + dj) * 40 + i + di)
        self.assertLessEqual(len(want ^ got), len(want) // 20)      # (corners touched by one sampling, not the other)
        self.assertEqual(M.trail_cells([], 0, 0, 5, 5).size, 0)
        self.assertEqual(M.trail_cells([[float('nan'), 1.0]], 0, 0, 5, 5).size, 0)
        self.assertEqual(M.trail_cells('x', 0, 0, 5, 5).size, 0)


class Quests(unittest.TestCase):
    def test_a_quest_over(self):
        d, clock = tempfile.mkdtemp(), Clock()
        rm = M.RouteMem(d, clock=clock)
        self.assertIsNone(rm.quest(None, 'x', Z, 'y'))
        for k in range(30):
            rm.quest(111, 'In-Flight Meals', Z if k < 20 else 'Wysteria/PA_Hub', 'Collect Pegasus Chow (%d of 5)' % (k // 10))
            if k == 10:
                walk(rm, clock, (0, 0), (0, 3000))
                done(rm)
            clock.t += 3
        clock.t += 1000                                      # (a long stop: not counted)
        rm.quest(111, '', Z, 'Talk to Groundskeeper Verne')
        said = rm.quest(222, 'Next One', Z, 'Go To Crystal Tower')
        self.assertIn("the quest 'In-Flight Meals' over", said)
        self.assertTrue(rm.flush(5.0))
        with open(os.path.join(d, M.QUESTS), encoding='utf-8') as f:
            q = [json.loads(line) for line in f]
        self.assertEqual(len(q), 1)
        q = q[0]
        self.assertEqual(q['quest'], 'In-Flight Meals')
        self.assertEqual(q['id'], '111')
        self.assertEqual(q['zones'], [Z, 'Wysteria/PA_Hub', Z])
        self.assertEqual(q['goals'], ['Collect Pegasus Chow (0 of 5)', 'Talk to Groundskeeper Verne'])
        self.assertEqual(q['kept'], 1)
        self.assertGreater(q['s'], 85)
        self.assertLess(q['s'], 110)
        self.assertGreater(q['span'], 1000)
        # (a quest followed a few seconds: not written)
        clock.t += 5
        rm.quest(333, 'Third', Z, 'x')
        self.assertTrue(rm.flush(5.0))
        with open(os.path.join(d, M.QUESTS), encoding='utf-8') as f:
            self.assertEqual(len(f.readlines()), 1)


class QuestsLast(unittest.TestCase):
    def test_its_last_battle_counted(self):
        # (review 2: the reading after a quest's boss battle is the next quest's - the battle was the old one's)
        d, clock = tempfile.mkdtemp(), Clock()
        rm = M.RouteMem(d, clock=clock)
        for _ in range(10):
            rm.quest(1, 'Boss', Z, 'Defeat the Boss')
            clock.t += 2.5
        clock.t += 240
        self.assertIn("the quest 'Boss' over - followed 4 min", rm.quest(2, 'Next', Z, 'x'))
        self.assertTrue(rm.flush(5.0))
        with open(os.path.join(d, M.QUESTS), encoding='utf-8') as f:
            q = json.loads(f.readline())
        self.assertGreater(q['s'], 260)
        self.assertGreater(q['span'], 260)


class Planner(unittest.TestCase):
    """the planner takes the warm way of two about as long - never a much longer one; walls stay walls and mobs as dear"""

    def setUp(self):
        import test_navroute as T
        self.T = T
        self.was = R.HEAT

    def tearDown(self):
        R.HEAT = self.was

    def side(self, heat, walls=((-150.0, 800.0, 150.0, 1200.0),)):
        R.HEAT = heat
        T = self.T
        f = T.field(geo=T.FlatGeo(walls=list(walls)))
        return T.crossing(T.route_pts(f, (0.0, 0.0)), 1000.0), f

    @staticmethod
    def warm(lo, hi):
        def heat(zone, x0, y0, nx, ny, cell):
            X = x0 + (np.arange(nx) + 0.5) * cell
            return np.repeat(((X > lo) & (X < hi)).astype(float)[None, :], ny, axis=0)
        return heat

    def test_warm_side_taken(self):
        self.assertIsNotNone(self.side(None)[0])
        self.assertGreater(self.side(self.warm(150, 400))[0], 150.0)
        self.assertLess(self.side(self.warm(-400, -150))[0], -150.0)

    @staticmethod
    def detour(off, n=3):
        """the route memory with n perfect walks round a detour off to the side (a mob once there) - from (0, 0) to
        (0, 2000) by (off, 700) and (off, 1300)"""
        d, clock = tempfile.mkdtemp(), Clock()
        rm = M.RouteMem(d, clock=clock)
        way = [(0, 0), (off, 700), (off, 1300), (0, 2000)]
        for _ in range(n):
            for a, b in zip(way, way[1:]):
                walk(rm, clock, a, b, target=(0.0, 2000.0, 0.0), zone='Test/Flat', ahead=None)
            rm.see('Test/Flat', (0.0, 2000.0, 0.0), NEXT, (0.0, 9000.0, 0.0))
            rm.leg = None
        rm.flush(5.0)
        return rm

    def test_a_much_longer_lane_isnt(self):
        # (review: walks once round a mob - a lane a fifth longer - kept the route on it after the mob had gone)
        for off in (500.0, 700.0):
            rm = self.detour(off)
            self.assertGreater(rm.heat01('Test/Flat', off - 10, 990.0, 1, 1, 20.0)[0, 0], 0.5)
            x, _ = self.side(rm.heat01, walls=())
            self.assertLess(abs(x), 100.0, off)
        # (a discount as big as the first one's - 25% - took it)
        was = R.HEAT_DISCOUNT
        try:
            R.HEAT_DISCOUNT = 0.25
            self.assertGreater(self.side(self.detour(500.0).heat01, walls=())[0], 300.0)   # (16% longer)
        finally:
            R.HEAT_DISCOUNT = was

    def test_discount_and_mobs_on_top(self):
        R.HEAT = lambda zone, x0, y0, nx, ny, cell: np.ones((ny, nx))
        f = self.T.field([(0.0, 1000.0, 0.0, None, True)], mob_near=300.0)
        self.assertAlmostEqual(f.cost[f.cell((0.0, 1000.0))], 1.0 - R.HEAT_DISCOUNT + R.MOB_COST)
        self.assertAlmostEqual(f.cost[f.cell((0.0, 1700.0))], 1.0 - R.HEAT_DISCOUNT)
        self.assertLessEqual(R.HEAT_DISCOUNT, 0.1)
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
            walk(rm, clock, (300, -500), (300, 2500), target=(300.0, 2500.0, 0.0), zone='Test/Flat')
            rm.see('Test/Flat', (300.0, 2500.0, 0.0), NEXT, (0.0, 9000.0, 0.0))
            rm.leg = None
        rm.flush(5.0)
        x, _ = self.side(rm.heat01)
        self.assertGreater(x, 150.0)


class HelperWiring(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(HERE, 'vision.py'), encoding='utf-8') as f:
            cls.src = f.read()
        with open(os.path.join(HERE, '..', 'Vision.ahk'), encoding='utf-8-sig') as f:
            cls.ahk = f.read().replace('\r\n', '\n')
        with open(os.path.join(HERE, '..', 'Autofarmer.ahk'), encoding='utf-8-sig') as f:
            cls.af = f.read().replace('\r\n', '\n')
        with open(os.path.join(HERE, '..', '..', 'AutoQuester', 'Walker.ahk'), encoding='utf-8-sig') as f:
            cls.wk = f.read()
        with open(os.path.join(HERE, '..', 'Settings.ahk'), encoding='utf-8-sig') as f:
            cls.st = f.read().replace('\r\n', '\n')

    def test_nav_reading_kept_before_the_route(self):
        s = self.src
        i = s.index('                    route_heat(q, r, goal)\n')
        self.assertLess(s.index("if q.get('avoid', '0') not in ('', '0'):\n                        near, cone = mob_avoid(q)"), i)
        self.assertLess(i, s.index('                    lines += route_lines(r, nm.game_dir, avoid, near, cone, arc_r, duels,'))
        self.assertIn("os.path.join(ROOT, 'routes', 'heat')", s)

    def test_route_heat_runs(self):
        # (the function itself, on a stand-in memory: a reading kept, the planner's heat set with heat=1 only)
        m = re.search(r"^def route_heat\(q, r, goal\):\n.*?\n\n\n", self.src, re.M | re.S)
        self.assertIsNotNone(m)
        seen, quests, logs = [], [], []

        class RM:
            heat01 = 'H'

            def see(self, *a, **k):
                seen.append((a, k))
                return 'said'

            def quest(self, *a):
                quests.append(a)
                return None
        ns = {'route_mem': RM, 'log': logs.append}
        exec(m.group(0), ns)
        was = R.HEAT
        try:
            r = {'zone': Z, 'pos': (0.0, 0.0, 0.0), 'goal': (0.0, 50.0, 0.0), 'quest': 7, 'goalid': 8, 'path': [(30.0, 40.0, 0.0)]}
            g = {'text': 'memory line', 'quest': 'Title', 'quest_id': 7, 'goal_id': 8}
            ns['route_heat']({'heat': '1', 'avoid': '1', 'goal': 'screen line'}, r, g)
            self.assertEqual(R.HEAT, RM.heat01)
            self.assertEqual(seen[-1], ((Z, (0.0, 0.0, 0.0), 'ids 7 8', (0.0, 50.0, 0.0)),
                                        {'clean': True, 'played': False, 'label': 'memory line',
                                         'ahead': 50.0 + math.sqrt(1000.0), 'there': False}))
            self.assertEqual(quests[-1], (7, 'Title', Z, 'memory line'))
            self.assertEqual(logs, ['said'])
            # (review 2: the memory's goal of the goal before - its ids not this reading's: no line, no title)
            ns['route_heat']({'avoid': '1', 'there': '1'}, r, dict(g, goal_id=7))
            self.assertEqual(seen[-1][1]['label'], '')
            self.assertTrue(seen[-1][1]['there'])
            self.assertEqual(quests[-1], (7, '', Z, ''))
            ns['route_heat']({'user': '1', 'goal': 'screen line'}, dict(r, goalid=None, path=None), None)
            self.assertIsNone(R.HEAT)
            self.assertEqual(seen[-1], ((Z, (0.0, 0.0, 0.0), '', (0.0, 50.0, 0.0)),
                                        {'clean': False, 'played': True, 'label': '', 'ahead': 50.0, 'there': False}))
            self.assertEqual(quests[-1], (7, '', Z, ''))
        finally:
            R.HEAT = was

    def test_map_shade(self):
        self.assertIn("    if not clear and zone:\n        heat_shade(img, zone, upp, ox, oy)\n    # the overlay, drawn big and shrunk", self.src)
        # (its pixels are render_navmap's at(): world x = (px + ox) * upp, y = -(py + oy) * upp)
        self.assertIn('gi = np.floor(((np.arange(w) + ox + 0.5) * upp - gx0) / routemem.CELL)', self.src)
        self.assertIn('gj = np.floor((-(np.arange(h) + oy + 0.5) * upp - gy0) / routemem.CELL)', self.src)

    def test_route_ask_args(self):
        a = self.ahk
        m = re.search(r'\nNavRouteArgs\(\)\n\t\{\n(.*?)\n\t\}\n', a, re.S)
        self.assertIsNotNone(m)
        body = m.group(1)
        self.assertIn('PlayerActedAt >= last', body)
        self.assertIn('NavHandsAt >= last', body)
        self.assertIn('(!HandsOffOn() && UserIdle() < 3000)', body)
        self.assertIn('(Stats.Has("routeheat") && !Stats["routeheat"] ? "" : "&heat=1") (played ? "&user=1" : "")', body)
        self.assertIn('. (IsSet(WkArrived) && WkArrived ? "&there=1" : "")', body)
        nr = a[a.index('\nNavRead('):]
        nr = nr[:nr.index('\n\t}\n')]
        # (with or without mob avoidance - a fight at the goal has it off)
        self.assertIn('\t\t}\n\t;(the route memory', nr)
        self.assertIn('\tif (withRoute)\n\t\tunblock .= NavRouteArgs()\n', nr)
        self.assertIn('\tif (withRoute && answer != "")\n\t\tNavRouteAt := A_TickCount\n', nr)
        self.assertIn('NavRouteAt := "", NavHandsAt := ""', a)
        self.assertIn('global NavRouteAt, NavHandsAt\n', a)
        self.assertNotIn('routeheat', a[a.index('\nNavMobArgs()'):a.index(";The route memory's arguments for a route ask")])
        # (the bot or its walking turned on: you may have walked him meanwhile)
        bt = self.af[self.af.index('\nBotToggle()'):]
        self.assertIn('NavHandsAt ; (v1 globals it sets)', bt[:bt.index('\n\t}\n')].split('\n')[3])
        self.assertIn('\t\tBotEverOn := 1\n\t\t;(the route memory: the wizard maybe walked by you while the bot was off - Vision.ahk NavRouteArgs)\n'
                      '\t\tNavHandsAt := A_TickCount\n', bt)
        wt = self.wk[self.wk.index('\nWalkToggle()'):]
        wt = wt[:wt.index('\n\t}\n')]
        self.assertIn('NavHandsAt, Refocus ; (v1 globals it sets)', wt)
        self.assertIn('NavUnblock := 1\n\t\t;(the route memory', wt)

    def test_setting(self):
        self.assertRegex(self.st, r'list\.Push\(V1Obj\(\{key: "routeheat", label: "\.\.\.prefer the ways that worked before", kind: "check", def: 1\n'
                                  r'\t\t, help: "[^"\n]*8% cheaper at most[^"\n]*"\}\)\)\n')


if __name__ == '__main__':
    unittest.main()
