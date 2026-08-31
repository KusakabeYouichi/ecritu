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

Vocabulary plists under `references/` (vin / ryukyu / it / personnalités /
drapeaux / monnaies etc.) are the author's original compilations, not
imports from external dictionaries (confirmed 2026-08-31).

Re-verify upstream LICENSE/notice documents before each release.
