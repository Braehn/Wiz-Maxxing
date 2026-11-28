"""test_battlerec.py - the battle recorder's checks on stand-in WizardClient.log lines (standard library only):
    python -m unittest test_battlerec          (from AutoFarmer\\vision)

The log's duel state machine (Parser.feed: the adds and subcircles, phases, casts, hanging effects, wards, health,
removes, the result; a duel not mine dropped, simulated and chat-like lines never counted), the bot's round posts
(parse_body / unesc), the rules that say what decided a round (classify), one battle record built from it all
(build_record: who played, the card played and its place in hand, the bot's rule, deaths and the result) - the format
the planner and the learned plays read, locked down - and the charms on each participant rebuilt from the log
(charms_now: blades, traps, shields used up by the next fitting hit). No game, no files: the lines are made here in the
log's own layout ("MM/DD/YY HH:MM:SS [TAG] Category message")."""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import battlerec as R  # noqa: E402

DUEL, GID = 7445553, "9876543210123"


class Log:
    """stand-in log lines fed to a Parser one by one - each a second after the last (tk in ms), all of them live"""

    def __init__(self, parser=None):
        self.p = parser or R.Parser()
        self.tk = 100000
        self.sec = 0

    def line(self, cat, msg, tag="DBGM"):
        self.sec += 1
        s = self.sec
        raw = "10/27/26 21:%02d:%02d [%s] %s %s" % (s // 60 % 60, s % 60, tag, cat, msg)
        self.tk += 1000
        self.p.feed(raw.encode("cp1252"), self.tk, self.sec * 100, True)
        return self.tk

    def duel_start(self, enemies=(("CL_Rat-R3", 11, 501),), me_gid="777", me_pid=21, duel=DUEL, my_sc=4,
                   others=(), name="Ned Stormblade"):
        """a duel joined: each enemy's add (its 'Added participant' - the first add gets no subcircle line), then mine
        (My SubCircle), the planning window's names, the round's first Planning, the Participant lines"""
        for k, (obj, pid, gid) in enumerate(enemies):
            self.line("ClientDuel", "Duel %d: MSG_CombatAdd(%s)" % (duel, obj))
            self.line("Duel", "AddNewParticipant player:%d" % gid)
            if k:
                self.line("CORE_SEER", "My SubCircle: %d, OtherPart's SubCircle: %d" % (k, my_sc))
            self.line("CORE_SEER", "Added participant %d to duel %d" % (pid, duel))
        self.line("ClientDuel", "Duel %d: MSG_CombatAdd(Local Player)" % duel)
        self.line("Duel", "AddNewParticipant player:%s" % me_gid)
        self.line("CORE_SEER", "My SubCircle: %d, OtherPart's SubCircle: 0" % my_sc)
        self.line("CORE_SEER", "Added participant %d to duel %d" % (me_pid, duel))
        for sc, pid, gid, nm in others:
            self.line("ClientDuel", "Duel %d: MSG_CombatAdd(Non-local Player)" % duel)
            self.line("Duel", "AddNewParticipant player:%d" % gid)
            self.line("CORE_SEER", "My SubCircle: %d, OtherPart's SubCircle: 0" % sc)
            self.line("CORE_SEER", "Added participant %d to duel %d" % (pid, duel))
        self.line("ClientDuel", "Duel %d: Local Player Entering Combat at (10.5, -20.25, 3.0)" % duel)
        self.line("CombatPlanningP", "Subcircle %d" % my_sc)
        self.line("MINION", "CombatantDataControl, name:%s" % name)
        return self

    def planning(self, duel=DUEL):
        return self.line("ClientDuel", "Duel %d: MSG_CombatPhase(kPhase_Planning)" % duel)

    def execution(self, parts, duel=DUEL):
        t = self.line("ClientDuel", "Duel %d: MSG_CombatPhase(kPhase_Execution)" % duel)
        for pid, team, hp, pips, pp in parts:
            self.line("CORE_SEER", "Participant: ID %d, Team %d, Health %d Pips %d PPips %d" % (pid, team, hp, pips, pp))
        return t

    def cast(self, rnd, sc, spell, gid=GID):
        return self.line("CombatDetails", "CombatResolver::ResolveCombatRound. Duel ID:%s Round:%d Caster:%d Spell:%s"
                         % (gid, rnd, sc, spell))

    def target(self, caster, t, effect, param):
        self.line("CombatDetails", "ProcessTargets. Caster:%d Target:%d Effect:%s Param:%d" % (caster, t, effect, param))

    def hang(self, t, effect, charm, param):
        self.line("CombatDetails", "AddHangingEffect. Target:%d Effect:%s Charm:%s Param:%d"
                  % (t, effect, "Yes" if charm else "No", param))

    def ward(self, caster, t, effect, param):
        self.line("CombatDetails", "ProcessWards. Caster:%d Target:%d Effect:%s Param:%d" % (caster, t, effect, param))

    def hp(self, pid, before, delta):
        self.line("CORE_SEER", "ModifyHealth called OwnerID:%d, m_playerHealth:%d, a_deltaHealth:%d" % (pid, before, delta))

    def resolution(self, duel=DUEL):
        return self.line("ClientDuel", "Duel %d: MSG_CombatPhase(kPhase_Resolution)" % duel)

    def win(self, objs=("CL_Rat-R3",), duel=DUEL):
        self.line("ClientDuel", "Duel %d: MSG_CombatPhase(kPhase_Victory)" % duel)
        for o in objs:
            self.line("ClientDuel", "Duel %d: MSG_CombatRemove(%s)" % (duel, o))
        self.line("ClientDuel", "Duel %d: MSG_CombatMatchResult(0)" % duel)
        self.line("ClientDuel", "Duel %d: MSG_EndDuel received" % duel)


def two_round_win():
    """a rat (sc 0, 501 health) fought: round 1 a Stormblade on me, the rat's bite; round 2 Storm Lord kills it"""
    L = Log().duel_start()
    L.planning()
    t_plan1 = L.tk
    L.execution([(11, 1, 501, 1, 0), (21, 0, 3000, 1, 0)])
    L.cast(1, 4, "Stormblade")
    L.hang(4, "kModifyOutgoingDamage", True, 35)
    L.cast(1, 0, "Rat Bite")
    L.target(0, 4, "kDamage", 120)
    L.hp(21, 3000, -120)
    L.resolution()
    L.planning()
    t_plan2 = L.tk
    L.execution([(11, 1, 501, 2, 0), (21, 0, 2880, 2, 0)])
    L.cast(2, 4, "Storm Lord")
    L.target(4, 0, "kDamage", 900)
    L.hp(11, 501, -501)
    L.resolution()
    L.win()
    return L, t_plan1, t_plan2


# ============================================================================ the log's duel state machine
class Parse(unittest.TestCase):
    def test_a_whole_duel(self):
        L, _t1, _t2 = two_round_win()
        p = L.p
        self.assertIsNone(p.duel)
        self.assertEqual(len(p.closed), 1)
        d = p.closed[0]
        self.assertEqual((d["num"], d["gid"], d["me_sc"], d["result"], d["rounds_n"]), (DUEL, GID, 4, "won", 2))
        self.assertEqual(sorted(d["parts"]), [0, 4])
        rat, me = d["parts"][0], d["parts"][4]
        self.assertEqual((rat["obj"], rat["pid"], rat["gid"], rat["team"], rat["hp0"]), ("CL_Rat-R3", 11, "501", 1, 501))
        self.assertEqual((rat["died_round"], rat["killed_by"], rat["out"]), (2, 4, "dead"))
        self.assertTrue(me["me"])
        self.assertEqual(d["names"], {4: "Ned Stormblade"})
        self.assertEqual(d["enter"], [10.5, -20.25, 3])
        r1, r2 = d["rounds"]
        self.assertEqual([c["spell"] for c in r1["casts"]], ["Stormblade", "Rat Bite"])
        self.assertEqual(r1["casts"][0]["hang"], [[4, "kModifyOutgoingDamage", 1, 35]])
        self.assertEqual(r1["casts"][1]["hp"], [[4, 3000, -120]])
        self.assertEqual(r1["casts"][1]["fx"], [[4, "kDamage", 120]])
        self.assertEqual(r1["hp_end"], {0: 501, 4: 2880})
        self.assertEqual(r2["died"], [0])
        self.assertEqual(r2["start"], [[0, 501, 2, 0], [4, 2880, 2, 0]])
        self.assertTrue(all(r["closed"] for r in d["rounds"]))
        self.assertIn(("closed", DUEL), p.events)

    def test_a_knockout_is_lost(self):
        """a knockout as the game logs it (2026-11-14): my health to 0, Ended, MatchResult(1), Victory (theirs), EndDuel -
        no MSG_CombatRemove(Local Player): lost, not unknown"""
        L = Log().duel_start()
        L.planning()
        L.execution([(11, 1, 501, 1, 0), (21, 0, 300, 1, 0)])
        L.cast(1, 0, "Rat Bite")
        L.target(0, 4, "kDamage", 352)
        L.hp(21, 300, -352)
        L.resolution()
        L.line("ClientDuel", "Duel %d: MSG_CombatPhase(kPhase_Ended)" % DUEL)
        L.line("ClientDuel", "Duel %d: MSG_CombatMatchResult(1)" % DUEL)
        L.line("ClientDuel", "Duel %d: MSG_CombatPhase(kPhase_Victory)" % DUEL)
        L.line("CORE_SEER", "Duel %d: MSG_EndDuel received: and we were a part of it." % DUEL)
        d = L.p.closed[0]
        self.assertEqual((d["result"], d["match_result"], d["parts"][4]["died_round"]), ("lost", 1, 1))
        # (the match lost but my health not down to 0 - not known how: unknown, as before)
        L = Log().duel_start()
        L.planning()
        L.execution([(11, 1, 501, 1, 0), (21, 0, 300, 1, 0)])
        L.resolution()
        L.line("ClientDuel", "Duel %d: MSG_CombatMatchResult(1)" % DUEL)
        L.line("CORE_SEER", "Duel %d: MSG_EndDuel received: and we were a part of it." % DUEL)
        self.assertEqual(L.p.closed[0]["result"], "unknown")

    def test_a_circles_duel_number_again(self):
        """the next battle at the same circle has the last one's duel number (the game's own, 2026-11-14): a win, then a
        knockout under it - both recorded, the second lost"""
        L, _t1, _t2 = two_round_win()
        L.duel_start(enemies=(("GH2-Skeleton-Ice-4-BOSS-R10", 12, 502),))
        L.planning()
        L.execution([(12, 1, 1690, 1, 0), (21, 0, 300, 1, 0)])
        L.cast(1, 0, "Ice Wyvern")
        L.target(0, 4, "kDamage", 352)
        L.hp(21, 300, -352)
        L.resolution()
        L.line("ClientDuel", "Duel %d: MSG_CombatMatchResult(1)" % DUEL)
        L.line("CORE_SEER", "Duel %d: MSG_EndDuel received: and we were a part of it." % DUEL)
        self.assertEqual([d["result"] for d in L.p.closed], ["won", "lost"])
        # (a closed duel's tail - a line that doesn't open one - still dropped)
        L.line("ClientDuel", "Duel %d: MSG_CombatPhase(kPhase_Victory)" % DUEL)
        self.assertEqual((len(L.p.closed), L.p.duel), (2, None))

    def test_another_wizards_duel_is_dropped(self):
        p = R.Parser()
        L = Log(p)
        L.line("ClientDuel", "Duel 555: MSG_CombatAdd(CL_Rat-R3)")
        L.line("ClientDuel", "Duel 555: MSG_CombatPhase(kPhase_Planning)")
        L.line("ClientDuel", "Duel 555: CombatPlanningPhaseWindow::HandleCombatPhase(kPhase_Planning, Other Player's Duel)")
        L.line("ClientDuel", "Duel 555: MSG_EndDuel received: and we were NOT a part of it")
        self.assertEqual((p.closed, p.duel, p.foreign), ([], None, 1))

    def test_lines_that_never_count(self):
        L = Log().duel_start()
        L.planning()
        L.execution([(11, 1, 501, 1, 0), (21, 0, 3000, 1, 0)])
        L.cast(1, 4, "Storm Lord")
        # (the game's own simulation of a cast, a chat line written like a health change, the wrong logger's)
        L.line("CORE_SEER", "{IsSim:1} Participant (sc 0) chose to pass.")
        L.line("CHAT", "ModifyHealth called OwnerID:11, m_playerHealth:501, a_deltaHealth:-501")
        L.line("CORE_SEER", "Bob says: ModifyHealth called OwnerID:11, m_playerHealth:501, a_deltaHealth:-501")
        L.hp(11, 501, -200)
        d = L.p.duel
        c = d["rounds"][-1]["casts"][0]
        self.assertEqual(c["hp"], [[0, 501, -200]])
        self.assertNotIn("pass", c)
        self.assertEqual(d["parts"][0]["hp"], 301)

    def test_repeats_and_passes(self):
        L = Log().duel_start()
        L.planning()
        L.execution([(11, 1, 501, 1, 0), (21, 0, 3000, 1, 0)])
        L.cast(1, 0, "None")
        L.line("CORE_SEER", "{IsSim:0} Participant (sc 0) chose to pass.")
        L.cast(1, 4, "Storm Shark")
        # (missed: the line's id taken as the caster's subcircle, as Parser._missed reads it)
        L.line("CORE_SEER", "{IsSim:0} Participant (id 4) missed")
        # (a line the game logged three times over: "| (x3)")
        L.line("CombatDetails", "AddHangingEffect. Target:0 Effect:kModifyIncomingDamage Charm:No Param:30 | (x3)")
        casts = L.p.duel["rounds"][-1]["casts"]
        self.assertEqual((casts[0]["spell"], casts[0]["pass"]), (None, True))
        self.assertTrue(casts[1]["missed"])
        self.assertEqual(casts[1]["hang"], [[0, "kModifyIncomingDamage", 0, 30]] * 3)

    def test_party_and_ally(self):
        # (a teammate at sc 5: an ally of my team; its wizard's add has no template name)
        L = Log().duel_start(others=((5, 31, 888, "Bob"),))
        L.planning()
        L.execution([(11, 1, 501, 1, 0), (21, 0, 3000, 1, 0), (31, 0, 2500, 1, 0)])
        d = L.p.duel
        self.assertEqual(sorted(d["parts"]), [0, 4, 5])
        self.assertTrue(d["parts"][5]["wiz"])
        self.assertEqual([R.side_of(d, d["parts"][s]) for s in (0, 4, 5)], ["enemy", "me", "ally"])

    def test_checkpoint_round_trip(self):
        L = Log().duel_start()
        L.planning()
        L.execution([(11, 1, 501, 1, 0), (21, 0, 3000, 1, 0)])
        L.cast(1, 4, "Stormblade")
        s = R.Parser.save(L.p)
        import json
        q = R.Parser()
        q.load(json.loads(json.dumps(s)))
        self.assertEqual(q.duel["parts"][0]["obj"], "CL_Rat-R3")
        self.assertIs(q.ctx(q.duel), q.duel["rounds"][-1]["casts"][0])
        # (the rest of the duel fed to the loaded one goes on where it was)
        L.p = q
        L.hang(4, "kModifyOutgoingDamage", True, 35)
        self.assertEqual(q.duel["rounds"][-1]["casts"][0]["hang"], [[4, "kModifyOutgoingDamage", 1, 35]])


# ============================================================================ the bot's posts and its rules
class Posts(unittest.TestCase):
    def test_unesc(self):
        self.assertEqual(R.unesc("a\\tb\\nc\\\\d"), "a\tb\nc\\d")
        self.assertEqual(R.unesc("caf\\u00e9"), "café")
        self.assertEqual(R.unesc("\\ud83d\\ude00"), "\U0001F600")            # (a pair made one character)
        self.assertEqual(R.unesc("plain"), "plain")

    def test_parse_body(self):
        body = ("duel\t7445553\nround\t3\nrole\thitter\n"
                "L\t12\t  UseHit hit3: found=1\nL\t40\tsee http://x - token\nL\tx\tno number\nL\tbroken\n")
        f, lines, dropped = R.parse_body(body.encode("ascii"))
        self.assertEqual((f["duel"], f["round"], f["role"]), ("7445553", "3", "hitter"))
        self.assertEqual(lines, [[12, "  UseHit hit3: found=1"], [40, "(line left out)"], [None, "no number"]])
        self.assertEqual(dropped, 0)
        many = "".join("L\t%d\tline %d\n" % (i, i) for i in range(R.LINES_CAP + 5))
        _f, lines, dropped = R.parse_body(many)
        self.assertEqual((len(lines), dropped), (R.LINES_CAP, 5))
        self.assertEqual(R.parse_body(None), ({}, [], 0))

    def test_classify(self):
        def rule(*texts):
            return R.classify([[i, t] for i, t in enumerate(texts)])[0]
        self.assertEqual(rule("  kill check: 700/2400 -> hit3", "  UseHit hit3: found=1"), "kill")
        # (a kill check with nothing cast after it: the round's other rule)
        self.assertEqual(rule("  kill check: 700/2400 -> hit3", "  UseBlade storm/blade: found=1"), "blade")
        self.assertEqual(rule("  you're playing - leaving this round to you"), "user")
        self.assertEqual(rule("  own health: 900/3000 - healing", "  UseHit hit1: found=1"), "heal")
        self.assertEqual(rule("  healer: Bob at 20% (under 40%) - a heal on Bob"), "party-heal")
        self.assertEqual(rule("  blader: Tower Shield on Bob"), "party-shield")
        self.assertEqual(rule("  UseTrap storm/trap: found=1"), "trap")
        self.assertEqual(rule("  Click aura: found=1"), "aura")
        self.assertEqual(rule("  Click pass: found=1"), "pass")
        self.assertEqual(rule("  nothing matches here"), "other")
        rule_, plan, casts = R.classify([[0, "  plan: Storm Lord (hit3): storm"], [5, "@cast Storm Lord"],
                                         [6, "  UseHit hit3: found=1"]])
        self.assertEqual((rule_, plan, casts), ("hit", "Storm Lord (hit3): storm", ["Storm Lord"]))
        self.assertEqual(R.classify([]), ("other", None, []))


# ============================================================================ a battle record
def hand_reading(cards, health=3000, most=3000):
    return {"in_battle": True, "planning": True, "settled": True,
            "me": {"health": health, "max_health": most, "school": "storm",
                   "pips": {"generic": 1, "power": 0, "storm": 0}},
            "cards": cards}


def hcard(slot, name, kind, tid, pips=0):
    return {"slot": slot, "name": name, "display": name, "kind": kind, "school": "Storm", "pips": pips,
            "template_id": tid, "enchantment_id": 0, "castable": True, "value_text": "35%" if kind == "blade" else
            "900-1000", "heads_text": "storm:900" if kind == "damage" else "", "boosts_text": "storm:35" if kind == "blade"
            else ""}


class Record(unittest.TestCase):
    def build(self):
        L, t1, t2 = two_round_win()
        d = L.p.closed[0]
        r1 = hand_reading([hcard("Card1", "Storm Lord", "damage", 101, 7), hcard("Card2", "Stormblade", "blade", 104)])
        r2 = hand_reading([hcard("Card1", "Storm Lord", "damage", 101, 7)], health=2880)
        hands = []
        for tk, r in ((t1 + 200, r1), (t2 + 200, r2)):
            hand, _facts = R.slim_hand(r)
            key = R.hand_key(r)
            hands.append({"tk": tk, "key": [list(key[0]), key[1], [list(x) for x in key[2]]], "hand": hand,
                          "src": "bot"})
        f1, lines1, _d = R.parse_body("duel\t%d\nround\t1\nrole\thitter\nL\t5\t  plan: Storm Lord (hit3): storm\n"
                                      "L\t9\t  UseBlade storm/blade: found=1\nL\t10\t@cast Stormblade\n" % DUEL)
        f2, lines2, _d = R.parse_body("duel\t%d\nround\t2\nrole\thitter\nL\t3\t  kill check: 501/501 -> hit3\n"
                                      "L\t8\t  UseHit hit3: found=1\n" % DUEL)
        posts = [{"tk": t1 + 900, "at": t1 + 500, "open": t1 + 500, "f": dict(f1, ev="round"), "lines": lines1,
                  "dropped": 0},
                 {"tk": t2 + 900, "at": t2 + 500, "open": t2 + 500, "f": dict(f2, ev="round"), "lines": lines2,
                  "dropped": 0}]
        env = {"state": {"name": "Ned Stormblade", "school": "storm"}, "hello": {"ver": "v1.3.0", "dual": "0"},
               "own": [], "posts": posts, "hands": hands, "battles": [], "who": [], "mobinfo": {}, "deck": None,
               "stats": None, "settings": {"planner": 0}, "chars": {}, "build": None, "mem_src": "on", "ahk_src": "on",
               "own_why": {}, "hand_why": None, "partial_why": None, "displays": {}}
        return R.build_record(d, env)

    def test_record_fields(self):
        rec = self.build()
        self.assertEqual((rec["rec"], rec["v"], rec["duel"], rec["duel_gid"], rec["result"], rec["rounds_n"]),
                         ("battle", R.V, DUEL, GID, "won", 2))
        self.assertTrue(rec["id"].endswith("-%d" % DUEL))
        self.assertEqual(rec["who"], {"bot": [1, 2], "user": [], "none": [], "unknown": []})
        me = rec["me"]
        self.assertEqual((me["sc"], me["school"], me["hp0"], me["max0"], me["role"]), (4, "storm", 3000, 3000, "hitter"))
        rat = next(p for p in rec["parts"] if p["sc"] == 0)
        self.assertEqual((rat["side"], rat["obj"], rat["rank"], rat["rank_src"], rat["died_round"], rat["killed_by"]),
                         ("enemy", "CL_Rat-R3", 3, "obj", 2, 4))
        self.assertEqual((rat["max"], rat["max_src"]), (501, "log"))
        r1, r2 = rec["rounds"]
        self.assertEqual((r1["played"]["spell"], r1["played"]["tid"], r1["played"]["hand_i"], r1["played"]["by"]),
                         ("Stormblade", 104, 1, "bot"))
        self.assertEqual((r1["bot"]["rule"], r1["bot"]["plan"], r1["bot"]["casts"]),
                         ("blade", "Storm Lord (hit3): storm", ["Stormblade"]))
        self.assertEqual((r2["played"]["spell"], r2["played"]["hand_i"], r2["played"]["targets"]), ("Storm Lord", 0, [0]))
        self.assertEqual(r2["bot"]["rule"], "kill")
        self.assertEqual((r1["hand_src"], len(r1["hand"]), r1["pips"]["generic"], r1["hp"]), ("bot", 2, 1, 3000))
        self.assertEqual(r2["died"], [0])
        self.assertEqual(rec["src"]["hands"], "2/2")
        self.assertIsNone(rec["partial"])
        self.assertEqual(rec["party"]["size"], 1)
        # (JSON as the store writes it - compact, ASCII)
        self.assertTrue(R.dumps(rec).startswith('{"rec":"battle"'))

    def test_who_without_a_post(self):
        L, _t1, _t2 = two_round_win()
        env = {"state": {}, "hello": {}, "posts": [], "hands": [], "who": [{"tk": 0, "bot": 0, "acting": 1, "pfm": 0}]}
        rec = R.build_record(L.p.closed[0], env)
        # (no bot post, the bot off: you played it)
        self.assertEqual(rec["who"]["user"], [1, 2])
        self.assertEqual(rec["rounds"][0]["hand"], None)
        self.assertEqual(rec["rounds"][0]["played"]["hand_i"], None)


# ============================================================================ the charms on now
FACTS = {104: {"tid": 104, "name": "Stormblade", "school": "Storm", "kind": "blade", "boosts": "storm:35"},
         105: {"tid": 105, "name": "Storm Trap", "school": "Storm", "kind": "trap", "boosts": "storm:30"},
         106: {"tid": 106, "name": "Fireblade", "school": "Fire", "kind": "blade", "boosts": "fire:35"},
         101: {"tid": 101, "name": "Storm Lord", "school": "Storm", "kind": "damage", "heads": "storm:900"},
         107: {"tid": 107, "name": "Elemental Blade", "school": "Balance", "kind": "blade",
               "boosts": "fire:25,ice:25,storm:25"}}


def duel(*rounds, me=4):
    return {"me_sc": me, "rounds": [{"n": k + 1, "casts": list(cs)} for k, cs in enumerate(rounds)]}


def cast(sc, spell, hang=(), hp=(), fx=(), **kw):
    c = {"sc": sc, "spell": spell}
    if hang:
        c["hang"] = [list(h) for h in hang]
    if hp:
        c["hp"] = [list(h) for h in hp]
    if fx:
        c["fx"] = [list(f) for f in fx]
    c.update(kw)
    return c


class Charms(unittest.TestCase):
    def test_on_and_used_up(self):
        d = duel([cast(4, "Stormblade", [(4, "kModifyOutgoingDamage", 1, 35)]),
                  cast(5, "Storm Trap", [(0, "kModifyIncomingDamage", 0, 30)]),
                  cast(0, "Dark Shield", [(0, "kModifyIncomingDamage", 0, -50)])],
                 [cast(5, "Fireblade", [(4, "ModifyOutgoingDamage", 1, 35)])])
        c = R.charms_now(d, FACTS)
        me, rat = c["by"][4], c["by"][0]
        self.assertEqual([(x["spell"], x["pct"], x["schools"]) for x in me["blades"]],
                         [("Stormblade", 35, ["storm"]), ("Fireblade", 35, ["fire"])])
        self.assertEqual([(x["pct"], x["schools"], x["by"]) for x in rat["traps"]], [(30, ["storm"], 5)])
        # (an enemy's own shield: its spell isn't in cards.jsonl - it fits every school, and that's said)
        self.assertEqual([(x["pct"], x["schools"]) for x in rat["shields"]], [(50, None)])
        self.assertTrue(any("not in cards.jsonl" in w for w in c["why"]))
        self.assertEqual((c["me"], c["round"], c["n"]), (4, 2, 4))
        # (round 3: Storm Lord on the rat - my Stormblade, its Storm Trap and its shield used; the Fireblade stays)
        d["rounds"].append({"n": 3, "casts": [cast(4, "Storm Lord", hp=[(0, 900, -400)], fx=[(0, "kDamage", 900)])]})
        c = R.charms_now(d, FACTS)
        self.assertEqual([x["spell"] for x in c["by"][4]["blades"]], ["Fireblade"])
        self.assertEqual((c["by"][0]["traps"], c["by"][0]["shields"]), ([], []))

    def test_identical_blades_dont_stack_traps_do(self):
        d = duel([cast(4, "Stormblade", [(4, "kModifyOutgoingDamage", 1, 35)]),
                  cast(5, "Stormblade", [(4, "kModifyOutgoingDamage", 1, 35)]),
                  cast(4, "Storm Trap", [(0, "kModifyIncomingDamage", 0, 30)]),
                  cast(5, "Storm Trap", [(0, "kModifyIncomingDamage", 0, 30)])])
        c = R.charms_now(d, FACTS)
        self.assertEqual(len(c["by"][4]["blades"]), 1)
        self.assertEqual(len(c["by"][0]["traps"]), 2)

    def test_a_hit_uses_only_what_fits(self):
        # (an enemy's hit on me - its school not known: every ward on me used; my Fire hit uses only a fire blade)
        d = duel([cast(4, "Fireblade", [(4, "kModifyOutgoingDamage", 1, 35)]),
                  cast(4, "Stormblade", [(4, "kModifyOutgoingDamage", 1, 35)]),
                  cast(0, "Curse", [(4, "kModifyIncomingDamage", 0, 25), (4, "kModifyOutgoingDamage", 1, -30)])],
                 [cast(0, "Bite", hp=[(4, 3000, -200)])],
                 [cast(4, "Fire Cat", hp=[(0, 500, -100)])])
        facts = dict(FACTS)
        facts[110] = {"tid": 110, "name": "Fire Cat", "school": "Fire", "kind": "damage", "heads": "fire:100"}
        c = R.charms_now(d, facts)
        self.assertEqual(c["by"][4]["traps"], [])               # (the enemy's trap on me: its bite used it)
        self.assertEqual([x["spell"] for x in c["by"][4]["blades"]], ["Stormblade"])
        self.assertEqual(c["by"][4]["weak"], [])                # (a weakness, -30 out: used by my next hit, unknown school)

    def test_missed_passes_and_removed(self):
        d = duel([cast(4, "Stormblade", [(4, "kModifyOutgoingDamage", 1, 35)]),
                  cast(4, "Storm Lord", hp=[(0, 900, -400)], missed=True),
                  cast(0, None, **{"pass": True})],
                 [cast(5, "Storm Trap", [(0, "kModifyIncomingDamage", 0, 30)],
                       removed=[[0, "kModifyIncomingDamage", 30, "ward"]])])
        c = R.charms_now(d, FACTS)
        self.assertEqual(len(c["by"][4]["blades"]), 1)          # (a missed hit uses nothing)
        self.assertEqual(c["by"][0]["traps"], [])               # (a REMOVED line took it off)

    def test_a_charms_own_effect_is_no_hit(self):
        # (were ProcessTargets written for a trap's own effect - kModifyIncomingDamage has "damage" in its name - it's
        # no hit: my Stormblade and the trap on already stay; a damage effect alone (no ModifyHealth line) still hits)
        curse = [(4, "kModifyIncomingDamage", 0, 25)]
        d = duel([cast(4, "Stormblade", [(4, "kModifyOutgoingDamage", 1, 35)]),
                  cast(5, "Storm Trap", [(0, "kModifyIncomingDamage", 0, 30)]),
                  cast(0, "Curse", curse, fx=[(4, "kModifyIncomingDamage", 25)])],
                 [cast(4, "Storm Trap", [(0, "kModifyIncomingDamage", 0, 30)], fx=[(0, "kModifyIncomingDamage", 30)]),
                  cast(0, "Curse", curse, fx=[(4, "ModifyIncomingDamage", 25)])])
        c = R.charms_now(d, FACTS)
        self.assertEqual([x["spell"] for x in c["by"][4]["blades"]], ["Stormblade"])
        self.assertEqual((len(c["by"][0]["traps"]), len(c["by"][4]["traps"])), (2, 2))
        d["rounds"].append({"n": 3, "casts": [cast(4, "Storm Lord", fx=[(0, "kDamage", 900)])]})
        c = R.charms_now(d, FACTS)
        self.assertEqual((c["by"][4]["blades"], c["by"][0]["traps"]), ([], []))

    def test_named_as_the_hand_shows_it(self):
        # (the log's spell is the template's name; name: cards.jsonl's display - battlesim.card_of's for a hand card)
        facts = {104: {"tid": 104, "name": "Storm Blade", "display": "Stormblade", "kind": "blade",
                       "boosts": "storm:35"}}
        d = duel([cast(4, "Storm Blade", [(4, "kModifyOutgoingDamage", 1, 35)]),
                  cast(0, "Dark Shield", [(0, "kModifyIncomingDamage", 0, -50)])])
        c = R.charms_now(d, facts)
        b = c["by"][4]["blades"][0]
        self.assertEqual((b["spell"], b["name"], b["schools"]), ("Storm Blade", "Stormblade", ["storm"]))
        self.assertEqual(c["by"][0]["shields"][0]["name"], "Dark Shield")    # (not in the facts: the log's)

    def test_absorb_soaks_damage(self):
        # (fix2: the hit's own number, not the health lost past the absorb - ModifyHealth's delta is after it: a hit it
        # soaked loses no health, and health lost means it soaked all it had)
        d = duel([cast(4, "Spirit Armor", [(4, "kAbsorbDamage", 1, 500)])],
                 [cast(0, "Bite", fx=[(4, "kDamage", 200)])])
        c = R.charms_now(d, FACTS)
        self.assertEqual([x["pct"] for x in c["by"][4]["absorb"]], [300])
        d["rounds"][1]["casts"] = [cast(0, "Bite", hp=[(4, 3000, -200)], fx=[(4, "kDamage", 700)])]
        self.assertEqual(R.charms_now(d, FACTS)["by"][4]["absorb"], [])

    def test_record_shaped_and_junk(self):
        rec = {"me": {"sc": 4}, "rounds": [{"n": 1, "casts": [cast(4, "Stormblade", [(4, "kModifyOutgoingDamage", 1, 35)])]}]}
        self.assertEqual(R.charms_now(rec, FACTS)["by"][4]["blades"][0]["schools"], ["storm"])
        for junk in (None, [], {"rounds": "x"}, {"rounds": [None, {"casts": [None, {"sc": 4, "spell": "x",
                                                                                     "hang": [[1, 2], "q", None]}]}]},
                     {"rounds": [{"casts": [{"sc": 4, "spell": "x", "hp": [[None, 1, -5]], "hang": [[4, None, 1, 35]]}]}]}):
            c = R.charms_now(junk, None)
            self.assertIsInstance(c["by"], dict)
        self.assertEqual(R.charms_now({"rounds": []})["n"], 0)

    def test_from_the_parser(self):
        # (the recorder's own open duel - the log's lines as the parser keeps them)
        L = Log().duel_start()
        L.planning()
        L.execution([(11, 1, 501, 1, 0), (21, 0, 3000, 1, 0)])
        L.cast(1, 4, "Elemental Blade")
        L.hang(4, "kModifyOutgoingDamage", True, 25)
        L.cast(1, 0, "Rat Shield")
        L.hang(0, "kModifyIncomingDamage", False, -40)
        c = R.charms_now(L.p.duel, FACTS)
        self.assertEqual(c["by"][4]["blades"][0]["schools"], ["fire", "ice", "storm"])
        self.assertEqual(c["by"][0]["shields"][0]["pct"], 40)


if __name__ == "__main__":
    unittest.main()
