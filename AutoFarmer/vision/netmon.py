"""Network: every bot on the home network, seen from every other - the dashboard's Network tab (v0.46.0, asked
2026-10-24: a PC that runs the bot all day, watched and steered from another).

  * Each bot's helper announces it every BEACON s: a UDP broadcast on the network port (Settings: netport, 47150) with
    what its AutoFarmer says (/net: the PC's name, version, wizard, school, zone, bot on / off / standby, Play for me,
    what it's doing, health, mana, deaths, its status line and last log line) - a small JSON; every field checked on
    the way in, as party.py does.
  * Each listens on that port (UDP) for the others', and serves them on it (TCP - a server of its own, only for private
    addresses; none of the helper's other requests can be reached from the network):
      GET /net/log?n=        the last lines of its debug.log
      GET /net/snap          a picture of its game - taken only while Wizard101 is the window in front (AutoFarmer
                             says, every 2 s): nothing else on its screen is ever sent
      GET /net/cmd?...       a command - bot on, bot off, Play for me off, restart - taken only with the network PIN
                             (Settings: netpin, the same on both PCs; 0: none taken or sent): signed with it (HMAC-SHA256
                             over the command, the bot it's for, the time and a nonce - 2 minutes old at most, each nonce
                             once). AutoFarmer picks it up at its next /net
  * Play for me can only be switched OFF from the network: on only at that PC (its button - your say-so).
  * /net/log and /net/snap are answered to any private address, no PIN asked (the Network tab's view - the PIN guards
    commands only). Wrong PINs: a few from one address - or more from all - in BAD_PIN_S and commands are refused till
    they've aged out (a PIN can't be guessed by trying them all).
Never sent: the game's login, anything from Credential Manager, the GitHub token, the Discord webhook, the PIN itself.
The log lines sent have the Windows account's own folder taken out (C:\\Users\\<name> - USERPROFILE - sent as
%USERPROFILE%)."""
import hashlib
import hmac
import http.client
import io
import ipaddress
import json
import os
import random
import re
import socket
import tempfile
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = 47150            # the network port, UDP and TCP (a setting)
BEACON = 3.0            # how often each bot announces itself
STALE = 15.0            # a bot not heard from this long is shown as gone quiet...
FORGET = 600.0          # ...and this long, dropped
CMD_AGE = 120.0         # a command at most this old (s) - the two PCs' clocks must agree that closely
COMMANDS = ('on', 'off', 'pfmoff', 'restart')
BIND = '0.0.0.0'        # where it listens (tests only: 127.0.0.1 - no firewall question)
TEXT_RE = re.compile(r"[^\x20-\x7E]")
BOTS = ('on', 'off', 'standby')
MAX_PEERS = 32          # bots kept from the beacons (more: one gone quiet makes room, else the new one isn't kept)
BAD_PIN_S = 600.0       # wrong PINs counted this long (s)...
BAD_PIN_IP = 5          # ...this many from one address - or...
BAD_PIN_ALL = 20        # ...this many from all of them -: every command refused till they're older (tries meanwhile not counted)
BAD_PIN_KEEP = 256      # the wrong tries remembered at most
HTTP_TIMEOUT = 3.0      # s a network client has to send its request (one that sends nothing doesn't hold a thread for good)
# the account's own folder in a log line - C:\Users\<name>, its \ doubled or not
USER_DIR_RE = re.compile(r'(?i)\b[a-z]:\\{1,2}users\\{1,2}[^\\/:*?"<>|\r\n,()]+')


def no_user_dir(text):
    """text with the Windows account's own folder (C:\\Users\\<name>, and USERPROFILE wherever it is) as %USERPROFILE%:
    the log lines another PC is sent"""
    home = os.environ.get('USERPROFILE') or ''
    if len(home) > 3:
        text = re.sub(re.escape(home).replace(r'\\', r'\\{1,2}'), '%USERPROFILE%', text, flags=re.I)
    return USER_DIR_RE.sub('%USERPROFILE%', text)


def _text(v, n):
    """printable ASCII, | out (the fields AutoFarmer splits on), at most n long"""
    return TEXT_RE.sub('', str(v if v is not None else '')).replace('|', '/')[:n].strip()


def _num(v, lo, hi):
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    return x if lo <= x <= hi else None


def clean_state(d):
    """a bot's state - only these fields, each checked (a wrong one: blank)"""
    d = d if isinstance(d, dict) else {}
    s = {'pc': _text(d.get('pc'), 32), 'ver': _text(d.get('ver'), 16), 'wiz': _text(d.get('wiz'), 32),
         'school': _text(d.get('school'), 10).lower(), 'zone': _text(d.get('zone'), 80), 'doing': _text(d.get('doing'), 80),
         'hp': _text(d.get('hp'), 24), 'mana': _text(d.get('mana'), 24), 'status': _text(d.get('status'), 120),
         'last': _text(d.get('last'), 160)}
    s['bot'] = d.get('bot') if d.get('bot') in BOTS else ''
    s['pfm'] = '1' if str(d.get('pfm')) == '1' else '0'
    for k, hi in (('deaths', 1e6), ('dall', 1e7), ('up', 1e8)):
        v = _num(d.get(k), 0, hi)
        s[k] = int(v) if v is not None else ''
    return s


def game_in_front():
    """Wizard101's window is the one in front (its class) - tests can stand in for it (GAME_FRONT)"""
    if GAME_FRONT is not None:
        return GAME_FRONT()
    try:
        import ctypes
        u = ctypes.windll.user32
        buf = ctypes.create_unicode_buffer(64)
        u.GetClassNameW(u.GetForegroundWindow(), buf, 64)
        return buf.value == 'Wizard Graphical Client'
    except Exception:  # noqa: BLE001
        return False


GAME_FRONT = None       # (tests only: a function standing in for game_in_front)


def private(ip):
    try:
        a = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return a.is_private or a.is_loopback


def _key(pin):
    return hashlib.sha256(('wiz-maxxing network|%s' % pin).encode()).digest()


def sign(pin, c, target, t, nonce):
    return hmac.new(_key(pin), ('%s|%s|%s|%s' % (c, target, t, nonce)).encode(), hashlib.sha256).hexdigest()


class NetServer(ThreadingHTTPServer):
    """the network's server: its port its own (no address reuse - on Windows that lets a second server share it)"""
    allow_reuse_address = False
    daemon_threads = True

    def server_bind(self):
        if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()


class NetMon:
    """this PC's part of the Network tab. grab(x1, y1, x2, y2): the screen there as an RGB array; log_file: debug.log"""

    def __init__(self, grab, log_file, log=print):
        self.grab, self.log_file, self.log = grab, log_file, log
        self.lock = threading.Lock()
        self.cfg = {'on': False, 'port': PORT, 'pin': 0}
        self.me = {}                        # what AutoFarmer said last (clean_state)
        self.front = (False, None, 0.0)     # Wizard101 in front, its area (x, y, w, h), when AutoFarmer said so
        self.peers = {}                     # PC name -> state with 'id', 'ip', 'port', 'at'
        self.cmds = []                      # commands taken, for AutoFarmer: (c, from PC)
        self.nonces = {}                    # nonce -> when (each taken once)
        self.bad = []                       # wrong PINs: (when, from ip), the last BAD_PIN_KEEP
        self.said = {}                      # a warning's key -> when it was last logged (once a minute each)
        self.state, self.why = 'off', ''
        self.udp, self.server, self.bound = None, None, None
        self.next_beacon = 0.0
        self.id = '%016x' % random.getrandbits(64)
        # the bot picked on this PC's Network tab: its id, fetched in a thread of its own (AutoFarmer never waits on the
        # network) - {id, at, log: [lines], snap: path or '', why}; a refresh asked for
        self.sel, self.sel_got, self.sel_now = '', {}, False
        threading.Thread(target=self._loop, name='netmon', daemon=True).start()
        threading.Thread(target=self._fetch_loop, name='netmon-fetch', daemon=True).start()

    # ------------------------------------------------------------------ from AutoFarmer (the helper's /net)
    def update(self, q):
        """/net: this bot's settings and state in; lines out - net|state|why, me|id|port, peer|..., cmd|c|from"""
        on = str(q.get('on', '0')) == '1'
        port = int(_num(q.get('port'), 1024, 65535) or PORT)
        pin = int(_num(q.get('pin'), 0, 99999999) or 0)
        front = str(q.get('front', '0')) == '1'
        area = tuple(int(_num(q.get(k), -20000, 20000) or 0) for k in ('gx', 'gy', 'gw', 'gh'))
        sel = str(q.get('sel', ''))
        with self.lock:
            self.cfg.update(on=on, port=port, pin=pin)
            self.sel = sel if re.match(r'^[0-9a-f]{16}$', sel) else ''
            self.sel_now = self.sel_now or str(q.get('refresh', '0')) == '1'
            self.me = clean_state(q)
            self.front = (front, area if area[2] > 0 and area[3] > 0 else None, time.monotonic())
            cmds, self.cmds = self.cmds, []
            now = time.monotonic()
            for name in [n for n, p in self.peers.items() if now - p['at'] > FORGET]:
                del self.peers[name]
            out = ['net|%s|%s' % (self.state, _text(self.why, 160)), 'me|%s|%d' % (self.id, port)]
            for name, p in sorted(self.peers.items()):
                out.append('|'.join(['peer', p['id'], p['ip'], '%.0f' % (now - p['at'])]
                                    + [str(p.get(k, '')) for k in ('pc', 'ver', 'wiz', 'school', 'zone', 'bot', 'pfm',
                                                                    'doing', 'hp', 'mana', 'deaths', 'dall', 'up',
                                                                    'status', 'last')]))
        out += ['cmd|%s|%s' % (c, _text(src, 32)) for c, src in cmds]
        return out

    def peer(self, pid):
        with self.lock:
            for p in self.peers.values():
                if p['id'] == pid:
                    return dict(p)
        return None

    def picked(self, pid):
        """/netpeer: what the fetch thread has of the picked bot pid - at|<s ago>, why|<why>, snap|<file>, log|<line>...;
        ERR when it isn't the one picked (yet)"""
        with self.lock:
            g = dict(self.sel_got)
        if g.get('id') != pid:
            return ['ERR fetching its log and game...']
        out = ['at|%.0f' % (time.monotonic() - g['at']), 'why|' + _text(g.get('why'), 160)]
        if g.get('snap'):
            out.append('snap|' + g['snap'])
        return out + ['log|' + ln for ln in g.get('log', [])]

    def _get(self, p, path, limit):
        """GET path from bot p: (status, body) - short waits: it's for a picture on a tab"""
        c = http.client.HTTPConnection(p['ip'], p['port'], timeout=2.5)
        try:
            c.request('GET', path)
            r = c.getresponse()
            return r.status, r.read(limit)
        finally:
            c.close()

    def _fetch_one(self, p):
        """the picked bot's log and picture: {id, at, log, snap, why}"""
        g = {'id': p['id'], 'at': time.monotonic(), 'log': [], 'snap': '', 'why': ''}
        who = p.get('pc') or p['ip']
        try:
            st, body = self._get(p, '/net/log?n=80', 256 * 1024)
            if st == 200:
                g['log'] = [TEXT_RE.sub('', ln)[:300] for ln in body.decode('utf-8', 'replace').splitlines()[-80:]]
            else:
                g['why'] = '%s says: %s' % (who, _text(body.decode('utf-8', 'replace'), 120))
            st, body = self._get(p, '/net/snap', 2 * 1024 * 1024)
            if st == 200 and body[:3] == b'\xff\xd8\xff':
                out = os.path.join(tempfile.gettempdir(), 'wiz-maxxing-net-%s.jpg' % p['id'])
                with open(out + '.tmp', 'wb') as fh:
                    fh.write(body)
                os.replace(out + '.tmp', out)
                g['snap'] = out
            elif not g['why']:
                g['why'] = _text(body.decode('utf-8', 'replace'), 160) if st != 200 else 'its picture isn\'t a JPEG'
        except OSError as e:
            g['why'] = 'no answer from %s (%s)' % (who, e.__class__.__name__)
        return g

    def _fetch_loop(self):
        """the picked bot's log and picture every 6 s (at once on a refresh), while it's heard - in this thread"""
        last = 0.0
        while True:
            time.sleep(0.5)
            try:
                with self.lock:
                    sel, now_ = self.sel, self.sel_now
                    self.sel_now = False
                if not sel:
                    continue
                p = self.peer(sel)
                if p is None:
                    continue
                age = time.monotonic() - p['at']
                if age > STALE:
                    with self.lock:
                        self.sel_got = {'id': sel, 'at': time.monotonic(), 'log': [], 'snap': '',
                                        'why': 'not heard from for %.0f s - asleep, off, or its network isn\'t Private?' % age}
                    continue
                if not now_ and time.monotonic() - last < 6.0 and self.sel_got.get('id') == sel:
                    continue
                last = time.monotonic()
                g = self._fetch_one(p)
                with self.lock:
                    if self.sel == sel:
                        self.sel_got = g
            except Exception as e:  # noqa: BLE001 - the thread carries on
                self.log('netmon: fetching failed (%r)' % (e,))

    def command(self, pid, c):
        """/netcmd: command c to a bot, signed with this PC's PIN - ok|<its answer> or ERR <why>"""
        if c not in COMMANDS:
            return 'ERR no such command'
        with self.lock:
            pin = self.cfg['pin']
        if not pin:
            return 'ERR set the network PIN first (Settings: netpin - the same on both PCs)'
        p = self.peer(pid)
        if p is None:
            return 'ERR that bot isn\'t heard any more'
        if time.monotonic() - p['at'] > STALE:
            return 'ERR %s hasn\'t been heard from for %.0f s - nothing sent' % (p.get('pc') or p['ip'], time.monotonic() - p['at'])
        t, nonce = '%d' % time.time(), '%016x' % random.getrandbits(64)
        q = urllib.parse.urlencode({'c': c, 'to': p['id'], 't': t, 'n': nonce, 'from': self.me.get('pc', ''),
                                    'mac': sign(pin, c, p['id'], t, nonce)})
        try:
            h = http.client.HTTPConnection(p['ip'], p['port'], timeout=2.5)
            h.request('GET', '/net/cmd?' + q)
            r = h.getresponse()
            body = _text(r.read(2000).decode('utf-8', 'replace'), 160)
            h.close()
        except OSError as e:
            return 'ERR no answer from %s (%s)' % (p.get('pc') or p['ip'], e.__class__.__name__)
        return ('ok|' if r.status == 200 else 'ERR ') + body

    # ------------------------------------------------------------------ from the network
    def _say_once(self, key, msg, every=60.0):
        """msg logged - the same key at most once a minute (a flood of bad beacons or tries is one line)"""
        now = time.monotonic()
        with self.lock:
            if now - self.said.get(key, -every) < every:
                return
            if len(self.said) > 256:
                self.said.clear()
            self.said[key] = now
        self.log(msg)

    def take(self, q, ip):
        """a command from the network: (status, answer)"""
        with self.lock:
            pin = self.cfg['pin']
        if not pin:
            return 403, 'this bot takes no commands (its network PIN is 0)'
        c, to, t, nonce, mac = (q.get(k, '') for k in ('c', 'to', 't', 'n', 'mac'))
        if c not in COMMANDS or to != self.id or not re.match(r'^\d{1,12}$', t) or not re.match(r'^[0-9a-f]{16}$', nonce):
            return 400, 'not a command for this bot'
        # (wrong PINs: BAD_PIN_IP from this address or BAD_PIN_ALL from all in BAD_PIN_S - every command refused, before
        # its PIN is looked at, till they're older: a PIN can't be found by trying them. A try meanwhile isn't counted -
        # its PIN never looked at, it tells nothing - so the PIN put right works BAD_PIN_S after the last wrong one, and
        # one PC's refused tries never lock out the others)
        with self.lock:
            now = time.monotonic()
            self.bad = [b for b in self.bad if now - b[0] <= BAD_PIN_S]
            mine = [b[0] for b in self.bad if b[1] == ip]
            wait = 0.0
            if len(mine) >= BAD_PIN_IP:                       # (till enough of this address's have aged out)
                wait = mine[len(mine) - BAD_PIN_IP] + BAD_PIN_S - now
            if len(self.bad) >= BAD_PIN_ALL:                  # (...or of all of them)
                wait = max(wait, self.bad[len(self.bad) - BAD_PIN_ALL][0] + BAD_PIN_S - now)
            n = len(self.bad)
        if wait > 0:
            mins = max(1, int(-(-wait // 60)))
            self._say_once('locked', 'netmon: a command from %s refused - %d wrong network PINs lately (%d from there): '
                                     'none taken for %d more minutes' % (ip, n, len(mine), mins))
            return 403, ('too many wrong network PINs lately - no command is taken for %d more minute%s (the PIN has '
                         'to be the same on both PCs)' % (mins, '' if mins == 1 else 's'))
        if not hmac.compare_digest(sign(pin, c, to, t, nonce), str(mac)):
            with self.lock:
                self.bad = (self.bad + [(time.monotonic(), ip)])[-BAD_PIN_KEEP:]
                n = len(self.bad)
            self._say_once('bad ' + ip, 'netmon: a command from %s with the wrong network PIN (%d wrong in the last %d '
                                        'minutes)' % (ip, n, BAD_PIN_S // 60))
            return 403, 'wrong network PIN (it has to be the same on both PCs)'
        off = time.time() - int(t)
        if abs(off) > CMD_AGE:
            return 403, 'the two PCs\' clocks are %d s apart - set both to the time automatically' % abs(off)
        with self.lock:
            now = time.monotonic()
            for n in [n for n, at in self.nonces.items() if now - at > 2 * CMD_AGE]:
                del self.nonces[n]
            if nonce in self.nonces:
                return 403, 'that command was taken already'
            self.nonces[nonce] = now
            self.cmds.append((c, _text(q.get('from'), 32) or ip))
        self.log('netmon: command %s from %s (%s)' % (c, _text(q.get('from'), 32), ip))
        return 200, 'taken: %s' % c

    def snap_jpeg(self):
        """a JPEG of the game while it's the window in front - AutoFarmer said so in the last 5 s, and it's so just before
        and just after the grab (an alt-tab meanwhile: nothing sent) - else None, why"""
        why = 'Wizard101 isn\'t the window in front there - no picture (nothing else on its screen is sent)'
        with self.lock:
            front, area, at = self.front
        if not front or area is None or time.monotonic() - at > 5.0 or not game_in_front():
            return None, why
        from PIL import Image
        import numpy as np
        x, y, w, h = area
        a = self.grab(x, y, x + w, y + h)
        if not game_in_front():
            return None, why
        im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
        if im.width > 960:
            im = im.resize((960, max(1, round(im.height * 960 / im.width))), Image.BILINEAR)
        buf = io.BytesIO()
        im.save(buf, 'JPEG', quality=65)
        return buf.getvalue(), ''

    def log_tail(self, n):
        try:
            with open(self.log_file, 'rb') as f:
                f.seek(0, os.SEEK_END)
                size = f.tell()
                f.seek(max(0, size - 64 * 1024))
                data = f.read()
        except OSError:
            return ''
        return no_user_dir('\n'.join(data.decode('utf-8', 'replace').splitlines()[-max(1, min(200, n)):]))

    def _handler(self):
        net = self

        class Handler(BaseHTTPRequestHandler):
            # (a client that connects and sends nothing is let go after this - as party.py's)
            timeout = HTTP_TIMEOUT

            def log_message(self, *a):
                pass

            def send(self, code, body, ctype='text/plain; charset=utf-8'):
                b = body if isinstance(body, bytes) else body.encode('utf-8')
                self.send_response(code)
                self.send_header('Content-Type', ctype)
                self.send_header('Content-Length', str(len(b)))
                self.end_headers()
                self.wfile.write(b)

            def do_GET(self):
                ip = self.client_address[0]
                if not private(ip) or len(self.path) > 2048:
                    return self.send(403, 'not from the home network')
                u = urllib.parse.urlparse(self.path)
                q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
                try:
                    if u.path == '/net/log':
                        return self.send(200, net.log_tail(int(_num(q.get('n'), 1, 200) or 60)))
                    if u.path == '/net/snap':
                        jpg, why = net.snap_jpeg()
                        return self.send(200, jpg, 'image/jpeg') if jpg else self.send(409, why)
                    if u.path == '/net/cmd':
                        code, text = net.take(q, ip)
                        return self.send(code, text)
                except Exception as e:  # noqa: BLE001 - never into the server
                    return self.send(500, 'failed (%s)' % e.__class__.__name__)
                return self.send(404, 'no such thing')
        return Handler

    # ------------------------------------------------------------------ its thread
    def _set(self, state, why):
        if (state, why) != (self.state, self.why):
            self.log('netmon: %s%s' % (state, ' - ' + why if why else ''))
        self.state, self.why = state, why

    def _close(self):
        for s in (self.udp,):
            try:
                s and s.close()
            except OSError:
                pass
        if self.server is not None:
            threading.Thread(target=self.server.shutdown, daemon=True).start()
            try:
                self.server.server_close()
            except OSError:
                pass
        self.udp, self.server, self.bound = None, None, None

    def _open(self, port):
        self._close()
        try:
            u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            u.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            if hasattr(socket, 'SO_EXCLUSIVEADDRUSE'):
                u.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            u.bind((BIND, port))
            u.settimeout(0.5)
            srv = NetServer((BIND, port), self._handler())
        except OSError as e:
            try:
                u.close()
            except (OSError, UnboundLocalError):
                pass
            self._set('error', 'port %d is in use or blocked (%s) - another program, or a second bot on this PC?' % (port, e.__class__.__name__))
            return False
        threading.Thread(target=srv.serve_forever, name='netmon-http', daemon=True).start()
        self.udp, self.server, self.bound = u, srv, port
        self._set('on', 'port %d - Windows may ask once to let Python through its firewall: allow it on Private networks' % port)
        return True

    def _broadcasts(self):
        """where a beacon goes: everyone on this network, and each of this PC's own /24 networks"""
        out = {'255.255.255.255'}
        try:
            for a in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
                ip = a[4][0]
                if private(ip) and not ip.startswith('127.'):
                    out.add(ip.rsplit('.', 1)[0] + '.255')
        except OSError:
            pass
        return out

    def _beacon(self, port):
        with self.lock:
            me = {k: v for k, v in self.me.items() if k not in ('status', 'last')}
        msg = json.dumps({'wm': 1, 'id': self.id, 'port': port, **me}, separators=(',', ':')).encode()[:1400]
        for b in self._broadcasts():
            try:
                self.udp.sendto(msg, (b, port))
            except OSError:
                pass

    def _heard(self, data, ip):
        try:
            self._heard_one(data, ip)
        except Exception:  # noqa: BLE001 - a malformed beacon (too deep, a huge number...) is just dropped
            pass

    def _heard_one(self, data, ip):
        if not private(ip):
            return
        try:
            d = json.loads(data.decode('utf-8'))
        except (ValueError, UnicodeDecodeError):
            return
        if not isinstance(d, dict) or d.get('wm') != 1 or not re.match(r'^[0-9a-f]{16}$', str(d.get('id'))) or d['id'] == self.id:
            return
        s = clean_state(d)
        port = int(_num(d.get('port'), 1024, 65535) or PORT)
        if not s['pc']:
            return
        said = None
        with self.lock:
            now = time.monotonic()
            old = self.peers.get(s['pc'])
            if old is not None and old['id'] != d['id'] and old['ip'] != ip and now - old['at'] <= STALE:
                # (a second bot calling itself a PC that's heard from elsewhere right now: not taken over - commands
                # and the PIN-signed ones above all would go to it. A bot started again keeps its address; one that
                # moved is taken once the old address has gone quiet)
                said = ('spoof ' + s['pc'], 'netmon: a beacon from %s says it is %s - heard at %s just now: not taken'
                        % (ip, s['pc'], old['ip']))
            elif old is None and len(self.peers) >= MAX_PEERS:
                for name in [n for n, p in self.peers.items() if now - p['at'] > STALE]:
                    del self.peers[name]
                if len(self.peers) >= MAX_PEERS:
                    said = ('full', 'netmon: %d bots heard already - %s (%s) not kept' % (MAX_PEERS, s['pc'], ip))
            if said is None:
                s.update(id=d['id'], ip=ip, port=port, at=now)
                self.peers[s['pc']] = s
        if said is not None:
            self._say_once(*said)

    def _loop(self):
        while True:
            with self.lock:
                on, port = self.cfg['on'], self.cfg['port']
            if not on:
                if self.bound is not None:
                    self._close()
                self._set('off', 'Settings: neton')
                time.sleep(1.0)
                continue
            if self.bound != port and not self._open(port):
                time.sleep(10.0)
                continue
            now = time.monotonic()
            if now >= self.next_beacon:
                self.next_beacon = now + BEACON
                self._beacon(port)
            try:
                data, addr = self.udp.recvfrom(2048)
                self._heard(data, addr[0])
            except socket.timeout:
                pass
            except OSError:
                time.sleep(0.2)

    def stop(self):
        with self.lock:
            self.cfg['on'] = False
        self._close()
