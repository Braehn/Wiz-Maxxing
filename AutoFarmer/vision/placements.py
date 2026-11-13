"""placements - READ-ONLY: the things a zone's file places (its gamedata.bin) and what the game calls each one - for the
vision helper's /items?far=1 (the quest's things the game's memory doesn't hold: it holds only what's within ~6.7k of the
wizard - 2026-10-25 "Use Inactive Protector in District of the Stars (0 of 3)": the nearest protector 10.8k away, none in
memory, and the bot stood there for hours) and /seller (where the potion sellers stand).

    rows = zone_placements(zone)    every object the zone's .wad places: [{name ("CL-DownedProtectors instance (3)"),
                                    template (its own name, by the template id it carries through Root.wad's
                                    TemplateManifest.xml - else the name's part before " instance"), n (the "(n)": 0 none,
                                    None not an instance name), instance, tid, file, pos (x, y, z), yaw, state ("Slumped"),
                                    at (where its record is in the file)}] - kept per zone; None when the file can't be read
    info = template_info(tpl)       a template's (its name, its file or its id) display key (m_displayName - the key a
                                    live object's template holds at +0xA8), interact title key, object name, id - None
                                    when it isn't in the files
    t = template_names(tpl)         ...with each key's English text ("CL-DownedProtectors" -> WizQst371C7_00000008 =
                                    "Inactive Protector") - kept per template
    rows = zone_things(zone)        zone_placements with what each is called: key (its display key, else its title key),
                                    text, keys (both), names, kind (item / object / npc / ambient - navmem.thing_kind).
                                    Builds what it needs: call it off the request threads (the worker does)
    rows = built_things(zone)       zone_things as the worker built it - None while it isn't (never built here: the worker
                                    is asked to); want_zone(zone) asks for it (the helper's /nav, at each zone change)
    warm()                          Root.wad's file table and the template manifest built in the worker (the helper's
                                    start)
    lang(), text(key), want_names(keys)   the name tables for zone objects' names (navmem's objects thread too): one
                                    persistent set (not questmem's, whose 60-table limit would drop the goal's tables),
                                    read in the worker
    busy(on)                        a memory read starts / ends (the helper's /nav, /mobs, /goal...): the worker waits for
                                    it between its steps

THE FILES (open(..., "rb") only - never written):
  <zone>.wad gamedata.bin  ObjectProperty records, each property u32 size in bits, u32 hash, its value. A placement:
      af a9 c8 25  u64 template id            (28 bytes before the location's hash - 44 since the 2026-11-12
                                              patch, which put a new u64 property, fe d9 63 5f, in between: TID_BACK)
      1b dc 7e 85  x, y, z (floats)           the location (k)
      8e 7f b7 8b  pitch, roll, yaw (floats)  k + 20
      a5 45 fd 1d  scale (float)              k + 40
      f3 03 fa ca  u16 length, the name       k + 52 (the letters at k + 58: all 23,233 named records of 2,268 zones)
      ca f8 27 81  u16 length, the state      right after the name
  Root.wad TemplateManifest.xml  BINd, flags 0x0f (byte 8 = 1, u32 size, a zlib stream): TemplateLocation records -
      bc 90 ce b9 the file (a length byte = 2 x letters), then 3a 8f 35 89 its u32 template id. A file
      "|<World>|WorldData|<path>" is in GameData\\<World>-WorldData.wad (253 placed templates: Darkmoor's lenses...)
  ObjectData/.../<template>.xml  BINd: strings are a length byte (2 x letters) after the property's hash -
      m_objectName (f3 c6 71 80), m_templateID (f6 32 b2 4c, u32), m_displayName (92 bc d8 91), the interact title
      (b7 d4 39 71, after the GUI_ prompt). The template's own m_displayName is the first one after its own
      m_objectName (a nested quest offer's - QuestTitle_* - comes before it: WC-RAV-NPC09 isn't 'Bugging out!');
      a template with none carries its name in the interact title only (AQ Tapestry, KT-SE-MARK-Cast_List_01)

THREADS. One worker thread (made when there's work, gone after a minute of none) does every build: the requests only
read what it built. The builds are pure Python (the GIL): a cold build in another thread pushed a live /nav read past
its 150 ms timeout (156-211 ms, measured 2026-10-25) - each ReadProcessMemory call hands the GIL back and waits for it
again - so the worker waits at each step (every few ms of work) while a memory read is in flight (busy). Builds run
under one lock (double-checked), so threads asking at once wait for one build instead of each making its own.
"""
import collections
import os
import re
import struct
import threading
import time
import zlib

import navgeo
import navmem

# the properties' hashes as the files hold them (little-endian u32)
H_TID, H_LOC, H_ORI, H_SCALE, H_NAME, H_STATE = (bytes.fromhex(h) for h in (
    "afa9c825", "1bdc7e85", "8e7fb78b", "a545fd1d", "f303faca", "caf82781"))
# (the template id's hash this far before the location's, nearest first - 4-byte steps, each a whole property: 28 before
# the 2026-11-12 patch, 44 after it; right before the hash a u64 property's size - 128 bits: its size, hash and value -
# so a property the game adds in between later is stepped over too, never another record's id: the record before ends
# with its name and state)
TID_BACK = tuple(range(28, 77, 4))
U64_PROP = struct.pack("<I", 128)
H_FILE, H_ID = bytes.fromhex("bc90ceb9"), bytes.fromhex("3a8f3589")          # TemplateManifest's TemplateLocation
H_OBJNAME, H_TPLID, H_DISPLAY, H_TITLE = (bytes.fromhex(h) for h in ("f3c67180", "f632b24c", "92bcd891", "b7d43971"))
INST = re.compile(r"^(.+?) instance(?: \((\d+)\))?$")
# a name-table key as a template holds it: "<table>_<digits>" ("WizQst371C7_00000008", "WizardGameObjects_00000375",
# "NPCs_01747525", "WC-NPCs_00000014") - not "OT_UNDEFINED", "ROP_AND", "CL-DIST-NPC03_Persona"; the display name's own
# property any questmem.KEY-like text
KEY = re.compile(r"^[A-Za-z][A-Za-z0-9-]*_\d+$")
ANYKEY = re.compile(r"^[A-Za-z][A-Za-z0-9-]*_\S+$")
NOT_NAMES = ("GUI_",)          # GUI_ keys are prompts ("Press ... to Interact"), never a thing's name
ROOT_KEEP = (b"objectdata/", b"locale/en-us/", b"templatemanifest.xml")     # Root.wad's entries kept (of 173,000)
ZONES_KEPT = 16                # zones' placements and things kept
GATE_MAX = 0.25                # s the worker waits at one step for the memory reads in flight
WORKER_IDLE = 60.0             # s the worker waits for work before it ends
RETRY = 30.0                   # s before a zone whose names or file couldn't all be read is built again
FILE_ERRORS = (OSError, ValueError, struct.error, zlib.error, IndexError)


def _say(msg):
    try:
        LOG[0](msg)
    except Exception:  # noqa: BLE001 - never into the caller
        pass


LOG = [lambda m: None]


def set_log(fn):
    LOG[0] = fn or (lambda m: None)


def _gd(game_dir):
    """the game's folder as a cache key ('' = navgeo.GAME_DIR: the same folder by either name is one key)"""
    return os.path.normcase(os.path.abspath(game_dir or navgeo.GAME_DIR))


def _finite(*v):
    return all(v_ == v_ and abs(v_) < 1e7 for v_ in v)


# ============================================================================ the worker's steps wait for memory reads
_LOCAL = threading.local()
_IDLE = threading.Event()
_IDLE.set()
_BUSY = [0]
_BUSY_LOCK = threading.Lock()
_BUILD = threading.RLock()     # every build (Root.wad's table, the manifest, the index, a zone, a template, names)
STATS = collections.Counter()  # gate_waits, gate_ms, builds - for the log and the tests


def busy(on):
    """a memory read (a /nav...) starts (on True) or ends: the worker waits at its next step till none is in flight"""
    with _BUSY_LOCK:
        _BUSY[0] = max(0, _BUSY[0] + (1 if on else -1))
        if _BUSY[0]:
            _IDLE.clear()
        else:
            _IDLE.set()


def _gate():
    """a step of a build: in the worker, waits (GATE_MAX s at most) while a memory read is in flight; else nothing"""
    if _IDLE.is_set() or not getattr(_LOCAL, "worker", False):
        return
    t0 = time.perf_counter()
    _IDLE.wait(GATE_MAX)
    STATS["gate_waits"] += 1
    STATS["gate_ms"] += (time.perf_counter() - t0) * 1000


# ============================================================================ .wad archives
class Wad:
    """a KIWAD archive read-only: its file table (read once - again when the file changes), entries kept by their lower
    case names (only those starting with keep's prefixes when given), and its files"""

    def __init__(self, path, keep=None):
        self.path, self.keep = path, keep
        self.stamp, self.files = None, {}
        self.stats = {}

    def _stamp(self):
        st = os.stat(self.path)
        return (st.st_size, st.st_mtime_ns)

    def table(self):
        """{lower case name: (offset, size, compressed size, compressed)} - raises OSError / ValueError"""
        stamp = self._stamp()
        if stamp == self.stamp:
            return self.files
        with _BUILD:
            if stamp != self.stamp:
                t0 = time.perf_counter()
                files = self._read_table()
                self.files, self.stamp = files, stamp
                self.stats.update(table_s=round(time.perf_counter() - t0, 3), files=len(files))
                self.changed()
        return self.files

    def changed(self):
        pass

    def _read_table(self):
        keep = self.keep
        files = {}
        with open(self.path, "rb") as f:
            head = f.read(14)
            if head[:5] != b"KIWAD":
                raise ValueError("%s isn't a KIWAD archive" % os.path.basename(self.path))
            version, count = struct.unpack_from("<II", head, 5)
            f.seek(13 + (1 if version >= 2 else 0))
            buf, p = f.read(1 << 20), 0
            for i in range(count):
                if not i & 1023:
                    _gate()
                if p + 21 > len(buf):
                    buf, p = buf[p:] + f.read(1 << 20), 0
                    if p + 21 > len(buf):
                        raise ValueError("%s's file table runs past its end" % os.path.basename(self.path))
                off, size, csize, comp, _crc, nlen = struct.unpack_from("<IIIBII", buf, p)
                e = p + 21 + nlen
                if e > len(buf):
                    buf, p = buf[p:] + f.read(max(1 << 20, nlen + 21)), 0
                    e = 21 + nlen
                    if e > len(buf):
                        raise ValueError("%s's file table runs past its end" % os.path.basename(self.path))
                low = buf[p + 21:e].rstrip(b"\0").lower()
                p = e
                if keep is None or low.startswith(keep):
                    files[low.decode("utf-8", "replace")] = (off, size, csize, comp)
        return files

    def read(self, name):
        """the file's bytes (decompressed), None when it isn't there or isn't downloaded yet - raises OSError /
        ValueError / zlib.error"""
        hit = self.table().get(name.lower())
        if hit is None:
            return None
        off, size, csize, comp = hit
        with open(self.path, "rb") as f:
            f.seek(off)
            raw = f.read(csize if comp else size)
        if not raw.strip(b"\0"):
            return None                                 # (not downloaded yet)
        data = zlib.decompress(raw) if comp else raw
        if len(data) != size:
            raise ValueError("%s in %s is %d bytes, its table says %d" % (name, os.path.basename(self.path), len(data), size))
        return data


class RootWad(Wad):
    """Root.wad: its ObjectData templates, Locale name tables and TemplateManifest.xml - the manifest {template id: file}
    and an index {template name (the file's base name, lower case): [files]}, each built once (again when Root.wad
    changes: a patch). A manifest file "|<World>|WorldData|<path>" is read from GameData\\<World>-WorldData.wad"""

    def __init__(self, path):
        super().__init__(path, ROOT_KEEP)
        self._manifest, self._base, self.worlds = None, None, {}

    def changed(self):
        self._manifest, self._base = None, None

    def read(self, name):
        if name.startswith("|"):
            parts = name.split("|", 3)
            if len(parts) < 4:
                return None
            w = os.path.join(os.path.dirname(self.path), "%s-%s.wad" % (parts[1], parts[2]))
            with _BUILD:
                wad = self.worlds.get(w)
                if wad is None:
                    wad = self.worlds[w] = Wad(w)
            try:
                return wad.read(parts[3])
            except FILE_ERRORS:
                return None                             # (that world's file missing or damaged: this template only)
        return Wad.read(self, name)

    def manifest(self):
        """{template id: its file} from TemplateManifest.xml (137,423 of them; built once, ~0.16 s)"""
        self.table()
        if self._manifest is not None:
            return self._manifest
        with _BUILD:
            if self._manifest is None:
                t0 = time.perf_counter()
                u = bind_body(self.read("TemplateManifest.xml")) or b""
                out, n = {}, 0
                i = u.find(H_FILE)
                while i >= 0:
                    if not n & 1023:
                        _gate()
                    n += 1
                    p = i + 4
                    if p < len(u):
                        k, p = (u[p] >> 1, p + 1) if not u[p] & 1 else (struct.unpack_from("<I", u, p)[0] >> 1, p + 4)
                        j = p + k
                        if 0 < k < 400 and u[j + 4:j + 8] == H_ID:
                            out[struct.unpack_from("<I", u, j + 8)[0]] = u[p:j].decode("utf-8", "replace")
                    i = u.find(H_FILE, i + 4)
                self._manifest = out
                self.stats.update(manifest_s=round(time.perf_counter() - t0, 3), manifest=len(out))
        return self._manifest

    def by_base(self, tname):
        """the ObjectData files named tname ("CL-DownedProtectors" -> objectdata/cl/cl-downedprotectors.xml), lower case"""
        files = self.table()
        if self._base is None:
            with _BUILD:
                if self._base is None:
                    t0 = time.perf_counter()
                    base = {}
                    for i, n in enumerate(files):
                        if not i & 2047:
                            _gate()
                        if n.startswith("objectdata/") and n.endswith(".xml"):
                            base.setdefault(n[n.rfind("/") + 1:-4], []).append(n)
                    self._base = base
                    self.stats.update(base_s=round(time.perf_counter() - t0, 3), base=len(base))
        return list(self._base.get((tname or "").lower(), ()))


ROOT = {}


def root_wad(game_dir=""):
    k = _gd(game_dir)
    with _BUILD:
        r = ROOT.get(k)
        if r is None:
            r = ROOT[k] = RootWad(os.path.join(game_dir or navgeo.GAME_DIR, "Data", "GameData", "Root.wad"))
        return r


def bind_body(d):
    """a BINd file's property bytes: flags 0x08 = compressed (a byte 1, u32 size, a zlib stream)"""
    if d is None or d[:4] != b"BINd":
        return d
    flags = struct.unpack_from("<I", d, 4)[0]
    if flags & 8:
        if d[8] == 1:
            return zlib.decompress(d[13:])
        return d[9:]
    return d[8:]


# ============================================================================ placements
PLACED = collections.OrderedDict()      # (zone, game folder) -> (its .wad's stamp, [placements])


def _string(b, p):
    """(text, end) of a u16-length string at p, or (None, p)"""
    if p + 2 > len(b):
        return None, p
    n = struct.unpack_from("<H", b, p)[0]
    s = b[p + 2:p + 2 + n]
    if len(s) != n:
        return None, p
    try:
        t = s.decode("utf-8")
    except UnicodeDecodeError:
        return None, p
    return (t if all(31 < ord(c) or c == "\t" for c in t) else None), p + 2 + n


def tid_at(b, k):
    """Where the template id's hash is before the location's at k (TID_BACK: 28 bytes before it in the files before
    the 2026-11-12 patch, 44 after), its u64 right after it - -1 none"""
    for back in TID_BACK:
        j = k - back
        if j < 4:
            break
        if b[j:j + 4] == H_TID and b[j - 4:j] == U64_PROP:
            return j
    return -1


def parse_placements(b):
    """[{name, tid, pos, yaw, state, at}] of every record in a gamedata.bin with a location, a template id a little before
    it (tid_at) and a name property 52 bytes after it (the layout at the top)"""
    out, n = [], 0
    k = b.find(H_LOC)
    while k >= 0:
        n += 1
        if not n & 127:
            _gate()
        t = tid_at(b, k)
        if (t >= 0 and k + 58 <= len(b) and b[k + 20:k + 24] == H_ORI
                and b[k + 52:k + 56] == H_NAME):
            x, y, z = struct.unpack_from("<3f", b, k + 4)
            _p, _r, yaw = struct.unpack_from("<3f", b, k + 24)
            name, end = _string(b, k + 56)
            if name is not None and _finite(x, y, z):
                tid = struct.unpack_from("<Q", b, t + 4)[0]
                state = None
                if b[end + 4:end + 8] == H_STATE:
                    state, _ = _string(b, end + 8)
                out.append({"name": name, "tid": tid, "pos": (x, y, z), "yaw": yaw if _finite(yaw) else None,
                            "state": state or "", "at": k})
        k = b.find(H_LOC, k + 4)
    return out


def _zone_stamp(zone, game_dir):
    st = os.stat(navgeo.wad_path(zone, game_dir or navgeo.GAME_DIR))
    return (st.st_size, st.st_mtime_ns)


def zone_placements(zone, game_dir="", instances_only=False):
    """[{name, template, n, instance, tid, file, pos, yaw, state, at}] of every object the zone's .wad places - see the top
    (kept per zone and .wad); None when the file can't be read (a zone with no .wad, a damaged one); [] when it has no
    gamedata.bin. instances_only: only the "<template> instance[ (n)]" ones"""
    if not zone:
        return None
    path = navgeo.wad_path(zone, game_dir or navgeo.GAME_DIR)
    try:
        st = os.stat(path)
    except OSError:
        return None
    stamp = (st.st_size, st.st_mtime_ns)
    k = (zone, _gd(game_dir))
    got = PLACED.get(k)
    if got is None or got[0] != stamp:
        with _BUILD:
            got = PLACED.get(k)
            if got is None or got[0] != stamp:
                try:
                    # (navgeo.read_wad_files' reading, its file table's loop stepping through the gate)
                    b = Wad(path).read("gamedata.bin")
                except FILE_ERRORS as e:
                    _say("placements: %s can't be read (%r)" % (zone, e))
                    return None
                _gate()
                rows = parse_placements(b or b"")
                try:
                    man = root_wad(game_dir).manifest()
                except FILE_ERRORS as e:
                    _say("placements: Root.wad's template manifest can't be read (%r)" % (e,))
                    man = None
                for r in rows:
                    m = INST.match(r["name"])
                    r["instance"] = bool(m)
                    r["n"] = (int(m.group(2)) if m.group(2) else 0) if m else None
                    f = (man or {}).get(r["tid"])
                    r["file"] = f or ""
                    base = f[f.rfind("/") + 1:] if f else ""
                    r["template"] = base[:-4] if base.lower().endswith(".xml") else (m.group(1) if m else "")
                if man is None:
                    # (not kept: the templates by their instance names only - asked again next time)
                    return [dict(r) for r in rows if r["instance"] or not instances_only]
                got = PLACED[k] = (stamp, rows)
                PLACED.move_to_end(k)
                while len(PLACED) > ZONES_KEPT:
                    PLACED.popitem(last=False)
    return [dict(r) for r in got[1] if r["instance"] or not instances_only]


# ============================================================================ templates and their names
TEMPLATES = {}                  # (template - name, file or id -, game folder) -> its record, False when it isn't there


def bind_strings(u):
    """[(offset, hash, text)] of a BINd body's byte-length strings (a length byte 2 x letters after a 4-byte hash) - only
    the printable ones of 2 letters or more"""
    out = []
    for n, m in enumerate(re.finditer(rb"[ -~]{2,}", u)):
        if not n & 511:
            _gate()
        for st in range(m.start(), m.end() - 1):
            if st < 5:
                continue
            L = u[st - 1]
            if L & 1 or L < 4 or st + (L >> 1) > m.end():
                continue
            out.append((st, u[st - 5:st - 1], u[st:st + (L >> 1)].decode("latin-1")))
            break                                       # (the first that fits: a hash's printable bytes come before)
    return out


def template_info(tpl, game_dir=""):
    """{file, object_name, template_id, display, title, keys [(hash hex, key)]} of a template - tpl its name, its file or
    its id - None when it isn't in the files. display: its own m_displayName (the first after its own m_objectName; ""
    none - a Basic Positional, a duel circle); title: its interact title key (not a GUI_ prompt); keys: every
    "<table>_<digits>" key it holds. Raises OSError / ValueError when Root.wad can't be read"""
    rw = root_wad(game_dir)
    if isinstance(tpl, int):
        f = rw.manifest().get(tpl)
        files = [f] if f else []
    elif "/" in tpl or "|" in tpl:
        files = [tpl]
    else:
        # (a mob's or an NPC's house-guest copy shares its name: the one outside Housing first)
        files = sorted(rw.by_base(tpl), key=lambda n: ("/housing/" in n.lower(), len(n)))
    by_name = isinstance(tpl, str) and "/" not in tpl and "|" not in tpl
    for f in files:
        try:
            u = bind_body(rw.read(f))
        except (zlib.error, struct.error, IndexError):
            u = None                                    # (a damaged file: not this one)
        if not u:
            continue
        strs = bind_strings(u)
        base = f[f.rfind("/") + 1:]
        base = base[:-4] if base.lower().endswith(".xml") else base
        want = (tpl if by_name else base).lower()
        ons = [(at, s) for at, h, s in strs if h == H_OBJNAME]
        own_at = next((at for at, s in ons if s.lower() == want), ons[-1][0] if ons else -1)
        obj = next((s for at, s in ons if at == own_at), "")
        if by_name and obj and obj.lower() != want:
            continue                                    # (a file of that name for another template)
        keys = []
        for _at, h, s in strs:
            if KEY.match(s) and (h.hex(), s) not in keys:
                keys.append((h.hex(), s))
        info = {"file": f, "object_name": obj, "template_id": None, "keys": keys,
                "display": next((s for at, h, s in strs if h == H_DISPLAY and at > own_at and ANYKEY.match(s)), ""),
                "title": next((s for at, h, s in strs if h == H_TITLE and KEY.match(s) and not s.startswith(NOT_NAMES)),
                              "")}
        i = u.find(H_TPLID)
        if i >= 0 and i + 8 <= len(u):
            info["template_id"] = struct.unpack_from("<I", u, i + 4)[0]
        return info
    return None


def _template(tpl, game_dir=""):
    """template_info made into template_names' record (kept per template); None when it isn't in the files - or the
    files can't be read now (not kept then)"""
    ck = (tpl, _gd(game_dir))
    got = TEMPLATES.get(ck)
    if got is not None:
        return got or None
    with _BUILD:
        got = TEMPLATES.get(ck)
        if got is not None:
            return got or None
        _gate()
        try:
            info = template_info(tpl, game_dir)
        except FILE_ERRORS as e:
            _say("placements: template %r can't be read (%r)" % (tpl, e))
            return None
        rec = False
        if info is not None:
            keys = [k for k in (info["display"], info["title"]) if k]
            rec = {"template": info["object_name"] or (tpl if isinstance(tpl, str) and "/" not in tpl else ""),
                   "file": info["file"], "template_id": info["template_id"], "display": info["display"],
                   "title": info["title"], "key": keys[0] if keys else "", "keys": list(dict.fromkeys(keys)),
                   "names": {}, "name": "", "named": not keys}
        if len(TEMPLATES) > 30000:
            TEMPLATES.clear()
        TEMPLATES[ck] = rec
    return rec or None


def _fill_names(recs, game_dir=""):
    """every record's names from the name tables (the tables they need read once, in one go)"""
    want = [k for g in recs if g and not g["named"] for k in g["keys"]]
    if not want:
        return
    L = lang(game_dir)
    L.load(want, block=True)
    with _BUILD:
        for g in recs:
            if not g or g["named"]:
                continue
            for k in g["keys"]:
                t = L.text(k)
                if t is not None:
                    g["names"][k] = t
            g["name"] = g["names"].get(g["key"], "")
            # (done once every table it may be in has been read - one missing from Root.wad reads as empty: done too)
            with L.lock:
                g["named"] = all(t in L.tables for k in g["keys"] for t in L.candidates(k))


def template_names(tpl, game_dir=""):
    """{template, file, template_id, display, title, key, keys, name, names} of a template (its name, file or id): key its
    display key (the live object's template holds it at +0xA8), else its interact title's; name that key's English text
    ("" none, or its table not read); keys both (display first); names {key: text} - None when the template isn't in the
    files. Kept per template"""
    got = _template(tpl, game_dir)
    if got is None:
        return None
    _fill_names([got], game_dir)
    return dict(got, keys=list(got["keys"]), names=dict(got["names"]))


def zone_things(zone, game_dir="", instances_only=False):
    """zone_placements with what each is called: key (its template's display key, else its interact title key - "" none:
    not a thing /items offers), text (its English text), keys, names (both, and their texts), display, title, kind
    (navmem.thing_kind: item / object / npc / ambient, "" no key), named (every name table read); None as
    zone_placements. Builds what it needs (the templates, the name tables) - the worker's"""
    rows = zone_placements(zone, game_dir, instances_only)
    if rows is None:
        return None
    recs = {}
    for r in rows:
        t = r["tid"] if r["file"] else r["template"]
        if t not in recs and (r["file"] or r["template"]):
            recs[t] = _template(t, game_dir)
        r["_t"] = t
    _fill_names([g for g in recs.values() if g], game_dir)
    for r in rows:
        g = recs.get(r.pop("_t")) or {}
        r["display"], r["title"], r["key"] = g.get("display", ""), g.get("title", ""), g.get("key", "")
        r["text"] = g.get("name", "")
        r["keys"], r["names"] = list(g.get("keys", ())), dict(g.get("names", {}))
        r["kind"] = navmem.thing_kind(r["key"])
        r["named"] = g.get("named", True)
        if g.get("template"):
            r["template"] = g["template"]
    return rows


# ============================================================================ the name tables (one persistent set)
_LANG = {}
_LANG_CLS = []


MARKUP, SPACES = re.compile(r"<[^>]*>"), re.compile(r"\s+")


def parse_lang(data):
    """handmem.parse_lang's reading of a .lang name table ({key: text}: UTF-16, a heading line, then key, comment, text
    for each entry; a text's line breaks written as \\n, its markup taken out) - its loop stepping through the gate (Items
    .lang alone held the GIL 69 ms in one go)"""
    out = {}
    try:
        lines = data.decode("utf-16").split("\r\n")
    except (UnicodeDecodeError, AttributeError):
        return out
    for n, i in enumerate(range(1, len(lines) - 2, 3)):
        if not n & 1023:
            _gate()
        key = lines[i].strip()
        if key:
            out[key] = SPACES.sub(" ", MARKUP.sub("", lines[i + 2].replace("\\r", " ").replace("\\n", " "))).strip()
    return out


class _NoProc:
    """questmem.Lang wants the game's process only for its folder - the folder is given here"""

    @staticmethod
    def image_path():
        raise OSError("no process")


def _lang_class():
    """questmem.Lang reading its tables through RootWad (its file table read once) and parse_lang (the gate) - built on
    first use (questmem imports navmem: imported here, not at the top)"""
    if not _LANG_CLS:
        import questmem

        class PlaceLang(questmem.Lang):
            KEEP = 400              # (zone objects' tables are many and small: the 60 of questmem's would thrash)

            def __init__(self, game_dir):
                super().__init__(_NoProc(), _say)
                self.game_dir = game_dir
                self.root = root_wad(game_dir).path

            def _read(self, want):
                rw = root_wad(self.game_dir)
                got = {}
                try:
                    for t in want:
                        _gate()
                        data = rw.read("Locale/en-US/%s.lang" % t)
                        got[t] = parse_lang(data) if data else {}
                except Exception as e:  # noqa: BLE001 - tried again in 30 s
                    with self.lock:
                        self.fail_at = time.monotonic()
                    _say("placements: the name tables couldn't be read (%r)" % (e,))
                with self.lock:
                    if len(self.tables) + len(got) > self.KEEP:
                        self.tables = {t: v for t, v in self.tables.items() if t in questmem.PRELOAD}
                    self.tables.update(got)
        _LANG_CLS.append(PlaceLang)
    return _LANG_CLS[0]


def lang(game_dir=""):
    """the name tables for zone objects (a questmem.Lang - each table read once, kept)"""
    k = _gd(game_dir)
    l_ = _LANG.get(k)
    if l_ is None:
        cls = _lang_class()
        with _BUILD:
            l_ = _LANG.get(k)
            if l_ is None:
                l_ = _LANG[k] = cls(game_dir)
    return l_


def text(key, game_dir=""):
    """a key's English text if its table has been read, else None (want_names reads it in the worker)"""
    return lang(game_dir).text(key) if key else None


def want_names(keys, game_dir=""):
    """the tables these keys may be in read in the worker (those not read yet)"""
    L = lang(game_dir)
    with L.lock:
        have = set(L.tables)
    tables = sorted({t for k in keys for t in L.candidates(k)} - have)
    if tables:
        keys = list(keys)
        _submit(("names", _gd(game_dir)) + tuple(tables), lambda: L.load(keys, block=True))


# ============================================================================ the worker
_JOBS = collections.OrderedDict()
_JOBS_CV = threading.Condition()
_WORKER = [None]
_RUNNING = [None]


def _submit(key, fn):
    """fn queued for the worker (once: not again while it's queued or running); the worker made if there's none"""
    with _JOBS_CV:
        if key in _JOBS or key == _RUNNING[0]:
            return False
        _JOBS[key] = fn
        th = _WORKER[0]
        if th is None or not th.is_alive():
            th = _WORKER[0] = threading.Thread(target=_work, name="placements", daemon=True)
            th.start()
        _JOBS_CV.notify()
    return True


def _work():
    _LOCAL.worker = True
    while True:
        with _JOBS_CV:
            if not _JOBS:
                _JOBS_CV.wait(WORKER_IDLE)
                if not _JOBS:
                    _WORKER[0] = None
                    return
            key, fn = _JOBS.popitem(last=False)
            _RUNNING[0] = key
        try:
            fn()
        except Exception as e:  # noqa: BLE001 - the next job
            _say("placements: %s failed (%r)" % (key[0], e))
        finally:
            with _JOBS_CV:
                _RUNNING[0] = None


def idle(wait=0.0):
    """True when the worker has nothing queued or running (waited for up to wait s) - for the tests"""
    end = time.monotonic() + wait
    while True:
        with _JOBS_CV:
            if not _JOBS and _RUNNING[0] is None:
                return True
        if time.monotonic() >= end:
            return False
        time.sleep(0.02)


def warm(game_dir=""):
    """Root.wad's file table and the template manifest built in the worker (the helper's start: before the walker's
    first zone needs them - ~0.4 s of work once, its steps waiting for the memory reads; ~57 MB kept). The index by
    template name (another 22 MB) isn't: only a lookup by name needs it (a placement whose template id the manifest
    lacks - none of 2,268 zones has one), and it's built then"""
    def run():
        t0 = time.perf_counter()
        rw = root_wad(game_dir)
        try:
            rw.manifest()
        except FILE_ERRORS as e:
            _say("placements: Root.wad couldn't be read (%r)" % (e,))
            return
        STATS["builds"] += 1
        _say("placements: Root.wad's templates read in %.0f ms (%s; waited %d times for memory reads, %.0f ms)" % (
            (time.perf_counter() - t0) * 1000, ", ".join("%s %s" % kv for kv in sorted(rw.stats.items())),
            STATS["gate_waits"], STATS["gate_ms"]))
    _submit(("warm", _gd(game_dir)), run)


THINGS = collections.OrderedDict()      # (zone, game folder) -> {stamp, rows (None: no file), at, complete}
_WANTED = [None]


def _build_zone(zone, game_dir):
    t0 = time.perf_counter()
    k = (zone, _gd(game_dir))
    try:
        stamp = _zone_stamp(zone, game_dir)
    except OSError:
        stamp = None
    rows = zone_things(zone, game_dir) if stamp is not None else None
    complete = rows is not None and all(r["named"] for r in rows)
    with _BUILD:
        THINGS[k] = {"stamp": stamp, "rows": rows, "at": time.monotonic(), "complete": complete}
        THINGS.move_to_end(k)
        while len(THINGS) > ZONES_KEPT:
            THINGS.popitem(last=False)
    STATS["builds"] += 1
    if rows is None:
        _say("placements: %s - no zone file to read" % zone)
    else:
        _say("placements: %s - %d placed, %d with a name, in %.0f ms%s" % (
            zone, len(rows), sum(1 for r in rows if r["key"]), (time.perf_counter() - t0) * 1000,
            "" if complete else " (a name table not read: again in %.0f s)" % RETRY))


def want_zone(zone, game_dir="", again=False):
    """zone's things built in the worker unless they are (cheap: called at every /nav; again: whatever the last zone
    asked for was)"""
    if not zone:
        return
    k = (zone, _gd(game_dir))
    if not again:
        if _WANTED[0] == k:
            return
        _WANTED[0] = k
        if k in THINGS:
            return
    _submit(("zone",) + k, lambda: _build_zone(zone, game_dir))


def built_things(zone, game_dir=""):
    """the zone's things as the worker built them (zone_things' rows, copies) - None while they aren't built (the worker
    asked to: never built here), or when the zone has no file"""
    if not zone:
        return None
    k = (zone, _gd(game_dir))
    got = THINGS.get(k)
    fresh = False
    if got is not None:
        try:
            stamp = _zone_stamp(zone, game_dir)
        except OSError:
            stamp = None
        fresh = stamp == got["stamp"] and (got["complete"] or time.monotonic() - got["at"] < RETRY)
    if not fresh:
        want_zone(zone, game_dir, again=True)
    if got is None or got["rows"] is None:
        return None
    return [dict(r) for r in got["rows"]]
