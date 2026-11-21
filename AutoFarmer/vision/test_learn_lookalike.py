"""test_learn_lookalike.py - look-alike cards learned by the game's names, the AutoHotkey side read (not run).
Standard library only: python -m unittest test_learn_lookalike  (from AutoFarmer\\vision)

2026-11-21 (UI 0.856, a fresh install learning every card again): Balanceblade's and Bladestorm's learned pictures are
mostly the same white disc, so the helper took a Bladestorm for a copy of the Balanceblade left of it (CardLearn.ahk
LearnCards' card.same) and never learned it; from then on Balanceblade's picture named every Bladestorm, LearnMemHand left
those boxes out (the game's name differs) and the bot left the blades uncast. Pins: with the game's hand on the boxes, a copy
is told by the game's name (memNew), not the picture; a box whose learned picture the game names otherwise, where the
memory has its card within Px(10) with one game window, is paired anyway with its name taken off (3 tries a card a run),
and LearnCards then learns it as the new card it is - before its name reaches a hit slot's SlotGame."""
import re
import unittest

from test_blades import func, read


class LookAlike(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cl = read("CardLearn.ahk")
        cls.lc = func(cls.cl, "LearnCards")
        cls.lm = func(cls.cl, "LearnMemHand")

    def test_copies_by_the_games_name(self):
        lc = self.lc
        self.assertLess(lc.index("memNew := V1Obj()"), lc.index("Loop Parse, answer"))
        self.assertIn("else if (IsObject(card.mem) ? memNew.Has(LearnMemGame(card.mem)) : card.same)\n\t\t\tcontinue", lc)
        # (a relearn whose card is known by now - earlier in this look - isn't learned again)
        m = re.search(r"if \(V1At\(card, \"relearn\"\) = \"\" \|\| !LearnGameKnown\(LearnMemGame\(card\.mem\)\)\)\n\t+\{\n"
                      r"\t+fresh\+\+\n\t+if \(IsObject\(card\.mem\)\)\n\t+memNew\[LearnMemGame\(card\.mem\)\] := 1\n(?:\t*;[^\n]*\n)*"
                      r"\t+if \(V1At\(card, \"relearn\"\) != \"\"\)\n\t+LearnRelearnCount\(card\.relearn, 1\)\n\t+placed \+= LearnNew\(card\)", lc)
        self.assertIsNotNone(m, "the name noted and a relearn's try counted right before LearnNew, in the fresh branch only")
        self.assertEqual(lc.count("memNew["), 1)
        self.assertEqual(lc.count("LearnRelearnCount("), 1)

    def test_false_match_name_taken_off_before_slot_game(self):
        lc = self.lc
        clear = lc.index("card.known := \"\"")
        self.assertLess(lc.index("card := V1Obj({left:"), clear)
        self.assertLess(clear, lc.index("SlotGame[card.known]"))
        self.assertLess(clear, lc.index("if (card.known != \"\")\n\t\t\tplaced += LearnSeenAgain(card)"))
        # (only the boxes LearnMemHand paired as a false match - not worked out again from the learned cards mid-loop)
        self.assertRegex(lc, r'if \(IsObject\(card\.mem\) && card\.known != "" && relearnBoxes\.Has\(boxes\)\)\n\t+card\.known := "", card\.relearn := relearnBoxes\[boxes\]')
        self.assertNotIn("lcK", lc)
        self.assertRegex(lc, r"mem := LearnMemHand\(answer\)\n\trelearnBoxes := LearnRelearnBoxes\(\)\n")

    def test_mem_hand_pairs_a_sure_false_match(self):
        lm = self.lm
        self.assertIn("static saidRelearn := V1Obj()", lm)
        self.assertNotIn("relearnTries", lm)
        self.assertIn("x: lmhF[2] + lmhF[4] / 2, y: lmhF[3] + lmhF[5] / 2", lm)
        m = re.search(r'if \(lmhWas != "" && lmhWas != LearnMemGame\(lmhM\)\)\n\t+\{\n(.*?)\n\t\t\t\}\n\t\tlmhOut\[lmhB\.n\] := lmhM', lm, re.S)
        self.assertIsNotNone(m)
        branch = m.group(1)
        # (only while no learned card is the game's card already - no duplicate record - and 3 learned at most this run)
        self.assertRegex(branch, r'if \(VisionMemOneClient\(\) && VisionCardPx\(lmhHand, lmhM, &lmhX, &lmhY\) && Max\(Abs\(lmhX - lmhB\.x\), Abs\(lmhY - lmhB\.y\)\) <= Px\(10\)'
                                 r'\n\t+&& LearnRelearnCount\(lmhKey\) < 3 && !LearnGameKnown\(LearnMemGame\(lmhM\)\)\)')
        sure, other = branch.split("\n\t\t\telse\n")
        self.assertIn('lmhB.known := "", lmhRel[lmhB.n] := lmhKey', sure)
        self.assertNotIn("continue", sure)
        # (this look's set emptied first - before any return)
        self.assertLess(lm.index("lmhRel := V1Obj(), LearnRelearnBoxes(lmhRel)"), lm.index("lmhHand := VisionCards("))
        self.assertNotIn("LearnRelearnCount(lmhKey, 1)", sure)
        self.assertIn("that box left out (said once)", other)
        self.assertIn("continue", other)
        # (the name taken off before the grouping of boxes found as one learned card)
        self.assertLess(lm.index('lmhB.known := ""'), lm.index("lmhBy := V1Obj()"))

    def test_helpers(self):
        """the run's count of relearns (counted only when learned) and the duplicate guard over this school's and shared cards"""
        rc = func(self.cl, "LearnRelearnCount")
        self.assertIn("static tries := V1Obj()", rc)
        self.assertRegex(rc, r"if \(add\)\n\t\ttries\[key\] := V1N\(V1At\(tries, key\)\) \+ add\n\treturn V1N\(V1At\(tries, key\)\)")
        rb = func(self.cl, "LearnRelearnBoxes")
        self.assertRegex(rb, r"static boxes := V1Obj\(\)\n\tif \(IsObject\(set\)\)\n\t\tboxes := set\n\treturn boxes")
        gk = func(self.cl, "LearnGameKnown")
        self.assertIn('if ((c.sch = hitschool || InStr(c.slot, "resources\\") = 1) && LearnFlag(c, "game") = name)', gk)
        self.assertRegex(gk, r'if \(name = "" \|\| !IsObject\(LearnedCards\)\)\n\t\treturn false')


if __name__ == "__main__":
    unittest.main()
