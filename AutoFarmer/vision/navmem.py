"""navmem - READ-ONLY reader of the wizard's position and the quest goal in a running Wizard101 client
(WizardGraphicalClient.exe), for the vision helper's /nav and /navmap.

    nm = NavMem(log=print)
    r, why = nm.read(path=True)     # r: a dict (see NavMem.read), or None and why it can't be read

    mobs, why = nm.mobs()           # the zone's mobs: [{name, pos (x, y, z), yaw, gid, template, title, title_id, rank,
                                    # health, school, boss, kind}], or None and why (title...kind: bossmem.py - None each
                                    # while not known)

    doors, why = nm.blockers()      # the zone's doors, gates and collision walls (no name key, a blocker's template
                                    # name - puzzlefile.is_blocker): [{name, pos, yaw, gid, template, state}], or None and
                                    # why (state: its ObjectStateBehavior's - statemem.py, NOT CONFIRMED in the game yet -
                                    # None while not known)

    hand, why = nm.cards()          # the cards in the wizard's hand in a battle and its pips (handmem.py), or None and why

    parts, why = nm.battle()        # the battle's participants (bossmem.py: team, health, max, boss flag...), each joined
                                    # to its mob (name, title, rank) - [] out of a battle's planning phase, or None and why

    goal, why = nm.goal()           # the quest's active goal: its line as the game shows it under the arrow, its kind,
                                    # count and the mob / item / NPC it names (questmem.py), or None and why
    quests, why = nm.quests()       # EVERY quest in the game's quest manager, each goal's kind / status / line, the
                                    # tracked one marked (questmem.py - /quests), or None and why

    deck, why = nm.deck(fresh=True) # the worn deck (deckmem.py: its cards, treasure cards, item cards, limits), read
                                    # paced under the lock (12 ms at a time, let go at once for a gated request; it
                                    # gives way - None - when not idle for 1 s or stop() says so) - the battle
                                    # recorder's, out of battle only; nm.deck(fresh=True, books=True): the spellbook
                                    # and treasure book too (/book - its own cache: the decks' stays theirs)
    sig, why = nm.deck_sig()        # its signature (~2 ms); nm.mob_infos(gids): the mobs' cached infos, no read

    gear, why = nm.gear()           # the worn gear and the backpack's with their equip effects and requirements, every
                                    # backpack item's id, the Equipment Sets, the level (gearmem.py - NOT CONFIRMED in
                                    # the game yet) - the helper's /gear (gearrank.py's swap plan, a run's drop log)

    python navmem.py [-n 5] [-i 1] [--path] [--mobs [--motion SECONDS]] [--goal]   readings from the command line (and how
                                    # long each took); --motion: the mobs watched walking (navroute.MobMotion)

SAFETY. The game is opened with PROCESS_VM_READ | PROCESS_QUERY_INFORMATION (falling back to
PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION) and nothing else. The only process APIs used are
CreateToolhelp32Snapshot / Process32*W (finding the pid), OpenProcess, ReadProcessMemory, VirtualQueryEx and
QueryWorkingSetEx (which of its memory is in use and in RAM - for the mobs; only that is read, nothing is paged
in), EnumProcessModulesEx, GetModuleBaseNameW,
QueryFullProcessImageNameW and GetExitCodeProcess. Nothing is
ever written, allocated, injected, hooked, suspended or debugged; no window is touched and no input is
sent. Signatures are looked for in a copy of the game's code read with ReadProcessMemory.

FAILS SOFT. Nothing here raises into the caller: every read gives (None, why) when it can't be done, and a
value that can't be read for sure is None (never a guess). Values the game's threads write are read twice
and kept only when two reads in a row agree.

WHAT IS READ (offsets of the client of 2026-10-13; when the helper attaches to a game, each is found again
by a signature in its code, or checked by a type name / window name it carries):

  player:  [exe + rva] GameClient*                          sig ZONE (also gives the zone offsets),
                                                             else sig GAMECLIENT
             +0x21368  ClientZone* -> +0x58 std::string     the zone, e.g. WizardCity/WC_Ravenwood
             +0x222C8  ElasticCamController*                checked by its type name, else found by it
               +0x108  the ClientObject the camera follows  = the wizard (type name ...ClientObject)
                 +0x1B8 AnimationBehavior* -> +0x70 ActorBody*   sig GETLOCATION
                   ActorBody +0x48 parent ClientObject (must be the wizard), +0x58 x, y, z (floats),
                   +0x64 pitch, +0x68 roll, +0x6C yaw (radians)
                 ClientObject +0xA8 x, y, z, +0xB4 pitch, roll, yaw: its own copy, used while it has
                   no body (zoning)
           The camera's object is checked to be a ClientObject by its type name (...ClientObject): a destroyed one's
           reads as PropertyClass (its destructor leaves the base class's vtable) and isn't followed - logged out or
           disconnected, the old world stays in memory a while.
           Z is up; yaw is measured from -Y: forward = (-sin yaw, -cos yaw).

  quest:   [exe + rva] WizardGUIManager*                    sig GUIMGR_HUD (candidates, voted), each
             +0x2D0  HUDWindow*                             checked by its window name "windowHUD"
               +0x6A8  QuestHelperHud*                      sig HUD_QHH, window name "QuestHelperHud"
                 +0x300 arrow target x, y, z (the node the on-screen arrow points at)  \
                 +0x334 arrow distance (along the path), +0x338 hops                    / sig HUD_FIELDS
                 +0x2C8 QuestHelperThread*                  sig QHH_THREAD, thread name "QuestHelper"
                   +0xC68 enabled (byte)                    sig ENABLED
                   +0xC88 quest id, +0xC90 goal id (GIDs)   sigs ACTIVE_QUEST, ACTIVE_GOAL
                   +0xCC0 std::string the thread's zone     sig ZONEINFO
                   +0xCFC goal x, y, z                      sig GOAL
                   +0xD08 hops (int): 0 = the goal is in this zone; N = N zone changes away, and
                          +0xCFC is the teleporter to take in this zone        sig HOPS
                   +0xD10 Path*: +0 std::list head, +8 count; list node +0x10 NavNode*,
                          NavNode +0x30 x, y, z (a zone.nav node)              sig PATH
           mobs:    every ClientObject of the zone holds the zone's ClientZone (GameClient +0x21368) at +0x130:
             the game's heap (its committed private read-write memory) is looked through for that pointer by a
             background thread - all of it (the pages in RAM) every OBJ_SETTLE_EVERY s for OBJ_SETTLE s in a new zone (its
             mobs come after the loading screen) and while none is found, then every OBJ_FULL s, in between only
             where objects were found, every OBJ_QUICK s (it stops when nobody has asked for OBJ_IDLE s - a long
             battle - keeping what it found: each is checked again at every read, and it carries on from there).
             ClientObject +0 vtable (a live one's type name ends ClientObject: a destroyed one's is its base class's,
             PropertyClass), +0x48 global id, +0x58 template, +0xA8 x, y, z (its own copy - the body's,
             as the wizard's, when it has one); template +0x60 its name (m_objectName), +0xA8 its display name's key
             (m_displayName), +0x1C8 its school (WizGameObjectTemplate's m_primarySchoolName - read on a Wiz* template
             only). A mob: a display name in one of the game's *Mobs name tables (Root.wad Locale/en-US/
             WizardMobs.lang, Mobs.lang) that has a name - wisps and the like have none - and a school (a teleporter
             can borrow a mob's name). Every other object with a name key is a thing (items()): an item (WizItems -
             Piece Of Coral), an object (WizQst371C7_00000008 - the Inactive Protector a USAGE goal names by that very
             key), an NPC, an ambient one (a mob's name, no school); its name from placements.py's name tables (read in
             its worker, kept). An object with no name key whose template's name is a door, a gate, a collision wall
             (puzzlefile.is_blocker: DynaTrigger_KT_DoorCollision, CL-StormLordTempleGate) is a blocker (blockers()):
             the walker held in front of one may have a puzzle to open it - and it going from memory is the way
             opening (the same template name and position reads as the mobs': no other offset) - each one's state read
             at every blockers() (statemem.py: its ObjectStateBehavior's current state, by reflected names - not
             confirmed in the game yet; None while not known; its reader made once per game in a thread like the
             titles'). An object with no name key whose template is one the zone's triggers' use events may be fired by
             (puzzlefile.use_templates - a lever the game names nowhere, matched by the event's words: "PedestalUsed",
             CL-Pedestal-01) is a thing of kind "use" (items(): name and key ""). An object is re-checked
             at each read
             - the same vtable (a destroyed one's is changed by its destructor), global id and zone - before its
             position is used.
           no place: a goal the game shows no way to (no arrow - "Use Inactive Protector in District of the Stars
             (0 of 3)") reads the thread's goal exactly (0, 0, 0), hops 0, the HUD's distance -1, hops 0: noplace 1
             (noplace_of), how long it has held for the goal timed by every read() (NoPlaceHold)
           titles:  each mob's title (Boss / Elite / Normal / Easy / Minion), rank, starting (max) health, school and the
             game's own boss flag: its NPCBehavior's NPCBehaviorTemplate - bossmem.py, its offsets found by name in the
             game's reflection registration (handmem.py's way), read under this lock once per mob object (kept while it
             lives: a mob's template doesn't change; one that couldn't be read tried again after BOSS_RETRY s); its
             reader made once per game in a thread like the hand's. In a battle (battle()): the battle GUI's participants
             (their health, max health, boss flag, team), each joined to its mob by its owner's global id
           goal:    the goal line (txtGoalName under the QuestHelperHud, its ids at +0x2D8 / +0x2E0) and the quest
             manager's quest data (WizQuestData -> WizGoalData -> its madlibs) - questmem.py, its offsets found by name
             in the game's reflection registration (handmem.py's way), read under this lock, the names looked up outside
             it; its reader made once per game in a thread like the hand's
           The quest thread (it updates every 100 ms) keeps its own zone name: after a zone change its goal
           belongs to the old zone until it catches up, so goal, target, distance and path count only while
           the thread's zone is the game's zone (and target / distance only while the arrow's hops are the
           thread's). The HUD and the thread are rebuilt on a character switch, so the chain is walked
           again on every read.
"""
import ctypes as C
import ctypes.wintypes as W
import math
import re
import struct
import threading
import time
from collections import Counter

EXE = "WizardGraphicalClient.exe"

# ============================================================================ read-only process access
PROCESS_VM_READ = 0x0010
PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
STILL_ACTIVE = 259
TH32CS_SNAPPROCESS = 0x2
LIST_MODULES_ALL = 0x3

k32 = C.WinDLL("kernel32", use_last_error=True)
psapi = C.WinDLL("psapi", use_last_error=True)
u32 = C.WinDLL("user32", use_last_error=True)


class PROCESSENTRY32W(C.Structure):
    _fields_ = [("dwSize", W.DWORD), ("cntUsage", W.DWORD), ("th32ProcessID", W.DWORD),
                ("th32DefaultHeapID", C.c_size_t), ("th32ModuleID", W.DWORD),
                ("cntThreads", W.DWORD), ("th32ParentProcessID", W.DWORD),
                ("pcPriClassBase", C.c_long), ("dwFlags", W.DWORD), ("szExeFile", W.WCHAR * 260)]


k32.CreateToolhelp32Snapshot.restype = W.HANDLE
k32.CreateToolhelp32Snapshot.argtypes = [W.DWORD, W.DWORD]
k32.Process32FirstW.argtypes = [W.HANDLE, C.POINTER(PROCESSENTRY32W)]
k32.Process32NextW.argtypes = [W.HANDLE, C.POINTER(PROCESSENTRY32W)]
k32.OpenProcess.restype = W.HANDLE
k32.OpenProcess.argtypes = [W.DWORD, W.BOOL, W.DWORD]
k32.CloseHandle.argtypes = [W.HANDLE]
k32.ReadProcessMemory.argtypes = [W.HANDLE, C.c_void_p, C.c_void_p, C.c_size_t, C.POINTER(C.c_size_t)]
k32.ReadProcessMemory.restype = W.BOOL
k32.GetExitCodeProcess.argtypes = [W.HANDLE, C.POINTER(W.DWORD)]
k32.GetExitCodeProcess.restype = W.BOOL
k32.QueryFullProcessImageNameW.argtypes = [W.HANDLE, W.DWORD, W.LPWSTR, C.POINTER(W.DWORD)]
k32.QueryFullProcessImageNameW.restype = W.BOOL
psapi.EnumProcessModulesEx.argtypes = [W.HANDLE, C.POINTER(W.HMODULE), W.DWORD, C.POINTER(W.DWORD), W.DWORD]
psapi.GetModuleBaseNameW.argtypes = [W.HANDLE, W.HMODULE, W.LPWSTR, W.DWORD]
u32.GetForegroundWindow.restype = W.HWND
u32.GetWindowThreadProcessId.argtypes = [W.HWND, C.POINTER(W.DWORD)]


def find_pids(exe=EXE):
    """the pids of the running game clients (a process snapshot: no process is opened)"""
    snap = k32.CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    if not snap or snap == W.HANDLE(-1).value:
        return []
    pe = PROCESSENTRY32W()
    pe.dwSize = C.sizeof(pe)
    out = []
    try:
        ok = k32.Process32FirstW(snap, C.byref(pe))
        while ok:
            if pe.szExeFile.lower() == exe.lower():
                out.append(pe.th32ProcessID)
            ok = k32.Process32NextW(snap, C.byref(pe))
    finally:
        k32.CloseHandle(snap)
    return out


def foreground_pid():
    """the pid owning the foreground window (only asked, nothing is done to the window)"""
    try:
        pid = W.DWORD()
        hwnd = u32.GetForegroundWindow()
        if hwnd:
            u32.GetWindowThreadProcessId(hwnd, C.byref(pid))
        return pid.value
    except Exception:  # noqa: BLE001
        return 0


class MEMORY_BASIC_INFORMATION(C.Structure):
    _fields_ = [("BaseAddress", C.c_void_p), ("AllocationBase", C.c_void_p), ("AllocationProtect", W.DWORD),
                ("PartitionId", W.WORD), ("RegionSize", C.c_size_t), ("State", W.DWORD), ("Protect", W.DWORD),
                ("Type", W.DWORD)]


k32.VirtualQueryEx.argtypes = [W.HANDLE, C.c_void_p, C.POINTER(MEMORY_BASIC_INFORMATION), C.c_size_t]
k32.VirtualQueryEx.restype = C.c_size_t
psapi.QueryWorkingSetEx.argtypes = [W.HANDLE, C.c_void_p, W.DWORD]
psapi.QueryWorkingSetEx.restype = W.BOOL
MEM_COMMIT, MEM_PRIVATE, PAGE_READWRITE = 0x1000, 0x20000, 0x04
PAGE = 0x1000


class ReadError(Exception):
    pass


class _GaveWay(RuntimeError):
    """NavMem.deck's paced read gave way (its lock let go and not taken again) - read again later"""


def ptr_ok(v):
    """a user-mode address (heap objects, and the exe's own sections at 0x7FF6...)"""
    return 0x10000 <= v < 0x7FFFFFFF0000


class Proc:
    """a read-only handle on one game process"""

    def __init__(self, pid):
        self.pid = pid
        self.access = PROCESS_VM_READ | PROCESS_QUERY_INFORMATION
        h = k32.OpenProcess(self.access, False, pid)
        if not h:
            self.access = PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION
            h = k32.OpenProcess(self.access, False, pid)
        if not h:
            raise OSError(C.get_last_error(), "OpenProcess failed")
        self.h = h

    def close(self):
        if self.h:
            k32.CloseHandle(self.h)
            self.h = None

    def alive(self):
        code = W.DWORD()
        return bool(self.h) and bool(k32.GetExitCodeProcess(self.h, C.byref(code))) and code.value == STILL_ACTIVE

    def image_path(self):
        buf, n = C.create_unicode_buffer(1024), W.DWORD(1024)
        return buf.value if k32.QueryFullProcessImageNameW(self.h, 0, buf, C.byref(n)) else ""

    def exe_base(self):
        mods, need = (W.HMODULE * 1)(), W.DWORD()
        if not psapi.EnumProcessModulesEx(self.h, mods, C.sizeof(mods), C.byref(need), LIST_MODULES_ALL) or not mods[0]:
            raise OSError(C.get_last_error(), "EnumProcessModulesEx failed")
        name = C.create_unicode_buffer(260)
        psapi.GetModuleBaseNameW(self.h, mods[0], name, 260)
        if name.value.lower() != EXE.lower():
            raise OSError(0, "first module is %r, not %s" % (name.value, EXE))
        return mods[0]

    def read(self, addr, n):
        buf, got = C.create_string_buffer(n), C.c_size_t()
        if not ptr_ok(addr) or not k32.ReadProcessMemory(self.h, C.c_void_p(addr), buf, n, C.byref(got)) or got.value != n:
            raise ReadError("read %d @ %#x failed" % (n, addr))
        return buf.raw[:n]

    def try_read(self, addr, n):
        try:
            return self.read(addr, n)
        except ReadError:
            return None

    def u64(self, a):
        return struct.unpack("<Q", self.read(a, 8))[0]

    def regions(self):
        """[(base, size)] of the game's committed private read-write memory - where its heap objects are"""
        out, addr, m = [], 0x10000, MEMORY_BASIC_INFORMATION()
        while addr < 0x7FFFFFFF0000:
            if not k32.VirtualQueryEx(self.h, C.c_void_p(addr), C.byref(m), C.sizeof(m)):
                if not out and addr == 0x10000:
                    raise ReadError("VirtualQueryEx failed (%d) - the game was opened without "
                                    "PROCESS_QUERY_INFORMATION" % C.get_last_error())
                break
            base, size = m.BaseAddress or 0, m.RegionSize
            if size <= 0:
                break
            if m.State == MEM_COMMIT and m.Type == MEM_PRIVATE and m.Protect == PAGE_READWRITE:
                out.append((base, size))
            addr = base + size
        return out

    def resident(self, base, size):
        """[(base, size)] runs of the pages of [base, base + size) that are in the game's working set (in RAM) -
        reading only those pages nothing in; the whole range if that can't be asked"""
        import numpy as np
        n = size // PAGE
        if n <= 0:
            return []
        runs = []
        for b0 in range(0, n, 0x10000):
            k = min(0x10000, n - b0)
            info = np.zeros(2 * k, dtype=np.uint64)
            info[0::2] = base + (b0 + np.arange(k, dtype=np.uint64)) * PAGE
            if not psapi.QueryWorkingSetEx(self.h, info.ctypes.data, info.nbytes):
                return [(base, size)]
            valid = (info[1::2] & 1).astype(bool)
            edges = np.flatnonzero(np.diff(np.concatenate(([False], valid, [False])).astype(np.int8)))
            for s, e in zip(edges[0::2], edges[1::2]):
                runs.append((base + (b0 + int(s)) * PAGE, int(e - s) * PAGE))
        return runs

    def read_pieces(self, base, size, piece=0x10000):
        """[(address, bytes)] of [base, base + size) read in pieces, the unreadable ones left out"""
        out = []
        for off in range(0, size, piece):
            raw = self.try_read(base + off, min(piece, size - off))
            if raw is not None:
                out.append((base + off, raw))
        return out

    def stable(self, addr, n, tries=6):
        """n bytes at addr, read until two reads in a row agree (a game thread may be writing them)"""
        prev = self.read(addr, n)
        for _ in range(tries):
            cur = self.read(addr, n)
            if cur == prev:
                return cur
            prev = cur
        raise ReadError("%d bytes @ %#x keep changing" % (n, addr))

    def string(self, a, stable=False):
        """an MSVC x64 std::string (16-byte inline buffer or a pointer, size @+0x10, capacity @+0x18) of
        printable ASCII, or None"""
        raw = self.stable(a, 0x20) if stable else self.read(a, 0x20)
        size, cap = struct.unpack_from("<QQ", raw, 0x10)
        if size > 0x1000 or cap < size or cap > 0x100000:
            return None
        if cap < 16:
            data = raw[:size]
        else:
            p = struct.unpack_from("<Q", raw)[0]
            data = (self.stable(p, size) if stable else self.read(p, size)) if size else b""
        s = data.decode("latin-1")
        return s if all(32 <= ord(ch) < 127 for ch in s) else None

    def try_string(self, a, stable=False):
        try:
            return self.string(a, stable)
        except ReadError:
            return None


class Module:
    """the game's exe image: its sections from the in-memory PE header"""

    def __init__(self, proc):
        self.p = proc
        self.base = proc.exe_base()
        hdr = proc.read(self.base, 0x1000)
        pe = struct.unpack_from("<I", hdr, 0x3C)[0]
        if hdr[:2] != b"MZ" or hdr[pe:pe + 4] != b"PE\0\0":
            raise OSError(0, "not a PE image")
        self.timestamp = struct.unpack_from("<I", hdr, pe + 8)[0]
        nsec = struct.unpack_from("<H", hdr, pe + 6)[0]
        optsz = struct.unpack_from("<H", hdr, pe + 20)[0]
        self.image_size = struct.unpack_from("<I", hdr, pe + 24 + 56)[0]
        self.sections = {}
        so = pe + 24 + optsz
        for _ in range(nsec):
            name = hdr[so:so + 8].rstrip(b"\0").decode("latin-1")
            vsize, va = struct.unpack_from("<II", hdr, so + 8)
            self.sections[name] = (va, vsize, struct.unpack_from("<I", hdr, so + 36)[0])
            so += 40

    @property
    def build(self):
        return "%08X-%X" % (self.timestamp, self.image_size)

    def in_section(self, addr, name):
        s = self.sections.get(name)
        return bool(s) and self.base + s[0] <= addr < self.base + s[0] + s[1]

    def code(self):
        """[(rva, bytes)] of the executable sections (unreadable pages as zeros)"""
        out = []
        for name, (va, vsize, chars) in self.sections.items():
            if chars & 0x20000000:
                parts = []
                for off in range(0, vsize, 0x100000):
                    n = min(0x100000, vsize - off)
                    parts.append(self.p.try_read(self.base + va + off, n) or b"\0" * n)
                out.append((va, b"".join(parts)))
        return out


LEA_RIP = re.compile(rb"[\x48\x4C]\x8D([\x05\x0D\x15\x1D\x25\x2D\x35\x3D])(....)", re.DOTALL)
TYPE_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_:<>, ]+")


class TypeNamer:
    """KingsIsle's reflected type names: vtable[0] of every PropertyClass is GetType(), whose body loads
    the class name with a RIP-relative LEA - the first one in its first 128 bytes that points at an
    identifier-like C string in .rdata (cached per vtable)"""

    def __init__(self, mod):
        self.m, self.p, self.cache = mod, mod.p, {}

    def of_vtable(self, vt):
        name = self.cache.get(vt, self)               # (one look: the objects thread may clear the cache meanwhile)
        if name is not self:
            return name
        name = None
        if self.m.in_section(vt, ".rdata"):
            f = self.p.try_read(vt, 8)
            fn = struct.unpack("<Q", f)[0] if f else 0
            b = self.p.try_read(fn, 5) if ptr_ok(fn) else None
            if b and b[0] == 0xE9:                              # incremental-link thunk
                fn = fn + 5 + struct.unpack_from("<i", b, 1)[0]
            if fn and self.m.in_section(fn, ".text"):
                for mt in LEA_RIP.finditer(self.p.try_read(fn, 128) or b""):
                    tgt = fn + mt.start() + 7 + struct.unpack("<i", mt.group(2))[0]
                    if self.m.in_section(tgt, ".rdata"):
                        raw = self.p.try_read(tgt, 96) or b""
                        s = raw.split(b"\0", 1)[0].decode("latin-1")
                        if s and TYPE_NAME.fullmatch(s):
                            name = s
                            break
        if len(self.cache) > 50000:
            self.cache.clear()
        self.cache[vt] = name
        return name

    def of(self, obj):
        b = self.p.try_read(obj, 8) if ptr_ok(obj) else None
        return self.of_vtable(struct.unpack("<Q", b)[0]) if b else None


# ============================================================================ signatures
# Each regex is matched in the game's code; captured int32s are RIP-relative displacements ("rip": resolved
# to an RVA; the displacement is the last 4 bytes of its instruction) or struct offsets ("off"; "u8" a
# one-byte offset). The hits' results are voted, then checked (see _Attached.resolve).
D = rb"(....)"
SIGS = {
    # mov rax,[rip+GameClient]; mov rax,[rax+ClientZone]; test rax,rax; je ..; lea rcx,[rax+name]
    "ZONE": (rb"\x48\x8B\x05" + D + rb"\x48\x8B\x80" + D + rb"\x48\x85\xC0(?:\x74.|\x0F\x84....)\x48\x8D\x48(.)",
             ("rip", "off", "u8")),
    # mov rax,[rip+GameClient]; mov rbx,rcx; cmp byte [rax+0x2xxxx],imm8 (wizwalker's, offset wildcarded)
    "GAMECLIENT": (rb"\x48\x8B\x05" + D + rb"\x48\x8B\xD9\x80\xB8..\x02\x00", ("rip",)),
    # the ClientObject location getter (the one wizwalker's PlayerHook patched):
    # mov rbx,[rcx+anim]; test; je; mov rax,[rbx+body]; ...; movsd xmm0,[rax+pos]; ...; movss [rcx+loc+4/8/0]
    "GETLOCATION": (rb"\x48\x8B\x99" + D + rb"\x48\x85\xDB\x74.\x48\x8B\x43(.)\x48\x8B\x5B.\x48\x85\xDB\x74."
                    rb"\xF0\xFF\x43\x08\x48\x85\xC0\x74.\xF2\x0F\x10\x40(.)\xF2\x0F\x11\x02\x8B\x40.\xEB."
                    rb"\xF3\x0F\x10\x91" + D + rb"\xF3\x0F\x10\x81" + D + rb"\xF3\x0F\x11\x44\x24.\xF3\x0F\x10\x89" + D,
                    ("off", "u8", "u8", "off", "off", "off")),
    # mov rax,[rip+GUIManager]; mov rcx,[rax+HUD]; (mov [..],rcx)?; mov rbx,[rax+HUD+8]  (copying the
    # SharedPointer<HUDWindow>) - many hits; the candidates are checked by the HUD's window name
    "GUIMGR_HUD": (rb"\x48\x8B\x05" + D + rb"[\x48\x4C]\x8B[\x80\x88\x90\x98\xA8\xB0\xB8]" + D +
                   rb"(?:[\x48\x4C]\x89(?:[\x45\x4D\x55\x5D\x65\x6D\x75\x7D].|[\x44\x4C\x54\x5C\x64\x6C\x74\x7C]\x24.|"
                   rb"[\x85\x8D\x95\x9D\xA5\xAD\xB5\xBD]....)|[\x48\x4C]\x8B[\xC0-\xFF])?"
                   rb"[\x48\x4C]\x8B[\x80\x88\x90\x98\xA8\xB0\xB8]" + D, ("rip", "off", "off")),
    # lea rdi,[r14+slot]; cmp qword [rdi],0; jne ..; mov ecx,sizeof(QuestHelperHud); call new
    "HUD_QHH": (rb"\x49\x8D\xBE" + D + rb"\x48\x83\x3F\x00\x75.\xB9" + D + rb"\xE8", ("off", "off")),
    # call QuestHelperThread::ctor; jmp; mov rax,rdi; mov [rsi+slot],rax; xor r8d,r8d; mov dl,1
    "QHH_THREAD": (rb"\xE8....\xEB\x03\x48\x8B\xC7\x48\x89\x86" + D + rb"\x45\x33\xC0\xB2\x01\x48\x8B\xC8\xE8",
                   ("off",)),
    # movss xmm0,[r15+goal]; movss [rbp-..],xmm0; movss xmm1,[r15+goal+4]; ...; +8  (wizwalker's QuestHook spot)
    "GOAL": (rb"\xF3\x41\x0F\x10[\x80-\xBF]" + D + rb"\xF3\x0F\x11\x45.\xF3\x41\x0F\x10[\x80-\xBF]" + D +
             rb"\xF3\x0F\x11\x4D.\xF3\x41\x0F\x10[\x80-\xBF]" + D + rb"\xF3\x0F\x11\x45.\x48\x8B\x4D.\x48\x85\xC9\x74",
             ("off", "off", "off")),
    # mov ecx,[r15+hops]; mov [rax+18h],ecx; imul eax,[r15+hops],10000
    "HOPS": (rb"\x41\x8B[\x80-\xBF]" + D + rb"\x89\x48\x18\x41\x69[\x80-\xBF]" + D + rb"\x10\x27\x00\x00",
             ("off", "off")),
    # QuestHelperThread::OnUpdateZoneInfo: lea rcx,[rdi+nav]; ...; lea rcx,[rdi+zone]; ...;
    #   mov eax,[rbx+30h]; mov [rdi+..],eax; movsd xmm0,[rbx+34h]; movsd [rdi+player],xmm0
    "ZONEINFO": (rb"\x48\x8D\x8F" + D + rb"\x48\x8B\xD3\xE8....\x4C\x8D\x43\x10\x48\x8D\x8F" + D +
                 rb".{10,40}?\x8B\x43\x30\x89\x87....\xF2\x0F\x10\x43\x34\xF2\x0F\x11\x87" + D,
                 ("off", "off", "off")),
    # QuestHelperThread::FindPathToClosestGoal's start: cmp byte [rcx+enabled],r12b; je; mov rax,[rcx+nav];
    # test rax,rax; je  (nav must be ZONEINFO's)
    "ENABLED": (rb"[\x40-\x4F]\x38[\x80-\xBF]" + D + rb"\x0F\x84....[\x48\x49]\x8B[\x80-\xBF]" + D + rb"\x48\x85\xC0\x0F\x84",
                ("off", "off")),
    # lea rcx,[r15+path]; call SharedPointer copy; mov ecx,50h; call new (the HUD message)
    "PATH": (rb"\x49\x8D\x8F" + D + rb"\xE8....\xB9\x50\x00\x00\x00\xE8", ("off",)),
    # mov rax,[r15+quest]; mov rcx,[rbp-..]; test rcx,rcx; je +9; cmp rax,[rcx+..]
    "ACTIVE_QUEST": (rb"\x49\x8B\x87" + D + rb"\x48\x8B\x4D.\x48\x85\xC9\x74\x09\x48\x3B\x81", ("off",)),
    # mov rcx,[r15+goal]; cmp rbx,rcx; je ..; mov rax,[rbp-..]; mov [rax],rcx
    "ACTIVE_GOAL": (rb"\x49\x8B\x8F" + D + rb"\x48\x3B\xD9\x74.\x48\x8B\x45.\x48\x89\x08", ("off",)),
    # QuestHelperHud::ThreadUpdateCallback copying the thread's message (hops, cost, distance, target)
    "HUD_FIELDS": (rb"\x48\x8B\x07\x8B\x48\x18\x89\x8B" + D + rb"\x48\x8B\x07\x8B\x48\x1C\x89\x8B" + D +
                   rb"\x48\x8B\x07\x8B\x48\x20\x89\x8B" + D +
                   rb"\x48\x8B\x07\xF3\x0F\x10\x40\x30\xF3\x0F\x10\x48\x2C.{5}\xF3\x0F\x10\x50\x28\x0F\x14\xD1"
                   rb"\xF2\x0F\x11\x93" + D, ("off", "off", "off", "off")),
}

# Offsets of objects that are checked by a name before use (so these are tried, never trusted): the
# client of 2026-10-13, build KNOWN_BUILD (PE timestamp - image size). In that build a failed check means
# the object isn't there now (login screen, loading); in another one the object is also looked for by name
KNOWN_BUILD = "6A9721E9-370E000"
KNOWN = {"gameclient_rva": 0x3320FF0, "guimgr_rva": 0x3322460, "gm_hud": 0x2D0, "hud_qhh": 0x6A8,
         "qhh_thread": 0x2C8, "gc_elastic_cam": 0x222C8, "cam_attached_object": 0x108, "gc_zone": 0x21368}
# Data offsets that every object of the kind carries (not tied to a signature; seen on every object)
DATA = {"window_name": 0x50, "thread_name": 0xB0, "navnode_pos": 0x30, "list_value": 0x10,
        "body_parent": 0x48, "co_orientation_after_location": 0xC,
        "co_gid": 0x48, "co_template": 0x58, "co_zone": 0x130, "tpl_name": 0x60, "tpl_display": 0xA8,
        "tpl_school": 0x1C8}
# The zone's objects (the mobs): the heap read in pieces this big; quick looks (where objects were found) every
# OBJ_QUICK s, all of it every OBJ_FULL s and on a new zone; the thread stops when nobody's asked for OBJ_IDLE s
SCAN_CHUNK = 0x400000
OBJ_QUICK, OBJ_FULL, OBJ_IDLE, OBJ_SETTLE, OBJ_SETTLE_EVERY = 3.0, 15.0, 120.0, 20.0, 5.0
OBJ_SPAN = 0x138                     # an object read from +0 to past its zone pointer (+0x130)
MOB_KEY = re.compile(r"^(\w*Mobs)_(\d+)$")
MOB_TABLES = ("WizardMobs", "Mobs")
# a thing lying about the zone that a quest has you collect (Piece Of Coral: CL-Coral-Object, WizItems_00001638) -
# its template's display key is in the items name table
ITEM_KEY = re.compile(r"^(WizItems)_(\d+)$")
ITEM_TABLES = ("WizItems",)
# any other thing of the zone with a name: its display key a name-table key ("<table>_<...>"), its kind by the table -
# an NPC's (WizardNPC, NPCs, WC-NPCs, KT-NPCs...), a mob's name on something that doesn't fight (ambient: DM-Ambient-*
# 'Veggie Revanant', a teleporter named after a mob), any other an object a quest may have you use, open, read
# (WizQst371C7_00000008 Inactive Protector, WizardGameObjects_00000344 Celestian Monolith)
THING_KEY = re.compile(r"^([A-Za-z][A-Za-z0-9-]*)_(\S+)$")
NPC_TABLE = re.compile(r"^(WizardNPC|NPCs|[A-Za-z0-9]+-NPCs)$")


def thing_kind(key):
    """what a thing's display key says it is: "item" (WizItems), "npc", "ambient" (a *Mobs key), "object" (any other
    name-table key), "" (none - a Basic Positional, the Player Object, a duel circle: not a thing)"""
    m = THING_KEY.match(key or "")
    if not m:
        return ""
    t = m.group(1)
    return ("ambient" if MOB_KEY.match(key) else "item" if t in ITEM_TABLES else "npc" if NPC_TABLE.match(t)
            else "object")


_BLOCKER_FN = []


def _is_blocker(name):
    """puzzlefile.is_blocker (a door's, a gate's, a collision wall's template name) - imported on first use (puzzlefile
    imports navgeo - numpy - which the rest of navmem doesn't need); False when it can't be"""
    if not _BLOCKER_FN:
        try:
            import puzzlefile
            _BLOCKER_FN.append(puzzlefile.is_blocker)
        except Exception:  # noqa: BLE001 - no blockers, the rest as before
            _BLOCKER_FN.append(lambda n: False)
    return _BLOCKER_FN[0](name)


def scan(code):
    """{signature: [result tuple, most voted first]}"""
    res = {}
    for name, (pat, kinds) in SIGS.items():
        rx = re.compile(pat, re.DOTALL)
        votes = Counter()
        for va, data in code:
            for m in rx.finditer(data):
                vals = []
                for g, k in enumerate(kinds, 1):
                    raw = m.group(g)
                    if k == "rip":
                        vals.append(va + m.start(g) + 4 + struct.unpack("<i", raw)[0])
                    elif k == "u8":
                        vals.append(raw[0])
                    else:
                        vals.append(struct.unpack("<i", raw)[0])
                votes[tuple(vals)] += 1
        res[name] = [k for k, _ in votes.most_common()]
    return res


def finite(*v):
    return all(isinstance(x, float) and math.isfinite(x) and abs(x) < 1e7 for x in v)


# A goal the game shows no way to (USAGE "Use Inactive Protector in District of the Stars (0 of 3)", 2026-10-25; "Collect
# Piece Of Coral in The Grotto", 2026-10-23) reads: the quest helper thread on the client's zone, enabled, its goal
# exactly (0, 0, 0) with hops 0, and the HUD's arrow distance -1 with hops 0 - quest() drops that goal as no place, the
# same as one it couldn't read; noplace_of tells the two apart
NOPLACE_ZERO = 1e-3


def _num(*v):
    return all(isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x) and abs(x) < 1e7 for x in v)


def _zero3(v):
    return v is not None and len(v) == 3 and _num(*v) and all(abs(c) <= NOPLACE_ZERO for c in v)


def noplace_of(raw):
    """1 / 0 / None from one reading's raw quest fields - raw: {same_zone, enabled, th_goal (x, y, z) | None, th_hops,
    hud_target, hud_dist, hud_hops}:
        1     no place: the same zone, enabled 1, the thread's goal exactly (0, 0, 0) and hops 0, the HUD's distance < 0
              and its hops 0 - every one of them read
        0     a place: the thread's goal finite, not (0, 0, 0), 0 <= hops < 1000 - exactly what quest() takes as the goal
        None  not known: another zone (the thread not caught up), the quest helper off, a field not read (a signature
              missing in this build), or a mix (the goal (0, 0, 0) while the HUD still shows a distance: a goal change
              caught between the thread's update and the HUD's)
    A goal with a place can't read 1 (it has hops > 0 - the way out of this zone -, or a goal that isn't (0, 0, 0)), but
    a goal change or a zone arrival can pass through all zeros for a moment: NoPlaceHold times how long 1 has held"""
    if not raw.get("same_zone"):
        return None
    g, h = raw.get("th_goal"), raw.get("th_hops")
    if g is not None and len(g) == 3 and _num(*g) and _num(h) and 0 <= h < 1000 and not _zero3(g):
        return 0
    if raw.get("enabled") != 1:
        return None
    d, hh = raw.get("hud_dist"), raw.get("hud_hops")
    if _zero3(g) and h == 0 and _num(d) and d < 0 and hh == 0:
        return 1
    return None


class NoPlaceHold:
    """how long noplace 1 has held for the same (quest, goal id): 0.0 at the reading it starts; None when it isn't 1"""

    def __init__(self):
        self.key, self.since = None, None

    def update(self, key, noplace, now=None):
        now = time.monotonic() if now is None else now
        if noplace != 1:
            self.key, self.since = None, None
            return None
        if key != self.key or self.since is None:
            self.key, self.since = key, now
        return now - self.since


# ============================================================================ one attached game
class _Attached:
    """the game process with pid, its signatures resolved (once: they hold for the process's lifetime)"""

    RESCAN_EVERY = 10.0      # s between name scans for an object whose known place failed

    def __init__(self, pid, log):
        self.log = log
        self._next_scan = {}
        t0 = time.perf_counter()
        self.p = Proc(pid)
        try:
            self.m = Module(self.p)
            self.tn = TypeNamer(self.m)
            self.how = {}
            self.o = {}
            code = self.m.code()
            self.scan_s = time.perf_counter() - t0
            self.sig = scan(code)
            del code
            self.resolve()
        except Exception:
            self.p.close()
            raise
        self.attach_s = time.perf_counter() - t0

    def close(self):
        self.p.close()

    def alive(self):
        return self.p.alive()

    # ------------------------------------------------------------ resolving (once per process)
    def _first(self, name, check=None):
        for cand in self.sig.get(name, []):
            try:
                if check is None or check(cand):
                    return cand
            except (IndexError, TypeError, ReadError):
                pass
        return None

    def _gameclient_ok(self, rva):
        """a GameClient static: it points at an object readable 0x20000 in"""
        b = self.p.try_read(self.m.base + rva, 8)
        gc = struct.unpack("<Q", b)[0] if b else 0
        return ptr_ok(gc) and self.p.try_read(gc + 0x20000, 8) is not None

    def resolve(self):
        o, how = self.o, self.how
        # GameClient and the zone name
        z = self._first("ZONE", lambda c: self._gameclient_ok(c[0]))
        if z:
            o["gameclient_rva"], o["gc_zone"], o["zone_name"] = z
            how["gameclient"] = "sig ZONE"
        else:
            g = self._first("GAMECLIENT", lambda c: self._gameclient_ok(c[0]))
            if not g:
                raise LookupError("the GameClient signature isn't in this game build (%s)" % self.m.build)
            o["gameclient_rva"] = g[0]
            o["gc_zone"], o["zone_name"] = None, 0x58     # gc_zone found by its type name on first read
            how["gameclient"] = "sig GAMECLIENT"
        # the wizard's location
        loc = self._first("GETLOCATION", lambda c: c[3] == c[5] + 4 and c[4] == c[5] + 8)   # y, z, x
        if not loc:
            raise LookupError("the location signature isn't in this game build (%s)" % self.m.build)
        o["co_anim"], o["anim_body"], o["body_pos"], o["co_location"] = loc[0], loc[1], loc[2], loc[5]
        how["location"] = "sig GETLOCATION"
        o["gc_elastic_cam"] = o["cam_attached_object"] = None     # checked by type name on read
        # the quest helper (each one may be missing: those fields are then left empty)
        o["gm_candidates"] = [(c[0], c[1]) for c in self.sig.get("GUIMGR_HUD", []) if c[2] == c[1] + 8][:16]
        if (KNOWN["guimgr_rva"], KNOWN["gm_hud"]) not in o["gm_candidates"]:
            o["gm_candidates"].append((KNOWN["guimgr_rva"], KNOWN["gm_hud"]))
        o["gm"] = None                                              # (rva, hud offset) once a HUD is named
        # (either signature not in this build - neither is in 6AF1C8A0-3B69000, 2026-11-12: the known slot instead, which
        # quest() never trusts - checked by the window / thread name it must carry, and in another build looked for by
        # that name when the check fails - so one changed instruction doesn't cost the quest helper)
        by_name = []
        c = self._first("HUD_QHH")
        o["hud_qhh"] = c[0] if c else KNOWN["hud_qhh"]
        if not c:
            by_name.append("hud_qhh")
        c = self._first("QHH_THREAD")
        o["qhh_thread"] = c[0] if c else KNOWN["qhh_thread"]
        if not c:
            by_name.append("qhh_thread")
        c = self._first("GOAL", lambda c: c[1] == c[0] + 4 and c[2] == c[0] + 8)
        o["th_goal"] = c[0] if c else None
        c = self._first("HOPS", lambda c: c[0] == c[1])
        o["th_hops"] = c[0] if c else None
        c = self._first("ZONEINFO")
        o["th_nav"], o["th_zone"] = (c[0], c[1]) if c else (None, None)
        c = self._first("ENABLED", lambda c: o["th_nav"] is not None and c[1] == o["th_nav"])
        o["th_enabled"] = c[0] if c else None
        c = self._first("PATH")
        o["th_path"] = c[0] if c else None
        c = self._first("ACTIVE_QUEST")
        o["th_quest"] = c[0] if c else None
        c = self._first("ACTIVE_GOAL")
        o["th_goalid"] = c[0] if c else None
        c = self._first("HUD_FIELDS", lambda c: len(set(c)) == 4)
        o["hud_hops"], o["hud_cost"], o["hud_dist"], o["hud_arrow"] = c if c else (None,) * 4
        missing = [k for k in ("hud_qhh", "qhh_thread", "th_goal", "th_hops", "th_zone", "th_enabled", "th_path",
                               "th_quest", "th_goalid", "hud_arrow") if o[k] is None]
        how["quest"] = ("all signatures found" if not missing else "missing: " + ", ".join(missing)) + (
            "; no signature, found by name: " + ", ".join(by_name) if by_name else "")

    def describe(self):
        o = self.o
        hx = lambda v: "?" if v is None else ("%#x" % v if isinstance(v, int) else str(v))     # ? = checked on read
        keys = ("gameclient_rva", "gc_zone", "zone_name", "gc_elastic_cam", "cam_attached_object", "co_anim",
                "anim_body", "body_pos", "co_location", "gm", "hud_qhh", "qhh_thread", "th_enabled", "th_quest",
                "th_goalid", "th_zone", "th_goal", "th_hops", "th_path", "hud_arrow", "hud_dist", "hud_hops")
        gm = o.get("gm")
        parts = [k + "=" + (("%#x+%#x" % gm) if k == "gm" and gm else hx(o.get(k))) for k in keys]
        return ("pid %d build %s, %.2f s (code read %.2f s); %s; %s; %s" %
                (self.p.pid, self.m.build, self.attach_s, self.scan_s, self.how.get("gameclient"),
                 self.how.get("location"), self.how.get("quest")) + "\n  " + " ".join(parts))

    # ------------------------------------------------------------ helpers
    def _due(self, key):
        """True at most once per RESCAN_EVERY for key (a name scan that may be slow)"""
        now = time.monotonic()
        if now < self._next_scan.get(key, 0):
            return False
        self._next_scan[key] = now + self.RESCAN_EVERY
        return True

    def _typed(self, obj, off, accept):
        """the pointer at obj+off if its type name passes accept, else 0"""
        b = self.p.try_read(obj + off, 8)
        v = struct.unpack("<Q", b)[0] if b else 0
        if ptr_ok(v):
            n = self.tn.of(v)
            if n and accept(n):
                return v
        return 0

    def _scan_typed(self, obj, size, accept):
        """the first offset in obj (size bytes) holding a pointer whose type name passes accept"""
        for base in range(0, size, 0x1000):
            blob = self.p.try_read(obj + base, min(0x1000, size - base))
            if blob is None:
                break
            for i in range(0, len(blob) - 7, 8):
                v = struct.unpack_from("<Q", blob, i)[0]
                if ptr_ok(v):
                    n = self.tn.of(v)
                    if n and accept(n):
                        return base + i
        return None

    def is_client_object(self, v):
        """v is a live ClientObject: its type name (from its vtable) ends ClientObject - a destroyed one's vtable is
        its base class's (it reads PropertyClass), its memory otherwise much as it was"""
        if not ptr_ok(v):
            return False
        n = self.tn.of(v)
        return bool(n) and n.endswith("ClientObject")

    def _object_at(self, obj, off):
        """the pointer at obj+off if it's a ClientObject, else 0"""
        b = self.p.try_read(obj + off, 8)
        v = struct.unpack("<Q", b)[0] if b else 0
        return v if self.is_client_object(v) else 0

    def _scan_objects(self, obj, size):
        """the first offset in obj (size bytes) holding a ClientObject"""
        raw = self.p.try_read(obj, size)
        if raw is None:
            return None
        for i in range(0, size - 7, 8):
            if self.is_client_object(struct.unpack_from("<Q", raw, i)[0]):
                return i
        return None

    def _named(self, obj, off, name_off, name):
        """the pointer at obj+off if the object's name string (at name_off) is name, else 0"""
        b = self.p.try_read(obj + off, 8)
        v = struct.unpack("<Q", b)[0] if b else 0
        return v if ptr_ok(v) and self.p.try_string(v + name_off) == name else 0

    def _scan_named(self, obj, size, name_off, name):
        raw = self.p.try_read(obj, size)
        if raw is None:
            return None
        for i in range(0, size - 7, 8):
            v = struct.unpack_from("<Q", raw, i)[0]
            if ptr_ok(v) and self.p.try_string(v + name_off) == name:
                return i
        return None

    def _member(self, key, parent, find, size, check):
        """the object at parent + o[key]: the known offset first (KNOWN), else one found by a scan of
        parent (at most every RESCAN_EVERY s); a found offset is kept for the process's lifetime"""
        o = self.o
        if o.get(key) is not None:
            return check(parent, o[key])
        v = check(parent, KNOWN[key]) if key in KNOWN else 0
        if v:
            o[key] = KNOWN[key]
            self.how[key] = "known offset, checked"
            return v
        if self.m.build == KNOWN_BUILD or not self._due(key):
            return 0
        off = find(parent, size)
        if off is not None:
            v = check(parent, off)
            if v:
                o[key] = off
                self.how[key] = "found by name"
                self.log("navmem: %s found at +%#x" % (key, off))
                return v
        return 0

    # ------------------------------------------------------------ reading
    def gameclient(self):
        return self.p.u64(self.m.base + self.o["gameclient_rva"])

    def zone(self, gc):
        o = self.o
        if o["gc_zone"] is None:
            o["gc_zone"] = self._scan_typed(gc, 0x30000, lambda n: n == "ClientZone") if self._due("gc_zone") else None
            if o["gc_zone"] is None:
                return None
        cz = self.p.u64(gc + o["gc_zone"])
        return self.p.try_string(cz + o["zone_name"], stable=True) if ptr_ok(cz) else None

    def player(self, gc):
        """{pos (x, y, z), yaw, source} or None, why"""
        p, o = self.p, self.o
        is_cam = lambda n: n == "ElasticCamController"
        cam = self._member("gc_elastic_cam", gc,
                           lambda obj, size: self._scan_typed(obj, size, is_cam), 0x30000,
                           lambda obj, off: self._typed(obj, off, is_cam))
        if not cam:
            return None, "no camera controller (not in the game world)"
        co = self._member("cam_attached_object", cam, self._scan_objects, 0x400, self._object_at)
        if not co:
            return None, "the camera follows no object"
        anim = p.u64(co + o["co_anim"])
        body = p.u64(anim + o["anim_body"]) if ptr_ok(anim) else 0
        if ptr_ok(body) and p.try_read(body + DATA["body_parent"], 8) == struct.pack("<Q", co):
            raw, src = p.stable(body + o["body_pos"], 24), "body"
        else:                                    # no body (zoning): the object's own copy
            raw, src = p.stable(co + o["co_location"], 24), "object"
        x, y, z, pitch, roll, yaw = struct.unpack("<6f", raw)
        if not finite(x, y, z, yaw):
            return None, "the position isn't a number"
        yaw = (yaw + math.pi) % (2 * math.pi) - math.pi
        return {"pos": (x, y, z), "yaw": yaw, "source": src}, ""

    def player_gid(self, gc):
        """the wizard's own global id - the object the camera follows (player()'s), its +0x48 - or None (a duel circle's
        participant whose owner it is: his own battle)"""
        is_cam = lambda n: n == "ElasticCamController"
        cam = self._member("gc_elastic_cam", gc,
                           lambda obj, size: self._scan_typed(obj, size, is_cam), 0x30000,
                           lambda obj, off: self._typed(obj, off, is_cam))
        if not cam:
            return None
        co = self._member("cam_attached_object", cam, self._scan_objects, 0x400, self._object_at)
        return (self.p.u64(co + DATA["co_gid"]) or None) if co else None

    def zone_ptr(self, gc):
        """the ClientZone the game is in (every object of the zone holds it at +0x130), or 0"""
        if self.o.get("gc_zone") is None:
            return 0
        cz = self.p.u64(gc + self.o["gc_zone"])
        return cz if ptr_ok(cz) and self.tn.of(cz) == "ClientZone" else 0

    def scan_objects(self, cz, regions=None):
        """([addresses of the objects holding cz at +0x130], [(base, size) of the regions they were in]) - in
        regions, or all of the game's heap (only its pages in RAM)"""
        import numpy as np                          # (only here: the rest of navmem doesn't need it)
        needle = np.uint64(cz)
        found, where = [], []
        for base, size in (regions if regions is not None else self.p.regions()):
            hit = False
            for rb, rs in self.p.resident(base, size):
                for off in range(0, rs, SCAN_CHUNK):
                    n = min(SCAN_CHUNK, rs - off)
                    raw = self.p.try_read(rb + off, n)
                    parts = [(rb + off, raw)] if raw is not None else self.p.read_pieces(rb + off, n)
                    for at, data in parts:
                        idx = np.flatnonzero(np.frombuffer(data, dtype=np.uint64, count=len(data) // 8) == needle)
                        if len(idx):
                            hit = True
                            found.extend(at + int(i) * 8 - DATA["co_zone"] for i in idx)
            if hit:
                where.append((base, size))
        return found, where

    def template_kind(self, tpl, names, cache):
        """(mob name or "", template name, item name or "", display key or "", kind) of a template - kind "mob": one that
        fights (a school - Fire, Storm...: +0x1C8 is WizGameObjectTemplate's m_primarySchoolName, read only on a Wiz*
        template), its name "" unless its display key is in one of the *Mobs name tables (names: {key: English name})
        with a name (a wisp has none; a teleporter can borrow a mob's name - Wormguts Tower - and has no school);
        else thing_kind's: "item" (the items table - its name from names), "ambient" (a *Mobs key - its name from
        names), "npc" / "object" (other tables: the name "" here - the objects thread looks it up), "" (no key: not a
        thing). None if tpl isn't a template (cached per template)"""
        if tpl in cache:
            return cache[tpl]
        k = None
        tname = self.tn.of(tpl) if ptr_ok(tpl) else None
        if tname and tname.endswith("Template"):
            key = self.p.try_string(tpl + DATA["tpl_display"]) or ""
            tn = self.p.try_string(tpl + DATA["tpl_name"]) or ""
            school = (self.p.try_string(tpl + DATA["tpl_school"]) or "").strip() if tname.startswith("Wiz") else ""
            if school:
                k = ((names.get(key) or "") if MOB_KEY.match(key) else "", tn, "", key, "mob")
            else:
                kind = thing_kind(key)
                k = ("", tn, (names.get(key) or "") if kind in ("item", "ambient") else "", key if kind else "", kind)
        if len(cache) > 20000:
            cache.clear()
        cache[tpl] = k
        return k

    def _group(self, base, fields):
        """{name: value} of fields {name: (offset, struct format)} at base, the whole span read until two
        reads agree (one span: they were written together)"""
        lo = min(off for off, f in fields.values())
        hi = max(off + struct.calcsize("<" + f) for off, f in fields.values())
        raw = self.p.stable(base + lo, hi - lo)
        out = {}
        for k, (off, f) in fields.items():
            v = struct.unpack_from("<" + f, raw, off - lo)
            out[k] = v[0] if len(v) == 1 else v
        return out

    def quest(self, gc_zone, want_path):
        """{enabled, quest, goalid, goal, hops, target, dist, path, thread_zone} (each None when it can't be
        read for sure) or None, why"""
        p, o = self.p, self.o
        wn, tn = DATA["window_name"], DATA["thread_name"]
        hud = 0
        if o["gm"] is not None:
            rva, off = o["gm"]
            gm = p.try_read(self.m.base + rva, 8)
            hud = self._named(struct.unpack("<Q", gm)[0], off, wn, "windowHUD") if gm else 0
        else:
            for rva, off in o["gm_candidates"]:
                gm = p.try_read(self.m.base + rva, 8)
                hud = self._named(struct.unpack("<Q", gm)[0], off, wn, "windowHUD") if gm else 0
                if hud:
                    o["gm"] = (rva, off)
                    self.how["gm"] = "sig GUIMGR_HUD, named windowHUD"
                    break
        if not hud:
            return None, "no HUD (not in the game world)"
        if o["hud_qhh"] is None or o["qhh_thread"] is None:
            return None, "the quest helper's signatures aren't in this build"
        qhh = self._named(hud, o["hud_qhh"], wn, "QuestHelperHud")
        if not qhh:
            # (the slot moved in a build where the signature still matched something else)
            if self.m.build != KNOWN_BUILD and self._due("hud_qhh"):
                off = self._scan_named(hud, 0xD00, wn, "QuestHelperHud")
                if off is not None:
                    o["hud_qhh"] = off
                    qhh = self._named(hud, off, wn, "QuestHelperHud")
            if not qhh:
                return None, "no quest helper on the HUD"
        th = self._named(qhh, o["qhh_thread"], tn, "QuestHelper")
        if not th:
            if self.m.build != KNOWN_BUILD and self._due("qhh_thread"):
                off = self._scan_named(qhh, 0x450, tn, "QuestHelper")
                if off is not None:
                    o["qhh_thread"] = off
                    th = self._named(qhh, off, tn, "QuestHelper")
            if not th:
                return None, "no quest helper thread"
        r = dict.fromkeys(("enabled", "quest", "goalid", "goal", "hops", "target", "dist", "path", "thread_zone",
                           "noplace"))
        ids = {k: v for k, v in (("enabled", (o["th_enabled"], "B")), ("quest", (o["th_quest"], "Q")),
                                 ("goalid", (o["th_goalid"], "Q"))) if v[0] is not None}
        if ids:
            r.update(self._group(th, ids))
        if o["th_zone"] is not None:
            r["thread_zone"] = p.try_string(th + o["th_zone"], stable=True)
        same_zone = r["thread_zone"] is not None and gc_zone is not None and r["thread_zone"] == gc_zone
        if not same_zone:
            return r, "the quest helper is still on zone %r" % r["thread_zone"]
        # (the fields as read, for noplace_of only - not handed out)
        raw = {"same_zone": True, "enabled": r["enabled"], "th_goal": None, "th_hops": None, "hud_target": None,
               "hud_dist": None, "hud_hops": None}
        if o["th_goal"] is not None and o["th_hops"] is not None:
            g = self._group(th, {"goal": (o["th_goal"], "3f"), "hops": (o["th_hops"], "i")})
            raw["th_goal"], raw["th_hops"] = tuple(g["goal"]), g["hops"]
            # (a goal the game shows no way to - collect things lying about the zone, 2026-10-23 Piece Of Coral: no arrow,
            # the goal at exactly 0, 0, 0 - is no place: not read as one, else the walker stands "at" it)
            if finite(*g["goal"]) and 0 <= g["hops"] < 1000 and any(abs(v) > 1e-3 for v in g["goal"]):
                r["goal"], r["hops"] = g["goal"], g["hops"]
        if o["hud_arrow"] is not None:
            h = self._group(qhh, {"target": (o["hud_arrow"], "3f"), "dist": (o["hud_dist"], "f"),
                                  "hops": (o["hud_hops"], "i")})
            raw["hud_target"], raw["hud_dist"], raw["hud_hops"] = tuple(h["target"]), h["dist"], h["hops"]
            # (the arrow is the thread's message as of its last update: only while it has the same hops)
            if (r["hops"] is not None and h["hops"] == r["hops"] and finite(*h["target"]) and finite(h["dist"])
                    and h["dist"] >= 0 and any(abs(v) > 1e-3 for v in h["target"])):
                r["target"], r["dist"] = h["target"], h["dist"]
        # (no place at all - the game shows no way to the goal: 1; a place: 0; not known: None - noplace_of)
        r["noplace"] = noplace_of(raw)
        if want_path and o["th_path"] is not None:
            r["path"] = self.path(th)
        return r, ""

    def path(self, th, limit=2000):
        """the thread's path: [(x, y, z)] in the game's order, read until two reads agree, or None"""
        p = self.p
        prev = None
        for _ in range(4):
            try:
                cur = self._path_once(th, limit)
            except ReadError:
                cur = None
            if cur is not None and cur == prev:
                return cur
            prev = cur
        return None

    def _path_once(self, th, limit):
        p = self.p
        sp = p.u64(th + self.o["th_path"])
        if not ptr_ok(sp):
            return []
        head, cnt = struct.unpack("<QQ", p.read(sp, 16))
        if not ptr_ok(head) or cnt > limit:
            return None
        pts, n = [], p.u64(head)
        while n != head:
            if len(pts) >= cnt or not ptr_ok(n):
                return None
            nxt, _prev, node = struct.unpack("<QQQ", p.read(n, 24))
            if not ptr_ok(node):
                return None
            x, y, z = struct.unpack("<3f", p.read(node + DATA["navnode_pos"], 12))
            if not finite(x, y, z):
                return None
            pts.append((x, y, z))
            n = nxt
        return pts if len(pts) == cnt else None


def _worn_misfit(every, worn):
    """why every deck's kept reading (NavMem._deck_all's r) no longer answers beside a newer worn-deck reading (worn's r),
    "" when it does: another character logged in on the same game (player_gid), a deck worn that it hasn't (new, or
    another character's), or one holding a card its copy there hasn't (a spell put in since - edited). Counts and cards
    gone aren't judged: a battle uses treasure cards up, and deckmem can't always tell a known spell's treasure card
    from the spell (the same template, side "main"), so they'd read as edits after every battle; an edit that only takes
    cards out stays unseen till every deck is read again (DeckLearnTick, 30 min). A deck whose cards weren't read (ok
    False) in either isn't judged"""
    pe, pw = every.get("player_gid"), worn.get("player_gid")
    if pe is not None and pw is not None and pe != pw:
        return "another character"
    have = {d.get("gid"): d for d in every.get("decks") or []}
    for d in worn.get("decks") or []:
        if not d.get("equipped") or d.get("ok") is False:
            continue
        k = have.get(d.get("gid"))
        if k is None:
            return "a deck worn it hasn't"
        if k.get("ok") is not False and {c.get("template_id") for c in d.get("cards") or []} - \
                {c.get("template_id") for c in k.get("cards") or []}:
            return "a deck worn edited since"
    return ""


# ============================================================================ the reader
class NavMem:
    """Attaches to the game (the foreground client if there are several), re-attaching when it is
    restarted; read() never raises. Thread-safe."""

    # s before attaching to the same pid again after it failed: it couldn't be opened or read (the game
    # starting up, or run as administrator) / a signature isn't in its code (that won't change while it runs)
    RETRY_READ, RETRY_SIG = 5.0, 300.0

    def __init__(self, log=None, pin=None):
        self.log = log or (lambda msg: None)
        # (pin: this client's pid alone - the bot's carry mode, two clients: one reader each - vision.py nav_reader)
        self.pin = pin or None
        self.lock = threading.Lock()
        self.st = None
        self.game_dir = ""
        self._thread = None
        self._failed = (0, 0.0, "")      # pid, when to try again, why
        self._last_why = None
        # the zone's mobs (the objects thread): {object address: (gid, name, template name, vtable)}, the zone they're
        # of, why there are none, when last asked for, the English names of the *Mobs tables (and the items table);
        # the zone's other things with a name (an item a quest has you collect, an object to use, an NPC...): {object
        # address: (gid, name - "" while its table isn't read -, template name, vtable, display key, kind)}
        self._objs, self._obj_cz, self._obj_why, self._obj_asked = {}, 0, "not looked yet", 0.0
        self._items = {}
        # (the zone's doors, gates and collision walls - no name key, a blocker's template name: {object address: (gid,
        # template name, template name, vtable)})
        self._blockers = {}
        # (the zone's duel circles - no name key, a duel behaviour (bossmem.is_duel_object): {object address: (gid, template
        # name, template name, vtable)}; each object looked at once {(object, gid, vtable): duel or not}; when duels() was
        # last asked for - only then are objects looked at for them: the duelavoid setting)
        self._duels, self._duel_seen, self._duel_asked = {}, {}, 0.0
        self._obj_thread, self._mob_names, self._names_retry, self.obj_stats = None, None, 0.0, {}
        self._names_said = 0.0           # (when a failure to ask for the things' name tables may be logged again)
        self._obj_state = (None, 0.0, None, 0.0, {})   # the objects thread's: regions, last full scan, zone, since, cache
        # the hand (handmem.py): its reader of the attached game, the thread making it (its classes looked up once, about
        # half a second), why it couldn't be made (the game it was for, when to try again); the game opened for the
        # cards alone when one of the walker's signatures isn't in this build (handmem.LightAttach)
        self._hand, self._hand_thread, self._hand_fail, self._light = None, None, (None, 0.0, ""), None
        self._failed_sig = False
        # the quest's goal (questmem.py): its reader of the attached game, the thread making it (about a second), why it
        # couldn't be made (the game it was for, when to try again)
        self._quest, self._quest_thread, self._quest_fail = None, None, (None, 0.0, "")
        # the mobs' title, rank and health (bossmem.py): its reader of the attached game, the thread making it (about half a
        # second), why it couldn't be made (the game it was for, when to try again); each mob object's reading
        # {(object, gid): (info or None, why, when to try again)} - kept while the object lives
        self._boss, self._boss_thread, self._boss_fail, self._boss_seen = None, None, (None, 0.0, ""), {}
        self._boss_said = 0.0            # (when a failure to read them may be logged again)
        # the doors' states (statemem.py - their ObjectStateBehavior): its reader of the attached game, the thread making it,
        # why it couldn't be made (the game it was for, when to try again); read again at every blockers() (a state
        # changes: nothing kept), when a failure to read them may be logged again
        self._state, self._state_thread, self._state_fail, self._state_said = None, None, (None, 0.0, ""), 0.0
        # the backpack, the HUD's tips and the game's windows by name (bagmem.py): its reader of the attached game, the
        # thread making it (about half a second), why it couldn't be made (the game it was for, when to try again)
        self._bagm, self._bagm_thread, self._bagm_fail = None, None, (None, 0.0, "")
        # the decks (deckmem.py - the battle recorder's and /deck): its reader of the attached game, the thread making it,
        # why it couldn't be made, the last reading {st, r, sig, read_at, all, kinds}
        self._deckm, self._deckm_thread, self._deckm_fail, self._deck_cache = None, None, (None, 0.0, ""), None
        # the gear (gearmem.py - the helper's /gear): its reader of the attached game, the thread making it, why it couldn't
        # be made (the game it was for, when to try again)
        self._gearm, self._gearm_thread, self._gearm_fail = None, None, (None, 0.0, "")
        # the pets (petmem.py - /pets: Quick Sell's pets to keep): its reader of the attached game, the thread making it,
        # why it couldn't be made (the game it was for, when to try again)
        self._petm, self._petm_thread, self._petm_fail = None, None, (None, 0.0, "")
        # the books' last reading (deck(books=True) - /book: {st, r, sig, read_at, kinds}) - its own, so a book read never
        # takes the place of the decks' (with their kinds: /decks, /sim)
        self._book_cache = None
        # every deck's last reading with their kinds (as _deck_cache's entry) - kept by itself, so a worn-deck reading
        # after it (the recorder's, once an Equipment Set is put on) never takes its place: /deckfor, /sim and /plan
        # answer from it (_deck_cached)
        self._deck_all = None
        # held while a fresh deck read runs (deck(fresh=True) - the recorder's, /deck, /decks, /book): one at a time,
        # since the decks' reader keeps a read's pace and its names' walk budget as its own state (DeckMem._pace,
        # _walk_left) - a second read run in the first one's gap (its lock let go) would leave the rest of the first
        # unpaced, holding navmem's lock to its end. A second read waits deck()'s queue s for it (a gated request: the
        # read in progress gives way to it), else gives way at once (the recorder's - read again later)
        self._deck_busy = threading.Lock()
        # how long the quest's goal has read "no place" (noplace 1) for the same quest and goal - every read() times it
        self._np_hold = NoPlaceHold()

    def close(self):
        with self.lock:
            if self.st:
                self.st.close()
                self.st = None
            if self._light:
                self._light.close()
                self._light = None
            self._hand = None
            self._quest = None
            self._boss = None
            self._boss_seen = {}
            self._state = None
            self._bagm = None
            self._deckm = None
            self._deck_cache = None
            self._deck_all = None
            self._gearm = None
            self._petm = None

    def _attach(self, pid):
        try:
            st = _Attached(pid, self.log)
        except Exception as e:  # noqa: BLE001
            sig = isinstance(e, LookupError)
            why = str(e) if sig else "can't read the game (%s)" % (e,)
            with self.lock:
                self._failed = (pid, time.monotonic() + (self.RETRY_SIG if sig else self.RETRY_READ), why)
                self._failed_sig = sig
            self.log("navmem: attaching to pid %d failed: %s" % (pid, why))
            return
        game_dir = ""
        try:
            exe = st.p.image_path()
            if exe.lower().endswith("\\bin\\" + EXE.lower()):
                game_dir = exe[: -len("\\bin\\" + EXE)]
        except Exception:  # noqa: BLE001
            pass
        with self.lock:
            self.st, self.game_dir = st, game_dir
        self.log("navmem: attached - " + st.describe())

    def _ensure(self, wait):
        with self.lock:
            if self.st is not None and not self.st.alive():
                self.log("navmem: the game (pid %d) has closed" % self.st.p.pid)
                self.st.close()
                self.st = None
            if self.st is not None:
                return self.st, ""
            th = self._thread
            if th is None or not th.is_alive():
                pids = find_pids()
                if not pids:
                    return None, "the game is not running"
                if self.pin:
                    if self.pin not in pids:
                        return None, "that game client (pid %d) isn't running" % self.pin
                    pid = self.pin
                else:
                    fg = foreground_pid()
                    pid = fg if fg in pids else pids[0]
                fpid, again, fwhy = self._failed
                if fpid == pid and time.monotonic() < again:
                    return None, fwhy
                th = self._thread = threading.Thread(target=self._attach, args=(pid,), daemon=True)
                th.start()
        th.join(wait)
        with self.lock:
            if self.st is not None:
                return self.st, ""
            if th.is_alive():
                return None, "attaching to the game (its code is looked through once)"
            return None, self._failed[2] or "can't attach to the game"

    def read(self, path=False, wait=1.0):
        """(r, why): r = {zone, pos (x, y, z), yaw, source, enabled, quest, goalid, goal (x, y, z), hops,
        target (x, y, z), dist, path [(x, y, z)], thread_zone, noplace, noplace_s, why_player, why_quest} - a value None
        when it can't be read for sure; r is None (and why says why) when the game can't be read at all. noplace: 1 the
        game shows no way to the goal (noplace_of), 0 the goal has a place, None not known; noplace_s: how long (s) the 1
        has held for this quest and goal (None unless it's 1)"""
        try:
            st, why = self._ensure(wait)
            if st is None:
                return None, why
            with self.lock:
                r = self._read(st, path)
                r["noplace_s"] = self._np_hold.update((r.get("quest"), r.get("goalid")), r.get("noplace"))
            note = (r.get("why_player") or "") + " / " + (r.get("why_quest") or "")
            if note != self._last_why:
                self._last_why = note
                if note != " / ":
                    self.log("navmem: " + note)
            return r, ""
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the game failed (%r)" % (e,)

    @staticmethod
    def _read(st, path):
        r = dict.fromkeys(("zone", "pos", "yaw", "source", "enabled", "quest", "goalid", "goal", "hops",
                           "target", "dist", "path", "thread_zone", "noplace", "noplace_s", "why_player", "why_quest"))
        try:
            gc = st.gameclient()
        except ReadError as e:
            r["why_player"] = r["why_quest"] = "no GameClient (%s)" % e
            return r
        if not ptr_ok(gc):
            r["why_player"] = r["why_quest"] = "no GameClient yet"
            return r
        try:
            r["zone"] = st.zone(gc)
        except ReadError:
            pass
        try:
            pl, r["why_player"] = st.player(gc)
            if pl:
                r.update(pl)
        except ReadError as e:
            r["why_player"] = "player: %s" % e
        try:
            q, r["why_quest"] = st.quest(r["zone"], path)
            if q:
                r.update(q)
        except ReadError as e:
            r["why_quest"] = "quest: %s" % e
        return r

    def describe(self):
        with self.lock:
            return self.st.describe() if self.st else "not attached"

    # ------------------------------------------------------------ the hand (handmem.py)
    def cards(self, want_effects=True, wait=0.5):
        """(r, why): r = the cards in the wizard's hand and its pips, read now (handmem.HandMem.read: in_battle,
        planning, settled, state, why, ms, me, cards) - through the same read-only handle on the game as everything
        here, under the same lock; its reader made again when the game is (a restart). When one of the walker's
        signatures isn't in this build the game is opened for the cards alone (handmem.LightAttach, read-only the
        same way). None and why when the game can't be read (not running, being attached to, the reader being made).
        Never raises"""
        try:
            st, why = self._ensure(wait)
            if st is None:
                st, why = self._cards_light(why)
                if st is None:
                    return None, why
            with self.lock:
                if st is self.st and self._light is not None:      # (attached in full again: the extra handle closed)
                    self._light.close()
                    self._light = None
                hm = self._hand
                if hm is not None and hm.st is st:
                    return hm.read(want_effects), ""
                fst, again, fwhy = self._hand_fail
                if fst is st and time.monotonic() < again:
                    return None, fwhy
                th = self._hand_thread
                if th is None or not th.is_alive():
                    self._hand = None
                    th = self._hand_thread = threading.Thread(target=self._hand_make, args=(st,), name="hand", daemon=True)
                    th.start()
            th.join(wait)
            with self.lock:
                hm = self._hand
                if hm is not None and hm.st is st:
                    return hm.read(want_effects), ""
                fst, again, fwhy = self._hand_fail
                if fst is st:
                    return None, fwhy
            return None, "reading the game's card classes (once, about a second)"
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the hand failed (%r)" % (e,)

    def _hand_make(self, st):
        """the hand's reader for game st (its code looked through once - outside the lock, then kept under it)"""
        try:
            import handmem
            hm = handmem.HandMem(st, log=self.log)
        except Exception as e:  # noqa: BLE001
            sig = isinstance(e, LookupError)
            why = ("the cards can't be read in this build: %s" % e) if sig else "the card classes couldn't be read (%r)" % (e,)
            self.log("handmem: " + why)
            with self.lock:
                self._hand_fail = (st, time.monotonic() + (self.RETRY_SIG if sig else 30.0), why)
            return
        with self.lock:
            self._hand = hm

    def _cards_light(self, why):
        """(the game opened for the cards alone, "") when navmem couldn't attach for a signature the walker needs (that
        won't change while it runs), else (None, why)"""
        with self.lock:
            lt = self._light
            if lt is not None and not lt.alive():
                lt.close()
                lt = self._light = None
                self._hand = None
            if lt is not None:
                return lt, ""
            sig, fpid = self._failed_sig, self._failed[0]
        if not sig:
            return None, why
        pids = find_pids()
        if fpid not in pids:
            return None, why
        try:
            import handmem
            lt = handmem.LightAttach(fpid, self.log)
        except Exception as e:  # noqa: BLE001
            return None, "%s; the game couldn't be opened for the cards (%r)" % (why, e)
        with self.lock:
            if self._light is None:
                self._light = lt
                self.log("navmem: the game opened for the cards alone (%s)" % why)
            else:
                lt.close()
            return self._light, ""

    # ------------------------------------------------------------ the quest's goal (questmem.py)
    def goal(self, r=None, wait=0.5):
        """(g, why): the quest's active goal, read now (questmem.QuestMem.resolve: text - the goal line as the game shows
        it under the arrow -, from, exact, shown, visible, distance, type, status, count, total, name, mob, item, npc,
        place, quest, quest_id, goal_id, ids_from, why, ms) - through the same read-only handle on the game as everything
        here, its memory read under the same lock (the names looked up in Root.wad outside it); its reader made in a
        thread once per game (its classes looked up, about a second - waited for up to wait s). wait 0: nothing waited
        for (the walker's /nav) - the reader made and a name table not read yet read in a thread meanwhile (the line is
        the HUD's own till then). r: a reading of read() whose quest helper ids stand in for the HUD's own (None: read
        now). None and why when there's no goal line to give (the game not running, being attached to, the reader being
        made, no quest...). Never raises"""
        try:
            st, why = self._ensure(wait)
            if st is None:
                return None, why
            qm, why = self._quest_reader(st, wait)
            if qm is None:
                return None, why
            with self.lock:
                if self.st is not st:
                    return None, "the game changed"
                if r is None:
                    r = self._read(st, False)
                snap = qm.snapshot((r.get("quest"), r.get("goalid")))
            g = qm.resolve(snap, block=wait > 0)
            if not g.get("text"):
                return None, g.get("why") or "no goal line"
            return g, ""
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the quest's goal failed (%r)" % (e,)

    def _quest_reader(self, st, wait):
        """(the quest goal's reader for game st, "") - made in a thread the first time; (None, why) meanwhile, or when it
        can't be made (tried again later)"""
        with self.lock:
            qm = self._quest
            if qm is not None and qm.st is st:
                return qm, ""
            fst, again, fwhy = self._quest_fail
            if fst is st and time.monotonic() < again:
                return None, fwhy
            th = self._quest_thread
            if th is None or not th.is_alive():
                self._quest = None
                th = self._quest_thread = threading.Thread(target=self._quest_make, args=(st,), name="quest", daemon=True)
                th.start()
        if wait > 0:
            th.join(wait)
        with self.lock:
            qm = self._quest
            if qm is not None and qm.st is st:
                return qm, ""
            fst, again, fwhy = self._quest_fail
            if fst is st:
                return None, fwhy
        return None, "reading the game's quest classes (once, about a second)"

    def _quest_make(self, st):
        """the quest goal's reader for game st (its code looked through once - outside the lock, then kept under it)"""
        try:
            import questmem
            qm = questmem.QuestMem(st, log=self.log)
        except Exception as e:  # noqa: BLE001
            sig = isinstance(e, LookupError)
            why = ("the quest's goal can't be read in this build: %s" % e) if sig else \
                "the quest classes couldn't be read (%r)" % (e,)
            self.log("questmem: " + why)
            with self.lock:
                self._quest_fail = (st, time.monotonic() + (self.RETRY_SIG if sig else 30.0), why)
            return
        with self.lock:
            self._quest = qm

    QUEST_GAP = 0.002       # s the lock is let go between two quests' reads (quests(): the walker's /nav gets in)

    def quests(self, wait=0.5):
        """(rows, why): EVERY quest in the game's quest manager (questmem.QuestMem.quest_ids / quest_raw /
        quests_resolve: [{id, title, title_key, tracked, goals [{gid, text, type, status, count, total, mob, item, npc,
        place, name_key, ...}], props {WizQuestData property: value}}]) - the tracked one (the HUD's ids, as goal()'s)
        marked. The map walked under the lock, then each quest read under it on its own (let go QUEST_GAP s in between:
        /nav waits on it), the names looked up outside it. (None, why) when there are none to give (the game not
        running, the quest classes being read, no quests - the login screen...). Never raises; read only"""
        try:
            st, why = self._ensure(wait)
            if st is None:
                return None, why
            qm, why = self._quest_reader(st, wait)
            if qm is None:
                return None, why
            with self.lock:
                if self.st is not st:
                    return None, "the game changed"
                r = self._read(st, False)
                snap = qm.snapshot((r.get("quest"), r.get("goalid")))
                ids, why = qm.quest_ids()
            if ids is None:
                return None, why
            raws, gone = [], 0
            for qid, q in ids:
                time.sleep(self.QUEST_GAP)
                with self.lock:
                    if self.st is not st:
                        return None, "the game changed"
                    raw = qm.quest_raw(qid, q)
                if raw is None:
                    gone += 1                # (done or dropped since the map was walked)
                else:
                    raws.append(raw)
            tracked = (snap.get("ids") or (None, None))[0]
            rows = qm.quests_resolve(raws, tracked=tracked, block=wait > 0)
            notes = [w for w in (snap.get("why") if tracked is None else "",
                                 "%d quest(s) left the map while it was read" % gone if gone else "") if w]
            return rows, "; ".join(notes)
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the quests failed (%r)" % (e,)

    # ------------------------------------------------------------ the mobs' titles and the battle (bossmem.py)
    BOSS_RETRY = 5.0        # s before a mob whose template couldn't be read is tried again

    def _boss_reader(self, st, wait=0.0):
        """(the titles' reader for game st, "") - made in a thread the first time (not waited for with wait 0); (None,
        why) meanwhile, or when it can't be made (tried again later)"""
        with self.lock:
            bm = self._boss
            if bm is not None and bm.st is st:
                return bm, ""
            fst, again, fwhy = self._boss_fail
            if fst is st and time.monotonic() < again:
                return None, fwhy
            th = self._boss_thread
            if th is None or not th.is_alive():
                self._boss, self._boss_seen = None, {}
                th = self._boss_thread = threading.Thread(target=self._boss_make, args=(st,), name="boss", daemon=True)
                th.start()
        if wait > 0:
            th.join(wait)
        with self.lock:
            bm = self._boss
            if bm is not None and bm.st is st:
                return bm, ""
            fst, again, fwhy = self._boss_fail
            if fst is st:
                return None, fwhy
        return None, "reading the game's mob classes (once, about half a second)"

    def _boss_make(self, st):
        """the titles' reader for game st (its code looked through once - outside the lock, then kept under it)"""
        try:
            import bossmem
            bm = bossmem.BossMem(st, log=self.log)
        except Exception as e:  # noqa: BLE001
            sig = isinstance(e, LookupError)
            why = ("the mobs' titles can't be read in this build: %s" % e) if sig else \
                "the mob classes couldn't be read (%r)" % (e,)
            self.log("bossmem: " + why)
            with self.lock:
                self._boss_fail = (st, time.monotonic() + (self.RETRY_SIG if sig else 30.0), why)
            return
        with self.lock:
            self._boss, self._boss_seen = bm, {}

    def _boss_fill(self, st, live):
        """each live mob's title, title_id, rank, health (its starting - max - health), school, boss (the game's own flag)
        and kind (boss / elite / normal / easy / minion) - bossmem.BossMem.mob, read once per mob object and kept while it
        lives (one that couldn't be read tried again after BOSS_RETRY s); None each while it isn't known (the reader being
        made, this build unreadable, the mob's template not read). live: [(object, gid, its dict)] - checked live just now"""
        import bossmem
        bm, _ = self._boss_reader(st)
        now = time.monotonic()
        with self.lock:
            if bm is not None and (self.st is not st or bm.st is not st):
                bm = None
            seen = self._boss_seen
            if len(seen) > 4000:
                seen.clear()
            for obj, gid, m in live:
                hit = seen.get((obj, gid))
                if bm is not None and (hit is None or (hit[0] is None and now >= hit[2])):
                    info, why = bm.mob(obj)
                    hit = seen[(obj, gid)] = (info, why, now + self.BOSS_RETRY)
                info = hit[0] if hit else None
                for k in bossmem.FIELDS:
                    m[k] = info.get(k) if info else None

    # ------------------------------------------------------------ the doors' states (statemem.py)
    def _state_reader(self, st, wait=0.0):
        """(the states' reader for game st, "") - made in a thread the first time (not waited for with wait 0); (None,
        why) meanwhile, or when it can't be made (tried again later: _state_fail)"""
        with self.lock:
            sm = self._state
            if sm is not None and sm.st is st:
                return sm, ""
            fst, again, fwhy = self._state_fail
            if fst is st and time.monotonic() < again:
                return None, fwhy
            th = self._state_thread
            if th is None or not th.is_alive():
                self._state = None
                th = self._state_thread = threading.Thread(target=self._state_make, args=(st,), name="state", daemon=True)
                th.start()
        if wait > 0:
            th.join(wait)
        with self.lock:
            sm = self._state
            if sm is not None and sm.st is st:
                return sm, ""
            fst, again, fwhy = self._state_fail
            if fst is st:
                return None, fwhy
        return None, "reading the game's state classes (once, about half a second)"

    def _state_make(self, st):
        """the states' reader for game st (its code looked through once - outside the lock, then kept under it)"""
        try:
            import statemem
            sm = statemem.StateMem(st, log=self.log)
        except Exception as e:  # noqa: BLE001
            self._state_failed(st, e)
            return
        with self.lock:
            self._state = sm

    def _state_failed(self, st, e):
        """_state_make's failure: kept (tried again after RETRY_SIG s - a class or property not in this build -, else 30 s)"""
        sig = isinstance(e, LookupError)
        why = ("the doors' states can't be read in this build: %s" % e) if sig else \
            "the state classes couldn't be read (%r)" % (e,)
        self.log("statemem: " + why)
        with self.lock:
            self._state_fail = (st, time.monotonic() + (self.RETRY_SIG if sig else 30.0), why)

    def _state_fill(self, st, live):
        """each live door's state (statemem.StateMem.state - its ObjectStateBehavior's: read every time, a state changes),
        None while it isn't known (the reader being made, this build unreadable, no state behaviour on it). live:
        [(object, gid, its dict)] - checked live just now"""
        sm, _ = self._state_reader(st)
        with self.lock:
            if sm is not None and (self.st is not st or sm.st is not st):
                sm = None
            for obj, _gid, d in live:
                d["state"] = sm.state(obj)[0] if sm is not None else None

    def _hand_reader(self, st, wait):
        """(the hand's reader for game st, "") - made in a thread the first time, as cards() makes it; (None, why)
        meanwhile, or when it can't be made"""
        with self.lock:
            hm = self._hand
            if hm is not None and hm.st is st:
                return hm, ""
            fst, again, fwhy = self._hand_fail
            if fst is st and time.monotonic() < again:
                return None, fwhy
            th = self._hand_thread
            if th is None or not th.is_alive():
                self._hand = None
                th = self._hand_thread = threading.Thread(target=self._hand_make, args=(st,), name="hand", daemon=True)
                th.start()
        if wait > 0:
            th.join(wait)
        with self.lock:
            hm = self._hand
            if hm is not None and hm.st is st:
                return hm, ""
            fst, again, fwhy = self._hand_fail
            if fst is st:
                return None, fwhy
        return None, "reading the game's card classes (once, about a second)"

    def ui_root(self, wait=0.5):
        """((w, h), why): the game's GUI root's size in GUI units - handmem's root (WorldView: the whole client), its
        m_Window - read now; the client's pixels over it are the GUI's scale (1827 x 1027 at 2560x1440 borderless, UI
        1.144: 1.4012 px a unit - castmem's POSITIONS.md). None and why when it can't be read (no game, the hand's reader
        being made, no HUD yet - the login screen). Never raises"""
        try:
            st, why = self._ensure(wait)
            if st is None:
                return None, why
            hm, why = self._hand_reader(st, wait)
            if hm is None:
                return None, why
            with self.lock:
                if self.st is not st or hm.st is not st:
                    return None, "the game changed"
                root = hm.root()
                r = hm.rect(root) if root else None
            if not r:
                return None, "no GUI root (not in the world yet?)"
            w, h = r[2] - r[0], r[3] - r[1]
            if not (0 < w <= 20000 and 0 < h <= 20000):
                return None, "the GUI root's size isn't plausible (%d x %d)" % (w, h)
            return (w, h), ""
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the GUI root failed (%r)" % (e,)

    def battle(self, wait=0.5):
        """(parts, why): the battle's participants, read now - bossmem.BossMem.battle (every one the battle's GUI shows,
        and mine: me, team, health, max_health, boss - the game's flag -, player, minion, mob_level, owner...), each joined
        to its mob by its owner's global id: name ("" not a mob of this zone's: a wizard) and mob (its title, rank, health,
        school, kind - None not read). ([], why) out of a battle's planning phase; None and why when the game can't be read
        (not running, the readers being made - waited for up to wait s). Never raises"""
        try:
            st, why = self._ensure(wait)
            if st is None:
                return None, why
            bm, why = self._boss_reader(st, wait)
            if bm is None:
                return None, why
            hm, why = self._hand_reader(st, wait)
            if hm is None:
                return None, why
            with self.lock:
                if self.st is not st or hm.st is not st or bm.st is not st:
                    return None, "the game changed"
                # (the zone's objects looked at again while a battle's asked about: the objects thread stops when nobody's
                # asked for a while, and the mobs' objects it kept may be gone by the battle - seen live 2026-10-25)
                self._obj_asked = time.monotonic()
                if self._obj_thread is None or not self._obj_thread.is_alive():
                    self._obj_thread = threading.Thread(target=self._objects_run, name="objects", daemon=True)
                    self._obj_thread.start()
                parts, why = bm.battle(hm)
                by_gid = {v[0]: (obj, v) for obj, v in self._objs.items()}
                cz = self._obj_cz
                for p in parts:
                    p["name"], p["mob"] = "", None
                    obj, v = by_gid.get(p["owner"], (0, None))
                    if not obj:
                        continue
                    # (still the same live object of this zone - as _live checks it)
                    raw = st.p.try_read(obj, OBJ_SPAN)
                    if (raw is None or struct.unpack_from("<Q", raw, 0)[0] != v[3]
                            or struct.unpack_from("<Q", raw, DATA["co_gid"])[0] != v[0]
                            or struct.unpack_from("<Q", raw, DATA["co_zone"])[0] != cz):
                        continue
                    p["name"] = v[1]
                    hit = self._boss_seen.get((obj, v[0]))
                    p["mob"] = hit[0] if hit and hit[0] else bm.mob(obj)[0]
                # (one whose mob object isn't found: by its template - the participant's template id -> the game's
                # template (handmem's template map) -> its name -> a mob of that template read before in the zone)
                if any(not p["player"] and p["mob"] is None for p in parts):
                    try:
                        self._battle_by_template(st, bm, hm, parts)
                    except Exception:  # noqa: BLE001 - the participants as they are
                        pass
            return parts, why
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the battle failed (%r)" % (e,)

    def _battle_by_template(self, st, bm, hm, parts):
        """(battle(), under the lock) the participants not joined to a mob object: their mob info from a mob of the same
        template read before in this zone (_boss_seen, by its template's name) and their name from its display key (the
        *Mobs name tables) - the participant's m_templateID -> handmem's template map -> the GameObjectTemplate (checked
        by its type name there) -> m_objectName / m_displayName. Left as they are when any of it can't be read"""
        seen = {}
        for _key, (info, _why, _again) in list(self._boss_seen.items()):
            if info and info.get("template"):
                seen.setdefault(info["template"], info)
        names = self._mob_names or {}
        GT = bm.P.get("GameObjectTemplate", {})
        if not GT.get("m_objectName"):
            return
        for p in parts:
            if p["player"] or p["mob"] is not None or not p.get("template_id"):
                continue
            t = hm.template(p["template_id"])
            if not t:
                continue
            tname = st.p.try_string(t + GT["m_objectName"])
            key = st.p.try_string(t + GT["m_displayName"]) if GT.get("m_displayName") else None
            if tname and tname in seen:
                p["mob"] = seen[tname]
            if not p["name"] and key and names.get(key):
                p["name"] = names[key]

    # ------------------------------------------------------------ the backpack and the game's windows (bagmem.py)
    def _bag_reader(self, st, wait=0.0):
        """(the backpack's reader for game st, "") - made in a thread the first time (not waited for with wait 0); (None,
        why) meanwhile, or when it can't be made (tried again later)"""
        with self.lock:
            bm = self._bagm
            if bm is not None and bm.st is st:
                return bm, ""
            fst, again, fwhy = self._bagm_fail
            if fst is st and time.monotonic() < again:
                return None, fwhy
            th = self._bagm_thread
            if th is None or not th.is_alive():
                self._bagm = None
                th = self._bagm_thread = threading.Thread(target=self._bag_make, args=(st,), name="bag", daemon=True)
                th.start()
        if wait > 0:
            th.join(wait)
        with self.lock:
            bm = self._bagm
            if bm is not None and bm.st is st:
                return bm, ""
            fst, again, fwhy = self._bagm_fail
            if fst is st:
                return None, fwhy
        return None, "reading the game's backpack and window classes (once, about half a second)"

    def _bag_make(self, st):
        """the backpack's reader for game st (its code looked through once - outside the lock, then kept under it)"""
        try:
            import bagmem
            bm = bagmem.BagMem(st, log=self.log)
        except Exception as e:  # noqa: BLE001
            sig = isinstance(e, LookupError)
            why = ("the backpack can't be read in this build: %s" % e) if sig else \
                "the backpack's classes couldn't be read (%r)" % (e,)
            self.log("bagmem: " + why)
            with self.lock:
                self._bagm_fail = (st, time.monotonic() + (self.RETRY_SIG if sig else 30.0), why)
            return
        with self.lock:
            self._bagm = bm

    def _bag_readers(self, wait):
        """(game, backpack reader, hand reader, "") - the hand's for the GUI's root and the template map - or (None, None,
        None, why)"""
        st, why = self._ensure(wait)
        if st is None:
            return None, None, None, why
        bm, why = self._bag_reader(st, wait)
        if bm is None:
            return None, None, None, why
        hm, why = self._hand_reader(st, wait)
        if hm is None:
            return None, None, None, why
        return st, bm, hm, ""

    def bag(self, wait=0.3):
        """(r, why): the backpack, read now - bagmem.BagMem.bag (items - the list's size -, allowed, extra, gold, gold_max,
        player_gid, cats {kind: [n, crowns, nosell, plain]}, crownshop, sets, set_items, tips - the HUD's right-hand icons -, space - the
        backpack page's N/M while it's shown -, root) - through the same read-only handle on the game as everything here,
        under the same lock; its reader made in a thread once per game (waited for up to wait s). None and why when the
        game can't be read. Never raises"""
        try:
            st, bm, hm, why = self._bag_readers(wait)
            if st is None:
                return None, why
            with self.lock:
                if self.st is not st or hm.st is not st or bm.st is not st:
                    return None, "the game changed"
                return bm.bag(hm)
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the backpack failed (%r)" % (e,)

    def gui(self, paths, wait=0.3):
        """(g, why): the game's windows named by paths ("Anc/Name"), read now - bagmem.BagMem.gui (each one's type, shown,
        rect in the root, its parent's, checked, greyed, text and key; the message box that's up and its buttons), the
        texts' "<string;KEY>" given their words from the name tables outside the lock (bagmem.finish_gui). None and why
        when the game can't be read. Never raises"""
        try:
            import bagmem
            st, bm, hm, why = self._bag_readers(wait)
            if st is None:
                return None, why
            with self.lock:
                if self.st is not st or hm.st is not st or bm.st is not st:
                    return None, "the game changed"
                g, why = bm.gui(hm, paths)
            return bagmem.finish_gui(g, hm.lang_text), why
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the game's windows failed (%r)" % (e,)

    # ------------------------------------------------------------ the decks (deckmem.py - the battle recorder, /deck)
    DECK_HOLD, DECK_GAP, DECK_IDLE = 0.012, 0.004, 1.0     # s: the lock held at most, then let go this long, idle waited

    def _deck_reader(self, st, wait=0.0):
        """(the decks' reader for game st, "") - made in a thread the first time (not waited for with wait 0); (None,
        why) meanwhile, or when it can't be made (tried again later)"""
        with self.lock:
            dm = self._deckm
            if dm is not None and dm.st is st:
                return dm, ""
            fst, again, fwhy = self._deckm_fail
            if fst is st and time.monotonic() < again:
                return None, fwhy
            th = self._deckm_thread
            if th is None or not th.is_alive():
                self._deckm = None
                th = self._deckm_thread = threading.Thread(target=self._deck_make, args=(st,), name="deck", daemon=True)
                th.start()
        if wait > 0:
            th.join(wait)
        with self.lock:
            dm = self._deckm
            if dm is not None and dm.st is st:
                return dm, ""
            fst, again, fwhy = self._deckm_fail
            if fst is st:
                return None, fwhy
        return None, "reading the game's deck classes (once, about half a second)"

    def _deck_make(self, st):
        """the decks' reader for game st (its code looked through once - outside the lock, then kept under it); the
        hand's reader gives it the template map and the names"""
        try:
            import deckmem
            hm, why = self._hand_reader(st, 2.0)
            if hm is None:
                raise RuntimeError("the hand's reader isn't made yet (%s)" % why)
            dm = deckmem.DeckMem(st, hm, log=self.log)
        except Exception as e:  # noqa: BLE001
            sig = isinstance(e, LookupError)
            why = ("the decks can't be read in this build: %s" % e) if sig else "the deck classes couldn't be read (%r)" % (e,)
            self.log("deckmem: " + why)
            with self.lock:
                self._deckm_fail = (st, time.monotonic() + (self.RETRY_SIG if sig else
                                                            5.0 if isinstance(e, RuntimeError) else 30.0), why)
            return
        with self.lock:
            self._deckm = dm

    def _deck_readers(self, wait):
        st, why = self._ensure(wait)
        if st is None:
            return None, None, why
        dm, why = self._deck_reader(st, wait)
        return st, dm, why

    def deck_sig(self, wait=0.0):
        """(signature, why): the worn deck's signature - deckmem.DeckMem.signature (the worn list only, about 2 ms) -
        under the lock. Never makes the decks' reader (its code look-through is deck()'s, out of battle only): None and
        why when there's none for this game yet, or no game. Never raises"""
        try:
            with self.lock:
                st, dm = self.st, self._deckm
                if st is None or not st.alive():
                    return None, "the game is not running"
                if dm is None or dm.st is not st or dm.hm is not self._hand:
                    return None, "the decks not read yet"
                # (a paced read let go in its gap: the reader's pace is that read's - signature() would call it, and it
                # lets go of the lock held here; not read now)
                if self._deck_busy.locked():
                    return None, "a deck read is in progress"
                return dm.signature(), ""
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the deck's signature failed (%r)" % (e,)

    def deck(self, fresh=False, wait=0.0, idle=None, only_equipped=True, stop=None, kinds=False, books=False,
             queue=0.0):
        """(r, why): the decks - deckmem.DeckMem.read(kinds=kinds) plus sig (its signature) and read_at (monotonic s).
        fresh False: the last reading (None, "not read yet" when there's none). fresh True: read now unless the worn
        deck's signature is the last reading's - under the lock, PACED: it is let go when it has been held DECK_HOLD s,
        or at once when idle(0) says a gated request (the bot's or the walker's reads; vision.GATE.idle) is in flight;
        then DECK_GAP s, then idle(0.05) is waited for before it is taken again (and before it is taken at first). Not
        idle within DECK_IDLE s, or stop() true (the battle recorder's: a battle began, the read ran long): the read
        GIVES WAY - (None, "gave way ..."), the lock not taken again; read again later (the spell names' walk goes on
        where it was). A reading with an item card's names not all read isn't kept by its signature (read again).
        only_equipped: the backpack's decks left out - such a reading never takes the place of every deck's with their
        kinds (_deck_all): asked for every deck after one (fresh False), that last reading of them answers, the decks worn
        marked as the newer one has them, its sig None (fresh True: read again) - unless the newer one doesn't fit it
        (_worn_misfit: another character, a deck worn it hasn't or one with a card put in since): that reading dropped,
        "not read yet" till every deck is read again. kinds: each card's kind, value, heads
        and boosts too (handmem's reading of its effects - the battle simulator's, vision\\battlesim.py; slower the first
        time a card is seen): a reading without them doesn't answer it (read again). books: the spellbook and the
        treasure book too (deckmem.read(books=True) - /book): such a reading has its own cache (the decks' is left as it
        was - a book read never takes the place of the decks' with their kinds) and is never answered by the worn deck's
        signature (a spell learned doesn't change the worn deck): fresh True always reads. ONE fresh read at a time (_deck_busy): asked
        while another runs (the recorder's let go in its gap, say), it waits for it up to queue s - a gated request's
        (vision.py DECK_QUEUE_S): the read in progress gives way to it within DECK_IDLE s, its idle() seeing it in
        flight - then gives way itself, (None, "gave way to another deck read in progress - read again later"); queue 0
        (the recorder's): at once. Never raises; read only"""
        try:
            cached = self._deck_cached(books, kinds, only_equipped)
            if not fresh:
                if cached is None:
                    return None, "not read yet"
                return dict(cached["r"], sig=cached["sig"], read_at=cached["read_at"]), ""
            st, dm, why = self._deck_readers(wait)
            if dm is None:
                return None, why
            # (one fresh read at a time - _deck_busy: a second one run in the first one's gap would leave the rest of
            # the first unpaced; the second waits queue s for the first to end or give way, else gives way itself - its
            # caller reads again later as after any giving way)
            busy = self._deck_busy
            if not (busy.acquire(timeout=queue) if queue > 0 else busy.acquire(blocking=False)):
                return None, "gave way to another deck read in progress - read again later"
            try:
                # (the last reading looked at again: the read waited for may have just been kept)
                return self._deck_paced(st, dm, self._deck_cached(books, kinds, only_equipped), idle, stop,
                                        only_equipped, kinds, books)
            finally:
                busy.release()
        except _GaveWay as e:
            return None, str(e)
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the decks failed (%r)" % (e,)

    def _deck_cached(self, books, kinds, only_equipped):
        """the last reading that answers deck(books, kinds, only_equipped) for the attached game ({st, r, sig, read_at,
        ...}), or None"""
        with self.lock:
            if books:
                c = self._book_cache
                return c if c is not None and c["st"] is self.st and (c.get("kinds") or not kinds) else None
            c = self._deck_cache
            if c is not None and c["st"] is self.st and (c["all"] or only_equipped) and (c.get("kinds") or not kinds):
                return c
            # (every deck's reading with their kinds, a narrower reading since - the worn deck's: the decks worn marked
            # as that newer one has them, its signature dropped - a fresh read of every deck reads again)
            a = self._deck_all
            if a is None or a["st"] is not self.st or (kinds and not a.get("kinds")):
                return None
            if c is None or c is a or c["st"] is not self.st:
                return a
            wr = c["r"]
            # (another character, a deck worn it hasn't or one edited since: not answered - _deck_paced drops it then,
            # this the guard - every deck read again)
            if _worn_misfit(a["r"], wr):
                return None
            worn = {d.get("gid") for d in wr.get("decks") or [] if d.get("equipped")}
            decks = [dict(d, equipped=d.get("gid") in worn, where="equipped" if d.get("gid") in worn else "backpack")
                     for d in a["r"].get("decks") or []]
            on = [d["gid"] for d in decks if d["equipped"]]
            r = dict(a["r"], decks=decks, equipped=on[0] if len(on) == 1 else None,
                     equipped_set=wr.get("equipped_set"), sets=wr.get("sets") or a["r"].get("sets"))
            return dict(a, r=r, sig=None)

    def _deck_paced(self, st, dm, cached, idle, stop, only_equipped, kinds, books):
        """deck(fresh=True)'s read itself, _deck_busy held (deck's docstring) - (r, why); raises _GaveWay when it gives
        way (deck() answers it)"""
        lock = self.lock
        held = [0.0]
        holding = [False]
        gave = [None]

        def wait_idle():
            """off the lock: idle(0.05) waited for - False (gave set) when stop() or not idle within DECK_IDLE s"""
            t0 = time.monotonic()
            while True:
                if stop is not None and stop():
                    gave[0] = "gave way (a battle began, or the read ran long) - read again later"
                    return False
                if idle is None or idle(0.05):
                    return True
                if time.monotonic() - t0 >= self.DECK_IDLE:
                    gave[0] = "gave way to the gated reads (not idle for %.0f s) - read again later" % (
                        self.DECK_IDLE,)
                    return False
                time.sleep(0.005)

        def pace():
            if time.perf_counter() - held[0] < self.DECK_HOLD and (idle is None or idle(0)):
                return
            lock.release()
            holding[0] = False
            try:
                time.sleep(self.DECK_GAP)
                ok = wait_idle()
            except Exception as e:  # noqa: BLE001 - an idle / stop that raises: given way all the same
                gave[0] = gave[0] or "gave way (%r) - read again later" % (e,)
                ok = False
            if not ok:
                raise _GaveWay(gave[0])
            lock.acquire()
            holding[0] = True
            held[0] = time.perf_counter()
            if self.st is not st or dm.st is not st:
                raise RuntimeError("the game changed while the decks were read")

        if not wait_idle():
            return None, gave[0]
        lock.acquire()
        holding[0] = True
        try:
            held[0] = time.perf_counter()
            if self.st is not st or dm.st is not st or dm.hm is not self._hand:
                return None, "the game changed"
            sig = dm.signature(pace)
            if not books and cached is not None and sig is not None and sig == cached["sig"]:
                return dict(cached["r"], sig=cached["sig"], read_at=cached["read_at"]), ""
            r = dm.read(books=books, kinds=kinds, only_equipped=only_equipped, pace=pace)
            if gave[0] is not None or not holding[0]:
                return None, gave[0] or "gave way - read again later"
            sig2 = dm.signature(pace)
            at = time.monotonic()
            keep = sig2 if sig2 == sig and not r.get("names_cut") else None
            if books:
                if r.get("spellbook") is not None:
                    self._book_cache = {"st": st, "r": r, "sig": keep, "read_at": at, "kinds": kinds}
            elif r.get("decks"):
                self._deck_cache = {"st": st, "r": r, "sig": keep, "read_at": at, "all": not only_equipped,
                                    "kinds": kinds}
                if not only_equipped and kinds:
                    self._deck_all = self._deck_cache
                elif self._deck_all is not None and self._deck_all["st"] is st and _worn_misfit(self._deck_all["r"], r):
                    # (the kept reading no longer fits the decks worn: dropped for good - wearing another deck later
                    # mustn't bring an edited one's old cards back; only a fresh read of every deck answers again)
                    self._deck_all = None
        finally:
            if holding[0]:
                holding[0] = False
                lock.release()
        return dict(r, sig=keep, read_at=at), ""

    # ------------------------------------------------------------ the gear (gearmem.py - the helper's /gear)
    def _gear_reader(self, st, wait=0.0):
        """(the gear's reader for game st, "") - made in a thread the first time (not waited for with wait 0); (None, why)
        meanwhile, or when it can't be made (tried again later) - _bag_reader's way"""
        with self.lock:
            gm = self._gearm
            if gm is not None and gm.st is st:
                return gm, ""
            fst, again, fwhy = self._gearm_fail
            if fst is st and time.monotonic() < again:
                return None, fwhy
            th = self._gearm_thread
            if th is None or not th.is_alive():
                self._gearm = None
                th = self._gearm_thread = threading.Thread(target=self._gear_make, args=(st,), name="gear", daemon=True)
                th.start()
        if wait > 0:
            th.join(wait)
        with self.lock:
            gm = self._gearm
            if gm is not None and gm.st is st:
                return gm, ""
            fst, again, fwhy = self._gearm_fail
            if fst is st:
                return None, fwhy
        return None, "reading the game's gear classes (once, about a second)"

    def _gear_make(self, st):
        """the gear's reader for game st (its code looked through once - outside the lock, then kept under it); the hand's
        reader gives it the template map and the names (_deck_make's way)"""
        try:
            import gearmem
            hm, why = self._hand_reader(st, 2.0)
            if hm is None:
                raise RuntimeError("the hand's reader isn't made yet (%s)" % why)
            gm = gearmem.GearMem(st, hm, log=self.log)
        except Exception as e:  # noqa: BLE001
            sig = isinstance(e, LookupError)
            why = ("the gear can't be read in this build: %s" % e) if sig else "the gear classes couldn't be read (%r)" % (e,)
            self.log("gearmem: " + why)
            with self.lock:
                self._gearm_fail = (st, time.monotonic() + (self.RETRY_SIG if sig else
                                                            5.0 if isinstance(e, RuntimeError) else 30.0), why)
            return
        with self.lock:
            self._gearm = gm

    def gear(self, wait=0.3):
        """(r, why): the wizard's gear, read now - gearmem.GearMem.read (worn, bag - the planned slots' gear with their
        equip effects and requirements -, bag_gids - every backpack item -, bag_size, sets, sets_ok, level, player_gid) -
        through the same read-only handle on the game as everything here, under the same lock (a template's effects and
        requirements are read once, then kept); each item's display name from the name tables outside it (gearmem.finish).
        Its reader made in a thread once per game (waited for up to wait s). None and why when the game can't be read.
        Never raises"""
        try:
            import gearmem
            st, why = self._ensure(wait)
            if st is None:
                return None, why
            gm, why = self._gear_reader(st, wait)
            if gm is None:
                return None, why
            with self.lock:
                if self.st is not st or gm.st is not st:
                    return None, "the game changed"
                r, why = gm.read()
            return (gearmem.finish(r, gm.hm.lang_text) if r is not None else None), why
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the gear failed (%r)" % (e,)

    # ------------------------------------------------------------ the pets (petmem.py - /pets)
    PET_HOLD, PET_GAP = 0.012, 0.004        # s: the lock held at most during a read, then let go this long

    def _pet_reader(self, st, wait=0.0):
        """(the pets' reader for game st, "") - made in a thread the first time (not waited for with wait 0); (None,
        why) meanwhile, or when it can't be made (tried again later) - the backpack's way"""
        with self.lock:
            pm = self._petm
            if pm is not None and pm.st is st:
                return pm, ""
            fst, again, fwhy = self._petm_fail
            if fst is st and time.monotonic() < again:
                return None, fwhy
            th = self._petm_thread
            if th is None or not th.is_alive():
                self._petm = None
                th = self._petm_thread = threading.Thread(target=self._pet_make, args=(st,), name="pets", daemon=True)
                th.start()
        if wait > 0:
            th.join(wait)
        with self.lock:
            pm = self._petm
            if pm is not None and pm.st is st:
                return pm, ""
            fst, again, fwhy = self._petm_fail
            if fst is st:
                return None, fwhy
        return None, "reading the game's pet classes (once, about half a second)"

    def _pet_make(self, st):
        """the pets' reader for game st (its code looked through once - outside the lock, then kept under it); the
        hand's reader gives it the template map and the names (deckmem's way)"""
        try:
            import petmem
            hm, why = self._hand_reader(st, 2.0)
            if hm is None:
                raise RuntimeError("the hand's reader isn't made yet (%s)" % why)
            pm = petmem.PetMem(st, hm, log=self.log)
        except Exception as e:  # noqa: BLE001
            sig = isinstance(e, LookupError)
            why = ("the pets can't be read in this build: %s" % e) if sig else "the pet classes couldn't be read (%r)" % (e,)
            self.log("petmem: " + why)
            with self.lock:
                self._petm_fail = (st, time.monotonic() + (self.RETRY_SIG if sig else
                                                           5.0 if isinstance(e, RuntimeError) else 30.0), why)
            return
        with self.lock:
            self._petm = pm

    def pets(self, wait=0.3):
        """(r, why): the wizard's pets, read now - petmem.PetMem.read (pets [{gid, where, level, level_name, template_id,
        object_name, display, cards, and the values not confirmed yet: xp, talents...}], energy, whole) - through the same
        read-only handle on the game as everything here, under the same lock, PACED: let go for PET_GAP s whenever it
        has been held PET_HOLD s (the walker's /nav waits on it - a backpack of 150 items is a few hundred reads); its
        reader made in a thread once per game (waited for up to wait s). None and why when the game can't be read.
        Never raises"""
        try:
            st, why = self._ensure(wait)
            if st is None:
                return None, why
            pm, why = self._pet_reader(st, wait)
            if pm is None:
                return None, why
            lock, held = self.lock, [0.0]

            def pace():
                if time.perf_counter() - held[0] < self.PET_HOLD:
                    return
                lock.release()
                try:
                    time.sleep(self.PET_GAP)
                finally:
                    lock.acquire()
                    held[0] = time.perf_counter()
                if self.st is not st or pm.st is not st:
                    raise RuntimeError("the game changed while the pets were read")

            with lock:
                held[0] = time.perf_counter()
                if self.st is not st or pm.st is not st or pm.hm is not self._hand:
                    return None, "the game changed"
                return pm.read(pace=pace), ""
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the pets failed (%r)" % (e,)

    def mob_infos(self, gids):
        """{gid: mob info} of the zone's mobs read before by the objects thread (bossmem's - _boss_seen: title, rank,
        health, school, school2, boss, kind, max_shadow_pips, ai, template) - a dict walk under the lock, no memory
        read (the battle recorder's, at a battle's first PrePlanning)"""
        want = set(gids or ())
        out = {}
        if not want:
            return out
        with self.lock:
            for (_obj, gid), (info, _why, _again) in self._boss_seen.items():
                if gid in want and info:
                    out[gid] = dict(info)
        return out

    # ------------------------------------------------------------ the zone's mobs
    def mobs(self):
        """(mobs, why): mobs = [{name, pos (x, y, z), yaw, gid, template, title, title_id, rank, health, school, boss,
        kind}] - the mobs in the game's zone, their positions and facing (yaw, radians, forward = (-sin yaw, -cos yaw);
        None if unread) read now, and what each is (_boss_fill: title Boss / Elite / Normal..., rank, max health, school,
        the game's boss flag - None each while not known) - or None and why (not attached, not looked yet, the names
        unreadable...). Never raises."""
        return self._live("mobs")

    def items(self):
        """(items, why): items = [{name, pos (x, y, z), yaw, gid, template, key, kind, src}] - the zone's things that
        aren't mobs and have a name key (template_kind), read now: kind "item" (the items table: Piece Of Coral - one
        picked up is gone), "object" (Inactive Protector, Celestian Monolith, a chest), "npc", "ambient"; key its display
        key (WizQst371C7_00000008 - the one a quest's goal names it by), src "mem"; name "" while its name table isn't
        read (placements.py reads it, kept). Also kind "use" (name and key ""): an object with no name key whose template
        a use event of the zone's triggers may be fired by (puzzlefile.use_templates - a lever). None and why as mobs().
        Never raises."""
        return self._live("items")

    def blockers(self):
        """(doors, why): doors = [{name, pos (x, y, z), yaw, gid, template, state}] - the zone's objects with no name key
        whose template's name is a door, a gate, a portcullis, a collision wall... (puzzlefile.is_blocker:
        DynaTrigger_KT_DoorCollision, CL-StormLordTempleGate), read now (name: the template's name). One gone from
        memory has been taken away (a door collision a trigger removes when the way opens). state: its ObjectStateBehavior's
        current state read now (_state_fill - statemem.py, not confirmed in the game yet), None while not known. None and
        why as mobs() - never "none" then: not read isn't gone. Never raises."""
        return self._live("blockers")

    def duels(self):
        """(duels, why): duels = [{name, pos (x, y, z), yaw, gid, template, duel, behavior, phase, phase_name, round, parts,
        players, teams, mine, pvp, active}] - the zone's duel circles (objects with no name key holding a duel behaviour:
        bossmem.is_duel_object - looked for only while duels are asked for, the duelavoid setting), read now, and each
        one's battle (bossmem.duel_of - None each when it can't be read; mine: the wizard's own). None and why as mobs().
        NOT CONFIRMED in the game yet (bossmem.py --duels is the check). Never raises."""
        try:
            with self.lock:
                self._duel_asked = time.monotonic()
            got, why = self._live("duels")
            if got is None:
                return None, why
            if not got:
                return got, ""
            import bossmem
            st = self.st
            bm, _ = self._boss_reader(st) if st is not None else (None, "")
            with self.lock:
                ok = bm is not None and self.st is st and bm.st is st
                me = None
                if ok:
                    try:
                        gc = st.gameclient()
                        me = st.player_gid(gc) if ptr_ok(gc) else None
                    except ReadError:
                        me = None
                by_gid = {v[0]: obj for obj, v in self._duels.items()}
                for d in got:
                    obj = by_gid.get(d["gid"])
                    info = bm.duel_of(obj, me) if ok and obj else None
                    for k in bossmem.DUEL_FIELDS:
                        d[k] = info.get(k) if info else None
            return got, ""
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the duels failed (%r)" % (e,)

    def _live(self, which):
        """mobs() / items() / blockers(): the objects thread's of that kind still the same live objects, their places read
        now"""
        try:
            with self.lock:
                self._obj_asked = time.monotonic()
                if self._obj_thread is None or not self._obj_thread.is_alive():
                    self._obj_thread = threading.Thread(target=self._objects_run, name="objects", daemon=True)
                    self._obj_thread.start()
                st, cz, why = self.st, self._obj_cz, self._obj_why
                objs = list({"mobs": self._objs, "items": self._items, "blockers": self._blockers,
                             "duels": self._duels}[which].items())
            if st is None or not cz or why:
                return None, why or "not attached"
            out, gids, live = [], set(), []
            for obj, v in objs:
                gid, name, tname, vt = v[:4]
                if gid in gids:
                    continue
                raw = st.p.try_read(obj, OBJ_SPAN)
                if raw is None:
                    continue
                # (still the same live object of this zone: a destroyed one's vtable is changed by its destructor,
                # freed and reused memory holds something else)
                if (struct.unpack_from("<Q", raw, 0)[0] != vt or struct.unpack_from("<Q", raw, DATA["co_gid"])[0] != gid
                        or struct.unpack_from("<Q", raw, DATA["co_zone"])[0] != cz):
                    continue
                pos = self._mob_pos(st, obj, raw)
                if pos is not None:
                    gids.add(gid)
                    out.append({"name": name, "pos": pos[:3], "yaw": pos[3], "gid": gid, "template": tname})
                    live.append((obj, gid, out[-1]))
                    if which == "items":
                        key, kind = (v[4], v[5]) if len(v) >= 6 else ("", "item")
                        out[-1].update(key=key, kind=kind, src="mem")
                        if not name and key:
                            out[-1]["name"] = self._thing_name(key)
            # (what each mob is - its title, rank, max health: bossmem.py, once per mob object - the walker's route
            # doesn't wait for it: a reader not made yet leaves them None)
            if which == "mobs" and live:
                try:
                    self._boss_fill(st, live)
                except Exception as e:  # noqa: BLE001 - the mobs without it (said once a minute)
                    for _obj, _gid, m in live:
                        for k in ("title", "title_id", "rank", "health", "school", "boss", "kind"):
                            m.setdefault(k, None)
                    if time.monotonic() >= self._boss_said:
                        self._boss_said = time.monotonic() + 60.0
                        self.log("bossmem: the mobs' titles couldn't be read (%r)" % (e,))
            # (each door's state - its ObjectStateBehavior: statemem.py, read now; None while not known - the reader not
            # made yet, a build it can't read: the doors as before)
            if which == "blockers" and live:
                try:
                    self._state_fill(st, live)
                except Exception as e:  # noqa: BLE001 - the doors without it (said once a minute)
                    for _obj, _gid, d in live:
                        d["state"] = None
                    if time.monotonic() >= self._state_said:
                        self._state_said = time.monotonic() + 60.0
                        self.log("statemem: the doors' states couldn't be read (%r)" % (e,))
            return out, ""
        except Exception as e:  # noqa: BLE001 - never into the server
            return None, "reading the %s failed (%r)" % (which, e)

    @staticmethod
    def _mob_pos(st, obj, raw):
        """a mob's x, y, z, yaw: its body's (where it's drawn, moving, facing) when it has one - as the wizard's -
        else the object's own copy (pitch, roll, yaw follow x, y, z in both); yaw None if it isn't a number; None if
        the position isn't"""
        o, p = st.o, st.p

        def pose(raw24):
            x, y, z, _pitch, _roll, yaw = struct.unpack("<6f", raw24)
            if not finite(x, y, z):
                return None
            return (x, y, z, (yaw + math.pi) % (2 * math.pi) - math.pi if finite(yaw) else None)
        try:
            anim = p.u64(obj + o["co_anim"]) if o.get("co_anim") else 0
            body = p.u64(anim + o["anim_body"]) if ptr_ok(anim) and o.get("anim_body") else 0
            if ptr_ok(body) and p.try_read(body + DATA["body_parent"], 8) == struct.pack("<Q", obj):
                b = p.try_read(body + o["body_pos"], 24)
                got = pose(b) if b else None
                if got is not None:
                    return got
        except ReadError:
            pass
        at = o.get("co_location") or 0xA8
        return pose(raw[at:at + 24]) if len(raw) >= at + 24 else None

    def _names(self):
        """{display key: English name} of the game's *Mobs name tables (Root.wad); None while they can't be read
        (tried again after a minute)"""
        if self._mob_names is None and time.monotonic() >= self._names_retry:
            names = {}
            try:
                import os
                import navgeo
                root = os.path.join(self.game_dir or navgeo.GAME_DIR, "Data", "GameData", "Root.wad")
                files = navgeo.read_wad_files(root, ["Locale/en-US/%s.lang" % t for t in MOB_TABLES + ITEM_TABLES])
                for tbl in MOB_TABLES + ITEM_TABLES:
                    data = files.get("Locale/en-US/%s.lang" % tbl)
                    if not data:
                        continue
                    lines = data.decode("utf-16").split("\r\n")
                    # (a heading line, then key, comment, text - a text's own line breaks written as \n)
                    for i in range(1, len(lines) - 2, 3):
                        if lines[i].isdigit():
                            text = re.sub(r"\s+", " ", lines[i + 2].replace("\\r", " ").replace("\\n", " ")).strip()
                            names["%s_%s" % (tbl, lines[i])] = text
            except Exception as e:  # noqa: BLE001
                self.log("navmem: the mob names couldn't be read (%r)" % (e,))
            if names:
                self._mob_names = names
                self.log("navmem: %d mob names read" % len(names))
            else:
                self._names_retry = time.monotonic() + 60.0
        return self._mob_names

    def _thing_name(self, key, want=None):
        """a thing's name (its display key's text) from placements' name tables - one persistent set, not questmem's,
        whose limit would drop the goal's tables; "" while its table isn't read (want gets the key then)"""
        try:
            import placements                       # (here: placements imports navmem)
            t = placements.text(key, self.game_dir)
        except Exception:  # noqa: BLE001 - no name
            t = None
        if t is None and want is not None:
            want.append(key)
        return t or ""

    def _set_objs(self, cz, objs, why, items=None, blockers=None, duels=None):
        with self.lock:
            self._obj_cz, self._objs, self._obj_why, self._items = cz, objs, why, items or {}
            self._blockers = blockers or {}
            self._duels = duels or {}

    def _duel_look(self, st, cands):
        """(the objects thread) which of cands [(object, gid, template name, vtable)] - objects with no name key that aren't
        mobs, things or blockers - are duel circles: {object: (gid, template name, template name, vtable)}. Only while
        duels() is asked for (OBJ_IDLE); each object looked at once (bossmem.is_duel_object, under the lock), kept per
        (object, gid, vtable); {} while the boss reader isn't made"""
        with self.lock:
            if time.monotonic() - self._duel_asked > OBJ_IDLE:
                return {}
        bm, _ = self._boss_reader(st)
        out = {}
        with self.lock:
            if bm is None or bm.st is not st or self.st is not st:
                return {}
            seen = self._duel_seen
            if len(seen) > 20000:
                seen.clear()
            for obj, gid, tname, vt in cands:
                key = (obj, gid, vt)
                if key not in seen:
                    seen[key] = bool(bm.is_duel_object(obj))
                if seen[key]:
                    out[obj] = (gid, tname, tname, vt)
        return out

    def _objects_run(self):
        """the objects thread: the zone's mobs looked for every OBJ_QUICK s (see the top) while anyone asks"""
        # (carried on from where it stopped when nobody asked: what it found is checked again at every read)
        regions, last_full, zone_seen, zone_from, cache = self._obj_state
        while True:
            t0 = time.monotonic()
            with self.lock:
                if t0 - self._obj_asked > OBJ_IDLE:
                    self._obj_thread = None
                    self._obj_state = (regions, last_full, zone_seen, zone_from, cache)
                    return
                st = self.st
            try:
                names = self._names() if st is not None else None
                gc = st.gameclient() if st is not None else 0
                cz = st.zone_ptr(gc) if ptr_ok(gc) else 0
                if st is None:
                    self._set_objs(0, {}, "not attached")
                elif not cz:
                    self._set_objs(0, {}, "not in a zone")
                elif names is None:
                    self._set_objs(0, {}, "the mob names couldn't be read (Root.wad)")
                else:
                    # (a new zone: its ClientZone or its name changed - the old one's may be freed and its memory
                    # given to the new one)
                    zone = (cz, st.zone(gc))
                    if zone != zone_seen:
                        zone_seen, zone_from, regions, cache = zone, t0, None, {}
                        self._set_objs(0, {}, "looking at the new zone")
                    full = (regions is None or not regions or t0 - last_full >= OBJ_FULL
                            or (t0 - zone_from < OBJ_SETTLE and t0 - last_full >= OBJ_SETTLE_EVERY))
                    found, where = st.scan_objects(cz, None if full else regions)
                    if full:
                        regions, last_full = where, t0
                    objs, items, doors, want, cands = {}, {}, {}, [], []
                    # (the templates the zone's triggers' use events may be fired by - puzzlefile's, as kept: none till
                    # built; no file read but a stat)
                    try:
                        import puzzlefile
                        uses = puzzlefile.use_templates(zone[1], self.game_dir)
                    except Exception:  # noqa: BLE001 - none: as before
                        uses = frozenset()
                    for obj in found:
                        raw = st.p.try_read(obj, OBJ_SPAN)
                        if raw is None:
                            continue
                        vt = struct.unpack_from("<Q", raw, 0)[0]
                        vname = st.tn.of_vtable(vt) if st.m.in_section(vt, ".rdata") else None
                        if not vname or not vname.endswith("ClientObject"):
                            continue                        # (not a live one: destroyed - its base class's vtable - or freed)
                        gid = struct.unpack_from("<Q", raw, DATA["co_gid"])[0]
                        tpl = struct.unpack_from("<Q", raw, DATA["co_template"])[0]
                        k = st.template_kind(tpl, names, cache)
                        if k and k[0]:
                            objs[obj] = (gid, k[0], k[1], vt)
                        elif k and k[3] and k[4] != "mob":
                            # (a thing with a name key: its name from navmem's tables, else placements' - its table read
                            # in placements' worker, outside this thread: "" till then)
                            items[obj] = (gid, k[2] or self._thing_name(k[3], want), k[1], vt, k[3], k[4])
                        elif k and not k[3] and k[1] and k[4] != "mob" and _is_blocker(k[1]):
                            # (no name key, a door's or a gate's template name: a blocker - its name its template's)
                            doors[obj] = (gid, k[1], k[1], vt)
                        elif k and not k[3] and k[1] and k[4] != "mob" and k[1] in uses:
                            # (no name key, a template a use event of the zone's triggers may be fired by - a lever the
                            # game names nowhere: a thing of kind "use", no name, no key - /items' - its live place stands
                            # for its placement's)
                            items[obj] = (gid, "", k[1], vt, "", "use")
                        elif k and not k[3] and k[4] != "mob":
                            # (no name key, nothing else: maybe a duel circle - looked at below, only while asked for)
                            cands.append((obj, gid, k[1], vt))
                    if want:
                        try:
                            import placements
                            placements.want_names(want, self.game_dir)
                        except Exception as e:  # noqa: BLE001 - the names stay "" (said once a minute)
                            if time.monotonic() >= self._names_said:
                                self._names_said = time.monotonic() + 60.0
                                self.log("navmem: the things' name tables couldn't be asked for (%r)" % (e,))
                    # (the duel circles - other players' battles: only while duels() is asked for - duelavoid)
                    try:
                        duels = self._duel_look(st, cands) if cands else {}
                    except Exception:  # noqa: BLE001 - none: as before
                        duels = {}
                    self._set_objs(cz, objs, "", items, doors, duels)
                    self.obj_stats = {"objects": len(found), "mobs": len(objs), "items": len(items), "doors": len(doors),
                                      "duels": len(duels), "uses": sum(1 for v in items.values() if v[5] == "use"),
                                      "full": full,
                                      "ms": round((time.monotonic() - t0) * 1000), "regions": len(regions or ())}
            except Exception as e:  # noqa: BLE001 - tried again next time
                self._set_objs(0, {}, "the zone's objects couldn't be read (%r)" % (e,))
            time.sleep(max(0.5, OBJ_QUICK - (time.monotonic() - t0)))


# ============================================================================ command line
def _motion_cli(nm, seconds, every=0.15):
    """--mobs --motion SECONDS: the zone's mobs read every `every` s through a navroute.MobMotion (as the vision helper
    feeds it), a line a mob every 2 s (the nearest 12) and a summary at the end - what tunes MOVE_MIN, MOTION_AHEAD_S,
    MOTION_FIT and PASS_GAP and confirms a walking mob's body yaw is its way (agree near 1): its speed (units / s),
    walking or standing and for how long, its way against its facing, its walks and stops, its jumps (respawns,
    teleports), and how often its position changes between readings (every frame, or in steps)"""
    import navroute
    mm = navroute.MobMotion()
    stats = {}                  # gid -> {name, n, changed, last, speeds, agrees, gaps}
    t_end, said = time.time() + seconds, 0.0
    reads, me = 0, None
    while time.time() < t_end:
        t0 = time.time()
        r, _ = nm.read(path=False, wait=5)
        mobs, why = nm.mobs()
        now = time.time()
        if r is not None and r.get("pos"):
            me = r["pos"]
        if mobs:
            reads += 1
            mm.update(now, mobs, me)
            for m in mobs:
                s = stats.setdefault(m["gid"], {"name": m["name"], "n": 0, "changed": 0, "last": None, "speeds": [],
                                                "agrees": [], "gaps": []})
                s["n"] += 1
                p = (round(m["pos"][0], 2), round(m["pos"][1], 2))
                if s["last"] is not None and p != s["last"][1]:
                    s["changed"] += 1
                    s["gaps"].append(now - s["last"][0])
                if s["last"] is None or p != s["last"][1]:
                    s["last"] = (now, p)
                i = mm.info(m["gid"])
                if i.get("moving") and i.get("speed") is not None:
                    s["speeds"].append(i["speed"])
                if i.get("agree") is not None:
                    s["agrees"].append(i["agree"])
        if now - said >= 2.0:
            said = now
            print("-- %s  %s mobs (%s)  the wizard's speed %s" % (
                time.strftime("%H:%M:%S"), len(mobs) if mobs else 0, why or "ok",
                "%.0f" % mm.my_speed() if mm.my_speed() else "not known"))
            near = sorted(mobs or [], key=lambda q: math.hypot(q["pos"][0] - me[0], q["pos"][1] - me[1]) if me else 0)[:12]
            for m in near:
                i = mm.info(m["gid"])
                state = ("walking %.1f s" % i["walk_s"] if i.get("moving") else "standing %.1f s" % i["still_s"]
                         if i.get("moving") is False else "not known")
                print("   %-26s %-9s %s  speed %s  way vs facing %s  jumps %s  legs %s" % (
                    m["name"], "%#x" % m["gid"], state, "%.0f" % i["speed"] if i.get("speed") is not None else "-",
                    i.get("agree"), i.get("jumps"), i.get("legs", [])[-4:]))
        time.sleep(max(0.0, every - (time.time() - t0)))
    print("== %d readings in %.0f s" % (reads, seconds))
    for gid, s in sorted(stats.items(), key=lambda kv: -len(kv[1]["speeds"])):
        i = mm.info(gid)
        sp = sorted(s["speeds"])
        gaps = sorted(s["gaps"])
        walks = [d for w, d in i.get("legs", []) if w]
        stops = [d for w, d in i.get("legs", []) if not w]
        print("   %-26s %-9s readings %d, position changed %d (median %.2f s apart)  speed walking: median %s max %s  "
              "way vs facing: mean %s  walks %s  stops %s  jumps %s" % (
                  s["name"], "%#x" % gid, s["n"], s["changed"], gaps[len(gaps) // 2] if gaps else 0.0,
                  "%.0f" % sp[len(sp) // 2] if sp else "-", "%.0f" % sp[-1] if sp else "-",
                  "%.2f" % (sum(s["agrees"]) / len(s["agrees"])) if s["agrees"] else "-",
                  [round(d, 1) for d in walks[-6:]], [round(d, 1) for d in stops[-6:]], i.get("jumps", 0)))


def _main():
    import argparse
    ap = argparse.ArgumentParser(description="read-only: the wizard's position and the quest goal")
    ap.add_argument("-n", type=int, default=3)
    ap.add_argument("-i", type=float, default=0.5)
    ap.add_argument("--path", action="store_true")
    ap.add_argument("--mobs", action="store_true", help="the zone's mobs too")
    ap.add_argument("--goal", action="store_true", help="the quest's goal line too (questmem.py)")
    ap.add_argument("--motion", type=float, default=0, metavar="SECONDS",
                    help="with --mobs: watch the mobs walk for this long (read every 150 ms) - each one's speed, its way "
                         "against its facing, its walks and stops, its jumps (navroute.MobMotion's numbers to tune)")
    a = ap.parse_args()
    nm = NavMem(log=print)
    if a.mobs and a.motion > 0:
        _motion_cli(nm, a.motion)
        print(nm.describe())
        return
    for k in range(a.n):
        t0 = time.perf_counter()
        r, why = nm.read(path=a.path, wait=30)
        ms = (time.perf_counter() - t0) * 1000
        if r is None:
            print("%7.1f ms  ERR %s" % (ms, why))
        else:
            fmt = lambda v: "-" if v is None else "(%.1f, %.1f, %.1f)" % tuple(v)
            print("%7.1f ms  zone %s  pos %s yaw %s [%s]  goal %s hops %s  target %s dist %s  quest %s/%s/%s  path %s"
                  % (ms, r["zone"], fmt(r["pos"]), None if r["yaw"] is None else round(r["yaw"], 4), r["source"],
                     fmt(r["goal"]), r["hops"], fmt(r["target"]), None if r["dist"] is None else round(r["dist"], 1),
                     r["enabled"], r["quest"], r["goalid"], "-" if r["path"] is None else len(r["path"])))
            for k2 in ("why_player", "why_quest"):
                if r[k2]:
                    print("           " + k2 + ": " + r[k2])
            if a.mobs:
                mobs, why = nm.mobs()
                print("           mobs: %s %s" % (why or "%d" % len(mobs), nm.obj_stats))
                for mb in sorted(mobs or [], key=lambda q: math.hypot(q["pos"][0] - r["pos"][0], q["pos"][1] - r["pos"][1]) if r["pos"] else 0)[:15]:
                    off = ""
                    if mb.get("yaw") is not None and r["pos"]:
                        dx, dy = r["pos"][0] - mb["pos"][0], r["pos"][1] - mb["pos"][1]
                        c = (dx * -math.sin(mb["yaw"]) + dy * -math.cos(mb["yaw"])) / (math.hypot(dx, dy) or 1.0)
                        off = "  yaw %.2f, you %.0f deg off its facing" % (mb["yaw"], math.degrees(math.acos(max(-1.0, min(1.0, c)))))
                    what = "%s rank %s health %s %s%s" % (mb.get("title"), mb.get("rank"), mb.get("health"), mb.get("school"),
                                                          " BOSS" if mb.get("boss") else "")
                    print("             %-24s %-30s (%.0f, %.0f, %.0f)%s  %s" % ((mb["name"], mb["template"]) + tuple(mb["pos"]) + (off, what)))
            if a.goal:
                g, why = nm.goal(r, wait=30)
                print("           goal: " + ("%r (from %s) %s %s %s/%s mob %r item %r npc %r - %.2f ms" % (
                    g["text"], g["from"], g["type"], g["status"], g["count"], g["total"], g["mob"], g["item"], g["npc"],
                    g["ms"]) if g else "none (%s)" % why))
        if k + 1 < a.n:
            time.sleep(a.i)
    print(nm.describe())


if __name__ == "__main__":
    _main()
