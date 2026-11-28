"""reflect - READ-ONLY discovery tool: every reflected PROPERTY of a class in a running Wizard101 client (its offset, its
name, a guess at its C++ type) and the reflected NAMES that match a pattern (classes, properties - with the classes that
register them -, enum options) - the one tool for finding where a value lives before a reader is written for it: a
pet's (BasePetItemBehavior, PetItemBehaviorTemplate, PetLevelInfo), gear's (StatisticEffectInfo, WizItemTemplate,
RequirementList), the quests' and the wizard's (WizQuestData, WizGameStats - training points, the wizard's level), a
gate's (ObjectStateBehavior). Found the way every reader here finds its offsets: handmem.Image (a copy of the game's code)
and questmem.class_props (its own reflection registration) - nothing hard-coded.

    python reflect.py --class WizGameStats [--class BasePetItemBehavior,PetLevelInfo ...]
                                    every property of each class: offset, name, type guess, bytes to the next one
    python reflect.py --grep "rain|Training|Level"
                                    the reflected names matching (any case; --case: as written) - for a property the
                                    classes that register it and its offset there, for a class how many properties
                                    (--props: those too)
    python reflect.py --class X --grep Y --out reflect.txt      both, also written to a file - to send back
    [--pid N]                       that game client (else the one in front, else the first)

A class's OWN properties only: those it inherits are its base class's registration (WizClientObject's m_globalID is
CoreObject's) - --class that one too (a property's grep names every class registering it).

The answer, one line each (| between fields; a field never holds a | or a line break):
    # python reflect.py ... (when) - build <build>, pid <pid>
    class|<name>|<properties>|<GetType rva>|<vtables>|<first vtable rva>      (properties 0, the rest empty: not a
                                    reflected class in this build)
    prop|<class>|<offset>|<name>|<type guess>|<bytes to the next property>|<adder rva>    (by offset; type: the same
                                    property adder - AddProperty<T> - as a property whose type the readers here rely on
                                    (ANCHORS), "?" when none shares it; adder rva: properties of one type share it)
    grep|<names matching>|<listed>                      (the pattern: in the # line - a regex holds |)
    name|<name>|<kind>|<string rva>|<copies>|<what>     (kind: prop (m_...), class (a GetType with its Type and
                                    vtable), enum (kName, Scope::NAME), name (another identifier), other (with spaces,
                                    <>...); what: a property's "Class+0x1a4 Other+0x60" ("" none found), a class's
                                    "N properties")
    none|<why>

SAFETY. The game is opened as deckmem.py's command line opens it - navmem.py's _Attached (its read-only Proc:
PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, falling back to PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION), else
handmem.py's LightAttach (the same Proc, without the walker's signatures) - and only read: ReadProcessMemory of the
game's PE header and .text / .rdata / .data (handmem.Image - .data is the game's writable statics, copied as they are),
what _Attached reads checking its signatures as it opens the game (each GameClient static it finds - 8 bytes - and 8
bytes of the GameClient that points at, 0x20000 in), plus the module / toolhelp enumeration navmem.py uses to find it.
Nothing is ever written, allocated, injected, hooked, suspended or debugged; no window is touched and no input is sent.
Apart from that GameClient check no object of the game is read - the classes come from its code and its sections' data,
no object is walked.

FAILS SOFT. A class that isn't in this build is said (class|X|0 and a none| line), never guessed; a name whose owner
can't be found has an empty what. The pure parts - grep_names, name_kind, name_at, owner_candidates, guess_types,
class_lines, name_lines - are tested on made-up bytes (test_reflect.py), report() on a made-up game image.
"""
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

# properties whose C++ type the readers here rely on (read that way in the game, right): a property registered by the
# same adder (AddProperty<T>) is the same T. questmem.KIND_REF's (the madlib arguments) and what bagmem / deckmem read
ANCHORS = (("Window", "m_sName", "std::string"), ("ControlText", "m_sText", "std::wstring"),
           ("SpellEffect", "m_numRounds", "int"), ("Spell", "m_templateID", "unsigned int"),
           ("Window", "m_fAlpha", "float"), ("WizGoalData", "m_goalID", "gid (u64)"),
           ("ControlText", "m_bUseOutline", "bool"), ("ControlButton", "m_bGreyed", "bool"),
           ("WizGameStats", "m_currentGold", "int"), ("BasePetItemBehavior", "m_level", "unsigned char (u8)"),
           ("PetLevelInfo", "m_powerCardName", "std::string"), ("SpellData", "m_templateID", "unsigned int"),
           ("CoreObject", "m_inactiveBehaviors", "std::vector<SharedPointer<BehaviorInstance>>"),
           ("Window", "m_Children", "std::vector<SharedPointer<Window>>"),
           ("GameObjectTemplate", "m_adjectiveList", "std::list<std::string>"),
           ("DeckBehavior", "m_spellList", "std::list<SharedPointer<SpellData>>"),
           ("InventoryBehaviorBase", "m_itemList", "std::list<SharedPointer<WizClientObjectItem>>"),
           ("ItemTemplate", "m_equipEffects", "std::list<SharedPointer<GameEffectInfo>>"))
# a reflected name in .rdata: a NUL-terminated C string of these characters, a NUL before it
NAME = re.compile(rb"\x00([A-Za-z_][A-Za-z0-9_:<>,. ]{1,127})(?=\x00)")
# ...or (loose) one right after other bytes - a constant's, no NUL between (build 6AFBB954-37B4000, 2026-11-20: the
# only copy of "CombatPlanningPhaseWindow" its GetType loads came after "(@" - handmem.find_types): no space in it, the
# byte before it none of a name's characters (so never the tail of a longer one)
NAME_LOOSE = re.compile(rb"(?<![\x00A-Za-z0-9_:<>,. ])([A-Za-z_][A-Za-z0-9_:<>,.]{1,127})(?=\x00)")
NAME_CHARS = frozenset(b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_:<>,. ")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
CLASSY = re.compile(r"[A-Za-z_][A-Za-z0-9_:<>, ]*")      # (navmem.TypeNamer's TYPE_NAME: a class's name as GetType loads it)
ENUM = re.compile(r"k[A-Z0-9][A-Za-z0-9_]*|[A-Za-z_][A-Za-z0-9_]*::[A-Za-z0-9_:]+")
BOUNDARY = re.compile(rb"\xCC{2,}|\xC3\xCC")             # (the padding between functions - handmem.Image.func_start's too)
GET_TYPE_LIM = 0x200     # a class's name is loaded this far into its GetType at most (questmem.GET_TYPE_LIM)
SPAN = 0x6000            # a property's registration is this far after its class's GetType at most (handmem.class_props)
BACK = 12                # functions looked back through for that GetType (class_props: within the 6 after it)
GREP_LIMIT = 300         # names listed at most
SITES = 40               # places a property's name is loaded that are looked at, at most
PROPS_CLASSES = 20       # --props: classes dumped at most


# ============================================================================ pure helpers (no game)
def cell(v):
    """a field: no | or line breaks in it; None as empty"""
    return '' if v is None else re.sub(r'[|\r\n]+', ' ', str(v)).strip()


def grep_names(buf, pattern, base=0, case=False, loose=False):
    """[(address, name, copies)] of the reflected-looking names in buf (a copy of .rdata at address base - NAME: a
    NUL-terminated C string of identifier characters with a NUL before it; loose: NAME_LOOSE's too, right after other
    bytes - report()'s) that pattern (a regex: str or compiled - re.search, any case unless case) finds, each name once
    (its first address, how many times it's there), in buf's order"""
    rx = pattern if hasattr(pattern, "search") else re.compile(pattern, 0 if case else re.IGNORECASE)
    seen, out = {}, []
    padded = b"\x00" + bytes(buf)
    ms = list(NAME.finditer(padded))
    if loose:
        ms = sorted(ms + list(NAME_LOOSE.finditer(padded)), key=lambda m: m.start(1))
    for m in ms:
        s = m.group(1).decode("latin-1")
        i = seen.get(s)
        if i is None:
            # (each name searched once: -1 looked at, not matching)
            i = seen[s] = len(out) if rx.search(s) else -1
            if i >= 0:
                out.append([base + m.start(1) - 1, s, 0])
        if i >= 0:
            out[i][2] += 1
    return [tuple(x) for x in out]


def name_kind(s):
    """what a reflected-looking name is by its looks: prop (m_...), enum (kName, Scope::NAME), name (an identifier -
    maybe a class: report() checks), other"""
    if s.startswith("m_"):
        return "prop"
    if ENUM.fullmatch(s):
        return "enum"
    if IDENT.fullmatch(s):
        return "name"
    return "other"


def name_at(rdata, r0, addr):
    """the C string at addr in a copy of .rdata at r0 when it starts there (the byte before it a NUL, or none of a
    name's characters: a constant's - NAME_LOOSE) and looks like a class's name (CLASSY, not a property's m_...), else
    None"""
    i = addr - r0
    if not (0 < i < len(rdata)) or rdata[i - 1] in NAME_CHARS:
        return None
    s = bytes(rdata[i:i + 128]).split(b"\0", 1)[0].decode("latin-1")
    return s if s and CLASSY.fullmatch(s) and not s.startswith("m_") else None


def owner_candidates(text, t0, la, lea_at, lea_tgt, name_of, back=BACK, span=SPAN, lim=GET_TYPE_LIM):
    """the names (nearest first, each once) loaded RIP-relative (lea_at -> lea_tgt: handmem.Image's) in the first lim
    bytes of each of the back functions before the one holding la (a copy of .text at t0; functions split by BOUNDARY -
    int3 padding, a ret and an int3), within span before la - where the GetType of the class whose registration loads
    a property's name at la is (handmem.class_props: GetType loads its class's name near its start, and the registration
    is one of the functions just after it). lea_at ascending (handmem.Image's is). name_of(address) -> a class-like name
    or None. Candidates only: report() keeps the one whose class_props has the property"""
    import numpy as np
    lo, hi = max(0, la - t0 - span), la - t0
    starts = [lo + m.end() for m in BOUNDARY.finditer(bytes(text[lo:hi]))]
    if not starts:
        return []
    at, tgt = np.asarray(lea_at, dtype=np.int64), np.asarray(lea_tgt, dtype=np.int64)
    out = []
    # (each function's first lim bytes - not into the next one: the last start is la's own function)
    spans = list(zip(starts, starts[1:]))[-back:]
    for s, e in reversed(spans):
        i0, i1 = np.searchsorted(at, [t0 + s, t0 + min(s + lim, e)])
        for k in range(int(i0), int(i1)):
            nm = name_of(int(tgt[k]))
            if nm and nm not in out:
                out.append(nm)
    return out


def guess_types(props, anchors=ANCHORS):
    """{adder rva: type} from anchors [(class, property, type)] - props {class: {property: (offset, adder rva)}}
    (questmem.class_props'); two types on one adder: both, "a / b" (one of them - not known which)"""
    seen = {}
    for cls, prop, ty in anchors:
        v = (props.get(cls) or {}).get(prop)
        if v and v[1] is not None:
            seen.setdefault(v[1], [])
            if ty not in seen[v[1]]:
                seen[v[1]].append(ty)
    return {a: " / ".join(sorted(t)) for a, t in seen.items()}


def class_lines(cls, props, gt=None, vts=(), base=0, types=None):
    """the class| line and a prop| line a property (by offset) of class cls - props {property: (offset, adder rva)}, gt
    its GetType's address, vts its vtables', base the exe's (rvas given), types guess_types'. Not in this build (no GetType
    or no property): class|cls|0||| and none|why"""
    types = types or {}
    if gt is None:
        return ["class|%s|0|||" % cell(cls),
                "none|%s: not a reflected class in this build (no GetType caching its Type with a vtable)" % cell(cls)]
    out = ["class|%s|%d|%#x|%d|%s" % (cell(cls), len(props), gt - base, len(vts), "%#x" % (vts[0] - base) if vts else "")]
    order = sorted(props.items(), key=lambda kv: (kv[1][0], kv[0]))
    for i, (name, (off, adder)) in enumerate(order):
        nxt = next((o for _, (o, _a) in order[i + 1:] if o > off), None)
        out.append("prop|%s|%#x|%s|%s|%s|%s" % (cell(cls), off, cell(name),
                                                cell(types.get(adder, "?") if adder is not None else "?"),
                                                "%#x" % (nxt - off) if nxt is not None else "",
                                                "%#x" % adder if adder is not None else ""))
    if not props:
        out.append("none|%s: a class, but no property registration found after its GetType" % cell(cls))
    return out


def name_lines(hits, total, base=0):
    """the grep| line and a name| line a name - hits [(address, name, copies, kind, what)], total the names found"""
    out = ["grep|%d|%d" % (total, len(hits))]
    for addr, name, copies, kind, what in hits:
        out.append("name|%s|%s|%#x|%d|%s" % (cell(name), kind, addr - base, copies, cell(what)))
    return out


# ============================================================================ the game's image (read-only)
def report(img, base, classes=(), pattern=None, case=False, limit=GREP_LIMIT, props=False, log=None):
    """the answer's lines (the module's docstring) for a copy of the game's code img (handmem.Image - or one made up,
    with its secs, lea_at, lea_tgt, strings and get_types) at the exe's base: each class's properties, then the names
    pattern finds. Never raises: a class or a name that fails is said"""
    import questmem as Q
    log = log or (lambda msg: None)
    cache = {}

    def props_of(cls):
        if cls not in cache:
            try:
                p, gt, vts = Q.class_props(img, cls)
                cache[cls] = ({k: (v[0], v[1]) for k, v in p.items()}, gt, vts)
            except Exception as e:  # noqa: BLE001 - said, the rest read
                log("reflect: %s couldn't be read (%r)" % (cls, e))
                cache[cls] = ({}, None, [])
        return cache[cls]

    def is_class(name):
        try:
            return any(st is not None and v for _f, st, v in Q.get_types(img, name))
        except Exception:  # noqa: BLE001
            return False

    out = []
    types = guess_types({cls: props_of(cls)[0] for cls, _p, _t in ANCHORS})
    want = [c for c in classes if c]
    for cls in want:
        p, gt, vts = props_of(cls)
        out += class_lines(cls, p, gt, vts, base, types)
    if pattern:
        r0, rdata = img.secs[".rdata"]
        t0, text = img.secs[".text"]
        found = grep_names(rdata, pattern, r0, case, loose=True)
        hits, dump = [], []
        for addr, name, copies in found[:limit]:
            kind, what = name_kind(name), ""
            try:
                if kind == "prop":
                    owners = []
                    for sa in img.strings(name) + img.strings(name, loose=True):
                        for la in list(img.lea_at[img.lea_tgt == sa])[:SITES]:
                            for cand in owner_candidates(text, t0, int(la), img.lea_at, img.lea_tgt,
                                                         lambda a: name_at(rdata, r0, a)):
                                p = props_of(cand)[0]
                                if name in p:
                                    if (cand, p[name][0]) not in owners:
                                        owners.append((cand, p[name][0]))
                                    break
                    what = " ".join("%s+%#x" % o for o in owners)
                elif kind in ("name", "other") and is_class(name):
                    kind = "class"
                    what = "%d properties" % len(props_of(name)[0])
                    if props and name not in want and len(dump) < PROPS_CLASSES:
                        dump.append(name)
            except Exception as e:  # noqa: BLE001 - this name's what left empty
                log("reflect: %s couldn't be looked into (%r)" % (name, e))
            hits.append((addr, name, copies, kind, what))
        out += name_lines(hits, len(found), base)
        for cls in dump:
            p, gt, vts = props_of(cls)
            out += class_lines(cls, p, gt, vts, base, types)
    return out


def attach(pid=None, log=None):
    """(the game opened read-only, "") - navmem's _Attached as deckmem.py's command line, else (a signature the walker
    needs isn't in this build) handmem's LightAttach: the same read-only Proc - or (None, why)"""
    log = log or (lambda msg: None)
    try:
        import navmem as N
    except Exception as e:  # noqa: BLE001 - (Windows only: its ctypes.WinDLL)
        return None, "the game's reader can't be loaded here (%r) - Windows only" % (e,)
    pids = N.find_pids()
    if not pids:
        return None, "the game is not running"
    if pid is None:
        fg = N.foreground_pid()
        pid = fg if fg in pids else pids[0]
    elif pid not in pids:
        return None, "no game client with pid %d (running: %s)" % (pid, ", ".join(str(p) for p in pids))
    try:
        return N._Attached(pid, lambda m: None), ""
    except LookupError as e:
        log("reflect: %s - opened without the walker's signatures" % e)
    except Exception as e:  # noqa: BLE001
        return None, "the game (pid %d) couldn't be opened for reading (%r)" % (pid, e)
    try:
        import handmem as H
        return H.LightAttach(pid, log=log), ""
    except Exception as e:  # noqa: BLE001
        return None, "the game (pid %d) couldn't be opened for reading (%r)" % (pid, e)


# ============================================================================ the command line
def _main():
    import argparse
    ap = argparse.ArgumentParser(description="read-only: every reflected property of a class, and the reflected names "
                                             "matching a pattern, in the running game")
    ap.add_argument("--class", dest="classes", action="append", default=[],
                    help="a class (repeat it, or A,B,...): every property, its offset and type guess")
    ap.add_argument("--grep", default="", help="a regex: the reflected names it finds (any case)")
    ap.add_argument("--case", action="store_true", help="with --grep: as written, not any case")
    ap.add_argument("--props", action="store_true", help="with --grep: every class it finds dumped too (%d at most)"
                                                         % PROPS_CLASSES)
    ap.add_argument("--limit", type=int, default=GREP_LIMIT, help="with --grep: names listed at most")
    ap.add_argument("--pid", type=int, default=None, help="that game client (else the one in front)")
    ap.add_argument("--out", default="", help="also write the answer to this file (to send)")
    a = ap.parse_args()
    classes = [c.strip() for arg in a.classes for c in arg.split(",") if c.strip()]
    if not classes and not a.grep:
        ap.error("--class and / or --grep")
    if any(not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_:<> ]*", c) for c in classes):
        ap.error("--class: a class's name - letters, digits, _ (and :: < > of a template's)")
    if a.grep:
        try:
            re.compile(a.grep)
        except re.error as e:
            ap.error("--grep: not a regex (%s)" % e)
    t0 = time.perf_counter()
    st, why = attach(a.pid, log=print)
    if st is None:
        lines = ["none|" + cell(why)]
    else:
        try:
            import handmem as H
            img = H.Image(st)
            print("(the game's code read in %.1f s)" % (time.perf_counter() - t0))
            lines = report(img, st.m.base, classes, a.grep or None, a.case, max(1, a.limit), a.props, log=print)
            lines.insert(0, "# python reflect.py %s (%s) - build %s, pid %d" % (
                " ".join(sys.argv[1:]), time.strftime("%Y-%m-%d %H:%M:%S"), st.m.build, st.p.pid))
        except Exception as e:  # noqa: BLE001
            lines = ["none|reading the game's code failed (%r)" % (e,)]
        finally:
            st.close()
    print("\n".join(lines))
    if a.out:
        with open(a.out, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        print("(written to %s - %d lines)" % (os.path.abspath(a.out), len(lines)))


if __name__ == "__main__":
    _main()
