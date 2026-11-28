"""test_fix_helpermem.py - the hand's reader made in spite of effect / target names that don't check out (a patch's new
enum layout - build 6B05FDF0-37BB000, 2026-11-26, turned off the GUI, backpack, login box, decks, gear and pets with the
cards): handmem.HandMem keeps its GUI root, template map and name tables and says cards_why; only the cards answer it
(HandMem.read, NavMem.cards), DeckMem gives no kinds - a read of the decks with their kinds isn't made at all (no deck
profile learned from cards with no kinds) -, the phase and the other readers still read. No game, no Windows:
    python -m unittest test_fix_helpermem   (from AutoFarmer\\vision)"""
import os
import sys
import types
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from test_handmem_boxes import H, fake_hand  # noqa: E402

BUILD = "6B05FDF0-37BB000"
GOOD_TYPES = {0: "kInvalidSpellEffect", 1: "kDamage", 2: "kDamageNoCrit", 3: "kHeal"}
GOOD_TARGETS = {0: "kInvalidTarget", 1: "kSpell", 2: "kEnemySingle", 4: "kEnemyTeam", 7: "kSelf"}


def made(etype, etarget, missing=()):
    """(a HandMem made on a made-up game - the code copy, its reflected classes and enums stood in for -, its log)"""
    props = {c: {k: (0x10 + 8 * i, "int") for i, k in enumerate(H.NEED.get(c, ())) if c + "." + k not in missing}
             for c in H.CLASSES}
    logged = []

    def class_props(img, nm, *a, **kw):
        return props.get(nm, {}), None, ([0x7FF600000010] if nm in H.VT_CLASSES else [])

    def read_enum(img, first, prop, cls, log=None):
        return dict(etype if first == "kInvalidSpellEffect" else etarget)
    st = types.SimpleNamespace(p=object(), m=types.SimpleNamespace(build=BUILD, base=0x7FF600000000))
    with mock.patch.object(H, "Image", lambda s: object()), mock.patch.object(H, "class_props", class_props), \
            mock.patch.object(H, "read_enum", read_enum), \
            mock.patch.object(H.HandMem, "_template_map", lambda self, img: 0x22220000):
        hm = H.HandMem(st, log=logged.append)
    return hm, logged


class Degraded(unittest.TestCase):
    """the effect names not read: the reader made, the cards alone refused"""

    def test_effect_names_unread_still_makes_the_reader(self):
        hm, logged = made({0: "kInvalidSpellEffect", 7: "kFoo"}, GOOD_TARGETS)
        self.assertEqual(hm.cards_why, "the cards can't be read in this build: the spell effect names couldn't be "
                                       "read in this build (%s)" % BUILD)
        # (the parts the GUI, backpack, deck, gear and pet readers use: there)
        self.assertEqual(hm.tm, 0x22220000)
        self.assertEqual(hm.lang, {})
        self.assertIn("m_Children", hm.P["Window"])
        self.assertTrue(hm.vt["SpellCheckBox"])
        self.assertTrue(callable(hm.root) and callable(hm.login_root) and callable(hm.lang_text))
        # (vision.log still says the card names couldn't be read - and that it's the cards alone)
        self.assertTrue(any(m.startswith("handmem: the cards can't be read in this build: the spell effect names "
                                         "couldn't be read") for m in logged), logged)
        self.assertTrue(any(m.startswith("handmem: ready in") for m in logged), logged)

    def test_target_names_unread_said_too(self):
        hm, logged = made(GOOD_TYPES, {0: "kInvalidTarget"})
        self.assertIn("the effect target names couldn't be read in this build (%s)" % BUILD, hm.cards_why)
        self.assertTrue(hm.cards_why.startswith("the cards can't be read in this build: "))

    def test_names_that_check_out_no_why(self):
        hm, logged = made(GOOD_TYPES, GOOD_TARGETS)
        self.assertEqual(hm.cards_why, "")
        self.assertFalse(any("can't be read" in m for m in logged), logged)

    def test_a_missing_property_still_raises(self):
        with self.assertRaises(LookupError):
            made(GOOD_TYPES, GOOD_TARGETS, missing=("Window.m_Children",))

    def test_read_refuses_the_cards_the_phase_still_reads(self):
        hm = fake_hand()
        ok = hm.read()
        self.assertTrue(ok["settled"])
        hm.cards_why = "the cards can't be read in this build: the spell effect names couldn't be read in this build (X)"
        r = hm.read()
        self.assertEqual((r["state"], r["settled"], r["cards"], r["why"]), ("none", False, [], hm.cards_why))
        self.assertIn("ms", r)
        self.assertEqual(H.answer(r), "none|" + hm.cards_why)
        p = hm.phase()
        self.assertEqual(p["state"], "hand")
        self.assertTrue(p["in_battle"] and p["planning"])

    def test_a_bare_reader_has_no_why(self):
        # (made-up readers without the attribute - other tests' - read as before)
        hm = fake_hand()
        hm.__dict__.pop("cards_why", None)
        self.assertTrue(hm.read()["settled"])


class Nav(unittest.TestCase):
    """navmem: /cards answers the why as it did when the reader wasn't made; the other readers get the reader"""

    @classmethod
    def setUpClass(cls):
        from test_navroute import import_navmem
        cls.N = import_navmem()

    def test_cards_why_through_navmem(self):
        nm = self.N.NavMem(log=lambda m: None)
        st = types.SimpleNamespace(alive=lambda: True)
        hm = fake_hand()
        hm.st = st
        hm.cards_why = "the cards can't be read in this build: the spell effect names couldn't be read in this build (X)"
        nm.st, nm._hand = st, hm
        nm._ensure = lambda wait: (st, "")
        self.assertEqual(nm.cards(want_effects=False), (None, hm.cards_why))
        # (the GUI, backpack, deck, gear, pet and battle readers: the reader itself)
        self.assertEqual(nm._hand_reader(st, 0.0), (hm, ""))
        # (names that check out: the hand read)
        hm.cards_why = ""
        r, why = nm.cards()
        self.assertEqual(why, "")
        self.assertTrue(r["settled"])
        self.assertFalse(nm.lock.locked())

    def test_hand_make_keeps_a_degraded_reader(self):
        nm = self.N.NavMem(log=lambda m: None)
        st = types.SimpleNamespace(alive=lambda: True)
        hm = types.SimpleNamespace(st=st, cards_why="the cards can't be read in this build: x")
        fake = types.ModuleType("handmem")
        fake.HandMem = lambda s, log=None: hm
        with mock.patch.dict(sys.modules, {"handmem": fake}):
            nm._hand_make(st)
        self.assertIs(nm._hand, hm)
        self.assertIsNot(nm._hand_fail[0], st)


class Deck(unittest.TestCase):
    """deckmem: a deck card's kind not guessed from effect numbers - its brief still read"""

    @classmethod
    def setUpClass(cls):
        from test_petmem import import_deckmem
        cls.D = import_deckmem()

    def test_no_kind_when_the_cards_cant_be_read(self):
        dm = object.__new__(self.D.DeckMem)
        dm.card_cache = {}
        calls = []
        dm.brief = lambda tid: {"template_id": tid, "name": "Fire Cat", "school": "Fire", "type": "Damage", "pips": 1}
        dm.hm = types.SimpleNamespace(cards_why="the cards can't be read in this build: x",
                                      tpl_info=lambda tid: calls.append(tid) or {"effects": []})
        c = dm.card(77)
        self.assertEqual(calls, [])
        self.assertEqual(c["name"], "Fire Cat")
        self.assertIsNone(c.get("kind"))
        self.assertEqual(c["kind_why"], "the cards can't be read in this build: x")

    def test_no_read_with_kinds_when_the_cards_cant_be_read(self):
        # (every deck with their kinds - /decks, the deck profiles learned from it: not read, why the cards_why; the
        # recorder's worn deck and /book without kinds still read)
        dm = object.__new__(self.D.DeckMem)
        dm.hm = types.SimpleNamespace(cards_why="the cards can't be read in this build: x")
        calls = []
        dm._read = lambda out, books, kinds, only_equipped=False: calls.append(kinds) or out.update(decks=[{"gid": 1}])
        r = dm.read(kinds=True)
        self.assertEqual((r["decks"], r["why"], calls), ([], "the cards can't be read in this build: x", []))
        r = dm.read(kinds=False, only_equipped=True)
        self.assertEqual((r["decks"], r["why"], calls), ([{"gid": 1}], "", [False]))
        dm.hm.cards_why = ""
        self.assertEqual(dm.read(kinds=True)["decks"], [{"gid": 1}])
        self.assertEqual(calls, [False, True])

    def test_navmem_decks_with_kinds_answer_the_why(self):
        from test_navroute import import_navmem
        N = import_navmem()
        nm = N.NavMem(log=lambda m: None)
        st = types.SimpleNamespace(alive=lambda: True)
        hm = types.SimpleNamespace(st=st, cards_why="the cards can't be read in this build: x")
        dm = types.SimpleNamespace(st=st, hm=hm)
        nm.st, nm._hand = st, hm
        nm._deck_readers = lambda wait: (st, dm, "")
        paced = []
        nm._deck_paced = lambda *a: paced.append(a[6]) or ({"decks": []}, "")
        self.assertEqual(nm.deck(fresh=True, only_equipped=False, kinds=True), (None, hm.cards_why))
        self.assertEqual(paced, [])
        # (without kinds - the recorder's: read)
        self.assertEqual(nm.deck(fresh=True, kinds=False), ({"decks": []}, ""))
        self.assertEqual(paced, [False])
        self.assertFalse(nm._deck_busy.locked())


class Source(unittest.TestCase):
    """the constructor no longer raises on the enums"""

    def test_no_raise_on_the_enum_check(self):
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "handmem.py"), encoding="utf-8") as f:
            src = f.read()
        self.assertNotIn('raise LookupError("the spell effect names', src)
        self.assertNotIn('raise LookupError("the effect target names', src)
        self.assertIn("self.cards_why = \"\"", src)


if __name__ == "__main__":
    unittest.main()
