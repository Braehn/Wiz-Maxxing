"""test_fix2_setup_release.py - Setup, the updater, the watcher, Cheat Engine's script, the pet trainer and the release
workflow after the 2026-11-27 review. python -m unittest test_fix2_setup_release  (from AutoFarmer\\vision)

- what counts as yours (Updater.ahk UpIsMine, read from its source) and what Setup's SuCopyMine leaves out, run on paths;
  SuInstallHome's two ways in (over an install there, or a whole folder's copy);
- UpCleanup deletes only the .old files an update moved aside - never one of yours (vision.log.old);
- SuOfferDelete never offers a folder whose backups\\ isn't in the install, and says what else isn't - "Everything was
  copied over" only when it all was (run on temp folders with its own patterns);
- every path in a single-quoted PowerShell string goes through UpPsQuote (O'Brien);
- the saved GitHub token is asked for again only when GitHub says it's no good, not when it couldn't be checked;
- WatchSet(on) closes a watcher another folder started;
- the pet trainer's Win+1 only with Wizard101 in front, and its round stops once it isn't;
- Cheat Engine's script only while the bot's speedhack setting is on (read again at the walking key: switched on, the
  bot's first press counts), says once when PlayerStats.txt can't be opened - the settings read last kept - and
  Setup puts it in neither for a path Cheat Engine can't open nor through a file in %TEMP% when it's elevated; no other
  .exe link taken for Cheat Engine's installer;
- release.yml: the token only in the steps that talk to GitHub, none kept by the checkout."""
import os
import re
import shutil
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AF = os.path.dirname(HERE)              # the AutoFarmer folder
ROOT = os.path.dirname(AF)              # the repository
SETUP_AHK = os.path.join(ROOT, 'Setup.ahk')
UPDATER_AHK = os.path.join(ROOT, 'Updater.ahk')
WATCH_AHK = os.path.join(ROOT, 'Watch.ahk')
PET_AHK = os.path.join(ROOT, 'AutoPetTrainer', 'PetTrainer.ahk')
LUA = os.path.join(ROOT, 'CheatEngine', 'wiz-maxxing.lua')
RELEASE_YML = os.path.join(ROOT, '.github', 'workflows', 'release.yml')
README = os.path.join(ROOT, 'README.md')

sys.path.insert(0, HERE)
import test_ahk_names as tan            # noqa: E402  (its AutoHotkey function finder)
import test_speedhack as ts             # noqa: E402  (its fake Cheat Engine: the Lua scenarios, with lupa)

M = ts.M


def fn_body(path, name):
    """a function's code lines (strings blanked, comments gone) - and its raw text, strings kept"""
    text = tan.read(path)
    for n, params, line, body in tan.functions(text):
        if n == name:
            raw = text.splitlines()[line - 1:body[-1][0]] if body else []
            return '\n'.join(c for _, c in body), '\n'.join(raw)
    return None, None


def ahk_re(pat):
    """an AutoHotkey RegEx string as Python's re: its i) option, \\x{hhhh} as \\uhhhh"""
    flags = 0
    m = re.match(r'^([imsx]*)\)', pat)
    if m:
        flags = re.I if 'i' in m.group(1) else 0
        pat = pat[m.end():]
    pat = re.sub(r'\\x\{([0-9A-Fa-f]{4})\}', lambda g: '\\u' + g.group(1), pat)
    return re.compile(pat, flags)


def patterns(raw, var):
    """the patterns of every RegExMatch / RegExReplace on var in raw, in order"""
    return [ahk_re(p) for p in re.findall(r'RegEx(?:Match|Replace)\(' + re.escape(var) + r', "((?:[^"]|"")*)"', raw)]


class Yours(unittest.TestCase):
    """UpIsMine (the updater keeps these) and SuCopyMine (Setup copies these of yours across) on real paths"""

    @classmethod
    def setUpClass(cls):
        _, raw = fn_body(UPDATER_AHK, 'UpIsMine')
        assert raw, 'Updater.ahk: UpIsMine'
        cls.rx = patterns(raw, 'rel')
        cls.raw = raw

    def mine(self, rel, slots=()):
        rx = self.rx
        slots = {s.lower() for s in slots}
        if any(r.search(rel) for r in rx[:4]):
            return True
        m = rx[4].search(rel)
        if m and m.group(1).lower() in slots:
            return True
        return rel.startswith('AutoFarmer\\') and ('file:' + rel[11:].lower()) in slots

    def test_the_rules_found(self):
        self.assertEqual(len(self.rx), 5, 'UpIsMine: its four plain rules and the slot picture one')
        self.assertIn('slots.HasKey("file:"', self.raw)

    def test_yours(self):
        for rel in ('AutoFarmer\\PlayerStats.txt', 'AutoFarmer\\dashboard.ini', 'AutoFarmer\\resources\\characters.txt',
                    'AutoFarmer\\learned\\cards.txt', 'AutoFarmer\\backups\\x (before learned card 3).png',
                    'AutoFarmer\\generated\\a.png', 'AutoQuester\\routes\\r.txt', 'AutoFarmer\\dungeons\\d.txt',
                    'AutoFarmer\\decks\\k.txt', 'AutoQuester\\resources\\walk_memory.txt',
                    'AutoQuester\\resources\\known_zones.txt', 'AutoFarmer\\debug.log', 'AutoFarmer\\vision\\vision.log',
                    'updater.ini'):
            self.assertTrue(self.mine(rel), rel)
        self.assertTrue(self.mine('AutoFarmer\\balance\\hit2.png', ['balance\\hit2']))
        self.assertTrue(self.mine('AutoFarmer\\ui1.25\\balance\\hit2.raw.png', ['balance\\hit2']))
        self.assertTrue(self.mine('AutoFarmer\\fire\\hit1.png', ['file:fire\\hit1.png']))

    def test_not_yours(self):
        for rel in ('Wiz-Maxxing.exe', 'Setup.exe', 'AutoFarmer\\Autofarmer.exe', 'AutoFarmer\\Autofarmer.ahk',
                    'AutoFarmer\\balance\\hit2.png', 'AutoQuester\\resources\\nav_calibration.txt', 'version.txt'):
            self.assertFalse(self.mine(rel), rel)

    def test_setup_copies_yours_but_backups_generated_logs(self):
        _, raw = fn_body(SETUP_AHK, 'SuCopyMine')
        skip = patterns(raw, 'rel')
        self.assertEqual(len(skip), 1)
        copied = lambda rel: not skip[0].search(rel) and self.mine(rel)
        self.assertTrue(copied('AutoFarmer\\learned\\cards.txt'))
        self.assertTrue(copied('AutoFarmer\\PlayerStats.txt'))
        for rel in ('AutoFarmer\\backups\\x.png', 'AutoFarmer\\generated\\a.png', 'AutoFarmer\\debug.log',
                    'AutoFarmer\\Autofarmer.exe'):
            self.assertFalse(copied(rel), rel)
        self.assertIn('UpIsMine(rel, slots)', raw)

    def test_install_home_two_ways_in(self):
        """over an install there (UpCopy - yours kept, the other folder's saved in backups\\), else a whole folder's copy
        (DirCopy: everything, backups\\ too) - a version picked takes only SuCopyMine's from this folder"""
        _, raw = fn_body(SETUP_AHK, 'SuInstallHome')
        a = raw.index('if (FileExist(home "\\AutoFarmer\\Autofarmer.ahk"))\n')
        self.assertLess(a, raw.index('res := UpCopy(from, home, rollback)'))
        self.assertLess(raw.index('res := UpCopy(from, home, rollback)'), raw.index('V1Do(DirCopy, from, home, 1)'))
        self.assertIn('if (src != "" && V1Gt(SuLastRun(A_ScriptDir), 0))', raw)
        self.assertIn('SuCopyMine(A_ScriptDir, home)', raw)
        self.assertIn('/moved `"" A_ScriptDir "`"', raw)


class Cleanup(unittest.TestCase):
    """UpCleanup: only an update's own moved-aside programs"""

    def test_only_what_an_update_moved_aside(self):
        code, raw = fn_body(UPDATER_AHK, 'UpCleanup')
        self.assertIsNotNone(raw)
        strip = patterns(raw, 'SubStr(A_LoopFilePath, StrLen(A_ScriptDir) + 2)')
        self.assertEqual(len(strip), 1, 'the .old (and .<tick>.old) taken off')
        self.assertRegex(code, r'if \(!UpIsMine\(rel, slots\)\)\s*V1Do\(FileDelete, A_LoopFilePath\)')
        mine = Yours()
        Yours.setUpClass()
        gone = lambda rel: not mine.mine(strip[0].sub('', rel))
        self.assertTrue(gone('AutoFarmer\\Autofarmer.exe.old'))
        self.assertTrue(gone('Wiz-Maxxing.exe.123456789.old'))
        self.assertTrue(gone('AutoQuester\\AutoQuester.exe.old'))
        self.assertFalse(gone('AutoFarmer\\vision\\vision.log.old'), "the vision helper's older log half")
        self.assertFalse(gone('AutoFarmer\\learned\\cards.txt.old'))
        self.assertFalse(gone('AutoFarmer\\backups\\x.png.old'))


class OfferDelete(unittest.TestCase):
    """SuOfferDelete's look at the old folder, run as it runs (its own patterns) on temp folders"""

    @classmethod
    def setUpClass(cls):
        _, cls.raw = fn_body(SETUP_AHK, 'SuOfferDelete')
        rx = patterns(cls.raw, 'rel')
        assert len(rx) == 2, rx
        cls.ignore, cls.backup = rx

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='wm_offer_')
        self.addCleanup(shutil.rmtree, self.dir, True)
        self.old = os.path.join(self.dir, 'Wiz-Maxxing-v1.14.6', 'Wiz-Maxxing')
        self.home = os.path.join(self.dir, 'Programs', 'Wiz-Maxxing')

    def put(self, root, *rels):
        for rel in rels:
            p = os.path.join(root, *rel.split('\\'))
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, 'w') as f:
                f.write('x')

    def look(self):
        missing, first, backups = 0, '', 0
        for d, _, fs in os.walk(self.old):
            for f in fs:
                rel = os.path.relpath(os.path.join(d, f), self.old).replace('/', '\\')
                if self.ignore.search(rel) or os.path.exists(os.path.join(self.home, *rel.split('\\'))):
                    continue
                missing += 1
                first = first or rel
                if self.backup.search(rel):
                    backups += 1
        return missing, backups

    def test_a_whole_copy_is_all_there(self):
        files = ('AutoFarmer\\Autofarmer.ahk', 'AutoFarmer\\backups\\b.png', 'AutoFarmer\\debug.log')
        self.put(self.old, *files)
        self.put(self.home, *files)
        self.put(self.old, 'updater.log', 'AutoFarmer\\Thumbs.db', 'Wiz-Maxxing.exe.old')
        self.assertEqual(self.look(), (0, 0))

    def test_backups_not_copied_never_offered(self):
        self.put(self.old, 'AutoFarmer\\Autofarmer.ahk', 'AutoFarmer\\learned\\cards.txt', 'AutoFarmer\\backups\\b.png',
                 'AutoFarmer\\debug.log')
        self.put(self.home, 'AutoFarmer\\Autofarmer.ahk', 'AutoFarmer\\learned\\cards.txt')
        self.assertEqual(self.look(), (2, 1))

    def test_other_files_named(self):
        self.put(self.old, 'AutoFarmer\\Autofarmer.ahk', 'AutoQuester\\resources\\nav_calibration.txt')
        self.put(self.home, 'AutoFarmer\\Autofarmer.ahk')
        self.assertEqual(self.look(), (1, 0))

    def test_the_question_says_so(self):
        raw = self.raw
        self.assertLess(raw.index('if (backups)'), raw.index('MsgBox('), 'backups\\ not there: no question at all')
        self.assertRegex(raw, r'if \(backups\)\s*return SuLogLine\(')
        self.assertIn('(missing ? "" : "(Everything was copied over', raw)
        self.assertIn('if (missing)', raw)
        self.assertIn('FileExist(home "\\" rel)', raw)
        self.assertIn('"Wiz-Maxxing setup", 262436)', raw, 'No the default button')


class PowerShellQuotes(unittest.TestCase):
    def test_ps_quote(self):
        _, raw = fn_body(UPDATER_AHK, 'UpPsQuote')
        self.assertIsNotNone(raw)
        m = re.search(r'RegExReplace\(s, "([^"]+)", "\$0\$0"\)', raw)
        self.assertIsNotNone(m)
        rx = ahk_re(m.group(1))
        q = lambda s: "'" + rx.sub(lambda g: g.group(0) * 2, s) + "'"
        self.assertEqual(q("C:\\Users\\O'Brien\\AppData"), "'C:\\Users\\O''Brien\\AppData'")
        self.assertEqual(q('C:\\Users\\O\u2019Brien'), "'C:\\Users\\O\u2019\u2019Brien'")
        self.assertEqual(q('C:\\plain'), "'C:\\plain'")

    def test_no_raw_path_in_a_quoted_powershell_string(self):
        for path in (SETUP_AHK, UPDATER_AHK):
            for no, line in enumerate(tan.read(path).splitlines(), 1):
                if 'powershell' in line.lower() and not line.lstrip().startswith(';'):
                    self.assertNotRegex(line, r"'\"\s*[A-Za-z_]", '%s:%d - a path put in \'...\' as it is' % (path, no))
        self.assertGreaterEqual(tan.read(SETUP_AHK).count('UpPsQuote('), 5)
        self.assertGreaterEqual(tan.read(UPDATER_AHK).count('UpPsQuote('), 3)


class Token(unittest.TestCase):
    def test_bad_only_when_github_says_so(self):
        code, raw = fn_body(UPDATER_AHK, 'UpTokenTest')
        self.assertRegex(tan.read(UPDATER_AHK), r'(?m)^UpTokenTest\(token, &bad := false\)')
        self.assertIn('bad := status = 401 || status = 404 || (status = 403 && !limit)', raw)
        self.assertIn('InStr(resp, "rate limit")', raw)

    def test_saved_token_kept_when_not_checked(self):
        code, raw = fn_body(SETUP_AHK, 'SuToken')
        self.assertIn('why := UpTokenTest(UpToken(), &bad)', raw)
        self.assertRegex(raw, r'if \(!bad\)\s*return SuLogLine\(')
        self.assertLess(raw.index('if (!bad)'), raw.index('Run("https://github.com/settings/personal-access-tokens/new")'))


class Watcher(unittest.TestCase):
    def test_another_folders_watcher_closed(self):
        code, raw = fn_body(WATCH_AHK, 'WatchSet')
        on = raw[:raw.index('V1Do(FileDelete, link)')]
        self.assertLess(on.index('WatchPids(root)'), on.index('if (!WatchPids().Length)'))
        self.assertIn('WatchClosePid(pid)', on)
        self.assertLess(on.index('DetectHiddenWindows(true)'), on.index('WatchClosePid(pid)'))

    def test_watch_pids_filter(self):
        code, raw = fn_body(WATCH_AHK, 'WatchPids')
        self.assertIn('mine := notFrom = "" ? "" : RTrim(notFrom, "\\") "\\Wiz-Maxxing."', raw)
        self.assertIn('(mine = "" || !InStr(p.CommandLine, mine))', raw)
        rx = ahk_re(re.search(r'RegExMatch\(p\.CommandLine, "((?:[^"`]|`.)+)"\)', raw).group(1).replace('`"', '"'))
        root = 'C:\\Bots\\Wiz-Maxxing'

        def other(cmd):
            mine = root.rstrip('\\') + '\\Wiz-Maxxing.'
            return bool(rx.search(cmd)) and mine.lower() not in cmd.lower()
        self.assertFalse(other('"C:\\Bots\\Wiz-Maxxing\\Wiz-Maxxing.exe" /watch'))
        self.assertFalse(other('"C:\\Program Files\\AutoHotkey\\v2\\AutoHotkey64.exe" "c:\\bots\\wiz-maxxing\\Wiz-Maxxing.ahk" /watch'))
        self.assertTrue(other('"C:\\Users\\me\\AppData\\Local\\Programs\\Wiz-Maxxing\\Wiz-Maxxing.exe" /watch'))
        self.assertTrue(other('"C:\\Bots\\Wiz-Maxxing2\\Wiz-Maxxing.exe" /watch'))


class PetTrainer(unittest.TestCase):
    def test_only_with_the_game_in_front(self):
        text = tan.read(PET_AHK)
        lines = text.splitlines()
        hk = [i for i, ln in enumerate(lines) if ln.startswith('#1::')]
        self.assertEqual(len(hk), 1)
        self.assertEqual(lines[hk[0] - 1].strip(), '#HotIf WinActive("ahk_exe WizardGraphicalClient.exe")')
        esc = [i for i, ln in enumerate(lines) if ln.startswith('Esc::')][0]
        between = [ln.strip() for ln in lines[hk[0]:esc]]
        self.assertIn('#HotIf', between, 'Esc closes it anywhere: the #HotIf ends before it')

    def test_every_send_and_click_checked(self):
        lines = tan.read(PET_AHK).splitlines()
        start = [i for i, ln in enumerate(lines) if ln.startswith('#1::')][0]
        end = [i for i, ln in enumerate(lines) if ln.strip() == '#HotIf' and i > start][0]
        last = None
        for i in range(start, end):
            s = lines[i].strip()
            if 'PetGameGone()' in s:
                last = 'checked'
            elif re.match(r'(Send\("x"\)|Click\(\)|direction := Random)', s):
                self.assertEqual(last, 'checked', 'line %d: %s with no PetGameGone() since the last one' % (i + 1, s))
                if s.startswith('Send') or s.startswith('direction'):
                    last = None
            elif re.match(r'Sleep\((Wait|Delay|Loading)\)', s):
                last = None
        code, raw = fn_body(PET_AHK, 'PetGameGone')
        self.assertIn('WinActive("ahk_exe WizardGraphicalClient.exe")', raw)
        self.assertIn('BlockInput("MouseMoveOff")', raw)


class CheatEngineScript(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(LUA, 'rb') as f:
            cls.raw = f.read()
        cls.text = cls.raw.decode('ascii')

    def test_plain_ascii(self):
        self.assertTrue(all(b < 128 for b in self.raw))

    def test_the_setting(self):
        t = self.text
        self.assertRegex(t, r'local s = \{speedhack = 0, speedfactor = 2, speedkeyfast = 2, speedkeynormal = 1\}',
                         "the bot's own default: off")
        self.assertIn('wm.on = s.speedhack == 1', t)
        n = t.replace('\r\n', '\n')
        # (the walking key stays bound and reads the setting when it's pressed: switched on, the first press counts)
        self.assertIn('if fast == normal then\n', n)
        walk = n.split('local function walkKey()\n', 1)[1]
        # (only a read with its speedhack line - a file the bot is just writing leaves the setting as it was)
        self.assertTrue(walk.startswith('  local s, read, seen = readSettings()\n  if read and seen.speedhack then\n    wm.on = s.speedhack == 1\n'
                                        '  end\n  if not wm.on then\n    return\n  end\n'), 'walkKey: the setting first')
        attach = n.split('local function attach()\n', 1)[1]
        self.assertTrue(attach.startswith('  if not wm.on then\n    return\n  end\n'), 'attach: nothing with it off')

    def test_unreadable_said_once_keys_kept(self):
        t = self.text.replace('\r\n', '\n')
        body = t.split('local function bindKeys()\n', 1)[1].split('\nend\n', 1)[0]
        self.assertIn('local s, read = readSettings()', body)
        self.assertRegex(body, r'if wm\.unread == 3 then\s+error\(')
        self.assertRegex(body, r', 0\)\n')
        # (both ways there, how to stop it, and the walking key off only when it is)
        self.assertIn("the bot's folder moved or deleted", body)
        self.assertIn('"autorun\\\\wiz-maxxing.lua in Cheat Engine\'s folder. "', body)
        self.assertIn('(wm.on and "The walking key keeps the settings read last" or "The walking key does nothing', body)
        self.assertRegex(body, r'if wm\.normal ~= nil then\s+return\s+end')
        self.assertIn('return s, false', t)
        self.assertIn('return s, true', t)

    def test_setup_refuses_a_path_cheat_engine_cant_open(self):
        _, raw = fn_body(SETUP_AHK, 'SuInstallCe')
        self.assertLess(raw.index('if (RegExMatch(text, "[^\\x01-\\x7F]"))'), raw.index('ce := CeDir()'))

    def test_elevated_copy_carries_the_text(self):
        code, raw = fn_body(SETUP_AHK, 'SuCePut')
        runas = [ln for ln in raw.splitlines() if '*RunAs' in ln]
        self.assertEqual(len(runas), 1)
        self.assertNotIn('tmp', runas[0], 'the admin command copies nothing from %TEMP%')
        self.assertNotIn('copy /y', raw)
        self.assertIn('[Convert]::FromBase64String(', raw)
        self.assertIn('[IO.File]::WriteAllBytes(" UpPsQuote(dest)', raw)
        self.assertIn('ok := V1FileRead(dest, "UTF-8") == text', raw)
        _, b64 = fn_body(SETUP_AHK, 'SuBase64')
        self.assertEqual(b64.count('0x40000001'), 2, 'CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF')
        self.assertIn('StrPut(text, buf, "UTF-8")', b64)

    def test_only_cheat_engines_own_link(self):
        _, raw = fn_body(SETUP_AHK, 'SuGetCheatEngine')
        self.assertEqual(len(re.findall(r'RegExMatch\(text,', raw)), 1, 'no other .exe link on the page taken for it')
        self.assertIn('cloudfront', raw)


@unittest.skipUnless(ts.lua53 is not None or ts.NEED_LUA, ts.NO_LUPA)
class CheatEngineScenarios(unittest.TestCase):
    """the speedhack setting and a PlayerStats.txt that can't be opened, run in test_speedhack's fake Cheat Engine"""
    ON = 'speedhack:1\r\nspeedfactor:2\r\nspeedkeyfast:2\r\nspeedkeynormal:1\r\n'
    OFF = 'speedhack:0\r\nspeedfactor:2\r\nspeedkeyfast:2\r\nspeedkeynormal:1\r\n'

    @classmethod
    def setUpClass(cls):
        if ts.lua53 is None:
            raise AssertionError(ts.NO_LUPA + ' - WIZ_MAXXING_NEED_LUA is set: the scenarios must run')

    def rig(self, games=(), front=ts.EXPLORER, **kw):
        return ts.Rig(self, games, front, **kw)

    def test_settings_speed_and_keys_with_it_on(self):
        """test_speedhack's test_settings_speed_and_keys with speedhack:1 in each PlayerStats.txt, as the bot writes
        it: the keys, the speed and its at most 50 still read every 2 s"""
        r = self.rig([M], M, stats='speedhack:1\r\nspeedfactor:3\r\nspeedkeyfast:5 ; F17\r\nspeedkeynormal:4\r\n')
        r.factor = 3
        self.assertEqual(r.walk(M, key=ts.F17), 1)
        r.assert_speeds({M: 3})
        self.assertEqual(r.onex(key=ts.F16), 1)
        r.assert_speeds({M: 1})
        self.assertEqual(r.walk(M, key=ts.F14), 0, 'the default walking key, not bound')
        r.set_stats('speedhack:1\r\nspeedfactor:1.5\r\nspeedkeyfast:5\r\nspeedkeynormal:4\r\n')
        r.tick()
        r.walk(M, key=ts.F17)
        r.assert_speeds({M: 1.5}, 'a Settings change within 2 s')
        r.set_stats('speedhack:1\r\nspeedfactor:99\r\nspeedkeyfast:5\r\nspeedkeynormal:4\r\n')
        r.tick()
        r.walk(M, key=ts.F17)
        r.assert_speeds({M: 50}, 'at most 50')
        r.set_stats('speedhack:1\r\nspeedfactor:3\r\nspeedkeyfast:4\r\nspeedkeynormal:4\r\n')
        r.tick()
        self.assertEqual(r.walk(M, key=ts.F16), 1, 'one key for both: the 1x key')
        r.assert_speeds({M: 1}, 'never stuck sped up')
        r.assert_clean()

    def test_off_or_never_set_nothing(self):
        for stats in (self.OFF, 'speedfactor:2\r\nspeedkeyfast:2\r\nspeedkeynormal:1\r\n'):
            r = self.rig([M], M, stats=stats)
            self.assertEqual(r.opened(), 0, 'no game attached with the setting off')
            r.walk(M)
            r.onex()
            r.tick(3)
            r.walk(M)
            r.assert_speeds({M: 1}, "the walking key (another program's F14) speeds nothing")
            self.assertEqual(r.opened(), 0)
            self.assertEqual(r.activations(), {}, 'nothing put into the game')
            r.assert_clean()

    def test_switched_on_the_first_press_counts(self):
        r = self.rig([M], M, stats=self.OFF)
        r.set_stats(self.ON)
        r.walk(M)
        r.assert_speeds({M: 2}, 'switched on in Settings: the bot walks before the next tick')
        r.onex()
        r.assert_speeds({M: 1})
        r.tick(2)
        self.assertEqual(r.opened(), M)
        r.assert_clean()

    def test_switched_off_the_1x_key_stays(self):
        r = self.rig([M], M)
        r.walk(M)
        r.set_stats(self.OFF)
        r.onex('the bot sends 1x as the setting goes off')
        r.assert_speeds({M: 1})
        r.walk(M)
        r.tick(2)
        r.walk(M)
        r.assert_speeds({M: 1}, 'switched off: the walking key does nothing')
        r.set_stats(self.ON)
        r.walk(M)
        r.assert_speeds({M: 2}, 'and on again')
        r.onex()
        r.assert_speeds({M: 1})
        r.assert_clean()

    def test_unreadable_later_said_once_keys_kept(self):
        r = self.rig([M], M)
        r.walk(M)
        r.onex()
        os.remove(r.stats)
        r.tick(2)
        self.assertEqual(r.lua_list('boxes'), [], 'not after 1 or 2 tries (the bot may be just writing it)')
        r.walk(M)
        r.assert_speeds({M: 2}, 'the settings read last kept')
        r.onex()
        r.tick(4)
        boxes = r.lua_list('boxes')
        self.assertEqual(len(boxes), 1, boxes)
        self.assertIn("the bot's folder moved or deleted", boxes[0])
        self.assertIn('autorun\\wiz-maxxing.lua', boxes[0])
        self.assertIn('The walking key keeps the settings read last', boxes[0])
        r.walk(M)
        r.onex()
        r.assert_speeds({M: 1})
        r.assert_clean(boxes=1)

    def test_unreadable_from_the_start_off(self):
        r = self.rig([M], M, start=False)
        os.remove(r.stats)
        r.start()
        r.tick(2)
        boxes = r.lua_list('boxes')
        self.assertEqual(len(boxes), 1, boxes)
        self.assertIn('The walking key does nothing till then', boxes[0])
        r.walk(M)
        r.assert_speeds({M: 1})
        self.assertEqual(r.activations(), {})
        self.assertEqual(r.opened(), 0)
        r.tick(5)
        self.assertEqual(len(r.lua_list('boxes')), 1, 'said once')
        r.assert_clean(boxes=1)


class ReleaseWorkflow(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = tan.read(RELEASE_YML).replace('\r\n', '\n')
        steps = cls.text.split('\n    steps:\n', 1)
        cls.job = steps[0]
        cls.steps = re.split(r'\n(?=      - )', steps[1])

    def step(self, name):
        hits = [s for s in self.steps if re.search(r'^      - name: ' + re.escape(name) + r'\s*$', s, re.M)]
        self.assertEqual(len(hits), 1, name)
        return hits[0]

    def test_no_tabs(self):
        self.assertNotIn('\t', self.text)

    def test_token_only_where_github_is_asked(self):
        job_env = self.job.split('\n    env:\n', 1)[1]
        self.assertNotIn('GH_TOKEN', job_env, 'not in every step')
        with_token = [s.split('\n', 1)[0].strip() for s in self.steps if 'GH_TOKEN: ${{ github.token }}' in s]
        self.assertEqual(with_token, ['- name: Check the version', '- name: Get AutoHotkey v2 and Ahk2Exe',
                                      '- name: Publish the release'])
        for name in ('Check every script loads (AutoHotkey /validate)', 'Build the exes (build.ps1)', 'Zip the release'):
            self.assertNotIn('GH_TOKEN', self.step(name), name + ': runs the downloaded AutoHotkey / Ahk2Exe')
        for s in self.steps:
            if 'GH_TOKEN: ${{ github.token }}' in s:
                self.assertRegex(s, r'\n        env:\n          GH_TOKEN: \$\{\{ github\.token \}\}\n        run: \|')

    def test_checkout_keeps_no_token(self):
        co = [s for s in self.steps if 'actions/checkout@' in s]
        self.assertEqual(len(co), 1)
        self.assertIn('\n        with:\n          persist-credentials: false', co[0])
        check = self.step('Check the version')
        self.assertIn('extraheader=AUTHORIZATION: basic $auth" ls-remote --tags origin', check)

    def test_the_tools_hash_logged(self):
        self.assertIn('Get-FileHash -LiteralPath $zip -Algorithm SHA256', self.step('Get AutoHotkey v2 and Ahk2Exe'))


class Readme(unittest.TestCase):
    def test_update_in_place_said(self):
        self.assertIn('**Update your install in place**', tan.read(README))


if __name__ == '__main__':
    unittest.main()
