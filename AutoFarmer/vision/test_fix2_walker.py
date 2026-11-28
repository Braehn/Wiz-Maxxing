"""test_fix2_walker.py - the walker's second round of review fixes (2026-11-27), checked by reading the AHK sources - no
AutoHotkey: python -m unittest test_fix2_walker  (from AutoFarmer\\vision)

  - gap3-2 / gap3-6 / walker-1-1 / walker-1-2 / walker-1-4 / walker-2-5: the walker's holds (HoldFor), memory turns
    (NavTurn), the dialogue's Space loop, the approach, and the window-close clicks let go for you at the keyboard or mouse
    there and then (WalkYouSince - "Wait while I play" as PlayerActing has it), and nothing more is pressed in that step
    (WalkYouHeld in WalkMayPress); a turn you touched the keys over never sets the heading's sign; the talk retries don't
    turn and X after an approach stopped for you.
  - puzzle-4: AutoQuester on its own installs both hooks and its WalkLoop waits while you play.
  - gap4-3 / gap4-8 / gap4-10 / extra-1: World Gates, sigils and boats get the Crowns look too (WalkCrownsNoX), GateStep's
    X again as well; the 2x prompt read never drops a Crowns line the 1x read had (WalkCrownLines).
  - walker-1-7: GateStep's give-up is a notice. walker-1-5: a dialogue box Space didn't close twice in 2 minutes isn't
    Spaced on and on. walker-1-6: WkSigilSeen (never set) gone. walker-1-8: a sigil wait you played over isn't a fail.
  - walker-2-4: the Commons spot is kept only once the teleport happened. walker-2-1 / walker-2-2: WalkZone reads at most
    ZoneTail bytes and keeps the zone over the game's own log rotation.
  - gap3-4 / gap1-2 / gap1-4: SpeedSet is Critical before it looks at SpeedNow, waits for modifiers to come up, and leaves
    SpeedNow as it was when there's no input desktop. walker-2-3: a turn from standing learns its own worth (MsStandK)."""
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


W = read(AQ, "Walker.ahk")
MS = read(AQ, "MouseSteer.ahk")
AQS = read(AQ, "AutoQuester.ahk")


class YieldsToYou(unittest.TestCase):
    def test_walk_you_since(self):
        ys = code(func(W, "WalkYouSince"))
        self.assertIn("ysIdle := UserIdle()", ys)
        self.assertIn("if (!from || ysIdle >= A_TickCount - from)\n\t\treturn false", ys)
        # (F8 / F6 and their letting go aren't you - PlayerActing's 0.6 s; the X pass-through is)
        self.assertIn('A_ThisHotkey != "~*x"', ys)
        self.assertIn("ysIdle <= A_TimeSinceThisHotkey + 50", ys)
        self.assertIn("ysIdle >= A_TimeSinceThisHotkey - 600", ys)
        # (AutoFarmer's "Wait while I play" by a guarded dynamic call - AutoQuester has no HandsOffOn)
        self.assertIn('V1IsFunc("HandsOffOn") ? %"HandsOffOn"% : 0', ys)
        self.assertIn('Stats["handsoff"] > 0', ys)
        self.assertIn("IsObject(Stats)", ys)
        self.assertRegex(ys, r"\n\tglobal WkYouAt\b")
        self.assertIn("WkYouAt := A_TickCount", ys)
        self.assertIsNone(re.search(r"(?<![\"%])\bHandsOffOn\(", ys))

    def test_may_press_and_held(self):
        self.assertIn("Walking && GameActive() && WalkBotOn() && !WalkYouHeld()", code(func(W, "WalkMayPress")))
        self.assertIn("WkYouAt && A_TickCount - WkYouAt < 2000", code(func(W, "WalkYouHeld")))

    def test_new_global_initialised(self):
        self.assertRegex(W, r"\nglobal WkYouAt, WkSigilYou\n")
        self.assertIn("global WkYouAt := 0, WkSigilYou := 0", func(W, "WalkerBlank"))
        wi = code(func(W, "WalkerInit"))
        self.assertIn("WkSigilYou := 0, WkYouAt := 0", wi)
        self.assertRegex(wi, r"\n\tglobal WkYouAt, WkSigilYou\b")
        ws = code(func(W, "WalkStep"))
        self.assertLess(ws.find("WkYouAt := 0"), ws.find("WalkMetrics()"))
        self.assertRegex(ws, r"\n\tglobal WkYouAt\b")

    def test_hold_for(self):
        hf = code(func(W, "HoldFor"))
        m = re.search(r"if \(WalkYouHeld\(\) \|\| WalkYouSince\(hfFrom\)\)\n\t\t\t\{\n(.*?)\n\t\t\t\}", hf, re.S)
        self.assertTrue(m)
        self.assertIn("ReleaseKeys()", m.group(1))
        self.assertIn("return false", m.group(1))
        self.assertLess(hf.find("hfFrom := A_TickCount"), hf.find("while (A_TickCount < stopAt)"))
        self.assertGreater(hf.find("WalkYouSince(hfFrom)"), hf.find("while (A_TickCount < stopAt)"))

    def test_back_up_stops(self):
        bu = code(func(W, "BackUp"))
        self.assertEqual(len(re.findall(r"if \(WalkYouHeld\(\)\)\n\t+return false", bu)), 2)

    def test_nav_turn(self):
        nt = code(func(W, "NavTurn"))
        loop = nt[nt.find("Loop\n"):nt.find('Send("{Blind}{" key " up}")')]
        self.assertIn("if (WalkYouHeld() || WalkYouSince(downAt))", loop)
        self.assertIn('ReleaseKeys(), ending := "you"', loop)
        # (before the reading - a turn of yours never judged)
        self.assertLess(loop.find("WalkYouSince(downAt)"), loop.find('nav := %"NavRead"%.Call(120)'))
        # (the sign's verdict by your input as it is - MouseSteerYours, "Wait while I play" on or off - review 1.3; a turn the way
        # it said, ending "", too: no WalkNavConfirm on your turn)
        self.assertIn('if ((ending = "wrong way" || ending = "not turning" || ending = "") && MouseSteerYours(downAt))\n\t\tending := "you"', nt)
        self.assertLess(nt.find("MouseSteerYours(downAt)"), nt.find("WkNavSign := -WkNavSign"))
        self.assertLess(nt.find("MouseSteerYours(downAt)"), nt.find("WalkNavConfirm("))
        self.assertIn('ending = "you" ? stillTurns : 0', nt)
        self.assertIn('ending != "you" && turned * h > 0 && Abs(turned) >= 15 && (!WkNavChecked || !WkNavTrusted)', nt)

    def test_turn_sign_only_by_the_key_alone(self):
        tn = code(func(W, "Turn"))
        self.assertIn("tnHeld := HoldFor(ms)", tn)
        self.assertIn('if (yaw0 != "" && Walking && tnHeld)', tn)
        self.assertIn('if (IsObject(nav) && nav.yaw != "" && !MouseSteerYours(tnDown))', tn)
        self.assertLess(tn.find("!MouseSteerYours(tnDown)"), tn.find("WkNavSign := -WkNavSign"))

    def test_skip_dialog(self):
        sd = code(func(W, "WalkSkipDialog"))
        loop = sd[sd.find("Loop 80"):sd.find("WalkDialogWontClose(true)")]
        self.assertIn("if (WalkYouHeld() || WalkYouSince(sdFrom))", loop)
        self.assertIn("return true", loop[loop.find("WalkYouSince(sdFrom)"):])

    def test_approach_by_walk_you_since(self):
        ap = code(func(W, "WalkApproach"))
        self.assertIn("if (WalkYouHeld() || WalkYouSince(apDown))", ap)
        self.assertNotIn("UserIdle() < A_TickCount - apDown", ap)
        # (its own opening NavTurn let go for you: "you", before W - review 1.2 / 2.1)
        turn = ap.find("NavTurn(gn.h)")
        held = ap.find('if (WalkYouHeld())\n\t\t\treturn "you"')
        self.assertGreater(held, turn)
        self.assertLess(held, ap.find("HoldW(1, true)"))

    def test_start_talk_no_try_while_held(self):
        st = code(func(W, "StartTalk"))
        # (no talk try, no "pressed X" while WalkYouHeld - PressKey would drop the X)
        end = st.find("WkArrived := 2, WkTalk := 0")
        held = st.rfind("if (WalkYouHeld())", 0, end)
        self.assertGreater(held, 0)
        self.assertIn("WkArrived := 0", st[held:end])
        # (the other-NPC branch's turn too)
        nt = st.find("NavTurn(stGoal.h)")
        self.assertLess(st.find("if (WalkYouHeld())", nt), st.find("WalkTalkCount()", nt))

    def test_talk_again_and_start_talk_stop_for_you(self):
        ta = code(func(W, "WalkTalkAgain"))
        stop = ta.find('if (taWhy = "you" || taWhy = "new goal" || taWhy = "")')
        self.assertGreater(stop, ta.find("taWhy := WalkApproach(TalkStop)"))
        self.assertLess(stop, ta.find("NavTurn(taGoal.h)"))
        self.assertLess(stop, ta.find("StartTalk("))
        self.assertIn("return true", ta[stop:ta.find("}", stop)])
        st = code(func(W, "StartTalk"))
        self.assertIn('stAp := stGoal.r > 150 ? WalkApproach(120) : "there"', st)
        stop = st.find('if (stAp = "you" || stAp = "new goal" || stAp = "")')
        self.assertGreater(stop, 0)
        self.assertLess(stop, st.find("NavTurn(stGoal.h)"))
        self.assertIn("WkArrived := 0", st[stop:st.find("return", stop)])

    def test_window_clicks_look_for_you(self):
        cw = code(func(W, "WalkCloseWindow"))
        self.assertLess(cw.find("cwFrom := A_TickCount"), cw.find("OcrRect("))
        self.assertLess(cw.find("WalkYouSince(cwFrom)"), cw.find("MouseMove("))
        ca = code(func(W, "WalkCloseAfterX"))
        self.assertLess(ca.find("caFrom := A_TickCount"), ca.find("WalkAfterXText("))
        self.assertLess(ca.find("if (WalkYouSince(caFrom))"), ca.find('PressKey("Escape")'))
        self.assertLess(ca.find("!WalkMayPress() || WalkYouSince(caFrom)"), ca.find("MouseMove("))


class AutoQuesterWaits(unittest.TestCase):
    def test_hooks(self):
        c = code(AQS)
        self.assertIn("\nInstallKeybdHook()\nInstallMouseHook()\n", c)
        self.assertLess(c.find("InstallKeybdHook()"), c.find("F8::"))

    def test_walk_loop_waits(self):
        wl = re.search(r"\nWalkLoop\(\) \{.*?\n\}\n", AQS, re.S).group(0)
        wl = code(wl)
        self.assertIn("local aqFrom := A_TickCount + 600, aqYou := 0", wl)
        wait = wl.find("if (GameActive() && UserIdle() < Min(3000, A_TickCount - aqFrom))")
        self.assertGreater(wait, 0)
        self.assertLess(wait, wl.find("WalkStep()"))
        branch = wl[wait:wl.find("continue", wait)]
        self.assertIn("ReleaseKeys()", branch)
        self.assertIn("Sleep(200)", branch)
        self.assertIn("aqYou := 0, WalkResume()", wl)


class CrownsAtEveryX(unittest.TestCase):
    def test_start_helpers_refuse_first(self):
        for name in ("StartGate", "StartSigil", "StartTransport"):
            body = code(func(W, name))
            no = body.find("if (WalkCrownsNoX(")
            self.assertGreater(no, 0, name)
            self.assertIn("return false", body[no:no + 120], name)
            for later in ("ReleaseKeys()", 'PressKey("x")', "WkArrived := "):
                self.assertLess(no, body.find(later), name + " " + later)
            self.assertTrue(body.rstrip().endswith("return true\n\t}"), name)

    def test_crowns_no_x(self):
        cn = code(func(W, "WalkCrownsNoX"))
        self.assertIn("if (!WalkPromptCrowns())\n\t\treturn false", cn)
        self.assertIn("return true", cn)
        self.assertIn("static cnSaid := 0", cn)

    def test_callers_use_the_answer(self):
        ws = code(func(W, "WalkStep"))
        self.assertEqual(ws.count("StartGate("), 2)
        self.assertEqual(len(re.findall(r"&& StartGate\(", ws)), 2)
        self.assertIn('if (sgWhy != "" && StartSigil(sgWhy, sgGoal))\n\t\t\t\treturn true', ws)
        tr = code(func(W, "WalkTransport"))
        self.assertRegex(tr, r"&& StartTransport\(dest, [^\n]*\)\)\n\t\treturn true")
        st = code(func(W, "StartTalk"))
        self.assertIn('if (prompt = "gate" && StartGate(', st)
        self.assertIn('if (prompt = "sigil" && !WalkPromptCrowns())', st)
        # (a gate's, sigil's or boat's prompt with Crowns at the goal: waited by with the notice, as a "Press X" one)
        conv = st.find('if (prompt != "" && prompt != "press" && WalkPromptCrowns())')
        self.assertGreater(conv, 0)
        self.assertLess(conv, st.find('if (prompt = "press" && WalkPromptCrowns())'))
        self.assertIn('prompt := "press"', st[conv:conv + 220])
        # (WkPromptDest assigned there: declared global, else a local - reading it unset throws)
        self.assertRegex(st, r"\n\tglobal WkPromptDest\b")

    def test_gate_step(self):
        gs = code(func(W, "GateStep"))
        three = gs[gs.find("if (WkGateClicks >= 3)"):gs.find("WkGateClicks += 1")]
        self.assertIn('WalkNotify("stuck"', three)
        self.assertIn("Walking := 0", three)
        self.assertIn('gsCrowns := WkGateX < 2 && InteractPrompt() != "" && WalkPromptCrowns()', gs)
        self.assertLess(gs.find("gsCrowns :="), gs.find('PressKey("x")'))
        self.assertIn("if (WkGateX < 2 && !gsCrowns)", gs)

    def test_second_read_keeps_crowns(self):
        ip = code(func(W, "InteractPrompt"))
        self.assertIn("t := t2, WkPromptText := t2 WalkCrownLines(WkPromptText, t2)", ip)
        cl = code(func(W, "WalkCrownLines"))
        self.assertIn('if (RegExMatch(t2, "i)cr[o0]wn") || !RegExMatch(t1, "i)cr[o0]wn"))\n\t\treturn ""', cl)
        self.assertIn('clOut .= "`n" A_LoopField', cl)

    def test_crown_lines_model(self):
        # (the same rule in Python: only the 1x read's Crowns lines, and only when the 2x read lost them)
        def crown_lines(t1, t2):
            rx = re.compile(r"cr[o0]wn", re.I)
            if rx.search(t2) or not rx.search(t1):
                return ""
            return "".join("\n" + ln for ln in t1.split("\n") if rx.search(ln))
        t1 = "PRIVATE ISLE\nPress X to Enter\n500 Crowns"
        t2 = "PRIVATE ISLE\nPress X to Enter\n500 Growns"
        self.assertEqual(crown_lines(t1, t2), "\n500 Crowns")
        self.assertEqual(crown_lines(t1, t1), "")
        self.assertEqual(crown_lines("Press X to Talk", "Press X to Talk"), "")


class DialogueAndSigil(unittest.TestCase):
    def test_wont_close_cap(self):
        sd = code(func(W, "WalkSkipDialog"))
        self.assertIn("acc := WalkDialogAccept(), sdClosed := 1", sd)
        # (only presses that reached the game counted - review 1.4)
        self.assertIn("if (!sdClosed && sdSent >= 80)\n\t\tWalkDialogWontClose(true)", sd)
        loop = sd[sd.find("Loop 80"):]
        self.assertLess(loop.find("sdSent += WalkMayPress() ? 1 : 0"), loop.find('PressKey("Space")'))
        ws = code(func(W, "WalkStep"))
        look = ws[ws.find("WkDlgLook := A_TickCount + 400"):]
        look = look[:look.find("WalkAcceptQuest(")]
        self.assertIn("if (WalkDialogWontClose() < 2)\n\t\t\t\treturn WalkSkipDialog()", look)
        wc = code(func(W, "WalkDialogWontClose"))
        self.assertIn("A_TickCount - wcT < 120000", wc)

    def test_sigil_seen_gone(self):
        self.assertNotIn("WkSigilSeen", code(W))
        self.assertNotIn("hiddenHere", code(W))

    def test_sigil_wait_you_played(self):
        wr = code(func(W, "WalkResume"))
        self.assertRegex(wr, r"\n\tglobal WkSigilYou, WkYouAt\b")
        # (only your own input since the X - not QuickSell's run calling this - review 1.6)
        self.assertIn('if (keepUntil && keepWhat = "sigil" && WkSigilXAt && UserIdle() < A_TickCount - WkSigilXAt)\n\t\tWkSigilYou := WkSigilXAt', wr)
        # (the hold-off for you over once you've been waited for - review 1.5)
        self.assertGreater(wr.find("WkYouAt := 0"), wr.find("WalkReset()"))
        sc = code(func(W, "WalkSigilCheck"))
        you = sc.find("if (WkSigilYou && WkSigilYou = WkSigilXAt)")
        self.assertGreater(you, 0)
        self.assertLess(you, sc.find("scSpot.fails += 1"))
        self.assertIn("return false", sc[you:sc.find("}", you)])


class CommonsAndZone(unittest.TestCase):
    def test_commons_spot_on_success_only(self):
        cr = code(func(W, "WalkCommonsReset"))
        self.assertNotIn("spots.Push(V1Obj(", cr)
        push = cr.find("spots.Push(spAt)")
        self.assertGreater(push, cr.find("if (!WkLoading && WkLoadedAt > t0 + 500)"))
        self.assertLess(push, cr.find("return true"))
        self.assertLess(cr.find("spAt := V1Obj("), cr.find('PressKey("End")'))

    def test_zone_read_is_bounded(self):
        wz = code(func(W, "WalkZone"))
        self.assertIn("static ZoneTail := 8388608", wz)
        self.assertIn("readFrom := Max(readFrom, logSize - ZoneTail, 0)", wz)
        self.assertIn("incremental := rotated || (scanned && logSize > lastSize && lastSize > 300)", wz)
        self.assertIn("if (incremental)\n\t\t{\n\t\tstartAt := InStr(chunk, \"MSG_ZoneTransferRequest\"", wz)
        self.assertNotIn("readFrom := 0, zone := \"\"", wz)
        self.assertIn("gamePid := V1Try(WinGetPID, WkGameWT())", wz)
        self.assertIn('if (lastHead != "" && gamePid != "" && gamePid = lastPid)', wz)

    def test_zone_further_back(self):
        # (a tail with no zone line: the log further back, ZoneTail at a time, at most 4 a look - review 1.1)
        wz = code(func(W, "WalkZone"))
        self.assertIn("static backPos := 0", wz)
        self.assertIn('if (!incremental && zone = "" && readFrom > 0)\n\t\t{\n\t\tbackPos := readFrom', wz)
        self.assertIn('if (ErrorLevel || (logSize = lastSize && !(zone = "" && backPos > 0)))', wz)
        self.assertIn("if (!rotated && scanned && logSize = lastSize)\n\t\tincremental := true, readFrom := logSize", wz)
        self.assertIn("scanned := 0, lastHead := logHead, backPos := 0", wz)
        back = wz[wz.find('if (zone = "" && backPos > 0)'):]
        self.assertIn("Loop 4", back)
        self.assertIn("backFrom := Max(backPos - ZoneTail, 0)", back)
        self.assertIn("backFile.Close()", back)
        # (history: looked for after zoneBefore was taken - no zone change made of it)
        self.assertLess(wz.find("zoneBefore := zone"), wz.find('if (zone = "" && backPos > 0)'))

    def test_zone_back_regex(self):
        # (the back look's regex, as the AHK has it, on a log as the game writes it: the last zone line wins)
        head = 'RegExMatch(backChunk, "'
        src = W[W.find(head) + len(head):]
        pat = src[:src.find('", &backMatch')]
        # (the pattern on one line, its \r \n written as escapes - not a line break in the AHK string)
        self.assertNotIn("\n", pat)
        log = ("x ConnectComplete destination Zone=WizardCity/WC_Hub\r\nnoise\r\n"
               "y Finished loading zone 'Karamelle/KM_Z03_GumdropForest'\r\ntexture error\r\n")
        for text, want in ((log, "Karamelle/KM_Z03_GumdropForest"),
                           ("a Finished loading zone 'X/Y'\r\nb ConnectComplete destination Zone=Wallaru/WL_Hub\r\nz", "Wallaru/WL_Hub")):
            at = max(text.rfind("ConnectComplete destination Zone="), text.rfind("Finished loading zone '"))
            m = re.compile(pat).search(text, at)
            self.assertEqual(m.group(2) or m.group(1), want)

    def test_zone_read_model(self):
        # (WalkZone's readFrom, as the AHK has it, over the cases the review traced)
        TAIL = 8388608

        class Z:
            def __init__(self):
                self.lastSize, self.lastHead, self.lastPid, self.scanned = -1, "", "", 0

            def look(self, size, head, pid):
                rotated = False
                if head != self.lastHead:
                    rotated = self.lastHead != "" and pid != "" and pid == self.lastPid
                    self.scanned, self.lastHead = 0, head
                if pid != "":
                    self.lastPid = pid
                inc = rotated or (self.scanned and size > self.lastSize and self.lastSize > 300)
                rf = 0 if rotated else (self.lastSize - 300 if inc else 0)
                rf = max(rf, size - TAIL, 0)
                self.lastSize, self.scanned = size, 1
                return rf, bool(inc)

        z = Z()
        # (the first look at a 2 GB log: its tail, history)
        self.assertEqual(z.look(2146435246, "A", 7), (2146435246 - TAIL, False))
        # (it grew: only what's new, now's)
        self.assertEqual(z.look(2146436000, "A", 7), (2146435246 - 300, True))
        # (the same game's log started afresh: the new file from its top, as new lines)
        self.assertEqual(z.look(5000, "B", 7), (0, True))
        self.assertEqual(z.look(9000, "B", 7), (4700, True))
        # (the game started again - another process: its tail, history)
        self.assertEqual(z.look(20000000, "C", 9), (20000000 - TAIL, False))


class SpeedKeys(unittest.TestCase):
    def test_critical_before_the_look(self):
        ss = code(func(W, "SpeedSet"))
        self.assertLess(ss.find("Critical()"), ss.find("SpeedSetIn(fast, why, force)"))
        si = code(func(W, "SpeedSetIn"))
        self.assertNotIn("Critical(", si)
        self.assertRegex(si, r"\n\tglobal SpeedNow, SpeedSentAt\b")

    def test_modifiers_and_input_desktop(self):
        si = code(func(W, "SpeedSetIn"))
        wait = si.find('GetKeyState("LWin", "P")')
        self.assertGreater(wait, 0)
        self.assertLess(wait, si.find('Send("{Blind}{" key " down}")'))
        self.assertIn("A_TickCount - spWait < 1000", si)
        desk = si.find('DllCall("OpenInputDesktop"')
        self.assertLess(desk, si.find('Send("{Blind}{" key " down}")'))
        self.assertIn('DllCall("CloseDesktop", "Ptr", spDesk)', si)
        # (the desktop looked at first - no gap or modifier wait for a key Windows drops; SpeedNow untouched then - review 2.2)
        self.assertLess(desk, wait)
        self.assertLess(desk, si.find("Sleep(gap)"))
        self.assertLess(desk, si.find("SpeedNow := want"))
        self.assertIn("return", si[desk:si.find('DllCall("CloseDesktop"')])


class StandTurnWorth(unittest.TestCase):
    def test_learned_and_used(self):
        st = code(func(MS, "MouseStandTurn"))
        self.assertIn("want := Round(h / MsK / msSk)", st)
        self.assertIn("msSk := V1IsNum(MsStandK) ? MsStandK : 1", st)
        self.assertRegex(st, r"\n\tglobal MsStandK\b")
        self.assertIn("msReal := h + ArrowWrap(turned - h), msRatio := msReal / h", st)
        self.assertIn("if (msRatio >= 0.5 && msRatio <= 2.5)", st)
        self.assertIn('global MsStandK := ""', func(MS, "MouseSteerBlank"))
        self.assertRegex(MS, r"\nglobal MsStandK\n")

    def test_ratio_model(self):
        def wrap(a):
            while a > 180:
                a -= 360
            while a <= -180:
                a += 360
            return a
        # (2026-11-26 18:12:36: 131 wanted, -158 read - 202 turned, 1.54x)
        real = 131 + wrap(-158 - 131)
        self.assertEqual(real, 202)
        self.assertAlmostEqual(real / 131, 1.542, places=2)
        # (the next 131 asked sends 1/1.54 of the counts: about 131 turned)
        self.assertAlmostEqual(131 / (real / 131) * (real / 131), 131)


if __name__ == "__main__":
    unittest.main()
