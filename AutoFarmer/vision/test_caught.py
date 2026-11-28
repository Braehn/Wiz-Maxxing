"""test_caught.py - which mob started a battle (/caught, for MobGrow's self-tuning reach): the battle's start and its
mobs by the game's log, the duel circle's readings left out. Standard library + the helper's own (vision.py imports
on any system): python -m unittest test_caught  (from AutoFarmer\\vision)

2026-11-21 (JSHSRVRWINB): the bot asked /caught at 16 battles' first rounds and not one catch was taken - MobGrow never
ran, the mobs' reach was only ever widened by hand. The walker reads on (/nav, mob avoidance on) till the bot's first
round, so the trail's last readings were from inside the duel circle: the game walks the wizard and the mobs onto its
sigils, each 600 from its middle - the wizard and the mobs 1150 or so apart - "none (the nearest mob was ... away)".
What the game's log says (11-21 copies; the wizard's memory track el\\yaw2.txt): "MSG_Duel received N" the moment the
mob and the wizard meet (17:17:10: his track stopped that tenth of a second; 17:18: the walk onto his sigil began 0.07 s
before the line's second), then 1.6 s of the game walking him in a straight line onto his sigil, then "MSG_CombatAdd"
+ "AddNewParticipant player:<id>" for each. The bot reads the log late while it turns the wizard (seconds), so the line's
own HH:MM:SS is the start. Pins: the bot sends that stamp and the battle's mobs; the helper keeps the readings from
before it (less CAUGHT_CUT) - 3 s before it at most, else none (you playing, the bot waiting) -, picks the nearest of
those mobs and follows its run back - not its own walk (a patrol his way), 4 s at most - to the reading where it stood;
a battle with the quest's mob in it is the quest's; an older bot (no arguments) gets the old answer; a "none" is logged;
one catch raises the reach by 200 at most, 20 when you walked into it; a battle begun while you played (as noted when
it formed) or on a dungeon run isn't counted. The wizard walks 900 a second here, as in the game."""
import math
import os
import re
import sys
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from test_tray import ahk_code  # noqa: E402  (AutoHotkey lines without their comments)


def read(*parts):
    with open(os.path.join(HERE, *parts), encoding="utf-8-sig") as f:
        return f.read().replace("\r\n", "\n")


def code(src):
    """src's AutoHotkey code (test_tray's ahk_code): comment lines and /* */ blocks gone, each line cut at its ' ;' - a
    pinned line commented out is gone, not still there for assertIn and index"""
    return "".join(ln.rstrip() + "\n" for ln in ahk_code(src.split("\n")) if ln.strip())


def func(src, name):
    m = re.search(r"^" + name + r"\(.*?\n\t\}\n", src, re.M | re.S)
    assert m, name + " not found"
    return m.group(0)


RAIDER, RAIDER2, CRAB, BOSS = 2434195598596581669, 2434195598596581700, 77, 2428003149108915639
WIZ = 900.0     # (the wizard's own walk - the bot's "walks 906 a second at 1x")


def sim(t0, mob, cadence=0.25, run=1300.0, notice=1100.0, until=14.0, notice_at=1.0, away=False, mid=0.0):
    """(readings, the catch's time, where the Raider stood when it set off): a reading every cadence s - the wizard
    walking +x from 0 at WIZ; the Impi Raider standing at mob notices him within notice, from notice_at s on (once he's
    gone past it), and runs after him (run a second, facing him) - run 0: it never does, he walks into it (it stands on
    his way); away: it faces away from him till it runs; mid: its run begins that far into the reading interval after
    the one it noticed him at (the first step that much shorter); they meet (80 apart) - the battle; then the game walks both
    onto the circle's sigils (1150 apart, 850 a second) and they stand there. Readings (time, wizard (x, y, z), {gid:
    (name, x, y, z, yaw)}); a crab 900 off his path all along"""
    out, me, (rx, ry) = [], [0.0, 0.0, 0.0], mob
    caught = set_off = None
    k, ran = 0, 0
    while k * cadence <= until:
        t = k * cadence
        k += 1
        if caught is None:
            me[0] = WIZ * t
            d = math.hypot(me[0] - rx, me[1] - ry)
            # (it notices him at a reading - still standing there - and runs from the next)
            if set_off is not None and d > 80.0:
                ran += 1
                step = min(d - 60.0, run * cadence * ((1.0 - mid) if ran == 1 else 1.0))
                rx, ry = rx + (me[0] - rx) / d * step, ry + (me[1] - ry) / d * step
            if set_off is None and run and d <= notice and t >= notice_at:
                set_off = (t, (me[0], me[1]), (rx, ry))
            if math.hypot(me[0] - rx, me[1] - ry) <= 80.0 or (not run and me[0] >= rx - 60.0):
                caught = t - cadence / 2.0
                mid = ((me[0] + rx) / 2.0, (me[1] + ry) / 2.0 + 300.0)
                seats = ((mid[0], mid[1] - 600.0), (mid[0] + 150.0, mid[1] + 590.0))
        else:
            for who in (0, 1):
                cx, cy = (me[0], me[1]) if who == 0 else (rx, ry)
                tx, ty = seats[who]
                d = math.hypot(tx - cx, ty - cy)
                s = min(d, 850.0 * cadence)
                nx, ny = (cx + (tx - cx) / d * s, cy + (ty - cy) / d * s) if d > 0 else (cx, cy)
                if who == 0:
                    me[0], me[1] = nx, ny
                else:
                    rx, ry = nx, ny
        yaw = math.atan2(-(me[0] - rx), -(me[1] - ry))     # (facing the wizard: forward = (-sin yaw, -cos yaw))
        if away and not ran:
            yaw = math.atan2(-(rx - me[0]), -(ry - me[1]))  # (facing away from him)
        mobs = {RAIDER: ('Impi Raider', rx, ry, 0.0, yaw), CRAB: ('Crab', me[0], 900.0, 0.0, None)}
        if caught is not None:
            mobs[RAIDER2] = ('Impi Raider', seats[1][0] + 150.0, seats[1][1], 0.0, yaw)
        out.append((t0 + t, tuple(me), mobs))
    assert caught is not None
    return out, t0 + caught, set_off


class Helper(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import vision
        cls.V = vision
        cls.log = vision.log
        vision.log = lambda *a, **kw: None

    @classmethod
    def tearDownClass(cls):
        cls.V.log = cls.log

    def load(self, trail):
        self.V.MOB_TRAIL.clear()
        for e in trail:
            self.V.MOB_TRAIL.append(e)

    def setUp(self):
        self.V.MOBS_SHOWN.clear()

    def run_case(self, frac=0.5, cadence=0.25, mob=(300.0, 700.0), run=1300.0, battle=(RAIDER, RAIDER2)):
        """the case with the catch frac into its log line's second; (answer fields, the catch, set_off, began)"""
        base = math.floor(time.time()) - 40.0
        trail, caught, set_off = sim(base, mob, cadence, run)
        shift = (math.floor(caught) + frac) - caught      # (the catch frac into its second)
        trail = [(t + shift, me, mobs) for t, me, mobs in trail]
        caught += shift
        began = math.floor(caught)                        # (the line's HH:MM:SS: the second the catch was in)
        self.load(trail)
        now = caught + 6.0                                # (the first round seen)
        f = self.V.caught_line(now, began=began, battle=list(battle) if battle else None).split('|')
        return f, caught, set_off, began

    def test_old_answer_missed_it(self):
        # (what the 11-21 bot got: the circle's readings last - the wizard and the Raiders on their sigils)
        base = time.time() - 30.0
        trail, caught, _ = sim(base, (300.0, 700.0))
        self.load(trail)
        self.assertRegex(self.V.caught_line(caught + 6.0), r"^none \(the nearest mob was 1\d\d\d away\)$")

    def test_it_came_for_him(self):
        # (it noticed him and ran after him: caught, came, from where it set off - wherever in its second the catch fell,
        # at the walker's cadences)
        for cadence in (0.25, 0.4):
            for frac in (0.05, 0.5, 0.95):
                f, caught, set_off, began = self.run_case(frac, cadence)
                self.assertEqual((f[0], f[1], f[4]), ('caught', 'Impi Raider', '1'), (cadence, frac, f))
                d0 = math.hypot(set_off[1][0] - set_off[2][0], set_off[1][1] - set_off[2][1])
                self.assertAlmostEqual(float(f[2]), d0, delta=2.0, msg=(cadence, frac, f))
                self.assertLessEqual(float(f[3]), 25.0)               # (it faced him - a reading before: he walked on 225)

    def test_the_reading_where_it_stood(self):
        # (the distance at the reading before its first step - not one more back)
        f, caught, set_off, began = self.run_case(0.5, 0.25)
        t_set, me_set, mob_set = set_off
        # (set_off is the first reading within 800: it stood there, its first step comes after it)
        self.assertAlmostEqual(float(f[2]), math.hypot(me_set[0] - mob_set[0], me_set[1] - mob_set[1]), delta=2.0)

    def test_side_catch_facing(self):
        # (it faced away till it ran, its run begun between two readings: its facing from before it turned - behind it,
        # not in front: MobGrow raises mobbody for that)
        V = self.V
        for mid in (0.0, 0.5, 0.95):
            base = math.floor(time.time()) - 40.0
            trail, caught, _ = sim(base, (300.0, 700.0), away=True, mid=mid)
            self.load(trail)
            f = V.caught_line(caught + 6.0, began=math.floor(caught), battle=[RAIDER]).split('|')
            self.assertEqual((f[0], f[4]), ('caught', '1'), (mid, f))
            self.assertGreaterEqual(float(f[3]), 150.0, (mid, f))

    def test_he_walked_into_it(self):
        # (it never ran - stood on his path: came 0)
        f, caught, _, began = self.run_case(0.5, 0.25, mob=(2600.0, 0.0), run=0.0)
        self.assertEqual((f[0], f[4]), ('caught', '0'), f)

    def test_circle_readings_not_used(self):
        # (readings from CAUGHT_CUT before the start's second on - the walk onto the sigils, the circle - aren't used,
        # however near the mob looks in them)
        V = self.V
        base = math.floor(time.time()) - 40.0
        trail, caught, _ = sim(base, (300.0, 700.0))
        began = math.floor(caught)
        cut = [e for e in trail if e[0] < began - V.CAUGHT_CUT]
        fake = (began - 0.1, cut[-1][1], {RAIDER: ('Impi Raider', cut[-1][1][0] + 30.0, 0.0, 0.0, None)})
        self.load(cut + [fake] + [e for e in trail if e[0] >= began])
        self.assertEqual(V.caught_line(caught + 6.0, began=began, battle=[RAIDER]).split('|')[0:2], ['caught', 'Impi Raider'])
        self.load(cut)
        a = V.caught_line(caught + 6.0, began=began, battle=[RAIDER])
        self.load(cut + [fake] + [e for e in trail if e[0] >= began])
        self.assertEqual(V.caught_line(caught + 6.0, began=began, battle=[RAIDER]), a)

    def test_only_the_battle_mobs(self):
        # (a crab nearer than the Raider just before the battle: not the battle's - not taken; no ids: the nearest)
        V = self.V
        base = math.floor(time.time()) - 40.0
        trail, caught, _ = sim(base, (300.0, 700.0))
        began = math.floor(caught)
        trail = [(t, me, {**mobs, CRAB: ('Crab', me[0] + 20.0, -20.0, 0.0, None)}) for t, me, mobs in trail]
        self.load(trail)
        self.assertEqual(V.caught_line(caught + 6.0, began=began, battle=[RAIDER]).split('|')[1], 'Impi Raider')
        self.assertEqual(V.caught_line(caught + 6.0, began=began).split('|')[1], 'Crab')

    def test_quest_battle(self):
        # (the quest's boss in the battle, its add the nearer: the quest's battle all the same)
        self.V.MOBS_SHOWN.update(quest={BOSS}, at=time.time())
        f = self.run_case(battle=(RAIDER, BOSS))[0]
        self.assertEqual((f[1], f[6]), ('Impi Raider', '1'), f)
        self.assertEqual(self.run_case(battle=(RAIDER,))[0][6], '0')
        # (the split from a minute before the first round - you played the battle's start, no /nav since: still it)
        self.V.MOBS_SHOWN.update(quest={BOSS}, at=time.time() - 60.0)
        self.assertEqual(self.run_case(battle=(RAIDER, BOSS))[0][6], '1')

    def test_start_unreadable(self):
        # (the battle's mobs sent, its start not readable: none - not the old answer off the circle's readings)
        base = time.time() - 30.0
        trail, caught, _ = sim(base, (300.0, 700.0))
        self.load(trail)
        self.assertEqual(self.V.caught_line(caught + 6.0, battle=[RAIDER]), "none (the battle's start couldn't be read)")
        src = read("vision.py")
        self.assertIn("if began is None and q.get('began', '') != '':\n"
                      "                    return self.reply(\"none (the battle's start couldn't be read: \"", src)

    def test_nothing_just_before(self):
        # (the readings stop 8 s before the catch - you took the keyboard, the bot waited, the game behind another
        # window - with the mob 400 off then: none, not that reading taken as the catch)
        V = self.V
        base = math.floor(time.time()) - 40.0
        trail = [(base, (0.0, 0.0, 0.0), {RAIDER: ('Impi Raider', 400.0, 0.0, 0.0, None)})]
        self.load(trail)
        a = V.caught_line(base + 14.0, began=base + 8.0, battle=[RAIDER])
        self.assertTrue(a.startswith('none (no mobs read just before the battle began'), a)
        trail, caught, _ = sim(base, (300.0, 700.0))
        self.load(trail)
        a = V.caught_line(caught + 6.0, began=math.floor(caught), battle=[12345])
        self.assertEqual(a, "none (the battle's mobs weren't among the mobs read just before it began)")

    def test_far(self):
        V = self.V
        base = math.floor(time.time()) - 40.0
        trail = [(base + k * 0.25, (0.0, 0.0, 0.0), {RAIDER: ('Impi Raider', 1600.0, 0.0, 0.0, None)}) for k in range(8)]
        self.load(trail)
        a = V.caught_line(base + 9.0, began=base + 2.0, battle=[RAIDER])
        self.assertRegex(a, r"^none \(the nearest of the battle's mobs was 1600 away \d\.\d s before it began\)$")

    def test_its_own_walk_not_followed_back(self):
        # (a mob walking its rounds straight at the waiting wizard - 80 a second from 1400 off - notices him at 500 and
        # runs: from 500, not 1400)
        V, out, mx = self.V, [], -1400.0
        base = math.floor(time.time()) - 40.0
        k = 0
        while mx < -80.0:
            out.append((base + k * 0.25, (0.0, 0.0, 0.0), {RAIDER: ('Impi Raider', mx, 0.0, 0.0, -math.pi / 2)}))
            mx += (80.0 if mx < -500.0 else 500.0) * 0.25
            k += 1
        self.load(out)
        f = V.caught_line(out[-1][0] + 6.0, began=math.floor(out[-1][0] + 0.5), battle=[RAIDER]).split('|')
        self.assertEqual((f[0], f[4]), ('caught', '1'), f)
        self.assertLess(float(f[2]), 560.0, f)
        self.assertGreater(float(f[2]), 450.0, f)

    def test_run_followed_back_4_s_at_most(self):
        # (a mob running at the waiting wizard from 3000 off, 300 a second: followed back 4 s at the most - 1200 or so)
        V, out, mx = self.V, [], -3000.0
        base = math.floor(time.time()) - 40.0
        k = 0
        while mx < -80.0:
            out.append((base + k * 0.25, (0.0, 0.0, 0.0), {RAIDER: ('Impi Raider', mx, 0.0, 0.0, -math.pi / 2)}))
            mx += 300.0 * 0.25
            k += 1
        self.load(out)
        f = V.caught_line(out[-1][0] + 6.0, began=math.floor(out[-1][0] + 0.5), battle=[RAIDER]).split('|')
        self.assertEqual((f[0], f[4]), ('caught', '1'), f)
        self.assertLess(float(f[2]), 1500.0, f)
        self.assertGreater(float(f[2]), 1000.0, f)

    def test_args(self):
        V = self.V
        now = time.time()
        stamp = time.strftime('%m/%d/%y %H:%M:%S', time.localtime(now - 5.0))
        self.assertAlmostEqual(V.caught_began(stamp, now), math.floor(now - 5.0), delta=1.0)
        for bad in ('', 'x', '11/21/26', None, '13/40/26 25:00:00',
                    time.strftime('%m/%d/%y %H:%M:%S', time.localtime(now - 3600.0))):
            self.assertIsNone(V.caught_began(bad, now), bad)
        self.assertEqual(V.caught_ids('2434195598596581669,2434195598596581700'), [RAIDER, RAIDER2])
        self.assertEqual(V.caught_ids(' 5, x,,6'), [5, 6])
        self.assertIsNone(V.caught_ids(''))
        self.assertIsNone(V.caught_ids(None))
        src = read("vision.py")
        self.assertIn("return self.reply(caught_line(began=began, battle=caught_ids(q.get('mobs', ''))))", src)
        self.assertIn("/caught[?began=stamp&mobs=gid,gid]", src)
        self.assertNotIn("caught_pulled", src)


class BotSide(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # (comments gone: a pinned line commented out - the /caught request, the MobGrow call - fails its pin)
        cls.es = code(read("..", "EnemySpells.ahk"))
        cls.vis = code(read("..", "Vision.ahk"))
        cls.af = code(read("..", "Autofarmer.ahk"))

    def test_log_lines_reach_it(self):
        bl = func(self.es, "BattleLogLine")
        self.assertIn('if (!InStr(blLine, "Combat") && !InStr(blLine, "Subcircle") && !InStr(blLine, "AddNewParticipant") '
                      '&& !InStr(blLine, "MSG_Duel received") && !InStr(blLine, "MSG_EndDuel"))\n\t\treturn\n', bl)
        # (before any of BattleLogLine's own returns)
        i = bl.index("BattleLogStart(blLine)")
        self.assertLess(i, bl.index('if (InStr(blLine, "MSG_CombatFlee"))'))
        self.assertEqual(bl[:i].count("return"), 1)

    def test_start_parser(self):
        bs = func(self.es, "BattleLogStart")
        self.assertIn('RegExMatch(blLine, "AddNewParticipant player:(\\d+)", &bsM)', bs)
        self.assertIn('RegExMatch(blLine, "Duel (?:received )?(\\d+):", &bsN)', bs)
        self.assertIn('bsAfresh := !IsObject(bsS) || bsS.over || (!bsS.me && A_TickCount - bsS.last > 15000)', bs)
        self.assertRegex(bs, r'if \(InStr\(blLine, "MSG_Duel received " bsD ":"\)\)\n\t\t\{\n\t\tif \(bsAfresh\)\n'
                             r'\t\t\tbsS := BattleLogStartNew\(bsD, A_TickCount, SubStr\(blLine, 1, 17\)\)')
        self.assertIn('bsS := BattleLogStartNew(bsD, 0)', bs)
        self.assertIn('bsS.me := 1, bsS.addAt := A_TickCount', bs)
        # (the template rule as battlerec.py's TEMPLATE_RX)
        rx = re.search(r'TEMPLATE_RX = re\.compile\(r"(.*?)"\)', read("battlerec.py")).group(1)
        self.assertIn('RegExMatch(bsM[1], "' + rx + '")', bs)
        self.assertIn('(?:MSG_CombatMatchResult|MSG_CombatRemove\\(Local Player\\)|MSG_EndDuel)', bs)
        new = func(self.es, "BattleLogStartNew")
        self.assertIn('BattleLogStartNew(bsD, duelAt, stamp := "")', new)
        self.assertIn('duelAt: duelAt, duelStamp: stamp, actedAt: IsSet(PlayerActedAt) ? PlayerActedAt : ""', new)
        self.assertIn('global BlOutDuel := "", BlStarts := "", BlAddPend := ""', self.es)
        last = func(self.es, "BattleLogLastStart")
        self.assertIn("blsV.me && blsV.addAt && A_TickCount - blsV.addAt < withinMs", last)
        # (the stamp: the log line's first 17 characters - battlerec.py's stamp_of reads the same "MM/DD/YY HH:MM:SS")
        self.assertIn('s = line[:17]', read("battlerec.py"))

    def test_caughtlog_sends_and_says(self):
        cl = func(self.vis, "CaughtLog")
        self.assertIn('clS := BattleLogLastStart(60000)', cl)
        self.assertIn('if (clS.wizBefore && !(IsSet(CarryOn) && CarryOn))', cl)
        self.assertIn('if (!clS.duelAt || clS.duelStamp = "" || clS.addAt - clS.duelAt > 10000)', cl)
        self.assertEqual(cl.count('DebugLog("  Caught: not counted - '), 2)
        self.assertIn('clArgs := "?began=" NavUri(clS.duelStamp) (clIds != "" ? "&mobs=" clIds : "")', cl)
        self.assertIn('clPlay := (clS.actedAt != "" && clS.actedAt >= clS.duelAt - 5000) || (PlayerActedAt != "" && PlayerActedAt > clS.duelAt)', cl)
        self.assertIn('a := VisionGet("/caught" clArgs, 600, true)', cl)
        self.assertRegex(cl, r'DebugLog\("  Caught: who started the battle not known - "')
        self.assertLess(cl.index("who started the battle not known - \" (clWhy"), cl.index("MobGrow(f, s, clPlay)"))

    def test_mobgrow(self):
        mg = func(self.vis, "MobGrow")
        self.assertIn("MobGrow(f, s, playing := 0)", mg)
        self.assertIn(': (PlayerActive || playing) ? "you were playing" : ""', mg)
        self.assertIn(': IsObject(DgRun) ? "a dungeon run - its fights walked into on purpose" :', mg)
        self.assertRegex(mg, r"mgTo := Min\(1500, Max\(mgWas \+ 20, Min\(mgDist \+ 25, mgWas \+ 200\)\)\)\n"
                             r"\tif \(V1At\(f, 5\) != 1\)\n\t\tmgTo := Min\(1500, mgWas \+ 20\)\n")
        pa = func(self.af, "PlayerActing")
        self.assertIn("global PlayerActive, PlayerActedAt", pa)
        self.assertRegex(pa, r"PlayerActive := acting\n\tif \(acting\)\n\t\tPlayerActedAt := A_TickCount\n")
        self.assertIn('global PlayerActive := 0, PlayerActedAt := "",', self.af)


if __name__ == "__main__":
    unittest.main()
