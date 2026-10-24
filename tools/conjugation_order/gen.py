import json, re, sys, collections
sys.path.insert(0, sys.argv[1])
from conj_spec import SPEC
S_DIR = sys.argv[1]
rows = json.load(open(S_DIR + '/conj.json', encoding='utf-8'))
shown = {}
for line in open(S_DIR + '/shown.txt', encoding='utf-8'):
    if line.startswith('SHOWN\t'):
        _, r, js = line.rstrip('\n').split('\t', 2)
        shown[r] = json.loads(js)

def is_kana(c):
    return all(0x3041 <= ord(ch) <= 0x3096 or ch == 'ー' for ch in c)

def head(c):
    if not is_kana(c) and c and 0x3041 <= ord(c[0]) <= 0x3096:
        return c
    out = ''
    for ch in c:
        if 0x3041 <= ord(ch) <= 0x3096:
            break
        out += ch
    return out

def heads_of(lst):
    out = []
    for c in lst:
        h = head(c)
        if h and h not in out:
            out.append(h)
    return out

def has_katakana(c):
    return any(0x30A1 <= ord(ch) <= 0x30FA for ch in c)

def apply_order(cur, target):
    out = []
    for h in target:
        if h in cur and h not in out:
            out.append(h)
    out += [h for h in cur if h not in out]
    return out

def move(order, h, p):
    if h not in order:
        return order
    o = [x for x in order if x != h]
    o.insert(min(p - 1, len(o)), h)
    return o

seeds, suppr, report = {}, [], []
by_reading = {r['reading']: r for r in rows}
for reading, spec in SPEC.items():
    r = by_reading[reading]
    labels = [f['label'] for f in r['forms']]
    form_reading = {f['label']: f['reading'] for f in r['forms']}
    cur = {L: heads_of(shown[form_reading[L]]) for L in labels}
    if 'skip' in spec:
        report.append(f'{reading}: 未対応 — {spec["skip"]}')
        continue
    if 'note' in spec:
        report.append(f'{reading}: 一部未対応 — {spec["note"]}')
    target = dict(cur)
    def majority_order(exclude=None):
        cnt = collections.Counter(tuple(cur[L][:2]) for L in labels if L != exclude and len(cur[L]) >= 2)
        best = cnt.most_common(1)[0][0]
        for L in labels:
            if tuple(cur[L][:2]) == best:
                return cur[L]
    if 'all' in spec:
        for L in labels:
            target[L] = apply_order(cur[L], spec['all'])
    if 'match' in spec:
        for L in labels:
            target[L] = apply_order(cur[L], cur[spec['match']])
    if spec.get('majority'):
        m = majority_order()
        for L in labels:
            target[L] = apply_order(cur[L], m)
    for L, f in spec.get('forms', {}).items():
        if isinstance(f, list):
            keep = [x for x in f if isinstance(x, tuple)]
            names = [x for x in f if not isinstance(x, tuple)]
            prefix = cur[L][:keep[0][1]] if keep else []
            target[L] = apply_order(cur[L], prefix + names)
        elif f[0] == 'match':
            target[L] = apply_order(cur[L], cur[f[1]])
        elif f[0] == 'majority':
            target[L] = apply_order(cur[L], majority_order(exclude=L))
        elif f[0] == 'swap12':
            t = list(cur[L])
            if len(t) >= 2:
                t[0], t[1] = t[1], t[0]
            target[L] = t
        elif f[0] == 'pos':
            target[L] = move(target[L], f[1], f[2])
    for h, p in spec.get('pos', []):
        for L in labels:
            target[L] = move(target[L], h, p)
    for L, lst in spec.get('pos_forms', {}).items():
        for h, p in lst:
            target[L] = move(target[L], h, p)
    if 'shift_later' in spec:
        h = spec['shift_later']
        for L in labels:
            if h in target[L]:
                target[L] = move(target[L], h, target[L].index(h) + 2)
    if 'forms_after' in spec:
        _, src = spec['forms_after']['*']
        for L in labels:
            t = [x for x in target[L] if x != '若杉']
            want = [x for x in cur[src][1:3] if x != '若杉']
            t = apply_order(t, t[:1] + want)
            target[L] = move(t + (['若杉'] if '若杉' in target[L] else []), '若杉', 4)
    for L in labels:
        fr = form_reading[L]
        removed = set(spec.get('remove', [])) | set(spec.get('remove_forms', {}).get(L, []))
        lst = shown[fr]
        drop = [c for c in lst if head(c) in removed or (spec.get('remove_katakana') and head(c) and has_katakana(c) and head(c) != c)]
        for c in drop:
            suppr.append((c, fr, reading))
        keep = [c for c in lst if c not in drop]
        # サ変は頼まれた頭が候補に無ければ 名詞+活用語尾 で補う
        if r['kind'] == 'suru':
            requested = list(spec.get('all') or [])
            suffix = fr[len(reading):]
            for h in requested:
                if h not in heads_of(keep) and h not in removed and all(0x4E00 <= ord(ch) <= 0x9FFF for ch in h):
                    keep.append(h + suffix)
                    report.append(f'{reading}/{fr}: {h}{suffix} を補った')
        base = target[L] + [h for h in heads_of(keep) if h not in target[L]]
        if spec.get('all'):
            base = apply_order(base, spec['all'])
        order = [h for h in base if h not in removed]
        # 並べ直し: かな(頭が空)は元の位置、漢字の頭は order の順
        kana_pos = {i: c for i, c in enumerate(keep) if not head(c)}
        groups = collections.OrderedDict((h, [c for c in keep if head(c) == h]) for h in order)
        flat = [c for g in groups.values() for c in g]
        flat += [c for c in keep if head(c) and c not in flat]
        result = []
        it = iter(flat)
        for i in range(len(keep)):
            if i in kana_pos:
                result.append(kana_pos[i])
            else:
                result.append(next(it))
        missing = [h for h in (spec.get('all') or []) if h not in heads_of(keep) and h not in removed]
        if L in spec.get('forms', {}) and isinstance(spec['forms'][L], list):
            missing += [h for h in spec['forms'][L] if isinstance(h, str) and h not in heads_of(keep)]
        if missing:
            report.append(f'{reading}/{fr}: 候補に無い頭 {missing}(並べられない)')
        if heads_of(result) != heads_of(lst) or drop or len(keep) != len(lst) - len(drop):
            seeds[fr] = result
json.dump({'seeds': seeds, 'suppr': suppr, 'report': report}, open(S_DIR + '/conj_out.json', 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
print(len(seeds), 'seeds', len(suppr), 'suppr', len(report), 'report')
