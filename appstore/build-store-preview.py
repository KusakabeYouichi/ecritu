#!/usr/bin/env python3
# appstore/metadata.md から docs/store-preview/index.html を生成する(テスター向けのストア掲載プレビュー)。
# スクリーンショットは appstore/screenshots/*.png を docs/store-preview/ へコピーして参照する。実行: python3 appstore/build-store-preview.py
import re, html, shutil, os, subprocess
root=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
md=open(f'{root}/appstore/metadata.md',encoding='utf-8').read()
def section(t):
    m=re.search(r'## '+re.escape(t)+r'[^\n]*\n\n(.*?)(?=\n## |\Z)', md, re.S); return m.group(1).strip()
out=f'{root}/docs/store-preview'; os.makedirs(out, exist_ok=True)
for f in sorted(os.listdir(f'{root}/appstore/screenshots')):
    if f.endswith('.png'): shutil.copy(f'{root}/appstore/screenshots/{f}', f'{out}/{f}')
subprocess.run(['sips','-Z','240',f'{root}/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png','--out',f'{out}/icon.png'],capture_output=True)
name='écritu'; subtitle=section('サブタイトル'); promo=section('プロモーションテキスト'); desc=section('説明文'); kw=section('キーワード')
paras=[]
for block in desc.split('\n\n'):
    lines=block.split('\n')
    if lines[0].startswith('■ '): paras.append(f'<h3>{html.escape(lines[0][2:])}</h3>'+''.join(f'<p>{html.escape(l)}</p>' for l in lines[1:]))
    else: paras.append(''.join(f'<p>{html.escape(l)}</p>' for l in lines))
shots=[('01-kana.png','かな入力と候補バー'),('02-comma-flick.png','や キーの 2 段フリック(sakura テーマ)'),('03-flags.png','国旗の長押し'),('04-kaomoji-search.png','顔文字の読み検索'),('05-number-unit.png','書式化数値(単位)'),('06-settings.png','設定アプリ')]
gallery=''.join(f'<figure><img src="{f}" alt="{html.escape(c)}" width="1320" height="2868" loading="lazy"><figcaption>{html.escape(c)}</figcaption></figure>' for f,c in shots)
page=f'''<!DOCTYPE html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>écritu ストア掲載プレビュー</title>
<link rel="stylesheet" href="../manual/assets/manual.css">
<style>
  .store-head {{ display:flex; gap:20px; align-items:flex-start; margin:1.5rem 0 1rem; }}
  .store-head img {{ width:120px; height:120px; border-radius:27px; box-shadow:0 2px 8px rgba(0,0,0,.12); flex:none; }}
  .store-head h1 {{ margin:0; font-size:1.9rem; line-height:1.3; }}
  .store-head .sub {{ margin:.2rem 0 0; color:var(--ink-sub); font-size:1.05rem; }}
  .promo {{ background:var(--card); border:1px solid var(--line); border-radius:12px; padding:.9rem 1.1rem; margin:1rem 0 1.5rem; }}
  .gallery {{ display:flex; gap:12px; overflow-x:auto; padding:4px 0 12px; scroll-snap-type:x mandatory; }}
  .gallery figure {{ flex:0 0 auto; width:min(62vw, 300px); margin:0; scroll-snap-align:start; }}
  .gallery img {{ width:100%; height:auto; border-radius:18px; border:1px solid var(--line); display:block; }}
  .gallery figcaption {{ font-size:.85rem; color:var(--ink-sub); margin-top:.3rem; }}
  .desc h3 {{ margin:1.3rem 0 .3rem; font-size:1.05rem; }}
  .meta {{ color:var(--ink-sub); font-size:.9rem; }}
</style>
</head>
<body>
<main>
  <p class="meta">これは App Store に載せる予定の文面と画像の確認用ページです(テスター向け・未公開)。文面は appstore/metadata.md と同期しています。</p>
  <div class="store-head">
    <img src="icon.png" alt="écritu のアイコン">
    <div>
      <h1>{html.escape(name)}</h1>
      <p class="sub">{html.escape(subtitle)}</p>
      <p class="meta">カテゴリ: ユーティリティ · 年齢: 4+ · 対応: iPhone</p>
    </div>
  </div>
  <div class="gallery">{gallery}</div>
  <div class="promo">{html.escape(promo)}</div>
  <div class="desc">{''.join(paras)}</div>
  <h3>キーワード(検索用・ストアには表示されません)</h3>
  <p class="meta">{html.escape(kw)}</p>
  <p class="meta">ご意見は TestFlight のフィードバック、または <a href="mailto:écritu@merope.pleiades.or.jp">écritu@merope.pleiades.or.jp</a> へ。</p>
</main>
</body>
</html>
'''
open(f'{out}/index.html','w',encoding='utf-8').write(page); print('store-preview generated')
