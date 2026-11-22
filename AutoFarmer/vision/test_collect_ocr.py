"""test_collect_ocr.py - a collect goal the game shows no way to (no arrow) is taken up though its line OCRs as nothing
like its words: the count's end ("of N)") is enough to show the line is on screen. Standard library only:
python -m unittest test_collect_ocr  (from AutoFarmer\\vision)

2026-11-22 (JSHSRVRWINB, UI 0.856 at 1920x1080): "Collect Pegasus Chow in Pegasus Place (0 of 5)" - the game's memory
had it, but CollectNoPlace also wants the line on screen (a dialogue or window over it isn't the goal), and the game's
outlined quest text read "'Cullet} 'Cil D Of 5)", "'Cil%9 Of 3)" (1x), "'CoJlzcr ill Of 3)" (2x), "COJlzci lill ?hcz (O
of 3)" (3x): no word shared, no count - no collect mode, "NEEDS YOU - No quest arrow" for 3 hours (08:51-11:3x)."""
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


class CountTail(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.w = read("..", "..", "AutoQuester", "Walker.ahk")
        f = func(cls.w, "CollectCountTail")
        rx = re.findall(r'RegExMatch\((?:text|ocr), "i\)(.*?)"\)', f)
        assert len(rx) == 2, rx
        cls.text_rx, cls.ocr_rx = (re.compile(r, re.I) for r in rx)

    def tail(self, text, ocr):
        return bool(self.text_rx.search(text)) and bool(self.ocr_rx.search(ocr))

    def test_real_reads(self):
        goal = "Collect Pegasus Chow in Pegasus Place (0 of 5)"
        for ocr in ("'Cullet} 'Cil�D Of 5)", "'Cil%9 Of 3)", "'CoJlzcr ill Of 3)", "COJlzci lill ?hcz (O of 3)",
                    "COJlzc�r 'jil (r) of 5)", "Collect Pegasus Chow (2 of 15)"):
            self.assertTrue(self.tail(goal, ocr), ocr)

    def test_not_the_line(self):
        goal = "Collect Pegasus Chow in Pegasus Place (0 of 5)"
        for ocr in ("", "Press X to Talk", "LOG OUT YES NO", "Health 2766/3525", "Cil%9", "soft) Gift"):
            self.assertFalse(self.tail(goal, ocr), ocr)
        # (a goal with no count: as before - the words or a collect word have to be read)
        self.assertFalse(self.tail("Use Strange Plant in Pegasus Place", "'Cil%9 Of 3)"))

    def test_wired_in(self):
        cnp = func(self.w, "CollectNoPlace")
        self.assertIn('if (cnpOcr = "" || WalkDialogOpen() || !(CollectGoal(cnpOcr) || WalkLineShares(text, cnpOcr) '
                      '|| CollectCountTail(text, cnpOcr)))\n\t\t\treturn false', cnp)
        self.assertNotIn("\b", self.w)                                 # (no backspace slipped into a regex)
        self.assertNotIn("\r\n", self.w)                               # (Walker.ahk's own LF line ends)

    def test_talk_ends_at_a_no_place_goal(self):
        # (an NPC's dialogue handing out a goal the game shows no way to - no arrow, no place: its id still ends talk
        # mode as a new goal - CollectGoalId has it from the no-place reading - so collect mode can come next)
        step = func(self.w, "WalkStep")
        i = step.index("if (WkArrived = 2)\n")
        talk = step[i:i + 3000]
        self.assertRegex(talk, r"\t\tmemGoal := CollectGoalId\(\)\n\t\tmemSame := \(WkTalkGoal != \"\" && memGoal != \"\"\) "
                               r"\? \(memGoal \"\|\" = WkTalkGoal \"\|\"\) : \"\"\n\t\tif \(memSame != \"\"\)\n\t\t\tWkFar := memSame \? 0 : 2")
        cg = func(self.w, "CollectGoalId")
        self.assertIn('return (WkNavOk && IsObject(WkNavObj)) ? WkNavObj.goalid : (WkNavNoPlace && WkNpGoal != "") ? WkNpGoal : ""', cg)


if __name__ == "__main__":
    unittest.main()
