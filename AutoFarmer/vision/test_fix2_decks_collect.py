"""test_fix2_decks_collect.py - the code review's decks and collect findings (2026-11-27). Standard library only:
python -m unittest test_fix2_decks_collect  (from AutoFarmer\\vision)

  - UseX / UseTalkX took any "crown" in the prompt box for Crowns - the quest's own line over it too ("Collect Crown
    Shards in ...", every goal in Baobab Crown): each thing was left for good at the first look. WalkPromptCrowns now.
  - An OCR failure read as "no prompt": the use / talk steps' X in case, and the collect step's X standing on an item -
    which looked at no prompt at all (a sigil's, a teleport stone's by it) - now need a good read.
  - The collect step swapped between two items round a wall, each swap starting its minute again.
  - Decks: a linked deck kept an Equipment Set its in-game deck had left; a rejected Set took the key off learned|; a
    deleted learned deck came back within 30 minutes; deckzone picked a deck no set puts on; /sim and /decks?fresh=1
    ran with W held."""
import os
import re
import unittest

import deckmem

HERE = os.path.dirname(os.path.abspath(__file__))


def read(*parts):
    with open(os.path.join(HERE, *parts), encoding="utf-8-sig") as f:
        return f.read().replace("\r\n", "\n")


def func(src, name):
    m = re.search(r"^" + name + r"\(.*?\n\t\}\n", src, re.M | re.S)
    assert m, name + " not found"
    return m.group(0)


class CollectCrowns(unittest.TestCase):
    def setUp(self):
        self.c = read("..", "Collect.ahk")

    def test_use_and_talk_x_use_walk_prompt_crowns(self):
        for name in ("UseX", "UseTalkX"):
            f = func(self.c, name)
            self.assertIn("if (WalkPromptCrowns())\n", f, name)
            self.assertNotIn('RegExMatch(WkPromptText, "i)cr[o0]wn")', f, name)

    def test_no_plain_crown_test_left(self):
        code = "\n".join(ln for ln in self.c.split("\n") if not ln.lstrip().startswith(";"))
        self.assertNotIn('RegExMatch(WkPromptText, "i)cr[o0]wn")', code)


class FailedReads(unittest.TestCase):
    def setUp(self):
        self.c = read("..", "Collect.ahk")

    def test_prompt_read_tells_a_failed_read(self):
        f = func(self.c, "CollectPromptRead")
        self.assertIn("cprP := InteractPrompt()", f)
        self.assertIn('return (cprP = "" && ErrorLevel) ? "?" : cprP', f)

    def test_use_and_talk_steps_read_through_it(self):
        for name in ("UseStep", "TalkStep"):
            f = func(self.c, name)
            self.assertIn("UsPrompt := CollectPromptRead()", f, name)
            self.assertNotIn("UsPrompt := InteractPrompt()", f, name)
            # (the X in case still needs a good read that came back empty)
            self.assertIn('UsPrompt = "" && UsPromptAt', f, name)


class StandingOnAnItem(unittest.TestCase):
    def setUp(self):
        self.f = func(read("..", "Collect.ahk"), "CollectItemStep")

    def test_x_on_it_looks_at_the_prompt(self):
        f = self.f
        at = f.index("if (d <= 45 &&")
        on = f[at:f.index("CiOnAt := 0", at)]
        self.assertIn('it.z = "" ||', on)                       # (a blank height never subtracted)
        self.assertIn("A_TickCount >= V1N(WkQuietUntil)", on)   # (not in the quiet time after a dialogue)
        self.assertIn('(ciSaw = "" && !WalkPromptCrowns())', on)
        self.assertIn('ciSaw = "press" && CollectPromptSafe()', on)
        self.assertIn('w[o0]rld\\s*gate|spiral', on)
        # (the X only inside the prompt check)
        self.assertLess(on.index("if ((ciSaw"), on.index('PressKey("x")'))

    def test_the_300_block_uses_the_same_rules(self):
        self.assertIn('ciSaw := "-"', self.f)
        self.assertIn('if (ciSaw = "press" && CollectPromptSafe()', self.f)
        g = func(read("..", "Collect.ahk"), "CollectPromptSafe")
        self.assertIn("!WalkPromptCrowns()", g)
        self.assertIn("i)teleport", g)
        self.assertIn("|enter)", g)

    def test_static_at_the_top(self):
        self.assertRegex(self.f, r"^CollectItemStep\(goal\)\n\t\{\n(\tglobal [^\n]*\n)+\tstatic ciNoXSaid := 0")

    def test_the_item_walked_to_is_kept(self):
        f = self.f
        self.assertIn("if (CiGid != \"\" && x.gid = CiGid)\n\t\t\t\tciNow := x", f)
        self.assertIn("if (IsObject(ciNow) && !(V1IsNum(it.dist) && V1IsNum(ciNow.dist) && it.dist <= 200 && it.dist < ciNow.dist / 2))\n"
                      "\t\tit := ciNow", f)
        self.assertLess(f.index("it := ciNow"), f.index("if (it.gid != CiGid)"))


def pick(items, cigid):
    """CollectItemStep's choice, in Python (items nearest first, each {gid, dist})"""
    it = items[0] if items else None
    now = next((x for x in items if cigid != "" and x["gid"] == cigid), None)
    if now is not None and not (it["dist"] <= 200 and it["dist"] < now["dist"] / 2):
        it = now
    return it


class ItemChoice(unittest.TestCase):
    def test_no_swap_round_a_wall(self):
        self.assertEqual(pick([{"gid": "b", "dist": 350}, {"gid": "a", "dist": 400}], "a")["gid"], "a")

    def test_one_right_by_the_wizard_first(self):
        self.assertEqual(pick([{"gid": "b", "dist": 120}, {"gid": "a", "dist": 900}], "a")["gid"], "b")

    def test_none_walked_to_the_nearest(self):
        self.assertEqual(pick([{"gid": "b", "dist": 350}, {"gid": "a", "dist": 400}], "")["gid"], "b")


class DeckSets(unittest.TestCase):
    def setUp(self):
        self.d = read("..", "Decks.ahk")

    def test_deck_line_field_5_is_the_sets(self):
        r = {"decks": [{"gid": 0xABC, "where": "backpack", "equipped": False, "sets": [2, 3]},
                       {"gid": 0xDEF, "where": "equipped", "equipped": True, "sets": []}], "equipped": 0xDEF}
        lines = [ln.split("|") for ln in deckmem.deck_lines(r) if ln.startswith("deck|")]
        self.assertEqual([(f[1], f[4]) for f in lines], [("abc", "2,3"), ("def", "")])   # (AutoHotkey's dlgF[2], dlgF[5])

    def test_learn_reads_the_sets(self):
        f = func(self.d, "DeckLearnGame")
        self.assertIn('if (V1At(dlgF, 1) = "deck" && dlgF.Length >= 5', f)
        self.assertIn('dlgSets[StrLower(Trim(dlgF[2]))] := "," Trim(dlgF[5]) ","', f)
        self.assertIn("if (!dlgSetsOk || InStr(dlgAns, \"couldn't be read whole\"))\n\t\tdlgSets := V1Obj()", f)
        self.assertIn("DeckLearnOne(dlgL, &dlgNew, dlgSets, manual)", f)
        # (a linked deck with no learn line, out of its set: cleared - only one the reading lists)
        self.assertIn("dlgDone.Has(dlgD.game) || !dlgSets.Has(dlgD.game)", f)

    def test_learn_one_clears_a_set_left(self):
        f = func(self.d, "DeckLearnOne")
        self.assertIn('else if (!L.eqset && dloD.eqset && IsObject(sets) && sets.Has(L.gid) && !InStr(sets[L.gid], "," dloD.eqset ","))', f)

    def test_unlearn_after_the_check(self):
        f = func(self.d, "DeckValSetClear")
        self.assertLess(f.index("DeckSay(DeckS.label"), f.index("DeckUnlearn(DeckEdit, DeckKey, false)"))
        self.assertIn("DeckUnlearn(DeckEdit, DeckKey, true), DeckEdit.vals.Delete(DeckKey)", f)
        self.assertEqual(f.count("DeckUnlearn("), 2)

    def test_deleted_decks_stay_deleted(self):
        self.assertIn("DeckGone(DeckEdit.game, 1)", func(self.d, "DeckDelClick"))
        f = func(self.d, "DeckLearnOne")
        self.assertIn("if (!manual && DeckGone(L.gid))\n\t\t\treturn \"gone\"", f)
        # gone stops only the making: a deck of yours on its Equipment Set is still linked first
        self.assertLess(f.index("if (!IsObject(dloD) && L.eqset)"), f.index("DeckGone(L.gid)"))
        self.assertLess(f.index("DeckGone(L.gid)"), f.index("if (DeckList.Length >= 6)"))
        # off the gone list only once made or linked and saved, never before the full check
        self.assertEqual(f.count("DeckGone(L.gid, -1)"), 1)
        self.assertIn("if (DeckSave(dloD) && (isNew || dloLink))\n\t\tDeckGone(L.gid, -1)", f)
        self.assertLess(f.index('return "full"'), f.index("DeckGone(L.gid, -1)"))
        self.assertIn("dloD.game := L.gid, dloLink := true,", f)
        g = func(self.d, "DeckGone")
        self.assertIn('IniRead(A_ScriptDir "\\dashboard.ini", "decks", "gone", A_Space)', g)

    def test_deckzone_never_a_deck_with_no_set(self):
        f = func(self.d, "DeckForZone")
        self.assertIn('if (dfzD.game = "" || !dfzD.eqset || !dfzRes.Has(dfzD.game)', f)

    def test_keys_let_go_before_slow_reads(self):
        f = func(self.d, "DeckBeat")
        self.assertLess(f.index("ReleaseKeys(true)"), f.index("dbAns := VisionGet(dbQ"))
        g = func(self.d, "DeckLearnGame")
        self.assertLess(g.index("ReleaseKeys(true)"), g.index('VisionGet("/decks?fresh=1&ob=1"'))

    def test_line_endings_kept(self):
        for name in ("Decks.ahk", "Collect.ahk"):
            with open(os.path.join(HERE, "..", name), "rb") as fh:
                self.assertNotIn(b"\r\n", fh.read(), name)


if __name__ == "__main__":
    unittest.main()
