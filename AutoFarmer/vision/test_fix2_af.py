"""test_fix2_af.py - the 2026-11-27 review's second round of AutoFarmer main-file fixes (Autofarmer.ahk read, not run).
Standard library only: python -m unittest test_fix2_af  (from AutoFarmer\\vision)

Pins: "you're playing" - PlayerActing's excusal windows (the bot's own hotkeys 600 ms, the boss / boost / player picks
11 s, X's pass-through and what the mouse lock swallowed never the bot's); a trap, Feint, bubble, negative aura or aura
counted only once it went out (BladeWentOut, as blades since v1.14.1); the aura and Reshuffle that weren't clicked fall on
down the chain to Pass; a screen that couldn't be read is neither "the card went out" for an ally heal's learning nor a
missing picture; the bot's clicks only on the game's own window under the pointer (GameUnderMouse) and the legacy modes'
keys only to Wizard101 in front, the bot on, you not playing (GameKeysOk); chat commands once a line; the AFK hold
reconnects only while you're not playing; the picks time out after 10 s and take only a click on the game; the
developer loops stop; 1x at the start and on F6; F6 off gives a pending refocus its release; StartBot's set-up error
leaves the bot off; the round counter counts in dual mode; the stats write is Critical; the Crown strip honours a shown
button read alone, and TargetSpotOk's answer carries to the click after the card's."""
import os
import re
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
AF = os.path.dirname(HERE)
ROOT = os.path.dirname(AF)


def read(*parts):
    with open(os.path.join(*parts), encoding='utf-8-sig') as f:
        return f.read().replace('\r\n', '\n')


def func(src, name):
    """a function's text: 'Name(...)' then '\\t{' ... '\\t}', or 'Name(...) {' ... '}' at the line's start"""
    m = re.search(r'(?ms)^' + re.escape(name) + r'\([^\n]*\)[ \t]*\n\t\{[^\n]*\n(.*?)^\t\}', src)
    if not m:
        m = re.search(r'(?ms)^' + re.escape(name) + r'\([^\n]*\)[ \t]*\{[^\n]*\n(.*?)^\}', src)
    assert m, name + ' not found'
    return m.group(1)


def code(text):
    """the lines without their comments (a ; at the start of a line, or ' ;' after code)"""
    out = []
    for ln in text.split('\n'):
        s = ln.strip()
        if s.startswith(';'):
            continue
        out.append(re.sub(r'\s;.*$', '', ln))
    return '\n'.join(out)


AFK = read(AF, 'Autofarmer.ahk')


def fn(name):
    if name == 'BattleLoop':
        # (its own Loop's braces sit at the line's start too: up to the next function, the mob loop)
        return code(AFK[AFK.index('\nBattleLoop() {'):AFK.index('\nmobloop() {')])
    return code(func(AFK, name))


class YoureePlayingWindows(unittest.TestCase):
    """x-tests-13: the input-yield rule behind every "no input while you play" was pinned by one regex"""

    def setUp(self):
        self.pa = fn('PlayerActing')

    def test_handsoff_seconds(self):
        self.assertIn('secs := Stats.Has("handsoff") ? Stats["handsoff"] : 3', self.pa)
        self.assertIn('acting := (HandsOffOn() && secs > 0 && UserIdle() < secs * 1000)', self.pa)

    def test_only_the_bots_own_hotkeys_excused(self):
        # (one excusal, its windows: 50 ms before the key, 600 ms after it - 11 s only for the picks that wait for a click)
        self.assertEqual(self.pa.count('acting := false'), 1)
        self.assertRegex(self.pa, r'if \(hkNow != "" && lastInput >= keyAt - 50 && lastInput <= keyAt \+ '
                                  r'\(HkIsAny\(hkNow, "boss,boost,player"\) \? 11000 : 600\)\)\n\t+acting := false')
        self.assertEqual(self.pa.count('11000'), 1)
        self.assertEqual(self.pa.count('HkIsAny('), 1)
        self.assertIn('if (acting && A_ThisHotkey != "")', self.pa)

    def test_swallowed_clicks_and_x_pass_through(self):
        # (a click the mouse lock swallowed is a hotkey too: the bot's own is the one before it)
        self.assertRegex(self.pa, r'if \(MouseLockIsKey\(hkNow\)\)\n\t+hkNow := A_PriorHotkey, keyAt := A_TickCount - '
                                  r'\(A_TimeSincePriorHotkey = "" \? -1 : A_TimeSincePriorHotkey\)')
        # (X's pass-through is your own X, never excused)
        self.assertRegex(self.pa, r'if \(hkNow = "~\*x"\)\n\t+hkNow := ""')
        self.assertLess(self.pa.index('hkNow = "~*x"'), self.pa.index('acting := false'))
        self.assertIn('lastInput := A_TickCount - UserIdle()', self.pa)

    def test_play_for_me_and_the_lock(self):
        ui = code(func(read(ROOT, 'AutoQuester', 'Walker.ahk'), 'UserIdle'))
        self.assertRegex(ui, r'if \(PlayForMe\)\n\t+return 2147483647')
        self.assertIn('return lockIdle ? lockIdle.Call() : A_TimeIdlePhysical', ui)


class CastsCountedOnlyWhenOut(unittest.TestCase):
    """af-main-1-5 / af-main-2-4"""

    def test_trap(self):
        t = fn('UseTrap')
        clicks = [m.end() for m in re.finditer(r'if \(!TrapTargetClick\(title, utBox\)\)\n\t+return false', t)]
        self.assertEqual(len(clicks), 2)
        for c in clicks:
            out = t.find('if (!BladeWentOut(title))', c)
            self.assertGreater(out, c)
            self.assertLess(out, t.find('boosts++', c))
            self.assertLess(out, t.find('TrapPut(', c))

    def test_bubble_and_negaura(self):
        b = fn('ClickBubble')
        self.assertEqual(b.count('if (!BladeWentOut(cbKey))'), 2)
        self.assertLess(b.index('if (!BladeWentOut(cbKey))'), b.index('bubble := 1, BubbleUp := cbAt.name'))
        self.assertLess(b.rindex('if (!BladeWentOut(cbKey))'), b.index('BubbleUp := cbName'))
        n = fn('UseNegAura')
        self.assertLess(n.index('if (!BladeWentOut("negaura"))'), n.index('NegAuraNote('))
        self.assertLess(n.index('if (!TargetClick('), n.index('if (!BladeWentOut("negaura"))'))

    def test_chain_aura_and_reshuffle_fall_through(self):
        loop = fn('BattleLoop')
        self.assertRegex(loop, r'\} else if \(aura == 1\) && BoostOk && Stat\("useaura"\) && \(AuraRounds <= 0\) && '
                               r'FindAndClick\(&_title := "aura", &aura, &hitschool\) && BladeWentOut\("aura"\)\n\t+\{\n'
                               r'\t+AuraRounds := 4')
        self.assertNotRegex(loop, r'\n\t+if FindAndClick\(&_title := "aura"')
        self.assertRegex(loop, r'\} else if \(reshuffle == 1\) && Stat\("usereshuffle"\) && \(PartySupport\(\) \? '
                               r'UseOnSelf\(&_title := "reshuffle", &reshuffle, &_dir := "resources"\) : '
                               r'UseOnHammer\(&_title := "reshuffle", &reshuffle, &_dir := "resources"\)\)\n\t+\{\n'
                               r'\t+if \(!PartySupport\(\)\)\n\t+ResetUsed\(\)\n\t+\} else if ClickPass\(\)')


class ScreenNotRead(unittest.TestCase):
    """af-main-1-7, vision-ahk-3: a capture that failed isn't a gone Pass button for learning, nor a missing picture"""

    def test_target_pending_marks_unread(self):
        tp = fn('TargetPending')
        self.assertIn('global TargetPendUnread', tp)
        self.assertRegex(tp, r'TargetPendUnread := 0\n')
        self.assertRegex(tp, r'tpErr := PassButtonAt\(&pendX, &pendY\)\n\t+if \(tpErr\)\n\t+\{\n\t+'
                             r'TargetPendUnread := \(tpErr = 2\)\n\t+return false')

    def test_heal_learns_nothing_unread(self):
        h = fn('UseHeal')
        un = h.index('if (TargetPendUnread)')
        self.assertLess(un, h.index('StatsSet([[dir "." title "target", allOf ? 2 : 0]])'))
        self.assertRegex(h[un:], r'^if \(TargetPendUnread\)\n\t+DebugLog\([^\n]*\)\n\t+else\n\t+\{\n\t+StatsSet\(')

    def test_round_start_not_a_missing_picture(self):
        loop = fn('BattleLoop')
        two = loop[loop.index('if (startErr = 2)'):loop.index('If (startErr = 0)')]
        self.assertIn('startPic := PicPath("resources\\roundstart.png")', two)
        self.assertLess(two.index('FileExist(startPic)'), two.index('Can\'t open '))
        self.assertIn('PicUnreadSaidAt', two[:two.index('Can\'t open ')])
        self.assertNotIn('PicError := 1', two[:two.index('else if (!PicError)')])
        self.assertRegex(loop, r'If \(startErr = 0\)\n\t+\{\n\t+PicError := 0\n')
        self.assertIn('local startPic', loop)


class ClicksOnlyOnTheGame(unittest.TestCase):
    """x-usersafety-3"""

    def test_under_the_pointer(self):
        g = fn('GameUnderMouse')
        self.assertIn('MouseGetPos(, , &gumWin)', g)
        self.assertIn('gumWant := GamePid()', g)
        self.assertRegex(g, r'if \(gumWin && gumClass = GameClass && gumExe = GameExe && \(!gumWant \|\| gumPid = gumWant\)\)'
                            r'\n\t+return true')
        # (fix2 review 1.1/2.2: a refused click only noted - the round goes on, its end looks whether it's still up)
        self.assertRegex(g, r'if \(inbattle == 1\)\n\t+RoundRefused := 1')
        self.assertIn('global RoundRefused', g)
        self.assertNotIn('RoundLeft', g)

    def test_refused_round_looked_at_its_end(self):
        loop = fn('BattleLoop')
        end = loop[loop.index('\nEndRound:'):]
        # (fix2 last pass: the game not showing there - the window that refused the click still over it, the screen
        # locked - left at once, as at first: the screen search for the Pass reads the other program; only with the
        # game showing does CastWentOut decide)
        self.assertRegex(end, r'if \(RoundRefused\)\n\t+\{\n\t+RoundRefused := 0\n\t+'
                              r'if \(!RoundLeft && inbattle == 1 && !GameShowing\(\)\)\n\t+\{\n\t+RoundLeft := 1\n[^{}]*\}\n\t+'
                              r'else if \(!RoundLeft && inbattle == 1 && !CastWentOut\(\)\)\n\t+\{\n\t+RoundLeft := 1\n')
        gs = fn('GameShowing')
        self.assertIn('RcOnGame(', gs)
        self.assertIn('WinExist(GameWT())', gs)
        # (the round left to you over once its Pass is gone - looked for only with the game showing there too)
        self.assertIn('if (RoundLeft && GameShowing())', loop)
        self.assertLess(end.index('if (RoundRefused)'), end.index('SwitchWindow()'))
        self.assertLess(end.index('if (RoundRefused)'), end.index('CarryRoundEnd()'))
        self.assertIn('RoundAgain := RoundLeft, RoundLeft := 0, RoundRefused := 0', loop)
        # (not in ResetVariables - every round's start sets it afresh, and Carry.ahk would have to swap it)
        self.assertNotIn('RoundRefused', fn('ResetVariables'))
        self.assertIn('RoundLeft := 0, RoundAgain := 0, RoundRefused := 0\n', AFK.replace('\r\n', '\n'))

    def test_hit_not_moved_for_a_covered_plate(self):
        tc = fn('TargetClick')
        self.assertIn('global TargetClickCovered', tc)
        self.assertLess(tc.index('if (GameInTray)'), tc.index('TargetClickCovered := 0'))
        self.assertRegex(tc, r'\}\n\t+else\n\t+TargetClickCovered := 1\n')
        h = fn('HitTarget')
        first = h.index('if (!TargetClick(tx, ty, tbox))')
        self.assertRegex(h[first:], r'^if \(!TargetClick\(tx, ty, tbox\)\)\n\t+\{\n\t+if \(TargetClickCovered\)\n\t+\{\n'
                                    r'\t+DebugLog\([^\n]*\)\n\t+return\n')
        self.assertLess(first, h.index('others := V1Obj()'))
        self.assertIn('else if (!TargetClickCovered && TargetClick(tx, ty, tbox))', h)

    def test_before_each_click(self):
        for name in ('ClickAt', 'TargetClick'):
            b = fn(name)
            self.assertLess(b.index('GameUnderMouse('), b.index('Click()'), name)
            self.assertEqual(b.count('Click()'), 1, name)
        self.assertIn('return tcOn ? 1 : 0', fn('TargetClick'))
        for name, out in (('DiscardCard', 'return 0'), ('DiscardSpent', 'break')):
            b = fn(name)
            self.assertRegex(b, r'if \(!GameInTray && !GameUnderMouse\("a discard"\)\)\n\t+' + out + r'\n', name)
            self.assertLess(b.index('GameUnderMouse('), b.index('Click("right")'), name)


class KeysOnlyToTheGame(unittest.TestCase):
    """x-usersafety-6 / af-main-1-4, gap4-2"""

    def test_the_check(self):
        g = fn('GameKeysOk')
        self.assertIn('gkoOk := !GameInTray && BotOn && GameActive() && !PlayerActing()', g)
        self.assertIn('return gkoOk', g)
        # (a held mob-loop or lore step said, at most once a minute - fix2 review 2.1)
        self.assertIn('if (!gkoOk && what != "" && (!saidAt || A_TickCount - saidAt > 60000))', g)

    def test_each_sender(self):
        for name, first in (('Respond', 'Send("{r}")'), ('Spam', 'Send("{"'), ('LockMove', 'Send("{"'),
                            ('Log', 'Send("{Esc}")'), ('CommandWalk', 'Send("{w Down}")'),
                            ('CommandEnter', 'Send("{Blind}{x down}")'), ('CommandPort', 'Send("{/}")')):
            b = fn(name)
            self.assertIn('if (!GameKeysOk())', b, name)
            self.assertLess(b.index('if (!GameKeysOk())'), b.index(first), name)
        mob = fn('mobloop')
        self.assertLess(mob.index('if (!GameKeysOk("The mob-loop step ('), mob.index('Send("{s down}")'))
        self.assertRegex(mob, r's\(5000\)\s*if \(GameInTray\)\s*return\s*if \(!GameKeysOk\(\)\)\s*return\s*'
                              r'Send\("\{w down\}"\)')
        self.assertIn('if (loremode == 1 && !GameKeysOk("Lore farming (', fn('LoreLoop'))
        # (the mob loop and lore farming run on each pass out of battle the spellbook's up - a held step tried again)
        out = fn('BattleLoop')
        out = out[out.index('if (bookSeen)\n\t\t{\n\t\tif (!SeenOut)'):]
        self.assertLess(out.index('mobloop()'), out.index('If (startErr = 0)'))

    def test_enter_only_at_a_sigil(self):
        e = fn('CommandEnter')
        self.assertIn('local cePrompt', e)
        self.assertIn('cePrompt := InteractPrompt()', e)
        self.assertIn('if (cePrompt != "sigil" || WalkPromptCrowns())', e)
        self.assertLess(e.index('WalkPromptCrowns()'), e.index('{x down}'))
        self.assertNotIn('Send("{x}")', e)

    def test_once_a_chat_line(self):
        cn = fn('CommandNew')
        self.assertIn('static cnSeen := Map()', cn)
        self.assertRegex(cn, r'if \(cnSeen\.Has\(word\)\)\n\t+cnSeen\.Delete\(word\)')
        for name, word, act in (('CommandEnter', 'enter', 'InteractPrompt()'), ('CommandWalk', 'walk', 'Respond('),
                                ('CommandPort', 'port', 'Send("{/}")')):
            b = fn(name)
            self.assertRegex(b, r'if \(ErrorLevel == 1\)\n\t+CommandNew\("%s", false\)' % word, name)
            # (walk, enter: only asked first - recorded right before the key, once every check has passed - fix2 review
            # 1.4/2.3; port: recorded before its keys as ever)
            ask = 'if (!CommandNew("%s", true%s))' % (word, '' if word == 'port' else ', false')
            new = b.index(ask)
            self.assertLess(b.index('if (!GameKeysOk())'), new, name)
            self.assertLess(new, b.index(act), name)
        self.assertIn('\nCommandNew(word, found, mark := true)\n', AFK.replace('\r\n', '\n'))
        self.assertRegex(cn, r'if \(mark\)\n\t+\{\n\t+cnSeen\[word\] := 1\n\t+return true\n\t+\}')
        # (fix2 last pass: only asked - for 30 s from the line's first look at most, then done for that line: not armed
        # for hours, the prompt read on every pass)
        self.assertRegex(cn, r'if \(!cnSeen\.Has\(word\)\)\n\t+cnSeen\[word\] := -A_TickCount\n\t+'
                             r'else if \(A_TickCount \+ cnSeen\[word\] > 30000\)\n\t+\{\n\t+cnSeen\[word\] := 2\n')
        self.assertIn('if (cnSeen.Has(word) && cnSeen[word] > 0)', cn)
        for name, word, key in (('CommandEnter', 'enter', 'Send("{Blind}{x down}")'), ('CommandWalk', 'walk', 'Send("{w Down}")')):
            b = fn(name)
            mark = b.index('\n\t\t\tCommandNew("%s", true)\n' % word)
            self.assertGreater(mark, b.rindex('if (!GameKeysOk())'), name)
            self.assertLess(mark, b.index(key), name)
            self.assertGreater(mark, b.index('Respond('), name)
        e = fn('CommandEnter')
        self.assertGreater(e.index('\n\t\t\tCommandNew("enter", true)\n'), e.index('WalkPromptCrowns()'))
        self.assertIn('static ceSaid := ""', e)
        self.assertIn('if (ceWhy != ceSaid)', e)


class HoldAndPicks(unittest.TestCase):
    """af-main-1-2, af-main-2-6, af-main-2-7"""

    def test_hold_no_reconnect_while_you_play(self):
        ca = fn('CheckAfk')
        self.assertRegex(ca, r'if \(PlayerActing\(\)\)\n\t+continue\n')
        self.assertLess(ca.index('if (PlayerActing())'), ca.index('ReconnectCheck()'))
        self.assertLess(ca.index('if (!BotOn)'), ca.index('InputHook('))

    def test_picks_time_out_on_the_game(self):
        self.assertNotIn('"D, 10"', code(AFK))
        p = fn('HkPickClick')
        self.assertIn('if (!KeyWait("LButton", "D T10"))', p)
        self.assertLess(p.index('UpdateGameRect()'), p.index('MouseOnGame(hpX, hpY)'))
        self.assertEqual(p.count('Gui1Destroy()'), 2)
        for name in ('HkBoss', 'HkBoost', 'HkPlayer'):
            self.assertIn('ErrorLevel := !HkPickClick()', fn(name), name)

    def test_dev_loops_stop(self):
        d = fn('DevLoopOn')
        self.assertIn('if (BotOn && GameActive() && !PlayerActing())', d)
        h1 = fn('HK1_')
        self.assertIn('while (DevLoopOn())', h1)
        self.assertRegex(h1, r'if \(Mod\(A_Index, 50\) = 1 && !DevLoopOn\(\)\)\n\t+\{\n\t+devStop := 1\n\t+break')
        # (stopped among the keys: not the turn's clicks after them either - each turn's clicks after a fresh look)
        stop = h1.index('if (devStop || !DevLoopOn())')
        self.assertGreater(stop, h1.index('Loop 600'))
        self.assertLess(stop, h1.index('MouseMove(610 + leftoffset'))
        self.assertIn('local devStop := 0', h1)
        self.assertRegex(h1, r'local [^\n]*\bLoading\b[^\n]*\bBufferVar\b')
        self.assertNotRegex(h1, r'\n\t+Loop\n')
        h2 = fn('HK2_')
        self.assertRegex(h2, r'Loop\n\t+\{\n\t+if \(Mod\(A_Index, 20\) = 1 && !DevLoopOn\(\)\)\n\t+break\n\t+Click\(\)')


class OnOffAndStart(unittest.TestCase):
    """gap1-3, gap3-5, extra: StartBot's own set-up error"""

    def test_one_x_on_start_and_on(self):
        t = fn('BotToggle')
        on = t[:t.index('else\n')]
        self.assertIn('SpeedSet(0, "bot on", true)', on)
        sb = fn('StartBot')
        self.assertRegex(sb, r'if \(BotOn\)\n\tSpeedSet\(0, "the bot started", true\)')
        self.assertLess(sb.index('WalkerInit('), sb.index('SpeedSet(0, "the bot started", true)'))

    def test_refocus_on_f6_off(self):
        t = fn('BotToggle')
        off = t[t.index('MouseLockRelease("the bot\'s off")') - 200:]
        self.assertRegex(off, r'if \(Refocus\)\n\t+SetTimer\(WalkerRefocusWatch,250\)')

    def test_setup_error_leaves_it_off(self):
        sb = fn('StartBot')
        lines = [ln.strip() for ln in sb.split('\n') if ln.strip()]
        self.assertEqual(lines[:4], ['global', 'local v1Keep := V1Thread()', 'local loopUp', 'loopUp := BotLoopMark()'])
        self.assertLess(sb.index('global BotSetUp := 1'), sb.index('\nBattleLoop()'))
        self.assertGreater(sb.index('global BotSetUp := 1'), sb.index('ResetUsed()'))
        g = fn('BotLoopGone')
        self.assertLess(g.index('BotOn := 0'), g.index('if (!BotSetUp)'))
        a = fn('BotLoopAgain')
        self.assertRegex(a, r'if \(!BotSetUp\)\n\t+\{\n\t+BotOn := 0')
        self.assertLess(a.index('if (!BotSetUp)'), a.index('BattleLoop()'))
        self.assertIn('global BotOn', a)
        blank = fn('AutofarmerBlank')
        self.assertIn('global BotLoopDead := 0, BotSetUp := 0', blank)
        self.assertIn('global TargetPendUnread := 0, TargetSpotKeep := "", PicUnreadSaidAt := 0, RoundRefused := 0, '
                      'TargetClickCovered := 0', blank)


class RoundsAndStats(unittest.TestCase):
    """af-main-2-9, x-persistence-12"""

    def test_dual_mode_counts(self):
        loop = fn('BattleLoop')
        self.assertNotIn('roundnumber := ""', loop)
        self.assertRegex(loop, r'if \(dualmode == 1\)\n\t+\{\n\t+roundnumber := V1N\(roundnumber\) \+ 1\n\t+\} else')
        self.assertIn('V1Lt(V1Sub(roundnumber, unWhen), dualmode == 1 ? 8 : 4)', fn('UseNegAura'))

    def test_stats_write_critical(self):
        sa = fn('StatsAuto')
        self.assertLess(sa.index('swCrit := A_IsCritical'), sa.index('msg := StatsWrite('))
        self.assertRegex(sa, r'swCrit := A_IsCritical\n\t+Critical\(\)\n\t+msg := StatsWrite\(')
        self.assertRegex(sa, r'CfgUncritical\(wasCrit, 0\)\n\t+CfgUncritical\(swCrit, 0\)')


class CrownCorner(unittest.TestCase):
    """gap4-7, extra: the read TargetSpotOk went by carries to the click after the card's"""

    def test_strip_honours_one_read_alone(self):
        s = fn('TargetClickSpot')
        self.assertIn('if (!tsUp || tsR = "" || x > tsR + Px(12) || y > tsB + Px(12))', s)
        self.assertNotIn('if (!tsAll || !tsUp', s)
        self.assertRegex(s, r'if \(tsR != ""\)\n\t+tsClear := Max\(tsClear, tsR \+ Px\(12\) \+ 1\)')

    def test_keep(self):
        s = fn('TargetClickSpot')
        # (only a read that came back carries - a blank one is read again past 1.5 s: fix2 review 1.3)
        self.assertIn('tsKeep := (TargetSpotKeep != "" && TargetSpotKeep = x "," y "," TargetCrownAt && IsObject(TargetCrownG))', s)
        self.assertRegex(s, r'TargetSpotKeep := ""\n\t+tsG := \(TargetCrownAt && \(tsKeep \|\| A_TickCount - '
                            r'TargetCrownAt < 1500\)\) \? TargetCrownG : TargetCrownRead\(\)')
        ok = fn('TargetSpotOk')
        self.assertIn('global TargetSpotKeep', ok)
        self.assertRegex(ok, r'if \(TargetClickSpot\(&tsoX, &tsoY, box, &tsoWhy\)\)\n\t+\{\n\t+'
                             r'TargetSpotKeep := x "," y "," TargetCrownAt\n\t+return true')
        self.assertIn('TargetCrownRead(), TargetSpotKeep := tx "," ty "," TargetCrownAt', fn('HitTarget'))


if __name__ == '__main__':
    unittest.main()
