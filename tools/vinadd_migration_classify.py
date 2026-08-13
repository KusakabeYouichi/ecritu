import re, math, pathlib, collections, json

REF = pathlib.Path("references")

def parse(name):
    """(section, phrase, reading, rawline_index) を返す"""
    lines = (REF/name).read_text().splitlines()
    out=[]; cur=None
    for i,ln in enumerate(lines):
        s=ln.strip()
        m=re.match(r"^<!--\s*(.*?)\s*-->$", s)
        if m: cur=m.group(1); continue
        mm=re.search(r"<key>phrase</key><string>(.*?)</string><key>shortcut</key><string>(.*?)</string>", s)
        if mm: out.append((cur, mm.group(1), mm.group(2), i))
    return lines, out

LATIN_SPLIT = re.compile(r"[^0-9A-Za-zÀ-ÖØ-öø-ÿĀ-ž']+")
def tokens(phrase):
    t=set()
    latin = [w.lower() for w in LATIN_SPLIT.split(phrase) if len(w)>=2]
    t.update(latin)
    # 日本語部分は2-gram
    ja = "".join(ch for ch in phrase if not re.match(r"[0-9A-Za-zÀ-ÖØ-öø-ÿĀ-ž'\s\-・.,()®️&;]", ch))
    for n in (2,3):
        for i in range(len(ja)-n+1): t.add("j:"+ja[i:i+n])
    if ja: t.add("jlast:"+ja[-1]); t.add("jfirst:"+ja[0])
    return t

def build(labeled):
    index=collections.defaultdict(list)   # token -> [row_id]
    toks=[]
    for idx,(sec,ph,rd,_) in enumerate(labeled):
        tk=tokens(ph); toks.append(tk)
        for t in tk: index[t].append(idx)
    N=len(labeled)
    idf={t: math.log(N/len(v)) for t,v in index.items()}
    return index, toks, idf

def classify(phrase, labeled, index, toks, idf, skip=None):
    tk=tokens(phrase)
    scores=collections.defaultdict(float)
    for t in tk:
        if t not in index: continue
        w=idf[t]
        if w < 1.0: continue          # ありふれたトークンは無視
        rows=index[t]
        if len(rows) > 400: continue  # 汎用すぎるトークン
        for r in rows:
            if r==skip: continue
            scores[r]+=w
    if not scores: return None,0.0,None
    best=max(scores.items(), key=lambda kv: kv[1])
    r,sc=best
    # セクション単位に集約(上位20件の投票)
    top=sorted(scores.items(), key=lambda kv:-kv[1])[:20]
    votes=collections.defaultdict(float)
    for rr,ss in top: votes[labeled[rr][0]]+=ss
    sec=max(votes.items(), key=lambda kv: kv[1])
    denom=sum(votes.values())
    conf = sec[1]/denom if denom else 0
    return sec[0], sc, conf
