"""v1.14.1 - Terri on PC_B, 2026-11-15, didn't blade herself against a boss: card logic 3 counted only an Alt+1 pick as a
boss battle (Tempest first every round), blade clicks that cast nothing were counted as cast (both casts gone - no blade
again that battle), and with no name learned her plate was the name pictures' first - the friend's. The scripts' text
checked: each fix where it must be"""
import os
import re
import sys
import unittest

if os.path.dirname(os.path.abspath(__file__)) not in sys.path:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from test_tray import ahk_code  # noqa: E402  (AutoHotkey lines without their comments)

AF = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def code(src):
    """src's AutoHotkey code (test_tray's ahk_code): comment lines and /* */ blocks gone, each line cut at its ' ;' - a
    pinned line commented out is gone, not still there for assertIn and index (fix2, x-tests-2)"""
    return "".join(ln.rstrip() + "\n" for ln in ahk_code(src.split("\n")) if ln.strip())


def read(name):
    """the AutoHotkey file's code (code: its comments gone)"""
    with open(os.path.join(AF, name), encoding="utf-8-sig") as f:
        return code(f.read().replace("\r\n", "\n"))


def func(src, name):
    m = re.search(r"^" + name + r"\(.*?\n\t\}\n", src, re.M | re.S)
    assert m, name + " not found"
    return m.group(0)


class Blades(unittest.TestCase):
    def test_blade_counted_only_once_it_went_out(self):
        body = func(read("Autofarmer.ahk"), "UseBlade")
        checks = [m.start() for m in re.finditer(r"if \(!BladeWentOut\(title\)\)\n\t*return false", body)]
        counts = [m.start() for m in re.finditer(r"\n\t*boosts\+\+", body)]
        self.assertEqual(len(checks), 2, "both casting paths check the cast went out")
        self.assertEqual(len(counts), 2)
        for c, n in zip(checks, counts):
            self.assertLess(c, n, "checked before anything is counted")
        self.assertIn("CastWentOut()", func(read("Autofarmer.ahk"), "BladeWentOut"))

    def test_card_logic_3_boss_from_memory(self):
        st = read("Settings.ahk")
        self.assertIn("!CardBossBattle()", func(st, "CardHitFirst"))
        boss = func(st, "CardBossBattle")
        for want in ("BossChoosen = 1", "RoundMemBoss = 1", 'DeckFoe.kind = "boss"'):
            self.assertIn(want, boss)
        rbm = func(read("Autofarmer.ahk"), "RoundBattleMem")
        self.assertRegex(rbm, r"RoundMemBoss := 0")
        self.assertRegex(rbm, r'rbmF\.boss = 1 \|\| rbmF\.title = "Boss"')

    def test_own_plate_in_a_team_battle(self):
        es = read("EnemySpells.ahk")
        self.assertIn("OwnMemName()", func(es, "OwnName"))
        self.assertIn("RoundMemName", func(es, "OwnMemName"))
        af = read("Autofarmer.ahk")
        by_mem = af.index('else if (rbmX != "" && BattleTeam() >= 2)')
        self.assertLess(af.index("if (PlayerPlateByName(&pbnX, &pbnY))"), by_mem)
        self.assertLess(by_mem, af.index('PicOpt("resources\\player.png"))', by_mem), "before the name pictures")


if __name__ == "__main__":
    unittest.main()
