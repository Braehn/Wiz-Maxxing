"""test_dglint.py - the dungeon run linter (vision\\dglint.py: a run file read as Dungeons.ahk's DgLoad reads it, the new
optional lines, and what the replay would trip on) on made-up run files - no game:  python3 -m unittest test_dglint
(from AutoFarmer\\vision)"""
import io
import os
import shutil
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import dglint as D  # noqa: E402

GOOD = """; Wiz-Maxxing dungeon run, recorded 20261030. One step a line: kind|zone|x|y|z
; walk: walk to this spot; x: press X here
name|Waterworks
deck|large
walk|Celestia/CL_Hub|100|100|0
walk|Celestia/CL_Hub|300|100|0
x|Celestia/CL_Hub|320|110|0
walk|Celestia/CL_Waterworks|0|0|0
fight|Celestia/CL_Waterworks|50|0|0
walk|Celestia/CL_Waterworks|900|0|0
walk|Celestia/CL_Hub|310|100|0
walk|Celestia/CL_Hub|120|100|0
"""


def kinds(issues):
    return [(lvl, step) for lvl, step, _t in issues]


class Parse(unittest.TestCase):
    def test_as_dgload(self):
        r = D.parse_run(GOOD + "Walk|Celestia/CL_Hub|1|2|3\nwalk|Z|||\nwalk|Z|1|2\nNAME|Renamed\nslots|hat, Robe,boots\n"
                        "stopafter|12\nnext|Darkmoor\nuntilgear|1\nboss|Kraken|large\nboss|Squid\ndeck|la$rge!\n",
                        "file.txt")
        self.assertEqual(r["name"], "Renamed")                 # (name| isn't case-sensitive; the last one wins)
        self.assertEqual(r["deck"], "large")                   # (DgLoad's [^\w-] taken out)
        self.assertEqual(len(r["steps"]), 8)                   # ("Walk" isn't a step; a blank or short one neither)
        self.assertEqual([n for n, _t in r["skipped"]], [13, 14, 15])          # (GOOD's 12 lines, then these)
        self.assertEqual(r["slots"], ["hat", "robe", "shoes"])
        self.assertEqual((r["stopafter"], r["next"], r["untilgear"]), (12, "Darkmoor", 1))
        self.assertEqual(r["bosses"], [("Kraken", "large"), ("Squid", "")])
        self.assertEqual(r["steps"][2], {"kind": "x", "zone": "Celestia/CL_Hub", "x": 320.0, "y": 110.0, "z": 0.0,
                                         "line": 7})
        self.assertEqual(D.parse_run("walk|A|1|2|3\n", "C:/x/My Run.txt")["name"], "My Run")
        self.assertIsNone(D._num("1e"))
        self.assertEqual(D._num(" 0x1F "), 31)

    def test_stats(self):
        s = D.stats(D.parse_run(GOOD))
        self.assertEqual((s["steps"], s["zones"], s["x"], s["fights"], s["start"], s["end"]),
                         (8, 2, 1, 1, "Celestia/CL_Hub", "Celestia/CL_Hub"))
        self.assertAlmostEqual(s["away"], 20.0)


class Lint(unittest.TestCase):
    def test_good_run(self):
        self.assertEqual(D.lint(D.parse_run(GOOD), runs={"Waterworks"}, decks={"large"}), [])

    def test_errors(self):
        r = D.parse_run("walk|A|1|2|3\n")
        self.assertEqual(kinds(D.lint(r)), [("error", 0)])
        # (fix2: a step with a coordinate that isn't a number is left out, as DgLoad leaves it out - not numbered among
        # the steps walked: one step left, and that line said - it gave [("error", 2)])
        r = D.parse_run("walk|A|1|2|3\nwalk|A|x|2|3\n")
        self.assertEqual(len(r["steps"]), 1)
        iss = D.lint(r)
        self.assertEqual(kinds(iss), [("error", 0), ("error", 0)])
        self.assertIn("line 2: a coordinate isn't a number (walk step in A) - Dungeons.ahk leaves the step out", iss[1][2])
        r = D.parse_run("walk|A|1|2|3\nwalk|A|x|2|3\nwalk|A|5|2|3\n")
        self.assertEqual([s["line"] for s in r["steps"]], [1, 3])
        self.assertEqual(kinds(D.lint(r)), [("error", 0)])

    def test_end_elsewhere_and_far(self):
        r = D.parse_run("walk|A|0|0|0\nx|A|10|0|0\nwalk|B|0|0|0\n")
        self.assertEqual(kinds(D.lint(r)), [("warn", 3)])
        r = D.parse_run("walk|A|0|0|0\nwalk|A|150|0|0\nwalk|A|300|0|0\nwalk|A|450|0|0\nwalk|A|600|0|0\n")
        iss = D.lint(r)
        self.assertEqual(kinds(iss), [("warn", 5)])
        self.assertIn("600 away", iss[0][2])

    def test_zone_change_after_fight_and_jump(self):
        r = D.parse_run("walk|A|0|0|0\nfight|A|0|0|0\nwalk|B|0|0|0\nwalk|B|5000|0|0\nx|B|5000|0|0\nwalk|A|0|0|0\n")
        iss = D.lint(r)
        self.assertEqual(kinds(iss), [("warn", 2), ("warn", 4)])
        self.assertIn("after a battle step", iss[0][2])
        self.assertIn("5000 from the step before", iss[1][2])

    def test_walk_after_x_drift(self):
        # (a sigil's X, the wizard drifted 40 before the loading screen: the recorder's doorway step after it)
        r = D.parse_run("walk|A|0|0|0\nx|A|100|0|0\nwalk|A|140|0|0\nwalk|D|0|0|0\nx|D|10|0|0\nwalk|A|5|0|0\n")
        iss = D.lint(r)
        self.assertEqual(kinds(iss), [("warn", 3)])
        self.assertIn("drifted at a sigil", iss[0][2])
        # (walked on 300 after an X to talk, then a doorway: not a drift)
        r = D.parse_run("walk|A|0|0|0\nx|A|100|0|0\nwalk|A|400|0|0\nwalk|D|0|0|0\nx|D|10|0|0\nwalk|A|5|0|0\n")
        self.assertEqual(D.lint(r), [])

    def test_gear_lines_checked(self):
        r = D.parse_run(GOOD + "slots|cape,gloves\nstopafter|lots\nnext|Nowhere\nboss|Kraken|nodeck\nboss|Squid\n"
                        "deck|gone\n")
        iss = D.lint(r, runs={"Waterworks", "Darkmoor"}, decks={"large"})
        texts = " / ".join(t for _l, _s, t in iss)
        for want in ("none of them is a slot", "isn't a number of runs", "next|Nowhere", "boss|Kraken|nodeck",
                     "boss|Squid - no deck id", "deck|gone"):
            self.assertIn(want, texts)
        # (until its gear is swapped with no slots: the catalogue's said, else only the dry runs)
        import gearrank as G
        cat = G.catalogue("Waterworks|Celestia||hat,robe|||\n")
        r = D.parse_run(GOOD + "untilgear|1\n")
        self.assertIn("the catalogue's Waterworks ones go (hat, robe)", D.lint(r, cat=cat)[0][2])
        r["name"] = "Somewhere Else"
        self.assertIn("only the dry runs", D.lint(r, cat=cat)[0][2])

    def test_lines(self):
        r = D.parse_run(GOOD + "slots|hat\nboss|Kraken|large\n")
        lines = D.lint_lines(r, D.lint(r), "x.txt")
        self.assertEqual(lines[0], "run|Waterworks|8|2|1|1|Celestia/CL_Hub|Celestia/CL_Hub|20|x.txt")
        self.assertEqual(lines[1], "gear|hat|||0|Kraken~large")
        self.assertEqual(lines[-1], "ok|0|0")


class ZoneChoice(unittest.TestCase):
    """Dungeons.ahk DungeonStep's choice when the wizard turns up in another zone (dglint.zone_choice - the same rule)"""
    # A (outside) -> X at the sigil -> B (the entrance) -> C (the boss) -> B -> A: the recorder's "walk back out to where
    # you started" - A and B come again on the way back
    RUN = D.parse_run("walk|A|0|0|0\nx|A|100|0|0\n"                          # 1-2   A, the sigil's X
                      "walk|B|0|0|0\nwalk|B|500|0|0\n"                        # 3-4   B, its doorway into C
                      "walk|C|0|0|0\nfight|C|800|0|0\nwalk|C|0|50|0\n"        # 5-7   C: the boss, back to the door
                      "walk|B|500|0|0\nwalk|B|0|0|0\n"                        # 8-9   B again
                      "walk|A|90|0|0\nwalk|A|10|0|0\n")["steps"]             # 10-11 A again, back at the start

    def test_defeat_at_the_boss(self):
        # (defeated at C's boss - step 6 walked to: respawned in B, or outside in A - on from that zone's FIRST visit, never
        # its later step on the way back, which would walk out and count a run whose boss wasn't beaten)
        self.assertEqual(D.zone_choice(self.RUN, 6, "B", (20, 0)), ("resume", 3))
        self.assertEqual(D.zone_choice(self.RUN, 6, "B", (480, 0)), ("resume", 4))
        self.assertEqual(D.zone_choice(self.RUN, 6, "A", (5, 0)), ("resume", 1))           # (the start, within 300)
        self.assertEqual(D.zone_choice(self.RUN, 6, "A", (900, 900)), ("resume", 2))
        # (a fourth time this run: stopped)
        self.assertEqual(D.zone_choice(self.RUN, 6, "B", (20, 0), resumes=3), ("stop", 3))

    def test_ahead_and_nowhere(self):
        # (a load from A that lands in C - a zone the run hasn't been in yet: on from its first step)
        self.assertEqual(D.zone_choice(self.RUN, 3, "C", (0, 0), from_zone="A"), ("ahead", 5))
        # (a zone ahead that is the one a load was waited for out of: not "ahead" - DgZoneAhead's guard)
        self.assertEqual(D.zone_choice([{"zone": "A", "x": 0, "y": 0}, {"zone": "B", "x": 0, "y": 0},
                                        {"zone": "C", "x": 0, "y": 0}], 2, "C", (0, 0), from_zone="C"), ("stop", 0))
        # (a zone the run doesn't go: stopped)
        self.assertEqual(D.zone_choice(self.RUN, 6, "Z", (0, 0)), ("stop", 0))
        # (on the way back, in C again after B's later steps began: C's first visit is earlier - resumed there)
        self.assertEqual(D.zone_choice(self.RUN, 9, "C", (0, 40)), ("resume", 7))

    def test_nearest_first_visit(self):
        self.assertEqual(D.nearest_first_visit(self.RUN, "B", (0, 0)), 3)         # (the first B block only: 3-4)
        self.assertEqual(D.nearest_first_visit(self.RUN, "A", (400, 0)), 2)
        self.assertEqual(D.nearest_first_visit(self.RUN, "Q", (0, 0)), 0)


class CommandLine(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="dglint_")
        os.makedirs(os.path.join(self.dir, "dungeons"))
        os.makedirs(os.path.join(self.dir, "decks"))
        with open(os.path.join(self.dir, "dungeons", "Waterworks.txt"), "w", newline="\r\n") as f:
            f.write(GOOD)
        with open(os.path.join(self.dir, "dungeons", "Broken.txt"), "wb") as f:
            f.write("name|Br\xf6ken\r\nwalk|A|1|2|3\r\n".encode("latin-1"))         # (the ANSI code page, as FileAppend wrote)
        with open(os.path.join(self.dir, "decks", "large.txt"), "w") as f:
            f.write("name|Large deck\n")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_folder(self):
        out = io.StringIO()
        with redirect_stdout(out):
            code = D._main([os.path.join(self.dir, "dungeons"), "--decks", os.path.join(self.dir, "decks"),
                            "--known", os.path.join(self.dir, "none.txt"), "--out", os.path.join(self.dir, "lint.txt")])
        text = out.getvalue()
        self.assertEqual(code, 1)                                    # (Broken has one step: an error)
        self.assertIn("run|Br\xf6ken|1|", text)
        self.assertIn("run|Waterworks|8|2|1|1|", text)
        self.assertIn("ok|0|0", text)
        with open(os.path.join(self.dir, "lint.txt"), encoding="utf-8") as f:
            self.assertIn("error|0|1 step(s)", f.read())

    def test_empty(self):
        out = io.StringIO()
        empty = os.path.join(self.dir, "empty")
        os.makedirs(empty)
        with redirect_stdout(out):
            self.assertEqual(D._main([empty, "--decks", empty]), 0)
        self.assertIn("none|no run files", out.getvalue())


if __name__ == "__main__":
    unittest.main()
