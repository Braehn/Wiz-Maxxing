"""test_fix2_last.py - the 2026-11-27 review's last repair pass: the changes the groups needed in files they didn't own,
and what the rechecks and the whole-diff review still found (the AHK sources read, not run - test_tray's ahk_code drops
their comments; vision.py's /readers run). Standard library only:
python -m unittest test_fix2_last  (from AutoFarmer\\vision)

Pins: the game's log read quietly in both bot-off waits (the main loop's and the AFK hold's - ReconnectOff); the refocus
watch kept on with walking on and the bot off (F6); every right-click discard and the Flee button's second click only on
the game's own window (GameUnderMouse); a talk at the goal whose prompt panel couldn't be read presses no X; the 1x key
sent at most 3 times in a row for a wizard still turning sped up, then the walking key left alone for the run and you told;
the walker's X paths go by WalkPromptCrowns, not "crown" anywhere on the panel; the dungeon's, the party ride's and the
carry's Crowns looks read the goal line first; the helper's /readers and the dashboard's note from it; /bag's unread field
read and not called Crown-shop gear; the carry's own FleeCheck counts; VisionStart takes only its own helper's /ping."""
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from test_tray import ahk_code  # noqa: E402  (AutoHotkey lines without their comments)

ROOT = os.path.dirname(os.path.dirname(HERE))


def code(*parts):
    """an AutoHotkey file's code: comment lines and /* */ blocks gone, each line cut at its ' ;', blank lines gone"""
    with open(os.path.join(ROOT, *parts), encoding="utf-8-sig") as f:
        text = f.read().replace("\r\n", "\n")
    return "".join(ln.rstrip() + "\n" for ln in ahk_code(text.split("\n")) if ln.strip())


def func(src, name):
    m = re.search(r"^" + name + r"\(.*?\n\t\}\n", src, re.M | re.S)
    assert m, name + " not found"
    return m.group(0)


class BotOffLogRead(unittest.TestCase):
    def test_both_off_waits_read_the_log_quietly(self):
        af = code("AutoFarmer", "Autofarmer.ahk")
        # (the main loop's off branch - in both off cases, standby's too - and the AFK hold's)
        main = af[af.index('MouseLockRelease("the bot\'s off")\n\t\tif (BotStandby && !BotEverOn)'):]
        main = main[:main.index("\t\tcontinue\n")]
        self.assertRegex(main, r"\}\n\t\tif \(!GameInTray\)\n\t\t\tReconnectOff\(\)\n\t\tSleep\(300\)\n$")
        hold = af[af.index('the hold waits till it\'s on again")'):]
        hold = hold[:hold.index("continue\n")]
        self.assertRegex(hold, r"if \(!GameInTray\)\n\t+ReconnectOff\(\)\n\t+Sleep\(300\)\n\t+$")
        self.assertEqual(af.count("ReconnectOff()"), 2)
        rc = code("AutoFarmer", "Reconnect.ahk")
        self.assertIn("\nReconnectOff()\n", rc)


class Walker(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.w = code("AutoQuester", "Walker.ahk")

    def test_refocus_watch_kept_on_with_the_bot_off(self):
        self.assertIn("if ((Walking && WalkBotOn()) || !Refocus)", func(self.w, "WalkerRefocusWatch"))

    def test_unread_prompt_no_x_at_the_goal(self):
        st = func(self.w, "StartTalk")
        read = st.index("prompt := InteractPrompt()")
        guard = st.index('if (prompt = "" && ErrorLevel)')
        self.assertLess(read, guard)
        self.assertLess(guard, st.index("WalkTalkCount()"))
        self.assertRegex(st[guard:], r'^if \(prompt = "" && ErrorLevel\)\n\t\t\{\n(?:\t\t[^\n]*\n)*?\t\treturn\n\t\t\}')

    def test_x_paths_by_walk_prompt_crowns(self):
        self.assertNotRegex(self.w, r'RegExMatch\(WkPromptDest " " WkPromptText, "i\)[^"]*cr\[o0\]wn')
        self.assertNotIn('RegExMatch(WkPromptText, "i)cr[o0]wn")\n\t\t|| WalkUseNames', self.w)
        self.assertGreaterEqual(self.w.count('!RegExMatch(WkPromptDest " " WkPromptText, "i)teleport") && !WalkPromptCrowns()'), 2)

    def test_talk_again_no_x_logged_after_your_turn(self):
        ta = func(self.w, "WalkTalkAgain")
        held = ta.rindex("if (WalkYouHeld())")
        self.assertLess(ta.rindex("NavTurn(taGoal.h)"), held)
        self.assertLess(held, ta.index('" again"'))

    def test_nav_confirm_not_on_your_turn(self):
        nt = func(self.w, "NavTurn")
        self.assertRegex(nt, r'&& \(!WkNavChecked \|\| !WkNavTrusted\)\n\t\t&& !MouseSteerYours\(downAt\)\)\n\t\tWalkNavConfirm\(')

    def test_one_x_key_three_times_at_most(self):
        nt = func(self.w, "NavTurn")
        self.assertIn("global SpeedOneTries", nt)
        # (a sped-up turn within the 10 s keeps the count - only a turn at about 1x starts it again)
        self.assertRegex(nt, r'else if \(SpeedNow = 1 && ratio > 1\.6\)\n\t+\{\n\t+SpeedMiss := 0\n\t+'
                             r'if \(SpeedSentAt && A_TickCount - SpeedSentAt > 10000 && SpeedOneTries < 3\)\n')
        self.assertIn("else if (SpeedSentAt && A_TickCount - SpeedSentAt > 10000 && SpeedOneTries = 3)", nt)
        self.assertRegex(nt, r'SpeedOneTries \+= 1\n\t+SpeedOff := "the game stays sped up after Cheat Engine restarted')
        self.assertIn('WalkNotify("speed", ', nt)
        self.assertIn("SpeedMiss := 0, SpeedOneTries := 0", nt)
        self.assertRegex(self.w, r"(?m)^global SpeedOneTries$")
        self.assertIn('SpeedOneTries := ""', func(self.w, "WalkerBlank"))
        self.assertIn("SpeedMiss := 0, SpeedOneTries := 0", func(self.w, "WalkerInit"))


class Clicks(unittest.TestCase):
    def test_every_right_click_discard_looks_at_the_window(self):
        for parts in (("AutoFarmer", "Autofarmer.ahk"), ("AutoFarmer", "KillCalc.ahk"), ("AutoFarmer", "Draw.ahk"),
                      ("AutoFarmer", "CardLearn.ahk")):
            c = code(*parts)
            n = c.count('Click("right")')
            # (LearnAllRound's breaks also mark the round cut short - cut := true: not counted as one with nothing new)
            stop = r'(?:break|return[^\n]*|\{\n\t+cut := true\n\t+break\n\t+\})'
            guarded = re.findall(r'if \(!GameInTray && !GameUnderMouse\("a discard"\)\)\n\t+' + stop + r'\n'
                                 r'\t+if \(GameInTray\)\n\t+' + stop + r'\n\t+Click\("right"\)', c)
            self.assertEqual(len(guarded), n, parts[-1])
        flee = func(code("AutoFarmer", "Flee.ahk"), "FleeCheck")
        self.assertRegex(flee, r'if \(!GameInTray && !GameUnderMouse\("the Flee button again"\)\)\s*return false\s*'
                               r'Sleep\(80\)\s*if \(GameInTray\)\s*return false\s*Click\(\)')

    def test_held_discards_by_the_games_name(self):
        kc = code("AutoFarmer", "KillCalc.ahk")
        for name, lc, b in (("BoostMemDiscard", "bmdLc", "bmdB.m"), ("BoostOffSchoolDiscard", "bosLc", "bosC")):
            f = func(kc, name)
            self.assertIn('else if (%s.known = "" && V1IsFunc("LearnCardByGame"))' % lc.replace("Lc", "B"), f, name)
            self.assertIn("%s := LearnCardByGame.Call(%s)" % (lc, b), f, name)
        lcg = func(code("AutoFarmer", "CardLearn.ahk"), "LearnCardByGame")
        self.assertIn('LearnFlag(c, "game") = lcbName', lcg)


class CrownsGoalLine(unittest.TestCase):
    def test_goal_line_read_before_the_crowns_look(self):
        for parts, name in ((("AutoFarmer", "Dungeons.ahk"), "daCrown := "), (("AutoFarmer", "Party.ahk"), "if (PartyRidePrompt("),
                            (("AutoFarmer", "Carry.ahk"), 'if (PartyRidePrompt(WkPromptText, WkPromptVerb, "")')):
            c = code(*parts)
            at = c.index(name)
            self.assertIn("WalkGoalLine()", c[at - 200:at], parts[-1])


class Readers(unittest.TestCase):
    def test_answer(self):
        import vision as V
        real = V.nav_reader

        class Fake:
            def __init__(self, out):
                self.out = out

            def broken(self):
                return self.out
        try:
            V.nav_reader = lambda: Fake(("6B05FDF0", []))
            self.assertEqual(V.readers_answer(), ["build|6B05FDF0", "ok"])
            V.nav_reader = lambda: Fake(("6B05FDF0", [("cards", "no class | here"), ("position", "MISSING sig")]))
            self.assertEqual(V.readers_answer(), ["build|6B05FDF0", "broken|cards|no class / here",
                                                  "broken|position|MISSING sig"])

            def boom():
                raise RuntimeError("x")
            V.nav_reader = boom
            out = V.readers_answer()
            self.assertEqual(out[0], "build|")
            self.assertTrue(out[1].startswith("broken|helper|"))
        finally:
            V.nav_reader = real
        with open(os.path.join(HERE, "vision.py"), encoding="utf-8") as f:
            src = f.read()
        self.assertIn("if u.path == '/readers':\n                # ", src)

    def test_ahk_side(self):
        v = code("AutoFarmer", "Vision.ahk")
        look = func(v, "VisionReadersLook")
        self.assertIn('VisionGet("/readers", 500, true)', look)
        self.assertIn("A_TickCount - VisionReadersAt < 60000", look)
        self.assertIn('VisionReadersSaid != vrBuild "|"', look)
        self.assertIn('AlertSend.Call("memory", ', look)
        self.assertRegex(v, r"(?m)^global VisionReadersAt, VisionReadersN, VisionReadersWhat, VisionReadersBuild, VisionReadersSaid$")
        self.assertIn('VisionReadersSaid := ""', func(v, "VisionBlank"))
        self.assertIn("dashMem := VisionReadersSay()", code("AutoFarmer", "Dashboard.ahk"))
        af = code("AutoFarmer", "Autofarmer.ahk")
        self.assertRegex(af, r"if \(inbattle != 1\)\n\t\t\{\n\t\tSpApplyPending\(\)\n\t\tUpdAuto\(\)\n\t\tVisionReadersLook\(\)\n")


class Bag(unittest.TestCase):
    def test_unread_field_read_and_said_apart(self):
        v = code("AutoFarmer", "Vision.ahk")
        self.assertIn('unread: V1At(nbgF, 4) = "1" ? 1 : 0}))', v)
        qs = code("AutoFarmer", "QuickSell.ahk")
        self.assertIn("why := qx.unread ? \"an item in the backpack couldn't be read from the game's memory", qs)
        # (listed from bag.crownShop itself: its groups are left out, so never in the loop over the groups sold)
        self.assertIn("if (qx.unread && StrLen(qUnread) < 400)", qs)
        self.assertIn("crownShop: qShopNames, unread: qUnread})", qs)


class Carry(unittest.TestCase):
    def test_flee_counts_the_carrys_own(self):
        c = code("AutoFarmer", "Carry.ahk")
        self.assertIn('"FleeNoCards", "FleeNoMana"', func(c, "CarryStateNames"))
        sw = func(c, "CarrySwap")
        self.assertRegex(sw, r"ResetVariables\(\)\n\tResetUsed\(\)\n\tFleeNoCards := 0, FleeNoMana := 0\n")


class VisionStart(unittest.TestCase):
    def test_only_its_own_helper_taken(self):
        vs = func(code("AutoFarmer", "Vision.ahk"), "VisionStart")
        self.assertNotIn('VisionGet("/ping", 500)', vs)
        self.assertIn('vsPing := VisionGet("/ping?pid=1", 500)', vs)
        # (its own by this start's token - a launcher pythonw.exe runs the helper under a child's pid - or by its pid)
        self.assertIn('" --token " vsTok', vs)
        self.assertIn('vsMine := RegExMatch(vsPing, " token (\\w+)\\s*$", &vsT) && vsT[1] == vsTok', vs)
        # (taken by its token: its own pid kept from then on - the launcher's would be checked, restarted and closed instead)
        self.assertRegex(vs, r'if \(vsMine \|\| vsPid = VisionPid\)\s*\{\s*if \(vsMine && vsPid > 0\)\s*VisionPid := vsPid\s*VisionOn := 1')
        self.assertIn('if (InStr(vsName, "python"))\n\t\t\t\t\t\ttry ProcessClose(vsPid)', vs)


if __name__ == "__main__":
    unittest.main()
