import json, sys, collections

items = json.load(open(sys.argv[1], encoding="utf-8"))
# 動詞読みごとにまとめ、件数順
groups = collections.OrderedDict()
for it in items:
    groups.setdefault(it["vr"], []).append(it)
order = sorted(groups, key=lambda k: -len(groups[k]))
data = []
for gi, vr in enumerate(order):
    for it in sorted(groups[vr], key=lambda x: -x["count"]):
        data.append({
            "vr": vr, "noun": it["noun"], "p": it["p"], "verb": it["verb"], "count": it["count"],
            "share": round(it["share"] * 100), "rivals": it["rivals"], "kana": it["kana"],
            "forms": [{"form": f["form"], "reading": f["reading"], "expected": f["expected"],
                       "status": f["status"], "top": f["top"]} for f in it["forms"]],
        })
verbs = [{"vr": vr, "n": len(groups[vr]), "label": vr + "(" + "/".join(sorted({it["verb"] for it in groups[vr]})[:3]) + ")"} for vr in order]

html = """<title>目的語で決まる動詞</title>
<meta name="claude:viewport-fit-sides" content="cover">
<style>
/* layout: 動詞の読みごとの節。各行は 1 連語(辞書形/た形)。上に件数と絞り込み、下に結果コピー */
:root {
  --bg: #f6f7f9; --surface: #ffffff; --fg: #1d2330; --muted: #5d6677; --line: #dde1e8;
  --accent: #2f5fb3; --bad-bg: #fff1d6; --bad-fg: #8a4b00; --ok: #2e7d4f; --fix: #b3372f;
  --font-body: -apple-system, "Hiragino Sans", "Hiragino Kaku Gothic ProN", "Noto Sans JP", sans-serif;
  --font-mono: ui-monospace, "SF Mono", Menlo, monospace;
}
@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) {
  --bg: #14171d; --surface: #1c2029; --fg: #e6e9ef; --muted: #9aa3b4; --line: #2e3442;
  --accent: #7aa2ec; --bad-bg: #3a2c12; --bad-fg: #f2c27a; --ok: #6fcf97; --fix: #f08a80; color-scheme: dark } }
:root[data-theme="dark"] {
  --bg: #14171d; --surface: #1c2029; --fg: #e6e9ef; --muted: #9aa3b4; --line: #2e3442;
  --accent: #7aa2ec; --bad-bg: #3a2c12; --bad-fg: #f2c27a; --ok: #6fcf97; --fix: #f08a80; color-scheme: dark }
body { background: var(--bg); color: var(--fg); font-family: var(--font-body); font-size: 14px; line-height: 1.6;
  padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); padding-block: 20px 48px; }
.wrap { max-width: 1040px; margin: 0 auto; display: grid; gap: 16px; }
h1 { font-size: 1.4rem; margin: 0; text-wrap: balance; }
h2 { font-size: 1.05rem; margin: 18px 0 6px; display: flex; gap: 10px; align-items: baseline; }
h2 .n { font-size: .8rem; color: var(--muted); font-weight: 400; }
.lede { color: var(--muted); margin: 0; max-width: 72ch; }
.bar { display: flex; flex-wrap: wrap; gap: 8px 16px; align-items: center; background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 10px 14px; }
.bar label { display: inline-flex; gap: 6px; align-items: center; }
.bar select { font: inherit; padding: 4px 8px; border-radius: 6px; border: 1px solid var(--line); background: var(--bg); color: var(--fg); max-width: 100%; }
.count { font-variant-numeric: tabular-nums; color: var(--muted); }
.card { background: var(--surface); border: 1px solid var(--line); border-radius: 10px; padding: 8px 14px; display: grid; gap: 6px; min-width: 0; margin-bottom: 8px; }
.card[data-mark="fix"] { border-color: var(--fix); }
.card[data-mark="ok"] { opacity: .55; }
.head { display: flex; flex-wrap: wrap; gap: 6px 12px; align-items: baseline; }
.phrase { font-size: 1.05rem; font-weight: 600; }
.meta { font-size: .78rem; color: var(--muted); }
.tag { font-size: .72rem; letter-spacing: .04em; color: var(--muted); border: 1px solid var(--line); border-radius: 999px; padding: 0 8px; }
.forms { overflow-x: auto; }
table { border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }
td, th { text-align: left; padding: 2px 8px; border-bottom: 1px solid var(--line); white-space: nowrap; vertical-align: top; }
th { font-weight: 500; color: var(--muted); font-size: .78rem; }
td.rd { font-family: var(--font-mono); font-size: .8rem; color: var(--muted); }
td.bad { background: var(--bad-bg); color: var(--bad-fg); font-weight: 600; }
td.okc { color: var(--ok); }
.decide { display: flex; flex-wrap: wrap; gap: 8px 14px; align-items: center; }
.decide input[type=text] { flex: 1 1 220px; min-width: 0; padding: 5px 8px; border: 1px solid var(--line); border-radius: 6px; background: var(--bg); color: var(--fg); font: inherit; }
button { font: inherit; padding: 6px 14px; border-radius: 8px; border: 1px solid var(--accent); background: var(--accent); color: var(--surface); cursor: pointer; }
button.ghost { background: transparent; color: var(--accent); }
button:focus-visible, input:focus-visible, select:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.out { width: 100%; min-height: 120px; font-family: var(--font-mono); font-size: .8rem; background: var(--surface); color: var(--fg); border: 1px solid var(--line); border-radius: 8px; padding: 8px; box-sizing: border-box; }
.note { color: var(--muted); font-size: .85rem; }
</style>

<div class="wrap">
  <h1>目的語で決まる動詞</h1>
  <p class="lede">Wikipedia の文から「名詞+助詞+動詞」を数え、同じ読みの動詞が複数あるのに、その名詞の後ろでは 7 割以上が 1 つの表記に決まる組を集めました。その表記が écritu の先頭に来ていない組だけを並べています。先頭が合っている形(辞書形か た形)は薄く示します。</p>
  <div class="bar">
    <label>動詞 <select id="verb"><option value="all">すべて</option></select></label>
    <label><input type="checkbox" id="hide-ok"> [このままでよい]を隠す</label>
    <label><input type="checkbox" id="hide-kana"> 先頭がかなの組を隠す</label>
    <label><input type="checkbox" id="hide-decided"> 入力済みを隠す</label>
    <span class="count" id="count"></span>
    <span class="note" id="status"></span>
  </div>
  <p class="note">[直す]はコーパスの表記(『期待』の列)を先頭にする指示です。別の表記にしたいときや、助詞違いまで含めて直したいときは右の欄に書いてください(書くと自動で[直す]になります)。入力は自動で保存されます。</p>
  <div id="list"></div>
  <div class="bar" style="flex-direction:column;align-items:stretch">
    <div class="decide"><button type="button" id="copy">結果をコピー</button><span class="note" id="copied"></span></div>
    <textarea class="out" id="out" readonly aria-label="結果"></textarea>
  </div>
</div>
<script type="application/json" id="data">__DATA__</script>
<script type="application/json" id="verbs">__VERBS__</script>
<script>
const rows = JSON.parse(document.getElementById('data').textContent);
const verbs = JSON.parse(document.getElementById('verbs').textContent);
rows.forEach((r, i) => { r.docId = 'c-' + String(i).padStart(4, '0'); r.key = r.noun + r.p + r.verb; });
let state = {};
let decisions = null;
const saveTimers = {};
function setStatus(text) { document.getElementById('status').textContent = text; }
function persist(r) {
  const s = state[r.docId] || {};
  if (!decisions) { return; }
  clearTimeout(saveTimers[r.docId]);
  saveTimers[r.docId] = setTimeout(() => {
    decisions.doc(r.docId).set({ key: r.key, mark: s.mark || '', note: s.note || '' })
      .then(() => setStatus('保存しました'))
      .catch(() => setStatus('保存できませんでした。もう一度選び直してください'));
  }, 500);
}
const sel = document.getElementById('verb');
verbs.forEach(v => { const o = document.createElement('option'); o.value = v.vr; o.textContent = v.label + ' ' + v.n; sel.appendChild(o); });
const list = document.getElementById('list');
function render() {
  const verb = sel.value;
  const hideOk = document.getElementById('hide-ok').checked;
  const hideKana = document.getElementById('hide-kana').checked;
  const hideDecided = document.getElementById('hide-decided').checked;
  list.textContent = '';
  let shown = 0, currentVr = null, section = null;
  rows.forEach((r, i) => {
    const s = state[r.docId] || {};
    if (verb !== 'all' && r.vr !== verb) return;
    if (hideOk && s.mark === 'ok') return;
    if (hideKana && r.kana) return;
    if (hideDecided && s.mark) return;
    shown++;
    if (r.vr !== currentVr) {
      currentVr = r.vr;
      const h = document.createElement('h2');
      const v = verbs.find(x => x.vr === r.vr);
      h.innerHTML = '<span></span><span class="n"></span>';
      h.firstChild.textContent = v.label; h.lastChild.textContent = v.n + ' 組';
      list.appendChild(h);
    }
    const card = document.createElement('section');
    card.className = 'card';
    if (s.mark) card.dataset.mark = s.mark;
    const head = document.createElement('div'); head.className = 'head';
    head.innerHTML = '<span class="phrase"></span><span class="meta"></span>';
    head.querySelector('.phrase').textContent = r.key;
    head.querySelector('.meta').textContent = 'コーパス ' + r.count + ' 回・' + r.share + '%／ほかの表記: ' + r.rivals;
    if (r.kana) { const t = document.createElement('span'); t.className = 'tag'; t.textContent = '先頭がかな'; head.appendChild(t); }
    card.appendChild(head);
    const box = document.createElement('div'); box.className = 'forms';
    const t = document.createElement('table');
    t.innerHTML = '<tr><th>形</th><th>読み</th><th>期待</th><th>今の先頭</th><th>2</th><th>3</th><th>4</th></tr>';
    r.forms.forEach(f => {
      const tr = document.createElement('tr');
      const cells = [f.form, f.reading, f.expected, f.top[0] || '', f.top[1] || '', f.top[2] || '', f.top[3] || ''];
      cells.forEach((c, j) => {
        const td = document.createElement('td'); td.textContent = c;
        if (j === 1) td.className = 'rd';
        if (j === 3) td.className = f.status === 'ok' ? 'okc' : 'bad';
        tr.appendChild(td);
      });
      t.appendChild(tr);
    });
    box.appendChild(t); card.appendChild(box);
    const d = document.createElement('div'); d.className = 'decide';
    ['fix', 'ok'].forEach(m => {
      const lab = document.createElement('label');
      const inp = document.createElement('input'); inp.type = 'radio'; inp.name = 'm' + i; inp.id = 'm' + i + m; inp.checked = s.mark === m;
      inp.addEventListener('change', () => { state[r.docId] = Object.assign({}, state[r.docId], { mark: m }); card.dataset.mark = m; persist(r); updateOut(); });
      lab.appendChild(inp); lab.append(m === 'fix' ? ' 直す(期待どおりに)' : ' このままでよい'); d.appendChild(lab);
    });
    const txt = document.createElement('input'); txt.type = 'text'; txt.id = 'o' + i; txt.placeholder = '別の表記・補足'; txt.value = s.note || '';
    txt.addEventListener('input', () => {
      state[r.docId] = Object.assign({}, state[r.docId], { note: txt.value });
      if (txt.value.trim() && state[r.docId].mark !== 'fix') { state[r.docId].mark = 'fix'; card.dataset.mark = 'fix'; const fx = document.getElementById('m' + i + 'fix'); if (fx) fx.checked = true; }
      persist(r); updateOut();
    });
    d.appendChild(txt); card.appendChild(d);
    list.appendChild(card);
  });
  updateCount(shown);
}
let lastShown = 0;
function updateCount(shown) {
  if (shown !== undefined) lastShown = shown;
  const decided = rows.filter(r => (state[r.docId] || {}).mark).length;
  document.getElementById('count').textContent = '表示 ' + lastShown + ' / ' + rows.length + ' 組・未入力 ' + (rows.length - decided) + ' 組';
}
function updateOut() {
  const lines = [];
  rows.forEach(r => {
    const s = state[r.docId];
    if (!s || !s.mark) return;
    lines.push((s.mark === 'fix' || (s.note || '').trim() ? '直す' : 'OK') + '\\t' + r.key + (s.note ? '\\t' + s.note : ''));
  });
  document.getElementById('out').value = lines.join('\\n');
  updateCount();
}
sel.addEventListener('change', render);
['hide-ok', 'hide-kana', 'hide-decided'].forEach(id => document.getElementById(id).addEventListener('change', render));
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
  decisions = db.collection('colloc');
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
html = html.replace("__DATA__", json.dumps(data, ensure_ascii=False).replace("</", "<\\/"))
html = html.replace("__VERBS__", json.dumps(verbs, ensure_ascii=False))
open(sys.argv[2], "w", encoding="utf-8").write(html)
print(len(data), len(verbs), len(html))
