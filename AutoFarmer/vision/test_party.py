"""test_party.py - the party link's checks (standard library only):  python -m unittest test_party  (in AutoFarmer\\vision)

The leader's doors (walked or a teleport, the last three with their ages), its loading flag and time in its zone, the
teleport advice (port_advice), a follower's teleport state (tp), and the lines AutoHotkey reads (Party.ahk PartyTick:
f[1] the line's kind - the fields it knew before stay where they were). No network, no thread: a stand-in reader and
clock, and Party's background loop switched off."""
import json
import os
import sys
import unittest
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import party as P  # noqa: E402


class Clock:
    """party.time stood in for: time() and monotonic() as set, sleep() moves it on"""

    def __init__(self, t=1000.0):
        self.t = t

    def time(self):
        return self.t

    def monotonic(self):
        return self.t

    def sleep(self, s):
        self.t += s


class Quiet(P.Party):
    """a Party whose background loop does nothing (the tests call _read, beat_in and lines themselves)"""

    def _loop(self):
        return


def ahk_fields(line, n=39):
    """a line as Party.ahk splits it: f[1] its kind, a field it doesn't have blank (1-based: f[k] is out[k])"""
    f = line.split('|')
    while len(f) < n:
        f.append('')
    return [None] + f


class PartyCase(unittest.TestCase):
    def setUp(self):
        self.clock = Clock()
        self._time = P.time
        P.time = self.clock
        self.logged = []

    def tearDown(self):
        P.time = self._time

    def make(self, role):
        """a Party with a stand-in reader (self.reading[party]) - its role set straight in (update() would start the
        leader's LAN server)"""
        box = {'r': None}
        p = Quiet(lambda: box['r'], log=self.logged.append)
        p.box = box
        p.cfg['role'] = role
        return p

    def at(self, p, zone, x, y, z=0.0, source='body'):
        """one reading of p's wizard (zone, place - navmem's source: 'body', or 'object' while zoning), then the clock on
        0.4 s"""
        p.box['r'] = {'zone': zone, 'pos': (x, y, z), 'yaw': 0.0, 'source': source}
        p._read()
        self.clock.t += 0.4

    def walk(self, p, zone, x0, y0, vx, vy, secs=2.0):
        """p walking in zone from (x0, y0) at (vx, vy) units a second, read every 0.4 s"""
        for i in range(int(round(secs / 0.4)) + 1):
            self.at(p, zone, x0 + vx * 0.4 * i, y0 + vy * 0.4 * i)

    def stand(self, p, zone, x, y, secs=2.0):
        for _ in range(int(round(secs / 0.4)) + 1):
            self.at(p, zone, x, y)

    def follow(self, leader, follower):
        """the follower's beat to the leader, its answer through JSON as on the network (_beat_out's own handling)"""
        d = json.loads(json.dumps(leader.beat_in({'id': follower.id, **follower._beat_query()}, '192.168.1.20')))
        follower.leader = dict(P.clean_peer(d.get('leader')), at=self.clock.t, others=[])
        return d


class Doors(PartyCase):
    def test_walked_door(self):
        L = self.make('leader')
        self.walk(L, 'WizardCity/WC_Ravenwood', 0, 0, 400, 0)
        self.at(L, 'WizardCity/WC_Commons', 5000, 5000)
        d = L.door
        self.assertEqual((d['zone'], d['to'], d['walked']), ('WizardCity/WC_Ravenwood', 'WizardCity/WC_Commons', True))
        self.assertAlmostEqual(d['x'], 800.0)              # its last spot in the zone it left
        self.assertAlmostEqual(d['dx'], 1.0)               # and the way it was going
        self.assertAlmostEqual(d['dy'], 0.0)
        self.assertEqual(L.doors, [d])
        self.assertIn('walked through a door', self.logged[-1])

    def test_teleport_standing_still(self):
        # (End / Home / a sigil / a friend's teleport: it stood still before the zone changed - before, this made a door
        # with no way on (dx = dy = 0) that a follower walked to and pushed into forever)
        L = self.make('leader')
        self.stand(L, 'WizardCity/WC_Ravenwood', 100, 100)
        self.at(L, 'WizardCity/WC_Commons', 0, 0)
        d = L.door
        self.assertIs(d['walked'], False)
        self.assertEqual((d['x'], d['y'], d['dx'], d['dy']), (100, 100, 0.0, 0.0))
        self.assertIn('a teleport', self.logged[-1])

    def test_zoning_reads_left_out(self):
        # (walked 2 s at 1000 a second, then 1.6 s of readings still in the old zone, frozen at the doorway, from the
        # ClientObject's own copy - no body: zoning -, then the new zone: a door walked through, its way on the way it
        # went - it was "a teleport", its way on none, and a follower refused the door)
        L = self.make('leader')
        self.walk(L, 'A', 0, 0, 1000, 0)
        for _ in range(4):
            self.at(L, 'A', 2000, 0, source='object')
        self.at(L, 'B', 0, 0)
        d = L.door
        self.assertIs(d['walked'], True)
        self.assertEqual((d['x'], d['y']), (2000, 0))              # its last spot in A, as before
        self.assertAlmostEqual(d['dx'], 1.0)
        self.assertIn('walked through a door', self.logged[-1])
        self.assertIn('4 zoning reads left out', self.logged[-1])
        self.assertIn('still for the last 1.6 s', self.logged[-1])

    def test_all_zoning_reads_kept(self):
        # (nothing but zoning reads in the zone left: those, as before - here it stood still)
        L = self.make('leader')
        self.stand(L, 'A', 5, 5)
        L.trail = [p[:5] + (True,) for p in L.trail]
        self.at(L, 'B', 0, 0)
        self.assertIs(L.door['walked'], False)
        self.assertNotIn('zoning reads left out', self.logged[-1])

    def test_still_for(self):
        trail = [(0.0, 'A', 0, 0, 0), (0.4, 'A', 400, 0, 0), (0.8, 'A', 400.5, 0, 0), (1.2, 'A', 400, 0, 0)]
        self.assertAlmostEqual(P.still_for(trail), 0.8)
        self.assertEqual(P.still_for(trail[:2]), 0.0)
        self.assertEqual(P.still_for([]), 0.0)

    def test_too_little_trail(self):
        L = self.make('leader')
        self.at(L, 'A', 0, 0)
        self.at(L, 'B', 900, 0)
        self.assertIsNone(L.door['walked'])

    def test_slow_reads(self):
        # (readings 2 s apart - a slow read: the one before is looked at)
        w, moved, span, back = P.walked_before([(0.0, 'A', 0, 0, 0), (2.0, 'A', 1500, 0, 0)])
        self.assertIs(w, True)
        self.assertEqual((moved, span, back[2]), (1500, 2.0, 0))
        self.assertIs(P.walked_before([(0.0, 'A', 5, 5, 0), (2.0, 'A', 5, 5, 0)])[0], False)
        self.assertEqual(P.walked_before([]), (None, 0.0, 0.0, None))

    def test_last_three_kept(self):
        L = self.make('leader')
        for i, (a, b) in enumerate([('A', 'B'), ('B', 'C'), ('C', 'D'), ('D', 'E')]):
            self.walk(L, a, 0, 0, 0, 500)
            self.at(L, b, 0, 0)
        self.assertEqual([(d['zone'], d['to']) for d in L.doors], [('B', 'C'), ('C', 'D'), ('D', 'E')])
        self.assertIs(L.door, L.doors[-1])

    def test_door_from_latest(self):
        doors = [{'zone': 'A', 'to': 'B'}, {'zone': 'B', 'to': 'A'}, {'zone': 'A', 'to': 'C'}]
        self.assertEqual(P.door_from('A', doors)['to'], 'C')        # where its path went on the last time it was there
        self.assertEqual(P.door_from('B', doors)['to'], 'A')
        self.assertIsNone(P.door_from('D', doors))
        self.assertIsNone(P.door_from('', doors))
        self.assertIsNone(P.door_from('A', None))

    def test_zone_age_and_doors_sent(self):
        L = self.make('leader')
        self.walk(L, 'A', 0, 0, 500, 0)
        t_in = self.clock.t
        self.at(L, 'B', 0, 0)
        self.stand(L, 'B', 0, 0, secs=2.0)
        me = L._me()
        self.assertEqual(me['zage'], round((self.clock.t - t_in) * 1000))   # since its first reading in B
        self.assertEqual(len(me['doors']), 1)
        self.assertNotIn('at', me['doors'][0])                     # an age, not the leader's clock
        self.assertEqual(me['doors'][0]['age'], me['zage'])
        self.assertIs(me['doors'][0]['walked'], True)
        json.dumps(me)                                             # the answer is JSON
        # (its zone not read for FRESH s - a loading screen: no zone, no zone age)
        self.clock.t += P.FRESH + 1
        me = L._me()
        self.assertEqual((me['zone'], me['zage']), ('', None))


class Advice(PartyCase):
    def leader(self, **kw):
        L = {'zone': 'C', 'loading': '0', 'zage': 10000, 'doors': [], 'at': self.clock.t}
        L.update(kw)
        return L

    def test_teleport_when_no_door(self):
        port, why = P.port_advice('A', self.leader(), self.clock.t)
        self.assertEqual(port, '1')
        self.assertIn('no door', why)
        self.assertNotIn('|', why)

    def test_teleported_from_here(self):
        L = self.leader(doors=[{'zone': 'A', 'to': 'C', 'walked': False}])
        port, why = P.port_advice('A', L, self.clock.t)
        self.assertEqual(port, '1')
        self.assertIn('teleported', why)

    def test_not_when(self):
        t = self.clock.t
        cases = [
            ('A', None, 'not heard'),
            ('A', self.leader(at=t - 6), 'not heard from in 6 s'),
            ('A', self.leader(zone=''), "zone isn't known"),
            ('', self.leader(), "this wizard's zone"),
            ('C', self.leader(), 'same zone'),
            ('A', self.leader(loading='1'), 'loading'),
            ('A', self.leader(zage=None), 'older version'),
            ('A', self.leader(zage=1000), 'only just got'),
            ('A', self.leader(doors=[{'zone': 'A', 'to': 'B', 'walked': True}]), 'walked through'),
            # (walked not known - an older leader's helper: a door to try, as ever)
            ('A', self.leader(doors=[{'zone': 'A', 'to': 'B', 'walked': None}]), 'walked through'),
        ]
        for me_zone, L, why in cases:
            with self.subTest(why=why):
                port, said = P.port_advice(me_zone, L, t)
                self.assertEqual(port, '0')
                self.assertIn(why, said)

    def test_zone_age_counts_since_heard(self):
        # (2.5 s in its zone as sent, heard 1 s ago: 3.5 s - old enough)
        L = self.leader(zage=2500, at=self.clock.t - 1.0)
        self.assertEqual(P.port_advice('A', L, self.clock.t)[0], '1')


class Lines(PartyCase):
    def leader_row(self, follower):
        rows = [ln for ln in follower.lines() if ln.startswith('leader|')]
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(rows[0].split('|')), 39)              # (38-39: the party's hit round - hitat, seat)
        return ahk_fields(rows[0])

    def test_chain_door_out_of_own_zone(self):
        # (A -> B -> C walked: a follower in A gets the door A -> B, not the last one - it had none before)
        L, F = self.make('leader'), self.make('follower')
        self.walk(L, 'A', 0, 0, 500, 0)
        self.at(L, 'B', 0, 0)
        self.walk(L, 'B', 0, 0, 0, 500)
        self.at(L, 'C', 0, 0)
        self.stand(L, 'C', 0, 0, secs=4.0)
        self.at(F, 'A', 300, 0)
        self.follow(L, F)
        f = self.leader_row(F)
        self.assertEqual((f[3], f[14], f[20], f[33], f[36]), ('C', 'A', 'B', '1', '0'))
        self.assertAlmostEqual(float(f[18]), 1.0)
        self.assertIn('walked through', f[37])
        # (through it, in B: the door B -> C)
        self.at(F, 'B', 0, 0)
        f = self.leader_row(F)
        self.assertEqual((f[14], f[20], f[33]), ('B', 'C', '1'))

    def test_teleport_away(self):
        L, F = self.make('leader'), self.make('follower')
        self.stand(L, 'A', 50, 50)
        self.at(L, 'Home', 0, 0)
        self.stand(L, 'Home', 0, 0, secs=1.2)
        self.at(F, 'A', 300, 0)
        self.follow(L, F)
        f = self.leader_row(F)
        self.assertEqual((f[14], f[20], f[33]), ('A', 'Home', '0'))
        self.assertEqual(f[36], '0')                               # under PORT_ZONE_AGE s there: not yet
        self.assertIn('only just got', f[37])
        self.stand(L, 'Home', 0, 0, secs=3.2)
        self.at(F, 'A', 300, 0)
        self.follow(L, F)
        f = self.leader_row(F)
        self.assertEqual(f[36], '1')
        self.assertGreaterEqual(int(f[34]), 3000)                  # its zone's age
        self.assertGreaterEqual(int(f[35]), int(f[34]))            # the door's: older

    def test_long_in_its_zone(self):
        # (17 minutes in Home, its door 20 minutes old - past 1e6 ms: they read as no age, "an older version", and the
        # teleport advice never came)
        L, F = self.make('leader'), self.make('follower')
        self.stand(L, 'A', 50, 50)
        self.at(L, 'Home', 0, 0)
        L.zone_at = self.clock.t - 17 * 60
        L.doors[-1]['at'] = L.door['at'] = self.clock.t - 20 * 60
        self.stand(L, 'Home', 0, 0, secs=0.4)
        self.at(F, 'A', 300, 0)
        self.follow(L, F)
        self.assertGreater(F.leader['zage'], 1000000)
        f = self.leader_row(F)
        self.assertGreaterEqual(int(f[34]), 17 * 60 * 1000)
        self.assertGreaterEqual(int(f[35]), 20 * 60 * 1000)
        self.assertEqual(f[36], '1')
        self.assertIn('teleported', f[37])

    def test_fields_known_before_stay(self):
        L, F = self.make('leader'), self.make('follower')
        L.ahk = P.clean_state({'battle': '1', 'hp': '77', 'ready': '1', 'walk': '1', 'hold': 'Bob is loading',
                               'brole': 'hitter', 'wiz': 'Ned Stormblade', 'school': 'storm', 'hits': '4', 'hitr': '9',
                               'plan': 'storm,fire', 'lasthit': 'storm', 'loading': '1'})
        L.cfg['name'] = 'Ned'
        self.walk(L, 'A', 0, 0, 500, 0)
        L.battle_spot = (11.0, 22.0, 33.0)
        self.at(L, 'B', 10, 20, 30)
        self.at(F, 'A', 0, 0)
        self.follow(L, F)
        f = self.leader_row(F)
        self.assertEqual(len(f) - 1, 39)
        # (Party.ahk PartyTick's leader fields 2-31, as ever)
        want = {2: 'Ned', 3: 'B', 4: '10', 5: '20', 6: '30', 8: '1', 9: '77', 10: '1', 11: '1', 14: 'A', 15: '1000',
                16: '0', 17: '0', 18: '1.000', 19: '0.000', 20: 'B', 21: '11', 22: '22', 23: '33', 24: 'Bob is loading',
                25: 'hitter', 26: 'Ned Stormblade', 27: 'storm', 28: '4', 29: '9', 30: 'storm,fire', 31: 'storm'}
        for k, v in want.items():
            with self.subTest(field=k):
                self.assertEqual(f[k], v)
        self.assertEqual(f[7], '0.0000')                            # its yaw
        self.assertTrue(f[12].isdigit())                            # the answer's age (ms)
        self.assertEqual(f[13], '')                                 # another zone: no distance
        # (the new ones: 32 loading, 33 dwalk, 36 port - it's loading: not now)
        self.assertEqual((f[32], f[33], f[36]), ('1', '1', '0'))
        self.assertIn('loading', f[37])

    def test_older_leader(self):
        # (a leader running the helper before this: one door, no walked, no ages, no zone age - fields 14-20 as before)
        F = self.make('follower')
        self.at(F, 'A', 0, 0)
        old = {'name': 'Ned', 'zone': 'B', 'x': 1, 'y': 2, 'z': 3, 'loading': '0',
               'door': {'zone': 'A', 'x': 10, 'y': 20, 'z': 0, 'dx': 0.6, 'dy': 0.8, 'to': 'B', 'at': 12345.0},
               'bspot': None}
        F.leader = dict(P.clean_peer(old), at=self.clock.t, others=[])
        self.assertEqual(len(F.leader['doors']), 1)
        self.assertIsNone(F.leader['doors'][0]['walked'])
        f = self.leader_row(F)
        self.assertEqual((f[14], f[15], f[16], f[18], f[19], f[20]), ('A', '10', '20', '0.600', '0.800', 'B'))
        self.assertEqual((f[33], f[34], f[35], f[36]), ('', '', '', '0'))
        self.assertIn('older version', f[37])

    def test_older_follower_reads_new_leader(self):
        # (a follower running the helper before this reads the new answer's door as ever: the doors list and the zone's
        # age aren't text or numbers it takes)
        L = self.make('leader')
        self.walk(L, 'A', 0, 0, 500, 0)
        self.at(L, 'B', 0, 0)
        d = json.loads(json.dumps(L.beat_in({'id': 'ab'}, '10.0.0.2')))
        old_view = {k: str(v) for k, v in d['leader'].items() if isinstance(v, (str, int, float))}
        self.assertNotIn('doors', old_view)
        self.assertEqual(d['leader']['door']['zone'], 'A')
        self.assertEqual(P.clean_state(old_view)['zone'], 'B')

    def test_me_line_not_stale(self):
        F = self.make('follower')
        self.at(F, 'A', 5, 6)
        self.assertEqual(ahk_fields(F.lines()[1])[2], 'A')
        self.clock.t += P.FRESH + 1                                 # a loading screen: nothing read since
        f = ahk_fields(F.lines()[1])
        self.assertEqual((f[1], f[2], f[3]), ('me', '', ''))


class TeleportState(PartyCase):
    def test_tp_cleaned(self):
        s = P.clean_state({'tp': 'wait', 'tpwhy': 'no door the leader walked through leads to WizardCity/WC_Commons'})
        self.assertEqual(s['tp'], 'wait')
        self.assertTrue(s['tpwhy'].startswith('no door'))
        self.assertEqual(P.clean_state({'tp': 'buy crowns', 'tpwhy': 'x'})['tp'], '')
        self.assertEqual(P.clean_state({'tp': 'wait', 'tpwhy': 'a|b'})['tpwhy'], '')
        self.assertEqual(P.clean_state({'tpwhy': 'nothing to say it for'})['tpwhy'], '')   # no tp, no why
        self.assertEqual(P.clean_state({})['tp'], '')

    def test_member_rows_carry_tp(self):
        L, F, G = self.make('leader'), self.make('follower'), self.make('follower')
        self.at(L, 'A', 0, 0)
        self.at(F, 'B', 0, 0)
        F.ahk = P.clean_state({'name': 'Bob', 'tp': 'wait', 'tpwhy': 'the leader teleported from here to Home'})
        F.cfg['name'] = 'Bob'
        self.follow(L, F)
        rows = [ahk_fields(ln) for ln in L.lines() if ln.startswith('member|')]
        self.assertEqual(len(rows), 1)
        f = rows[0]
        self.assertEqual(len(f) - 1, 39)                            # padded as Party.ahk pads
        self.assertEqual(len(L.lines()[-1].split("|")), 25)         # (24-25: the hit round - hitat, seat)
        why = 'the leader teleported from here to Home'
        self.assertEqual((f[2], f[3], f[13], f[22], f[23]), ('Bob', 'B', '0', 'wait', why))
        # (another follower sees Bob's the same way - the leader passes it on)
        self.at(G, 'A', 0, 0)
        d = self.follow(L, G)
        others = []
        for o in d['others']:
            c = P.clean_state({k: str(v) for k, v in o.items() if isinstance(v, (str, int, float))})
            c['age'] = int(o['age'])
            others.append(c)
        G.leader['others'] = others
        rows = [ahk_fields(ln) for ln in G.lines() if ln.startswith('member|')]
        self.assertEqual((rows[0][2], rows[0][22], rows[0][23]), ('Bob', 'wait', why))

    def test_beat_query(self):
        F = self.make('follower')
        F.cfg['name'] = 'Bob'
        F.ahk = P.clean_state({'name': 'Bob', 'tp': 'stuck', 'tpwhy': 'stuck on the way to the leader', 'hold': ''})
        self.walk(F, 'A', 0, 0, 500, 0)
        self.at(F, 'B', 0, 0)
        q = F._beat_query()
        for k in ('door', 'doors', 'bspot', 'zage'):
            self.assertNotIn(k, q)
        self.assertEqual((q['tp'], q['id']), ('stuck', F.id))
        # (an everyday long one - a 40-character zone, a 70-character why and hold, every school: all of it sent)
        F.ahk = P.clean_state({'name': 'Bob', 'wiz': 'Bob Stormblade', 'tp': 'wait', 'tpwhy': 'x' * 70,
                               'hold': 'Ned is in another zone (stuck on its way)', 'plan': ','.join(P.SCHOOLS)})
        self.at(F, 'WizardCity/WC_Streets/Interiors/WC_Ravenwood', 1234.5, -5678.5, 90.25)
        q = F._beat_query()
        self.assertEqual((q['tpwhy'], q['hold']), ('x' * 70, 'Ned is in another zone (stuck on its way)'))
        # (the longest the checks let by - each field of the characters the URL makes 3 of: a 120-character zone of
        # backslashes, 24-character names and an 80-character hold and why of apostrophes, every school: ~1300, over the
        # server's 1024 - its why and hold left out till it fits, the rest kept)
        F.ahk = P.clean_state({'name': "'" * 24, 'wiz': "'" * 24, 'tp': 'wait', 'tpwhy': "'" * 80,
                               'hold': "'" * 80, 'plan': ','.join(P.SCHOOLS), 'lasthit': ','.join(P.SCHOOLS),
                               'hits': '999999', 'hitr': '999999', 'hp': '100', 'brole': 'healer', 'school': 'balance',
                               'hitat': '99', 'seat': '7'})
        F.cfg['name'] = "'" * 24
        self.at(F, '\\' * 120, -99999.5, -99999.5, -99999.5)
        self.assertEqual(len(F._me()['zone']), 120)
        full = dict(F._me(), id=F.id)
        full = {k: ('' if v is None else v) for k, v in full.items() if k not in ('door', 'doors', 'bspot', 'zage')}
        self.assertGreater(len('/party/beat?' + urllib.parse.urlencode(full)), P.MAX_PATH)
        path = '/party/beat?' + urllib.parse.urlencode(F._beat_query())
        self.assertLessEqual(len(path), P.MAX_PATH)
        got = P.clean_state({k: v[0] for k, v in urllib.parse.parse_qs(path.split('?', 1)[1]).items()})
        self.assertEqual((got['tp'], got['zone'], got['name'], got['wiz']), ('wait', '\\' * 120, "'" * 24, "'" * 24))
        self.assertEqual((got['tpwhy'], got['hold']), ('', ''))
        # (the hit round kept: its why and hold were enough)
        self.assertEqual((got['hitat'], got['seat']), (99, 7))
        # (and were it still over - a smaller server -: the seat, then hitat, go before the rest)
        keep = P.MAX_PATH
        try:
            P.MAX_PATH = len(path) - 1
            q = F._beat_query()
            self.assertEqual((q['seat'], q['hitat'], q['zone']), ('', 99, '\\' * 120))
            P.MAX_PATH = len(path) - 30
            q = F._beat_query()
            self.assertEqual((q['seat'], q['hitat']), ('', ''))
        finally:
            P.MAX_PATH = keep


class HitRound(PartyCase):
    """the party's hit round (v1.0.0): the hitter's hitat - the log round its planned hit goes out - and each wizard's
    seat, from AutoFarmer to the party and back (leader| 38-39, member| 24-25)"""

    def test_cleaned(self):
        s = P.clean_state({'hitat': '7', 'seat': '5'})
        self.assertEqual((s['hitat'], s['seat']), (7, 5))
        for bad in ('0', '100', '-3', '7.5', 'nan', 'soon', '', None):
            with self.subTest(hitat=bad):
                self.assertIsNone(P.clean_state({'hitat': bad})['hitat'])
        for bad in ('3', '8', '4.2', 'x', ''):
            with self.subTest(seat=bad):
                self.assertIsNone(P.clean_state({'seat': bad})['seat'])

    def test_to_the_followers_and_back(self):
        L, F, G = self.make('leader'), self.make('follower'), self.make('follower')
        self.at(L, 'A', 0, 0)
        self.at(F, 'A', 10, 0)
        self.at(G, 'A', 20, 0)
        L.ahk = P.clean_state({'battle': '1', 'brole': 'hitter', 'wiz': 'Ned Stormblade', 'hitat': '6', 'seat': '4'})
        F.ahk = P.clean_state({'name': 'Bob', 'battle': '1', 'brole': 'blader', 'wiz': 'Bob Fireheart', 'seat': '5'})
        F.cfg['name'] = 'Bob'
        self.follow(L, F)
        f = ahk_fields(next(ln for ln in F.lines() if ln.startswith('leader|')))
        self.assertEqual((f[25], f[38], f[39]), ('hitter', '6', '4'))
        # (the leader's own rows: Bob's seat, no hitat)
        m = ahk_fields(next(ln for ln in L.lines() if ln.startswith('member|')))
        self.assertEqual((m[2], m[24], m[25]), ('Bob', '', '5'))
        # (another follower sees Bob's the same way - the leader passes it on)
        d = self.follow(L, G)
        others = []
        for o in d['others']:
            c = P.clean_state({k: str(v) for k, v in o.items() if isinstance(v, (str, int, float))})
            c['age'] = int(o['age'])
            others.append(c)
        G.leader['others'] = others
        m = ahk_fields(next(ln for ln in G.lines() if ln.startswith('member|')))
        self.assertEqual((m[2], m[24], m[25]), ('Bob', '', '5'))

    def test_older_bots(self):
        # (a bot sending no hitat / seat - an older one: blank fields, its supports cast as ever; an older helper's
        # answer read the same way)
        L, F = self.make('leader'), self.make('follower')
        self.at(L, 'A', 0, 0)
        self.at(F, 'A', 0, 0)
        L.ahk = P.clean_state({'battle': '1', 'brole': 'hitter'})
        self.follow(L, F)
        f = ahk_fields(next(ln for ln in F.lines() if ln.startswith('leader|')))
        self.assertEqual((f[38], f[39]), ('', ''))
        F.leader = dict(P.clean_peer({'name': 'Ned', 'zone': 'A', 'brole': 'hitter'}), at=self.clock.t, others=[])
        f = ahk_fields(next(ln for ln in F.lines() if ln.startswith('leader|')))
        self.assertEqual((f[25], f[38], f[39]), ('hitter', '', ''))
        # (a bot that reads only fields 2-37 / 2-23 - an older Party.ahk - finds them where they were)
        self.assertEqual(len(next(ln for ln in F.lines() if ln.startswith('leader|')).split('|')[:37]), 37)


class Clean(unittest.TestCase):
    def test_doors_cleaned(self):
        s = P.clean_peer({'zone': 'B', 'doors': [{'zone': 'A\n', 'to': 'B'}, 'junk', None,
                                                 {'zone': 'C', 'to': 'D', 'x': 'nan', 'walked': 'yes', 'age': -5},
                                                 {'zone': 'D', 'to': 'E', 'x': 1, 'walked': 0, 'age': 250.7}]})
        self.assertEqual([d['zone'] for d in s['doors']], ['C', 'D'])   # the last three sent, the junk left out
        self.assertEqual((s['doors'][0]['x'], s['doors'][0]['walked'], s['doors'][0]['age']), (None, None, None))
        self.assertEqual((s['doors'][1]['walked'], s['doors'][1]['age']), (False, 250))
        s = P.clean_peer({'doors': [{'zone': 'A\n', 'to': 'B|C'}]})
        self.assertEqual((s['doors'][0]['zone'], s['doors'][0]['to']), ('', ''))   # nothing that breaks a line
        self.assertEqual(P.clean_peer({'doors': 'A'})['doors'], [])
        self.assertEqual(P.clean_peer({})['doors'], [])
        self.assertIsNone(P.clean_peer({'zage': 'soon'})['zage'])
        self.assertEqual(P.clean_peer({'zage': 4000})['zage'], 4000)
        self.assertEqual(P.clean_peer('not a dict')['doors'], [])

    def test_ages_past_16_minutes(self):
        # (ms ages aren't places: 1e6 - _f's cap - is 16.7 minutes; up to ~11 days taken)
        self.assertEqual((P._ms(999999), P._ms(1000000), P._ms('1200000'), P._ms(1026000.7)),
                         (999999, 1000000, 1200000, 1026000))
        for junk in (1e9, -1, 'nan', 'inf', None, '', 'soon', True, [5]):
            with self.subTest(age=junk):
                self.assertIsNone(P._ms(junk))
        s = P.clean_peer({'zage': 1026000, 'doors': [{'zone': 'A', 'to': 'Home', 'walked': 0, 'age': 1200000}]})
        self.assertEqual((s['zage'], s['doors'][0]['age']), (1026000, 1200000))


# ============================================================================ partyorders (TODO goal 3 - advice only)
def hcard(name, tid, kind, pips=0, vtext='', vench='', ench_effect='', school='Storm'):
    """a card as handmem's reading has it (the fields hand_of reads)"""
    return {'name': name, 'display': name, 'template_id': tid, 'kind': kind, 'pips': pips, 'school': school,
            'value_text': vtext, 'value_ench': vench, 'ench_effect': ench_effect}


def rd(cards, pips=None, settled=True):
    """a HandMem.read() reading, shaped as test_plan's reading(): 3 generic, 2 power, 1 storm and 1 shadow pip"""
    pp = {'generic': 3, 'power': 2, 'balance': 0, 'death': 0, 'fire': 0, 'ice': 0, 'life': 0, 'myth': 0, 'storm': 1,
          'shadow': 1}
    pp.update(pips or {})
    return {'in_battle': True, 'planning': True, 'settled': settled, 'state': 'hand' if settled else 'changing',
            'me': {'health': 2500, 'max_health': 3000, 'school': 'storm', 'pips': pp}, 'cards': cards}


LORD = hcard('Storm Lord', 101, 'damage', 7, '1000-1130')
BLADE = hcard('Stormblade', 104, 'blade', 0, '35%')
SNAKE = hcard('Thunder Snake', 102, 'damage', 2, '150-170')
SNAKE_E = hcard('Thunder Snake', 102, 'damage', 2, '150-170', '325-345', 'kModifyCardDamage +175')
TOWER = hcard('Tower Shield', 300, 'ward', 0, '50%')
RESH = hcard('Reshuffle', 301, 'manipulation', 0, '')
EPIC = hcard('Epic', 302, 'enchant', 0, '+275')
HAND6 = [LORD, BLADE, SNAKE_E, TOWER, RESH, EPIC]
BOB_HAND = 'd12r5~5~0~2500~3000~6~3~101:damage:7:storm:1000-1130;104:blade:0:storm:35%'
TEAM = ('Bob Fireheart~5~fire~2000~3000~blader~~~|Ann Stormy~6~storm~1500~3000~hitter~~~|'
        'Cid Lifey~7~life~~3000~healer~~~|Dee Deathly~4~death~~3000~hitter~~~')
FB, FA, FC = 'b0b0', 'a0a0', 'c0c0'


class Orders(PartyCase):
    """partyorders: a follower's hand to the leader once it asks, the leader's team plan's card for it back - advice
    only; off at either end: the beats and answers as before"""

    def follower(self, orders='1', battle='1'):
        F = self.make('follower')
        F.cfg['orders'] = orders
        F.cfg['name'] = 'Bob'
        F.ahk = P.clean_state({'name': 'Bob', 'battle': battle, 'brole': 'blader', 'wiz': 'Bob Fireheart', 'seat': '5'})
        self.at(F, 'A', 10, 0)
        return F

    def twin(self, F):
        """a follower like F in every way the beat reads (its state, settings, place and id) that never had a hand"""
        G = self.make('follower')
        G.cfg.update(F.cfg)
        G.ahk, G.mem, G.id = dict(F.ahk), dict(F.mem), F.id
        return G

    def leader(self, orders='1', plans='1'):
        L = self.make('leader')
        L.cfg['orders'], L.cfg['plans'] = orders, plans
        L.ahk = P.clean_state({'battle': '1', 'brole': 'hitter', 'wiz': 'Ned Stormblade', 'seat': '4'})
        self.at(L, 'A', 0, 0)
        return L

    def follow2(self, L, F, ip='192.168.1.20'):
        """F's beat to L and L's answer through JSON, F taking it as _beat_out does"""
        d = json.loads(json.dumps(L.beat_in({'id': F.id, **F._beat_query()}, ip)))
        F._took(d)
        return d

    def heard(self, F, hands=None, order=None):
        """F hears from its leader now: an answer with hands (the ask) and order"""
        d = {'v': 1, 'leader': {'name': 'Ned', 'zone': 'A'}, 'others': []}
        if hands is not None:
            d['hands'] = hands
        if order is not None:
            d['order'] = order
        F._took(json.loads(json.dumps(d)))

    def team(self, ann='d9r4~4~0~1500~3000~2~0~777:damage:0:storm:95'):
        """a leader with Bob's (round 5), Ann's (round 4) hands in and Cid sending none"""
        L = self.leader()
        for fid, wiz, seat in ((FB, 'Bob Fireheart', '5'), (FA, 'Ann Stormy', '6'), (FC, 'Cid Lifey', '7')):
            L.members[fid] = dict(P.clean_state({'wiz': wiz, 'seat': seat, 'battle': '1'}), at=self.clock.t, ip='x')
        L.hands[FB] = dict(P.clean_hand(BOB_HAND), at=self.clock.t)
        L.hands[FA] = dict(P.clean_hand(ann), at=self.clock.t)
        return L

    def answer(self, L, fid, battle='1'):
        return json.loads(json.dumps(L.beat_in({'id': fid, 'battle': battle}, '192.168.1.20')))

    def test_cfg_defaults(self):
        F, L = self.make('follower'), self.make('leader')
        for p in (F, L):
            self.assertEqual((p.cfg['orders'], p.cfg['plans']), ('', ''))
            p._beat_query()
            p.beat_in({'id': 'ab'}, '10.0.0.2')
            self.assertEqual(p.path_max(), P.MAX_PATH)
            self.assertTrue(p.order_line('d1r1').startswith('order|none|1|'))
            self.assertEqual(p.lead_count(), 0)
            self.assertEqual(p.no_plan(1), 0)

    def test_hand_of(self):
        cards = HAND6 + [hcard('No Kind', 999, None), hcard('No Tid', None, 'damage'), hcard('Bool Tid', True, 'damage')]
        h = P.hand_of(rd(cards))
        self.assertEqual((h['pips'], h['power'], h['hp'], h['max']), (6, 3, 2500, 3000))
        got = [(c['tid'], c['kind'], c['pips'], c['school'], c['value'], c['ench'], c['mark'], c['gi']) for c in h['cards']]
        self.assertEqual(got, [(101, 'damage', 7, 'storm', '1000-1130', None, '', 0),
                               (104, 'blade', 0, 'storm', '35%', None, '', 1),
                               (102, 'damage', 2, 'storm', '150-170', 175, '', 2),     # (the plain value, ench apart)
                               (300, 'ward', 0, 'storm', '50%', None, 'tower', 3),
                               (301, 'manipulation', 0, 'storm', '', None, 'resh', 4),
                               (302, 'enchant', 0, 'storm', '+275', None, 'epic', 5)])
        self.assertEqual(h['cards'][0]['name'], 'Storm Lord')               # (kept here - never sent)
        self.assertIsNone(P.hand_of(rd(cards, settled=False)))
        self.assertIsNone(P.hand_of(rd([hcard('No Kind', 999, None)])))      # (no card: not known, never empty)
        self.assertEqual(len(P.hand_of(rd([dict(LORD, template_id=k) for k in range(12)]))['cards']), 9)
        for junk in (None, 'x', {}, {'in_battle': True}, rd('junk'), rd([None, 5, 'x'])):
            self.assertIsNone(P.hand_of(junk))

    def test_wire_round_trip(self):
        t = self.clock.t
        h = P.hand_of(rd(HAND6))
        wire = P.hand_wire({'tag': 'd12r5', 'round': 5, 'at': t, 'hand': h}, t + 1.83)
        self.assertTrue(wire.startswith('d12r5~5~1830~2500~3000~6~3~101:damage:7:storm:1000-1130;104:blade:0:storm:35%;'
                                        '102:damage:2:storm:150-170:175;300:ward:0:storm:50%::tower;'), wire)
        self.assertTrue(wire.endswith(';301:manipulation:0:storm:::resh;302:enchant:0:storm:+275::epic'), wire)
        c = P.clean_hand(wire)
        self.assertEqual((c['tag'], c['round'], c['age'], c['hp'], c['max'], c['pips'], c['power']),
                         ('d12r5', 5, 1830, 2500, 3000, 6, 3))
        self.assertEqual(c['cards'], [{k: x[k] for k in ('tid', 'kind', 'pips', 'school', 'value', 'ench', 'mark')}
                                      for x in h['cards']])
        self.assertNotIn('name', c['cards'][0])
        self.assertNotIn('gi', c['cards'][0])
        # (the stash's round - the battle recorder's - not the tag's)
        self.assertTrue(P.hand_wire({'tag': 'd12r5', 'round': 6, 'at': t, 'hand': h}, t).startswith('d12r5~6~0~'))
        for junk in ('x12r5~5~0~1~1~1~1~101:damage:7:storm:1', 'd12r0~0~0~1~1~1~1~101:damage:7:storm:1',
                     'd12r5~5~-1~1~1~1~1~101:damage:7:storm:1', '', None, 12,
                     'd1r1~1~0~~~0~0~abc:damage::storm:1;1:DAMAGE!::x:1'):
            with self.subTest(junk=junk):
                self.assertIsNone(P.clean_hand(junk))
        c = P.clean_hand('d1r1~1~0~~~0~0~101:damage:7:storm:1000-1130;12345678901:aoe:1:x:1')
        self.assertEqual([x['tid'] for x in c['cards']], [101])
        self.assertEqual((c['hp'], c['max']), (None, None))
        c = P.clean_hand('d1r1~1~0~1~1~99~0~101:damage:7:storm:10 0;102:damage:2:storm:1:12345;300:ward:0:storm:1::TOWER!')
        self.assertEqual([(x['value'], x['ench'], x['mark']) for x in c['cards']], [('', None, ''), ('1', None, ''),
                                                                                 ('1', None, '')])
        self.assertEqual(c['pips'], 0)                                     # (99: not a pip count)

    def test_off_byte_identical(self):
        # (a) both off: a follower that once had a hand beats exactly as one that never had
        F = self.follower()
        F.saw_hand(rd(HAND6), 'd12r5')
        self.assertIsNotNone(F.stash)
        F.cfg['orders'] = ''
        G = self.twin(F)
        L = self.leader(orders='', plans='')
        self.assertEqual(list(self.follow2(L, F)), ['v', 'leader', 'others'])
        self.assertNotIn('hand', F._beat_query())
        self.assertEqual(urllib.parse.urlencode(F._beat_query()), urllib.parse.urlencode(G._beat_query()))
        self.assertEqual(L.path_max(), P.MAX_PATH)
        # (b) the leader on, the follower off: its beats as ever; the answer only gains the top-level 'hands'
        L.cfg['orders'] = L.cfg['plans'] = '1'
        d_on = self.follow2(L, F)
        self.assertEqual(urllib.parse.urlencode(F._beat_query()), urllib.parse.urlencode(G._beat_query()))
        self.assertEqual(list(d_on), ['v', 'leader', 'others', 'hands'])
        self.assertEqual(L.path_max(), 2048)
        L.cfg['orders'] = L.cfg['plans'] = ''
        d_off = json.loads(json.dumps(L.beat_in({'id': F.id, **F._beat_query()}, '192.168.1.20')))
        self.assertEqual(json.dumps({k: v for k, v in d_on.items() if k != 'hands'}), json.dumps(d_off))
        # (c) orders on, not planning: answers as an off leader's - but its server still takes 2048
        L.cfg['orders'] = '1'
        d_c = json.loads(json.dumps(L.beat_in({'id': F.id, **F._beat_query()}, '192.168.1.20')))
        self.assertEqual(json.dumps(d_c), json.dumps(d_off))
        self.assertEqual(L.path_max(), 2048)
        # (a follower with it off keeps no hand)
        H = self.follower(orders='')
        H.saw_hand(rd(HAND6), 'd12r5')
        self.assertIsNone(H.stash)

    def test_handshake(self):
        L, F, G = self.leader(), self.follower(), self.follower()
        G.id = 'abcdef12'
        F.saw_hand(rd(HAND6), 'd12r5')
        self.assertNotIn('hand', F._beat_query())                         # (no ask yet)
        d = self.follow2(L, F)
        self.assertEqual(d['hands'], {'max': 2048, 'got': ''})
        q = F._beat_query()
        self.assertEqual(list(q)[-2:], ['id', 'hand'])
        d = json.loads(json.dumps(L.beat_in({'id': F.id, **q}, '192.168.1.20')))
        F._took(d)
        self.assertEqual(L.hands[F.id]['round'], 5)
        self.assertEqual(d['hands']['got'], 'd12r5')
        self.assertNotIn('order', d)
        self.assertEqual(L.path_max(), 2048)
        # (the hand is never in the members' rows, nor in what the other followers get)
        rows = [ln for ln in L.lines() if ln.startswith('member|')]
        self.assertEqual(len(rows), 1)
        self.assertEqual(len(rows[0].split('|')), 25)
        self.assertNotIn('d12r5', rows[0])
        self.assertNotIn(':damage:', rows[0])
        dg = self.follow2(L, G)
        self.assertEqual(len(dg['others']), 1)
        self.assertNotIn('hand', dg['others'][0])
        self.assertNotIn('d12r5', json.dumps(dg['others']))
        # (the leader stops planning - plans no longer sent: hands and orders gone, no more asks, the server as it was)
        L._serve = lambda: None
        L.update({'role': 'leader', 'orders': '1', 'battle': '1'})
        self.assertEqual((L.hands, L.orders), ({}, {}))
        d = self.follow2(L, F)
        self.assertNotIn('hands', d)
        self.assertIsNone(F.asked)
        self.assertNotIn('hand', F._beat_query())
        self.assertEqual(L.path_max(), 2048)

    def adversarial(self, F):
        """F's state as test_beat_query's longest: ~1316 characters of beat without a hand"""
        F.ahk = P.clean_state({'name': "'" * 24, 'wiz': "'" * 24, 'tp': 'wait', 'tpwhy': "'" * 80, 'battle': '1',
                               'hold': "'" * 80, 'plan': ','.join(P.SCHOOLS), 'lasthit': ','.join(P.SCHOOLS),
                               'hits': '999999', 'hitr': '999999', 'hp': '100', 'brole': 'healer', 'school': 'balance',
                               'hitat': '99', 'seat': '7'})
        F.cfg['name'] = "'" * 24
        self.at(F, '\\' * 120, -99999.5, -99999.5, -99999.5)

    def test_size_limit(self):
        F = self.follower()
        self.adversarial(F)
        G = self.twin(F)
        card = {'tid': 9999999999, 'kind': 'enchant', 'pips': 14, 'school': 'balance', 'value': '+125%', 'ench': None,
                'mark': 'gargantuan', 'gi': 0, 'name': 'Gargantuan'}
        F.stash = {'tag': 'd999999999r999', 'round': 999, 'at': self.clock.t,
                   'hand': {'hp': 999999, 'max': 999999, 'pips': 14, 'power': 14, 'cards': [dict(card)] * 9}}
        F.asked = {'max': 2048, 'got': ''}
        F.leader = dict(P.clean_peer({}), at=self.clock.t, others=[])
        q = F._beat_query()
        path = '/party/beat?' + urllib.parse.urlencode(q)
        self.assertIn('hand', q)
        self.assertGreater(len(path), P.MAX_PATH)
        self.assertLessEqual(len(path), P.MAX_PATH_HANDS)
        self.assertEqual((q['tpwhy'], q['hold']), ("'" * 80, "'" * 80))  # (not blanked: the new leader takes 2048)
        self.assertEqual(P.clean_hand(q['hand'])['round'], 999)
        # (a leader's server that takes less than the beat with its hand: the hand left out first, the rest as ever)
        F.asked['max'] = len(path) - 1
        q = F._beat_query()
        self.assertNotIn('hand', q)
        self.assertEqual((q['tpwhy'], q['hold']), ('', ''))
        self.assertEqual(urllib.parse.urlencode(q), urllib.parse.urlencode(G._beat_query()))
        # (a typical blader in battle with a 7-card hand: fits even an older leader's 1024)
        T = self.follower()
        self.at(T, 'WizardCity/WC_Streets/Interiors/WC_Ravenwood_Battle', 1234.5, -5678.5, 90.25)
        T.saw_hand(rd([LORD, BLADE, SNAKE, SNAKE, hcard('Storm Trap', 105, 'trap', 0, '30%'),
                       hcard('Tempest', 103, 'aoe', 6, '400-460'), hcard('Storm Shark', 107, 'damage', 3, '300-340')]),
                   'd12r5')
        T.asked = {'max': 2048, 'got': ''}
        T.leader = dict(P.clean_peer({}), at=self.clock.t, others=[])
        q = T._beat_query()
        self.assertIn('hand', q)
        self.assertLessEqual(len('/party/beat?' + urllib.parse.urlencode(q)), P.MAX_PATH)

    def test_old_leader(self):
        F = self.follower()
        F.saw_hand(rd(HAND6), 'd12r5')
        F._took({'v': 1, 'leader': {'name': 'Ned', 'zone': 'A'}, 'others': []})
        self.assertIsNone(F.asked)
        self.assertNotIn('hand', F._beat_query())
        line = F.order_line('d12r5')
        self.assertTrue(line.startswith('order|none|5|'), line)
        self.assertTrue(line.endswith("(an older version, partyorders or planner off there, its bot off or unable to "
                                      "read the game)"), line)

    def worst_leader(self):
        """a leader with the longest state the checks let by, three doors of 120-character zones and three followers
        as long"""
        L = self.leader()
        L.ahk = P.clean_state({'name': "'" * 24, 'wiz': "'" * 24, 'battle': '1', 'hold': "'" * 80,
                               'plan': ','.join(P.SCHOOLS), 'lasthit': ','.join(P.SCHOOLS), 'hits': '999999',
                               'hitr': '999999', 'hp': '100', 'brole': 'hitter', 'school': 'balance', 'hitat': '99',
                               'seat': '4'})
        L.cfg['name'] = "'" * 24
        for z in ('\\' * 119 + 'A', '\\' * 119 + 'B', '\\' * 119 + 'C', '\\' * 119 + 'D'):
            self.walk(L, z, -99999.5, -99999.5, 500, 0)
        L.battle_spot = (-99999.5, -99999.5, -99999.5)
        return L

    def test_old_follower_reads_new_answer(self):
        F = self.follower()
        self.adversarial(F)
        F.saw_hand(rd(HAND6), 'd12r5')
        widths = {}
        for on in ('', '1'):
            L = self.worst_leader()
            L.cfg['orders'] = L.cfg['plans'] = on
            others = [self.follower() for _ in range(2)]
            for k, o in enumerate(others):
                o.id = '%08x' % (k + 7)
                self.adversarial(o)
                self.follow2(L, o)
            self.follow2(L, F)
            self.follow2(L, F)
            if on:
                L.orders[F.id] = {'tag': 'd12r5', 'round': 5, 'i': 1, 'tid': 9999999999, 'kind': 'enchantother',
                                  'target': 'x' * 40, 'won': 100, 'n': 1000000, 'why': '', 'at': self.clock.t}
            d = self.follow2(L, F)
            self.assertEqual(('hands' in d, 'order' in d), (bool(on), bool(on)))
            self.assertLess(len(json.dumps(d)), 16384)
            # (an older follower reads the leader and the others only)
            self.assertFalse({'hands', 'order'} & set(P.clean_peer(d['leader'])))
            old = self.make('follower')
            old.mem = dict(F.mem)
            others = []
            for o in d['others']:
                c = P.clean_state({k: str(v) for k, v in o.items() if isinstance(v, (str, int, float))})
                c['age'] = int(o['age'])
                others.append(c)
            old.leader = dict(P.clean_peer(d['leader']), at=self.clock.t, others=others)
            widths[on] = sorted({(ln.split('|')[0], len(ln.split('|'))) for ln in old.lines()
                                 if ln.startswith(('leader|', 'member|'))})
        self.assertEqual(widths[''], [('leader', 39), ('member', 25)])
        self.assertEqual(widths['1'], widths[''])

    def test_403_clears_ask(self):
        F = self.follower()
        F.saw_hand(rd(HAND6), 'd12r5')
        self.heard(F, hands={'max': 2048, 'got': ''})
        self.assertIn('hand', F._beat_query())
        F._fail('the leader answered 403')
        self.assertIsNone(F.asked)
        self.assertNotIn('hand', F._beat_query())

    def test_fill_mates(self):
        L = self.team()
        text, used, notes = L.fill_mates(TEAM, 5)
        specs = text.split('|')
        self.assertEqual(len(specs), 3)                                   # (Dee: the 4th - plan_mates keeps 3)
        self.assertEqual(specs[0], 'Bob Fireheart~5~fire~2500~3000~blader~6~3~101:damage:7:storm:1000-1130;'
                                   '104:blade:0:storm:35%')
        self.assertEqual(specs[1:], TEAM.split('|')[1:3])
        self.assertEqual(used, [{'fid': FB, 'tag': 'd12r5', 'duel': '12', 'name': 'Bob Fireheart'},
                                {'fid': FA, 'tag': '', 'duel': '9', 'name': 'Ann Stormy', 'why': 'late'}, None])
        self.assertTrue(any("Ann Stormy: its hand is round 4's, not this round's (5)" in n for n in notes), notes)
        self.assertTrue(any('Cid Lifey: no hand from its bot' in n for n in notes), notes)
        self.assertFalse(any('Dee' in n for n in notes), notes)
        # (41 s on - its member still heard from: Bob's hand too old)
        self.clock.t += 41
        for m in L.members.values():
            m['at'] = self.clock.t
        _t, used, notes = L.fill_mates(TEAM, 5)
        self.assertEqual(used[0], {'fid': FB, 'tag': '', 'duel': '12', 'name': 'Bob Fireheart', 'why': 'old'})
        self.assertTrue(any('Bob Fireheart: its hand is 41 s old' in n for n in notes), notes)
        # (matched by the name's letters - WalkLetters' - and the seat when both are known)
        L = self.team()
        self.assertEqual(L.fill_mates('BOB-FIREHEART~5~fire~~3000~blader~~~', 5)[1][0]['tag'], 'd12r5')
        self.assertEqual(L.fill_mates('Bob Fireheart~~fire~~3000~blader~~~', 5)[1][0]['tag'], 'd12r5')
        t, used, notes = L.fill_mates('Bob Fireheart~6~fire~~3000~blader~~~', 5)
        self.assertEqual((t, used), ('Bob Fireheart~6~fire~~3000~blader~~~', [None]))
        self.assertIn("not one of the party's bots", notes[0])
        own = 'Bob Fireheart~5~fire~~3000~blader~~~777:damage:0:storm:95'
        self.assertEqual(L.fill_mates(own, 5)[:2], (own, [None]))         # (a hand AutoFarmer sent: as sent)
        # (ALIGNMENT: plan_team's who k is used[k - 1] - a blank spec between them dropped, as plan_mates drops it)
        L = self.team(ann='d9r5~5~0~1500~3000~2~0~777:damage:0:storm:95')
        t, used, notes = L.fill_mates('Bob Fireheart~5~fire~~3000~blader~~~|~~~~~~~~|Ann Stormy~6~storm~~3000~hitter~~~',
                                      5)
        self.assertEqual([u['fid'] for u in used], [FB, FA])
        self.assertEqual([s.split('~')[0] for s in t.split('|')], ['Bob Fireheart', 'Ann Stormy'])
        self.assertEqual(notes, [])
        try:
            import vision
        except ImportError:                               # (numpy / Pillow: the helper's own needs)
            vision = None
        if vision is not None:
            self.assertEqual([m.name for m in vision.plan_mates(t, {})], ['Bob Fireheart', 'Ann Stormy'])
            self.assertEqual([c.tid for c in vision.plan_mates(t, {})[1].hand], [777])
        # (ench and mark come out as sent)
        L = self.team()
        L.hands[FB] = dict(P.clean_hand('d12r5~5~0~2500~3000~6~3~102:damage:2:storm:150-170:175;300:ward:0:storm:50%::tower'),
                           at=self.clock.t)
        self.assertTrue(L.fill_mates(TEAM, 5)[0].split('|')[0].endswith(
            '~102:damage:2:storm:150-170:175;300:ward:0:storm:50%::tower'))
        # (partyorders off in the leader's helper: the text as it came)
        L.cfg['orders'] = ''
        t, used, notes = L.fill_mates(TEAM, 5)
        self.assertEqual((t, used), (TEAM, [None, None, None]))
        self.assertEqual(notes, ["partyorders isn't on in this helper - the mates' hands not known"])
        for junk in (None, 12, '|' * 20):
            self.assertEqual(P.Party.fill_mates(L, junk, 5)[1], [])

    def test_set_orders_and_answer(self):
        L = self.team()
        _t, used, _n = L.fill_mates(TEAM, 5)
        me = {'who': 0, 'name': 'Ned', 'seat': 4, 'i': 0, 'card': 'Storm Lord', 'tid': 101, 'kind': 'damage', 'aim': 0,
              'n': 12, 'won': 0.9}
        bob = {'who': 1, 'name': 'Bob Fireheart', 'seat': 5, 'i': 1, 'card': '?', 'tid': 104, 'kind': 'blade',
               'aim': None, 'n': 12, 'won': 0.8}
        L.set_orders([me, bob], used, ['Bonestriker'], 5)
        d = self.answer(L, FB)
        self.assertEqual(d['order'], {'tag': 'd12r5', 'duel': None, 'round': 5, 'i': 1, 'tid': 104, 'kind': 'blade',
                                      'target': '', 'won': 80, 'n': 12, 'why': '', 'age': 0})
        self.assertEqual(list(d)[-2:], ['hands', 'order'])
        d = self.answer(L, FA)
        self.assertEqual({k: d['order'][k] for k in ('tag', 'duel', 'round', 'why')},
                         {'tag': '', 'duel': '9', 'round': 5, 'why': 'late'})
        self.assertNotIn('order', self.answer(L, FC))                     # (never sent a hand: no marker)
        # (the enemy's name, cleaned; an aoe's 'all'; the card's name never sent)
        for kind, aim, foes, want in (('damage', 0, ['Bonestriker'], 'Bonestriker'), ('aoe', None, ['A'], 'all'),
                                      ('damage', 0, ['Bob (the) Boss: x'], 'Bob the Boss x'),
                                      ('damage', 5, ['A'], ''), ('trap', 0, ['A\n|B'], 'AB')):
            L.set_orders([dict(bob, kind=kind, aim=aim)], used, foes, 5)
            self.assertEqual(L.orders[FB]['target'], want)
            self.assertNotIn('card', L.orders[FB])
        # (TWO FOLLOWERS: who 1 Bob's, who 2 Ann's - by used, not by name)
        L = self.team(ann='d9r5~5~0~1500~3000~2~0~777:damage:0:storm:95')
        _t, used, _n = L.fill_mates('Bob Fireheart~5~fire~~3000~blader~~~|~~~~~~~~|Ann Stormy~6~storm~~3000~hitter~~~', 5)
        ann = dict(bob, who=2, name='Ann Stormy', i=0, tid=777, kind='damage', aim=0)
        L.set_orders([me, bob, ann], used, ['Bonestriker'], 5)
        self.assertEqual((self.answer(L, FB)['order']['tid'], self.answer(L, FA)['order']['tid']), (104, 777))
        self.assertEqual(self.answer(L, FA)['order']['target'], 'Bonestriker')
        L.set_orders([me, bob], used, ['Bonestriker'], 5)
        self.assertEqual(self.answer(L, FA)['order']['why'], 'noplay')
        # (ORDER_FRESH s on: not sent, then pruned; a follower gone from members takes its hand and order along)
        self.clock.t += 21
        self.assertNotIn('order', self.answer(L, FB))
        L._prune_orders(self.clock.t)
        self.assertNotIn(FB, L.orders)
        L.set_orders([me, bob], used, ['Bonestriker'], 5)
        L.members.pop(FA)
        L._prune_orders(self.clock.t)
        self.assertNotIn(FA, L.hands)
        self.assertNotIn(FA, L.orders)
        self.assertIn(FB, L.orders)
        # (the leader not planning: nothing kept)
        L.orders = {}
        L.cfg['plans'] = ''
        L.set_orders([me, bob], used, ['Bonestriker'], 5)
        self.assertEqual(L.orders, {})
        L.cfg['plans'] = '1'
        L.set_orders('junk', [1, 'x', {'fid': FB, 'tag': 'd12r5'}], None, 5)       # (junk: never raises)
        self.assertEqual(L.orders[FB]['why'], 'noplay')

    def test_no_plan_and_lead(self):
        L = self.team(ann='d9r5~5~0~1500~3000~2~0~777:damage:0:storm:95')
        _t, used, _n = L.fill_mates('Bob Fireheart~5~fire~~3000~blader~~~', 5)
        L.set_orders([{'who': 1, 'i': 1, 'tid': 104, 'kind': 'blade', 'aim': None, 'n': 12, 'won': 0.8}], used, [], 5)
        self.assertEqual(L.lead_count(), 2)
        self.assertEqual(L.no_plan(5), 1)
        o = self.answer(L, FA)['order']
        self.assertEqual({k: o[k] for k in ('tag', 'duel', 'round', 'why')},
                         {'tag': '', 'duel': '9', 'round': 5, 'why': 'noplan'})
        self.assertEqual(self.answer(L, FB)['order']['tid'], 104)        # (the planned one untouched)
        self.assertEqual(L.no_plan(5), 0)                                  # (said once: it may be asked every round)
        self.assertEqual(L.no_plan(6), 0)                                  # (no hand for round 6)
        # (a follower whose battle is over: its hand and order gone)
        self.answer(L, FA, battle='0')
        self.assertEqual(L.lead_count(), 1)
        self.assertNotIn(FA, L.hands)
        self.assertNotIn(FA, L.orders)
        # (a hand too old isn't counted)
        self.clock.t += P.HAND_FRESH + 1
        self.answer(L, FB)
        self.assertEqual(L.lead_count(), 0)
        # (a follower's helper, or the leader's with partyorders off or not planning: none, nothing marked)
        for cfg in ({'role': 'follower'}, {'orders': ''}, {'plans': ''}):
            M = self.team(ann='d9r5~5~0~1500~3000~2~0~777:damage:0:storm:95')
            M.cfg.update(cfg)
            self.assertEqual((M.lead_count(), M.no_plan(5)), (0, 0))
            self.assertEqual(M.orders, {})

    def test_battle_scoped(self):
        F = self.follower()
        F.saw_hand(rd(HAND6), 'd12r5')
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'},
                   order={'tag': 'd12r5', 'round': 5, 'i': 1, 'tid': 104, 'kind': 'blade', 'won': 80, 'n': 12, 'age': 0})
        self.assertIsNotNone(F.order)
        F.update({'role': 'follower', 'orders': '1', 'battle': '0', 'name': 'Bob'})
        self.assertEqual((F.stash, F.order), (None, None))
        self.assertIsNotNone(F.asked)
        self.assertNotIn('hand', F._beat_query())
        F.saw_hand(rd(HAND6), 'd12r6')
        self.assertIsNone(F.stash)                                         # (out of battle: not kept)
        # (the leader: a follower's beat out of battle drops its hand and order; its own battle over: all of them)
        L = self.team()
        _t, used, _n = L.fill_mates(TEAM, 5)
        L.set_orders([{'who': 1, 'i': 1, 'tid': 104, 'kind': 'blade', 'aim': None, 'n': 12, 'won': 0.8}], used, [], 5)
        self.assertEqual(set(L.orders), {FB, FA})
        self.answer(L, FB, battle='0')
        self.assertNotIn(FB, L.hands)
        self.assertNotIn(FB, L.orders)
        L._serve = lambda: None
        L.update({'role': 'leader', 'orders': '1', 'plans': '1', 'battle': '0'})
        self.assertEqual((L.hands, L.orders), ({}, {}))
        # (battle A's marker never reaches battle B, even when B starts at once)
        F.update({'role': 'follower', 'orders': '1', 'battle': '1', 'name': 'Bob'})
        F.saw_hand(rd(HAND6), 'd12r1')
        self.heard(F, hands={'max': 2048, 'got': 'd12r1'}, order={'tag': '', 'duel': '12', 'round': 1, 'why': 'noplan'})
        self.assertTrue(F.order_line('d12r1').startswith('order|none|1|||mark|'), F.order_line('d12r1'))
        F.update({'role': 'follower', 'orders': '1', 'battle': '0', 'name': 'Bob'})
        F.update({'role': 'follower', 'orders': '1', 'battle': '1', 'name': 'Bob'})
        F.saw_hand(rd(HAND6), 'd13r1')
        self.assertTrue(F.order_line('d13r1').startswith('order|wait|1|'), F.order_line('d13r1'))

    def test_order_line_states(self):
        F = self.follower()
        lines = []

        def ol(tag='d12r5'):
            ln = F.order_line(tag)
            lines.append(ln)
            return ahk_fields(ln, 11)
        F.cfg['role'] = 'leader'
        self.assertEqual(ol()[2:4] + ol()[11:], ['none', '5', "this PC isn't a follower"])
        F.cfg['role'] = 'follower'
        F.cfg['orders'] = ''
        self.assertEqual(ol()[11], 'partyorders is off on this PC')
        F.cfg['orders'] = '1'
        self.assertEqual(ol()[11], 'the leader not heard from')
        self.heard(F)
        self.assertIn("doesn't plan the team now", ol()[11])
        self.heard(F, hands={'max': 2048, 'got': ''})
        self.assertIn("hand wasn't read this round", ol()[11])
        F.saw_hand(rd(HAND6), 'd12r4')
        self.assertIn("hand wasn't read this round", ol()[11])
        self.assertEqual(ol('junk')[2:4], ['none', ''])
        F.saw_hand(rd(HAND6), 'd12r5')
        self.assertEqual(ol()[2:4] + ol()[11:], ['wait', '5', 'its hand is on its way to the leader'])
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'})
        self.assertEqual(ol()[2:4] + ol()[11:], ['wait', '5', 'the leader has its hand - no order yet'])
        order = {'tag': 'd12r5', 'round': 5, 'i': 1, 'tid': 104, 'kind': 'blade', 'target': '', 'won': 80, 'n': 12,
                 'age': 500, 'why': '', 'card': 'Stormblade (the leader says)'}
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order=order)
        self.clock.t += 0.25
        self.assertEqual(ol()[1:], ['order', 'ok', '5', 'Stormblade', '104', 'blade', '', '80', '12', '750', ''])
        # (by its place in the hand: two Thunder Snakes, the enchanted one the 6th)
        F.saw_hand(rd([LORD, BLADE, SNAKE, TOWER, RESH, SNAKE_E]), 'd12r5')
        for i, want in ((5, 'Thunder Snake (enchanted)'), (4, 'Thunder Snake'), (None, 'Thunder Snake')):
            self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order=dict(order, i=i, tid=102, kind='damage'))
            self.assertEqual(ol()[4], want)
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order=dict(order, i=2, tid=999, kind='damage'))
        f = ol()
        self.assertEqual((f[2], f[4], f[5], f[11]), ('ok', 'tid 999', '999', "not in this wizard's hand as last read"))
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order=dict(order, i=None, tid=None, kind='pass'))
        f = ol()
        self.assertEqual((f[2], f[4], f[5], f[6]), ('ok', 'pass', '', 'pass'))
        # (the stash's round the battle recorder's: 6 - an order for its tag's round 5 isn't for it)
        F.saw_hand(rd(HAND6), 'd12r5', ('12', 6))
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order=order)
        self.assertEqual(ol()[2:4], ['wait', '6'])
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order=dict(order, round=6))
        self.assertEqual(ol()[2:5], ['ok', '6', 'Stormblade'])
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order={'tag': '', 'duel': '12', 'round': 6, 'why': 'late'})
        self.assertEqual(ol()[2:4] + [ol()[6]], ['none', '6', 'mark'])
        # (markers: each code in this PC's own words, matched by the tag's duel and the stash's round)
        F.saw_hand(rd(HAND6), 'd12r5')
        for code in P.MARK_WHYS:
            self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order={'tag': '', 'duel': '12', 'round': 5, 'why': code})
            f = ol()
            self.assertEqual((f[2], f[6], f[11]), ('none', 'mark', P.MARK_TEXT[code]))
        for marker in ({'tag': '', 'duel': '12', 'round': 4, 'why': 'late'},
                       {'tag': '', 'duel': '13', 'round': 5, 'why': 'late'}):
            self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order=marker)
            self.assertEqual(ol()[2], 'wait')
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order=dict(order, tag='d12r4'))
        self.assertEqual(ol()[2], 'wait')
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order=dict(order, age=21000))
        self.assertEqual(ol()[2], 'wait')
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order=dict(order, age=19900))
        self.assertEqual(ol()[2], 'ok')
        self.clock.t += 0.2                                                # (its age and since heard: 20.1 s)
        self.assertEqual(ol()[2], 'wait')
        for ln in lines:
            self.assertEqual(len(ln.split('|')), 11, ln)
            self.assertNotIn('\n', ln)
            self.assertNotIn('the leader says', ln)

    def test_clean_order_and_ask(self):
        for junk in ('x', None, [1], {'round': 'x', 'tag': 'd1r1', 'kind': 'damage'}, {'round': 0, 'kind': 'damage'},
                     {'round': 1000, 'kind': 'damage'}, {'round': True, 'kind': 'damage', 'tag': 'd1r1'}):
            with self.subTest(junk=junk):
                self.assertIsNone(P.clean_order(junk))
        base = {'tag': 'd1r1', 'round': 1, 'kind': 'damage'}
        self.assertIsNone(P.clean_order(dict(base, kind='DAMAGE!')))
        self.assertIsNone(P.clean_order(dict(base, tag='junk')))
        o = P.clean_order(dict(base, tid='12345678901', i=9, target='X\nY', won=150, why='late', card='Storm Lord',
                               n=-1, age=-5))
        self.assertEqual((o['tid'], o['i'], o['target'], o['won'], o['why'], o['n'], o['age']),
                         (None, None, '', None, '', None, None))
        self.assertNotIn('card', o)
        self.assertEqual(set(o), {'tag', 'duel', 'round', 'kind', 'i', 'tid', 'target', 'won', 'n', 'age', 'why'})
        for i in (-1, True, 8.0, '1'):
            self.assertIsNone(P.clean_order(dict(base, i=i))['i'])
        self.assertEqual(P.clean_order(dict(base, i=8, tid='104'))['i'], 8)
        self.assertEqual(P.clean_order(dict(base, tid='104'))['tid'], 104)
        for t in ('A (B)', 'a:b', 'a|b', 'x' * 41, 5):
            self.assertEqual(P.clean_order(dict(base, target=t))['target'], '')
        self.assertEqual(P.clean_order(dict(base, target="Bob the Boss's x"))['target'], "Bob the Boss's x")
        self.assertEqual(P.clean_order(dict(base, target='all'))['target'], 'all')
        self.assertEqual(P.clean_order(dict(base, kind='pass'))['kind'], 'pass')
        # (markers: a code and a duel, or nothing)
        m = P.clean_order({'tag': '', 'duel': '12', 'round': 5, 'why': 'late'})
        self.assertEqual((m['tag'], m['duel'], m['why']), ('', '12', 'late'))
        self.assertEqual(P.clean_order({'duel': 12, 'round': 5, 'why': 'noplan'})['duel'], '12')
        for bad in ({'why': "you're playing - leaving this round to you"}, {'why': 'LATE'}, {'duel': ''},
                    {'duel': 'x'}, {'duel': None}):
            with self.subTest(marker=bad):
                self.assertIsNone(P.clean_order(dict({'tag': '', 'duel': '12', 'round': 5, 'why': 'late'}, **bad)))
        # (the ask)
        for junk in ('yes', {'max': 'nan'}, {}, {'max': float('nan')}, {'max': float('inf')}, {'max': True}, None):
            with self.subTest(ask=junk):
                self.assertIsNone(P.clean_ask(junk))
        self.assertEqual(P.clean_ask({'max': 99999}), {'max': 2048, 'got': ''})
        self.assertEqual(P.clean_ask({'max': 10, 'got': 'd12r5'}), {'max': 1024, 'got': 'd12r5'})
        self.assertEqual(P.clean_ask({'max': 1500.7, 'got': 'd12r5\n'})['got'], '')
        self.assertEqual(P.clean_ask({'max': 2048, 'got': 5})['got'], '')
        # (/partyorder's cells: 11 fields, nothing that breaks a line)
        ln = P.order_cells('ok', 5, 'a|b\nc', None, 'x\r')
        self.assertEqual(ln.split('|'), ['order', 'ok', '5', 'a/b c', '', 'x ', '', '', '', '', ''])

    def test_saw_hand_rules(self):
        for setup in ({'role': 'leader'}, {'orders': ''}, {'battle': '0'}):
            F = self.follower()
            if 'battle' in setup:
                F.ahk['battle'] = '0'
            else:
                F.cfg.update(setup)
            F.saw_hand(rd(HAND6), 'd12r5')
            self.assertIsNone(F.stash, setup)
        F = self.follower()
        for tag in ('x12r5', 'd12r5\n', 'd1234567890r5', '', None, 12):
            F.saw_hand(rd(HAND6), tag)
            self.assertIsNone(F.stash, tag)
        for local, want in ((('12', 6), 6), (None, 5), (('99', 6), 6), (('12', 0), 5), (('12', 'x'), 5), ('junk', 5)):
            F.saw_hand(rd(HAND6), 'd12r5', local)
            self.assertEqual((F.stash['tag'], F.stash['round']), ('d12r5', want), local)
        self.assertEqual(F.stash['at'], self.clock.t)
        # (a hand being dealt, or one with no card it can send: the last one stays)
        F.saw_hand(rd([LORD, BLADE]), 'd12r5')
        F.saw_hand(rd([TOWER], settled=False), 'd12r5')
        F.saw_hand(rd([hcard('No Kind', 9, None)]), 'd12r5')
        F.saw_hand('junk', 'd12r5')
        self.assertEqual([c['tid'] for c in F.stash['hand']['cards']], [101, 104])
        # (a later settled hand under the same tag - after a discard: that one)
        F.saw_hand(rd([BLADE]), 'd12r5')
        self.assertEqual([c['tid'] for c in F.stash['hand']['cards']], [104])
        self.assertEqual(self.logged, [])

    def test_pointed_at_another_leader(self):
        F = self.follower()
        F.saw_hand(rd(HAND6), 'd12r5')
        order = {'tag': 'd12r5', 'round': 5, 'i': 1, 'tid': 104, 'kind': 'blade', 'won': 80, 'n': 12, 'age': 0}
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order=order)
        upd = {'role': 'follower', 'orders': '1', 'battle': '1', 'name': 'Bob', 'brole': 'blader', 'wiz': 'Bob Fireheart',
               'seat': '5'}
        F.update(upd)                                                      # (the same leader and port: all kept)
        self.assertEqual(F.asked, {'max': 2048, 'got': 'd12r5'})
        self.assertEqual(ahk_fields(F.order_line('d12r5'), 11)[2], 'ok')
        # (the address changed mid-battle - Party window: the old leader's ask and order go, its first beat as before)
        F.update(dict(upd, leader='192.168.1.99'))
        self.assertEqual((F.asked, F.order), (None, None))
        self.assertIsNotNone(F.stash)                                      # (this wizard's own hand stays)
        self.assertIsNotNone(F.leader)                                     # (the last answer kept, as ever)
        self.assertNotIn('hand', F._beat_query())
        self.assertEqual(ahk_fields(F.order_line('d12r5'), 11)[2], 'none')
        # (an answer from the old address still on its way asks nothing; the new leader's does)
        d = {'v': 1, 'leader': {'name': 'Ned', 'zone': 'A'}, 'others': [], 'hands': {'max': 2048, 'got': 'd12r5'},
             'order': order}
        F._took(json.loads(json.dumps(d)), at=('', P.PORT))
        self.assertEqual((F.asked, F.order), (None, None))
        self.assertEqual(F.state, 'following')
        F._took(json.loads(json.dumps(d)), at=('192.168.1.99', P.PORT))
        self.assertEqual(F.asked, {'max': 2048, 'got': 'd12r5'})
        self.assertIn('hand', F._beat_query())
        # (the port changed: the same)
        F.update(dict(upd, leader='192.168.1.99', port='47141'))
        self.assertEqual((F.asked, F.order), (None, None))
        self.assertNotIn('hand', F._beat_query())
        # (partyorders off here: the leader's answer still taken from either address, nothing asked)
        G = self.follower(orders='')
        G._took(json.loads(json.dumps(d)), at=('10.0.0.9', P.PORT))
        self.assertEqual((G.asked, G.order, G.state), (None, None, 'following'))
        self.assertIsNotNone(G.leader)

    def test_server_takes_a_long_beat_only_with_orders_on(self):
        import http.client
        import threading
        from http.server import HTTPServer
        P.time = self._time                                                # (a real clock for the server's thread)
        L = self.make('leader')
        L.cfg['orders'] = '1'
        srv = HTTPServer(('127.0.0.1', 0), L._handler())
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            def get(path):
                c = http.client.HTTPConnection('127.0.0.1', srv.server_address[1], timeout=10)
                try:
                    c.request('GET', path)
                    r = c.getresponse()
                    r.read()
                    return r.status
                finally:
                    c.close()
            path = '/party/beat?id=ab&hold=' + 'x' * 1500
            self.assertGreater(len(path), P.MAX_PATH)
            self.assertLessEqual(len(path), P.MAX_PATH_HANDS)
            self.assertEqual(get(path), 200)
            self.assertEqual(get('/party/beat?id=ab&hold=' + 'x' * P.MAX_PATH_HANDS), 403)
            L.cfg['orders'] = ''
            self.assertEqual(get(path), 403)                               # (off: today's 1024)
            self.assertEqual(get('/party/beat?id=ab'), 200)
        finally:
            srv.shutdown()
            srv.server_close()

    def test_freshest_member_after_a_restart(self):
        # (the follower's helper restarted: its old id lingers STALE s - the newer id's hand is the one used)
        L = self.leader()
        for fid, ago in (('01d', 5), ('0e1', 0)):
            L.members[fid] = dict(P.clean_state({'wiz': 'Bob Fireheart', 'seat': '5', 'battle': '1'}),
                                  at=self.clock.t - ago, ip='x')
        L.hands['01d'] = dict(P.clean_hand('d12r4~4~0~2500~3000~6~3~101:damage:7:storm:1'), at=self.clock.t - 5)
        L.hands['0e1'] = dict(P.clean_hand(BOB_HAND), at=self.clock.t)
        _t, used, _n = L.fill_mates('Bob Fireheart~5~fire~~3000~blader~~~', 5)
        self.assertEqual((used[0]['fid'], used[0]['tag']), ('0e1', 'd12r5'))

    def test_follower_not_stored(self):
        # (a 4th follower - MAX_FOLLOWERS stored: not asked for its hand, and none kept)
        L = self.team()
        self.assertEqual(len(L.members), P.MAX_FOLLOWERS)
        d = json.loads(json.dumps(L.beat_in({'id': 'dddd', 'battle': '1', 'hand': BOB_HAND}, '192.168.1.20')))
        self.assertEqual(list(d), ['v', 'leader', 'others'])
        self.assertNotIn('dddd', L.hands)
        self.assertNotIn('hands', self.answer(L, 'eeee'))
        self.assertIn('hands', self.answer(L, FB))

    def test_follower_hand_too_old(self):
        F = self.follower()
        F.saw_hand(rd(HAND6), 'd12r5')
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'})
        self.assertIn('hand', F._beat_query())
        self.clock.t += P.HAND_FRESH + 1
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'})
        self.assertNotIn('hand', F._beat_query())                         # (not sent)
        f = ahk_fields(F.order_line('d12r5'), 11)
        self.assertEqual(f[2], 'none')                                     # (no wait for it)
        self.assertIn("hand wasn't read this round", f[11])

    def test_card_cap(self):
        wire = 'd1r1~1~0~1~1~1~1~' + ';'.join('%d:damage:1:storm:1' % k for k in range(12))
        self.assertEqual([c['tid'] for c in P.clean_hand(wire)['cards']], list(range(P.MAX_CARDS)))

    def test_orders_off_through_update(self):
        F = self.follower()
        F.saw_hand(rd(HAND6), 'd12r5')
        self.heard(F, hands={'max': 2048, 'got': 'd12r5'}, order={'tag': '', 'duel': '12', 'round': 5, 'why': 'late'})
        self.assertIsNotNone(F.order)
        F.update({'role': 'follower', 'battle': '1', 'name': 'Bob'})     # (orders not sent: off)
        self.assertEqual((F.stash, F.asked, F.order), (None, None, None))
        L = self.team()
        L._serve = lambda: None
        L.update({'role': 'leader', 'battle': '1'})
        self.assertEqual((L.hands, L.orders, L.cfg['orders'], L.cfg['plans']), ({}, {}, '', ''))

    def test_loop_prunes_gone_followers(self):
        L = self.team()
        _t, used, _n = L.fill_mates(TEAM, 5)
        L.set_orders([{'who': 1, 'i': 1, 'tid': 104, 'kind': 'blade', 'aim': None, 'n': 12, 'won': 0.8}], used, [], 5)
        self.clock.t += P.STALE + 1
        L.members[FB]['at'] = self.clock.t                                  # (Bob still heard from, Ann and Cid gone)

        class Stop(BaseException):
            pass

        def stop(s):
            raise Stop()
        self.clock.sleep = stop                                            # (one pass of the loop, then out)
        with self.assertRaises(Stop):
            P.Party._loop(L)
        self.assertEqual((set(L.members), set(L.hands)), ({FB}, {FB}))
        self.assertNotIn(FA, L.orders)

    def test_name_key(self):
        self.assertEqual(P.name_key("Bob Fire-heart"), 'BOBFIREHEART')
        self.assertEqual(P.name_key('B0b 5t0rm18'), 'BOBSTORMIB')
        self.assertEqual(P.name_key('Élan'), 'LAN')
        self.assertEqual(P.name_key(None), '')


if __name__ == '__main__':
    unittest.main()
