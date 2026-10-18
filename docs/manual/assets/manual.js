// 見出しの右端に、その見出しへ直接ジャンプする URL をコピーするボタンを付ける。
// 章の見出し(h1)はページの URL、節・項(id 付きの h2/h3)は #id 付きの URL。
// id は章番号を含まない英単語(ズレない)。JavaScript が無い環境では何も付かず、ページはそのまま読める。
(function () {
  'use strict';
  var LABEL = 'この見出しの URL をコピー';

  function pageURL() {
    return location.origin + location.pathname;
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    // 古い WebView 向けの予備(選択→コピー)
    return new Promise(function (resolve, reject) {
      var area = document.createElement('textarea');
      area.value = text;
      area.setAttribute('readonly', '');
      area.style.position = 'fixed';
      area.style.top = '-1000px';
      document.body.appendChild(area);
      area.select();
      var ok = false;
      try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
      document.body.removeChild(area);
      ok ? resolve() : reject(new Error('copy failed'));
    });
  }

  function attach(heading, url) {
    var button = document.createElement('button');
    button.type = 'button';
    button.className = 'anchor-copy';
    button.title = LABEL;
    button.setAttribute('aria-label', LABEL);
    button.textContent = '⧉';
    button.addEventListener('click', function (event) {
      event.preventDefault();
      copyText(url).then(function () {
        button.classList.add('copied');
        button.textContent = '✓';
        setTimeout(function () {
          button.classList.remove('copied');
          button.textContent = '⧉';
        }, 1400);
      }, function () {
        // コピーできない環境では URL を選択状態で見せる
        window.prompt('この URL をコピーしてください', url);
      });
    });
    heading.classList.add('has-anchor-copy');
    heading.appendChild(button);
  }

  function init() {
    var base = pageURL();
    var h1 = document.querySelector('main h1');
    if (h1) { attach(h1, base); }
    var headings = document.querySelectorAll('main h2[id], main h3[id]');
    for (var i = 0; i < headings.length; i++) {
      attach(headings[i], base + '#' + headings[i].id);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
