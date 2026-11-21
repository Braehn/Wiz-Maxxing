"""test_own_health.py - the wizard's own health from the game's memory every round, and the potions after a knockout, the
AutoHotkey side read (not run). Standard library only: python -m unittest test_own_health  (from AutoFarmer\\vision)

2026-11-21 08:09-08:23 (UI 0.856, no own plate found by picture): the memory had the wizard's health every round (136, 349,
39, 117 of 3525), but OwnHealthLow - the only reader of it - was only asked with the plate found. So the potion check never
learned the most health, counted 100% and never drank, and the wizard walked from knockout to knockout (5 in 9 minutes).
Pins: OwnHealthLow asked every round from the round's flow, memory first and the plate only when found; the potions' most
noted from every reading as before; EnemyDanger reading it without a plate, EnemyDefend and the heals still needing the plate
(they click it), the party healer not holding an ally's heal for one that can't go; PotionCheck drinking up to 3 in a row
while under the limit (not once you play, a battle starts or the bot is off), taking an unread globe just after a knockout
as 1 (one game window only; a guessed drink books nothing), and that knockout done with once any health is seen."""
import os
import re
import unittest

from test_blades import func, read


class OwnHealth(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.af = read("Autofarmer.ahk")
        cls.es = read("EnemySpells.ahk")
        cls.po = read("Potions.ahk")

    def test_memory_first_plate_when_found(self):
        b = func(self.af, "OwnHealthLow")
        mem = b.index("r := OwnMemHealth()")
        plate = re.search(r'if \(!IsObject\(r\) && player == 1 && playerX != "" && !\(playerX = 0 && playerY = 0\)\)\n\t*r := PlateHealth\(playerX, playerY\)', b)
        self.assertIsNotNone(plate)
        self.assertLess(mem, plate.start())
        self.assertEqual(len(re.findall(r"PlateHealth\(", b)), 1)

    def test_potions_most_as_before(self):
        """every reading notes the most health for the potions, as before (a carry-turn guard was reviewed out 2026-11-21:
        with carrymain Passes the main never reads its own, and its potions would never learn a most at all)"""
        b = func(self.af, "OwnHealthLow")
        self.assertRegex(b, r"\n\tPotionNoteMax\(most\)\n")
        self.assertNotIn("CarryTurn", b)
        self.assertEqual(len(re.findall(r"PotionNoteMax\(", b)), 1)

    def test_party_healer_waits_only_for_a_castable_own_heal(self):
        b = func(read("Party.ahk"), "PartyHealAlly")
        self.assertIn("if (OwnHpRound = roundnumber && OwnHpPct != \"\" && OwnHpPct <= PartyLowPct && V1Ge(OwnHpVotes, 3) && player == 1 && playerX != \"\")\n", b)

    def test_asked_every_round(self):
        """after the round's "player=" line and before BoostSearch - not behind the plate"""
        m = re.search(r'\nDebugLog\("  player=".*?\nif \(OwnHpRound != roundnumber\)\n\tOwnHealthLow\(true\)\n(?:;[^\n]*\n)*BoostSearch\(\)', self.af, re.S)
        self.assertIsNotNone(m)
        self.assertNotIn("player == 1", m.group(0).split("if (OwnHpRound != roundnumber)")[1])

    def test_enemy_danger_without_plate(self):
        """the danger worked out without a plate (not in dual mode: its round number is always blank); defending - a heal or
        Tower Shield clicks your plate - only with it"""
        self.assertIn('if (hitter != 0) && (playerX != "" || (roundnumber != "" && OwnHpRound = roundnumber))\n', self.af)
        self.assertIn('if (EnemyDanger() && !PlayerTookRound && playerX != "" && EnemyDefend())', self.af)
        self.assertNotIn('if (hitter != 0) && (playerX != "")\n', self.af)
        ed = func(self.es, "EnemyDanger")
        line = next(ln for ln in ed.split("\n") if "OwnHpWin = WinExist(\"A\")))" in ln and "OwnHpAt < 20000" in ln)
        self.assertNotIn("playerX", line)

    def test_heals_still_need_the_plate(self):
        """a heal clicks your plate (UseHeal refuses without it): those gates keep player == 1"""
        self.assertEqual(len(re.findall(r"\(player == 1\) && \(\(heal1 == 1\) \|\| \(heal2 == 1\)\) && OwnHealthLow\(\)", self.af)), 2)

    def test_knockout_noted(self):
        b = func(self.es, "BattleDefeated")
        self.assertIn("global PotionKoAt", b)
        # (one game window only - two write the one log: the other's knockout isn't this wizard's)
        self.assertRegex(b, r'if \(!CarryOn && \(!V1IsFunc\("VisionGameClients"\) \|\| VisionGameClients\.Call\(\) <= 1\)\)\n\t\tPotionKoAt := A_TickCount')
        self.assertIn('PotionKoAt := ""', func(self.po, "PotionsBlank"))

    def test_unread_globe_after_knockout(self):
        b = func(self.po, "PotionCheck")
        self.assertIn("PotionNextCheck := A_TickCount + 4000, pcGuess := 0\n", b)
        m = re.search(r'hp := PotionHealth\(\)\n(?:\t*;[^\n]*\n)*\tif \(hp = "" && V1IsNum\(PotionKoAt\) && PotionKoAt > 0 && A_TickCount - PotionKoAt < 60000 && !GameInTray\)\n\t\t\{\n\t\thp := 1, PotionKoAt := 0, pcGuess := 1\n', b)
        self.assertIsNotNone(m, "the knockout's 1 health comes right after the globe's read, before the tray check")
        self.assertIn("global PotionStuckSince, PotionKoAt", b)

    def test_knockout_done_with_once_health_seen(self):
        """any health seen after the knockout (read, or taken as 1) ends it - never guessed from again"""
        b = func(self.po, "PotionCheck")
        self.assertRegex(b, r'if \(hp = "" \|\| GameInTray\)\n\t\treturn\n(?:\t*;[^\n]*\n)*\tPotionKoAt := 0\n\tmost := PotionMost\(\)')

    def test_guessed_drink_books_nothing(self):
        """a drink on the knockout's guess that PotionDrink couldn't confirm (no globe): no rest, no 'none left', no run"""
        b = func(self.po, "PotionCheck")
        m = re.search(r"if \(GameInTray\)\n\t\t\treturn\n(?:\t*;[^\n]*\n)*\t\tif \(pcGuess\)\n\t\t\treturn\n(?:\t*;[^\n]*\n)*\t\tif \(V1IsNum\(PotionDrinkHave\) && PotionDrinkHave >= 1\)", b)
        self.assertIsNotNone(m)
        self.assertLess(b.index("if (pcGuess)"), b.index("PotionNoneAt := A_TickCount\n"))

    def test_drinks_again_under_the_limit(self):
        b = func(self.po, "PotionCheck")
        m = re.search(r"if \(PotionDrink\(hp\)\)\n\t*\{\n\t*PotionNoneAt := 0\n(?:\t*;[^\n]*\n)*\t*Loop 2\n\t*\{\n(.*?)\n\t*\}\n\t*return\n", b, re.S)
        self.assertIsNotNone(m)
        loop = m.group(1)
        self.assertIn("pcHp := PotionHealth()", loop)
        self.assertRegex(loop, r'BattleLogRead\(\)\n\t*if \(pcHp = "" \|\| GameInTray \|\| !BotOn \|\| PlayerActing\(\) \|\| BattleLogInBattle\(\) \|\| 100 \* pcHp / most >= limit\)\n\t*break')
        self.assertRegex(loop, r"if \(!PotionDrink\(pcHp\)\)\n\t*break")

    def test_drink_model(self):
        """PotionCheck's arithmetic with the most known from memory - the case that was a silent 100% before"""
        def check(hp, most, limit=40):
            pct = 100 * hp / most if most else 100
            return bool(most) and pct < limit
        self.assertTrue(check(1, 3525))
        self.assertTrue(check(349, 3525))
        self.assertFalse(check(3000, 3525))
        self.assertFalse(check(1, ""))


if __name__ == "__main__":
    unittest.main()
