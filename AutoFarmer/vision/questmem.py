"""questmem - READ-ONLY reader of the quest's active goal in a running Wizard101 client (WizardGraphicalClient.exe): the
goal line as the game shows it under the quest arrow ("Defeat Crustacean Waverunner and Collect Foul Tasting Algae in The
Grotto (0 of 3)"), its kind, status and count, and the mob / item / NPC it names - for the vision helper's /goal, and the
line its /nav, /mobs and /items match the zone's mobs and items against (instead of the OCR of the screen, which slips
letters: 2026-10-24 "Opiio (jn -rhe" for "Defeat Optio Agenor ...", and the quest's own mob was kept away from).

    qm = QuestMem(st, log=print)        # st: navmem's attached game (navmem._Attached); about a second, once per game
    snap = qm.snapshot((quest, goal))   # the memory reads - under navmem's lock (the ids: the quest helper thread's,
                                        # navmem's quest / goalid, standing in for the HUD's own)
    g = qm.resolve(snap)                # the names looked up (Root.wad's name tables - outside the lock), the line built

    g, why = navmem.NavMem().goal()     # the same through navmem's own attached game and lock (vision.py's way)

    ids, why = qm.quest_ids()           # EVERY quest in the quest manager's map [(GID, WizQuestData)] - under the lock,
    raw = qm.quest_raw(qid, q)          # each one's keys, goals and properties - under the lock (one quest at a time),
    rows = qm.quests_resolve([raw...], tracked=qid)   # the names looked up - outside it (navmem.NavMem.quests, /quests)
    print("\n".join(quest_lines(rows)))   # one line a quest, one a goal

    python questmem.py [-n 3] [-i 2] [--all]     readings from the command line (and how long each took); --all: every
                                                 quest too, as /quests answers

SAFETY. The game is opened by navmem.py's Proc - PROCESS_VM_READ | PROCESS_QUERY_INFORMATION (falling back to
PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION) and nothing else - and only read: ReadProcessMemory, plus the module /
toolhelp enumeration navmem.py uses to find it. Nothing is ever written, allocated, injected, hooked, suspended or
debugged; no window is touched (not even asked about - only the command line picks the game in front) and no input is
sent. Every class and property offset is found by NAME in a copy of the game's code read with ReadProcessMemory (its own
reflection registration: handmem.py's Image / class_props); every object is checked by its type name or window name
before it's used; the three places that aren't reflected (the quest manager's map, a quest's goal map, the HUD's ids) are
found by their shape and checked by key == id at every read.

FAILS SOFT. snapshot() and resolve() never raise: whatever goes wrong comes back as why, and a value that can't be read
for sure is None ("" for a name) - never a guess. The constructor raises (LookupError: a reflected class or property
isn't in this build) - NavMem.goal() catches that and answers (None, why).

WHAT IS READ (build QUEST_BUILD, 2026-10-24 - the offsets are found by name each attach; the numbers are what they were):

  the line   [exe + WizardGUIManager static] (navmem's gm) +0x2D0 the HUD (window name "windowHUD") -> +0x6A8
             QuestHelperHud (navmem's hud_qhh, window name "QuestHelperHud") -> its children (Window.m_Children +0x70:
             a vector of SharedPointer<Window>, 16 bytes each), 6 levels at most, down to the window named
             "txtGoalName" (type ControlText; its sibling "txtDistance" holds the arrow's number) -> ControlText.m_sText
             +0x2C8 (std::wstring "<center>Defeat ... (0 of 3)</center>" - its markup taken out)
             on screen: bit 0 of Window.m_Flags (+0x9C) of it and of every window above it up to the HUD (a battle
             hides the ElementWindow - the text stays; a loading screen or a dialogue drawn over it still reads shown)
  its ids    QuestHelperHud +0x2D8 quest GID, +0x2E0 goal GID: the ones it sets txtGoalName from - ahead of the quest
             helper thread's +0xC88 / +0xC90 by up to a second at a goal change. Not reflected: checked at every read
             (the quest in the manager's map, the goal in its goals); in another build looked for in +0x200..+0x800.
             The thread's ids stand in when they fail; a goal reading COMPLETE is the quest moving on (the other ids'
             goal is taken when it isn't)
  the data   [exe + rva 0x3336E80] the quest manager (not reflected; in another build found by its shape: a .data
             pointer to an object holding the map below) +0x80 std::map<u64 quest GID, SharedPointer<WizQuestData>>
             (head, size; node +0 left, +8 parent, +0x10 right, +0x19 isnil, +0x20 key, +0x28 the object) - checked:
             the values are WizQuestData whose m_id is the key (+0x90 holds the same quests by another key)
             WizQuestData: m_id, m_title (QuestTitle_...); +0xB0 std::map<u64 goal GID, SharedPointer<WizGoalData>> (not
             a reflected property - m_goalList is an empty list: found by shape, the map whose values are WizGoalData
             with m_goalID = key, then kept); for /quests, EVERY other reflected property of its own whose type is one
             of KIND_REF's (int, unsigned int, bool, float, std::string, std::wstring, a gid - told by its property adder,
             as a madlib argument's) - none named here: what tells a spell quest apart isn't known yet, so all of them
             are read and shown (QUEST_PROPS_CAP at most, by offset)
             WizGoalData: m_goalID, m_name (WizardQuestGoals_Kill ...), m_status (GOAL_STATUS_*), m_type
             (GoalTemplate::GOAL_TYPE_*), m_location (ZoneLocName_...), m_madLibs -> MadlibBlock
             MadlibBlock.m_madlibs: std::list<SharedPointer<MadlibArg>> (head, size; node +0 next, +0x10 the arg)
             MadlibArg.m_madlibToken: NAME, LOCATION, TALLYTEXT (an item or object), TALLYTEXT2 (a mob), COUNT, TOTAL,
             FIRSTNAME, LASTNAME ...; MadlibArgT<T>.m_madlibArgument: T told by the property adder that the function in
             its vtable's slot 3 calls to register it - the same adder as a known property's of that type
             (std::string Window.m_sName, std::wstring ControlText.m_sText, int SpellEffect.m_numRounds ...)
             (the quest helper thread keeps a copy of the quests at +0xC70 - without the madlibs: not used)
  enums      m_status / m_type option names: each name string is loaded in WizGoalData's registration code and its
             value stored just after (mov dword [rbp-50h], imm32) - checked by known values, else numbers only
  names      "<Table>_<key>" -> Root.wad Locale/en-US/<Table>.lang (handmem.parse_lang), each table read once
  the line   the game's own sentence for the goal's kind (Quest.lang: BountyChat, BountyCollectChat, UsageChat,
             ScavengeChat, PersonaChatFL / F / L; else "NAME TALLYTEXT in LOCATION") - its #n: and $GOAL_PREFIX$ left
             out, the place the part after "|" ("Celestia|The Grotto") - then " (COUNT of TOTAL)" when TOTAL > 1: the
             same as the HUD's own line for every goal seen live
"""
import os
import re
import struct
import sys
import threading
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import navmem as N                   # noqa: E402
import handmem as H                  # noqa: E402

# The build the places below were seen in (2026-10-24): there a place that fails is the object not being there now (the
# login screen); in another one it's looked for
QUEST_BUILD = "6A9721E9-370E000"
KNOWN = {"qm_rva": 0x3336E80, "qm_quests": 0x80, "quest_goals": 0xB0, "hud_ids": 0x2D8}
# reflected classes read at attach, and the properties that must be found in each
NEED = {"Window": ("m_sName", "m_Children", "m_Flags"),
        "ControlText": ("m_sText",),
        "WizQuestData": ("m_id", "m_title"),
        "WizGoalData": ("m_goalID", "m_name", "m_status", "m_type", "m_location", "m_madLibs"),
        "MadlibBlock": ("m_madlibs",),
        "MadlibArg": ("m_madlibToken",)}
# a known property of each madlib argument type: its adder (AddProperty<T>) names T in this build
KIND_REF = {"string": ("Window", "m_sName"), "wstring": ("ControlText", "m_sText"), "int": ("SpellEffect", "m_numRounds"),
            "uint": ("Spell", "m_templateID"), "float": ("Window", "m_fAlpha"), "gid": ("WizGoalData", "m_goalID"),
            "bool": ("ControlText", "m_bUseOutline")}
GET_TYPE_LIM = 0x200        # WizGoalData's GetType loads its name at +0x13F (handmem's limit is 0x80)
RESCAN_EVERY = 5.0          # s between looks for a place that failed (the known static, the HUD's ids)
SCAN_EVERY = 60.0           # ...and between looks through .data for the quest manager (another build only: in a thread,
                            # outside navmem's lock - 2, 4, 8, at most 16 times as long while it finds nothing)
# the game's sentence for a goal's kind (Quest.lang); any other kind: PLAIN
SENTENCE = {"BOUNTY": "BountyChat", "BOUNTYCOLLECT": "BountyCollectChat", "SCAVENGE": "ScavengeChat", "USAGE": "UsageChat"}
PLAIN = "$GOAL_NAME$ $GOAL_TALLYTEXT2$ $GOAL_TALLYTEXT$ in $GOAL_LOCATION$"
# a name-table key ("WizardMobs_00000720", "ZoneLocName_227109", "WC-NPCs_00000014"); anything else is words already
# (a talk goal's NAME is the wstring 'Talk To')
KEY = re.compile(r"^[A-Za-z][A-Za-z0-9-]*_\S.*$")
TABLE = re.compile(r"^[A-Za-z][A-Za-z0-9_-]*$")
PRELOAD = ("Quest", "WizardQuestGoals", "ZoneLocName", "WizardMobs", "WizItems", "QuestTitle")
QUESTS_CAP = 200            # quests read at most (/quests - a wizard holds a few dozen at most)
GOALS_CAP = 40              # goals of one quest read at most
QUEST_PROPS_CAP = 32        # WizQuestData's other properties read at most (by offset)
QUEST_SKIP = ("m_id", "m_title")    # (read already: not among its other properties)


# ============================================================================ reflection (handmem's, a longer prologue)
def get_types(img, name, lim=GET_TYPE_LIM):
    """handmem.Image.get_types with the name's LEA allowed up to lim bytes into GetType: [(GetType function, static
    Type** or None, [vtables])]"""
    import numpy as np
    out = []
    for sa in img.strings(name):
        for la in img.lea_at[img.lea_tgt == sa]:
            la = int(la)
            fn = img.func_start(la)
            if fn is None or la - fn > lim:
                continue
            code = img.code_at(la, 0x40)
            static = None
            k = code.find(b"\x48\x89\x05", 7)          # the first mov [rip+x], rax after the LEA: the cached Type*
            if 0 <= k < 0x30:
                static = la + k + 7 + struct.unpack_from("<i", code, k + 3)[0]
            entry = {fn} | {int(a) for a in img.jmp_at[img.jmp_tgt == fn]}
            r0 = img.secs[".rdata"][0]
            vts = sorted(r0 + int(qi) * 8 for e in entry for qi in np.flatnonzero(img.rdata_q == np.uint64(e)))
            out.append((fn, static, vts))
    return out


def class_props(img, name):
    """handmem.class_props with get_types' longer prologue: ({property: (offset, adder rva)}, GetType, [vtables])"""
    orig = img.get_types
    img.get_types = lambda n: get_types(img, n)
    try:
        return H.class_props(img, name)
    finally:
        img.get_types = orig


def read_enum_run(img, gt, first, prop):
    """{value: name} of an enum property whose option names (any identifier: GoalTemplate::GOAL_TYPE_UNKNOWN) run in
    .rdata from first, each followed by prop; each is loaded in the registration code after gt and its value stored
    just after - mov dword [rsp|rbp+d8], imm32, or a register kept at 0 (mov [rsp|rbp+d8], esi), the same slot d8 for
    every option (the most stored; WizGoalData's [rbp-50h] - its [rbp-4Ch] holds a bit, 1/2/4). {} when not read"""
    import numpy as np
    at0 = img.strings(first)
    if not at0 or gt is None:
        return {}
    r0, rdata = img.secs[".rdata"]
    i = at0[0] - r0
    names, prev = [], prop
    for mt in re.finditer(rb"([\x20-\x7e]+)\x00+", rdata[i:i + 0x2000]):
        s = mt.group(1).decode()
        if s != prop and not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_:]+", s):
            break
        if s == prop:
            prev = s
            continue
        if prev != prop or s.startswith("m_"):
            break                      # two names in a row / the next property's name: the run is over
        names.append((r0 + i + mt.start(), s))
        prev = s
    t0, text = img.secs[".text"]
    lo = gt - t0
    seg = np.frombuffer(text[lo:lo + 0x10000], dtype=np.uint8).astype(np.int64)
    d = seg[:-3] | (seg[1:-2] << 8) | (seg[2:-1] << 16) | (seg[3:] << 24)
    d = np.where(d >= 1 << 31, d - (1 << 32), d)
    tgt = np.arange(len(d)) + t0 + lo + 4 + d
    # (the register kept at 0: any 32-bit one - esi before; r15d in build 6AF1C8A0-3B69000, 2026-11-12, where the value slot
    # missed its 0 store lost the count to the bit slot: mov [rsp+d8] / [rbp+d8], r32 - 89 /r, REX 44 for r8d..r15d)
    store = re.compile(rb"\xC7\x44\x24(.)(....)|\xC7\x45(.)(....)|\x44?\x89[\x44\x4C\x54\x5C\x64\x6C\x74\x7C]\x24(.)"
                       rb"|\x44?\x89[\x45\x4D\x55\x5D\x65\x6D\x75\x7D](.)", re.DOTALL)
    seen = []
    for addr, s in names:
        hit = np.flatnonzero(tgt == addr)
        if not len(hit):
            continue
        k = int(hit[0]) + lo
        stores = []
        for m in store.finditer(text, k, k + 0x50):
            g = m.groups()
            if g[0] is not None:
                stores.append((("rsp", g[0][0]), struct.unpack("<i", g[1])[0]))
            elif g[2] is not None:
                stores.append((("rbp", g[2][0]), struct.unpack("<i", g[3])[0]))
            elif g[4] is not None:
                stores.append((("rsp", g[4][0]), 0))
            else:
                stores.append((("rbp", g[5][0]), 0))
        seen.append((s, stores))
    slots = Counter(slot for _, st_ in seen for slot in {sl for sl, _ in st_})
    if not slots:
        return {}
    top = max(slots.values())
    slot = min((sl for sl, c in slots.items() if c == top), key=lambda sl: (sl[0], sl[1] - 256 if sl[1] >= 128 else sl[1]))
    out = {}
    for s, st_ in seen:
        for sl, v in st_:
            if sl == slot:
                out.setdefault(v, s)
                break
    return out


def madlib_arg_kinds(img, st, P):
    """{vtable: (kind, offset)} of the MadlibArgT<T> classes: the function in vtable slot 3 registers m_madlibArgument
    (lea r8,[reg+OFFSET]; lea rdx,"m_madlibArgument"; call AddProperty<T>) - T named by the adder (KIND_REF)"""
    import numpy as np
    ref = {}
    for kind, (cls, prop) in KIND_REF.items():
        v = P.get(cls, {}).get(prop)
        if v and v[1] is not None:
            ref.setdefault(v[1], kind)
    out = {}
    base = st.m.base
    r0 = img.secs[".rdata"][0]
    for sa in img.strings("m_madlibArgument"):
        for la in img.lea_at[img.lea_tgt == sa]:
            la = int(la)
            code = img.code_at(la - 0x40, 0x80)
            if len(code) < 0x80 or code[0x40 + 1] != 0x8D or code[0x40 + 2] not in (0x15, 0x05):
                continue
            off = H._off_before(code, 0x40, 0 if code[0x42] == 0x15 else 1)
            k = code.find(b"\xE8", 0x47, 0x60)
            if off is None or k < 0:
                continue
            adder = la - 0x40 + k + 5 + struct.unpack_from("<i", code, k + 1)[0] - base
            fn = img.func_start(la)
            if fn is None:
                continue
            entry = {fn} | {int(a) for a in img.jmp_at[img.jmp_tgt == fn]}
            for e in entry:
                for qi in np.flatnonzero(img.rdata_q == np.uint64(e)):
                    out[r0 + int(qi) * 8 - 0x18] = (ref.get(adder, "adder %#x" % adder), off)
    return out


def strip_markup(s):
    return re.sub(r"\s+", " ", re.sub(r"<[^>]*>", "", s or "")).strip()


def raw_key(v):
    """a madlib's or field's value when it is a name-table key ("WizQst371C7_00000008"), else "" (none, a number, or
    words already - a talk goal's NAME 'Talk To')"""
    return v if isinstance(v, str) and KEY.match(v) else ""


def adder_kinds(P):
    """{property adder rva: kind} of KIND_REF's known properties in P ({class: {property: (offset, adder rva, ...)}}) -
    the adder (AddProperty<T>) a property is registered by names its type T (madlib_arg_kinds' way)"""
    out = {}
    for kind, (cls, prop) in KIND_REF.items():
        v = (P.get(cls) or {}).get(prop)
        if v and len(v) > 1 and v[1] is not None:
            out.setdefault(v[1], kind)
    return out


def quest_props(props, kinds, skip=QUEST_SKIP, cap=QUEST_PROPS_CAP):
    """[(property, offset, kind)] of a class's properties ({property: (offset, adder rva, ...)}) whose adder names a
    type that can be read (kinds - adder_kinds'), by offset (then name), skip left out, cap at most - every scalar one,
    none named: WizQuestData's for /quests (what marks a spell quest isn't known yet)"""
    out = []
    for name, v in (props or {}).items():
        if name in skip or not v or len(v) < 2 or v[0] is None:
            continue
        kind = kinds.get(v[1])
        if kind:
            out.append((name, v[0], kind))
    return sorted(out, key=lambda x: (x[1], x[0]))[:cap]


def _qcell(v):
    """a field of /quests' lines: no | or line breaks in it; None as empty"""
    return '' if v is None else re.sub(r'[|\r\n]+', ' ', str(v)).strip()


def _pval(v):
    """a property's value in quest|'s props field: bools 1/0, no , = | or line breaks"""
    if isinstance(v, bool):
        return "1" if v else "0"
    return re.sub(r'[,=|\r\n]+', ' ', '' if v is None else str(v)).strip()


def quest_lines(rows, why="", ms=None):
    """/quests' answer for quests_resolve's rows (None: none|why):
    quest|quest id|title|tracked (1/0)|goals|goals complete|title key|props (name=value,... - WizQuestData's other
        properties: an empty value not read)
    goal|quest id|goal id|kind|status|count|total|text|mob|item|npc|place|name key
    quests|quests n|tracked quest id|ms|why
    (ids decimal, as /goal's quest| line; a field not read: empty)"""
    if rows is None:
        return ["none|" + _qcell(why or "no quests read")]
    out, tracked = [], None
    for q in rows:
        goals = q.get("goals") or []
        if q.get("tracked"):
            tracked = q.get("id")
        props = ",".join("%s=%s" % (k, _pval(v)) for k, v in (q.get("props") or {}).items())
        out.append("|".join(["quest", _qcell(q.get("id")), _qcell(q.get("title")), "1" if q.get("tracked") else "0",
                             str(len(goals)), str(sum(1 for g in goals if g.get("status") == "COMPLETE")),
                             _qcell(q.get("title_key")), _qcell(props)]))
        for g in goals:
            out.append("|".join(["goal", _qcell(q.get("id")), _qcell(g.get("gid"))] +
                                [_qcell(g.get(k)) for k in ("type", "status", "count", "total", "text", "mob", "item",
                                                            "npc", "place", "name_key")]))
    out.append("|".join(["quests", str(len(rows)), _qcell(tracked), "" if ms is None else "%.1f" % ms, _qcell(why)]))
    return out


# ============================================================================ the name tables
class Lang:
    """Root.wad's name tables (Locale/en-US/<table>.lang, handmem.parse_lang), each read once - the tables a batch of keys
    needs in one pass over the wad's file list (about 0.1 s), outside navmem's lock; or in a thread, not waited for.
    Thread-safe"""

    KEEP = 60                       # tables kept (then all but PRELOAD's dropped - the next keys read theirs again)

    def __init__(self, p, log):
        self.p, self.log = p, log
        self.lock = threading.Lock()
        self.tables = {}
        self.root = None
        self.fail_at = -1e9
        self.loading = False

    def _root(self):
        if self.root is None:
            import navgeo
            gd = ""
            try:
                exe = self.p.image_path()
                if exe.lower().endswith("\\bin\\" + N.EXE.lower()):
                    gd = exe[: -len("\\bin\\" + N.EXE)]
            except Exception:  # noqa: BLE001
                pass
            self.root = os.path.join(gd or navgeo.GAME_DIR, "Data", "GameData", "Root.wad")
        return self.root

    @staticmethod
    def candidates(key):
        """the tables a key may be in: the part before each underscore ('WizQst371BE_00000000' -> WizQst371BE)"""
        if not isinstance(key, str) or not KEY.match(key):
            return []
        return [key[:m.start()] for m in re.finditer("_", key) if TABLE.match(key[:m.start()])]

    def load(self, keys, block=True):
        """reads the tables these keys may be in that aren't read yet (one pass; a table not in Root.wad is kept empty) -
        block False: in a thread (one at a time), not waited for"""
        want = sorted({t for k in keys for t in self.candidates(k)})
        with self.lock:
            want = [t for t in want if t not in self.tables]
            if not want or time.monotonic() - self.fail_at < 30.0 or (not block and self.loading):
                return
            if not block:
                self.loading = True
        if not block:
            threading.Thread(target=self._load_bg, args=(want,), name="questlang", daemon=True).start()
            return
        self._read(want)

    def _load_bg(self, want):
        try:
            self._read(want)
        finally:
            with self.lock:
                self.loading = False

    def _read(self, want):
        try:
            import navgeo
            files = navgeo.read_wad_files(self._root(), ["Locale/en-US/%s.lang" % t for t in want])
            got = {}
            for t in want:
                data = files.get("Locale/en-US/%s.lang" % t)
                got[t] = H.parse_lang(data) if data else {}
        except Exception as e:  # noqa: BLE001 - tried again in 30 s
            with self.lock:
                self.fail_at = time.monotonic()
            self.log("questmem: the name tables couldn't be read (%r)" % (e,))
            return
        with self.lock:
            if len(self.tables) + len(got) > self.KEEP:
                self.tables = {t: v for t, v in self.tables.items() if t in PRELOAD}
            self.tables.update(got)

    def text(self, key):
        """the key's text (the first of its candidate tables that is in Root.wad), None when it isn't found"""
        for t in self.candidates(key):
            with self.lock:
                names = self.tables.get(t)
            if names:
                return names.get(key[len(t) + 1:])
        return None


# ============================================================================ the reader
class QuestMem:
    """the quest's active goal - see the top. snapshot() reads the game (call it under navmem's lock: NavMem.goal);
    resolve() only looks names up and builds the line (its name tables have their own lock)"""

    def __init__(self, st, log=None):
        self.log = log or (lambda msg: None)
        t0 = time.perf_counter()
        self.st, self.p = st, st.p
        self.build = st.m.build
        img = H.Image(st)
        classes = sorted(set(NEED) | {c for c, _ in KIND_REF.values()})
        self.P = P = {c: class_props(img, c)[0] for c in classes}
        missing = [c + "." + k for c, ks in NEED.items() for k in ks if k not in P[c]]
        if missing:
            raise LookupError("reflected properties not found in this build (%s): %s" % (self.build, ", ".join(missing)))
        gt = get_types(img, "WizGoalData")
        gt = gt[0][0] if gt else None
        sn = read_enum_run(img, gt, "GOAL_STATUS_INVALID", "m_status")
        tn = read_enum_run(img, gt, "GoalTemplate::GOAL_TYPE_UNKNOWN", "m_type")
        self.status_names = {v: n.rsplit("GOAL_STATUS_", 1)[-1] for v, n in sn.items()}
        self.type_names = {v: n.rsplit("GOAL_TYPE_", 1)[-1] for v, n in tn.items()}
        # (names that don't check out: numbers only - never a guess; the line then is the HUD's own)
        if not (self.status_names.get(0) == "INCOMPLETE" and self.status_names.get(1) == "COMPLETE"):
            self.log("questmem: the goal status names couldn't be read in this build (%s) - numbers only" % self.build)
            self.status_names = {}
        if not (self.type_names.get(1) == "BOUNTY" and self.type_names.get(2) == "BOUNTYCOLLECT"
                and self.type_names.get(5) == "WAYPOINT"):
            self.log("questmem: the goal kind names couldn't be read in this build (%s) - numbers only" % self.build)
            self.type_names = {}
        self.arg_kinds = madlib_arg_kinds(img, st, P)
        # (WizQuestData's other properties, each read by its type - /quests; none named: whichever this build has)
        self.quest_extra = quest_props(P.get("WizQuestData"), adder_kinds(P))
        kinds = {k for k, _ in self.arg_kinds.values()}
        if not {"string", "int"} <= kinds:
            self.log("questmem: the goal's madlib argument types couldn't be read in this build (%s) - the HUD's line only"
                     % self.build)
            self.arg_kinds = {}
        del img                      # (the code copy: only for finding the places above)
        self.o = {}                  # places found (and checked) this attach
        self.how = {}
        self._next = {}
        self.qm_static = self._find_qm(scan=self.build != QUEST_BUILD)
        # (not found: the next look not at once - the first snapshot runs under navmem's lock; another build's look through
        # .data in a thread of its own, at 60 s, then 2, 4, 8, at most 16 min apart while it finds nothing - qmap)
        self._qm_thread, self._qm_fails = None, 0
        if self.qm_static is None:
            self._next["qm"] = time.monotonic() + (SCAN_EVERY if self.build != QUEST_BUILD else RESCAN_EVERY)
        self.lang = Lang(self.p, self.log)
        self.lang.load(["%s_x" % t for t in PRELOAD])
        self.attach_s = time.perf_counter() - t0
        self.log("questmem: ready in %.2f s - quest manager %s, %d goal kinds, %d statuses, madlib types %s" % (
            self.attach_s, self.how.get("qm"), len(self.type_names), len(self.status_names),
            ", ".join(sorted(k for k in kinds if not k.startswith("adder"))) or "none"))

    # ---------------------------------------------------------------- small readers
    def u64(self, a):
        b = self.p.try_read(a, 8) if N.ptr_ok(a) else None
        return struct.unpack("<Q", b)[0] if b else 0

    def u32(self, a):
        b = self.p.try_read(a, 4) if N.ptr_ok(a) else None
        return struct.unpack("<I", b)[0] if b else None

    def i32(self, a):
        b = self.p.try_read(a, 4) if N.ptr_ok(a) else None
        return struct.unpack("<i", b)[0] if b else None

    def off(self, cls, prop):
        """a reflected property's offset (None: not in this build)"""
        v = self.P.get(cls, {}).get(prop)
        return v[0] if v else None

    def tname(self, a):
        return self.st.tn.of(a) if N.ptr_ok(a) else None

    def wname(self, w):
        return self.p.try_string(w + self.off("Window", "m_sName")) if N.ptr_ok(w) else None

    def wstr(self, a):
        """an MSVC x64 std::wstring (8-wchar inline buffer or a pointer, size @+0x10, capacity @+0x18), or None"""
        raw = self.p.try_read(a, 0x20) if N.ptr_ok(a) else None
        if not raw:
            return None
        size, cap = struct.unpack_from("<QQ", raw, 0x10)
        if size > 0x2000 or cap < size or cap > 0x100000:
            return None
        if cap < 8:
            data = raw[:size * 2]
        else:
            data = self.p.try_read(struct.unpack_from("<Q", raw)[0], size * 2) if size else b""
        try:
            return data.decode("utf-16-le") if data is not None else None
        except UnicodeDecodeError:
            return None

    def read_kind(self, a, kind):
        """a value of one of KIND_REF's types at a (string, wstring, int, uint, float, gid, bool) - None not read"""
        if kind == "string":
            return self.p.try_string(a)
        if kind == "wstring":
            return self.wstr(a)
        if kind == "int":
            return self.i32(a)
        if kind == "uint":
            return self.u32(a)
        if kind == "gid":
            b = self.p.try_read(a, 8) if N.ptr_ok(a) else None
            return struct.unpack("<Q", b)[0] if b else None
        b = self.p.try_read(a, 4 if kind == "float" else 1) if N.ptr_ok(a) and kind in ("float", "bool") else None
        if not b:
            return None
        return round(struct.unpack("<f", b)[0], 4) if kind == "float" else bool(b[0])

    def _due(self, key, every):
        now = time.monotonic()
        if now < self._next.get(key, 0):
            return False
        self._next[key] = now + every
        return True

    # ---------------------------------------------------------------- std containers
    def map_ok(self, obj, off, lim=100000):
        """(head, size) if obj+off holds an MSVC std::map's {head, size}: the head is the nil node (+0x19 = 1) and its
        root's parent is the head (an empty map: the head is its own parent)"""
        b = self.p.try_read(obj + off, 16) if N.ptr_ok(obj) else None
        if not b:
            return None
        head, size = struct.unpack("<QQ", b)
        if not N.ptr_ok(head) or size > lim:
            return None
        hb = self.p.try_read(head, 0x20)
        if not hb or hb[0x19] != 1:
            return None
        root = struct.unpack_from("<Q", hb, 8)[0]
        if size == 0:
            return (head, 0) if root == head else None
        return (head, size) if N.ptr_ok(root) and self.u64(root + 8) == head else None

    def map_nodes(self, head, lim=5000):
        """[(key, value)] of the map at head (u64 keys, the SharedPointer's object)"""
        out, stack, seen = [], [self.u64(head + 8)], set()
        while stack and len(out) <= lim:
            n = stack.pop()
            if not N.ptr_ok(n) or n == head or n in seen:
                continue
            seen.add(n)
            b = self.p.try_read(n, 0x30)
            if not b or b[0x19] != 0:
                continue
            out.append((struct.unpack_from("<Q", b, 0x20)[0], struct.unpack_from("<Q", b, 0x28)[0]))
            stack.append(struct.unpack_from("<Q", b, 0)[0])
            stack.append(struct.unpack_from("<Q", b, 0x10)[0])
        return out

    def map_find(self, head, key, lim=64):
        """the value for key in the map at head (a tree walk), 0 when it isn't there"""
        n, k = self.u64(head + 8), 0
        while N.ptr_ok(n) and n != head and k < lim:
            b = self.p.try_read(n, 0x30)
            if not b or b[0x19] != 0:
                return 0
            nk = struct.unpack_from("<Q", b, 0x20)[0]
            if nk == key:
                return struct.unpack_from("<Q", b, 0x28)[0]
            n = struct.unpack_from("<Q", b, 0 if key < nk else 0x10)[0]
            k += 1
        return 0

    def lst(self, a, lim=64):
        """the values (+0x10) of an MSVC std::list {head, size} at a, or None"""
        b = self.p.try_read(a, 16) if N.ptr_ok(a) else None
        if not b:
            return None
        head, size = struct.unpack("<QQ", b)
        if not N.ptr_ok(head) or size > lim:
            return None
        out, n = [], self.u64(head)
        while n != head:
            if len(out) >= size or not N.ptr_ok(n):
                return None
            out.append(self.u64(n + 0x10))
            n = self.u64(n)
        return out if len(out) == size else None

    # ---------------------------------------------------------------- the quest manager
    def _quests_map(self, obj, off):
        """(head, size) of a map at obj+off whose values are WizQuestData keyed by their m_id, else None"""
        m = self.map_ok(obj, off, 5000)
        if not m or not m[1]:
            return None
        nodes = self.map_nodes(m[0], 4)
        # (keyed by the quest's GID: the manager has a second map of the same quests keyed otherwise, +0x90)
        ok = (nodes and self.tname(nodes[0][1]) == "WizQuestData"
              and self.u64(nodes[0][1] + self.off("WizQuestData", "m_id")) == nodes[0][0])
        return m if ok else None

    def _find_qm(self, scan):
        """(rva, map offset) of the quest manager's static and its quest map: the known one (checked), else - scan, in
        another build - a .data pointer to an object holding a map of WizQuestData; None not found (no quests yet: the
        login screen)"""
        base = self.st.m.base
        qm = self.u64(base + KNOWN["qm_rva"])
        if N.ptr_ok(qm) and self._quests_map(qm, KNOWN["qm_quests"]):
            self.how["qm"] = "known static rva %#x +%#x (checked: its map holds WizQuestData)" % (
                KNOWN["qm_rva"], KNOWN["qm_quests"])
            return (KNOWN["qm_rva"], KNOWN["qm_quests"])
        if not scan:
            self.how["qm"] = "not there yet (no quests: the login screen?)"
            return None
        import numpy as np
        va, vs, _ = self.st.m.sections[".data"]
        for at, raw in self.p.read_pieces(base + va, vs, 0x100000):
            q = np.frombuffer(raw[:len(raw) // 8 * 8], dtype=np.uint64)
            for i in np.flatnonzero((q > 0x10000000) & (q < 0x7FF000000000) & ((q & 7) == 0)):
                obj = int(q[i])
                blob = self.p.try_read(obj, 0x200)
                if not blob:
                    continue
                for off in range(8, 0x1F8, 8):
                    head, size = struct.unpack_from("<QQ", blob, off)
                    if N.ptr_ok(head) and 0 < size < 5000 and self._quests_map(obj, off):
                        rva = at + int(i) * 8 - base
                        self.how["qm"] = "found: static rva %#x +%#x (a map of WizQuestData)" % (rva, off)
                        self.log("questmem: the quest manager found at rva %#x +%#x" % (rva, off))
                        return (rva, off)
        self.how["qm"] = "not found (no quests yet?)"
        return None

    def qmap(self):
        """(head, size) of the quest manager's map of quests (walked from the static at every read: a character switch
        builds it again), or None"""
        if self.qm_static is None:
            if self.build == QUEST_BUILD:
                if self._due("qm", RESCAN_EVERY):
                    self.qm_static = self._find_qm(scan=False)      # (one check of the known static: cheap)
            elif (not (self._qm_thread and self._qm_thread.is_alive())
                  and self._due("qm", SCAN_EVERY * min(2 ** self._qm_fails, 16))):
                # (the look through .data takes seconds - 2.5 s measured: never under navmem's lock, which /nav, /cards
                # and the goal wait on - in a thread, as the reader itself is made)
                self._qm_thread = threading.Thread(target=self._scan_qm, name="questscan", daemon=True)
                self._qm_thread.start()
            if self.qm_static is None:
                return None
        rva, off = self.qm_static
        return self._quests_map(self.u64(self.st.m.base + rva), off)

    def _scan_qm(self):
        """the quest manager looked for through .data (another build) - outside navmem's lock (read-only reads, as the
        constructor's); published when found"""
        try:
            found = self._find_qm(scan=True)
        except Exception as e:                  # (a read gone bad mid-look: the next look as if nothing was found)
            self.log("questmem: the look for the quest manager failed: %s" % e)
            found = None
        if found is None:
            self._qm_fails += 1                 # (60 s, then 2, 4, 8, at most 16 min between looks)
        else:
            self.qm_static = found              # (a tuple set in one go: read by qmap under the lock)

    def quest(self, qmap, qid):
        """the WizQuestData for quest GID qid (checked: its type name and m_id), else 0"""
        q = self.map_find(qmap[0], qid) if qid else 0
        ok = q and self.tname(q) == "WizQuestData" and self.u64(q + self.off("WizQuestData", "m_id")) == qid
        return q if ok else 0

    def goal_map(self, q):
        """(head, size) of the quest's goal map (values WizGoalData keyed by their m_goalID); its offset found once by
        shape and kept"""
        off = self.o.get("quest_goals")
        tries = [off] if off is not None else [KNOWN["quest_goals"]] + list(range(0x48, 0x200, 8))
        for o in tries:
            m = self.map_ok(q, o, 200)
            if not m or not m[1]:
                continue
            nodes = self.map_nodes(m[0], 4)
            if (nodes and self.tname(nodes[0][1]) == "WizGoalData"
                    and self.u64(nodes[0][1] + self.off("WizGoalData", "m_goalID")) == nodes[0][0]):
                if off is None:
                    self.o["quest_goals"] = o
                    self.how["quest_goals"] = "+%#x (%s)" % (o, "known, checked" if o == KNOWN["quest_goals"] else "found by shape")
                return m
        return None

    def goal_of(self, q, gid):
        """the WizGoalData for goal GID gid of quest q (checked: its type name and m_goalID), else 0"""
        gm = self.goal_map(q) if q and gid else None
        g = self.map_find(gm[0], gid) if gm else 0
        ok = g and self.tname(g) == "WizGoalData" and self.u64(g + self.off("WizGoalData", "m_goalID")) == gid
        return g if ok else 0

    # ---------------------------------------------------------------- one goal's own data
    def madlibs(self, g):
        """[(token, kind, value)] of a goal's MadlibBlock (value None: its type isn't known), or None (no block)"""
        mb = self.u64(g + self.off("WizGoalData", "m_madLibs"))
        if not N.ptr_ok(mb) or self.tname(mb) != "MadlibBlock":
            return None
        args = self.lst(mb + self.off("MadlibBlock", "m_madlibs"))
        if args is None:
            return None
        out = []
        tok_off = self.off("MadlibArg", "m_madlibToken")
        for a in args:
            if not N.ptr_ok(a):
                continue
            kind, voff = self.arg_kinds.get(self.u64(a), (None, None))
            tok = self.p.try_string(a + tok_off)
            v = None
            if kind == "string":
                v = self.p.try_string(a + voff)
            elif kind == "wstring":
                v = self.wstr(a + voff)
            elif kind == "int":
                v = self.i32(a + voff)
            elif kind == "uint":
                v = self.u32(a + voff)
            elif kind == "float":
                b = self.p.try_read(a + voff, 4)
                v = struct.unpack("<f", b)[0] if b else None
            elif kind == "gid":
                v = self.u64(a + voff)
            out.append((tok, kind, v))
        return out

    def goal_raw(self, g):
        """a goal's keys and numbers as they are in memory (the names not looked up yet)"""
        o = lambda prop: g + self.off("WizGoalData", prop)  # noqa: E731
        st, ty = self.i32(o("m_status")), self.i32(o("m_type"))
        return {"gid": self.u64(o("m_goalID")), "name_key": self.p.try_string(o("m_name")),
                "status": self.status_names.get(st), "status_raw": st, "type": self.type_names.get(ty), "type_raw": ty,
                "location_key": self.p.try_string(o("m_location")), "madlibs": self.madlibs(g)}

    # ---------------------------------------------------------------- the HUD: its line and ids
    def kids(self, w):
        b = self.p.try_read(w + self.off("Window", "m_Children"), 16) if N.ptr_ok(w) else None
        if not b:
            return []
        lo, hi = struct.unpack("<QQ", b)
        if not (N.ptr_ok(lo) and lo <= hi <= lo + 0x8000 and (hi - lo) % 16 == 0):
            return []
        raw = self.p.try_read(lo, hi - lo) or b""
        return [struct.unpack_from("<Q", raw, i)[0] for i in range(0, len(raw), 16)]

    def shown_flag(self, w):
        v = self.u32(w + self.off("Window", "m_Flags"))
        return None if v is None else bool(v & 1)

    def hud(self):
        """(HUD, QuestHelperHud, "") checked by their window names, else (.., 0, why)"""
        o = self.st.o
        if o.get("gm") is None or o.get("hud_qhh") is None:
            return 0, 0, "no HUD yet"
        rva, off = o["gm"]
        gm = self.u64(self.st.m.base + rva)
        hud = self.u64(gm + off) if N.ptr_ok(gm) else 0
        if self.wname(hud) != "windowHUD":
            return 0, 0, "no HUD (not in the game world)"
        qhh = self.u64(hud + o["hud_qhh"])
        if self.wname(qhh) != "QuestHelperHud":
            return hud, 0, "no quest helper on the HUD"
        return hud, qhh, ""

    def shown(self, hud, qhh):
        """({raw, text, visible, flags, distance} of the HUD's txtGoalName, "") or (None, why)"""
        found, seen = {}, set()

        def walk(w, chain, d):
            for c in self.kids(w):
                if not N.ptr_ok(c) or c in seen or len(seen) > 500:
                    continue
                seen.add(c)
                nm = self.wname(c)
                if nm in ("txtGoalName", "txtDistance") and nm not in found and self.tname(c) == "ControlText":
                    found[nm] = chain + [c]
                if d < 6 and len(found) < 2:
                    walk(c, chain + [c], d + 1)
        walk(qhh, [qhh], 0)
        if "txtGoalName" not in found:
            return None, "no txtGoalName under the QuestHelperHud"
        chain = found["txtGoalName"]
        raw = self.wstr(chain[-1] + self.off("ControlText", "m_sText"))
        if raw is None:
            return None, "the goal line's text can't be read"
        flags = [self.shown_flag(hud)] + [self.shown_flag(w) for w in chain]
        dist = None
        if "txtDistance" in found:
            dist = strip_markup(self.wstr(found["txtDistance"][-1] + self.off("ControlText", "m_sText")))
        return {"raw": raw, "text": strip_markup(raw), "visible": None if None in flags else all(flags), "flags": flags,
                "distance": dist}, ""

    def hud_ids(self, qhh, qmap):
        """(quest GID, goal GID) the QuestHelperHud shows - +0x2D8 / +0x2E0 in build QUEST_BUILD, else the first pair in
        it that is a quest of the manager's map and a goal of that quest (checked at every read) - or None"""
        def ok(at):
            b = self.p.try_read(qhh + at, 16)
            if not b:
                return None
            qid, gid = struct.unpack("<QQ", b)
            return (qid, gid) if self.goal_of(self.quest(qmap, qid), gid) else None
        at = self.o.get("hud_ids", KNOWN["hud_ids"])
        got = ok(at)
        if got is None and "hud_ids" not in self.o and self.build != QUEST_BUILD and self._due("hud_ids", RESCAN_EVERY):
            for at in range(0x200, 0x800, 8):
                got = ok(at)
                if got:
                    self.how["hud_ids"] = "found at +%#x" % at
                    break
        if got:
            self.o["hud_ids"] = at
        return got

    # ---------------------------------------------------------------- one reading
    def snapshot(self, thread_ids=(None, None)):
        """the memory reads of one reading (call it under navmem's lock) - never raises: {shown, shown_why, hud_ids,
        thread_ids, ids, ids_from, quest {title_key, id}, goal (goal_raw), why, ms}"""
        t0 = time.perf_counter()
        out = {"shown": None, "shown_why": "", "hud_ids": None, "thread_ids": tuple(thread_ids or (None, None)),
               "ids": None, "ids_from": "", "quest": None, "goal": None, "why": "", "ms": 0.0}
        try:
            self._snapshot(out)
        except Exception as e:  # noqa: BLE001 - never into the server
            out["why"] = "reading the quest's goal failed (%r)" % (e,)
        out["ms"] = (time.perf_counter() - t0) * 1000
        return out

    def _snapshot(self, out):
        hud, qhh, why = self.hud()
        if qhh:
            out["shown"], out["shown_why"] = self.shown(hud, qhh)
        else:
            out["shown_why"] = why
        qm = self.qmap()
        if qm is None:
            out["why"] = "no quests in the game's memory (%s)" % self.how.get("qm", "?")
            return
        cands = []
        hq = self.hud_ids(qhh, qm) if qhh else None
        if hq:
            out["hud_ids"] = hq
            cands.append((hq, "hud"))
        tq = out["thread_ids"]
        if tq[0] and tq[1] and tq != hq:
            cands.append((tq, "thread"))
        if not cands:
            out["why"] = "no quest goal ids to read (the quest helper's)"
            return
        got, why = [], ""
        for (qid, gid), src in cands:
            q = self.quest(qm, qid)
            if not q:
                why = why or "quest %s isn't in the game's quests" % qid
                continue
            g = self.goal_of(q, gid)
            if not g:
                why = why or "goal %s isn't in quest %s's goals" % (gid, qid)
                continue
            got.append(((qid, gid), src, q, self.goal_raw(g)))
            if got[-1][3]["status"] != "COMPLETE":
                break               # (COMPLETE: the quest moving on - the other ids' goal, if it isn't)
        if not got:
            out["why"] = why
            return
        ids, src, q, g = next((x for x in got if x[3]["status"] != "COMPLETE"), got[0])
        out["ids"], out["ids_from"], out["goal"] = ids, src, g
        out["quest"] = {"id": ids[0], "title_key": self.p.try_string(q + self.off("WizQuestData", "m_title"))}

    # ---------------------------------------------------------------- the names and the line
    def name(self, v):
        """a madlib's or field's words: a name-table key's text (None when it isn't found), anything else as it is"""
        if not v:
            return ""
        if not KEY.match(v):
            return v                 # (words already: a talk goal's NAME is 'Talk To')
        return self.lang.text(v)

    def compose(self, g, args):
        """(the goal's line as the game builds it - see the top -, every name in it found)"""
        kind = g.get("type") or ""
        key = SENTENCE.get(kind)
        if kind == "PERSONA":
            f, l_ = bool(args.get("FIRSTNAME")), bool(args.get("LASTNAME"))
            key = "PersonaChatFL" if f and l_ else "PersonaChatF" if f else "PersonaChatL" if l_ else None
        ok = [bool(kind)]                # (its kind not read: which sentence isn't known - the HUD's line)
        fmt = self.lang.text("Quest_" + key) if key else PLAIN
        if not fmt:
            ok[0], fmt = False, PLAIN      # (the game's sentence not read yet: not the line it shows)

        def val(m):
            tok = m.group(1)
            if tok == "PREFIX":
                return ""
            if tok in args and args[tok] is None:
                ok[0] = False        # (its type isn't known: not read)
            v = args.get(tok)
            if v is None and tok == "NAME":
                v = g.get("name_key")
            if v is None and tok == "LOCATION":
                v = g.get("location_key")
            if isinstance(v, str):
                t = self.name(v)
                if t is None:
                    ok[0], t = False, ""
            else:
                t = "" if v is None else str(v)
            return t.split("|")[-1] if tok == "LOCATION" else t
        s = re.sub(r"\$GOAL_([A-Z0-9_]+)\$", val, re.sub(r"#\d+:", "", fmt))
        s = re.sub(r"\s+", " ", s).strip()
        s = re.sub(r"^in |\s+in$", "", s).strip()
        count, total = args.get("COUNT"), args.get("TOTAL")
        if isinstance(total, int) and total > 1 and isinstance(count, int):
            s += " (%d of %d)" % (count, total)
        return s, ok[0]

    def resolve(self, snap, block=True):
        """the reading for the bot from a snapshot (block False: a name table not read yet is read in a thread, not
        waited for - the line is then the HUD's own till it's there) - never raises:
            text      the goal line ("Defeat Optio Misemos in The Grotto") - the one built from the quest's data (the
                      HUD's ids' goal), else the HUD's own; None when neither can be read (why says why)
            from      "data" / "hud": which of the two text is
            exact     True when text is the data's with every name in it found (the fields below are then the goal's)
            shown, visible, distance    the HUD's own line, on screen or not (None: unknown), the arrow's number
            type, status   BOUNTY (defeat), BOUNTYCOLLECT (defeat and collect), USAGE (collect / open / use / read),
                      WAYPOINT (go to), PERSONA (talk to), SCAVENGE...; INCOMPLETE / COMPLETE (None: not read)
            count, total   "(count of total)" (None: none - a talk or go-to goal)
            name, mob, item, npc, place   the goal's verb ("Defeat"), the mob it names (TALLYTEXT2: "Crustacean
                      Waverunner", "Gobblers"), the item / object / one to go to (TALLYTEXT), the NPC to talk to
                      (FIRSTNAME LASTNAME), the place ("" none)
            quest, quest_id, goal_id, ids_from   the quest's title, the GIDs read, whose ids they are ("hud" / "thread")
            item_key, mob_key, npc_keys, name_key   the same names' name-table keys as the goal holds them - TALLYTEXT
                      ("WizQst371C7_00000008" = Inactive Protector: the display key of the zone objects it means - their
                      template's +0xA8), TALLYTEXT2 ("WizardMobs_00000883"), (FIRSTNAME, LASTNAME), the goal's own name
                      (m_name "WizardQuestGoals_UseItem", else NAME's): exact, no name lookup - there even while a name
                      table isn't read. "" (("", "")) when there's none or the value is words, not a key; cleared with
                      the names when the quest has moved on. A match candidate, never the only test: a goal's key may be
                      another table's for the same words (Jack O' Lantern's, Flame Gems')
            why, ms"""
        out = {"text": None, "from": "", "exact": False, "shown": None, "visible": None, "distance": None,
               "type": None, "type_raw": None, "status": None, "count": None, "total": None, "name": "", "mob": "",
               "item": "", "npc": "", "place": "", "quest": "", "quest_id": None, "goal_id": None,
               "ids_from": "", "why": "", "ms": 0.0,
               "item_key": "", "mob_key": "", "npc_keys": ("", ""), "name_key": ""}
        t0 = time.perf_counter()
        try:
            self._resolve(snap, out, block)
        except Exception as e:  # noqa: BLE001
            out["text"], out["why"] = None, "building the goal line failed (%r)" % (e,)
        out["ms"] = round((snap.get("ms") or 0.0) + (time.perf_counter() - t0) * 1000, 2)
        return out

    def _resolve(self, snap, out, block):
        sh = snap.get("shown") or {}
        out.update(shown=sh.get("text") or None, visible=sh.get("visible"), distance=sh.get("distance"),
                   ids_from=snap.get("ids_from") or "", why=snap.get("why") or "")
        if snap.get("ids"):
            out["quest_id"], out["goal_id"] = snap["ids"]
        g = snap.get("goal")
        data_text, ok = None, False
        if g:
            args = {t: v for t, _k, v in (g.get("madlibs") or []) if t}
            title_key = (snap.get("quest") or {}).get("title_key")
            keys = [v for v in list(args.values()) + [g.get("name_key"), g.get("location_key"), title_key]
                    if isinstance(v, str)]
            self.lang.load(keys + ["Quest_x"], block)
            if g.get("madlibs") is not None:
                data_text, ok = self.compose(g, args)
            nm = lambda v: self.name(v) or ""  # noqa: E731
            count, total = args.get("COUNT"), args.get("TOTAL")
            out.update(type=g.get("type"), type_raw=g.get("type_raw"), status=g.get("status"),
                       count=count if isinstance(count, int) else None, total=total if isinstance(total, int) else None,
                       name=nm(args.get("NAME") or g.get("name_key")), mob=nm(args.get("TALLYTEXT2")),
                       item=nm(args.get("TALLYTEXT")),
                       npc=" ".join(x for x in (nm(args.get("FIRSTNAME")), nm(args.get("LASTNAME"))) if x),
                       place=nm(args.get("LOCATION") or g.get("location_key")).split("|")[-1],
                       quest=nm(title_key))
            # (the raw keys: no lookup - there even while a name table isn't read yet)
            out.update(item_key=raw_key(args.get("TALLYTEXT")), mob_key=raw_key(args.get("TALLYTEXT2")),
                       npc_keys=(raw_key(args.get("FIRSTNAME")), raw_key(args.get("LASTNAME"))),
                       name_key=raw_key(g.get("name_key")) or raw_key(args.get("NAME")))
            if g.get("madlibs") is None:
                out["why"] = "the goal has no madlibs (the HUD's line only)"
        shown = out["shown"]
        moved_on = bool(g) and g.get("status") == "COMPLETE" and shown and shown != data_text
        if data_text and ok and not moved_on:
            out.update(text=data_text, exact=bool(g.get("type")))
            out["from"] = "data"
        elif shown:
            out["text"] = shown
            out["from"] = "hud"
            if moved_on:
                # (the quest moved on: the HUD shows the next goal already, the ids read are a goal behind - their names
                # aren't this line's)
                out.update(type=None, type_raw=None, status=None, count=None, total=None, name="", mob="", item="",
                           npc="", place="", item_key="", mob_key="", npc_keys=("", ""), name_key="")
                out["why"] = "the goal read is complete - the HUD's line is the next one"
            elif g and not ok:
                out["why"] = out["why"] or "a name of the goal's isn't in the name tables (yet) - the HUD's line"
        elif data_text:
            # (no line with a name left out: the bot reads the screen instead)
            out["why"] = out["why"] or "a name of the goal's isn't in the name tables (yet), and the HUD's line can't be read"
        if not out["text"] and not out["why"]:
            out["why"] = snap.get("shown_why") or "no goal line"

    # ---------------------------------------------------------------- every quest (/quests, the command line's --all)
    def quest_ids(self):
        """([(quest GID, its WizQuestData)] of the quest manager's map - by GID, QUESTS_CAP at most -, "") or (None, why)
        (call it under navmem's lock; each quest read after with quest_raw - the lock let go in between)"""
        qm = self.qmap()
        if qm is None:
            return None, "no quests in the game's memory (%s)" % self.how.get("qm", "?")
        return sorted(self.map_nodes(qm[0], QUESTS_CAP))[:QUESTS_CAP], ""

    def quest_raw(self, qid, q):
        """one quest's keys and numbers as they are in memory - {id, title_key, goals [goal_raw...] (by GID), props
        {property: value} (quest_extra's)} - or None when q is no longer quest qid (its type name and m_id checked: done
        or dropped since the map was walked). Call it under navmem's lock"""
        if not q or self.tname(q) != "WizQuestData" or self.u64(q + self.off("WizQuestData", "m_id")) != qid:
            return None
        gm = self.goal_map(q)
        goals = []
        for gid, g in sorted(self.map_nodes(gm[0], GOALS_CAP) if gm else [])[:GOALS_CAP]:
            if self.tname(g) == "WizGoalData" and self.u64(g + self.off("WizGoalData", "m_goalID")) == gid:
                goals.append(self.goal_raw(g))
        return {"id": qid, "title_key": self.p.try_string(q + self.off("WizQuestData", "m_title")), "goals": goals,
                "props": {name: self.read_kind(q + off, kind) for name, off, kind in self.quest_extra}}

    def quests_resolve(self, raws, tracked=None, block=True):
        """[{id, title, title_key, tracked, goals [{gid, text, type, type_raw, status, count, total, mob, item, npc, place,
        name_key, item_key, mob_key, npc_keys, why}], props}] for quest_raw's readings - the names looked up (outside
        navmem's lock; every table they need in one pass, block False: in a thread, not waited for), each goal as
        resolve() reads it from the quest's data (text None when a name isn't in the tables - there's no HUD line to fall
        back on here); tracked: the quest GID the HUD shows (goal()'s). Never raises - a quest that fails is left out"""
        keys = ["Quest_x"]
        for raw in raws:
            keys.append(raw.get("title_key"))
            for g in raw.get("goals") or []:
                keys += [g.get("name_key"), g.get("location_key")] + [v for _t, _k, v in (g.get("madlibs") or [])]
        try:
            self.lang.load([k for k in keys if isinstance(k, str)], block)
        except Exception as e:  # noqa: BLE001 - the keys then (resolve says a name isn't found)
            self.log("questmem: the quests' name tables couldn't be read (%r)" % (e,))
        rows = []
        for raw in raws:
            try:
                qid, tk = raw["id"], raw.get("title_key")
                goals = []
                for g in raw.get("goals") or []:
                    r = self.resolve({"ids": (qid, g.get("gid")), "ids_from": "map", "quest": {"id": qid, "title_key": tk},
                                      "goal": g}, block=False)
                    goals.append(dict({k: r.get(k) for k in ("text", "type", "type_raw", "status", "count", "total",
                                                            "mob", "item", "npc", "place", "name_key", "item_key",
                                                            "mob_key", "npc_keys", "why")}, gid=g.get("gid")))
                rows.append({"id": qid, "title": self.name(tk) or "", "title_key": tk or "",
                             "tracked": tracked is not None and qid == tracked, "goals": goals,
                             "props": dict(raw.get("props") or {})})
            except Exception as e:  # noqa: BLE001 - that quest left out, the rest given
                self.log("questmem: quest %s couldn't be read (%r)" % (raw.get("id"), e))
        return rows


# ============================================================================ command line
def _main():
    import argparse
    ap = argparse.ArgumentParser(description="read-only: the quest's active goal and its line")
    ap.add_argument("-n", type=int, default=1)
    ap.add_argument("-i", type=float, default=2.0)
    ap.add_argument("--all", action="store_true", help="every quest's goals too")
    a = ap.parse_args()
    nm = N.NavMem(log=print)
    for k in range(a.n):
        if k:
            time.sleep(a.i)
        t0 = time.perf_counter()
        g, why = nm.goal(wait=60)
        ms = (time.perf_counter() - t0) * 1000
        if g is None:
            print("%7.1f ms  none: %s" % (ms, why))
            continue
        print("%7.1f ms  %r (from %s, exact %s)  %s %s %s/%s  mob %r item %r npc %r place %r  [%s: %s / %s]  %s" % (
            ms, g["text"], g["from"], g["exact"], g["type"], g["status"], g["count"], g["total"], g["mob"], g["item"],
            g["npc"], g["place"], g["ids_from"], g["quest_id"], g["goal_id"], g["why"]))
        print("           quest %r; on screen %r visible=%s distance=%s; read in %.2f ms" % (
            g["quest"], g["shown"], g["visible"], g["distance"], g["ms"]))
    if a.all:
        t0 = time.perf_counter()
        rows, why = nm.quests(wait=60)
        print("\n".join(quest_lines(rows, why, (time.perf_counter() - t0) * 1000)))
    print(nm.describe())


if __name__ == "__main__":
    _main()
