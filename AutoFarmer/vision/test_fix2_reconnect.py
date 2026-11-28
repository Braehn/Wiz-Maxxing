"""test_fix2_reconnect.py - the 2026-11-27 review's Reconnect and Network tab fixes (the AHK sources read, not run; the
rules they follow mirrored here and run on the cases seen). Standard library only:
python -m unittest test_fix2_reconnect  (from AutoFarmer\\vision)

Pins: typing the saved login in goes test (zq7) read back -> username -> read back -> the Password box -> xqz not in the
Account box -> xqz taken off and the username still whole -> password -> the Account box still the username -> Enter, and
stops at every step - nothing more typed, Enter never - when the bot's switched off (F6), auto-reconnect is, you touch the
keyboard or mouse with the game in front, or the game doesn't take the keys (RcChars false on the first that isn't taken
in a second); a field clicked near its right end, so the backspaces clear all of it; the Account field from the game's
memory only when its GUI root is the shape of the game area (2026-11-21: 1920x1200 vs the 1920x1080 the game drew - the
field put on the Password box); the read-back says how much it read, never what; a login box's words never logged;
"Ban" only a word of its own in a message box's key (not GUI_BankEquipped); a login turned down by its own words, not by
any "account"; a message box while logging in with another Wizard101 open taken as this one's only when the game's memory
shows one up; the game the bot started itself not taken for closed while the picked main (Alt+M) is gone; no bringing the
game to the front while the PC's screen is locked or its remote session disconnected, and "couldn't bring the game to the
front" said once per state; the game's log read quietly while the bot's off (ReconnectOff); the Network tab's picture not
loaded again while it's the same."""
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
    """the body without ; comments (a whole-line one, or one after a space or tab)"""
    out = []
    for ln in body.splitlines():
        if ln.strip().startswith(';'):
            continue
        out.append(re.sub(r'[ \t];.*$', '', ln))
    return '\n'.join(out)


def ahk_round(x):
    """AutoHotkey's Round: half away from zero"""
    return int(x + 0.5) if x >= 0 else -int(-x + 0.5)


def ahk_rx(pattern):
    """an AutoHotkey regex's options ("i)") as Python's"""
    m = re.match(r'^([imsx]*)\)', pattern)
    if not m:
        return re.compile(pattern)
    flags = 0
    for c in m.group(1):
        flags |= {'i': re.I, 'm': re.M, 's': re.S, 'x': re.X}[c]
    return re.compile(pattern[m.end():], flags)


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        row = [i]
        for j, cb in enumerate(b, 1):
            row.append(min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = row
    return prev[-1]


def line_dist(lines, text):
    """RcLineDist's rule on lines of text read: (best, withX) - 99 nothing like it"""
    want = re.sub(r'\s', '', text.lower())
    best, with_x = 99, 99
    for ln in lines:
        raw = re.sub(r'\s', '', ln.strip().lower())
        no_acct = re.sub(r'^account:?', '', raw)
        for seen in (raw, no_acct, re.sub(r'[1li|!]$', '', raw), re.sub(r'[1li|!]$', '', no_acct)):
            if seen == '' or abs(len(seen) - len(want)) > 4:
                continue
            best = min(best, edit_distance(seen, want))
            with_x = min(with_x, edit_distance(seen, want + 'xqz'))
    return best, with_x


class LoginOrder(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rc = read('Reconnect.ahk')
        cls.start = code(function(cls.rc, 'RcStartStep'))

    def steps(self):
        marks = ['RcLoginTest(rcField, gameWin, &rcBg, rcGoAt, rcFront, &rcHalt, &rcRead)', 'RcChars(gameWin, loginUser)',
                 'RcLoginFocus(rcPwAt, "Password")', 'RcChars(gameWin, "xqz")', 'RcChars(gameWin, "", 3)',
                 'RcChars(gameWin, loginPass)', 'RcChars(gameWin, Chr(13))', 'RcSet("login"']
        at = [self.start.find(m) for m in marks]
        for m, i in zip(marks, at):
            self.assertGreater(i, 0, m)
        return marks, at

    def test_the_order(self):
        marks, at = self.steps()
        self.assertEqual(at, sorted(at), marks)
        # (each once: no second way round a check)
        for m in marks[1:7]:
            self.assertEqual(self.start.count(m), 1, m)

    def test_each_step_read_back_and_halted_before_the_next(self):
        marks, at = self.steps()
        # (the username, the test letters - the Password box's click and xqz one step -, the 3 backspaces, the password)
        for k in (1, 3, 4, 5):
            seg = self.start[at[k]:at[k + 1]]
            self.assertIn('RcLineDist(loginUser, gameWin, &rcDistX, rcField)', seg, marks[k])
            self.assertIn('rcHalt := RcLoginHalt(rcGoAt, rcFront, rcOk)', seg, marks[k])
            self.assertIn('return RcLoginCut(rcHalt)', seg, marks[k])
            # (the halt looked at before the read-back's verdict - a read spoilt by your keys isn't the login's fault)
            self.assertLess(seg.index('RcLoginHalt('), seg.index('return RcLoginHelp('), marks[k])
        # (after the test, before anything of the login)
        seg = self.start[at[0]:at[1]]
        self.assertIn('if (rcHalt != "")', seg)
        self.assertIn('return RcLoginCut(rcHalt)', seg)

    def test_halt_starts_after_the_idle_check(self):
        idle = self.start.index('if (RcGameActive() && UserIdle() < (RcBoxFound ? 30000 : 3000))')
        go = self.start.index('rcGoAt := A_TickCount, rcFront := RcGameActive()')
        self.assertLess(idle, go)
        self.assertLess(go, self.start.index('RcLoginTest('))

    def test_xqz_taken_off_before_the_box_is_cleared_for_the_password(self):
        three = self.start.index('rcOk := RcChars(gameWin, "", 3)')
        forty = self.start.index('rcOk := RcChars(gameWin, "", 40) && RcChars(gameWin, loginPass)')
        self.assertLess(three, forty)
        between = self.start[three:forty]
        self.assertRegex(between, r'if \(rcDist > rcTol\)\s*\{\s*RcChars\(gameWin, "", 40\)\s*loginUser := "", loginPass := ""\s*'
                                  r'return RcLoginHelp\(')

    def test_the_bots_own_letters_cleared_not_taken_for_a_username(self):
        self.assertIn('if (!RcCutTyped && RcLineDist(loginUser, gameWin, &rcDistX, rcField) <= rcTol)', self.start)
        cut = code(function(self.rc, 'RcLoginCut'))
        self.assertIn('RcCutTyped := 1', cut)
        self.assertIn('global RcCutTyped', cut)
        # (cleared once logged in, and for a new game)
        self.assertIn('RcLoggedIn := 1, RcCutTyped := 0', code(function(self.rc, 'RcLogLine')))
        self.assertIn('RcLoggedIn := 0, RcBoxSaid := 0, RcCutTyped := 0', code(function(self.rc, 'RcReadLog')))

    def test_cut_counts_no_try_and_marks_nothing(self):
        cut = code(function(self.rc, 'RcLoginCut'))
        for bad in ('RcTries', 'RcMarkBad', 'RcChars(', 'RcCloseGame'):
            self.assertNotIn(bad, cut)
        # (only the game not taking the keys counted - with the tests, 3 then left to you)
        keys = cut[cut.index('if (InStr(why, "didn\'t take"))'):]
        self.assertEqual(cut.count('RcLoginTests :='), 0)
        self.assertEqual(cut.count('RcLoginTests +='), keys.count('RcLoginTests +='))

    def test_you_touching_it_hands_the_box_over(self):
        # (any login box - the bot's own restart too: no new try 3 s after you stop, your username cleared - review 1.2/2.2)
        cut = code(function(self.rc, 'RcLoginCut'))
        # (fix2 last pass: only with you at the game - Wizard101 in front, or its login box found up: "you touched" is any
        # key or mouse on the PC, and a box handed over had no close, tip or alert after it. Elsewhere: tried again 30 s on)
        self.assertRegex(cut, r'if \(InStr\(why, "you touched"\) && \(RcGameActive\(\) \|\| RcBoxFound\)\)\s*\{\s*'
                              r'RcSet\("", [^\n]*left to you"\)\s*return false')
        self.assertRegex(cut, r'if \(InStr\(why, "you touched"\)\)\s*\{\s*RcLookAt := A_TickCount \+ 30000\s*RcLogMsg\([^\n]*\)\s*return true')
        # (the box then logged in only once you've left the PC alone a minute)
        self.assertIn('UserIdle() < 60000', code(function(self.rc, 'RcLoginBoxCheck')))

    def test_keys_not_taken_backs_off_and_gives_up(self):
        # (a hung or elevated game: not clicked and logged every 1.5 s till the 15-minute close - review 1.3/2.2)
        cut = code(function(self.rc, 'RcLoginCut'))
        self.assertRegex(cut, r'if \(InStr\(why, "didn\'t take"\)\)\s*\{\s*RcLoginTests \+= 1, RcLookAt := A_TickCount \+ 8500\s*'
                              r'if \(RcLoginTests >= 3\)\s*return RcLoginHelp\(')
        self.assertRegex(cut, r'(?m)^\tglobal RcLookAt\b')
        self.assertRegex(cut, r'(?m)^\tglobal [^\n]*\bRcLoginTests\b')
        self.assertIn('"the game didn\'t take the keys typed', code(function(self.rc, 'RcLoginHalt')))
        # (RcStartStep waits while RcLookAt is ahead: 10 s to the next look)
        self.assertIn('nowMs - RcLookAt < 1500', self.start)

    def test_halt_rules(self):
        h = code(function(self.rc, 'RcLoginHalt'))
        self.assertIn('if (!typed)', h)
        self.assertIn('if (!RcOn)', h)
        self.assertIn('if (V1IsFunc("BotIsOn") && !BotIsOn.Call())', h)
        self.assertIn('if ((front || RcGameActive()) && UserIdle() < A_TickCount - goAt)', h)
        # (the bot off said first - F6 is a key of yours too)
        self.assertLess(h.index('BotIsOn'), h.index('UserIdle()'))

    def test_the_test_halts_too(self):
        t = code(function(self.rc, 'RcLoginTest'))
        # (before the click too - the guard's reads take a while: review 2.3 - and after it, before zq7)
        focus = t.index('RcLoginFocus(field)')
        self.assertLess(t.index('halt := RcLoginHalt(goAt, front)'), focus)
        after = t[focus:]
        self.assertLess(after.index('halt := RcLoginHalt(goAt, front)'), after.index('RcChars(gameWin, "zq7")'))
        self.assertEqual(len(re.findall(r'halt := RcLoginHalt\(goAt, front\)\s*if \(halt != ""\)\s*return 99', t)), 2)
        self.assertIn('halt := RcLoginHalt(goAt, front, rcSent)', t)

    def test_chars_stop_at_the_first_not_taken(self):
        c = code(function(self.rc, 'RcChars'))
        self.assertEqual(c.count('"ahk_id " win, , , , 1000)'), 2)
        self.assertEqual(c.count('return false'), 2)
        self.assertIn('return true', c)

    def test_field_clicked_near_its_right_end(self):
        f = code(function(self.rc, 'RcLoginFocus'))
        self.assertIn('rcPx := (what = "OK") ? field.cx : Max(field.cx, field.x + field.w - Max(4, field.h // 2)), rcPy := field.cy', f)
        self.assertIn('return RcClick(rcPx, rcPy,', f)
        self.assertIn('MouseMove(rcPx, rcPy, 0)', f)
        self.assertNotIn('MouseMove(field.cx', f)

    def test_nothing_read_logged(self):
        d = code(function(self.rc, 'RcLineDist'))
        self.assertIn('readInfo := rcLineN ? rcLineN " line"', d)
        self.assertNotRegex(d, r'readInfo := [^\n]*(rcRaw|rcSeen|ocrLine\.text)')
        self.assertNotRegex(d, r'RcLogMsg|DebugLog')
        why = self.start[self.start.index('rcTestWhy :='):]
        why = why[:why.index('\n')]
        self.assertNotIn('loginUser', why)
        self.assertNotIn('loginPass', why)


class LoginRules(unittest.TestCase):
    """the rules mirrored, on the cases seen"""
    @classmethod
    def setUpClass(cls):
        cls.rc = read('Reconnect.ahk')

    def test_account_field_from_the_password_label(self):
        # (2026-11-13 at 1920x1080, the game's memory: the field 525-545, x 845-1076; the label's top 557, 13 high)
        f = code(function(self.rc, 'RcAccountField'))
        self.assertIn('rcX := word.left - Round(rcH * 0.2), rcY := word.top - Round(rcH * 2.5), rcW := Round(rcH * 17), '
                      'rcFH := Round(rcH * 1.7)', f)
        h, top, left = 13, 557, 843
        x, y, w, fh = left - ahk_round(h * 0.2), top - ahk_round(h * 2.5), ahk_round(h * 17), ahk_round(h * 1.7)
        self.assertEqual((x, y, w, fh), (840, 524, 221, 22))   # (as logged 2026-11-26 19:05:37)
        self.assertLessEqual(y, 525)
        self.assertGreaterEqual(y + fh, 545)
        # (the right-end click inside the real field)
        px = max(x + w // 2, x + w - max(4, fh // 2))
        self.assertTrue(845 < px < 1076, px)

    def test_memory_field_only_when_the_root_fits_the_game_area(self):
        m = code(function(self.rc, 'RcLoginMem'))
        self.assertIn('Abs(rcG.rootW * GameH / (rcG.rootH * GameW) - 1) > 0.03', m)
        self.assertLess(m.index('> 0.03'), m.index('rcX := GameLeft + Round(rcW.l * GameW / rcG.rootW)'))
        self.assertRegex(m, r'> 0\.03\)\s*\{\s*memOk := 0')

        def fits(rw, rh, gw, gh):
            return not abs(rw * gh / (rh * gw) - 1) > 0.03
        self.assertTrue(fits(1827, 1027, 1920, 1080))
        self.assertFalse(fits(1827, 1027, 1920, 1200))   # (2026-11-21 08:55: the field put 58 px too low)
        self.assertTrue(fits(1827, 1142, 1920, 1200))
        # (test_login_root's field at 1920x1080: 845,525 231x20 - where the 11-13 game had it)
        l, t, r, b = 804, 499, 1024, 518
        self.assertEqual((ahk_round(l * 1920 / 1827), ahk_round(t * 1080 / 1027)), (845, 525))
        self.assertEqual(ahk_round(r * 1920 / 1827) - ahk_round(l * 1920 / 1827), 231)
        # (and what the 1200-high area made of it: the logged 845,583 231x22)
        self.assertEqual((ahk_round(t * 1200 / 1027), ahk_round(b * 1200 / 1027) - ahk_round(t * 1200 / 1027)), (583, 22))

    def test_line_dist(self):
        self.assertEqual(line_dist(['ZQ71'], 'zq7')[0], 0)            # (2026-11-13 21:22 at 1x)
        self.assertEqual(line_dist(['Account: zq7|'], 'zq7')[0], 0)
        self.assertEqual(line_dist(['someuser'], 'someuser'), (0, 3))
        self.assertEqual(line_dist(['someuserxqz'], 'someuser'), (3, 0))   # (xqz in the Account box: stopped)
        self.assertEqual(line_dist(['someus'], 'someuser')[0], 2)          # (3 backspaces into the Account box...)
        self.assertGreater(line_dist(['someu'], 'someuser')[0], 2)         # (... more than any slip let through)
        # (letters left after the cursor - a click in the middle - and the test never reads back: 99)
        self.assertEqual(line_dist(['zq7abcdefgh'], 'zq7')[0], 99)

    def test_padded_reads_only_when_nothing_near(self):
        d = code(function(self.rc, 'RcLineDist'))
        self.assertIn('[[2, 0], [1, 0], [3, 0], [2, 1], [1, 1]]', d)
        self.assertRegex(d, r'if \(rcPass\[2\] && rcBest <= 1\)\s*break')

    def test_ban_only_a_word_of_the_key(self):
        lg = code(function(self.rc, 'RcLogLine'))
        m = re.search(r'rcKeyWords := "_" RegExReplace\(boxKey, "([^"]+)", "\$1_"\) "_"', lg)
        self.assertIsNotNone(m)
        split = re.compile(m.group(1))
        m2 = re.search(r'RegExMatch\(rcKeyWords, "([^"]+)"\)', lg)
        self.assertIsNotNone(m2)
        ban = ahk_rx(m2.group(1))
        self.assertNotRegex(lg, r'ForceDisconnect\|CSRDisconnect\|Ban')

        def banned(key):
            return bool(ban.search('_' + split.sub(r'\1_', key) + '_'))
        for key in ('GUI_BankEquipped', 'GUI_BankEquippedPet', 'GUI_BankPetFromShared', 'GUI_ESM_MoveToBank',
                    'GUI_TrashBanking', 'GUI_TrashBankingHasItems', 'GUI_ConnectionAFK', 'GUI2_00000988', 'Urban'):
            self.assertFalse(banned(key), key)
        for key in ('GUI_AccountBanned', 'GUI_BanAccount', 'GUI_BANNED', 'GUI_Ban'):
            self.assertTrue(banned(key), key)

    def test_login_turned_down_by_its_own_words(self):
        lg = code(function(self.rc, 'RcLogLine'))
        m = re.search(r'if \(RegExMatch\(boxMsg, "(i\)invalid\|incorrect[^"]+)"\)\)\s*\{\s*RcMarkBad\(\)', lg)
        self.assertIsNotNone(m)
        rx = ahk_rx(m.group(1))
        for msg in ('Invalid username or password.', 'Incorrect password', 'Your account has been locked.'):
            self.assertTrue(rx.search(msg), msg)
        for msg in ('This item will be bound to your account.', 'You have been disconnected due to inactivity.',
                    'Your account settings have been saved.'):
            self.assertFalse(rx.search(msg), msg)

    def test_another_clients_box_while_logging_in(self):
        lg = code(function(self.rc, 'RcLogLine'))
        login = lg[lg.index('if (RcState = "login")'):]
        self.assertLess(login.index('if (RcOtherClients())'), login.index('RcMarkBad()'))
        self.assertRegex(login, r'RcLoginMem\(&rcBoxWhy, &rcBoxSeen, , , &rcBoxMemOk, &rcBoxUp\)\s*'
                                r'if \(rcBoxMemOk && !rcBoxUp\)\s*\{\s*RcLogMsg\([^\n]*\)\s*return')
        self.assertIn('seen := 1, boxUp := 1', code(function(self.rc, 'RcLoginMem')))
        o = code(function(self.rc, 'RcOtherClients'))
        self.assertIn('CarryGameWins.Call()', o)
        self.assertIn('V1IsFunc("CarryGameWins")', o)


class Reconnect(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rc = read('Reconnect.ahk')

    def test_own_game_not_taken_for_closed(self):
        chk = code(function(self.rc, 'ReconnectCheck'))
        self.assertIn('else if (!gamePid && RcPid && !RcOwnGame())', chk)
        own = code(function(self.rc, 'RcOwnGame'))
        self.assertIn('rcPicked != RcPid && !ProcessExist(rcPicked) && ProcessExist(RcPid)', own)
        close = code(function(self.rc, 'RcCloseGame'))
        self.assertIn('rcProc := rcOwn ? RcPid : GamePid() ? GamePid() : GameExe', close)
        # (ReconnectCheck's local gamePid would hide the GamePid function there: only RcOwnGame calls it)
        self.assertNotIn('GamePid()', chk)

    def test_no_peeks_without_a_screen(self):
        st = code(function(self.rc, 'RcStep'))
        self.assertIn('nowMs - RcPeekAt > 120000 && UserIdle() > 60000) && RcDeskOk()))', st)
        d = code(function(self.rc, 'RcDeskOk'))
        self.assertIn('DllCall("OpenInputDesktop", "UInt", 0, "Int", 0, "UInt", 0x0100, "Ptr")', d)
        self.assertIn('DllCall("CloseDesktop", "Ptr", rcDesk)', d)
        fc = code(function(self.rc, 'RcFrontClick'))
        self.assertIn('if (failSaidAt != RcStateAt)', fc)
        self.assertIn('static failSaidAt := ""', fc)

    def test_login_box_words_not_logged(self):
        fw = code(function(self.rc, 'RcFindWord'))
        self.assertIn('(loginSeen ? "a login box\'s - not logged" : SubStr(wordsSeen, 1, 200))', fw)
        m = re.search(r'RegExMatch\(Trim\(ocrWord\.text\), "([^"]+)"\)', fw)
        self.assertIsNotNone(m)
        rx = ahk_rx(m.group(1))
        for w in ('Account:', 'Accmna:', 'PASSWORD:', 'PASSWQD:', 'password'):
            self.assertTrue(rx.search(w), w)
        for w in ('Pass', 'RECONNECT', 'QUIT', 'OK', 'You', 'disconnected'):
            self.assertFalse(rx.search(w), w)
        # (looked at before a word on a long line is passed over)
        self.assertLess(fw.index('loginSeen := 1'), fw.index('if (lineMax && ocrLine.words.Length > lineMax)'))

    def test_log_read_quietly_while_off(self):
        off = code(function(self.rc, 'ReconnectOff'))
        self.assertIn('RcScanning := 1, RcOffRead := 1', off)
        self.assertRegex(off, r'try\s*RcReadLog\(\)\s*finally\s*RcScanning := 0, RcOffRead := 0')
        self.assertIn('RcOffAt := A_TickCount', off)
        chk = code(function(self.rc, 'ReconnectCheck'))
        self.assertRegex(chk, r'if \(RcOffAt\)\s*\{\s*RcOffAt := 0\s*RcAfterTray\(\)')
        lg = code(function(self.rc, 'RcLogLine'))
        self.assertIn('if (RcOffRead && RcCharAt)\n\t\t\tRcCharSelAt := A_TickCount', lg)
        self.assertIn('if ((!RcScanning || RcOffRead) && ((RcOn && RcState != "")', lg)

    def test_quiet_read_gives_the_login_no_answer(self):
        # (the bot off: no game closed - RcFail -, no login marked bad or TrayTip from a line read then - review 1.1/2.1)
        lg = code(function(self.rc, 'RcLogLine'))
        login = lg[lg.index('if (RcState = "login")'):]
        self.assertRegex(login, r'^if \(RcState = "login"\)\s*\{\s*if \(RcOffRead\)\s*return\n')
        for later in ('RcOtherClients()', 'RcFail(', 'RcMarkBad()'):
            self.assertLess(login.index('if (RcOffRead)'), login.index(later), later)
        self.assertRegex(login, r'RcMarkBad\(\)\s*RcSet\("stopped", [^\n]*\)\s*if \(!RcScanning\)\s*TrayTip\(')
        # (every TrayTip of RcLogLine and RcFail looked at RcScanning first)
        for fn in ('RcLogLine', 'RcFail'):
            body = code(function(self.rc, fn))
            n = 0
            for m in re.finditer(r'\n([^\n]*)\n\t*TrayTip\(', body):
                n += 1
                self.assertIn('if (!RcScanning', m.group(1), fn)
            self.assertEqual(n, body.count('TrayTip('), fn)

    def test_own_game_window_taken_as_main_in_the_afk_hold(self):
        # (the AFK hold's loop runs ReconnectCheck, not CarryTick: MainTick from here - review 2.4)
        chk = code(function(self.rc, 'ReconnectCheck'))
        # (fix2 last pass: CarryTick first when it's there - it runs MainTick, and in carry mode ends it for a gone main)
        self.assertRegex(chk, r'else if \(!gamePid && RcPid && !RcOwnGame\(\)\)\s*\{[^{}]*\{[^{}]*\}\s*\}\s*'
                              r'else if \(!gamePid && RcPid && V1IsFunc\("CarryTick"\)\)\s*CarryTick\.Call\(\)\s*'
                              r'else if \(!gamePid && RcPid && V1IsFunc\("MainTick"\)\)\s*MainTick\.Call\(\)')
        self.assertRegex(read('Carry.ahk'), r'\nCarryTick\(\)\n\t\{\n[^\n]*\n\tMainTick\(\)')
        self.assertIn('\nMainTick()', read('Carry.ahk'))

    def test_new_globals_declared_blanked_and_set(self):
        top = [ln for ln in self.rc.split('\n') if ln.startswith('global ')]
        blank = code(function(self.rc, 'ReconnectBlank'))
        init = code(function(self.rc, 'ReconnectInit'))
        for name in ('RcCutTyped', 'RcOffRead', 'RcOffAt'):
            self.assertTrue(any(re.search(r'\b%s\b' % name, ln) for ln in top), name)
            self.assertIn('%s := ""' % name, blank)
            self.assertIn('%s := 0' % name, init)
            # (every function that sets it declares it global - v2: else a local)
            for m in re.finditer(r'(?m)^([A-Za-z]\w*)\([^\n]*\)\s*\n\t\{', self.rc):
                fn = m.group(1)
                body = code(function(self.rc, fn))
                if re.search(r'(?<![\w.])%s\s*:=' % name, body):
                    self.assertRegex(body, r'(?m)^\tglobal [^\n]*\b%s\b' % name, fn + ' sets ' + name)


class NetworkTab(unittest.TestCase):
    def test_same_picture_not_loaded_again(self):
        net = read('Network.ahk')
        f = code(function(net, 'NetFetchPicked'))
        self.assertIn('global NetSnapAt', f)
        self.assertIn('NetSnapAt := snapKey, shownLog := text', f)
        self.assertRegex(f, r'if \(NetSnapAt != "" && snapKey == NetSnapAt && text == shownLog\)\s*return')
        self.assertIn('V1Try(FileGetTime, pic, "M")', f)
        # (the "seconds ago" the helper sends changes every ask: not what tells a picture apart)
        self.assertNotIn('"at|"', f)
        self.assertLess(f.index('NetSnapAt := snapKey'), f.index('DashNetShow.Call(text, pic, why)'))


if __name__ == '__main__':
    unittest.main()
