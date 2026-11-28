"""test_fix2_ui_misc.py - the 2026-11-27 review's keys, alerts, dashboard, stats and puzzle fixes (the AHK sources read, not
run). Standard library only: python -m unittest test_fix2_ui_misc  (from AutoFarmer\\vision)

Pins: the mode and pick keys (ctx "on") work only with Wizard101 in front - Alt+E/D/S/C/R/L were taken from Chrome and
Word while the bot ran; key capture refuses Alt+Tab, Alt+Space and Ctrl+Esc (not Alt+Esc, the second restart key's
default); a Discord alert is kept from repeating by its kind AND title, and one not sent is said in debug.log; the
dashboard's CPU/RAM row closes the handles of processes it no longer looks at; characters.txt is written to a .tmp and
moved over; PzNext steps back before continuing after planning tiers 1-3; a run's recording leaves out the bot's tries
the way was found still shut after (unless the run's own tries opened it), and a learned way whose tries ran out
counts as failed; a recording's fights get names from one /mobs read; another wizard ("Non-local Player") is no foe and
a fight with no place isn't recorded; VisionStart's failure lines leave the ImageSearch words to a first start, and any
answer resets the helper's fail count."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AF = os.path.dirname(HERE)


def read(name):
    with open(os.path.join(AF, name), encoding='utf-8-sig') as f:
        return f.read().replace('\r\n', '\n')


def function(text, name):
    """the function's body: from its header to its closing brace at one tab"""
    m = re.search(r'^' + name + r'\([^\n]*\)\s*\n', text, re.M)
    assert m, name + ' not found'
    rest = text[m.end():]
    end = re.search(r'^\t}\s*$', rest, re.M)
    assert end, name + ' has no end'
    return rest[:end.end()]


def code(body):
    """the body without ; comments"""
    out = []
    for ln in body.splitlines():
        s = ln.strip()
        if s.startswith(';'):
            continue
        out.append(re.sub(r'\s;\s.*$', '', ln))
    return '\n'.join(out)


class Keys(unittest.TestCase):
    def test_mode_keys_only_in_the_game(self):
        body = code(function(read('Hotkeys.ahk'), 'HkCtxOn'))
        self.assertIn('return BotOn && WinActive("ahk_exe WizardGraphicalClient.exe")', body)

    def test_keys_tab_says_so(self):
        self.assertIn('a.ctx = "on" ? "the bot on, in Wizard101"', read('Hotkeys.ahk'))

    def test_windows_alt_combos_refused(self):
        body = code(function(read('Hotkeys.ahk'), 'HkRefuse'))
        self.assertIn('if (InStr(mods, "!") && (low = "tab" || low = "space"))', body)
        self.assertIn('if (InStr(mods, "^") && !InStr(mods, "!") && !InStr(mods, "#") && (low = "escape" || low = "esc"))', body)
        # (Alt+Esc stays allowed: restart2's own default - Default... on the Keys tab must still take it)
        self.assertIn('def: "!Esc"', read('Hotkeys.ahk'))

    def test_refused_before_the_other_actions_check(self):
        body = code(function(read('Hotkeys.ahk'), 'HkRefuse'))
        self.assertLess(body.index('(low = "tab" || low = "space")'), body.index('for i, a in HkActions()'))


class Alerts(unittest.TestCase):
    def test_same_alert_is_kind_and_title(self):
        body = code(function(read('Alerts.ahk'), 'AlertSend'))
        self.assertIn('same := kind "|" title', body)
        self.assertIn('if (AlertLast.Has(same) && now - AlertLast[same] < 600000)', body)
        self.assertIn('AlertLast[same] := now, AlertLast[""] := now', body)
        self.assertNotIn('AlertLast[kind]', body)
        self.assertIn('if (w.kind = kind && w.title = title)', body)

    def test_a_dropped_alert_is_logged_once(self):
        body = code(function(read('Alerts.ahk'), 'AlertSend'))
        i = body.index('if (AlertLast.Has(same) && now - AlertLast[same] < 600000)')
        block = body[i:body.index('return', i)]
        self.assertIn('DebugLog("Discord: alert', block)
        self.assertIn('AlertLast[same "|said"] := AlertLast[same]', block)


class Dashboard(unittest.TestCase):
    def test_handles_of_processes_gone_are_closed(self):
        body = code(function(read('Dashboard.ahk'), 'DashUsage'))
        i = body.index('gone := []')
        rest = body[i:body.index(';the whole PC') if ';the whole PC' in body else len(body)]
        self.assertIn('if (!looked.Has(pid))', rest)
        self.assertIn('DllCall("CloseHandle", "Ptr", procs[pid])', rest)
        self.assertIn('procs.Delete(pid)', rest)
        self.assertIn('last.Delete(pid)', rest)
        # (deleted after the walk over procs, not during it)
        self.assertLess(body.index('for pid, h in procs'), body.index('for each, pid in gone'))
        # (only one that has exited: carry mode's game PID swaps every turn - a live one keeps its handle and times)
        self.assertIn('if (!h || (DllCall("GetExitCodeProcess", "Ptr", h, "UInt*", &code) && code != 259))', rest)


class Stats(unittest.TestCase):
    def test_characters_written_whole(self):
        body = code(function(read('StatsRead.ahk'), 'StatsNoteSchool'))
        self.assertNotIn('V1Do(FileDelete, path)\n', body)
        self.assertIn('V1Do(FileDelete, path ".tmp")', body)
        self.assertRegex(body, r'if \(V1Do\(FileAppend, .+, path "\.tmp"\)\s*\n\s*\|\| V1Do\(FileMove, path "\.tmp", path, 1\)\)')


class Puzzle(unittest.TestCase):
    def test_first_new_try_not_skipped(self):
        body = code(function(read('Puzzle.ahk'), 'PzNext'))
        self.assertRegex(body, r'PzPlan\(r, "123"\)\s*\n\s*if \(r\.ci <= r\.cands\.Length\)\s*\n\s*\{\s*\n\s*r\.ci -= 1\s*\n\s*continue')

    def test_shut_marks_the_recording(self):
        text = read('Puzzle.ahk')
        self.assertIn('PzRecShut(r)', code(function(text, 'PzShut')))
        body = code(function(text, 'PzRecShut'))
        self.assertIn('rec.shut := rec.steps.Length', body)
        self.assertIn('PzRecWrite()', body)
        # (kept by a restart: the rec line's 12th field)
        self.assertIn('"|" V1N(rec.pulled) "|" V1N(rec.shut) "`r`n"', code(function(text, 'PzRecWrite')))
        self.assertIn('shut: V1N(PzNumOf(V1At(f, 12)))', code(function(text, 'PzRecResume')))
        self.assertIn('shut: 0', code(function(text, 'PzRecStart')))
        # (the rewrite keeps the walked points - PzRecResume reads them back)
        write = code(function(text, 'PzRecWrite'))
        self.assertRegex(write, r'for i, w in rec\.walks\s*\n\s*t \.= PzRecLine\(w\) "`r`n"')

    def test_hold_marks_the_recording(self):
        body = code(function(read('Puzzle.ahk'), 'PuzzleEnd'))
        hold = body[body.index('PzRun := ""\n\tif (IsObject(r.learned)'):]
        self.assertLess(hold.index('PzRecShut(r)'), hold.index('h := V1Obj({zone: r.zone'))

    def test_solution_leaves_out_failed_bot_tries(self):
        text = read('Puzzle.ahk')
        body = code(function(text, 'PzSolution'))
        self.assertIn('(i <= V1N(rec.pulled) || i <= shut)', body)
        # (only when a step of yours came after them - else the bot's tries are all that could have opened it)
        # (fix2 last pass: after the bot's last try before the shut look - a held look moves rec.shut past your steps -
        # and only a step of yours PzSolution keeps: a lost fight, a Crown or enter X opened nothing)
        self.assertRegex(body, r'shut := 0\s*\n\s*if \(rec\.run && !rec\.byRun && V1N\(rec\.shut\)\)')
        self.assertRegex(body, r'if \(i <= V1N\(rec\.shut\) && e\.who = "bot"\)\s*lastBot := i')
        self.assertIn('if (i > lastBot && e.who = "you" && (!rec.openAt || e.at <= rec.openAt) && PzStepKept(e, rec))', body)
        kept = code(function(text, 'PzStepKept'))
        self.assertIn('!PzFightIsGoal(e, rec)', kept)
        self.assertIn('e.crown', kept)
        self.assertLess(body.index('shut := V1N(rec.shut)'), body.index('(i <= V1N(rec.pulled) || i <= shut)'))
        end = code(function(text, 'PuzzleEnd'))
        self.assertIn('PzRec.byRun := r.probeOnly ? 0 : 1', end)
        self.assertLess(end.index('PzRec.byRun :='), end.index('PzRecEnd(true'))

    def test_learned_way_run_out_counts_as_failed(self):
        body = code(function(read('Puzzle.ahk'), 'PuzzleEnd'))
        hold = body[body.index('PzRun := ""\n\tif (IsObject(r.learned)'):]
        self.assertIn('if (IsObject(r.learned) && !r.learnedOut)', hold)
        self.assertIn('PzLearnedResult(r.learned, false)', hold)

    def test_recorded_fights_get_names(self):
        text = read('Puzzle.ahk')
        body = code(function(text, 'PzTplFill'))
        self.assertIn('NavMobs(rec.line, 600)', body)
        self.assertIn('sq := PzSaveQuiet()', body)
        self.assertIn('PzRestoreQuiet(sq)', body)
        self.assertIn('!PzTpl.Has(m.template)', body)
        # (as a recording starts every one read is noted afresh - an old quest flag doesn't linger)
        self.assertRegex(body, r'if \(all\)\s*\n\s*\{\s*\n\s*PzTplNote\(ms\)\s*\n\s*return')
        self.assertRegex(body, r'global [^\n]*\bPzTpl\b')
        end = code(function(text, 'PzRecEnd'))
        self.assertLess(end.index('PzTplFill(rec)'), end.index('PzSolution(rec)'))
        self.assertIn('PzTplFill(rec, true)', code(function(text, 'PzRecStart')))

    def test_other_wizards_and_placeless_fights(self):
        text = read('Puzzle.ahk')
        log = code(function(text, 'PzLogLineDo'))
        self.assertIn('if (m[2] = "Local Player" || m[2] = "Non-local Player")', log)
        self.assertIn('if (m[2] = "Non-local Player")\n\t\t\t\treturn\n\t\t\td.outs += 1', log)
        self.assertIn('if (e.kind = "fight" && !PzXY(e))', code(function(text, 'PzRecOnEntry')))
        sol = code(function(text, 'PzSolution'))
        self.assertRegex(sol, r'if \(e\.kind = "fight"\)\s*\n\s*\{\s*\n\s*if \(!PzXY\(e\)\)\s*\n\s*continue')


class Vision(unittest.TestCase):
    def test_restart_failure_lines_leave_imagesearch_to_retry(self):
        body = code(function(read('Vision.ahk'), 'VisionStart'))
        self.assertIn('vsThen := V1N(VisionRestarts) ? "" : " - cards are found with ImageSearch"', body)
        # (every failure line says it only through vsThen)
        self.assertEqual(body.count('cards are found with ImageSearch'), 2, 'vsThen itself and the 8 s line\'s ", cards..." form')
        self.assertLess(body.index('vsThen :='), body.index('py := VisionPython()'))

    def test_any_answer_resets_the_fail_count(self):
        body = code(function(read('Vision.ahk'), 'VisionGet'))
        ok = body[body.index('throw text'):body.index('return text = "" ? " " : text')]
        self.assertIn('VisionFails := 0', ok)
        self.assertNotIn('if (!noCount)\n\t\t\tVisionFails := 0', ok)


if __name__ == '__main__':
    unittest.main()
