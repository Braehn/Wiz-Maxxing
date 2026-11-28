"""test_fix2_potions_sell.py - the code review's potion run, flee and quick sell findings (2026-11-27). Standard library
only:  python -m unittest test_fix2_potions_sell  (from AutoFarmer\\vision)

  - The potion run's teleport keys (Page Down / Home / End / Page Up and the Spaces through a talk) went out with only the
    tray looked at: into the window you'd gone to, or a Recall while you played, the bot off. Each is now behind PotionOk
    (the bot on, your hands off since the run began, Wizard101 in front, no battle) - the recording's own (tray menu)
    excepted - and a run you took over keeps its Mark for the next run instead of recalling.
  - The recorded replay looked at your hands only in the last 400 ms and not at all for an event already due; its click
    landed wherever the mouse was. Now since the run's start, right before every key and click, and the click AT x, y.
  - The shop's Fill All / BUY / OK clicks (ClickAt) clicked wherever the mouse was after the hover: PotionClickAt.
  - PotionOk pulled the game back in front before it saw you'd Alt+Tabbed away.
  - Review 2: those clicks also need the game in front as it is (not pulled back after the Crown read) and its window
    under the pointer (GameUnderMouse, as ClickAt) - PotionClickFine; no failure notices when PotionOk was the stop; the
    drink after buying gated too; a skipped Recall told to you when farming has no other way back.
  - NoCrownsNear (the never-spend-Crowns screen check) and QsConfirmOk (the last gate before SELL) pinned.
  - Carry mode: a flee by the carry made the main drink a potion / run / hold after the battle.
  - Quick sell: a tray run cut short with quicksell:0 left its windows open; a drop that came in during the run (after
    the look the guards went by) could be sold unjudged."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))


def read(*parts):
    with open(os.path.join(HERE, *parts), encoding="utf-8-sig") as f:
        return f.read().replace("\r\n", "\n")


def func(src, name):
    m = re.search(r"^" + name + r"\(.*?\n\t\}\n", src, re.M | re.S)
    assert m, name + " not found"
    return m.group(0)


def calls(text, name):
    """Each call's arguments (balanced parentheses) of name( in text."""
    out = []
    for m in re.finditer(r"\b" + name + r"\(", text):
        i, depth = m.end(), 1
        while depth:
            depth += {"(": 1, ")": -1}.get(text[i], 0)
            i += 1
        out.append(text[m.end():i - 1])
    return out


def code(text):
    """The lines that aren't comments, with a line's own trailing ; comment cut off."""
    out = []
    for ln in text.split("\n"):
        if ln.lstrip().startswith(";"):
            continue
        out.append(re.sub(r"\s+;\s.*$", "", ln))
    return "\n".join(out)


class PotionTeleportKeys(unittest.TestCase):
    def setUp(self):
        self.p = read("..", "Potions.ahk")

    def test_teleport_asks_potion_ok_before_its_key(self):
        f = code(func(self.p, "PotionTeleport"))
        self.assertIn("PotionTeleport(key, what, arrived := \"\", again := 0, since := 0, yours := false)", f)
        first_send = f.index('Send("{Blind}" key)')
        gate = f.index("if (!yours && !PotionOk(true, since))")
        self.assertLess(gate, first_send)
        self.assertIn("if (GameInTray)", f[gate:first_send])
        # every Space through a talk too, and the second go keeps since / yours
        space = f.index('Send("{Blind}{Space}")')
        self.assertIn("(!yours && !PotionOk(true, since))", f[f.index("Loop 4"):space])
        self.assertIn("return PotionTeleport(key, what, arrived, 1, since, yours)", f)

    def test_recall_kept_when_the_run_mayn_t_carry_on(self):
        f = code(func(self.p, "PotionRecall"))
        self.assertIn("PotionRecall(since := 0, yours := false)", f)
        gate = f.index("if (!yours && !PotionOk(true, since))")
        self.assertLess(gate, f.index("PotionTeleport("))
        # the mark isn't dropped on that path: it returns before PotionMarkZone := ""
        self.assertLess(f.index("return", gate), f.index('PotionMarkZone := ""'))

    def test_every_run_teleport_and_recall_passes_the_run_start(self):
        for name in ("PotionRun", "PotionRunMark", "PotionRunWalk", "PotionToCommons"):
            f = code(func(self.p, name))
            for args in calls(f, "PotionTeleport"):
                self.assertTrue(args.endswith(", 0, since"), name + ": " + args)
            for args in calls(f, "PotionRecall"):
                self.assertEqual(args, "since", name)
            for args in calls(f, "PotionReplay"):
                self.assertEqual(args, "route, since", name)

    def test_the_recording_s_own_keys_are_yours(self):
        f = code(func(self.p, "PotionRecordStart"))
        tele = calls(f, "PotionTeleport")
        self.assertEqual(len(tele), 2)
        for args in tele:
            self.assertTrue(args.endswith(", 0, 0, true"), args)
        # (saved, or a route's save failed: taken back from the Commons all the same)
        self.assertEqual(calls(f, "PotionRecall"), ["0, true", "0, true"])

    def test_page_down_marks_ask_potion_ok(self):
        for name in ("PotionRun", "PotionRunWalk"):
            f = code(func(self.p, name))
            pd = f.index('Send("{Blind}{PgDn}")')
            self.assertIn("if (!PotionOk(true, since))", f[max(0, pd - 300):pd], name)
            self.assertIn("if (GameInTray)", f[max(0, pd - 300):pd], name)

    def test_run_mark_checks_before_the_no_mark_notices(self):
        f = code(func(self.p, "PotionRunMark"))
        # (a run you started from the tray - PotionManual: only your last 400 ms)
        self.assertIn("since := PotionManual ? 0 : A_TickCount", f)
        self.assertLess(f.index("if (!PotionOk(true, since))"), f.index('PotionTeleport("{PgUp}"'))

    def test_home_alert_only_when_the_run_may_carry_on(self):
        f = code(func(self.p, "PotionRunWalk"))
        alert = f.index('"The Home key didn\'t lead to your house')
        self.assertIn("if (PotionOk(true, since))", f[max(0, alert - 400):alert])


class PotionReplayYields(unittest.TestCase):
    def setUp(self):
        self.f = code(func(read("..", "Potions.ahk"), "PotionReplay"))

    def test_since_the_run_start(self):
        self.assertIn("PotionReplay(route, since := 0)", self.f)
        self.assertIn("since := since ? since : t0", self.f)
        self.assertNotIn("PotionOk()", self.f)
        self.assertIn("if (!PotionOk(true, since))", self.f)

    def test_right_before_each_key(self):
        send = self.f.index('Send("{Blind}{" name (f[4] = "down" ? " down" : " up") "}")')
        self.assertIn("if (!PotionOk(true, since))", self.f[max(0, send - 250):send])

    def test_click_at_the_spot_after_the_checks(self):
        self.assertNotIn("Click()", self.f)
        click = self.f.index("Click(x, y)")
        before = self.f[:click]
        self.assertLess(before.index("if (!PotionOk(true, since))"), before.index("if (GameInTray || !PotionNoCrowns(x, y))"))
        hover = before.index("Sleep(120)")
        after_hover = before[hover:]
        self.assertIn('if (GameInTray || !PotionClickFine(x, y, since, "the route\'s click"))', after_hover)
        self.assertEqual(self.f.count("Click(x, y)"), 1)


class PotionShopClicks(unittest.TestCase):
    def setUp(self):
        self.p = read("..", "Potions.ahk")

    def test_click_at_checks_then_clicks_at_x_y(self):
        f = code(func(self.p, "PotionClickAt"))
        self.assertNotIn("Click()", f)
        hover = f.index("MoveToCard(x, y)")
        ok = f.index('pcaOk := !GameInTray && PotionClickFine(x, y, since, "the shop\'s button")')
        click = f.index("Click(x, y)")
        self.assertTrue(hover < ok < click)
        self.assertIn("if (pcaOk)", f[ok:click])
        self.assertIn("MouseLockOff(\"click\")", f[click:])

    def test_buy_here_clicks_only_through_it_each_after_a_crown_check(self):
        f = code(func(self.p, "PotionBuyHere"))
        self.assertNotRegex(f, r"\bClickAt\(")
        self.assertNotIn("Click(", f.replace("PotionClickAt(", ""))
        for m in re.finditer(r"PotionClickAt\((\w)\.x, \1\.y, 300, since\)", f):
            v = m.group(1)
            self.assertIn("PotionNoCrowns(%s.x, %s.y)" % (v, v), f[:m.start()], m.group(0))
        self.assertEqual(len(re.findall(r"PotionClickAt\(", f)), 3)

    def test_click_fine_game_in_front_as_it_is_then_ok_mouse_and_window(self):
        """Review 2 (2026-11-27): the shop's clicks lost ClickAt's GameUnderMouse; PotionOk brought a game that left the
        front during the Crown check's read back and passed - the click on a spot never read"""
        f = code(func(self.p, "PotionClickFine"))
        active = f.index("if (!GameActive())")
        ok = f.index("if (!PotionOk(true, since))")
        at = f.index("if (!PotionMouseAt(x, y))")
        under = f.index('if (V1IsFunc("GameUnderMouse") && !GameUnderMouse.Call(')
        self.assertTrue(active < ok < at < under)
        self.assertNotIn("GameToFront", f)
        self.assertEqual(f.count("return true"), 1)
        self.assertTrue(f.rstrip().endswith("return true\n\t}"))

    def test_mouse_at(self):
        f = code(func(self.p, "PotionMouseAt"))
        self.assertIn("return Abs(pmaX - x) <= 2 && Abs(pmaY - y) <= 2", f)


class PotionOkOrder(unittest.TestCase):
    def test_hands_before_bringing_the_game_to_the_front(self):
        f = code(func(read("..", "Potions.ahk"), "PotionOk"))
        bot = f.index("if (!WalkBotOn())")
        hands = f.index("if (watchHands && HandsOffOn() && (UserIdle() < 400 || (since && A_TickCount - UserIdle() > since)))")
        front = f.index('GameToFront.Call("the potion run is under way", false)')
        self.assertTrue(bot < hands < front)


class NoCrownsNearPinned(unittest.TestCase):
    """The never-spend-Crowns screen check: fails closed when the OCR can't run, refuses any crown / cr0wn."""

    def setUp(self):
        self.p = read("..", "Potions.ahk")
        self.f = code(func(self.p, "NoCrownsNear"))

    def test_fails_closed(self):
        ocr = self.f.index("text := OcrRect(")
        err = self.f.index("if (ErrorLevel)", ocr)
        self.assertLess(err, self.f.index("RegExMatch(text"))
        block = self.f[err:self.f.index("}", err)]
        self.assertIn("return false", block)
        self.assertNotIn("return true", block)
        # the only return true is the last line
        self.assertEqual(self.f.count("return true"), 1)
        self.assertTrue(self.f.rstrip().endswith("return true\n\t}"))

    def test_the_regex(self):
        self.assertIn('if (RegExMatch(text, "i)cr[o0]wn"))', self.f)
        rx = re.compile(r"(?i)cr[o0]wn")
        for seen in ("CROWNS", "Crowns", "crown", "Cr0wns", "CR0WN Equipment", "Buy with Crowns"):
            self.assertTrue(rx.search(seen), seen)
        for seen in ("Crow", "Gold", "FILL ALL", ""):
            self.assertFalse(rx.search(seen), seen)
        crown = self.f.index('if (RegExMatch(text, "i)cr[o0]wn"))')
        self.assertIn("return false", self.f[crown:self.f.index("}", crown)])

    def test_box_not_read_is_no_click(self):
        self.assertIn("r := (r = \"\" || V1Le(r, 0)) ? V1Round(V1Mul(260, UiScale)) : V1Round(r)", self.f)

    def test_every_quick_sell_click_after_it(self):
        q = read("..", "QuickSell.ahk")
        for name in ("QsClickBox", "QsClickTarget"):
            f = code(func(q, name))
            click = f.index("QsClickAt(")
            self.assertIn("NoCrownsNear(", f[:click], name)


class QsConfirmOkPinned(unittest.TestCase):
    """The last gate before quick sell's SELL (pure): each refusal branch."""

    def setUp(self):
        q = read("..", "QuickSell.ahk")
        self.f = code(func(q, "QsConfirmOk"))
        self.names = code(func(q, "QsConfirmNames"))

    def test_names(self):
        self.assertIn('["Equipment", "CrownEquipment", "Furniture", "CrownFurniture", "Jewels", "Reagents", "TreasureCards", "Pet", "Total"]', self.names)

    def refuses(self, cond):
        i = self.f.index(cond)
        block = self.f[i:self.f.index("}", i)]
        self.assertIn("return false", block, cond)

    def test_every_number_read(self):
        self.refuses('if (!IsObject(nums[qn]) || nums[qn].n = "" || nums[qn].gold = "")')

    def test_crown_rows(self):
        self.refuses("if (nums.CrownEquipment.n != 0 || nums.CrownFurniture.n != 0)")

    def test_pets_only_when_on(self):
        self.refuses("if (!pets && nums.Pet.n != 0)")

    def test_not_gear(self):
        self.assertIn('for qi, qn in ["Furniture", "Jewels", "Reagents", "TreasureCards"]', self.f)
        self.refuses("if (nums[qn].n != 0)")

    def test_totals(self):
        self.refuses("if (nums.Total.n < 1)")
        self.refuses("if (nums.Total.n != qSumN || nums.Total.gold != qSumG)")
        self.assertIn('if (qn != "Total")', self.f)

    def test_no_more_than_the_groups_hold(self):
        self.refuses('if (gearMax != "" && nums.Equipment.n > gearMax)')
        self.refuses('if (petMax != "" && nums.Pet.n > petMax)')

    def test_one_return_true_at_the_end(self):
        self.assertEqual(self.f.count("return true"), 1)
        self.assertGreater(self.f.index("return true"), self.f.index("nums.Pet.n > petMax"))

    def test_the_caller_stops_on_it(self):
        f = code(func(read("..", "QuickSell.ahk"), "QsConfirm"))
        self.assertRegex(f, r"qOk := QsConfirmOk\(")
        self.assertIn('return QsFail("the confirmation: " qWhy)', f)


class FleeByTheCarry(unittest.TestCase):
    def test_no_potion_on_the_main_for_the_carry_s_flee(self):
        f = code(func(read("..", "Flee.ahk"), "FleeCheck"))
        i = f.index('FleeWhy := (CarryOn && CarryTurn) ? "" : (InStr(why, "mana") || FleeNoMana >= 2) ? "mana" : "cards"')
        self.assertLess(i, f.index("FleeNoCards := 0, FleeNoMana := 0, FleeNoHits := 0"))
        self.assertLess(f.index("if (CarryOn && CarryTurn)\n\t\tDebugLog("), f.index("FleeNoCards := 0, FleeNoMana := 0"))


class QuickSellLeftoversAndChanges(unittest.TestCase):
    def setUp(self):
        self.q = read("..", "QuickSell.ahk")

    def test_leftovers_closed_with_quick_sell_off(self):
        f = code(func(self.q, "QsTick"))
        off = f.index("if (!qMode)")
        block = f[off:f.index("return", off)]
        self.assertIn("QsLeftoverTick()", block)
        self.assertNotIn("QsLeftover := 0", block)

    def test_bag_read_again_before_sell(self):
        f = code(func(self.q, "QsSteps"))
        same = f.index("qr := QsBagSame(bag)")
        self.assertLess(f.index("qr := QsSelectGroup(qc, &qn)"), same)
        self.assertLess(same, f.index('QsClickWait("buyWindow/sellAction"'))

    def test_bag_same(self):
        f = code(func(self.q, "QsBagSame"))
        self.assertIn("qNow := NavBag()", f)
        self.assertIn("qNow.items <= bag.items)", f)
        self.assertIn('res: "changed"', f)
        self.assertIn("back: 1", f)

    def test_changed_is_not_a_failure(self):
        f = code(func(self.q, "QsAfter"))
        i = f.index('else if (r.res = "changed")')
        self.assertLess(i, f.index("QsFails += 1"))
        self.assertNotIn("QsFails", f[i:f.index("}", i)])



class PotionReviewTwo(unittest.TestCase):
    """Review 2 (2026-11-27): notices sent when PotionOk was the stop, the drink after buying not gated, a skipped
    Recall said to nobody"""
    def setUp(self):
        self.p = read("..", "Potions.ahk")

    def test_no_seller_after_commons_notices_only_when_the_run_may_carry_on(self):
        f = code(func(self.p, "PotionRunWalk"))
        for text in ('"Out of potions - Home and the Commons (End)', '"Home and the Commons didn\'t lead'):
            at = f.index(text)
            self.assertIn("if (PotionOk(true, since))", f[max(0, at - 500):at], text)

    def test_no_recall_notices_only_when_the_run_may_carry_on(self):
        f = code(func(self.p, "PotionRunMark"))
        for text in ('"Out of potions, and Page Up (Recall) went nowhere.', '"The Recall to your Mark went nowhere'):
            at = f.index(text)
            self.assertIn("if (PotionOk(true, since))", f[max(0, at - 500):at], text)

    def test_drink_after_buying_only_while_the_run_may_carry_on(self):
        self.assertNotRegex(code(self.p), r"ok := PotionAfterBuy\(")
        for name, call in (("PotionRun", "PotionAfterBuy()"), ("PotionRunMark", "PotionAfterBuy()"),
                           ("PotionRunWalk", "PotionAfterBuy(true)")):
            # (fix2 last pass: the refusal kept - PotionRunCut - so FleeRefillMana drinks none after it either)
            self.assertIn("PotionRunCut := !PotionOk(true, since)\n\tok := PotionRunCut ? true : %s" % call,
                          code(func(self.p, name)), name)
            self.assertIn("global PotionRunCut", code(func(self.p, name)), name)
        self.assertIn("PotionRunCut := 0", code(func(self.p, "PotionRun")))
        self.assertIn("PotionRunCut := 0", code(func(self.p, "PotionsBlank")))
        frm = code(func(read("..", "Flee.ahk"), "FleeRefillMana"))
        self.assertRegex(frm, r'if \(PotionRun\(\)\)\s*\{\s*if \(PotionRunCut\)\s*\{[^{}]*return true\s*\}\s*now := ')
        self.assertIn("PotionOk(true, since) && FleeDrinkForMana(manaLeft)", code(func(self.p, "PotionRunWalk")))

    def test_skipped_recall_told_when_farming(self):
        f = code(func(self.p, "PotionRecall"))
        skip = f.index("if (!yours && !PotionOk(true, since))")
        told = f[skip:f.index('DebugLog("Potions: back to the mark (Page Up)")')]
        self.assertIn("if (afkVar || loopmode || loremode)", told)
        self.assertIn("TrayTip(", told)
        self.assertIn('AlertSend("potions", ', told)
        self.assertIn("return", told)

if __name__ == "__main__":
    unittest.main()
