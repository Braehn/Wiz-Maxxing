"""test_fix_visionahk.py - the vision helper is paused, not switched off for good, when it stops answering (Vision.ahk read,
not run). Standard library only: python -m unittest test_fix_visionahk  (from AutoFarmer\\vision)

Before: a counted timeout added 1 to VisionFails in VisionGet's poll loop and 1 more in its catch, so two slow /cards
in a row set VisionOn := 0 - and nothing ever set it back (only VisionStart, at the bot's start), nor restarted a helper
whose process had gone. Every game-memory feature (the walker's memory, mobs, the GUI checks, selling, the hand...) was
off for the rest of the run, while debug.log only said the cards were found with ImageSearch from now on. Pins: a
timeout counts once; 3 counted failures, or the process gone, go through VisionBackOff (VisionOn 0 - callers keep their
fast "no answer" - and a one-shot VisionRetry timer); VisionRetry starts with V1Thread, re-probes /ping, restarts the
helper with VisionStart when it's gone or still doesn't answer, at most 3 times in 30 min; the new globals start blank
in VisionBlank; the log says the game-memory features are paused."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
VISION_AHK = os.path.join(os.path.dirname(HERE), 'Vision.ahk')


def read():
    with open(VISION_AHK, encoding='utf-8-sig') as f:
        return f.read()


def function(text, name):
    """the function's body: from its header to the next line that starts a new function (a name at column 0 then "(")"""
    m = re.search(r'^' + name + r'\([^\n]*\)\s*\n', text, re.M)
    assert m, name + ' not found'
    rest = text[m.end():]
    end = re.search(r'^\t}\s*$', rest, re.M)
    assert end, name + ' has no end'
    return rest[:end.end()]


def code(body):
    """the body without ; comments (full lines and trailing ones outside strings - good enough here)"""
    out = []
    for ln in body.splitlines():
        s = ln.strip()
        if s.startswith(';'):
            continue
        out.append(re.sub(r'\s;\s.*$', '', ln))
    return '\n'.join(out)


class TimeoutCountsOnce(unittest.TestCase):
    def test_no_increment_in_the_poll_loop(self):
        body = code(function(read(), 'VisionGet'))
        self.assertEqual(len(re.findall(r'VisionFails\s*:=\s*V1N\(VisionFails\)\s*\+\s*1|\+\+VisionFails|VisionFails\s*\+=', body)), 1,
                         'VisionFails must be added to in one place only (the catch)')
        loop = body[body.index('while (!req.WaitForResponse(0))'):body.index('text := req.ResponseText')]
        self.assertNotIn('VisionFails', loop)

    def test_backoff_instead_of_switching_off(self):
        body = code(function(read(), 'VisionGet'))
        self.assertNotIn('VisionOn := 0', body)
        self.assertNotIn('from now on', body)
        self.assertEqual(body.count('VisionBackOff('), 2, 'the process gone and 3 failures in a row both back off')
        self.assertRegex(body, r'VisionFails >= 3\)\s*\n\s*VisionBackOff\(')


class BackOff(unittest.TestCase):
    def test_backoff_pauses_and_arms_the_retry(self):
        body = code(function(read(), 'VisionBackOff'))
        self.assertRegex(body, r'global [^\n]*\bVisionOn\b')
        self.assertRegex(body, r'global [^\n]*\bVisionRetryAt\b')
        self.assertIn('VisionOn := 0', body)
        self.assertRegex(body, r'SetTimer\(VisionRetry, -delayMs\)')
        # (the log says what's actually off)
        self.assertIn('game-memory features', body)
        self.assertIn('paused', body)

    def test_retry_is_a_thread_with_its_own_errorlevel(self):
        body = function(read(), 'VisionRetry')
        first = [ln.strip() for ln in body.splitlines() if ln.strip() not in ('', '{') and not ln.strip().startswith(';')][0]
        self.assertEqual(first, 'local v1Keep := V1Thread() ; (v1: each thread had its own ErrorLevel)')

    def test_retry_pings_restarts_and_limits(self):
        body = code(function(read(), 'VisionRetry'))
        for name in ('VisionOn', 'VisionFails', 'VisionRetryAt', 'VisionStuck', 'VisionRestarts', 'VisionRestartsFrom'):
            self.assertRegex(body, r'global [^\n]*\b' + name + r'\b', name)
        self.assertIn('VisionGet("/ping", 1000, true)', body)
        self.assertIn('VisionOn := 1', body)
        self.assertIn('VisionStart()', body)
        self.assertIn('ProcessClose(VisionPid)', body)
        self.assertRegex(body, r'V1N\(VisionRestarts\) >= 3')
        self.assertIn('1800000', body)
        # (every way out that leaves it paused arms the timer again - never a tight loop: 45 s at least, but the restart
        # put off while in a battle, 2 s - no ping then, see RestartAtASafePoint)
        self.assertGreaterEqual(body.count('SetTimer(VisionRetry, -'), 4)
        self.assertNotRegex(body, r'SetTimer\(VisionRetry, -(?!45000|vrWait|2000\))')
        self.assertIn('Max(VisionRestartsFrom + 1800000 - A_TickCount, 45000)', body)
        # (BattleRec.ahk's hello to the new helper: reached by name - Vision.ahk doesn't need BattleRec.ahk)
        self.assertIn('if (V1IsFunc("BrecHello"))', body)
        # (sent "later": BrecRoundClose sends it out of a round, never between a round's clicks)
        self.assertIn('%"BrecHello"%.Call("later")', body)
        self.assertNotIn('%"BrecHello"%.Call()', body)

    def test_pid_blank_never_asks_for_this_process(self):
        # (ProcessExist("") is this script's own pid)
        body = code(function(read(), 'VisionRetry'))
        self.assertIn('(VisionPid && ProcessExist(VisionPid))', body)


class RestartAtASafePoint(unittest.TestCase):
    """the restart (ProcessClose + VisionStart: seconds, up to ~14) runs in this timer thread and holds up the thread it
    interrupted - the walker with W held, a battle round's clicks"""

    def test_put_off_in_a_battle_a_round_or_the_mouse_lock(self):
        body = code(function(read(), 'VisionRetry'))
        m = re.search(r'if \(inbattle == 1 \|\| \(IsSet\(MouseLocked\) && MouseLocked\) \|\| \(IsSet\(BrecOpen\) && BrecOpen\)\)', body)
        self.assertTrue(m, 'the restart waits while in a battle, a round open or the mouse locked')
        wait = body[m.end():body.index('return', m.end())]
        self.assertIn('SetTimer(VisionRetry, -2000)', wait)
        # (before the restart itself and its count)
        self.assertLess(m.start(), body.index('VisionRestarts := V1N(VisionRestarts) + 1'))
        self.assertLess(m.start(), body.index('VisionStart()'))

    def test_no_ping_once_the_restart_is_decided(self):
        # (a 1 s ping each 2 s while it waits for the battle's end would hold up the battle)
        body = code(function(read(), 'VisionRetry'))
        self.assertIn('if (vrUp && V1N(VisionStuck) < 2)', body)

    def test_walker_keys_let_go_before_the_restart(self):
        body = code(function(read(), 'VisionRetry'))
        i = body.index('%"ReleaseKeys"%.Call(true)')
        self.assertIn('if (V1IsFunc("ReleaseKeys") && (KeysDown || HeldW))', body)
        self.assertLess(i, body.index('VisionStart()'))
        self.assertLess(i, body.index('ProcessClose(VisionPid)'))

    def test_a_reused_pid_isnt_pinged_or_stopped(self):
        body = code(function(read(), 'VisionRetry'))
        self.assertIn('try vrUp := (ProcessGetName(VisionPid) = "pythonw.exe") ? 1 : 0', body)
        self.assertRegex(body, r'if \(vrUp\)\s*\n\s*ProcessClose\(VisionPid\)')

    def test_client_pinned_again_after_the_restart(self):
        text = read()
        retry = code(function(text, 'VisionRetry'))
        ok = retry[retry.index('if (VisionStart())'):]
        self.assertIn('VisionRepin()', ok[:ok.index('return')])
        body = code(function(text, 'VisionRepin'))
        self.assertRegex(body, r'global [^\n]*\bCarryPin\b')
        self.assertIn('CarryPin := ""', body)
        self.assertIn('VisionGet("/client?pids=" CarryMainPid "," CarryPid, 1500, true)', body)
        self.assertIn('VisionGet("/client?pid=" vpP, 1500, true)', body)
        self.assertIn('vpP := CarryTurn ? CarryPid : CarryMainPid', body)
        self.assertIn('MainPin()', body)
        # (no window brought to the front from a timer - CarryFront would activate one)
        self.assertNotIn('CarryFront(', body)


class Globals(unittest.TestCase):
    def test_new_globals_declared_and_blank(self):
        text = read()
        blank = function(text, 'VisionBlank')
        for name in ('VisionRetryAt', 'VisionStuck', 'VisionRestarts', 'VisionRestartsFrom'):
            self.assertRegex(text, r'(?m)^global [^\n]*\b' + name + r'\b', name)
            self.assertRegex(blank, r'\b' + name + r' := ""', name)

    def test_status_for_the_dashboard(self):
        body = code(function(read(), 'VisionStatus'))
        self.assertIn('return "on"', body)
        self.assertIn('paused', body)
        self.assertIn('return "off"', body)

    def test_crlf_kept(self):
        with open(VISION_AHK, 'rb') as f:
            raw = f.read()
        self.assertEqual(raw.count(b'\n'), raw.count(b'\r\n'))


if __name__ == '__main__':
    unittest.main()
