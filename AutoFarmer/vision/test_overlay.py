"""test_overlay.py - the overlay over the game: its pictures and frame files (overlay.py), the vision helper's /ovmap
and POST /ovlog and the map they share with /navmap (vision.py) - no game, no Windows:
python -m unittest vision\\test_overlay.py  (from AutoFarmer\\vision: python -m unittest test_overlay)

/navmap's default picture is pinned by golden digests (on the Pillow and numpy they were taken with, no Windows
fonts); AhkParity reads Overlay.ahk and the files wired to it (once they're there) for the constants and names this
side relies on - static checks, not a run of AutoHotkey."""
import hashlib
import http.client
import os
import random
import re
import shutil
import struct
import sys
import tempfile
import threading
import time
import unittest
from http.server import ThreadingHTTPServer
from urllib.parse import quote

import numpy as np
import PIL
from PIL import Image, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
AF = os.path.dirname(HERE)              # the AutoFarmer folder
sys.path.insert(0, HERE)

TEST_RGBS = [(255, 0, 0), (0, 255, 0), (255, 255, 0), (0, 255, 255), (255, 0, 255), (255, 128, 0), (128, 0, 255),
             (0, 128, 255), (255, 0, 128), (128, 255, 0), (0, 255, 128), (255, 255, 255), (128, 128, 255),
             (255, 128, 128), (0, 0, 255)]


# ---------------------------------------------------------------- the golden scenes (ovdesign/golden.py, as it is)

def scene_a(V):
    V.MOBS_SHOWN.update(near=120.0, cone=(180.0, 300.0), avoid=True, at=time.time(), quest={7})
    r = {'pos': (0.0, 0.0, 0.0), 'yaw': 0.5, 'zone': 'Test/NoSuchZone', 'goal': (900.0, 300.0, 0.0), 'hops': 0,
         'target': (400.0, -200.0, 0.0), 'path': [(300.0, 100.0, 0.0), (900.0, 300.0, 0.0)]}
    mobs = [{'name': 'Crab', 'pos': (300.0, 200.0, 0.0), 'yaw': 0.0, 'quest': False, 'gid': 5, 'vel': (150.0, 0.0), 'moving': True},
            {'name': 'Ghost', 'pos': (-300.0, 200.0, 0.0), 'yaw': None, 'quest': True, 'gid': 7}]
    items = [{'name': 'Bone', 'pos': (-200.0, -400.0, 0.0), 'gid': 9, 'quest': True}, {'name': 'Rock', 'pos': (200.0, -400.0, 0.0), 'gid': 10, 'quest': False}]
    duels = [{'pos': (0.0, -600.0, 0.0), 'gid': 1}]
    route = {'route': [(0.0, 0.0, 0.0), (200.0, 150.0, 0.0), (900.0, 300.0, 0.0)], 'aim': (200.0, 150.0, 0.0)}
    return V.render_navmap(r, 200, 160, '/nonexistent', 3000.0, route, mobs, True, items, duels=duels, walls=None)


def fake_layers(V, zone='Test/Fake'):
    z = object.__new__(V.ZoneLayers)
    z.zone, z.why = zone, ''

    def tb(t):
        return (t, np.concatenate([t.min(1), t.max(1)], 1))
    z.tris = {'floor': tb(np.array([[[-2000., -2000.], [2000., -2000.], [0., 2000.]]])),
              'water': tb(np.array([[[-2000., 2100.], [-1000., 2100.], [-1500., 2600.]]]))}
    ob = [np.array([[100., 100.], [300., 100.], [300., 300.], [100., 300.]])]
    z.polys = {'floor': ([], np.zeros((0, 4))), 'obst': (ob, np.array([[100., 100., 300., 300.]]))}
    z.tz = {'floor': np.array([50.0]), 'floorpoly': np.zeros(0)}
    z.zlo, z.zhi = 0.0, 100.0
    z.segs = np.array([[[0., 0.], [500., 500.]]])
    z.nodes = np.array([[0., 0.], [500., 500.]])
    z.bounds = (-2000., -2000., 2000., 2600.)
    z.made = time.time()
    return z


def scene_b(V, clear=False):
    z = fake_layers(V)
    V.NAV_ZONES['Test/Fake'] = z
    for k in [k for k in V.NAV_TILES if k[0] == 'Test/Fake']:
        del V.NAV_TILES[k]
    r = {'pos': (0.0, 0.0, 0.0), 'yaw': 0.5, 'zone': 'Test/Fake', 'goal': None, 'hops': None, 'target': None, 'path': []}
    if clear:
        return V.render_navmap(r, 200, 160, '', 6000.0, clear=True)
    return V.render_navmap(r, 200, 160, '', 6000.0)


def digest(im):
    return hashlib.sha256(im.tobytes()).hexdigest()


def no_map_fonts():
    """none of the map's Windows fonts loads (Pillow's own font draws the golden scenes' text)"""
    for n in ('segoeuib.ttf', 'segoeui.ttf', 'arialbd.ttf', 'arial.ttf'):
        try:
            ImageFont.truetype(n, 10)
            return False
        except OSError:
            pass
    return True


GOLDEN_ENV = PIL.__version__ == '12.3.0' and np.__version__ == '2.5.3' and no_map_fonts()


# ---------------------------------------------------------------- BattleRec.ahk BrecEsc, in Python

def brec_esc(s):
    """BattleRec.ahk BrecEsc: s as it is when every character is printable ASCII but a backslash; else \\ -> \\\\,
    tab -> \\t, LF -> \\n, CR dropped and every other character outside printable ASCII -> \\uXXXX (a surrogate pair
    above U+FFFF)"""
    if not re.search(r'[^\x20-\x5B\x5D-\x7E]', s):
        return s
    s = s.replace('\\', '\\\\').replace('\t', '\\t').replace('\n', '\\n').replace('\r', '')
    out = []
    for ch in s:
        c = ord(ch)
        if 0x20 <= c <= 0x7E:
            out.append(ch)
        elif c > 0xFFFF:
            c -= 0x10000
            out.append('\\u%04X\\u%04X' % (0xD800 + (c >> 10), 0xDC00 + (c & 0x3FF)))
        else:
            out.append('\\u%04X' % c)
    return ''.join(out)


# ---------------------------------------------------------------- the tests

class Base(unittest.TestCase):
    """vision as V and overlay as OV; vision's log silenced (as test_navroute.Helper); every vision global a test may
    touch saved before it and put back after"""
    ATTRS = ('ROUTER', 'nav_reader', 'mobs_now', 'items_now', 'map_route', 'REC')
    SHOWN = ('MOBS_SHOWN', 'DUELS_SHOWN', 'ITEMS_SHOWN')
    KEYED = ('NAV_ZONES', 'NAV_TILES', 'OV_TILES')

    @classmethod
    def setUpClass(cls):
        import vision
        import overlay
        cls.V, cls.OV = vision, overlay
        cls.log = vision.log
        vision.log = lambda *a, **kw: None             # (nothing into vision\vision.log from the tests)

    @classmethod
    def tearDownClass(cls):
        cls.V.log = cls.log

    def setUp(self):
        V = self.V
        attrs = {k: getattr(V, k) for k in self.ATTRS}
        shown = {k: dict(getattr(V, k)) for k in self.SHOWN}
        keyed = {k: self.zone_keys(getattr(V, k)) for k in self.KEYED}

        def restore():
            for k, v in attrs.items():
                setattr(V, k, v)
            for k, v in shown.items():
                getattr(V, k).clear()
                getattr(V, k).update(v)
            for k, saved in keyed.items():
                d = getattr(V, k)
                for key in self.zone_keys(d):
                    del d[key]
                d.update(saved)
        self.addCleanup(restore)

    @staticmethod
    def zone_keys(d):
        """the 'Test/...' entries of a zone or tile dict"""
        return {k: v for k, v in d.items() if (k if isinstance(k, str) else k[0]).startswith('Test/')}

    def tmpdir(self):
        d = tempfile.mkdtemp()                         # (under tempfile.gettempdir(): ov_path_ok's temp folder)
        self.addCleanup(shutil.rmtree, d, True)
        return d


class Frames(Base):
    def test_magic_and_header(self):
        OV = self.OV
        self.assertEqual(struct.unpack('<I', OV.FRAME_MAGIC)[0], 0x564F5A57)
        self.assertEqual(OV.FRAME_HEAD.size, 32)

    def test_frame_layout(self):
        OV = self.OV
        img = Image.new('RGBA', (3, 2))
        for y in range(2):
            for x in range(3):
                img.putpixel((x, y), (10 + 40 * x, 20 + 60 * y, 30 + 10 * x + 5 * y, 255))
        img.putpixel((0, 0), (255, 0, 0, 255))
        fb = OV.frame_bytes(img, -5, 7, 9)
        self.assertEqual(len(fb), 32 + 24)
        magic, ver, w, h, stride, seq, x, y = OV.FRAME_HEAD.unpack(fb[:32])
        self.assertEqual((magic, ver, w, h, stride, seq, x, y), (b'WZOV', 1, 3, 2, 12, 9, -5, 7))
        r, g, b, a = img.getpixel((2, 1))
        at = 32 + (1 * 3 + 2) * 4
        self.assertEqual(list(fb[at:at + 4]), [b, g, r, a])
        self.assertEqual(fb[32:36], b'\x00\x00\xff\xff')            # (opaque red)

    def test_premultiplied(self):
        OV = self.OV
        for rgba, want in (((255, 128, 0, 128), [0, 64, 128, 128]), ((200, 100, 50, 0), [0, 0, 0, 0]),
                           ((12, 34, 56, 255), [56, 34, 12, 255]), ((255, 0, 0, 1), [0, 0, 1, 1])):
            img = Image.new('RGBA', (1, 1), rgba)
            self.assertEqual(list(OV.premul_bgra(img)), want, rgba)
            self.assertEqual(list(OV._premul_numpy(img)), want, rgba)

    def test_premul_paths_agree(self):
        OV = self.OV
        arr = np.random.default_rng(1234).integers(0, 256, (23, 37, 4), dtype=np.uint8)
        arr[0, :, 3] = 0
        arr[1, :, 3] = 255
        img = Image.fromarray(arr)
        self.assertEqual((img.mode, img.size), ('RGBA', (37, 23)))
        try:
            fast = img.tobytes('raw', 'BGRa')
        except (ValueError, KeyError, OSError):
            self.skipTest("this Pillow has no 'BGRa' raw mode")
        self.assertEqual(fast, OV._premul_numpy(img))
        px = np.frombuffer(OV.premul_bgra(img), np.uint8).reshape(23, 37, 4)
        self.assertTrue((px[..., :3] <= px[..., 3:4]).all())

    def test_write_frame(self):
        OV = self.OV
        out = os.path.join(self.tmpdir(), 'sub', 'frame.wzov')
        img = Image.new('RGBA', (4, 3), (10, 200, 30, 180))
        self.assertEqual(OV.write_frame(out, img, 1, 2, 5), 'ok')
        self.assertEqual(OV.write_frame(out, img, 1, 2, 6), 'same')            # (the same picture, a new seq)
        self.assertEqual(OV.write_frame(out, img, 1, 2, 7, force=True), 'ok')
        self.assertEqual(OV.write_frame(out, img, 3, 2, 8), 'ok')              # (moved)

        def check(seq, x):
            with open(out, 'rb') as f:
                data = f.read()
            self.assertEqual(len(data), 32 + 4 * 3 * 4)
            self.assertEqual(os.path.getsize(out), 32 + 4 * 3 * 4)
            self.assertEqual(OV.FRAME_HEAD.unpack(data[:32]), (b'WZOV', 1, 4, 3, 16, seq, x, 2))
            self.assertEqual(data[32:], OV.premul_bgra(img))
            self.assertFalse(os.path.exists(out + '.tmp'))
            self.assertEqual([f for f in os.listdir(os.path.dirname(out)) if f.endswith('.tmp')], [])
        check(8, 3)
        os.remove(out)
        self.assertEqual(OV.write_frame(out, img, 3, 2, 9), 'ok')              # (gone: written again)
        check(9, 3)


class Layout(Base):
    SIZES = ((200, 150), (800, 600), (1280, 720), (1366, 768), (1920, 1080), (2560, 1440), (3840, 2160), (1080, 1920),
             (10000, 150), (200, 10000))

    @staticmethod
    def overlap(b, c):
        return b[0] < c[0] + c[2] and c[0] < b[0] + b[2] and b[1] < c[1] + c[3] and c[1] < b[1] + b[3]

    def inside(self, b, gw, gh):
        x, y, w, h = b
        self.assertTrue(0 <= x and 0 <= y and x + w <= gw and y + h <= gh, (b, gw, gh))
        self.assertTrue(1 <= w <= 4000 and 1 <= h <= 4000, b)

    def test_defaults_1080(self):
        OV = self.OV
        lay = OV.layout(1920, 1080, OV.layout_args({}))
        self.assertEqual(lay['map'], (13, 13, 302, 302))
        self.assertEqual(lay['log'], (13, 328, 730, 210))
        self.assertEqual((lay['px'], lay['line_h'], lay['pad'], lay['margin']), (15, 20, 5, 13))
        self.assertEqual(lay['why'], '')

    def test_boxes_inside_and_apart(self):
        OV = self.OV
        n = 0
        for gw, gh in self.SIZES:
            for mapat in range(1, 6):
                for logat in range(1, 6):
                    for msize in (15, 28, 60):
                        for lines in (3, 10, 30):
                            for lw in (20, 38, 90):
                                for text in (60, 100, 200):
                                    a = OV.layout_args({'mapat': mapat, 'logat': logat, 'msize': msize, 'lines': lines,
                                                        'lw': lw, 'text': text})
                                    lay = OV.layout(gw, gh, a)
                                    n += 1
                                    m, lg = lay['map'], lay['log']
                                    self.assertEqual(m is None, mapat == 1)
                                    if m is not None:
                                        self.inside(m, gw, gh)
                                        self.assertEqual(m[2], m[3])
                                    if lg is not None:
                                        self.inside(lg, gw, gh)
                                        self.assertGreaterEqual(lg[3], 2 * lay['line_h'] + 2 * lay['pad'])
                                        if m is not None:
                                            self.assertFalse(self.overlap(m, lg), (gw, gh, a, m, lg))
                                    elif logat != 1:
                                        self.assertTrue(lay['why'], (gw, gh, a))
        self.assertEqual(n, 20250)

    def test_off_parts_none(self):
        OV = self.OV
        lay = OV.layout(1920, 1080, OV.layout_args({'mapat': 1}))
        self.assertIsNone(lay['map'])
        self.assertEqual(lay['log'][:2], (13, 13))                  # (the log alone in the corner)
        lay = OV.layout(1920, 1080, OV.layout_args({'logat': 1}))
        self.assertIsNone(lay['log'])
        self.assertEqual(lay['why'], '')
        self.assertEqual(lay['map'], (13, 13, 302, 302))
        lay = OV.layout(1920, 1080, OV.layout_args({'mapat': '1', 'logat': '1'}))
        self.assertEqual((lay['map'], lay['log']), (None, None))

    def test_same_corner_beside_or_none(self):
        OV = self.OV
        # (a map too tall for the log under it - only past LIMITS' msize: the log beside it, or none)
        a = dict(OV.layout_args({}), msize=100)
        lay = OV.layout(1920, 1080, a)
        self.assertEqual(lay['map'], (13, 13, 1054, 1054))
        self.assertEqual(lay['log'], (13 + 1054 + 13, 13, 730, 210))
        lay = OV.layout(1200, 1080, a)
        self.assertIsNone(lay['log'])
        self.assertIn("there's no room for the log next to the map", lay['why'])
        # (another corner: lines dropped till it's clear of the map, else none)
        lay = OV.layout(1920, 1080, OV.layout_args({'mapat': 2, 'logat': 4, 'msize': 60, 'lines': 30}))
        self.assertFalse(self.overlap(lay['map'], lay['log']))
        self.assertLess(lay['log'][3], 30 * lay['line_h'] + 2 * lay['pad'])
        lay = OV.layout(200, 150, OV.layout_args({'mapat': 2, 'logat': 3}))
        self.assertIsNone(lay['log'])
        self.assertIn('the log would cover the map', lay['why'])

    def test_nudges_clamped_inside(self):
        OV = self.OV
        lay = OV.layout(1920, 1080, OV.layout_args({'mdx': 10, 'mdy': '-3', 'ldx': 7, 'ldy': 2}))
        self.assertEqual(lay['map'][:2], (23, 10))
        self.assertEqual(lay['log'][:2], (20, 330))
        for gw, gh in self.SIZES:
            for mapat, logat in ((2, 2), (3, 5), (5, 4), (4, 3)):
                for d in (-4000, -100, 100, 4000):
                    a = OV.layout_args({'mapat': mapat, 'logat': logat, 'mdx': d, 'mdy': d, 'ldx': -d, 'ldy': d})
                    lay = OV.layout(gw, gh, a)
                    for b in (lay['map'], lay['log']):
                        if b is not None:
                            self.inside(b, gw, gh)

    def test_args_defaults_and_clamps(self):
        OV = self.OV
        self.assertEqual(OV.layout_args({}), {k: d for k, (lo, hi, d) in OV.LIMITS.items()})
        a = OV.layout_args({'mapat': '9', 'msize': '1', 'lines': '-5', 'lw': '100', 'text': '12.7', 'back': '91',
                            'mdx': '-99999', 'ldy': '99999', 'span': '1e9'})
        self.assertEqual((a['mapat'], a['msize'], a['lines'], a['lw'], a['text'], a['back']), (5, 15, 3, 90, 60, 90))
        self.assertEqual((a['mdx'], a['ldy'], a['span']), (-4000, 4000, 100000))
        self.assertEqual(OV.layout_args({'text': '150.9'})['text'], 150)
        for bad in ('x', 'nan', 'inf', '-inf', '', None):
            a = OV.layout_args({k: bad for k in OV.LIMITS})
            self.assertEqual(a, OV.layout_args({}), bad)
        self.assertEqual(set(OV.SETTINGS.values()) - set(OV.LIMITS), set())

    def test_font_px(self):
        OV = self.OV
        self.assertEqual(OV.font_px(1080, 100), 15)
        for text in (60, 100, 200):
            last = 0
            for gh in range(150, 10001, 10):
                px = OV.font_px(gh, text)
                self.assertTrue(9 <= px <= 48, (gh, text, px))
                self.assertGreaterEqual(px, last)
                last = px

    def test_parse_request(self):
        OV = self.OV
        good = {'gw': '1920', 'gh': '1080', 'out': '/somewhere/overlay-map.wzov'}
        yes, no = (lambda p: True), (lambda p: False)
        for q, ok in ((dict(good, out='/somewhere/x.png'), yes), (good, no), (dict(good, gw='100'), yes),
                      (dict(good, gh='100'), yes), ({k: v for k, v in good.items() if k != 'gw'}, yes),
                      (dict(good, gh='lots'), yes), (dict(good, gw='10001'), yes)):
            p, err = OV.parse_request(q, ok)
            self.assertIsNone(p, q)
            self.assertTrue(err.startswith('ERR '), err)
        p, err = OV.parse_request(dict(good, out='/x/Y.WZOV', seq='4294967301', force='1', msize='40'), yes)
        self.assertEqual(err, '')
        self.assertEqual((p['gw'], p['gh'], p['out'], p['seq'], p['force']), (1920, 1080, '/x/Y.WZOV', 5, True))
        self.assertEqual(p['args'], dict(OV.layout_args({}), msize=40))
        p, err = OV.parse_request(dict(good, seq='x', force='0'), yes)
        self.assertEqual((p['seq'], p['force']), (0, False))
        p, err = OV.parse_request(good, yes)
        self.assertEqual((p['seq'], p['force']), (0, False))


class LogBody(Base):
    def test_parse_log_body(self):
        OV = self.OV
        body = b"FF6B6B\t12:00:01 Walk: stuck\n7FB3FF\t12:00:02 caf\\u00E9 \\uD83D\\uDE00\nzzz\tbad colour\n\nplain\r\n"
        self.assertEqual(OV.parse_log_body(body), [((255, 107, 107), '12:00:01 Walk: stuck'),
                                                   ((127, 179, 255), '12:00:02 caf\u00e9 \U0001F600'),
                                                   ((218, 218, 218), 'bad colour'), ((218, 218, 218), 'plain')])
        self.assertEqual(OV.parse_log_body(b'a0b0c0\tone\\ttwo\\nthree\\\\four\n'), [((160, 176, 192), 'one two three\\four')])
        self.assertEqual(OV.parse_log_body(''), [])
        self.assertEqual(OV.parse_log_body(b'\xff\xfe\tx\n')[0][0], (218, 218, 218))
        many = OV.parse_log_body(''.join('00FF00\tline %d\n' % k for k in range(70)).encode('ascii'))
        self.assertEqual(len(many), 60)
        self.assertEqual((many[0][1], many[-1][1]), ('line 10', 'line 69'))

    def test_unesc_roundtrip_with_brecesc(self):
        OV = self.OV
        self.assertEqual(brec_esc('plain [text] ~'), 'plain [text] ~')
        self.assertEqual(brec_esc('a\\b\tc\r\nd\u00e9\U0001F600'), 'a\\\\b\\tc\\nd\\u00E9\\uD83D\\uDE00')
        rng = random.Random(77)
        alphabet = list('abc XYZ019:-|[]~{}"\'') + ['\\', '\t', '\u00e9', '\u00fc', '\u4e2d', '\u20ac', '\U0001F600',
                                                    '\U0001D11E', '\x7f', '\\u00E9']
        texts = [''.join(rng.choice(alphabet) for _ in range(rng.randint(1, 40))) for _ in range(300)]
        body = ''.join('A0B0C0\t' + brec_esc('12:00:00 ' + t) + '\n' for t in texts).encode('ascii')
        got = OV.parse_log_body(body)
        want = [((160, 176, 192), ('12:00:00 ' + t).replace('\t', ' ')) for t in texts][-OV.LOG_LINES_KEPT:]
        self.assertEqual(got, want)


class LogPicture(Base):
    """(on Linux with Pillow's own font - load_default(px) - for the log)"""
    W, PX, LH, PAD = 600, 15, 20, 5

    def render(self, lines, rows, back):
        OV = self.OV
        return OV.render_log(lines, self.W, rows * self.LH + 2 * self.PAD, self.PX, self.LH, self.PAD, back)

    def test_fit_text(self):
        OV = self.OV
        f = OV.log_font(15)
        long = '12:00:00 Walk: ' + 'a long line of the log ' * 20
        t = OV.fit_text(f, long, 300)
        self.assertTrue(t.endswith('...'))
        self.assertLessEqual(f.getlength(t), 300)
        self.assertTrue(long.startswith(t[:-3].rstrip()))
        self.assertGreater(len(t), 10)
        self.assertEqual(OV.fit_text(f, 'short', 300), 'short')
        self.assertEqual(OV.fit_text(f, 'WWWWWWWW', 1), '...')

    def test_render_log_shape(self):
        OV = self.OV
        img = self.render([((255, 107, 107), '12:00:01 one'), ((127, 179, 255), '12:00:02 two')], 10, 89)
        self.assertEqual((img.mode, img.size), ('RGBA', (600, 210)))
        self.assertEqual(img.getpixel((0, 0))[3], 0)
        self.assertEqual(img.getpixel((600 - 5 - 2, 5 + 2)), OV.BG + (89,))

    def test_newest_at_bottom(self):
        lines = [(rgb, '12:00:%02d line %d MWHIl|#MWHIl|#MWHIl|#' % (k, k)) for k, rgb in enumerate(TEST_RGBS)]
        a = np.asarray(self.render(lines, 10, 89))
        h = a.shape[0]
        band = a[h - self.PAD - self.LH:h - self.PAD]
        self.assertTrue((band == np.array(TEST_RGBS[-1] + (255,), np.uint8)).all(-1).any())
        self.assertFalse((a == np.array(TEST_RGBS[0] + (255,), np.uint8)).all(-1).any())
        self.assertFalse((a == np.array(TEST_RGBS[4] + (255,), np.uint8)).all(-1).any())     # (not shown: rows 10)

    def test_fade(self):
        A = ((255, 255, 255), '12:00:01 the older line, A')
        B = ((255, 255, 255), '12:00:02 the newer line, B')
        top = slice(self.PAD, self.PAD + self.LH)
        bottom = slice(self.PAD + self.LH, self.PAD + 2 * self.LH)
        newest = np.asarray(self.render([A, B], 2, 0))[bottom, :, 3].mean()
        older = np.asarray(self.render([B, A], 2, 0))[top, :, 3].mean()
        self.assertGreater(newest, older)
        self.assertGreater(older, 0)

    def test_back_zero_clear(self):
        lines = [((255, 255, 0), 'line %d' % k) for k in range(30)]
        a = np.asarray(self.render(lines, 10, 0))
        self.assertTrue((a[:self.PAD, :, 3] == 0).all())
        self.assertTrue((a[:, :self.PAD // 2, 3] == 0).all())

    def test_strip_cache_bounded(self):
        OV = self.OV
        for k in range(300):
            OV.line_strip('12:00:00 distinct line %d' % k, (200, 200, 200), 15, 590, 20)
        self.assertLessEqual(len(OV.STRIPS), OV.STRIPS_KEPT)
        self.assertIn(('12:00:00 distinct line 299', (200, 200, 200), 15, 590, 20), OV.STRIPS)
        for k in range(30):
            self.render([((1, 2, 3), 'render %d.%d' % (k, j)) for j in range(10)], 10, 35)
        self.assertLessEqual(len(OV.STRIPS), OV.STRIPS_KEPT)
        # (a frame's most lines and its placeholder fit - no thrash -, but not hundreds of lines scrolled off: each
        # strip is the log's full width, never asked for again once off)
        self.assertGreater(OV.STRIPS_KEPT, OV.LIMITS['lines'][1])
        self.assertLessEqual(OV.STRIPS_KEPT, 2 * OV.LIMITS['lines'][1])

    def test_empty_placeholder(self):
        a = np.asarray(self.render([], 10, 89))
        self.assertTrue((a[..., 3] == 255).any())

    def test_rounded_mask(self):
        OV = self.OV
        a = np.asarray(OV.rounded_mask(60, 40, 8))
        self.assertEqual(a.shape, (40, 60))
        for x, y in ((0, 0), (59, 0), (0, 39), (59, 39)):
            self.assertEqual(a[y, x], 0, (x, y))
        for x, y in ((30, 0), (30, 39), (0, 20), (59, 20), (30, 20)):
            self.assertEqual(a[y, x], 255, (x, y))
        self.assertTrue(np.array_equal(a, a[::-1]))
        self.assertTrue(np.array_equal(a, a[:, ::-1]))
        self.assertTrue(np.array_equal(np.asarray(OV.rounded_mask(5, 3, 8)), np.asarray(OV.rounded_mask(5, 3, 1))))


class MapPicture(Base):
    @unittest.skipUnless(GOLDEN_ENV, 'the golden digests were taken on Pillow 12.3.0, numpy 2.5.3, no Windows fonts')
    def test_navmap_default_unchanged(self):
        V = self.V
        self.assertEqual(digest(scene_a(V)), 'ba2a1ab1cb3529c69bc325170dca8dc4227f31a5176dcdd1edf23f8a247d4f82')
        self.assertEqual(digest(scene_b(V)), '114979cd63e872f42b695f120d1e142db764cde9acd17c9efedc4ebe764cd39b')
        self.assertEqual(digest(fake_layers(V).tile(6000.0 / 160, 0, -1)),
                         '78105f9f95b1b4e4b5bb4a6c0d4f34b515ad51a6d89e257242136ab3267ab1ca')

    def test_navmap_default_opaque(self):
        V = self.V
        img = scene_a(V)
        self.assertEqual((img.mode, img.size), ('RGB', (200, 160)))
        self.assertEqual(img.getpixel((0, 0)), V.MAP_BG)

    def test_clear_render(self):
        V = self.V
        V.drop_tiles('Test/Fake')
        nav_keys = set(V.NAV_TILES)
        img = scene_b(V, clear=True)
        self.assertEqual((img.mode, img.size), ('RGBA', (200, 160)))
        self.assertEqual(img.getpixel((0, 0))[3], 0)
        self.assertEqual(img.getpixel((100, 80)), V.MAP_ME + (255,))
        al = np.asarray(img)[..., 3]
        self.assertTrue(((al > 0) & (al < 255)).any())
        self.assertEqual(set(V.NAV_TILES), nav_keys)
        ov = [k for k in V.OV_TILES if k[0] == 'Test/Fake']
        self.assertTrue(ov)
        self.assertTrue(all(V.OV_TILES[k] is None or V.OV_TILES[k].mode == 'RGBA' for k in ov))
        # (and the other way round: the default picture keeps to NAV_TILES)
        ov_keys = set(V.OV_TILES)
        img = scene_b(V)
        self.assertEqual(img.mode, 'RGB')
        self.assertEqual(set(V.OV_TILES), ov_keys)
        self.assertTrue(all(V.NAV_TILES[k] is None or V.NAV_TILES[k].mode == 'RGB' for k in V.NAV_TILES if k[0] == 'Test/Fake'))

    def test_tile_clear(self):
        V = self.V
        t = fake_layers(V).tile(37.5, 0, -1, clear=True)
        self.assertEqual((t.mode, t.size), ('RGBA', (256, 256)))
        self.assertEqual(t.getpixel((128, 128))[3], 0)
        self.assertGreaterEqual(t.getpixel((2, 254))[3], V.OV_FLOOR_A)
        self.assertEqual(fake_layers(V).tile(37.5, 0, -1).mode, 'RGB')

    def test_drop_tiles(self):
        V = self.V
        for tiles in (V.NAV_TILES, V.OV_TILES):
            tiles[('Test/Fake', 1.0, 0, 0)] = None
            tiles[('Test/Fake', 2.0, 1, -1)] = None
            tiles[('Test/Other', 1.0, 0, 0)] = None
        V.drop_tiles('Test/Fake')
        for tiles in (V.NAV_TILES, V.OV_TILES):
            self.assertEqual([k for k in tiles if k[0] == 'Test/Fake'], [])
            self.assertIn(('Test/Other', 1.0, 0, 0), tiles)

    def test_finish_map(self):
        OV = self.OV
        img = Image.new('RGBA', (100, 100), (0, 0, 0, 0))
        img.putpixel((50, 50), (242, 242, 242, 255))
        out = OV.finish_map(img, OV.back_alpha(35))
        self.assertEqual((out.mode, out.size), ('RGBA', (100, 100)))
        for x, y in ((0, 0), (99, 0), (0, 99), (99, 99)):
            self.assertEqual(out.getpixel((x, y))[3], 0, (x, y))
        self.assertEqual(out.getpixel((50, 50)), (242, 242, 242, 255))
        self.assertEqual(out.getpixel((20, 50)), OV.BG + (OV.back_alpha(35),))
        self.assertEqual(OV.back_alpha(35), 89)
        self.assertEqual(img.getpixel((20, 50)), (0, 0, 0, 0))             # (the map itself left as it was)

    def test_clear_keeps_a_picture_of_tiles(self):
        """the overlay's tiles: never fewer kept than one picture needs (else each is pushed out just before it's
        drawn again - every tile drawn afresh every frame)"""
        V = self.V
        self.addCleanup(setattr, V, 'OV_TILES_KEPT', V.OV_TILES_KEPT)
        V.OV_TILES_KEPT = 1                                 # (200 x 160 round (0, 0) at 37.5 upp: 2 x 2 tiles)
        V.drop_tiles('Test/Fake')
        z = fake_layers(V)
        V.NAV_ZONES['Test/Fake'] = z
        calls = []
        real = z.tile
        z.tile = lambda *a, **kw: calls.append(a) or real(*a, **kw)
        r = {'pos': (0.0, 0.0, 0.0), 'yaw': 0.5, 'zone': 'Test/Fake', 'goal': None, 'hops': None, 'target': None, 'path': []}
        first = V.render_navmap(r, 200, 160, '', 6000.0, clear=True)
        self.assertEqual(len(calls), 4)
        again = V.render_navmap(r, 200, 160, '', 6000.0, clear=True)
        self.assertEqual(len(calls), 4)
        self.assertEqual(digest(first), digest(again))

    def test_cold_zone_steps(self):
        """a zone read for the overlay's map (clear) pauses at each step while a gated request is in flight
        (gate_wait); the dashboard's reads it as it always did (no step)"""
        V = self.V
        seen = []

        class Cold:
            def __init__(self, zone, game_dir='', step=None):
                seen.append((zone, step))
                self.zone, self.why = zone, 'no zone file (test)'
        self.addCleanup(setattr, V, 'ZoneLayers', V.ZoneLayers)
        V.ZoneLayers = Cold
        for zone, clear in (('Test/ColdOv', True), ('Test/ColdDash', False)):
            r = {'pos': (0.0, 0.0, 0.0), 'yaw': 0.5, 'zone': zone, 'goal': None, 'hops': None, 'target': None, 'path': []}
            V.render_navmap(r, 200, 160, '', 6000.0, clear=clear)
        self.assertEqual(seen, [('Test/ColdOv', V.gate_wait), ('Test/ColdDash', None)])

    def test_zone_read_step_each_shape(self):
        """navgeo.load_bcd and ZoneLayers call step before each collision shape"""
        import navgeo
        V = self.V

        def box(name):
            nb = name.encode()
            return (struct.pack('<III', 0, 0x1, 0) + struct.pack('<I', len(nb)) + nb
                    + struct.pack('<9f', 1, 0, 0, 0, 1, 0, 0, 0, 1) + struct.pack('<3f', 100, 100, 0) + struct.pack('<f', 1.0)
                    + struct.pack('<I', 0) + struct.pack('<I', 0) + struct.pack('<3f', 50, 50, 50))
        data = struct.pack('<I', 3) + box('a') + box('b') + box('c')
        n = []
        shapes = navgeo.load_bcd(data, lambda: n.append(1))
        self.assertEqual((len(shapes), len(n)), (3, 3))
        self.assertEqual(len(navgeo.load_bcd(data)), 3)
        passed = []

        def fake_load_zone(zone, game_dir='', use_katsuba=True, step=None):
            passed.append(step)
            return {'nav': None, 'bcd': shapes}
        self.addCleanup(setattr, navgeo, 'load_zone', navgeo.load_zone)
        navgeo.load_zone = fake_load_zone
        n.clear()
        z = V.ZoneLayers('Test/Steps', '/nonexistent', lambda: n.append(1))
        self.assertEqual((len(n), z.why), (3, ''))
        self.assertEqual(len(z.polys['obst'][0]), 3)
        self.assertTrue(callable(passed[0]))


class Routes(Base):
    """/navmap, /ovmap and POST /ovlog through a real server (vision.Handler) - the game's readers stood in for"""
    R = {'pos': (0.0, 0.0, 0.0), 'yaw': 0.5, 'zone': 'Test/NoSuchZone', 'goal': None, 'hops': None, 'target': None,
         'path': []}

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.srv = ThreadingHTTPServer(('127.0.0.1', 0), cls.V.Handler)
        cls.srv.daemon_threads = True
        cls.port = cls.srv.server_address[1]
        cls.thread = threading.Thread(target=cls.srv.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        super().tearDownClass()

    def setUp(self):
        super().setUp()
        V = self.V
        test = self
        self.answer = (dict(self.R), '')

        class Reader:
            game_dir = ''

            def read(self, path=False, wait=0.0):
                return test.answer
        V.nav_reader = lambda: Reader()
        V.mobs_now = lambda r, *a, **k: ([], '')
        V.items_now = lambda *a, **k: ([], '')
        V.map_route = lambda *a, **k: None
        V.MOBS_SHOWN['at'] = V.DUELS_SHOWN['at'] = V.ITEMS_SHOWN['at'] = 0
        V.ROUTER = None
        self.dir = self.tmpdir()

    def ask(self, method, path, body=None, headers=None):
        c = http.client.HTTPConnection('127.0.0.1', self.port, timeout=60)
        try:
            c.request(method, path, body=body, headers=headers or {})
            res = c.getresponse()
            return res.status, res.read().decode('utf-8')
        finally:
            c.close()

    def query(self, out, gw=1280, gh=720, seq=5, force=0, **change):
        """the layout query as Overlay.ahk sends it (its keys in this order), then seq, force and out"""
        a = dict(self.OV.layout_args({}), **change)
        return ('gw=%d&gh=%d' % (gw, gh) + ''.join('&%s=%s' % (k, a[k]) for k in self.OV.LIMITS)
                + '&seq=%d&force=%d&out=%s' % (seq, force, quote(out, safe='')))

    def frame_head(self, path):
        with open(path, 'rb') as f:
            data = f.read()
        head = self.OV.FRAME_HEAD.unpack(data[:32])
        self.assertEqual(head[:2], (b'WZOV', 1))
        self.assertEqual(len(data), 32 + head[2] * head[3] * 4)
        self.assertEqual(head[4], head[2] * 4)
        return head

    def test_navmap_route_unchanged(self):
        V = self.V
        out = os.path.join(self.dir, 'map.png')
        code, text = self.ask('GET', '/navmap?w=200&h=160&span=6000&out=' + quote(out, safe=''))
        self.assertEqual((code, text), (200, 'ok|' + os.path.abspath(out)))
        with Image.open(out) as im:
            self.assertEqual(im.mode, 'RGB')
            got = im.tobytes()
        want = V.render_navmap(dict(self.R), 200, 160, '', 6000.0, None, [], False, [], None, None)
        self.assertEqual(got, want.tobytes())
        self.assertEqual(self.ask('GET', '/navmap?w=8&h=160&out=' + quote(out, safe=''))[0], 400)

    def test_navmap_errors(self):
        out = quote(os.path.join(self.dir, 'map.png'), safe='')
        self.answer = (None, 'not in the world')
        self.assertEqual(self.ask('GET', '/navmap?w=200&h=160&out=' + out), (200, 'ERR not in the world'))
        self.answer = (dict(self.R, pos=None, why_player='x'), '')
        self.assertEqual(self.ask('GET', '/navmap?w=200&h=160&out=' + out),
                         (200, "ERR the wizard's position can't be read (x)"))
        self.answer = (dict(self.R, yaw=None), '')
        self.assertEqual(self.ask('GET', '/navmap?w=200&h=160&out=' + out),
                         (200, "ERR the wizard's position can't be read (?)"))

    def test_ovmap(self):
        OV = self.OV
        out = os.path.join(self.dir, 'Wizard101 bot map', 'overlay-map.wzov')
        box = OV.layout(1280, 720, OV.layout_args({}))['map']
        code, text = self.ask('GET', '/ovmap?' + self.query(out))
        self.assertEqual((code, text), (200, 'ok|' + os.path.abspath(out)))
        head = self.frame_head(out)
        self.assertEqual((head[6], head[7], head[2], head[3]), box)
        self.assertEqual(head[5], 5)
        self.assertEqual(self.ask('GET', '/ovmap?' + self.query(out, seq=6)), (200, 'same|' + os.path.abspath(out)))
        self.assertEqual(self.frame_head(out)[5], 5)                         # (not written)
        self.assertEqual(self.ask('GET', '/ovmap?' + self.query(out, seq=7, force=1)), (200, 'ok|' + os.path.abspath(out)))
        self.assertEqual(self.frame_head(out)[5], 7)
        self.assertEqual(self.ask('GET', '/ovmap?' + self.query(os.path.join(self.dir, 'x.png')))[0], 400)
        self.assertEqual(self.ask('GET', '/ovmap?' + self.query('/etc/x.wzov'))[0], 400)
        code, text = self.ask('GET', '/ovmap?' + self.query(out, gw=100))
        self.assertEqual(code, 400)
        self.assertTrue(text.startswith('ERR gw must be'), text)
        self.assertEqual(self.ask('GET', '/ovmap?' + self.query(out, mapat=1)), (200, 'ERR the map is off'))
        self.assertEqual(self.ask('GET', '/ovmap?' + self.query(out, mdx=25, seq=9))[1], 'ok|' + os.path.abspath(out))
        head = self.frame_head(out)
        self.assertEqual((head[6], head[5]), (box[0] + 25, 9))
        self.answer = (None, 'not in the world')
        self.assertEqual(self.ask('GET', '/ovmap?' + self.query(out)), (200, 'ERR not in the world'))

    def test_ovlog(self):
        OV = self.OV
        out = os.path.join(self.dir, 'overlay-log.wzov')
        body = ('FF6B6B\t12:00:01 Walk: stuck\n7FB3FF\t12:00:02 caf\\u00E9 \\uD83D\\uDE00\n'
                'DADADA\t12:00:03 Overlay: on (Win+4 or the tray menu switches it off)\n').encode('ascii')
        hdr = {'Content-Type': 'text/plain; charset=us-ascii'}
        box = OV.layout(1280, 720, OV.layout_args({}))['log']
        code, text = self.ask('POST', '/ovlog?' + self.query(out), body, hdr)
        self.assertEqual((code, text), (200, 'ok|' + os.path.abspath(out)))
        head = self.frame_head(out)
        self.assertEqual((head[6], head[7], head[2], head[3]), box)
        self.assertEqual(head[5], 5)
        self.assertEqual(self.ask('POST', '/ovlog?' + self.query(out, seq=6), body, hdr), (200, 'same|' + os.path.abspath(out)))
        self.assertEqual(self.ask('POST', '/ovlog?' + self.query(out, seq=7), body + b'00FF00\tone more\n', hdr),
                         (200, 'ok|' + os.path.abspath(out)))
        self.assertEqual(self.ask('POST', '/ovlog?' + self.query(out, logat=1), body, hdr), (200, 'ERR the log is off'))
        self.assertEqual(self.ask('POST', '/ovlog?' + self.query(out, gw=200, gh=150, logat=3), body, hdr)[1][:30],
                         'ERR the log would cover the ma')
        self.assertEqual(self.ask('POST', '/ovlog?' + self.query(out + '.png'), body, hdr)[0], 400)
        self.assertEqual(self.ask('POST', '/other', b'x'), (404, 'ERR unknown request /other'))
        self.V.REC = None
        self.assertEqual(self.ask('POST', '/rec?ev=round', b'x'), (200, 'off'))

    def test_direct_replies(self):
        V = self.V
        out = os.path.join(self.dir, 'direct.wzov')
        good = {'gw': '1280', 'gh': '720', 'out': out, 'seq': '3'}
        for reply in (V.ovmap_reply, lambda q: V.ovlog_reply(q, b'')):
            for q, start in (({k: v for k, v in good.items() if k != 'gw'}, "ERR gw and gh (the game's size) are needed"),
                             (dict(good, gh='149'), 'ERR gw must be 200-10000 and gh 150-10000'),
                             (dict(good, out=out[:-5] + '.png'), 'ERR out must be a .wzov file'),
                             (dict(good, out='/etc/direct.wzov'), 'ERR out must be a .wzov file')):
                text, code = reply(q)
                self.assertEqual(code, 400, q)
                self.assertTrue(text.startswith(start), text)
        self.assertEqual(V.ovmap_reply(dict(good, mapat='1')), ('ERR the map is off', 200))
        self.assertEqual(V.ovlog_reply(dict(good, logat='1'), b''), ('ERR the log is off', 200))
        text, code = V.ovlog_reply(dict(good, gw='200', gh='150', logat='3'), b'')
        self.assertEqual(code, 200)
        self.assertTrue(text.startswith('ERR the log would cover the map'), text)
        self.assertEqual(V.ovlog_reply(good, b''), ('ok|' + os.path.abspath(out), 200))      # ((nothing logged yet))
        self.assertEqual(V.ovmap_reply(good), ('ok|' + os.path.abspath(out), 200))
        self.answer = (None, 'the game is not running')
        self.assertEqual(V.ovmap_reply(good), ('ERR the game is not running', 200))
        self.answer = (dict(self.R, pos=None, why_player='x'), '')
        self.assertEqual(V.ovmap_reply(good), ("ERR the wizard's position can't be read (x)", 200))

    def test_ov_yield(self):
        V = self.V
        V.GATE.enter()
        try:
            t0 = time.monotonic()
            V.ov_yield(0.2)
            dt = time.monotonic() - t0
        finally:
            V.GATE.leave()
        self.assertTrue(0.15 <= dt <= 1.0, dt)
        t0 = time.monotonic()
        V.ov_yield(0.5)
        self.assertLess(time.monotonic() - t0, 0.4)


# ---------------------------------------------------------------- the AutoHotkey side, read (not run)

def ahk_lines(name):
    with open(os.path.join(AF, name), encoding='utf-8-sig', errors='replace') as f:
        return f.read().splitlines()


def ahk_semi(line):
    """ahk_semicolon.py's scan of a line: (where its first ' ;' / '\\t;' is - AutoHotkey's comment start, even inside
    a string - else len(line), and whether that's inside a double-quoted string). "" is an escaped quote, a
    backtick skips the next character"""
    inq, i = False, 0
    while i < len(line):
        c = line[i]
        if c == '"':
            if inq and i + 1 < len(line) and line[i + 1] == '"':
                i += 2
                continue
            inq = not inq
        elif c == '`':
            i += 2
            continue
        elif c == ';' and i > 0 and line[i - 1] in ' \t':
            return i, inq
        i += 1
    return len(line), False


def semicolon_hits(lines):
    """the code lines with a ' ;' / '\\t;' inside a double-quoted string (AutoHotkey takes it as a comment)"""
    return [(n, ln.strip()) for n, ln in enumerate(lines, 1) if not ln.lstrip().startswith(';') and ahk_semi(ln)[1]]


def ahk_code(lines):
    """each line's code: '' for a comment line (; or a /* */ block), else the line up to its comment"""
    out, block = [], False
    for ln in lines:
        s = ln.lstrip()
        if block or s.startswith('/*'):
            block = '*/' not in (s[2:] if not block else s)
            out.append('')
        elif s.startswith(';'):
            out.append('')
        else:
            out.append(ln[:ahk_semi(ln)[0]])
    return out


OVERLAY_AHK = os.path.join(AF, 'Overlay.ahk')


@unittest.skipUnless(os.path.exists(OVERLAY_AHK), 'no Overlay.ahk yet')
class AhkParity(unittest.TestCase):
    """the constants and names the Python side relies on, as Overlay.ahk, Settings.ahk, Hotkeys.ahk, Autofarmer.ahk,
    Dashboard.ahk and Decks.ahk have them (their code - comments left out)"""

    @classmethod
    def setUpClass(cls):
        import overlay
        cls.OV = overlay
        cls.ov_lines = ahk_lines('Overlay.ahk')
        cls.ov = '\n'.join(ahk_code(cls.ov_lines))

    def has(self, pattern, literal=False):
        """whether Overlay.ahk's code has it (a regex, or literal text)"""
        return (pattern in self.ov) if literal else bool(re.search(pattern, self.ov))

    def code_lines_matching(self, pattern):
        return [ln.strip() for ln in self.ov.split('\n') if re.search(pattern, ln)]

    def test_overlay_frame_and_window(self):
        for text in ('0x564F5A57', '+ 32', '+E0x08080020', '10.0.19041'):
            self.assertTrue(self.has(text, True), text)
        for off in (8, 12, 16, 20):
            self.assertTrue(self.has(r'NumGet\(\w+, %d, "UInt"\)' % off), off)
        for off in (24, 28):
            self.assertTrue(self.has(r'NumGet\(\w+, %d, "Int"\)' % off), off)
        self.assertTrue(self.has(r'SetWindowDisplayAffinity"\s*,\s*"Ptr"\s*,\s*[\w.]+\s*,\s*"UInt"\s*,\s*0x11'),
                        'SetWindowDisplayAffinity 0x11')

    def test_overlay_query_and_ini(self):
        for k in ('"mapdx"', '"mapdy"', '"logdx"', '"logdy"', '"mapspan"'):
            self.assertTrue(self.has(k, True), k)
        for k in ['gw', 'gh'] + list(self.OV.LIMITS):
            self.assertTrue(self.has('"&' + k + '="', True) or self.has('"' + k + '="', True), k)

    def test_overlay_never(self):
        # (its code only: the header comment names what it never calls)
        for bad in (r'SetWindowDisplayAffinity"[^\n]*"UInt"\s*,\s*(1|0x1|0x01)\b', r'\.Show\(', r'WinActivate', r'Sleep\(',
                    r'WinSetTransparent', r'WinSetTransColor', r'SetLayeredWindowAttributes'):
            self.assertEqual(self.code_lines_matching(bad), [], bad)

    def test_overlay_drawn_for_size(self):
        """a part is shown only with a picture drawn for the game's client size now (else, after a resize, at its old
        place - maybe outside the game): OvShowParts tests the start of the query its picture was asked with
        (drawnQ), which OvQuery must keep starting with gw and gh - else no part would ever show"""
        self.assertTrue(self.has('return "gw=" OvGw "&gh=" OvGh "&mapat="', True))
        self.assertTrue(self.has('InStr(win.drawnQ, "gw=" OvGw "&gh=" OvGh "&") = 1', True))
        self.assertEqual(len(self.code_lines_matching(r'win\.drawnQ := win\.sentQ\s*$')), 2)
        self.assertTrue(self.has('sentQ: "", drawnQ: ""}', True))

    def test_settings(self):
        lines = ahk_lines('Settings.ahk')
        code = ahk_code(lines)
        OV = self.OV

        def entry(key):
            found = [ln for ln in code if 'key: "%s"' % key in ln]
            self.assertEqual(len(found), 1, key)
            ln = found[0]

            def num(name):
                m = re.search(r'\b%s: (-?\d+)' % name, ln)
                return int(m.group(1)) if m else None
            kind = re.search(r'\bkind: "(\w+)"', ln)
            picks = re.search(r'\bpicks: \[([^\]]*)\]', ln)
            return (kind.group(1) if kind else None, num('lo'), num('hi'), num('def'),
                    len(re.findall(r'"[^"]*"', picks.group(1))) if picks else None)
        for key, q in OV.SETTINGS.items():
            lo, hi, d = OV.LIMITS[q]
            kind, elo, ehi, edef, npicks = entry(key)
            if q in ('mapat', 'logat'):
                self.assertEqual((kind, 1, npicks, edef), ('pick', lo, hi, d), key)
            else:
                self.assertEqual((kind, elo, ehi, edef), ('num', lo, hi, d), key)
        self.assertEqual(entry('overlay')[0::3], ('check', 0))
        self.assertEqual(entry('overlayopacity')[:4], ('num', 20, 100, 90))

    def test_discardspent_wiring(self):
        """v1.8.0: the simulator plays discardspent only if the AutoFarmer sends it - Settings.ahk's CfgList entry a
        check with def 1 (LoadStats puts it in Stats: Decks.ahk DeckSimVals sends only a key Stats has), Decks.ahk's
        DeckKeys naming it (DeckSimVals' list), every DeckKey kept by the battle recorder (BattleRec.ahk BrecSetKeys ->
        battlerec.SETTINGS_KEYS) and the simulator's Opts reading it; and 0 where the bot never runs it this session -
        DeckSimVals' line and DeckForZone's deck profiles (dual mode, Autofarmer.ahk DiscardSpentRole: a Blader or
        Healer with the party on)"""
        import battlerec
        import battlesim
        lines = ahk_lines('Settings.ahk')
        code = ahk_code(lines)
        found = [ln for ln in code if 'key: "discardspent"' in ln]
        self.assertEqual(len(found), 1)
        self.assertRegex(found[0], r'\bkind: "check"')
        self.assertRegex(found[0], r'\bdef: 1\b')
        # (no ' ;' in the strings of the entries v1.8.0 wrote - AutoHotkey would take the rest as a comment)
        mine, follow = [], False
        for ln in lines:
            if re.search(r'key: "(discardspent|discardmax|reboost)"', ln):
                mine.append(ln)
                follow = True
            elif follow and ln.lstrip().startswith(','):
                mine.append(ln)
            else:
                follow = False
        self.assertEqual(len(mine), 6, mine)
        self.assertEqual(semicolon_hits(mine), [])
        dk = '\n'.join(ahk_code(ahk_lines('Decks.ahk')))
        m = re.search(r'DeckKeys\(\)\s*\{(.*?)return keys', dk, re.S)
        self.assertIsNotNone(m)
        keys = re.findall(r'"(\w+)"', m.group(1))
        self.assertIn('discardspent', keys)
        self.assertIn('discardmax', keys)
        for k in keys:
            self.assertIn(k, battlerec.SETTINGS_KEYS, k)
        self.assertIn('discardspent', battlesim.Opts.KEYS)
        # (DeckSimVals' 0 - /sim, /plan and /deckfor's vals -, and DeckForZone's over a deck profile's own 1: the
        # simulator holds the copies where the bot does)
        self.assertRegex(dk, r'dsvK = "discardspent" && \(dualmode == 1 \|\| \(V1IsFunc\("DiscardSpentRole"\) '
                             r'&& !DiscardSpentRole\.Call\(\)\)\)\)\s*dsvV := 0')
        m = re.search(r'\nDeckForZone\(p, inBattle := false\)\s*\{.*?\n\t\}', dk, re.S)
        self.assertIsNotNone(m)
        self.assertRegex(m.group(0), r'dfzNoSpent := V1IsFunc\("DiscardSpentRole"\) && !DiscardSpentRole\.Call\(\)')
        self.assertRegex(m.group(0), r'\(dfzK2 = "discardspent" && dfzNoSpent\)\) \? 0 : dfzV2')
        af = '\n'.join(ahk_code(ahk_lines('Autofarmer.ahk')))
        self.assertRegex(af, r'\nDiscardSpentRole\(\)\s*\{\s*return PartyBattleSet\(\) = "hitter" \|\| '
                             r'PartyRoleSet\(\) = "off"\s*\}')
        # (a treasure card drawn this battle - Draw.ahk: a sharpened cast may have spent its Sharpen, not the deck's -
        # counts none of the worn deck's down)
        self.assertRegex(af, r'dspCome := V1IsNum\(dspHas\) && dspHas - \(V1N\(DrawsBattle\) \? 0 : '
                             r'DiscardSpentSharpened\(dspKind\)\) > 0')

    def test_reboostkeep_wiring(self):
        """v1.9.1: with reboost on DiscardSpare keeps a blade's copies where a hit of yours frees both its casts again
        (Autofarmer.ahk ReboostKeepRole - set to Hitter or the party off, not Alt+2's pick -, inside KillCalc.ahk
        ConsumeBoosts' own test, left as it was) while a hit can still free them (BoostFreeable) and says so once a
        battle a blade; Decks.ahk DeckSimVals always sends reboostkeep by ReboostKeepRole, never a deck's own setting;
        the simulator's Opts read it"""
        import battlesim
        lines = ahk_lines('Autofarmer.ahk')
        af = '\n'.join(ahk_code(lines))
        self.assertRegex(af, r'\nReboostKeepRole\(\)\s*\{\s*global Manual\s*return Manual != 1 && !PartySupport\(\) '
                             r'&& DiscardSpentRole\(\)\s*\}')
        m = re.search(r'\nDiscardSpare\(\)\s*\{.*?\n\t\}', af, re.S)
        self.assertIsNotNone(m)
        body = m.group(0)
        self.assertRegex(body, r'local did := 0, [^\n]*\bdsKeep\b')
        self.assertIn('dsKeep := Stat("reboost") == 1 && ReboostKeepRole()', body)
        # (the both-casts test as it was; under it the throw without dsKeep or once no hit can free the key any more -
        # reboost came on in the battle after a hit used both its casts up -, else the once-a-battle line)
        self.assertRegex(body, r'if \(!dsDone\.Has\(dsK\) && IsObject\(dsF\) && UsedFlag\(dsF\[1\]\) == 1 && '
                               r'UsedFlag\(dsF\[2\]\) == 1 && !BoostCanGo\(dsK\)\)\s*\{\s*'
                               r'if \(!dsKeep \|\| !BoostFreeable\(dsK\)\)\s*did \+= ')
        # (BoostFreeable: the key's deck entry - plain or sharpened, no '@' - still in AppliedBlades or BoostUnrec,
        # the lists KillCalc.ahk ConsumeBoosts frees the flags of)
        self.assertRegex(af, r'\nBoostFreeable\(key\)\s*\{\s*global AppliedBlades, BoostUnrec\s*'
                             r'if \(IsObject\(AppliedBlades\) && \(AppliedBlades\.Has\(key\) \|\| '
                             r'AppliedBlades\.Has\(key "\+"\)\)\)\s*return true\s*'
                             r'for bfI, bfK in \(IsObject\(BoostUnrec\) \? BoostUnrec : \[\]\)\s*'
                             r'if \(bfK = key \|\| bfK = key "\+"\)\s*return true\s*return false\s*\}')
        self.assertRegex(body, r'\belse if \(IsObject\(BoostSaid\) && !BoostSaid\.Has\("both\|" dsK\)\)\s*'
                               r'BoostSaid\["both\|" dsK\] := 1, DebugLog\(')
        self.assertIn('its plain and sharpened casts both went - its copies kept in hand: with reboost on, the next hit '
                      'it fits lets it go again (said once a battle)', body)
        # (the spare-Sharpen rule kept as it was)
        self.assertIn('if (sharpen == 1) && dsSharpUsed && !dsNeed', body)
        start = next(i for i, ln in enumerate(lines) if ln.startswith('DiscardSpare()'))
        end = next(i for i in range(start, len(lines)) if lines[i] == '\t}')
        self.assertEqual(semicolon_hits(lines[start:end + 1]), [])
        # (ConsumeBoosts' freeing test as it was - ReboostKeepRole is inside it)
        kc = '\n'.join(ahk_code(ahk_lines('KillCalc.ahk')))
        m = re.search(r'\nConsumeBoosts\(hh := ""\)\s*\{.*?\n\t\}', kc, re.S)
        self.assertIsNotNone(m)
        self.assertIn('if (Stat("reboost") == 1 && !PartySupport())', m.group(0))
        # (and the lists it frees the flags of are BoostFreeable's: AppliedBlades' entries it uses up, BoostUnrec's)
        self.assertIn('for cbI, cbList in [AppliedBlades, BossTraps]', m.group(0))
        self.assertIn('for cbJ, cbKey in (IsObject(BoostUnrec) ? BoostUnrec : [])', m.group(0))
        dk = '\n'.join(ahk_code(ahk_lines('Decks.ahk')))
        m = re.search(r'\nDeckSimVals\(d, sch\)\s*\{.*?\n\t\}', dk, re.S)
        self.assertIsNotNone(m)
        self.assertRegex(m.group(0), r'dsvRk := \(V1IsFunc\("ReboostKeepRole"\) && !ReboostKeepRole\.Call\(\)\) \? 0 : 1'
                                     r'\s*dsvOut \.= \(dsvOut = "" \? "" : ","\) "reboostkeep:" dsvRk\s*return dsvOut')
        m = re.search(r'DeckKeys\(\)\s*\{(.*?)return keys', dk, re.S)
        self.assertIsNotNone(m)
        self.assertNotIn('"reboostkeep"', m.group(1))
        self.assertIn('reboostkeep', battlesim.Opts.KEYS)

    def test_hotkeys(self):
        lines = ahk_lines('Hotkeys.ahk')
        code = ahk_code(lines)
        self.assertTrue([ln for ln in code if 'id: "overlay"' in ln and 'def: "#4"' in ln and 'run: "MenuOverlay"' in ln])
        self.assertEqual('\n'.join(lines).count('def: "#4"'), 1)
        # (an action's default you had already given another action - the overlay's, new in an update - isn't taken
        # from it: HkKeyOf reads the [hotkeys] section and gives none then)
        start = next(i for i, ln in enumerate(code) if ln.startswith('HkKeyOf(id)'))
        end = next(i for i, ln in enumerate(code) if i > start and ln == '\t}')
        body = '\n'.join(code[start:end])
        self.assertIn('IniRead(A_ScriptDir "\\dashboard.ini", "hotkeys")', body)
        self.assertIn('HkSame(Trim(SubStr(A_LoopField, p + 1)), a.def)', body)
        self.assertNotIn('? k : a.def', body)
        # (v1.8.1: the overlay's key only with Wizard101 in front - Windows+4 stays your other programs' while the bot
        # runs; every other action's context as it was)
        self.assertTrue([ln for ln in code if 'id: "overlay"' in ln and 'ctx: "front"' in ln])
        self.assertEqual(len([ln for ln in code if 'ctx: "front"' in ln]), 1)
        for act in ('bot', 'walk'):
            self.assertTrue([ln for ln in code if 'id: "%s"' % act in ln and 'ctx: "game"' in ln], act)
        text = '\n'.join(code)
        self.assertRegex(text, r'\nHkCtxFront\(hk := ""\)\s*\{\s*return WinActive\("ahk_exe WizardGraphicalClient\.exe"\)\s*\}')
        self.assertIn('ctx := V1Obj({game: HkCtxGame, on: HkCtxOn, front: HkCtxFront})', text)
        self.assertIn('a.ctx = "front" ? "in Wizard101"', text)

    def test_mousesteer_v181(self):
        """v1.8.1: the mouse never given up on silently (MouseSteer.ahk) - each reason through MouseSteerNote, the
        measuring try's back-off, a failed facing read counted as a miss, the 10-minute pause shown, the raw press
        retried when the drag didn't reach the game, 1x for the turn above 5x, the bot's own windows' words left out;
        the callers that drop the speed say so (slows) - msWalk doesn't"""
        ms_lines = ahk_lines(os.path.join('..', 'AutoQuester', 'MouseSteer.ahk'))
        ms = '\n'.join(ahk_code(ms_lines))
        self.assertEqual(semicolon_hits(ms_lines), [])
        self.assertIn('MouseSteerWhyNot(needW := true, byMem := true, slows := false)', ms)
        self.assertIn('if (SpeedNow > 5 && !slows)', ms)
        self.assertRegex(ms, r'why := MouseSteerWhyNot\(true, byMem, true\)\s*if \(why != ""\)\s*\{\s*'
                             r'MouseSteerNote\("not now - " why\)\s*return ""')
        self.assertNotIn('why != "off"', ms)
        self.assertIn('if (MsK = "" && MsTriedAt && A_TickCount - MsTriedAt < 10000)', ms)
        self.assertEqual(ms.count('SpeedSet(0, "a mouse turn")'), 2)
        self.assertEqual(ms.count('MouseSteerNote("the facing couldn\'t be read (" MsYawWhy ")'), 2)
        self.assertIn('if (MsK = "" && !msUser)', ms)
        self.assertNotIn('if (MsK = "" && msY != "" && !msUser)', ms)
        self.assertIn('MsFails := 0, MsOffUntil := A_TickCount + 600000, msGaveUp := true', ms)
        m = re.search(r'\nMouseSteerGaveUp\(\)\s*\{.*?\n\t\}', ms, re.S)
        self.assertIsNotNone(m)
        for bit in ('SetStatus(', 'TrayTip(', 'static msTold := 0', 'Lock my mouse while the bot uses it for one run',
                    'check your wizard turns when you right-drag yourself'):
            self.assertIn(bit, m.group(0), bit)
        self.assertIn('"the game didn\'t take the right-button drag"', ms)
        self.assertIn('"the game took the drag but the wizard didn\'t turn"', ms)
        self.assertIn('"the wizard\'s facing couldn\'t be read from the game\'s memory mid-turn ("', ms)
        # (a word's or window's place left out of the once-a-minute key: one moving about isn't said at every look)
        self.assertIn('msKey := RegExReplace(what, " at -?\\d+,-?\\d+ in the game", "")', ms)
        self.assertIn('if (msNoted.Has(msKey) && A_TickCount - msNoted[msKey] < 60000)', ms)
        # (a look that turned him the wrong way isn't "too small", nor held back 10 s like a missed measuring try)
        self.assertIn('if (!sent && MsK != "")', ms)
        self.assertIn('MsTriedAt := A_TickCount - ((!probed && MsK = "") ? 9500 : 0)', ms)
        # (the raw press: the retry only when the cursor showed before and after, and let go the way it was pressed)
        self.assertIn('if (MsK = "" && msY != "" && !msUser && !MsRaw && InStr(msCur0, "shown") && InStr(msCur1, "shown"))', ms)
        self.assertIn('if (down ? MsRaw : (MsHeld = 2))', ms)
        self.assertIn('DllCall("mouse_event", "UInt", down ? 0x0008 : 0x0010', ms)
        # (AutoQuester has no mouse lock: each call of another file's function guarded - NavRead's by MouseSteerOn,
        # which every turn asks first)
        lines = ms.split('\n')
        for i, ln in enumerate(lines):
            for fn in re.findall(r'%"(\w+)"%\.Call', ln):
                if fn == 'NavRead':
                    continue
                self.assertIn('V1IsFunc("%s")' % fn, lines[i - 1] + ln, (i, fn))
        # (the bot's own windows: read, never hidden; the press point's window looked at)
        m = re.search(r'\nMouseSteerWindowClear\(\)\s*\{.*?\n\t\}', ms, re.S)
        self.assertIsNotNone(m)
        for bit in ('MouseSteerUnder(mwPx, mwPy, &mwWhat)', 'MouseSteerOwnRects()', 'MouseSteerInRects(', '&mwLines)'):
            self.assertIn(bit, m.group(0), bit)
        for bad in ('WinHide', '.Hide()', 'SetWindowDisplayAffinity', 'WinSetTransparent', 'WinMove'):
            self.assertNotIn(bad, ms, bad)
        self.assertIn('global MsYawWhy := "", MsRaw := "", MsMissWhy := ""', ms)
        wk = '\n'.join(ahk_code(ahk_lines(os.path.join('..', 'AutoQuester', 'Walker.ahk'))))
        self.assertIn('&& ((arcOk = 1 && Abs(steer) <= 150) || (arcOk = "" && Abs(steer) <= 100)) && MouseSteerWhyNot(false) = ""', wk)
        self.assertEqual(wk.count('MouseSteerWhyNot(HeldW ? true : false, false, true) = ""'), 2)
        self.assertRegex(wk, r'WalkNavSay\(why, nav\)\s*WalkMouseSay\(why\)')
        self.assertIn('wmNow := V1IsFunc("NavRead") ? "off (Settings: Turn with the mouse while walking)"', wk)
        self.assertIn('wmNow := "waiting for the game\'s memory ("', wk)
        # ("ready" only while it steers by the game's memory - a count measured in a dungeon isn't that)
        self.assertRegex(wk, r'else if \(WkNavUse\)\s*wmNow := wmSaid = "" \? "" : "ready')
        dg = '\n'.join(ahk_code(ahk_lines('Dungeons.ahk')))
        self.assertIn('MouseSteerWhyNot(true, false, true) = "" && MouseTurn(h, false) != ""', dg)
        st = '\n'.join(ahk_code(ahk_lines('Settings.ahk')))
        m = re.search(r'\nMouseLockRightFree\(free\)\s*\{.*?\n\t\}', st, re.S)
        self.assertIsNotNone(m)
        self.assertIn('HkTry("*RButton", "Off")', m.group(0))
        self.assertIn('HkTry("*RButton", MouseLockSwallow, "On")', m.group(0))
        af = '\n'.join(ahk_code(ahk_lines('Autofarmer.ahk')))
        self.assertRegex(af, r'\nif \(SpeedSetting\(\)\)\s*SpeedNow := fast \? SpeedFactor\(\) : 1\s*SpeedSentAt := A_TickCount')

    def test_autofarmer(self):
        code = ahk_code(ahk_lines('Autofarmer.ahk'))
        self.assertTrue(any('OverlayBlank()' in ln for ln in code[:15]))
        self.assertIn('#Include "%A_ScriptDir%\\Overlay.ahk"', [ln.strip() for ln in code])
        start = next(i for i, ln in enumerate(code) if 'StartBot() {' in ln)
        loop = next(i for i, ln in enumerate(code) if i > start and 'BattleLoop()' in ln)
        self.assertTrue(any('OverlayInit()' in ln for ln in code[start + 1:loop]))
        dl = next(i for i, ln in enumerate(code) if ln.startswith('DebugLog(msg)'))
        end = next(i for i, ln in enumerate(code) if i > dl and ln == '\t}')
        self.assertTrue(any('OvLogNote.Call(' in ln for ln in code[dl:end]))
        text = '\n'.join(code)
        self.assertIn('MenuOverlay(A_ThisMenuItem', text)
        self.assertIn('Tray.Add(HkMenu("overlay"), MenuOverlay)', text)
        # (StatsAuto's reload under Critical, as CfgWrite's and LearnStatsWrite's: OvTick never reads Stats half
        # reloaded - overlay:0, its default, till PlayerStats.txt's line - and switches the overlay off and on)
        sa = next(i for i, ln in enumerate(code) if ln.startswith('StatsAuto()'))
        end = next(i for i, ln in enumerate(code) if i > sa and ln == '\t}')
        body = [ln.strip() for ln in code[sa:end] if ln.strip()]
        k = body.index('LoadStats(true)')
        self.assertEqual(body[k - 2:k + 2], ['wasCrit := A_IsCritical', 'Critical()', 'LoadStats(true)',
                                             'CfgUncritical(wasCrit, 0)'])

    def test_dashboard(self):
        code = ahk_code(ahk_lines('Dashboard.ahk'))
        kind = next(i for i, ln in enumerate(code) if ln.startswith('DashLogKind(line)'))
        system = next(i for i, ln in enumerate(code) if i > kind and 'return "system"' in ln)
        self.assertIn('Overlay:', code[system - 1])
        self.assertIn('Vision:|Overlay:|', code[system - 1])

    def test_semicolon_rule(self):
        self.assertEqual(semicolon_hits(self.ov_lines), [])
        lines = ahk_lines('Settings.ahk')
        mine, follow = [], False
        for ln in lines:
            if 'overlay' in ln.lower():
                mine.append(ln)
                follow = True
            elif follow and ln.lstrip().startswith(','):
                mine.append(ln)
            else:
                follow = False
        self.assertTrue(mine)
        self.assertEqual(semicolon_hits(mine), [])


if __name__ == '__main__':
    unittest.main()
