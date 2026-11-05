"""test_dashmenu.py - v1.10.0's menu bar on the dashboard (File | Bot | View | Settings | Help: most of its buttons
moved there), the AutoHotkey side read (not run). Standard library only:
python3 -m unittest test_dashmenu  (from AutoFarmer\\vision)

Pins the bar and its Alt letters (none an Alt key the bot takes while it's on), each menu's items in their places and
what each does (what its button or the tray menu's item did), every pick a thread of its own that hands the menu's
ItemName, ItemPos and Menu to no button handler and is logged as the menu's (never through the tray's handlers), the
bar put on the window after its last control and before the window's first shown, the ticks kept by every hook that
shows a state and by the once-a-second look, "Update to vX" at the bar's right end while one is out, the keys the
items name made again when one changes, the tray settings saved through Settings.ahk CfgApply, Save / Load settings
through SettingsFile.ahk (included right after Settings.ahk), the buttons that moved gone from the window, the bot's
button on the heading row and the window's sizes without the bottom row.

And one check of every script: each control reached through Dash["X"] - or a list a loop hands to Dash[c], or a
helper's parameter (DashSet) - is one Dashboard.ahk makes with vX. AutoHotkey v2 throws on one that isn't there, only
when the line runs: a reference left to a removed button."""
import os
import re
import subprocess
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


def ahk_files():
    """every .ahk file of the repository: git's - tracked, and new ones not ignored (not committed yet) - else the
    folders walked (an unzipped release)"""
    try:
        out = subprocess.run(['git', 'ls-files', '--cached', '--others', '--exclude-standard', '--', '*.ahk'],
                             cwd=ROOT, capture_output=True, text=True, check=True).stdout
        files = [os.path.normpath(os.path.join(ROOT, f)) for f in out.splitlines() if f.strip()]
        files = [f for f in files if os.path.isfile(f)]
    except (OSError, subprocess.CalledProcessError):
        files = []
    if not files:
        for d, _, fs in os.walk(ROOT):
            files += [os.path.normpath(os.path.join(d, f)) for f in fs if f.lower().endswith('.ahk')]
    return sorted(set(files))


def skip_string(text, i):
    """text[i] is a '"': where its string ends (just past the closing quote - a backtick escapes the next character;
    a string never runs past its line)"""
    j = i + 1
    while j < len(text) and text[j] not in '"\n':
        j += 2 if text[j] == '`' else 1
    return min(j + 1, len(text))


def call_args(text, at):
    """the arguments (stripped texts) of the call or index whose '(' / '[' is just before text[at], and where its
    closing bracket is: ([], i) for none; (None, len) if it never closes"""
    args, depth, cur, i = [], 0, [], at
    while i < len(text):
        c = text[i]
        if c == '"':
            j = skip_string(text, i)
            cur.append(text[i:j])
            i = j
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            if depth == 0:
                args.append(''.join(cur).strip())
                return ([] if args == [''] else args), i
            depth -= 1
        elif c == ',' and depth == 0:
            args.append(''.join(cur).strip())
            cur = []
            i += 1
            continue
        cur.append(c)
        i += 1
    return None, len(text)


def strings_in(expr):
    """the double-quoted string literals in an expression, in order"""
    out, i = [], 0
    while i < len(expr):
        if expr[i] == '"':
            j = skip_string(expr, i)
            out.append(expr[i + 1:j - 1])
            i = j
        else:
            i += 1
    return out


def lead(expr):
    """the string an expression starts with ("Exit" DashMenuKey("quit") -> Exit), else None"""
    m = re.match(r'\s*"((?:[^"`\n]|`.)*)"', expr)
    return m.group(1) if m else None


def masked(code):
    """code with every string's inside blanked (same length, line by line): what's found in it is code, not words"""
    out = []
    for ln in code.split('\n'):
        chars, i = list(ln), 0
        while i < len(ln):
            if ln[i] == '"':
                j = skip_string(ln, i)
                for k in range(i + 1, max(i + 1, j - 1)):
                    chars[k] = ' '
                i = j
            else:
                i += 1
        out.append(''.join(chars))
    return '\n'.join(out)


def functions(code):
    """[(name, [parameter names], body start, body end)] - both of body()'s shapes"""
    out = []
    for pat in (r'(?ms)^(\w+)\(([^\n]*)\)[ \t]*\n\t\{\n(.*?)^\t\}', r'(?ms)^(\w+)\(([^\n]*)\)[ \t]*\{[^\n]*\n(.*?)^\}'):
        for m in re.finditer(pat, code):
            ps, _ = call_args(m.group(2) + ')', 0)
            names = [re.sub(r'^[&*]|:=.*$|\*$', '', p).strip() for p in (ps or [])]
            out.append((m.group(1), [n for n in names if n], m.start(3), m.end(3)))
    return out


# AutoHotkey v2's Gui members (Dash.X): anything else on Dash is no control - a control is Dash["X"]
GUI_MEMBERS = set(n.lower() for n in """
Add AddActiveX AddButton AddCheckbox AddComboBox AddCustom AddDateTime AddDDL AddDropDownList AddEdit AddGroupBox
AddHotkey AddLink AddListBox AddListView AddMonthCal AddPic AddPicture AddProgress AddRadio AddSlider AddStatusBar
AddTab AddTab2 AddTab3 AddText AddTreeView AddUpDown Destroy Flash GetClientPos GetPos Hide Maximize Minimize Move
OnEvent Opt Restore SetFont Show Submit BackColor FocusedCtrl Hwnd MarginX MarginY MenuBar Name Title
""".split())

# paths a message might show (never a whole path in debug.log or a box: file and folder names only)
PATHS = ('A_ScriptDir', 'A_WorkingDir', 'A_ScriptFullPath', 'A_AppData', 'A_Temp', 'A_MyDocuments', 'A_Desktop',
         'A_ProgramFiles', 'A_ComSpec', 'A_InitialWorkingDir')


def path_names(b):
    """the names in a function body that hold a whole path: the built-in ones, a variable set to one (or to a
    string starting with one), a SplitPath's OutDir of one - a SplitPath's OutFileName is a name only"""
    names = set(PATHS)
    for _ in range(3):
        for m in re.finditer(r'\b(\w+) := (\w+)', b):
            if m.group(2) in names:
                names.add(m.group(1))
        for m in re.finditer(r'\bSplitPath\((\w+)\s*,\s*&?\w*\s*,\s*&(\w+)', b):
            if m.group(1) in names:
                names.add(m.group(2))
    return names


class DashMenuBar(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dash = code_of(os.path.join(AF, 'Dashboard.ahk'))
        cls.af = code_of(os.path.join(AF, 'Autofarmer.ahk'))
        cls.cfg = code_of(os.path.join(AF, 'Settings.ahk'))
        cls.hk = code_of(os.path.join(AF, 'Hotkeys.ahk'))
        sf = os.path.join(AF, 'SettingsFile.ahk')
        cls.sf = code_of(sf) if os.path.isfile(sf) else ''
        cls.make = body(cls.dash, 'DashMenuMake') or ''
        cls.menus, cls.bar, cls.barvar = cls.parse_menus(cls.make)

    @staticmethod
    def parse_menus(make):
        """DashMenuMake's menus - {key: [item (name expression, callback expression, options), or None: a line]},
        the bar's [(caption, key)] in order, and the bar's variable"""
        menus, bar = {}, []
        mb = re.search(r'\b(\w+) := MenuBar\(\)', make)
        keyed = re.search(r'DashMenus := Map\(([^\n]*)\)', make)
        if not mb or not keyed:
            return menus, bar, None
        keys = {var: key for key, var in re.findall(r'"(\w+)", (\w+)', keyed.group(1))}
        made = set(re.findall(r'\b(\w+) := Menu\(\)', make))
        for m in re.finditer(r'\b(\w+)\.Add\(', make):
            var = m.group(1)
            args, _ = call_args(make, m.end())
            if args is None:
                continue
            if var == mb.group(1):
                bar.append((lead(args[0]), keys.get(args[1]) if len(args) > 1 else None))
            elif var in made and var in keys:
                menus.setdefault(keys[var], []).append(
                    None if not args else (args[0], args[1] if len(args) > 1 else '', args[2] if len(args) > 2 else ''))
        return menus, bar, mb.group(1)

    def fn(self, code, name):
        b = body(code, name)
        self.assertIsNotNone(b, name + ' not found')
        return b

    def pos(self, key, text):
        """where item text (its leading words) is in menu key, counting the lines - as "N&" counts"""
        names = [None if it is None else lead(it[0]) for it in self.menus.get(key, [])]
        self.assertIn(text, names, '%s > %s' % (key, text))
        return names.index(text) + 1

    def handler(self, key, text):
        """what an item's pick runs: X of DashMenuRun.Bind("Menu", X)"""
        cb = self.menus[key][self.pos(key, text) - 1][1]
        m = re.match(r'DashMenuRun\.Bind\("[^"]*", (.+)\)$', cb)
        self.assertIsNotNone(m, '%s > %s: %s' % (key, text, cb))
        return m.group(1)

    # ---- the bar

    def test_bar_and_alt_letters(self):
        """a MenuBar of the five menus, in order; Settings is Se&ttings - Alt+S (and every Alt key the bot's hotkeys
        take while it's on: Hotkeys.ahk's defaults) is none of the bar's letters"""
        self.assertIsNotNone(self.barvar, 'no MenuBar() in DashMenuMake')
        self.assertEqual(self.bar, [('&File', 'file'), ('&Bot', 'bot'), ('&View', 'view'), ('Se&ttings', 'set'),
                                    ('&Help', 'help')])
        self.assertNotIn('&Settings', self.dash)
        letters = [re.search(r'&(\w)', cap).group(1).lower() for cap, _ in self.bar]
        self.assertEqual(len(set(letters)), len(letters))
        alt = {k.lower() for k in re.findall(r'\bdef: "!(\w)"', self.fn(self.hk, 'HkActions'))}
        self.assertEqual(set(letters) & alt, set())
        self.assertTrue({'1', '2', 'e', 'l', 'd', 'c', 's', 'r'} <= alt, alt)
        self.assertIn('DashMenus := Map("file", ', self.make)
        self.assertRegex(self.make, r'"bar", %s\)' % self.barvar)

    def test_the_items(self):
        """each menu's items in their places (a line: '-'); the keys an item names only through DashMenuKey"""
        want = {
            'file': ['Save settings as...', 'Load settings from...', '-', 'Open bot folder', 'Open debug.log', '-',
                     'Exit'],
            'bot': ['Bot on/off', 'Walking on/off', '-', 'Play for me', 'Wait for me', 'Bring Wizard101 to the front',
                    '-', 'Show Wizard101'],
            'view': ['Map', 'Simple view', '-', 'Log colours...', 'Pause log', 'Clear log', '-', 'Overlay'],
            'set': ['Settings...', '-', "Put the bot's window in the tray", 'Put Wizard101 in the tray', '-',
                    'Discord alerts...', 'Party...', 'Wizard101 login...'],
            'help': ['Check for updates', 'Report a bug...', 'Read me', '-', 'About']}
        got = {k: ['-' if it is None else lead(it[0]) for it in its] for k, its in self.menus.items()}
        self.assertEqual(got, want)
        keyed = {}
        for key, its in self.menus.items():
            for it in its:
                if it is None:
                    continue
                self.assertNotIn('`t', it[0], 'a tab only from DashMenuKey: ' + it[0])
                m = re.fullmatch(r'"[^"]*"(?: DashMenuKey\("(\w+)"\))?', it[0])
                self.assertIsNotNone(m, it[0])
                if m.group(1):
                    keyed[(key, lead(it[0]))] = m.group(1)
        self.assertEqual(keyed, {('file', 'Exit'): 'quit', ('bot', 'Bot on/off'): 'bot',
                                 ('bot', 'Walking on/off'): 'walk', ('view', 'Overlay'): 'overlay'})

    def test_every_pick_is_a_thread_of_its_own(self):
        """each item: DashMenuRun.Bind("<its menu>", X) - a thread (V1Thread) that logs the pick and calls X with
        nothing (a Dash* button handler would take ItemName, ItemPos, Menu for A_GuiEvent, A_GuiControl, Info); never a
        tray handler (TrayPicked would log it as "Tray: ...")"""
        tops = {key: cap.replace('&', '') for cap, key in self.bar}
        tray = set(re.findall(r'(?m)^(Menu\w+)\(A_ThisMenuItem', self.af))
        self.assertIn('MenuExit', tray)
        n = 0
        for key, its in self.menus.items():
            for it in its:
                if it is None:
                    continue
                n += 1
                m = re.match(r'DashMenuRun\.Bind\("([^"]*)", (.+)\)$', it[1])
                self.assertIsNotNone(m, '%s: %s' % (it[0], it[1]))
                self.assertEqual(m.group(1), tops[key], it[0])
                self.assertNotIn(re.match(r'\w+', m.group(2)).group(0), tray, it[0])
        self.assertEqual(n, 27)
        for t in tray:
            self.assertIsNone(re.search(r'(?<![\w"])%s\b' % t, self.dash), t)
        self.assertNotIn('TrayPicked', self.dash)
        m = re.search(r'(?m)^DashMenuRun\((\w+), (\w+), (\w+) := "", \*\)$', self.dash)
        self.assertIsNotNone(m, 'DashMenuRun(top, fn, item := "", *): the menu\'s other two swallowed by *')
        run = self.fn(self.dash, 'DashMenuRun')
        self.assertRegex(run, r'^\s*local v1Keep := V1Thread\(\)[ \t]*\n')
        fnp = m.group(2)
        self.assertEqual(re.findall(r'(?<![\w.])%s\(([^)]*)\)' % fnp, run), [''])
        self.assertRegex(run, r'DebugLog\("Menu: " ')
        self.assertIn('RegExReplace(%s, "`t.*")' % m.group(3), run)

    def test_each_does_what_its_button_or_tray_item_did(self):
        """an item's pick reaches the same call as the tray menu's item for it (or the button it replaced)"""
        same = [('bot', 'Bot on/off', 'BotToggle', 'MenuBotToggle'),
                ('bot', 'Walking on/off', 'WalkToggle', 'MenuWalk'),
                ('bot', 'Play for me', 'PlayForMeToggle', 'MenuPlayForMe'),
                ('bot', 'Wait for me', 'HandsOffToggle', 'MenuHandsOff'),
                ('bot', 'Bring Wizard101 to the front', 'GameFrontToggle', 'MenuGameFront'),
                ('bot', 'Show Wizard101', 'GameTrayShow', 'MenuGameShow'),
                ('view', 'Map', 'DashMapToggle', 'MenuMap'),
                ('view', 'Overlay', 'OverlayToggle', 'MenuOverlay'),
                ('set', 'Settings...', 'CfgShow', 'MenuSettings'),
                ('set', 'Discord alerts...', 'AlertSetup', 'MenuAlerts'),
                ('set', 'Party...', 'PartySetup', 'MenuParty'),
                ('set', 'Wizard101 login...', 'ReconnectSetLogin', 'MenuLogin'),
                ('help', 'Check for updates', 'UpdCheckNow', 'MenuUpdates'),
                ('help', 'Report a bug...', 'BugShow', 'MenuBug'),
                ('file', 'Exit', 'ExitApp', 'MenuExit')]
        for key, text, core, tray in same:
            h = self.handler(key, text)
            if h != core:
                self.assertRegex(self.fn(self.dash, h), r'(?<![\w."])%s(\.Call)?\(' % core, text)
            self.assertRegex(self.fn(self.af, tray), r'(?<![\w."])%s\(' % core, tray)
        # (Show Wizard101: the user's own pick - shown and brought to the front, as the tray's: user true)
        self.assertRegex(self.fn(self.dash, self.handler('bot', 'Show Wizard101')), r'GameTrayShow\.Call\(true, "')
        self.assertIn('GameTrayShow(true, ', self.fn(self.af, 'MenuGameShow'))
        # (Check for updates: the old button's - "Checking..." a while)
        self.assertEqual(self.handler('help', 'Check for updates'), 'DashUpdButton')
        upd = self.fn(self.dash, 'DashUpdButton')
        self.assertRegex(upd, r'if \(UpdCheckNow\(\)\)\s*\{\s*DashUpdBusy := A_TickCount\s*DashMenuTicks\(\)')
        # (the ones with no tray item: what their buttons did)
        own = [('file', 'Open bot folder', 'Run(A_ScriptDir)'),
               ('file', 'Open debug.log', '\\debug.log'),
               ('view', 'Simple view', 'DashSimple := !DashSimple'),
               ('view', 'Log colours...', 'DashLogColorsWindow()'),
               ('view', 'Pause log', 'DashPaused := !DashPaused'),
               ('view', 'Clear log', 'Dash["DashConsole"].Text := ""'),
               ('help', 'Read me', '"\\README.txt"'),
               ('help', 'About', 'BotVersion()')]
        for key, text, does in own:
            self.assertIn(does, self.fn(self.dash, self.handler(key, text)), text)
        self.assertTrue(os.path.isfile(os.path.join(AF, 'README.txt')))

    def test_bar_put_on_after_the_last_control(self):
        """Dash.MenuBar set once, in DashMenuMake, the bar complete; DashMenuMake run by DashInit after its last
        control and before the window's minimum size (DashApplyView) and first show"""
        self.assertEqual(self.dash.count('Dash.MenuBar :='), 1)
        at = self.make.index('Dash.MenuBar := %s' % self.barvar)
        self.assertLess(self.make.rindex(self.barvar + '.Add('), at)
        init = self.fn(self.dash, 'DashInit')
        call = init.index('DashMenuMake()')
        self.assertEqual(init.count('DashMenuMake()'), 1)
        self.assertLess(init.rindex('Dash.Add('), call)
        self.assertLess(init.rindex('.OnEvent('), call)
        self.assertLess(call, init.index('DashApplyView()'))
        self.assertLess(call, init.index('DashShow()'))
        # (it can't break the window: an error only logged)
        self.assertRegex(self.make, r'catch as (\w+)\s*\{\s*DashMenus := ""\s*DebugLog\("Dashboard: ')

    # ---- the ticks

    def test_ticks_from_every_hook(self):
        """DashMenuTicks from each hook that shows a state, and every second from DashRefresh (Walking, the tray
        settings, Wizard101 in the tray, the overlay are set in many places); the Autofarmer.ahk hooks reach them"""
        for name in ('DashBotShow', 'DashHandsShow', 'DashPlayShow', 'DashFrontShow', 'DashMapShow', 'DashMapHide',
                     'DashPauseLog', 'DashApplyView', 'DashRefresh', 'DashWalkToggle', 'DashUpdButton',
                     'DashMenuMake'):
            self.assertIn('DashMenuTicks()', self.fn(self.dash, name), name)
        ref = self.fn(self.dash, 'DashRefresh')
        self.assertLess(ref.index('DashUpdBusy := 0'), ref.index('DashMenuTicks()'))
        for hook, dash in (('BotOnShow', 'DashBotShow'), ('HandsOffShow', 'DashHandsShow'),
                           ('PlayForMeShow', 'DashPlayShow'), ('GameFrontShow', 'DashFrontShow')):
            self.assertRegex(self.fn(self.af, hook), r'if \(V1IsFunc\("%s"\)\)\s*%s\.Call\(' % (dash, dash), hook)
        # (Settings saved, from the window, the menu or a file: Settings.ahk CfgApply)
        self.assertRegex(self.fn(self.cfg, 'CfgApply'), r'if \(V1IsFunc\("DashMenuTicks"\)\)\s*DashMenuTicks\.Call\(\)')

    def test_ticks_read_the_state(self):
        """each tick and greyed item from the state itself, by its place; nothing before the bar's made; an error
        logged once, never a box"""
        ticks = self.fn(self.dash, 'DashMenuTicks')
        self.assertRegex(ticks, r'^\s*static [^\n]*\n\s*try\s*\{\s*if \(!IsObject\(DashMenus\)\)\s*return\n')
        want = [('bot', 'Bot on/off', 'tick', 'BotOn'),
                ('bot', 'Walking on/off', 'tick', 'Walking'),
                ('bot', 'Play for me', 'tick', 'PlayForMe'),
                ('bot', 'Wait for me', 'tick', 'V1IsFunc("HandsOffOn") && HandsOffOn.Call()'),
                ('bot', 'Bring Wizard101 to the front', 'tick', 'V1IsFunc("GameFrontOn") && GameFrontOn.Call()'),
                ('bot', 'Show Wizard101', 'on', 'GameInTray'),
                ('view', 'Map', 'tick', 'DashMapShown'),
                ('view', 'Simple view', 'tick', 'DashSimple'),
                ('view', 'Pause log', 'tick', 'DashPaused'),
                ('view', 'Pause log', 'on', '!DashSimple'),
                ('view', 'Clear log', 'on', '!DashSimple'),
                ('view', 'Overlay', 'tick', 'V1IsFunc("OvStat") && OvStat.Call("overlay", 0)'),
                ('set', "Put the bot's window in the tray", 'tick', 'V1IsFunc("TrayBotOn") && TrayBotOn.Call()'),
                ('set', 'Put Wizard101 in the tray', 'tick', 'V1IsFunc("TrayGameOn") && TrayGameOn.Call()'),
                ('help', 'Check for updates', 'on', '!DashUpdBusy')]
        for key, text, what, state in want:
            self.assertIn('DashMenuSet("%s", %d, "%s", %s)' % (key, self.pos(key, text), what, state), ticks, text)
        self.assertEqual(ticks.count('DashMenuSet('), len(want))
        self.assertIn('DashMenuName("help", %d, DashUpdBusy ? "Checking..." : "Check for updates")'
                      % self.pos('help', 'Check for updates'), ticks)
        self.assertRegex(ticks, r'catch as (\w+)\s*\{\s*if \(!errSaid\)\s*errSaid := 1, DebugLog\(')
        # (every place named anywhere is an item - not a line, not past the end)
        for key, p in re.findall(r'DashMenu(?:Set|Name)\("(\w+)", (\d+),', self.dash):
            its = self.menus.get(key, [])
            self.assertTrue(1 <= int(p) <= len(its) and its[int(p) - 1] is not None, '%s %s' % (key, p))
        # (set by place, only when changed)
        ms = self.fn(self.dash, 'DashMenuSet')
        self.assertRegex(ms, r'(\w+) := pos "&"')
        for verb in ('Check', 'Uncheck', 'Enable', 'Disable'):
            self.assertRegex(ms, r'\.%s\(\w+\)' % verb)
        self.assertRegex(ms, r'if \(was\.Has\(\w+\) && was\[\w+\] = want\)\s*return')
        # (renamed only when the name is new - "Checking..." and back, a key changed - and remembered after)
        self.assertRegex(self.fn(self.dash, 'DashMenuName'),
                         r'if \(named\.Has\(mnKey\) && named\[mnKey\] == name\)\s*return\s*'
                         r'DashMenus\[which\]\.Rename\(pos "&", name\)\s*named\[mnKey\] := name\s*$')

    def test_the_update_item(self):
        """a newer version out (UpdState): "Update to vX" at the bar's right end ("Right" - a MenuBar's own option),
        the dashboard's update button's pick; taken off when there's none; the bar touched only when that changed (the
        name it shows remembered) and drawn again after"""
        ticks = self.fn(self.dash, 'DashMenuTicks')
        self.assertIn('V1IsFunc("UpdState") ? UpdState.Call() : ""', ticks)
        self.assertRegex(ticks, r'\.newer\) \? "Update to " \w+\.latest : ""')
        m = re.search(r'(\w+)\.Add\((\w+), DashMenuRun\.Bind\("", DashUpdButton\), "Right"\)', ticks)
        self.assertIsNotNone(m)
        bv, n = m.group(1), len(self.bar) + 1
        self.assertIn('%s := DashMenus["bar"]' % bv, ticks)
        dl = re.search(r'if \(%s != (\w+)\)\s*\{\s*if \(\1 != ""\)\s*%s\.Delete\("%d&"\)\s*if \(%s != ""\)\s*%s\.Add\('
                       r'[^\n]*\n\s*\1 := %s\n' % (m.group(2), bv, n, m.group(2), bv, m.group(2)), ticks)
        self.assertIsNotNone(dl, 'only when it changed: the old one taken off first, the new one only when there is '
                                 'one, and its name remembered')
        self.assertRegex(ticks, r'(?m)^\s*static [^\n]*\b%s := ""' % dl.group(1))
        draw = 'DllCall("DrawMenuBar", "Ptr", DashHwnd)'
        self.assertLess(m.start(), ticks.index(draw))
        for verb in ('Enable', 'Disable'):
            self.assertLess(ticks.index('%s.%s("%d&")' % (bv, verb, n)), ticks.rindex(draw))
        self.assertEqual(ticks.count(draw), 2)
        self.assertEqual(self.dash.count('"Right"'), 1)

    # ---- the keys the items name

    def test_key_text_follows_the_keys_tab(self):
        """DashKeysChanged names the items again (by place, as DashMenuMake named them); the text after the tab is
        HkText's, in brackets - display only (a bare key name after a tab is a shortcut in a menu bar)"""
        self.assertIn('DashMenuKeys()', self.fn(self.dash, 'DashKeysChanged'))
        keys = self.fn(self.dash, 'DashMenuKeys')
        self.assertRegex(keys, r'^\s*try\s*\{\s*if \(!IsObject\(DashMenus\)\)\s*return\n')
        n = 0
        for key, its in self.menus.items():
            for p, it in enumerate(its, 1):
                if it and 'DashMenuKey(' in it[0]:
                    n += 1
                    self.assertIn('DashMenuName("%s", %d, %s)' % (key, p, it[0]), keys)
        self.assertEqual(keys.count('DashMenuName('), n)
        self.assertEqual(n, 4)
        mk = self.fn(self.dash, 'DashMenuKey')
        m = re.search(r'(\w+) := HkText\(id\)', mk)
        self.assertIsNotNone(m)
        self.assertRegex(mk, r'return %s = "\(none\)" \? "" : "`t\(" %s "\)"' % (m.group(1), m.group(1)))

    # ---- the settings

    def test_tray_settings_through_cfgapply(self):
        """Put the bot's window / Wizard101 in the tray: switched through Settings.ahk CfgApply(Map(key, new),
        "Menu") - reached only through V1IsFunc, nothing written here"""
        for text, key in (("Put the bot's window in the tray", 'traybot'), ('Put Wizard101 in the tray', 'traygame')):
            self.assertEqual(self.handler('set', text), 'DashMenuTraySet.Bind("%s")' % key)
        ts = self.fn(self.dash, 'DashMenuTraySet')
        self.assertRegex(ts, r'^\s*if \(!V1IsFunc\("CfgApply"\)\)\s*return\n')
        m = re.search(r'CfgApply\.Call\(Map\(key, (\w+) \? 0 : 1\), "Menu"\)', ts)
        self.assertIsNotNone(m)
        self.assertRegex(ts, r'%s := \(key = "traybot"\) \? \(V1IsFunc\("TrayBotOn"\) && TrayBotOn\.Call\(\)\) : '
                             r'\(V1IsFunc\("TrayGameOn"\) && TrayGameOn\.Call\(\)\)' % m.group(1))
        for bad in ('CfgWrite', 'StatsSet', 'IniWrite', 'FileAppend', 'FileOpen', 'Stats['):
            self.assertNotIn(bad, ts)
        self.assertIsNone(re.search(r'(?<![\w"])CfgApply\(', self.dash))
        # (CfgApply takes the two: a third, if any, optional)
        self.assertRegex(self.cfg, r'(?m)^CfgApply\(pairs, source(?:, \w+ := [^,)]+)*\)$')

    def test_save_and_load_through_v1isfunc(self):
        """File > Save settings as... / Load settings from...: SettingsFile.ahk's CfgSaveAs / CfgLoadFrom (no
        parameters), reached only through V1IsFunc"""
        for text, name, f in (('Save settings as...', 'DashMenuSaveAs', 'CfgSaveAs'),
                              ('Load settings from...', 'DashMenuLoadFrom', 'CfgLoadFrom')):
            self.assertEqual(self.handler('file', text), name)
            self.assertRegex(self.fn(self.dash, name), r'if \(V1IsFunc\("%s"\)\)\s*%s\.Call\(\)' % (f, f))
            self.assertIsNone(re.search(r'(?<![\w"])%s\(' % f, self.dash), f)
            self.assertRegex(self.sf, r'(?m)^%s\(\)$' % f)

    def test_settingsfile_included_after_settings(self):
        lines = [ln.strip() for ln in read_lines(os.path.join(AF, 'Autofarmer.ahk'))]
        at = lines.index('#Include "%A_ScriptDir%\\Settings.ahk"')
        self.assertEqual(lines[at + 1], '#Include "%A_ScriptDir%\\SettingsFile.ahk"')
        self.assertEqual(sum(1 for ln in lines if ln.startswith('#Include') and 'SettingsFile.ahk' in ln), 1)
        self.assertTrue(os.path.isfile(os.path.join(AF, 'SettingsFile.ahk')))

    # ---- the window

    def test_moved_buttons_gone(self):
        """the buttons the menus took - none made, none named in any script; no button left on the Bot tab"""
        gone = ('DashBugBtn', 'DashUpdBtn', 'DashCfgBtn', 'DashMapBtn', 'DashColBtn', 'DashPauseBtn', 'DashClearBtn',
                'DashLogBtn', 'DashWalkBtn', 'DashFolderBtn', 'DashHandsBtn', 'DashFrontBtn', 'DashViewBtn')
        for p in ahk_files():
            code = code_of(p)
            for g in gone:
                self.assertIsNone(re.search(r'\b%s\b' % g, code), '%s in %s' % (g, os.path.relpath(p, ROOT)))
        self.assertNotIn('DashRowList', self.dash)
        init = self.fn(self.dash, 'DashInit')
        bot = init[init.index('tabs.UseTab(1)'):init.index('tabs.UseTab(2)')]
        self.assertNotIn('Dash.Add("Button"', bot)

    def test_bot_button_on_the_heading_row(self):
        """the window's one button above the tabs: the bot's on / off (its words DashBotShow's and DashKeysChanged's),
        kept at the row's right end with the heading's line up to it"""
        init = self.fn(self.dash, 'DashInit')
        tab = re.search(r'Dash\.Add\("Tab3", "[^"]*\by(\d+)\b', init)
        above = re.findall(r'Dash\.Add\("Button", "([^"]*)", ([^\n]*)', init[:tab.start()])
        self.assertEqual(len(above), 1)
        opts, rest = above[0]
        self.assertRegex(opts, r'\bvDashBotBtn\b')
        y, h = int(re.search(r'\by(\d+)', opts).group(1)), int(re.search(r'\bh(\d+)', opts).group(1))
        self.assertLessEqual(y + h, int(tab.group(1)))
        self.assertIn('HkText("bot")', rest)
        self.assertIn('DashGLabel.Bind(DashBotToggle, "Normal")', rest)
        size = self.fn(self.dash, 'DashGuiSize')
        b = re.search(r'Dash\["DashBotBtn"\]\.Move\(A_GuiWidth - (\d+)\)', size)
        hd = re.search(r'Dash\["DashHead"\]\.Move\(, , A_GuiWidth - (\d+)\)', size)
        self.assertIsNotNone(b)
        self.assertIsNotNone(hd)
        w = int(re.search(r'\bw(\d+)', opts).group(1))
        hx = int(re.search(r'Dash\.Add\("Text", "x(\d+) [^"]*\bvDashHead\b', init).group(1))
        self.assertGreaterEqual(int(b.group(1)), w)                             # (inside the window)
        self.assertLessEqual(hx + int(b.group(1)) + 6, int(hd.group(1)))         # (the heading ends left of it)
        for name, state in (('DashBotShow', 'isOn'), ('DashKeysChanged', 'BotOn')):
            self.assertIn('Dash["DashBotBtn"].Text := "Bot: " (%s ? "on" : "off") " (" HkText("bot") ")"' % state,
                          self.fn(self.dash, name))
        # (the status line names the menu's item now)
        m = re.search(r'if \(GameInTray\)\s*doing := "([^"]*)"', self.fn(self.dash, 'DashRefresh'))
        self.assertIn('Bot > Show Wizard101', m.group(1))
        self.assertNotIn('tray menu', m.group(1))

    def test_sizes_without_the_bottom_row(self):
        """the tabs' inside measured with a Bot tab control, put back where it was made; the log to the window's
        bottom; the lists never under 40; the frame with the menu bar for the dashboard only (the map's 40); the simple
        view 330 high at least (a deck's value row on the Cards tab still on the window), the advanced 784 by default,
        older saves 20 less (layout 4)"""
        size = self.fn(self.dash, 'DashGuiSize')
        m = re.search(r'if \(DashTabOX = ""\)\s*\{\s*Dash\["(\w+)"\]\.Move\(0, 0\)\s*'
                      r'Dash\["\1"\]\.GetPos\(&DashTabOX, &DashTabOY, &DashTabOW, &DashTabOH\)\s*'
                      r'Dash\["\1"\]\.Move\((\d+) - DashTabOX, (\d+) - DashTabOY\)\s*\}', size)
        self.assertIsNotNone(m)
        init = self.fn(self.dash, 'DashInit')
        bot = init[init.index('tabs.UseTab(1)'):init.index('tabs.UseTab(2)')]
        made = re.search(r'Dash\.Add\("\w+", "x(\d+) y(\d+) [^"]*\bv%s\b' % m.group(1), bot)
        self.assertIsNotNone(made, m.group(1) + ' on the Bot tab')
        self.assertEqual(made.groups(), (m.group(2), m.group(3)))
        con = re.search(r'ClassRICHEDIT50W x\d+ y(\d+) ', init)
        self.assertIn('Dash["DashConsole"].Move(, , A_GuiWidth - 24, Max(40, A_GuiHeight - %d))'
                      % (int(con.group(1)) + 10), size)
        for ctl in ('DgList', 'SpList', 'DashConsole'):
            self.assertRegex(size, r'Dash\["%s"\]\.Move\([^\n]*, Max\(40, A_GuiHeight - \d+\)\)' % ctl, ctl)
        fh = self.fn(self.dash, 'DashFrameH')
        self.assertRegex(fh, r'return 40 \+ \(IsObject\(DashMenus\) \? Round\(DllCall\("GetSystemMetrics", "Int", 15, '
                             r'"Int"\) \* 96 / A_ScreenDPI\) : 0\)')
        self.assertRegex(self.dash, r'(?m)^DashFitHeight\(x, y, &h, frameH := 40\)$')
        self.assertIn('Floor((mBottom - y - 20) / dpi) - frameH)', self.fn(self.dash, 'DashFitHeight'))
        show = self.fn(self.dash, 'DashShow')
        self.assertIn('frameH := DashFrameH()', show)
        self.assertIn('DashFitHeight(x, y, &h, frameH)', show)
        self.assertIn('Floor((mBottom - mTop - 40) / dpi) - frameH)', show)
        self.assertIn('V1Round(V1Mul(V1Add(h, frameH), dpi))', show)
        self.assertNotIn('V1Add(h, 40)', show)
        self.assertIn('DashFitHeight(x, y, &h)', self.fn(self.dash, 'DashMapShow'))
        self.assertIn('Dash.Opt("+MinSize740x" (DashSimple ? 330 : 640))', self.fn(self.dash, 'DashApplyView'))
        self.assertIn('h := (h = "") ? 330 : V1Max(330, h)', show)
        # (the simple view's least height holds a deck's value row - its box, Set, Not set by this deck and the first
        # line of the note where the deck view says what it did - at the row's lowest place, DashGuiSize's floor)
        least = re.search(r'\+MinSize740x" \(DashSimple \? (\d+) : ', self.fn(self.dash, 'DashApplyView'))
        floor = re.search(r'DashDeckRowY := Max\(([\d +]+), A_GuiHeight - \d+\) - DashTabOY', size)
        self.assertIsNotNone(least)
        self.assertIsNotNone(floor)
        for ctl in ('DeckFValT', 'DeckFVal', 'DeckFValSet', 'DeckFValClear', 'DeckFNote'):
            made = re.search(r'Dash\.Add\("\w+", "x\d+ y\d+ w\d+ h(\d+) [^"]*\bv%s\b' % ctl, init)
            mv = re.search(r'Dash\["%s"\]\.Move\(, DashDeckRowY(?: \+ (\d+))?[,)]' % ctl, size)
            self.assertIsNotNone(made, ctl)
            self.assertIsNotNone(mv, ctl)
            tall = 18 if ctl == 'DeckFNote' else int(made.group(1))
            low = sum(int(t) for t in floor.group(1).split('+')) + int(mv.group(1) or 0) + tall
            self.assertLessEqual(low, int(least.group(1)), ctl + ' off the simple view at its least height')
        self.assertIn('h := (h = "") ? 784 : (V1Lt(layout, 2) ? V1Add(h, 160) : V1Lt(layout, 3) ? V1Add(h, 8) : '
                      'V1Lt(layout, 4) ? V1Sub(h, 20) : h)', show)
        self.assertIn('V1Do(IniWrite, 4, A_ScriptDir "\\dashboard.ini", "window", "layout")',
                      self.fn(self.dash, 'DashSavePlace'))

    # ---- the standing rules

    def test_nothing_by_itself_and_no_paths(self):
        """the ticks, the names and the bar's making open nothing and take no focus (only a pick - yours - opens a
        box); no menu function puts a whole path in debug.log or a box: About says the folder's name only"""
        for name in ('DashMenuMake', 'DashMenuTicks', 'DashMenuKeys', 'DashMenuName', 'DashMenuSet', 'DashMenuKey',
                     'DashMenuRun'):
            b = self.fn(self.dash, name)
            self.assertIsNone(re.search(r'(?<![\w.])(MsgBox|WinActivate|InputBox|FileSelect|Run|V1Run|TrayTip)\(|'
                                        r'\.Show\(', b), name)
        names = re.findall(r'(?m)^(DashMenu\w+)\(', self.dash)
        self.assertGreaterEqual(len(set(names)), 15)
        for name in set(names):
            b = self.fn(self.dash, name)
            paths = path_names(b)
            for m in re.finditer(r'(?<![\w.])(DebugLog|MsgBox|TrayTip|ToolTip)\(', b):
                args, _ = call_args(b, m.end())
                said = ', '.join(args or [])
                for p in paths:
                    self.assertIsNone(re.search(r'(?<![\w.])%s\b' % re.escape(p), said), '%s: %s(%s)'
                                      % (name, m.group(1), said))
        about = self.fn(self.dash, 'DashMenuAbout')
        self.assertRegex(about, r'SplitPath\(A_ScriptDir, , &(\w+)\)\s*SplitPath\(\1, &\w+\)')
        self.assertIn('BotVersion()', about)


def made_controls(code):
    """the names Dash.Add gives its controls (vX in its options): ({exact}, {prefix}) - a prefix for one made in a
    loop ("... vDeckView" A_Index)"""
    exact, prefix = set(), set()
    for m in re.finditer(r'(?<![\w.])Dash\.Add\(', masked(code)):
        args, _ = call_args(code, m.end())
        if not args or len(args) < 2:
            continue
        opts = args[1]
        for lit in re.finditer(r'"((?:[^"`\n]|`.)*)"', opts):
            more = opts[lit.end():].strip() != ''
            for v in re.finditer(r'(?:^|\s)v([A-Za-z_]\w*)(?=\s|$)', lit.group(1)):
                (prefix if v.end() == len(lit.group(1)) and more else exact).add(v.group(1))
    return exact, prefix


class ControlScan:
    """every control the scripts (codes: {file: code, comments gone}) reach on the dashboard's Gui (Dash), and the
    ones Dashboard.ahk (the file dashboard) makes"""

    def __init__(self, codes, dashboard):
        self.files = sorted(codes)
        self.code = codes
        self.mask = {p: masked(c) for p, c in codes.items()}
        self.funcs = {p: functions(c) for p, c in codes.items()}
        self.exact, self.prefix = made_controls(codes[dashboard])

    def enclosing(self, p, at):
        for f in self.funcs[p]:
            if f[2] <= at < f[3]:
                return f
        return None

    def loop_source(self, p, at, var, f):
        """the names a 'for ..., var in <source>' before at hands over: the strings of its list, of the function it
        calls, or of what the variable it names is set to (:=, .Push, .InsertAt) - None when there's no such loop"""
        code, mask = self.code[p], self.mask[p]
        lo = f[2] if f else 0
        loops = [m for m in re.finditer(r'(?m)^[ \t]*for\s+(\w+)(?:\s*,\s*(\w+))?\s+in\s+', mask[lo:at])
                 if (m.group(2) or m.group(1)) == var]
        if not loops:
            return None
        s = lo + loops[-1].end()
        lines = code[s:].split('\n')
        src = lines[0]
        for ln in lines[1:]:            # (continuation lines: ", ..." and the like)
            if ln.strip() and ln.lstrip()[0] in ',.+?:':
                src += ln
            else:
                break
        found = strings_in(src)
        if found:
            return found
        call = re.fullmatch(r'\s*(\w+)\(\)\s*', src)
        if call:
            for q, fs in self.funcs.items():
                for g in fs:
                    if g[0] == call.group(1):
                        return strings_in(self.code[q][g[2]:g[3]]) or None
            return None
        name = re.fullmatch(r'\s*(\w+)\s*', src)
        if name:
            got = []
            for ln in (code[f[2]:f[3]] if f else code).split('\n'):
                if re.search(r'\b%s\s*:=|\b%s\.(?:Push|InsertAt)\(' % (name.group(1), name.group(1)), ln):
                    got += strings_in(ln)
            return got or None
        return None

    def resolve(self, p, at, expr, depth=0):
        """the names an expression in a Dash[...] (or a helper's argument) at p:at stands for - [(name, is_prefix,
        how)], how: literal, loop or param - or None when that can't be told"""
        expr = expr.strip()
        m = re.fullmatch(r'"((?:[^"`\n]|`.)*)"', expr)
        if m:
            return [(m.group(1), False, 'literal')]
        m = re.match(r'"((?:[^"`\n]|`.)*)"\s+\S', expr)
        if m:
            return [(m.group(1), True, 'literal')]
        m = re.fullmatch(r'(\w+)(\[.*\])?', expr)
        if not m or depth > 3:
            return None
        var, f = m.group(1), self.enclosing(p, at)
        if f and var in f[1] and not m.group(2):
            # (a parameter: what each call hands it)
            k, out = f[1].index(var), []
            for q in self.files:
                for c in re.finditer(r'(?<![\w.])%s\(' % re.escape(f[0]), self.mask[q]):
                    args, close = call_args(self.code[q], c.end())
                    if args is None or re.match(r'[ \t]*(\{|\n\t\{)', self.code[q][close + 1:]):
                        continue     # (its own definition)
                    got = self.resolve(q, c.start(), args[k], depth + 1) if len(args) > k else None
                    if got is None:
                        return None
                    out += [(n, pre, 'param') for n, pre, _ in got]
            return out
        names = self.loop_source(p, at, var, f)
        return None if names is None else [(n, False, 'loop') for n in names]

    def is_made(self, name, is_prefix):
        if is_prefix:
            return any(e.startswith(name) for e in self.exact) or \
                any(q.startswith(name) or (name.startswith(q) and name[len(q):].isdigit()) for q in self.prefix)
        return name in self.exact or any(name.startswith(q) and name[len(q):].isdigit() for q in self.prefix)

    def refs(self):
        """[(file, line, how, name, is_prefix)] of every control reached on Dash, and [(file, line, what)] of the ones
        that can't be told (Dash.X: no Gui member - a control is Dash["X"])"""
        out, unknown = [], []
        for p in self.files:
            code, mask = self.code[p], self.mask[p]
            rel = os.path.relpath(p, ROOT) if os.path.isabs(p) else p
            for m in re.finditer(r'(?<![\w.])Dash\[', mask):
                args, _ = call_args(code, m.end())
                line = code.count('\n', 0, m.start()) + 1
                got = self.resolve(p, m.start(), args[0]) if args and len(args) == 1 else None
                if got is None:
                    unknown.append((rel, line, 'Dash[%s]' % ', '.join(args or [])))
                else:
                    out += [(rel, line, how, n, pre) for n, pre, how in got]
            for m in re.finditer(r'(?<![\w.])Dash\.(\w+)', mask):
                if m.group(1).lower() not in GUI_MEMBERS:
                    unknown.append((rel, code.count('\n', 0, m.start()) + 1, 'Dash.%s' % m.group(1)))
        return out, unknown

    def problems(self):
        """(the references that can't be told, the ones to a control not made) - as lines to show"""
        refs, unknown = self.refs()
        bad = [(f, ln, how, n, pre) for f, ln, how, n, pre in refs if not self.is_made(n, pre)]
        return unknown, bad


class ControlNames(unittest.TestCase):
    """every control a script reaches on the dashboard (Dash) is one Dashboard.ahk makes"""

    @classmethod
    def setUpClass(cls):
        dash = os.path.normpath(os.path.join(AF, 'Dashboard.ahk'))
        cls.scan = ControlScan({p: code_of(p) for p in ahk_files()}, dash)

    def test_every_control_reached_is_made(self):
        unknown, bad = self.scan.problems()
        self.assertEqual(unknown, [], 'not told which control:\n' + '\n'.join('%s:%d %s' % u for u in unknown))
        self.assertEqual(bad, [], 'no such control:\n' + '\n'.join(
            '%s:%d Dash["%s"%s] (%s) - Dashboard.ahk makes no v%s' % (f, ln, n, ' ...' if pre else '', how, n)
            for f, ln, how, n, pre in bad))

    def test_the_check_sees_them(self):
        """the check itself, on the scripts: it finds the controls made (in a loop too) and reached - plainly, in a
        list a loop hands to Dash[c] (a list, a function's, a V1Obj's values), through a helper's parameter"""
        scan = self.scan
        self.assertGreater(len(scan.exact), 80)
        for name in ('DashBotBtn', 'DashHead', 'DashLogHead', 'DashConsole', 'DashTabs', 'DeckView0', 'KeyList'):
            self.assertIn(name, scan.exact)
        self.assertEqual(scan.prefix, {'DeckView', 'DashCardPic', 'DashCardTxt'})
        refs, _ = scan.refs()
        got = {(n, how) for f, ln, how, n, pre in refs}
        self.assertGreater(sum(1 for r in refs if r[2] == 'literal'), 100)
        self.assertIn(('DashConsole', 'loop'), got)         # (DashApplyView's list)
        self.assertIn(('DashLearnBtn', 'loop'), got)        # (Decks.ahk DeckHandCtrls - a function's list)
        self.assertIn(('DeckFWBoss', 'loop'), got)          # (a V1Obj's values)
        self.assertIn(('NetStatus', 'param'), got)          # (DashSet's callers)
        self.assertIn(('DashHead', 'param'), got)
        self.assertIn(('KeyStatus', 'literal'), got)        # (Hotkeys.ahk)
        self.assertIn(('DashStatText', 'literal'), got)     # (BugReport.ahk)
        self.assertTrue(any(n == 'DashCardPic' and pre for f, ln, how, n, pre in refs))

    def test_the_check_catches_them(self):
        """the check itself, on a made-up script: a button that's gone reached each way - plainly, by a name's start,
        in a list a loop hands over (a list, a variable's, a function's), through a helper's parameter - and Dash.X and
        a Dash[x] it can't tell; the ones made (in a loop too) pass"""
        dash = '\n'.join([
            'DashInit()', '\t{',
            '\tDash.Add("Button", "x12 y7 w136 h24 vDashBotBtn", "Bot")',
            '\tLoop 3', '\t\tDash.Add("Text", "x" A_Index " y7 Hidden vDashCardPic" A_Index)',
            '\t}', '',
            'DashSet(control, text)', '\t{', '\tDash[control].Text := text', '\t}', '',
            'Ctrls()', '\t{', '\treturn ["DashBotBtn", "DashFolderBtn"]', '\t}', '',
            'Size(thisGui:="", MinMax:="") {',
            '\tDash["DashBotBtn"].Move(1)',
            '\tDash["DashCardPic" 2].Visible := 1',
            '\tDash["DashUpdBtn"].Move(2)',
            '\tDash["DashCfgBtn" n].Move(2)',
            '\tDash["DashCardPics" n].Move(2)',
            '\trow := [["DashBotBtn", 100], ["DashWalkBtn", 140]]',
            '\trow.InsertAt(1, ["DashPauseBtn", 100])',
            '\tfor i, b in row', '\t\tDash[b[1]].Move(3)',
            '\tfor each, c in ["DashLogHead", "DashCardPic3"', '\t\t, "DashColBtn"]', '\t\tDash[c].Visible := 1',
            '\tfor i, c in Ctrls()', '\t\t{', '\t\tDash[c].Visible := 0', '\t\t}',
            '\tDashSet("DashBotBtn", "x")', '\tDashSet("DashMapBtn", "y")',
            '\tDash.DashViewBtn.Text := ""', '\tDash.Opt("+OwnDialogs"), Dash.MenuBar := ""',
            '\tDash[zz].Text := ""',
            '}'])
        scan = ControlScan({'Dashboard.ahk': dash}, 'Dashboard.ahk')
        self.assertEqual((scan.exact, scan.prefix), ({'DashBotBtn'}, {'DashCardPic'}))
        unknown, bad = scan.problems()
        self.assertEqual(sorted((n, how, pre) for f, ln, how, n, pre in bad),
                         [('DashCardPics', 'literal', True), ('DashCfgBtn', 'literal', True),
                          ('DashColBtn', 'loop', False), ('DashFolderBtn', 'loop', False),
                          ('DashLogHead', 'loop', False), ('DashMapBtn', 'param', False),
                          ('DashPauseBtn', 'loop', False), ('DashUpdBtn', 'literal', False),
                          ('DashWalkBtn', 'loop', False)])
        self.assertEqual([u[2] for u in unknown], ['Dash[zz]', 'Dash.DashViewBtn'])


if __name__ == '__main__':
    unittest.main()
