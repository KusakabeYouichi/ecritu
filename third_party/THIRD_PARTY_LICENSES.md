# Third-Party Licenses

The canonical, user-facing notice document bundled with the app is
`third_party/APP_STORE_OPEN_SOURCE_NOTICES.md` (shown in the in-app
license screen). This file is the repository-side index of the same
information. Keep the two in sync.

## SudachiDict (kana-kanji dictionary source)

- Project: https://github.com/WorksApplications/SudachiDict
- Sources used: core + small CSVs under `tmp/sudachi_raw` (not committed)
- License: Apache License, Version 2.0 (`third_party/sudachidict/LICENSE-2.0.txt`)
- Additional notices: `third_party/sudachidict/LEGAL` (includes UniDic BSD terms and NEologd Apache terms)
- The bundled databases are modified, derived works (converted, filtered, merged, re-indexed)

## wordfreq (Latin suggestion frequencies: en / de / it)

- Project: https://github.com/rspeer/wordfreq
- Data license: CC BY-SA 4.0 (code: Apache-2.0). Credit the SUBTLEX authors
  (Marc Brysbaert et al.), OpenSubtitles/OPUS, Wikipedia, Google Books Ngrams
  and the other corpora listed in the wordfreq documentation

## Tatoeba (German display-form restoration)

- https://tatoeba.org/ — CC BY 2.0 FR. Used only to restore German
  capitalization and ß spellings in the bundled German list

## Wiktionary (German display-form fallback)

- https://de.wiktionary.org/ — CC BY-SA. Entry titles only

## Lexique 3.83 (French suggestion frequencies)

- http://www.lexique.org/ — CC BY-SA 4.0 (license confirmed in the
  distribution README, 2026-08-31). Authors: B. New, C. Pallier

## Unihan Database (kanji radical index)

- https://www.unicode.org/charts/unihan.html — Unicode License
  (https://www.unicode.org/license.txt)

## Japanese Wikipedia (word n-gram language model)

- https://ja.wikipedia.org/ — CC BY-SA 4.0 / GFDL. Bundled tables are
  aggregated frequency statistics only (no article text); to the extent
  they are considered an adaptation they are provided under CC BY-SA 4.0

## Unicode CLDR (emoji readings)

- https://cldr.unicode.org/ — Unicode License. Japanese emoji annotations,
  reading-normalized (provenance verified against CLDR ja, 2026-08-31)

## Derived word lists (ShareAlike)

The bundled Latin suggestion lists `LatinSuggestionLexicon_{en,fr,de,it}.txt`
are provided under CC BY-SA 4.0 (several sources are ShareAlike-licensed).
Position taken (2026-09-04): the CC BY-SA files are unencrypted plain data
inside the .ipa and may be extracted and redistributed under CC BY-SA 4.0;
the app's sale terms impose no additional restriction on them (CC BY-SA
4.0 §2(a)(5)(B)). Stated in the in-app notices.

SUBTLEX (one of wordfreq's inputs) is distributed for research use by its
authors; wordfreq redistributes the derived frequencies under CC BY-SA 4.0
and we bundle only word forms with wordfreq's ordinal ranks (no SUBTLEX
counts). Determination (2026-09-04): use is covered by wordfreq's license;
the SUBTLEX authors are credited as wordfreq requires.

Profanity/slur filtering: `tools/latin_suggestion_blocklist.txt` removes a
small set of words from the *suggestion* lists only (2026-09-04).

Vocabulary plists under `references/` (vin / vin-acronyme / ryukyu / it /
personnalités / drapeaux / monnaies / sacoche / misc / suppr / poubelle)
are the author's original compilations, not imports from external
dictionaries (confirmed 2026-08-31; drapeaux readings re-confirmed
2026-09-04). `LatinSuggestionSupplemental.txt` is generated from those
files (tools/build_latin_suggestion_supplemental.swift).

`references/bushu.plist` (radical position table used by the kanji picker)
was compiled from general knowledge, not imported from KANJIDIC2/RADKFILE
or any other database (confirmed 2026-09-04): the radical names are the
customary Japanese names in public use, the position classes (偏/旁/冠/
脚/垂/繞/構/独立) follow from the glyph shapes and were checked entry by
entry by the author, and the stroke counts are facts. Only the Kangxi
radical numbers are cross-checked against Unihan kRSKangxi (Unicode
License, bundled).

Flag names shown on long-press are generated at runtime from Foundation's
`Locale(identifier: "fr_FR")` region names (no bundled table; 2026-09-04).

## Mozc (Google Japanese Input) — kaomoji dictionary

- https://github.com/google/mozc — BSD 3-Clause, Copyright 2010-2018 Google Inc.
- About 440 emoticons with readings (categories SMILE/SADNESS/SWEAT/DISPLEASURE/
  OTHER mapped to this app's 17 categories) are taken from Mozc's emoticon
  dictionary; `third_party/mozc/MOZC-LICENSE` is bundled and shown in-app.
- The remaining ~1,320 emoticons: strings are widely circulated character
  sequences; readings and category assignments were authored for this app
  (2026-09-04, tools/build_kaomoji_catalog.py from tmp/kaomoji_merged.json).
  An earlier build had used readings/categories scraped from a third-party
  keyboard's website; those were removed and re-authored.

## Unicode License text

`third_party/unicode/UNICODE-LICENSE.txt` (Unicode License v3) is bundled
and shown in the in-app license screen, as required for the Unihan and
CLDR derived data.

Re-verify upstream LICENSE/notice documents before each release.
