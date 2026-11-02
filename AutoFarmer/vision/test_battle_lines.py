"""test_battle_lines.py - the vision helper's /battle lines (battle_lines: the old 13 fields as they were, the plate's box
and the hidden-health flag after them - plate_box), memory /cards' log key (not every box change) and /phase on a local
server, the game's readers made up - no game, no Windows:  python3 -m unittest test_battle_lines   (from AutoFarmer\\vision)"""
import os
import sys
import tempfile
import threading
import types
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import vision as V  # noqa: E402
from test_handmem_boxes import C2, C3, fake_hand, import_handmem  # noqa: E402

ROOT = (0, 0, 1827, 1027)


def part(**kw):
    p = {'me': False, 'team': 2, 'name': 'Fire Elf', 'health': 400, 'max_health': 450, 'boss': False, 'player': False,
         'owner': 0x1234, 'school': 'fire', 'mob': {'title': 'Normal', 'rank': 2, 'school': 'Fire'},
         'box': (913, 100, 1096, 140), 'root': ROOT, 'hide_hp': False}
    p.update(kw)
    return p


class BattleLines(unittest.TestCase):
    """/battle's part| lines"""

    def test_old_fields_then_box_and_hide(self):
        me = part(me=True, team=1, name='', player=True, owner=99, mob=None, school='storm', box=(0, 900, 182, 940),
                  hide_hp=False)
        foe = part(hide_hp=True)
        ln = V.battle_lines([foe, me])
        self.assertEqual(len(ln), 2)
        f = ln[0].split('|')
        # (the wizard's own first; the 13 fields an older bot reads exactly as before)
        self.assertEqual(f[:13], ['part', '1', '1', '', '400', '450', '0', '', '', 'Storm', '1', '99', '0.0498'])
        self.assertEqual(f[13:], ['0.0000', '0.8763', '0.0996', '0.9153', '0'])
        g = ln[1].split('|')
        self.assertEqual(g[:13], ['part', '0', '2', 'Fire Elf', '400', '450', '0', 'Normal', '2', 'Fire', '0', '4660',
                                  '0.5498'])
        self.assertEqual(g[13:17], ['0.4997', '0.0974', '0.5999', '0.1363'])
        self.assertEqual(g[17], '1')
        self.assertEqual(len(g), 18)

    def test_box_not_read(self):
        # (the wizard's own read from handmem, no window: box None - x and the box blank, the flag still there)
        p = part(me=True, box=None, hide_hp=None)
        f = V.battle_lines([p])[0].split('|')
        self.assertEqual(len(f), 18)
        self.assertEqual(f[12:], ['', '', '', '', '', ''])

    def test_plate_box_pure(self):
        self.assertEqual(V.plate_box({'box': (0, 0, 1827, 1027), 'root': ROOT}), ['0.0000', '0.0000', '1.0000', '1.0000'])
        self.assertEqual(V.plate_box({'box': (10, 10, 10, 20), 'root': ROOT}), ['', '', '', ''])     # (empty)
        self.assertEqual(V.plate_box({'box': (10, 10, 20, 20), 'root': (0, 0, 0, 0)}), ['', '', '', ''])
        self.assertEqual(V.plate_box({'box': (10, 10, 20, 20)}), ['', '', '', ''])
        self.assertEqual(V.plate_box({}), ['', '', '', ''])
        self.assertEqual(V.plate_box({'box': (1, 2), 'root': ROOT}), ['', '', '', ''])

    def test_none_line(self):
        self.assertEqual(V.battle_lines([], "not in a battle's planning phase"), ["none|not in a battle's planning phase"])
        self.assertEqual(V.battle_lines(None, ''), ['none|not in a battle'])
        self.assertEqual(V.battle_lines([], 'a|b'), ['none|a b'])


class FakeNav:
    """navmem's NavMem as cards(), nav_phase and the server use it - the made-up hand"""

    def __init__(self, hm):
        self.hm, self.st, self.lock = hm, object(), threading.Lock()
        hm.st = self.st

    def cards(self, want_effects=True, wait=0.5):
        return self.hm.read(want_effects), ''

    def _ensure(self, wait):
        return self.st, ''

    def _hand_reader(self, st, wait):
        return self.hm, ''


class Helper(unittest.TestCase):
    """memory /cards' log key and /phase - handmem put in sys.modules for the requests only (the routes import it), and
    taken out again"""

    def setUp(self):
        self.H = import_handmem()
        self.keep = (V.nav_reader, V.LOG, V.log, sys.modules.get('handmem'), dict(V.CARDS_LOGGED), V.PARTY, V.REC,
                     V._rec_hook)
        self.logged = []
        V.log = lambda text, *a, **kw: self.logged.append(text)
        sys.modules['handmem'] = self.H

    def tearDown(self):
        V.nav_reader, V.LOG, V.log, had, cl, V.PARTY, V.REC, V._rec_hook = self.keep
        V.CARDS_LOGGED.clear()
        V.CARDS_LOGGED.update(cl)
        if had is None:
            sys.modules.pop('handmem', None)
        else:
            sys.modules['handmem'] = had

    def test_cards_logged_when_the_cards_change_not_their_boxes(self):
        hm = fake_hand()
        V.nav_reader = lambda: FakeNav(hm)
        rec = V._rec_hook
        V._rec_hook = lambda *a: None
        try:
            V.CARDS_LOGGED['text'] = None
            text = V.cards_answer()
            self.assertIn('root|1827|1027', text.split('\n'))
            self.assertEqual(len(self.logged), 1)
            # (the hand raised: every box moved up, the cards the same - not logged again; x, field 3, is the left edge
            # and still counts, as before)
            for w in list(hm.rects):
                if hm.wname(w).startswith('Card'):
                    l, t, r, b = hm.rects[w]
                    hm.rects[w] = (l, t - 12, r, b - 12)
            text2 = V.cards_answer()
            self.assertNotEqual(text, text2)
            self.assertEqual(len(self.logged), 1)
            # (a card gone: logged)
            hm2 = fake_hand(cards_shown=(C2, C3))
            V.nav_reader = lambda: FakeNav(hm2)
            V.cards_answer()
            self.assertEqual(len(self.logged), 2)
        finally:
            V._rec_hook = rec

    def test_cards_kept_for_the_leader(self):
        # (partyorders, a follower: /cards?ptag= - the hand read also kept for the party's leader, the round the battle
        # recorder's; no ptag: /cards as ever, nothing kept)
        import party
        hm = fake_hand()
        V.nav_reader = lambda: FakeNav(hm)
        V._rec_hook = lambda *a: None
        V.REC = types.SimpleNamespace(on=True, broken=False, parser=types.SimpleNamespace(
            duel={'num': 12, 'phase': 'Planning', 'rounds': [{'n': 6}]}))

        class Quiet(party.Party):
            def _loop(self):
                return
        F = Quiet(lambda: None, log=lambda *a: None)
        F.cfg.update(role='follower', orders='1')
        F.ahk = party.clean_state({'battle': '1'})
        V.PARTY = F

        def cards(q=None):
            # (the answer but its hand| line - its read's ms)
            return [ln for ln in V.cards_answer(q).split('\n') if not ln.startswith('hand|')]
        text = cards()
        self.assertIsNone(F.stash)
        self.assertEqual(cards({'ptag': 'd12r5'}), text)                  # (the answer as ever)
        self.assertEqual((F.stash['tag'], F.stash['round']), ('d12r5', 6))
        self.assertEqual([c['tid'] for c in F.stash['hand']['cards']], [8192, 4096, 0])
        # (no recorder: the tag's round; partyorders off in this helper: nothing kept)
        V.REC = None
        V.cards_answer({'ptag': 'd12r7'})
        self.assertEqual((F.stash['tag'], F.stash['round']), ('d12r7', 7))
        F.cfg['orders'], F.stash = '', None
        V.cards_answer({'ptag': 'd12r8'})
        self.assertIsNone(F.stash)
        # (no party in this helper: /cards as ever)
        V.PARTY = None
        self.assertEqual(cards({'ptag': 'd12r8'}), text)

    def test_phase_route(self):
        import urllib.request
        from http.server import ThreadingHTTPServer
        hm = fake_hand(cards_shown=(), items=[1, 2])
        with tempfile.TemporaryDirectory() as d:
            V.nav_reader, V.LOG = (lambda: FakeNav(hm)), os.path.join(d, 'vision.log')
            srv = ThreadingHTTPServer(('127.0.0.1', 0), V.Handler)
            th = threading.Thread(target=srv.serve_forever, daemon=True)
            th.start()
            try:
                def get(path):
                    with urllib.request.urlopen('http://127.0.0.1:%d%s' % (srv.server_address[1], path), timeout=5) as r:
                        return r.status, r.read().decode()
                code, text = get('/phase')
                self.assertEqual(code, 200)
                f = text.split('|')
                self.assertEqual(f[:7], ['phase', 'waiting', '1', '1', '0', '0', '2'])
                V.nav_reader = lambda: types.SimpleNamespace(lock=threading.Lock(),
                                                             _ensure=lambda wait: (None, 'the game is not running'))
                self.assertEqual(get('/phase'), (200, 'none|the game is not running'))
            finally:
                srv.shutdown()
                srv.server_close()
        self.assertEqual(V.GATE.n, 0)              # (the gated request left the gate)


if __name__ == '__main__':
    unittest.main()
