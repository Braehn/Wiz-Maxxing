"""handmem - READ-ONLY reader of the spell cards in the wizard's hand during a battle, and the wizard's own pips, in a
running Wizard101 client (WizardGraphicalClient.exe), for the vision helper's /cards.

    hm = HandMem(st, log=print)     # st: navmem's attached game (navmem._Attached) or a LightAttach; ~0.5 s once
    r = hm.read()                   # a dict (see HandMem.read) - never raises
    print(answer(r, ""))            # the lines /cards answers
    p = hm.phase()                  # the round's phase alone, cheaply (no spell read - see HandMem.phase): /phase

    r, why = navmem.NavMem().cards()   # the same through navmem's own attached game, under its lock (vision.py's way)

    python handmem.py [-n 3] [-i 2] [--json]        readings from the command line (and how long each took)
    python handmem.py --phase -n 100 -i 0.1          the round's phase alone, 10 a second (what the hand does as a
                                                     card's clicked, its target clicked, the round played)

SAFETY. The game is opened by navmem.py's Proc - PROCESS_VM_READ | PROCESS_QUERY_INFORMATION (falling back to
PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION) and nothing else - and only read: ReadProcessMemory, plus
VirtualQueryEx / QueryWorkingSetEx and the module / toolhelp enumeration navmem.py uses to find it. Nothing is ever
written, allocated, injected, hooked, suspended or debugged; no window is touched (not even asked about - only the
command line looks at which one is in front, to pick the game) and no input is sent. Every offset is found by NAME in
a copy of the game's code read with ReadProcessMemory (its own reflection registration), or checked by a type name /
window name the object carries before it's used.

FAILS SOFT. HandMem.read() never raises: whatever goes wrong comes back as why (a card that can't be read: its own
why, the others still read), and 'ms' and 'planning' are always set. A value that can't be read for sure is None,
never a guess. The hand is only "settled" - the cards to play - when the cards on screen are exactly the wizard's
own hand list (see read); while the game is dealing, discarding or laying the cards out it says 'hand changing'
(callers ask again every 100 ms, up to 1.5 s). The constructor raises (LookupError: a reflected class or property
isn't in this build) - NavMem.cards() catches that and answers (None, why).

WHAT IS READ (offsets of the client of 2026-10-13, build HAND_BUILD; each is found again by name or checked by type
or window name - in another build a place that fails is looked for, and kept once a second card window agrees):

  GUI      [exe + WizardGUIManager static] (navmem's GUIMGR_HUD candidates, checked by the HUD's window name
             "windowHUD") -> the root window: the pointer in the manager whose children hold the HUD (+0x118 now)
             -> its children (Window.m_Children: a vector of SharedPointer<Window>, 16 bytes each) down to the window
                of type CombatPlanningPhaseWindow -> SpellSelectionWindow -> the window named "Hand"
             -> its SpellCheckBox children "Card1".."Card7" and "PetCard": on screen left to right by their left
                edge (Window.m_Window.left - Card1 is the rightmost; windows are reused as cards come and go, so a
                name is no place)
             shown: Window.m_Flags bit 0 - on the planning window: the planning phase; on a card: it's on screen (a
                discarded / not yet dealt card's window is hidden, its old spell still in it; out of a battle the
                windows read shown with no spell at all - so nothing is read from them out of a battle)
             box (v1.0.0, NOT CHECKED against the screen yet): a card's place in the root - its m_Window (in the Hand
                window's units) plus the left / top of every window on the way down from the root (the root's own left
                / top not added: bossmem.combatant_windows' rule for the plates) - in GUI units, the root's rect beside
                it (the client: 1827 x 1027 at 2560x1440). Whether a zoomed card (the mouse on it) or the hand sliding
                back to the middle after a card leaves changes m_Window isn't known: AutoFarmer's KillCalc.ahk
                MemBoxCheck compares these boxes with the ones /hand sees on the screen, log only, before any is clicked
             the card's spell: the pointer in the SpellCheckBox whose type is GraphicalSpell (+0x450 now)
  me       the pointer in the SpellSelection window whose type is ClientCombatParticipant (+0x358 now) - alive only in a
             battle (a destroyed one's vtable is its base class's): CombatParticipant.m_ownerID.m_full,
             m_primaryMagicSchoolID, m_playerHealth, m_maxPlayerHealth, m_pipCount -> PipCount (m_genericPips,
             m_powerPips, m_<school>Pips, m_shadowPips), m_pHand -> Hand.m_spellList (a std::list: head, size; node +0
             next, +0x10 the spell) - the same GraphicalSpells as the shown cards, Card1..Card7 order
  spell    GraphicalSpell : Spell - Spell.m_templateID, m_enchantment (the enchantment's template id, 0 none),
             m_pipCost -> SpellRank (m_spellRank: the pips, m_<school>Pips / m_shadowPips: pips of a kind it wants
             besides, m_xPipSpell), m_accuracy, m_treasureCard, m_itemCard, m_magicSchoolID, m_paramOverrides
             (SpellEffectParamOverride m_effectIndex, m_paramValue: a number of the template's own changed for this
             card)
  template [exe + TemplateManager static] -> +0x30 a std::map<u32 template id, SharedPointer<template>> (22k):
             node +0 left, +8 parent, +0x10 right, +0x19 isnil, +0x20 key, +0x28 the template - checked by its type
             name (SpellTemplate, TieredSpellTemplate...). SpellTemplate.m_name, m_displayName (a name-table key,
             "Spells_00005060" or "Spells_Ice Trap"), m_sMagicSchoolName, m_sTypeName, m_effects (a tree: SpellEffect
             m_effectType, m_effectParam, m_effectTarget, m_numRounds, m_sDamageType; RandomSpellEffect /
             VariableSpellEffect / EffectListSpellEffect / CountBasedSpellEffect m_effectList, ConditionalSpellEffect
             m_elements -> ConditionalSpellElement.m_pEffect, TargetCountSpellEffect m_effectLists)
  names    m_displayName "<table>_<key>" -> Root.wad Locale/en-US/<table>.lang (UTF-16: a heading line, then key,
             comment, text for each entry; any key - parse_lang)
  enums    kSpellEffects / the effect target's names: each option's name string is loaded for the registration and
             its value stored just after (mov dword [rsp+30h], imm32) - read from the code, checked by known values
  Property offsets: GetType's registration code -  lea r8|r9,[reg+OFFSET] ... lea rdx|r8,"m_name" ... call AddProperty
"""
import json
import os
import re
import struct
import sys
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
import navmem as N                   # noqa: E402

# The build the places below were seen in (navmem.KNOWN_BUILD, 2026-10-13): there a place that fails is the object not
# being there now (out of a battle); in another one it's looked for (and kept once a second window agrees)
HAND_BUILD = "6A9721E9-370E000"
KNOWN = {"root_in_gm": 0x118, "card_spell": 0x450, "tm_rva": 0x3322800, "tm_map": 0x30, "ss_participant": 0x358}
SCHOOL_PIPS = ("balance", "death", "fire", "ice", "life", "myth", "storm")
ASTRAL = ("sun", "star", "moon")
# The schools' ids (KingsIsle's hash of the name; a participant's m_primaryMagicSchoolID, a spell's m_magicSchoolID) -
# checked against the cards in hand: a card's id and its template's school name win over this list
SCHOOL_IDS = {72777: "ice", 78483: "sun", 2330892: "life", 2343174: "fire", 2625203: "star", 2448141: "myth",
              2504141: "moon", 78318724: "death", 83375795: "storm", 1027491821: "balance", 1429009101: "shadow"}
# reflected classes read at attach, and the properties that must be found in each (the rest are read with .get)
# A container whose effect list is its base class's, registered there (its own property set is empty)
INHERIT = {"RandomPerTargetSpellEffect": "RandomSpellEffect"}
CLASSES = ("Window", "Spell", "SpellRank", "SpellTemplate", "SpellEffect", "CombatParticipant", "Hand", "PipCount",
           "EffectListSpellEffect", "RandomSpellEffect", "RandomPerTargetSpellEffect", "VariableSpellEffect",
           "ConditionalSpellEffect", "ConditionalSpellElement", "CountBasedSpellEffect", "TargetCountSpellEffect",
           "SpellEffectParamOverride")
NEED = {"Window": ("m_sName", "m_Children", "m_Flags", "m_Window"),
        "Spell": ("m_templateID", "m_enchantment", "m_pipCost", "m_treasureCard", "m_itemCard", "m_accuracy"),
        "SpellRank": ("m_spellRank", "m_shadowPips", "m_xPipSpell") + tuple("m_%sPips" % s for s in SCHOOL_PIPS),
        "SpellTemplate": ("m_name", "m_displayName", "m_sMagicSchoolName", "m_sTypeName", "m_effects"),
        "SpellEffect": ("m_effectType", "m_effectParam", "m_numRounds", "m_effectTarget"),
        "CombatParticipant": ("m_ownerID.m_full", "m_primaryMagicSchoolID", "m_playerHealth", "m_maxPlayerHealth",
                              "m_pipCount", "m_pHand"),
        "Hand": ("m_spellList",),
        "PipCount": ("m_genericPips", "m_powerPips", "m_shadowPips") + tuple("m_%sPips" % s for s in SCHOOL_PIPS)}
VT_CLASSES = ("GraphicalSpell", "Spell", "SpellCheckBox", "CombatPlanningPhaseWindow", "SpellSelectionWindow",
              "ClientCombatParticipant")
WINDOW_NAME = N.DATA["window_name"]   # (Window.m_sName: +0x50, as navmem reads the HUD's)
RESCAN_EVERY = 2.0                    # s between looks for a place that failed (another build only)


# ============================================================================ the game's code (a copy, read-only)
class Image:
    """READ-ONLY: a copy of the game's .text / .rdata / .data read with ReadProcessMemory, and every RIP-relative LEA
    and E9 jump in its code - to find a reflected class by its name: the name string in .rdata, the GetType functions
    that LEA it (and the .data static each caches its Type* in), the vtables whose slot 0 leads there (directly or
    through an E9 thunk)"""

    def __init__(self, st):
        import numpy as np
        self.st, self.m = st, st.m
        base = st.m.base
        self.secs = {}
        for name in (".text", ".rdata", ".data"):
            va, vs, _ = st.m.sections[name]
            parts = []
            for off in range(0, vs, 0x100000):
                n = min(0x100000, vs - off)
                parts.append(st.p.try_read(base + va + off, n) or b"\0" * n)
            self.secs[name] = (base + va, b"".join(parts))
        t0, text = self.secs[".text"]
        tb = np.frombuffer(text, dtype=np.uint8)
        rex = (tb[:-6] == 0x48) | (tb[:-6] == 0x4C)
        idx = np.flatnonzero(rex & (tb[1:-5] == 0x8D) & ((tb[2:-4] & 0xC7) == 0x05))
        d = (tb[idx + 3].astype(np.int64) | (tb[idx + 4].astype(np.int64) << 8) | (tb[idx + 5].astype(np.int64) << 16)
             | (tb[idx + 6].astype(np.int64) << 24))
        d = np.where(d >= 1 << 31, d - (1 << 32), d)
        self.lea_at = idx.astype(np.int64) + t0
        self.lea_tgt = self.lea_at + 7 + d
        j = np.flatnonzero(tb[:-4] == 0xE9)
        dj = (tb[j + 1].astype(np.int64) | (tb[j + 2].astype(np.int64) << 8) | (tb[j + 3].astype(np.int64) << 16)
              | (tb[j + 4].astype(np.int64) << 24))
        dj = np.where(dj >= 1 << 31, dj - (1 << 32), dj)
        self.jmp_at = j.astype(np.int64) + t0
        self.jmp_tgt = self.jmp_at + 5 + dj
        r0, rdata = self.secs[".rdata"]
        self.rdata_q = np.frombuffer(rdata[:len(rdata) // 8 * 8], dtype=np.uint64)

    def strings(self, s):
        """addresses in .rdata of the NUL-terminated string s (preceded by a NUL)"""
        r0, rdata = self.secs[".rdata"]
        out, needle, i = [], b"\0" + s.encode() + b"\0", 0
        while True:
            i = rdata.find(needle, i)
            if i < 0:
                return out
            out.append(r0 + i + 1)
            i += 1

    def code_at(self, addr, n):
        """n bytes of the code copy at addr (b"" outside .text)"""
        t0, text = self.secs[".text"]
        return text[addr - t0: addr - t0 + n] if t0 <= addr < t0 + len(text) else b""

    def rdata_str(self, addr, n=64):
        r0, rdata = self.secs[".rdata"]
        return rdata[addr - r0: addr - r0 + n].split(b"\0")[0] if r0 <= addr < r0 + len(rdata) else b""

    def func_start(self, addr):
        """the start of the function holding addr: after the int3 / ret padding before it"""
        t0, text = self.secs[".text"]
        i = addr - t0
        while i > 0 and not (text[i - 1] == 0xCC and text[i - 2] in (0xCC, 0xC3)):
            i -= 1
            if addr - t0 - i > 0x400:
                return None
        return t0 + i

    def get_types(self, name):
        """[(GetType function, static Type** or None, [vtables])] for class name"""
        import numpy as np
        out = []
        for sa in self.strings(name):
            for la in self.lea_at[self.lea_tgt == sa]:
                la = int(la)
                fn = self.func_start(la)
                if fn is None or la - fn > 0x80:
                    continue
                code = self.code_at(la, 0x40)
                static = None
                k = code.find(b"\x48\x89\x05", 7)          # the first mov [rip+x], rax after the LEA: the cached Type*
                if 0 <= k < 0x30:
                    static = la + k + 7 + struct.unpack_from("<i", code, k + 3)[0]
                entry = {fn} | {int(a) for a in self.jmp_at[self.jmp_tgt == fn]}
                vts = []
                r0 = self.secs[".rdata"][0]
                for e in entry:
                    for qi in np.flatnonzero(self.rdata_q == np.uint64(e)):
                        vts.append(r0 + int(qi) * 8)
                out.append((fn, static, sorted(vts)))
        return out


# lea r8/r9(d), [base + disp8/disp32]: REX 0x44/0x45/0x4C/0x4D, 8D, modrm mod 1|2
LEA_OFF = re.compile(rb"[\x44\x45\x4C\x4D]\x8D([\x40-\x4F\x80-\x8F])", re.DOTALL)
IDENT = re.compile(rb"m_[A-Za-z0-9_.]+")


def _off_before(code, end, want_reg):
    """the displacement of the last lea r8 (want_reg 0) / r9 (1), [reg+disp] in code[:end] (within 0x30 bytes), or None"""
    best = None
    for mt in LEA_OFF.finditer(code, max(0, end - 0x30), end):
        modrm = mt.group(1)[0]
        mod, reg, rm = modrm >> 6, (modrm >> 3) & 7, modrm & 7
        rex = code[mt.start()]
        p = mt.end()
        if rm == 4:
            # [r12 + disp]: a SIB byte of base r12 alone (24h, no index; REX.B set) - the zero register in build
            # 6AF1C8A0-3B69000's ClientWizEquipmentBehavior registration (2026-11-12). [rsp + disp] is the stack: never
            if p >= end or code[p] != 0x24 or not (rex & 1):
                continue
            p += 1
        if reg != want_reg or (mod == 0 and rm == 5) or not (rex & 4):
            continue
        if mod == 1:
            disp, ln = struct.unpack_from("<b", code, p)[0], p + 1
        else:
            disp, ln = struct.unpack_from("<i", code, p)[0], p + 4
        if ln <= end and 0 <= disp < 0x10000:
            best = disp
    return best


def class_props(img, name, max_len=0x6000):
    """({property name: (offset, adder rva)}, GetType function, [vtables]) for class name, read from its registration
    code: GetType's first-call path creates the Type and registers each property inline -
        lea r8|r9, [reg + OFFSET]     (the property's offset: reg is 0 there)
        lea rdx|r8, [rip + "m_name"]  (its name, a C string in .rdata)
        call AddProperty<T>
    in the first of the functions after GetType that LEAs an m_ name. Nothing is guessed: a name whose offset isn't
    found isn't returned; ({}, None, []) when the class isn't in this build"""
    st = img.st
    out, gt, vts = {}, None, []
    for fn, static, v in img.get_types(name):
        if static is None or not v:
            continue
        gt, vts = fn, v
        code = img.code_at(fn, max_len)
        segs, pos = [], 0
        for mm in re.finditer(rb"\xCC{2,}", code):
            segs.append((pos, mm.start()))
            pos = mm.end()
        start = lim = None
        for a, b in segs[1:7]:
            for mm in re.finditer(rb"[\x48\x4C]\x8D[\x15\x05](....)", code[a:b], re.DOTALL):
                tgt = fn + a + mm.start() + 7 + struct.unpack("<i", mm.group(1))[0]
                if st.m.in_section(tgt, ".rdata") and IDENT.fullmatch(img.rdata_str(tgt)):
                    start, lim = a, b
                    break
            if start is not None:
                break
        if start is None:
            break
        for i in range(start, lim - 7):
            b0, b1, b2 = code[i], code[i + 1], code[i + 2]
            if b0 in (0x48, 0x4C) and b1 == 0x8D and b2 in (0x15, 0x05):   # lea rdx|r8, [rip+x]
                tgt = fn + i + 7 + struct.unpack_from("<i", code, i + 3)[0]
                if not st.m.in_section(tgt, ".rdata"):
                    continue
                s = img.rdata_str(tgt)
                if not IDENT.fullmatch(s):
                    continue
                off = _off_before(code, i, 0 if b2 == 0x15 else 1)    # (the name in rdx: the offset in r8; r8: r9)
                k = code.find(b"\xE8", i + 7, i + 0x20)
                adder = fn + k + 5 + struct.unpack_from("<i", code, k + 1)[0] - st.m.base if k >= 0 else None
                if off is not None and s.decode() not in out:
                    out[s.decode()] = (off, adder)
        break
    return out, gt, vts


def read_enum(img, first, prop, cls, log=None):
    """{value: 'kName'} of a reflected enum property's options: the option names run in .rdata after the first one, each
    followed by the property's name (the linker pools some elsewhere); in cls's registration code each name is loaded
    (RIP-relative) and its value stored just after - mov dword [rsp+30h], imm32 (or a register kept at 0: mov
    [rsp+30h], esi - ebx in build 6AF1C8A0-3B69000, 2026-11-12: any 32-bit register taken). {} when it can't be read"""
    import numpy as np
    try:
        at0 = img.strings(first)
        if not at0:
            return {}
        r0, rdata = img.secs[".rdata"]
        i = at0[0] - r0
        names, prev = [], prop
        for mt in re.finditer(rb"([\x20-\x7e]+)\x00+", rdata[i:i + 0x4000]):
            s = mt.group(1).decode()
            if s != prop and not re.fullmatch(r"k[A-Za-z0-9_]+", s):
                break
            if s != prop and prev == prop:
                names.append((r0 + i + mt.start(), s))
            prev = s
        t0, text = img.secs[".text"]
        gt = class_props(img, cls)[1]
        if gt is None:
            return {}
        lo = gt - t0
        seg = np.frombuffer(text[lo:lo + 0x10000], dtype=np.uint8).astype(np.int64)
        d = seg[:-3] | (seg[1:-2] << 8) | (seg[2:-1] << 16) | (seg[3:] << 24)
        d = np.where(d >= 1 << 31, d - (1 << 32), d)
        tgt = np.arange(len(d)) + t0 + lo + 4 + d
        out, at = {}, []
        # (mov [rsp+30h], r32: 89 /r, modrm 01 reg 100 - eax..edi; with REX 44 r8d..r15d)
        store = re.compile(rb"\xC7\x44\x24\x30(....)|\x44?\x89[\x44\x4C\x54\x5C\x64\x6C\x74\x7C]\x24\x30", re.DOTALL)
        for addr, s in names:
            hit = np.flatnonzero(tgt == addr)
            if not len(hit):
                continue
            k = int(hit[0]) + lo
            at.append(k)
            m = store.search(text, k, k + 0x40)
            if m:
                out.setdefault(struct.unpack("<i", m.group(1))[0] if m.group(1) else 0, s)
        # (names pooled elsewhere in .rdata - kStun, kSelf - aren't in the run: each value stored among the options' code
        # that has no name yet takes the k-string loaded RIP-relative just before it)
        if at:
            for m in re.finditer(rb"\xC7\x44\x24\x30(....)", text[min(at):max(at) + 0x200], re.DOTALL):
                v = struct.unpack("<i", m.group(1))[0]
                if v in out:
                    continue
                p = min(at) + m.start()
                for back in range(8, 0x70):
                    q = p - back
                    tg = t0 + q + 4 + struct.unpack_from("<i", text, q)[0]
                    if img.m.in_section(tg, ".rdata"):
                        sname = rdata[tg - r0: tg - r0 + 64].split(b"\0")[0]
                        if re.fullmatch(rb"k[A-Za-z0-9_]{2,}", sname) and rdata[tg - r0 - 1] == 0:
                            out[v] = sname.decode()
                            break
        return out
    except Exception as e:  # noqa: BLE001 - numbers only, then
        if log:
            log("handmem: the %s names couldn't be read (%r)" % (prop, e))
        return {}


# ============================================================================ the game without navmem's signatures
class LightAttach:
    """The game opened as navmem's _Attached does - its read-only Proc (PROCESS_VM_READ | PROCESS_QUERY_INFORMATION) -
    for the cards when a signature the walker needs (GameClient, location) isn't in this build: only the module, its
    type names and the GUI manager's candidate statics (navmem's GUIMGR_HUD signature, voted)"""

    def __init__(self, pid, log=None):
        self.log = log or (lambda msg: None)
        self.p = N.Proc(pid)
        try:
            self.m = N.Module(self.p)
            self.tn = N.TypeNamer(self.m)
            pat, _kinds = N.SIGS["GUIMGR_HUD"]
            rx, votes = re.compile(pat, re.DOTALL), Counter()
            for va, data in self.m.code():
                for mt in rx.finditer(data):
                    rip = va + mt.start(1) + 4 + struct.unpack("<i", mt.group(1))[0]
                    o1, o2 = struct.unpack("<i", mt.group(2))[0], struct.unpack("<i", mt.group(3))[0]
                    if o2 == o1 + 8:
                        votes[(rip, o1)] += 1
            cands = [k for k, _ in votes.most_common(16)]
            if (N.KNOWN["guimgr_rva"], N.KNOWN["gm_hud"]) not in cands:
                cands.append((N.KNOWN["guimgr_rva"], N.KNOWN["gm_hud"]))
            self.o = {"gm_candidates": cands}
        except Exception:
            self.p.close()
            raise

    def alive(self):
        return self.p.alive()

    def close(self):
        self.p.close()


# ============================================================================ the name tables
def parse_lang(data):
    """{key: text} of a .lang name table (UTF-16: a heading line, then key, comment, text for each entry - any key,
    "00005060" or "Ice Trap"; a text's own line breaks written as \\n, its markup <...> taken out)"""
    out = {}
    try:
        lines = data.decode("utf-16").split("\r\n")
    except (UnicodeDecodeError, AttributeError):
        return out
    for i in range(1, len(lines) - 2, 3):
        key = lines[i].strip()
        if key:
            text = re.sub(r"<[^>]*>", "", lines[i + 2].replace("\\r", " ").replace("\\n", " "))
            out[key] = re.sub(r"\s+", " ", text).strip()
    return out


# ============================================================================ the hand
class HandMem:
    """the cards in the wizard's hand and the wizard's pips - see the top. Not thread-safe: NavMem.cards() calls it under
    navmem's lock"""

    def __init__(self, st, log=None):
        self.log = log or (lambda msg: None)
        t0 = time.perf_counter()
        self.st, self.p = st, st.p
        self.build = st.m.build
        img = Image(st)
        P = {nm: class_props(img, nm)[0] for nm in CLASSES}
        missing = [c + "." + k for c, ks in NEED.items() for k in ks if k not in P[c]]
        if missing:
            raise LookupError("reflected properties not found in this build (%s): %s" % (self.build, ", ".join(missing)))
        self.P = P
        self.vt = {nm: set(class_props(img, nm)[2]) for nm in VT_CLASSES}
        none = [nm for nm, v in self.vt.items() if not v]
        if none:
            raise LookupError("reflected classes not found in this build (%s): %s" % (self.build, ", ".join(none)))
        self.etype = read_enum(img, "kInvalidSpellEffect", "m_effectType", "SpellEffect", self.log)
        # (names that don't check out: no reader at all - read as numbers every hit would come out "keep", and still say
        # it was read from the game)
        if not (self.etype.get(0) == "kInvalidSpellEffect" and self.etype.get(1) == "kDamage" and self.etype.get(3) == "kHeal"):
            raise LookupError("the spell effect names couldn't be read in this build (%s)" % self.build)
        self.etarget = read_enum(img, "kInvalidTarget", "m_effectTarget", "SpellEffect", self.log)
        if not (self.etarget.get(0) == "kInvalidTarget" and {"kEnemySingle", "kEnemyTeam", "kSelf"} <= set(self.etarget.values())):
            raise LookupError("the effect target names couldn't be read in this build (%s)" % self.build)
        self.o = {}                  # places found (and checked) this attach
        self.how = {}
        self._cand = {}              # a place found in one window, waiting for a second: key -> {offset: {windows}}
        self._prov = {}              # the place last found for key, not kept yet (used, checked by type, till it's kept)
        self._next_scan = {}
        self.win = {}                # the planning, spell selection and hand windows (checked at every read)
        self.tm = self._template_map(img)
        self.tpl = {}                # template id -> its info (templates don't change while the game runs)
        self.lang = {}               # name table -> {key: text}
        self.school_of_id = dict(SCHOOL_IDS)
        del img                      # (the code copy: only for finding the places above)
        self.attach_s = time.perf_counter() - t0
        self.log("handmem: ready in %.2f s - template map %s, %d effect names, %d target names" % (
            self.attach_s, self.how.get("template_map"), len(self.etype), len(self.etarget)))

    # ------------------------------------------------------------------ small readers
    def u64(self, a):
        b = self.p.try_read(a, 8) if N.ptr_ok(a) else None
        return struct.unpack("<Q", b)[0] if b else 0

    def u32(self, a):
        b = self.p.try_read(a, 4) if N.ptr_ok(a) else None
        return struct.unpack("<I", b)[0] if b else None

    def u8(self, a):
        b = self.p.try_read(a, 1) if N.ptr_ok(a) else None
        return b[0] if b else None

    def tname(self, obj):
        return self.st.tn.of(obj) if N.ptr_ok(obj) else None

    def off(self, cls, prop):
        """a reflected property's offset (None: not in this build)"""
        v = self.P.get(cls, {}).get(prop)
        return v[0] if v else None

    def _due(self, key):
        now = time.monotonic()
        if now < self._next_scan.get(key, 0):
            return False
        self._next_scan[key] = now + RESCAN_EVERY
        return True

    def _confirm(self, key, offset, window):
        """True once two different windows have shown the place offset for key (then it's kept)"""
        seen = self._cand.setdefault(key, {}).setdefault(offset, set())
        seen.add(window)
        if len(seen) >= 2:
            self.o[key] = offset
            self.how[key] = "found by type, confirmed by a second window"
            self._cand.pop(key, None)
            self._prov.pop(key, None)
            self.log("handmem: %s found at +%#x" % (key, offset))
            return True
        return False

    # ------------------------------------------------------------------ the template map
    def _map_ok(self, obj, off):
        head, size = self.u64(obj + off), self.u64(obj + off + 8)
        return (N.ptr_ok(head) and 1000 <= size <= 1000000 and self.u8(head + 0x19) == 1
                and self.u64(self.u64(head + 8) + 8) == head)

    def _template_map(self, img):
        """the head node of the TemplateManager's map (0: not found)"""
        tm = self.u64(self.st.m.base + KNOWN["tm_rva"])
        if N.ptr_ok(tm) and self._map_ok(tm, KNOWN["tm_map"]):
            self.how["template_map"] = "static rva %#x +%#x (known, checked)" % (KNOWN["tm_rva"], KNOWN["tm_map"])
            return self.u64(tm + KNOWN["tm_map"])
        # (another build: a .data static pointing at an object that holds {head (isnil), size} of a big map of templates)
        import numpy as np
        d0, data = img.secs[".data"]
        q = np.frombuffer(data[:len(data) // 8 * 8], dtype=np.uint64)
        for i in np.flatnonzero((q > 0x10000000) & (q < 0x7FF000000000) & ((q & 7) == 0)):
            obj = int(q[i])
            if not self.p.try_read(obj, 0x80):
                continue
            for off in range(8, 0x78, 8):
                if self._map_ok(obj, off):
                    head = self.u64(obj + off)
                    if self._lookup(head, None):
                        self.how["template_map"] = "static rva %#x +%#x (found)" % (d0 + int(i) * 8 - self.st.m.base, off)
                        return head
        self.how["template_map"] = "not found"
        return 0

    def _lookup(self, head, tid):
        """the template for tid in the map at head (tid None: any node's - the map holds templates), else 0"""
        n, k = self.u64(head + 8), 0
        while N.ptr_ok(n) and n != head and k < 64:
            key = self.u32(n + 0x20)
            if key is None:
                return 0
            if tid is None or key == tid:
                t = self.u64(n + 0x28)
                return t if (self.tname(t) or "").endswith("Template") else 0
            n = self.u64(n + (0 if tid < key else 0x10))
            k += 1
        return 0

    def template(self, tid):
        """(the template object for id tid, or 0)"""
        if not tid or not self.tm:
            return 0
        return self._lookup(self.tm, tid)

    # ------------------------------------------------------------------ the name tables
    def lang_text(self, key):
        """'Spells_00005060' -> 'Impair', 'Spells_Ice Trap' -> its text: the table is the part before an underscore (the
        first that names a table in Root.wad), the key the rest; None when not found"""
        if not key or "_" not in key:
            return None
        for i in [m.start() for m in re.finditer("_", key)]:
            table, k = key[:i], key[i + 1:]
            names = self._table(table)
            if names:
                return names.get(k)
        return None

    def _table(self, table):
        if table not in self.lang:
            names = {}
            try:
                import navgeo
                gd, exe = "", self.p.image_path()
                if exe.lower().endswith("\\bin\\" + N.EXE.lower()):
                    gd = exe[: -len("\\bin\\" + N.EXE)]
                root = os.path.join(gd or navgeo.GAME_DIR, "Data", "GameData", "Root.wad")
                rel = "Locale/en-US/%s.lang" % table
                data = navgeo.read_wad_files(root, [rel]).get(rel)
                if data:
                    names = parse_lang(data)
            except Exception as e:  # noqa: BLE001
                self.log("handmem: %s.lang couldn't be read (%r)" % (table, e))
            if len(self.lang) > 40:
                self.lang.clear()
            self.lang[table] = names
        return self.lang[table]

    # ------------------------------------------------------------------ the GUI
    def kids(self, w):
        o = self.off("Window", "m_Children")
        b = self.p.try_read(w + o, 16) if N.ptr_ok(w) else None
        if not b:
            return []
        lo, hi = struct.unpack("<QQ", b)
        if not (N.ptr_ok(lo) and lo <= hi <= lo + 0x8000):
            return []
        raw = self.p.try_read(lo, hi - lo) or b""
        return [v for v in (struct.unpack_from("<Q", raw, i)[0] for i in range(0, len(raw) - 7, 16)) if N.ptr_ok(v)]

    def wname(self, w):
        return self.p.try_string(w + self.off("Window", "m_sName")) if N.ptr_ok(w) else None

    def flags(self, w):
        return self.u32(w + self.off("Window", "m_Flags")) or 0

    def rect(self, w):
        b = self.p.try_read(w + self.off("Window", "m_Window"), 16) if N.ptr_ok(w) else None
        return struct.unpack("<4i", b) if b else None

    def _vt(self, w):
        return self.u64(w)

    def _named(self, obj, off, name):
        v = self.u64(obj + off)
        return v if N.ptr_ok(v) and self.p.try_string(v + WINDOW_NAME) == name else 0

    def root(self):
        """the GUI's root window (the one whose children hold the HUD), or 0"""
        st, hud, gm = self.st, 0, 0
        gmo = self.o.get("gm") or st.o.get("gm")
        cands = ([gmo] if gmo else []) + list(st.o.get("gm_candidates") or [(N.KNOWN["guimgr_rva"], N.KNOWN["gm_hud"])])
        for rva, off in cands:
            gm = self.u64(st.m.base + rva)
            hud = self._named(gm, off, "windowHUD") if N.ptr_ok(gm) else 0
            if hud:
                self.o["gm"] = (rva, off)       # (checked: it holds the window named windowHUD)
                break
        if not hud:
            return 0
        o = self.o.get("root_in_gm")
        for off in ([o] if o is not None else []) + [KNOWN["root_in_gm"]] + list(range(0, 0x600, 8)):
            r = self.u64(gm + off)
            if N.ptr_ok(r) and r != hud and hud in self.kids(r):
                self.o["root_in_gm"] = off       # (checked: its children hold the HUD)
                return r
        return 0

    def _find(self, w, pred, depth):
        p = self._path(w, pred, depth)
        return p[-1] if p else 0

    def _path(self, w, pred, depth):
        """[w, ..., the first window under w (w itself too) that pred takes, depth first within depth levels] - the way
        down to it, for its place in the root (hand_offset); [] none"""
        if pred(w):
            return [w]
        if depth > 0:
            for k in self.kids(w):
                p = self._path(k, pred, depth - 1)
                if p:
                    return [w] + p
        return []

    def windows(self):
        """(planning window, spell selection window, hand window) - kept, and checked by type and name at every read;
        with them the root and the way down from it to the hand (self.win's root, chain: [root, ..., planning window,
        ..., spell selection window, ..., hand] - hand_offset)"""
        pp, ss, hand = self.win.get("pp", 0), self.win.get("ss", 0), self.win.get("hand", 0)
        if (pp and self._vt(pp) in self.vt["CombatPlanningPhaseWindow"] and ss
                and self._vt(ss) in self.vt["SpellSelectionWindow"] and hand and self.wname(hand) == "Hand"):
            return pp, ss, hand
        self.win = {}
        root = self.root()
        if not root:
            return 0, 0, 0
        to_pp = self._path(root, lambda w: self._vt(w) in self.vt["CombatPlanningPhaseWindow"], 4)
        pp = to_pp[-1] if to_pp else 0
        to_ss = self._path(pp, lambda w: self._vt(w) in self.vt["SpellSelectionWindow"], 6) if pp else []
        ss = to_ss[-1] if to_ss else 0
        to_hand = self._path(ss, lambda w: self.wname(w) == "Hand", 2) if ss else []
        hand = to_hand[-1] if to_hand else 0
        if pp and ss and hand:
            self.win = {"pp": pp, "ss": ss, "hand": hand, "root": root, "chain": to_pp + to_ss[1:] + to_hand[1:]}
        return pp, ss, hand

    def hand_offset(self):
        """(dx, dy): where a rect in the Hand window's units (a card's m_Window) starts in the GUI's root - the left / top
        of every window from the root's child down to the hand added (offset_of); None when one can't be read or the
        windows aren't found (windows() first)"""
        chain = self.win.get("chain") or []
        return offset_of([self.rect(w) for w in chain[1:]]) if len(chain) > 1 else None

    def root_size(self):
        """(w, h) of the GUI's root in its own units (the client: 1827 x 1027 at 2560x1440), None not read or not
        plausible (windows() first)"""
        root = self.win.get("root")
        return size_of(self.rect(root)) if root else None

    def _typed_in(self, key, obj, vts, size=0x800):
        """(the pointer in obj of a type in vts, None) at the place kept for key (KNOWN's first); in another build, when
        that fails, the first such pointer in obj (looked for at most every RESCAN_EVERY s) and its place - used, checked
        by type each time, while it isn't kept (a hand read with it still has to match the hand list to count), and
        kept once a second window shows it at the same place (_confirm). (0, None) none"""
        off = self.o.get(key, KNOWN[key])
        v = self.u64(obj + off)
        if v and self._vt(v) in vts:
            return v, None
        if self.build == HAND_BUILD:
            return 0, None
        # (the place found last time, not kept yet: tried first - still checked by type - till it's kept or fails)
        prov = self._prov.get(key)
        if prov is not None:
            v = self.u64(obj + prov)
            if v and self._vt(v) in vts:
                return v, prov
        if not self._due(key + "%x" % obj):
            return 0, None
        raw = self.p.try_read(obj, size) or b""
        for i in range(0, len(raw) - 7, 8):
            v = struct.unpack_from("<Q", raw, i)[0]
            if N.ptr_ok(v) and self._vt(v) in vts:
                self._prov[key] = i
                return v, i
        return 0, None

    def participant(self, ss):
        """(my ClientCombatParticipant: the pointer of that type in the spell selection window (+0x358 now) or 0, the
        place it was found at when it's not kept yet - the one window holding it: kept once its hand list is the cards
        shown, which is the second look)"""
        return self._typed_in("ss_participant", ss, self.vt["ClientCombatParticipant"])

    def card_spell(self, card):
        """the GraphicalSpell a card window shows (+0x450 now), or 0 - a place found in another build kept once a second
        card window shows its spell there too"""
        v, at = self._typed_in("card_spell", card, self.vt["GraphicalSpell"])
        if at is not None:
            self._confirm("card_spell", at, card)
        return v

    # ------------------------------------------------------------------ containers
    def vec(self, a, limit=64):
        """the objects of a std::vector<SharedPointer<T>> at a (begin, end: 16-byte elements)"""
        b = self.p.try_read(a, 16) if N.ptr_ok(a) else None
        if not b:
            return []
        x, y = struct.unpack("<QQ", b)
        if N.ptr_ok(x) and x <= y <= x + 16 * limit:
            raw = self.p.try_read(x, y - x) or b""
            return [struct.unpack_from("<Q", raw, i)[0] for i in range(0, len(raw) - 7, 16)]
        return []

    def lst(self, a, limit=64):
        """(the objects of a std::list<SharedPointer<T>> at a - head node, size; node +0 next, +0x10 the object - and
        the size it says), or (None, None) when it doesn't read as one"""
        b = self.p.try_read(a, 16) if N.ptr_ok(a) else None
        if not b:
            return None, None
        head, size = struct.unpack("<QQ", b)
        if not N.ptr_ok(head) or size > limit:
            return None, None
        out, n = [], self.u64(head)
        while N.ptr_ok(n) and n != head:
            if len(out) > size:
                return None, size
            out.append(self.u64(n + 0x10))
            n = self.u64(n)
        return (out, size) if n == head else (None, size)

    def seq(self, a, limit=64):
        """a reflected container of SharedPointers at a: a vector, else a list"""
        v = self.vec(a, limit)
        if v:
            return v
        items, _ = self.lst(a, limit)
        return items or []

    # ------------------------------------------------------------------ templates and their effects
    def effects(self, tpl, limit=1000):
        """[{class, type, param, rounds, per_round, school, target, depth}] of a template's m_effects, depth first (a
        container's - random, variable, list, conditional - own effects follow it one deeper). The whole tree: 24 cut a
        tier-B ramp's main damage off (the largest seen live: 424 effects, 15 ms, kept per template); still at limit:
        tpl_info marks it effects_cut and kind_of guesses nothing"""
        SE = self.P["SpellEffect"]
        o = {k: v[0] for k, v in SE.items()}
        out = []

        def one(e, depth):
            if len(out) >= limit or not N.ptr_ok(e):
                return
            tn = self.tname(e) or ""
            raw = self.p.try_read(e, max(o.values()) + 8)
            if not raw or "Effect" not in tn:
                return
            g = lambda k: struct.unpack_from("<i", raw, o[k])[0] if k in o else None   # noqa: E731
            et, tg = g("m_effectType"), g("m_effectTarget")
            out.append({"class": tn, "type": self.etype.get(et, et), "param": g("m_effectParam"),
                        "rounds": g("m_numRounds"), "per_round": g("m_paramPerRound"),
                        "school": self.p.try_string(e + o["m_sDamageType"]) if "m_sDamageType" in o else None,
                        "target": self.etarget.get(tg, tg), "depth": depth})
            if depth >= 3:
                return
            kp = self.P.get(tn) or {}
            if not any(k in kp for k in ("m_effectList", "m_elements", "m_effectLists")) and tn in INHERIT:
                kp = self.P.get(INHERIT[tn]) or {}         # (its list is the base class's, registered there)
            if "m_effectList" in kp:
                kids = self.seq(e + kp["m_effectList"][0])
            elif "m_elements" in kp:                       # (conditional: [requirements, effect] elements)
                pe = self.off("ConditionalSpellElement", "m_pEffect")
                kids = [self.u64(k + pe) for k in self.seq(e + kp["m_elements"][0])] if pe is not None else []
            elif "m_effectLists" in kp:                    # (by the count of targets: a list of effect lists)
                kids = self.seq(e + kp["m_effectLists"][0])
            else:
                kids = []
            for k in kids:
                one(k, depth + 1)
        for e in self.seq(tpl + self.off("SpellTemplate", "m_effects")):
            one(e, 0)
        return out

    def tpl_info(self, tid):
        """{name, display_key, display, school, type, template_class, no_discard, effects} of template tid (kept: the
        templates don't change while the game runs), or None"""
        t = self.template(tid)
        if not t:
            return None
        hit = self.tpl.get(tid)
        if hit and hit[0] == t:
            return hit[1]
        T = self.P["SpellTemplate"]
        key = self.p.try_string(t + T["m_displayName"][0])
        info = {"name": self.p.try_string(t + T["m_name"][0]), "display_key": key, "display": self.lang_text(key),
                "school": self.p.try_string(t + T["m_sMagicSchoolName"][0]),
                "type": self.p.try_string(t + T["m_sTypeName"][0]), "template_class": self.tname(t),
                "no_discard": self.u8(t + T["m_noDiscard"][0]) if "m_noDiscard" in T else None,
                "effects": self.effects(t)}
        info["effects_cut"] = len(info["effects"]) >= 1000
        if len(self.tpl) > 4000:
            self.tpl.clear()
        self.tpl[tid] = (t, info)
        return info

    # ------------------------------------------------------------------ a card
    def spell(self, g):
        """the card's spell g: its template's info, its own pips, flags, enchantment, numbers changed for it"""
        S, R = self.P["Spell"], self.P["SpellRank"]
        span = max(v[0] for v in S.values()) + 16
        raw = self.p.read(g, span)
        # (the hand changes under the reader - a discarded card's spell freed and its memory reused: the bytes count
        # only while they still start with a GraphicalSpell / Spell vtable)
        if struct.unpack_from("<Q", raw)[0] not in self.vt["GraphicalSpell"] | self.vt["Spell"]:
            raise N.ReadError("the card's spell changed while it was read")
        f = lambda k, fmt="<I": struct.unpack_from(fmt, raw, S[k][0])[0] if k in S else None   # noqa: E731
        b = lambda k: raw[S[k][0]] if k in S else None                                       # noqa: E731
        tid = f("m_templateID")
        r = {"template_id": tid, "spell_class": self.tname(g)}
        info = self.tpl_info(tid)
        if info:
            r.update(info)
        rank = f("m_pipCost", "<Q")
        rr = self.p.try_read(rank, R["m_xPipSpell"][0] + 1) if N.ptr_ok(rank) else None
        if rr:
            r.update(pips=rr[R["m_spellRank"][0]], x_pips=bool(rr[R["m_xPipSpell"][0]]),
                     shadow_pips=rr[R["m_shadowPips"][0]],
                     school_pips={s: rr[R["m_%sPips" % s][0]] for s in SCHOOL_PIPS if rr[R["m_%sPips" % s][0]]})
        r.update(accuracy=b("m_accuracy"), treasure=bool(b("m_treasureCard")), item_card=bool(b("m_itemCard")),
                 school_id=f("m_magicSchoolID"))
        # (a number of the template's changed for this card: [(index of the effect, its number)])
        po = self.off("Spell", "m_paramOverrides")
        ei, pv = self.off("SpellEffectParamOverride", "m_effectIndex"), self.off("SpellEffectParamOverride", "m_paramValue")
        if po is not None and ei is not None and pv is not None:
            ovr = []
            for obj in self.seq(g + po, 16):
                a, v = self.u32(obj + ei), self.u32(obj + pv)
                if a is not None and v is not None:
                    ovr.append((struct.unpack("<i", struct.pack("<I", a))[0], struct.unpack("<i", struct.pack("<I", v))[0]))
            if ovr:
                r["overrides"] = ovr
        ench = f("m_enchantment") or 0
        r["enchantment_id"] = ench
        if ench:
            ei_ = self.tpl_info(ench)
            if ei_:
                r["enchantment"] = ei_.get("display") or ei_.get("name")
                r["ench_effects"] = ei_.get("effects") or []
        return r

    # ------------------------------------------------------------------ me
    def me(self, c):
        """{owner, school_id, school, health, max_health, pips {generic, power, <school>..., shadow}} of a participant,
        and its hand list ([spells], the size the list says)"""
        CP = {k: v[0] for k, v in self.P["CombatParticipant"].items()}
        r = {"owner": self.u64(c + CP["m_ownerID.m_full"]), "school_id": self.u32(c + CP["m_primaryMagicSchoolID"])}
        hp, top = self.u32(c + CP["m_playerHealth"]), self.u32(c + CP["m_maxPlayerHealth"])
        r["health"] = None if hp is None else struct.unpack("<i", struct.pack("<I", hp))[0]
        r["max_health"] = None if top is None else struct.unpack("<i", struct.pack("<I", top))[0]
        r["school"] = self.school_of_id.get(r["school_id"], "")
        pc = self.u64(c + CP["m_pipCount"])
        if N.ptr_ok(pc) and self.tname(pc) == "PipCount":
            PC = {k: v[0] for k, v in self.P["PipCount"].items() if k.endswith("Pips")}
            lo, hi = min(PC.values()), max(PC.values()) + 1
            try:
                # (read until two reads agree: the game adds pips at the round's start)
                raw = self.p.stable(pc + lo, hi - lo)
                r["pips"] = {k[2:-4].lower(): raw[o - lo] for k, o in PC.items()}
            except N.ReadError:
                pass
        items, size = self.hand_list(c)
        return r, items, size

    def hand_list(self, c):
        """(my hand list's spells - participant c's m_pHand -> Hand.m_spellList - and the size the list says), (None,
        None) / (None, size) when it doesn't read as one"""
        hand = self.u64(c + self.off("CombatParticipant", "m_pHand"))
        if N.ptr_ok(hand) and self.tname(hand) == "Hand":
            return self.lst(hand + self.off("Hand", "m_spellList"), 20)
        return None, None

    # ------------------------------------------------------------------ the read
    def read(self, want_effects=True):
        """{in_battle, planning, settled, state, why, ms, me, cards: [...]} - never raises.
          in_battle  my participant is alive (out of a battle nothing else is read: the card windows keep old spells)
          planning   the planning phase (the planning window shows)
          settled    the cards are the hand to play: the shown cards' spells (the pet's card left out) are exactly my
                     hand list's - as many as its size says - and every card has a name. Else why = 'hand changing'
          state      'none' (not in a battle / no planning window), 'waiting' (planning, no card shown but the hand list
                     isn't empty: a card's been chosen, the others are waited for), 'changing', 'hand' (settled)
          me         {owner, school_id, school, health, max_health, pips {generic, power, balance... storm, shadow}}
          cards      left to right: {slot, x, box, shown, name, display, school, type, pips, x_pips, shadow_pips,
                     school_pips, accuracy, treasure, item_card, enchantment, effects, kind, value, ..., castable
                     (a normal-mode estimate - see castable), why (a card that couldn't be read)} - box: its place in the
                     root, (l, t, r, b) in GUI units (box_in_root - None not read; not checked against the screen yet)
          root       (w, h) the GUI root's size in the same units (root_size - None not read)"""
        t0 = time.perf_counter()
        out = {"in_battle": False, "planning": False, "settled": False, "state": "none", "why": "", "ms": 0.0,
               "me": None, "cards": [], "root": None}
        try:
            self._read(out, want_effects)
        except Exception as e:  # noqa: BLE001 - never into the caller
            out["settled"], out["cards"] = False, []
            out["why"] = "the hand couldn't be read (%r)" % (e,)
        out["ms"] = round((time.perf_counter() - t0) * 1000, 1)
        return out

    def _read(self, out, want_effects):
        pp, ss, hand = self.windows()
        if not pp:
            out["why"] = "no planning window (not in the game world)"
            return
        out["planning"] = bool(self.flags(pp) & 1)
        if not ss or not hand:
            out["why"] = "no hand window"
            return
        c, c_at = self.participant(ss)
        out["in_battle"] = bool(c)
        if not c:
            out["why"] = "not in a battle"
            return
        me, items, size = self.me(c)
        out["me"] = me
        if not out["planning"]:
            out["why"] = "in a battle, not in the planning phase"
            return
        # (where the hand's cards are in the root, and the root's size - each read once a read: a card's box is its
        # m_Window moved by the hand's offset, box_in_root)
        off, out["root"] = self.hand_offset(), self.root_size()
        cards = []
        for w in self.kids(hand):
            if self._vt(w) not in self.vt["SpellCheckBox"]:
                continue
            fl, rc = self.flags(w), self.rect(w)
            card = {"slot": self.wname(w) or "", "x": rc[0] if rc else None, "box": box_in_root(rc, off),
                    "shown": bool(fl & 1), "flags": fl}
            if card["shown"]:
                try:
                    g = self.card_spell(w)
                    card["_g"] = g
                    if g:
                        card.update(self.spell(g))
                        finish(card, want_effects)
                    else:
                        card["why"] = "no spell"
                except Exception as e:  # noqa: BLE001 - this card only
                    card["why"] = "not read (%r)" % (e,)
            cards.append(card)
        shown = sorted((cd for cd in cards if cd["shown"]), key=lambda cd: cd["x"] if cd["x"] is not None else 1 << 30)
        # (a card's school id named by its template: the participant's school read the same way)
        for cd in shown:
            if cd.get("school_id") and cd.get("school"):
                self.school_of_id[cd["school_id"]] = cd["school"].lower()
        me["school"] = self.school_of_id.get(me.get("school_id"), me.get("school") or "")
        own = [cd for cd in shown if cd["slot"] != "PetCard"]
        if not shown:
            if items is None:
                out.update(state="changing", why="hand changing")
            elif items:
                out.update(state="waiting", why="planning, no card shown - a card's chosen, waiting for the round")
            else:
                out.update(state="hand", settled=True, why="")          # (an empty hand: the deck used up)
            return
        gs = [cd.get("_g") for cd in own]
        if (items is None or size is None or len(own) != len(items) or len(items) != size or 0 in gs or None in gs
                or set(gs) != set(items) or not all(cd.get("name") for cd in shown)):
            out.update(state="changing", why="hand changing")
            out["cards"] = shown
            return
        for cd in shown:
            cd["castable"] = castable(cd, me)
            cd.pop("_g", None)
        # (a participant found by looking - another build: its hand list is the cards shown, the second look - kept)
        if c_at is not None:
            self._confirm("ss_participant", c_at, "its hand list is the cards shown")
            self._confirm("ss_participant", c_at, ss)
        out.update(state="hand", settled=True, why="", cards=shown)

    # ------------------------------------------------------------------ the round's phase alone (cheap)
    def phase(self):
        """{in_battle, planning, state, shown, own, size, why, ms} - the round's phase without reading a spell (the
        windows, the planning flag, my participant, the card windows' shown flags and my hand list's length: about a
        millisecond, read() is 5-50) - for a check after a click (did the card go out?) and the round's start. Never
        raises. state (phase_state): 'none' not in a battle / no planning window, 'round' in a battle out of the
        planning phase (the round being played out), 'waiting' planning, no card shown but cards in my hand list (a
        card's been chosen, the others are waited for), 'changing' planning, the cards shown not as many as the list
        says (dealing, discarding, laying out - or a target being picked? NOT SEEN yet), 'hand' as many shown as the list
        says (the hand to play: not checked card by card as read() does). shown: card windows shown (the pet's too), own:
        those without the pet's card, size: the list's own size (None: not read)"""
        t0 = time.perf_counter()
        out = {"in_battle": False, "planning": False, "state": "none", "shown": None, "own": None, "size": None,
               "why": "", "ms": 0.0}
        try:
            pp, ss, hand = self.windows()
            items = None
            if pp:
                out["planning"] = bool(self.flags(pp) & 1)
                c = self.participant(ss)[0] if ss else 0
                out["in_battle"] = bool(c)
                if c and out["planning"] and hand:
                    items, out["size"] = self.hand_list(c)
                    cards = [w for w in self.kids(hand) if self._vt(w) in self.vt["SpellCheckBox"] and self.flags(w) & 1]
                    out["shown"] = len(cards)
                    out["own"] = sum(1 for w in cards if self.wname(w) != "PetCard")
            out["state"], out["why"] = phase_state(bool(pp), out["in_battle"], out["planning"], out["shown"], out["own"],
                                                   None if items is None else len(items), out["size"])
        except Exception as e:  # noqa: BLE001 - never into the caller
            out.update(state="none", why="the phase couldn't be read (%r)" % (e,))
        out["ms"] = round((time.perf_counter() - t0) * 1000, 1)
        return out


# ============================================================================ boxes and the phase (pure: tested offline)
def offset_of(rects):
    """(dx, dy): the rects' left / top added - a window's m_Window is in its parent's units, so a rect in a window's
    units starts in the root at every window's left / top from the root's child down to that window (pure); None when
    there's none or one isn't read"""
    if not rects or any(r is None or len(r) < 2 for r in rects):
        return None
    return sum(r[0] for r in rects), sum(r[1] for r in rects)


def box_in_root(rect, off):
    """a card window's rect (l, t, r, b - in its parent's units) moved by off (offset_of) - its place in the root in GUI
    units (pure); None when either isn't read or the rect is empty or inside out"""
    if rect is None or off is None or len(rect) < 4:
        return None
    l, t, r, b = rect[:4]
    if r <= l or b <= t:
        return None
    return l + off[0], t + off[1], r + off[0], b + off[1]


def size_of(rect):
    """(w, h) of a root rect, None when it isn't read or isn't plausible (as navmem.ui_root: 1..20000 each way)"""
    if rect is None or len(rect) < 4:
        return None
    w, h = rect[2] - rect[0], rect[3] - rect[1]
    return (w, h) if 0 < w <= 20000 and 0 < h <= 20000 else None


def phase_state(found, in_battle, planning, shown, own, n_items, size):
    """(state, why) of HandMem.phase from what it read (pure) - the same rule as read()'s state, without the spells:
    found the planning window, n_items my hand list's length (None: it didn't read as a list), size the length it says"""
    if not found:
        return "none", "no planning window (not in the game world)"
    if not in_battle:
        return "none", "not in a battle"
    if not planning:
        return "round", "in a battle, not in the planning phase"
    if not shown:
        if n_items is None:
            return "changing", "hand changing"
        if n_items:
            return "waiting", "planning, no card shown - a card's chosen, waiting for the round"
        return "hand", ""                       # (an empty hand: the deck used up)
    if n_items is None or size is None or own != n_items or n_items != size:
        return "changing", "hand changing"
    return "hand", ""


# ============================================================================ what a card does (pure: tested offline)
DAMAGE = {"kDamage", "kDamageNoCrit", "kStealHealth", "kMaxHealthDamage", "kDamagePerTotalPipPower", "kDivideDamage"}
DOT = {"kDamageOverTime", "kDeferredDamage"}
HEAL = {"kHeal", "kHealPercent", "kHealByWard"}
HOT = {"kHealOverTime"}
CLEAR = {"kRemoveCharm", "kRemoveWard", "kRemoveOverTime", "kRemoveCombatTriggerList"}
PRISM = {"kModifyIncomingDamageType", "kModifyOutgoingDamageType"}
ENEMY_ALL = {"kEnemyTeam", "kEnemyTeamAllAtOnce"}
FRIEND_ALL = {"kFriendlyTeam", "kFriendlyTeamAllAtOnce"}
ENEMY = ENEMY_ALL | {"kEnemySingle", "kAtLeastOneEnemy", "kPreselectedEnemySingle", "kMultiTargetEnemy", "kEnemyMinion"}
MINION = {"kMinion", "kFriendlyMinion", "kCasterMinion", "kTargetMinion"}
# (2026-10-26: every battle spell type of the game's own list - m_sTypeName, read off its files - has a kind; those the
# bot doesn't play are named all the same, for the Spells tab. Absorbs soak N damage; a summon (or one that works on your
# minion); a spell that gives pips; the game's three shadow types)
ABSORB = {"kAbsorbDamage"}
SUMMON = {"kSummonCreature", "kSpawnCreature"}
PIPS = {"kModifyPips", "kModifyPowerPips", "kModifySchoolPips", "kModifyShadowPips"}
SHADOW_TYPES = {"shadow", "shadow_self", "shadow_creature"}
KINDS = ("damage", "aoe", "heal", "ward", "absorb", "blade", "trap", "aura", "negaura", "bubble", "weakness", "curse",
         "charm", "enchant", "sharpen", "potent", "enchantother", "mutate", "dot", "stun", "dispel", "prism", "clear",
         "polymorph", "shadow", "minion", "pips", "manipulation", "keep")
# (what a global - a bubble - changes, for its text: the effect's type -> the words)
GLOBAL_WORDS = {"kModifyOutgoingDamage": "damage", "kModifyIncomingDamage": "damage taken", "kModifyOutgoingHeal": "healing",
                "kModifyIncomingHeal": "healing received", "kModifyOutgoingArmorPiercing": "pierce",
                "kModifyAccuracy": "accuracy", "kModifyPowerPipChance": "power pip chance"}


def global_heads(hs, tt=""):
    """a global's heads (a bubble - all of the battle, everyone's spells): those aimed at kGlobal, every head when the card's
    type is Global and none says so"""
    g = [h for h in hs if h["target"] == "kGlobal"]
    return g if g else (list(hs) if (tt or "").lower() == "global" else [])


def _tree(effects):
    """the flat effects (depth first, 'depth') as [(effect, [children])]"""
    def node(i, depth):
        e, kids, j = effects[i], [], i + 1
        while j < len(effects) and effects[j].get("depth", 0) > depth:
            kid, j = node(j, depth + 1)
            kids.append(kid)
        return (e, kids), j
    out, i = [], 0
    while i < len(effects):
        n, i = node(i, effects[i].get("depth", 0))
        out.append(n)
    return out


def heads(effects, overrides=None):
    """what the spell does: [{type, lo, hi, per_pip, rounds, school, target, cond}] - a random effect's choices as one
    head lo-hi, a variable (X pips) one's as per pip (its first choice: one pip), a list's effects each; conditional
    effects - one's elements, and conditionals one after another (a gambit: 710 damage, or with a jinx on the target
    1490) - are alternatives, of which the one doing the least damage now counts (the first of those: a ramp's), its
    heads marked cond. A leaf with no effect type (kInvalidSpellEffect: a gambit's placeholders) is no head.
    overrides [(index, number)]: the card's own numbers for top-level effects"""
    ov = dict(overrides or [])

    def tgt(e, parent):
        t = e.get("target")
        return parent if (t in (None, 0, "kInvalidTarget") and parent) else t

    def damage(hs):
        return sum(h["lo"] for h in hits(hs))

    def walk(nodes, parent_target, top, out):
        i = 0
        while i < len(nodes):
            e, kids = nodes[i]
            cls, t = e.get("class") or "SpellEffect", tgt(e, parent_target)
            if cls == "ConditionalSpellEffect":
                alts, j = [], i
                while j < len(nodes) and (nodes[j][0].get("class") or "") == "ConditionalSpellEffect":
                    tj = tgt(nodes[j][0], parent_target)
                    for k in nodes[j][1]:
                        hs = []
                        walk([k], tj, False, hs)
                        alts.append(hs)
                    j += 1
                if alts:
                    for h in min(alts, key=damage):        # (min keeps the first of equals)
                        out.append(dict(h, cond=True))
                i = j
                continue
            # (one effect list per number of targets chosen - 1, 2, 3, 4: alternatives, not heads; the first is one
            # target's, as the bot casts it - added up they came out 2.5-3x too high)
            if cls == "TargetCountSpellEffect" and kids:
                walk(kids[:1], t, False, out)
                i += 1
                continue
            if kids and cls in ("RandomSpellEffect", "RandomPerTargetSpellEffect", "VariableSpellEffect") and all(not k[1] for k in kids):
                vals = [k[0].get("param") or 0 for k in kids]
                k0 = kids[0][0]
                out.append({"type": k0.get("type"), "lo": vals[0] if cls == "VariableSpellEffect" else min(vals),
                            "hi": vals[0] if cls == "VariableSpellEffect" else max(vals), "per_pip": cls == "VariableSpellEffect",
                            "rounds": k0.get("rounds") or 0, "school": k0.get("school") or "", "target": tgt(k0, t), "cond": False})
            elif kids:
                walk(kids, t, False, out)
            elif e.get("type") in ("kInvalidSpellEffect", 0):
                pass                                       # (a container whose own effects weren't read, a placeholder)
            else:
                v = e.get("param") or 0
                if top and i in ov:
                    v = ov[i]
                out.append({"type": e.get("type"), "lo": v, "hi": v, "per_pip": False, "rounds": e.get("rounds") or 0,
                            "school": e.get("school") or "", "target": t, "cond": False})
            i += 1
    res = []
    walk(_tree(effects or []), None, True, res)
    return res


def hits(hs, types=DAMAGE):
    """the heads that hurt an enemy (types: DAMAGE, or DOT for over time) - aimed at one, or at no one said (the older
    reads had no targets): not a minion of your own sacrificed (Draw Power's and Siphon Health's instant kill)"""
    return [h for h in hs if h["type"] in types and (h["target"] in ENEMY or h["target"] in (None, 0, "kInvalidTarget", "kSpell"))]


def kind_of(card):
    """(kind, value, dot): what the bot calls the card - KINDS - from its template's type (m_sTypeName) and what its
    effects do; value: a hit's least damage, every head of it (its damage per pip for an X-pip hit), a heal's amount,
    the % of a shield, blade, trap, aura or weakness, an enchant's damage, a bubble's (a global's) damage % (else its
    biggest number), the damage an absorb soaks (a pip's for an X-pip one), a negative aura's % (the damage taken it adds,
    else its biggest), a Sharpened Blade's / Potent Trap's +%, a curse's / charm's biggest number, the pips a pips spell
    gives - None none; dot: damage (or healing) over time besides, None none"""
    # (its effects cut short: what it does isn't known for sure - no kind, rather than a wrong one from the part read)
    if card.get("effects_cut"):
        return None, None, None
    tt = (card.get("type") or "").lower()
    hs = heads(card.get("effects"), card.get("overrides"))
    types = {h["type"] for h in hs}
    # (a shadow form - Shadow Shrike, Seraph, Sentinel...: the game's type Polymorph paid with a shadow pip - and the game's
    # own shadow types, never in a wizard's hand: not played - backlash)
    if tt in SHADOW_TYPES or (tt == "polymorph" and (card.get("shadow_pips") or 0) > 0):
        return "shadow", None, None
    # (one that needs a minion of your own - Siphon Health heals by sacrificing it, Draw Power takes pips from it: cast
    # with none it's no heal; not a learned card's job - a minion spell, like the summons below)
    if any(h["target"] in MINION for h in hs):
        return "minion", None, None
    dmg, dot = hits(hs), hits(hs, DOT)
    # (a pip-power head whose number isn't damage - Mana Burn's and Steal Pips' -1: the enemy's pips decide it - is no
    # hit; an X-pip card's is its damage a pip)
    if not card.get("x_pips"):
        dmg = [h for h in dmg if not (h["type"] == "kDamagePerTotalPipPower" and (h["lo"] or 0) < 0)]
    heal = [h for h in hs if h["type"] in HEAL]
    hot = [h for h in hs if h["type"] in HOT]
    dotv = sum(h["lo"] for h in dot) or None
    if dmg:
        aoe = tt == "aoe" or any(h["target"] in ENEMY_ALL for h in dmg)
        per_pip = card.get("x_pips") or any(h["per_pip"] for h in dmg)
        return ("aoe" if aoe else "damage"), (dmg[0]["lo"] if per_pip else sum(h["lo"] for h in dmg)), dotv
    if dot and not heal and not hot:
        return "dot", None, dotv
    if heal or (hot and (tt == "heal" or types <= HOT | CLEAR)):
        return "heal", (sum(h["lo"] for h in heal) if heal else sum(h["lo"] for h in hot)), (sum(h["lo"] for h in hot) if heal and hot else None)
    # (a summon - Animate, a pet's minion, Spectral Minion: after the hits and heals, which may summon besides - Colossus)
    if types & SUMMON:
        return "minion", None, None
    if "kStun" in types:
        return "stun", None, None
    if "kDispel" in types:
        return "dispel", None, None
    # (an absorb - soaks N damage: Spirit Armor, Ice Armor (X pips: N a pip), Legion Absorb - on you or your team)
    ab = [h for h in hs if h["type"] in ABSORB and h["target"] not in ENEMY]
    if ab:
        return "absorb", (ab[0]["lo"] if (card.get("x_pips") or any(h["per_pip"] for h in ab)) else sum(h["lo"] or 0 for h in ab)), None
    # (a negative aura - the game's type AuraNegative: on one enemy for 4 rounds, not used up by a hit - Attenuate's +N%
    # damage taken (a school's, a Weaving one's that converts besides), Starfall's -N% damage, Pathogen's healing down)
    if tt == "auranegative":
        up = [h["lo"] for h in hs if h["type"] == "kModifyIncomingDamage" and (h["lo"] or 0) > 0]
        big = [abs(h["lo"]) for h in hs if h["type"] not in PRISM and isinstance(h["lo"], (int, float)) and h["lo"]]
        return "negaura", (max(up) if up else (max(big) if big else None)), None
    # (a prism - converts the school; not a trap, blade or aura that converts besides - the Weaving ones: Heat Trap's +40%
    # twice and a conversion, Drought Blade's +35% twice, Dust Amplify's +30%: a trap, blade or aura, below)
    if types & PRISM and not any((h["lo"] or 0) > 0 and ((h["type"] == "kModifyIncomingDamage" and h["target"] not in FRIEND_ALL
                                                           and h["target"] not in ("kSelf", "kFriendlySingle"))
                                                          or (h["type"] == "kModifyOutgoingDamage" and h["target"] not in ENEMY)) for h in hs):
        return "prism", None, None
    if "kPolymorph" in types or tt == "polymorph":
        return "polymorph", None, None
    # (a mutation - turns one spell in hand into its mutated version: Mutate Kraken; an enchantment - played onto a card in
    # hand: +N damage (enchant), Sharpened Blade's +N% on a blade (sharpen), Potent Trap's on a trap (potent), the others -
    # accuracy, protect, cloak, rank, healing - enchantother)
    if tt == "mutate" or "kModifyCardMutation" in types:
        return "mutate", None, None
    if tt == "enchantment" or any(str(t).startswith("kModifyCard") for t in types):
        cd = [h for h in hs if h["type"] == "kModifyCardDamage" and h["lo"] > 0]
        if cd:
            return "enchant", cd[0]["lo"], None
        sh = [h["lo"] for h in hs if h["type"] == "kModifyCardOutgoingDamage" and (h["lo"] or 0) > 0]
        if sh:
            return "sharpen", max(sh), None
        po = [h["lo"] for h in hs if h["type"] == "kModifyCardIncomingDamage" and (h["lo"] or 0) > 0]
        if po:
            return "potent", max(po), None
        # (a card of another type that changes a card - Shroud, a Global that cloaks: kept, as before)
        return ("enchantother" if tt == "enchantment" else "keep"), None, None
    # (a global - a bubble: all of the battle, everyone's spells - its number the damage it adds, else its biggest; the
    # bot casts your school's before a hit: CardLearn.ahk <school>\bubble, KillCalc.ahk BubbleMatches)
    gl = global_heads(hs, tt)
    if gl:
        up = [h["lo"] for h in gl if h["type"] == "kModifyOutgoingDamage" and (h["lo"] or 0) > 0]
        big = [abs(h["lo"]) for h in gl if isinstance(h["lo"], (int, float)) and h["lo"]]
        return "bubble", (max(up) if up else (max(big) if big else None)), None
    out_d = [h for h in hs if h["type"] == "kModifyOutgoingDamage"]
    in_d = [h for h in hs if h["type"] == "kModifyIncomingDamage"]
    up = [h for h in out_d if h["lo"] > 0 and h["target"] not in ENEMY]
    if tt == "aura" and up:                                # (a Star aura: +N% for some rounds, whatever else it does)
        return "aura", max(h["lo"] for h in up), None
    if out_d and not in_d:
        h = max(out_d, key=lambda q: abs(q["lo"]))
        if h["lo"] < 0 or h["target"] in ENEMY:
            return "weakness", abs(h["lo"]), None
        return ("aura" if (h["rounds"] > 0 or tt == "aura") else "blade"), h["lo"], None
    if in_d:
        neg = [h for h in in_d if h["lo"] < 0 and h["target"] not in ENEMY]
        pos = [h for h in in_d if h["lo"] > 0 and (h["target"] in ENEMY or h["target"] in (None, 0, "kInvalidTarget") or tt == "jinx")]
        if pos and (tt == "jinx" or not neg):
            return "trap", max(h["lo"] for h in pos), None
        if neg and not any(h["rounds"] for h in neg):
            return "ward", max(-h["lo"] for h in neg), None
        return other_kind(tt, hs)
    if types & CLEAR:
        return "clear", None, None
    if hot:
        return "heal", sum(h["lo"] for h in hot), None
    return other_kind(tt, hs)


def other_kind(tt, hs):
    """(kind, value, None) of a card kind_of found nothing else for, by the game's type: a curse (an enemy's accuracy or
    healing down - Black Mantle, Infection, Smoke Screen; the game's Curse), a charm (spears, accuracy, a healing boost -
    Firespear, Guidance, Guiding Light; the game's Charm) - their biggest number -, a pips spell (gives pips to you or an
    ally, nothing on an enemy: Donate Power, Bestow, Empower - the pips given), any other Manipulation (steal a charm or
    ward, aggro, push, Reshuffle, Mana Burn...: manipulation); else keep (a ward that isn't a shield - Stun Block -, an aura
    that adds no damage, a jinx that adds a card...)"""
    big = [abs(h["lo"]) for h in hs if h["type"] not in PRISM and isinstance(h["lo"], (int, float)) and h["lo"]]
    if tt == "curse":
        return "curse", (max(big) if big else None), None
    if tt == "charm":
        # (a Charm that lowers - its numbers aimed at an enemy all below 0, or every number below 0: Black Mantle, Smoke
        # Screen, Tardiness, Mass Infection as the game types some of their copies, an "Unhelpful" one put on your team -
        # is a curse; the review, 2026-10-26)
        num = [h for h in hs if h["type"] not in PRISM and isinstance(h["lo"], (int, float)) and h["lo"]]
        at_foe = [h for h in num if h["target"] in ENEMY]
        if num and (all(h["lo"] < 0 for h in at_foe) if at_foe else all(h["lo"] < 0 for h in num)):
            return "curse", max(big), None
        return "charm", (max(big) if big else None), None
    pp = [h for h in hs if h["type"] in PIPS and (h["lo"] or 0) > 0 and h["target"] not in ENEMY]
    if pp and not any(h["target"] in ENEMY for h in hs):
        return "pips", sum(h["lo"] for h in pp), None
    if tt == "manipulation":
        return "manipulation", None, None
    return "keep", None, None


def value_text(card, kind, value):
    """the number as /cards writes it: a hit 'lo-hi' (every head added; lo alone when they're the same), 'N/pip' for an
    X-pip hit or absorb, a heal or absorb 'N', a % 'N%', an enchant '+N', a Sharpened Blade / Potent Trap '+N%'; '' none"""
    if value is None:
        return ""
    if kind in ("damage", "aoe"):
        hs = hits(heads(card.get("effects"), card.get("overrides")))
        if card.get("x_pips") or any(h["per_pip"] for h in hs):
            return "%d/pip" % value
        hi = sum(h["hi"] for h in hs)
        return "%d-%d" % (value, hi) if hi > value else "%d" % value
    if kind in ("ward", "blade", "trap", "aura", "weakness", "bubble", "negaura", "curse", "charm"):
        return "%d%%" % value
    if kind == "enchant":
        return "+%d" % value
    if kind in ("sharpen", "potent"):
        return "+%d%%" % value
    if kind == "absorb" and (card.get("x_pips") or any(h["per_pip"] for h in heads(card.get("effects"), card.get("overrides"))
                                                        if h["type"] in ABSORB)):
        return "%d/pip" % value
    return "%d" % value


def ench_bonus(card):
    """(the enchantment's effect in words - 'kModifyCardDamage +175' -, the card's number with it) - an enchanted
    card's template still holds its own numbers: the enchantment's are added here (+N damage, +N% on a blade, +N
    healing, +N% accuracy; others named only); ('', '') when it has none"""
    if not card.get("enchantment_id"):
        return "", ""
    eh = heads(card.get("ench_effects") or [])
    words = "; ".join("%s %+d" % (h["type"], h["lo"]) for h in eh) or (card.get("enchantment") or "")
    kind, value = card.get("kind"), card.get("value")
    if value is None:
        return words, ""
    add = {h["type"]: h["lo"] for h in eh}
    v = value
    if kind in ("damage", "aoe") and "kModifyCardDamage" in add:
        v = value + add["kModifyCardDamage"]
    elif kind in ("blade", "trap") and "kModifyCardOutgoingDamage" in add:
        v = value + add["kModifyCardOutgoingDamage"]
    elif kind == "heal" and ("kModifyCardHeal" in add or "kModifyCardOutgoingHeal" in add):
        v = value + add.get("kModifyCardHeal", add.get("kModifyCardOutgoingHeal", 0))
    else:
        return words, ""
    return words, value_text(card, kind, v)


def _schools(hs):
    s = []
    for h in hs:
        n = (h.get("school") or "").strip()
        if n and n.lower() != "all" and n not in s:
            s.append(n)
    return s


def describe(card):
    """the card's text, about as the game writes it ("255-285 Life damage", "+35% to next Ice, Storm, Fire spell",
    "Heal 400 to all") - what the bot keeps as the text read off it"""
    kind, value = card.get("kind"), card.get("value")
    hs = heads(card.get("effects"), card.get("overrides"))
    words = []
    if kind in ("damage", "aoe"):
        d = hits(hs)
        per = card.get("x_pips") or any(h["per_pip"] for h in d)
        parts = ["%s%s" % (("%d-%d" % (h["lo"], h["hi"])) if h["hi"] > h["lo"] else "%d" % h["lo"],
                           (" " + h["school"]) if h["school"] and h["school"] != "All" else "") for h in d]
        words.append(" + ".join(parts) + " damage" + (" per pip" if per else "") + (" to all enemies" if kind == "aoe" else "")
                     + (" (or more, on a condition)" if any(h.get("cond") for h in d) else ""))
        for h in hits(hs, DOT):
            words.append("+ %d%s over %d rounds" % (h["lo"], (" " + h["school"]) if h["school"] and h["school"] != "All" else "", h["rounds"] or 3))
    elif kind == "dot":
        for h in hits(hs, DOT):
            words.append("%d%s damage over %d rounds" % (h["lo"], (" " + h["school"]) if h["school"] and h["school"] != "All" else "", h["rounds"] or 3))
    elif kind == "heal":
        for h in hs:
            if h["type"] in HEAL:
                words.append("Heal %d%s" % (h["lo"], " to all" if h["target"] in FRIEND_ALL else ""))
            elif h["type"] in HOT:
                words.append("Heal %d over %d rounds%s" % (h["lo"], h["rounds"] or 3, " to all" if h["target"] in FRIEND_ALL else ""))
    elif kind in ("blade", "trap", "ward", "weakness"):
        want = "kModifyOutgoingDamage" if kind in ("blade", "weakness") else "kModifyIncomingDamage"
        hh = [h for h in hs if h["type"] == want]
        sch = _schools(hh)
        sign = "-" if kind in ("ward", "weakness") else "+"
        words.append("%s%d%% to next %s" % (sign, value or 0, (", ".join(sch) + " spell") if sch else "spell")
                     + (" (all of you)" if any(h["target"] in FRIEND_ALL for h in hh) else ""))
    elif kind == "aura":
        hh = [h for h in hs if h["type"] == "kModifyOutgoingDamage"]
        sch = _schools(hh)
        words.append("+%d%% to %s for %d rounds" % (value or 0, (", ".join(sch) + " spells") if sch else "all spells",
                                                     max([h["rounds"] for h in hh] + [4])))
    elif kind == "enchant":
        words.append("+%d damage to a spell" % (value or 0))
    elif kind == "bubble":
        parts = []
        for h in global_heads(hs, card.get("type")):
            t, lo = h["type"], h["lo"] or 0
            what = GLOBAL_WORDS.get(t) or (("effect %s" % t) if isinstance(t, int) or not str(t).startswith("k") else str(t)[1:])
            sch = h["school"] if h["school"] and h["school"] != "All" else ""
            p = ("%+d%% " % lo if lo else "") + (sch + " " if sch else "") + what
            if p not in parts:
                parts.append(p)
        words.append("Global: " + (", ".join(parts[:4]) or "a bubble"))
    elif kind == "absorb":
        ab = [h for h in hs if h["type"] in ABSORB]
        per = card.get("x_pips") or any(h["per_pip"] for h in ab)
        words.append("Absorbs %d damage%s%s" % (value or 0, " per pip" if per else "",
                                               " (all of you)" if any(h["target"] in FRIEND_ALL for h in ab) else ""))
    elif kind in ("sharpen", "potent"):
        words.append("+%d%% to a %s card" % (value or 0, "blade" if kind == "sharpen" else "trap"))
    elif kind in ("negaura", "curse", "charm"):
        # (what it changes, as a bubble's text: "+25% Fire damage taken", "-45% accuracy"; a negative aura's rounds)
        parts = []
        for h in hs:
            t, lo = h["type"], h["lo"] or 0
            if t in PRISM:
                p = "changes the school"
            else:
                what = GLOBAL_WORDS.get(t) or (("effect %s" % t) if isinstance(t, int) or not str(t).startswith("k") else str(t)[1:])
                sch = h["school"] if h["school"] and h["school"] != "All" else ""
                p = ("%+d%% " % lo if lo and t in GLOBAL_WORDS else "") + (sch + " " if sch else "") + what
            if p not in parts:
                parts.append(p)
        rounds = max([h["rounds"] or 0 for h in hs] + [0])
        words.append(", ".join(parts[:4]) + ((" for %d rounds" % rounds) if kind == "negaura" and rounds else "")
                     + (" (an enemy)" if kind != "charm" and any(h["target"] in ENEMY for h in hs) else ""))
    else:
        seen = []
        for h in hs:
            t = h["type"]
            t = ("effect %s" % t) if isinstance(t, int) or not str(t).startswith("k") else str(t)[1:]
            if t not in seen:
                seen.append(t)
        words.append(", ".join(seen[:4]) or (card.get("type") or ""))
    text = " ".join(w for w in words if w)
    return re.sub(r"\s+", " ", text).strip()[:120]


# (the damage types counted head by head - /cards' heads; a pip-power one only on an X-pip card, where it's per pip)
HEAD_TYPES = {"kDamage", "kDamageNoCrit", "kStealHealth"}
ODD_HEADS = {"kMaxHealthDamage", "kDivideDamage", "kInstantKill"}
LEAF_CLASSES = ("SpellEffect",)


def read_complete(card):
    """Whether everything the card does was read, so its heads and boosts can be trusted: its effects there and not cut
    short (tpl_info's effects_cut), every effect's type and target named (a number: that enum's name wasn't read), and
    every container (any class but SpellEffect - random, variable, list, conditional...) followed by its own effects one
    deeper (a container whose list wasn't read - Phantastic Jinn's, Delusion's - is no head at all in heads())"""
    fx = card.get("effects")
    if not isinstance(fx, list) or card.get("effects_cut") or len(fx) >= 1000:
        return False
    for i, e in enumerate(fx):
        t, tg = e.get("type"), e.get("target")
        if isinstance(t, int) or t is None or (isinstance(tg, int) and tg != 0):
            return False
        if (e.get("class") or "SpellEffect") not in LEAF_CLASSES:
            nxt = fx[i + 1] if i + 1 < len(fx) else None
            if nxt is None or (nxt.get("depth") or 0) <= (e.get("depth") or 0):
                return False
    return True


def heads_field(card):
    """/cards' field 24: the up-front damage of a damage / aoe card by school, every head of it - "fire:230,ice:230,
    storm:230" (a school's heads added, in the game's order; lower case, one of the seven). Each head its least: a random
    effect's lowest choice, a variable or X-pip effect's one pip, a conditional's least-damage alternative (heads()) -
    so the heads add up to /cards' value (an X-pip card: per pip). The enchantment on it isn't added (fields 20-21).
    "" not a damage / aoe card (pure damage over time included); "?" don't trust it: not read_complete, a head of a kind
    that isn't plain damage (max-health, divide, instant kill; pip power on a card that isn't X-pip), a head of no school
    of the seven (All, blank, Sun / Moon / Star / Shadow), or no head counted at all"""
    if card.get("kind") not in ("damage", "aoe"):
        return ""
    if not read_complete(card):
        return "?"
    hs = hits(heads(card.get("effects"), card.get("overrides")), DAMAGE | ODD_HEADS)
    out = {}
    for h in hs:
        t = h["type"]
        if t in ODD_HEADS or (t == "kDamagePerTotalPipPower" and not card.get("x_pips")):
            return "?"
        if t not in HEAD_TYPES and t != "kDamagePerTotalPipPower":
            return "?"
        s = (h.get("school") or "").strip().lower()
        if s not in SCHOOL_PIPS:
            return "?"
        out[s] = out.get(s, 0) + (h["lo"] or 0)
    if not out:
        return "?"
    return ",".join("%s:%d" % kv for kv in out.items())


def boosts_field(card):
    """/cards' field 25: what a blade, trap or aura boosts, by school - "ice:35,storm:35,fire:35" (Elemental Blade), "all:25"
    (Balanceblade: damage type All, or none - every school), the largest % per school, the card's own (a Sharpened Blade
    on it isn't added). A blade's or aura's: its kModifyOutgoingDamage effects of more than 0% not aimed at an enemy; a
    trap's: its kModifyIncomingDamage ones of more than 0% on an enemy or on no one said (Feint's +30% on yourself left
    out). A bubble's (a global): the damage its global effects add, the same way ("myth:25" Time of Legend; a global that
    adds no damage - healing, pierce - "?", like one with none). A negative aura's as a trap's: the damage an enemy takes
    besides ("fire:25" Fire Attenuate, "all:20" Attenuate; Starfall, Pathogen - none - "?"). "" not a blade, trap, aura,
    bubble or negative aura; "?" not read_complete, one of those from a conditional, one of another school (Sun, Moon,
    Star, Shadow), or none at all"""
    kind = card.get("kind")
    if kind not in ("blade", "trap", "aura", "bubble", "negaura"):
        return ""
    if not read_complete(card):
        return "?"
    out = {}
    hs = heads(card.get("effects"), card.get("overrides"))
    for h in (global_heads(hs, card.get("type")) if kind == "bubble" else hs):
        lo = h["lo"] or 0
        if kind in ("trap", "negaura"):
            if h["type"] != "kModifyIncomingDamage" or lo <= 0 or not (h["target"] in ENEMY or h["target"] in (None, 0, "kInvalidTarget")):
                continue
        elif h["type"] != "kModifyOutgoingDamage" or lo <= 0 or h["target"] in ENEMY:
            continue
        if h.get("cond"):
            return "?"
        s = (h.get("school") or "").strip().lower()
        s = "all" if s in ("", "all") else s
        if s != "all" and s not in SCHOOL_PIPS:
            return "?"
        out[s] = max(out.get(s, 0), lo)
    if not out:
        return "?"
    return ",".join("%s:%d" % kv for kv in out.items())


def finish(card, want_effects=True):
    """the card's kind, value, dot, text, its enchantment's effect, its heads and boosts by school - from what spell()
    read (in place)"""
    kind, value, dot = kind_of(card)
    card.update(kind=kind, value=value, dot=dot)
    card["value_text"] = value_text(card, kind, value)
    card["text"] = describe(card)
    card["ench_effect"], card["value_ench"] = ench_bonus(card)
    # (before the effects go: they're what these are worked out from)
    card["heads_text"], card["boosts_text"] = heads_field(card), boosts_field(card)
    if not want_effects:
        card.pop("effects", None)
        card.pop("ench_effects", None)


def castable(card, me):
    """Whether the card can be cast with my pips - an ESTIMATE for the normal mode (the hand as dealt: not while an
    enchantment or a target is being chosen), since the game keeps no "greyed" flag for a hand card (it draws the grey
    from the pips). True / False, None when it can't be told: no pips read, an astral spell (Sun, Star, Moon: how the
    game counts power pips for them isn't known here), or pips of a school it wants that I don't have (whether a
    power pip pays for those isn't known). The rule: a pip of a school the card wants (school_pips: "1 Fire pip"
    besides its pips) is paid with my pips of that school; then its pips (1 for an X-pip spell) with what's left -
    a generic pip counts 1, a power pip 2 for a spell of my own school (else 1), a school pip 2 for a spell of that
    school (else 1); its shadow pips with my shadow pips"""
    if card.get("pips") is None or not me or not me.get("pips"):
        return None
    sch = (card.get("school") or "").lower()
    if sch in ASTRAL:
        return None
    left = dict(me["pips"])
    for s, n in (card.get("school_pips") or {}).items():
        if left.get(s, 0) < n:
            return None
        left[s] = left.get(s, 0) - n
    if (card.get("shadow_pips") or 0) > left.get("shadow", 0):
        return False
    own = sch != "" and sch == (me.get("school") or "")
    have = left.get("generic", 0) + left.get("power", 0) * (2 if own else 1)
    have += sum(left.get(s, 0) * (2 if s == sch else 1) for s in SCHOOL_PIPS)
    need = 1 if card.get("x_pips") else card["pips"]
    return have >= need


# ============================================================================ /cards' lines
def _f(v):
    return "" if v is None else str(v).replace("|", "/").replace("\r", " ").replace("\n", " ")


def _b(v):
    return "" if v is None else ("1" if v else "0")


def me_line(me):
    """me|health|max|generic|power|balance|death|fire|ice|life|myth|storm|shadow|school (my own; '' unknown)"""
    pp = me.get("pips") or {}
    return "|".join(["me", _f(me.get("health")), _f(me.get("max_health")), _f(pp.get("generic")), _f(pp.get("power"))]
                    + [_f(pp.get(s)) for s in SCHOOL_PIPS] + [_f(pp.get("shadow")), _f(me.get("school"))])


def card_line(c):
    """card|slot|x|name|display|school|type|pips|xpip|shadow|castable|tc|item|enchantment|accuracy|value|kind|dot|
    school pips|enchantment's effect|value with it|template id|text|heads|boosts|l|t|r|b - heads (field 24): a damage
    card's damage by school, every head ("fire:230,ice:230,storm:230" - heads_field); boosts (25): what a blade, trap,
    aura or bubble boosts by school ("ice:35,storm:35,fire:35", "all:25" - boosts_field); "?" either one not to be
    trusted, "" none. l|t|r|b (26-29, v1.0.0 - after the old ones: an older bot reads its 25): the card's box in the
    GUI's root (GUI units, the root's size on answer's root| line - box_in_root; NOT CHECKED against the screen yet), ""
    not read"""
    sp = ",".join("%s:%d" % kv for kv in sorted((c.get("school_pips") or {}).items()))
    box = c.get("box") or (None, None, None, None)
    return "|".join(["card", _f(c.get("slot")), _f(c.get("x")), _f(c.get("name")), _f(c.get("display")),
                     _f(c.get("school")), _f(c.get("type")), _f(c.get("pips")), _b(bool(c.get("x_pips"))),
                     _f(c.get("shadow_pips")), _b(c.get("castable")), _b(bool(c.get("treasure"))),
                     _b(bool(c.get("item_card"))), _f(c.get("enchantment") or ""), _f(c.get("accuracy")),
                     _f(c.get("value_text")), _f(c.get("kind")), _f(c.get("dot")), sp, _f(c.get("ench_effect")),
                     _f(c.get("value_ench")), _f(c.get("template_id")), _f(c.get("text")),
                     _f(c.get("heads_text")), _f(c.get("boosts_text"))] + [_f(v) for v in box[:4]])


def answer(r, why=""):
    """/cards' answer: "none|<why>" unless in a battle, in the planning phase and settled; else one me| line, a card|
    line for each card shown (left to right: 29 fields - card_line), root|<w>|<h> (the GUI root's size in GUI units -
    the cards' boxes are in it; only when it's read - v1.0.0, an older bot skips the line) and hand|<cards>|<ms>"""
    if r is None:
        return "none|" + _f(why or "the game can't be read")
    if not (r.get("in_battle") and r.get("planning") and r.get("settled")):
        return "none|" + _f(r.get("why") or ("not in a battle" if not r.get("in_battle") else "not the planning phase"))
    lines = [me_line(r.get("me") or {})] + [card_line(c) for c in r.get("cards") or []]
    root = r.get("root")
    if root:
        lines.append("root|%d|%d" % (root[0], root[1]))
    lines.append("hand|%d|%s" % (len(r.get("cards") or []), r.get("ms")))
    return "\n".join(lines)


def phase_line(p, why=""):
    """/phase's answer: phase|state|in battle|planning|shown|own|size|ms|why (HandMem.phase: state none / round /
    waiting / changing / hand, 1/0 flags, "" not read), or none|<why> when the game can't be read"""
    if p is None:
        return "none|" + _f(why or "the game can't be read")
    return "|".join(["phase", _f(p.get("state")), _b(p.get("in_battle")), _b(p.get("planning")), _f(p.get("shown")),
                     _f(p.get("own")), _f(p.get("size")), _f(p.get("ms")), _f(p.get("why"))])


def nav_phase(nm, wait=0.3):
    """(p, why): HandMem.phase through navmem's NavMem nm - its attached game (or the one opened for the cards alone),
    its hand reader and its lock, as NavMem.cards (kept here so navmem.py needn't change: bagmem.nav_tree's way). None and
    why when the game can't be read (not running, the reader being made). Never raises"""
    try:
        st, why = nm._ensure(wait)
        if st is None:
            light = getattr(nm, "_cards_light", None)
            st, why = light(why) if light is not None else (None, why)
            if st is None:
                return None, why
        hm, why = nm._hand_reader(st, wait)
        if hm is None:
            return None, why
        with nm.lock:
            if hm.st is not st:
                return None, "the game changed"
            return hm.phase(), ""
    except Exception as e:  # noqa: BLE001 - never into the server
        return None, "reading the round's phase failed (%r)" % (e,)


# ============================================================================ command line
def _main():
    import argparse
    ap = argparse.ArgumentParser(description="read-only: the cards in your hand during a battle, and your pips")
    ap.add_argument("-n", type=int, default=1)
    ap.add_argument("-i", type=float, default=2.0)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--phase", action="store_true",
                    help="the round's phase alone (HandMem.phase - /phase), one line a reading: to watch what the hand "
                         "does when a card is clicked, its target clicked, the round played (e.g. -n 100 -i 0.1)")
    a = ap.parse_args()
    pids = N.find_pids()
    if not pids:
        sys.exit("the game is not running")
    fg = N.foreground_pid()
    try:
        st = N._Attached(fg if fg in pids else pids[0], print)
    except LookupError as e:
        print("navmem can't attach (%s) - the cards alone" % e)
        st = LightAttach(fg if fg in pids else pids[0], print)
    hm = HandMem(st, log=print)
    for k in range(a.n):
        if a.phase:
            print("%s  %s" % (time.strftime("%H:%M:%S"), phase_line(hm.phase())))
            if k + 1 < a.n:
                time.sleep(a.i)
            continue
        r = hm.read()
        print("%s  %s" % (time.strftime("%H:%M:%S"), answer(r).replace("\n", "\n          ")))
        print("          state %s, %.1f ms" % (r["state"], r["ms"]))
        if a.json:
            print(json.dumps(r, default=str)[:6000])
        if k + 1 < a.n:
            time.sleep(a.i)


if __name__ == "__main__":
    _main()
