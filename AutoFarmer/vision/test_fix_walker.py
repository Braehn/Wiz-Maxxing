"""test_fix_walker.py - the walker's review fixes (2026-11-27), checked by reading the AHK sources - no AutoHotkey:
python -m unittest test_fix_walker  (from AutoFarmer\\vision)

  - walker-1-3: the main "prompt on the way" X (WalkStep's prompt look) had no Crowns check, unlike the waiting-at-the-goal
    X, the X-opened-nothing X and collecting: StartPressX - every prompt X goes through it - now refuses a prompt with
    Crowns on it (WalkPromptCrowns) before anything is let go of or pressed.
  - gap3-1: F6 (BotToggle) sets BotOn only, never Walking: the step under way went on pressing W/A/D/S, X and clicking
    till it got back to the main loop. Each input primitive now looks at the bot being on too (WalkBotOn - AutoFarmer's
    WalkHostOn without the look for you, through a guarded dynamic call: AutoQuester has no BotOn); HoldFor returns false
    and lets go once it's off.
  - x-persistence-3 (the walker's part): WalkMemSave and WalkNavSave moved the .tmp over the real file without looking at
    the FileAppend - a full disk left an empty .tmp to replace walk_memory.txt / nav_calibration.txt."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AQ = os.path.join(HERE, "..", "..", "AutoQuester")


def read(*parts):
    with open(os.path.join(*parts), encoding="utf-8-sig") as f:
        return f.read().replace("\r\n", "\n")


def func(src, name):
    m = re.search(r"^" + name + r"\(.*?\n\t\}\n", src, re.M | re.S)
    assert m, name + " not found"
    return m.group(0)


def code(text):
    """the lines without their comments (a ; at the start of a line, or ' ;' after code)"""
    out = []
    for ln in text.split("\n"):
        s = ln.strip()
        if s.startswith(";"):
            continue
        out.append(re.sub(r"\s;.*$", "", ln))
    return "\n".join(out)


class CrownsPromptX(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.w = read(AQ, "Walker.ahk")
        cls.spx = code(func(cls.w, "StartPressX"))

    def test_start_press_x_refuses_crowns_first(self):
        crowns = self.spx.find("WalkPromptCrowns()")
        self.assertGreater(crowns, 0)
        # (before anything is let go of, counted as a talk try, or pressed)
        for later in ("ReleaseKeys()", "WalkTalkCount()", 'PressKey("x")', "WkArrived := 6"):
            self.assertGreater(self.spx.find(later), crowns, later)
        refusal = self.spx[crowns:self.spx.find("}", crowns)]
        self.assertIn("return false", refusal)
        # (walked past for a minute - WalkPromptFree - not looked at again at every step)
        self.assertIn("WkPromptUsed[", refusal)
        self.assertIn("return true", self.spx)

    def test_every_prompt_x_goes_through_start_press_x(self):
        # (no X at a prompt in the walker but StartPressX's and StartTalk's (both look for Crowns) and the World Gate's,
        # a sigil's and a transport's own)
        allowed = {"StartPressX", "StartTalk", "StartGate", "GateStep", "StartSigil", "StartTransport"}
        for m in re.finditer(r'^(\w+)\(.*?\n\t\}\n', self.w, re.M | re.S):
            body = code(m.group(0))
            if 'PressKey("x")' in body and m.group(1) not in allowed:
                self.fail(m.group(1) + " presses X outside StartPressX - check it for Crowns")

    def test_start_talk_refuses_crowns(self):
        st = code(func(self.w, "StartTalk"))
        crowns = st.find('if (prompt = "press" && WalkPromptCrowns())')
        self.assertGreater(crowns, 0)
        self.assertLess(crowns, st.find('PressKey("x")'))
        self.assertLess(crowns, st.rfind("WalkTalkCount()"))
        self.assertIn("return", st[crowns:st.find("return", crowns) + 6])

    def test_start_talk_crowns_waits_with_a_notice(self):
        # (review: refused with WkArrived 0 it walked back up and refused again every few seconds, nobody told - now it waits
        # by it as WalkTalkWait does, with a notice once for the goal; WalkTalkRetry asks again only a minute after)
        st = code(func(self.w, "StartTalk"))
        crowns = st.find('if (prompt = "press" && WalkPromptCrowns())')
        branch = st[crowns:st.find("\t\treturn\n", crowns)]
        self.assertIn("WkArrived := 1", branch)
        self.assertNotIn("WkArrived := 0", branch)
        self.assertIn('WalkNotify("wait"', branch)
        self.assertIn('WkPromptUsed["crownsno"] := A_TickCount', branch)
        self.assertRegex(st, r"\n\tglobal [^\n]*\bWkArrDist\b[^\n]*\bWkArrGoal\b")
        tr = code(func(self.w, "WalkTalkRetry"))
        self.assertIn('A_TickCount - WkPromptUsed["crownsno"] < 60000', tr)

    def test_talk_goal_prompt_with_crowns_not_refused_every_look(self):
        # (WalkTalkPromptOk has no once-a-minute: a Crowns prompt is left to the WalkPromptFree way, refused once a minute)
        self.assertIn("WalkPromptCrowns()", code(func(self.w, "WalkTalkPromptOk")))

    def test_quest_marker_talk_returns_start_press_x(self):
        qm = code(func(self.w, "WalkQuestMarkerTalk"))
        self.assertIn("return StartPressX(WkPromptDest)", qm)
        self.assertNotIn("StartPressX(WkPromptDest)\n\treturn true", qm)

    def test_walk_prompt_crowns_no_crowns_no_change(self):
        # (a prompt with no Crowns on it: WalkPromptCrowns false straight away - StartPressX goes on as before)
        wpc = code(func(self.w, "WalkPromptCrowns"))
        self.assertRegex(wpc, r'if \(!RegExMatch\(WkPromptText, "i\)cr\[o0\]wn"\)\)\n\t\treturn false')


class BotOffStopsTheStep(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.w = read(AQ, "Walker.ahk")
        cls.ms = read(AQ, "MouseSteer.ahk")

    def test_walk_bot_on_is_a_guarded_call(self):
        wbo = code(func(self.w, "WalkBotOn"))
        self.assertIn('V1IsFunc("WalkHostOn")', wbo)
        self.assertIn('%"WalkHostOn"%', wbo)
        # (no from: WalkHostOn's look for you stays off - the yield to you is the main loop's, as before)
        self.assertIn("hostOn.Call()", wbo)
        self.assertIn(": true", wbo)
        mp = code(func(self.w, "WalkMayPress"))
        self.assertIn("Walking && GameActive() && WalkBotOn()", mp)

    def test_no_bare_bot_on_in_the_walker(self):
        # (AutoQuester's standalone build has no BotOn, WalkHostOn or PotionManual: only the guarded call)
        for src in (self.w, self.ms):
            c = code(src)
            self.assertIsNone(re.search(r"\bBotOn\b", c))
            self.assertIsNone(re.search(r"(?<![\"%])\bWalkHostOn\(", c))
            self.assertIsNone(re.search(r"\bPotionManual\b", c))

    def test_the_primitives_look_at_the_bot(self):
        for name in ("WalkClick", "PressKey", "Turn", "NavTurnOrKeys", "NavTurn"):
            body = code(func(self.w, name))
            self.assertIn("WalkMayPress()", body, name)
            self.assertNotIn("Walking && GameActive()", body, name)
            self.assertNotIn("!Walking || !GameActive()", body, name)
        bu = code(func(self.w, "BackUp"))
        self.assertIn("WalkMayPress()", bu)
        # (false after the hold once the bot's off: what comes after it doesn't)
        self.assertEqual(len(re.findall(r"if \(!WalkBotOn\(\)\)\n\t+return false", bu)), 2)
        un = code(func(self.w, "Unstick"))
        self.assertEqual(un.count("if (!WalkMayPress())"), 2)

    def test_hold_for_lets_go_and_returns_false(self):
        hf = code(func(self.w, "HoldFor"))
        m = re.search(r"if \(!WalkBotOn\(\)\)\n\t\t\t\{\n(.*?)\n\t\t\t\}", hf, re.S)
        self.assertTrue(m)
        self.assertIn("ReleaseKeys()", m.group(1))
        self.assertIn("return false", m.group(1))
        # (inside the wait loop, every 50 ms - not only at the start)
        self.assertGreater(hf.find("WalkBotOn()"), hf.find("while (A_TickCount < stopAt)"))

    def test_hold_w_no_w_with_the_bot_off(self):
        hw = code(func(self.w, "HoldW"))
        off = hw.find("if (on && !WalkBotOn())")
        self.assertGreater(off, 0)
        self.assertLess(off, hw.find('Send("{Blind}{w down}")'))
        self.assertLess(off, hw.find("SpeedWalking()"))
        # (review: asked again inside Critical - F6 between the first look and Critical can't get a W down after it)
        crit = hw.find("Critical()")
        self.assertLess(crit, hw.find("if (on && !HeldW && WalkMayPress())"))

    def test_nav_turn_lets_go_in_its_loop(self):
        nt = code(func(self.w, "NavTurn"))
        loop = nt[nt.find("Loop\n"):]
        self.assertIn('ending := "bot off"', loop)
        self.assertIn('ending != "bot off"', nt)

    def test_mouse_steering(self):
        why = code(func(self.ms, "MouseSteerWhyNot"))
        self.assertIn("if (!WalkBotOn())", why)
        for name in ("MouseTurn", "MouseStandTurn"):
            body = code(func(self.ms, name))
            self.assertIn("!WalkBotOn()", body[:body.find("MouseGetPos(")], name)

    def test_walk_bot_on_is_cheap(self):
        # (asked every 10-50 ms: the function looked up once, not V1IsFunc each time)
        wbo = func(self.w, "WalkBotOn")
        self.assertIn("static hostOn", wbo)


class SavesKeepTheOldFile(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.w = read(AQ, "Walker.ahk")

    def check(self, name, var):
        body = code(func(self.w, name))
        m = re.search(r"if \(V1Do\(FileAppend, text, " + var + r' "\.tmp", "`n"\)\)\s*\n\t\t\{\n(.*?)\n\t\t\}', body, re.S)
        self.assertTrue(m, name)
        fail = m.group(1)
        self.assertIn("V1Do(FileDelete, " + var + ' ".tmp")', fail)
        self.assertIn("WalkLog(", fail)
        self.assertIn("return", fail)
        self.assertNotIn("FileMove", fail)
        self.assertGreater(body.find("V1Do(FileMove"), body.find("V1Do(FileAppend"))
        return body

    def test_walk_memory(self):
        self.check("WalkMemSave", "WkMemFile")

    def test_nav_calibration(self):
        body = self.check("WalkNavSave", "WkNavFile")
        # (the sign counted as saved only once it is: the next check saves again)
        self.assertGreater(body.find("WkNavSignSaved := WkNavSign"), body.find("V1Do(FileMove"))


if __name__ == "__main__":
    unittest.main()
