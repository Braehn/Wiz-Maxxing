"""test_talk_x.py - X at quest goals: a talk goal's NPC walked up to within X's reach, a part-named thing taken for the goal's
item when its template names the rest. Standard library only: python -m unittest test_talk_x  (from AutoFarmer\\vision)

2026-11-22 (JSHSRVRWINB, Zafaria, UI 0.856):
  - every talk: the approach stopped at TalkUnits (300) - 313-347 off with its early let-go - and X there opened nothing,
    9 times of 9 (Esop Thornpaw, Kakuta Darkmane, Hannibal Onetusk x3, Kiliman Copperleaf, Amar Sharptusk, Rakstede
    Steelhorn); the X again from 127-185 off talked 7 times of 7. Each wasted ~4 s and a try - with Hannibal's prompt read 'HANNIEALMCTUSK...'
    the 3 tries ran out: NEEDS YOU "Talking to Hannibal Onetusk didn't work" (19:22:30) till the user talked to him.
  - "Collect Library Book in Baobab Crown": the game's memory names the item "Library Book" (key WizQst71A28_00000011);
    the Library Classroom's thing is "Book" (WizItems_00001791, template ZF-Library_Book, at -1983, 707 - right where the
    game's arrow pointed). whole_name("Book", "Library Book") is false: "none of the goal's things", 45 minutes of
    looking about and 5 "Way blocked" notices (18:35-19:21) till the user picked it up."""
import os
import re
import sys
import unittest

if os.path.dirname(os.path.abspath(__file__)) not in sys.path:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from test_tray import ahk_code  # noqa: E402  (AutoHotkey lines without their comments)

import vision as V

HERE = os.path.dirname(os.path.abspath(__file__))


def code(src):
    """src's AutoHotkey code (test_tray's ahk_code): comment lines and /* */ blocks gone, each line cut at its ' ;' - a
    pinned line commented out is gone, not still there for assertIn and index (fix2, x-tests-2)"""
    return "".join(ln.rstrip() + "\n" for ln in ahk_code(src.split("\n")) if ln.strip())


def read(*parts):
    """the file's text - an AutoHotkey file's code only (code: its comments gone)"""
    with open(os.path.join(HERE, *parts), encoding="utf-8-sig") as f:
        text = f.read().replace("\r\n", "\n")
    return code(text) if parts[-1].lower().endswith(".ahk") else text


def func(src, name):
    m = re.search(r"^" + name + r"\(.*?\n\t\}\n", src, re.M | re.S)
    assert m, name + " not found"
    return m.group(0)


class PartByTemplate(unittest.TestCase):
    GOAL = {"text": "Collect Library Book in Baobab Crown", "exact": True, "item": "Library Book",
            "item_key": "WizQst71A28_00000011"}
    BOOK = {"name": "Book", "key": "WizItems_00001791", "keys": ["WizItems_00001791"], "kind": "item",
            "template": "ZF-Library_Book", "src": "file"}

    def test_the_library_book(self):
        self.assertTrue(V.part_by_template("Book", "ZF-Library_Book", "Library Book"))
        self.assertTrue(V.quest_item(self.BOOK, "", self.GOAL, key_hit=False))
        self.assertTrue(V.quest_item(dict(self.BOOK, src="mem", keys=None), "", self.GOAL, key_hit=False))
        # (camel case and a plural)
        self.assertTrue(V.part_by_template("Book", "ZF_LibraryBook", "Library Books"))

    def test_on_the_old_rule(self):
        # (what the bot did: whole names only)
        self.assertFalse(V.whole_name("Book", "Library Book"))

    def test_not_a_part_named_alone(self):
        # (whole_name's pairs: the template doesn't name the rest)
        self.assertFalse(V.part_by_template("Urn", "KT_Urn", "Urn Piece"))
        self.assertFalse(V.part_by_template("Teleporter", "WC_Teleporter", "To Teleporter Hub"))
        self.assertFalse(V.part_by_template("Portal Piece", "DS_PortalPiece", "Third Portal Piece"))
        self.assertFalse(V.part_by_template("Book", "ZF_Book", "Library Book"))
        # (a name with a word of its own isn't a part of the item)
        self.assertFalse(V.part_by_template("Spell Book", "ZF-Library_Book", "Library Book"))
        # (the whole name: whole_name's, not this)
        self.assertFalse(V.part_by_template("Library Book", "ZF-Library_Book", "Library Book"))
        for bad in ("", None):
            self.assertFalse(V.part_by_template("Book", bad, "Library Book"))
            self.assertFalse(V.part_by_template(bad, "ZF-Library_Book", "Library Book"))
            self.assertFalse(V.part_by_template("Book", "ZF-Library_Book", bad))

    def test_not_an_npc_or_a_mob(self):
        for kind in ("npc", "mob"):
            self.assertFalse(V.quest_item(dict(self.BOOK, kind=kind), "", self.GOAL, key_hit=False), kind)

    def test_the_goals_key_still_decides(self):
        # (a thing listed with the goal's own key: only those are the quest's - the 4 Inactive Protectors)
        self.assertFalse(V.quest_item(self.BOOK, "", self.GOAL, key_hit=True))

    def test_the_lever(self):
        # (test_puzzlefile's: a nameless use thing never by its name)
        self.assertFalse(V.quest_item({"name": "", "kind": "use", "template": "Lever"}, "Use the Lever",
                                      {"text": "Use the Lever", "exact": True, "item": "Lever"}))

    def test_name_words(self):
        self.assertEqual(V.name_words("ZF-Library_Book"), ["zf", "library", "book"])
        self.assertEqual(V.name_words("GH_GloomWoodBark"), ["gh", "gloom", "wood", "bark"])
        self.assertEqual(V.name_words("Pieces of Coral"), ["piece", "of", "coral"])
        self.assertEqual(V.name_words("Glass"), ["glass"])


class TalkApproach(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.w = read("..", "..", "AutoQuester", "Walker.ahk")

    def test_settings(self):
        init = func(self.w, "WalkerInit")
        # (fix2: the code only - read() leaves the comments out: each setting's line ends at its value)
        self.assertRegex(init, r"\n\tTalkUnits := 300\n")
        self.assertRegex(init, r"\n\tTalkStop := 120\n")
        self.assertRegex(init, r"\n\tTalkXReach := 185\n")
        self.assertIn("\tglobal TalkStop, TalkXReach\n", init)
        blank = func(self.w, "WalkerBlank")
        self.assertIn('TalkStop := "", TalkXReach := "", WkNpcNearAt := "", WkNpcNear := ""', blank)

    def test_the_approach_stops_within_reach(self):
        step = func(self.w, "WalkApproachStep")
        self.assertIn("asStop := IsObject(asTalk) ? TalkStop : ArriveUnits", step)
        self.assertNotIn("? TalkUnits : ArriveUnits", step)
        # (stopped short - past it, off to the side, the time up - within TalkXReach - 40 on the same floor (the reading's on
        # the move): X there; stopped by something within TalkUnits of the NPC: X, as before)
        self.assertIn('if (asWhy = "there" || asNow.r <= asStop || (IsObject(asTalk) && asNow.r <= TalkXReach - 40 '
                      '&& (asNow.dz = "" || Abs(asNow.dz) <= 150))\n'
                      '\t\t|| (asWhy = "blocked" && IsObject(asTalk) && asNow.r <= TalkUnits && (asNow.dz = "" || Abs(asNow.dz) <= 150))\n'
                      '\t\t|| (asWhy = "blocked" && asNow.r <= TalkReach && !WalkRouteRound(asNow.r)))', step)
        self.assertIn("didn't get within \" (IsObject(asTalk) ? TalkXReach - 40 : asStop) \" of the goal", step)

    def test_x_again_walks_up_first(self):
        # (X again from over TalkXReach off: walked up to TalkStop first - not X'd again from where X didn't reach)
        again = func(self.w, "WalkTalkAgain")
        self.assertIn("if (IsObject(taGoal) && taGoal.r > TalkXReach)\n\t\t{\n\t\ttaFrom := taGoal.r\n"
                      "\t\ttaWhy := WalkApproach(TalkStop)", again)

    def test_garbled_name_by_memory(self):
        ig = func(self.w, "WalkIsGoalNpc")
        self.assertTrue(ig.rstrip().endswith("return WalkGoalNpcByMem(tg, inName)\n\t}"), ig[-200:])
        by = func(self.w, "WalkGoalNpcByMem")
        self.assertIn('WkNpcNear := %"NavItems"%.Call("", false, 800)', by)
        self.assertIn("return gbGoal != \"\" && gbGoal <= 200 && (gbOther = \"\" || gbOther >= gbGoal + 100)", by)
        self.assertIn("if (!WkNpcNearAt || A_TickCount - WkNpcNearAt > 1500)", by)
        # (never a mob, an item, a use thing; measured from where the wizard is now; another: an NPC - its name unread too -,
        # no kind, a named ambient one, an object with an NPC's or a shop's template)
        self.assertIn('if (gbT.kind = "mob" || gbT.kind = "item" || gbT.kind = "use")\n\t\t\tcontinue', by)
        self.assertIn("gbD := (IsObject(gbMe) && gbT.x != \"\" && gbT.y != \"\") ? Sqrt((gbT.x - gbMe.x) ** 2 + (gbT.y - gbMe.y) ** 2) "
                      ": gbT.dist", by)
        self.assertIn('else if (gbT.kind = "npc" || gbT.kind = "" || (gbT.kind = "ambient" && gbT.name != "")\n'
                      '\t\t\t|| RegExMatch(gbT.template, "i)npc|shopkeep|vendor|merchant|stand-?in"))', by)
        self.assertNotIn("\r\n", self.w)                               # (Walker.ahk's own LF line ends)


class PartTwins(unittest.TestCase):
    """Nastrond (Grizzleheim/GH_HFjord/GH_Nastrond): 8 blank stones named 'Rune' (GH2-Blank-rune-stone) would answer 'Rune
    stone' by part of the name; 4 lettered stones named 'Rune' too (GH2-Runestone-Y/M/I/R, one word: not matched) stand within
    ~12 of 4 of them - there the name doesn't tell which is meant"""
    GOAL = {"text": "Use Rune stone in Nastrond", "exact": True, "item": "Rune stone", "item_key": "wizqst63e8e_00000022"}

    def thing(self, tpl, x, y):
        return {"name": "Rune", "pos": (x, y, 0.0), "template": tpl, "key": "WizardGameObjects_00000407",
                "keys": ["WizardGameObjects_00000407"], "kind": "object", "src": "file"}

    def test_a_lettered_twin_by_it(self):
        blank_alone, blank_by, lettered = (self.thing("GH2-Blank-rune-stone", 7181, -13593),
                                           self.thing("GH2-Blank-rune-stone", 7439, -13549),
                                           self.thing("GH2-Runestone-R", 7440, -13560))
        things = [blank_alone, blank_by, lettered]
        for t in things:
            t["quest"] = V.quest_item(t, "", self.GOAL, key_hit=False)
        self.assertEqual([t["quest"] for t in things], [True, True, False])
        V.part_twins(things, self.GOAL)
        self.assertEqual([t["quest"] for t in things], [True, False, False])

    def test_an_effect_on_the_spot_isnt_a_twin(self):
        # (Wysteria/PA_Z02_Tanglewood: 'Fountain' PA-PiggleFountain at 1299, 2784 and 'Fountain' PA-PiggleFountState 10 off -
        # its template says 'fount', it couldn't name 'Piggle Fountain': the fountain stays the goal's)
        goal = {"text": "Use Piggle Fountain in Tanglewood Way", "exact": True, "item": "Piggle Fountain",
                "item_key": "WizQst73472_00000007"}
        mk = lambda tpl, x, y: {"name": "Fountain", "pos": (x, y, 0.0), "template": tpl, "key": "WizardGameObjects_00000473",
                                "keys": ["WizardGameObjects_00000473"], "kind": "object", "src": "file"}
        real, state = mk("PA-PiggleFountain", 1299, 2784), mk("PA-PiggleFountState", 1291, 2790)
        things = [real, state]
        for t in things:
            t["quest"] = V.quest_item(t, "", goal, key_hit=False)
        self.assertEqual([t["quest"] for t in things], [True, False])
        V.part_twins(things, goal)
        self.assertEqual([t["quest"] for t in things], [True, False])
        # (KT_KaranahnPalace: a Tree Obelisk stacked on the Skull one doesn't drop it for 'Skull Obelisk')
        goal = {"text": "Use Skull Obelisk", "exact": True, "item": "Skull Obelisk", "item_key": "wizqst15803_x"}
        mk2 = lambda tpl: {"name": "Obelisk", "pos": (9645.0, -5051.0, 0.0), "template": tpl, "kind": "object", "src": "file"}
        skull, tree = mk2("KT_Obelisk_Skull"), mk2("KT_Obelisk_Tree")
        for t in (skull, tree):
            t["quest"] = V.quest_item(t, "", goal, key_hit=False)
        V.part_twins([skull, tree], goal)
        self.assertEqual([skull["quest"], tree["quest"]], [True, False])
        self.assertTrue(V.part_twin_named({"template": "GH2-Runestone-R"}, ["rune", "stone"]))
        self.assertFalse(V.part_twin_named({"template": "PA-PiggleFountState"}, ["piggle", "fountain"]))
        self.assertFalse(V.part_twin_named({"template": ""}, ["piggle", "fountain"]))

    def test_the_book_kept(self):
        book = dict(PartByTemplate.BOOK, pos=(-1982.7, 707.2, 160.0), quest=True)
        kiliman = {"name": "Kiliman Copperleaf", "pos": (-2633.6, -10.4, 510.5), "kind": "npc", "quest": False}
        V.part_twins([book, kiliman], PartByTemplate.GOAL)
        self.assertTrue(book["quest"])

    def test_whole_names_never_dropped(self):
        a = {"name": "Library Book", "pos": (0.0, 0.0, 0.0), "template": "X_Library_Book", "kind": "item", "quest": True}
        b = {"name": "Library Book", "pos": (10.0, 0.0, 0.0), "template": "X_Other", "kind": "item", "quest": False}
        V.part_twins([a, b], PartByTemplate.GOAL)
        self.assertTrue(a["quest"])

    def test_wired_in(self):
        src = read("vision.py")
        self.assertIn("        it['quest'] = quest_item(it, goal_line, goal, key_hit)\n    if not key_hit:\n"
                      "        part_twins(things, goal)\n", src)


class TightSteer(unittest.TestCase):
    """2026-11-22 18:28-18:31, Evil Magma Peas: the wizard ran round the peas (92 off, then 921 off 30 s later; W held 82-100%
    of the time, no turn on the spot - a turning circle of 310-342 at ~820 a second) and the arcs swept him into the Redbands
    Hut's doorway twice. A walk to a thing (Collect.ahk) turns on the spot when the thing is inside the circle he can't run to"""

    @classmethod
    def setUpClass(cls):
        cls.d = read("..", "Dungeons.ahk")
        cls.c = read("..", "Collect.ahk")

    def test_rule(self):
        f = func(self.d, "DgSteer")
        self.assertTrue(f.startswith("DgSteer(nav, p, d, tight := false)\n"))
        # (never while the route leads out of a mob's ring or sight: standing turning in it is how it catches the wizard)
        self.assertIn("if (tight && Abs(h) > 25 && d != \"\" && nav.escape = \"\")\n", f)
        self.assertIn("if (Abs(h) > 90 || d < Min(700, 2 * dsR * Sin(Abs(h) * 0.0174533) + 60))\n\t\t\t{\n\t\t\tHoldW(0)\n"
                      "\t\t\tif (IsObject(WkMet))\n\t\t\t\tWkMet.spot += 1\n", f)
        # (before the old big-turn rule and the walking-on branch)
        self.assertLess(f.index("if (tight &&"), f.index("if (Abs(h) > 60 && d < 250)"))
        self.assertNotIn("\r\n", self.d)

    def test_geometry(self):
        # (a thing at distance d, h degrees off, can't be reached running round a circle of radius R when d < 2 R sin h)
        import math
        R = 314
        for h, d, inside in ((30, 300, True), (30, 400, False), (60, 560, True), (20, 200, False), (100, 900, True)):
            got = abs(h) > 25 and (abs(h) > 90 or d < min(700, 2 * R * math.sin(math.radians(abs(h))) + 60))
            self.assertEqual(got, inside, (h, d))

    def test_walks_to_things_only(self):
        for line in ("DgSteer(nav, V1Obj({x: it.x, y: it.y}), d, true)", "DgSteer(usNav, V1Obj({x: UsIt.x, y: UsIt.y}), usDist, true)",
                     "DgSteer(tsNav, V1Obj({x: UsIt.x, y: UsIt.y}), tsD, true)"):
            self.assertIn(line, self.c)
        self.assertEqual(self.c.count("DgSteer(gsNav, V1Obj({x: UsIt.x, y: UsIt.y}), gsD, true)"), 2)
        calls = [ln for ln in self.c.split("\n") if "DgSteer(" in ln]
        self.assertEqual(len(calls), 5)
        self.assertTrue(all(ln.rstrip().endswith(", true)") for ln in calls), calls)  # (every Collect.ahk call passes tight)
        for f in ("Dungeons.ahk", "Party.ahk", "Puzzle.ahk"):
            self.assertNotRegex(read("..", f), r"DgSteer\([^\n]*, true\)", f)

    def test_escape_from_navto(self):
        src = read("vision.py")
        self.assertIn("+ ([f\"escape|{goal_cell(res['escape'])}\"] if res.get('escape') else []))", src)
        party = read("..", "Party.ahk")
        nt = func(party, "PartyNavTo")
        self.assertIn('why: "", zone: "", escape: ""})', nt)
        self.assertIn('else if (f[1] = "escape")\n\t\t\tnav.escape := f[2]', nt)

    def test_prompt_by_it_logged(self):
        step = func(self.c, "UseStep")
        self.assertIn('if (UsPrompt = "press" && (!UsPromptSaidAt || A_TickCount - UsPromptSaidAt >= 5000))', step)
        self.assertIn("\tglobal UsPromptSaidAt\n", step)
        self.assertIn('UsPromptSaidAt := ""', func(self.c, "CollectBlank"))


if __name__ == "__main__":
    unittest.main()
