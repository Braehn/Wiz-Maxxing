"""test_plan.py - the round planner's checks (battlesim.plan_round / plan_lines, vision.py /plan's plan_lines_for with
stand-in readers shaped as handmem's and bossmem's readings), the 'planner' rule of the battle recorder, and /sim and
/decks on deckmem-shaped decks whose item cards' facts are value_text strings (standard library only):
    python -m unittest test_plan          (from AutoFarmer\\vision)"""
import os
import random
import sys
import time
import types
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import battlesim as S  # noqa: E402


def C(name, kind, pips=0, value=0, school="storm", **kw):
    return S.Card(name, kind, school, pips, value=value, **kw)


LORD = C("Storm Lord", "damage", 7, 1000, tid=101)
SNAKE = C("Thunder Snake", "damage", 2, 150, tid=102)
TEMPEST = C("Tempest", "aoe", 6, 400, tid=103)
BLADE = C("Stormblade", "blade", 0, 35, tid=104)
TRAP = C("Storm Trap", "trap", 0, 30, tid=105)
HEAL = C("Satyr", "heal", 3, 900, school="life", tid=106)
DECK = [LORD] * 4 + [SNAKE] * 6 + [TEMPEST] * 4 + [BLADE] * 4 + [TRAP] * 4 + [HEAL] * 3


def foe(name="Rat", hp=1200, lo=100, hi=150, pips=1, boss=False):
    return S.Foe(name, hp, spells=[("Bite", 1.0, {"pips": pips, "min": lo, "max": hi, "accuracy": 100})], boss=boss)


def sure_me(**kw):
    """a storm wizard whose cards never miss (70 + 30 % accuracy)"""
    kw.setdefault("accuracy", 30)
    return S.Me("storm", kw.pop("maxhp", 3000), **kw)


class PlanRound(unittest.TestCase):
    def test_kill_now_beats_boosting(self):
        st = S.State.of_deck([LORD, BLADE, TRAP, SNAKE], DECK, pips=7, fhp=[900], rnd=4, me_first=True)
        p = S.plan_round(st, sure_me(damage=60), [foe()], seed=1)
        best = p["plays"][0]
        self.assertEqual((best["name"], best["kind"], best["aim"]), ("Storm Lord", "damage", 0))
        self.assertGreater(best["kill"], 0.95)
        self.assertEqual(best["rounds"], 1)
        self.assertTrue(best["chain"])                # (the bot's own kill check picks it too)
        self.assertIn("ends it this round", best["why"])

    def test_blade_then_hit_beats_a_weak_hit(self):
        # (6 pips, no power pips: Storm Lord next round - with a blade now it kills (1000 x 2 x 1.35 x 0.85 = 2295);
        # Thunder Snake now spends the pips it needs: the Lord two rounds later)
        st = S.State.of_deck([LORD, BLADE, SNAKE], DECK, pips=6, fhp=[2200], rnd=3, me_first=True)
        p = S.plan_round(st, sure_me(damage=100, power_pip=0), [foe("Boss", 2200, 50, 80, boss=True)],
                         S.Opts(cardlogic=2, boss=True), seed=2, budget_ms=2000)
        by = {pl["name"]: pl for pl in p["plays"]}
        self.assertEqual(p["plays"][0]["name"], "Stormblade")
        self.assertGreater(by["Stormblade"]["score"], by["Thunder Snake"]["score"])
        self.assertEqual(by["Stormblade"]["rounds"], 2)
        self.assertGreater(by["Thunder Snake"]["rounds"], 2)

    def test_heal_when_the_next_hit_kills(self):
        st = S.State.of_deck([HEAL, SNAKE], DECK, pips=4, hp=400, fhp=[5000], rnd=5, me_first=False)
        p = S.plan_round(st, sure_me(), [foe("Brute", 5000, 500, 600)], seed=3)
        self.assertEqual(p["plays"][0]["kind"], "heal")
        snake = next(pl for pl in p["plays"] if pl["name"] == "Thunder Snake")
        self.assertGreater(snake["lost"], 0.9)

    def test_pass_when_nothing_is_payable(self):
        st = S.State.of_deck([LORD, TEMPEST], DECK, pips=2, fhp=[900], rnd=2)
        p = S.plan_round(st, sure_me(), [foe()], seed=4)
        self.assertEqual([pl["kind"] for pl in p["plays"]], ["pass"])
        self.assertTrue(any("not paid for" in w for w in p["why"]))
        self.assertTrue(S.plan_lines(p, [foe()])[0].startswith("plan|-1|||pass|"))

    def test_single_target_tried_at_each_enemy(self):
        st = S.State.of_deck([SNAKE, TRAP, TEMPEST, BLADE], DECK, pips=6, fhp=[500, 900, 0], rnd=2)
        p = S.plan_round(st, sure_me(), [foe("A", 900), foe("B", 900), foe("C", 900)], seed=5)
        aims = sorted(pl["aim"] for pl in p["plays"] if pl["name"] == "Thunder Snake")
        self.assertEqual(aims, [0, 1])                # (the dead one isn't a target)
        self.assertEqual([pl["aim"] for pl in p["plays"] if pl["name"] == "Tempest"], [None])

    def test_copies_and_switched_off_once(self):
        st = S.State.of_deck([SNAKE, SNAKE, BLADE], DECK, pips=4, fhp=[900], rnd=2)
        p = S.plan_round(st, sure_me(), [foe()], S.Opts(useblades=0), seed=6)
        self.assertEqual(sorted(pl["name"] for pl in p["plays"]), ["Thunder Snake", "pass"])
        self.assertTrue(any("switched off" in w for w in p["why"]))

    def test_same_seed_same_answer(self):
        st = S.State.of_deck([LORD, BLADE, TRAP, SNAKE, TEMPEST], DECK, pips=5, fhp=[2000, 1500], rnd=2)
        foes = [foe("A", 2000), foe("B", 1500)]
        a = S.plan_round(st, sure_me(), foes, n=40, seed=9, budget_ms=5000)
        b = S.plan_round(st, sure_me(), foes, n=40, seed=9, budget_ms=5000)
        strip = lambda p: [(x["name"], x["aim"], x["n"], x["won"], round(x["score"], 9)) for x in p["plays"]]  # noqa: E731
        self.assertEqual(strip(a), strip(b))
        self.assertEqual(S.plan_lines(a, foes), S.plan_lines(b, foes))

    def test_within_budget(self):
        hand = [LORD, BLADE, TRAP, SNAKE, TEMPEST, HEAL, C("Storm Shark", "damage", 3, 300, tid=107)]
        st = S.State.of_deck(hand, DECK, pips=7, hp=1500, fhp=[2000, 1500, 1800, 2500], rnd=3)
        foes = [foe("E%d" % i, 2500) for i in range(4)]
        t = time.perf_counter()
        p = S.plan_round(st, sure_me(), foes, n=2000, budget_ms=60, seed=1)
        ms = (time.perf_counter() - t) * 1000
        self.assertTrue(p["plays"])
        self.assertLess(ms, 60 + 150)                 # (one round robin past the budget at most)
        self.assertTrue(any("in the time given" in w for w in p["why"]))

    def test_prior_nudges_and_is_quoted(self):
        st = S.State.of_deck([BLADE, TRAP], DECK, pips=3, fhp=[5000], rnd=2)
        foes = [foe("Boss", 5000, boss=True)]
        seen = {}

        def prior(sit):
            seen.update(sit)
            return {"trap": 1.0, "blade": -1.0}, "learned: traps won here"
        p = S.plan_round(st, sure_me(), foes, n=30, seed=1, budget_ms=5000, prior=prior)
        self.assertEqual(p["learned"], "learned: traps won here")
        self.assertEqual((seen["school"], seen["pips"], seen["alive"], seen["boss"], seen["hit"]), ("storm", 3, 1, True,
                                                                                                    False))
        by = {pl["kind"]: pl for pl in p["plays"]}
        self.assertAlmostEqual(by["trap"]["bonus"], S.PRIOR_W)
        self.assertAlmostEqual(by["blade"]["bonus"], -S.PRIOR_W)
        self.assertIn("learned +", by["trap"]["why"])
        self.assertTrue(any(ln.startswith("learned|") for ln in S.plan_lines(p, foes)))

    def test_junk_never_raises(self):
        for st, me, foes in ((None, S.Me(), [foe()]), (S.State(None), S.Me(), [foe()]), (S.State([LORD]), S.Me(), []),
                             (S.State(["x", None], pips="abc", fhp=["?"], blades=[(1, "x")], aura=("x", "y"),
                                      traps="junk", rnd=float("inf")), S.Me(), [foe()]),
                             (S.State([LORD], fhp=[0]), S.Me(), [foe()])):
            p = S.plan_round(st, me, foes, budget_ms=20)
            self.assertIsInstance(p["plays"], list)
            lines = S.plan_lines(p, foes)
            self.assertTrue(lines and all(isinstance(ln, str) for ln in lines))
        self.assertEqual(S.plan_lines(S.plan_round(S.State([LORD]), S.Me(), []), [])[0], "none|no enemies")
        self.assertEqual(S.plan_lines(None, []), ["none|nothing to plan"])


class FromStateLines(unittest.TestCase):
    def test_plan_line_fields(self):
        st = S.State.of_deck([SNAKE, TEMPEST, BLADE], DECK, pips=6, fhp=[400, 900], rnd=2)
        foes = [foe("A", 900), foe("B", 900)]
        p = S.plan_round(st, sure_me(), foes, seed=1)
        lines = S.plan_lines(p, foes, ids=[(2, "Card3", 102), (4, "Card5", 103), (5, "Card6", 104)])
        f = lines[0].split("|")
        self.assertEqual(f[0], "plan")
        self.assertEqual(len(f), 15)
        names = {"Thunder Snake": ("2", "Card3", "102"), "Tempest": ("4", "Card5", "103"),
                 "Stormblade": ("5", "Card6", "104"), "pass": ("-1", "", "")}
        self.assertEqual(tuple(f[1:4]), names[f[10]])
        for ln in lines:
            g = ln.split("|")
            if g[0] in ("plan", "alt", "chain"):
                self.assertEqual(len(g), 15)
                if g[4] == "aoe":
                    self.assertEqual((g[5], g[11]), ("all", "all"))
                elif g[4] == "damage":
                    self.assertIn(g[11], ("A", "B"))


class BotBlades(unittest.TestCase):
    """review fix: the bot's keys for the blades on (KillCalc.ahk AppliedBlades - storm/blade, blade3...) named as the
    cards', so a copy in hand of a blade on is 'on already' - never tried, picked by the chain or stacked"""

    def test_plain_keys_named_as_the_card(self):
        bal = C("Balanceblade", "blade", 0, 25, school="balance", boosts={"all": 25}, tid=201)
        every = C("Bladestorm", "blade", 0, 20, school="balance", boosts={s: 20 for s in S.SCHOOLS}, tid=202)
        elem = C("Elemental Blade", "blade", 0, 25, school="balance", boosts={"fire": 25, "ice": 25, "storm": 25})
        edge = C("Storm Edge", "blade", 0, 45, boosts={"storm": 45})
        cards = [LORD, BLADE, BLADE, edge, bal, every, elem]
        got = S.bot_blades([("storm/blade", {"storm": 35.0}), ("blade3", {"all": 25.0}), ("blade4", {"all": 20.0}),
                            ("elementalblade", {"fire": 25.0, "ice": 25.0, "storm": 25.0}),
                            ("spiritblade", {"death": 25.0, "life": 25.0, "myth": 25.0})], cards)
        self.assertEqual([n for n, _b in got], ["Stormblade", "Balanceblade", "Bladestorm", "Elemental Blade",
                                                "spiritblade"])        # (no card fits the spirit schools: kept)
        self.assertEqual(got[0][1], {"storm": 35.0})                  # (the bot's own %)
        # (two blades of one school: the nearest %)
        self.assertEqual(S.bot_blades([("storm/blade", {"storm": 44.0})], cards), [("Storm Edge", {"storm": 44.0})])
        # (already a card's name: as it is)
        self.assertEqual(S.bot_blades([("Stormblade", {"storm": 35})], cards), [("Stormblade", {"storm": 35})])

    def test_copies_keep_the_bots_key(self):
        # (a sharpened cast or a treasure / item card's copy: the bot counts it on top of the deck's plain one)
        keys = [("storm/blade+", {"storm": 40.0}), ("storm/blade@item", {"storm": 35.0}),
                ("storm/blade@tc", {"storm": 35.0}), ("storm/blade@item+", {"storm": 40.0})]
        self.assertEqual(S.bot_blades(keys, [BLADE, LORD]), keys)
        # (only a treasure / pet copy among the cards: the deck's plain cast isn't named after it)
        tc = C("Stormblade", "blade", 0, 35, boosts={"storm": 35}, tid=104, tc=True)
        pet = C("Stormblade", "blade", 0, 35, boosts={"storm": 35}, tid=304, item=True)
        plain = [("storm/blade", {"storm": 35.0})]
        self.assertEqual(S.bot_blades(plain, [tc, pet]), plain)
        # (v1.7.0: a treasure / item card's copy named after such a card of its own kind - <name>@tc stacks with the
        # deck's copy, as the bot counts it)
        self.assertEqual(S.bot_blades([("storm/blade@tc", {"storm": 35.0})], [tc]),
                         [("Stormblade@tc", {"storm": 35.0})])
        self.assertEqual(S.bot_blades([("storm/blade@item", {"storm": 35.0})], [tc, pet]),
                         [("Stormblade@item", {"storm": 35.0})])

    def test_junk_never_raises(self):
        self.assertEqual(S.bot_blades(None, None), [])
        self.assertEqual(S.bot_blades([("x", {"storm": 35})], [5, None, "a"]), [("x", {"storm": 35})])
        self.assertEqual(S.bot_blades([("x", None), ("y", "z"), 7, ("a", "b", "c")], [BLADE]),
                         [("x", None), ("y", "z"), 7, ("a", "b", "c")])
        self.assertEqual(S.bot_blades([("storm/blade", {"storm": "35"})], 12), [("storm/blade", {"storm": "35"})])

    def test_a_blade_on_isnt_cast_again(self):
        """the reviewers' case: a Stormblade on (the bot's storm/blade), another in hand, Storm Lord not paid for yet"""
        foes = [S.Foe("Boss", 9000, boss=True)]
        opts = S.Opts(boss=True)
        hand, pile = [BLADE, LORD], [LORD] * 3 + [BLADE] * 3 + [SNAKE] * 6
        st = S.State(hand, pile, pips=3, fhp=[9000], me_first=True,
                     blades=S.bot_blades([("storm/blade", {"storm": 35.0})], hand + pile))
        b = S._Battle.from_state(st, sure_me(), foes, opts, random.Random(1))
        self.assertEqual(S._plannable(BLADE, opts, b), "on already")
        self.assertIsNone(b.choose())                                 # (the chain casts no second copy: a pass)
        self.assertIsNone(b.pick_boost(LORD))
        p = S.plan_round(st, sure_me(), foes, opts, n=20, seed=1, budget_ms=2000)
        self.assertEqual([x["name"] for x in p["plays"]], ["pass"])
        self.assertIn("1 card in hand not tried (on already)", p["why"])
        # (cast all the same - as the simulator's chain never does -, it doesn't stack: one blade on)
        b.me.accuracy = 100
        b.cast(BLADE)
        self.assertEqual(b.blades, [("Stormblade", {"storm": 35.0})])
        # (a pet's copy on - storm/blade@item -: the deck's Stormblade in hand still goes, as the bot casts it)
        st = S.State(hand, pile, pips=3, fhp=[9000], me_first=True,
                     blades=S.bot_blades([("storm/blade@item", {"storm": 40.0})], hand + pile))
        p = S.plan_round(st, sure_me(), foes, opts, n=20, seed=1, budget_ms=2000)
        self.assertIn("Stormblade", [x["name"] for x in p["plays"]])


def planner_text(ans, ms=300):
    """Planner.ahk PlannerText / PlannerAt, line for line (AHK's arrays count from 1: f[11] here is f[10]) - the advice
    line it logs from /plan's answer"""
    best = chain = None
    learned = ""
    for ln in ans:
        f = [""] + ln.split("|")
        if f[1] == "plan" and len(f) - 1 >= 15:
            best = f
        elif f[1] == "chain" and len(f) - 1 >= 15:
            chain = f
        elif f[1] == "learned":
            learned = ln[8:]

    def at(f):
        return " on all" if f[6] == "all" else (" at " + f[12]) if f[6] != "" else (" on you" if f[12] == "me" else "")
    t = "Plan: would play " + best[11] + at(best) + " (won " + best[7] + "%" + (
        (" in " + best[8] + " rounds") if best[8] != "" else "") + ", " + best[13] + " tries; " + best[10] + ")"
    if chain:
        t += " - your settings' way: " + chain[11] + at(chain) + " (won " + chain[7] + "%)"
    if best[4] != "":
        t += " [tid " + best[4] + "]"
    t += " - advice only (planner:1, %d ms)" % ms
    return t + ((" - " + learned[:150]) if learned else "")


def party_order_text(f, waited, names):
    """Party.ahk PartyOrderText / PartyOrderFoe, line for line (f as AHK splits /partyorder's line: f[1] 'order'; names
    the follower's own log names for the enemies - BlNames 0-3, matched as AHK's = matches: case aside)"""
    def foe(name):
        return next((n for n in names if name != "" and n.lower() == name.lower()), "")
    if f[7] == "all":
        at = " on all"
    elif foe(f[7]) != "":
        at = " at " + foe(f[7])
    elif f[7] != "":
        at = " at an enemy not named in this PC's log"
    else:
        at = ""
    return ("Plan: the leader would have you play " + f[4] + at + " (won " + f[8] + "%, " + f[9] + " tries)"
            + ((" [tid " + f[5] + "]") if f[5] != "" else "")
            + " - the leader's plan, advice only (partyorders, " + f[10] + " ms after it planned, waited " + str(waited)
            + " ms)" + ((" - " + f[11]) if f[11] != "" else ""))


class AdviceLine(unittest.TestCase):
    def test_order_line_text(self):
        # (partyorders: the follower's line for the leader's card - never the planner's advice to battlelearn --advice,
        # the enemy only in this PC's own words)
        import battlelearn
        import party
        names = ["Bonestriker", "Rattlebones Jr"]
        cases = [(("Stormblade", 104, "blade", ""), "104", None),
                 (("Lightning Strike", 777, "damage", "bonestriker"), "777", " at Bonestriker"),
                 (("Tempest", 103, "aoe", "all"), "103", " on all"),
                 (("pass", "", "pass", ""), None, None),
                 (("Storm Lord", 101, "damage", "Leader Named It"), "101", " at an enemy not named in this PC's log")]
        for (card, tid, kind, target), want_tid, want_at in cases:
            ln = party.order_cells("ok", 5, card, tid, kind, target, 80, 12, 1830, "")
            line = "  " + party_order_text([""] + ln.split("|"), 1200, names)
            self.assertIsNone(battlelearn.ADVICE_RX.search(line), line)          # (planner:1's statistics untouched)
            m = battlelearn.ADVICE_TID.search(line)
            self.assertEqual(m.group(1) if m else None, want_tid, line)
            self.assertIn("Plan: the leader would have you play " + card, line)
            self.assertIn("1830 ms after it planned, waited 1200 ms", line)
            if want_at:
                self.assertIn(want_at, line)
            self.assertNotIn("Leader Named It", line)
            self.assertNotIn("bonestriker", line)                               # (this PC's own spelling of it)

    def test_round_trip_to_the_recorder(self):
        # (plan_lines -> the line Planner.ahk logs -> what battlelearn reads back from the round's bot lines)
        import battlelearn
        import battlerec
        cases = [([LORD, BLADE], [900], "Storm Lord", 101), ([TEMPEST, SNAKE], [300, 300], "Tempest", 103),
                 ([LORD, TEMPEST], [900], "pass", None)]
        for hand, fhp, want, tid in cases:
            pips = 2 if want == "pass" else 7
            st = S.State.of_deck(hand, DECK, pips=pips, fhp=fhp, rnd=3, me_first=True)
            foes = [foe("E%d" % k, 900) for k in range(len(fhp))]
            p = S.plan_round(st, sure_me(damage=60), foes, seed=1, budget_ms=2000)
            ids = [(k, "Card%d" % (k + 1), c.tid) for k, c in enumerate(st.hand)]
            line = "  " + planner_text(S.plan_lines(p, foes, ids))
            self.assertEqual(battlerec.classify([[0, line]])[0], "other", line)     # (advice never decides a round)
            rows = battlelearn.advice_rows({"result": "won", "rounds": [
                {"n": 3, "bot": {"lines": [[10, line]]},
                 "played": None if want == "pass" else {"spell": want, "tid": tid}}]})
            self.assertEqual((rows[0]["advised"], rows[0]["tid"], rows[0]["same"]), (want, tid, True), line)


# ============================================================================ vision.py /plan (plan_lines_for)
def hand_card(slot, x, name, kind, school="Storm", pips=0, value=None, vtext="", tid=0, heads="", boosts="", xp=False,
              acc=None, treasure=False, item=False):
    """a card as handmem's reading has it (HandMem.read's cards)"""
    return {"slot": slot, "x": x, "shown": True, "name": name, "display": name, "school": school, "type": (kind or "").title(),
            "pips": pips, "x_pips": xp, "shadow_pips": 0, "castable": True, "treasure": treasure, "item_card": item,
            "enchantment": "", "accuracy": acc, "value": value, "value_text": vtext, "kind": kind, "dot": None,
            "school_pips": {}, "template_id": tid, "text": "", "heads_text": heads, "boosts_text": boosts}


def reading(cards, health=2500, most=3000, pips=None, settled=True):
    pp = {"generic": 3, "power": 2, "balance": 0, "death": 0, "fire": 0, "ice": 0, "life": 0, "myth": 0, "storm": 0,
          "shadow": 0}
    pp.update(pips or {})
    return {"in_battle": True, "planning": True, "settled": settled, "state": "hand" if settled else "changing",
            "why": "" if settled else "hand changing", "ms": 3.0,
            "me": {"health": health, "max_health": most, "school": "storm", "pips": pp}, "cards": cards}


def parts(*enemies, team=2):
    """a battle as bossmem / navmem's battle reading has it: me first, then the enemies (name, health, max, boss)"""
    out = [{"me": True, "team": 1, "player": True, "health": 2500, "max_health": 3000, "boss": False, "name": "",
            "mob": None, "owner": 1, "box": None, "root": None}]
    for k, (name, hp, most, boss) in enumerate(enemies):
        out.append({"me": False, "team": team, "player": False, "health": hp, "max_health": most, "boss": boss,
                    "name": name, "mob": {"title": "Undead", "school": "Death", "rank": 4}, "owner": 100 + k,
                    "box": (100 + 200 * k, 10, 180 + 200 * k, 40), "root": (0, 0, 1000, 600)})
    return out


HAND = [hand_card("Card1", 10, "Storm Lord", "damage", pips=7, value=1000, vtext="1000-1130", tid=101,
                  heads="storm:1000"),
        hand_card("Card2", 60, "Stormblade", "blade", value=35, vtext="35%", tid=104, boosts="storm:35"),
        hand_card("Card3", 110, "Storm Trap", "trap", value=30, vtext="30%", tid=105, boosts="storm:30"),
        hand_card("Card4", 160, "Thunder Snake", "damage", pips=2, value=150, vtext="150-170", tid=102,
                  heads="storm:150")]


def deckmem_deck(item_tid=None):
    """the worn deck as deckmem.read(kinds=True) has it: main cards with their kinds, item cards with no kind at all"""
    def dc(name, kind, pips, value, vtext, tid, count, heads="", boosts="", side="main"):
        return {"template_id": tid, "name": name, "display": name, "school": "Storm", "type": kind.title(), "pips": pips,
                "x_pips": False, "shadow_pips": 0, "school_pips": {}, "count": count, "enchantment_id": 0, "side": side,
                "known": True, "tc_flag": False, "max_copies": 4, "kind": kind, "value": value, "value_text": vtext,
                "heads_text": heads, "boosts_text": boosts}
    d = {"gid": 0xABC, "where": "equipped", "equipped": True, "sets": [1], "template_id": 1, "object_name": "Deck",
         "display": "Storm Deck", "school": "Storm", "limits": {}, "main_n": 22, "treasure_n": 0, "excluded": [],
         "item_n": 1, "ok": True, "why": "",
         "cards": [dc("Storm Lord", "damage", 7, 1000, "1000-1130", 101, 4, heads="storm:1000"),
                   dc("Thunder Snake", "damage", 2, 150, "150-170", 102, 6, heads="storm:150"),
                   dc("Stormblade", "blade", 0, 35, "35%", 104, 4, boosts="storm:35"),
                   dc("Storm Trap", "trap", 0, 30, "30%", 105, 4, boosts="storm:30"),
                   dc("Tempest", "aoe", 6, 400, "400-460", 103, 4, heads="storm:400")],
         "item_cards": []}
    if item_tid:
        d["item_cards"] = [{"name": "Lightning Strike", "template_id": item_tid, "count": 2, "display": "Lightning Strike",
                            "from": "Wand"}]
    return d


# (cards.jsonl's facts: the recorder writes handmem's value_text there - strings, not numbers)
FACTS = {777: {"rec": "card", "v": 1, "tid": 777, "name": "Lightning Strike", "display": "Lightning Strike",
               "school": "Storm", "kind": "damage", "pips": 0, "x": False, "value": "95-115", "heads": "storm:95",
               "boosts": None, "acc": 70, "full": True},
         888: {"rec": "card", "v": 1, "tid": 888, "name": "Pet Blade", "display": "Pet Blade", "school": "Storm",
               "kind": "blade", "pips": 0, "x": False, "value": "+20%", "heads": None, "boosts": "storm:20",
               "full": True}}


class PlanLinesFor(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            import vision
        except ImportError as e:                          # (numpy / Pillow: the helper's own needs)
            raise unittest.SkipTest("vision.py can't be imported here (%s)" % e)
        cls.V = vision
        cls.log = vision.log
        vision.log = lambda *a, **kw: None                # (nothing into vision\vision.log from the tests)

    @classmethod
    def tearDownClass(cls):
        cls.V.log = cls.log

    def ctx(self, decks=True, plays=None, facts=None):
        return {"book": S.FoeBook(battles=[]), "facts": FACTS if facts is None else facts, "plays": plays, "wiki": None,
                "casts": None, "decks": {"decks": [deckmem_deck(777)]} if decks else None}

    def ask(self, q, hand=None, battle=None, ctx=None, rd=None):
        cr = lambda: (rd if rd is not None else reading(HAND if hand is None else hand), "")          # noqa: E731
        br = lambda: (parts(("Bonestriker", 700, 2400, False)) if battle is None else battle, "")  # noqa: E731
        return self.V.plan_lines_for(q, cr, br, ctx if ctx is not None else self.ctx())

    def test_lethal_hit_with_slot_tid_and_target(self):
        out = self.ask({"seed": "1", "budget": "2000", "acc": "30", "first": "1"})
        f = out[0].split("|")
        self.assertEqual(f[0], "plan", out)
        self.assertEqual((f[1], f[2], f[3], f[4], f[5], f[10], f[11]),
                         ("0", "Card1", "101", "damage", "0", "Storm Lord", "Bonestriker"))
        self.assertTrue(any(ln.startswith("foe|0|Bonestriker|700|2400|0|0.1400") for ln in out), out)
        planned = next(ln for ln in out if ln.startswith("planned|")).split("|")
        self.assertGreater(int(planned[1]), 0)

    def test_not_settled_and_not_read(self):
        out = self.V.plan_lines_for({}, lambda: (reading(HAND, settled=False), ""), lambda: ([], ""), self.ctx())
        self.assertEqual(out, ["none|hand changing"])
        out = self.V.plan_lines_for({}, lambda: (None, "the game is not running"), lambda: ([], ""), self.ctx())
        self.assertEqual(out, ["none|the game is not running"])
        out = self.V.plan_lines_for({}, lambda: (reading([]), ""), lambda: ([], ""), self.ctx())
        self.assertEqual(out, ["none|no card in hand"])
        # (the hand changing - the bot's discards just made: asked again within the budget, then planned)
        reads = [reading(HAND, settled=False), reading(HAND, settled=False), reading(HAND)]
        out = self.V.plan_lines_for({"budget": "2000"}, lambda: (reads.pop(0) if len(reads) > 1 else reads[0], ""),
                                    lambda: (parts(("Rat", 500, 900, False)), ""), self.ctx())
        self.assertTrue(out[0].startswith("plan|"), out)

    def test_enemies_from_the_bot_when_memory_has_none(self):
        out = self.V.plan_lines_for({"foes": "Rat~1200~storm~0~300|~~~", "seed": "1", "budget": "2000"},
                                    lambda: (reading(HAND), ""), lambda: (None, "the game can't be read"), self.ctx())
        self.assertTrue(out[0].startswith("plan|"), out)
        self.assertTrue(any(ln.startswith("foe|0|Rat|300|1200|0|") for ln in out), out)
        self.assertTrue(any("as the bot named them" in ln for ln in out))
        out = self.V.plan_lines_for({}, lambda: (reading(HAND), ""), lambda: (None, "the game can't be read"),
                                    self.ctx())
        self.assertEqual(out, ["none|no enemies (the game can't be read)"])

    def test_bot_bookkeeping_reaches_the_state(self):
        got = {}
        real = S.plan_round

        def spy(state, me, foes, opts=None, **kw):
            got.update(state=state, me=me, foes=foes, opts=opts, kw=kw)
            return real(state, me, foes, opts, **kw)
        q = {"blades": "storm/blade~storm~35|blade3~all~25|junk~~", "traps": "storm/trap~storm~30|trap3~all~30",
             "trapmax": "2400", "aura": "storm~25~3", "boostrun": "2", "round": "6", "first": "0",
             "vals": "cardlogic:2,boostmax:3,useheal:0", "damage": "80", "crit": "500", "budget": "2000", "seed": "1"}
        battle = parts(("Imp", 3000, 3000, False), ("Bonestriker", 1500, 2400, True), ("Imp", 900, 3000, False))
        with mock.patch.object(S, "plan_round", spy):
            out = self.ask(q, battle=battle)
        self.assertTrue(out[0].startswith("plan|"), out)
        st, me, opts = got["state"], got["me"], got["opts"]
        # (the bot's storm/blade named as the hand's Stormblade - a copy of it in hand is then on already -; no card
        # boosts every school: blade3 kept)
        self.assertEqual(st.blades, [("Stormblade", {"storm": 35.0}), ("blade3", {"all": 25.0})])
        self.assertEqual(st.traps, [[], [{"storm": 30.0}, {"all": 30.0}], []])   # (on the one whose most is 2400)
        self.assertEqual(st.aura, ({"storm": 25.0}, 3))
        self.assertEqual((st.boosts_run, st.round, st.me_first), (2, 6, False))
        self.assertEqual((st.pips, st.power, st.hp, st.fhp), (5, 2, 2500, [3000, 1500, 900]))
        self.assertEqual((me.school, me.maxhp, me.damage, me.crit), ("storm", 3000, 80, 500))
        self.assertEqual((opts.cardlogic, opts.boostmax, opts.useheal, opts.boss), (2, 3, False, True))
        self.assertEqual([f.name for f in got["foes"]], ["Imp", "Bonestriker", "Imp"])
        # (the draw pile: the worn deck - its wand's item cards known from cards.jsonl's value_text facts - less the hand)
        names = sorted(c.name for c in st.pile)
        self.assertEqual(names.count("Lightning Strike"), 2)
        self.assertEqual(names.count("Storm Lord"), 3)
        self.assertEqual(names.count("Tempest"), 4)
        # (traps with no trapmax match: on the enemy with the most health now)
        with mock.patch.object(S, "plan_round", spy):
            self.ask(dict(q, trapmax="9999"), battle=battle)
        self.assertEqual([len(t) for t in got["state"].traps], [2, 0, 0])

    def test_a_blade_on_isnt_tried_again(self):
        """review fix: the bot's storm/blade on, another Stormblade in hand, Storm Lord not paid for yet - the
        Stormblade is on already: not tried, not the chain's ('your settings' way') pick, a pass the only play"""
        rd = reading([HAND[1], HAND[0]], pips={"power": 0})                 # (3 pips: Storm Lord can't go yet)
        boss = parts(("Bonestriker", 9000, 9000, True))
        lines = lambda out: [ln.split("|") for ln in out if ln.split("|")[0] in ("plan", "alt", "chain")]  # noqa: E731
        out = self.ask({"blades": "storm/blade~storm~35", "seed": "1", "budget": "2000", "n": "20"}, rd=rd,
                       battle=boss)
        self.assertIn("note|1 card in hand not tried (on already)", out)
        self.assertEqual([g[10] for g in lines(out)], ["pass"], out)
        # (a pet's copy on - storm/blade@item -: the deck's Stormblade still goes, as the bot casts it, and stacks)
        out = self.ask({"blades": "storm/blade@item~storm~40", "seed": "1", "budget": "2000", "n": "20"}, rd=rd,
                       battle=boss)
        self.assertNotIn("note|1 card in hand not tried (on already)", out)
        self.assertIn("Stormblade", [g[10] for g in lines(out)], out)

    def spy_ask(self, q, **kw):
        """ask, the State, Opts and plan plan_round got kept"""
        got = {}
        real = S.plan_round

        def spy(state, me, foes, opts=None, **k):
            got.update(state=state, opts=opts, plan=real(state, me, foes, opts, **k))
            return got["plan"]
        with mock.patch.object(S, "plan_round", spy):
            got["out"] = self.ask(dict({"seed": "1", "budget": "2000", "n": "20"}, **q), **kw)
        return got

    def test_used_flags_and_draws_reach_the_state(self):
        """v1.7.0: Planner.ahk's used= (PlannerUsed - the bot's used flags), draws= (DrawsBattle), drawoff=1,
        pshield=1"""
        got = self.spy_ask({"used": "storm/blade~storm~35", "draws": "2", "drawoff": "1", "pshield": "1"})
        self.assertTrue(got["out"][0].startswith("plan|"), got["out"])
        st = got["state"]
        self.assertEqual((st.boosts_used, st.draws, st.drawoff, st.pshield_used),
                         ([("blade", "", {"storm": 35.0})], 2, True, True))
        self.assertNotIn("Stormblade", [p["name"] for p in got["plan"]["plays"]])
        # (a treasure copy's flag holds back only a treasure Stormblade in hand - the deck's copy is still tried)
        tcb = hand_card("Card5", 210, "Stormblade", "blade", value=35, vtext="35%", tid=104, boosts="storm:35",
                        treasure=True)
        got = self.spy_ask({"used": "storm/blade@tc~storm~35"}, hand=HAND + [tcb])
        self.assertIn("note|1 card in hand not tried (used this battle)", got["out"])
        tried = [p["i"] for p in got["plan"]["plays"] if p["name"] == "Stormblade"]
        self.assertTrue(tried and all(not got["state"].hand[i].tc for i in tried), tried)
        # ("-": none used, unlike no used= at all - an older AutoFarmer: None, the blades on taken as cast)
        self.assertEqual(self.spy_ask({"used": "-"})["state"].boosts_used, [])
        st = self.spy_ask({})["state"]
        self.assertEqual((st.boosts_used, st.draws, st.drawoff, st.pshield_used), (None, 0, False, False))
        for q in ({"draws": "x", "used": "~~|junk|a~b~c|storm/blade~storm~nan"}, {"draws": "inf", "used": "|||"},
                  {"draws": "-5", "drawoff": "maybe", "pshield": "[1]", "used": "storm/blade+~storm~45"}):
            got = self.spy_ask(q)
            self.assertTrue(got["out"][0].startswith("plan|"), (q, got["out"]))
            self.assertEqual((got["state"].boosts_used, got["state"].draws, got["state"].drawoff), ([], 0, False), q)

    def test_settings_reach_the_opts(self):
        got = self.spy_ask({"vals": "reboost:1,drawenchant:1,drawneed:175,drawround:2,drawmax:4,enemyspells:0"})
        o = got["opts"]
        self.assertEqual((o.reboost, o.drawenchant, o.drawneed, o.drawround, o.drawmax, o.enemyspells),
                         (True, True, 175.0, 2, 4, False))
        o = self.spy_ask({})["opts"]
        self.assertEqual((o.reboost, o.drawenchant, o.drawneed, o.drawround, o.drawmax, o.enemyspells),
                         (False, False, 100.0, 3, 6, True))

    def test_place_in_hand_counts_every_card(self):
        """review fix: i (plan|'s field 1) is the card's place among every card read - one with no name read before it
        still counts"""
        hand = [hand_card("Card1", 5, "", "damage", pips=1, value=10, heads="storm:10"), dict(HAND[0], slot="Card2")]
        out = self.ask({"seed": "1", "budget": "2000", "acc": "30", "first": "1"}, hand=hand)
        f = out[0].split("|")
        self.assertEqual((f[0], f[1], f[2], f[10]), ("plan", "1", "Card2", "Storm Lord"), out)

    def test_no_deck_read_and_cards_with_no_kind(self):
        hand = HAND + [hand_card("Card5", 210, "Mystery", None, tid=999),
                       hand_card("PetCard", 300, "Pet Blade", None, tid=888)]
        out = self.ask({"seed": "1", "budget": "2000"}, hand=hand, ctx=self.ctx(decks=False))
        self.assertTrue(out[0].startswith("plan|"), out)
        self.assertTrue(any("1 card in hand with no kind known left out" in ln for ln in out), out)
        self.assertTrue(any("the deck isn't read" in ln for ln in out))
        # (the pet's blade - its kind from cards.jsonl - is the hand's 6th card: i 5 in the game's hand)
        alts = [ln.split("|") for ln in out if ln.split("|")[0] in ("plan", "alt", "chain")]
        self.assertFalse(any(a[1] == "4" for a in alts))

    def test_learned_prior_passed(self):
        got = {}
        real = S.plan_round

        def spy(state, me, foes, opts=None, **kw):
            got.update(kw)
            return real(state, me, foes, opts, **kw)

        class Plays:
            rounds = 10

            def prior_fn(self, school):
                got["school"] = school
                return lambda sit: ({"blade": 1.0}, "learned: blades")
        with mock.patch.object(S, "plan_round", spy):
            out = self.ask({"seed": "1", "budget": "2000"}, ctx=self.ctx(plays=Plays()))
        self.assertEqual(got["school"], "storm")
        self.assertIsNotNone(got["prior"])
        self.assertIn("learned|learned: blades", out)
        with mock.patch.object(S, "plan_round", spy):
            self.ask({"seed": "1"}, ctx=self.ctx(plays=None))
        self.assertIsNone(got["prior"])

    def test_within_budget_and_junk(self):
        t = time.perf_counter()
        out = self.ask({"budget": "120", "n": "5000"})
        ms = (time.perf_counter() - t) * 1000
        self.assertTrue(out[0].startswith("plan|"), out)
        self.assertLess(ms, 120 + 150)
        for q in ({"budget": "abc", "round": "x", "blades": "~~~|||", "traps": "junk", "aura": "a~b~c", "n": "-4",
                   "first": "maybe", "vals": ":,::,a:b", "hp": "nan", "damage": "inf", "deck": "zz", "seed": "q"},
                  {"budget": "0"}, {"foes": "~" * 50}):
            out = self.ask(q)
            self.assertTrue(out and (out[0].startswith("plan|") or out[0].startswith("none|")), (q, out))
        bad = self.V.plan_lines_for({}, lambda: 1 / 0, lambda: ([], ""), self.ctx())
        self.assertTrue(bad[0].startswith("none|the plan failed (ZeroDivisionError"))
        weird = reading([{"name": "x", "kind": "damage", "value": "?", "heads_text": "?", "pips": "seven"}, None, 5])
        out = self.ask({"budget": "300"}, rd=weird)
        self.assertTrue(out[0].startswith(("plan|", "none|")), out)


class Book(unittest.TestCase):
    """plan_book: the battles recorded read in a thread (pausing while a gated request is in flight) - /plan never waits"""

    def test_read_in_a_thread(self):
        try:
            import vision as V
        except ImportError as e:
            self.skipTest("vision.py can't be imported here (%s)" % e)
        import datetime
        import json
        import tempfile
        today = datetime.date.today()
        rec = {"rec": "battle", "v": 1, "id": today.strftime("%Y%m%d") + "-120000-1", "result": "won", "rounds_n": 1,
               "me": {"sc": 4, "school": "storm"}, "parts": [{"sc": 0, "side": "enemy", "name": "Foe1", "max": 900}],
               "rounds": [{"n": 1, "hand": [{"i": 0, "kind": "damage", "ok": True, "name": "Bolt", "tid": 1}],
                           "pips": {"generic": 3}, "hp": 3000, "max": 3000,
                           "played": {"spell": "Bolt", "tid": 1, "hand_i": 0}}]}
        keep_sim, keep_plan, keep_log = dict(V.SIM), dict(V.PLAN), V.log
        with tempfile.TemporaryDirectory() as root:
            folder = os.path.join(root, "learned", "battles", today.strftime("%Y-%m"))
            os.makedirs(folder)
            with open(os.path.join(folder, today.isoformat() + ".jsonl"), "w") as f:
                # (compact, as the recorder writes them - battlereport skips a line not starting {"rec":"battle")
                f.write('{"rec":"header","v":1}\n' + json.dumps(rec, separators=(",", ":")) + "\n{torn\n")
            try:
                V.log = lambda *a, **kw: None
                V.SIM.update(book=None, facts=None, at=0.0)
                V.PLAN.update(plays=None, at=0.0, thread=None)
                with mock.patch.object(V, "ROOT", root):
                    V.GATE.enter()                    # (a gated request in flight: the reading waits for it)
                    try:
                        first = V.plan_book()
                    finally:
                        V.GATE.leave()
                    self.assertIn("still being read", first["why"])
                    self.assertEqual(first["book"].by, {})
                    V.PLAN["thread"].join(15)
                    c = V.plan_book()
                self.assertEqual(c["why"], "")
                self.assertIn("Foe1", c["book"].by)
                self.assertEqual((c["plays"].battles, c["plays"].rounds), (1, 1))
                self.assertTrue(os.path.exists(os.path.join(root, "learned", "battles", "plays.json")))
            finally:
                V.log = keep_log
                V.SIM.clear()
                V.SIM.update(keep_sim)
                V.PLAN.clear()
                V.PLAN.update(keep_plan)

    def test_an_odd_record_skips_only_itself(self):
        """review fix: one pass feeds the FoeBook and the learned plays - a record the FoeBook can't take (an enemy's
        max '?') skipped there, every later battle still read by both"""
        try:
            import vision as V
        except ImportError as e:
            self.skipTest("vision.py can't be imported here (%s)" % e)
        import datetime
        import json
        import tempfile
        today = datetime.date.today()

        def rec(k, most):
            return {"rec": "battle", "v": 1, "id": today.strftime("%Y%m%d") + "-12000%d-1" % k, "result": "won",
                    "rounds_n": 1, "me": {"sc": 4, "school": "storm"},
                    "parts": [{"sc": 0, "side": "enemy", "name": "Foe%d" % k, "max": most}],
                    "rounds": [{"n": 1, "hand": [{"i": 0, "kind": "damage", "ok": True, "name": "Bolt", "tid": 1}],
                                "pips": {"generic": 3}, "hp": 3000, "max": 3000,
                                "played": {"spell": "Bolt", "tid": 1, "hand_i": 0}}]}
        keep_sim, keep_plan, keep_log = dict(V.SIM), dict(V.PLAN), V.log
        with tempfile.TemporaryDirectory() as root:
            folder = os.path.join(root, "learned", "battles", today.strftime("%Y-%m"))
            os.makedirs(folder)
            with open(os.path.join(folder, today.isoformat() + ".jsonl"), "w") as f:
                for k, most in ((1, 900), (2, "?"), (3, 900), (4, 900)):
                    f.write(json.dumps(rec(k, most), separators=(",", ":")) + "\n")
            try:
                V.log = lambda *a, **kw: None
                with mock.patch.object(V, "ROOT", root):
                    V._plan_load()
                book, plays = V.SIM["book"], V.PLAN["plays"]
                self.assertEqual((plays.battles, plays.rounds), (4, 4))
                self.assertTrue({"Foe1", "Foe3", "Foe4"} <= set(book.by), book.by)
                self.assertIn("1 battle couldn't be read (ValueError", book.why)
            finally:
                V.log = keep_log
                V.SIM.clear()
                V.SIM.update(keep_sim)
                V.PLAN.clear()
                V.PLAN.update(keep_plan)


class Route(unittest.TestCase):
    """/plan on a local server (127.0.0.1, any free port), its game reader a stand-in: 200 and lines, never a 500"""

    def test_plan_route(self):
        try:
            import vision as V
        except ImportError as e:
            self.skipTest("vision.py can't be imported here (%s)" % e)
        import tempfile
        import threading
        import urllib.error
        import urllib.request
        from http.server import ThreadingHTTPServer

        class FakeNav:
            broken = False

            def cards(self, want_effects=True, wait=0.5):
                if FakeNav.broken:
                    raise RuntimeError("the reader fell over")
                return reading(HAND), ""

            def battle(self, wait=0.5):
                return parts(("Bonestriker", 700, 2400, False)), ""
        ctx = {"book": S.FoeBook(battles=[]), "facts": FACTS, "plays": None, "why": ""}
        keep = (V.nav_reader, V.LOG)
        with tempfile.TemporaryDirectory() as d, \
                mock.patch.object(V, "plan_book", lambda: dict(ctx)), \
                mock.patch.object(V, "enemy_state", lambda: (None, None)), \
                mock.patch.object(V, "decks_reading", lambda fresh, out=False: ({"decks": [deckmem_deck(777)]}, "")):
            V.nav_reader, V.LOG = (lambda: FakeNav()), os.path.join(d, "vision.log")
            srv = ThreadingHTTPServer(("127.0.0.1", 0), V.Handler)
            th = threading.Thread(target=srv.serve_forever, daemon=True)
            th.start()
            try:
                def get(path):
                    try:
                        with urllib.request.urlopen("http://127.0.0.1:%d%s" % (srv.server_address[1], path),
                                                    timeout=10) as r:
                            return r.status, r.read().decode().split("\n")
                    except urllib.error.HTTPError as e:
                        return e.code, e.read().decode().split("\n")
                code, ln = get("/plan?school=storm&round=3&budget=300&seed=1&acc=30&blades=storm%2Fblade~storm~35")
                self.assertEqual(code, 200)
                self.assertTrue(ln[0].startswith("plan|0|Card1|101|damage|0|"), ln)
                self.assertTrue(any(x.startswith("planned|") for x in ln))
                FakeNav.broken = True
                code, ln = get("/plan")
                self.assertEqual(code, 200)
                self.assertTrue(ln[0].startswith("none|the plan failed (RuntimeError"), ln)
            finally:
                srv.shutdown()
                srv.server_close()
                V.nav_reader, V.LOG = keep
        self.assertIn("/plan", V.GATED)
        self.assertEqual(V.GATE.n, 0)


# ============================================================================ the recorder's 'planner' rule
class PlannerRule(unittest.TestCase):
    def test_rule_and_settings_key(self):
        import battlerec
        self.assertIn("planner", battlerec.SETTINGS_KEYS)
        for k in ("memclicks", "deckzone", "partyhitround"):       # (the battle settings v1.0.0 added)
            self.assertIn(k, battlerec.SETTINGS_KEYS)
        self.assertGreaterEqual(battlerec.RULE_V, 2)
        # (advice only - planner:1 - never decides a round: the round is the bot's own rule's)
        advice = [[0, "  Plan: would play Storm Lord at Bonestriker (won 92% in 3 rounds, 100 tries) - advice only"],
                  [5, "  UseBlade storm/blade: found=1"]]
        self.assertEqual(battlerec.classify(advice)[0], "blade")
        # (a card the planner itself cast - planner:2, not built yet - is its rule, before the boosts and hits)
        played = [[0, "  planner: Storm Lord cast at Bonestriker (won 92%)"], [5, "  UseHit hit3: found=1"]]
        self.assertEqual(battlerec.classify(played)[0], "planner")
        kill = [[0, "  kill check: 700/2400 -> hit3"], [3, "  UseHit hit3: found=1"],
                [4, "  planner: Storm Lord cast at Bonestriker"]]
        self.assertEqual(battlerec.classify(kill)[0], "kill")

    def test_discardspent_key_and_lines(self):
        # (v1.8.0: discardspent kept in the record's settings - BattleRec.ahk BrecSetKeys sends every DeckKey -, and
        # Autofarmer.ahk DiscardSpent's lines are no rule's: a round is still its own rule's)
        import battlerec
        self.assertIn("discardspent", battlerec.SETTINGS_KEYS)
        blade = [5, "  UseBlade storm/blade: found=1"]
        for line in ("  spent copies: the worn deck holds 2 Sharpen and 0 Potent card(s) (the helper's reading, 812.4 s "
                     "old) - a blade's or trap's copy kept back while one may still come",
                     "  spent copies: the worn deck holds 1 Sharpen and 1 Potent card(s) (the helper's reading, 3.0 s "
                     "old, its signature not checked) - a blade's or trap's copy kept back while one may still come",
                     "  spent copies: the worn deck's Sharpen and Potent cards not known (another deck worn since the "
                     "helper's reading) - only one in hand keeps a copy back",
                     "  Discarded Stormblade - storm/blade: 3 of the deck's copies in hand, 1 cast left this battle "
                     "(card 2 of 7, right-click at 512,640)",
                     "  spent copies of storm/blade: 3 in hand, 1 cast left this battle - not discarded: the hand's card "
                     "boxes and the game's cards don't line up (not as many, or the hand not read)",
                     "  spent copies of storm/trap: 2 in hand, 0 casts left this battle - not discarded: card 2 of 7 "
                     "looks like a treasure card",
                     "  spent copies of blade3: the game's hand doesn't say for sure which cards are its copies - the "
                     "both-casts rule's (said once a battle)",
                     "  spent copies of storm/blade: 3 in hand after a right-click on one - it didn't go; not tried "
                     "again this battle"):
            with self.subTest(line=line):
                self.assertEqual(battlerec.classify([[0, line]])[0], "other")
                self.assertEqual(battlerec.classify([[0, line], blade])[0], "blade")

    def test_plan_lines_never_a_rule(self):
        # (partyorders - RULE_V 3: no "Plan:" line decides a round - advice and the leader's orders are never casts, and
        # nothing in one can spell a rule's phrase into it)
        import battlerec
        self.assertIn("partyorders", battlerec.SETTINGS_KEYS)
        self.assertGreaterEqual(battlerec.RULE_V, 3)
        order = ("  Plan: the leader would have you play Stormblade (won 80%, 12 tries) [tid 104] - the leader's plan, "
                 "advice only (partyorders, 1830 ms after it planned, waited 1200 ms)")
        blade = [5, "  UseBlade storm/blade: found=1"]
        self.assertEqual(battlerec.classify([[0, order]])[0], "other")
        self.assertIsNone(battlerec.classify([[0, order]])[1])
        self.assertEqual(battlerec.classify([[0, order], blade])[0], "blade")
        for line in ("  Plan: no order from the leader in 3010 ms (the leader has its hand - no order yet) - your own "
                     "way (partyorders)",
                     "  Plan: not waiting for the leader's orders again this battle (two rounds in a row with none) - "
                     "still asked once a round",
                     "  Plan: not waiting for the leader's orders till one comes (six rounds in a row with none) - still "
                     "asked once a round",
                     "  Plan: no order from the leader - the leader's round went another way - no team plan this round "
                     "(partyorders)",
                     "  Plan: the team's round - Bob Fireheart Stormblade (won 80%) / Ann Stormy Lightning Strike at "
                     "Bonestriker (won 75%) - each follower told its card, advice only (partyorders)",
                     "  Plan: the team isn't planned - partyorders needs planner on on the leader's PC (Settings: "
                     "planner) (partyorders)"):
            with self.subTest(line=line):
                self.assertEqual(battlerec.classify([[0, line]])[0], "other")
        # (HOSTILE: a card's or an enemy's name in an order spelling another rule's phrase - still the bot's own rule)
        hostile = ("  Plan: the leader would have you play learned hit X cast at at  - the kill check counts it there "
                   "(won 80%, 12 tries) - the leader's plan, advice only (partyorders, 1 ms after it planned, waited 0 ms)")
        self.assertEqual(battlerec.classify([[0, hostile], blade])[0], "blade")
        self.assertEqual(battlerec.classify([[0, "  Plan: the leader would have you play you're playing - leaving "
                                                  "this round to you (won 1%, 1 tries)"]])[0], "other")
        self.assertNotEqual(battlerec.classify([[0, "  kill check: 700/2400 -> hit3"],
                                                [3, "  Plan: the leader would have you play UseHit hit3: found=1 (won 1%, "
                                                    "1 tries)"]])[0], "kill")


# ============================================================================ /sim and /decks on deckmem-shaped decks
class SimOnGameDecks(unittest.TestCase):
    """the critic's note (v1.0.0): DeckBeat's /sim and DeckLearnGame's /decks on decks as deckmem reads them, whose item
    cards (a wand's, a pet's) have no kind of their own - only cards.jsonl's facts, where value is a value_text string"""

    @classmethod
    def setUpClass(cls):
        try:
            import vision
        except ImportError as e:
            raise unittest.SkipTest("vision.py can't be imported here (%s)" % e)
        cls.V = vision

    def reading(self):
        d = deckmem_deck(777)
        d["item_cards"].append({"name": "Pet Blade", "template_id": 888, "count": 1, "display": "Pet Blade",
                                "from": "Pet"})
        spare = dict(deckmem_deck(), gid=0xDEF, equipped=False, where="backpack", sets=[2], display="Spare")
        return {"decks": [d, spare], "equipped": 0xABC, "why": "", "read_at": time.monotonic()}

    def test_sim_lines_for_with_item_card_facts(self):
        class Wiki:
            def creature(self, name):
                return {"missing": True}
        with mock.patch.object(self.V, "decks_reading", lambda fresh, out=False: (self.reading(), "")), \
                mock.patch.object(self.V, "sim_book", lambda: (S.FoeBook(battles=[]), FACTS)), \
                mock.patch.object(self.V, "enemy_state", lambda: (Wiki(), None)):
            out = self.V.sim_lines_for({"foes": "Governor Nereus~9000~ice~1", "n": "60", "hp": "4000", "damage": "90",
                                        "vals": "cardlogic:1,boostmax:0"})
            spare = self.V.sim_lines_for({"foes": "Rat~500", "deck": "def", "n": "20"})
        self.assertTrue(out[0].startswith("sim|"), out)
        self.assertTrue(any(ln.startswith("verdict|") for ln in out))
        self.assertIn("deck|abc|Storm Deck", out)
        self.assertFalse(any("simulation failed" in ln for ln in out), out)
        self.assertFalse(any("no kind known" in ln for ln in out), out)      # (both item cards known from the facts)
        self.assertTrue(spare[0].startswith("sim|"), spare)
        self.assertIn("deck|def|Spare", spare)

    def test_sim_settings_reach_the_opts(self):
        """v1.7.0: /sim's vals (Decks.ahk DeckSimVals) - reboost and the rest reach the simulator; a key not sent: an
        older AutoFarmer's (discardspent off, though this one's Settings default is on)"""
        class Wiki:
            def creature(self, name):
                return {"missing": True}
        seen = []
        real = S.simulate

        def spy(cards, me, foes, opts=None, **kw):
            seen.append(opts)
            return real(cards, me, foes, opts, **kw)
        with mock.patch.object(self.V, "decks_reading", lambda fresh, out=False: (self.reading(), "")), \
                mock.patch.object(self.V, "sim_book", lambda: (S.FoeBook(battles=[]), FACTS)), \
                mock.patch.object(self.V, "enemy_state", lambda: (Wiki(), None)), mock.patch.object(S, "simulate", spy):
            for vals in ("reboost:1,drawenchant:1,drawneed:175,enemyspells:0", "reboost:0", ""):
                out = self.V.sim_lines_for({"foes": "Rat~500", "n": "10", "vals": vals})
                self.assertTrue(out[0].startswith("sim|"), out)
            # (v1.8.0: discardspent - this AutoFarmer always sends it, 0 where the bot never runs it this session)
            for vals in ("reboost:0,discardspent:1", "discardspent:0", ""):
                out = self.V.sim_lines_for({"foes": "Rat~500", "n": "10", "vals": vals})
                self.assertTrue(out[0].startswith("sim|"), out)
        self.assertEqual([(o.reboost, o.drawenchant, o.drawneed, o.enemyspells) for o in seen[:3]],
                         [(True, True, 175.0, False), (False, False, 100.0, True), (False, False, 100.0, True)])
        self.assertEqual([o.discardspent for o in seen[3:]], [True, False, False])

    def test_decks_lines_learns_decks_with_item_cards(self):
        fake = types.ModuleType("deckmem")
        fake.deck_lines = lambda r: ["decks|%d" % len(r.get("decks") or [])]
        saved = sys.modules.get("deckmem")
        sys.modules["deckmem"] = fake
        try:
            with mock.patch.object(self.V, "decks_reading", lambda fresh, out=False: (self.reading(), "")), \
                    mock.patch.object(self.V, "sim_book", lambda: (S.FoeBook(battles=[]), FACTS)):
                out = self.V.decks_lines(False)
        finally:
            if saved is None:
                sys.modules.pop("deckmem", None)
            else:
                sys.modules["deckmem"] = saved
        self.assertEqual(out[0], "decks|2")
        learn = [ln for ln in out if ln.startswith("learn|")]
        self.assertEqual(len(learn), 2, out)
        self.assertTrue(learn[0].startswith("learn|abc|Storm Deck|storm|1|"))
        self.assertFalse(any(ln.startswith("nolearn|") for ln in out), out)
        self.assertTrue(out[-1].startswith("deckage|"))
        # (the item cards counted by their facts' kinds: 4 + 6 + 4 main hits + 2 wand hits; 4 + 1 blades)
        import battlesim
        kinds, _sp = battlesim.deck_kinds(self.reading()["decks"][0], FACTS)
        self.assertEqual((kinds["damage"], kinds["blade"], kinds.get("?", 0)), (12, 5, 0))


# ============================================================================ v1.0.0 batch 3: /plan's team, the log's charms
class PlanTeam(unittest.TestCase):
    """/plan's mates=, role=, seat=, teamplan=1 and charms=log (plan_lines_for with stand-in readers)"""

    @classmethod
    def setUpClass(cls):
        try:
            import vision
        except ImportError as e:
            raise unittest.SkipTest("vision.py can't be imported here (%s)" % e)
        cls.V = vision
        cls.log = vision.log
        vision.log = lambda *a, **kw: None

    @classmethod
    def tearDownClass(cls):
        cls.V.log = cls.log

    def ask(self, q, battle=None, ctx=None, hand=None, spy=None):
        c = {"book": S.FoeBook(battles=[]), "facts": FACTS, "plays": None, "wiki": None, "casts": None,
             "decks": {"decks": [deckmem_deck(777)]}}
        c.update(ctx or {})
        cr = lambda: (reading(HAND if hand is None else hand), "")                          # noqa: E731
        br = lambda: (parts(("Bonestriker", 700, 2400, False)) if battle is None else battle, "")  # noqa: E731
        if spy is None:
            return self.V.plan_lines_for(q, cr, br, c)
        real = S.plan_round

        def grab(state, me, foes, opts=None, **kw):
            spy.update(state=state, me=me, foes=foes, opts=opts)
            return real(state, me, foes, opts, **kw)
        with mock.patch.object(S, "plan_round", grab):
            return self.V.plan_lines_for(q, cr, br, c)

    def test_mates_parsed(self):
        got = {}
        q = {"seed": "1", "budget": "2000", "seat": "5", "role": "hitter",
             "mates": "Ann~4~storm~1500~3000~blader~3~1~104:blade:0:storm:35%;105::0::|"
                      "Bob~6~fire~~2800~hitter~~~|~~~~~~~~|Junk|x~y~z"}
        out = self.ask(q, spy=got)
        self.assertTrue(out[0].startswith("plan|"), out)
        st = got["state"]
        self.assertEqual(st.seat, 5)
        self.assertEqual([m.name for m in st.mates], ["Ann", "Bob", "Junk"])   # (3 at most; the empty one skipped)
        ann, bob = st.mates[0], st.mates[1]
        self.assertEqual((ann.seat, ann.role, ann.me.school, ann.hp, ann.me.maxhp, ann.pips, ann.power),
                         (4, "blader", "storm", 1500, 3000, 3, 1))
        # (Ann's hand: a blade as sent; tid 105 with no kind - cards.jsonl's facts don't know it: left out)
        self.assertEqual([(c.name, c.kind, c.boosts) for c in ann.hand], [("?", "blade", {"storm": 35.0})])
        self.assertIsNone(bob.hand)                   # (not known: its role's way)
        self.assertEqual((bob.seat, bob.me.maxhp, bob.hp), (6, 2800, None))
        self.assertTrue(any("the team model: 3 mates" in ln and "Bob hitter - its hand not known" in ln for ln in out),
                        out)
        # (a mate down - the party's 0 %, PlannerMates' "~0~": 0, not full health; blank: not known)
        down = self.V.plan_mates("Ann~5~storm~0~3000~hitter~~~|Bob~6~fire~~2800~hitter~~~", {})
        self.assertEqual([m.hp for m in down], [0, None])

    def test_teamplan_orders(self):
        q = {"seed": "1", "budget": "3000", "n": "20", "teamplan": "1", "acc": "30",
             "mates": "Ann~5~storm~3000~3000~hitter~7~0~777:damage:0:storm:95"}
        out = self.ask(q)
        orders = [ln.split("|") for ln in out if ln.startswith("order|")]
        self.assertEqual([o[1] for o in orders], ["0", "1"], out)
        self.assertEqual((orders[1][2], orders[1][3], orders[1][5]), ("5", "Ann", "777"))
        self.assertTrue(out[0].startswith("plan|"))
        self.assertTrue(out[-1].startswith("planned|"))
        # (no teamplan: no order lines - the mates still in the rollouts)
        out = self.ask(dict(q, teamplan="0"))
        self.assertFalse(any(ln.startswith("order|") for ln in out))

    def test_charms_from_the_log(self):
        # (the recorder's duel stand-in: the party's Stormblade on me, my side's trap and the enemy's own shield on it -
        # the enemy matched to the memory's plate by its gid, 100)
        duel = {"me_sc": 4, "parts": {0: {"gid": "100"}, 4: {"gid": "7"}},
                "rounds": [{"n": 1, "casts": [
                    {"sc": 5, "spell": "Stormblade", "hang": [[4, "kModifyOutgoingDamage", 1, 35]]},
                    {"sc": 5, "spell": "Storm Trap", "hang": [[0, "kModifyIncomingDamage", 0, 30]]},
                    {"sc": 0, "spell": "Dark Shield", "hang": [[0, "kModifyIncomingDamage", 0, -40]]}]}]}
        facts = dict(FACTS)
        facts[104] = {"tid": 104, "name": "Stormblade", "boosts": "storm:35"}
        facts[105] = {"tid": 105, "name": "Storm Trap", "boosts": "storm:30"}
        got = {}
        out = self.ask({"seed": "1", "budget": "2000", "charms": "log"}, ctx={"duel": duel, "facts": facts}, spy=got)
        st = got["state"]
        self.assertEqual(st.blades, [("Stormblade", {"storm": 35.0})])
        self.assertEqual(st.traps, [[{"storm": 30.0}]])
        self.assertEqual(st.fshields, [[(40, None)]])
        self.assertTrue(any("3 charms on from the game's log (1 of 1 enemies matched by gid)" in ln for ln in out), out)
        # (the copy of Stormblade in hand is on already: not tried)
        self.assertFalse(any(ln.split("|")[0] in ("plan", "alt") and ln.split("|")[10] == "Stormblade" for ln in out))
        # (no duel followed: the bot's own count, said)
        out = self.ask({"seed": "1", "budget": "2000", "charms": "log"}, ctx={"duel": None})
        self.assertTrue(any("the log's charms not read" in ln for ln in out), out)
        # (not asked: nothing of it)
        out = self.ask({"seed": "1", "budget": "2000"}, ctx={"duel": duel})
        self.assertFalse(any("charm" in ln for ln in out))

    def party(self, hand="d12r5~5~0~3000~3000~7~0~777:damage:0:storm:95-115"):
        """a leader's party.Party (its thread doing nothing) with Ann's hand in - partyorders on, planning"""
        import party

        class Quiet(party.Party):
            def _loop(self):
                return
        L = Quiet(lambda: None, log=lambda *a: None)
        L.cfg.update(role="leader", orders="1", plans="1")
        L.members["a1"] = dict(party.clean_state({"wiz": "Ann Stormy", "seat": "5", "battle": "1"}), at=time.time(),
                               ip="x")
        L.hands["a1"] = dict(party.clean_hand(hand), at=time.time())
        return L

    def test_hands_from_the_party(self):
        L = self.party()
        q = {"seed": "1", "budget": "3000", "n": "20", "acc": "30", "round": "5", "hands": "party",
             "mates": "Ann Stormy~5~storm~2400~3000~hitter~~~"}
        out = self.ask(q, ctx={"party": L})
        orders = [ln.split("|") for ln in out if ln.startswith("order|")]
        self.assertEqual([o[1] for o in orders], ["0", "1"], out)              # (teamplan implied: a hand filled in)
        self.assertEqual((orders[1][3], orders[1][5]), ("Ann Stormy", "777"))
        model = [ln for ln in out if "the team model: 1 mate" in ln]
        self.assertTrue(model, out)
        self.assertNotIn("hand not known", model[0])
        o = L.orders["a1"]
        self.assertEqual((o["tag"], o["round"], o["tid"], o["i"]), ("d12r5", 5, 777, 0))
        # (its hand is round 5's, this is round 6: no team plan, plan_round at today's 300 ms, a 'late' marker)
        out = self.ask(dict(q, round="6", n="2000"), ctx={"party": L})
        self.assertTrue(out[0].startswith("plan|"), out)
        self.assertFalse(any(ln.startswith("order|") for ln in out), out)
        self.assertTrue(any(ln.startswith("teamnote|") and "its hand is round 5's" in ln for ln in out), out)
        self.assertEqual((L.orders["a1"]["tag"], L.orders["a1"]["why"], L.orders["a1"]["round"]), ("", "late", 6))
        planned = next(ln for ln in out if ln.startswith("planned|")).split("|")
        self.assertLessEqual(int(planned[2]), 300, planned)
        # (the battle recorder's round wins over AutoFarmer's; not in Planning - lagging -: AutoFarmer's)
        duel = {"num": 12, "phase": "Planning", "rounds": [{"n": 5}]}
        out = self.ask(dict(q, round="6"), ctx={"party": L, "duel": duel})
        self.assertEqual([ln.split("|")[5] for ln in out if ln.startswith("order|1|")], ["777"], out)
        # (the order kept for the recorder's round too - the follower's stash has its own recorder's round, 5)
        self.assertEqual((L.orders["a1"]["tag"], L.orders["a1"]["round"]), ("d12r5", 5))
        out = self.ask(dict(q, round="6"), ctx={"party": L, "duel": dict(duel, phase="Execution")})
        self.assertFalse(any(ln.startswith("order|") for ln in out), out)
        self.assertEqual((L.orders["a1"]["why"], L.orders["a1"]["round"]), ("late", 6))
        # (no party in this helper: said, the round planned as ever - with mates= or without)
        for qq in (q, {k: v for k, v in q.items() if k != "mates"}):
            out = self.ask(qq, ctx={"party": None})
            self.assertTrue(out[0].startswith("plan|"), out)
            self.assertTrue(any(ln.startswith("teamnote|") and "the party isn't running in this helper" in ln
                                for ln in out), out)
        # (no hands=party: the party isn't asked, nothing new said)
        keep = dict(L.orders)
        out = self.ask({k: v for k, v in q.items() if k != "hands"}, ctx={"party": L})
        self.assertEqual(L.orders, keep)
        self.assertFalse(any(ln.startswith("teamnote|") for ln in out), out)
        self.assertFalse(any(ln.startswith("order|") for ln in out), out)
        # (what the simulator reads off a card's name travels as its mark; a hit's damage enchant as its ench)
        L = self.party("d12r5~5~0~3000~3000~7~0~300:ward:0:storm:50%::tower;301:manipulation:0:storm:::resh;"
                       "102:damage:2:storm:150-170:175")
        got = {}
        self.ask(q, ctx={"party": L}, spy=got)
        hand = got["state"].mates[0].hand
        self.assertEqual([(c.kind, c.tower, c.resh, c.ench) for c in hand],
                         [("ward", True, False, 0.0), ("manipulation", False, True, 0.0), ("damage", False, False, 175.0)])
        self.assertEqual((got["state"].mates[0].pips, got["state"].mates[0].hp), (7, 3000))

    def test_partyorder_route(self):
        """/partyorder (partyorder_answer) - what Party.ahk asks: lead=1, noplan=<round> (the recorder's round when it's
        in Planning), tag= (the follower's order_line)"""
        import party
        V = self.V
        keep = (V.PARTY, V.REC)

        def rec(phase, n):
            return types.SimpleNamespace(on=True, broken=False, parser=types.SimpleNamespace(
                duel={"num": 12, "phase": phase, "rounds": [{"n": n}]}))
        try:
            # (no party in this helper)
            V.PARTY, V.REC = None, rec("Planning", 5)
            self.assertEqual(V.partyorder_answer({"lead": "1"}), "lead|0")
            self.assertEqual(V.partyorder_answer({"noplan": "5"}), "noplan|0")
            f = V.partyorder_answer({"tag": "d12r5"}).split("|")
            self.assertEqual((f[:2], len(f), f[-1]), (["order", "none"], 11, "the party isn't on in this helper"))
            # (the leader's: Ann's round-5 hand held; the recorder's round 5 wins over AutoFarmer's 6)
            V.PARTY = self.party()
            self.assertEqual(V.partyorder_answer({"lead": "1"}), "lead|1")
            self.assertEqual(V.partyorder_answer({"noplan": "6"}), "noplan|1")
            self.assertEqual((V.PARTY.orders["a1"]["why"], V.PARTY.orders["a1"]["round"]), ("noplan", 5))
            # (not in Planning - lagging -: AutoFarmer's round)
            V.PARTY, V.REC = self.party(), rec("Execution", 5)
            self.assertEqual(V.partyorder_answer({"noplan": "6"}), "noplan|0")
            self.assertEqual(V.partyorder_answer({"noplan": "x"}), "noplan|0")
            self.assertEqual(V.partyorder_answer({"noplan": "5"}), "noplan|1")
            V.REC = None
            V.PARTY = self.party()
            self.assertEqual(V.partyorder_answer({"noplan": "5"}), "noplan|1")
            # (the follower's: order_line's own line, for the tag asked)
            F = self.party()
            F.cfg.update(role="follower", orders="1", plans="")
            F.ahk = party.clean_state({"battle": "1"})
            F.saw_hand(reading(HAND), "d12r5")
            self.assertIsNotNone(F.stash)
            F._took({"v": 1, "leader": {"name": "Ned"}, "others": [], "hands": {"max": 2048, "got": "d12r5"},
                     "order": {"tag": "d12r5", "round": 5, "i": 1, "tid": 104, "kind": "blade", "won": 80, "n": 12,
                               "age": 0}})
            V.PARTY = F
            ln = V.partyorder_answer({"tag": "d12r5"})
            self.assertTrue(ln.startswith("order|ok|5|Stormblade|104|blade|"), ln)
            self.assertEqual(ln, F.order_line("d12r5"))
            self.assertTrue(V.partyorder_answer({"tag": "d12r4"}).startswith("order|none|4|"))
            self.assertTrue(V.partyorder_answer({}).startswith("order|none||"))
        finally:
            V.PARTY, V.REC = keep

    def test_plan_mates_fixes(self):
        self.assertIsNone(self.V.plan_mates("Ann~5~storm~~3000~hitter~~~999::0::", {})[0].hand)
        m = self.V.plan_mates("Ann~5~storm~~3000~hitter~7~0~1234567:damage:0:storm:95", {})[0]
        self.assertEqual(m.hand[0].tid, 1234567)
        self.assertEqual(self.V.plan_mates("Ann~5~storm~~3000~hitter~1234567~0~1:damage:0:storm:95", {})[0].pips, 0)
        # (a 5-cell card as before - no enchant, no mark: its fact's name)
        c = self.V.plan_mates("Ann~5~storm~~3000~hitter~7~0~777:damage:0:storm:95", FACTS)[0].hand[0]
        self.assertEqual((c.name, c.ench, c.tower, c.resh, c.bot_ench), ("Lightning Strike", 0.0, False, False, ""))
        c = self.V.plan_mates("Ann~5~storm~~3000~hitter~7~0~302:enchant:0:storm:+275::gargantuan", {})[0].hand[0]
        self.assertEqual((c.name, c.bot_ench), ("Gargantuan", "gargantuan"))
        c = self.V.plan_mates("Ann~5~storm~~3000~hitter~7~0~102:damage:2:storm:150-170:12345:bogus", {})[0].hand[0]
        self.assertEqual((c.ench, c.name), (0.0, "?"))

    def test_junk_team_params(self):
        for q in ({"mates": "~" * 40, "teamplan": "1", "budget": "200"}, {"mates": "|" * 10, "seat": "99", "role": "x"},
                  {"mates": "a~5~storm~-1~nan~healer~99~99~1:2:3:4:5:6;;;:::", "teamplan": "1", "budget": "150"},
                  {"charms": "log", "budget": "200"}):
            out = self.ask(q, ctx={"duel": {"rounds": "junk", "parts": "junk"}})
            self.assertTrue(out and out[0].startswith(("plan|", "none|")), (q, out))
        self.assertEqual(self.V.plan_mates(None, {}), [])
        self.assertEqual(self.V.plan_mates(12, {}), [])


class DeckFor(unittest.TestCase):
    """/deckfor (deckfor_lines_for): each deck in an Equipment Set against the zone's enemy groups recorded"""

    @classmethod
    def setUpClass(cls):
        try:
            import vision
        except ImportError as e:
            raise unittest.SkipTest("vision.py can't be imported here (%s)" % e)
        cls.V = vision

    def ctx(self):
        rec = {"zone": "Z/Graveyard", "me": {"sc": 4, "school": "storm"}, "rounds": [],
               "parts": [{"sc": 0, "side": "enemy", "name": "Rat", "max": 600},
                         {"sc": 1, "side": "enemy", "name": "Rat", "max": 600}, {"sc": 4, "side": "me"}]}
        strong = deckmem_deck()
        weak = dict(deckmem_deck(), gid=0xDEF, equipped=False, sets=[2], display="Weak",
                    cards=[dict(c, value=10, heads_text="storm:10", value_text="10-12") for c in deckmem_deck()["cards"]])
        loose = dict(deckmem_deck(), gid=0x123, equipped=False, sets=[], display="Loose")
        return {"book": S.FoeBook(battles=[rec, rec]), "facts": FACTS, "wiki": None, "casts": None,
                "decks": {"decks": [weak, strong, loose]}}

    def test_ranked_and_kept(self):
        keep = dict(self.V.DECKFOR["cache"])
        try:
            self.V.DECKFOR["cache"].clear()
            q = {"zone": "Z/Graveyard", "school": "storm", "hp": "3000", "n": "20", "acc": "30"}
            out = self.V.deckfor_lines_for(q, self.ctx(), wait=True)
            rows = [ln.split("|") for ln in out if ln.startswith("deckfor|")]
            self.assertEqual([r[1] for r in rows], ["abc", "def"], out)      # (the loose deck: in no set)
            self.assertIn("group|2|Rat,Rat", out)
            self.assertIn("zone|Z/Graveyard", out)
            # (asked again: kept - the same lines, nothing worked out)
            with mock.patch.object(S, "best_decks", lambda *a, **kw: 1 / 0):
                self.assertEqual(self.V.deckfor_lines_for(q, self.ctx()), out)
            # (another zone with no battles recorded there)
            out = self.V.deckfor_lines_for(dict(q, zone="Z/Nowhere"), self.ctx(), wait=True)
            self.assertTrue(out[0].startswith("none|no enemy group known"), out)
            # (foes= instead of the book's groups)
            out = self.V.deckfor_lines_for(dict(q, zone="Z/Nowhere", foes="Rat~Rat|Rat"), self.ctx(), wait=True)
            self.assertTrue(out[0].startswith("deckfor|abc|"), out)
        finally:
            self.V.DECKFOR["cache"].clear()
            self.V.DECKFOR["cache"].update(keep)

    def test_profiles_settings_per_deck(self):
        """v1.7.0: vals= your settings, dvals= each in-game deck's bot deck profile's own (Decks.ahk DeckForZone) - a
        deck with a profile plays its values over yours and no learn_deck guess; one with none: learn_deck's on top"""
        c = self.ctx()
        plain = dict(deckmem_deck(), gid=0xA1, display="Plain", sets=[3],
                     cards=[x for x in deckmem_deck()["cards"] if x["kind"] != "blade"])
        decks = [plain] + [d for d in c["decks"]["decks"] if d["gid"] == 0xDEF]
        c["decks"] = {"decks": decks}
        specs = {}
        real = S.best_decks

        def spy(ds, *a, **kw):
            specs.clear()
            specs.update({key: o for key, _n, _c, o in ds})
            return real(ds, *a, **kw)
        keep = dict(self.V.DECKFOR["cache"])
        try:
            self.V.DECKFOR["cache"].clear()
            q = {"zone": "Z/Graveyard", "school": "storm", "n": "10", "vals": "reboost:0,cardlogic:2",
                 "dvals": "A1~reboost:1,cardlogic:1"}
            with mock.patch.object(S, "best_decks", spy):
                out = self.V.deckfor_lines_for(q, c, wait=True)
                self.assertTrue(out[0].startswith("deckfor|"), out)
                a, b = specs["a1"], specs["def"]
                # (the profile's own beat yours; no learn_deck guess - its useblades 0 for a deck with no blade)
                self.assertEqual((a.reboost, a.cardlogic, a.useblades), (True, 1, True))
                want = S.learn_deck(decks[1], FACTS, 2)["vals"].get("cardlogic", 2)
                self.assertEqual((b.reboost, b.cardlogic), (False, want))                  # (learn_deck's on top)
                self.V.deckfor_lines_for(dict(q, dvals="a1~"), c, wait=True)
                a = specs["a1"]
                self.assertEqual((a.reboost, a.cardlogic, a.useblades), (False, 2, True))  # (yours alone)
                self.assertEqual(len(self.V.DECKFOR["cache"]), 2)                         # (another dvals: its own)
                self.V.deckfor_lines_for(dict(q, vals="reboost:1"), c, wait=True)
                self.assertEqual(len(self.V.DECKFOR["cache"]), 3)
                for junk in ("~", "x", "|||", "a~b:c", "~~~|a1~~:", "a1~reboost:nan,:5,cardlogic"):
                    out = self.V.deckfor_lines_for(dict(q, dvals=junk), c, wait=True)
                    self.assertTrue(out[0].startswith("deckfor|"), (junk, out))
        finally:
            self.V.DECKFOR["cache"].clear()
            self.V.DECKFOR["cache"].update(keep)

    def test_profile_with_every_hit_off(self):
        """a deck profile with usehit1-4 all 0 (a support's - Decks.ahk DeckFilterHand then plays no hit): its deck
        played with none, the rule /sim and /plan use - not scored a hitter that wins with the hits it never casts"""
        c = {"book": S.FoeBook(battles=[]), "facts": FACTS, "wiki": None, "casts": None,
             "decks": {"decks": [deckmem_deck()]}}
        off = "usehit1:0,usehit2:0,usehit3:0,usehit4:0"
        specs = {}
        real = S.best_decks

        def spy(ds, *a, **kw):
            specs.clear()
            specs.update({key: o for key, _n, _c, o in ds})
            return real(ds, *a, **kw)
        keep = dict(self.V.DECKFOR["cache"])
        try:
            self.V.DECKFOR["cache"].clear()
            q = {"zone": "Z", "foes": "Rat", "school": "storm", "n": "30"}
            with mock.patch.object(S, "best_decks", spy):
                won = {}
                for name, extra in (("none", {}), ("off", {"dvals": "abc~" + off}),
                                    ("one on", {"dvals": "abc~usehit1:0,usehit2:0,usehit3:1,usehit4:0"}),
                                    ("yours off, profile on", {"vals": off, "dvals": "abc~usehit1:1"}),
                                    ("yours off, no profile", {"vals": off})):
                    out = self.V.deckfor_lines_for(dict(q, **extra), c, wait=True)
                    row = out[0].split("|")
                    self.assertEqual(row[:3], ["deckfor", "abc", "Storm Deck"], (name, out))
                    won[name] = (int(row[3]), specs["abc"].usehit)
            self.assertEqual(won["off"], (0, False), won)                    # (the support's: no hit, no win)
            self.assertEqual(won["yours off, no profile"], (0, False), won)  # (yours with all off: as /sim)
            for name in ("none", "one on", "yours off, profile on"):
                self.assertEqual(won[name][1], True, (name, won))
                self.assertGreater(won[name][0], 50, (name, won))
        finally:
            self.V.DECKFOR["cache"].clear()
            self.V.DECKFOR["cache"].update(keep)

    def test_in_a_thread_and_junk(self):
        keep = dict(self.V.DECKFOR["cache"])
        try:
            self.V.DECKFOR["cache"].clear()
            q = {"zone": "Z/Graveyard", "n": "10"}
            first = self.V.deckfor_lines_for(q, self.ctx())
            self.assertEqual(first, ["none|working it out - ask again in a few seconds"])
            self.V.DECKFOR["thread"].join(30)
            self.assertTrue(self.V.deckfor_lines_for(q, self.ctx())[0].startswith("deckfor|"))
            out = self.V.deckfor_lines_for({}, {"decks": None, "why": "not read"})
            self.assertEqual(out, ["none|not read"])
            out = self.V.deckfor_lines_for({"n": "abc", "hp": "inf"}, dict(self.ctx(), book=None), wait=True)
            self.assertTrue(out[0].startswith("none|"), out)
        finally:
            self.V.DECKFOR["cache"].clear()
            self.V.DECKFOR["cache"].update(keep)

    def test_old_lines_while_worked_out_again(self):
        # (an answer kept past DECKFOR_S: handed back with a note| while the thread works it out again - the bot's
        # 10-minute re-ask never gets a "working it out" that would drop the zone's deck for a moment)
        keep = dict(self.V.DECKFOR["cache"])
        try:
            self.V.DECKFOR["cache"].clear()
            q = {"zone": "Z/Graveyard", "school": "storm", "n": "10"}
            out = self.V.deckfor_lines_for(q, self.ctx(), wait=True)
            (key, (at, lines)), = self.V.DECKFOR["cache"].items()
            self.V.DECKFOR["cache"][key] = (at - self.V.DECKFOR_S - 120, lines)
            old = self.V.deckfor_lines_for(q, self.ctx())
            self.assertEqual(old[:len(out)], out)
            self.assertTrue(old[-1].startswith("note|worked out 12 minutes ago"), old)
            self.V.DECKFOR["thread"].join(30)
            self.assertGreater(self.V.DECKFOR["cache"][key][0], at)    # (worked out again, kept anew)
            self.assertEqual(self.V.deckfor_lines_for(q, self.ctx()), out)
        finally:
            self.V.DECKFOR["cache"].clear()
            self.V.DECKFOR["cache"].update(keep)

    def test_battles_read_again_paced_outside_the_lock(self):
        # (/deckfor's thread: the battles recorded read again pausing for each while a gated request is in flight, with
        # SIM_LOCK free - a gated /decks or /sim waiting on it is in flight itself)
        V = self.V
        busy, seen, slept = [3], [], []

        def battles(base, days):
            for k in range(2):
                seen.append((V.SIM_LOCK.locked(), busy[0]))
                yield {"zone": "Z/Graveyard", "me": {"sc": 4, "school": "storm"}, "rounds": [],
                       "parts": [{"sc": 0, "side": "enemy", "name": "Rat", "max": 600}, {"sc": 4, "side": "me"}]}

        def is_busy():
            busy[0] = max(0, busy[0] - 1)
            return busy[0] > 0
        keep = dict(V.SIM)
        try:
            V.SIM.update(book=None, facts=None, at=0.0)
            with mock.patch.object(S.FoeBook, "_read", staticmethod(battles)), \
                    mock.patch.object(V.GATE, "busy", is_busy), mock.patch.object(V.time, "sleep", slept.append):
                book, facts = V.sim_book(paced=True)
            # (the lock free while read; the first battle held till the gated requests ended - 2 waits)
            self.assertEqual(seen, [(False, 3), (False, 0)])
            self.assertEqual(slept, [0.05, 0.05])
            self.assertEqual(dict(book.groups["Z/Graveyard"]), {("Rat",): 2})
            self.assertIs(V.SIM["book"], book)
            # (kept: asked again within SIM_BOOK_S, nothing read)
            with mock.patch.object(S.FoeBook, "_read", staticmethod(lambda base, days: 1 / 0)):
                self.assertIs(V.sim_book(paced=True)[0], book)
                self.assertIs(V.sim_book()[0], book)
            self.assertEqual(V.SIM["refreshing"], 0)
        finally:
            V.SIM.clear()
            V.SIM.update(keep)

    def test_old_book_while_a_paced_read_runs(self):
        # (a gated /sim or /decks while /deckfor's - or the planner's - paced read runs: the old book, never the whole
        # archive read again inside the request; none at all: read there)
        V = self.V
        old = S.FoeBook(battles=[])
        keep = dict(V.SIM)
        try:
            # (stale by the clock - at 0.0 isn't stale on a machine up under SIM_BOOK_S)
            V.SIM.update(book=old, facts={"f": 1}, at=time.monotonic() - V.SIM_BOOK_S - 1, refreshing=1)
            with mock.patch.object(S, "FoeBook", lambda *a, **kw: 1 / 0):
                self.assertEqual(V.sim_book(), (old, {"f": 1}))
                self.assertEqual(V.sim_book(paced=True), (old, {"f": 1}))
            V.SIM.update(book=None, refreshing=1)
            with mock.patch.object(S, "load_facts", lambda path: {}):
                self.assertIsNotNone(V.sim_book()[0])
            # (a paced read that fails: the count put back)
            V.SIM.update(book=None, at=0.0, refreshing=0)
            with mock.patch.object(S.FoeBook, "_read", staticmethod(lambda base, days: iter([]))), \
                    mock.patch.object(S, "load_facts", lambda path: 1 / 0):
                with self.assertRaises(ZeroDivisionError):
                    V.sim_book(paced=True)
            self.assertEqual(V.SIM["refreshing"], 0)
        finally:
            V.SIM.clear()
            V.SIM.update(keep)

    def test_plan_load_counts_its_read(self):
        # (the planner's thread: SIM refreshing up while it reads the battles, put back after - and after a failure)
        import tempfile
        import battlelearn
        V = self.V
        seen = []

        def read(base, days=120):
            seen.append(V.SIM["refreshing"])
            return iter([])
        keep_sim, keep_plan, keep_log = dict(V.SIM), dict(V.PLAN), V.log
        try:
            V.log = lambda *a, **kw: None
            V.SIM["refreshing"] = 0
            with tempfile.TemporaryDirectory() as root, mock.patch.object(V, "ROOT", root), \
                    mock.patch.object(battlelearn, "read", read):
                os.makedirs(os.path.join(root, "learned", "battles"))
                V._plan_load()
                self.assertEqual((seen, V.SIM["refreshing"]), ([1], 0))
                with mock.patch.object(S, "load_facts", lambda path: 1 / 0):
                    V._plan_load()
                self.assertEqual((seen, V.SIM["refreshing"]), ([1, 1], 0))
        finally:
            V.log = keep_log
            V.SIM.clear()
            V.SIM.update(keep_sim)
            V.PLAN.clear()
            V.PLAN.update(keep_plan)

    def test_thread_reads_paced_and_pauses(self):
        # (the deckfor thread's own wiring: sim_book(paced=True) and best_decks(pause=gate_wait))
        V = self.V
        c = self.ctx()
        asked = {}

        def book(paced=False):
            asked["paced"] = paced
            return c["book"], c["facts"]

        def best(*a, **kw):
            asked["pause"] = kw.get("pause")
            return {"decks": [], "groups": [], "why": []}
        keep = dict(V.DECKFOR["cache"])
        try:
            V.DECKFOR["cache"].clear()
            with mock.patch.object(V, "sim_book", book), mock.patch.object(V, "enemy_state", lambda: (None, None)), \
                    mock.patch.object(S, "best_decks", best):
                V.deckfor_lines_for({"zone": "Z/Graveyard", "n": "10"}, {"decks": c["decks"], "why": ""}, wait=True)
            self.assertEqual(asked, {"paced": True, "pause": V.gate_wait})
        finally:
            V.DECKFOR["cache"].clear()
            V.DECKFOR["cache"].update(keep)

    def test_route(self):
        """/deckfor on a local server: the decks' last reading, the battles recorded and the wiki stood in for"""
        import tempfile
        import threading
        import urllib.request
        from http.server import ThreadingHTTPServer
        V, c = self.V, self.ctx()
        keep_cache, keep_log = dict(V.DECKFOR["cache"]), V.LOG
        with tempfile.TemporaryDirectory() as d, \
                mock.patch.object(V, "decks_reading", lambda fresh, out=False: (c["decks"], "")), \
                mock.patch.object(V, "sim_book", lambda paced=False: (c["book"], c["facts"])), \
                mock.patch.object(V, "enemy_state", lambda: (None, None)):
            V.LOG = os.path.join(d, "vision.log")
            V.DECKFOR["cache"].clear()
            srv = ThreadingHTTPServer(("127.0.0.1", 0), V.Handler)
            threading.Thread(target=srv.serve_forever, daemon=True).start()
            try:
                def get(path):
                    with urllib.request.urlopen("http://127.0.0.1:%d%s" % (srv.server_address[1], path),
                                                timeout=10) as r:
                        return r.status, r.read().decode().split("\n")
                code, ln = get("/deckfor?zone=Z%2FGraveyard&school=storm&n=10")
                self.assertEqual((code, ln), (200, ["none|working it out - ask again in a few seconds"]))
                V.DECKFOR["thread"].join(30)
                code, ln = get("/deckfor?zone=Z%2FGraveyard&school=storm&n=10")
                self.assertEqual(code, 200)
                self.assertTrue(ln[0].startswith("deckfor|abc|Storm Deck|"), ln)
            finally:
                srv.shutdown()
                srv.server_close()
                V.LOG = keep_log
                V.DECKFOR["cache"].clear()
                V.DECKFOR["cache"].update(keep_cache)
        self.assertNotIn("/deckfor", V.GATED)          # (no memory read: the decks' last reading only)


# ============================================================================ v1.8.0: discardspent - /plan's mates,
# /deckkinds
class SpentMates(unittest.TestCase):
    """/plan's mates throw their spent copies as the asking bot's own vals say (vision.py plan_lines_for): discardspent
    sent - the party runs this AutoFarmer; not sent - an older one, which holds them (Mate's own default). A Blader's or
    Healer's 0 is its own role's (Decks.ahk DeckSimVals), not the party's: its hitter mates still throw theirs"""

    @classmethod
    def setUpClass(cls):
        try:
            import vision
        except ImportError as e:
            raise unittest.SkipTest("vision.py can't be imported here (%s)" % e)
        cls.V = vision
        cls.log = vision.log
        vision.log = lambda *a, **kw: None

    @classmethod
    def tearDownClass(cls):
        cls.V.log = cls.log

    ask = PlanTeam.ask

    def test_mates_take_this_bots_discardspent(self):
        # (role: the asking bot's - Planner.ahk sends it only for a party's Blader or Healer, whose DeckSimVals always
        # sends discardspent 0: the key there says the party runs this AutoFarmer; a hitter's - no role - its setting)
        for role, vals, want in (("blader", "discardspent:1", True), ("blader", "discardspent:0", True),
                                 ("healer", "discardspent:0", True), ("blader", "", False),
                                 ("", "discardspent:1", True), ("", "discardspent:0", False), ("", "", False)):
            got = {}
            q = {"seed": "1", "budget": "1500", "seat": "4", "vals": vals,
                 "mates": "Ann~5~storm~3000~3000~hitter~7~0~104:blade:0:storm:35%;104:blade:0:storm:35%"}
            if role:
                q["role"] = role
            out = self.ask(q, spy=got)
            self.assertTrue(out[0].startswith("plan|"), out)
            self.assertEqual([m.opts.discardspent for m in got["state"].mates], [want], (role, vals))
            # (the asking bot itself plays as its own vals say - a support never throws: its role gate)
            self.assertEqual(got["opts"].discardspent, vals == "discardspent:1", (role, vals))

    def test_a_support_leaders_hitter_mate_throws(self):
        """a Blader leader's team plan (vals discardspent:0 - its role's): the hitter mate's spent Stormblades go, as
        its own bot throws them; a support mate's are held (_discard_spent's role gate)"""
        for mrole, want in (("hitter", 1), ("blader", 3)):
            got = {}
            q = {"seed": "1", "budget": "1500", "seat": "4", "role": "blader", "vals": "discardspent:0",
                 "mates": "Ann~5~storm~3000~3000~%s~7~0~101:damage:7:storm:1000;104:blade:0:storm:35%%;"
                          "104:blade:0:storm:35%%;104:blade:0:storm:35%%" % mrole}
            out = self.ask(q, spy=got)
            self.assertTrue(out[0].startswith("plan|"), out)
            b = S._Battle.from_state(got["state"], got["me"], got["foes"], got["opts"], random.Random(1))
            k = next(i for i in range(len(b.side)) if b.side[i] is not None and getattr(b.side[i], "name", "") == "Ann")
            b._swap(k)
            b.discard()
            self.assertEqual(sum(1 for c in b.hand if c.kind == "blade"), want, mrole)


class DeckKinds(unittest.TestCase):
    """/deckkinds (Autofarmer.ahk DiscardSpentDeck, once a battle): the worn deck's Sharpen and Potent copies - main
    side and item cards, never the treasure side - from the decks' last reading, and whether the worn deck's signature
    now is that reading's"""

    @classmethod
    def setUpClass(cls):
        try:
            import vision
        except ImportError as e:
            raise unittest.SkipTest("vision.py can't be imported here (%s)" % e)
        cls.V = vision

    def test_deckkinds(self):
        d = deckmem_deck()
        d["cards"].append(dict(d["cards"][2], name="Sharpened Blade", display="Sharpened Blade", kind="sharpen",
                               template_id=201, count=2, boosts_text="", value_text="+10%"))
        d["cards"].append(dict(d["cards"][2], name="Sharpened Blade", display="Sharpened Blade", kind="sharpen",
                               template_id=201, count=3, side="treasure", boosts_text="", value_text="+10%"))
        d["item_cards"] = [{"name": "Potent Trap", "template_id": 202, "count": 1, "display": "Potent Trap",
                            "from": "Pet"}]
        facts = dict(FACTS)
        facts[202] = {"rec": "card", "v": 1, "tid": 202, "name": "Potent Trap", "kind": "potent", "value": "+10%",
                      "full": True}
        reading = {"decks": [d], "equipped": 0xABC, "why": "", "read_at": time.monotonic() - 30}
        worn = {"decks": [dict(d)], "sig": "S1", "read_at": time.monotonic()}
        out = self.V.deckkinds_lines({"decks": reading, "worn": worn, "sig": "S1", "facts": facts})
        self.assertEqual(len(out), 1, out)
        f = out[0].split("|")
        self.assertEqual(f[:4], ["kinds", "2", "1", "1"])      # (the treasure side's 3 Sharpens not counted)
        self.assertAlmostEqual(float(f[4]), 30, delta=2)
        # (another deck worn since the reading: sig 0; the signature not known: "")
        self.assertEqual(self.V.deckkinds_lines({"decks": reading, "worn": worn, "sig": "S2", "facts": facts})[0]
                         .split("|")[3], "0")
        other = {"decks": [dict(d, gid=0xDEF)], "sig": "S1"}
        self.assertEqual(self.V.deckkinds_lines({"decks": reading, "worn": other, "sig": "S1", "facts": facts})[0]
                         .split("|")[3], "0")
        self.assertEqual(self.V.deckkinds_lines({"decks": reading, "worn": None, "sig": None, "facts": facts})[0]
                         .split("|")[3], "")
        # (no reading with kinds: the worn deck's reading, kinds from the facts)
        self.assertEqual(self.V.deckkinds_lines({"decks": None, "worn": worn, "sig": "S1", "facts": facts})[0]
                         .split("|")[:4], ["kinds", "2", "1", "1"])
        self.assertTrue(self.V.deckkinds_lines({"decks": None, "worn": None, "sig": None, "facts": {}})[0]
                        .startswith("none|"))
        # (junk never raises)
        self.assertTrue(self.V.deckkinds_lines({"decks": {"decks": "x"}, "worn": 5, "sig": [], "facts": 7})[0]
                        .startswith(("none|", "kinds|")))

    def test_never_reads_the_battles(self):
        """the facts without waiting (it answers in a battle, 600 ms at most): the simulator's last read of them at any
        age, else cards.jsonl alone - never sim_book, whose read of every battle recorded would hold the request"""
        import json
        import tempfile
        d = deckmem_deck()
        d["item_cards"] = [{"name": "Potent Trap", "template_id": 202, "count": 1, "display": "Potent Trap",
                            "from": "Pet"}]
        potent = {"rec": "card", "v": 1, "tid": 202, "name": "Potent Trap", "kind": "potent", "value": "+10%",
                  "full": True}
        reading = {"decks": [d], "read_at": time.monotonic()}
        worn = {"decks": [dict(d)], "sig": "S1", "read_at": time.monotonic()}
        ctx = {"decks": reading, "worn": worn, "sig": "S1"}       # (no facts: the helper's own)

        def no(*a, **kw):
            raise AssertionError("the battles recorded read in a battle's request")
        keep_root, keep_facts, keep_at = self.V.ROOT, self.V.SIM["facts"], self.V.SIM["at"]
        with tempfile.TemporaryDirectory() as root, mock.patch.object(self.V, "sim_book", no), \
                mock.patch.object(S, "FoeBook", no):
            try:
                os.makedirs(os.path.join(root, "learned", "battles"))
                with open(os.path.join(root, "learned", "battles", "cards.jsonl"), "w", encoding="utf-8") as f:
                    f.write(json.dumps(potent) + "\n")
                self.V.ROOT = root
                # (none read yet: cards.jsonl's)
                self.V.SIM["facts"] = None
                self.assertEqual(self.V.deckkinds_lines(dict(ctx))[0].split("|")[:4], ["kinds", "0", "1", "1"])
                # (the simulator's, however old - SIM_BOOK_S long gone: not read again here)
                self.V.SIM["facts"], self.V.SIM["at"] = {}, time.monotonic() - 10 * self.V.SIM_BOOK_S
                self.assertEqual(self.V.deckkinds_lines(dict(ctx))[0].split("|")[:4], ["kinds", "0", "0", "1"])
                self.V.SIM["facts"] = {202: potent}
                self.assertEqual(self.V.deckkinds_lines(dict(ctx))[0].split("|")[:4], ["kinds", "0", "1", "1"])
            finally:
                self.V.ROOT, self.V.SIM["facts"], self.V.SIM["at"] = keep_root, keep_facts, keep_at

    def test_route(self):
        """/deckkinds on a local server: gated (navmem's lock for deck_sig - the recorder waits), deckkinds_lines'
        answer"""
        import tempfile
        import threading
        import urllib.request
        from http.server import ThreadingHTTPServer
        V = self.V
        self.assertIn("/deckkinds", V.GATED)
        keep_log = V.LOG
        with tempfile.TemporaryDirectory() as d, \
                mock.patch.object(V, "deckkinds_lines", lambda ctx=None: ["kinds|1|0|1|2.0"]):
            V.LOG = os.path.join(d, "vision.log")
            srv = ThreadingHTTPServer(("127.0.0.1", 0), V.Handler)
            threading.Thread(target=srv.serve_forever, daemon=True).start()
            try:
                with urllib.request.urlopen("http://127.0.0.1:%d/deckkinds" % srv.server_address[1], timeout=10) as r:
                    self.assertEqual((r.status, r.read().decode().split("\n")), (200, ["kinds|1|0|1|2.0"]))
            finally:
                srv.shutdown()
                srv.server_close()
                V.LOG = keep_log
        self.assertEqual(V.GATE.n, 0)


if __name__ == "__main__":
    unittest.main()
