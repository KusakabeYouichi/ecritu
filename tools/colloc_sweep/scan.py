#!/usr/bin/env python3
"""Wikipedia コーパスから 名詞 + 助詞(を/が/に/は/も/の) + 動詞 の3語組を数える。
出力: colloc_counts.json
  trigram[(noun_surface, noun_reading, particle, verb_reading_dictform)][verb_dictform_surface] = count
  verb_overall[verb_reading_dictform][verb_dictform_surface] = count
"""
import json
import re
import sys
import collections
from multiprocessing import Pool

from sudachipy import Dictionary, SplitMode

PARTICLES = {"を", "が", "に", "は", "も", "の"}
sent_split = re.compile(r"[。\n！？!?]")

_tok = None


def _init():
    global _tok
    _tok = Dictionary().create()


def _kata2hira(s):
    return "".join(chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c for c in s)


def _process(chunk):
    tri = collections.Counter()
    verb = collections.Counter()
    for sent in sent_split.split(chunk):
        sent = sent.strip()
        if not sent or len(sent) > 400:
            continue
        try:
            ms = _tok.tokenize(sent, SplitMode.C)
        except Exception:
            continue
        n = len(ms)
        for i in range(n):
            m = ms[i]
            pos = m.part_of_speech()
            if pos[0] != "動詞":
                continue
            dform = m.dictionary_form()
            if not dform or not any("一" <= ch <= "鿿" for ch in dform):
                continue  # 漢字を含む動詞だけ
            # 辞書形の読み: 表層の読み + 活用語尾を辞書形に合わせるのは難しいので、辞書形を再解析して読みを取る
            vr = _dict_reading(dform)
            if not vr:
                continue
            verb[(vr, dform)] += 1
            if i < 2:
                continue
            p = ms[i - 1]
            if p.part_of_speech()[0] != "助詞" or p.surface() not in PARTICLES:
                continue
            nm = ms[i - 2]
            npos = nm.part_of_speech()
            if npos[0] != "名詞" or npos[1] not in ("普通名詞",):
                continue
            ns = nm.surface()
            if not any("一" <= ch <= "鿿" for ch in ns):
                continue
            nr = _kata2hira(nm.reading_form())
            if not nr or not all("ぁ" <= ch <= "ゟ" or ch == "ー" for ch in nr):
                continue
            tri[(ns, nr, p.surface(), vr, dform)] += 1
    return tri, verb


_dict_reading_cache = {}


def _dict_reading(dform):
    r = _dict_reading_cache.get(dform)
    if r is not None:
        return r
    ms = _tok.tokenize(dform, SplitMode.C)
    if len(ms) != 1 or ms[0].part_of_speech()[0] != "動詞":
        r = ""
    else:
        r = _kata2hira(ms[0].reading_form())
        if not all("ぁ" <= ch <= "ゟ" or ch == "ー" for ch in r):
            r = ""
    _dict_reading_cache[dform] = r
    return r


def main():
    src, out = sys.argv[1], sys.argv[2]
    text = open(src, encoding="utf-8", errors="ignore").read()
    size = 2_000_000
    chunks = []
    i = 0
    while i < len(text):
        j = min(len(text), i + size)
        k = text.rfind("\n", i, j)
        if k <= i:
            k = j
        chunks.append(text[i:k])
        i = k
    tri = collections.Counter()
    verb = collections.Counter()
    with Pool(6, initializer=_init) as pool:
        for n, (t, v) in enumerate(pool.imap_unordered(_process, chunks)):
            tri.update(t)
            verb.update(v)
            if n % 10 == 0:
                print(f"chunk {n}/{len(chunks)} tri={len(tri)}", file=sys.stderr, flush=True)
    json.dump(
        {
            "tri": [[*k, c] for k, c in tri.items() if c >= 2],
            "verb": [[*k, c] for k, c in verb.items()],
        },
        open(out, "w", encoding="utf-8"),
        ensure_ascii=False,
    )
    print("done", len(tri), len(verb), file=sys.stderr)


if __name__ == "__main__":
    main()
