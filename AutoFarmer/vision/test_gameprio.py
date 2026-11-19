"""test_gameprio.py - "Run Wizard101 at High priority" (Settings: gamehigh), the AutoHotkey side read (not run).
Standard library only: python3 -m unittest test_gameprio  (from AutoFarmer\\vision)

2026-11-18: opening a menu, card or enchant the game hasn't shown for a while freezes it while it builds it (its own log:
"TIMING Event DisplayCharStats took 138 ms" opening the spellbook), and the user found those freezes much shorter with
the game at High priority. Pins: the setting (a check, on by default, after gamefront, in the simple view), the bot
raising each game once from a 5 s timer and from Settings' CfgApply (through V1IsFunc), only ever High or Normal -
never Realtime - and only the right to query/set information on the game's process, DetectHiddenWindows put back, a
priority set by hand afterwards left alone, and the README's paragraph."""
import os
import re
import unittest

from test_tray import AF, ahk_code, body, code_of, read_lines, semicolon_hits


class GamePriority(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.af = code_of(os.path.join(AF, 'Autofarmer.ahk'))
        cls.cfg_lines = read_lines(os.path.join(AF, 'Settings.ahk'))
        cls.cfg = '\n'.join(ahk_code(cls.cfg_lines))

    def fn(self, code, name):
        b = body(code, name)
        self.assertIsNotNone(b, name + ' not found')
        return b

    def test_setting(self):
        """a check, on by default, right after gamefront, in the simple view; no ' ;' in its strings"""
        found = [ln for ln in self.cfg.split('\n') if 'key: "gamehigh"' in ln]
        self.assertEqual(len(found), 1)
        self.assertRegex(found[0], r'\bkind: "check"')
        self.assertRegex(found[0], r'\bdef: 1\b')
        keys = re.findall(r'list\.Push\(V1Obj\(\{key: "([^"]+)"', self.cfg)
        self.assertEqual(keys[keys.index('gamefront') + 1], 'gamehigh')
        mine, follow = [], False
        for ln in self.cfg_lines:
            if 'key: "gamehigh"' in ln:
                mine.append(ln)
                follow = True
            elif follow and ln.lstrip().startswith(','):
                mine.append(ln)
            else:
                follow = False
        self.assertEqual(len(mine), 2, mine)
        self.assertEqual(semicolon_hits(mine), [])
        self.assertIn('"gamehigh"', self.fn(self.cfg, 'CfgSimpleKeys'))

    def test_reader(self):
        """on unless it's 0 - an unreadable Stats counts as on"""
        b = self.fn(self.af, 'GameHighOn')
        self.assertIn('Stats["gamehigh"] = 0) ? 0 : 1', b)
        self.assertRegex(b, r'catch\s*return 1')

    def test_tick_wiring(self):
        """once at the start and every 5 s; from CfgApply after the write, through V1IsFunc, before the menu bar's ticks"""
        self.assertRegex(self.af, r'(?m)^GamePriorityTick\(\)\s*\nSetTimer\(GamePriorityTick,5000\)')
        ap = self.fn(self.cfg, 'CfgApply')
        m = re.search(r'if \(V1IsFunc\("GamePriorityTick"\)\)\s*GamePriorityTick\.Call\(\)', ap)
        self.assertIsNotNone(m)
        self.assertGreater(m.start(), ap.index('if (!CfgWrite('))
        self.assertLess(m.start(), ap.index('DashMenuTicks.Call()'))
        self.assertNotRegex(ap, r'(?<![\w.])GamePriorityTick\(')

    def test_only_high_or_normal(self):
        """the bot sets no other priority anywhere - never Realtime - and the game's process is opened only to read its
        priority class (PROCESS_QUERY_LIMITED_INFORMATION)"""
        code = []
        for name in sorted(os.listdir(AF)):
            if name.lower().endswith('.ahk'):
                code.append(code_of(os.path.join(AF, name)))
        code = '\n'.join(code)
        levels = re.findall(r'(?<![\w.])ProcessSetPriority\(\s*"([^"]*)"', code)
        self.assertEqual(sorted(set(levels)), ['High', 'Normal'])
        self.assertEqual(len(re.findall(r'(?<![\w.])ProcessSetPriority\(', code)), len(levels))
        self.assertNotRegex(code, r'(?i)"(realtime|r)"\s*,\s*\w*pid')
        of = self.fn(self.af, 'GamePriorityOf')
        self.assertIn('DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")', of)
        self.assertIn('DllCall("CloseHandle", "Ptr", gpoH)', of)

    def test_tick(self):
        """each game raised once and checked (0x80); a failure said once; off: only the ones it raised that are still
        at High go back to Normal; games gone forgotten; DetectHiddenWindows put back in a finally"""
        t = self.fn(self.af, 'GamePriorityTick')
        self.assertRegex(t, r'static raised := Map\(\), failed := Map\(\)')
        self.assertIn('gpDhw := A_DetectHiddenWindows', t)
        self.assertRegex(t, r'finally\s*DetectHiddenWindows\(gpDhw\)')
        self.assertIn('WinGetList("ahk_exe " GameExe)', t)
        self.assertIn('ProcessExist(GameExe)', t)
        self.assertIn('if (gpOn && !raised.Has(gpPid) && !failed.Has(gpPid))', t)
        self.assertRegex(t, r'ProcessSetPriority\("High", gpPid\)\s*if \(GamePriorityOf\(gpPid\) = 0x80\)')
        self.assertRegex(t, r'else if \(!gpOn && raised\.Has\(gpPid\)\)\s*\{\s*raised\.Delete\(gpPid\)')
        self.assertRegex(t, r'if \(GamePriorityOf\(gpPid\) = 0x80\)\s*\{\s*try\s*ProcessSetPriority\("Normal", gpPid\)')
        self.assertRegex(t, r'for each, gpMap in \[raised, failed\]')

    def test_readme(self):
        with open(os.path.join(AF, 'README.txt'), encoding='utf-8-sig') as f:
            readme = f.read()
        self.assertIn('Run Wizard101 at High priority (gamehigh:1', readme)
        self.assertIn("it's never Realtime", readme)
        # (raised / failed are this run's: a restart raises a game you lowered by hand again - both texts say so)
        self.assertIn('a restart of the bot sets it to High\nagain', readme)
        self.assertIn('a restart of the bot sets it to High again', self.cfg)


if __name__ == '__main__':
    unittest.main()
