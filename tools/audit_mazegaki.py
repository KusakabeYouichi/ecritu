"""辞書の交ぜ書き候補の洗い出し(3699)。同じ読みに「全部漢字」の表記があり、かな+漢字の表記がその一部をかなに
置き換えた形になっているものを列挙する。出力: tmp/mazegaki_audit.tsv"""
import sqlite3, json, re, sys, collections, os
# リポジトリ直下(このファイルの 1 つ上)。作者の手元のパスをコードに残さない(セキュリティー検査 2026-10-25)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
joyo = set()
for line in open(f'{ROOT}/tmp/unihan_raw/Unihan_OtherMappings.txt', encoding='utf8'):
    if '\tkJoyoKanji\t' in line:
        joyo.add(chr(int(line.split('\t')[0][2:], 16)))
suppressed = collections.defaultdict(set)
for name in ('InitialSupprHiddenVocabMigration', 'InitialSupprVocabMigration'):
    try:
        for r, cs in json.load(open(f'{ROOT}/KeyboardExtension/{name}.json', encoding='utf8')).items():
            suppressed[r].update(cs)
    except FileNotFoundError:
        pass

def is_kanji(c): return '一' <= c <= '鿿' or c in '々〆'
def is_hira(c): return 'ぁ' <= c <= 'ゟ'
def all_kanji(s): return all(is_kanji(c) for c in s)
def mixed(s): return any(is_kanji(c) for c in s) and any(is_hira(c) for c in s) and all(is_kanji(c) or is_hira(c) for c in s)

def tokens(a):
    out = []
    for c in a:
        if is_hira(c) and out and out[-1][0] == 'h':
            out[-1] = ('h', out[-1][1] + c)
        else:
            out.append(('h', c) if is_hira(c) else ('k', c))
    return out

def align(a, b):
    """a(混ぜ書き)の かな run が b(全部漢字)の 1〜3 字に対応するか。対応する漢字の列を返す"""
    toks = tokens(a)
    def go(i, j, replaced):
        if i == len(toks):
            return replaced if j == len(b) else None
        kind, text = toks[i]
        if kind == 'k':
            if j < len(b) and b[j] == text:
                return go(i + 1, j + 1, replaced)
            return None
        for take in (1, 2, 3):
            if j + take <= len(b):
                r = go(i + 1, j + take, replaced + [b[j:j + take]])
                if r is not None:
                    return r
        return None
    return go(0, 0, [])

con = sqlite3.connect(f'{ROOT}/tmp/kana_kanji_dictionary.sqlite')
rows = con.execute('select reading, rank, candidate, cost from dictionary_entries order by reading, rank').fetchall()
groups = collections.defaultdict(list)
for reading, rank, cand, cost in rows:
    groups[reading].append((rank, cand, cost))
out = []
for reading, entries in groups.items():
    fulls = [(r, c, cost) for r, c, cost in entries if all_kanji(c)]
    if not fulls:
        continue
    for r, a, cost in entries:
        if not mixed(a) or a in suppressed.get(reading, ()):
            continue
        t = tokens(a)
        # 丁寧の接頭辞(お/ご)だけがかなのものは交ぜ書きではない
        if t[0][0] == 'h' and t[0][1] in ('お', 'ご') and all(k == 'k' for k, _ in t[1:]):
            continue
        for rb, b, costb in fulls:
            rep = align(a, b)
            if rep is None:
                continue
            flat = ''.join(rep)
            nonjoyo = [c for c in flat if c not in joyo]
            out.append((reading, a, b, flat, '非常用' if nonjoyo else '常用', r, rb, cost, costb))
            break
out.sort(key=lambda x: (x[4] != '非常用', x[5], x[0]))
with open(f'{ROOT}/tmp/mazegaki_audit.tsv', 'w', encoding='utf8') as f:
    f.write('読み\t交ぜ書き\t全部漢字\tかなに置かれた漢字\t区分\t順位(交)\t順位(漢)\tコスト(交)\tコスト(漢)\n')
    for row in out:
        f.write('\t'.join('' if v is None else str(v) for v in row) + '\n')
print('total', len(out), 'nonjoyo', sum(1 for x in out if x[4] == '非常用'), 'joyo', sum(1 for x in out if x[4] == '常用'))
print('rank0 mixed', sum(1 for x in out if x[5] == 0))
