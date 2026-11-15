"""battlehist.py - the Battles tab of the bot's window (Dashboard.ahk DashBhFill): every card cast in a battle, round by
round, by everyone in it - you, your party, the enemies. Read from the battle recorder's files only (vision\\battlerec.py
writes them: learned\\battles\\current.json for the battle in progress, YYYY-MM\\YYYY-MM-DD.jsonl for the ones over) -
never the game's memory, never the game's log.

    GET /bhist?list=1     the battles recorded today and yesterday, newest first (50 at most), one a line:
                            b<TAB>id<TAB>HH:MM<TAB>result<TAB>rounds<TAB>enemies
    GET /bhist?b=cur      the battle in progress, else the last one recorded
    GET /bhist?b=<id>     one recorded battle (an id from the list)
  A battle's answer: a heading line, then one line a cast (and a line for the effects over time and the knockouts of a
  round), in the order the game played them:
      h<TAB>id<TAB>live (1: in progress)<TAB>result<TAB>rounds<TAB>zone<TAB>enemies<TAB>HH:MM
      c<TAB>round<TAB>side (me / ally / enemy / "")<TAB>who<TAB>card<TAB>pips<TAB>targets<TAB>what it did
  "none<TAB>why" when there's nothing to show; "busy" while a gated request (the bot's or the walker's read) is in flight
  (vision.py: the dashboard asks again a few seconds later).

Names: you are "You"; a wizard on your side who isn't in your own party is "Ally" and one on the other side "Enemy
wizard" - the recorder keeps only a hash of a stranger's name. Enemies of the same name are numbered left to right
(Winter Skull 1, Winter Skull 2). A card's name is the game's display name where cards.jsonl knows it (the cards seen in
your hand), else the spell's own name made readable ("HeckHoundIce_Trainable" -> "Heck Hound Ice").

Cheap: current.json is read again only when it changed; a day file is read once and then only what was added to it,
each battle's place in the file kept so one battle is read back by itself.
"""
import json
import os
import re
import threading
import time

LIST_MAX = 50
_LOCK = threading.Lock()
_DAYS = {}      # path: {"size", "mtime", "pos", "items": [summary + "off"/"len"]}
_CUR = {"key": None, "duel": None}
_NAMES = {"key": None, "map": {}}

# (an effect's words: the game's effect name -> (a word for it, the param is a percent))
EFFECTS = {
    "kModifyOutgoingDamage": ("blade", True), "kModifyIncomingDamage": ("trap", True),
    "kModifyIncomingDamageType": ("prism", False), "kModifyOutgoingDamageType": ("convert", False),
    "kModifyAccuracy": ("accuracy", True), "kModifyOutgoingArmorPiercing": ("pierce", True),
    "kModifyIncomingArmorPiercing": ("pierce taken", True), "kModifyOutgoingHeal": ("outgoing heal", True),
    "kModifyIncomingHeal": ("incoming heal", True), "kAbsorbDamage": ("absorb", False),
    "kDamageOverTime": ("damage over time", False), "kHealOverTime": ("heal over time", False),
    "kStun": ("stun", False), "kStunResist": ("stun block", False), "kStunBlock": ("stun block", False),
    "kDispel": ("dispel", False),
    "kReshuffle": ("reshuffle", False), "kModifyPips": ("pips", False), "kModifyPowerPips": ("power pips", False),
    "kModifyShadowPips": ("shadow pips", False), "kPipConversion": ("pip conversion", False),
    "kCloakedCharm": ("hidden charm", False), "kCloakedWard": ("hidden ward", False),
    "kModifyCardDamage": ("enchant", False), "kMaxHealth": ("max health", False), "kPolymorph": ("polymorph", False),
    "kRemoveCharm": ("charm removed", False), "kRemoveWard": ("ward removed", False),
    "kRemoveOverTime": ("over-time removed", False), "kConfusion": ("confusion", False),
    "kClue": ("clue", False), "kHeal": ("heal", False), "kHealPercent": ("heal", True), "kDamage": ("damage", False),
}


def battles_dir(root):
    return os.path.join(root, "learned", "battles")


# ---------------------------------------------------------------------------------------------------- names
def card_names(base):
    """{the spell's own name: its display name} from cards.jsonl (read again when it changed)"""
    p = os.path.join(base, "cards.jsonl")
    try:
        st = os.stat(p)
    except OSError:
        return {}
    key = (st.st_size, st.st_mtime_ns)
    if _NAMES["key"] == key:
        return _NAMES["map"]
    names = {}
    try:
        with open(p, "r", encoding="utf-8", errors="replace") as f:
            for ln in f:
                try:
                    c = json.loads(ln)
                except ValueError:
                    continue
                if isinstance(c, dict) and c.get("rec") == "card" and c.get("name") and c.get("display"):
                    names[c["name"]] = c["display"]
    except OSError:
        return _NAMES["map"]
    _NAMES["key"], _NAMES["map"] = key, names
    return names


def pretty(spell, names=None):
    """a spell's name for people: its display name when known, else its own one made readable"""
    if spell is None:
        return ""
    s = str(spell)
    if names and s in names:
        return names[s]
    m = re.match(r"^Pet\s*-\s*(.+?)\s*-\s*Trigger$", s)
    if m:
        return "Pet: " + m.group(1)
    s = re.sub(r"_(Trainable|Monster|Mob|Boss|NPC|TC|Treasure)\b", "", s, flags=re.I)
    s = s.replace("_", " ")
    s = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", s)
    return re.sub(r"\s+", " ", s).strip() or str(spell)


def obj_name(obj):
    """a mob's template object name made readable, for one the log named nowhere: CL_Rat-R3 -> Rat"""
    s = re.sub(r"-R\d+$", "", str(obj))
    s = re.sub(r"^[A-Za-z0-9]{1,4}_", "", s)
    s = re.sub(r"[-_]+", " ", s)
    s = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def clean(s):
    return re.sub(r"[\t\r\n]+", " ", str(s)) if s is not None else ""


# ---------------------------------------------------------------------------------------------------- one battle
def who_names(parts):
    """{sc: (side, name)} from [{sc, side, name | name_h}] - you "You", a stranger by side, same-named enemies numbered"""
    out = {}
    for p in sorted(parts, key=lambda p: p["sc"]):
        side = p.get("side") or ("enemy" if p["sc"] < 4 else "ally")
        nm = p.get("name")
        if side == "me":
            nm = "You"
        elif not nm and p.get("obj"):
            nm = obj_name(p["obj"])
        if side != "me" and (not nm or str(nm).startswith("#h:")):
            nm = "Ally" if side == "ally" else ("Enemy wizard" if p.get("wiz") or p.get("player") else "Enemy")
        out[p["sc"]] = [side, clean(nm)]
    count = {}
    for sc, (side, nm) in out.items():
        count[(side, nm)] = count.get((side, nm), 0) + 1
    seen = {}
    for sc in sorted(out):
        side, nm = out[sc]
        if count[(side, nm)] > 1 and nm != "You":
            seen[(side, nm)] = seen.get((side, nm), 0) + 1
            out[sc][1] = "%s %d" % (nm, seen[(side, nm)])
    return {sc: tuple(v) for sc, v in out.items()}


def enemies_text(who):
    n = {}
    for sc in sorted(who):
        side, nm = who[sc]
        if side == "enemy":
            base = re.sub(r" \d+$", "", nm)
            n[base] = n.get(base, 0) + 1
    return ", ".join(k + (" x%d" % v if v > 1 else "") for k, v in n.items())


def num(v):
    try:
        return "{:,}".format(int(round(float(v))))
    except (TypeError, ValueError):
        return str(v)


def effect_text(effect, param):
    word, pct = EFFECTS.get(effect, (None, False))
    if word is None:
        word = re.sub(r"(?<=[a-z])(?=[A-Z])", " ", re.sub(r"^k", "", str(effect))).lower()
    if effect == "kModifyIncomingDamage" and isinstance(param, (int, float)) and param < 0:
        word = "shield"
    if effect == "kModifyOutgoingDamage" and isinstance(param, (int, float)) and param < 0:
        word = "weakness"
    if effect in ("kModifyIncomingDamageType", "kModifyOutgoingDamageType", "kStun", "kStunResist", "kStunBlock",
                  "kDispel", "kReshuffle", "kCloakedCharm", "kCloakedWard", "kPolymorph", "kConfusion") or param in (None, ""):
        return word
    if pct:
        p = int(round(float(param))) if isinstance(param, (int, float)) else param
        return "%s %s%%" % (word, ("+%d" % p) if isinstance(p, int) and p > 0 else p)
    return "%s %s" % (word, num(param))


def cast_line(c, who, names):
    """(card, pips, targets, what it did) of one cast"""
    def nm(sc):
        w = who.get(sc)
        return w[1] if w else "?"
    if c.get("pass"):
        return "Pass", "", "", ""
    card = pretty(c.get("spell"), names) if c.get("spell") is not None else "(nothing)"
    pips = ""
    pp = c.get("pips")
    if isinstance(pp, list) and pp:
        pips = str(pp[0])
        if len(pp) > 1 and pp[1]:
            pips += "+%s shadow" % pp[1]
    if c.get("missed"):
        return card, pips, "", "fizzled"
    targets, did = [], []

    def tgt(sc):
        if sc is not None and sc not in targets:
            targets.append(sc)
    hp = [h for h in c.get("hp") or [] if isinstance(h, list) and len(h) >= 3]
    hit = set()
    for sc, before, delta in (h[:3] for h in hp):
        tgt(sc)
        hit.add(sc)
        if isinstance(delta, (int, float)) and delta < 0:
            did.append("%s to %s" % (num(-delta), nm(sc)))
        elif isinstance(delta, (int, float)) and delta > 0:
            did.append("healed %s %s" % (nm(sc), num(delta)))
    fx_words = {}
    for f in c.get("fx") or []:
        if not isinstance(f, list) or len(f) < 3:
            continue
        sc, eff, param = f[0], f[1], f[2]
        tgt(sc)
        if eff == "kDamage":
            if sc not in hit:
                did.append("%s to %s (no health lost)" % (num(param), nm(sc)))
            continue
        if eff in ("kHeal", "kHealPercent") and sc in hit:
            continue
        fx_words.setdefault(effect_text(eff, param), []).append(nm(sc))
    for word, on in fx_words.items():
        did.append("%s on %s" % (word, ", ".join(dict.fromkeys(on))))
    if any(isinstance(x, list) and len(x) >= 3 and not x[2] for x in c.get("crit") or []):
        did.append("critical")
    if c.get("dead"):
        did.append("(out of the battle)")
    names_t = [nm(sc) for sc in targets]
    caster_side = who.get(c.get("sc"), ("", ""))[0]
    foes = sorted(sc for sc, w in who.items() if (w[0] == "enemy") != (caster_side == "enemy"))
    if len(targets) > 1 and foes and sorted(targets) == foes:
        names_t = ["all enemies" if caster_side != "enemy" else "your side"]
    return card, pips, ", ".join(names_t), "; ".join(did)


def rows_of(rounds, who, names):
    """[[round, side, who, card, pips, targets, did]] - every cast, a round's effects over time and knockouts"""
    out = []
    for r in rounds:
        n = r.get("n")
        for c in r.get("casts") or []:
            w = who.get(c.get("sc"), ("", "?"))
            card, pips, targets, did = cast_line(c, who, names)
            if c.get("pet") and card and not card.startswith("Pet"):
                card = "Pet: " + card
            out.append([n, w[0], w[1], card, pips, targets, did])
        fx = r.get("fx") or {}
        ticks = []
        for h in fx.get("hp") or []:
            if isinstance(h, list) and len(h) >= 3 and isinstance(h[2], (int, float)) and h[2]:
                w = who.get(h[0], ("", "?"))
                ticks.append(("%s to %s" % (num(-h[2]), w[1])) if h[2] < 0 else ("healed %s %s" % (w[1], num(h[2]))))
        if ticks:
            out.append([n, "", "", "(over time)", "", "", "; ".join(ticks)])
        died = [who.get(sc, ("", "?"))[1] for sc in r.get("died") or []]
        if died:
            out.append([n, "", "", "(knocked out)", "", ", ".join(died), ""])
    return out


def answer(head, rows):
    lines = ["\t".join(["h"] + [clean(x) for x in head])]
    for r in rows:
        lines.append("\t".join(["c"] + [clean(x) for x in r]))
    return "\n".join(lines)


def hhmm(stamp):
    m = re.search(r"\b(\d\d:\d\d)(:\d\d)?$", str(stamp or ""))
    return m.group(1) if m else ""


def record_answer(rec, names, live=False):
    parts = rec.get("parts") or []
    if isinstance(parts, dict):
        parts = list(parts.values())
    who = who_names([p for p in parts if isinstance(p, dict) and p.get("sc") is not None])
    head = [rec.get("id") or "", "1" if live else "0", rec.get("result") or ("in progress" if live else ""),
            str(rec.get("rounds_n") if rec.get("rounds_n") is not None else len(rec.get("rounds") or [])),
            rec.get("zone") or "", enemies_text(who), hhmm(rec.get("t0"))]
    return answer(head, rows_of(rec.get("rounds") or [], who, names))


def duel_answer(s, names):
    """the open duel of current.json (battlerec's Parser state) as an answer"""
    import battlerec
    d = battlerec.load_duel(s)
    parts = []
    for sc, p in d["parts"].items():
        p = dict(p, sc=sc)
        q = {"sc": sc, "side": battlerec.side_of(d, p), "name": d["names"].get(sc), "wiz": p.get("wiz"),
             "obj": p.get("obj")}
        parts.append(q)
    rounds = [r for r in d["rounds"] if r.get("casts") or r.get("died") or (r.get("fx") or {}).get("hp")]
    rec = {"id": "%s-%s" % (re.sub(r"\D", "", str(d.get("t0") or ""))[:14], d.get("num")), "result": None,
           "rounds_n": max([r.get("n") or 0 for r in d["rounds"]] or [0]), "zone": d.get("zone"), "t0": d.get("t0"),
           "parts": parts, "rounds": rounds}
    return record_answer(rec, names, live=True)


# ---------------------------------------------------------------------------------------------------- the files
def current_duel(base):
    """the open duel (battlerec's saved Parser state) in current.json, else None"""
    p = os.path.join(base, "current.json")
    try:
        st = os.stat(p)
    except OSError:
        return None
    key = (st.st_size, st.st_mtime_ns)
    if _CUR["key"] != key:
        try:
            with open(p, "r", encoding="utf-8", errors="replace") as f:
                ck = json.load(f)
            duel = ((ck.get("parser") or {}).get("duel")) if isinstance(ck, dict) else None
        except (OSError, ValueError):
            return _CUR["duel"]
        _CUR["key"], _CUR["duel"] = key, duel
    return _CUR["duel"]


def day_files(base, now=None):
    """today's and yesterday's day files (with their -2, -3 ... parts), newest first"""
    t = time.time() if now is None else now
    out = []
    for day in (time.localtime(t), time.localtime(t - 86400)):
        d = time.strftime("%Y-%m-%d", day)
        folder = os.path.join(base, d[:7])
        try:
            names = os.listdir(folder)
        except OSError:
            continue
        rx = re.compile(r"^%s(-(\d+))?\.jsonl$" % re.escape(d))
        got = sorted(((int(m.group(2) or 1), n) for n in names for m in [rx.match(n)] if m), reverse=True)
        out += [os.path.join(folder, n) for _, n in got]
    return out


def day_items(path):
    """the battles in a day file, oldest first: {id, t0, result, rounds, zone, enemies, off, len} - read on from where
    the last read stopped"""
    try:
        st = os.stat(path)
    except OSError:
        _DAYS.pop(path, None)
        return []
    c = _DAYS.get(path)
    if c is None or st.st_size < c["pos"]:
        c = _DAYS[path] = {"pos": 0, "items": []}
    if st.st_size > c["pos"]:
        with open(path, "rb") as f:
            f.seek(c["pos"])
            data = f.read(st.st_size - c["pos"])
        end = data.rfind(b"\n") + 1      # (a line still being written stays for the next read)
        off = c["pos"]
        for raw in data[:end].split(b"\n"):
            here, off = off, off + len(raw) + 1
            if b'"battle"' not in raw[:40]:
                continue
            try:
                rec = json.loads(raw)
            except ValueError:
                continue
            parts = rec.get("parts") or []
            who = who_names([p for p in parts if isinstance(p, dict) and p.get("sc") is not None])
            c["items"].append({"id": rec.get("id") or "", "t0": rec.get("t0") or "", "result": rec.get("result") or "",
                               "rounds": rec.get("rounds_n") or 0, "zone": rec.get("zone") or "",
                               "enemies": enemies_text(who), "off": here, "len": len(raw)})
        c["pos"] += end
    return c["items"]


def recent(base, now=None):
    items = []
    for p in day_files(base, now):
        items += [dict(i, path=p) for i in day_items(p)]
    items.sort(key=lambda i: (i["t0"], i["id"]), reverse=True)
    return items[:LIST_MAX]


def read_record(item):
    with open(item["path"], "rb") as f:
        f.seek(item["off"])
        return json.loads(f.read(item["len"]))


def list_answer(base, now=None):
    items = recent(base, now)
    if not items:
        return "none\tno battles recorded today or yesterday (Settings: battlerec)"
    return "\n".join("\t".join(["b", clean(i["id"]), hhmm(i["t0"]), clean(i["result"]), str(i["rounds"]),
                                clean(i["enemies"])]) for i in items)


def battle_answer(base, which, now=None):
    names = card_names(base)
    if which in ("", "cur"):
        d = current_duel(base)
        if d is not None and d.get("rounds"):
            return duel_answer(d, names)
    items = recent(base, now)
    if not items:
        return "none\tno battle recorded yet today (Settings: battlerec)"
    item = items[0] if which in ("", "cur") else next((i for i in items if i["id"] == which), None)
    if item is None:
        return "none\tthat battle isn't in today's or yesterday's records"
    try:
        return record_answer(read_record(item), names)
    except (OSError, ValueError) as e:
        _DAYS.pop(item["path"], None)
        return "none\tits record couldn't be read (%s)" % (e.__class__.__name__,)


def reply(root, q, now=None):
    """the /bhist answer (vision.py)"""
    base = battles_dir(root)
    with _LOCK:
        if q.get("list") == "1":
            return list_answer(base, now)
        return battle_answer(base, q.get("b", "cur"), now)
