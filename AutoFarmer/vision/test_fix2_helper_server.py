"""test_fix2_helper_server.py - the helper's own runtime (the code review of 2026-11-27): its log written by one thread at a
time and rotated without losing a line; a damaged picture left out, not an ERR for the whole request, and pictures
written whole then put in place; an answer the bot stopped waiting for said as that, never a second one; /deckfor's
failed working-out not kept over a good answer, tried again after a minute (longer each failure in a row); its port its own (SO_EXCLUSIVEADDRUSE) and
/ping?pid=1; the readers of clients gone dropped; AutoFarmer's process held and waited on. The party's door not made
up from a trail long gone, and netmon's wrong-PIN lock, beacon checks, request timeout and the account's folder out
of the log lines it serves. No game, no network:  python -m unittest test_fix2_helper_server  (from AutoFarmer\\vision)"""
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import netmon as N  # noqa: E402
import party as P  # noqa: E402

try:
    import numpy as np  # noqa: E402
    from PIL import Image  # noqa: E402
    import vision as V  # noqa: E402
except ImportError:     # (numpy / Pillow missing: the helper's own checks skipped)
    V = None


def src(name):
    with open(os.path.join(HERE, name), encoding='utf-8') as f:
        return f.read()


@unittest.skipIf(V is None, 'needs numpy and Pillow')
class HelperCase(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='wm-fix2-')
        self._log = V.LOG
        V.LOG = os.path.join(self.dir, 'vision.log')

    def tearDown(self):
        V.LOG = self._log
        shutil.rmtree(self.dir, ignore_errors=True)

    def logged(self):
        try:
            with open(V.LOG, encoding='utf-8') as f:
                return f.read()
        except OSError:
            return ''


class Log(HelperCase):
    def test_rotated_once_and_no_line_lost(self):
        # (vision.log past 512 KB, 8 threads logging at once: one rotation - .old the whole old log - and every line in
        # the new one)
        with open(V.LOG, 'w', encoding='utf-8') as f:
            f.write('x' * (600 * 1024) + '\n')
        go = threading.Event()

        def many(k):
            go.wait()
            for i in range(50):
                V.log('line %d %d' % (k, i))
        ts = [threading.Thread(target=many, args=(k,)) for k in range(8)]
        for t in ts:
            t.start()
        go.set()
        for t in ts:
            t.join(30)
        self.assertGreater(os.path.getsize(V.LOG + '.old'), 512 * 1024)
        text = self.logged()
        for k in range(8):
            for i in range(50):
                self.assertIn(' line %d %d\n' % (k, i), text)

    def test_a_failed_rotation_still_writes_the_line(self):
        with mock.patch.object(V.os, 'replace', side_effect=PermissionError('in use')), \
                mock.patch.object(V.os.path, 'getsize', return_value=10 ** 9):
            V.log('still here')
        self.assertIn('still here', self.logged())


class Pictures(HelperCase):
    def picture(self, path, w=20, h=20):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        Image.fromarray(np.full((h, w, 3), 90, np.uint8)).save(path)

    def test_a_damaged_copy_passed_over(self):
        bad, good = os.path.join(self.dir, 'bad'), os.path.join(self.dir, 'good')
        os.makedirs(os.path.join(bad, 'balance'))
        open(os.path.join(bad, 'balance', 'hit1.png'), 'wb').close()          # (cut short: 0 bytes)
        self.picture(os.path.join(good, 'balance', 'hit1.png'))
        lib = V.Library.__new__(V.Library)
        lib.sets, lib.cache, lib.lock = [(bad, 1.0), (good, 1.0)], {}, threading.Lock()
        V.BADPIC_SAID.clear()
        got = lib.get('balance\\hit1.png', 1.0)
        self.assertIsNotNone(got)
        self.assertEqual(got[0].shape[:2], (20, 20))
        self.assertIn("can't be read", self.logged())
        # (all damaged: None - the picture absent - not an exception; usable says no)
        lib2 = V.Library.__new__(V.Library)
        lib2.sets, lib2.cache, lib2.lock = [(bad, 1.0)], {}, threading.Lock()
        self.assertIsNone(lib2.get('balance\\hit1.png', 1.0))
        with mock.patch.object(V, 'picture_sets', return_value=[(bad, 1.0)]):
            self.assertFalse(lib2.usable('balance\\hit1.png'))

    def test_refine_and_cut_written_whole(self):
        f = os.path.join(self.dir, 'learned', 'abc.png')
        self.picture(f)
        tpl = np.full((20, 20, 3), 90, np.float32)
        mask = np.ones((20, 20), bool)
        diff = np.zeros((20, 20), np.float32)
        diff[0, :] = 999
        pic = dict(tpl=tpl, mask=mask, name='learned/abc', files=[f], cid='abc', slot='', setdir='')
        with mock.patch.object(V, 'pictures_changed'):
            self.assertTrue(V.refine(pic, diff))
        a = np.asarray(Image.open(f).convert('RGB'))
        self.assertEqual(tuple(a[0, 0]), (255, 0, 255))
        self.assertFalse(os.path.exists(f + '.tmp'))
        for fn in ('refine', 'cut_here', 'cut_card'):
            body = src('vision.py').split('\ndef %s(' % fn, 1)[1].split('\ndef ', 1)[0]
            self.assertNotRegex(body, r'\)\.save\(|\ba\.save\(', fn)
            self.assertIn('save_png(', body, fn)


class Reply(HelperCase):
    def handler(self, exc):
        h = V.Handler.__new__(V.Handler)
        h.path, h.request_version, h.requestline, h.command = '/nav?x=1', 'HTTP/1.0', 'GET /nav?x=1 HTTP/1.0', 'GET'
        h.client_address, h.close_connection = ('127.0.0.1', 5), False
        h.t0 = time.perf_counter() - 0.2

        class W:
            def write(self, b):
                raise exc

            def flush(self):
                pass
        h.wfile = W()
        return h

    def test_closed_connection_said_once_no_second_reply(self):
        for exc in (ConnectionResetError(10054, 'reset'), ConnectionAbortedError(10053, 'aborted'), BrokenPipeError()):
            h = self.handler(exc)
            h.reply('OK')                                   # (no exception out of it)
            self.assertTrue(h.close_connection)
        text = self.logged()
        self.assertRegex(text, r'/nav: the bot stopped waiting after \d+ ms \(it closed the connection\)')
        self.assertNotIn('ERR', text)
        # (VisionStartWhy takes a line with "error" or "exception" as why a start failed)
        self.assertNotRegex(text.lower(), r'error|exception')

    def test_rec_posts_not_logged(self):
        h = self.handler(ConnectionResetError())
        h.path = '/rec?k=round'
        h.reply('ok')
        self.assertEqual(self.logged(), '')


@unittest.skipIf(V is None, 'needs numpy and Pillow')
class DeckForFailed(unittest.TestCase):
    def setUp(self):
        import test_plan as TP
        import battlesim as S
        self.TP, self.S = TP, S
        self.keep = (dict(V.DECKFOR['cache']), dict(V.DECKFOR['failed']))
        V.DECKFOR['cache'].clear()
        V.DECKFOR['failed'].clear()

    def tearDown(self):
        t = V.DECKFOR['thread']
        if t is not None:
            t.join(30)
        V.DECKFOR['cache'].clear()
        V.DECKFOR['failed'].clear()
        V.DECKFOR['cache'].update(self.keep[0])
        V.DECKFOR['failed'].update(self.keep[1])

    def boom(self, *a, **kw):
        raise RuntimeError('an odd record')

    def test_good_answer_kept_through_a_failed_refresh(self):
        ctx = self.TP.DeckFor.ctx(None)
        q = {'zone': 'Z/Graveyard', 'school': 'storm', 'n': '10'}
        good = V.deckfor_lines_for(q, ctx, wait=True)
        self.assertTrue(good[0].startswith('deckfor|'), good)
        (key, (at, lines)), = V.DECKFOR['cache'].items()
        V.DECKFOR['cache'][key] = (at - V.DECKFOR_S - 120, lines)
        with mock.patch.object(self.S, 'best_decks', self.boom):
            old = V.deckfor_lines_for(q, ctx)
            self.assertEqual(old[:len(good)], good)
            V.DECKFOR['thread'].join(30)
            # (the good answer still kept as it was, the failure kept apart)
            self.assertEqual(V.DECKFOR['cache'][key], (at - V.DECKFOR_S - 120, lines))
            self.assertIn(key, V.DECKFOR['failed'])
            # (asked again within the minute: the old rows with a note, no new thread)
            again = V.deckfor_lines_for(q, ctx)
            self.assertFalse(V.DECKFOR['thread'].is_alive())
            self.assertEqual(again[:len(good)], good)
            self.assertIn('working it out again failed', again[-1])
        # (a minute on: worked out again - good now - and the failure forgotten)
        f = V.DECKFOR['failed'][key]
        V.DECKFOR['failed'][key] = (f[0] - V.DECKFOR_RETRY_S - 1,) + f[1:]
        V.deckfor_lines_for(q, ctx)
        V.DECKFOR['thread'].join(30)
        self.assertNotIn(key, V.DECKFOR['failed'])
        self.assertEqual(V.DECKFOR['cache'][key][1], good)

    def test_first_failure_answered_not_retried_at_once(self):
        ctx = self.TP.DeckFor.ctx(None)
        q = {'zone': 'Z/Graveyard', 'school': 'storm', 'n': '10'}
        with mock.patch.object(self.S, 'best_decks', self.boom):
            out = V.deckfor_lines_for(q, ctx, wait=True)
            self.assertTrue(out[0].startswith("none|the decks couldn't be simulated"), out)
            self.assertEqual(V.DECKFOR['cache'], {})
            self.assertEqual(V.deckfor_lines_for(q, ctx), out)
            self.assertFalse(V.DECKFOR['thread'] is not None and V.DECKFOR['thread'].is_alive())

    def test_failing_again_backs_off_and_is_said_once(self):
        # (review 2.2: one that always fails - tried again twice as late each time, DECKFOR_S at most, and the same
        # failure logged once, not every minute)
        ctx = self.TP.DeckFor.ctx(None)
        q = {'zone': 'Z/Graveyard', 'school': 'storm', 'n': '10'}
        said = []
        with mock.patch.object(self.S, 'best_decks', self.boom), mock.patch.object(V, 'log', said.append):
            retries = []
            for _ in range(6):
                V.deckfor_lines_for(q, ctx, wait=True)
                (key, f), = V.DECKFOR['failed'].items()
                retries.append(f[2])
            self.assertEqual(retries, [60, 120, 240, 480, 600, 600])
            self.assertEqual(len([x for x in said if "couldn't be simulated" in x]), 1, said)
            # (within its retry time: answered from the failure, no thread)
            f = V.DECKFOR['failed'][key]
            V.DECKFOR['failed'][key] = (f[0] - 300,) + f[1:]
            self.assertTrue(V.deckfor_lines_for(q, ctx)[0].startswith('none|'))
            self.assertFalse(V.DECKFOR['thread'] is not None and V.DECKFOR['thread'].is_alive())
            # (a DECKFOR_S on: said again)
            f = V.DECKFOR['failed'][key]
            V.DECKFOR['failed'][key] = f[:3] + (f[3] - V.DECKFOR_S,) + f[4:]
            V.deckfor_lines_for(q, ctx, wait=True)
            self.assertEqual(len([x for x in said if "couldn't be simulated" in x]), 2, said)


@unittest.skipIf(V is None, 'needs numpy and Pillow')
class Port(unittest.TestCase):
    def test_exclusive_port(self):
        a = V.HelperServer(('127.0.0.1', 0), V.Handler)
        try:
            port = a.server_address[1]
            with self.assertRaises(OSError):
                V.HelperServer(('127.0.0.1', port), V.Handler).server_close()
            # (a server of Python's own - SO_REUSEADDR - doesn't bind beside it either)
            from http.server import ThreadingHTTPServer
            with self.assertRaises(OSError):
                ThreadingHTTPServer(('127.0.0.1', port), V.Handler).server_close()
        finally:
            a.server_close()
        self.assertTrue(V.HelperServer.daemon_threads)
        self.assertIn('server = HelperServer((', src('vision.py'))

    def test_ping_pid(self):
        srv = V.HelperServer(('127.0.0.1', 0), V.Handler)
        threading.Thread(target=srv.serve_forever, daemon=True).start()
        try:
            import http.client
            for path, want in (('/ping', 'OK ' + V.VERSION), ('/ping?pid=1', 'OK %s pid %d' % (V.VERSION, os.getpid()))):
                c = http.client.HTTPConnection('127.0.0.1', srv.server_address[1], timeout=5)
                c.request('GET', path)
                self.assertEqual(c.getresponse().read().decode(), want)
                c.close()
        finally:
            srv.shutdown()
            srv.server_close()


@unittest.skipIf(V is None, 'needs numpy and Pillow')
class Clients(HelperCase):
    def test_gone_clients_dropped(self):
        import navmem

        class R:
            closed = False

            def close(self):
                R.closed = True
        keep = dict(V.NAVS)
        try:
            V.NAVS.clear()
            V.NAVS.update({111: R(), 222: R(), 333: R()})
            with mock.patch.object(navmem, 'find_pids', return_value=[222]):
                V.clients_gone({333})
            self.assertEqual(sorted(V.NAVS), [222, 333])       # (333 just asked for: kept, running or not)
            for _ in range(100):
                if R.closed:
                    break
                time.sleep(0.02)
            self.assertTrue(R.closed)
            self.assertIn('pid 111 no longer running', self.logged())
            # (no client running - or the list not had: none dropped)
            with mock.patch.object(navmem, 'find_pids', return_value=[]):
                V.clients_gone(set())
            self.assertEqual(sorted(V.NAVS), [222, 333])
        finally:
            V.NAVS.clear()
            V.NAVS.update(keep)
        self.assertIn('clients_gone(asked | {CLIENT})', src('vision.py'))


@unittest.skipIf(V is None or os.name != 'nt', 'needs numpy, Pillow and Windows')
class Parent(unittest.TestCase):
    def test_held_and_waited_on(self):
        p = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(1)'])
        h = V.parent_handle(p.pid)
        self.assertTrue(h)
        t0 = time.monotonic()
        V.parent_wait(h, p.pid, every=0.2)
        self.assertLess(time.monotonic() - t0, 10)
        p.wait(5)
        self.assertIsNotNone(p.returncode)
        main = src('vision.py').split('\ndef main(', 1)[1]
        self.assertIn('parent_h = parent_handle(args.parent)', main)
        self.assertIn('parent_wait(parent_h, args.parent)', main)


class Clock:
    def __init__(self, t=1000.0):
        self.t = t

    def time(self):
        return self.t

    def monotonic(self):
        return self.t

    def sleep(self, s):
        self.t += s


class Quiet(P.Party):
    def _loop(self):
        return


class PartyDoor(unittest.TestCase):
    def setUp(self):
        self.clock, self._time = Clock(), P.time
        P.time = self.clock
        self.logged = []
        self.box = {'r': None}
        self.p = Quiet(lambda: self.box['r'], log=self.logged.append)
        self.p.cfg['role'] = 'leader'

    def tearDown(self):
        P.time = self._time

    def at(self, zone, x, y):
        self.box['r'] = {'zone': zone, 'pos': (x, y, 0.0), 'yaw': 0.0, 'source': 'body'}
        self.p._read()
        self.clock.t += 0.4

    def walk(self, zone):
        for i in range(6):
            self.at(zone, 400 * 0.4 * i, 0)

    def test_door_across_a_loading_screen(self):
        self.walk('A')
        self.box['r'] = None
        for _ in range(50):                 # (20 s of no reading: a loading screen)
            self.p._read()
            self.clock.t += 0.4
        self.at('B', 0, 0)
        self.assertEqual((self.p.door['zone'], self.p.door['walked']), ('A', True))

    def test_no_door_after_a_long_gap(self):
        self.walk('A')
        self.box['r'] = None
        self.p._read()
        self.clock.t += 3600
        self.at('B', 0, 0)
        self.assertIsNone(self.p.door)
        self.assertEqual(self.p.doors, [])
        self.assertIn('not a door', self.logged[-1])
        self.assertEqual(self.p.zone_at, self.clock.t - 0.4)

    def test_trail_cleared_while_off(self):
        self.walk('A')
        self.p.cfg['role'] = 'off'
        self.p._read()
        self.assertEqual(self.p.trail, [])
        self.p.cfg['role'] = 'leader'
        self.at('B', 0, 0)
        self.assertIsNone(self.p.door)


class NetCase(unittest.TestCase):
    def make(self):
        with mock.patch.object(threading.Thread, 'start'):
            n = N.NetMon(lambda *a: None, os.devnull, log=self.logged.append)
        n.cfg['pin'] = 1234
        return n

    def setUp(self):
        self.logged = []

    def cmd(self, n, pin, ip='192.168.1.9', c='on'):
        t, nonce = '%d' % time.time(), '%016x' % int.from_bytes(os.urandom(8), 'big')
        return n.take({'c': c, 'to': n.id, 't': t, 'n': nonce, 'mac': N.sign(pin, c, n.id, t, nonce), 'from': 'X'}, ip)


class NetPin(NetCase):
    def test_wrong_pins_lock_one_address(self):
        n = self.make()
        for pin in range(N.BAD_PIN_IP):
            self.assertEqual(self.cmd(n, pin)[0], 403)
        code, why = self.cmd(n, 1234)                       # (the right one now: refused too)
        self.assertEqual(code, 403)
        self.assertIn('too many wrong network PINs', why)
        self.assertEqual(self.cmd(n, 1234, ip='192.168.1.10')[0], 200)     # (another address: taken)
        self.assertEqual(len([x for x in self.logged if 'with the wrong network PIN' in x]), 1)   # (once a minute)
        # (aged out: taken again)
        n.bad = [(at - N.BAD_PIN_S - 1, ip) for at, ip in n.bad]
        self.assertEqual(self.cmd(n, 1234)[0], 200)

    def test_wrong_pins_from_all_lock_all(self):
        n = self.make()
        for i in range(N.BAD_PIN_ALL):
            self.cmd(n, 1, ip='192.168.1.%d' % (100 + i % 4))
        self.assertIn('too many', self.cmd(n, 1234, ip='192.168.1.50')[1])

    def test_lock_not_stretched_by_tries_meanwhile(self):
        # (review 2.1: tries while locked aren't counted - the PIN put right works 10 minutes after the last wrong one
        # however often it's tried meanwhile, and one PC's refused tries never lock out the others)
        n = self.make()
        for pin in range(N.BAD_PIN_IP):
            self.cmd(n, pin)
        for _ in range(3 * N.BAD_PIN_ALL):
            code, why = self.cmd(n, 1234)
            self.assertEqual(code, 403)
        self.assertEqual(len(n.bad), N.BAD_PIN_IP)
        self.assertIn('for 10 more minutes', why)
        self.assertEqual(self.cmd(n, 1234, ip='192.168.1.10')[0], 200)     # (another PC: not locked by them)
        n.bad = [(at - N.BAD_PIN_S + 90, ip) for at, ip in n.bad]
        self.assertIn('for 2 more minutes', self.cmd(n, 1234)[1])           # (the minutes really left)
        n.bad = [(at - 91, ip) for at, ip in n.bad]
        self.assertEqual(self.cmd(n, 1234)[0], 200)

    def test_not_for_this_bot_not_counted(self):
        n = self.make()
        for _ in range(10):
            self.assertEqual(n.take({'c': 'on', 'to': '0' * 16}, '192.168.1.9')[0], 400)
        self.assertEqual(self.cmd(n, 1234)[0], 200)


class NetBeacons(NetCase):
    def beacon(self, n, pc, nid, ip):
        import json
        n._heard(json.dumps({'wm': 1, 'id': nid, 'port': 47150, 'pc': pc}).encode(), ip)

    def test_a_pc_heard_now_not_taken_over(self):
        n = self.make()
        self.beacon(n, 'DESK', 'a' * 16, '192.168.1.5')
        self.beacon(n, 'DESK', 'b' * 16, '192.168.1.66')            # (another address, another id: refused)
        self.assertEqual((n.peers['DESK']['id'], n.peers['DESK']['ip']), ('a' * 16, '192.168.1.5'))
        self.assertIn('not taken', self.logged[-1])
        self.beacon(n, 'DESK', 'c' * 16, '192.168.1.5')             # (started again: same address, new id)
        self.assertEqual(n.peers['DESK']['id'], 'c' * 16)
        n.peers['DESK']['at'] -= N.STALE + 1                        # (gone quiet: one that moved is taken)
        self.beacon(n, 'DESK', 'd' * 16, '192.168.1.77')
        self.assertEqual(n.peers['DESK']['ip'], '192.168.1.77')

    def test_peers_capped(self):
        n = self.make()
        for i in range(N.MAX_PEERS + 20):
            self.beacon(n, 'PC%d' % i, '%016x' % (i + 1), '10.0.0.%d' % (i % 250 + 1))
        self.assertEqual(len(n.peers), N.MAX_PEERS)
        for p in list(n.peers.values())[:5]:
            p['at'] -= N.STALE + 1
        self.beacon(n, 'NEW', 'f' * 16, '10.0.1.1')                 # (one gone quiet makes room)
        self.assertIn('NEW', n.peers)
        self.assertLessEqual(len(n.peers), N.MAX_PEERS)

    def test_handler_timeout(self):
        n = self.make()
        self.assertEqual(n._handler().timeout, N.HTTP_TIMEOUT)


class NetLog(unittest.TestCase):
    def test_account_folder_out(self):
        line = ('18:04:37 Vision: helper running (C:\\Users\\someone\\AppData\\Local\\Programs\\Python\\Python312\\\\'
                'pythonw.exe, pid 11268)\nshot C:\\\\Users\\\\someone\\\\x.png and D:\\Games\\w.exe')
        with mock.patch.dict(os.environ, {'USERPROFILE': 'E:\\Home\\me'}):
            out = N.no_user_dir(line + ' E:\\Home\\me\\a.txt')
        self.assertNotIn('someone', out)
        self.assertNotIn('Home\\me', out)
        self.assertIn('%USERPROFILE%\\AppData\\Local', out)
        self.assertIn('D:\\Games\\w.exe', out)
        d = tempfile.mkdtemp(prefix='wm-fix2-')
        try:
            f = os.path.join(d, 'debug.log')
            with open(f, 'w', encoding='utf-8') as fh:
                fh.write(line + '\n')
            with mock.patch.object(threading.Thread, 'start'):
                n = N.NetMon(lambda *a: None, f, log=lambda m: None)
            self.assertNotIn('someone', n.log_tail(10))
        finally:
            shutil.rmtree(d, ignore_errors=True)


if __name__ == '__main__':
    unittest.main()
