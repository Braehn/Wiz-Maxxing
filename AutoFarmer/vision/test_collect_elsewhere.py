"""test_collect_elsewhere.py - a fight goal isn't collected away from where the game's memory has it (the walker's
text read, not run). Standard library only: python -m unittest test_collect_elsewhere  (from AutoFarmer\\vision)

2026-11-21 16:54:40 (JSHSRVRWINB): knocked out, the arrow hidden 3 s while the wizard came back - the walker's no-arrow
rule (CollectNoPlace, 2 s with nothing standing in) took 'Defeat Shaka Zebu in Zamunda' for a goal the game shows no way
to and started collecting it in Zamunda Outskirts, though the game's memory had just said the goal was 2 zone changes away.
Collecting a fight goal walks into monsters on purpose (no mob avoidance) and "same goal as before" kept it up after every
battle: the bot walked into every Jackal Bandit and Impi Raider there and was knocked out again and again ("it walks right
into enemies"). Pins: a fight goal isn't taken up by the no-arrow rule while the memory places it (another zone or a place
here); collecting a fight goal the memory has in another zone - or, taken up with no way to it, a place now - stops and
follows the way there."""
import os
import re
import sys
import unittest

if os.path.dirname(os.path.abspath(__file__)) not in sys.path:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from test_tray import ahk_code  # noqa: E402  (AutoHotkey lines without their comments)

WALKER = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "AutoQuester", "Walker.ahk"))


def code(src):
    """src's AutoHotkey code (test_tray's ahk_code): comment lines and /* */ blocks gone, each line cut at its ' ;' - a
    pinned line commented out is gone, not still there for assertIn and index (fix2, x-tests-2)"""
    return "".join(ln.rstrip() + "\n" for ln in ahk_code(src.split("\n")) if ln.strip())


def read():
    """Walker.ahk's code (code: its comments gone)"""
    with open(WALKER, encoding="utf-8-sig") as f:
        return code(f.read().replace("\r\n", "\n"))


def func(src, name):
    m = re.search(r"^" + name + r"\(.*?\n\t\}\n", src, re.M | re.S)
    assert m, name + " not found"
    return m.group(0)


class CollectElsewhere(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.w = read()

    def test_no_arrow_rule_waits_for_the_memory(self):
        np = func(self.w, "CollectNoPlace")
        kinds = np.index('(cnpKind != "fight" && !WkNavNoPlace))\n\t\treturn false')
        m = re.search(r'\n\tif \(cnpKind = "fight" && !WkNavNoPlace && CollectPlacedByMem\(\)\)\n\t\treturn false', np)
        self.assertIsNotNone(m, "a fight goal the memory places isn't taken up for 'no way to it'")
        self.assertLess(kinds, m.start())
        # (before anything is set up for collecting)
        self.assertLess(m.start(), np.index("WkCollect := V1Obj("))
        self.assertLess(m.start(), np.index("StartCollect("))

    def test_placed_by_memory(self):
        p = func(self.w, "CollectPlacedByMem")
        self.assertIn('return IsObject(WkNavLast) && (V1Gt(WkNavLast.hops, 0) || (WkNavLast.noplace = 0 && WkNavLast.noplace != ""))', p)
        # (WkNavLast: the last reading the helper answered - a global the walker keeps, reset with the walk)
        self.assertRegex(self.w, r"(?m)^global .*\bWkNavLast\b")
        self.assertIn("WkNavLast := nav", func(self.w, "WalkNav"))

    def test_elsewhere(self):
        """this step's usable memory reading has the goal in another zone - for the same goal, or ids not known"""
        e = func(self.w, "CollectElsewhere")
        self.assertIn('return !WkNavNoPlace && WkNavOk && IsObject(WkNavObj) && V1Gt(WkNavHops, 0)\n'
                      '\t\t&& (goalid = "" || WkNavObj.goalid = "" || goalid "|" = WkNavObj.goalid "|")', e)

    def test_arrival_doesnt_collect_a_goal_elsewhere(self):
        """(review 2026-11-21: arrival-time collecting at a way out that doesn't load, the goal a zone on - CollectCheck took it
        up, CollectStep dropped it, for ever, no notice) - neither taken up nor carried on there: the walk's own wait"""
        cc = func(self.w, "CollectCheck")
        drop = re.search(r'\n\tif \(IsObject\(WkCollect\) && !WkCollect\.gaveUp && \(ccMode = "" \|\| ccMode = "fight"\) '
                         r'&& CollectElsewhere\(WkCollect\.goalid\)\)\n\t\t\{\n(.*?)\n\t\t\}\n', cc, re.S)
        self.assertIsNotNone(drop)
        self.assertIn('WkCollect := ""', drop.group(1))
        self.assertNotIn("return", drop.group(1))
        self.assertLess(drop.start(), cc.index("going := IsObject(WkCollect)"))
        new = cc.index('\tif (ccKind = "fight" && CollectElsewhere(CollectGoalId()))\n\t\treturn false\n')
        self.assertLess(cc.index('if (ccKind != "fight" && ccKind != "use")'), new)
        self.assertLess(new, cc.index("WkCollect := V1Obj("))

    def test_collecting_stops_when_the_goal_is_elsewhere(self):
        cs = func(self.w, "CollectStep")
        m = re.search(r'\n\tif \(csKind = "fight" && \(CollectElsewhere\(WkCollect\.goalid\) \|\| \(WkCollect\.noPlace && !WkNavNoPlace '
                      r'&& WkNavOk && IsObject\(WkNavObj\)\n'
                      r'\t\t&& \(WkCollect\.goalid = "" \|\| WkNavObj\.goalid = "" \|\| WkCollect\.goalid "\|" = WkNavObj\.goalid "\|"\)\n'
                      r'\t\t&& WkNavObj\.noplace = 0 && WkNavObj\.tx != ""\)\)\)\n'
                      r'\t\t\{\n(.*?)\n\t\t\}\n', cs, re.S)
        self.assertIsNotNone(m)
        body = m.group(1)
        for want in ('WkCollect := ""', 'WalkNotifyClose("collect")', "ReleaseKeys()", "WalkReset()", "return true"):
            self.assertIn(want, body)
        self.assertLess(body.index('WkCollect := ""'), body.index("WalkReset()"))
        # (after the goal-changed check, before any monster is walked into or the area roamed)
        self.assertLess(cs.index("if (CollectGoalChanged(text))"), m.start())
        self.assertLess(m.start(), cs.index("CollectItemStep"))
        self.assertLess(m.start(), cs.index("A_TickCount - WkCollect.progressAt > CollectStall"))

    def test_knockouts_counted_at_the_last_goal_line(self):
        """(review 2026-11-21: the knockout guard keyed a knockout with the goal line blank - a battle, a loading screen - by
        'somewhere in <zone>': one goal's six knockouts under four keys, its stop at 3 never reached) - the last line that
        wasn't blank then"""
        gl = func(self.w, "WalkGoalLine")
        self.assertRegex(gl, r'WkGoalLine := text\n\tif \(text != ""\)\n\t\tWkGoalSeen := text\n\treturn text')
        self.assertIn("\tglobal WkGoalLineAt, WkGoalFrom, WkGoalLine, WkGoalSeen\n", gl)
        self.assertRegex(self.w, r"(?m)^global WkGoalSeen$")
        self.assertRegex(self.w, r'(?m)^\tglobal WkGoalSeen := ""$')
        es = os.path.join(os.path.dirname(WALKER), "..", "AutoFarmer", "EnemySpells.ahk")
        with open(es, encoding="utf-8-sig") as f:
            ko = func(f.read().replace("\r\n", "\n"), "KoNote")
        seen = ko.index('if (koG = "" && IsSet(WkGoalSeen))\n\t\tkoG := Trim(WkGoalSeen)')
        self.assertLess(ko.index(': Trim(WkGoalLine)'), seen)
        self.assertLess(seen, ko.index('koG := "somewhere in "'))

    def test_fight_collecting_still_walks_into_mobs(self):
        """(unchanged: collecting a fight goal there - at its arrival - turns mob avoidance off; the fix only keeps it from
        starting, or going on, elsewhere)"""
        nav = func(self.w, "WalkNav")
        self.assertIn('&& !(WkArrived = 7 && !(IsObject(WkCollect) && WkCollect.kind != "" && WkCollect.kind != "fight"))', nav)


if __name__ == "__main__":
    unittest.main()
