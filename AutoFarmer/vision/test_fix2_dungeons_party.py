"""test_fix2_dungeons_party.py - the 2026-11-27 review's fixes in Dungeons.ahk, Party.ahk and Carry.ahk, static checks on
the scripts (no AutoHotkey):  python -m unittest test_fix2_dungeons_party      (from AutoFarmer\\vision)

- a follower's ride X only at a prompt whose own lines name a ride (not the quest's goal line under it), never a vendor's or
  one with Crowns (gap4-5); a follower Spaces through a dialogue (party-dungeons-2)
- Alt+M's main: every other client open while it lives is an other one (party-dungeons-3); carry mode brings a game window
  up only while you're away and a game window is the one in front (party-dungeons-4)
- a recording never deletes a run of the same name unasked (x-persistence-5); a run's X step reads the prompt first
  (gap4-6); a step with a coordinate that isn't a number is left out (party-dungeons-9); a battle-cut load try isn't
  counted (party-dungeons-7); DgSetLine writes nothing when it couldn't read the file (party-dungeons-5)"""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AF = os.path.dirname(HERE)


def read(name):
    with open(os.path.join(AF, name), encoding='utf-8-sig') as f:
        return f.read().replace('\r\n', '\n')


def func(text, name):
    m = re.search(r'^' + name + r'\([^\n]*\)\n\t\{\n(.*?)\n\t\}\n', text, re.S | re.M)
    if not m:
        raise AssertionError(name + ' not found')
    return m.group(1)


def ride_prompt(text, verb, wiz):
    """Party.ahk PartyRidePrompt, line for line (PartyKey: the letters in capitals)"""
    key = lambda s: re.sub(r'[^A-Z]', '', s.upper())
    if re.match(r'(?i)(talk|speak|chat|shop|trade|buy|sell|browse|craft|learn|train)', verb):
        return False
    own = [line for line in text.replace('\r', '').split('\n')
           if re.search(r'(?i)\bpress\b|\bclick\b', line) or re.match(r"^\s*[A-Z][A-Z'.\- ]{3,}\s*$", line)]
    if any(re.search(r'(?i)teleport', line) for line in own):
        return False
    if re.match(r'(?i)(ride|mount|board|join|hop)', verb):
        return True
    k = key(wiz)
    for line in own:
        if re.search(r'(?i)\b(mount|ride|riding|passenger)\b', line):
            return True
        if len(k) >= 4 and k in key(line):
            return True
    return False


class RidePrompt(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p = read('Party.ahk')
        cls.c = read('Carry.ahk')

    def test_source_is_the_mirror(self):
        f = func(self.p, 'PartyRidePrompt')
        self.assertIn('if (RegExMatch(verb, "i)^(talk|speak|chat|shop|trade|buy|sell|browse|craft|learn|train)"))\n\t\treturn false', f)
        self.assertIn('Loop Parse, text, "`n", "`r"', f)
        self.assertIn('if (RegExMatch(A_LoopField, "i)\\bpress\\b|\\bclick\\b") || '
                      'RegExMatch(A_LoopField, "^\\s*[A-Z][A-Z\'.\\- ]{3,}\\s*$"))\n\t\t\tprOwn.Push(A_LoopField)', f)
        self.assertIn('for i, prL in prOwn\n\t\tif (RegExMatch(prL, "i)teleport"))\n\t\t\treturn false', f)
        self.assertIn('if (RegExMatch(prL, "i)\\b(mount|ride|riding|passenger)\\b"))', f)
        self.assertLess(f.index('i)teleport'), f.index('i)^(ride|mount'))
        # (the whole text's match is gone - teleport's too, review 2: a goal line's Teleporter refused the ride)
        self.assertNotIn('RegExMatch(text, "i)teleport")', f)
        self.assertNotIn('RegExMatch(text, "i)\\b(mount', f)
        self.assertNotIn('PartyKey(text)', f)

    def test_cases(self):
        goal = 'Talk to Zeus in Mount Olympus'
        self.assertFalse(ride_prompt('ZEUS\nPress X to Talk\n' + goal, 'Talk', 'Bob Stormblade'))
        self.assertFalse(ride_prompt('ARMOR VENDOR\nPress X to Shop\n' + goal, 'Shop', ''))
        self.assertFalse(ride_prompt('SOME THING\nPress X to Collect\n' + goal, 'Collect', ''))
        self.assertTrue(ride_prompt('Press X to Ride\n' + goal, 'Ride', ''))
        self.assertTrue(ride_prompt("BOB'S MOUNT\nPress X to Interact\n" + goal, 'Interact', ''))
        self.assertTrue(ride_prompt('BOB STORMBLADE\nPress X to Interact', 'Interact', 'Bob Stormblade'))
        self.assertFalse(ride_prompt('Press X to Interact\nDefeat Bob Stormblade in Mount Olympus', 'Interact', 'Bob Stormblade'))
        self.assertFalse(ride_prompt('Press X to Ride\nTELEPORTER', 'Ride', ''))
        self.assertFalse(ride_prompt('Press X to Teleport', 'Teleport', ''))
        # (a goal line's teleporter isn't the prompt's)
        self.assertTrue(ride_prompt('Press X to Ride\nUse the Teleporter in Mount Olympus', 'Ride', ''))
        self.assertTrue(ride_prompt("BOB'S MOUNT\nPress X to Interact\nTeleport to Zeus", 'Interact', ''))

    def test_crowns_never(self):
        rc = func(self.p, 'PartyRideCheck')
        self.assertIn('if (PartyRidePrompt(WkPromptText, WkPromptVerb, L.wiz) && !WalkPromptCrowns())', rc)
        bo = func(self.c, 'CarryBattleOver')
        self.assertIn('if (PartyRidePrompt(WkPromptText, WkPromptVerb, "") && !WalkPromptCrowns())', bo)


class FollowerDialogue(unittest.TestCase):
    def test_dialogs_in_the_hidden_book_branch(self):
        f = func(read('Party.ahk'), 'PartyFollowStep')
        m = re.search(r'if \(!Walking \|\| !GameActive\(\) \|\| inbattle = 1 \|\| !BotNoBattle\(\)\)\n\t\t\{\n(.*?)\n\t\treturn\n', f, re.S)
        self.assertIsNotNone(m)
        self.assertRegex(m.group(1), r'if \(Walking && GameActive\(\) && inbattle != 1\)\n\t\t\tDgDialogs\(\)')
        # (stuck with the book still up: a dialogue first, not a stuck try)
        self.assertRegex(f, r'if \(A_TickCount - PartyStillAt > 3000\)\n\t\t\t\{\n(?:\t*;[^\n]*\n)*\t\t\tif \(DgDialogs\(\)\)\n'
                            r'\t\t\t\t\{\n\t\t\t\tPartyStillAt := 0\n\t\t\t\treturn')
        self.assertIn('global WkFrontLook, PartyNear, PartyTries, PartyStillAt,', f)


class MainAndCarry(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = read('Carry.ahk')

    def test_others_kept_up_while_main_lives(self):
        f = func(self.c, 'MainTick')
        alive = f[f.index('if (CarryWinOf(MainPid))'):f.index('for i, w in CarryGameWins()\n\t\tif (w.pid != MainPid && !MainOthers.Has(w.pid))')]
        self.assertIn('for i, w in CarryGameWins()\n\t\t\tif (w.pid && w.pid != MainPid)\n\t\t\t\tMainOthers[w.pid] := 1', alive)
        self.assertIn('return\n', alive)
        self.assertIn('if (GameInTray && GameTrayPid = MainPid && ProcessExist(MainPid))\n\t\treturn', f)
        self.assertIn('global GameInTray, GameTrayPid', f)

    def test_front_only_when_may(self):
        may = func(self.c, 'CarryMayFront')
        self.assertIn('if (PlayerActing())\n\t\treturn false', may)
        self.assertIn('WinActive("ahk_id " CarryMainHwnd)', may)
        self.assertIn('WinActive("ahk_id " CarryHwnd)', may)
        self.assertIn('CarryFront(which, why, quiet := false, swap := true, bring := true)', self.c)
        self.assertIn('if (bring && !WinActive("ahk_id " cfH))', func(self.c, 'CarryFront'))
        nr = func(self.c, 'CarryNoRound')
        self.assertIn('CarryFront(0, "no round up on the carry\'s window for 6 s", false, true, CarryMayFront())', nr)
        bo = func(self.c, 'CarryBattleOver')
        self.assertIn('if (!StatOr("partyride", 1) || !cboMay)\n\t\treturn', bo)
        self.assertEqual(bo.count('CarryFront(0, "back to the main", false, false, CarryMayFront())'), 2)
        self.assertNotIn('CarryFront(0, "back to the main", false, false)', bo)
        re_ = func(self.c, 'CarryRoundEnd')
        self.assertEqual(re_.count(', CarryMayFront())'), 2)
        # (every CarryFront that isn't a key you pressed or a start - CarryStart / CarryRestore / MainSet - asks first; the
        # mount prompt's comes after cboMay's return)
        self.assertLess(bo.index('if (!StatOr("partyride", 1) || !cboMay)'), bo.index('its mount\'s prompt"'))
        for line in self.c.split('\n'):
            if 'CarryFront(' in line and not line.lstrip().startswith(';') and 'CarryFront(which' not in line:
                if any(w in line for w in ('"carry mode on', '"the main picked"', 'its mount\'s prompt"', 'CarryFront(CarryTurn,')):
                    continue
                self.assertTrue('CarryMayFront()' in line or 'cboMay' in line, line)

    def test_held_back_window_brought_later(self):
        # (a switch held back while you act is done once you've stopped at a game window - not dropped: reviews 1.1 / 2.1)
        self.assertIn('global CarrySaidPrompts, CarryRounds, CarryMainRounds, CarryFrontLate', self.c)
        self.assertIn('CarryFrontLate := 0', func(self.c, 'CarryBlank'))
        cf = func(self.c, 'CarryFront')
        self.assertIn('global CarryTurn, CarryTurnAt, CarryPin, CarryFrontLate', cf)
        self.assertIn('CarryFrontLate := !bring && !cfOk', cf)
        tk = func(self.c, 'CarryTick')
        self.assertRegex(tk, r'if \(CarryFrontLate && CarryMayFront\(\)\)\n\t\tCarryFront\(CarryTurn, "[^"\n]+", false, false\)')
        self.assertLess(tk.index('if (!CarryOn)'), tk.index('CarryFrontLate'))
        off = func(self.c, 'CarryOff')
        self.assertIn('CarryFrontLate', off.split('\n')[0])
        self.assertIn('CarryTurn := 0, CarryFrontLate := 0', off)


class Dungeons(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.d = read('Dungeons.ahk')

    def test_lf_kept(self):
        with open(os.path.join(AF, 'Dungeons.ahk'), 'rb') as f:
            self.assertNotIn(b'\r\n', f.read())
        with open(os.path.join(AF, 'Carry.ahk'), 'rb') as f:
            self.assertNotIn(b'\r\n', f.read())
        with open(os.path.join(AF, 'Party.ahk'), 'rb') as f:
            b = f.read()
        self.assertEqual(b.count(b'\r\n'), b.count(b'\n'))

    def test_record_asks_before_replacing(self):
        f = func(self.d, 'DgRecordStop')
        self.assertNotIn('V1Do(FileDelete, file)\n', f)
        self.assertIn('drsOld := DgFindRun(name)', f)
        self.assertIn('262435)', f)                                        # (Yes / No / Cancel, No the default)
        self.assertIn('V1Do(FileRecycle, drsF)', f)
        self.assertLess(f.index('drsOld := DgFindRun(name)'), f.index('V1Do(FileAppend, text, file ".tmp")'))
        self.assertIn('V1Do(FileMove, file ".tmp", file, 1)', f)
        self.assertEqual(262144 + 256 + 32 + 3, 262435)

    def test_x_step_reads_the_prompt(self):
        f = func(self.d, 'DgArrive')
        i_prompt, i_x = f.index('daKind := InteractPrompt()'), f.index('PressKey("x")')
        self.assertLess(i_prompt, i_x)
        # (Crowns in any text read - one of no kind InteractPrompt knows too)
        self.assertIn('daCrown := WkPromptText != "" && WalkPromptCrowns()', f)
        self.assertNotIn('daKind != "" && WalkPromptCrowns()', f)
        self.assertIn('if (daCrown || daShop)', f)
        # (not with the dialogue still up - as the walker's)
        self.assertIn('if (!daCrown && !daShop && !WalkDialogOpen())\n\t\t\tWalkCloseAfterX()', f)
        self.assertIn('global WkPreXText', f)

    def test_bad_coordinate_left_out(self):
        f = func(self.d, 'DgLoad')
        self.assertIn('if (V1IsNum(dlX) && V1IsNum(dlY) && V1IsNum(dlZ))\n\t\t\t\tsteps.Push(', f)
        self.assertIn('static dlSaid := Map()', f)

    def test_battle_cut_try_not_counted(self):
        f = func(self.d, 'DungeonStep')
        self.assertIn('dlCut := battles != r.loadBattles\n\t\t\tif (!dlCut)\n\t\t\t\tr.loadTries += 1', f)
        self.assertEqual(f.count('r.loadTries += 1'), 1)

    def test_setline_checks_the_read(self):
        f = func(self.d, 'DgSetLine')
        rd = f.index('text := V1FileRead(file)')
        chk = f.index('if (ErrorLevel || !RegExMatch(text, "(^|\\n)\\s*(walk|x|fight)\\|"))')
        self.assertLess(rd, chk)
        self.assertLess(chk, f.index('V1Try(FileOpen, file ".tmp", "w", "CP0")'))
        # (the AHK pattern: a step line found in a file of either line ending, none in one with no step)
        pat = r'(^|\n)\s*(walk|x|fight)\|'
        self.assertTrue(re.search(pat, '; c\r\nname|a\r\nwalk|Z|1|2|3\r\n'))
        self.assertTrue(re.search(pat, 'x|Z|1|2|3\n'))
        self.assertFalse(re.search(pat, '; x: press X here\r\nname|a\r\ndeck|7\r\n'))


if __name__ == '__main__':
    unittest.main()
