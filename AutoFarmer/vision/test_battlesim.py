"""test_battlesim.py - the battle simulator's checks (standard library only):  python -m unittest vision\\test_battlesim.py"""
import contextlib
import datetime
import io
import json
import os
import random
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import battlesim as S  # noqa: E402


def hit(name="Storm Lord", pips=7, value=1000, school="storm", aoe=False, count=1):
    return {"name": name, "display": name, "kind": "aoe" if aoe else "damage", "school": school, "pips": pips,
            "value": value, "heads_text": "%s:%d" % (school, value), "count": count, "side": "main"}


def boost(kind, name, pct, school="storm", count=1):
    return {"name": name, "display": name, "kind": kind, "school": school, "pips": 0, "value": pct,
            "boosts_text": "%s:%d" % (school, pct), "count": count, "side": "main"}


class Maths(unittest.TestCase):
    def test_damage_curve(self):
        self.assertAlmostEqual(S.damage_multiplier(0), 1.0)
        self.assertAlmostEqual(S.damage_multiplier(100), 2.0)
        self.assertAlmostEqual(S.damage_multiplier(150), 2.5)
        self.assertAlmostEqual(S.damage_multiplier(150.0001), 2.5, places=3)   # continuous at the knee
        self.assertLess(S.damage_multiplier(400), 3.0)                         # towards +200 %
        self.assertGreater(S.damage_multiplier(200), S.damage_multiplier(160))

    def test_crit(self):
        self.assertAlmostEqual(S.crit_mult(630, 90), 1.7, places=2)   # Decks.ahk's worked example
        self.assertEqual(S.crit_mult(500, 0), 2)
        self.assertEqual(S.crit_mult(0, 50), 1)
        self.assertAlmostEqual(S.crit_chance(300, 0, 100), 1.0)
        self.assertEqual(S.crit_chance(0, 0), 0)

    def test_pairs(self):
        self.assertEqual(S.parse_pairs("fire:230,ice:230,storm:230"), {"fire": 230, "ice": 230, "storm": 230})
        self.assertEqual(S.parse_pairs("all:25"), {"all": 25})
        self.assertEqual(S.parse_pairs("?"), {})
        self.assertEqual(S.fits({"all": 25}, "fire"), 25)
        self.assertEqual(S.fits({"ice": 35}, "fire"), 0)

    def test_resist_and_pierce(self):
        f = S.Foe("x", 100, "storm", resist={"storm": 0.6})
        self.assertAlmostEqual(f.resist_mult("storm"), 0.6)
        self.assertAlmostEqual(f.resist_mult("storm", pierce=10), 0.7)
        self.assertAlmostEqual(f.resist_mult("storm", pierce=90), 1.0)     # pierce never past nothing
        boosted = S.Foe("y", 100, "fire", resist={"storm": 1.2})
        self.assertAlmostEqual(boosted.resist_mult("storm", pierce=10), 1.2)
        plain = S.Foe("z", 100, "fire")
        self.assertAlmostEqual(plain.resist_mult("fire"), 0.85)            # its own school: the bot's 15 %
        self.assertAlmostEqual(plain.resist_mult("storm"), 0.85)           # nothing learned: 15 % on everything


class Pips(unittest.TestCase):
    def test_power_pips_double_for_school(self):
        b = S._Battle([], S.Me("storm"), [S.Foe("x", 10)], S.Opts(), random.Random(1))
        b.pips, b.power = 4, 3
        storm = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1})
        fire = S.Card("Fire Dragon", "damage", "fire", 7, heads={"fire": 1})
        self.assertTrue(b.pay(storm)[0])         # 1 + 3 x 2 = 7
        self.assertFalse(b.pay(fire)[0])         # 4 of another school
        b.spend(storm)
        self.assertEqual((b.pips, b.power), (0, 0))

    def test_x_pip(self):
        b = S._Battle([], S.Me("fire"), [S.Foe("x", 10)], S.Opts(), random.Random(1))
        b.pips, b.power = 5, 2
        x = S.Card("Meteor", "aoe", "fire", 0, x=True, heads={"fire": 100})
        self.assertEqual(b.pip_value(x), 7)
        self.assertAlmostEqual(b.least(x, 0), 7 * 100 * 0.85)     # every pip (power 2), the 15 % resist


class Simulate(unittest.TestCase):
    def test_easy_win(self):
        cards = S.deck_cards({"cards": [hit(count=20)]})
        me = S.Me("storm", 3000, damage=50)
        r = S.simulate(cards, me, [S.Foe("Rat", 500)], n=200, seed=1)
        self.assertGreater(r["won"], 0.95)
        self.assertLessEqual(r["rounds"], 8)

    def test_no_hits(self):
        cards = S.deck_cards({"cards": [boost("blade", "Stormblade", 35, count=10)]})
        r = S.simulate(cards, S.Me("storm"), [S.Foe("Rat", 500)], n=50, seed=1)
        self.assertEqual(r["won"], 0)
        self.assertIn("no hit in the deck", r["why"])

    def test_strong_foe_kills(self):
        cards = S.deck_cards({"cards": [hit(value=50, pips=1, count=40)]})
        foe = S.Foe("Ogre", 50000, spells=[("Smash", 1.0, {"pips": 1, "min": 900, "max": 1000, "accuracy": 100})])
        r = S.simulate(cards, S.Me("storm", 1500), [foe], n=100, seed=2)
        self.assertGreater(r["lost"], 0.95)

    def test_boosts_help(self):
        foe = S.Foe("Boss", 6000, spells=[("Hit", 1.0, {"pips": 2, "min": 150, "max": 200, "accuracy": 100})])
        me = S.Me("storm", 3000)
        plain = S.deck_cards({"cards": [hit(count=8)]})
        boosted = S.deck_cards({"cards": [hit(count=8), boost("blade", "Stormblade", 35, count=6),
                                          boost("trap", "Storm Trap", 30, count=6)]})
        a = S.simulate(plain, me, [foe], n=300, seed=3)
        # (reboost 1: each blade and trap again after the hit it went into - with reboost off the used copies clog the
        # hand: Reboost.test_used_copies_clog_the_hand)
        b = S.simulate(boosted, me, [foe], S.Opts(reboost=1), n=300, seed=3)
        self.assertLessEqual(b["rounds"] or 99, a["rounds"] or 99)
        name, dmg, used = S.best_hit(boosted, me, foe)
        self.assertEqual(name, "Storm Lord")
        self.assertEqual(sorted(used), ["Storm Trap", "Stormblade"])
        self.assertAlmostEqual(dmg, 1000 * 1.35 * 1.30 * 0.85, places=3)

    def test_aoe_against_many(self):
        cards = S.deck_cards({"cards": [hit("Tempest", 6, 500, aoe=True, count=10)]})
        foes = [S.Foe("Imp %d" % i, 400) for i in range(4)]
        r = S.simulate(cards, S.Me("storm", 3000), foes, n=100, seed=4)
        self.assertGreater(r["won"], 0.9)

    def test_verdict_words(self):
        cards = S.deck_cards({"cards": [hit(count=20)]})
        me = S.Me("storm", 3000)
        foes = [S.Foe("Rat", 500)]
        r = S.simulate(cards, me, foes, n=100, seed=1)
        v = S.verdict(r, cards, me, foes)
        self.assertEqual(v["word"], "yes")
        self.assertIn("Rat 500 health", v["text"])
        lines = S.sim_lines(r, v, foes)
        self.assertTrue(lines[0].startswith("sim|"))
        self.assertTrue(any(x.startswith("verdict|yes|") for x in lines))

    def test_bad_input_never_raises(self):
        r = S.simulate(None, S.Me(), [S.Foe("x", 10)], n=5)
        self.assertTrue(r["why"])
        self.assertEqual(S.verdict({}, [], S.Me(), [])["word"], "unknown")


class Learn(unittest.TestCase):
    def test_support_and_boss(self):
        boss_deck = {"gid": 0x1234, "display": "Boss Storm", "school": "Storm", "sets": [2],
                     "cards": [hit(count=4), boost("blade", "Stormblade", 35, count=3),
                               boost("trap", "Storm Trap", 30, count=3),
                               {"name": "Tower Shield", "display": "Tower Shield", "kind": "ward", "count": 2}]}
        mob_deck = {"gid": 0x99, "display": "Mobs", "school": "storm", "sets": [1],
                    "cards": [hit("Tempest", 6, 500, aoe=True, count=8), hit("Thunder Snake", 2, 125, count=2)]}
        loose = {"gid": 0x7, "display": "Spare", "sets": [], "cards": []}
        learned = S.learn_decks({"decks": [boss_deck, mob_deck, loose]})
        self.assertEqual(len(learned), 2)
        b, m = learned
        self.assertEqual((b["gid"], b["school"], b["eqset"], b["when"]), ("1234", "storm", 2, ["boss"]))
        self.assertEqual(b["vals"].get("cardlogic"), 1)
        self.assertNotIn("useblades", b["vals"])
        self.assertNotIn("usetower", b["vals"])
        self.assertEqual(b["vals"]["useheal"], 0)
        self.assertEqual((m["eqset"], m["when"]), (1, ["default", "collect"]))
        self.assertEqual(m["vals"]["useblades"], 0)
        self.assertEqual(m["vals"]["cardlogic"], 2)
        line = S.learn_lines([b])[0]
        self.assertTrue(line.startswith("learn|1234|Boss Storm|storm|2|boss|"))

    def test_only_deck_is_default(self):
        d = {"gid": 1, "display": "Only", "equipped": True, "sets": [], "cards": [hit(count=5)]}
        (L,) = S.learn_decks({"decks": [d]})
        self.assertEqual(L["when"], ["default"])
        self.assertEqual(L["eqset"], 0)


class Book(unittest.TestCase):
    def test_learned_from_records(self):
        battle = {"me": {"sc": 4, "school": "storm"},
                  "parts": [{"sc": 0, "side": "enemy", "name": "Bonestriker", "max": 2400, "school": "death"},
                            {"sc": 4, "side": "me", "name": "Me"}],
                  "rounds": [{"hand": [{"school": "storm"}], "played": {"hand_i": 0, "targets": [0]},
                              "casts": [{"sc": 4, "spell": "Storm Lord", "res": [[0, 20, 0.8]], "crit": [[1, 2, 1, 2]]},
                                        {"sc": 0, "spell": "Deathblade"}]},
                             {"hand": [], "played": {},
                              "casts": [{"sc": 0, "spell": "Wraith", "hp": [[4, 3000, -420]]}]}]}
        book = S.FoeBook(battles=[battle, battle])
        f = book.foe("Bonestriker")
        self.assertEqual((f.maxhp, f.school), (2400, "death"))
        self.assertAlmostEqual(f.resist["storm"], 0.8)
        self.assertEqual(f.block_p, 1.0)
        self.assertEqual(f.hits, [420, 420])
        self.assertAlmostEqual(f.hit_p, 0.5)
        unknown = book.foe("Nobody")
        self.assertIn("generic hitter", unknown.src)
        self.assertEqual(unknown.maxhp, 1000)


class Fixes(unittest.TestCase):
    """v1.0.0: what the simulator's first build got wrong"""

    def test_value_text_from_facts(self):
        # (cards.jsonl keeps handmem's value_text: an item card's kind and value only from there)
        facts = {123: {"kind": "damage", "value": "295-335", "school": "storm", "pips": 4, "heads": "storm:295"},
                 124: {"kind": "aoe", "value": "100/pip", "school": "fire", "pips": 0},
                 125: {"kind": "blade", "value": "35%", "school": "storm", "boosts": "storm:35"}}
        cards = S.deck_cards({"item_cards": [{"template_id": 123, "count": 1}, {"template_id": 124, "count": 1},
                                             {"template_id": 125, "count": 2}]}, facts)
        self.assertEqual(len(cards), 4)
        hit, meteor, blade = cards[0], cards[1], cards[2]
        self.assertEqual(hit.value, 295)
        self.assertAlmostEqual(hit.top, 335 / 295.0)
        self.assertTrue(meteor.x)
        self.assertEqual(meteor.value, 100)
        self.assertEqual(blade.boosts, {"storm": 35})
        self.assertEqual(S.value_of("+10%"), (10.0, None, False))
        self.assertEqual(S.value_of(""), (None, None, False))
        # (and deck learning with such an item card doesn't fall over)
        L = S.learn_decks({"decks": [{"gid": 5, "sets": [1], "display": "D", "cards": [hit_dict()],
                                      "item_cards": [{"template_id": 123, "count": 1, "name": "Wand"}]}]}, facts)
        self.assertEqual(L[0]["kinds"]["damage"], 2)

    def test_range_top_from_value_text(self):
        c = S.card_of({"display": "Kraken", "kind": "damage", "school": "storm", "pips": 4, "value": 485,
                       "value_text": "485-525", "heads_text": "storm:485"})
        self.assertAlmostEqual(c.top, 525 / 485.0)
        plain = S.card_of({"display": "X", "kind": "damage", "school": "storm", "pips": 4, "value": 100})
        self.assertEqual(plain.top, S.RANGE_TOP)

    def test_torn_line_keeps_the_rest(self):
        today = datetime.date.today()
        with tempfile.TemporaryDirectory() as base:
            folder = os.path.join(base, today.strftime("%Y-%m"))
            os.makedirs(folder)
            def battle(i):
                return json.dumps({"rec": "battle", "v": 1, "id": today.strftime("%Y%m%d") + "-0000%02d-%d" % (i, i),
                                   "me": {"sc": 4}, "parts": [{"sc": 0, "side": "enemy", "name": "Foe%d" % i,
                                                               "max": 100 * (i + 1)}], "rounds": []},
                                  separators=(",", ":"))      # (compact, as the recorder writes them)
            with open(os.path.join(folder, today.isoformat() + ".jsonl"), "w") as f:
                f.write('{"rec":"header","v":1}\n' + battle(1) + "\n" + battle(2)[:40] + "\n" + battle(3) + "\n")
            book = S.FoeBook(base, days=2)
        self.assertEqual(book.why, "")
        self.assertEqual(sorted(book.by), ["Foe1", "Foe3"])

    def test_crit_chance_learned(self):
        battle = {"me": {"sc": 4, "school": "storm"},
                  "parts": [{"sc": 0, "side": "enemy", "name": "Tank", "max": 3000}],
                  "rounds": [{"hand": [], "played": {"targets": [0]},
                              "casts": [{"sc": 4, "spell": "Kraken", "crit_p": [600, 150, 150, 0.2]}]},
                             {"hand": [], "played": {"targets": [0]},
                              "casts": [{"sc": 4, "spell": "Kraken", "crit_p": [600, 150, 150, 30]}]}]}
        f = S.FoeBook(battles=[battle]).foe("Tank")
        self.assertAlmostEqual(f.crit_p, 0.25)     # 0.2 and 30% -> their median
        # (no criticals at all when the game says 0, whatever the rating)
        f.crit_p = 0.0
        cards = S.deck_cards({"cards": [hit(count=30)]})
        none = S.simulate(cards, S.Me("storm", 5000, crit=900), [f], n=60, seed=5)
        f.crit_p = 1.0
        every = S.simulate(cards, S.Me("storm", 5000, crit=900), [f], n=60, seed=5)
        self.assertLess(every["rounds"], none["rounds"])

    def test_unknown_block_is_not_zero(self):
        f = S.Foe("x", 100)
        me = S.Me("storm", crit=400)
        self.assertEqual(f.block_for(me), 400)
        self.assertAlmostEqual(S.crit_chance(400, f.block_for(me)), 0.75)
        v = S.verdict(S.simulate(S.deck_cards({"cards": [hit(count=5)]}), me, [f], n=10, seed=1),
                      S.deck_cards({"cards": [hit(count=5)]}), me, [f])
        self.assertTrue(any("critical chance isn't known" in n for n in v["notes"]))

    def test_identical_blades_dont_stack(self):
        cards = S.deck_cards({"cards": [boost("blade", "Stormblade", 35, count=4)]})
        b = S._Battle(cards, S.Me("storm"), [S.Foe("x", 1000)], S.Opts(), random.Random(1))
        b.draw()
        blades = [c for c in b.hand if c.kind == "blade"]
        b.me.accuracy = 100
        b.cast(blades[0])
        b.cast(blades[1])
        self.assertEqual(len(b.blades), 1)
        plan = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000})
        self.assertIsNone(b.pick_boost(plan))      # another Stormblade adds nothing


class FromState(unittest.TestCase):
    """v1.0.0: a battle started in the middle (the planner's round now)"""

    def cards(self):
        lord = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000}, tid=1)
        snake = S.Card("Thunder Snake", "damage", "storm", 2, heads={"storm": 150}, tid=2)
        blade = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3)
        trap = S.Card("Storm Trap", "trap", "storm", 0, boosts={"storm": 30}, tid=4)
        return lord, snake, blade, trap

    def test_of_deck_takes_the_hand_out(self):
        lord, snake, blade, trap = self.cards()
        pet = S.Card("Pet Blade", "blade", "storm", 0, boosts={"storm": 20}, tid=99)
        st = S.State.of_deck([lord, snake, snake, pet], [lord] * 3 + [snake] * 4 + [blade] * 2, rnd=3)
        self.assertEqual(sorted(c.name for c in st.pile), ["Storm Lord"] * 2 + ["Stormblade"] * 2 + ["Thunder Snake"] * 2)
        self.assertEqual(st.used, 2)                  # (about a card a round drawn before)
        self.assertEqual(S.State([lord], rnd=1, used=5).used, 5)

    def test_state_carried_over(self):
        lord, snake, blade, trap = self.cards()
        st = S.State([lord, blade], [snake] * 10 + [trap] * 5, pips=5, power=2, hp=1234, fhp=[800, None, 0],
                     blades=[("Stormblade", {"storm": 35}), ("Stormblade", {"storm": 35})],
                     traps=[[], [{"storm": 30}]], aura=({"storm": 25}, 2), rnd=4, boosts_run=1, me_first=True,
                     fpips=[3, None, 1])
        foes = [S.Foe("A", 1000), S.Foe("B", 2000), S.Foe("C", 500)]
        b = S._Battle.from_state(st, S.Me("storm", 3000), foes, S.Opts(), random.Random(1))
        self.assertEqual([c.name for c in b.hand], ["Storm Lord", "Stormblade"])
        self.assertEqual(len(b.pile), 15 - 3)       # (the 3 cards drawn before round 4 taken off)
        self.assertEqual((b.pips, b.power, b.hp, b.fhp), (5, 2, 1234, [800, 2000, 0]))
        self.assertEqual(b.blades, [("Stormblade", {"storm": 35})])   # (identical blades don't stack)
        self.assertEqual(b.traps, [[], [{"storm": 30}], []])
        self.assertEqual((b.aura, b.round0, b.boosts_run, b.me_first), (({"storm": 25}, 2), 4, 1, True))
        self.assertEqual(b.fpips[0], 3)
        self.assertEqual(b.fpips[2], 1)
        self.assertEqual(b.alive(), [0, 1])
        # (the state itself is never changed by a rollout)
        b.run_from(None, None, 3)
        self.assertEqual((st.pips, len(st.hand), len(st.pile), st.blades[0][0]), (5, 2, 15, "Stormblade"))

    def test_forced_play_and_aim(self):
        lord, snake, blade, trap = self.cards()
        foes = [S.Foe("A", 3000), S.Foe("B", 900)]
        st = S.State([lord, trap], [snake] * 10, pips=7, fhp=[3000, 900], me_first=True)
        me = S.Me("storm", 3000, accuracy=30)        # (never a miss)
        b = S._Battle.from_state(st, me, foes, S.Opts(), random.Random(2))
        b.run_from(b.hand[0], 1, horizon=1)          # (Storm Lord at B, not the one with the most health)
        self.assertEqual(b.fhp[1], 0)
        self.assertEqual(b.fhp[0], 3000)
        self.assertIsNone(b.aim)
        b = S._Battle.from_state(st, me, foes, S.Opts(), random.Random(2))
        b.force(b.hand[1], 1)                         # (the trap on B)
        self.assertEqual(b.traps, [[], [{"storm": 30}]])
        b = S._Battle.from_state(st, me, foes, S.Opts(), random.Random(2))
        b.force(b.hand[1])                            # (no aim: the bot's own - the most health)
        self.assertEqual(b.traps, [[{"storm": 30}], []])

    def test_round_now_has_no_pip_or_draw(self):
        lord, snake, blade, trap = self.cards()
        st = S.State([snake], [lord] * 10, pips=2, fhp=[5000], me_first=True)
        b = S._Battle.from_state(st, S.Me("storm", 3000, power_pip=0), [S.Foe("A", 5000)], S.Opts(), random.Random(3))
        r = b.run_from(None, None, horizon=1)        # (a pass: nothing spent, nothing drawn in the round now)
        self.assertEqual((r, b.pips, len(b.hand), b.rounds_run), ("cut", 2, 1, 1))
        b = S._Battle.from_state(st, S.Me("storm", 3000, power_pip=0), [S.Foe("A", 5000)], S.Opts(), random.Random(3))
        b.run_from(None, None, horizon=2)            # (round two: a pip and the hand refilled)
        self.assertEqual(b.pips, 3 - (2 if b.casts.get("Thunder Snake") else 0))
        self.assertGreaterEqual(len(b.hand) + sum(b.casts.values()), 7)

    def test_chain_as_simulate_plays_it(self):
        # (play=False: the round now is the bot's chain - choose - with no draw or discard)
        lord, snake, blade, trap = self.cards()
        st = S.State([snake, blade], [lord] * 5, pips=3, fhp=[5000], me_first=True)
        b = S._Battle.from_state(st, S.Me("storm", 3000, accuracy=30), [S.Foe("A", 5000)], S.Opts(cardlogic=1),
                                 random.Random(4))
        self.assertIs(b.choose(), b.hand[1])        # (boost first: the blade for the planned hit)
        b.run_from(False, None, horizon=1)
        self.assertEqual(b.casts, {"Stormblade": 1})


def hit_dict():
    return hit()


# ============================================================================ v1.0.0 batch 3: what the simulator lacked
def lord(tid=1, dot=None, value=1000, pips=7):
    return S.Card("Storm Lord", "damage", "storm", pips, heads={"storm": value}, tid=tid, dot=dot)


def biter(name="Biter", hp=6000, lo=100, hi=120, passes=False):
    """an enemy biting every round it can (passes: half its rounds a pass)"""
    return S.Foe(name, hp, spells=([(None, 1.0, None)] if passes else []) +
                 [("Bite", 1.0, {"pips": 1, "min": lo, "max": hi, "accuracy": 100})])


def sure(**kw):
    kw.setdefault("accuracy", 30)
    return S.Me("storm", kw.pop("maxhp", 3000), **kw)


class Dots(unittest.TestCase):
    def test_a_hits_damage_over_time_ticks(self):
        # (Fire Dragon's kind: 1000 now and 600 over 3 rounds - a tick of 200 at each of the next rounds' start)
        c = S.card_of({"display": "Dragon", "kind": "damage", "school": "storm", "pips": 1, "value": 1000,
                       "heads_text": "storm:1000", "dot": 600})
        self.assertEqual(c.dot, 600)
        self.assertEqual(S.card_of({"display": "X", "kind": "damage", "school": "storm", "value": 5}).dot, 0)
        self.assertEqual(S.Card("B", "blade", "storm", value=35, dot=600).dot, 0)     # (only a hit's)
        foe = S.Foe("Tank", 5000, resist={"storm": 1.0})
        tower = S.Card("Tower Shield", "ward", "ice", 0, value=50)
        st = S.State([c], [tower] * 20, pips=7, fhp=[5000], me_first=True)
        b = S._Battle.from_state(st, sure(power_pip=0), [foe], S.Opts(discardunused=0), random.Random(1))
        b.force(b.hand[0], 0)
        after = b.fhp[0]
        self.assertEqual(b.fdots[0], [[200.0, 3]])
        # (no hit in hand: the ticks only - its Tower Shields now go on me as the chain's filler, which deals nothing)
        r = b.run_from(None, None, horizon=5)
        self.assertEqual(r, "cut")
        self.assertEqual(after - b.fhp[0], 600)
        b = S._Battle.from_state(st, sure(power_pip=0), [foe], S.Opts(), random.Random(1))
        b.force(b.hand[0], 0)
        b.round = 1
        for _ in range(4):
            b.tick_dots()
        self.assertEqual(after - b.fhp[0], 600)                     # (3 ticks, then none)
        self.assertEqual(b.fdots[0], [])

    def test_no_dot_on_a_dead_enemy(self):
        c = S.Card("Dragon", "damage", "storm", 1, heads={"storm": 1000}, dot=600)
        st = S.State([c], [], pips=7, fhp=[500], me_first=True)
        b = S._Battle.from_state(st, sure(), [S.Foe("Rat", 500)], S.Opts(), random.Random(1))
        b.force(b.hand[0], 0)
        self.assertEqual((b.fhp[0], b.fdots[0]), (0, []))


def foe_rounds(foe, team=1, mates=None, n=3000, seed=1):
    """enemy foe's rounds alone against my side (nobody ever down): (the share of them it healed in, damage a round on
    me, on my whole side)"""
    st = S.State([], [], hp=10 ** 9, fhp=[1000], me_first=False, mates=mates or [])
    b = S._Battle.from_state(st, S.Me("storm", 10 ** 9, team=team), [foe], S.Opts(), random.Random(seed))
    heals = on_me = on_side = 0
    for _ in range(n):
        b.fhp[0] = 1000
        hp0 = [b._wiz(k).hp for k in b.wizards()]
        b.foe_round()
        hp1 = [b._wiz(k).hp for k in b.wizards()]
        heals += b.fhp[0] > 1000
        on_me += hp0[0] - hp1[0]
        on_side += sum(hp0) - sum(hp1)
    return heals / float(n), on_me / float(n), on_side / float(n)


def enemy_record(acts_round, n_rounds=4, zone="WizardCity/WC_Streets"):
    """a battle record where the enemy (sc 0, 'Shaman') does acts_round's casts (its hang / hp / fx) each round"""
    rounds = []
    for k in range(n_rounds):
        rounds.append({"n": k + 1, "hand": [], "played": None, "casts": [dict(acts_round, sc=0)]})
    return {"zone": zone, "me": {"sc": 4, "school": "storm"},
            "parts": [{"sc": 0, "side": "enemy", "name": "Shaman", "max": 3000},
                      {"sc": 1, "side": "enemy", "name": "Imp", "max": 800},
                      {"sc": 4, "side": "me"}, {"sc": 5, "side": "ally"}], "rounds": rounds}


class LearnedActs(unittest.TestCase):
    def test_what_an_enemy_does_besides_hitting(self):
        shield = {"spell": "Dark Shield", "hang": [[0, "kModifyIncomingDamage", 0, -50]]}
        heal = {"spell": "Mend", "hp": [[1, 300, 400]]}
        blade = {"spell": "Deathblade", "hang": [[0, "ModifyOutgoingDamage", 1, 35]]}
        trap = {"spell": "Death Trap", "hang": [[4, "kModifyIncomingDamage", 0, 30]]}
        weak = {"spell": "Weakness", "hang": [[5, "kModifyOutgoingDamage", 1, -25]]}
        stun = {"spell": "Stun", "fx": [[4, "kStun", 1]]}
        bite = {"spell": "Bite", "hp": [[4, 3000, -300]]}
        recs = [enemy_record(shield), enemy_record(heal), enemy_record(blade), enemy_record(trap), enemy_record(weak),
                enemy_record(stun), enemy_record(bite, n_rounds=12)]
        f = S.FoeBook(battles=recs).foe("Shaman")
        self.assertEqual(set(f.acts), {"heal", "shield", "blade", "trap", "weak", "stun"})
        self.assertAlmostEqual(f.acts["shield"]["p"], 4 / 36.0)
        self.assertEqual((f.acts["shield"]["v"], f.acts["heal"]["v"], f.acts["blade"]["v"], f.acts["trap"]["v"],
                          f.acts["weak"]["v"]), (50, 400, 35, 30, 25))
        self.assertIsNone(f.acts["stun"]["v"])
        self.assertAlmostEqual(f.dmg_p, 12 / 36.0)
        self.assertIn("besides its hits", f.src)
        self.assertEqual(f.hits, [300] * 12)

    def test_damage_over_time_ticks_learned(self):
        # (its DoT on me in round 1, ticks of 90 on me at the start of rounds 2-4 - outside any cast)
        dot = {"spell": "Poison", "hp": [[4, 3000, -100]], "hang": [[4, "kDamageOverTime", 0, 270]]}
        rec = enemy_record({"spell": "Bite", "hp": [[4, 3000, -100]]}, n_rounds=4)
        rec["rounds"][0]["casts"] = [dict(dot, sc=0)]
        for k in (1, 2, 3):
            rec["rounds"][k]["fx"] = {"hp": [[4, 2900, -90]]}
        f = S.FoeBook(battles=[rec]).foe("Shaman")
        self.assertEqual(f.acts["dot"], {"p": 0.25, "v": 90.0})

    def test_nothing_learned_nothing_changes(self):
        f = S.FoeBook(battles=[enemy_record({"spell": "Bite", "hp": [[4, 3000, -300]]})]).foe("Shaman")
        self.assertEqual(f.acts, {})
        self.assertNotIn("besides", f.src)
        # (a foe with acts {} and the same foe never given any: the same battles, number for number)
        cards = S.deck_cards({"cards": [hit(count=20)]})
        a = S.simulate(cards, S.Me("storm", 3000), [biter()], n=80, seed=7)
        g = biter()
        g.acts, g.dmg_p = {}, 0.5
        b = S.simulate(cards, S.Me("storm", 3000), [g], n=80, seed=7)
        self.assertEqual((a["won"], a["rounds"], a["hp_left"], a["dmg_in"]), (b["won"], b["rounds"], b["hp_left"],
                                                                              b["dmg_in"]))

    def test_acts_in_the_battle(self):
        cards = S.deck_cards({"cards": [hit("Bolt", 1, 500, count=40)]})
        me = S.Me("storm", 30000)
        plain = S.simulate(cards, me, [biter("Tank", 4000, passes=True)], n=120, seed=3)
        shielder = biter("Tank", 4000, passes=True)
        shielder.acts, shielder.dmg_p = {"shield": {"p": 0.5, "v": 50}}, 0.5
        shielded = S.simulate(cards, me, [shielder], n=120, seed=3)
        self.assertGreater(shielded["rounds"], plain["rounds"])
        healer = biter("Tank", 4000, passes=True)
        healer.acts, healer.dmg_p = {"heal": {"p": 0.5, "v": 300}}, 0.5
        self.assertGreater(S.simulate(cards, me, [healer], n=120, seed=3)["rounds"], plain["rounds"])
        # (a blade on itself and a trap on me: its hits harder)
        bladed = biter("Tank", 4000, passes=True)
        bladed.acts, bladed.dmg_p = {"blade": {"p": 0.5, "v": 100}, "trap": {"p": 0.5, "v": 100}}, 0.5
        # (the same seed: a blade and a trap that did nothing would leave it as plain's - 100% each: well over)
        self.assertGreater(S.simulate(cards, me, [bladed], n=120, seed=3)["dmg_in"], plain["dmg_in"] * 1.5)

    def test_acts_not_inflated_by_the_team(self):
        # (it hits one of my side 80% of the rounds and healed in 20%: 20% whoever of us its hits land on - alone with
        # Me.team 4 a single hit on another wizard is still a round it hit, not one free for a heal)
        def foe():
            f = S.Foe("Ogre", 90000, spells=[(None, 0.2, None), ("Bite", 0.8, {"pips": 0, "min": 10, "max": 10,
                                                                                 "accuracy": 100})])
            f.acts, f.dmg_p = {"heal": {"p": 0.2, "v": 100}}, 0.8
            return f
        for team in (1, 4):
            heals, _me, _side = foe_rounds(foe(), team=team)
            self.assertTrue(0.16 < heals < 0.24, (team, heals))
        # (known by its hits only, recorded in a party: on me 20% of the rounds, on one of us 80%, a heal 20%)
        f = S.Foe("Ghoul", 90000, hits=[300] * 10, hit_p=0.2)
        f.acts, f.dmg_p = {"heal": {"p": 0.2, "v": 100}}, 0.8
        heals, on_me, _side = foe_rounds(f)
        self.assertTrue(0.16 < heals < 0.24, heals)
        self.assertTrue(50 < on_me < 70, on_me)                     # (300 a hit, 20% of the rounds)

    def test_stun_skips_my_round(self):
        st = S.State([lord()], [], pips=7, fhp=[5000], me_first=True, stun=1)
        b = S._Battle.from_state(st, sure(), [S.Foe("Rat", 5000)], S.Opts(), random.Random(1))
        self.assertFalse(b.my_round(fresh=False))
        self.assertEqual((b.stun, len(b.hand)), (0, 1))
        stunner = S.Foe("Stunner", 5000, spells=[(None, 1.0, None)])
        stunner.acts, stunner.dmg_p = {"stun": {"p": 1.0, "v": None}}, 0.0
        b = S._Battle.from_state(S.State([lord()], [], pips=7, fhp=[5000], me_first=False), sure(), [stunner],
                                 S.Opts(), random.Random(1))
        b.foe_round()
        self.assertEqual(b.stun, 1)


class Charms(unittest.TestCase):
    """the charms on now (State: from the bot or the game's log - charms_from) in the battle"""

    def test_shields_and_weakness_on_my_hit(self):
        foe = S.Foe("Tank", 9000, resist={"storm": 1.0})
        st = S.State([lord()], [], pips=7, fhp=[9000], fshields=[[(50, ["storm"]), (20, ["fire"])]],
                     myweak=[(25, None)], me_first=True)
        b = S._Battle.from_state(st, sure(), [foe], S.Opts(), random.Random(1))
        self.assertAlmostEqual(b.least(b.hand[0], 0), 1000 * 0.5 * 0.75)
        b.force(b.hand[0], 0)
        self.assertEqual(b.fshields[0], [(20, ["fire"])])           # (the storm one used, the fire one left)
        self.assertEqual(b.myweak, [])

    def test_shields_traps_absorb_on_me(self):
        foe = S.Foe("Smasher", 9000, school="death", spells=[("Smash", 1.0, {"pips": 0, "min": 1000, "max": 1000,
                                                                           "accuracy": 100})])
        st = S.State([lord()], [], pips=0, fhp=[9000], shields=[(50, ["death"]), (40, ["fire"])],
                     mytraps=[(20, None)], absorb=100, me_first=False)
        b = S._Battle.from_state(st, sure(), [foe], S.Opts(), random.Random(1))
        b.foe_round()
        self.assertEqual(b.hp, 3000 - int(1000 * 1.2 * 0.5 - 100))
        self.assertEqual((b.shields, b.mytraps, b.absorb), ([(40, ["fire"])], [], 0))

    def test_charms_from_the_log(self):
        import battlerec
        facts = {104: {"name": "Stormblade", "boosts": "storm:35"}, 105: {"name": "Storm Trap", "boosts": "storm:30"}}
        d = {"me_sc": 4, "rounds": [{"n": 1, "casts": [
            {"sc": 5, "spell": "Stormblade", "hang": [[4, "kModifyOutgoingDamage", 1, 35]]},
            {"sc": 5, "spell": "Storm Trap", "hang": [[1, "kModifyIncomingDamage", 0, 30]]},
            {"sc": 1, "spell": "Shield", "hang": [[1, "kModifyIncomingDamage", 0, -50]]},
            {"sc": 0, "spell": "Curse", "hang": [[4, "kModifyIncomingDamage", 0, 25]]}]}]}
        ch = battlerec.charms_now(d, facts)
        st = S.State([lord()], [], pips=7, fhp=[900, 900], blades=[("storm/blade", {"storm": 35})])
        n = st.charms_from(ch, None, [0, 1])
        self.assertEqual(n, 4)
        self.assertEqual(st.blades, [("Stormblade", {"storm": 35.0})])
        self.assertEqual(st.traps, [[], [{"storm": 30.0}]])
        self.assertEqual(st.fshields, [[], [(50, None)]])
        self.assertEqual(st.mytraps, [(25, None)])
        # (an enemy not matched to its subcircle: nothing put on it)
        st = S.State([lord()], [], fhp=[900, 900])
        st.charms_from(ch, 4, [None, None])
        self.assertEqual((st.traps, st.fshields), ([[], []], [[], []]))
        self.assertEqual(S.State([lord()]).charms_from(None), 0)
        self.assertEqual(S.State([lord()]).charms_from({"by": "junk"}), 0)

    def test_an_enemy_not_matched_keeps_the_bots_count(self):
        # (the bot's Storm Trap on enemy 0; the log matched to enemy 1 only: enemy 0's trap kept, 1's from the log)
        import battlerec
        d = {"me_sc": 4, "rounds": [{"n": 1, "casts": [
            {"sc": 1, "spell": "Shield", "hang": [[1, "kModifyIncomingDamage", 0, -50]]}]}]}
        ch = battlerec.charms_now(d, {})
        st = S.State([lord()], [], fhp=[900, 900], traps=[[{"storm": 30}], [{"fire": 25}]],
                     fshields=[[(20, None)]], fblades=[[], [(10, None)], [(5, None)]])
        self.assertEqual(st.charms_from(ch, 4, [None, 1]), 1)
        self.assertEqual(st.traps, [[{"storm": 30}], []])
        self.assertEqual(st.fshields, [[(20, None)], [(50, None)]])
        self.assertEqual(st.fblades, [[], [], [(5, None)]])          # (one past the plates: kept as it was)

    def test_blade_named_as_the_hand_shows_it(self):
        # (the log names a spell by its template; the hand by its display - the blade on is the hand's card's name, so
        # a copy in hand is "on already" and never stacked)
        import battlerec
        facts = {104: {"tid": 104, "name": "Storm Blade", "display": "Stormblade", "kind": "blade",
                       "boosts": "storm:35"}}
        d = {"me_sc": 4, "rounds": [{"n": 1, "casts": [
            {"sc": 4, "spell": "Storm Blade", "hang": [[4, "kModifyOutgoingDamage", 1, 35]]}]}]}
        st = S.State([], [])
        st.charms_from(battlerec.charms_now(d, facts))
        self.assertEqual(st.blades, [("Stormblade", {"storm": 35.0})])
        blade = S.card_of({"template_id": 104, "name": "Storm Blade", "display": "Stormblade", "kind": "blade",
                           "school": "storm", "boosts_text": "storm:35"})
        self.assertEqual(blade.name, st.blades[0][0])

    def test_empty_charms_change_nothing(self):
        hand = [lord(), S.Card("Snake", "damage", "storm", 2, heads={"storm": 150}, tid=2),
                S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3)]
        foes = [biter("A", 2400), biter("B", 1200)]
        a = S.plan_round(S.State(hand, hand * 3, pips=6, fhp=[2000, 900], rnd=3), sure(), foes, n=30, seed=5,
                         budget_ms=10000)
        b = S.plan_round(S.State(hand, hand * 3, pips=6, fhp=[2000, 900], rnd=3, shields=[], fshields=[[], []],
                                 fblades=[], mytraps=None, myweak=[], absorb=0, stun=0, mates=[]), sure(), foes, n=30,
                         seed=5, budget_ms=10000)
        strip = lambda p: [(x["name"], x["aim"], x["n"], round(x["score"], 9)) for x in p["plays"]]  # noqa: E731
        self.assertEqual(strip(a), strip(b))

    def test_junk_charms(self):
        st = S.State([lord()], shields=[("x", None), (30, "storm"), None, (float("nan"), None), (25, ["storm", "q"])],
                     fshields="junk", fblades=[[(-5, None)]], stun="9", absorb="abc", mates=["no", 5], seat="x")
        self.assertEqual(st.shields, [(30, None), (25, ["storm"])])
        self.assertEqual((st.fshields, st.fblades, st.stun, st.absorb, st.mates, st.seat), ([], [[]], 3, 0, [], 0))


def mate(name, seat, role="hitter", hand=None, hp=None, maxhp=3000, pips=0):
    return S.Mate(name, seat, S.Me("storm", maxhp, accuracy=30), role, hand, [], pips, 0, hp)


class Team(unittest.TestCase):
    def test_side_in_cast_order(self):
        st = S.State([lord()], [], pips=7, fhp=[9000], seat=6,
                     mates=[mate("Bob", 7), mate("Ann", 4, "blader", []), mate("Cy", None, "healer", [])])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        self.assertEqual([b._wiz(k).name if k else "me" for k in b.wizards()], ["Ann", "me", "Bob", "Cy"])
        self.assertTrue(b.side[1].nohand)                            # (Bob: its hand not known)
        self.assertFalse(b.side[2].nohand)                           # (Ann: an empty hand is known)
        self.assertEqual(b.hitter(), 0)                              # (me, before Bob)

    def test_blader_puts_its_blade_on_the_hitter(self):
        blade = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3)
        trap = S.Card("Storm Trap", "trap", "storm", 0, boosts={"storm": 30}, tid=4)
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True,
                     mates=[mate("Ann", 4, "blader", [blade, trap])])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b.side_round(0, {})
        self.assertEqual(b.blades, [("Stormblade", {"storm": 35})])   # (on me - Ann's own: none)
        self.assertEqual(b.side[1].blades, [])
        self.assertEqual(b.cur, 0)
        b.side_round(1, {})                                          # (next round: the trap on the boss)
        self.assertEqual(b.traps, [[{"storm": 30}]])

    def test_healer_heals_the_lowest(self):
        heal = S.Card("Satyr", "heal", "life", 0, value=900, tid=6)
        st = S.State([lord()], [], pips=0, hp=600, fhp=[9000], me_first=True,
                     mates=[mate("Ann", 5, "healer", [heal]), mate("Bob", 6, hp=2000)])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b.side_round(0, {})
        self.assertEqual((b.hp, b.side[2].hp), (1500, 2000))

    def test_single_hits_spread_and_lost_only_when_all_down(self):
        foe = S.Foe("Ogre", 90000, spells=[("Smash", 1.0, {"pips": 0, "min": 400, "max": 400, "accuracy": 100})])
        st = S.State([], [], hp=3000, fhp=[90000], me_first=False, mates=[mate("Bob", 5, hp=3000)])
        b = S._Battle.from_state(st, sure(), [foe], S.Opts(), random.Random(2))
        for _ in range(6):
            b.foe_round()
        self.assertEqual(b.hp + b.side[1].hp, 6000 - 6 * 400)
        self.assertTrue(b.hp < 3000 and b.side[1].hp < 3000)         # (both hit)
        b.hp = 0
        self.assertFalse(b.lost())                                   # (Bob's still up)
        b.side[1].hp = 0
        self.assertTrue(b.lost())

    def test_unknown_hitter_mate_and_plan(self):
        # (a hitter mate whose hand isn't known: the generic hitter - the boss falls sooner than with me alone)
        snake = S.Card("Snake", "damage", "storm", 2, heads={"storm": 150}, tid=2)
        foes = [S.Foe("Boss", 1500, spells=[("Hit", 1.0, {"pips": 1, "min": 50, "max": 60, "accuracy": 100})])]
        alone = S.plan_round(S.State([snake], [snake] * 20, pips=2, fhp=[1500], me_first=True), sure(), foes, n=40,
                             seed=1, budget_ms=10000, horizon=30)
        st = S.State([snake], [snake] * 20, pips=2, fhp=[1500], me_first=True, mates=[mate("Bob", 5, pips=5)])
        team = S.plan_round(st, sure(), foes, n=40, seed=1, budget_ms=10000, horizon=30)
        r = lambda p: next(x for x in p["plays"] if x["name"] == "Snake")["rounds"]   # noqa: E731
        self.assertLess(r(team), r(alone))

    def test_plan_team_orders(self):
        # (Ann - a hitter mate - holds the kill; me a Snake: the team's plan gives Ann the kill)
        tempest = S.Card("Tempest", "aoe", "storm", 4, heads={"storm": 900}, tid=7)
        snake = S.Card("Snake", "damage", "storm", 2, heads={"storm": 150}, tid=2)
        foes = [biter("A", 600), biter("B", 600)]
        st = S.State([snake], [snake] * 10, pips=2, fhp=[600, 600], seat=4, me_first=True,
                     mates=[mate("Ann", 5, hand=[tempest, snake], pips=4), mate("Bob", 6, "blader")])
        tp = S.plan_team(st, sure(), foes, n=20, seed=3, budget_ms=8000)
        self.assertEqual([o["who"] for o in tp["orders"]], [0, 1])  # (Bob's hand not known: no order for it)
        ann = tp["orders"][1]
        self.assertEqual((ann["name"], ann["card"], ann["seat"]), ("Ann", "Tempest", 5))
        self.assertGreater(ann["won"], 0.9)
        self.assertTrue(any("hand isn't known" in w for w in tp["why"]))
        lines = S.team_lines(tp, foes)
        self.assertTrue(lines[1].startswith("order|1|5|Ann|0|7|aoe|all|"), lines)
        self.assertTrue(any(ln.startswith("teamnote|") for ln in lines))

    def test_recorded_hits_on_each_wizard(self):
        # (known by its hits on me only: half the rounds, 300 - with 3 mates each of us still takes them at that rate,
        # the side four times it - not my own rate shared out)
        def foe():
            return S.Foe("Ghoul", 90000, hits=[300] * 10, hit_p=0.5)
        _h, alone, _s = foe_rounds(foe())
        _h, on_me, on_side = foe_rounds(foe(), mates=[mate(nm, s, maxhp=10 ** 9) for nm, s in (("A", 5), ("B", 6),
                                                                                                ("C", 7))])
        self.assertTrue(135 < alone < 165 and 135 < on_me < 165, (alone, on_me))
        self.assertTrue(540 < on_side < 660, on_side)

    def test_a_mate_down(self):
        # (the party's 0 %: down - still in the duel, never back to full health; not known: its max)
        self.assertEqual([S.Mate(hp=v).hp for v in (0, "0", None, "", "x", float("nan"), -5, 1200)],
                         [0, 0, None, None, None, None, 0, 1200])
        foe = S.Foe("Ogre", 90000, spells=[("Smash", 1.0, {"pips": 0, "min": 400, "max": 400, "accuracy": 100})])
        st = S.State([], [], hp=3000, fhp=[90000], me_first=False, mates=[mate("Ann", 5, hp=0), mate("Bob", 6)])
        b = S._Battle.from_state(st, sure(), [foe], S.Opts(), random.Random(2))
        self.assertEqual([b._wiz(k).hp for k in b.wizards()], [3000, 0, 3000])
        self.assertEqual(b.up(), [0, 2])
        for _ in range(6):
            b.foe_round()
        self.assertEqual(b.side[1].hp, 0)                           # (Ann soaks no hit)
        self.assertEqual(b.hp + b.side[2].hp, 6000 - 6 * 400)

    def test_team_junk_never_raises(self):
        for st in (S.State([lord()], mates=[mate("", None, "x", ["junk", None])]), S.State(None, mates=[]),
                   S.State([lord()], fhp=[0], mates=[mate("A", 5)])):
            tp = S.plan_team(st, sure(), [biter()], budget_ms=30)
            self.assertIsInstance(tp["orders"], list)
            self.assertIsInstance(S.team_lines(tp, [biter()]), list)
            p = S.plan_round(st, sure(), [biter()], budget_ms=30)
            self.assertIsInstance(p["plays"], list)
        self.assertEqual(S.plan_team(S.State([lord()]), sure(), [])["why"], ["no enemies"])


class BestDecks(unittest.TestCase):
    def test_groups_by_zone(self):
        recs = [enemy_record({"spell": "Bite"}, zone="Z1"), enemy_record({"spell": "Bite"}, zone="Z1"),
                enemy_record({"spell": "Bite"}, zone="Z2"), enemy_record({"spell": "Bite"}, zone=None)]
        book = S.FoeBook(battles=recs)
        self.assertEqual(dict(book.groups["Z1"]), {("Imp", "Shaman"): 2})
        self.assertEqual(sorted(book.groups), ["Z1", "Z2"])

    def test_the_stronger_deck_first(self):
        strong = S.deck_cards({"cards": [hit("Storm Lord", 3, 1500, count=20)]})
        weak = S.deck_cards({"cards": [hit("Thunder Snake", 2, 100, count=20)]})
        groups = {("Rat", "Rat"): 5, ("Ogre",): 1}
        made = {"Rat": 900, "Ogre": 4000}
        res = S.best_decks([("a1", "Weak", weak, S.Opts()), ("b2", "Strong", strong, S.Opts())], groups,
                           lambda names: [biter(nm, made[nm]) for nm in names], S.Me("storm", 3000), n=30, seed=1)
        self.assertEqual([d["name"] for d in res["decks"]], ["Strong", "Weak"])
        self.assertEqual(res["groups"], [(("Rat", "Rat"), 5), (("Ogre",), 1)])
        best = res["decks"][0]
        self.assertGreater(best["won"], res["decks"][1]["won"] - 1e-9)
        self.assertEqual((best["groups"], best["battles"]), (2, 6))
        lines = S.deckfor_lines(res, "Z1")
        self.assertTrue(lines[0].startswith("deckfor|b2|Strong|"))
        self.assertIn("group|5|Rat,Rat", lines)
        self.assertIn("zone|Z1", lines)

    def test_same_cards_score_the_same(self):
        # (one deck in two Equipment Sets, its cards listed apart: the same numbers, seed or none - common random
        # numbers, so DeckForZone's 5-point gap is never the dice's)
        a = S.deck_cards({"cards": [hit("Storm Lord", 3, 700, count=10), hit("Thunder Snake", 2, 300, count=10)]})
        b = S.deck_cards({"cards": [hit("Thunder Snake", 2, 300, count=10), hit("Storm Lord", 3, 700, count=10)]})
        groups = {("Ghoul", "Ghoul", "Wraith"): 12, ("Ghoul",): 5}
        made = {"Ghoul": 1200, "Wraith": 2000}
        def run(decks, seed=None):
            res = S.best_decks(decks, groups, lambda names: [biter(nm, made[nm], 500, 700) for nm in names],
                               S.Me("storm", 3000), n=30, seed=seed)
            return [(d["won"], d["lost"], d["rounds"], d["hp_left"]) for d in res["decks"]]
        for seed in (None, 5):
            x, y = run([("a", "A", a, S.Opts()), ("b", "B", b, S.Opts())], seed)
            self.assertEqual(x, y)
            self.assertLess(x[0], 1.0)                              # (close fights: the dice matter)
        # (asked again - the helper every 10 minutes: the same answer, not a new roll)
        self.assertEqual(run([("a", "A", a, S.Opts())]), run([("b", "B", b, S.Opts())]))

    def test_pause_before_each_simulation_not_counted(self):
        # (vision.py's gate_wait: the gated reads go first - its time never cuts a deck off the budget)
        import time
        cards = S.deck_cards({"cards": [hit("Storm Lord", 3, 1500, count=20)]})
        groups = {("Rat",): 2, ("Ogre",): 1}
        made = {"Rat": 900, "Ogre": 4000}
        calls = []

        def pause():
            calls.append(1)
            time.sleep(0.03)
        decks = [("a", "A", cards, S.Opts()), ("b", "B", cards, S.Opts())]
        res = S.best_decks(decks, groups, lambda names: [biter(nm, made[nm]) for nm in names], S.Me("storm", 3000),
                           n=5, seed=1, budget_ms=60, pause=pause)
        self.assertEqual(len(calls), 4)                             # (2 decks x 2 groups)
        self.assertEqual([d["key"] for d in res["decks"]], ["a", "b"])
        self.assertFalse(any("not simulated in the time given" in w for w in res["why"]), res["why"])

    def test_no_groups_and_junk(self):
        res = S.best_decks([("a", "A", [], S.Opts())], {}, lambda names: [], S.Me())
        self.assertEqual(res["decks"], [])
        self.assertTrue(S.deckfor_lines(res)[0].startswith("none|no enemy group known"))
        res = S.best_decks(None, [["Rat"]], lambda names: 1 / 0, S.Me())
        self.assertTrue(any("couldn't all be simulated" in w for w in res["why"]))
        self.assertEqual(S.deckfor_lines(None), ["none|no deck to simulate"])

    def test_verdict_says_what_was_learned(self):
        cards = S.deck_cards({"cards": [hit(count=10)]})
        f, g = biter("Shaman", 2000), biter("Rat", 500)
        f.acts = {"shield": {"p": 0.2, "v": 50}}
        r = S.simulate(cards, S.Me("storm", 3000), [f, g], n=20, seed=1)
        v = S.verdict(r, cards, S.Me("storm", 3000), [f, g])
        self.assertTrue(any(n.startswith("learned from the battles recorded") and "Shaman shield" in n
                            for n in v["notes"]), v["notes"])
        self.assertTrue(any(n.startswith("not modelled:") and "Rat" in n and "Shaman" not in n for n in v["notes"]))


# ============================================================================ the bot's whole chain: enchants, the defend
# check, Tower Shield / absorb and the filler, Reshuffle and the spent pile, the support's chain
def snake():
    return S.Card("Thunder Snake", "damage", "storm", 2, heads={"storm": 150}, tid=2)


def ench(name="Epic", value=300, tc=False):
    return S.Card(name, "enchant", "", 0, value=value, tc=tc)


def tower():
    return S.Card("Tower Shield", "ward", "ice", 0, value=50, tid=60)


def absorb(pips=0, value=200):
    return S.Card("Spirit Armor", "absorb", "", pips, value=value, tid=61)


def resh():
    return S.Card("Reshuffle", "manipulation", "", 0, tid=62)


def satyr():
    return S.Card("Satyr", "heal", "life", 3, value=900, tid=6)


def stormblade():
    return S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3)


def smasher(hp=9000, dmg=1000):
    return S.Foe("Smasher", hp, spells=[("Smash", 1.0, {"pips": 0, "min": dmg, "max": dmg, "accuracy": 100})])


def battle(hand, pile=(), foes=None, opts=None, seed=1, **kw):
    """a battle from a State (sure(): storm, 3000 health, never a miss; an enemy with no resist learned: x0.85)"""
    st = S.State(list(hand), list(pile), **dict({"fhp": None, "me_first": True}, **kw))
    return S._Battle.from_state(st, sure(), foes or [S.Foe("A", 9000)], opts or S.Opts(), random.Random(seed))


def names(cards):
    return [c.name for c in cards]


class Enchants(unittest.TestCase):
    """Part A: the bot's damage enchants on every hit its chain casts (Autofarmer.ahk UseHit, KillCalc.ahk HeadsDamage /
    FindLethalHit)"""

    def test_cards_read(self):
        e = S.card_of({"name": "Epic", "kind": "enchant", "value": 300})
        self.assertEqual((e.kind, e.value, e.hit, e.bot_ench), ("enchant", 300.0, False, "epic"))
        c = S.card_of({"template_id": 5}, {5: {"kind": "enchant", "value": "+275", "name": "Colossal"}})
        self.assertEqual((c.value, c.bot_ench), (275, "colossal"))
        self.assertEqual(S.card_of({"name": "Primordial", "kind": "enchant", "value": 350}).bot_ench, "")
        self.assertEqual(S.enchant_add(S.Card("Strong", "enchant")), 100)        # (no number: the bot's default)
        self.assertEqual(S.enchant_add(S.Card("Primordial", "enchant", value=350)), 0)
        self.assertEqual(S.enchant_add(None), 0)
        d = {"name": "Storm Lord", "kind": "damage", "school": "storm", "pips": 7, "value": 1000,
             "heads_text": "storm:1000", "ench_effect": "kModifyCardDamage +175"}
        h = S.card_of(d)
        self.assertEqual((h.ench, h.heads), (175.0, {"storm": 1000.0}))
        self.assertEqual(S.card_of(dict(d, kind="blade")).ench, 0.0)          # (only a hit's)
        self.assertEqual(S.card_of(dict(d, ench_effect="kModifyCardAccuracy +10")).ench, 0.0)
        self.assertEqual(lord().ench, 0.0)

    def test_least_with_an_add(self):
        b = S._Battle([], S.Me("storm"), [S.Foe("A", 900)], S.Opts(), random.Random(1))
        self.assertEqual(b.least(lord(), 0), 850)                              # (unchanged)
        self.assertAlmostEqual(b.least(lord(), 0, add=300), 1105.0)
        c = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000}, ench=300)
        self.assertAlmostEqual(b.least(c, 0), 1105.0)                          # (the enchantment on it counted)
        b = S._Battle([], S.Me("storm"), [S.Foe("A", 900, resist={"fire": 0.5, "ice": 0.85, "storm": 0.85})], S.Opts(),
                      random.Random(1))
        hydra = S.Card("Hydra", "damage", "fire", 8, heads={"fire": 230, "ice": 230, "storm": 230})
        self.assertAlmostEqual(b.least(hydra, 0, add=300), 230 * 0.5 + 2 * 230 * 0.85 + 300 * 0.5)   # (the least head)
        self.assertEqual(b._add_head(hydra, 0), "fire")
        b = S._Battle([], S.Me("fire"), [S.Foe("A", 900)], S.Opts(), random.Random(1))
        b.pips, b.power = 5, 2
        meteor = S.Card("Meteor", "aoe", "fire", 0, x=True, heads={"fire": 100})
        self.assertAlmostEqual(b.least(meteor, 0, add=300), (7 * 100 + 300) * 0.85)   # (once, not a pip)

    def test_pass_one_kill_saves_the_enchant(self):
        b = battle([lord(), ench()], pips=7, fhp=[700], foes=[S.Foe("A", 900)])
        self.assertTrue(b.my_round(fresh=False))                               # (850 >= 700 x 1.15)
        self.assertEqual(names(b.hand), ["Epic"])
        self.assertEqual(b.fhp, [0])
        self.assertNotIn("Epic", b.casts)

    def test_pass_two_kill_uses_it(self):
        b = battle([lord(), ench()], pips=7, fhp=[900], foes=[S.Foe("A", 900)])
        self.assertTrue(b.my_round(fresh=False))                               # (850 < 1035 <= 1105)
        self.assertEqual((b.hand, b.fhp, b.pips, b.boosts_run), ([], [0], 0, 0))
        self.assertEqual(b.casts, {"Storm Lord": 1, "Epic": 1})

    def test_a_hit_takes_the_best_enchant(self):
        b = battle([lord(), ench("Giant", 125), ench()], pips=7, fhp=[5000], foes=[S.Foe("A", 5000)])
        self.assertTrue(b.my_round(fresh=False))
        self.assertEqual(names(b.hand), ["Giant"])
        self.assertTrue(3785 <= b.fhp[0] <= 3895, b.fhp)                     # ((1000..1130 + 300) x 0.85)
        self.assertEqual(b.casts["Epic"], 1)
        # (equal adds: EnchantList's order - Colossal before a Giant given 275)
        b = battle([ench("Giant", 275), ench("Colossal", 275)], pips=7)
        self.assertEqual(b._best_ench().name, "Colossal")

    def test_never_on_an_item_or_an_enchanted_card(self):
        wand = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000}, item=True)
        b = battle([wand, ench()], pips=7, fhp=[5000], foes=[S.Foe("A", 5000)])
        self.assertTrue(b.my_round(fresh=False))
        self.assertEqual(names(b.hand), ["Epic"])
        self.assertTrue(4040 <= b.fhp[0] <= 4150, b.fhp)                     # (plain: 850..960)
        done = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000}, ench=300)
        b = battle([done, ench()], pips=7, fhp=[900], foes=[S.Foe("A", 900)])
        self.assertTrue(b.my_round(fresh=False))                               # (pass 1: its own 300 counted)
        self.assertEqual((names(b.hand), b.fhp), (["Epic"], [0]))

    def test_no_enchant_on_a_hit_not_paid_for(self):
        b = battle([lord(), ench()], pips=6, fhp=[5000])
        self.assertFalse(b.my_round(fresh=False))
        self.assertEqual(names(b.hand), ["Storm Lord", "Epic"])
        # (cast itself: the hit is paid for before the enchant goes on - Autofarmer.ahk UseHit)
        b = battle([lord(), ench()], pips=6, fhp=[5000])
        self.assertFalse(b.force(b.hand[0]))
        self.assertEqual(names(b.hand), ["Epic"])
        self.assertNotIn("Epic", b.casts)

    def test_a_fizzle_loses_both(self):
        st = S.State([lord(), ench()], [], pips=7, fhp=[5000], me_first=True)
        b = S._Battle.from_state(st, S.Me("storm", 3000, accuracy=-100), [S.Foe("A", 9000)], S.Opts(),
                                 random.Random(1))
        self.assertFalse(b.my_round(fresh=False))
        self.assertEqual((b.hand, b.pips, b.fhp), ([], 7, [5000]))
        self.assertEqual(b.casts, {"Storm Lord": 1, "Epic": 1})
        self.assertEqual(sorted(names(b.spent)), ["Epic", "Storm Lord"])

    def test_enchant_draws_no_random_number(self):
        b1, b2 = [S._Battle([], S.Me("storm"), [S.Foe("A", 9000)], S.Opts(), random.Random(7)) for _ in range(2)]
        b1.hit(lord(), 1)
        b2.hit(lord(), 1, add=300)
        self.assertEqual(b1.rng.getstate(), b2.rng.getstate())
        self.assertLessEqual(abs((9000 - b2.fhp[0]) - (9000 - b1.fhp[0]) - 255), 1)     # (300 x 0.85)
        b = battle([lord(), ench()], pips=7, fhp=[5000])
        s0 = b.rng.getstate()
        b.choose()
        self.assertEqual(b.rng.getstate(), s0)

    def test_hit_puts_the_add_on_the_least_head_once(self):
        def gap(me, foe, card, per):
            b1, b2 = [S._Battle([], me, [foe], S.Opts(), random.Random(7)) for _ in range(2)]
            b1.hit(card, per)
            b2.hit(card, per, add=300)
            self.assertEqual(b1.rng.getstate(), b2.rng.getstate())
            return b2, b1.fhp[0] - b2.fhp[0]
        # (Hydra: its least head here is ice, not its first - the add goes there, x0.5)
        hydra = S.Card("Hydra", "damage", "fire", 8, heads={"fire": 230, "ice": 230, "storm": 230})
        b, d = gap(S.Me("storm"), S.Foe("A", 90000, resist={"ice": 0.5, "fire": 0.85, "storm": 0.85}), hydra, 1)
        self.assertEqual(b._add_head(hydra, 0), "ice")
        self.assertLessEqual(abs(d - 150), 1)                                  # (the first head's would be 255)
        # (an X-pip hit: the add once, not a pip - 300 x 0.85, not 7 x 300 x 0.85)
        meteor = S.Card("Meteor", "aoe", "fire", 0, x=True, heads={"fire": 100})
        _b, d = gap(S.Me("fire"), S.Foe("A", 90000), meteor, 7)
        self.assertLessEqual(abs(d - 255), 1)

    def test_value_counts_the_enchant(self):
        big = S.Card("Big", "damage", "storm", 5, heads={"storm": 1200})
        wave = S.Card("Wave", "aoe", "storm", 4, heads={"storm": 500})
        foes = [S.Foe("A", 5000), S.Foe("B", 5000)]
        b = battle([big, wave, ench()], foes=foes, pips=7)
        self.assertEqual(b.choose().name, "Wave")                              # ((500 + 300) x 0.85 x 2 > 1500 x 0.85)
        b = battle([big, wave], foes=foes, pips=7)
        self.assertEqual(b.choose().name, "Big")                               # (1020 > 850)

    def test_forced_plain_kill_keeps_the_enchant(self):
        # (force: a hit that kills without the enchant goes plain - the kill check's pass 1; a fizzle shows the Epic
        # stayed in hand)
        st = S.State([lord(), ench()], [], pips=7, fhp=[700], me_first=True)
        b = S._Battle.from_state(st, S.Me("storm", 3000, accuracy=-100), [S.Foe("A", 900)], S.Opts(), random.Random(1))
        self.assertIs(b.force(b.hand[0]), False)
        self.assertEqual(names(b.hand), ["Epic"])
        self.assertNotIn("Epic", b.casts)

    def test_discard_keeps_the_bots_enchants(self):
        b = S._Battle([], S.Me("storm"), [S.Foe("A", 900)], S.Opts(discardunused=1, discardmax=4), random.Random(1))
        b.hand = [ench(), S.Card("Freeze", "stun"), S.Card("Poison", "dot"), S.Card("Primordial", "enchant", value=350),
                  S.Card("Keen Eyes", "enchantother")]
        b.discard()
        # (every damage enchant kept - CardLearn.ahk DiscardUnused skips type enchant whatever its name: a Primordial
        # the bot never finds stays in hand as a dead card)
        self.assertEqual(names(b.hand), ["Epic", "Primordial"])
        self.assertEqual(sorted(names(b.spent)), ["Freeze", "Keen Eyes", "Poison"])

    def test_planner_carries_the_enchant(self):
        st = S.State([lord(), ench()], [snake()] * 10, pips=7, fhp=[900], me_first=True)
        p = S.plan_round(st, sure(), [S.Foe("A", 900)], n=20, seed=1, budget_ms=5000)
        best = p["plays"][0]
        self.assertEqual((best["name"], best["won"], best["rounds"]), ("Storm Lord", 1.0, 1))
        self.assertNotIn("Epic", [x["name"] for x in p["plays"]])
        self.assertTrue(any("goes on a hit" in w for w in p["why"]), p["why"])
        # (an enchant the bot never finds - a Primordial - never goes on a hit: not simulated, as before the change)
        st = S.State([lord(), S.Card("Primordial", "enchant", value=350)], [lord()] * 5, pips=7, fhp=[5000],
                     me_first=True)
        p = S.plan_round(st, sure(), [S.Foe("A", 5000)], n=10, seed=1, budget_ms=5000)
        self.assertIn("1 card in hand not tried (not simulated)", p["why"])

    def test_a_mate_uses_its_enchant(self):
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True,
                     mates=[mate("Ann", 4, "blader", [snake(), ench()], pips=2)])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b.side_round(0, {})
        self.assertEqual(b.side[1].hand, [])
        self.assertEqual(b.casts, {"Thunder Snake": 1, "Epic": 1})
        self.assertTrue(8601 <= b.fhp[0] <= 8618, b.fhp)                     # ((150..169.5 + 300) x 0.85)

    def test_a_held_enchant_keeps_the_battle_going(self):
        # (the bot flees only with no card in hand: an enchant with no hit to go on keeps it passing - before, the Epic
        # was discarded and the battle a timeout)
        st = S.State([ench()], [], pips=0, fhp=[9000], me_first=True)
        b = S._Battle.from_state(st, sure(), [S.Foe("Rat", 9000)], S.Opts(), random.Random(1))
        self.assertEqual(b.run_from(False, None, horizon=5), "cut")
        self.assertEqual(names(b.hand), ["Epic"])


def _has_enemies():
    try:
        __import__("numpy")
        __import__("enemies")
        return True
    except Exception:  # noqa: BLE001
        return False


class Defend(unittest.TestCase):
    """Part B and C: the defend check (EnemySpells.ahk EnemyDanger / EnemyDefend), Tower Shield and absorbs as cast, the
    filler"""

    def test_opts_reads_the_chain_keys(self):
        def keys(o):
            return (o.usetower, o.useabsorb, o.defendat, o.usereshuffle)
        self.assertEqual(keys(S.Opts()), (True, True, 30.0, True))
        self.assertEqual(keys(S.Opts.of({"usetower": "0", "defendat": "50", "useabsorb": "0", "usereshuffle": "0"})),
                         (False, False, 50.0, False))
        self.assertEqual(S.Opts.of({"defendat": "x"}).defendat, 30.0)
        self.assertEqual(S.Opts.of({"defendat": "nan"}).defendat, 30.0)
        self.assertEqual(S.Opts(1, 0, 40, 15, 1, 1, 1, 1, 1, 3, True).boss, True)    # (positional calls as before)
        # (v1.7.0: the keys the bot reads besides - SettingsSent.test_opts_new_keys has the rest)
        self.assertEqual((S.Opts().reboost, S.Opts().drawenchant, S.Opts().enemyspells), (False, False, True))
        self.assertEqual(S.Opts.of({"reboost": "1", "enemyspells": "0"}).reboost, True)
        self.assertEqual(S.Opts(1, 0, 40, 15, 1, 1, 1, 1, 1, 3, True).reboost, False)

    def test_tower_shield_halves_the_next_hit(self):
        b = battle([tower()], foes=[smasher()], pips=0)
        self.assertIs(b.force(b.hand[0]), True)
        self.assertEqual(b.shields, [(50.0, None)])
        b.foe_round()
        self.assertEqual((b.hp, b.shields), (2500, []))
        # (the enemies first: a shield cast after their hit waits for the next one)
        b = battle([tower()], foes=[smasher()], pips=0, me_first=False)
        b.foe_round()
        self.assertEqual(b.hp, 2000)
        b.force(b.hand[0])
        self.assertEqual(b.shields, [(50.0, None)])
        self.assertEqual((tower().acc, S.Card("Fire Shield", "ward", "fire", 0, value=80).tower), (100, False))
        self.assertTrue(S.card_of({"display": "Escudo", "name": "Tower Shield", "kind": "ward"}).tower)

    def test_absorb_card_soaks(self):
        b = battle([absorb(value=200)], foes=[smasher(dmg=500)])
        b.force(b.hand[0])
        b.foe_round()
        self.assertEqual((b.hp, b.absorb), (2700, 0))
        b = battle([S.Card("Spirit Armor", "absorb", "", 0, value="100/pip")], pips=3)
        b.force(b.hand[0])
        self.assertEqual((b.absorb, b.pips), (300, 0))                         # (an X-pip absorb's N a pip)

    def test_defend_tower_when_lethal(self):
        b = battle([snake(), tower()], foes=[smasher()], pips=2, hp=900, fhp=[9000])
        b._snap_danger()
        self.assertAlmostEqual(b._danger(), 1.0)
        self.assertEqual(b.choose().name, "Tower Shield")
        for o in (S.Opts(defendat=0), S.Opts(usetower=0)):
            b = battle([snake(), tower()], foes=[smasher()], pips=2, hp=900, fhp=[9000], opts=o)
            b._snap_danger()
            self.assertEqual(b.choose().name, "Thunder Snake")
        b = battle([snake(), tower()], foes=[smasher()], pips=2, hp=1100, fhp=[9000])
        b._snap_danger()
        self.assertEqual(b._danger(), 0.0)                                     # (the fast path: 1000 < 1100)
        self.assertEqual(b.choose().name, "Thunder Snake")
        b = battle([snake(), tower()], foes=[smasher()], pips=2, hp=900, fhp=[9000])
        self.assertEqual((b._danger(), b.choose().name), (0.0, "Thunder Snake"))    # (no snapshot: no defend)

    def test_defend_heals_first_under_90_percent(self):
        for pips, hp, o, want in ((3, 2400, S.Opts(), "Satyr"), (3, 2850, S.Opts(), "Tower Shield"),
                                  (2, 2400, S.Opts(), "Tower Shield"), (3, 2400, S.Opts(useheal=0), "Tower Shield")):
            b = battle([snake(), tower(), satyr()], foes=[smasher(dmg=3000)], pips=pips, hp=hp, fhp=[9000], opts=o)
            b._snap_danger()
            self.assertEqual(b.choose().name, want, (pips, hp))
        # (the 90 % is the round start's health - the planning phase's -, not what's left after the enemies went first)
        b = battle([tower(), satyr()], foes=[smasher(dmg=3000)], pips=3, hp=2850, fhp=[9000])
        b._snap_danger()
        b.hp = 2550
        self.assertEqual(b.choose().name, "Tower Shield")

    def test_defend_absorb_any_cost_filler_only_free(self):
        def pick(hand, dmg, pips=2):
            b = battle(hand, foes=[smasher(dmg=dmg)], pips=pips, hp=900, fhp=[9000])
            b._snap_danger()
            c = b.choose()
            return c.name if c is not None else None
        self.assertEqual(pick([snake(), absorb(pips=2, value=500)], 1000), "Spirit Armor")    # (the defend's)
        self.assertEqual(pick([snake(), absorb(pips=2, value=500)], 100), "Thunder Snake")    # (no danger)
        self.assertIsNone(pick([lord(), absorb(pips=2)], 100))                                # (the filler's: not free)
        self.assertEqual(pick([lord(), absorb(pips=0)], 100), "Spirit Armor")                 # (free: the filler's)

    def test_kill_check_before_defend(self):
        b = battle([lord(), tower()], foes=[smasher(hp=700)], pips=7, hp=900, fhp=[700])
        b._snap_danger()
        self.assertEqual(b.choose().name, "Storm Lord")

    def test_kill_check_before_the_heal(self):
        b = battle([lord(), satyr()], foes=[S.Foe("A", 700)], pips=7, hp=600, fhp=[700])
        self.assertEqual(b.choose().name, "Storm Lord")                        # (before: the Satyr)

    def test_danger_draws_no_random_number(self):
        b = battle([snake(), tower()], foes=[smasher()], pips=2, hp=900, fhp=[9000])
        b._snap_danger()
        s0 = b.rng.getstate()
        b._danger()
        b.choose()
        self.assertEqual(b.rng.getstate(), s0)
        cards = S.deck_cards({"cards": [hit(count=20)]})
        self.assertEqual(S.simulate(cards, S.Me("storm", 3000), [biter()], S.Opts(), n=80, seed=7),
                         S.simulate(cards, S.Me("storm", 3000), [biter()], S.Opts(defendat=0), n=80, seed=7))

    @unittest.skipUnless(_has_enemies(), "numpy / enemies.py not importable")
    def test_danger_matches_enemies_predict(self):
        import numpy as np
        import enemies

        class W:
            SP = {"Bite": {"pips": 2, "min": 300, "max": 400, "accuracy": 85, "type": "Damage"},
                  "Big": {"pips": 5, "min": 800, "max": 950, "accuracy": 80, "type": "Damage"},
                  "Wave": {"pips": 4, "min": 400, "max": 500, "accuracy": 85, "type": "AoE", "aoe": True},
                  "Hex": {"pips": 1, "type": "Curse"},
                  "Storm": {"xpips": True, "perpip": [90, 110], "accuracy": 75, "type": "Damage"}}

            def creature(self, n):
                return {"spells": list(self.SP)}

            def spell(self, s):
                return self.SP.get(s)

            def brief(self, s):
                return ""
        for k in (3, 5, 7):
            for team in (1, 2):
                for health in (500, 900, 1500, 2500):
                    eb = enemies.Battle(W(), enemies.NoCasts(), ["Ogre", "Imp"], team)
                    for e in eb.enemies:
                        e.pips = np.zeros(enemies.MAX_PIPS + 1)
                        e.pips[k] = 1.0
                    _, lethal = eb.predict(health)
                    foes = [S.Foe(n, 5000, spells=S.wiki_spells(W(), None, n)) for n in ("Ogre", "Imp")]
                    b = S._Battle([], S.Me("storm", 3000, team=team), foes, S.Opts(), random.Random(1))
                    b.fpips = [k - 1, k - 1]
                    b.hp = health
                    b._snap_danger()
                    self.assertLess(abs(b._danger() - lethal), 0.03, (k, team, health, b._danger(), lethal))

    def test_lethal_exact_at_the_edge(self):
        # (the grid's bin at hp holds hp itself: counted half - before, damage half a bin short of hp counted as a kill)
        self.assertLess(abs(S._lethal((((1.0, 600.0, 700.0),),), 650) - 0.5), 0.005)
        self.assertLess(abs(S._lethal((((2 / 3.0, 295.0, 335.0),),), 318) - 0.2833), 0.005)
        self.assertLess(abs(S._lethal((((0.5, 400.0, 500.0),), ((0.5, 400.0, 500.0),)), 900) - 0.125), 0.005)
        self.assertEqual(S._lethal((((1.0, 1000.0, 1000.0),),), 1000), 1.0)    # (a sure hit of hp: a kill)
        self.assertEqual(S._lethal((((1.0, 1004.0, 1004.0),),), 1000), 1.0)
        self.assertEqual(S._lethal((((1.0, 995.0, 995.0),),), 1000), 0.0)
        # (the defend check's flip: a Bite 295-335 with a pass beside it, 5 pips; enemies.py's predict gives 0.282 at
        # 318 health - under defendat 30: the bot casts the Snake; at 300 it's 0.58: the Tower Shield)
        sp = {"Bite": {"pips": 2, "min": 295, "max": 335, "accuracy": 100, "type": "Damage"}}

        class W:
            def creature(self, n):
                return {"spells": list(sp)}

            def spell(self, s):
                return sp.get(s)

            def brief(self, s):
                return ""
        foe = S.Foe("Ogre", 5000, spells=S.wiki_spells(W(), None, "Ogre"))
        for hp, want in ((318, "Thunder Snake"), (300, "Tower Shield")):
            b = battle([snake(), tower()], [snake()] * 5, foes=[foe], pips=2, hp=hp, fhp=[5000])
            b.fpips = [4]
            b._snap_danger()
            self.assertEqual(b.choose().name, want, (hp, b._danger()))

    def test_danger_ignores_foes_the_wiki_hasnt(self):
        for f in (S.Foe("Ghoul", 9000, hits=[2000] * 5, hit_p=1.0), S.Foe("Rat", 9000)):
            b = battle([snake(), tower()], foes=[f], pips=2, hp=900, fhp=[9000])
            b._snap_danger()
            self.assertEqual((b._danger(), b.choose().name), (0.0, "Thunder Snake"))
        self.assertEqual(S._lethal((), 900), 0.0)
        self.assertEqual(S._lethal("junk", 900), 0.0)                          # (never raises)

    def test_danger_at_the_round_start(self):
        b = battle([snake(), tower()], [snake()] * 10, foes=[smasher(dmg=900)], pips=2, hp=1500, fhp=[9000],
                   me_first=False)
        b._snap_danger()
        b.foe_round()
        self.assertEqual(b.hp, 600)
        self.assertEqual(b.choose().name, "Thunder Snake")                     # (the danger at 1500: 0)
        b.new_round()
        b._snap_danger()
        self.assertEqual(b.choose().name, "Tower Shield")                      # (at 600: 1)

    def test_planner_round_now_doesnt_defend(self):
        st = S.State([snake(), tower()], [snake()] * 10, pips=2, hp=1000, fhp=[9000], me_first=True)
        foes = [smasher(dmg=900)]
        b = S._Battle.from_state(st, sure(), foes, S.Opts(), random.Random(2))
        b.run_from(False, None, horizon=1)
        self.assertEqual(b.casts, {"Thunder Snake": 1})                        # (the bot asked the planner: no defend)
        b = S._Battle.from_state(st, sure(), foes, S.Opts(), random.Random(2))
        b.run_from(False, None, horizon=2)
        self.assertEqual(b.casts.get("Tower Shield"), 1)                       # (round 2 at 100 health)
        # (a sure kill this round still gets no defend of mine: at 900 against 1000 the danger is 1)
        st2 = S.State([snake(), tower()], [snake()] * 10, pips=2, hp=900, fhp=[9000], me_first=True)
        b = S._Battle.from_state(st2, sure(), [smasher(dmg=1000)], S.Opts(), random.Random(2))
        self.assertEqual(b.run_from(False, None, horizon=1), "lost")
        self.assertEqual(b.casts, {"Thunder Snake": 1})
        p = S.plan_round(st, sure(), foes, n=10, seed=1, budget_ms=5000)
        self.assertTrue(any(x["name"] == "Tower Shield" and x["kind"] == "ward" for x in p["plays"]), p["plays"])
        p = S.plan_round(st, sure(), foes, S.Opts(usetower=0), n=10, seed=1, budget_ms=5000)
        self.assertFalse(any(x["name"] == "Tower Shield" for x in p["plays"]))
        self.assertTrue(any("switched off" in w for w in p["why"]), p["why"])

    def test_discard_keeps_tower_and_absorb(self):
        hand = [tower(), S.Card("Fire Shield", "ward", "fire", 0, value=80), absorb()]
        b = battle([], opts=S.Opts(discardunused=1, discardmax=3))
        b.hand = list(hand)
        b.discard()
        self.assertEqual(names(b.hand), ["Tower Shield", "Spirit Armor"])
        b = battle([], opts=S.Opts(usetower=0, discardunused=1, discardmax=3))
        b.hand = list(hand)
        b.discard()
        self.assertEqual(b.hand, [])

    def test_filler_tower_instead_of_a_pass(self):
        b = battle([lord(), tower(), tower()], pips=0, fhp=[5000])
        b.my_round(fresh=False)
        b.my_round(fresh=False)
        self.assertEqual(b.shields, [(50.0, None), (50.0, None)])              # (stacked: the bot stacks them)
        self.assertEqual(names(b.hand), ["Storm Lord"])
        p = S.plan_round(S.State([lord(), tower()], [snake()] * 10, pips=0, fhp=[5000], me_first=True), sure(),
                         [S.Foe("A", 5000)], n=10, seed=1, budget_ms=5000)
        self.assertEqual(p["chain"]["name"], "Tower Shield")


class TeamChain(unittest.TestCase):
    """Part E: the support's chain in the bot's order - PartyShield (Party.ahk), the defend check for every role"""

    def test_healer_party_shield(self):
        def side(bob_hp):
            st = S.State([lord()], [], pips=0, hp=3000, fhp=[9000], me_first=True,
                         mates=[mate("Ann", 5, "healer", [tower(), tower()]), mate("Bob", 6, hp=bob_hp)])
            return S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b = side(900)
        b.side_round(0, {})
        self.assertEqual(b.side[2].shields, [(50.0, None)])                    # (Bob: 30 % < 2 x 40 %)
        self.assertEqual((b.shields, b.side[1].shields, b.side[1].pshield_used), ([], [], True))
        b.side_round(1, {})
        self.assertEqual(b.side[1].shields, [(50.0, None)])                    # (PartyShield went: the filler, on Ann)
        self.assertEqual(b.side[2].shields, [(50.0, None)])
        b = side(3000)
        b.side_round(0, {})
        self.assertEqual(b.shields, [(50.0, None)])                            # (nobody low: on the hitter - me)

    def test_blader_party_shield_after_its_boosts(self):
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True,
                     mates=[mate("Ann", 4, "blader", [stormblade(), tower()])])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b.side_round(0, {})
        self.assertEqual((b.blades, b.shields), ([("Stormblade", {"storm": 35})], []))
        b.side_round(1, {})
        self.assertEqual(b.shields, [(50.0, None)])
        self.assertIs(b.side[1].pshield_used, True)
        # (a forced Tower Shield goes where PartyShield puts it - on the hitter)
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True,
                     mates=[mate("Ann", 4, "blader", [tower()])])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b.side_round(0, {1: (0, None)})
        self.assertEqual((b.shields, b.side[1].shields, b.side[1].pshield_used), ([(50.0, None)], [], True))

    def test_defend_for_every_role(self):
        for hp, want in ((500, "Tower Shield"), (1200, "Stormblade")):
            st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True,
                         mates=[mate("Ann", 4, "blader", [stormblade(), tower()], hp=hp)])
            b = S._Battle.from_state(st, sure(), [smasher()], S.Opts(), random.Random(1))
            b._snap_danger()
            b._swap(1)
            card = b.choose_support()
            self.assertEqual(card.name, want, hp)                              # (team 2: the hit at Ann half the time)
            if hp == 500:
                self.assertIsNone(b.shield_to)                                 # (the defend's: on Ann herself)
            b._swap(0)

    def test_party_shield_gone_already(self):
        # (State / Mate pshield_used: the bot's used19 - a support's PartyShield went since the side's hitter's last
        # hit; not given: not gone)
        hitter = S.Mate("Hit", 5, S.Me("storm", 3000), "hitter", hand=[lord()], pile=[], pips=2)

        def healer(used):
            st = S.State([stormblade(), tower()], [], pips=2, hp=3000, fhp=[9000], me_first=True, seat=4,
                         mates=[hitter], pshield_used=used)
            return S._Battle.from_state(st, S.Me("storm", 3000), [S.Foe("Boss", 9000)], S.Opts(role="healer"),
                                        random.Random(1))
        b = healer(False)
        self.assertEqual((b.choose_support().name, b.shield_to), ("Tower Shield", 1))
        b = healer(True)
        self.assertIs(b.pshield_used, True)
        self.assertEqual((b.choose_support().name, b.blade_to), ("Stormblade", 1))
        b = healer(True)
        b.force(next(c for c in b.hand if c.tower))
        self.assertEqual((b.shields, b.side[1].shields), ([(50.0, None)], []))    # (on itself)
        # (a blader mate whose PartyShield went: its chain's Tower Shield is the filler's, on itself)
        for used, mine, ann in ((False, [(50.0, None)], []), (True, [], [(50.0, None)])):
            st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True,
                         mates=[S.Mate("Ann", 4, S.Me("storm", 3000, accuracy=30), "blader", [tower()], [], 0, 0, None,
                                       pshield_used=used)])
            b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
            b.side_round(0, {})
            self.assertEqual((b.shields, b.side[1].shields), (mine, ann), used)
        self.assertEqual((S.State([], pshield_used="junk").pshield_used, S.Mate(pshield_used=[1]).pshield_used),
                         (False, False))

    def test_mates_defend_in_the_round_now(self):
        # (the round now: only my own defend check is off - the bot asked the planner after it declined; a mate's bot
        # runs its own chain, defend first. Ann at 900 against a sure 1000 AoE shields herself and lives)
        smash = S.Foe("Smasher", 9000, spells=[("Smash", 1.0, {"pips": 0, "min": 1000, "max": 1000, "accuracy": 100,
                                                                "type": "Damage", "aoe": True})])
        ann = S.Mate("Ann", 4, S.Me("fire", 3000), "blader", hand=[snake(), tower()], pile=[snake()] * 5, pips=2, hp=900)
        st = S.State([lord()], [snake()] * 10, pips=0, hp=3000, fhp=[9000], me_first=True, seat=5, mates=[ann])
        b = S._Battle.from_state(st, sure(), [smash], S.Opts(), random.Random(1))
        self.assertEqual(b.run_from(False, None, horizon=1), "cut")
        self.assertEqual((b.side[1].hp, b.shields, b.casts), (400, [], {"Tower Shield": 1}))

    def test_wiz_fields(self):
        for k in ("spent", "danger_hp", "pshield_used", "tcs", "draws", "draw_off", "boosts_used"):
            self.assertIn(k, S.WIZ_FIELDS)


class Reshuffle(unittest.TestCase):
    """Part D: Reshuffle (the filler's last) and the spent pile it puts back"""

    def test_spotted_and_never_missing(self):
        for c in (S.Card("Reshuffle", "manipulation"), S.Card("Reshuffle", "keep"),
                  S.card_of({"display": "Reshuffle", "name": "X", "kind": "manipulation"}),
                  S.card_of({"display": "Remezclar", "name": "Reshuffle", "kind": "manipulation"})):
            self.assertTrue(c.resh)
        self.assertFalse(lord().resh)
        self.assertEqual(S.Card("Reshuffle", "manipulation").acc, 100)
        for seed in range(50):
            b = S._Battle([], S.Me("storm", accuracy=0), [S.Foe("A", 900)], S.Opts(), random.Random(seed))
            b.hand = [resh()]
            self.assertIs(b.cast(b.hand[0]), True)

    def test_never_discarded(self):
        b = battle([], opts=S.Opts(discardunused=1, discardmax=3))
        b.hand = [resh()] + [S.Card("Black Mantle", "curse")] * 3
        b.discard()
        self.assertEqual((names(b.hand), len(b.spent)), (["Reshuffle"], 3))
        b = battle([], opts=S.Opts(usereshuffle=0, discardmax=4))
        b.hand = [resh()] + [S.Card("Black Mantle", "curse")] * 3
        b.discard()
        self.assertEqual(b.hand, [])
        b = battle([])
        b.hand = [S.Card("Black Mantle", "curse", tc=True)]
        b.discard()
        # (a treasure card in hand (one the bot drew) is never discarded (Draw.ahk DiscardIsTc, CardLearn.ahk))
        self.assertEqual((names(b.hand), b.spent), (["Black Mantle"], []))

    def test_filler_reshuffle(self):
        def pick(hand, opts=None, pips=2):
            b = battle(hand, pips=pips, fhp=[9000], opts=opts)
            s0 = b.rng.getstate()
            c = b.choose()
            self.assertEqual(b.rng.getstate(), s0)
            return c.name if c is not None else None
        self.assertEqual(pick([resh(), lord()]), "Reshuffle")
        self.assertEqual(pick([resh(), lord(), stormblade()]), "Stormblade")  # (boost first: it fits the Lord)
        self.assertEqual(pick([resh(), snake()]), "Thunder Snake")
        self.assertIsNone(pick([resh(), lord()], S.Opts(usereshuffle=0)))
        self.assertEqual(pick([resh(), lord(), tower()]), "Tower Shield")
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True, mates=[mate("Ann", 4, "blader", [resh()])])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b._swap(1)
        self.assertEqual(b.choose_support().name, "Reshuffle")
        b._swap(0)

    def test_spent_cards_go_back(self):
        b = S._Battle([], sure(), [S.Foe("A", 90000)], S.Opts(discardunused=1), random.Random(1))
        miss = S.Card("Thunder Snake", "damage", "storm", 2, heads={"storm": 150}, acc=-200)
        tcs = S.Card("Thunder Snake", "damage", "storm", 2, heads={"storm": 150}, tc=True)
        curse = S.Card("Curse", "curse")
        r = resh()
        snakes = [snake() for _ in range(4)]
        b.hand = snakes + [miss, tcs, curse, curse, r]
        for c in snakes + [miss, tcs]:
            b.pips = 7
            b.cast(c)
        b.discard()
        b.cast(r)
        self.assertEqual(sorted(names(b.pile)), ["Curse", "Curse"] + ["Thunder Snake"] * 5)
        self.assertEqual(b.spent, [])
        self.assertFalse(any(c.tc for c in b.pile))                            # (a treasure card's used up)
        self.assertNotIn("Reshuffle", names(b.pile))                           # (one use a copy)
        b.pile = []
        b.hand = [resh()]
        b.cast(b.hand[0])
        self.assertEqual(b.pile, [])                                           # (nothing spent: nothing back)
        # (a treasure hit in /plan's hand still goes - and is used up)
        kraken = S.Card("Kraken", "damage", "storm", 3, heads={"storm": 5000}, tc=True)
        b = battle([kraken], pips=7, fhp=[9000])
        self.assertIs(b.choose(), kraken)
        b.cast(kraken)
        self.assertEqual(b.spent, [])
        # (the cards drawn before the planner's round: spent - a Reshuffle brings them back)
        st = S.State.of_deck([resh()], [snake()] * 4 + [resh()], used=3)
        b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(), random.Random(1))
        self.assertEqual((len(b.pile), len(b.spent)), (1, 3))

    def _deck(self, resh_first=False):
        r = {"name": "Reshuffle", "display": "Reshuffle", "kind": "manipulation", "school": "", "pips": 0, "count": 1,
             "side": "main"}
        bolts = hit("Bolt", 1, 300, count=8)
        return S.deck_cards({"cards": [r, bolts] if resh_first else [bolts, r]})

    def test_fewer_timeouts(self):
        cards = self._deck()
        foe = biter("Tank", 4000, 50, 60)
        on = S.simulate(cards, sure(), [foe], S.Opts(), n=200, seed=1)
        off = S.simulate(cards, sure(), [foe], S.Opts(usereshuffle=0), n=200, seed=1)
        self.assertGreaterEqual(on["won"], 0.95)
        self.assertLess(on["timeout"], 0.05)
        self.assertEqual(on["casts"]["Reshuffle"], 1.0)
        # (off: today's simulator's numbers for this deck, computed before the change - it threw the Reshuffle away;
        # usereshuffle 0 does the same, with no random number in between)
        keys = ("won", "lost", "timeout", "rounds", "rounds_p90", "hp_left", "dmg_in", "first_kill", "casts")
        self.assertEqual(tuple(off[k] for k in keys), (0.0, 0.0, 1.0, None, None, None, 55, None, {"Bolt": 8.0}))

    def test_planner_lists_reshuffle(self):
        deck = [snake()] * 10 + [resh()]
        st = S.State.of_deck([resh(), snake()], deck, pips=0, fhp=[6000], me_first=True, used=9)
        p = S.plan_round(st, sure(), [S.Foe("A", 6000)], n=20, seed=1, budget_ms=5000, horizon=20)
        r = [x for x in p["plays"] if x["name"] == "Reshuffle"]
        self.assertEqual((len(r), r[0]["kind"], r[0]["chain"]), (1, "manipulation", True))
        line = next(ln for ln in S.plan_lines(p, [S.Foe("A", 6000)]) if ln.split("|")[10:11] == ["Reshuffle"])
        self.assertEqual(line.split("|")[11], "me")
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, mates=[mate("Ann", 4, "blader", [resh()])])
        b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(), random.Random(1))
        self.assertIn((0, None), S._team_cands(b, 1, b.alive()))

    def test_a_mates_reshuffle_refills_its_own_pile(self):
        st = S.State([lord()], [], pips=0, fhp=[9000], seat=5, me_first=True, mates=[mate("Ann", 4, "blader", [resh()])])
        b = S._Battle.from_state(st, sure(), [S.Foe("Boss", 9000)], S.Opts(), random.Random(1))
        b.side[1].spent = [snake()] * 3
        b.side_round(1, {})
        self.assertEqual((len(b.side[1].pile), b.side[1].spent), (3, []))
        self.assertEqual((b.pile, b.spent), ([], []))

    def test_reshuffle_deck_same_score_listed_apart(self):
        groups = {("Ghoul", "Wraith"): 3, ("Ghoul",): 2}
        made = {"Ghoul": 1500, "Wraith": 2500}

        def run(cards):
            res = S.best_decks([("a", "A", cards, S.Opts())], groups,
                               lambda nm: [biter(x, made[x], 50, 60) for x in nm], sure(), n=30, seed=2)
            return [(d["won"], d["lost"], d["rounds"], d["hp_left"]) for d in res["decks"]]
        self.assertEqual(run(self._deck()), run(self._deck(resh_first=True)))


class ZeroEffect(unittest.TestCase):
    """a deck with no damage enchant, Tower Shield, absorb, Reshuffle or heal, no treasure side and at most one copy of
    each blade and trap: today's numbers exactly (pins computed with the simulator before the whole chain went in -
    common random numbers, bit-identical floats); the ones with copies re-pinned for once a battle (reboost off), the
    treasure side's checked equal to its main side alone"""
    KEYS = ("won", "lost", "timeout", "rounds", "rounds_p90", "hp_left", "dmg_in", "first_kill")

    def test_mixed_deck_pinned(self):
        # (v1.7.0: 4 Stormblades and 4 Storm Traps - each slot once a battle, the used copies held: re-pinned)
        cards = S.deck_cards({"cards": [hit(count=8), hit("Thunder Snake", 2, 150, count=6),
                                        boost("blade", "Stormblade", 35, count=4),
                                        boost("trap", "Storm Trap", 30, count=4)]})
        r = S.simulate(cards, S.Me("storm", 2500, damage=40), [biter("Ogre", 3000, 150, 200),
                                                              biter("Imp", 800, 60, 80, passes=True)], n=120, seed=11)
        self.assertEqual(tuple(r[k] for k in self.KEYS), (0.2, 0.8, 0.0, 15.0, 17, 12.4, 192, 10))
        self.assertEqual(r["casts"], {"Storm Lord": 2.87, "Stormblade": 0.94, "Storm Trap": 0.93,
                                      "Thunder Snake": 0.34})

    def test_timeout_deck_pinned(self):
        # (v1.7.0: 2 Stormblades - the second held: re-pinned)
        cards = S.deck_cards({"cards": [hit("Thunder Snake", 2, 300, count=10),
                                        boost("blade", "Stormblade", 35, count=2)]})
        r = S.simulate(cards, S.Me("storm", 3000), [biter("Tank", 2600, 50, 60)], n=100, seed=3)
        self.assertEqual(tuple(r[k] for k in self.KEYS), (0.02, 0.0, 0.98, 14.0, 13, 75.3, 54, 14.0))
        self.assertEqual(r["casts"], {"Thunder Snake": 10.0, "Stormblade": 1.0})

    def test_treasure_side_pinned(self):
        # (a treasure side is never dealt - the game deals the main deck only - and with drawenchant off never drawn: a
        # deck with one plays number for number as its main side alone; v1.7.0's numbers pinned)
        stun = {"name": "Freeze", "display": "Freeze", "kind": "stun", "school": "ice", "pips": 0, "value": 0, "count": 3,
                "side": "treasure"}
        main = [hit("Thunder Snake", 2, 300, count=10), boost("blade", "Stormblade", 35, count=2)]
        tank = [biter("Tank", 2600, 50, 60)]
        r = S.simulate(S.deck_cards({"cards": main + [stun]}), S.Me("storm", 3000), tank, n=100, seed=3)
        self.assertEqual(r, S.simulate(S.deck_cards({"cards": main}), S.Me("storm", 3000), tank, n=100, seed=3))
        # (the timeout deck's)
        self.assertEqual(tuple(r[k] for k in self.KEYS), (0.02, 0.0, 0.98, 14.0, 13, 75.3, 54, 14.0))
        main = [hit(count=6), hit("Thunder Snake", 2, 150, count=10), boost("blade", "Stormblade", 35, count=4)]
        tside = [{"name": "Stun", "display": "Stun", "kind": "stun", "count": 6, "side": "treasure"},
                 {"name": "Weakness", "display": "Weakness", "kind": "weakness", "count": 4, "side": "treasure"}]
        tank = S.Foe("Tank", 3000, "fire", spells=[(None, 0.5, None), ("Bite", 1.0, {"pips": 2, "min": 200, "max": 250,
                                                                                      "accuracy": 85, "type": "Damage"})])
        r = S.simulate(S.deck_cards({"cards": main + tside}), S.Me("storm", 3000), [tank], n=120, seed=5)
        self.assertEqual(r, S.simulate(S.deck_cards({"cards": main}), S.Me("storm", 3000), [tank], n=120, seed=5))
        self.assertEqual(tuple(r[k] for k in self.KEYS),
                         (0.9916666666666667, 0.008333333333333333, 0.0, 19, 24, 38.5, 97, 19))
        self.assertEqual(r["casts"], {"Storm Lord": 4.17, "Thunder Snake": 2.61, "Stormblade": 0.95})
        # (the planner: a treasure side in the State's pile is a pile of its own, never dealt - the same plays as with
        # the treasure cards out of its pile)
        tstun = S.Card("Stun", "stun", tc=True)
        strip = lambda p: [(x["name"], x["aim"], x["n"], round(x["score"], 9)) for x in p["plays"]]  # noqa: E731
        st = S.State([lord(), snake(), tstun], [snake()] * 6 + [tstun] * 6, pips=3, fhp=[3000], me_first=True)
        p = S.plan_round(st, sure(), [tank], n=30, seed=3, budget_ms=10000)
        self.assertEqual(strip(p), [("pass", None, 30, 0.288038341), ("Thunder Snake", 0, 30, 0.282951066)])
        st = S.State([lord(), snake(), tstun], [snake()] * 6, pips=3, fhp=[3000], me_first=True)
        self.assertEqual(strip(S.plan_round(st, sure(), [tank], n=30, seed=3, budget_ms=10000)), strip(p))

    def test_plan_pinned(self):
        # (v1.7.0: a pile of 3 Stormblades - the copies held once one went: re-pinned)
        hand = [lord(), S.Card("Snake", "damage", "storm", 2, heads={"storm": 150}, tid=2), stormblade()]
        p = S.plan_round(S.State(hand, hand * 3, pips=6, fhp=[2000, 900], rnd=3), sure(),
                         [biter("A", 2400), biter("B", 1200)], n=30, seed=5, budget_ms=10000)
        self.assertEqual([(x["name"], x["aim"], x["n"], round(x["score"], 9)) for x in p["plays"]],
                         [("pass", None, 30, 0.366897899), ("Stormblade", None, 30, 0.366185891),
                          ("Snake", 0, 30, 0.364007468), ("Snake", 1, 30, 0.351465871)])

    def test_treasure_side_changes_nothing(self):
        # (common random numbers: a treasure side - listed first, so best_decks' sort and the main side's filter both
        # play - changes nothing while drawenchant is off, nor with it on when no hit would kill with +drawneed)
        main = [hit(count=6), hit("Thunder Snake", 2, 150, count=10), boost("blade", "Stormblade", 35, count=4)]
        strong = {"name": "Strong", "display": "Strong", "kind": "enchant", "value": 100, "count": 6,
                  "side": "treasure"}
        tside = [strong, dict(hit("Tempest", 6, 400, aoe=True, count=4), side="treasure")] + main
        foes = [biter("Ogre", 2500), biter("Imp", 700)]
        for seed in (1, 2, 3):
            a, b = S.deck_cards({"cards": tside}), S.deck_cards({"cards": main})
            self.assertEqual(S.simulate(a, sure(), foes, S.Opts(), n=30, seed=seed),
                             S.simulate(b, sure(), foes, S.Opts(), n=30, seed=seed))
            tank = [S.Foe("Tank", 90000)]
            self.assertEqual(S.simulate(a, sure(), tank, S.Opts(drawenchant=1), n=30, seed=seed),
                             S.simulate(b, sure(), tank, S.Opts(drawenchant=1), n=30, seed=seed))
            self.assertEqual(S.simulate(b, sure(), foes, S.Opts(drawenchant=1), n=30, seed=seed),
                             S.simulate(b, sure(), foes, S.Opts(), n=30, seed=seed))
        res = S.best_decks([("a", "A", S.deck_cards({"cards": tside}), None),
                            ("b", "B", S.deck_cards({"cards": main}), None)], [["Ogre", "Imp"]],
                           lambda names: [biter("Ogre", 2500), biter("Imp", 700)], sure(), n=40)
        rows = [{k: v for k, v in d.items() if k not in ("key", "name")} for d in res["decks"]]
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0], rows[1])
        self.assertGreater(rows[0]["won"], 0)                       # (a group it can beat: the check means something)

    def test_single_copies_pinned(self):
        # (one copy of each blade and trap, no Reshuffle, no treasure side: v1.6.0's numbers bit for bit - computed with
        # v1.6.0's simulator - with reboost off and on)
        cards = S.deck_cards({"cards": [hit(count=6), hit("Thunder Snake", 2, 150, count=6),
                                        boost("blade", "Stormblade", 35), boost("trap", "Storm Trap", 30)]})
        v160 = {"n": 120, "won": 0.7916666666666666, "lost": 0.20833333333333334, "timeout": 0.0, "rounds": 12,
                "rounds_p90": 14, "hp_left": 20.0, "dmg_in": 168, "first_kill": 12,
                "casts": {"Storm Lord": 2.88, "Storm Trap": 0.78, "Stormblade": 0.72, "Thunder Snake": 0.66}, "why": []}
        for o in (S.Opts(), S.Opts(reboost=1)):
            r = S.simulate(cards, S.Me("storm", 2500, damage=40), [biter("Ogre", 3000, 150, 200)], o, n=120, seed=11)
            self.assertEqual(r, v160)


class ChainFixes(unittest.TestCase):
    """two bugs the whole chain's review found: an enemy's wiki heal played as damage on you; learn_deck switching a
    deck's absorbs off"""

    def mender(self, **d):
        spell = dict({"pips": 0, "min": 300, "max": 400, "accuracy": 100, "type": "Healing",
                      "text": "Heals 300-400 Health"}, **d)
        return S.Foe("Shaman", 5000, spells=[("Mend", 1.0, spell)])

    def test_a_wiki_heal_heals_its_side(self):
        imp = S.Foe("Imp", 2000, spells=[(None, 1.0, None)])                  # (it only passes)
        b = battle([], foes=[self.mender(), imp], fhp=[1000, 2000], me_first=False)
        b.foe_round()
        self.assertEqual((b.hp, b.dmg_in), (3000, 0))                          # (before: 300-400 off my health)
        self.assertTrue(1300 <= b.fhp[0] <= 1400, b.fhp)                       # (the weakest of its side)
        self.assertEqual(b.fhp[1], 2000)
        # (no type, a heal's words; an AoE heal's words: each of its side)
        b = battle([], foes=[self.mender(type="", text="Heals 300 to all allies", aoe=True, max=300), imp],
                   fhp=[1000, 1500], me_first=False)
        b.foe_round()
        self.assertEqual((b.hp, b.fhp), (3000, [1300, 1800]))
        # (a wiki heal is its turn: no learned act besides)
        m = self.mender()
        m.acts, m.dmg_p = {"heal": {"p": 1.0, "v": 1000}}, 0.0
        b = battle([], foes=[m], fhp=[1000], me_first=False)
        b.foe_round()
        self.assertTrue(1300 <= b.fhp[0] <= 1400, b.fhp)
        # (the danger estimate leaves it out, as the bot's does; a damage spell still hurts)
        self.assertEqual(S._foe_outcomes(self.mender(), 7, 1), ())
        b = battle([], foes=[self.mender(type="Damage", text="Deals 300-400 Storm damage")], fhp=[1000], me_first=False)
        b.foe_round()
        self.assertTrue(2600 <= b.hp <= 2700, b.hp)
        r = S.simulate(S.deck_cards({"cards": [hit(count=20)]}), sure(), [self.mender()], n=20, seed=1)
        self.assertEqual((r["dmg_in"], r["lost"]), (0, 0.0))

    def test_learn_deck_keeps_usetower_for_absorbs(self):
        armor = {"name": "Spirit Armor", "display": "Spirit Armor", "kind": "absorb", "count": 2}
        shield = {"name": "Tower Shield", "display": "Tower Shield", "kind": "ward", "count": 2}
        for cards, off in (([hit(count=4), armor], False), ([hit(count=4), shield], False), ([hit(count=4)], True)):
            L = S.learn_deck({"gid": 1, "display": "D", "sets": [1], "cards": cards})
            self.assertEqual("usetower" in L["vals"], off, cards)
            if off:
                self.assertEqual(L["vals"]["usetower"], 0)
                self.assertIn("no Tower Shields or absorbs", L["why"])


class ChainDocs(unittest.TestCase):
    def test_verdict_notes(self):
        cards = S.deck_cards({"cards": [hit(count=10),
                                        {"name": "Tower Shield", "display": "Tower Shield", "kind": "ward", "pips": 0,
                                         "count": 2, "side": "main"},
                                        {"name": "Epic", "display": "Epic", "kind": "enchant", "value": 300, "count": 2,
                                         "side": "main"}]})
        me = S.Me("storm", 3000)
        foes = [biter("Rat", 500), S.Foe("Ghoul", 900)]
        v = S.verdict(S.simulate(cards, me, foes, n=20, seed=1), cards, me, foes)
        nm = next(n for n in v["notes"] if n.startswith("not modelled:"))
        self.assertTrue("stuns" in nm and "minions" in nm, nm)
        for w in ("Tower Shield", "enchants", "Reshuffle", "absorbs"):
            self.assertNotIn(w, nm)
        self.assertTrue(any(n.startswith("defending (defendat 30%): Ghoul not on the wiki") for n in v["notes"]),
                        v["notes"])
        # (nothing to defend with, or defendat 0: no such note)
        plain = S.deck_cards({"cards": [hit(count=10)]})
        v = S.verdict(S.simulate(plain, me, foes, n=20, seed=1), plain, me, foes)
        self.assertFalse(any(n.startswith("defending") for n in v["notes"]))
        v = S.verdict(S.simulate(cards, me, foes, n=20, seed=1), cards, me, foes, S.Opts(defendat=0))
        self.assertFalse(any(n.startswith("defending") for n in v["notes"]))
        # (v1.9.0: Sharpen and Potent modelled; the enemies' cheats aren't)
        self.assertNotIn("Sharpen", nm)
        self.assertIn("the enemies' cheats", nm)
        for w in ("reboost", "treasure cards dealt"):
            self.assertNotIn(w, nm)
        tdeck = cards + [S.Card("Strong", "enchant", value=100, tc=True)] * 3
        v = S.verdict(S.simulate(tdeck, me, foes, n=20, seed=1), tdeck, me, foes)
        self.assertIn("treasure cards (3): never dealt - the game deals only the main deck; drawenchant is off: never "
                      "drawn", v["notes"])
        v = S.verdict(S.simulate(tdeck, me, foes, n=20, seed=1), tdeck, me, foes, S.Opts(drawenchant=1))
        self.assertIn("treasure cards (3): never dealt - the game deals only the main deck; drawn for an enchant that "
                      "makes the kill (drawenchant)", v["notes"])
        self.assertFalse(any(n.startswith("treasure cards") for n in S.verdict(
            S.simulate(cards, me, foes, n=20, seed=1), cards, me, foes)["notes"]))
        # (enemyspells off: the bot never defends - no "defending (" note, this one instead)
        v = S.verdict(S.simulate(cards, me, foes, n=20, seed=1), cards, me, foes, S.Opts(enemyspells=0))
        self.assertFalse(any(n.startswith("defending (") for n in v["notes"]))
        self.assertIn("no defending: enemyspells is off (the bot doesn't foresee the enemies' hits)", v["notes"])
        v = S.verdict(S.simulate(plain, me, foes, n=20, seed=1), plain, me, foes, S.Opts(enemyspells=0))
        self.assertFalse(any(n.startswith("no defending") for n in v["notes"]))     # (nothing to defend with)
        # (best_hit: the main side only - a treasure hit or blade is never dealt)
        f = S.Foe("Rat", 5000)
        tc = [S.Card("Kraken", "damage", "storm", 3, heads={"storm": 5000}, tc=True),
              S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tc=True)]
        self.assertEqual(S.best_hit(plain + tc, me, f), S.best_hit(plain, me, f))
        self.assertEqual(S.best_hit(tc, me, f), (None, 0, []))
        # (a deck whose only hits are treasure cards: the verdict's text says none in the MAIN deck, as simulate's why
        # does - not "no hit in the deck" for a deck holding five Tempests; no hit at all: "no hit in the deck")
        ogre = [S.Foe("Ogre", 3200)]
        tdeck = [S.Card("Tempest", "aoe", "storm", 6, heads={"storm": 400}, tid=9, tc=True)] * 5 + [stormblade()] * 3
        r = S.simulate(tdeck, me, ogre, n=10, seed=1)
        self.assertIn("no hit in the main deck (its treasure cards are never dealt)", r["why"])
        self.assertTrue(S.verdict(r, tdeck, me, ogre)["text"].endswith("Ogre 3200 health: no hit in the main deck"),
                        S.verdict(r, tdeck, me, ogre)["text"])
        blades = [stormblade()] * 3 + [S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tc=True)]
        r = S.simulate(blades, me, ogre, n=10, seed=1)
        self.assertIn("no hit in the deck", r["why"])
        self.assertTrue(S.verdict(r, blades, me, ogre)["text"].endswith("Ogre 3200 health: no hit in the deck"),
                        S.verdict(r, blades, me, ogre)["text"])

    def test_sharpen_with_no_blade_note(self):
        # (v1.9.0: Sharpens and no blade in the deck - held all battle, as the bot holds them; useblades off throws
        # them away, a blade gives them a use: no note then)
        sh = {"name": "Sharpened Blade", "display": "Sharpened Blade", "kind": "sharpen", "school": "", "pips": 0,
              "value": "+10%", "count": 4, "side": "main"}
        me, foes = S.Me("storm", 3000), [S.Foe("Ogre", 3000)]
        note = ("4 Sharpen cards and no blade in the deck: held all battle, a card short in hand (the bot keeps one for "
                "a blade's second cast) - useblades off for this deck throws them away")

        def notes(deck, o=None):
            cards = S.deck_cards({"cards": deck})
            return S.verdict(S.simulate(cards, me, foes, o, n=20, seed=1), cards, me, foes, o)["notes"]
        deck = [hit("Thunder Snake", 2, 150, count=10), hit(count=6), sh]
        self.assertIn(note, notes(deck))
        self.assertFalse(any("Sharpen card" in n for n in notes(deck, S.Opts(useblades=0))))
        self.assertFalse(any("Sharpen card" in n for n in notes(deck + [boost("blade", "Stormblade", 35)])))
        # (discardunused off: nothing throws them - Settings.ahk DiscardSwitchedOff - so the note stays with useblades
        # off too, and says that instead)
        off = note.replace("useblades off for this deck throws them away", "discardunused is off: nothing throws them")
        self.assertIn(off, notes(deck, S.Opts(discardunused=0)))
        self.assertIn(off, notes(deck, S.Opts(discardunused=0, useblades=0)))
        # (a pet's or gear's blade never takes one: held all battle the same, so the note shows)
        cards = S.deck_cards({"cards": [hit(count=10), dict(sh, count=3)],
                              "item_cards": [boost("blade", "Stormblade", 35, count=2)]})
        self.assertEqual([c.name for c in cards if c.kind == "blade" and c.item], ["Stormblade", "Stormblade"])
        r = S.simulate(cards, me, foes, n=20, seed=1)
        self.assertNotIn("Sharpened Blade", r["casts"])
        self.assertIn(note.replace("4 Sharpen", "3 Sharpen"), S.verdict(r, cards, me, foes)["notes"])
        # (a Potent and no trap: the same, singular)
        self.assertIn("1 Potent card and no trap in the deck: held all battle, a card short in hand (the bot keeps one "
                      "for a trap's second cast) - usetraps off for this deck throws it away",
                      notes(deck[:2] + [dict(sh, name="Potent Trap", display="Potent Trap", kind="potent", count=1)]))


# ============================================================================ v1.7.0: treasure cards drawn the bot's
# way, each blade and trap once a battle (reboost), the settings sent, junk never raises
def t3(opts=None, **kw):
    """the draw's battle: Storm Lord 850 at its least, 920 needed (Foe A: x0.85, killmargin 15) - 935 with a Strong's
    +100 - a full hand, a Strong the treasure pile's only card"""
    hand = [S.Card("Curse", "curse"), lord(), snake(), snake(), snake(), snake(), stormblade()]
    return battle(hand, [snake()] * 5 + [ench("Strong", 100, tc=True)], pips=7, fhp=[800],
                  opts=opts or S.Opts(drawenchant=1), **kw)


def freeze():
    return S.Card("Freeze", "stun", tc=True)


def kraken_battle(**kw):
    """T8(b)'s battle: a treasure Kraken (a hit, not an enchant) the only card to draw, one pass a round"""
    kraken = S.Card("Kraken", "damage", "storm", 3, heads={"storm": 5000}, tc=True)
    hand = [S.Card("Curse", "curse"), lord(), snake(), snake(), snake(), snake(), stormblade()]
    return battle(hand, [kraken], pips=7, fhp=[800], opts=S.Opts(drawenchant=1, drawround=1), **kw), kraken


class TreasureCards(unittest.TestCase):
    """the treasure side a pile of its own: never dealt, drawn only the bot's way (Draw.ahk DrawWouldKill /
    DrawForKill / DrawMakeRoom), never discarded"""

    def test_dealt_from_the_main_deck_only(self):
        strong = {"name": "Strong", "display": "Strong", "kind": "enchant", "value": 100, "count": 6,
                  "side": "treasure"}
        cards = S.deck_cards({"cards": [hit(count=4), hit("Thunder Snake", 2, 150, count=10), strong]})
        b = S._Battle(cards, S.Me("storm"), [S.Foe("x", 9000)], S.Opts(), random.Random(1))
        self.assertFalse(any(c.tc for c in b.pile))
        self.assertEqual((len(b.pile), len(b.tcs), all(c.tc for c in b.tcs), b.draw_off), (14, 6, True, False))
        b.run(True)
        self.assertEqual(len(b.tcs), 6)
        self.assertNotIn("Strong", b.casts)

    def test_never_discarded(self):
        b = battle([])
        b.hand = [freeze(), S.Card("Curse", "curse")]
        b.discard()
        self.assertEqual((names(b.hand), names(b.spent)), (["Freeze"], ["Curse"]))

    def test_draws_for_the_kill(self):
        b = t3()
        self.assertTrue(b.tcs)
        self.assertIs(b.draw_off, False)
        r = b.draw_for_kill()
        self.assertIs(r, False)                                     # (an enchant came)
        self.assertEqual((names(b.spent), b.draws, b.tcs, len(b.hand)), (["Curse"], 1, [], 7))
        self.assertIn("Strong", names(b.hand))
        c = b.choose()
        self.assertEqual(c.name, "Storm Lord")
        b.cast(c)
        self.assertEqual((b.fhp, b.casts.get("Strong")), ([0], 1))
        self.assertFalse(any(x.tc for x in b.spent))                # (the Strong used up)

    def test_room_card_rules(self):
        def room(hand):
            c = battle(hand, pips=7)._room_card(keep=lord())
            return c
        h = [lord(), snake(), snake(), stormblade()]
        self.assertIs(room(h), h[3])                                # (a non-hit first, even a blade)
        h = [lord(), snake(), lord()]
        self.assertIs(room(h), h[1])                                # (never a copy of the kill hit)
        h = [freeze(), S.Card("Primordial", "enchant", value=0), S.Card("Pet", "curse", item=True),
             S.Card("Pricey", "heal", "life", 8, value=500), snake()]
        self.assertIs(room(h), h[4])                                # (never a treasure / item card, an enchant, unpaid)
        self.assertIsNone(room([lord(), freeze()]))

    def test_limits(self):
        def b5(opts, fhp=800):
            return battle([S.Card("Curse", "curse")] * 3 + [lord()] + [snake()] * 3, [freeze()] * 5, pips=7, fhp=[fhp],
                          opts=opts)
        b = b5(S.Opts(drawenchant=1))
        self.assertIs(b.draw_for_kill(), True)                      # (drawround 3: three draws, no enchant came)
        self.assertEqual((b.draws, len(b.spent), len(b.tcs), names(b.hand).count("Freeze")), (3, 3, 2, 3))
        b = b5(S.Opts(drawenchant=1, drawmax=2))
        b.draw_for_kill()
        self.assertEqual(b.draws, 2)
        hand, spent = list(b.hand), list(b.spent)
        self.assertIs(b.draw_for_kill(), False)                     # (drawmax reached: nothing)
        self.assertEqual((b.draws, b.hand, b.spent), (2, hand, spent))
        self.assertEqual(S.Opts(drawneed=0).drawneed, 100.0)
        b = b5(S.Opts(drawenchant=1), fhp=850)
        self.assertEqual((b.draw_for_kill(), b.draws), (False, 0))  # (935 < 977.5)
        b = b5(S.Opts(drawenchant=1, drawneed=175), fhp=850)
        b.draw_for_kill()
        self.assertEqual(b.draws, 3)                                # (998.75 >= 977.5)
        # (a full hand with nothing to spare: no draw, and no DrawOff - tried again next round)
        b = battle([lord()] + [freeze()] * 6, [freeze()] * 2, pips=7, fhp=[800], opts=S.Opts(drawenchant=1))
        self.assertEqual((b.draw_for_kill(), b.draws, b.draw_off), (False, 0, False))

    def test_treasure_pile_runs_out(self):
        curse = S.Card("Curse", "curse")
        b = battle([curse] * 2 + [lord()] + [snake()] * 4, [freeze()], pips=7, fhp=[800], opts=S.Opts(drawenchant=1))
        self.assertIs(b.draw_for_kill(), True)
        # (the second Curse thrown away for a draw the empty pile can't give - Draw greyed out: drawing off)
        self.assertEqual((b.spent, b.draws, b.draw_off), ([curse, curse], 1, True))
        hand = list(b.hand)
        self.assertIs(b.draw_for_kill(), False)
        self.assertEqual((b.hand, b.draws), (hand, 1))
        b = battle([lord()] + [snake()] * 4, [freeze()], pips=7, fhp=[800], opts=S.Opts(drawenchant=1))
        self.assertIs(b.draw_for_kill(), True)
        self.assertEqual((b.spent, b.draws, b.draw_off, names(b.hand)[-1]), ([], 1, True, "Freeze"))
        # (no treasure card in the State's pile: drawing off from the start - never a room card thrown away)
        b = t3()
        b = battle(b.hand, [snake()] * 5, pips=7, fhp=[800], opts=S.Opts(drawenchant=1))
        self.assertIs(b.draw_off, True)
        self.assertEqual((b.draw_for_kill(), b.spent), (False, []))

    def test_gates(self):
        def same(b):
            hand, s0 = list(b.hand), b.rng.getstate()
            b.draw_for_kill()
            self.assertEqual((b.draws, b.hand, b.rng.getstate()), (0, hand, s0))
        same(t3(S.Opts()))                                          # (drawenchant off)
        hand = [S.Card("Curse", "curse"), lord(), snake(), snake(), snake(), snake(), stormblade()]
        pile = [snake()] * 5 + [ench("Strong", 100, tc=True)]
        o = S.Opts(drawenchant=1)
        same(battle([ench()] + hand[1:], pile, pips=7, fhp=[800], opts=o))      # (an enchant in hand)
        same(battle(hand, pile, pips=7, fhp=[500], opts=o))                      # (a plain kill)
        wand = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000}, item=True)
        same(battle([hand[0], wand] + hand[2:], pile, pips=7, fhp=[800], opts=o))   # (only an item card's would kill)
        done = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000}, ench=50)
        same(battle([hand[0], done] + hand[2:], pile, pips=7, fhp=[800], opts=o))   # (enchanted: 892.5, never a keep)
        same(battle(hand, pile, pips=7, fhp=[5000], opts=o))                     # (no kill even with +100)
        # (a Primordial - an enchant the bot never finds - doesn't stop it)
        b = battle([S.Card("Primordial", "enchant", value=0)] + hand[1:], pile, pips=7, fhp=[800], opts=o)
        b.draw_for_kill()
        self.assertEqual(b.draws, 1)

    def test_after_the_draw(self):
        # (an enchant that doesn't make the kill: it stays and goes on the next hit cast)
        curse = S.Card("Curse", "curse")
        b = battle([curse, lord(), snake(), snake(), snake(), snake(), curse], [ench("Strong", 100, tc=True)], pips=7,
                   fhp=[950], opts=S.Opts(drawenchant=1, drawneed=300))
        self.assertIs(b.draw_for_kill(), False)
        self.assertEqual(names(b.spent), ["Curse"])
        c = b.choose()
        self.assertEqual((c.name, b.ench_plain), ("Storm Lord", False))
        b.cast(c)
        self.assertEqual(b.casts, {"Storm Lord": 1, "Strong": 1})
        # (a treasure hit drawn: no kill check again this round - the bot's card flags were set before the draw)
        b, kraken = kraken_battle()
        self.assertIs(b.draw_for_kill(), True)
        self.assertEqual(b.drawn_now, [kraken])
        self.assertEqual(b.choose(kill=False).name, "Stormblade")
        self.assertIs(b.choose(), kraken)
        # (two Freezes drawn, two cards cast: the draw refills to 7 with both still in hand)
        b = battle([curse] * 2 + [lord()] + [snake()] * 4, [snake()] * 5 + [freeze()] * 2, pips=7, fhp=[800],
                   opts=S.Opts(drawenchant=1, drawround=2))
        self.assertIs(b.draw_for_kill(), True)
        for c in [c for c in b.hand if c.name == "Thunder Snake"][:2]:
            b.cast(c)
        b.draw()
        self.assertEqual((len(b.hand), names(b.hand).count("Freeze")), (7, 2))
        # (my_round holds the cards drawn now: the Stormblade goes, not the Kraken - the next round the Kraken kills)
        b, kraken = kraken_battle()
        self.assertIs(b.my_round(fresh=True), True)
        self.assertEqual((b.casts, b.draws, names(b.hand)[-1], names(b.spent)),
                         ({"Stormblade": 1}, 1, "Kraken", ["Curse", "Stormblade"]))
        self.assertIs(b.my_round(fresh=True), True)
        self.assertEqual((b.casts.get("Kraken"), b.fhp), (1, [0]))
        # (a treasure blade drawn this round is held too, so the Lord goes plain - not boost first with the drawn
        # Stormblade: no deck blade here to cast either way)
        tcb = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tc=True)
        b = battle([S.Card("Curse", "curse"), lord(), snake(), snake(), snake(), snake()], [tcb], pips=7, fhp=[800],
                   opts=S.Opts(drawenchant=1, drawround=1))
        self.assertIs(b.my_round(fresh=True), True)
        self.assertEqual((b.casts, b.draws, b.hand[-1]), ({"Storm Lord": 1}, 1, tcb))
        # (an enchant drawn isn't held: the Lord goes with it)
        b = t3()
        b.my_round(fresh=True)
        self.assertEqual(b.casts, {"Storm Lord": 1, "Strong": 1})

    def test_choose_stays_pure(self):
        b = t3()
        s0, h0, t0 = b.rng.getstate(), list(b.hand), list(b.tcs)
        b.choose()
        b.choose_support()
        self.assertEqual((b.rng.getstate(), b.hand, b.tcs), (s0, h0, t0))
        b.my_round(fresh=False)
        self.assertEqual(b.tcs, t0)
        b = t3()
        b.run_from(False, None, horizon=1)                          # (the planner's round now: no Draw)
        self.assertEqual(b.draws, 0)
        b = t3(S.Opts())
        b.my_round(fresh=True)
        self.assertEqual(b.draws, 0)
        b, _k = kraken_battle(stun=1)                               # (the draw comes after the stun check)
        t0 = list(b.tcs)
        self.assertIs(b.my_round(fresh=True), False)
        self.assertEqual((b.draws, b.tcs, b.stun), (0, t0, 0))

    def test_reshuffle_and_treasure(self):
        b = t3()
        b.draw_for_kill()
        b.cast(b.choose())                                          # (the Lord, the Strong on it)
        r = resh()
        b.hand.append(r)
        self.assertIs(b.cast(r), True)
        self.assertIn("Curse", names(b.pile))                       # (the room card: a main card, back)
        self.assertFalse(any(c.tc for c in b.pile))
        self.assertEqual(b.tcs, [])

    def test_planner_state(self):
        b = battle([freeze(), lord()], [snake()] * 4 + [freeze()] * 6, draws=2)
        self.assertEqual((len(b.tcs), b.draws), (5, 2))             # (6 less 2 drawn, 1 of them still in hand)
        strong = ench("Strong", 100, tc=True)
        b = t3(S.Opts(drawenchant=1, drawmax=6), draws=6)
        b = battle(b.hand, [snake()] * 5 + [strong] * 10, pips=7, fhp=[800], opts=S.Opts(drawenchant=1, drawmax=6),
                   draws=6)
        t0 = list(b.tcs)
        b.my_round(fresh=True)
        self.assertEqual((b.draws, b.tcs), (6, t0))                 # (drawmax reached)
        self.assertIs(battle([lord()], [freeze()] * 3, drawoff=1).draw_off, True)
        st = S.State([], draws="x", drawoff=[1])
        self.assertEqual((st.draws, st.drawoff), (0, False))
        tblade = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3, tc=True)
        st = S.State.of_deck([tblade], [stormblade(), tblade])
        self.assertEqual([c.tc for c in st.pile], [False])          # (the hand's treasure copy took the treasure one)
        # (the treasure pile's drops come last: every other random number as with nothing drawn)
        main = [lord(), snake(), stormblade(), S.Card("Curse", "curse"), resh(),
                S.Card("Tempest", "aoe", "storm", 6, heads={"storm": 400})]
        got = []
        for draws in (0, 2):
            st = S.State([freeze()], main + [freeze()] * 6, draws=draws)
            b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000), S.Foe("B", 900)], S.Opts(), random.Random(5))
            got.append((names(b.pile), b.me_first, b.fpips, len(b.tcs)))
        self.assertEqual(got[0][:3], got[1][:3])
        self.assertEqual((got[0][3], got[1][3]), (6, 5))
        # (a pile of treasure cards only: no draw pile - as the same State with them out of it)
        p = S.plan_round(S.State([lord()], [freeze()] * 3, pips=7, fhp=[9000], me_first=True), sure(),
                         [S.Foe("A", 9000)], n=5, seed=1, budget_ms=5000)
        self.assertIn("no draw pile known - the rollouts play the hand only", p["why"])

    def test_team_draws(self):
        # (a mate draws no treasure card - its pile's go nowhere: neither its draw pile nor a treasure pile)
        hit_mate = S.Mate("Hit", 5, S.Me("storm", 3000, accuracy=30), "hitter", [lord()],
                          [snake()] * 3 + [freeze()] * 2, 7, 0, None)
        st = S.State(t3().hand, [snake()] * 5 + [ench("Strong", 100, tc=True)], pips=7, fhp=[800], seat=4,
                     me_first=True, mates=[hit_mate])
        b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(role="blader", drawenchant=1), random.Random(1))
        self.assertEqual((b.side[1].tcs, b.side[1].draw_off), ([], True))
        self.assertFalse(any(c.tc for c in b.side[1].pile))
        self.assertEqual(len(b.side[1].pile), 3)
        b.my_round(fresh=True)
        self.assertEqual(b.draws, 1)


def trap():
    return S.Card("Storm Trap", "trap", "storm", 0, boosts={"storm": 30}, tid=4)


class Reboost(unittest.TestCase):
    """each blade and trap once a battle (KillCalc.ahk's used flags - reboost:0, the default): keyed by slot, marked at
    the click, freed by a hitter's Reshuffle - reboost:1 by the hit it fits; a treasure / item card's copy once more"""

    def test_once_a_battle(self):
        b = battle([stormblade(), stormblade(), lord()], pips=0, fhp=[9000])
        self.assertIs(b.cast(b.hand[0]), True)
        self.assertEqual(b.boosts_used, {("blade", "storm", ""): {"storm": 35}})
        b.blades = []                                               # (as if a hit used it)
        self.assertIsNone(b.pick_boost(lord()))
        b.discard()
        # (the used copy held - discardspent off: an older AutoFarmer)
        self.assertEqual(names(b.hand), ["Stormblade", "Storm Lord"])
        b = battle([trap(), trap(), lord()], pips=0, fhp=[9000])
        b.cast(b.hand[0])
        self.assertIsNone(b.pick_boost(lord()))
        feint = S.Card("Feint", "trap", "", 0, boosts={"all": 70})
        hexed = S.Card("Hex", "trap", "", 0, boosts={"all": 30})
        self.assertEqual((S._bkey(feint), S._bkey(hexed)), (("trap", "all/70", ""), ("trap", "all/30", "")))
        b = battle([feint, hexed, lord()], pips=0, fhp=[9000])
        b.cast(feint)
        self.assertIs(b.pick_boost(lord()), hexed)
        # (one slot, two names: the bot's one storm/blade flag)
        b = battle([stormblade(), S.Card("Thunderblade", "blade", "storm", 0, boosts={"storm": 40}), lord()], pips=0,
                   fhp=[9000])
        b.cast(b.hand[0])
        self.assertIsNone(b.pick_boost(lord()))
        self.assertEqual(S._slot("blade", None), ("blade", ""))
        self.assertEqual(S._slot("blade", {"storm": "x", "fire": float("nan")}), ("blade", ""))
        self.assertEqual(S._slot("blade", {"fire": 35, "ice": 35, "storm": 35}), ("blade", "fire,ice,storm"))

    def test_copies_go_once_more_and_stack(self):
        tcb = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3, tc=True)
        pet = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3, item=True)
        b = battle([stormblade(), tcb, pet, tcb, lord()], pips=0, fhp=[9000])
        b.cast(b.hand[0])
        self.assertIs(b.pick_boost(lord()), tcb)
        b.cast(tcb)
        self.assertEqual([n for n, _b in b.blades], ["Stormblade", "Stormblade@tc"])
        self.assertIs(b.pick_boost(lord()), pet)
        b.cast(pet)
        self.assertEqual([n for n, _b in b.blades], ["Stormblade", "Stormblade@tc", "Stormblade@item"])
        self.assertIsNone(b.pick_boost(lord()))                     # (the second treasure copy: its one cast went)
        both = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tc=True, item=True)
        self.assertEqual((S._bkey(both), S._on_name(both)), (("blade", "storm", "item"), "Stormblade@item"))

    def test_a_fizzle_marks(self):
        c = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, acc=-200)
        b = battle([c, lord()], pips=0, fhp=[9000])
        self.assertIs(b.cast(c), False)
        self.assertIn(("blade", "storm", ""), b.boosts_used)

    def test_reboost_on(self):
        def go(opts, cards):
            b = battle(cards, pips=7, fhp=[9000], opts=opts)
            for c in list(b.hand[:2]):
                b.cast(c)
            return b
        orthrus = S.Card("Orthrus", "damage", "myth", 3, heads={"myth": 400})
        b = go(S.Opts(reboost=1), [stormblade(), lord(), stormblade()])
        self.assertEqual(b.boosts_used, {})
        self.assertIs(b.pick_boost(lord()), b.hand[0])              # (the second copy: one cast between hits)
        self.assertIn(("blade", "storm", ""), go(S.Opts(reboost=2), [stormblade(), lord()]).boosts_used)
        self.assertIn(("blade", "storm", ""), go(S.Opts(reboost=1), [stormblade(), orthrus]).boosts_used)
        bal = S.Card("Balanceblade", "blade", "balance", 0, boosts={"all": 25})
        self.assertEqual(go(S.Opts(reboost=1), [bal, orthrus]).boosts_used, {})
        b = battle([trap(), trap(), lord()], pips=7, fhp=[9000], opts=S.Opts(reboost=1))
        b.cast(b.hand[0])
        self.assertIsNone(b.pick_boost(lord()))                     # (identical traps never stack before a hit)
        b.cast(b.hand[-1])
        self.assertIs(b.pick_boost(lord()), b.hand[0])
        miss = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000}, acc=-200)
        b = go(S.Opts(reboost=1), [stormblade(), miss])
        self.assertEqual((b.casts["Storm Lord"], b.pips, b.boosts_used), (1, 7, {}))    # (a fizzle frees too)
        # (a support's own hit frees nothing, even with reboost 1 - KillCalc.ahk: not PartySupport())
        b = battle([stormblade(), snake()], pips=2, fhp=[9000], opts=S.Opts(role="blader", reboost=1))
        b.cast(b.hand[0])
        b.cast(b.hand[0])
        self.assertEqual(b.casts, {"Stormblade": 1, "Thunder Snake": 1})
        self.assertIn(("blade", "storm", ""), b.boosts_used)

    def test_reshuffle_frees(self):
        b = battle([stormblade(), stormblade(), lord(), resh()], pips=0, fhp=[9000])
        b.cast(b.hand[0])
        b.cast(b.hand[-1])
        self.assertEqual(b.boosts_used, {})
        self.assertEqual(b.blades, [("Stormblade", {"storm": 35})])   # (the blades on stay on)
        second = b.pick_boost(lord())
        self.assertIs(second, b.hand[0])
        b.cast(second)                                              # (cast again and wasted, as the bot does)
        self.assertEqual(b.blades, [("Stormblade", {"storm": 35})])
        st = S.State([stormblade(), resh()], [], pips=0, fhp=[9000], seat=4, me_first=True,
                     mates=[mate("Hit", 5, "hitter", [lord()], pips=7)])
        b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(role="blader"), random.Random(1))
        b.cast(b.hand[0])
        b.cast(b.hand[-1])                                          # (a support's Reshuffle frees nothing)
        self.assertIn(("blade", "storm", ""), b.boosts_used)

    def test_supports_get_theirs_back(self):
        def blader(hand, mates=None, pshield=False):
            st = S.State(hand, [], pips=2, fhp=[9000], seat=4, me_first=True, pshield_used=pshield,
                         mates=mates or [mate("Hit", 5, "hitter", [lord()], pips=7)])
            return S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(role="blader"), random.Random(1))
        b = blader([stormblade(), stormblade()], pshield=True)
        c = b.choose_support()
        self.assertEqual((c.name, b.blade_to), ("Stormblade", 1))
        b.cast(c)
        self.assertIsNone(b.choose_support())                       # (the second copy held)
        b._swap(1)
        b.cast(b.hand[0])                                           # (the hitter's Lord)
        b._swap(0)
        self.assertEqual((b.boosts_used, b.pshield_used), ({}, False))
        cat = S.Card("Fire Cat", "damage", "fire", 1, heads={"fire": 100})
        b = blader([stormblade()], mates=[mate("Hit", 5, "hitter", [lord(), cat], pips=7)])
        b.cast(b.choose_support())                                  # (for the Lord, the hitter's biggest)
        b._swap(1)
        b.cast(b.hand[1])                                           # (the Fire Cat: a storm blade doesn't fit it)
        b._swap(0)
        self.assertIn(("blade", "storm", ""), b.boosts_used)
        b = blader([stormblade(), snake()])
        b.cast(b.hand[0])
        b.cast(b.hand[0])                                           # (its own hit frees nothing)
        self.assertIn(("blade", "storm", ""), b.boosts_used)
        b = blader([stormblade()], mates=[mate("Hit", 5, "hitter", None)])
        b.cast(b.hand[0])
        b._swap(1)
        b.rng = random.Random(1)                                    # (its first roll 0.13 < GENERIC_CAST: it hits)
        self.assertIs(b.generic_round(), True)
        b._swap(0)
        self.assertEqual(b.boosts_used, {})
        # (the gate is its own used set, not the hitter's blades: with a Stormblade on the hitter already it still
        # casts one - wasted, as the bot's blader does)
        hit_on = S.Mate("Hit", 5, S.Me("storm", 3000, accuracy=30), "hitter", [lord()], [], 7, 0, None,
                        blades=[("Stormblade", {"storm": 35})])
        b = blader([stormblade(), stormblade()], mates=[hit_on])
        c = b.choose_support()
        self.assertEqual((c.name, b.blade_to), ("Stormblade", 1))

    def test_party_shield_till_the_hitters_hit(self):
        st = S.State([tower(), tower()], [], pips=2, hp=3000, fhp=[9000], me_first=True, seat=4, pshield_used=True,
                     mates=[mate("Hit", 5, "hitter", [lord()], pips=7)])
        b = S._Battle.from_state(st, S.Me("storm", 3000), [S.Foe("Boss", 9000)], S.Opts(role="healer"),
                                 random.Random(1))
        self.assertIsNone(b._party_shield())
        b._swap(1)
        b.cast(b.hand[0])
        b._swap(0)
        self.assertIs(b.pshield_used, False)
        self.assertEqual((b._party_shield().name, b.shield_to), ("Tower Shield", 1))

    def test_used_copies_clog_the_hand(self):
        """the older AutoFarmer's play (Opts() - discardspent off): its used copies held in hand, so reboost 1 wins more.
        This AutoFarmer throws them away: SpentCopies.test_thrown_beats_held"""
        foe = S.Foe("Boss", 6000, spells=[("Hit", 1.0, {"pips": 2, "min": 150, "max": 200, "accuracy": 100})])
        boosted = S.deck_cards({"cards": [hit(count=8), boost("blade", "Stormblade", 35, count=6),
                                          boost("trap", "Storm Trap", 30, count=6)]})
        off = S.simulate(boosted, S.Me("storm", 3000), [foe], S.Opts(), n=300, seed=3)
        on = S.simulate(boosted, S.Me("storm", 3000), [foe], S.Opts(reboost=1), n=300, seed=3)
        self.assertLessEqual(off["casts"]["Stormblade"], 1.0)       # (no Reshuffle: once a battle)
        self.assertLessEqual(off["casts"]["Storm Trap"], 1.0)
        self.assertGreater(on["won"], off["won"])


class SettingsSent(unittest.TestCase):
    """every setting the simulator reads, as the bot reads it (Opts - Decks.ahk DeckSimVals sends them)"""

    def test_opts_new_keys(self):
        o = S.Opts()
        self.assertEqual((o.reboost, o.drawenchant, o.drawneed, o.drawround, o.drawmax, o.enemyspells, o.useabsorb),
                         (False, False, 100.0, 3, 6, True, True))
        self.assertIs(o.discardspent, False)                        # (v1.8.0: not sent - an older AutoFarmer's)
        o = S.Opts.of({"reboost": "1", "drawenchant": "1", "drawneed": "175", "drawround": "2", "drawmax": "4",
                       "enemyspells": "0", "discardspent": "1"})
        self.assertEqual((o.reboost, o.drawenchant, o.drawneed, o.drawround, o.drawmax, o.enemyspells),
                         (True, True, 175.0, 2, 4, False))
        self.assertIs(o.discardspent, True)
        # (the bot: Stat("reboost") == 1 - on only at exactly 1; drawenchant at any number but 0)
        self.assertEqual((S.Opts.of({"reboost": "2"}).reboost, S.Opts.of({"reboost": "0.5"}).reboost), (False, False))
        self.assertIs(S.Opts.of({"drawenchant": "2"}).drawenchant, True)
        plain = vars(S.Opts())
        for junk in ("x", "nan", "inf", "1e400", "-inf", None, [1]):
            self.assertEqual(vars(S.Opts.of({k: junk for k in S.Opts.KEYS})), plain, junk)
        for vals in (5, "abc", ["cardlogic"], None):
            self.assertEqual(vars(S.Opts.of(vals)), plain, vals)
        self.assertEqual(vars(S.Opts(cardlogic=float("nan"), boostmax=float("inf"), discardmax="x",
                                     healat=float("nan"), killmargin=float("-inf"))), plain)
        self.assertEqual(S.Opts(1, 0, 40, 15, 1, 1, 1, 1, 1, 3, True).boss, True)

    def test_enemyspells_off(self):
        b = battle([snake(), tower()], foes=[smasher()], pips=2, hp=900, fhp=[9000], opts=S.Opts(enemyspells=0))
        b._snap_danger()
        self.assertIsNone(b._defend())
        self.assertNotEqual(b.choose().name, "Tower Shield")
        b = battle([snake(), tower()], foes=[smasher()], pips=2, hp=900, fhp=[9000])
        b._snap_danger()
        self.assertEqual(b.choose().name, "Tower Shield")


# (J3: every deck this file hands deck_cards, and the new tests' valid ones - deck_cards' output (runs of one Card:
# copies and every field) computed with v1.6.0's simulator)
def deck_fixtures():
    resh_d = {"name": "Reshuffle", "display": "Reshuffle", "kind": "manipulation", "school": "", "pips": 0, "count": 1,
              "side": "main"}
    stun = {"name": "Freeze", "display": "Freeze", "kind": "stun", "school": "ice", "pips": 0, "value": 0, "count": 3,
            "side": "treasure"}
    facts = {123: {"kind": "damage", "value": "295-335", "school": "storm", "pips": 4, "heads": "storm:295"},
             124: {"kind": "aoe", "value": "100/pip", "school": "fire", "pips": 0},
             125: {"kind": "blade", "value": "35%", "school": "storm", "boosts": "storm:35"}}
    tower_d = {"name": "Tower Shield", "display": "Tower Shield", "kind": "ward", "pips": 0, "count": 2, "side": "main"}
    epic = {"name": "Epic", "display": "Epic", "kind": "enchant", "value": 300, "count": 2, "side": "main"}
    strong = {"name": "Strong", "display": "Strong", "kind": "enchant", "value": 100, "count": 6, "side": "treasure"}
    tempest = dict(hit("Tempest", 6, 400, aoe=True, count=4), side="treasure")
    main = [hit(count=6), hit("Thunder Snake", 2, 150, count=10), boost("blade", "Stormblade", 35, count=4)]
    return [({"cards": [hit(count=n)]}, None) for n in (20, 8, 30, 5, 10)] + [
        ({"cards": [boost("blade", "Stormblade", 35, count=10)]}, None),
        ({"cards": [hit(value=50, pips=1, count=40)]}, None),
        ({"cards": [hit(count=8), boost("blade", "Stormblade", 35, count=6), boost("trap", "Storm Trap", 30, count=6)]},
         None),
        ({"cards": [hit("Tempest", 6, 500, aoe=True, count=10)]}, None),
        ({"item_cards": [{"template_id": 123, "count": 1}, {"template_id": 124, "count": 1},
                         {"template_id": 125, "count": 2}]}, facts),
        ({"cards": [hit()], "item_cards": [{"template_id": 123, "count": 1, "name": "Wand"}]}, facts),
        ({"cards": [boost("blade", "Stormblade", 35, count=4)]}, None),
        ({"cards": [hit("Bolt", 1, 500, count=40)]}, None),
        ({"cards": [hit("Storm Lord", 3, 1500, count=20)]}, None),
        ({"cards": [hit("Thunder Snake", 2, 100, count=20)]}, None),
        ({"cards": [hit("Storm Lord", 3, 700, count=10), hit("Thunder Snake", 2, 300, count=10)]}, None),
        ({"cards": [hit("Thunder Snake", 2, 300, count=10), hit("Storm Lord", 3, 700, count=10)]}, None),
        ({"cards": [hit("Bolt", 1, 300, count=8), resh_d]}, None),
        ({"cards": [resh_d, hit("Bolt", 1, 300, count=8)]}, None),
        ({"cards": [hit(count=8), hit("Thunder Snake", 2, 150, count=6), boost("blade", "Stormblade", 35, count=4),
                    boost("trap", "Storm Trap", 30, count=4)]}, None),
        ({"cards": [hit("Thunder Snake", 2, 300, count=10), boost("blade", "Stormblade", 35, count=2)]}, None),
        ({"cards": [hit("Thunder Snake", 2, 300, count=10), boost("blade", "Stormblade", 35, count=2), stun]}, None),
        ({"cards": [hit(count=6), hit("Thunder Snake", 2, 150, count=10), boost("blade", "Stormblade", 35, count=4),
                    {"name": "Stun", "display": "Stun", "kind": "stun", "count": 6, "side": "treasure"},
                    {"name": "Weakness", "display": "Weakness", "kind": "weakness", "count": 4, "side": "treasure"}]},
         None),
        ({"cards": [hit(count=10), tower_d, epic]}, None),
        ({"gid": 0x1234, "display": "Boss Storm", "school": "Storm", "sets": [2],
          "cards": [hit(count=4), boost("blade", "Stormblade", 35, count=3), boost("trap", "Storm Trap", 30, count=3),
                    {"name": "Tower Shield", "display": "Tower Shield", "kind": "ward", "count": 2}]}, None),
        ({"cards": [hit("Tempest", 6, 500, aoe=True, count=8), hit("Thunder Snake", 2, 125, count=2)]}, None),
        ({"cards": [hit(count=6), hit("Thunder Snake", 2, 150, count=6), boost("blade", "Stormblade", 35),
                    boost("trap", "Storm Trap", 30)]}, None),
        ({"cards": main}, None),
        ({"cards": [strong, tempest] + main}, None),
        ({"cards": [hit(count=4), hit("Thunder Snake", 2, 150, count=10), strong]}, None)]


def deck_sig(cards):
    """deck_cards' output as runs of one Card object: [[copies, name, kind, school, pips, x, value, heads, boosts, acc,
    tid, tc, item, top, dot, ench, tower, resh, bot_ench]]"""
    out = []
    for c in cards:
        if out and out[-1][0] is c:
            out[-1][1] += 1
            continue
        out.append([c, 1])
    return [[n, c.name, c.kind, c.school, c.pips, c.x, c.value, sorted(c.heads.items()), sorted(c.boosts.items()),
             c.acc, c.tid, c.tc, c.item, c.top, c.dot, c.ench, c.tower, c.resh, c.bot_ench] for c, n in out]


J3_PINS = [[[20, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, '']],
           [[8, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, '']],
           [[30, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, '']],
           [[5, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, '']],
           [[10, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, '']],
           [[10, 'Stormblade', 'blade', 'storm', 0, False, 35.0, [], [('storm', 35.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, '']],
           [[40, 'Storm Lord', 'damage', 'storm', 1, False, 50.0, [('storm', 50.0)], [], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, '']],
           [[8, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [6, 'Stormblade', 'blade', 'storm', 0, False, 35.0, [], [('storm', 35.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, ''],
            [6, 'Storm Trap', 'trap', 'storm', 0, False, 30.0, [], [('storm', 30.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, '']],
           [[10, 'Tempest', 'aoe', 'storm', 6, False, 500.0, [('storm', 500.0)], [], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, '']],
           [[1, '?', 'damage', 'storm', 4, False, 295.0, [('storm', 295.0)], [], 70, 123, False, True,
             1.1355932203389831, 0.0, 0.0, False, False, ''],
            [1, '?', 'aoe', 'fire', 0, True, 100.0, [('fire', 100.0)], [], 75, 124, False, True, 1.13, 0.0, 0.0,
             False, False, ''],
            [2, '?', 'blade', 'storm', 0, False, 35.0, [], [('storm', 35.0)], 70, 125, False, True, 1.13, 0.0, 0.0,
             False, False, '']],
           [[1, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [1, 'Wand', 'damage', 'storm', 4, False, 295.0, [('storm', 295.0)], [], 70, 123, False, True,
             1.1355932203389831, 0.0, 0.0, False, False, '']],
           [[4, 'Stormblade', 'blade', 'storm', 0, False, 35.0, [], [('storm', 35.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, '']],
           [[40, 'Bolt', 'damage', 'storm', 1, False, 500.0, [('storm', 500.0)], [], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, '']],
           [[20, 'Storm Lord', 'damage', 'storm', 3, False, 1500.0, [('storm', 1500.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, '']],
           [[20, 'Thunder Snake', 'damage', 'storm', 2, False, 100.0, [('storm', 100.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, '']],
           [[10, 'Storm Lord', 'damage', 'storm', 3, False, 700.0, [('storm', 700.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [10, 'Thunder Snake', 'damage', 'storm', 2, False, 300.0, [('storm', 300.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, '']],
           [[10, 'Thunder Snake', 'damage', 'storm', 2, False, 300.0, [('storm', 300.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [10, 'Storm Lord', 'damage', 'storm', 3, False, 700.0, [('storm', 700.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, '']],
           [[8, 'Bolt', 'damage', 'storm', 1, False, 300.0, [('storm', 300.0)], [], 70, None, False, False, 1.13, 0.0,
             0.0, False, False, ''],
            [1, 'Reshuffle', 'manipulation', '', 0, False, 0.0, [], [], 100, None, False, False, 1.13, 0.0, 0.0,
             False, True, '']],
           [[1, 'Reshuffle', 'manipulation', '', 0, False, 0.0, [], [], 100, None, False, False, 1.13, 0.0, 0.0,
             False, True, ''],
            [8, 'Bolt', 'damage', 'storm', 1, False, 300.0, [('storm', 300.0)], [], 70, None, False, False, 1.13, 0.0,
             0.0, False, False, '']],
           [[8, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [6, 'Thunder Snake', 'damage', 'storm', 2, False, 150.0, [('storm', 150.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [4, 'Stormblade', 'blade', 'storm', 0, False, 35.0, [], [('storm', 35.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, ''],
            [4, 'Storm Trap', 'trap', 'storm', 0, False, 30.0, [], [('storm', 30.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, '']],
           [[10, 'Thunder Snake', 'damage', 'storm', 2, False, 300.0, [('storm', 300.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [2, 'Stormblade', 'blade', 'storm', 0, False, 35.0, [], [('storm', 35.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, '']],
           [[10, 'Thunder Snake', 'damage', 'storm', 2, False, 300.0, [('storm', 300.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [2, 'Stormblade', 'blade', 'storm', 0, False, 35.0, [], [('storm', 35.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, ''],
            [3, 'Freeze', 'stun', 'ice', 0, False, 0.0, [], [], 80, None, True, False, 1.13, 0.0, 0.0, False, False,
             '']],
           [[6, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [10, 'Thunder Snake', 'damage', 'storm', 2, False, 150.0, [('storm', 150.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [4, 'Stormblade', 'blade', 'storm', 0, False, 35.0, [], [('storm', 35.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, ''],
            [6, 'Stun', 'stun', '', 0, False, 0.0, [], [], 85, None, True, False, 1.13, 0.0, 0.0, False, False, ''],
            [4, 'Weakness', 'weakness', '', 0, False, 0.0, [], [], 85, None, True, False, 1.13, 0.0, 0.0, False,
             False, '']],
           [[10, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [2, 'Tower Shield', 'ward', '', 0, False, 0.0, [], [], 100, None, False, False, 1.13, 0.0, 0.0, True,
             False, ''],
            [2, 'Epic', 'enchant', '', 0, False, 300.0, [], [], 85, None, False, False, 1.13, 0.0, 0.0, False, False,
             'epic']],
           [[4, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [3, 'Stormblade', 'blade', 'storm', 0, False, 35.0, [], [('storm', 35.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, ''],
            [3, 'Storm Trap', 'trap', 'storm', 0, False, 30.0, [], [('storm', 30.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, ''],
            [2, 'Tower Shield', 'ward', '', 0, False, 0.0, [], [], 100, None, False, False, 1.13, 0.0, 0.0, True,
             False, '']],
           [[8, 'Tempest', 'aoe', 'storm', 6, False, 500.0, [('storm', 500.0)], [], 70, None, False, False, 1.13, 0.0,
             0.0, False, False, ''],
            [2, 'Thunder Snake', 'damage', 'storm', 2, False, 125.0, [('storm', 125.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, '']],
           [[6, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [6, 'Thunder Snake', 'damage', 'storm', 2, False, 150.0, [('storm', 150.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [1, 'Stormblade', 'blade', 'storm', 0, False, 35.0, [], [('storm', 35.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, ''],
            [1, 'Storm Trap', 'trap', 'storm', 0, False, 30.0, [], [('storm', 30.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, '']],
           [[6, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [10, 'Thunder Snake', 'damage', 'storm', 2, False, 150.0, [('storm', 150.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [4, 'Stormblade', 'blade', 'storm', 0, False, 35.0, [], [('storm', 35.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, '']],
           [[6, 'Strong', 'enchant', '', 0, False, 100.0, [], [], 85, None, True, False, 1.13, 0.0, 0.0, False, False,
             'strong'],
            [4, 'Tempest', 'aoe', 'storm', 6, False, 400.0, [('storm', 400.0)], [], 70, None, True, False, 1.13, 0.0,
             0.0, False, False, ''],
            [6, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [10, 'Thunder Snake', 'damage', 'storm', 2, False, 150.0, [('storm', 150.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [4, 'Stormblade', 'blade', 'storm', 0, False, 35.0, [], [('storm', 35.0)], 70, None, False, False, 1.13,
             0.0, 0.0, False, False, '']],
           [[4, 'Storm Lord', 'damage', 'storm', 7, False, 1000.0, [('storm', 1000.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [10, 'Thunder Snake', 'damage', 'storm', 2, False, 150.0, [('storm', 150.0)], [], 70, None, False, False,
             1.13, 0.0, 0.0, False, False, ''],
            [6, 'Strong', 'enchant', '', 0, False, 100.0, [], [], 85, None, True, False, 1.13, 0.0, 0.0, False, False,
             'strong']]]


class JunkInput(unittest.TestCase):
    """deck_cards, card_of, deck_kinds, learn_deck, learn_decks and Opts.of never raise on junk: a bad card is left out
    and counted - one garbled deck never fails every deck in /deckfor's work thread"""
    CARD_JUNK = [None, 1, "s", [1, 2], {"kind": "damage", "count": "x"}, {"count": "nan"},
                 {"pips": "x", "kind": "damage"}, {"kind": "blade", "school": 5}, {"kind": "damage", "heads_text": 5},
                 {"kind": "blade", "boosts_text": ["x"]}, {"kind": "damage", "template_id": [1]},
                 {"kind": "damage", "school": "storm", "value": 100, "count": float("inf")},
                 {"kind": "damage", "count": float("-inf")}]

    HUGE = ({"kind": "damage", "school": "storm", "pips": 2, "value": 300, "heads_text": "storm:1.7e308,fire:1.7e308"},
            {"kind": "damage", "school": "storm", "pips": 2, "value": 300, "heads_text": "storm:1.7e308,storm:1.7e308"},
            {"kind": "damage", "school": "storm", "pips": 2, "value": "9" * 400},
            {"kind": "damage", "school": "storm", "pips": 2, "value": 1.7e308})

    def junk_decks(self):
        return [5, "abc", [1, 2], {"cards": "xy"}, {"cards": 5}, {"cards": [None, 1, "s", [1, 2]]},
                {"cards": [{"kind": "damage", "count": "x"}]}, {"cards": [{"count": "nan"}]},
                {"cards": [{"pips": "x", "kind": "damage"}]}, {"cards": [{"kind": "blade", "school": 5}]},
                {"cards": [{"kind": "damage", "heads_text": 5}]}, {"cards": [{"kind": "blade", "boosts_text": ["x"]}]},
                {"cards": [{"kind": "damage", "template_id": [1]}]}, {"cards": None, "item_cards": [None]},
                {"item_cards": "ab"}, {"cards": {"a": 1}},
                {"cards": [{"kind": "damage", "school": "storm", "value": 100, "count": float("inf")}]},
                json.loads('{"cards": [{"name": "x", "kind": "damage", "school": "storm", "value": 100, '
                           '"count": 1e400}]}'),
                {"cards": [{"kind": "damage", "count": float("-inf")}]},
                {"item_cards": [{"kind": "damage", "count": float("inf")}]}]

    def test_deck_cards_never_raises(self):
        for facts in (None, "x", [1]):
            for junk in self.junk_decks():
                cards = S.deck_cards(junk, facts, [])
                self.assertIsInstance(cards, list, junk)
                self.assertIsInstance(S.deck_kinds(junk, facts), tuple, junk)
        # (the infinite counts: one copy each)
        self.assertEqual(len(S.deck_cards(self.junk_decks()[17])), 1)
        self.assertEqual(S.deck_kinds(self.junk_decks()[17])[0], {"damage": 1})
        why = []
        cards = S.deck_cards({"cards": [hit(count=2), {"pips": "x", "kind": "damage", "count": 3}, None]}, None, why)
        self.assertEqual(names(cards), ["Storm Lord"] * 2)
        self.assertEqual(why, ["4 cards with no kind known left out"])
        why = []
        self.assertEqual(S.deck_cards(5, None, why), [])
        self.assertEqual(why, ["the deck couldn't be read"])

    def test_second_order_junk(self):
        for c in ({"kind": "damage", "school": "storm", "pips": 2, "value": 300, "accuracy": "x"},
                  {"kind": "damage", "school": "storm", "pips": 2, "value": 300, "heads_text": "fire:inf"},
                  {"name": ["a"], "kind": "damage", "school": "storm", "pips": 2, "value": 300},
                  {"kind": ["damage"], "school": "storm", "pips": 2, "value": 300},
                  {"kind": "damage", "school": "storm", "pips": 2, "value": float("nan")}) + self.HUGE:
            cards = S.deck_cards({"cards": [dict(c, count=10)]})
            r = S.simulate(cards, sure(), [biter("Rat", 500)], n=5, seed=1)
            self.assertGreater(r["n"], 0, (c, r["why"]))
        c = S.card_of({"kind": "damage", "school": "storm", "pips": 2, "value": 300, "accuracy": "x"})
        self.assertEqual(c.acc, 70)
        self.assertEqual(S.card_of({"kind": "damage", "value": 300, "heads_text": "fire:inf,storm:300"}).heads,
                         {"storm": 300.0})
        self.assertEqual(S.value_of(float("nan")), (None, None, False))
        self.assertEqual((S.school_of(5), S.parse_pairs(5), S.parse_pairs("storm:nan,fire:30")),
                         ("", {}, {"fire": 30.0}))
        # (a number past 1e9 is junk too - no card's is near it, and a sum or int() of it can't overflow later)
        self.assertEqual((S.parse_pairs("storm:1.7e308,storm:1.7e308,fire:30"), S.parse_pairs("storm:-2e9")),
                         ({"fire": 30.0}, {}))
        self.assertEqual([S.value_of(v) for v in (1.7e308, -2e9, 10 ** 400, "9" * 400, "-" + "9" * 12)],
                         [(None, None, False)] * 5)
        self.assertEqual((S.value_of("295-" + "9" * 400), S.value_of(1e9)), ((295.0, None, False), (1e9, None, False)))

    def test_valid_decks_unchanged(self):
        sigs = [deck_sig(S.deck_cards(d, f)) for d, f in deck_fixtures()]
        self.assertEqual(len(sigs), len(J3_PINS))
        for k, (got, want) in enumerate(zip(sigs, J3_PINS)):
            self.assertEqual(got, want, k)
        # (the copies of one entry are one Card object - deck_cards' list order is what the shuffle draws on)
        cards = S.deck_cards({"cards": [hit(count=3)]})
        self.assertTrue(cards[0] is cards[1] is cards[2])

    def test_learning_never_raises(self):
        for junk in self.junk_decks() + [{"cards": [hit()], "sets": 5}, {"cards": [hit()], "sets": ["a"]},
                                         {"cards": [hit()], "sets": [True]}, {"sets": [12]}]:
            self.assertIsInstance(S.deck_kinds(junk), tuple)
            L = S.learn_deck(junk)
            self.assertIsInstance(L, dict, junk)
            self.assertIn(L["eqset"], range(10))
        self.assertEqual(S.learn_deck({"cards": [hit()], "sets": [3]})["eqset"], 3)
        for reading in ({"decks": 5}, {"decks": [5]}, "x", None, {"decks": [{"sets": [1], "cards": "x"}]}):
            self.assertIsInstance(S.learn_decks(reading), list, reading)
        # (numbers past 1e9: no overflow in the hits' sums - each deck learned, the good one next to it too)
        for c in self.HUGE:
            deck = {"cards": [dict(c, count=4), hit(count=4)], "sets": [1]}
            self.assertIsInstance(S.deck_kinds(deck), tuple, c)
            self.assertIsInstance(S.learn_deck(deck), dict, c)
            got = S.learn_decks({"decks": [deck, {"cards": [hit(count=4)], "sets": [2]}]})
            self.assertEqual(len(got), 2, c)
        for c in self.CARD_JUNK:
            self.assertTrue(S.card_of(c) is None or isinstance(S.card_of(c), S.Card), c)


class PlanUsed(unittest.TestCase):
    """the planner holds back a blade or trap the bot cast this battle (its used flags - Planner.ahk used=)"""

    def test_used_this_battle(self):
        st = S.State([stormblade(), lord()], [snake()] * 5, pips=3, fhp=[9000], me_first=True,
                     boosts_used=[("blade", "", {"storm": 35})])
        b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(), random.Random(1))
        self.assertEqual(S._plannable(stormblade(), S.Opts(), b), "used this battle")
        p = S.plan_round(st, sure(), [S.Foe("A", 9000)], n=10, seed=1, budget_ms=5000)
        self.assertNotIn("Stormblade", [x["name"] for x in p["plays"]])
        self.assertIn("1 card in hand not tried (used this battle)", p["why"])
        self.assertEqual(S.State([], boosts_used=[("aura", "", {"storm": 25}), ("x",), 5]).boosts_used, [])
        self.assertEqual(S.State([], boosts_used=[("trap", "pet", {"storm": "30", "fire": float("inf")})]).boosts_used,
                         [("trap", "", {"storm": 30.0})])
        self.assertIsNone(S.State([], boosts_used="junk").boosts_used)

    def test_old_bot_fallback(self):
        # (no used= - an older AutoFarmer: the blades on taken as cast - today's "on already", checked first)
        b = battle([stormblade(), lord()], blades=[("Stormblade", {"storm": 35})])
        self.assertEqual(b.boosts_used, {("blade", "storm", ""): {"storm": 35}})
        self.assertEqual(S._plannable(stormblade(), S.Opts(), b), "on already")
        for n in ("Stormblade@tc", "storm/blade@tc"):
            self.assertEqual(list(battle([], blades=[(n, {"storm": 35})]).boosts_used), [("blade", "storm", "tc")])
        self.assertEqual(battle([], blades=[("storm/blade+", {"storm": 45})]).boosts_used, {})
        self.assertEqual(battle([], blades=[("Stormblade", {"storm": 35})], boosts_used=[]).boosts_used, {})

    def test_bot_boosts_used(self):
        got = S.bot_boosts_used([("storm/blade", {"storm": 35}), ("storm/trap", {"storm": 30}), ("feint", {"all": 70}),
                                 ("trap3", {"all": 30}), ("elementalblade", {"fire": 35, "ice": 35, "storm": 35}),
                                 ("storm/blade@tc", {"storm": 35}), ("storm/blade@item", {"storm": 35}),
                                 ("storm/blade+", {"storm": 45})])
        self.assertEqual(got, [("blade", "", {"storm": 35}), ("trap", "", {"storm": 30}), ("trap", "", {"all": 70}),
                               ("trap", "", {"all": 30}), ("blade", "", {"fire": 35, "ice": 35, "storm": 35}),
                               ("blade", "tc", {"storm": 35}), ("blade", "item", {"storm": 35})])
        b = battle([], boosts_used=got)
        cards = [stormblade(), trap(), S.Card("Feint", "trap", "", 0, boosts={"all": 70}),
                 S.Card("Hex", "trap", "", 0, boosts={"all": 30}),
                 S.Card("Elemental Blade", "blade", "balance", 0, boosts={"fire": 35, "ice": 35, "storm": 35}),
                 S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tc=True),
                 S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, item=True)]
        self.assertEqual(sorted(b.boosts_used), sorted(S._bkey(c) for c in cards))
        for junk in (None, 5, [("x",)], [(1, "y")], [("storm/blade", "x")], [("storm/blade@pet", {"storm": 35})],
                     [("storm/blade", {"storm": float("nan")})]):
            self.assertEqual(S.bot_boosts_used(junk), [], junk)

    def test_copy_kinds_as_plays(self):
        # (a deck copy and a treasure card's copy of one blade: both tried - a treasure card is used up, and their used
        # keys and stacking differ; plan_round's and the team's candidates alike)
        tcb = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tc=True)
        p = S.plan_round(S.State([stormblade(), tcb, lord()], [snake()] * 5, pips=3, fhp=[9000], me_first=True), sure(),
                         [S.Foe("A", 9000)], n=2, seed=1, budget_ms=5000)
        self.assertEqual(sorted(x["i"] for x in p["plays"] if x["name"] == "Stormblade"), [0, 1])
        st = S.State([lord()], [], pips=7, fhp=[9000], seat=6, me_first=True,
                     mates=[mate("Ann", 4, "blader", [stormblade(), tcb])])
        b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(), random.Random(1))
        self.assertEqual(sorted(i for i, _a in S._team_cands(b, 1, b.alive()) if i is not None), [0, 1])
        # (an item card's copy goes with the deck's - one play, as before v1.7.0 - unless the deck's can't go: on
        # already or used, the item card's is still tried)
        ilord = S.Card("Storm Lord", "damage", "storm", 7, heads={"storm": 1000}, tid=1, item=True)
        p = S.plan_round(S.State([lord(), ilord, snake(), ench()], [snake()] * 5, pips=7, fhp=[9000], me_first=True),
                         sure(), [S.Foe("A", 9000)], n=2, seed=1, budget_ms=5000)
        self.assertEqual([x["i"] for x in p["plays"] if x["name"] == "Storm Lord"], [0])
        iblade = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3, item=True)
        for kw in ({}, {"blades": [("Stormblade", {"storm": 35})]}, {"boosts_used": [("blade", "", {"storm": 35})]}):
            p = S.plan_round(S.State([stormblade(), iblade, lord()], [snake()] * 5, pips=3, fhp=[9000], me_first=True,
                                     **kw), sure(), [S.Foe("A", 9000)], n=2, seed=1, budget_ms=5000)
            self.assertEqual([x["i"] for x in p["plays"] if x["name"] == "Stormblade"], [1] if kw else [0], kw)
        st = S.State([lord()], [], pips=7, fhp=[9000], seat=6, me_first=True,
                     mates=[mate("Ann", 4, "blader", [stormblade(), iblade])])
        b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(), random.Random(1))
        self.assertEqual([i for i, _a in S._team_cands(b, 1, b.alive()) if i is not None], [0])


class BestDecksBoss(unittest.TestCase):
    def test_each_group_as_the_bot_plays_it(self):
        # (cardlogic 3 - boss: boost first, mobs: hit first: a recorded group with a boss played as a boss fight; the
        # deck's own Opts never changed)
        seen = []
        real = S.simulate

        def spy(cards, me, foes, opts=None, **kw):
            seen.append((tuple(f.name for f in foes), opts.boss, opts.cardlogic))
            return real(cards, me, foes, opts, **kw)
        o = S.Opts(cardlogic=3)
        cards = S.deck_cards({"cards": [hit(count=8), boost("blade", "Stormblade", 35, count=2)]})
        groups = [["Imp", "Imp"], ["Boss", "Imp"]]               # (the boss group last: the deck's Opts after it)
        with mock.patch.object(S, "simulate", spy):
            S.best_decks([("a", "A", cards, o)], groups,
                         lambda names: [S.Foe(nm, 2000, boss=nm == "Boss") for nm in names], sure(), n=10, seed=1)
        self.assertEqual(seen, [(("Imp", "Imp"), False, 3), (("Boss", "Imp"), True, 3)])
        self.assertIs(o.boss, False)


# ============================================================================ v1.8.0: the blade and trap copies the bot
# can't cast again thrown away (discardspent)
ON = S.Opts(discardspent=1)
SHARPEN = S.Card("Sharpened Blade", "sharpen")
POTENT = S.Card("Potent Trap", "potent")


def feint():
    return S.Card("Feint", "trap", "", 0, boosts={"all": 70}, tid=6)


class SpentCopies(unittest.TestCase):
    """discardspent (Autofarmer.ahk DiscardSpent - with discardunused, reboost off, a hitter): the deck's copies of a
    blade or trap slot past the casts it has left this battle thrown away, the weakest first, at most 3 a slot a round;
    one more kept while a Sharpen / Potent is in hand or in the deck; never a treasure or item card's copy. Opts' own
    default is off (an older AutoFarmer, which holds them): the tests here turn it on (ON) unless they say otherwise"""
    KEYS = ("won", "lost", "timeout", "rounds", "rounds_p90", "hp_left", "dmg_in", "first_kill")

    def test_opts(self):
        self.assertIs(S.Opts().discardspent, False)
        self.assertIs(S.Opts.of({"discardspent": "1"}).discardspent, True)
        self.assertIs(S.Opts.of({"discardspent": "1.0"}).discardspent, True)
        # (on only at exactly 1, as Stat("discardspent") == 1 - not _int's 1.5 -> 1)
        for v in ("2", "0.5", "0", "x", "1.5", "1.9", "-1", "nan", ""):
            self.assertIs(S.Opts.of({"discardspent": v}).discardspent, False, v)
        # (a mate's own: off - an older AutoFarmer's - till /plan gives it this bot's: SpentMates)
        self.assertIs(S.Mate("Ann", 5).opts.discardspent, False)

    def test_used_and_extra_copies(self):
        b = battle([stormblade(), stormblade(), lord()], pips=0, fhp=[9000], opts=ON)
        b.cast(b.hand[0])
        b.discard()
        self.assertEqual((names(b.hand), names(b.spent)), (["Storm Lord"], ["Stormblade", "Stormblade"]))
        b = battle([stormblade()] * 3 + [lord()], pips=0, fhp=[9000], opts=ON)
        b.discard()
        self.assertEqual(names(b.hand), ["Stormblade", "Storm Lord"])
        b = battle([trap(), trap(), lord()], pips=0, fhp=[9000], opts=ON)
        b.cast(b.hand[0])
        b.discard()
        self.assertEqual(names(b.hand), ["Storm Lord"])
        b = battle([stormblade(), stormblade(), lord()], pips=0, fhp=[9000])         # (off: held, as v1.7.0)
        b.cast(b.hand[0])
        b.discard()
        self.assertEqual(names(b.hand), ["Stormblade", "Storm Lord"])

    def test_cap_is_per_slot_and_counts_the_casts_left(self):
        # (two slots used, 3 copies each: 3 + 3 go - one a key a look, 3 looks; not 3 a round in all)
        b = battle([stormblade()] * 3 + [trap()] * 3 + [lord()], pips=0, fhp=[9000], opts=ON)
        b.boosts_used[("blade", "storm", "")] = {"storm": 35}
        b.boosts_used[("trap", "storm", "")] = {"storm": 30}
        b.discard()
        self.assertEqual(names(b.hand), ["Storm Lord"])
        # (5 unused copies, 1 cast left: 4 past it, 3 go this round - 2 stay; not min(5, 3) - 1)
        b = battle([stormblade()] * 5 + [lord()], pips=0, fhp=[9000], opts=ON)
        b.discard()
        self.assertEqual(names(b.hand).count("Stormblade"), 2)
        # (6 used copies: 3 go, 3 stay)
        b = battle([stormblade()] * 6 + [lord()], pips=0, fhp=[9000], opts=ON)
        b.boosts_used[("blade", "storm", "")] = {"storm": 35}
        b.discard()
        self.assertEqual((names(b.hand).count("Stormblade"), len(b.spent)), (3, 3))

    def test_sharpen_in_hand_keeps_one(self):
        b = battle([stormblade()] * 3 + [SHARPEN, lord()], pips=0, fhp=[9000], opts=ON)
        b.discard()
        self.assertEqual(names(b.hand).count("Stormblade"), 2)
        b = battle([trap()] * 3 + [SHARPEN, lord()], pips=0, fhp=[9000], opts=ON)
        b.discard()
        self.assertEqual(names(b.hand).count("Storm Trap"), 1)              # (a Sharpen keeps no trap)
        b = battle([trap()] * 3 + [POTENT, lord()], pips=0, fhp=[9000], opts=ON)
        b.discard()
        self.assertEqual(names(b.hand).count("Storm Trap"), 2)
        # (a treasure card's Sharpen in hand counts too - FindCards' sharpen, any copy; it never counts as one to come)
        b = battle([stormblade()] * 3 + [S.Card("Sharpened Blade", "sharpen", tc=True), lord()], pips=0, fhp=[9000],
                   opts=ON)
        b.discard()
        self.assertEqual(names(b.hand).count("Stormblade"), 2)

    def test_sharpen_still_to_come_keeps_one(self):
        # (the deck holds one - the bot's /deckkinds count, less its sharpened casts (none here) - wherever it is now:
        # the draw pile, or the spent pile (cast, or thrown away); not hand + draw pile only)
        b = battle([stormblade()] * 3 + [lord()], pile=[SHARPEN] * 3, pips=0, fhp=[9000], opts=ON)
        b.discard()
        self.assertEqual(names(b.hand).count("Stormblade"), 2)
        b = battle([stormblade()] * 3 + [lord()], pips=0, fhp=[9000], opts=ON)
        b.spent.append(SHARPEN)
        b.discard()
        self.assertEqual(names(b.hand).count("Stormblade"), 2)
        # (used and the deck still holds a Sharpen: the sharpened cast left - 1 kept)
        b = battle([stormblade()] * 3 + [lord()], pile=[SHARPEN], pips=0, fhp=[9000], opts=ON)
        b.boosts_used[("blade", "storm", "")] = {"storm": 35}
        b.discard()
        self.assertEqual(names(b.hand).count("Stormblade"), 1)
        # (none in the deck: 1; a treasure card's is the treasure pile's - never dealt, never counted (Draw.ahk draws
        # only an enchant for a kill); a Potent keeps a trap, not a blade; an item card's counts - a pet's Sharpened
        # Blade)
        tcs = S.Card("Sharpened Blade", "sharpen", tc=True)
        pet = S.Card("Sharpened Blade", "sharpen", item=True)
        for pile, want in (([], 1), ([tcs], 1), ([POTENT], 1), ([pet], 2)):
            b = battle([stormblade()] * 3 + [lord()], pile=pile, pips=0, fhp=[9000], opts=ON)
            b.discard()
            self.assertEqual(names(b.hand).count("Stormblade"), want, pile)
        b = battle([trap()] * 3 + [lord()], pile=[POTENT], pips=0, fhp=[9000], opts=ON)
        b.discard()
        self.assertEqual(names(b.hand).count("Storm Trap"), 2)

    def test_weakest_by_its_percent_first(self):
        for strong, weak in ((40, 35), (30, 35)):
            tb = S.Card("Thunderblade", "blade", "storm", 0, boosts={"storm": strong})
            for hand in ([tb, stormblade(), lord()], [stormblade(), tb, lord()]):
                b = battle(hand, pips=0, fhp=[9000], opts=ON)
                b.discard()
                self.assertEqual(names(b.spent), ["Stormblade" if strong > weak else "Thunderblade"], (strong, hand))
        # (of equal ones the first in hand - BoostMemDiscard's leftmost)
        tb = S.Card("Thunderblade", "blade", "storm", 0, boosts={"storm": 35})
        for hand, first in (([tb, stormblade(), lord()], "Thunderblade"), ([stormblade(), tb, lord()], "Stormblade")):
            b = battle(hand, pips=0, fhp=[9000], opts=ON)
            b.discard()
            self.assertEqual(names(b.spent), [first])

    def test_every_school_ones_count(self):
        # (Feint - all:70 - boosts every school: the search always looks for it)
        b = battle([feint()] * 3 + [lord()], pips=0, fhp=[9000], opts=ON)
        b.discard()
        self.assertEqual(names(b.hand).count("Feint"), 1)

    def test_never_a_treasure_or_item_copy(self):
        tcb = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3, tc=True)
        pet = S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tid=3, item=True)
        b = battle([tcb, tcb, pet, pet, stormblade(), lord()], pips=0, fhp=[9000], opts=ON)
        b.cast(b.hand[4])
        b.cast(b.hand[0])
        b.cast(b.hand[1])
        b.discard()
        self.assertEqual([(c.tc, c.item) for c in b.hand if c.kind == "blade"], [(True, False), (False, True)])

    def test_only_what_the_search_looks_for(self):
        fb = S.Card("Fireblade", "blade", "fire", 0, boosts={"fire": 35})
        cat = S.Card("Fire Cat", "damage", "fire", 1, heads={"fire": 100})
        b = battle([fb, fb, fb, lord()], pile=[cat], pips=0, fhp=[9000], opts=ON)
        b.discard()
        self.assertEqual(names(b.hand).count("Fireblade"), 3)
        b = battle([fb, fb, fb, cat], pips=0, fhp=[9000], opts=ON)
        b.discard()
        self.assertEqual(names(b.hand).count("Fireblade"), 1)

    def test_gates(self):
        for o in (S.Opts(discardspent=1, reboost=1), S.Opts(discardspent=1, discardunused=0), S.Opts(discardspent=2)):
            b = battle([stormblade()] * 4 + [lord()], pips=0, fhp=[9000], opts=o)
            b.discard()
            self.assertEqual(len(b.hand), 5)
        b = battle([stormblade()] * 4 + [lord()], pips=0, fhp=[9000], opts=S.Opts(discardspent=1, useblades=0,
                                                                                  discardmax=1))
        b.discard()
        self.assertEqual(names(b.hand).count("Stormblade"), 3)                 # (switched off: _useless's, discardmax)
        # (a blader in the planner - from_state: simulate() always plays a hitter)
        st = S.State([stormblade()] * 3, [], pips=0, fhp=[9000], seat=4, me_first=True,
                     mates=[mate("Hit", 5, "hitter", [lord()], pips=7)])
        b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(role="blader", discardspent=1),
                                 random.Random(1))
        b.discard()
        self.assertEqual(len(b.hand), 3)
        # (simulate() always plays a hitter - Opts.role is from_state's: the rule runs there whatever role says)
        deck = S.deck_cards({"cards": [hit(count=8), boost("blade", "Stormblade", 35, count=6),
                                       boost("trap", "Storm Trap", 30, count=6)]})
        boss = S.Foe("Boss", 6000, spells=[("Hit", 1.0, {"pips": 2, "min": 150, "max": 200, "accuracy": 100})],
                     boss=True)
        args = (deck, sure(damage=40), [boss])
        on = S.simulate(*args, S.Opts(role="blader", discardspent=1), n=60, seed=3)
        self.assertEqual(on, S.simulate(*args, ON, n=60, seed=3))
        self.assertNotEqual(on, S.simulate(*args, S.Opts(role="blader"), n=60, seed=3))

    def test_a_hitter_mate_by_its_opts(self):
        # (the team model: a hitter mate holding 3 copies throws 2 at its own fresh round's discards with discardspent
        # on - /plan gives it this bot's, a Blader's or Healer's sent 0 read as on: its role's, not the party's -, keeps
        # them with it off - Mate's own default)
        for on, want in ((True, 1), (False, 3)):
            m = mate("Hit", 5, "hitter", [stormblade()] * 3 + [lord()], pips=7)
            m.opts.discardspent = on
            st = S.State([lord()], [], pips=0, fhp=[9000], seat=4, me_first=True, mates=[m])
            b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(role="blader", discardspent=1),
                                     random.Random(1))
            k = next(i for i in range(len(b.side)) if b.side[i] is not None and getattr(b.side[i], "name", "") == "Hit")
            b._swap(k)
            b.discard()
            self.assertEqual(names(b.hand).count("Stormblade"), want, on)

    def test_no_random_number(self):
        b = battle([stormblade()] * 4 + [lord()], pile=[SHARPEN], pips=0, fhp=[9000], opts=ON)
        before = b.rng.getstate()
        b.discard()
        self.assertEqual(b.rng.getstate(), before)

    def test_pinned(self):
        # (ZeroEffect's mixed deck and timeout deck and the treasure-side fixture's main deck, discardspent on - their
        # own pins, with it off, stay as they were)
        cards = S.deck_cards({"cards": [hit(count=8), hit("Thunder Snake", 2, 150, count=6),
                                        boost("blade", "Stormblade", 35, count=4),
                                        boost("trap", "Storm Trap", 30, count=4)]})
        r = S.simulate(cards, S.Me("storm", 2500, damage=40),
                       [biter("Ogre", 3000, 150, 200), biter("Imp", 800, 60, 80, passes=True)], ON, n=120, seed=11)
        self.assertEqual(tuple(r[k] for k in self.KEYS),
                         (0.26666666666666666, 0.7333333333333333, 0.0, 15.0, 16, 16.0, 188, 10))
        self.assertEqual(r["casts"],
                         {"Storm Lord": 3.23, "Stormblade": 0.96, "Storm Trap": 0.95, "Thunder Snake": 0.03})
        cards = S.deck_cards({"cards": [hit("Thunder Snake", 2, 300, count=10),
                                        boost("blade", "Stormblade", 35, count=2)]})
        r = S.simulate(cards, S.Me("storm", 3000), [biter("Tank", 2600, 50, 60)], ON, n=100, seed=3)
        self.assertEqual(tuple(r[k] for k in self.KEYS), (0.05, 0.0, 0.95, 16, 16, 73.7, 54, 16))
        self.assertEqual(r["casts"], {"Thunder Snake": 9.99, "Stormblade": 1.0})
        # (the treasure-side fixture's main deck against the fire Tank - its treasure side changes nothing)
        main = [hit(count=6), hit("Thunder Snake", 2, 150, count=10), boost("blade", "Stormblade", 35, count=4)]
        tside = [{"name": "Stun", "display": "Stun", "kind": "stun", "count": 6, "side": "treasure"},
                 {"name": "Weakness", "display": "Weakness", "kind": "weakness", "count": 4, "side": "treasure"}]
        tank = S.Foe("Tank", 3000, "fire", spells=[(None, 0.5, None),
                                                   ("Bite", 1.0, {"pips": 2, "min": 200, "max": 250, "accuracy": 85,
                                                                  "type": "Damage"})])
        r = S.simulate(S.deck_cards({"cards": main + tside}), S.Me("storm", 3000), [tank], ON, n=120, seed=5)
        self.assertEqual(tuple(r[k] for k in self.KEYS), (0.925, 0.025, 0.05, 19, 22, 38.7, 97, 19))
        self.assertEqual(r["casts"], {"Storm Lord": 4.61, "Thunder Snake": 2.83, "Stormblade": 1.0})
        self.assertEqual(r, S.simulate(S.deck_cards({"cards": main}), S.Me("storm", 3000), [tank], ON, n=120, seed=5))

    def test_single_copies_unchanged(self):
        cards = S.deck_cards({"cards": [hit(count=6), hit("Thunder Snake", 2, 150, count=6),
                                        boost("blade", "Stormblade", 35), boost("trap", "Storm Trap", 30)]})
        args = (cards, S.Me("storm", 2500, damage=40), [biter("Ogre", 3000, 150, 200)])
        self.assertEqual(S.simulate(*args, ON, n=120, seed=11), S.simulate(*args, S.Opts(), n=120, seed=11))

    def test_thrown_beats_held(self):
        foe = S.Foe("Boss", 6000, spells=[("Hit", 1.0, {"pips": 2, "min": 150, "max": 200, "accuracy": 100})],
                    boss=True)
        deck = S.deck_cards({"cards": [hit(count=8), boost("blade", "Stormblade", 35, count=6),
                                       boost("trap", "Storm Trap", 30, count=6)]})
        held = S.simulate(deck, sure(damage=40), [foe], S.Opts(), n=200, seed=7)
        spent = S.simulate(deck, sure(damage=40), [foe], ON, n=200, seed=7)
        self.assertEqual((held["won"], spent["won"]), (0.875, 1.0))
        self.assertEqual(S.simulate(deck, sure(damage=40), [foe], S.Opts(reboost=1, discardspent=1), n=200, seed=7),
                         S.simulate(deck, sure(damage=40), [foe], S.Opts(reboost=1), n=200, seed=7))

    def test_thrown_beats_held_paired(self):
        # (each battle on its own seed in both modes - the same dice battle by battle, not one stream that drifts
        # apart at the first discard: the 6+6 deck against the 6000 boss, the generic hitter - section 1's A)
        deck = S.deck_cards({"cards": [hit(count=8), boost("blade", "Stormblade", 35, count=6),
                                       boost("trap", "Storm Trap", 30, count=6)]})
        me, foes = S.Me("storm", 3500, damage=60), [S.Foe("Boss", 6000, boss=True)]
        w = {o: [S.simulate(deck, me, foes, S.Opts(discardspent=o), n=1, seed=300000 + i)["won"] for i in range(40)]
             for o in (0, 1)}
        self.assertEqual((sum(w[0]), sum(w[1]), sum(a < b for a, b in zip(w[0], w[1])),
                          sum(a > b for a, b in zip(w[0], w[1]))), (23.0, 38.0, 15, 0))

    def test_main_plays_it_on(self):
        seen = []
        real = S.simulate

        def spy(cards, me, foes, opts=None, **kw):
            seen.append(opts)
            return real(cards, me, foes, opts, **kw)
        deck = {"cards": [hit(count=4), boost("blade", "Stormblade", 35, count=3)]}
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "deck.json")
            with open(p, "w", encoding="utf-8") as fh:
                json.dump(deck, fh)
            out = io.StringIO()
            with mock.patch.object(S, "simulate", spy), contextlib.redirect_stdout(out):
                self.assertEqual(S.main(["--deck", p, "--foe", "Rat:500", "-n", "5", "--seed", "1"]), 0)
        self.assertTrue(out.getvalue().startswith("sim|"), out.getvalue()[:200])
        self.assertEqual([(o.discardspent, o.boss) for o in seen], [(True, False)])


# ============================================================================ v1.9.0: Sharpen and Potent played the
# bot's way (UseBlade / UseTrap's sharpened cast, DiscardSpare's two rules, the planner's used1=)
def tcb():
    return S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, tc=True)


def pet():
    return S.Card("Stormblade", "blade", "storm", 0, boosts={"storm": 35}, item=True)


TSH = S.Card("Sharpened Blade", "sharpen", tc=True)
U = {("blade", "storm", ""): {"storm": 35}, ("blade", "storm", "+"): {"storm": 35}}


class SharpenPotent(unittest.TestCase):
    """the first Sharpen / Potent in hand goes on the blade / trap the chain casts while its sharpened cast is free (no
    pip, no turn, the card's +N); a deck copy's two casts a battle (plain and sharpened), a treasure card's copy one
    either way, an item card's copy never sharpened; DiscardSpare's both-casts and spare-Sharpen rules; the planner's
    sharpened flags (used1=, else inferred from the '+' blades on)"""

    def test_sharpened_then_plain_then_none(self):
        b = battle([stormblade()] * 3 + [SHARPEN, lord()], pips=0, fhp=[9000])
        c = b.pick_boost(lord())
        self.assertIs(c, b.hand[0])
        self.assertTrue(b.cast(c))
        self.assertEqual(b.blades, [("Stormblade+", {"storm": 45.0})])
        self.assertEqual(b.boosts_used, {("blade", "storm", "+"): {"storm": 35}})
        self.assertEqual(b.casts, {"Stormblade": 1, "Sharpened Blade": 1})
        self.assertEqual(names(b.spent), ["Stormblade", "Sharpened Blade"])
        self.assertEqual(S._plannable(b.hand[0], b.opts, b), "")          # (its plain cast is still free)
        self.assertTrue(b.cast(b.pick_boost(lord())))
        self.assertEqual(b.blades, [("Stormblade+", {"storm": 45.0}), ("Stormblade", {"storm": 35})])
        self.assertIsNone(b.pick_boost(lord()))
        self.assertEqual(S._plannable(b.hand[0], b.opts, b), "on already")

    def test_plain_first_then_sharpened(self):
        b = battle([stormblade(), stormblade(), lord()], pile=[], pips=0, fhp=[9000])
        b.cast(b.hand[0])
        self.assertIsNone(b.pick_boost(lord()))
        b.hand.append(S.Card("Sharpened Blade", "sharpen", value="+15%"))      # (its own number: +15)
        self.assertEqual(S._plannable(b.hand[0], b.opts, b), "")
        b.cast(b.pick_boost(lord()))
        self.assertEqual(b.blades, [("Stormblade", {"storm": 35}), ("Stormblade+", {"storm": 50.0})])

    def test_potent_trap(self):
        b = battle([trap(), POTENT, lord()], pips=0, fhp=[9000])
        b.cast(b.hand[0])
        self.assertEqual(b.traps, [[{"storm": 40.0}]])
        self.assertEqual(list(b.boosts_used), [("trap", "storm", "+")])
        b = battle([trap(), SHARPEN, lord()], pips=0, fhp=[9000])                # (a Sharpen goes on no trap)
        b.cast(b.hand[0])
        self.assertEqual(b.traps, [[{"storm": 30}]])
        self.assertIn("Sharpened Blade", names(b.hand))

    def test_feint_and_bladestorm(self):
        # (no exclusion: the bot's UseTrap / UseBlade puts one on Feint and Bladestorm too)
        b = battle([S.Card("Feint", "trap", boosts={"all": 70}), POTENT, lord()], pips=0, fhp=[9000])
        b.cast(b.hand[0])
        self.assertEqual(b.traps, [[{"all": 80.0}]])
        self.assertEqual(list(b.boosts_used), [("trap", "all/70", "+")])
        b = battle([S.Card("Bladestorm", "blade", boosts={"all": 20}), SHARPEN, lord()], pips=0, fhp=[9000])
        b.cast(b.hand[0])
        self.assertEqual(b.blades, [("Bladestorm+", {"all": 30.0})])
        self.assertEqual(list(b.boosts_used), [("blade", "all/20", "+")])

    def test_copies(self):
        # (an item card's copy is never sharpened - the Sharpen stays; a treasure card's copy takes it, keeps its one
        # flag, and neither goes to the spent pile)
        b = battle([pet(), SHARPEN, lord()], pips=0, fhp=[9000])
        b.cast(b.hand[0])
        self.assertEqual(b.blades, [("Stormblade@item", {"storm": 35})])
        self.assertEqual(names(b.hand), ["Sharpened Blade", "Storm Lord"])
        b = battle([tcb(), TSH, lord()], pips=0, fhp=[9000])
        b.cast(b.hand[0])
        self.assertEqual(b.blades, [("Stormblade@tc+", {"storm": 45.0})])
        self.assertEqual(b.spent, [])
        self.assertEqual(list(b.boosts_used), [("blade", "storm", "tc")])

    def test_moved_copy_goes_plain(self):
        # (KillCalc.ahk BoostCopyPick: the slot's first copy in hand - the one Find finds - can't go, so UseBlade moves
        # to another copy that can go plain and casts it plain, never sharpened (!ubMoved); none can go plain: nothing)
        P = {"storm": 35}
        # (a pet's copy first, its flag set; a fresh deck copy after it: cast plain, the Sharpen kept)
        b = battle([pet(), stormblade(), SHARPEN, lord()], pips=0, fhp=[9000])
        b.boosts_used = {("blade", "storm", "item"): P}
        self.assertIsNone(b._sharp_for(b.hand[1]))
        self.assertEqual([S._plannable(c, b.opts, b) for c in b.hand[:2]], ["used this battle", ""])
        c = b.pick_boost(lord())
        self.assertIs(c, b.hand[1])
        self.assertTrue(b.cast(c))
        self.assertEqual(b.blades, [("Stormblade", P)])
        self.assertEqual(names(b.hand), ["Stormblade", "Sharpened Blade", "Storm Lord"])
        self.assertEqual(sorted(b.boosts_used), [("blade", "storm", ""), ("blade", "storm", "item")])
        self.assertNotIn("Sharpened Blade", b.casts)
        # (the deck copy's plain flag gone too: no copy can go plain - nothing is cast)
        b = battle([pet(), stormblade(), SHARPEN, lord()], pips=0, fhp=[9000])
        b.boosts_used = {("blade", "storm", "item"): P, ("blade", "storm", ""): P}
        self.assertIsNone(b.pick_boost(lord()))
        self.assertEqual(S._plannable(b.hand[1], b.opts, b), "used this battle")
        # (a deck copy first, both its casts gone; a treasure card's copy after it: cast plain)
        b = battle([stormblade(), tcb(), SHARPEN, lord()], pips=0, fhp=[9000])
        b.boosts_used = dict(U)
        c = b.pick_boost(lord())
        self.assertIs(c, b.hand[1])
        self.assertTrue(b.cast(c))
        self.assertEqual(b.blades, [("Stormblade@tc", P)])
        self.assertEqual(names(b.hand), ["Stormblade", "Sharpened Blade", "Storm Lord"])
        self.assertIn(("blade", "storm", "tc"), b.boosts_used)
        # (the deck copy first and fresh, the pet's after it with its flag set: the first copy goes sharpened - looked
        # at before it leaves the hand)
        b = battle([stormblade(), pet(), SHARPEN, lord()], pips=0, fhp=[9000])
        b.boosts_used = {("blade", "storm", "item"): P}
        self.assertTrue(b.cast(b.hand[0]))
        self.assertEqual(b.blades, [("Stormblade+", {"storm": 45.0})])
        self.assertEqual(names(b.hand), ["Stormblade", "Storm Lord"])

    def test_first_sharpen_in_hand(self):
        # (Find's first match - any copy: the treasure card's, used up)
        b = battle([TSH, SHARPEN, stormblade(), lord()], pips=0, fhp=[9000])
        b.cast(b.hand[2])
        self.assertEqual(names(b.hand), ["Sharpened Blade", "Storm Lord"])
        self.assertFalse(b.hand[0].tc)
        self.assertEqual(names(b.spent), ["Stormblade"])
        self.assertEqual(b.casts["Sharpened Blade"], 1)

    def test_fizzle_and_no_random_number(self):
        st = S.State([stormblade(), SHARPEN, lord()], [], fhp=[9000], me_first=True)
        b = S._Battle.from_state(st, sure(accuracy=-200), [S.Foe("A", 9000)], S.Opts(), random.Random(1))
        self.assertFalse(b.cast(b.hand[0]))                 # (a fizzle loses both and keeps the flag)
        self.assertEqual(b.blades, [])
        self.assertEqual(names(b.hand), ["Storm Lord"])
        self.assertEqual(list(b.boosts_used), [("blade", "storm", "+")])

        def after(hand):
            b = battle(hand, pips=0, fhp=[9000])
            b.cast(b.hand[0])
            return b.rng.getstate()
        self.assertEqual(after([stormblade(), lord()]), after([stormblade(), SHARPEN, lord()]))

    def test_unpaid(self):
        b = battle([S.Card("Stormblade", "blade", "storm", 2, boosts={"storm": 35}), SHARPEN, lord()], pips=0,
                   fhp=[9000])
        self.assertFalse(b.cast(b.hand[0]))
        self.assertEqual(names(b.hand), ["Sharpened Blade", "Storm Lord"])
        self.assertEqual(b.boosts_used, {})
        self.assertNotIn("Sharpened Blade", b.casts)

    def test_reboost_and_reshuffle_free_it(self):
        b = battle([stormblade(), SHARPEN, lord()], pips=7, fhp=[90000], opts=S.Opts(reboost=1))
        b.cast(b.hand[0])
        self.assertEqual(list(b.boosts_used), [("blade", "storm", "+")])
        b.cast(b.hand[0])
        self.assertEqual(b.boosts_used, {})
        b = battle([stormblade(), SHARPEN, resh(), lord()], pips=0, fhp=[9000])
        b.cast(b.hand[0])
        self.assertEqual(list(b.boosts_used), [("blade", "storm", "+")])
        b.cast(b.hand[0])
        self.assertEqual(b.boosts_used, {})

    def test_kept_not_thrown(self):
        b = battle([SHARPEN, POTENT, lord()], pips=0, fhp=[9000])
        b.discard()
        self.assertEqual(names(b.hand), ["Sharpened Blade", "Potent Trap", "Storm Lord"])
        b = battle([SHARPEN, POTENT, lord()], pips=0, fhp=[9000], opts=S.Opts(useblades=0))
        b.discard()
        self.assertEqual(names(b.hand), ["Potent Trap", "Storm Lord"])
        b = battle([SHARPEN, POTENT, lord()], pips=0, fhp=[9000], opts=S.Opts(usetraps=0))
        b.discard()
        self.assertEqual(names(b.hand), ["Sharpened Blade", "Storm Lord"])
        for o, want in ((S.Opts(), ("goes on a blade", "goes on a trap")),
                        (S.Opts(useblades=0), ("switched off", "goes on a trap")),
                        (S.Opts(usetraps=0), ("goes on a blade", "switched off"))):
            b = battle([SHARPEN, POTENT, lord()], pips=0, fhp=[9000], opts=o)
            self.assertEqual((S._plannable(SHARPEN, o, b), S._plannable(POTENT, o, b)), want)

    def test_spent_countdown_and_gate(self):
        # (the deck's one Sharpen spent on this slot: none still to come - all 3 copies go)
        b = battle([stormblade()] * 3 + [lord()], pile=[SHARPEN], pips=0, fhp=[9000], opts=ON)
        b.boosts_used = dict(U)
        b.discard()
        self.assertEqual(names(b.hand).count("Stormblade"), 0)
        # (another slot sharpened: the count goes down; two in the deck, or a treasure card drawn - DrawsBattle -: one
        # still to come, the storm slot's sharpened cast free - 1 kept)
        for pile, draws, want in (([SHARPEN], 0, 0), ([SHARPEN, SHARPEN], 0, 1), ([SHARPEN], 1, 1)):
            b = battle([stormblade()] * 3 + [lord()], pile=pile, pips=0, fhp=[9000], opts=ON, draws=draws)
            b.boosts_used = {("blade", "storm", ""): {"storm": 35}, ("blade", "fire", "+"): {"fire": 35}}
            b.discard()
            self.assertEqual(names(b.hand).count("Stormblade"), want, (pile, draws))

    def test_spare_sharpen(self):
        fb = S.Card("Fireblade", "blade", "fire", 0, boosts={"fire": 35})
        for o in (S.Opts(), S.Opts(discardunused=0), ON):
            b = battle([SHARPEN, SHARPEN, lord()], pips=0, fhp=[9000], opts=o)
            b.discard()
            self.assertEqual(names(b.hand), ["Sharpened Blade", "Sharpened Blade", "Storm Lord"], o.discardunused)
            b.boosts_used[("blade", "storm", "+")] = {"storm": 35}
            b.discard()
            self.assertEqual(names(b.hand), ["Storm Lord"], o.discardunused)
            # (no blade in hand the search looks for - the Fireblade fits no hit: thrown)
            b = battle([SHARPEN, fb, lord()], pips=0, fhp=[9000], opts=o)
            b.boosts_used[("blade", "storm", "+")] = {"storm": 35}
            b.discard()
            self.assertNotIn("Sharpened Blade", names(b.hand), o.discardunused)
            # (a Stormblade in hand whose sharpened cast is free: kept)
            b = battle([SHARPEN, stormblade(), lord()], pips=0, fhp=[9000], opts=o)
            b.boosts_used[("blade", "fire", "+")] = {"fire": 35}
            b.discard()
            self.assertIn("Sharpened Blade", names(b.hand), o.discardunused)
        # (Find's first match: a treasure card's - nothing goes; it stops there)
        b = battle([TSH, SHARPEN, lord()], pips=0, fhp=[9000])
        b.boosts_used[("blade", "storm", "+")] = {"storm": 35}
        b.discard()
        self.assertEqual(names(b.hand), ["Sharpened Blade", "Sharpened Blade", "Storm Lord"])
        b = battle([SHARPEN, TSH, SHARPEN, lord()], pips=0, fhp=[9000])
        b.boosts_used[("blade", "storm", "+")] = {"storm": 35}
        b.discard()
        self.assertEqual([(c.name, c.tc) for c in b.hand],
                         [("Sharpened Blade", True), ("Sharpened Blade", False), ("Storm Lord", False)])
        # (a support: BoostMisfitDiscard, not this; no spare-Potent rule)
        b = battle([SHARPEN, lord()], pips=0, fhp=[9000], opts=S.Opts(role="blader"))
        b.boosts_used[("blade", "storm", "+")] = {"storm": 35}
        b.discard()
        self.assertIn("Sharpened Blade", names(b.hand))
        b = battle([POTENT, lord()], pips=0, fhp=[9000])
        b.boosts_used[("trap", "storm", "+")] = {"storm": 30}
        b.discard()
        self.assertIn("Potent Trap", names(b.hand))

    def test_both_casts(self):
        # (both casts went, no copy can go: the first copy thrown, 3 a round - discardunused or not, reboost or not)
        for o in (S.Opts(), S.Opts(discardunused=0), S.Opts(reboost=1, discardspent=1)):
            b = battle([stormblade()] * 4 + [lord()], pips=0, fhp=[9000], opts=o)
            b.boosts_used = dict(U)
            b.discard()
            self.assertEqual(names(b.hand).count("Stormblade"), 1, (o.discardunused, o.reboost))
        o = S.Opts(discardunused=0)
        # (a treasure card's copy with its flag free can still go: the slot's copies kept)
        b = battle([stormblade()] * 2 + [tcb(), lord()], pips=0, fhp=[9000], opts=o)
        b.boosts_used = dict(U)
        b.discard()
        self.assertEqual(names(b.hand).count("Stormblade"), 3)
        # (its flag set too: the first copy in hand - a treasure card's stops it there)
        ut = dict(U)
        ut[("blade", "storm", "tc")] = {"storm": 35}
        for hand, gone in (([tcb(), stormblade(), stormblade(), lord()], 0),
                           ([stormblade(), tcb(), stormblade(), lord()], 1)):
            b = battle(hand, pips=0, fhp=[9000], opts=o)
            b.boosts_used = dict(ut)
            b.discard()
            self.assertEqual(len(b.spent), gone, names(hand))
        # (DiscardSpent ran - discardspent on: it settles it; off: the rule, stopped at the treasure card's copy)
        b = battle([tcb()] + [stormblade()] * 3 + [lord()], pips=0, fhp=[9000], opts=ON)
        b.boosts_used = dict(ut)
        b.discard()
        self.assertEqual([(c.name, c.tc) for c in b.hand], [("Stormblade", True), ("Storm Lord", False)])
        b = battle([tcb()] + [stormblade()] * 3 + [lord()], pips=0, fhp=[9000])
        b.boosts_used = dict(ut)
        b.discard()
        self.assertEqual(names(b.hand).count("Stormblade"), 4)
        # (no '+' key - the plain flag only: nothing, as before v1.9.0)
        b = battle([stormblade()] * 4 + [lord()], pips=0, fhp=[9000], opts=o)
        b.boosts_used = {("blade", "storm", ""): {"storm": 35}}
        b.discard()
        self.assertEqual(names(b.hand).count("Stormblade"), 4)

    def test_reboost_keeps_the_copies(self):
        # (v1.9.1 - this AutoFarmer, reboostkeep:1 - Autofarmer.ahk ReboostKeepRole: with reboost on the next hit a
        # blade fits frees both its casts - KillCalc.ahk ConsumeBoosts -, so its copies stay in hand; no random number
        # drawn. discardunused, discardspent: the same - DiscardSpent never runs under reboost)
        for o in (S.Opts(reboost=1, reboostkeep=1), S.Opts(reboost=1, reboostkeep=1, discardunused=0),
                  S.Opts(reboost=1, reboostkeep=1, discardspent=1)):
            b = battle([stormblade()] * 4 + [lord()], pips=0, fhp=[9000], opts=o)
            b.boosts_used = dict(U)
            st = b.rng.getstate()
            b.discard()
            self.assertEqual((names(b.hand).count("Stormblade"), b.spent), (4, []), (o.discardunused, o.discardspent))
            self.assertEqual(b.rng.getstate(), st)
        # (not sent - an older AutoFarmer, which still throws them under reboost -, reboost off, or either at another
        # number: the both-casts rule, as before)
        for o in (S.Opts(reboost=1), S.Opts(reboostkeep=1), S.Opts(reboost=2, reboostkeep=1),
                  S.Opts(reboost=1, reboostkeep=2), S.Opts(reboost=1, reboostkeep=0.5)):
            b = battle([stormblade()] * 4 + [lord()], pips=0, fhp=[9000], opts=o)
            b.boosts_used = dict(U)
            b.discard()
            self.assertEqual(names(b.hand).count("Stormblade"), 1, (o.reboost, o.reboostkeep))
        rk = S.Opts(reboost=1, reboostkeep=1)
        # (the spare-Sharpen rule still runs: no blade in hand can take one - the Sharpen goes, the blades stay)
        b = battle([SHARPEN, stormblade(), stormblade(), lord()], pips=0, fhp=[9000], opts=rk)
        b.boosts_used = dict(U)
        b.discard()
        self.assertEqual(names(b.hand), ["Stormblade", "Stormblade", "Storm Lord"])
        # (a support: its DiscardSpare is BoostMisfitDiscard - nothing here, as before)
        b = battle([stormblade()] * 4 + [lord()], pips=0, fhp=[9000],
                   opts=S.Opts(role="blader", reboost=1, reboostkeep=1))
        b.boosts_used = dict(U)
        b.discard()
        self.assertEqual(names(b.hand).count("Stormblade"), 4)
        # (the whole turn: sharpened, plain, the copy kept - an older AutoFarmer's thrown -, the hit frees both casts,
        # the kept copy goes again)
        for o, kept in ((rk, 1), (S.Opts(reboost=1), 0)):
            b = battle([stormblade()] * 3 + [SHARPEN, lord()], pips=7, fhp=[9000], opts=o)
            self.assertTrue(b.cast(b.pick_boost(lord())))
            self.assertTrue(b.cast(b.pick_boost(lord())))
            self.assertEqual(sorted(b.boosts_used), [("blade", "storm", ""), ("blade", "storm", "+")])
            b.discard()
            self.assertEqual(names(b.hand).count("Stormblade"), kept, o.reboostkeep)
            self.assertTrue(b.cast(b.hand[-1]))                              # (Storm Lord: both casts free again)
            self.assertEqual(b.boosts_used, {})
            c = b.pick_boost(lord())
            self.assertEqual(c is not None and c.name, "Stormblade" if kept else False, o.reboostkeep)

    def test_opts_reboostkeep(self):
        # (v1.9.1: on only at exactly 1, like discardspent - not sent, junk, NaN: off; never raises)
        self.assertIs(S.Opts().reboostkeep, False)
        self.assertIn("reboostkeep", S.Opts.KEYS)
        for v, want in (("1", True), ("1.0", True), ("0", False), ("2", False), ("0.5", False), ("x", False),
                        ("nan", False), ("inf", False), ("", False)):
            self.assertIs(S.Opts.of({"reboostkeep": v}).reboostkeep, want, v)
        self.assertIs(S.Opts.of({}).reboostkeep, False)

    def test_planner_state(self):
        blades = S.bot_blades([("storm/blade+", {"storm": 45.0})], [stormblade(), lord()])
        self.assertEqual(blades, [("Stormblade+", {"storm": 45.0})])
        # (no used= - an older AutoFarmer: the '+' blade on as its sharpened cast, only with a Sharpen among the cards)
        b = battle([stormblade(), SHARPEN, lord()], blades=blades)
        self.assertEqual(sorted(b.boosts_used), [("blade", "storm", "+")])
        self.assertEqual(S._plannable(b.hand[0], b.opts, b), "")
        self.assertIsNone(b._sharp_for(b.hand[0]))
        self.assertEqual(battle([stormblade(), lord()], blades=blades).boosts_used, {})
        # (used= given: as sent - vision.py adds the sharpened casts)
        self.assertEqual(battle([stormblade(), SHARPEN, lord()], blades=blades, boosts_used=[]).boosts_used, {})
        self.assertEqual(S.State([], boosts_used=[("blade", "+", {"storm": 35})]).boosts_used,
                         [("blade", "+", {"storm": 35.0})])

    def test_bot_sharpened(self):
        bal = S.Card("Balanceblade", "blade", "balance", 0, boosts={"all": 25})
        cards = [stormblade(), SHARPEN, tcb(), bal]
        keys = [("storm/blade+", {"storm": 45}), ("storm/blade", {"storm": 35}), ("storm/blade@tc+", {"storm": 45}),
                ("junk",), ("blade3+", {"all": 35}), ("x@pet+", {"storm": 45})]
        self.assertEqual(S.bot_sharpened(keys, cards, "blade"),
                         [("blade", "+", {"storm": 35}), ("blade", "tc", {"storm": 35}), ("blade", "+", {"all": 25})])
        self.assertEqual(S.bot_sharpened(keys, [stormblade(), tcb(), bal], "blade"), [])
        self.assertEqual(S.bot_sharpened([("storm/trap+", {"storm": 40})], [trap(), POTENT], "trap"),
                         [("trap", "+", {"storm": 30})])
        self.assertEqual(S.bot_sharpened(None, None, "blade"), [])
        self.assertEqual(S.bot_sharpened(keys, cards, "aura"), [])

    def test_plan_round_tries_both_copies(self):
        # (a Sharpen in hand: the deck copy goes sharpened, the item card's plain - tried apart)
        def plan(hand):
            st = S.State(hand, [lord()] * 5, fhp=[9000], me_first=True, pips=3)
            return st, S.plan_round(st, sure(), [S.Foe("A", 9000)], n=10, seed=1, budget_ms=5000)
        st, p = plan([pet(), stormblade(), SHARPEN, lord()])
        self.assertEqual(sorted(x["i"] for x in p["plays"] if x["name"] == "Stormblade"), [0, 1])
        self.assertTrue(next(x for x in p["plays"] if x["i"] == 1)["why"].startswith("with Sharpened Blade"), p)
        self.assertIn("1 card in hand not tried (goes on a blade)", p["why"])
        b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(), random.Random(1))
        self.assertEqual(S._team_cands(b, 0, b.alive()), [(None, None), (0, None), (1, None)])
        st, p = plan([pet(), stormblade(), lord()])
        self.assertEqual([x["i"] for x in p["plays"] if x["name"] == "Stormblade"], [0])
        b = S._Battle.from_state(st, sure(), [S.Foe("A", 9000)], S.Opts(), random.Random(1))
        self.assertEqual(S._team_cands(b, 0, b.alive()), [(None, None), (0, None)])

    def test_sharpen_deck_pinned(self):
        sh = {"name": "Sharpened Blade", "display": "Sharpened Blade", "kind": "sharpen", "school": "", "pips": 0,
              "value": "+10%", "count": 2, "side": "main"}
        deck = S.deck_cards({"cards": [hit(count=8), boost("blade", "Stormblade", 35, count=6),
                                       boost("trap", "Storm Trap", 30, count=6), sh,
                                       dict(sh, name="Potent Trap", display="Potent Trap", kind="potent")]})
        foe = S.Foe("Boss", 6000, spells=[("Hit", 1.0, {"pips": 2, "min": 150, "max": 200, "accuracy": 100})],
                    boss=True)
        keys = SpentCopies.KEYS

        def run(o):
            return S.simulate(deck, sure(damage=40), [foe], o, n=200, seed=7)
        r = run(S.Opts())
        self.assertEqual(tuple(r[k] for k in keys), (0.945, 0.0, 0.055, 16, 21, 49.8, 93, 16))
        self.assertEqual(r["casts"], {"Storm Lord": 3.12, "Storm Trap": 1.84, "Stormblade": 1.79, "Potent Trap": 0.88,
                                      "Sharpened Blade": 0.82})
        on = run(ON)
        self.assertEqual(tuple(on[k] for k in keys), (1.0, 0.0, 0.0, 15.0, 19, 52.6, 93, 15.0))
        self.assertEqual(list(on["casts"].items()), [("Storm Lord", 3.04), ("Storm Trap", 2.0), ("Stormblade", 1.99),
                                                     ("Potent Trap", 1.0), ("Sharpened Blade", 0.99)])
        rb = run(S.Opts(reboost=1))
        self.assertEqual(tuple(rb[k] for k in keys), (0.94, 0.0, 0.06, 11.0, 16, 62.0, 95, 11.0))
        self.assertEqual(run(S.Opts(discardunused=0)), r)
        # (HEAD v1.8.1 gave Opts() 0.88 / ON 1.0 in 21 / 22 rounds, discardunused 0 0.51)

    def test_sharpen_deck_reboostkeep_pinned(self):
        # (v1.9.1: test_sharpen_deck_pinned's deck - reboost with this AutoFarmer's reboostkeep: the blade's copies kept
        # for the cast after the hit; the marker alone, or with discardspent, changes nothing)
        sh = {"name": "Sharpened Blade", "display": "Sharpened Blade", "kind": "sharpen", "school": "", "pips": 0,
              "value": "+10%", "count": 2, "side": "main"}
        deck = S.deck_cards({"cards": [hit(count=8), boost("blade", "Stormblade", 35, count=6),
                                       boost("trap", "Storm Trap", 30, count=6), sh,
                                       dict(sh, name="Potent Trap", display="Potent Trap", kind="potent")]})
        foe = S.Foe("Boss", 6000, spells=[("Hit", 1.0, {"pips": 2, "min": 150, "max": 200, "accuracy": 100})],
                    boss=True)
        keys = SpentCopies.KEYS

        def run(o):
            return S.simulate(deck, sure(damage=40), [foe], o, n=200, seed=7)
        rk = run(S.Opts(reboost=1, reboostkeep=1))
        self.assertEqual(tuple(rk[k] for k in keys), (0.985, 0.0, 0.015, 12, 16, 61.0, 93, 12))
        self.assertEqual(rk["casts"], {"Storm Trap": 3.33, "Stormblade": 3.29, "Storm Lord": 2.44, "Potent Trap": 1.23,
                                       "Sharpened Blade": 1.05})
        self.assertEqual(run(S.Opts(reboost=1, reboostkeep=1, discardspent=1)), rk)
        self.assertEqual(run(S.Opts(reboost=1, reboostkeep=1, discardunused=0)), rk)
        self.assertEqual(run(S.Opts(reboostkeep=1)), run(S.Opts()))
        self.assertEqual(run(S.Opts(discardspent=1, reboostkeep=1)), run(ON))
        # (HEAD v1.9.0 - no reboostkeep: 0.94 in 16 rounds, Stormblade 2.69 a battle - test_sharpen_deck_pinned's rb)


if __name__ == "__main__":
    unittest.main()
