"""test_zone_mobs.py - just into a zone, the walker waits for the new zone's mobs to be read (navmem's objects thread woken
for a fresh look at the heap, /nav's mobscan line, Walker.ahk's hold). Standard library only (navmem needs numpy, as the
helper does): python -m unittest test_zone_mobs  (from AutoFarmer\\vision)

2026-11-21 (JSHSRVRWINB): the walker set off into Zamunda 1-2 s after its loading screen; the helper looks at the whole
heap for a zone's objects only every few seconds (2-5 s a look, the mobs coming after the screen), so the route had no
mobs in it - "nothing in the way" - and an Impi Raider caught the wizard 3 times out of 4 entries (08:09, 08:22, 16:53;
the 16:53 one entered at 1 health, the knockout that set off the collect incident). Pins: from the loading screen's end (or
Reconnect's back in the world) the walker holds still; once the game's memory has the zone the log names, it asks for a
fresh look half a second on and walks once one begun after that is in (8 s at most, an older helper not waited for); the
hold is a wait to the stuck watch; the helper's thread is woken for the look at once and says how old its last one is.
(Review: a look asked at the log's ConnectComplete scanned the old zone's ClientZone; the stuck watch ran on through the
hold; a relaunch's entry had no hold; the 8 s line was said with no hold.)"""
import os
import re
import sys
import threading
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def read(*parts):
    with open(os.path.join(HERE, *parts), encoding="utf-8-sig") as f:
        return f.read().replace("\r\n", "\n")


def func(src, name):
    m = re.search(r"^" + name + r"\(.*?\n\t\}\n", src, re.M | re.S)
    assert m, name + " not found"
    return m.group(0)


def pyfunc(src, name):
    m = re.search(r"^(\s*)def " + name + r"\(.*?(?=\n\1(?:def |class |\S)|\Z)", src, re.M | re.S)
    assert m, name + " not found"
    return m.group(0)


class HelperSide(unittest.TestCase):
    def test_scan_age_and_wake(self):
        # (the real navmem.py, under a name of its own - other tests leave stand-ins for "navmem" in sys.modules)
        import importlib.util
        if HERE not in sys.path:
            sys.path.insert(0, HERE)
        spec = importlib.util.spec_from_file_location("navmem_zone_mobs_test", os.path.join(HERE, "navmem.py"))
        N = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(N)
        except ImportError as e:            # (numpy - the helper's own)
            self.skipTest("navmem can't be imported here (%s)" % e)
        nm = N.NavMem(log=lambda m: None)
        try:
            self.assertIsNone(nm.mobs_scan_age("A/Zone"), "no look finished yet: None")
            with nm.lock:
                nm._obj_zone_name, nm._obj_full_began = "A/Zone", time.monotonic() - 1.5
            self.assertAlmostEqual(nm.mobs_scan_age("A/Zone"), 1.5, delta=0.3)
            self.assertIsNone(nm.mobs_scan_age("Another/Zone"), "the objects thread on another zone: None")
            self.assertIsNone(nm.mobs_scan_age(None))
            # (asked for: wanted, the thread woken - the event set - and started if it wasn't)
            nm.want_full_scan()
            with nm.lock:
                self.assertTrue(nm._obj_full_want or nm._obj_thread is not None)
                self.assertIsInstance(nm._obj_thread, threading.Thread)
        finally:
            nm.close()

    def test_objects_thread(self):
        src = read("navmem.py")
        run = pyfunc(src, "_objects_run")
        # (a look at the whole heap when one is wanted - the flag taken under the lock)
        self.assertRegex(run, r"want, self\._obj_full_want = self\._obj_full_want, False\n\s+full = \(want or regions is None")
        # (a new zone: no finished look at it yet)
        self.assertRegex(run, r"self\._obj_zone_name, self\._obj_full_began = zone\[1\], 0\.0")
        # (a full look finished: when it began - for this zone)
        self.assertRegex(run, r"if full:\n\s+with self\.lock:\n\s+if self\._obj_zone_name == zone\[1\]:\n\s+self\._obj_full_began = t0")
        self.assertLess(run.index('self._set_objs(cz, objs, "", items, doors, duels)'), run.index("self._obj_full_began = t0"))
        # (its wait cut short by want_full_scan)
        self.assertIn("self._obj_wake.wait(max(0.5, OBJ_QUICK - (time.monotonic() - t0)))\n            self._obj_wake.clear()", run)
        self.assertNotIn("time.sleep(max(0.5, OBJ_QUICK", run)

    def test_nav_answer(self):
        src = read("vision.py")
        self.assertIn("lines.append(mobscan_line(nm.mobs_scan_age(r.get('zone'))))", src)
        i = src.index("if q.get('freshmobs', '0') not in ('', '0'):\n                            nm.want_full_scan()")
        self.assertLess(src.index("if q.get('avoid', '0') not in ('', '0'):"), i)
        self.assertLess(i, src.index("lines.append(mobscan_line("))
        ns = {}
        exec(pyfunc(src, "mobscan_line"), ns)
        self.assertEqual(ns["mobscan_line"](None), "mobscan|-1")
        self.assertEqual(ns["mobscan_line"](2.345), "mobscan|2.3")
        self.assertIn("mobscan|s            (only with route=1&avoid=1", src)


class WalkerSide(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.vis = read("..", "Vision.ahk")
        cls.w = read("..", "..", "AutoQuester", "Walker.ahk")

    def test_navread(self):
        nr = func(self.vis, "NavRead")
        self.assertIn('NavRead(timeoutMs := 150, withPath := false, withRoute := false, avoidMobs := false, goalLine := "", freshMobs := false)', nr)
        self.assertIn('(freshMobs ? "&freshmobs=1" : "")', nr)
        self.assertIn('noplace: "", noplaceheld: "", mobscan: ""})', nr)
        self.assertRegex(nr, r'else if \(V1At\(f, 1\) = "mobscan" && withRoute && avoidMobs\)\n\t+nav\.mobscan := NavNum\(V1At\(f, 2\)\)')

    def test_walknav_holds_till_read(self):
        wn = func(self.w, "WalkNav")
        self.assertIn('WkNavRel := "", WkMobHold := 0', wn)
        self.assertLess(wn.index("WkMobHold := 0"), wn.index('if (!V1IsFunc("NavRead") || inbattle)'))
        # (the arrival: the later of the log's loading screen over and Reconnect's back in the world - a relaunch too)
        self.assertRegex(wn, r'msKey := WkLoadedAt\n\tif \(V1IsFunc\("RcBackAgo"\)\)\n\t\t\{\n\t\tmsBack := %"RcBackAgo"%\.Call\(\)\n'
                             r'\t\tif \(msBack != "" && A_TickCount - msBack > msKey\)\n\t\t\tmsKey := A_TickCount - msBack')
        self.assertIn('msOn := avoidMobs && msSince != "" && msSince < MobScanWait && WkMobScanDone != msKey', wn)
        self.assertIn("if (msOn && WkMobKey != msKey)\n\t\tWkMobKey := msKey, WkMobArriveAt := 0", wn)
        # (the fresh look asked half a second after the memory has the log's zone - not the old zone's ClientZone)
        self.assertIn("msFresh := msOn && WkMobArriveAt && A_TickCount - WkMobArriveAt >= 500 && WkMobScanAsked != msKey", wn)
        self.assertIn('nav := %"NavRead"%.Call(150, false, NavRoute, avoidMobs, WalkGoalLine, msFresh)', wn)
        m = re.search(r'if \(msOn && IsObject\(nav\) && nav\.mobscan != ""\)\n\t\t\{\n(?:\t\t;[^\n]*\n)*'
                      r'\t\tif \(!WkMobArriveAt && nav\.zone != "" && WalkSameZone\(nav\.zone, WalkZone\(true\)\)\)\n\t\t\tWkMobArriveAt := A_TickCount\n'
                      r'\t\tif \(WkMobArriveAt && nav\.mobscan >= 0 && nav\.mobscan < \(A_TickCount - WkMobArriveAt\) / 1000 - 0\.4\)\n'
                      r'\t\t\tWkMobScanDone := msKey, WalkLog\(.*\)\n\t\telse\n\t\t\tWkMobHold := 1, WkMobHeldFor := msKey\n\t\t\}\n'
                      r'\telse if \(avoidMobs && msSince != "" && msSince >= MobScanWait && WkMobHeldFor = msKey && WkMobScanDone != msKey\)', wn)
        self.assertIsNotNone(m, "held till a look begun after the zone is in memory is in - MobScanWait at most; the cap said only after a hold")

    def test_step_holds(self):
        ws = func(self.w, "WalkStep")
        nav = ws.index('WalkNav(fair && A_TickCount - WkTurnAt > WalkSettle() + 150 ? h : "", fair ? dist : "")')
        m = re.search(r'\n\tif \(WkMobHold\)\n\t\t\{\n(?:\t\t;[^\n]*\n)*'
                      r'\t\tif \(WkArrived = 2 \|\| WkArrived = 3\)\n\t\t\t\{\n'
                      r'\t\t\tWalkLog\(\(WkArrived = 3 \? "push" : "talk"\) ": through the way out - [^\n]*"\)\n'
                      r'\t\t\tif \(WkArrived = 2 && WkDialog\)\n\t\t\t\tWkQuietUntil := A_TickCount \+ DialogQuiet, WkQuietLogged := 0\n'
                      r'\t\t\tWalkReset\(\)\n\t\t\tWkLoadAt := A_TickCount, WkSeenAt := 0, WkLastDist := ""\n\t\t\t\}\n'
                      r'\t\tif \(KeysDown \|\| HeldW\)\n\t\t\tReleaseKeys\(true\)\n\t\tSetStatus\("waiting - [^\n]*"\)\n'
                      r'\t\tWkBestTime := A_TickCount, WkLastRead := A_TickCount, WkTries := 0\n\t\tSleep\(100\)\n\t\treturn true\n\t\t\}\n', ws)
        self.assertIsNotNone(m, "a wait: keys let go with the speed kept, the stuck watch's clocks kept; a push through a way "
                                "out over (2026-11-21 20:18: it went on into the next zone and 'arrived' short of the goal)")
        # (WalkReset: the push's and the talk's state - and the old zone's best distance - not the hold's own)
        wr = func(self.w, "WalkReset")
        for k in ("WkBestDist := \"\"", "WkArrived := 0", "WkPushes := 0", "WkStraight := 0"):
            self.assertIn(k, wr)
        self.assertNotIn("WkMob", wr)
        self.assertLess(nav, m.start())
        # (before any walking, turning, arriving or collecting)
        for later in ("if (WkArrived = 7)", "CollectCheck(dist)"):
            self.assertLess(m.start(), ws.index(later))

    def test_reset_and_blank(self):
        self.assertRegex(self.w, r"(?m)^global WkMobHold, WkMobScanAsked, WkMobScanDone, MobScanWait, WkMobKey, WkMobArriveAt, WkMobHeldFor$")
        reset = "WkMobHold := 0, WkMobScanAsked := 0, WkMobScanDone := 0, MobScanWait := 8000, WkMobKey := 0, WkMobArriveAt := 0, WkMobHeldFor := 0"
        self.assertIn("\t" + reset + "\n", self.w)
        self.assertIn("\tglobal " + reset + "\n", self.w)


if __name__ == "__main__":
    unittest.main()
