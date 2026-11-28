"""test_fix_af.py - AutoFarmer's main-file review fixes (2026-11-27), checked by reading the AHK sources - no AutoHotkey:
python -m unittest test_fix_af  (from AutoFarmer\\vision)

  - x-usersafety-1 / af-main-2-1: the only OnError (Settings.ahk MouseLockOnError, registered at the first mouse lock)
    let go of the mouse lock only - W/A/S/D, the right mouse button of a mouse turn and Cheat Engine's speed stayed on
    under the error box, and the main loop's thread was gone with the bot still "on". BotOnError, registered at the start,
    lets go of them all and logs the error (what, file, line) - the box shown as ever; the main loop's end (BotLoopMark)
    leaves the bot off (BotLoopGone), and F6 / the dashboard's button start the loop again (BotToggle) - never by itself.
  - gap4-1: trap, negative-aura and prism target clicks were plain ClickAt's - into the Crown shop's corner when enemy 1's
    plate was there. Now through TargetClick (TargetClickSpot), asked before the card is clicked (TargetSpotOk); refused:
    not cast, not counted, not TrapPut.
  - af-main-1-3 / af-main-2-2: the AFK hold's InputHook had no V - it swallowed what you typed in any program for the
    whole hold, F6 or not; Space ended it too. Now "V T1", only W/A/S/D, only in Wizard101, and no hook with the bot off.
  - af-main-1-1: Find's ErrorLevel-2 branch (the search couldn't run) left the flag's old 1 with X, Y blank: FindAndClick's
    sum on the blank threw. The flag is 0 then, and FindAndClick never clicks a blank spot."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AF = os.path.join(HERE, "..")


def read(*parts):
    with open(os.path.join(*parts), encoding="utf-8-sig") as f:
        return f.read().replace("\r\n", "\n")


def func(src, name):
    """a function's text - braces on their own line, tabbed (\\t{ ... \\t}) or not ({ ... } at the line's start)"""
    m = re.search(r"^" + name + r"\(.*?\n\t\}\n", src, re.M | re.S)
    if m and "\n" + name not in m.group(0)[1:] and not re.search(r"\n[A-Za-z]\w*\(.*\)\s*\n\t\{", m.group(0)[1:]):
        return m.group(0)
    m = re.search(r"^" + name + r"\(\) \{.*?\n\}\n", src, re.M | re.S)
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


class ErrorLetsGo(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.af = read(AF, "Autofarmer.ahk")
        cls.st = read(AF, "Settings.ahk")
        cls.boe = code(func(cls.af, "BotOnError"))

    def test_registered_at_the_start(self):
        top = code(self.af[:self.af.find("\nreturn\n")])
        self.assertIn("OnError(BotOnError)", top)
        # (before the main loop's timer: an error in StartBot's set-up is covered too)
        self.assertLess(top.find("OnError(BotOnError)"), top.find("SetTimer(StartBot"))

    def test_lets_go_of_keys_button_speed_mouse(self):
        b = self.boe
        self.assertRegex(b.split("\n")[2], r"local v1Keep := V1Thread\(\)")
        send = b.find('try Send("{Blind}{w up}{a up}{s up}{d up}")')
        self.assertGreater(send, 0)
        # (the keys up on their own, first - ReleaseKeys lets go of the right button before them)
        self.assertLess(send, b.find("ReleaseKeys(true)"))
        self.assertIn("MouseSteerButton(0)", b)
        self.assertRegex(b, r'try SpeedSet\(0, "[^"]+", true\)')
        self.assertIn("try MouseLockRelease(", b)
        self.assertIn('try BlockInput("Off")', b)
        # (every step tried on its own - one that throws keeps none of the rest from running)
        for ln in b.split("\n"):
            s = ln.strip()
            if re.match(r"(ReleaseKeys|SpeedSet|MouseLockRelease|BlockInput|Send|DebugLog)\(", s):
                self.fail("not in a try: " + s)

    def test_logs_the_error_and_keeps_its_box(self):
        b = self.boe
        for what in ("e.Message", "e.File", "e.Line"):
            self.assertIn(what, b)
        self.assertIn("try DebugLog(", b)
        self.assertRegex(b, r"\n\treturn 0\n")
        self.assertNotRegex(b, r"return (1|-1|true)\b")

    def test_mouse_lock_handler_cant_stop_the_next(self):
        m = code(func(self.st, "MouseLockOnError"))
        self.assertIn("OnError(MouseLockOnError, -1)", self.st)
        for s in ("BlockInput(\"MouseMoveOff\")", "BlockInput(\"Off\")"):
            self.assertIn("try " + s, m)
        self.assertRegex(m, r"try\n\t\t\{\n\t\tif \(MouseLocked\)")
        self.assertRegex(m, r"\n\treturn 0\n")


class LoopGoneLeavesOff(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.af = read(AF, "Autofarmer.ahk")

    def test_the_loops_thread_marked(self):
        sb = code(func(self.af, "StartBot"))
        self.assertIn("local loopUp", sb)
        mark, loop = sb.find("loopUp := BotLoopMark()"), sb.find("\nBattleLoop()")
        self.assertGreater(mark, 0)
        self.assertGreater(loop, mark)
        cls_ = self.af[self.af.find("class BotLoopMark"):]
        cls_ = cls_[:cls_.find("\n\t}\n") + 4]
        self.assertIn("__Delete()", cls_)
        self.assertIn("BotLoopDead := 1", cls_)
        self.assertIn("SetTimer(BotLoopGone,", cls_)

    def test_gone_leaves_the_bot_off(self):
        g = code(func(self.af, "BotLoopGone"))
        self.assertRegex(g.split("\n")[2], r"local v1Keep := V1Thread\(\)")
        self.assertIn("global BotOn", g)
        self.assertIn("BotOn := 0", g)
        self.assertIn("ReleaseKeys(true)", g)
        self.assertRegex(g, r'SpeedSet\(0, "[^"]+", true\)')
        self.assertIn("BotOnShow()", g)

    def test_started_again_only_by_you(self):
        t = code(func(self.af, "BotToggle"))
        self.assertIn("if (BotOn && BotLoopDead)", t)
        # (priority -1: only from idle - the loop never returns, so it must not start on top of another thread)
        self.assertIn("SetTimer(BotLoopAgain, -1, -1)", t)
        a = code(func(self.af, "BotLoopAgain"))
        self.assertRegex(a.split("\n")[2], r"local v1Keep := V1Thread\(\)")
        self.assertIn("if (!BotLoopDead || !BotOn)", a)
        self.assertIn("loopUp := BotLoopMark()", a)
        # (nothing else starts it - no timer of its own, no retry after an error)
        self.assertEqual(len(re.findall(r"SetTimer\(BotLoopAgain", code(self.af))), 1)
        self.assertNotIn("BotLoopAgain", code(func(self.af, "BotLoopGone")))
        self.assertNotIn("BotLoopAgain", code(func(self.af, "BotOnError")))

    def test_blank_start(self):
        self.assertIn("global BotLoopDead := 0", code(func(self.af, "AutofarmerBlank")))


class TargetClicksGuarded(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.af = read(AF, "Autofarmer.ahk")

    def test_no_plain_click_on_a_plate(self):
        for name, x in (("UseTrap", "TrapAtX"), ("UseNegAura", "unX"), ("UseConvert", "bossX")):
            b = code(func(self.af, name))
            self.assertNotIn("ClickAt(" + x, b, name)

    def test_asked_before_the_card_is_clicked(self):
        for name, card in (("UseNegAura", "ClickAt(unAt.x"), ("UseConvert", "ClickAt(foundX")):
            b = code(func(self.af, name))
            ok = b.find("TargetSpotOk(")
            self.assertGreater(ok, 0, name)
            self.assertLess(ok, b.find(card), name)
            self.assertIn("if (!TargetClick(", b, name)
        t = code(func(self.af, "UseTrap"))
        ok = t.find("TargetSpotOk(TrapAtX, TrapAtY")
        self.assertGreater(ok, 0)
        self.assertLess(ok, t.find("ClickAt(potentX"))
        self.assertLess(ok, t.find("ClickAt(foundX"))

    def test_refused_not_counted(self):
        t = code(func(self.af, "UseTrap"))
        clicks = [m.start() for m in re.finditer(r"if \(!TrapTargetClick\(title, utBox\)\)\n\t+return false", t)]
        self.assertEqual(len(clicks), 2)
        # (each before its boosts++ and TrapPut)
        for c, nxt in zip(clicks, [t.find("boosts++", clicks[0]), t.find("boosts++", clicks[1])]):
            self.assertLess(c, nxt)
        self.assertLess(clicks[0], t.find("TrapPut(", clicks[0]))
        self.assertLess(clicks[1], t.find("TrapPut(", clicks[1]))
        n = code(func(self.af, "UseNegAura"))
        self.assertLess(n.find("if (!TargetClick("), n.find("NegAuraNote("))
        c = code(func(self.af, "UseConvert"))
        self.assertLess(c.find("if (!TargetClick("), c.find("ConvertOn :="))
        tc = code(func(self.af, "TrapTargetClick"))
        self.assertIn("if (!TargetClick(TrapAtX, TrapAtY, box))", tc)

    def test_potent_trap_asked_again_after_the_wait(self):
        # (review 2.1: BoostSettle takes the first read past 1.5 s - a fresh read and the spot asked again before the
        # trap's own click, not after it)
        t = code(func(self.af, "UseTrap"))
        settle = t.find("BoostSettle(n, &foundX, &foundY, boostX)")
        self.assertGreater(settle, 0)
        again = t.find("TargetSpotOk(TrapAtX, TrapAtY, utBox, title)", settle)
        self.assertGreater(again, settle)
        self.assertLess(t.find("TargetCrownRead()", settle), again)
        self.assertGreater(t.find("TargetCrownRead()", settle), settle)
        card = t.find("ClickAt(foundX, foundY, 150)", settle)
        self.assertLess(again, card)
        self.assertLess(card, t.find("TrapTargetClick(", settle))
        self.assertIn("return false", t[again:card])

    def test_spot_ok_is_target_click_spots(self):
        s = code(func(self.af, "TargetSpotOk"))
        self.assertIn("TargetClickSpot(&tsoX, &tsoY, box, &tsoWhy)", s)
        self.assertIn('if (x = "" || y = "")', s)
        b = code(func(self.af, "TargetBoxAt"))
        self.assertIn('V1At(tbaE, "box")', b)

    def test_new_locals_declared(self):
        # (UseTrap and UseConvert are assume-global: their new names local - no stray global)
        self.assertRegex(code(func(self.af, "UseTrap")), r"local utKey[^\n]*\butBox\b")
        self.assertIn("local ucBox", code(func(self.af, "UseConvert")))


class AfkHoldTyping(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.af = read(AF, "Autofarmer.ahk")
        cls.ca = code(func(cls.af, "CheckAfk"))

    def test_hook_visible_wasd_only(self):
        hooks = re.findall(r'InputHook\("([^"]*)",\s*"([^"]*)"', self.ca)
        self.assertEqual(len(hooks), 1)
        opts, ends = hooks[0]
        self.assertIn("V", opts.split())
        self.assertEqual(ends, "{w}{a}{s}{d}")
        self.assertIn('if (Errorlevel != "Timeout" && GameActive())', self.ca)

    def test_no_hook_with_the_bot_off(self):
        off, hook = self.ca.find("if (!BotOn)"), self.ca.find("InputHook(")
        self.assertGreater(off, 0)
        self.assertLess(off, hook)
        block = self.ca[off:hook]
        self.assertIn("continue", block)
        # (no reconnecting either with it off - as the main loop's off)
        self.assertNotIn("ReconnectCheck", block)


class FindBlankSpot(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.af = read(AF, "Autofarmer.ahk")

    def test_search_failed_flag_off(self):
        f = code(func(self.af, "Find"))
        two = f[f.find("(Errorlevel == 2)"):]
        self.assertIn('card := 0, X := "", Y := ""', two[:two.find("ErrorBox(")])
        # (every way out of Find sets the flag: the game's memory, the helper, ImageSearch's 0, 1 and 2)
        self.assertEqual(len(re.findall(r"\bcard := ", f)), 5)

    def test_find_and_click_refuses_a_blank(self):
        f = code(func(self.af, "FindAndClick"))
        guard = f.find('if (click == 1 && (clickX = "" || clickY = ""))')
        self.assertGreater(guard, 0)
        self.assertLess(guard, f.find("ClickAt(clickX + Px(5)"))
        g = f[guard:f.find("}", guard)]
        self.assertIn("click := 0", g)
        self.assertIn("return false", g)


if __name__ == "__main__":
    unittest.main()
