"""test_fix_setup.py - Setup and the updater after the 2026-11 review. python -m unittest test_fix_setup  (from
AutoFarmer\\vision)

- SuOwnFolder's list of the bot's own top-level names (Setup.ahk) takes every name a release ships: without CheatEngine\\,
  CheatEngine.ahk, GameRect.ahk and StreamView.ahk in it every unzipped release was "not the bot's own", so "Install to
  your Programs folder" and the download's clean-up never ran. Read from Setup.ahk and run on git ls-files' top-level
  names (all but what release.yml leaves out) and the exes release.yml adds, so a new file can't slip past it again;
- the repo the updater, Setup's Version list, the token test and Report a bug use is UpRepo()'s - the account's new name,
  Braehn/Wiz-Maxxing - and no GitHub /repos/ address is made any other way;
- Setup run from a fresh download never points your install's shortcuts, watcher, PATH or Cheat Engine script at that
  blank copy by itself: your install somewhere else (SuOtherInstall: what those start, the bot has run there) is what
  "Update your install in place" puts this version into, as an update does - settings and learned cards kept: the
  one the bot ran from last, never an old folder over this one when this one's your install (SuStartedHere), and its
  own data kept unless you say this folder's is yours; your install itself is never moved by itself, nor a separate
  copy made beside one Setup can't copy over; and never while the bot's own update is going (UpOnlyOne)."""
import os
import re
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AF = os.path.dirname(HERE)              # the AutoFarmer folder
ROOT = os.path.dirname(AF)              # the repository
SETUP_AHK = os.path.join(ROOT, 'Setup.ahk')
UPDATER_AHK = os.path.join(ROOT, 'Updater.ahk')
RELEASE_YML = os.path.join(ROOT, '.github', 'workflows', 'release.yml')

sys.path.insert(0, HERE)
import test_ahk_names as tan            # noqa: E402  (its AutoHotkey function finder)


def fn_body(path, name):
    """a function's code lines (strings blanked, comments gone) - and its raw text, strings kept"""
    text = tan.read(path)
    for n, params, line, body in tan.functions(text):
        if n == name:
            raw = text.splitlines()[line - 1:body[-1][0]] if body else []
            return '\n'.join(c for _, c in body), '\n'.join(raw)
    return None, None


def own_folder_regex():
    """SuOwnFolder's pattern for the bot's own top-level names, as Python's re reads it (AutoHotkey's i) = re.I)"""
    _, raw = fn_body(SETUP_AHK, 'SuOwnFolder')
    m = re.search(r'RegExMatch\(A_LoopFileName, "i\)([^"]+)"\)', raw or '')
    return re.compile(m.group(1), re.I) if m else None


def top_level_names():
    """git ls-files' top-level names, but the ones release.yml's zip leaves out; None when this isn't a git checkout"""
    try:
        out = subprocess.run(['git', '-c', 'core.quotepath=false', 'ls-files'], cwd=ROOT, capture_output=True,
                             text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    names = {f.split('/')[0] for f in out.splitlines() if f.strip()}
    if not names:
        return None
    left_out = set(re.findall(r"\$_ -ne '([^']+)'", tan.read(RELEASE_YML)))
    return sorted(names - left_out)


class OwnFolder(unittest.TestCase):
    def setUp(self):
        self.rx = own_folder_regex()
        self.assertIsNotNone(self.rx, "SuOwnFolder's RegExMatch on A_LoopFileName not found in Setup.ahk")

    def test_release_yml_leaves_out_todo_only(self):
        # (what the test leaves out is what the zip does - read from release.yml, not guessed)
        self.assertEqual(set(re.findall(r"\$_ -ne '([^']+)'", tan.read(RELEASE_YML))), {'TODO.md'})

    def test_every_top_level_name_a_release_ships_is_the_bots(self):
        names = top_level_names()
        if names is None:
            self.skipTest('not a git checkout')
        bad = [n for n in names if not self.rx.match(n)]
        self.assertEqual(bad, [], "Setup.ahk SuOwnFolder doesn't take these top-level names a release ships - "
                                  "every unzipped release would be 'not the bot's own'")

    def test_the_exes_release_adds_and_what_the_bot_makes(self):
        exes = re.findall(r"'([^'\\]+\.exe)'", re.search(r"foreach \(\$exe in ([^)]*)\)", tan.read(RELEASE_YML)).group(1))
        self.assertIn('Setup.exe', exes)
        for n in exes + ['version.txt', 'updater.ini', 'updater.log', 'backups', 'Wiz-Maxxing.exe.old',
                         'StreamView.exe', 'desktop.ini', 'Thumbs.db']:
            self.assertTrue(self.rx.match(n), n)

    def test_the_four_that_were_missing(self):
        for n in ['CheatEngine', 'CheatEngine.ahk', 'GameRect.ahk', 'StreamView.ahk', 'cheatengine']:
            self.assertTrue(self.rx.match(n), n)

    def test_other_things_still_refused(self):
        # (a folder with your own things in it is never copied in or offered to the Recycle Bin)
        for n in ['Photos', 'notes.txt', 'CheatEngine2', 'GameRect.ahk.txt', 'xAutoFarmer', 'StreamView.txt',
                  'TODO.md', 'fix.patch', 'Wiz-Maxxing-v1.14.5.zip']:
            self.assertIsNone(self.rx.match(n), n)


class Repo(unittest.TestCase):
    def test_uprepo_is_the_new_name(self):
        _, raw = fn_body(UPDATER_AHK, 'UpRepo')
        self.assertIn('return "Braehn/Wiz-Maxxing"', raw)

    def test_old_owner_nowhere(self):
        for f in tan.ahk_files():
            self.assertNotIn('joshuasbraincells', tan.read(f).lower(), f)

    def test_every_repos_address_goes_through_uprepo(self):
        uses = 0
        for f in tan.ahk_files():
            for n, ln in enumerate(tan.read(f).splitlines(), 1):
                if ln.lstrip().startswith(';'):
                    continue
                for m in re.finditer(r'"/repos/', ln):
                    uses += 1
                    self.assertRegex(ln[m.start():], r'^"/repos/" UpRepo\(\) "/', '%s:%d' % (f, n))
                self.assertNotRegex(ln, r'(?i)github\.com/repos/|api\.github\.com/[^"]*/Wiz-Maxxing', '%s:%d' % (f, n))
        # the update check, the token test, Report a bug, Setup's Version list
        self.assertGreaterEqual(uses, 4)


class NoRepointing(unittest.TestCase):
    def body(self, name):
        code, raw = fn_body(SETUP_AHK, name)
        self.assertIsNotNone(code, name + ' not found in Setup.ahk')
        return code, raw

    def test_other_install_is_where_the_shortcuts_go_and_the_bot_ran(self):
        code, raw = self.body('SuEntryDirs')
        for must in ['A_Programs "\\Wiz-Maxxing\\Wiz-Maxxing.lnk"', 'A_Desktop "\\Wiz-Maxxing.lnk"', 'WatchLink()',
                     'App Paths\\Wiz-Maxxing.exe', 'FileGetShortcut', 'dirs.Push(dir)']:
            self.assertIn(must, raw, must)
        code, raw = self.body('SuOtherInstall')
        for must in ['SuEntryDirs()', '!SuSamePath(dir, A_ScriptDir)', 'FileExist(dir "\\AutoFarmer\\Autofarmer.ahk")']:
            self.assertIn(must, raw, must)

    def test_other_install_the_one_run_last_never_over_this_one(self):
        # (an old folder one shortcut still starts is never "your install" over the one the rest start and the bot
        # ran from - nor the first found over the one the bot ran from last)
        code, raw = self.body('SuOtherInstall')
        self.assertRegex(code, r'(?m)^\s*if \(SuStartedHere\(\)\)\s*\n\s*return ""', 'this folder your install: none other')
        self.assertIn('V1Gt(at, bestAt)', raw)
        self.assertIn('best := dir, bestAt := at', raw)
        self.assertNotRegex(code, r'return dir\b', 'not the first found')
        code, raw = self.body('SuStartedHere')
        for must in ['here := SuLastRun(A_ScriptDir)', 'if (!V1Gt(here, 0))', 'SuEntryDirs()', 'SuSamePath(dir, A_ScriptDir)',
                     # (not your install when another folder your links start has run since)
                     'V1Gt(SuLastRun(dir), here))', 'return found']:
            self.assertIn(must, raw, must)

    def test_install_dir_never_a_git_checkout_or_a_folder_of_yours(self):
        code, raw = self.body('SuInstallDir')
        for must in ['SuOtherInstall()', 'FileExist(other "\\.git") = ""', 'SuOwnFolder(other, false) = ""',
                     'return SuHome()', 'SuSamePath(A_ScriptDir, SuHome())']:
            self.assertIn(must, raw, must)

    def test_install_updates_that_install_in_place(self):
        code, raw = self.body('SuInstallHome')
        self.assertIn('home := SuInstallDir()', raw)
        self.assertNotIn('home := SuHome()', raw)
        # (over an install there: UpCopy - yours kept - and the data the bot used last kept in use, the other saved)
        self.assertIn('UpCopy(from, home, rollback)', raw)
        self.assertIn('SuCopyMine', raw)
        _, vt = self.body('SuVerTarget')
        self.assertIn('SuInstallDir()', vt)

    def test_the_repointing_rows_arent_ticked_for_your_install(self):
        code, raw = self.body('SuCheck')
        self.assertIn('home := SuInstallDir()', raw)
        self.assertIn('other := SuOtherInstall()', raw)
        # each row that would point your install's entry at this folder: not wanted when it's your install's
        for box, wanted in [('SuSm', '!smOther'), ('SuSh', '!scOther'), ('SuPa', '!paOther'),
                            ('SuWa', 'WatchIsOn() && !waOther'), ('SuCe', 'ceIn && !ceOther')]:
            m = re.search(r'SuShow\("%s", .*, tick, ([^\n]*)\)\s*$' % box, raw, re.M)
            self.assertIsNotNone(m, box)
            self.assertEqual(m.group(1), wanted, box)
        for v, check in [('smOther', 'SuLinkHere(A_Programs "\\Wiz-Maxxing\\Wiz-Maxxing.lnk", other)'),
                         ('scOther', 'SuLinkHere(A_Desktop "\\Wiz-Maxxing.lnk", other)'),
                         ('paOther', 'SuPathFor(other)'), ('waOther', 'SuLinkHere(WatchLink(), other)'),
                         ('ceOther', 'CeScriptText(other)')]:
            self.assertRegex(raw, r'%s := [^\n]*other != "" && [^\n]*%s' % (v, re.escape(check)), v)
        self.assertIn('"Update your install in place"', raw)

    def test_your_install_itself_never_moved_by_itself(self):
        # (run from the install your shortcuts start, the bot ran there: OK, not ticked - no copy to the Programs
        # folder, no re-pointing, no Recycle Bin offer unless you tick it)
        code, raw = self.body('SuCheck')
        m = re.search(r'else if \(SuStartedHere\(\)\)\s*\n\s*SuShow\("SuIn", "SuInS", (\w+), [^\n]*, tick\)\s*$', raw, re.M)
        self.assertIsNotNone(m, 'SuCheck: the SuStartedHere branch')
        self.assertEqual(m.group(1), 'true')
        # (before the ones that would tick it)
        self.assertLess(raw.index('SuStartedHere()'), raw.index('"runs from "'))
        self.assertLess(raw.index('SuStartedHere()'), raw.index('"this version put over your install'))

    def test_install_somewhere_setup_cant_copy_over_isnt_a_silent_copy(self):
        # (your install a git checkout or a folder of yours: Install would make a separate copy nothing starts - not
        # ticked by itself, and said why)
        code, raw = self.body('SuCheck')
        m = re.search(r'else if \(other != "" && !SuSamePath\(other, home\)\)\s*\n\s*SuShow\("SuIn", [^\n]*, tick, false\)\s*$', raw, re.M)
        self.assertIsNotNone(m, 'SuCheck: the branch for your install where Setup cannot copy over')
        self.assertIn('a separate copy in', m.group(0))
        self.assertLess(raw.index('other != "" && !SuSamePath(other, home)'), raw.index('"runs from "'))

    def test_your_install_keeps_its_data_unless_you_say(self):
        code, raw = self.body('SuInstallHome')
        self.assertIn('keepHome := false', raw)
        # (asked for any install there the bot has run from - your Programs folder's too - and never for a first install)
        # (never when this folder is your install itself - moved to your Programs folder: its own data, unasked)
        self.assertIn('if (!SuStartedHere() && FileExist(home "\AutoFarmer\Autofarmer.ahk") && V1Gt(SuLastRun(home), 0) && V1Gt(SuLastRun(A_ScriptDir), SuLastRun(home)))', raw)
        # (the update lock taken only past the questions, before the bots are closed)
        self.assertLess(raw.index('keepHome := msgResult = "No"'), raw.index('if (!UpOnlyOne(false))'))
        self.assertLess(raw.index('if (!UpOnlyOne(false))'), raw.index('UpCloseBots(A_ScriptDir)'))
        # (Yes/No, the question icon, No the default button, on top)
        self.assertIn('"Wiz-Maxxing setup", 262436)', raw)
        self.assertEqual(262436, 262144 + 256 + 32 + 4)
        self.assertIn('keepHome := msgResult = "No"', raw)
        self.assertIn('oldWins := !keepHome && V1Gt(SuLastRun(A_ScriptDir), SuLastRun(home))', raw)
        # (asked before anything's closed or copied)
        self.assertLess(raw.index('262436'), raw.index('UpCloseBots(A_ScriptDir)'))
        _, w = self.body('SuWhen')
        self.assertIn('V1Gt(at, 0) ? FormatTime(at, "yyyy-MM-dd HH:mm") : "never"', w)

    def test_install_waits_for_the_bots_own_update(self):
        # (an automatic update waiting for the bot to close would write into the same install at once)
        code, raw = self.body('SuInstallHome')
        self.assertIn('if (!UpOnlyOne(false))', raw)
        self.assertLess(raw.index('UpOnlyOne(false)'), raw.index('UpCloseBots(home)'))
        self.assertLess(raw.index('UpOnlyOne(false)'), raw.index('UpCopy(from, home, rollback)'))
        self.assertGreater(raw.index('UpOnlyOne(false)'), raw.index('"installed here already"'))

    def test_the_download_offered_is_never_the_install(self):
        code, raw = self.body('SuOfferDelete')
        self.assertIn('home := A_ScriptDir', raw)
        self.assertIn('SuSamePath(old, SuHome())', raw)

    def test_the_watcher_closed_for_the_copy_comes_back(self):
        code, raw = self.body('SuMovedPrep')
        self.assertIn('(WatchIsOn() && SuLinkHere(WatchLink()))', raw)


if __name__ == '__main__':
    unittest.main()
