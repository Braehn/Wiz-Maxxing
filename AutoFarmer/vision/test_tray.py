"""test_tray.py - v1.10.0's two tray settings, the AutoHotkey side read (not run): traybot (the dashboard's X and
minimize put it in the tray, the bot plays on) and traygame (Alt+F4 in Wizard101, its own X and - windowed - its
minimize hide its window in the tray, the bot off meanwhile). Standard library only:
python3 -m unittest test_tray  (from AutoFarmer\\vision)

Pins the wiring each part needs: the Settings entries and their save hook, the dashboard's close and minimize, the
Alt+F4 hotkey only in the game, the left button's check acting only on the game's own close button (HTCLOSE) with a
bounded wait, the window hidden and shown without the bot ever taking the focus by itself, the shows at exit, at the
next start and from the watcher, nothing the bot had under way sent to the window behind once the game's hidden, a
minimized dashboard back where it was, and nothing that reaches into the game."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AF = os.path.dirname(HERE)              # the AutoFarmer folder
ROOT = os.path.dirname(AF)              # the repository


def read_lines(path):
    with open(path, encoding='utf-8-sig', errors='replace') as f:
        return f.read().splitlines()


def ahk_semi(line):
    """where a line's AutoHotkey comment starts (its first ' ;' / '\\t;' - even inside a string), else len(line), and
    whether that's inside a double-quoted string. "" is an escaped quote, a backtick skips the next character"""
    inq, i = False, 0
    while i < len(line):
        c = line[i]
        if c == '"':
            if inq and i + 1 < len(line) and line[i + 1] == '"':
                i += 2
                continue
            inq = not inq
        elif c == '`':
            i += 2
            continue
        elif c == ';' and i > 0 and line[i - 1] in ' \t':
            return i, inq
        i += 1
    return len(line), False


def semicolon_hits(lines):
    """the code lines with a ' ;' / '\\t;' inside a double-quoted string (AutoHotkey takes it as a comment)"""
    return [(n, ln.strip()) for n, ln in enumerate(lines, 1) if not ln.lstrip().startswith(';') and ahk_semi(ln)[1]]


def ahk_code(lines):
    """each line's code: '' for a comment line (; or a /* */ block), else the line up to its comment"""
    out, block = [], False
    for ln in lines:
        s = ln.lstrip()
        if block or s.startswith('/*'):
            block = '*/' not in (s[2:] if not block else s)
            out.append('')
        elif s.startswith(';'):
            out.append('')
        else:
            out.append(ln[:ahk_semi(ln)[0]])
    return out


def code_of(path):
    return '\n'.join(ahk_code(read_lines(path)))


def body(code, name):
    """a function's body in code (comments gone): 'Name(...)' then '\\t{' ... '\\t}', or 'Name(...) {' ... '}'"""
    m = re.search(r'(?ms)^%s\([^\n]*\)[ \t]*\n\t\{\n(.*?)^\t\}' % re.escape(name), code)
    if not m:
        m = re.search(r'(?ms)^%s\([^\n]*\)[ \t]*\{[^\n]*\n(.*?)^\}' % re.escape(name), code)
    return m.group(1) if m else None


class TrayWiring(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.af = code_of(os.path.join(AF, 'Autofarmer.ahk'))
        cls.dash = code_of(os.path.join(AF, 'Dashboard.ahk'))
        cls.cfg_lines = read_lines(os.path.join(AF, 'Settings.ahk'))
        cls.cfg = '\n'.join(ahk_code(cls.cfg_lines))
        cls.watch = code_of(os.path.join(ROOT, 'Watch.ahk'))
        cls.rc = code_of(os.path.join(AF, 'Reconnect.ahk'))

    def fn(self, code, name):
        b = body(code, name)
        self.assertIsNotNone(b, name + ' not found')
        return b

    # ---- the settings

    def test_settings_entries(self):
        """each a check, off by default, after gamefront, in the simple view; no ' ;' in their strings"""
        order = []
        for key in ('traybot', 'traygame'):
            found = [ln for ln in self.cfg.split('\n') if 'key: "%s"' % key in ln]
            self.assertEqual(len(found), 1, key)
            self.assertRegex(found[0], r'\bkind: "check"', key)
            self.assertRegex(found[0], r'\bdef: 0\b', key)
            self.assertRegex(found[0], r'label: "[^"]*\(untried\)"', key)
            order.append(self.cfg.index('key: "%s"' % key))
        self.assertLess(self.cfg.index('key: "gamefront"'), order[0])
        mine, follow = [], False
        for ln in self.cfg_lines:
            if re.search(r'key: "(traybot|traygame)"', ln):
                mine.append(ln)
                follow = True
            elif follow and ln.lstrip().startswith(','):
                mine.append(ln)
            else:
                follow = False
        self.assertEqual(len(mine), 4, mine)
        self.assertEqual(semicolon_hits(mine), [])
        simple = self.fn(self.cfg, 'CfgSimpleKeys')
        for key in ('traybot', 'traygame'):
            self.assertIn('"%s"' % key, simple)

    def test_save_hook(self):
        """Save applies them at once: through V1IsFunc (Settings.ahk reaches Autofarmer.ahk's functions only so)"""
        save = self.fn(self.cfg, 'CfgSaveNow')
        self.assertRegex(save, r'if \(V1IsFunc\("TrayWinTick"\)\)\s*TrayWinTick\.Call\(\)')
        tick = self.fn(self.af, 'TrayWinTick')
        self.assertIn('tgOn := TrayGameOn()', tick)
        self.assertIn('TrayWinShow()', tick)
        self.assertIn('GameTrayKeys(tgOn)', tick)
        # (traygame switched off with the game in the tray: shown again, never activated - user false)
        self.assertRegex(tick, r'if \(!tgOn && GameInTray\)\s*GameTrayShow\(false, ')

    def test_readers(self):
        for key, name in (('traybot', 'TrayBotOn'), ('traygame', 'TrayGameOn')):
            b = self.fn(self.af, name)
            self.assertIn('Stats["%s"] = 1' % key, b)
            self.assertIn('catch', b)

    def test_not_deck_keys(self):
        dk = code_of(os.path.join(AF, 'Decks.ahk'))
        m = re.search(r'DeckKeys\(\)\s*\{(.*?)return keys', dk, re.S)
        self.assertIsNotNone(m)
        keys = re.findall(r'"(\w+)"', m.group(1))
        self.assertIn('cardlogic', keys)
        self.assertNotIn('traybot', keys)
        self.assertNotIn('traygame', keys)

    def test_playerstats(self):
        """a line each, its comment right above it (the updater carries a key's comment lines with it), CRLF"""
        path = os.path.join(AF, 'PlayerStats.txt')
        with open(path, 'rb') as f:
            raw = f.read()
        self.assertNotIn(b'\n', raw.replace(b'\r\n', b''))
        lines = raw.decode('utf-8').split('\r\n')
        for key in ('traybot', 'traygame'):
            at = [i for i, ln in enumerate(lines) if ln.startswith(key + ':')]
            self.assertEqual(len(at), 1, key)
            self.assertEqual(lines[at[0]], key + ':0')
            self.assertTrue(lines[at[0] - 1].startswith('; '), key)
            self.assertTrue(lines[at[0] - 2].startswith('; ' + key + ': 1 = '), key)

    # ---- traybot: the dashboard

    def test_dashboard_close_and_minimize(self):
        """the X: the setting looked at before ExitApp - on, to the tray and return true (v2 hides nothing more);
        minimized (MinMax -1): to the tray too"""
        close = self.fn(self.dash, 'DashGuiClose')
        self.assertRegex(close, r'if \(V1IsFunc\("TrayBotOn"\) && TrayBotOn\.Call\(\)\)\s*\{\s*DashToTray\("its X"\)'
                                r'\s*return true\s*\}')
        self.assertLess(close.index('TrayBotOn.Call()'), close.index('ExitApp()'))
        size = self.fn(self.dash, 'DashGuiSize')
        self.assertRegex(size, r'if \(MinMax = -1\)\s*\{\s*if \(V1IsFunc\("TrayBotOn"\) && TrayBotOn\.Call\(\)\)\s*'
                               r'DashToTray\("its minimize button"\)\s*return\s*\}')
        hide = self.fn(self.dash, 'DashToTray')
        self.assertLess(hide.index('DashSavePlace()'), hide.index('Dash.Hide()'))
        self.assertIn('DashShown := 0', hide)
        self.assertIn('DebugLog(', hide)
        self.assertRegex(hide, r'if \(!said\)\s*said := true, TrayTip\(')
        # (the tray icon's double-click while it's on: show only - never DashToggle, which hides one that's up)
        show = self.fn(self.dash, 'DashFromTray')
        self.assertNotIn('DashToggle', show)
        self.assertNotIn('Hide', show)
        self.assertIn('DashShow()', show)
        self.assertIn('DashFromTray()', self.fn(self.af, 'MenuDashShow'))
        win = self.fn(self.af, 'TrayWinShow')
        self.assertRegex(win, r'Tray\.Insert\("[^"]+", "Show the bot\'s window", MenuDashShow\)')
        self.assertIn('Tray.Default := tbOn ? "Show the bot\'s window" : HkMenu("walk")', win)
        # (the tray menu's Exit stays - it stops the bot)
        self.assertIn('Tray.Add(HkMenu("quit"), MenuExit)', self.af)

    # ---- traygame: catching Alt+F4, the X and the minimize

    def test_alt_f4_only_in_the_game(self):
        """made under the hook's own check that Wizard101 is the window in front, on only while traygame is"""
        keys = self.fn(self.af, 'GameTrayKeys')
        self.assertRegex(keys, r'HotIfWinActive\("ahk_class Wizard Graphical Client ahk_exe WizardGraphicalClient\.exe"\)'
                               r'\s*HkTry\("\$\*!F4", GameTrayAltF4, on \? "On" : "Off"\)\s*HotIfWinActive\(\)')
        alt = self.fn(self.af, 'GameTrayAltF4')
        self.assertIn('WinActive("ahk_class " GameClass " ahk_exe " GameExe)', alt)
        self.assertIn('GameTrayHide(gaWin, "Alt+F4")', alt)

    def test_x_click_gate(self):
        """the left button's hotkey: its own HotIf check, on only over the title bar; the check never acts in the
        game's inside and only on HTCLOSE (20), asking the game with a bounded wait"""
        gate = self.fn(self.af, 'GameTrayXGate')
        self.assertRegex(gate, r'HotIf\(GameTrayXHit\)\s*HkTry\("\*LButton", GameTrayXClick, on \? "On" : "Off"\)'
                               r'\s*HotIf\(\)')
        self.assertIn('MouseLocked', gate)
        hit = self.fn(self.af, 'GameTrayXHit')
        m = re.search(r'SendMessage\(0x84, 0, [^\n]*, , "ahk_id " xhWin, , , , (\d+)\) = 20\b', hit)
        self.assertIsNotNone(m, 'WM_NCHITTEST with a timeout, HTCLOSE only')
        self.assertLessEqual(int(m.group(1)), 100)
        self.assertEqual(hit.count('SendMessage('), 1)
        # (the game's inside - its client area - never: return false before the game is asked)
        inside = re.search(r'if \(xhX >= xhL && xhX < xhL \+ NumGet\(xhRc, 8, "Int"\) && xhY >= xhT && '
                           r'xhY < xhT \+ NumGet\(xhRc, 12, "Int"\)\)\s*return false', hit)
        self.assertIsNotNone(inside)
        self.assertLess(inside.start(), hit.index('SendMessage('))
        self.assertRegex(hit, r'GetAncestor", "Ptr", xhAt, "UInt", 2, "Ptr"\) != xhWin\)\s*return false')
        self.assertRegex(hit, r'catch\s*return false')
        self.assertIn('GameTrayHide(GameTrayXWin, "its X")', self.fn(self.af, 'GameTrayXClick'))
        step = self.fn(self.af, 'GameTrayStep')
        self.assertIn('GameTrayXGate(!stIconic && seenCaption && GameTrayOverCaption(stWin), stWin)', step)

    def test_minimize_poll(self):
        """IsIconic polled (never WinGetMinMax), windowed only (WS_CAPTION), not exclusive full screen, a change
        seen while running"""
        step = self.fn(self.af, 'GameTrayStep')
        self.assertIn('DllCall("IsIconic", "Ptr", stWin)', step)
        self.assertNotIn('WinGetMinMax', step)
        self.assertIn('& 0xC00000) = 0xC00000', step)
        self.assertRegex(step, r'if \(stWin != seenWin\)\s*seenWin := stWin, seenIconic := stIconic')
        self.assertRegex(step, r'if \(stIconic && seenCaption && !fullScreen\)\s*\{\s*GameTrayXGate\(0\)\s*'
                               r'GameTrayHide\(stWin, "its minimize button"\)')
        self.assertIn('fullScreen := (stQuns = 3)', step)
        tick = self.fn(self.af, 'TrayWinTick')
        self.assertIn('SetTimer(GameTrayTick, 100)', tick)

    # ---- traygame: hiding and showing

    def test_hide(self):
        """refused for two game windows and a reconnect under way; keys let go first, the bot off the normal way,
        then hidden with ShowWindowAsync 0, kept in globals and dashboard.ini"""
        no = self.fn(self.af, 'GameTrayNo')
        self.assertIn('if (gnCount >= 2)', no)
        self.assertIn('if (RcState != "" && RcState != "box" && RcState != "stopped")', no)
        hide = self.fn(self.af, 'GameTrayHide')
        self.assertRegex(hide, r'if \(ghNo != ""\)\s*\{[^}]*TrayTip\([^}]*return false\s*\}')
        order = [hide.index(s) for s in ('ghNo := ', 'ReleaseKeys()', 'GameTrayBotWas := BotOn ? 1 : 0',
                                         'BotToggle()', 'DllCall("ShowWindowAsync", "Ptr", win, "Int", 0)',
                                         'GameInTray := 1')]
        self.assertEqual(order, sorted(order))
        for k in ('hwnd', 'pid', 'min'):
            self.assertRegex(hide, r'V1Do\(IniWrite, \w+, ghIni, "gametray", "%s"\)' % k)
        self.assertRegex(hide, r'if \(!said\)\s*said := true, TrayTip\(')

    def test_shows_never_activate_by_themselves(self):
        """only the tray menu's Show Wizard101 (user) activates it; every other show is SW_SHOWNA / SW_SHOWNOACTIVATE
        / SW_SHOWMINNOACTIVE"""
        show = self.fn(self.af, 'GameTrayShow')
        m = re.search(r'DllCall\("ShowWindowAsync", "Ptr", gsWin, "Int", user \? \(gsMin \? (\d+) : (\d+)\) : '
                      r'\(gsMin \? (\d+) : (\d+)\)\)', show)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(1), '9')
        self.assertIn(m.group(3), ('7',))
        self.assertIn(m.group(4), ('4', '8'))
        self.assertEqual(show.count('WinActivate'), 1)
        self.assertRegex(show, r'if \(user\)\s*\{[^}]*\{[^}]*\}\s*V1Try\(WinActivate, "ahk_id " gsWin\)\s*\}')
        self.assertIn('GameTrayShow(true, ', self.fn(self.af, 'MenuGameShow'))
        back = self.fn(self.af, 'GameTrayBack')
        self.assertRegex(back, r'if \(botBack && gbBot && !BotOn\)\s*BotToggle\(\)')
        forget = self.fn(self.af, 'GameTrayForget')
        self.assertIn('GameInTray := 0', forget)
        self.assertIn('IniDelete(A_ScriptDir "\\dashboard.ini", "gametray")', forget)
        self.assertIn('RcAfterTray()', forget)
        self.assertIn('RcStateAt := A_TickCount', self.fn(self.rc, 'RcAfterTray'))
        win = self.fn(self.af, 'TrayWinShow')
        self.assertRegex(win, r'if \(gameItem && GameInTray\)\s*Tray\.Enable\("Show Wizard101"\)')

    def test_show_holds_the_tick_back(self):
        """Show Wizard101 waits for the window: Critical from before the show till it's forgotten (GameTrayBack) - a
        tick run in that wait would take the show for the game showing itself and bring it out of the tray twice, the
        bot on before the game's in front. A caller's own Critical is left as it was"""
        show = self.fn(self.af, 'GameTrayShow')
        self.assertRegex(show, r'gsCrit := A_IsCritical\s*Critical\(\)')
        for later in ('ShowWindowAsync', 'Sleep(', 'WinActivate'):
            self.assertLess(show.index('Critical()'), show.index(later), later)
        self.assertRegex(show, r'GameTrayBack\("shown again - " why, botBack\)\s*'
                               r'if \(!gsCrit\)\s*Critical\("Off"\)\s*$')
        self.assertEqual(show.count('Critical('), 2)

    def test_dashboard_minimized_comes_back_in_place(self):
        """minimized when it went to the tray (DashSaveWin can't save a minimized window's place): shown with no place
        or size - Windows' own place for it holds - before any of dashboard.ini's numbers are read"""
        show = self.fn(self.dash, 'DashShow')
        m = re.search(r'if \(DashHwnd && DllCall\("IsIconic", "Ptr", DashHwnd\)\)\s*\{\s*Dash\.Show\("NoActivate"\)\s*'
                      r'DashShown := 1\s*DashRefresh\(\)\s*return\s*\}', show)
        self.assertIsNotNone(m)
        self.assertLess(m.start(), show.index('IniRead('))
        self.assertIn('Dash.Show("x" x " y" y " w" w " h" h " NoActivate")', show)
        self.assertRegex(self.fn(self.dash, 'DashSaveWin'), r'if \(mm != 0\)\s*return false')
        self.assertIn('DashShow()', self.fn(self.dash, 'DashFromTray'))

    def test_nothing_sent_elsewhere_once_hidden(self):
        """Alt+F4 or the X hides the game from another thread, maybe while a round or a potion run is under way: what
        that had under way sends nothing more - no click, pointer move or key lands in the window behind. GameInTray
        looked at first, and again right before the click or key; only read there (assigned, it'd be a local)"""
        def first_is_guard(b, ret):
            return re.match(r'\tif \(GameInTray\)\n\t\treturn%s\n' % ret, b.lstrip('\n')) is not None
        for name, ret in (('ClickAt', ''), ('MoveToCard', ''), ('CenterMouse', ''), ('TargetClick', ' 0'),
                          ('Spam', ''), ('LockMove', '')):
            b = self.fn(self.af, name)
            self.assertTrue(first_is_guard(b, ret), name)
            self.assertNotRegex(b, r'GameInTray\s*:=', name)
        for name in ('ClickAt', 'TargetClick'):
            b = self.fn(self.af, name)
            self.assertRegex(b, r'if \(!GameInTray\)\s*Click\(\)', name)
            self.assertEqual(b.count('Click()'), 1, name)
        mob = self.fn(self.af, 'mobloop')
        self.assertRegex(mob, r'^global\n+if \(GameInTray\)\n\treturn\n')
        self.assertRegex(mob, r's\(5000\)\s*if \(GameInTray\)\s*return\s*Send\("\{w down\}"\)')
        lore = re.search(r'(?ms)^LoreLoop\(\)\n\t\{[^\n]*\n(.*?)^\t\}', self.af)
        self.assertIsNotNone(lore)
        self.assertRegex(lore.group(1), r'^\tglobal\n\tlocal _direction\s*\n+\tif \(GameInTray\)\n\t\treturn\n')
        # (every right-click discard in the round's files: looked at right before the click)
        for fname in ('Autofarmer.ahk', 'KillCalc.ahk', 'Draw.ahk', 'CardLearn.ahk'):
            code = self.af if fname == 'Autofarmer.ahk' else code_of(os.path.join(AF, fname))
            n = code.count('Click("right")')
            self.assertGreaterEqual(n, 1, fname)
            guarded = re.findall(r'if \(GameInTray\)\n\t+(?:break|return[^\n]*)\n\t+Click\("right"\)', code)
            self.assertEqual(len(guarded), n, fname)
        flee = self.fn(code_of(os.path.join(AF, 'Flee.ahk')), 'FleeCheck')
        self.assertRegex(flee, r'if \(!CastWentOut\(\)\)\s*\{\s*if \(GameInTray\)\s*return false\s*fx := ')
        pot = code_of(os.path.join(AF, 'Potions.ahk'))
        self.assertRegex(self.fn(pot, 'PotionCheck'),
                         r'hp := PotionHealth\(\)\s*if \(hp = "" \|\| GameInTray\)\s*return')
        drink = self.fn(pot, 'PotionDrink')
        self.assertTrue(first_is_guard(drink, ' false'))
        self.assertLess(drink.index('GameInTray'), drink.index('Send('))
        self.assertRegex(self.fn(pot, 'PotionRun'), r'if \(GameInTray\)\s*return false\s*Send\("\{Blind\}\{PgDn\}"\)')
        self.assertRegex(self.fn(pot, 'PotionTeleport'), r'if \(GameInTray\)\s*return false\s*Send\("\{Blind\}" key\)')
        for name in ('PotionCheck', 'PotionDrink', 'PotionRun', 'PotionTeleport'):
            self.assertNotRegex(self.fn(pot, name), r'GameInTray\s*:=', name)
        # (a global, declared - so the reads above find it)
        self.assertIn('global GameInTray := 0', self.fn(self.af, 'AutofarmerBlank'))

    def test_on_exit(self):
        """the bot closing: shown again, never activated, the bot not switched on; first of the callbacks; 0"""
        ex = self.fn(self.af, 'GameTrayOnExit')
        self.assertRegex(ex, r'try\s*\{\s*if \(GameInTray\)\s*GameTrayShow\(false, "[^"]+", false\)\s*\}')
        self.assertRegex(ex, r'return 0\s*$')
        start = self.fn(self.af, 'StartBot')
        self.assertIn('OnExit(GameTrayOnExit, -1)', start)
        self.assertIn('TrayWinTick()', start)

    def test_start_up_recovery(self):
        """the bot starting: a game left hidden by a run that died shown again before its window is measured"""
        start = self.fn(self.af, 'StartBot')
        self.assertIn('local gtBack := WatchTrayBack(A_ScriptDir, ', start)
        self.assertLess(start.index('WatchTrayBack('), start.index('UpdateGameRect()'))
        self.assertRegex(start, r'if \(gtBack != ""\)\s*DebugLog\(')

    def test_watch_recovery(self):
        """WatchTrayBack: the stored window, the same process and class, hidden - shown without activating, then
        forgotten; the watcher runs it while no bot runs"""
        back = self.fn(self.watch, 'WatchTrayBack')
        self.assertIn('IniRead(wtIni, "gametray", "hwnd", "")', back)
        self.assertIn('DllCall("IsWindow", "Ptr", wtHwnd)', back)
        self.assertIn('if (wtWinPid = wtPid && StrGet(wtCls) = "Wizard Graphical Client")', back)
        self.assertIn('DllCall("IsWindowVisible", "Ptr", wtHwnd)', back)
        m = re.search(r'DllCall\("ShowWindowAsync", "Ptr", wtHwnd, "Int", wtMin = 1 \? (\d+) : (\d+)\)', back)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(1), '7')
        self.assertIn(m.group(2), ('4', '8'))
        self.assertNotIn('WinActivate', back)
        self.assertIn('IniDelete(wtIni, "gametray")', back)
        loop = self.fn(self.watch, 'WatchGame')
        self.assertRegex(loop, r'if \(WatchTrayLeft\(dir\) && !WatchBotRunning\(\)\)\s*WatchTrayBack\(dir\)')

    def test_while_in_the_tray(self):
        """the bot never brings it up, can't be switched on, and the tray's game actions say "show it first"; the
        dashboard says so; a game that closed or showed itself is forgotten"""
        front = self.fn(self.af, 'GameToFront')
        self.assertRegex(front, r'if \(GameInTray\)\s*return false')
        self.assertLess(front.index('GameInTray'), front.index('WinActivate'))
        bot = self.fn(self.af, 'BotToggle')
        self.assertRegex(bot, r'if \(!BotOn && GameTrayBlocked\("[^"]+"\)\)\s*return')
        self.assertLess(bot.index('GameTrayBlocked'), bot.index('BotOn := !BotOn'))
        for menu, then in (('MenuPotionRun', 'PotionRun()'), ('MenuPotionRoute', 'PotionRecordStart()'),
                           ('MenuQuickSell', 'QsMenuNow(false)'), ('MenuQuickSellRehearse', 'QsMenuNow(true)')):
            b = self.fn(self.af, menu)
            self.assertRegex(b, r'if \(GameTrayBlocked\("[^"]+"\)\)\s*return', menu)
            self.assertLess(b.index('GameTrayBlocked'), b.index(then), menu)
        self.assertRegex(self.fn(self.dash, 'DashRefresh'), r'if \(GameInTray\)\s*doing := "Wizard101 is in the tray')
        step = self.fn(self.af, 'GameTrayStep')
        self.assertRegex(step, r'if \(!DllCall\("IsWindow", "Ptr", GameTrayHwnd\) \|\| \(GameTrayPid && '
                               r'!ProcessExist\(GameTrayPid\)\)\)\s*GameTrayBack\(')

    def test_nothing_reaches_into_the_game(self):
        """no injection, no hook into the game, no message to it but the X's hit test, no window call that takes
        the focus or closes it (the only WinActivate: the tray menu's Show Wizard101)"""
        names = ['TrayBotOn', 'TrayGameOn', 'TrayWinTick', 'TrayWinShow', 'GameTrayKeys', 'GameTrayAltF4',
                 'GameTrayXClick', 'GameTrayNo', 'GameTrayHide', 'GameTrayShow', 'GameTrayBack', 'GameTrayForget',
                 'GameTrayBlocked', 'GameTrayOnExit', 'GameTrayTick', 'GameTrayStep', 'GameTrayOverCaption',
                 'GameTrayXGate', 'GameTrayXHit']
        code = '\n'.join(self.fn(self.af, n) for n in names)
        code += '\n' + self.fn(self.watch, 'WatchTrayBack') + '\n' + self.fn(self.dash, 'DashToTray')
        for bad in ('WriteProcessMemory', 'CreateRemoteThread', 'VirtualAllocEx', 'SetWindowsHookEx', 'LoadLibrary',
                    'SetWinEventHook', 'SetWindowLong', 'SetWindowLongPtr', 'PostMessage', 'WinClose', 'WinKill',
                    'ProcessClose', 'WinHide', 'WinShow', 'WinRestore', 'WinMinimize', 'WinMaximize', 'ControlSend',
                    'ControlClick', 'Send', 'SendInput', 'SendEvent', 'Click', 'MouseClick', 'DetectHiddenWindows'):
            # (a whole name - TrayWinShow isn't WinShow, SendMessage isn't Send)
            self.assertIsNone(re.search(r'(?<!\w)%s\b' % bad, code), bad)
        self.assertEqual(len(re.findall(r'(?<!\w)WinActivate\b', code)), 1)
        self.assertEqual(len(re.findall(r'(?<!\w)SendMessage\b', code)), 1)


if __name__ == '__main__':
    unittest.main()
