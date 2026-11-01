#!/usr/bin/env python3
"""一括検査の a/b(と c_policy/c_style)を 1 枚の確認表(Artifact)にする。
使い方: python3 -I tools/conversion_audit/html.py <out.html> <items.json> <結果ディレクトリ>...
  結果ディレクトリは references/conversion_audit/<edition>/(a_register.tsv 等が有る所)。複数なら読み+期待が同じ行は 1 つにまとめる。
  items.json は decisions.py export が doc id(v-NNNN)と行を突き合わせるのに使う(並びは html と同じ)。
Artifact は capabilities db+user、collection "audit"。判定は fix(直す)/ok(このままでよい)、備考は自由記入。
"""
import json
import os
import sys

CLASSES = [("a_register", "a 登録が要る"), ("b_logic", "b 並び・区切り"), ("c_policy", "c かなで書く方針"), ("c_style", "c 書き手がかな書き")]
STAGE_LABEL = {"1": "1 直すべし", "2": "2 できたら直す", "3": "3 直さなくていい", "": "段階なし"}


def read_tsv(path):
    with open(path, encoding="utf-8") as f:
        head = f.readline().rstrip("\n").split("\t")
        for line in f:
            cols = line.rstrip("\n").split("\t")
            yield dict(zip(head, cols))


def load_dir(d, rows):
    sample = os.path.basename(d.rstrip("/"))
    for cls, _ in CLASSES:
        p = os.path.join(d, cls + ".tsv")
        if not os.path.exists(p):
            continue
        for r in read_tsv(p):
            reading = r.get("読み", "")
            expected = r.get("期待", "")
            key = reading + "\t" + expected
            if key in rows:
                if sample not in rows[key]["samples"]:
                    rows[key]["samples"].append(sample)
                continue
            rows[key] = {
                "cls": cls, "stage": r.get("段階", ""), "reason": r.get("理由", ""), "reading": reading, "expected": expected,
                "top": r.get("先頭", ""), "diff": r.get("違い(期待→先頭)", ""), "mark": r.get("印", ""),
                "cands": [c for c in r.get("上位6", "").split("|") if c], "samples": [sample],
            }


def main():
    out_html, out_items, dirs = sys.argv[1], sys.argv[2], sys.argv[3:]
    rows = {}
    for d in dirs:
        load_dir(d, rows)
    cls_order = {c: i for i, (c, _) in enumerate(CLASSES)}
    data = sorted(rows.values(), key=lambda r: (cls_order[r["cls"]], r["stage"] or "9", r["diff"], r["reading"]))
    for i, r in enumerate(data):
        r["id"] = "v-%04d" % i
        r["key"] = r["reading"] + "\t" + r["expected"]
    json.dump(data, open(out_items, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    samples = sorted({s for r in data for s in r["samples"]})
    html = TEMPLATE.replace("__DATA__", json.dumps(data, ensure_ascii=False).replace("</", "<\\/"))
    html = html.replace("__CLASSES__", json.dumps(CLASSES, ensure_ascii=False))
    html = html.replace("__STAGES__", json.dumps(STAGE_LABEL, ensure_ascii=False))
    html = html.replace("__SAMPLES__", json.dumps(samples, ensure_ascii=False))
    open(out_html, "w", encoding="utf-8").write(html)
    print(len(data), "rows", len(html), "bytes", file=sys.stderr)


TEMPLATE = """<title>変換の一括検査</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
/* layout: 分類×段階の節。各行は 1 断片(期待と今の先頭、候補の上位)。上に絞り込み、下に結果コピー。連語スキャンの確認表と同じ型 */
:root {
  --bg: #f6f7f9; --surface: #ffffff; --fg: #1d2330; --muted: #5d6677; --line: #dde1e8;
  --accent: #2f5fb3; --bad-bg: #fff1d6; --bad-fg: #8a4b00; --ok: #2e7d4f; --fix: #b3372f; --chip: #eef1f6;
  --font-body: -apple-system, "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans JP", sans-serif;
  --font-mono: ui-monospace, "SF Mono", Menlo, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg: #14171d; --surface: #1c2029; --fg: #e6e9ef; --muted: #9aa3b4; --line: #2e3442;
  --accent: #7aa2ec; --bad-bg: #3a2c12; --bad-fg: #f2c27a; --ok: #6fcf97; --fix: #f08a80; --chip: #262b36; color-scheme: dark } }
:root[data-theme="dark"] {
  --bg: #14171d; --surface: #1c2029; --fg: #e6e9ef; --muted: #9aa3b4; --line: #2e3442;
  --accent: #7aa2ec; --bad-bg: #3a2c12; --bad-fg: #f2c27a; --ok: #6fcf97; --fix: #f08a80; --chip: #262b36; color-scheme: dark }
body { background: var(--bg); color: var(--fg); font-family: var(--font-body); font-size: 14px; line-height: 1.6;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); padding-block: 20px 48px; }
.wrap { max-width: 1040px; margin: 0 auto; display: grid; gap: 16px; }
h1 { font-size: 1.4rem; margin: 0; text-wrap: balance; }
h2 { font-size: 1.05rem; margin: 18px 0 6px; display: flex; gap: 10px; align-items: baseline; }
h2 .n { font-size: .8rem; color: var(--muted); font-weight: 400; }
.lede { color: var(--muted); margin: 0; max-width: 72ch; }
.bar { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: center; background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 10px 14px; }
.bar label { display: inline-flex; gap: 6px; align-items: center; }
.bar select, .bar input[type=search] { font: inherit; padding: 4px 8px; border-radius: 6px; border: 1px solid var(--line); background: var(--bg); color: var(--fg); max-width: 100%; }
.count { font-variant-numeric: tabular-nums; color: var(--muted); }
.card { background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 8px 14px; display: grid; gap: 6px; min-width: 0; margin-bottom: 8px; }
.card[data-mark="fix"] { border-color: var(--fix); }
.card[data-mark="ok"] { opacity: .55; }
.head { display: flex; flex-wrap: wrap; gap: 4px 12px; align-items: baseline; }
.phrase { font-size: 1.05rem; font-weight: 600; }
.phrase .arrow { color: var(--muted); font-weight: 400; margin: 0 6px; }
.phrase .top { background: var(--bad-bg); color: var(--bad-fg); border-radius: 4px; padding: 0 4px; }
.phrase .top.none { background: transparent; color: var(--muted); font-weight: 400; }
.rd { font-family: var(--font-mono); font-size: .8rem; color: var(--muted); }
.tag { font-size: .72rem; letter-spacing: .04em; color: var(--muted); border: 1px solid var(--line); border-radius: 999px; padding: 0 8px; white-space: nowrap; }
.cands { display: flex; flex-wrap: wrap; gap: 4px 6px; font-size: .85rem; }
.cands span { background: var(--chip); border-radius: 4px; padding: 0 6px; }
.cands span.hit { outline: 1px solid var(--ok); color: var(--ok); }
.decide { display: flex; flex-wrap: wrap; gap: 8px 14px; align-items: center; }
.decide input[type=text] { flex: 1 1 220px; min-width: 0; padding: 5px 8px; border: 1px solid var(--line); border-radius: 6px; background: var(--bg); color: var(--fg); font: inherit; }
button { font: inherit; padding: 6px 14px; border-radius: 8px; border: 1px solid var(--accent); background: var(--accent); color: var(--surface); cursor: pointer; }
button:focus-visible, input:focus-visible, select:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.out { width: 100%; min-height: 120px; font-family: var(--font-mono); font-size: .8rem; background: var(--surface); color: var(--fg); border: 1px solid var(--line); border-radius: 8px; padding: 8px; box-sizing: border-box; }
.note { color: var(--muted); font-size: .85rem; }
</style>

<div class="wrap">
  <h1>変換の一括検査</h1>
  <p class="lede">Wikipedia の文を句点・読点・記号で区切った断片の読みを推定して変換し、候補バーの先頭が元の表記(『期待』)に戻らなかったものを並べています。『先頭』は今の écritu の先頭、その下は候補の上位 6 件(期待が候補に有れば緑の枠)。段階は機械的な目安です。</p>
  <div class="bar">
    <label>分類 <select id="cls"><option value="all">すべて</option></select></label>
    <label>段階 <select id="stage"><option value="all">すべて</option><option value="1">1 直すべし</option><option value="2">2 できたら直す</option><option value="3">3 直さなくていい</option></select></label>
    <label>標本 <select id="sample"><option value="all">すべて</option></select></label>
    <label>違い <input type="search" id="q" placeholder="例: 賞→章" size="12"></label>
    <label><input type="checkbox" id="hide-ok"> [このままでよい]を隠す</label>
    <label><input type="checkbox" id="hide-decided"> 入力済みを隠す</label>
    <span class="count" id="count"></span>
    <span class="note" id="status"></span>
  </div>
  <p class="note">[直す]は『期待』の表記を先頭にする指示です。期待そのものが違う(読みの推定が変、別の表記が正しい)ときは右の欄に正しい表記を書いてください(書くと自動で[直す]になります)。[このままでよい]は直さない指示です。入力は自動で保存されます。</p>
  <div id="list"></div>
  <div class="bar" style="flex-direction:column;align-items:stretch">
    <div class="decide"><button type="button" id="copy">結果をコピー</button><span class="note" id="copied"></span></div>
    <textarea class="out" id="out" readonly aria-label="結果"></textarea>
  </div>
</div>
<script type="application/json" id="data">__DATA__</script>
<script type="application/json" id="classes">__CLASSES__</script>
<script type="application/json" id="stages">__STAGES__</script>
<script type="application/json" id="samples">__SAMPLES__</script>
<script>
const rows = JSON.parse(document.getElementById('data').textContent);
const classes = JSON.parse(document.getElementById('classes').textContent);
const stageLabel = JSON.parse(document.getElementById('stages').textContent);
const samples = JSON.parse(document.getElementById('samples').textContent);
const clsLabel = Object.fromEntries(classes);
let state = {};
let decisions = null;
const saveTimers = {};
function setStatus(text) { document.getElementById('status').textContent = text; }
function persist(r) {
  const s = state[r.id] || {};
  if (!decisions) { return; }
  clearTimeout(saveTimers[r.id]);
  saveTimers[r.id] = setTimeout(() => {
    decisions.doc(r.id).set({ key: r.key, mark: s.mark || '', note: s.note || '' })
      .then(() => setStatus('保存しました'))
      .catch(() => setStatus('保存できませんでした。もう一度選び直してください'));
  }, 500);
}
const selCls = document.getElementById('cls');
classes.forEach(([c, label]) => { const o = document.createElement('option'); o.value = c; o.textContent = label + ' ' + rows.filter(r => r.cls === c).length; selCls.appendChild(o); });
const selSample = document.getElementById('sample');
samples.forEach(s => { const o = document.createElement('option'); o.value = s; o.textContent = s; selSample.appendChild(o); });
const list = document.getElementById('list');
const PAGE = 150;
let limit = PAGE;
const FILTER_IDS = ['cls', 'stage', 'sample', 'q', 'hide-ok', 'hide-decided'];
function filterValue(id) { const el = document.getElementById(id); return el.type === 'checkbox' ? el.checked : el.value; }
function saveFilters() { try { localStorage.setItem('audit-filters', JSON.stringify(Object.fromEntries(FILTER_IDS.map(id => [id, filterValue(id)])))); } catch (e) {} }
function restoreFilters() {
  let saved = null;
  try { saved = JSON.parse(localStorage.getItem('audit-filters') || 'null'); } catch (e) {}
  if (!saved) { saved = { stage: '1', sample: samples.includes('3640b') ? '3640b' : 'all' }; }
  FILTER_IDS.forEach(id => { if (!(id in saved)) return; const el = document.getElementById(id); if (el.type === 'checkbox') el.checked = !!saved[id]; else el.value = saved[id]; if (el.tagName === 'SELECT' && el.value !== saved[id]) el.value = 'all'; });
}
function render() {
  const cls = selCls.value, stage = document.getElementById('stage').value, sample = selSample.value;
  const q = document.getElementById('q').value.trim();
  const hideOk = document.getElementById('hide-ok').checked;
  const hideDecided = document.getElementById('hide-decided').checked;
  list.textContent = '';
  let shown = 0, currentGroup = null;
  rows.forEach((r, i) => {
    const s = state[r.id] || {};
    if (cls !== 'all' && r.cls !== cls) return;
    if (stage !== 'all' && r.stage !== stage) return;
    if (sample !== 'all' && !r.samples.includes(sample)) return;
    if (q && !(r.diff.includes(q) || r.expected.includes(q) || r.reading.includes(q) || r.top.includes(q))) return;
    if (hideOk && s.mark === 'ok') return;
    if (hideDecided && s.mark) return;
    shown++;
    if (shown > limit) return;
    const group = r.cls + '/' + r.stage;
    if (group !== currentGroup) {
      currentGroup = group;
      const h = document.createElement('h2');
      h.innerHTML = '<span></span><span class="n"></span>';
      h.firstChild.textContent = clsLabel[r.cls] + ' · ' + (stageLabel[r.stage] || r.stage);
      h.lastChild.textContent = rows.filter(x => x.cls === r.cls && x.stage === r.stage).length + ' 件';
      list.appendChild(h);
    }
    const card = document.createElement('section');
    card.className = 'card';
    if (s.mark) card.dataset.mark = s.mark;
    const head = document.createElement('div'); head.className = 'head';
    const ph = document.createElement('span'); ph.className = 'phrase';
    const ex = document.createElement('span'); ex.textContent = r.expected; ph.appendChild(ex);
    const ar = document.createElement('span'); ar.className = 'arrow'; ar.textContent = '→'; ph.appendChild(ar);
    const tp = document.createElement('span'); tp.className = 'top' + (r.top ? '' : ' none'); tp.textContent = r.top || '(候補なし)'; ph.appendChild(tp);
    head.appendChild(ph);
    const rd = document.createElement('span'); rd.className = 'rd'; rd.textContent = r.reading; head.appendChild(rd);
    [r.diff, r.mark, r.reason].concat(r.samples.length === samples.length && samples.length > 1 ? ['両方の標本'] : (samples.length > 1 ? r.samples : [])).forEach(t => {
      if (!t) return; const tag = document.createElement('span'); tag.className = 'tag'; tag.textContent = t; head.appendChild(tag);
    });
    card.appendChild(head);
    const cd = document.createElement('div'); cd.className = 'cands';
    r.cands.forEach(c => { const sp = document.createElement('span'); sp.textContent = c; if (c === r.expected) sp.className = 'hit'; cd.appendChild(sp); });
    if (!r.cands.length) { const sp = document.createElement('span'); sp.textContent = '候補なし'; cd.appendChild(sp); }
    card.appendChild(cd);
    const d = document.createElement('div'); d.className = 'decide';
    ['fix', 'ok'].forEach(m => {
      const lab = document.createElement('label');
      const inp = document.createElement('input'); inp.type = 'radio'; inp.name = 'm' + i; inp.id = 'm' + i + m; inp.checked = s.mark === m;
      inp.addEventListener('change', () => { state[r.id] = Object.assign({}, state[r.id], { mark: m }); card.dataset.mark = m; persist(r); updateOut(); });
      lab.appendChild(inp); lab.append(m === 'fix' ? ' 直す(期待どおりに)' : ' このままでよい'); d.appendChild(lab);
    });
    const txt = document.createElement('input'); txt.type = 'text'; txt.id = 'o' + i; txt.placeholder = '正しい表記・補足'; txt.value = s.note || '';
    txt.addEventListener('input', () => {
      state[r.id] = Object.assign({}, state[r.id], { note: txt.value });
      if (txt.value.trim() && state[r.id].mark !== 'fix') { state[r.id].mark = 'fix'; card.dataset.mark = 'fix'; const fx = document.getElementById('m' + i + 'fix'); if (fx) fx.checked = true; }
      persist(r); updateOut();
    });
    d.appendChild(txt); card.appendChild(d);
    list.appendChild(card);
  });
  if (shown > limit) {
    const more = document.createElement('button'); more.type = 'button'; more.id = 'more';
    more.textContent = '次の ' + Math.min(PAGE, shown - limit) + ' 件を表示(残り ' + (shown - limit) + ' 件)';
    more.addEventListener('click', () => { limit += PAGE; render(); });
    list.appendChild(more);
  }
  updateCount(shown);
}
let lastShown = 0;
function updateCount(shown) {
  if (shown !== undefined) lastShown = shown;
  const decided = rows.filter(r => (state[r.id] || {}).mark).length;
  document.getElementById('count').textContent = '絞り込み ' + lastShown + ' / 全 ' + rows.length + ' 件・未入力 ' + (rows.length - decided) + ' 件';
}
function updateOut() {
  const lines = [];
  rows.forEach(r => {
    const s = state[r.id];
    if (!s || !s.mark) return;
    lines.push((s.mark === 'fix' || (s.note || '').trim() ? '直す' : 'OK') + '\\t' + r.expected + '\\t' + r.reading + (s.note ? '\\t' + s.note : ''));
  });
  document.getElementById('out').value = lines.join('\\n');
  updateCount();
}
function onFilter() { limit = PAGE; saveFilters(); render(); }
['cls', 'stage', 'sample', 'hide-ok', 'hide-decided'].forEach(id => document.getElementById(id).addEventListener('change', onFilter));
document.getElementById('q').addEventListener('input', onFilter);
restoreFilters();
document.getElementById('copy').addEventListener('click', () => {
  const out = document.getElementById('out'); const msg = document.getElementById('copied');
  navigator.clipboard.writeText(out.value).then(() => { msg.textContent = 'コピーしました'; })
    .catch(() => { out.focus(); out.select(); msg.textContent = '選択しました。コピーしてください'; });
});
render(); updateOut();
setStatus('保存先に接続しています…');
(async () => {
  const db = window.claude ? await window.claude.use('db') : null;
  if (!db) { setStatus('保存できない表示です(サインインしていないなど)。入力はページを閉じると消えます'); return; }
  decisions = db.collection('audit');
  let first = true;
  decisions.onSnapshot(snap => {
    const next = {};
    snap.docs.forEach(doc => { const v = doc.data() || {}; next[doc.id] = { mark: v.mark || '', note: v.note || '' }; });
    const active = document.activeElement;
    state = Object.assign({}, state, next);
    if (first || !(active && active.tagName === 'INPUT' && active.type === 'text')) { render(); }
    updateOut();
    if (first) { setStatus('claude.ai に自動保存されます(どの端末から開いても同じ内容です)'); first = false; }
  }, () => setStatus('保存先との接続が切れました。再読み込みしてください'));
})();
</script>
"""

if __name__ == "__main__":
    main()
