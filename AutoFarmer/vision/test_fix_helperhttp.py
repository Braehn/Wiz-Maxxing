"""test_fix_helperhttp.py - the vision helper's HTTP server answers AutoFarmer, its tools and an address typed into the
browser, never a web page (request_refused: an Origin, a cross-site Sec-Fetch-Site, another site's Referer, a Host that
isn't 127.0.0.1 / localhost at its port - DNS rebinding; a browser only for BROWSER_PAGES), and the paths it writes to stay in their folders (inside_root,
inside_temp, rel_ok, cut_out_ok, learned_pic) - no game, no Windows:  python -m unittest test_fix_helperhttp
(from AutoFarmer\\vision)"""
import http.client
import os
import re
import sys
import tempfile
import threading
import unittest
from http.server import ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import vision as V  # noqa: E402

FARMER = os.path.dirname(HERE)


def ahk(name):
    with open(os.path.join(FARMER, name), encoding='utf-8-sig', errors='replace') as f:
        return f.read()


class Refused(unittest.TestCase):
    """request_refused on the headers alone"""
    PORT = 47128

    def why(self, path='/quit', **h):
        return V.request_refused({k.replace('_', '-'): v for k, v in h.items()}, self.PORT, path)

    def test_autofarmer_and_tools_answered(self):
        # (WinHttp's and urllib's / http.client's: Host 127.0.0.1:<port>, nothing else)
        self.assertEqual(self.why(Host='127.0.0.1:47128'), '')
        self.assertEqual(self.why(Host='localhost:47128'), '')
        self.assertEqual(self.why(Host='LocalHost:47128'), '')
        self.assertEqual(self.why(), '')                     # (HTTP/1.0, no Host: never a browser)

    def test_typed_into_the_browser_answered(self):
        # (a top-level navigation the user made: Sec-Fetch-Site none, no Origin, no Referer; a reload of the page)
        self.assertEqual(self.why('/book', Host='127.0.0.1:47128', Sec_Fetch_Site='none', Sec_Fetch_Mode='navigate'), '')
        self.assertEqual(self.why('/book', Host='localhost:47128', Sec_Fetch_Site='same-origin',
                                  Referer='http://localhost:47128/book'), '')
        self.assertEqual(self.why(Host='127.0.0.1:47128', Origin='http://127.0.0.1:47128'), '')

    def test_browser_only_for_the_pages(self):
        # (a link to /quit or /net?on=1 clicked in a chat or a mail: the default browser's top-level navigation,
        # Sec-Fetch-Site none - not answered; a page the docs link to is)
        nav = dict(Host='127.0.0.1:47128', Sec_Fetch_Site='none', Sec_Fetch_Mode='navigate', Sec_Fetch_Dest='document',
                   Sec_Fetch_User='?1')
        for path in ('/quit', '/net', '/netcmd', '/party', '/navmap', '/cut', '/snap', '/rec', '/ovlog', '/forget'):
            self.assertIn('browser', self.why(path, **nav), path)
        self.assertIn('browser', self.why('/quit', Host='127.0.0.1:47128', Sec_Fetch_Mode='no-cors'))
        for path in ('/book', '/quests', '/decks', '/items', '/ping'):
            self.assertEqual(self.why(path, **nav), '', path)

    def test_site_link_to_a_page_answered(self):
        # (TODO.md's /decks?fresh=1&ob=1 link clicked on github.com: cross-site, navigate, document, its Referer)
        link = dict(Host='127.0.0.1:47128', Sec_Fetch_Site='cross-site', Sec_Fetch_Mode='navigate',
                    Sec_Fetch_Dest='document', Referer='https://github.com/')
        for path in ('/decks', '/items', '/book', '/quests'):
            self.assertEqual(self.why(path, **link), '', path)
        # (but not another endpoint, an <img> / iframe / fetch of a page, nor a form's post with its Origin)
        self.assertIn('browser', self.why('/quit', **link))
        self.assertIn('Sec-Fetch-Site', self.why('/book', **dict(link, Sec_Fetch_Mode='no-cors', Sec_Fetch_Dest='image')))
        self.assertIn('Sec-Fetch-Site', self.why('/book', **dict(link, Sec_Fetch_Dest='iframe')))
        self.assertIn('Origin', self.why('/book', **dict(link, Origin='https://github.com')))
        self.assertIn('Host', self.why('/book', **dict(link, Host='evil.example:47128')))

    def test_dns_rebinding_refused(self):
        self.assertIn('Host', self.why(Host='evil.example:47128'))
        self.assertIn('Host', self.why(Host='evil.example'))
        self.assertIn('Host', self.why(Host='127.0.0.1:8080'))
        self.assertIn('Host', self.why(Host='127.0.0.1.evil.example:47128'))
        self.assertIn('Host', self.why(Host=''))

    def test_web_pages_refused(self):
        h = '127.0.0.1:47128'
        self.assertIn('Origin', self.why(Host=h, Origin='https://evil.example'))
        self.assertIn('Origin', self.why(Host=h, Origin='null'))
        self.assertIn('Origin', self.why(Host=h, Origin='http://127.0.0.1:3000'))
        # (an <img> or no-cors fetch from a site: no Origin, but Sec-Fetch-Site says where it came from)
        self.assertIn('Sec-Fetch-Site', self.why('/book', Host=h, Sec_Fetch_Site='cross-site'))
        self.assertIn('Sec-Fetch-Site', self.why('/book', Host=h, Sec_Fetch_Site='same-site'))
        self.assertTrue(self.why(Host=h, Sec_Fetch_Site='cross-site'))
        # (an older browser: the site's Referer)
        self.assertIn('Referer', self.why(Host=h, Referer='https://evil.example/page'))
        self.assertIn('Referer', self.why(Host=h, Referer='http://127.0.0.1:3000/'))

    def test_host_ok(self):
        self.assertTrue(V.host_ok('127.0.0.1', 47128))
        self.assertTrue(V.host_ok(' 127.0.0.1:47128 ', 47128))
        self.assertFalse(V.host_ok('[::1]:47128', 47128))
        self.assertFalse(V.host_ok('127.0.0.1:47128:1', 47128))


class Server(unittest.TestCase):
    """the filter on a real server (vision.Handler): a web page's /quit, /net or POST /rec does nothing"""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.log_was = V.LOG
        V.LOG = os.path.join(cls.tmp.name, 'vision.log')
        cls.srv = ThreadingHTTPServer(('127.0.0.1', 0), V.Handler)
        cls.srv.daemon_threads = True
        cls.port = cls.srv.server_address[1]
        cls.thread = threading.Thread(target=cls.srv.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        V.LOG = cls.log_was
        cls.tmp.cleanup()

    def setUp(self):
        V.REFUSED.update(at=0.0, n=0)

    def ask(self, path, method='GET', headers=None, body=None, host=None):
        c = http.client.HTTPConnection('127.0.0.1', self.port, timeout=30)
        try:
            h = dict(headers or {})
            if host is not None:
                c.putrequest(method, path, skip_host=True)
                c.putheader('Host', host)
                for k, v in h.items():
                    c.putheader(k, v)
                if body is not None:
                    c.putheader('Content-Length', str(len(body)))
                c.endheaders(body)
            else:
                c.request(method, path, body=body, headers=h)
            res = c.getresponse()
            return res.status, res.read().decode('utf-8')
        finally:
            c.close()

    def test_plain_request_answered(self):
        self.assertEqual(self.ask('/ping'), (200, 'OK ' + V.VERSION))
        self.assertEqual(self.ask('/ping', host='localhost:%d' % self.port,
                                  headers={'Sec-Fetch-Site': 'none', 'Sec-Fetch-Mode': 'navigate'}),
                         (200, 'OK ' + V.VERSION))
        # (a link to /quit clicked in a chat: refused, the helper still runs)
        code, text = self.ask('/quit?x=1', headers={'Sec-Fetch-Site': 'none', 'Sec-Fetch-Mode': 'navigate',
                                                    'Sec-Fetch-Dest': 'document', 'Sec-Fetch-User': '?1'})
        self.assertEqual(code, 403)
        self.assertIn('/book', text)
        self.assertEqual(self.ask('/ping')[0], 200)

    def said(self):
        try:
            with open(V.LOG, encoding='utf-8') as f:
                return [ln for ln in f if 'refused' in ln]
        except OSError:
            return []

    def test_web_page_refused_and_nothing_done(self):
        before = len(self.said())
        for headers, host in (({'Origin': 'https://evil.example'}, None),
                              ({'Sec-Fetch-Site': 'cross-site', 'Sec-Fetch-Dest': 'image'}, None),
                              ({}, 'evil.example:%d' % self.port)):
            code, text = self.ask('/quit', headers=headers, host=host)
            self.assertEqual(code, 403, (headers, host))
            self.assertTrue(text.startswith('ERR refused'), text)
        # (the helper still runs: /quit did nothing)
        self.assertEqual(self.ask('/ping')[0], 200)
        # (said once in vision.log, the rest counted)
        self.assertEqual(len(self.said()) - before, 1)
        self.assertEqual(V.REFUSED['n'], 2)

    def test_web_page_post_refused(self):
        code, text = self.ask('/rec?ev=round', method='POST', body=b'x' * 100,
                              headers={'Origin': 'https://evil.example', 'Content-Type': 'text/plain'})
        self.assertEqual(code, 403)
        self.assertEqual(self.ask('/rec?ev=round', method='POST', body=b'x', headers={'Content-Type': 'text/plain'}),
                         (200, 'off'))

    def test_paths_outside_their_folder_refused(self):
        # (/navmap: a relative out once came out of vision\ into the AutoFarmer folder)
        code, _ = self.ask('/navmap?w=16&h=16&out=..%5Cresources%5Cblade3.png')
        self.assertEqual(code, 400)
        # (/cut: only <set>\learned\<id>, a full path in the AutoFarmer folder)
        for out in (os.path.join(V.ROOT, 'balance', 'hit1'), V.ROOT + 'X' + os.sep + 'learned' + os.sep + 'c1',
                    os.path.join('..', 'learned', 'c1')):
            code, _ = self.ask('/cut?left=0&top=0&scale=1&out=' + quote(out))
            self.assertEqual(code, 400, out)
        # (/hand: thumbs a full path in the AutoFarmer folder; here a set folder's name in it)
        rect = '/hand?x1=0&y1=0&x2=10&y2=10&scale=1'
        for extra in ('&thumbs=' + quote(V.ROOT + 'X' + os.sep + 'hand'), '&thumbs=' + quote('generated\\hand'),
                      '&here=' + quote('..\\..'), '&here=' + quote(tempfile.gettempdir())):
            code, _ = self.ask(rect + extra)
            self.assertEqual(code, 400, extra)


def quote(s):
    from urllib.parse import quote as q
    return q(s, safe='')


class Paths(unittest.TestCase):
    """the path checks themselves"""

    def test_inside_root(self):
        self.assertTrue(V.inside_root(os.path.join(V.ROOT, 'balance', 'hit1.png')))
        self.assertFalse(V.inside_root(V.ROOT))
        self.assertFalse(V.inside_root(V.ROOT + 'X' + os.sep + 'a.png'))            # (a folder beside it)
        self.assertFalse(V.inside_root(os.path.join('..', 'resources', 'blade3.png')))  # (relative: never)
        self.assertFalse(V.inside_root('resources\\blade3.png'))
        self.assertFalse(V.inside_root(''))

    def test_inside_temp(self):
        self.assertTrue(V.inside_temp(os.path.join(tempfile.gettempdir(), 'Wizard101 bot map', 'navmap.png')))
        self.assertFalse(V.inside_temp('navmap.png'))
        self.assertFalse(V.inside_temp(tempfile.gettempdir() + 'X' + os.sep + 'a.png'))

    def test_rel_ok(self):
        for good in ('', 'ui1.144', 'ui0.917', 'balance\\hit1', 'resources/blade4', 'ui1.144\\learned'):
            self.assertTrue(V.rel_ok(good), good)
        for bad in ('..', '..\\x', 'a\\..\\..\\x', '...', '. .', '.', 'a\\\\b', '\\x', '/x', 'C:\\x', 'C:x',
                    '\\\\server\\share\\x', 'ui1.144:stream', 'a\0b', tempfile.gettempdir()):
            self.assertFalse(V.rel_ok(bad), bad)
        self.assertTrue(V.rel_ok('c261121081340_754', name=True))
        self.assertFalse(V.rel_ok('learned\\c1', name=True))
        self.assertFalse(V.rel_ok('learned/c1', name=True))

    def test_cut_out_ok(self):
        self.assertTrue(V.cut_out_ok(os.path.join(V.ROOT, 'learned', 'c261121081340_754')))
        self.assertTrue(V.cut_out_ok(os.path.join(V.ROOT, 'ui1.144', 'learned', 'c261121081340_754')))
        self.assertFalse(V.cut_out_ok(os.path.join(V.ROOT, 'balance', 'hit1')))
        self.assertFalse(V.cut_out_ok(os.path.join(V.ROOT, 'learned', '..', 'balance', 'hit1')))
        self.assertFalse(V.cut_out_ok(os.path.join(V.ROOT, 'learned', '..')))
        self.assertFalse(V.cut_out_ok(os.path.join('learned', 'c1')))
        self.assertFalse(V.cut_out_ok(os.path.join(tempfile.gettempdir(), 'learned', 'c1')))

    def test_learned_pic_names_stay_in_the_folder(self):
        # (refused before any file is looked at)
        for ent in ('c1:C:\\elsewhere:', 'c1:..:', 'c1::..\\..\\x', '..\\c1::', 'a\\b::', ':ui1.144:'):
            self.assertIsNone(V.learned_pic(ent, 1.0), ent)
        self.assertIsNone(V.learned_pic('c1::', 1.0, here='C:\\elsewhere'))


class Callers(unittest.TestCase):
    """every caller of the helper still passes the filter and the path checks: AutoFarmer asks 127.0.0.1 with WinHttp,
    no Origin header, and writes where the checks let it"""

    def test_ahk_callers_ask_127_0_0_1(self):
        for name in ('Vision.ahk', 'Dashboard.ahk', 'Overlay.ahk', 'BattleRec.ahk'):
            src = ahk(name)
            self.assertIn('"http://127.0.0.1:"', src, name)
            self.assertNotRegex(src, r'(?i)SetRequestHeader\("(Origin|Referer|Host|Sec-Fetch)', name)

    def test_cardlearn_paths(self):
        src = ahk('CardLearn.ahk')
        # (/cut's out: <set>\learned\<id>, the set a full path - A_WorkingDir, PicDir or a set's dir)
        self.assertRegex(src, r'/cut\?[^\n]*&out=" LearnUri\(setDir "\\learned\\" id\)')
        # (/hand's thumbs: a full path in the AutoFarmer folder; here: the set relative to it)
        self.assertIn('"&thumbs=" LearnUri(A_ScriptDir "\\generated\\hand")', src)
        self.assertRegex(src, r'hereRel := SubStr\(here, ')

    def test_map_files_in_temp(self):
        self.assertIn('DashMapFile := A_Temp "\\Wizard101 bot map\\navmap.png"', ahk('Dashboard.ahk'))
        self.assertTrue(re.search(r'OvFile := Map\("map", A_Temp "\\Wizard101 bot map\\', ahk('Overlay.ahk')))


if __name__ == '__main__':
    unittest.main()
