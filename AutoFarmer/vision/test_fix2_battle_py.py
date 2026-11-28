"""test_fix2_battle_py.py - the code review's (2026-11-27) battle simulator, recorder and Battles-tab fixes. Standard
library only: python -m unittest test_fix2_battle_py  (from AutoFarmer\\vision)

Pins: a blade, trap, aura, enchant or Sharpen with no accuracy known never misses - the school's accuracy for a hit and
a heal only (battlesim-2); enemies cast round 1 with 1-3 pips, enemies.py's START_PIPS (battlesim-3); an enemy's blades
boost and are used up only by a hit of their school (battlesim-5); a hit's deck copy stands for an item card's copy in
the plan, whichever is first in hand (battlesim-4); plan_team keeps to its budget and runs one pass when the time
fits too few rollouts for more (battlesim-1), and a later round's enemy with pips not known casts with 2-4 as before
(review 2.2); charms_now wears an absorb down by what it soaked - the hit after the target's resist -, not by the health
lost past it (battlerec-6), and a charm whose fact is a deck read's brief line fits every school (battlerec-2); a stranger's
name kept only hashed is still cut out of the bot's lines (battlerec-4); back_scan finds a battle in progress at a
circle whose number ended earlier in the window (battlerec-5); a battle is written once - a checkpoint's pending one
already in its day file, or one queued twice, not again; current.json after the write (battlerec-3); the game's own
log rotation is followed on - a new log seen before its first stamp is all written too -, a restart still closes the
duels (battlerec-1); the Battles tab shows current.json's duel
as in progress only while it's being written (battlerec-7)."""
import os
import random
import sys
import tempfile
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import battlehist as H  # noqa: E402
import battlerec as R  # noqa: E402
import battlesim as S  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))


def src(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read()


def body(text, head):
    """the text of the def starting with head, up to the next def at its indent or less"""
    i = text.index(head)
    ind = len(text[text.rindex("\n", 0, i) + 1:i])
    j = i + len(head)
    while True:
        k = text.find("\n", j)
        if k < 0:
            return text[i:]
        ln = text[k + 1:text.find("\n", k + 1) if text.find("\n", k + 1) >= 0 else len(text)]
        if ln.strip() and len(ln) - len(ln.lstrip()) <= ind and ln.lstrip().startswith(("def ", "class ")):
            return text[i:k]
        j = k + 1


# ============================================================================ battlesim
class SureKinds(unittest.TestCase):
    def test_boosts_never_miss(self):
        for kind in ("blade", "trap", "aura", "enchant", "sharpen", "potent", "ward", "absorb"):
            c = S.card_of({"name": "X", "kind": kind, "school": "storm", "value": 35})
            self.assertEqual(c.acc, 100, kind)
        # (a hit and a heal: the school's)
        self.assertEqual(S.card_of({"kind": "damage", "school": "storm", "pips": 2, "value": 300}).acc, 70)
        self.assertEqual(S.Card("Heal", "heal", "life", 2, value=400).acc, 90)
        # (a fact's / a hand's accuracy wins)
        self.assertEqual(S.card_of({"kind": "blade", "school": "storm", "value": 35, "accuracy": 90}).acc, 90)

    def test_a_storm_blade_is_always_cast(self):
        rng = random.Random(3)
        blade = S.Card("Stormblade", "blade", "storm", 0, value=35)
        b = S._Battle([], S.Me("storm", 3000), [S.Foe("A", 9000)], S.Opts(), rng)
        went = 0
        for _ in range(200):
            b.hand, b.blades, b.boosts_used = [blade], [], {}
            went += bool(b.cast(blade))
        self.assertEqual(went, 200)


class EnemyPips(unittest.TestCase):
    def test_round_one_with_one_to_three(self):
        seen = set()
        for k in range(60):
            b = S._Battle([], S.Me("storm", 3000), [S.Foe("A", 900)], S.Opts(), random.Random(k))
            b._snap_danger()
            seen.add(b.danger_foes[0][1])
            self.assertIn(b.fpips[0], (0, 1, 2))
        self.assertEqual(seen, {1, 2, 3})

    def test_no_four_pip_cast_in_round_one(self):
        foe = S.Foe("Big", 9000, spells=[("Quake", 1.0, {"pips": 4, "min": 400, "max": 400, "accuracy": 100})])
        for k in range(60):
            b = S._Battle([], S.Me("storm", 3000), [foe], S.Opts(), random.Random(k))
            hp = b.hp
            b.foe_round()
            self.assertEqual(b.hp, hp, k)

    def test_a_later_round_from_state(self):
        # (pips not known: round 1 cast with 1-3; a later round with 2-4, as before - a pip a round since; given: kept)
        foes = [S.Foe("A", 900)]
        for rnd, want in ((1, {0, 1, 2}), (4, {1, 2, 3})):
            seen = set()
            for k in range(60):
                st = S.State([], [], fhp=[900], rnd=rnd)
                seen.add(S._Battle.from_state(st, S.Me("storm", 3000), foes, S.Opts(), random.Random(k)).fpips[0])
            self.assertEqual(seen, want, rnd)
        st = S.State([], [], fhp=[900], rnd=4, fpips=[0])
        self.assertEqual(S._Battle.from_state(st, S.Me("storm", 3000), foes, S.Opts(), random.Random(1)).fpips, [0])


class FoeBlades(unittest.TestCase):
    def test_only_the_hits_school(self):
        foe = S.Foe("Boss", 9000, "fire")
        st = S.State([], [], fhp=[9000], fblades=[[(35, ["storm"]), (30, ["fire"])]])
        b = S._Battle.from_state(st, S.Me("storm", 5000), [foe], S.Opts(), random.Random(1))
        hp = b.hp
        b._hurt(0, 0, 1000)
        self.assertEqual(hp - b.hp, 1300)
        self.assertEqual(b.fblades[0], [(35.0, ["storm"])])
        # (a blade of every school fits)
        st = S.State([], [], fhp=[9000], fblades=[[(25, None)]])
        b = S._Battle.from_state(st, S.Me("storm", 5000), [foe], S.Opts(), random.Random(1))
        hp = b.hp
        b._hurt(0, 0, 1000)
        self.assertEqual((hp - b.hp, b.fblades[0]), (1250, []))


class ItemCopy(unittest.TestCase):
    def test_deck_copy_tried_whichever_first(self):
        elf_i = S.Card("Fire Elf", "damage", "fire", 1, heads={"fire": 200}, tid=1, item=True)
        elf = S.Card("Fire Elf", "damage", "fire", 1, heads={"fire": 200}, tid=1)
        epic = S.Card("Epic", "enchant", "", 0, value=275, names="Epic")
        me = S.Me("fire", 3000, accuracy=100)
        for hand, deck_i in (([elf_i, elf, epic], 1), ([elf, elf_i, epic], 0)):
            st = S.State(hand, [], pips=1, fhp=[280], me_first=True)
            p = S.plan_round(st, me, [S.Foe("A", 280)], n=20, seed=1, budget_ms=3000)
            elves = [x for x in p["plays"] if x["name"] == "Fire Elf"]
            self.assertEqual([x["i"] for x in elves], [deck_i])
            self.assertEqual(elves[0]["kill"], 1.0)
            self.assertEqual(p["chain"]["i"], deck_i)
            b = S._Battle.from_state(st, me, [S.Foe("A", 280)], S.Opts(), random.Random(1))
            self.assertEqual([i for i, _a in S._team_cands(b, 0, b.alive()) if i is not None], [deck_i])


class TeamBudget(unittest.TestCase):
    def test_one_pass_and_the_budget(self):
        def hand():
            return [S.Card("Storm Lord", "damage", "storm", 7, value=1000),
                    S.Card("Thunder Snake", "damage", "storm", 2, value=150),
                    S.Card("Storm Shark", "damage", "storm", 3, value=250),
                    S.Card("Stormblade", "blade", "storm", 0, value=35),
                    S.Card("Storm Trap", "trap", "storm", 0, value=30)]
        mates = [S.Mate("M%d" % k, 5 + k, S.Me("storm", 3000), "hitter", hand(), [], 3, 0, None) for k in range(3)]
        st = S.State(hand(), [], pips=3, fhp=[5000, 2000, 2000], seat=4, me_first=True, mates=mates)
        foes = [S.Foe("Boss", 5000, boss=True), S.Foe("Mob1", 2000), S.Foe("Mob2", 2000)]
        tp = S.plan_team(st, S.Me("storm", 3000), foes, budget_ms=120, seed=3)
        self.assertEqual(len(tp["orders"]), 4)
        self.assertIn("one pass only (too little time for a second)", tp["why"])
        self.assertLess(tp["ms"], 600)          # (one round of each wizard's plays at most past it - loose)
        # (time enough: a second pass, no note)
        tp = S.plan_team(st, S.Me("storm", 3000), foes, n=2, budget_ms=20000, seed=3)
        self.assertNotIn("one pass only (too little time for a second)", tp["why"])
        self.assertTrue(all(o["n"] == 2 for o in tp["orders"]), tp["orders"])


# ============================================================================ battlerec
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


ARMOR = cast(4, "Spirit Armor", [(4, "kAbsorbDamage", 1, 500)])


class Absorb(unittest.TestCase):
    def left(self, bite):
        return [x["pct"] for x in R.charms_now(duel([ARMOR], [bite]), {})["by"][4]["absorb"]]

    def test_worn_by_what_it_soaked(self):
        # (health lost: the hit got past it - gone)
        self.assertEqual(self.left(cast(0, "Bite", hp=[(4, 3000, -200)], fx=[(4, "kDamage", 700)])), [])
        # (none lost: it soaked the hit - its ProcessWards number, else its ProcessTargets one)
        self.assertEqual(self.left(cast(0, "Bite", fx=[(4, "kDamage", 200)])), [300])
        self.assertEqual(self.left(cast(0, "Bite", fx=[(4, "kDamage", 200)], wards=[[0, 4, "kDamage", 260]])), [240])
        # (a damage over time's param isn't the hit's)
        self.assertEqual(self.left(cast(0, "Bite", fx=[(4, "kDamageOverTime", 900), (4, "kDamage", 100)])), [400])

    def test_after_the_targets_resist(self):
        # (the log's own round: ProcessWards 721, the target's StatRebalance x0.62 - 447 soaked, 53 of 500 left)
        self.assertEqual(self.left(cast(0, "Centaur", fx=[(4, "kDamage", 555)], wards=[[0, 4, "kDamage", 721]], res=[[4, 38.0, 0.62]])), [53])
        # (another target's resist isn't this one's)
        self.assertEqual(self.left(cast(0, "Bite", fx=[(4, "kDamage", 200)], res=[[5, 50.0, 0.5]])), [300])


class BriefFacts(unittest.TestCase):
    def test_a_deck_reads_line_fits_every_school(self):
        brief = {7: {"tid": 7, "name": "Tri Blade", "school": "Balance", "kind": None, "boosts": None, "full": False}}
        d = duel([cast(4, "Tri Blade", [(4, "kModifyOutgoingDamage", 1, 35)])])
        self.assertIsNone(R.charms_now(d, brief)["by"][4]["blades"][0]["schools"])
        d["rounds"].append({"n": 2, "casts": [cast(4, "Thunder Snake", hp=[(0, 500, -300)])]})
        self.assertEqual(R.charms_now(d, brief)["by"][4]["blades"], [])
        # (a full fact with no boosts text: its own school, as before)
        full = {7: {"tid": 7, "name": "Odd Blade", "school": "Fire", "kind": "blade", "boosts": "", "full": True}}
        d = duel([cast(4, "Odd Blade", [(4, "kModifyOutgoingDamage", 1, 35)])])
        self.assertEqual(R.charms_now(d, full)["by"][4]["blades"][0]["schools"], ["fire"])


class HashedNames(unittest.TestCase):
    def test_cut_out_by_its_hash(self):
        d = {"names": {5: "#h:" + R.name_h("Ryan Stormbane"), 4: "Me Myself", 0: "Rat"}}
        hashes = R.hidden_hashes(d)
        self.assertEqual(hashes, {R.name_h("Ryan Stormbane")})
        lines = [[1, "your side's plates: Ryan Stormbane 2500, Me Myself 3000"], [2, "Ryan alone"], [3, None]]
        out = R.scrub(lines, [], hashes)
        self.assertEqual(out[0][1], "your side's plates: (ally %s) 2500, Me Myself 3000" % R.name_h("Ryan Stormbane"))
        self.assertEqual(out[1:], lines[1:])
        self.assertIs(R.scrub(lines, [], ()), lines)

    def test_used_where_the_lines_go_out(self):
        t = src("battlerec.py")
        self.assertIn('scrub(post["lines"], hide, hashes)', t)
        self.assertIn('scrub(x["lines"], hide, hashes)', t)


def log_line(t, msg, cat="ClientDuel"):
    return "%s [STAT] %s %s" % (time.strftime("%m/%d/%y %H:%M:%S", time.localtime(t)), cat, msg)


class BackScanReuse(unittest.TestCase):
    def test_a_number_used_again(self):
        t = time.time() - 300
        ln = [log_line(t, "Duel 555: MSG_CombatAdd(Local Player)"),
              log_line(t, "Duel 555: MSG_CombatPhase(kPhase_Planning) PlayerID:0"),
              log_line(t + 60, "Duel 555: MSG_EndDuel received"),
              log_line(t + 120, "Duel 555: MSG_CombatAdd(CL_Rat-R3)")]
        second = len("\n".join(ln)) + 1
        ln += [log_line(t + 120, "Duel 555: MSG_CombatAdd(Local Player)"),
               log_line(t + 121, "Duel 555: MSG_CombatPhase(kPhase_Planning) PlayerID:0"),
               log_line(t + 130, "Duel 555: MSG_SetPlanningPhaseTimer(30)")]
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "WizardClient.log")
            with open(p, "wb") as f:
                f.write(("\n".join(ln) + "\n").encode("ascii"))
            _z, _c, prog, _w = R.back_scan(p, os.path.getsize(p))
        self.assertEqual(prog, (555, second - len(ln[3]) - 1))


def rec(rid="20261115-101000-555", t0="2026-11-15 10:10:00"):
    return {"rec": "battle", "id": rid, "t0": t0, "t1": "2026-11-15 10:12:00", "result": "won"}


class WrittenOnce(unittest.TestCase):
    def lines(self, d):
        with open(os.path.join(d, "2026-11", "2026-11-15.jsonl"), encoding="ascii") as f:
            return [x for x in f.read().splitlines() if '"rec":"battle"' in x]

    def test_not_twice(self):
        with tempfile.TemporaryDirectory() as d:
            said = []
            st = R.Store(d, said.append)
            st.add(rec())
            st.add(rec())
            self.assertEqual(len(st.pending), 1)
            st.flush(0)
            self.assertEqual(len(self.lines(d)), 1)
            # (a restart: current.json's pending one again - already in the day file)
            st2 = R.Store(d, said.append)
            st2.add(rec())
            st2.add(rec("20261115-101500-555", "2026-11-15 10:15:00"))
            st2.flush(0)
            self.assertEqual(len(self.lines(d)), 2)
            self.assertEqual(st2.pending, [])
            self.assertTrue(any("not written again" in s for s in said), said)

    def test_checkpoint_after_the_write(self):
        t = src("battlerec.py")
        b = body(t, "    def _flush(self, now):")
        self.assertLess(b.index("self.store.flush(now)"), b.index("self._checkpoint()"))
        r = body(t, "    def _run(self):")
        self.assertLess(r.index("self.store.flush()"), r.index("self._checkpoint()"))


class Rotation(unittest.TestCase):
    def test_rest_of_a_rotated_log(self):
        t = time.time()
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "WizardClient.log")
            with open(p, "wb") as f:
                f.write((log_line(t - 99, "start", "CORE_SEER") + "\n").encode("ascii"))
            tail = R.Tail(p)
            self.assertEqual(tail.read()[0], "ok")
            more = log_line(t - 50, "Duel 7: MSG_CombatPhase(kPhase_Planning) PlayerID:0") + "\n"
            with open(p, "ab") as f:
                f.write((more + log_line(t - 49, "Current log file has reached the maximum size--will create new "
                                                 "log file.", "PLAT_KILOG") + "\n").encode("ascii"))
            os.rename(p, os.path.join(d, "WizardClient.261124_0018.log"))
            with open(p, "wb") as f:
                f.write((log_line(t - 48, "new", "CORE_SEER") + "\n").encode("ascii"))
            state, base, data = tail.read()
            self.assertEqual((state, base), ("new", 0))
            pos, rest = tail.rotated_rest()
            self.assertTrue(rest.startswith(more.encode("ascii")), rest)
            self.assertIn(R.ROTATED, rest)
            self.assertIsNone(tail.rotated_rest())          # (once)
            # (a restart: the log written over, no renamed file with its head - not a rotation)
            with open(p, "wb") as f:
                f.write((log_line(t - 10, "again", "CORE_SEER") + "\n").encode("ascii"))
            self.assertEqual(tail.read()[0], "new")
            self.assertIsNone(tail.rotated_rest())

    def test_new_log_seen_before_its_first_stamp(self):
        t = time.time()
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "WizardClient.log")
            with open(p, "wb") as f:
                f.write((log_line(t - 99, "start", "CORE_SEER") + "\n").encode("ascii"))
            tail = R.Tail(p)
            self.assertEqual(tail.read()[0], "ok")
            more = log_line(t - 50, "Duel 7: MSG_CombatPhase(kPhase_Planning) PlayerID:0") + "\n"
            with open(p, "ab") as f:
                f.write((more + log_line(t - 49, "Current log file has reached the maximum size--will create new "
                                                 "log file.", "PLAT_KILOG") + "\n").encode("ascii"))
            os.rename(p, os.path.join(d, "WizardClient.261124_0018.log"))
            # (the game made the new log, nothing in it yet - then a part of its first stamp)
            for part in (b"", log_line(t - 48, "new", "CORE_SEER").encode("ascii")[:9]):
                with open(p, "wb") as f:
                    f.write(part)
                self.assertEqual(tail.read(), ("ok", tail.pos, b""))
            with open(p, "wb") as f:
                f.write((log_line(t - 48, "new", "CORE_SEER") + "\n").encode("ascii"))
            self.assertEqual(tail.read()[0], "new")
            pos, rest = tail.rotated_rest()
            self.assertTrue(rest.startswith(more.encode("ascii")), rest)
            self.assertEqual(tail.read()[0], "ok")

    def test_tail_keeps_the_duel_on_a_rotation(self):
        b = body(src("battlerec.py"), "    def _tail(self, now):")
        self.assertLess(b.index("rotated_rest()"), b.index("close_all("))
        self.assertIn("if rest is None:", b)


# ============================================================================ battlehist
class StaleCurrent(unittest.TestCase):
    def test_in_progress_only_while_written(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "current.json")
            with open(p, "w", encoding="utf-8") as f:
                f.write('{"v": 1, "parser": {"duel": {"num": 1, "rounds": [{"n": 1}]}}}')
            H._CUR.update(key=None, duel=None)
            now = os.stat(p).st_mtime
            self.assertIsNotNone(H.current_duel(d, now + 60))
            self.assertIsNone(H.current_duel(d, now + H.CUR_FRESH_S + 60))
            self.assertTrue(H.battle_answer(d, "cur", now + H.CUR_FRESH_S + 60).startswith("none\t"))
            H._CUR.update(key=None, duel=None)


if __name__ == "__main__":
    unittest.main()
