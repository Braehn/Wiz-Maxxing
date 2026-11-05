"""test_settingsfile.py - v1.10.0's settings files (AutoFarmer\\SettingsFile.ahk: the dashboard's File > Save settings
as... and Load settings from...) and the one way every setting is set now (Settings.ahk CfgApply), the AutoHotkey side
read (not run). Standard library only:  python3 -m unittest test_settingsfile  (from AutoFarmer\\vision)

Pins CfgApply's contract (only what differs from Stats written, the mobs' floors with it, every hook through V1IsFunc -
GameFrontShow and DashMenuTicks too -, an open Settings window shown the new values, true / false), the Settings
window's Save as CfgCollect + CfgApply(..., "Settings"), Save as (its dialog, .txt and the overwrite question, the
bot's own files refused, the first line, no network PIN, the floors, ASCII / CRLF / no BOM through a .tmp moved over
once more after 200 ms, a file's name only in debug.log) and Load (256 KB at most, read as UTF-8 with a BOM taken off,
ParseStat's pattern without ParseStat, the Settings window's ranges, netpin / floors / CharIDs never taken, a file
with no setting stopped, the party's two unticked, not with the Settings window open, PlayerStats.txt copied to
backups\\ first, Critical round the re-check and CfgApply and never over a box, the working folder put back). Save's
lines are also made from the code's own strings and read with a port of LoadStats' ParseStat: every one it can write
is a comment or a line LoadStats reads, its value as it was."""
import math
import os
import re
import unittest

from test_ahk_names import BUILTINS, code_lines, functions, hidden_calls

HERE = os.path.dirname(os.path.abspath(__file__))
AF = os.path.dirname(HERE)              # the AutoFarmer folder
ROOT = os.path.dirname(AF)              # the repository

# what FormatTime gives for each format the files use (an unknown one comes back as itself - no date: the test fails)
TIMES = {'yyyy-MM-dd': '2026-11-05', 'yyyy-MM-dd HH:mm': '2026-11-05 14:07', 'yyyy-MM-dd HHmmss': '2026-11-05 140709'}
DOCS = 'C:\\Users\\someone\\Documents'
ESC = {'n': '\n', 'r': '\r', 't': '\t', '"': '"', "'": "'", '`': '`', ';': ';', 's': ' ', 'b': '\b'}
DIALOGS = re.compile(r'(?<![\w.])(?:MsgBox|InputBox|FileSelect|DirSelect)\(|\.Show\(')
# the dashboard's buttons v1.10.0's menu bar took (each is a menu item now - the window has no such button)
GONE_BUTTONS = ('Report a bug', 'Check for updates', 'Updates', 'Settings', 'Map', 'Colours', 'Pause log', 'Clear',
                'Open debug.log', 'Walking', 'Open bot folder', 'Wait for me', 'Game to front', 'Advanced view',
                'Simple view')


def read_lines(path):
    with open(path, encoding='utf-8-sig', errors='replace') as f:
        return f.read().splitlines()


def ahk_semi(line):
    """where a line's AutoHotkey comment starts (its first ' ;' / '\\t;' - even inside a string), else len(line), and
    whether that's inside a double-quoted string. A backtick skips the next character"""
    inq, i = False, 0
    while i < len(line):
        c = line[i]
        if c == '"':
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


def closing(text, i):
    """where the ) is that closes the ( at text[i] - strings and brackets inside skipped"""
    depth, inq, j = 0, False, i
    while j < len(text):
        c = text[j]
        if inq:
            if c == '`':
                j += 2
                continue
            if c == '"':
                inq = False
        elif c == '"':
            inq = True
        elif c in '([':
            depth += 1
        elif c in ')]':
            depth -= 1
            if depth == 0:
                return j
        j += 1
    raise ValueError('no ) for ' + text[i:i + 60])


def split_args(text):
    """a call's arguments (their text) - split at the commas outside strings and brackets"""
    out, depth, inq, cur, i = [], 0, False, '', 0
    while i < len(text):
        c = text[i]
        if inq:
            cur += c
            if c == '`' and i + 1 < len(text):
                cur += text[i + 1]
                i += 2
                continue
            if c == '"':
                inq = False
        elif c == '"':
            inq, cur = True, cur + c
        elif c in '([{':
            depth, cur = depth + 1, cur + c
        elif c in ')]}':
            depth, cur = depth - 1, cur + c
        elif c == ',' and depth == 0:
            out.append(cur.strip())
            cur = ''
        else:
            cur += c
        i += 1
    out.append(cur.strip())
    return out


def call_args(code, name):
    """[argument texts] of each call of name in code (not a method of that name, not the function's own first line)"""
    out = []
    for m in re.finditer(r'(?<![\w.])%s\(' % re.escape(name), code):
        if m.start() == 0 or code[m.start() - 1] == '\n':
            continue    # (the function's own first line)
        j = closing(code, m.end() - 1)
        out.append(split_args(code[m.end():j]))
    return out


def ahk_text(expr, names=None, calls=None):
    """the text an AutoHotkey v2 concatenation makes: "strings" (their `r `n ... escapes), names (names: name -> text)
    and calls (calls: name -> fn(its argument texts)) side by side or joined by ' . '. Anything else - an operator,
    a number, a name or call not given - raises ValueError: a changed line can't pass for the old one"""
    names, calls, out, i = names or {}, calls or {}, [], 0
    while i < len(expr):
        c = expr[i]
        if c in ' \t\r\n':
            i += 1
        elif c == '.' and (i + 1 == len(expr) or expr[i + 1] in ' \t'):
            i += 1
        elif c == '"':
            j, s = i + 1, ''
            while expr[j] != '"':
                if expr[j] == '`':
                    s += ESC[expr[j + 1]]
                    j += 2
                else:
                    s += expr[j]
                    j += 1
            out.append(s)
            i = j + 1
        else:
            m = re.match(r'[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*', expr[i:])
            if not m:
                raise ValueError('not text: ' + expr[i:])
            name, i = m.group(0), i + m.end()
            if i < len(expr) and expr[i] == '(':
                j = closing(expr, i)
                if name not in calls:
                    raise ValueError('a call it has no text for: ' + name)
                out.append(calls[name](split_args(expr[i + 1:j])))
                i = j + 1
            else:
                if name not in names:
                    raise ValueError('a name it has no text for: ' + name)
                out.append(names[name])
    return ''.join(out)


def format_time(args):
    if args[0] != '' or len(args) != 2:
        raise ValueError('FormatTime(%s): not today in a format' % ', '.join(args))
    fmt = ahk_text(args[1])
    return TIMES.get(fmt, fmt)


def ahk_re(pattern):
    """an AutoHotkey (PCRE) pattern as Python's - its "i)"-style options taken off the front, ASCII \\w \\s \\d"""
    flags = re.ASCII
    m = re.match(r'^([imsx]+)\)', pattern)
    if m:
        for o in m.group(1):
            flags |= {'i': re.I, 'm': re.M, 's': re.S, 'x': re.X}[o]
        pattern = pattern[m.end():]
    return re.compile(pattern, flags)


def ahk_num(text):
    """what ParseStat's m[2] + 0 makes of a value: a whole number, else a float"""
    return int(text) if re.fullmatch(r'-?\d+', text) else float(text)


def cfg_file_num(v):
    """a port of SettingsFile.ahk CfgFileNum: a whole number as it is, another with up to 6 decimals, '' for text"""
    if not isinstance(v, (int, float)) or isinstance(v, bool):
        return ''
    if isinstance(v, int):
        return str(v)
    t = ('%.6f' % v).rstrip('0').rstrip('.')
    return '0' if t == '-0' else t


def cfg_list(lines):
    """Settings.ahk CfgList's entries in order: {key, label, kind, def, lo, hi, picks} (a heading: key '-', "|" a
    column break - no def)"""
    entries, cur = [], None
    for ln in lines:
        s = ln.strip()
        if s.startswith('list.Push(V1Obj({key:'):
            cur = [s]
            entries.append(cur)
        elif cur is not None and s.startswith(','):
            cur.append(s)
        else:
            cur = None
    out = []
    for parts in entries:
        t = re.sub(r', help: "(?:[^"`]|`.)*"', '', ' '.join(parts))
        e = {'key': re.search(r'key: "([^"]*)"', t).group(1)}
        m = re.search(r'label: "((?:[^"`]|`.)*)"', t)
        if m:
            e['label'] = ahk_text('"%s"' % m.group(1))
        for f in ('kind',):
            m = re.search(r'\b%s: "(\w+)"' % f, t)
            if m:
                e[f] = m.group(1)
        for f in ('def', 'lo', 'hi'):
            m = re.search(r'\b%s: (-?\d+)\b' % f, t)
            if m:
                e[f] = int(m.group(1))
        m = re.search(r'picks: \[(.*?)\]', t)
        if m:
            e['picks'] = re.findall(r'"((?:[^"`]|`.)*)"', m.group(1))
        out.append(e)
    return out


def critical_dialogs(code):
    """[line] - each box or window shown (MsgBox, InputBox, FileSelect, DirSelect, .Show) while code, read top to
    bottom, has Critical on"""
    on, hits = False, []
    for ln in code.split('\n'):
        if re.search(r'(?<![\w.])Critical\((?:|true|1|"On")\)', ln):
            on = True
        if re.search(r'(?<![\w.])Critical\((?:"Off"|false|0)\)', ln):
            on = False
        if on and DIALOGS.search(ln):
            hits.append(ln.strip())
    return hits


def ahk_walk():
    """every .ahk file in the repository (a new one not committed yet too)"""
    files = []
    for d, ds, fs in os.walk(ROOT):
        ds[:] = [x for x in ds if not x.startswith('.')]
        files += [os.path.join(d, f) for f in fs if f.lower().endswith('.ahk')]
    return sorted(files)


class SettingsFileWiring(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cfg_lines = read_lines(os.path.join(AF, 'Settings.ahk'))
        cls.cfg = '\n'.join(ahk_code(cls.cfg_lines))
        cls.sf_path = os.path.join(AF, 'SettingsFile.ahk')
        cls.sf_lines = read_lines(cls.sf_path)
        cls.sf = '\n'.join(ahk_code(cls.sf_lines))
        cls.kc = code_of(os.path.join(AF, 'KillCalc.ahk'))
        cls.entries = cfg_list(cls.cfg_lines)
        with open(os.path.join(ROOT, 'version.txt'), encoding='ascii') as f:
            cls.version = f.read().strip()
        ps = body(cls.kc, 'ParseStat')
        cls.ps_strip = re.search(r'line := RegExReplace\(line, "([^"]*)"\)', ps).group(1)
        cls.ps_pat = re.search(r'RegExMatch\(line, "([^"]*)", &m\)', ps).group(1)

    def fn(self, code, name):
        b = body(code, name)
        self.assertIsNotNone(b, name + ' not found')
        return b

    def order(self, code, *parts):
        """each part found in code, in this order (each after the one before)"""
        at = -1
        for p in parts:
            i = code.find(p, at + 1)
            self.assertGreater(i, at, '%r not after the one before it' % p)
            at = i

    def parse_stat(self, line, stats):
        """a port of KillCalc.ahk ParseStat (its own two patterns): True if the line is read (a key:value set in
        stats) or has nothing in it"""
        line = ahk_re(self.ps_strip).sub('', line, count=1)
        m = ahk_re(self.ps_pat).search(line)
        if m:
            stats[m.group(1).lower()] = ahk_num(m.group(2))
            return True
        return line.strip(' \t') == ''

    def load_stats(self):
        """Stats as LoadStats leaves them with the shipped PlayerStats.txt: its built-in defaults, CfgList's, the
        file's lines"""
        ls = self.fn(self.kc, 'LoadStats')
        stats = {}
        for part in ''.join(re.findall(r'"([^"]*)"', ls[:ls.index('Stats := V1Obj()')])).split(','):
            self.assertTrue(self.parse_stat(part, stats), part)
        for e in self.entries:
            if 'def' in e and e['key'] not in stats:
                stats[e['key']] = e['def']
        with open(os.path.join(AF, 'PlayerStats.txt'), encoding='utf-8') as f:
            for ln in f.read().splitlines():
                self.parse_stat(ln, stats)
        return stats

    def save_text(self, entries, stats):
        """what CfgFileText writes for these CfgList entries and Stats - each line made from the code's own strings
        (its first lines, the heading's line, the setting's line), the loop as the code has it (pinned below)"""
        code = self.fn(self.sf, 'CfgFileText')
        lines = code.split('\n')
        at = [i for i, ln in enumerate(lines) if ':= "; Wiz-Maxxing settings file' in ln]
        self.assertEqual(len(at), 1)
        head = [lines[at[0]].split(':=', 1)[1]]
        for ln in lines[at[0] + 1:]:
            if not ln.lstrip().startswith('.'):
                break
            head.append(ln)
        adds = re.findall(r'(?m)^\t+cftOut \.= (.*)$', code)
        self.assertEqual(len(adds), 2, 'the heading\'s line and the setting\'s line')
        ascii_m = re.fullmatch(r'\s*return RegExReplace\(text, "([^"]*)", "([^"]*)"\)\s*',
                               self.fn(self.sf, 'CfgFileAscii'))
        self.assertIsNotNone(ascii_m)
        names = {}

        def ascii_of(args):
            return ahk_re(ascii_m.group(1)).sub(ascii_m.group(2), ahk_text(args[0], names, calls))

        calls = {'Chr': lambda a: chr(int(a[0], 0)), 'FormatTime': format_time,
                 'CfgFileVersion': lambda a: self.version, 'CfgFileAscii': ascii_of}
        out = ahk_text('\n'.join(head), names, calls)
        for e in entries:
            if e['key'] == '-':
                names.clear()
                names['cftS.label'] = e['label']
                out += ahk_text(adds[0], names, calls)
                continue
            if 'def' not in e or e['key'] == 'netpin':
                continue
            v = stats.get(e['key'], e['def'])
            floor = stats.get(e['key'] + 'floor')
            if e['key'] in ('mobradius', 'mobbody') and isinstance(floor, (int, float)):
                v = floor
            t = cfg_file_num(v)
            if t == '':
                continue
            names.clear()
            names.update({'cftS.key': e['key'], 'cftS.label': e['label'], 'cftT': t})
            out += ahk_text(adds[1], names, calls)
        return out

    def check_saved(self, text, entries, stats):
        """every line of a saved file: ASCII, CRLF, a comment or a key:value line ParseStat reads - every setting
        once (not netpin), its value as Stats has it (the floor for the mobs' reach)"""
        self.assertTrue(text.endswith('\r\n'))
        text.encode('ascii')
        self.assertFalse(text.startswith('\ufeff'))
        lines = text.split('\r\n')[:-1]
        got = {}
        for ln in lines:
            self.assertNotIn('\r', ln)
            self.assertNotIn('\n', ln)
            one = {}
            self.assertTrue(self.parse_stat(ln, one), 'LoadStats can\'t read: %r' % ln)
            if one:
                (k, v), = one.items()
                self.assertNotIn(k, got, 'twice: ' + k)
                got[k] = v
            else:
                self.assertTrue(ln == '' or ln.startswith(';'), ln)
        want = {}
        for e in entries:
            if 'def' in e and e['key'] != 'netpin':
                v = stats.get(e['key'], e['def'])
                floor = stats.get(e['key'] + 'floor')
                if e['key'] in ('mobradius', 'mobbody') and isinstance(floor, (int, float)):
                    v = floor
                if isinstance(v, (int, float)):
                    want[e['key']] = v
        self.assertEqual(sorted(got), sorted(want))
        for k, v in want.items():
            self.assertTrue(math.isclose(got[k], v, rel_tol=1e-6, abs_tol=1e-6), '%s: %r saved as %r' % (k, v, got[k]))
        return lines, got

    # ---- the files themselves

    def test_files(self):
        """SettingsFile.ahk: CRLF, plain ASCII, no BOM, no ' ;' in a string, #Included right after Settings.ahk"""
        for path in (self.sf_path, os.path.join(AF, 'Settings.ahk')):
            with open(path, 'rb') as f:
                raw = f.read()
            self.assertFalse(raw.startswith(b'\xef\xbb\xbf'), path)
            self.assertNotIn(b'\n', raw.replace(b'\r\n', b''), path)
            self.assertNotIn(b'\r', raw.replace(b'\r\n', b''), path)
            raw.decode('ascii')
        self.assertEqual(semicolon_hits(self.sf_lines), [])
        self.assertEqual(semicolon_hits(self.cfg_lines), [])
        with open(os.path.join(AF, 'Autofarmer.ahk'), 'rb') as f:
            af = f.read()
        self.assertIn(b'#Include "%A_ScriptDir%\\Settings.ahk"\r\n#Include "%A_ScriptDir%\\SettingsFile.ahk"\r\n', af)
        self.assertEqual(af.count(b'SettingsFile.ahk"'), 1)

    def test_contract_names(self):
        """CfgSaveAs() and CfgLoadFrom() take nothing; CfgApply(pairs, source) - a note after it may be left out"""
        self.assertRegex(self.sf, r'(?m)^CfgSaveAs\(\)$')
        self.assertRegex(self.sf, r'(?m)^CfgLoadFrom\(\)$')
        self.assertRegex(self.cfg, r'(?m)^CfgApply\(pairs, source(?:, \w+ := "")?\)$')
        self.assertRegex(self.cfg, r'(?m)^CfgCollect\(&fixed\)$')

    def test_names(self):
        """no local named like a function it calls (test_ahk_names - for a file not committed yet too)"""
        texts = {}
        for p in ahk_walk():
            with open(p, encoding='utf-8-sig', errors='replace') as f:
                texts[p] = f.read()
        known = set(BUILTINS)
        for t in texts.values():
            known |= {f[0].lower() for f in functions(t)}
        for p in (self.sf_path, os.path.join(AF, 'Settings.ahk')):
            self.assertIn(p, texts)
            self.assertEqual(hidden_calls(texts[p], known), [], p)
        self.assertGreaterEqual(len(functions(texts[self.sf_path])), 15)

    def test_other_files_through_v1isfunc(self):
        """SettingsFile.ahk calls no other file's function by name - each through V1IsFunc("X") and X.Call (V1Compat's
        and AutoHotkey's own aside), and every X.Call has its V1IsFunc("X")"""
        own, other = set(), set()
        for p in ahk_walk():
            with open(p, encoding='utf-8-sig', errors='replace') as f:
                names = {fn[0].lower() for fn in functions(f.read())}
            if p == self.sf_path or os.path.basename(p) == 'V1Compat.ahk':
                own |= names
            else:
                other |= names
        other -= own | BUILTINS
        with open(self.sf_path, encoding='utf-8-sig') as f:
            raw = f.read()
        code = '\n'.join(code_lines(raw))
        direct = sorted({n for n in re.findall(r'(?<![\w.%])([A-Za-z_]\w*)\(', code) if n.lower() in other})
        self.assertEqual(direct, [])
        for n in set(re.findall(r'(?<![\w.])([A-Za-z_]\w*)\.Call\(', self.sf)):
            self.assertIn('V1IsFunc("%s")' % n, self.sf, n)
        for n in ('CfgList', 'CfgApply', 'CfgIsOpen', 'DebugLog', 'BotVersion'):
            self.assertIn('V1IsFunc("%s")' % n, self.sf, n)

    def test_nothing_reaches_into_the_game(self):
        """the menu's own boxes only: no key, click or focus taken, nothing sent to a window"""
        code = '\n'.join(code_lines('\n'.join(self.sf_lines)))
        for bad in ('WinActivate', 'Send', 'SendInput', 'SendEvent', 'SendText', 'Click', 'MouseMove', 'ControlSend',
                    'ControlClick', 'PostMessage', 'SendMessage', 'WriteProcessMemory', 'CreateRemoteThread', 'Run',
                    'RunWait', 'WinClose', 'WinKill', 'ProcessClose'):
            self.assertIsNone(re.search(r'(?<![\w.])%s\b' % bad, code), bad)

    # ---- CfgApply: the one way a setting is set

    def test_apply_writes_only_what_differs(self):
        """in CfgList's order, a setting of pairs (a Map) written only when it isn't so in Stats already"""
        ap = self.fn(self.cfg, 'CfgApply')
        self.assertRegex(ap, r'if !\(pairs is Map\)\s*return CfgUncritical\(capWas, false\)')
        self.assertIn('for each, capS in CfgList()', ap)
        self.assertIn('if (!capS.Has("def") || !pairs.Has(capS.key) || !V1IsNum(pairs[capS.key]))', ap)
        self.assertRegex(ap, r'capV := pairs\[capS\.key\] \+ 0\s*'
                             r'capOld := Stats\.Has\(capS\.key\) \? Stats\[capS\.key\] : capS\.def\s*'
                             r'if \(V1IsNum\(capOld\) && capOld \+ 0 = capV\)\s*\{[^{}]*\bcontinue\s*\}\s*'
                             r'capList\.Push\(\[capS\.key, capV\]\), capSaid \.= ", " capS\.key '
                             r'\(capS\.key = "netpin" \? " changed" : " " capOld " -> " capV\)')
        self.assertNotIn('CfgShownVals[capS.key]', ap)
        self.assertRegex(ap, r'if \(!capList\.Length && !capFloor\.Length\)\s*return CfgUncritical\(capWas, true\)')
        self.order(ap, 'if (!capList.Length && !capFloor.Length)', 'CfgWrite(')
        # (V1Obj - what CfgCollect hands over - is a Map)
        with open(os.path.join(ROOT, 'V1Compat.ahk'), encoding='utf-8-sig') as f:
            self.assertIn('class V1Obj extends Map', f.read())

    def test_apply_floors(self):
        """the mobs' reach set: its floor too (Vision.ahk MobShrinkTick comes back down to it) - written with it"""
        ap = self.fn(self.cfg, 'CfgApply')
        m = re.search(r'(\w+) := capList\.Clone\(\)\s*for each, (\w+) in capFloor\s*\1\.Push\(\2\)\s*'
                      r'for each, \2 in capList\s*'
                      r'if \(\2\[1\] = "mobradius" \|\| \2\[1\] = "mobbody"\)\s*'
                      r'\1\.Push\(\[\2\[1\] "floor", \2\[2\]\]\)\s*if \(!CfgWrite\(\1\)\)', ap)
        self.assertIsNotNone(m)
        # (the reach set to what the bot widened it to meanwhile - so the same as Stats, not written again: its floor
        # still set to it, unless it's that already - the Settings window's Save before CfgApply wrote both)
        self.assertRegex(ap, r'if \(V1IsNum\(capOld\) && capOld \+ 0 = capV\)\s*\{\s*'
                             r'if \(\(capS\.key = "mobradius" \|\| capS\.key = "mobbody"\) && '
                             r'!\(Stats\.Has\(capS\.key "floor"\) && V1IsNum\(Stats\[capS\.key "floor"\]\) && '
                             r'Stats\[capS\.key "floor"\] \+ 0 = capV\)\)\s*'
                             r'capFloor\.Push\(\[capS\.key "floor", capV\]\), capSaid \.= [^\n]+\s*continue\s*\}')
        self.assertEqual(ap.count('CfgWrite('), 1)
        shrink = self.fn(code_of(os.path.join(AF, 'Vision.ahk')), 'MobShrinkTick')
        self.assertIn('Stat("mobradiusfloor")', shrink)
        self.assertIn('Stat("mobbodyfloor")', shrink)

    def test_apply_hooks(self):
        """after the write, each hook through V1IsFunc (never by name): the tray ticks and the dashboard's menu bar's
        (HandsOffShow, GameFrontShow), battles only, the battle recorder, the speedhack switched on, the tray
        settings, the menu bar's ticks; none if the write failed"""
        ap = self.fn(self.cfg, 'CfgApply')
        wrote = ap.index('if (!CfgWrite(')
        self.assertRegex(ap, r'if \(!CfgWrite\(\w+\)\)\s*\{\s*DebugLog\(source ": [^\n]*\)\s*'
                             r'return CfgUncritical\(capWas, false\)\s*\}')
        for name, args in (('HandsOffShow', ''), ('GameFrontShow', ''), ('BattlesOnlyTick', ''),
                           ('BrecHello', '"later"'), ('TrayWinTick', ''), ('DashMenuTicks', '')):
            m = re.search(r'if \(V1IsFunc\("%s"\)\)\s*%s\.Call\(%s\)' % (name, name, re.escape(args)), ap)
            self.assertIsNotNone(m, name)
            self.assertGreater(m.start(), wrote, name)
            self.assertNotRegex(ap, r'(?<![\w.])%s\(' % name)
        m = re.search(r'for each, (\w+) in capList\s*if \(\1\[1\] = "speedhack" && \1\[2\] = 1 && '
                      r'V1IsFunc\("SpeedCheatEngine"\)\)\s*SpeedCheatEngine\.Call\(', ap)
        self.assertIsNotNone(m)
        self.assertGreater(m.start(), wrote)
        self.assertNotRegex(ap, r'(?<![\w.])SpeedCheatEngine\(')
        # (the last thing: true)
        self.assertRegex(ap, r'DashMenuTicks\.Call\(\)\s*return CfgUncritical\(capWas, true\)\s*$')

    def test_apply_log_and_result(self):
        """one debug.log line - source ": key old -> new, ..."; Critical as it goes (a caller's own kept); every
        way out true or false through CfgUncritical"""
        ap = self.fn(self.cfg, 'CfgApply')
        self.assertRegex(ap, r'^\s*capWas := A_IsCritical\s*Critical\(\)')
        rets = re.findall(r'(?<![\w.])return\b([^\n]*)', ap)
        self.assertGreaterEqual(len(rets), 4)
        for r in rets:
            self.assertRegex(r, r'^ CfgUncritical\(capWas, (true|false)\)$')
        self.assertEqual(sorted(set(rets)), [' CfgUncritical(capWas, false)', ' CfgUncritical(capWas, true)'])
        self.assertRegex(self.fn(self.cfg, 'CfgUncritical'), r'if \(!wasOn\)\s*Critical\("Off"\)\s*return result')
        self.assertIn('DebugLog(source ": " SubStr(capSaid, 3)', ap)
        self.assertEqual(ap.count('DebugLog('), 2)
        self.order(ap, 'if (!CfgWrite(', 'DebugLog(source ": " SubStr(capSaid, 3)', 'V1IsFunc("HandsOffShow")')
        self.assertEqual(critical_dialogs('Critical()\n' + ap), [])

    def test_the_pin_never_in_the_log(self):
        """the network PIN: CfgApply's line says it changed, never its numbers (debug.log's end goes into a public
        bug report); Report a bug blanks one in an older line ("netpin 0 -> 1234", the Save's before v1.10.0) or
        a netpin:1234 line, and nothing else"""
        ap = self.fn(self.cfg, 'CfgApply')
        said = re.findall(r'capSaid \.= ([^\n]*)', ap)
        self.assertEqual(len(said), 2)
        self.assertIn('(capS.key = "netpin" ? " changed" : " " capOld " -> " capV)', said[1])
        # (the floor branch's: only mobradius / mobbody reach it)
        self.assertRegex(ap, r'if \(\(capS\.key = "mobradius" \|\| capS\.key = "mobbody"\) && [^\n]*\s*capFloor\.Push')
        red = self.fn(code_of(os.path.join(AF, 'BugReport.ahk')), 'BugRedact')
        m = re.search(r's := RegExReplace\(s, "i\)(\\bnetpin[^"]*)", "netpin \[left out\]"\)', red)
        self.assertIsNotNone(m)
        pin = re.compile(m.group(1), re.I)
        for line, want in (('Settings saved (used from now on): netpin 0 -> 1234, healat 30 -> 40',
                            'Settings saved (used from now on): netpin [left out], healat 30 -> 40'),
                           ('netpin:4821   ; the PIN', 'netpin [left out]   ; the PIN'),
                           ('Settings: NetPin 12 -> -3', 'Settings: netpin [left out]'),
                           ('Settings: netpin changed', 'Settings: netpin changed'),
                           ('netpinned 5 -> 6', 'netpinned 5 -> 6')):
            self.assertEqual(pin.sub('netpin [left out]', line), want)
        self.order(red, 'Bearer [left out]', 'netpin [left out]', 'return RegExReplace(')

    def test_write_tries_twice(self):
        """PlayerStats.txt replaced by its .tmp - once more after 200 ms if that fails (Cheat Engine's script
        reading it just then); still not: the .tmp gone, false"""
        cw = self.fn(self.cfg, 'CfgWrite')
        self.assertRegex(cw, r'V1Do\(FileMove, cfgPath "\.tmp", cfgPath, 1\)\s*if \(ErrorLevel\)\s*\{\s*Sleep\(200\)\s*'
                             r'V1Do\(FileMove, cfgPath "\.tmp", cfgPath, 1\)\s*\}\s*if \(ErrorLevel\)\s*\{\s*'
                             r'V1Do\(FileDelete, cfgPath "\.tmp"\)\s*return CfgUncritical\(cfgWas, false\)\s*\}\s*'
                             r'LoadStats\(true\)')

    def test_apply_open_window(self):
        """the Settings window open: what it wrote shown in it (a pick chosen, a check or number its value) and in
        CfgShownVals, so its Save doesn't take it back; nothing of the window touched with it closed"""
        ap = self.fn(self.cfg, 'CfgApply')
        m = re.search(r'if \(CfgIsOpen\(\)\)\s*for each, capKv in capList\s*if \(CfgCtls\.Has\(capKv\[1\]\)\)\s*'
                      r'\{(.*?)\n\t\t\t\t\}', ap, re.S)
        self.assertIsNotNone(m)
        blk = m.group(1)
        self.assertIn('capShow := (capS.kind = "check") ? (capKv[2] ? 1 : 0) : (capS.kind = "pick") ? '
                      'Max(1, Min(capS.picks.Length, Round(capKv[2]))) : Round(capKv[2])', blk)
        self.assertRegex(blk, r'if \(capS\.kind = "pick"\)\s*'
                              r'GuiCtrlFromHwnd\(CfgCtls\[capKv\[1\]\]\)\.Choose\(capShow\)\s*else\s*'
                              r'GuiCtrlFromHwnd\(CfgCtls\[capKv\[1\]\]\)\.Value := capShow')
        self.assertRegex(blk, r'\}\s*CfgShownVals\[capKv\[1\]\] := capShow\s*$')
        rest = ap[:m.start()] + ap[m.end():]
        for bad in (r'(?<!\w)Cfg\[', r'\bCfgCtls\b', r'\bCfgShownVals\b', r'\bCfgNote\b', r'\bCfgHwnd\b'):
            self.assertNotRegex(rest, bad)
        self.order(ap, 'DebugLog(source ": " SubStr(capSaid, 3)', 'if (CfgIsOpen())', 'V1IsFunc("HandsOffShow")')
        self.assertRegex(self.fn(self.cfg, 'CfgIsOpen'),
                         r'return \(CfgHwnd && WinExist\("ahk_id " CfgHwnd\) && IsObject\(CfgCtls\) && '
                         r'IsObject\(CfgShownVals\)\) \? 1 : 0')

    # ---- the Settings window's Save: CfgCollect + CfgApply

    def test_save_button(self):
        """Save: still Critical; the window's values (CfgCollect) set by CfgApply as "Settings" - no write or hook
        of its own"""
        btn = self.fn(self.cfg, 'CfgSave')
        self.assertIn('local v1Keep := V1Thread()', btn)
        self.assertRegex(btn, r'Critical\(\)\s*CfgSaveNow\(\)')
        save = self.fn(self.cfg, 'CfgSaveNow')
        m = re.search(r'^\s*(\w+) := CfgCollect\(&(\w+)\)', save)
        self.assertIsNotNone(m)
        self.assertRegex(save, r'if \(!CfgApply\(%s, "Settings", %s\)\)\s*\{' % (m.group(1), m.group(2)))
        self.assertEqual(save.count('CfgApply('), 1)
        for bad in ('CfgWrite(', 'V1IsFunc(', 'DebugLog(', 'GuiCtrlFromHwnd(', 'HandsOffShow', 'LoadStats('):
            self.assertNotIn(bad, save)
        for name in ('CfgSaveNow', 'CfgCollect', 'CfgWrite'):
            self.assertIsNone(DIALOGS.search(self.fn(self.cfg, name)), name)

    def test_collect(self):
        """the window's values not as it showed them: a number out of range brought into it, one that isn't a
        number put back - a Map (V1Obj) of key -> value, nothing written"""
        co = self.fn(self.cfg, 'CfgCollect')
        self.assertRegex(co, r'^\s*ccPairs := V1Obj\(\), fixed := ""')
        self.assertIn('ccV := GuiCtrlFromHwnd(ccC).Value', co)
        self.assertRegex(co, r'if !IsInteger\(ccV\)\s*\{[^}]*GuiCtrlFromHwnd\(ccC\)\.Value := CfgShownVals\[ccS\.key\]'
                             r'\s*continue\s*\}')
        self.assertRegex(co, r'if \(ccV < ccS\.lo \|\| ccV > ccS\.hi\)\s*\{\s*'
                             r'ccV := Max\(ccS\.lo, Min\(ccS\.hi, ccV\)\)')
        self.assertRegex(co, r'if \(ccV != CfgShownVals\[ccS\.key\]\)\s*ccPairs\[ccS\.key\] := ccV')
        self.assertRegex(co, r'return ccPairs\s*$')
        self.assertNotIn('CfgWrite(', co)
        self.assertNotIn('CfgApply(', co)

    # ---- File > Save settings as...

    def test_save_as_dialog(self):
        """its own boxes over the dashboard; Documents, today's date in the name, a .txt; the working folder put
        back however the dialog ends"""
        sa = self.fn(self.sf, 'CfgSaveAs')
        args = call_args(sa, 'FileSelect')
        self.assertEqual(len(args), 1)
        a = args[0]
        self.assertEqual(a[0], '"S16"')
        self.assertEqual(ahk_text(a[1], {'A_MyDocuments': DOCS}, {'FormatTime': format_time}),
                         DOCS + '\\Wiz-Maxxing settings 2026-11-05.txt')
        self.assertEqual([ahk_text(x) for x in a[2:]], ['Save settings as', 'Settings (*.txt)'])
        self.check_own_dialogs(sa, 'csa')
        self.check_working_dir(sa)

    def check_own_dialogs(self, b, p):
        m = re.search(r'(%sDash) := CfgFileDash\(\)\s*if \(IsObject\(\1\)\)\s*\1\.Opt\("\+OwnDialogs"\)' % p, b)
        self.assertIsNotNone(m)
        self.assertLess(m.start(), b.index('FileSelect('))

    def check_working_dir(self, b):
        """A_WorkingDir kept before the FileSelect (in a try) and set again right after it, before any return"""
        m = re.search(r'(\w+) := A_WorkingDir\s*try\s*(\w+) := FileSelect\([^\n]*\)\s*catch\s*\2 := ""\s*'
                      r'SetWorkingDir\(\1\)\s*if \(\2 = ""\)\s*return', b)
        self.assertIsNotNone(m)
        self.assertEqual(b.count('FileSelect('), 1)
        self.assertEqual(b.count('SetWorkingDir('), 1)

    def test_save_as_name(self):
        """.txt added to a name without one - asked about here then, as the dialog asked about the name typed; the
        bot's own PlayerStats.txt, dashboard.ini and party.ini refused before anything's asked or written"""
        sa = self.fn(self.sf, 'CfgSaveAs')
        self.assertRegex(sa, r'SplitPath\(csaPath, , , &csaExt\)\s*csaAsk := false\s*if \(csaExt = ""\)\s*'
                             r'csaPath := RTrim\(csaPath, "\. "\) "\.txt", csaAsk := true')
        self.assertRegex(sa, r'if \(CfgFileOurs\(csaPath\)\)\s*\{\s*MsgBox\([^\n]*\)\s*return\s*\}')
        self.assertRegex(sa, r'if \(csaAsk && FileExist\(csaPath\) && MsgBox\([^\n]*"YesNo[^"]*"\) != "Yes"\)\s*'
                             r'return')
        self.assertRegex(sa, r'if \(!CfgFileWrite\(csaPath, csaText\)\)\s*\{[^}]*return\s*\}')
        self.order(sa, 'FileSelect(', '".txt", csaAsk := true', 'if (CfgFileOurs(csaPath))',
                   'if (csaAsk && FileExist(csaPath)', 'CfgFileText(', 'CfgFileWrite(csaPath')
        ours = self.fn(self.sf, 'CfgFileOurs')
        self.assertIn('SplitPath(path, &cfoName, &cfoDir)', ours)
        self.assertRegex(ours, r'for cfoI, cfoAt in \[A_ScriptDir(?:, A_WorkingDir)?\]\s*if \(cfoDir = cfoAt\)\s*'
                               r'for cfoJ, cfoOwn in \[(.*?)\]\s*if \(cfoName = cfoOwn\)\s*return true')
        names = re.search(r'for cfoJ, cfoOwn in \[(.*?)\]', ours).group(1)
        self.assertEqual(sorted(ahk_text(x).lower() for x in split_args(names)),
                         ['dashboard.ini', 'party.ini', 'playerstats.txt'])
        self.assertNotIn('==', ours)
        self.assertRegex(ours, r'return false\s*$')

    def test_save_as_content(self):
        """the first line names the file's kind, the bot and when; one says what isn't in it; then CfgList's
        headings and settings in its order - netpin left out, the value as stored (quicksell:2), the mobs' floor"""
        sa = self.fn(self.sf, 'CfgSaveAs')
        self.assertIn('csaText := CfgFileText(&csaCount)', sa)
        tx = self.fn(self.sf, 'CfgFileText')
        self.assertIn('for each, cftS in CfgList.Call()', tx)
        self.assertRegex(tx, r'if \(cftS\.key = "-"\)\s*\{\s*cftOut \.= [^\n]*\s*continue\s*\}')
        self.assertRegex(tx, r'if \(!cftS\.Has\("def"\) \|\| cftS\.key = "netpin"\)\s*continue')
        self.assertRegex(tx, r'cftV := Stats\.Has\(cftS\.key\) \? Stats\[cftS\.key\] : cftS\.def\s*'
                             r'if \(\(cftS\.key = "mobradius" \|\| cftS\.key = "mobbody"\) && '
                             r'Stats\.Has\(cftS\.key "floor"\) && V1IsNum\(Stats\[cftS\.key "floor"\]\)\)\s*'
                             r'cftV := Stats\[cftS\.key "floor"\]\s*cftT := CfgFileNum\(cftV\)\s*'
                             r'if \(cftT = ""\)\s*continue')
        self.assertEqual(len(re.findall(r'\bcftV :=', tx)), 2)
        for bad in ('? 1 : 0', 'Round(', 'Integer(', 'Max(', 'Min('):
            self.assertNotIn(bad, tx)
        num = self.fn(self.sf, 'CfgFileNum')
        self.assertRegex(num, r'if \(IsInteger\(cfnumV\)\)\s*return String\(Integer\(cfnumV\)\)')
        self.assertIn('Format("{:.6f}", cfnumV + 0)', num)
        # (the first two lines as written)
        text = self.save_text(self.entries, self.load_stats())
        first = text.split('\r\n')[:3]
        self.assertEqual(first[0], '; Wiz-Maxxing settings file 1 - saved by Wizard101 bot %s on 2026-11-05 14:07'
                         % self.version)
        self.assertRegex(first[1], r'^; ')
        for what in ('stats', 'cards', 'the settings kept only in PlayerStats.txt', 'network PIN', 'Discord webhook',
                     'login'):
            self.assertIn(what, first[1])
        self.assertTrue(first[2].startswith('; '))
        self.assertIn('\r\n; ---- THE MOUSE AND WAITS ----\r\n', text)
        self.assertNotRegex(text, r'(?m)^netpin')

    def test_save_as_lines_load_back(self):
        """the shipped PlayerStats.txt's settings saved: every line read by ParseStat (a port), each setting once
        with its value - quicksell:2 kept, the mobs' floor rather than the reach the bot learned on top"""
        stats = self.load_stats()
        stats.update({'quicksell': 2, 'gearswap': 2, 'mobradius': 450, 'mobradiusfloor': 300, 'mobbody': 130,
                      'netpin': 4711, 'speedfactor': 2.5})
        text = self.save_text(self.entries, stats)
        lines, got = self.check_saved(text, self.entries, stats)
        self.assertEqual(got['quicksell'], 2)
        self.assertEqual(got['mobradius'], 300)
        self.assertEqual(got['mobbody'], 130)
        self.assertNotIn('netpin', got)
        self.assertNotIn('4711', text)
        settings = [e for e in self.entries if 'def' in e]
        self.assertGreater(len(settings), 90)
        self.assertEqual(len(got), len(settings) - 1)
        # (each a setting's line with its label after it, as a comment)
        for ln in lines:
            if ln and not ln.startswith(';'):
                self.assertRegex(ln, r'^[a-z0-9]+:-?\d+(?:\.\d+)?   ; \S')
        # (a heading line for each heading, in order)
        heads = [ln for ln in lines if ln.startswith('; ---- ')]
        self.assertEqual(heads, ['; ---- %s ----' % e['label'] for e in self.entries if e['key'] == '-'])
        # (Load reads the bot's version from the first line the way it's written)
        pa = self.fn(self.sf, 'CfgFileParse')
        m = re.search(r'RegExMatch\(cfpLn, "([^"]*)"\) && RegExMatch\(cfpLn, "([^"]*)", &cfpM\)\)\s*'
                      r'cfpGot\.version := RTrim\(cfpM\[1\], "\."\)', pa)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(2), r'bot (v[\d.]+)')
        self.assertTrue(ahk_re(m.group(1)).search(lines[0]))
        self.assertEqual(ahk_re(m.group(2)).search(lines[0]).group(1).rstrip('.'), self.version)

    def test_save_as_any_value(self):
        """whatever a setting holds - a range's ends, below or above it, a fraction, a tiny one, a huge one - and a
        label with a ; or letters past ASCII: still a line LoadStats reads, plain ASCII"""
        entries = list(self.entries) + [
            {'key': '-', 'label': 'A HEADING \u2013 M\u00c4USE ; "x"'},
            {'key': 'zzlabel', 'label': 'Gr\u00fc\u00dfe \u2014 a ; b "q"', 'kind': 'num', 'def': 1, 'lo': 0, 'hi': 9}]
        for v in (0, 1, 2, -1, -250, 99999999, 123456789012345, 2.5, -2.5, 0.1 + 0.2, 1e-9, -1e-9, 1e15 + 0.5,
                  100.0, -0.0):
            stats = {e['key']: v for e in entries if 'def' in e}
            stats.update({'mobradiusfloor': v, 'mobbodyfloor': v})
            text = self.save_text(entries, stats)
            self.check_saved(text, entries, stats)
            self.assertIn('; ---- A HEADING - M-USE ; "x" ----\r\n', text)
            self.assertRegex(text, r'\r\nzzlabel:[-\d.]+   ; Gr--e - a ; b "q"\r\n')
        # (a value that isn't a number: no line, nothing LoadStats would refuse)
        stats = {e['key']: '' for e in entries if 'def' in e}
        text = self.save_text(entries, stats)
        _, got = self.check_saved(text, entries, stats)
        self.assertEqual(got, {})

    def test_save_as_writing(self):
        """a .tmp beside it - as it is, no BOM (UTF-8-RAW: the text is ASCII) - then moved over it, once more after
        200 ms if that fails (Cheat Engine reading the file just then); the .tmp gone if it can't"""
        wr = self.fn(self.sf, 'CfgFileWrite')
        self.assertRegex(wr, r'try\s*\{\s*cfwF := FileOpen\(path "\.tmp", "w", "UTF-8-RAW"\)\s*'
                             r'cfwF\.Write\(text\)\s*cfwF\.Close\(\)\s*\}\s*catch\s*\{[^}]*'
                             r'try FileDelete\(path "\.tmp"\)\s*return false\s*\}')
        self.assertRegex(wr, r'Loop 2\s*\{\s*try\s*\{\s*FileMove\(path "\.tmp", path, 1\)\s*return true\s*\}\s*'
                             r'if \(A_Index = 1\)\s*Sleep\(200\)\s*\}\s*'
                             r'try FileDelete\(path "\.tmp"\)\s*return false\s*$')
        for bad in ('FileAppend', 'V1Do(', '"UTF-8"', 'UTF-16', 'CP1252'):
            self.assertNotIn(bad, wr)
        self.assertEqual(wr.count('FileOpen('), 1)
        # (CRLF in every line it makes; plain ASCII - a label's other letters made a "-")
        tx = self.fn(self.sf, 'CfgFileText')
        self.assertEqual(re.findall(r'(?<!`r)`n', tx), [])
        self.assertGreaterEqual(tx.count('`r`n'), 4)
        self.assertEqual(len(re.findall(r'CfgFileAscii\(cftS\.label\)', tx)), 2)
        self.assertNotRegex(tx, r'(?<!CfgFileAscii\()cftS\.label')
        self.assertRegex(self.fn(self.sf, 'CfgFileAscii'), r'return RegExReplace\(text, "\[\^\\x20-\\x7E\]", "-"\)')

    def test_log_names_only(self):
        """debug.log (public in a bug report) gets a file's name, never where it is - the user's name is in a path"""
        logs = call_args(self.sf, 'CfgFileLog')
        self.assertGreaterEqual(len(logs), 6)
        for a in logs:
            self.assertEqual(len(a), 1)
            idents = re.findall(r'[A-Za-z_][\w.]*', re.sub(r'"(?:[^"`]|`.)*"', '""', a[0]))
            for x in idents:
                self.assertRegex(x, r'(?i)(name|count|length)$', a[0])
        self.assertIn('SplitPath(csaPath, &csaName)', self.fn(self.sf, 'CfgSaveAs'))
        self.assertIn('SplitPath(clfPath, &clfName)', self.fn(self.sf, 'CfgLoadFrom'))
        self.assertRegex(self.fn(self.sf, 'CfgFileLog'), r'if \(V1IsFunc\("DebugLog"\)\)\s*DebugLog\.Call\(msg\)')
        self.assertNotRegex(self.sf, r'(?<![\w.])DebugLog\(')
        # (CfgApply's line: the file's name, the backup's name)
        ap = self.fn(self.sf, 'CfgFileApply')
        a = call_args(ap.replace('CfgApply.Call(', 'CfgApplyCall('), 'CfgApplyCall')
        self.assertEqual(len(a), 1)
        self.assertEqual(a[0][1], '"Settings loaded from " cfaData.name')
        self.assertEqual(a[0][2], 'cfaBack = "" ? "" : "PlayerStats.txt as it was: backups\\" cfaBack')

    def test_dashboard_owner_guarded(self):
        """the dashboard's Gui read only in CfgFileDash, in a try (Dash unset before DashInit)"""
        d = self.fn(self.sf, 'CfgFileDash')
        self.assertRegex(d, r'try\s*\{\s*if \(DashHwnd && GuiFromHwnd\(DashHwnd\) && IsObject\(Dash\)\)\s*'
                            r'return Dash\s*\}\s*return ""\s*$')
        rest = self.sf.replace(d, '')
        self.assertNotRegex(rest, r'(?<![\w.])Dash(?:Hwnd)?\b')

    # ---- File > Load settings from...

    def test_load_dialog(self):
        """not with the Settings window open (its unsaved changes); its own boxes; Documents; the working folder put
        back; at most 256 KB, read as UTF-8 in a try, a BOM taken off, CR / LF / CRLF lines"""
        lf = self.fn(self.sf, 'CfgLoadFrom')
        self.assertRegex(lf, r'^\s*if \(!V1IsFunc\("CfgList"\) \|\| !V1IsFunc\("CfgApply"\)\)\s*return')
        m = re.search(r'if \(CfgFileCfgOpen\(\)\)\s*\{\s*MsgBox\("Close the Settings window first[^"]*"[^\n]*\)\s*'
                      r'return\s*\}', lf)
        self.assertIsNotNone(m)
        self.assertLess(m.start(), lf.index('FileSelect('))
        self.assertRegex(self.fn(self.sf, 'CfgFileCfgOpen'),
                         r'return V1IsFunc\("CfgIsOpen"\) \? CfgIsOpen\.Call\(\) : 0')
        args = call_args(lf, 'FileSelect')
        self.assertEqual(len(args), 1)
        self.assertEqual(args[0][:2], ['3', 'A_MyDocuments'])
        self.assertEqual([ahk_text(x) for x in args[0][2:]], ['Load settings from', 'Settings (*.txt)'])
        self.check_own_dialogs(lf, 'clf')
        self.check_working_dir(lf)
        self.assertRegex(lf, r'try\s*clfSize := FileGetSize\(clfPath\)\s*catch\s*clfSize := -1\s*'
                             r'if \(clfSize < 0 \|\| clfSize > (\d+) \* (\d+)\)\s*\{\s*MsgBox\([^\n]*\)\s*return\s*\}')
        a, b = re.search(r'clfSize > (\d+) \* (\d+)\)', lf).groups()
        self.assertEqual(int(a) * int(b), 256 * 1024)
        self.assertRegex(lf, r'try\s*clfText := FileRead\(clfPath, "UTF-8"\)\s*catch\s*\{\s*MsgBox\([^\n]*\)\s*'
                             r'return\s*\}')
        self.assertRegex(lf, r'if \(SubStr\(clfText, 1, 1\) = Chr\(0xFEFF\)\)\s*clfText := SubStr\(clfText, 2\)\s*'
                             r'clfGot := CfgFileParse\(StrReplace\(StrReplace\(clfText, "`r`n", "`n"\), "`r", "`n"\)\)')
        self.order(lf, 'if (CfgFileCfgOpen())', 'FileSelect(', 'FileGetSize(', 'FileRead(', 'Chr(0xFEFF)',
                   'CfgFileParse(', 'CfgFileShow(')

    def test_load_not_a_settings_file(self):
        """no setting of the Settings window in it: said, nothing more"""
        lf = self.fn(self.sf, 'CfgLoadFrom')
        m = re.search(r'if \(!clfGot\.known\)\s*\{[^}]*MsgBox\([^\n]*(?:isn\'t|not) a settings file[^\n]*\)\s*'
                      r'return\s*\}', lf)
        self.assertIsNotNone(m)
        self.assertLess(m.end(), lf.index('CfgFileChanges('))
        self.assertRegex(lf, r'if \(!clfItems\.Length\)\s*\{[^}]*MsgBox\([^\n]*\)\s*return\s*\}\s*'
                             r'CfgFileLog\([^\n]*\)\s*CfgFileShow\(clfName, clfItems, clfNotes\)\s*$')
        # (nothing to change, but the notes say a value it can't take, or the network PIN, isn't loaded: the box
        # speaks of what it can load - "every setting in" the file only when nothing in it was left out)
        nb = re.search(r'if \(!clfItems\.Length\)\s*\{([^}]*)\}', lf).group(1)
        self.assertRegex(nb, r'clfWhat := \(clfGot\.rejected\.Count \|\| clfGot\.pin\) \? '
                             r'"every setting it can load from " : "every setting in "\n')
        self.assertIn('MsgBox("Nothing to change: " clfWhat clfName " is as it\'s set now."', nb)
        self.assertNotIn('every setting in it', nb)
        no = self.fn(self.sf, 'CfgFileNotes')
        self.assertRegex(no, r'for cfnK, cfnT in got\.rejected\s*cfnList\.Push\(cfnT\)\s*if \(cfnList\.Length\)\s*'
                             r'cfnOut\.Push\("Not loaded - ')
        self.assertRegex(no, r'if \(got\.pin\)\s*cfnOut\.Push\("The network PIN in it is never loaded\.')

    def test_load_reads_as_loadstats(self):
        """each line read with ParseStat's own two patterns - never ParseStat itself (it sets Stats): nothing in
        Stats changed but by CfgApply"""
        pa = self.fn(self.sf, 'CfgFileParse')
        self.assertIn('Loop Parse, text, "`n", "`r"', pa)
        self.assertIn('cfpLn := A_LoopField', pa)
        self.assertIn('cfpCode := RegExReplace(cfpLn, "%s")' % self.ps_strip, pa)
        self.assertIn('if (!RegExMatch(cfpCode, "%s", &cfpM))' % self.ps_pat, pa)
        self.assertIn('cfpKey := StrLower(cfpM[1]), cfpRaw := cfpM[2]', pa)
        self.assertRegex(pa, r'cfpGot\.bad \+= 1')
        # (not by name, not through .Call: only CfgApply writes)
        for bad in (r'\bParseStat\b', r'\bLoadStats\b', r'\bStatsSet\b', r'\bCfgWrite\b', r'\bStats\[[^\]\n]*\]\s*:=',
                    r'\bStats\.(?:Delete|Set|Clear)\(', r'\bStats :='):
            self.assertNotRegex(self.sf, bad)

    def test_load_keys_taken(self):
        """only CfgList's settings - netpin, a *floor line and a CharID never; other keys listed as skipped, each
        once"""
        pa = self.fn(self.sf, 'CfgFileParse')
        self.assertRegex(pa, r'for each, cfpS in CfgList\.Call\(\)\s*if \(cfpS\.Has\("def"\)\)\s*'
                             r'cfpBy\[cfpS\.key\] := cfpS')
        self.assertRegex(pa, r'if \(cfpKey = "netpin"\)\s*\{\s*cfpGot\.pin := 1\s*continue\s*\}')
        self.assertRegex(pa, r'if \(RegExMatch\(cfpKey, "floor\$"\) \|\| InStr\(cfpKey, "charid"\)\)\s*continue')
        # (but the mobs' reach's own floor line - what you set there, the reach line being what the bot widened it
        # to, as a PlayerStats.txt from another PC has it - taken as its value, last line deciding, in its range)
        self.assertRegex(pa, r'if \(cfpKey = "mobradiusfloor" \|\| cfpKey = "mobbodyfloor"\)\s*\{\s*'
                             r'cfpFloor\[SubStr\(cfpKey, 1, -5\)\] := cfpRaw\s*continue\s*\}')
        self.assertRegex(pa, r'for cfpKey, cfpRaw in cfpFloor\s*if \(IsInteger\(cfpRaw\) && cfpBy\.Has\(cfpKey\)\)\s*\{\s*'
                             r'cfpS := cfpBy\[cfpKey\]\s*'
                             r'cfpGot\.rejected\.Delete\(cfpKey\), cfpGot\.fixed\.Delete\(cfpKey\)\s*'
                             r'cfpGot\.vals\[cfpKey\] := Max\(cfpS\.lo, Min\(cfpS\.hi, Integer\(cfpRaw\)\)\)\s*\}\s*'
                             r'return cfpGot\s*$')
        self.order(pa, 'cfpKey = "mobradiusfloor"', '"floor$"')
        self.assertEqual(len('floor'), 5)
        self.assertRegex(pa, r'if \(!cfpBy\.Has\(cfpKey\)\)\s*\{\s*if \(!cfpSeen\.Has\(cfpKey\)\)\s*'
                             r'cfpSeen\[cfpKey\] := 1, cfpGot\.skipped\.Push\(cfpKey\)\s*continue\s*\}')
        self.order(pa, 'cfpKey := StrLower(', 'if (cfpKey = "netpin")', '"floor$"', 'if (!cfpBy.Has(cfpKey))',
                   'cfpGot.known += 1', 'cfpGot.vals[cfpKey] := cfpV')
        # (netpin is a CfgList setting - so it has to go before the lookup; mobradiusfloor isn't)
        keys = [e['key'] for e in self.entries if 'def' in e]
        self.assertIn('netpin', keys)
        self.assertFalse([k for k in keys if k.endswith('floor') or 'charid' in k])

    def test_load_checks(self):
        """as the Settings window checks: a whole number; a check 0 / 1 (2 too for quicksell, gearswap, planner); a
        pick one of its choices, else not loaded; a number brought into its range, said; the last line of a key
        decides"""
        pa = self.fn(self.sf, 'CfgFileParse')
        self.assertRegex(pa, r'if \(!IsInteger\(cfpRaw\)\)\s*cfpWhy := "[^"]+"\s*else\s*\{\s*cfpV := Integer\(cfpRaw\)')
        # (quicksell:2 the rehearsal; gearswap and planner read 2 and up as 2 - Gear.ahk, Planner.ahk)
        m = re.search(r'if \(cfpS\.kind = "check"\)\s*\{\s*'
                      r'if \(cfpV != 0 && cfpV != 1 && !\(cfpV = 2 && cfpKey = "quicksell"\) && '
                      r'!\(cfpV >= 2 && \((.*?)\)\)\)\s*cfpWhy := "[^"]+"\s*\}', pa)
        self.assertIsNotNone(m)
        self.assertEqual(sorted(re.findall(r'cfpKey = "(\w+)"', m.group(1))), ['gearswap', 'planner'])
        self.assertEqual(len(split_args(m.group(1).replace(' || ', ','))), 2)
        self.assertIn('StatOr("planner", 0) >= 2', code_of(os.path.join(AF, 'Planner.ahk')))
        self.assertRegex(pa, r'else if \(cfpS\.kind = "pick"\)\s*\{\s*'
                             r'if \(cfpV < 1 \|\| cfpV > cfpS\.picks\.Length\)\s*cfpWhy := ')
        self.assertRegex(pa, r'else if \(cfpV < cfpS\.lo \|\| cfpV > cfpS\.hi\)\s*\{\s*'
                             r'cfpV := Max\(cfpS\.lo, Min\(cfpS\.hi, cfpV\)\)\s*cfpFix := [^\n]+\s*\}')
        self.assertRegex(pa, r'cfpGot\.rejected\.Delete\(cfpKey\), cfpGot\.fixed\.Delete\(cfpKey\)\s*'
                             r'if \(cfpWhy != ""\)\s*\{\s*cfpGot\.rejected\[cfpKey\] := [^\n]+\s*'
                             r'cfpGot\.vals\.Delete\(cfpKey\)\s*continue\s*\}\s*'
                             r'if \(cfpFix != ""\)\s*cfpGot\.fixed\[cfpKey\] := cfpFix\s*'
                             r'cfpGot\.vals\[cfpKey\] := cfpV\s*\}')
        self.assertNotIn('vals.Has(', pa)
        # (each kind there is checked: the three CfgList has)
        self.assertEqual(sorted({e['kind'] for e in self.entries if 'def' in e}), ['check', 'num', 'pick'])
        for e in self.entries:
            if e.get('kind') == 'num':
                self.assertLessEqual(e['lo'], e['hi'], e['key'])
            if e.get('kind') == 'pick':
                self.assertTrue(1 <= e['def'] <= len(e['picks']), e['key'])

    def test_load_preview(self):
        """a window of its own over the dashboard: only the settings that would change (label, now, from the file),
        each ticked but the party's two; Apply, Cancel, its X and Esc"""
        ch = self.fn(self.sf, 'CfgFileChanges')
        self.assertIn('for each, cfchS in CfgList.Call()', ch)
        self.assertRegex(ch, r'if \(!cfchS\.Has\("def"\) \|\| !got\.vals\.Has\(cfchS\.key\)\)\s*continue\s*'
                             r'cfchNow := Stats\.Has\(cfchS\.key\) \? Stats\[cfchS\.key\] : cfchS\.def\s*'
                             r'if \(V1IsNum\(cfchNow\) && cfchNow \+ 0 = got\.vals\[cfchS\.key\]\)\s*continue')
        m = re.search(r'tick: !\(([^()]*)\)\}', ch)
        self.assertIsNotNone(m)
        self.assertEqual(sorted(re.findall(r'cfchS\.key = "(\w+)"', m.group(1))), ['partybattle', 'partyrole'])
        self.assertEqual(m.group(1).count('||'), 1)
        sh = self.fn(self.sf, 'CfgFileShow')
        self.assertRegex(sh, r'cfsWin := Gui\(\(IsObject\(cfsDash\) \? "\+Owner" cfsDash\.Hwnd " " : ""\) ')
        lv = re.search(r'cfsLv := cfsWin\.Add\("ListView", ([^\n]*)\)\n', sh)
        self.assertIsNotNone(lv)
        lv = split_args(lv.group(1))
        self.assertEqual(len(lv), 2)
        self.assertEqual(lv[1], '["Setting", "Now", "From the file"]')
        for o in ('Checked', 'NoSort', 'vCfgFileList'):
            self.assertIn(o, ' '.join(re.findall(r'"([^"]*)"', lv[0])).split())
        self.assertRegex(sh, r'for each, cfsIt in items\s*'
                             r'cfsLv\.Add\(cfsIt\.tick \? "Check" : "", CfgFileLabel\(cfsIt\.s\), '
                             r'CfgFileShown\(cfsIt\.s, cfsIt\.now\), CfgFileShown\(cfsIt\.s, cfsIt\.from\)\)')
        self.assertRegex(sh, r'if \(notes != ""\)\s*\{[^}]*cfsWin\.Add\("Text", [^\n]*, notes\)\s*\}')
        self.assertIn('.OnEvent("Click", CfgFileApply.Bind(cfsData))', sh)
        self.assertIn('.OnEvent("Click", CfgFileCancel.Bind(cfsData))', sh)
        self.assertIn('cfsWin.OnEvent("Close", CfgFileCancel.Bind(cfsData))', sh)
        self.assertIn('cfsWin.OnEvent("Escape", CfgFileCancel.Bind(cfsData))', sh)
        self.assertIn('cfaLv := cfaWin["CfgFileList"]', self.fn(self.sf, 'CfgFileApply'))
        ca = self.fn(self.sf, 'CfgFileCancel')
        self.assertRegex(ca, r'^\s*local v1Keep := V1Thread\(\)')
        self.assertRegex(ca, r'if \(cfxData\.busy\)\s*return true')
        self.assertIn('try cfxWin.Destroy()', ca)

    def test_load_notes(self):
        """under the list: what still wins (a school's own value, the deck in use), Wait for me's reset at each
        start, the party's two left unticked, values brought into range or not taken, skipped keys, unreadable
        lines, the PIN, a newer bot's file"""
        no = self.fn(self.sf, 'CfgFileNotes')
        self.assertRegex(no, r'for cfnI, cfnSch in \["storm", "fire", "ice", "life", "death", "myth", "balance"\]\s*'
                             r'if \(Stats\.Has\(cfnSch "\." cfnIt\.key\)\)')
        self.assertRegex(no, r'try\s*\{\s*if \(IsObject\(DeckNow\) && IsObject\(DeckNow\.vals\)\)[^}]*'
                             r'if \(DeckNow\.vals\.Has\(cfnIt\.key\)\)')
        self.assertRegex(no, r'if \(cfnHas\.Has\("handsoffon"\) \|\| cfnHas\.Has\("handsoff"\)\)\s*cfnOut\.Push\(')
        self.assertRegex(no, r'if \(cfnHas\.Has\("partyrole"\) \|\| cfnHas\.Has\("partybattle"\)\)\s*cfnOut\.Push\(')
        for has in ('for cfnK, cfnT in got.fixed', 'for cfnK, cfnT in got.rejected', 'if (got.skipped.Length)',
                    'if (got.bad)', 'if (got.pin)'):
            self.assertRegex(no, re.escape(has) + r'\s*(?:cfnList|cfnOut)\.Push\(', has)
        # (each list gathered goes into a note - cfnOut - and every note into the text it returns: what the window
        # and the "Nothing to change" box show)
        self.assertRegex(no, r'if \(cfnOwn\.Length\)\s*cfnOut\.Push\([^\n]*CfgFileFew\(cfnOwn\)')
        self.assertRegex(no, r'if \(cfnDeck\.Length\)\s*cfnOut\.Push\([^\n]*CfgFileFew\(cfnDeck\)')
        lists = re.findall(r'cfnList := \[\]\s*for cfnK, cfnT in got\.(\w+)\s*cfnList\.Push\(cfnT\)\s*'
                           r'if \(cfnList\.Length\)\s*cfnOut\.Push\("([^"]*)" CfgFileFew\(cfnList\)', no)
        self.assertEqual([k for k, t in lists], ['fixed', 'rejected'])
        self.assertTrue(lists[0][1].startswith('Brought into its range'))
        self.assertTrue(lists[1][1].startswith('Not loaded'))
        self.assertRegex(no, r'cfnText := ""\s*for each, cfnT in cfnOut\s*cfnText \.= [^\n]*"- " cfnT\s*return cfnText\s*$')
        self.assertEqual(no.count('return '), 1)
        lf = self.fn(self.sf, 'CfgLoadFrom')
        self.assertRegex(lf, r'(\w+) := CfgFileNotes\(')
        nv = re.search(r'(\w+) := CfgFileNotes\(', lf).group(1)
        self.assertRegex(lf, r'CfgFileShow\([^\n]*\b%s\)' % nv)
        self.assertRegex(no, r'cfnNewer := VerCompare\(LTrim\(got\.version, "vV"\), LTrim\(cfnBot, "vV"\)\) > 0')
        self.assertRegex(no, r'if \(cfnNewer\)\s*cfnOut\.Push\(')
        # (the start-up reset it warns about: on, 3 s - as the note says)
        af = code_of(os.path.join(AF, 'Autofarmer.ahk'))
        self.assertIn('StatsSet([["handsoffon", 1], ["handsoff", 3]]', af)
        self.assertRegex(no, r'Wait for me goes back on, with 3 s, at every start')

    def test_load_skipped_said_rightly(self):
        """the skipped keys named by what Load takes - the Settings window's settings: a plain PlayerStats.txt has
        settings the bot reads that aren't in that window (navmem...), skipped too - never said to be "not settings
        of this bot" """
        cfg_keys = {e['key'] for e in self.entries if 'def' in e}
        ps = {}
        with open(os.path.join(AF, 'PlayerStats.txt'), encoding='utf-8') as f:
            for ln in f.read().splitlines():
                self.parse_stat(ln, ps)
        read = set()
        for p in ahk_walk():
            read |= {k.lower() for k in re.findall(r'(?<![\w.])Stat\("(\w+)"', code_of(p))}
        kept = sorted(k for k in ps if k not in cfg_keys and k in read)
        self.assertIn('navmem', kept)
        no = self.fn(self.sf, 'CfgFileNotes')
        m = re.search(r'if \(got\.skipped\.Length\)\s*cfnOut\.Push\("([^"]*)"', no)
        self.assertIsNotNone(m)
        self.assertNotIn('settings of this bot', m.group(1))
        self.assertIn('not in the Settings window', m.group(1))
        self.assertIn('settings kept only in PlayerStats.txt', m.group(1))

    def test_help_names_the_menu_bar(self):
        """the Settings window's help says where a switch is now - the dashboard's menu bar -, never a dashboard
        button the menus took (Wait for me, Game to front, Check for updates...: gone from the window)"""
        helps = re.findall(r'help: "((?:[^"`]|`.)*)"', '\n'.join(self.cfg_lines))
        self.assertGreater(len(helps), 50)
        for h in helps:
            for g in GONE_BUTTONS:
                self.assertNotRegex(h, r'(?i)\b%s"? button' % re.escape(g), h[:60])
        wait = [h for h in helps if h.startswith('While you use the keyboard or mouse yourself the bot waits')]
        self.assertEqual(len(wait), 1)
        self.assertIn("dashboard's Bot menu: Wait for me", wait[0])

    def test_heading_names_the_menu(self):
        """the heading CfgWrite - and Setup's SuStatSet, the same one - puts over a key PlayerStats.txt hasn't got
        names no dashboard button the menu bar took, and the one written before v1.10.0 counts as there (no second
        heading); the shipped PlayerStats.txt names no such button either"""
        old = "; ---- Set in the Settings window (the dashboard's Settings button) ----"
        cw = self.fn(self.cfg, 'CfgWrite')
        su = self.fn(code_of(os.path.join(ROOT, 'Setup.ahk')), 'SuStatSet')
        head = re.search(r'\bcfgHead := "([^"]*)"', cw)
        self.assertIsNotNone(head)
        self.assertTrue(head.group(1).startswith('; ---- Set in the Settings window ('), head.group(1))
        for g in GONE_BUTTONS:
            self.assertNotRegex(head.group(1), r'(?i)\b%s"? button' % re.escape(g))
        self.assertIn('cfgLines.Push(cfgHead)', cw)
        self.assertIn('head := "%s"' % head.group(1), su)
        self.assertIn('lines.Push(head)', su)
        for code, ln, var, has in ((cw, 'cfgLn', 'cfgHead', 'cfgHas'), (su, 'line', 'head', 'hasHead')):
            m = re.search(r'if \(%s == %s \|\| %s == (\w+)\)\s*%s := true' % (ln, var, ln, has), code)
            self.assertIsNotNone(m, var + ': the old heading counts as there too')
            self.assertIn('%s := "%s"' % (m.group(1), old), code)
        for ln in read_lines(os.path.join(AF, 'PlayerStats.txt')):
            for g in GONE_BUTTONS:
                self.assertNotRegex(ln, r'(?i)\b%s"? button' % re.escape(g), ln)

    def test_apply(self):
        """Apply: not with the Settings window open; PlayerStats.txt copied to backups\\ first (nothing set if that
        fails); then Critical round the ticked rows checked against Stats again and CfgApply - no box while it's
        held; a short note after"""
        ap = self.fn(self.sf, 'CfgFileApply')
        self.assertRegex(ap, r'^\s*local v1Keep := V1Thread\(\)[^\n]*\s*if \(cfaData\.busy\)\s*return')
        self.assertRegex(ap, r'if \(CfgFileCfgOpen\(\)\)\s*\{\s*MsgBox\("Close the Settings window first[^\n]*\)\s*'
                             r'return\s*\}')
        self.assertRegex(ap, r'while \(cfaRow := cfaLv\.GetNext\(cfaRow, "C"\)\)\s*'
                             r'if \(cfaRow <= cfaData\.items\.Length\)\s*cfaTicked\.Push\(cfaData\.items\[cfaRow\]\)')
        self.assertIn('cfaStats := A_WorkingDir "\\PlayerStats.txt"', ap)
        back = re.search(r'cfaBack := ([^\n]*)', ap.split('if (FileExist(cfaStats))', 1)[1]).group(1)
        self.assertEqual(ahk_text(back, {}, {'FormatTime': format_time}),
                         'PlayerStats before settings load 2026-11-05 140709.txt')
        self.assertRegex(ap, r'try\s*\{\s*if \(!DirExist\(A_WorkingDir "\\backups"\)\)\s*'
                             r'DirCreate\(A_WorkingDir "\\backups"\)\s*'
                             r'FileCopy\(cfaStats, A_WorkingDir "\\backups\\" cfaBack, 1\)\s*\}\s*catch\s*\{[^}]*'
                             r'MsgBox\([^\n]*\)\s*return\s*\}')
        self.assertRegex(ap, r'Critical\(\)\s*cfaPairs := V1Obj\(\)\s*for each, cfaIt in cfaTicked\s*\{\s*'
                             r'cfaNow := Stats\.Has\(cfaIt\.key\) \? Stats\[cfaIt\.key\] : cfaIt\.s\.def\s*'
                             r'if \(!V1IsNum\(cfaNow\) \|\| cfaNow \+ 0 != cfaIt\.from\)\s*'
                             r'cfaPairs\[cfaIt\.key\] := cfaIt\.from')
        self.assertRegex(ap, r'cfaOk := V1IsFunc\("CfgApply"\) \? CfgApply\.Call\(cfaPairs, ')
        self.order(ap, 'if (CfgFileCfgOpen())', 'cfaData.busy := 1', 'FileCopy(', 'Critical()', 'Stats.Has(',
                   'CfgApply.Call(', 'Critical("Off")', 'cfaWin.Destroy()', 'MsgBox(')
        self.assertEqual(ap.count('Critical('), 2)
        self.assertEqual(critical_dialogs(ap), [])
        self.assertGreaterEqual(len(DIALOGS.findall(ap.split('Critical("Off")', 1)[1])), 3)

    def test_critical_never_over_a_box(self):
        """Critical only round Apply's check and write - never in the menu's own threads, never over a box"""
        self.assertEqual(self.sf.count('Critical('), 2)
        for fname, _, _, _ in functions('\n'.join(self.sf_lines)):
            b = self.fn(self.sf, fname)
            self.assertEqual(critical_dialogs(b), [], fname)
        for name in ('CfgSaveAs', 'CfgLoadFrom', 'CfgFileShow', 'CfgFileCancel'):
            self.assertNotIn('Critical(', self.fn(self.sf, name), name)
        self.assertEqual(critical_dialogs(self.sf), [])


if __name__ == '__main__':
    unittest.main()
