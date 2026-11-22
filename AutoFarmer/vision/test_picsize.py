"""test_picsize.py - the pictures after the game's window changed size, the AutoHotkey side read (not run).
Standard library only: python3 -m unittest test_picsize  (from AutoFarmer\\vision)

2026-11-20 20:51: the bot started beside a full-screen Wizard101 - minimized whenever another window takes the focus -
whose minimized window read 160x28 at -32000,-32000: it chose its pictures for a 160x28 window (the main set, UI 1) and,
the game back at 1920x1080 (UI 0.856, whose made spellbook is too see-through to pick a set by), never switched out of a
battle. Pins: UpdateGameRect keeps the last size for a minimized window (IsIconic), and the main loop's PicSizeKept -
a size the window was played at before (generated\\scales.txt), nothing on screen telling the size since: that size's set,
as at the start; the start's own size left to the start, and a set seen or measured at the new size kept."""
import os
import re
import unittest

from test_tray import AF, body, code_of


class PicSize(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.af = code_of(os.path.join(AF, 'Autofarmer.ahk'))
        cls.ps = code_of(os.path.join(AF, 'PicScale.ahk'))
        cls.gr = code_of(os.path.join(AF, '..', 'GameRect.ahk'))

    def fn(self, code, name):
        b = body(code, name)
        self.assertIsNotNone(b, name + ' not found')
        return b

    def test_minimized_kept(self):
        """a minimized game window: nothing measured (its client area isn't 0 x 0 with a title bar) - nor one with no
        client area (GameClientRect false: w or h 0)"""
        u = self.fn(self.af, 'UpdateGameRect')
        m = re.search(r'if \(DllCall\("IsIconic", "Ptr", hwnd\) \|\| !GameClientRect\(hwnd, &x, &y, &w, &h\)\)\s*\{\s*return\s*\}', u)
        self.assertIsNotNone(m)
        self.assertLess(m.start(), u.index('GameLeft := x'))
        self.assertNotIn('GetClientRect', u)
        g = self.fn(self.gr, 'GameClientRect')
        self.assertRegex(g, r'if \(w <= 0 \|\| h <= 0\)\s*return false')

    def test_full_screen_bigger_than_its_screen(self):
        """2026-11-21: a full-screen Wizard101 1920x1200 on a 1920x1080 screen (the remote desktop's size changed after
        it started) draws for 1920x1080 - only the part on its screen is the game's; a window with a title bar (windowed)
        or one not at its screen's top left measured whole, as before"""
        g = self.fn(self.gr, 'GameClientRect')
        cap = g.index('if ((DllCall("GetWindowLong", "Ptr", hwnd, "Int", -16, "Int") & 0xC00000) = 0xC00000)\n\t\treturn true')
        mon = g.index('DllCall("MonitorFromWindow", "Ptr", hwnd, "UInt", 2, "Ptr")')
        self.assertLess(cap, mon)
        self.assertRegex(g, r'mL := NumGet\(mi, 4, "Int"\), mT := NumGet\(mi, 8, "Int"\), mR := NumGet\(mi, 12, "Int"\), '
                            r'mB := NumGet\(mi, 16, "Int"\)')
        self.assertIn('if (x != mL || y != mT || (w <= mR - mL && h <= mB - mT))\n\t\treturn true', g)
        self.assertIn('w := Min(w, mR - mL), h := Min(h, mB - mT)', g)
        # (said once per size, the log line keeping the caller's ErrorLevel - UpdateGameRect runs between a search and
        # its check in places; the size said kept in a global with no initializer - an #Included file's top lines aren't
        # run - and emptied once Autofarmer's debug.log is started: said in that run's own log)
        self.assertRegex(g, r'if \(!IsSet\(GameRectSaid\) \|\| gcSize != GameRectSaid\)[\s\S]*local gcKeep := V1Thread\(\)[\s\S]*%"DebugLog"%\(')
        self.assertRegex(self.gr, r'(?m)^global GameRectSaid$')
        self.assertNotIn('restarting Wizard101', self.gr)
        rot = self.af.index(r'V1Do(FileMove, A_ScriptDir "\debug.log", A_ScriptDir "\debug.previous.log", 1)')
        self.assertLess(self.af.index('local gtBack := WatchTrayBack(A_ScriptDir, 500)\nUpdateGameRect()'), rot)
        self.assertLess(rot, self.af.index('GameRectSaid := ""'))
        # (the bot, the stats reader and the walker on its own all measure the game by it)
        sr = code_of(os.path.join(AF, 'StatsReader.ahk'))
        self.assertIn('GameClientRect(hwnd, &GameLeft, &GameTop, &GameW, &GameH)', sr)
        aq = code_of(os.path.join(AF, '..', 'AutoQuester', 'AutoQuester.ahk'))
        self.assertIn('if (!GameClientRect(hwnd, &x, &y, &w, &h))', body(aq, 'UpdateGameRect'))
        for src in (self.af, sr, aq):
            self.assertIn(r'#Include "%A_ScriptDir%\..\GameRect.ahk"', src)
            self.assertNotIn('GetClientRect", "Ptr", hwnd', src)

    def test_main_loop(self):
        """right after the main loop's UpdateGameRect, with its PicSetOkSize - before the heartbeat line and any search;
        switched: PicSetOkSize emptied (it vouched for the set left)"""
        # (code_of leaves a comment line blank)
        self.assertIsNotNone(re.search(r'\n\tCarryTick\(\)\n\tUpdateGameRect\(\)\n+\tif \(PicSizeKept\(PicSetOkSize\)\)\n'
                                       r'\t\tPicSetOkSize := ""\n\tif \(A_TickCount - LastBeat > 10000\)', self.af))
        self.assertNotIn('PicSizeKept(', code_of(os.path.join(AF, 'StatsReader.ahk')))

    def test_start(self):
        """the start notes the size it chose the set for, right after choosing it - the only other call"""
        self.assertIsNotNone(re.search(r'\nif \(!DetectPicSet\(\)\)\n\tUsePicSet\(PicSetForSize\(\), [^\n]*\n+PicSizeKept\("", true\)\n', self.af))
        self.assertEqual(len(re.findall(r'(?<![\w.])PicSizeKept\(', self.af)), 2)

    def test_kept(self):
        """the start's size (start, or the first look without it) only noted; a change to a remembered size not seen or
        measured since, another scale than the set in use: PicSetForSize, said why - and the size marks that vouched for
        the set left emptied"""
        k = self.fn(self.ps, 'PicSizeKept')
        self.assertRegex(k, r'static seenSize := ""')
        self.assertRegex(k, r'if \(start \|\| seenSize = "" \|\| size = seenSize\)\s*\{\s*seenSize := size\s*return false\s*\}\s*seenSize := size')
        self.assertIn('if (okSize = size || PicCutOkSize = size || PicMeasuredSize = size', k)
        self.assertIn('want := PicScaleFor(size)', k)
        self.assertRegex(k, r'if \(want = "" \|\| V1Lt\(V1Abs\(V1Sub\(PicSets\[PicSet\]\.scale, want\)\), 0\.002\)\)')
        self.assertRegex(k, r'UsePicSet\(PicSetForSize\(\), "the window is " size " now - [^\n]*\n\s*PicCutOkSize := "", PicMeasuredSize := ""\s*return true')
        self.assertEqual(len(re.findall(r'UsePicSet\(', k)), 1)
        self.assertRegex(k, r'global PicCutOkSize, PicMeasuredSize')


if __name__ == '__main__':
    unittest.main()
