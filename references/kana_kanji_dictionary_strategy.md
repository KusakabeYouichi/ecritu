# Kana-Kanji Dictionary Strategy (ecritu)

## Current
- Runtime converter loads this file from App Group container if present:
   - `ÉcrituPremierVocab.json`
- Fallback seed dictionary is built into KeyboardExtension.
- User dictionary and learning are stored in shared defaults.

## Build System Dictionary from SudachiDict
1. Prepare Sudachi dictionary source CSV files.
2. Run:
   - `python tools/build_sudachi_index.py --input-glob "<SUDACHI_CSV_GLOB>" --output tmp/ÉcrituPremierVocab.json --max-candidates 8 --min-reading-len 1 --max-reading-len 10 --max-candidate-len 20 --single-reading-max-candidates 8 --single-reading-max-candidate-len 1`
   - 1文字読みは有効化しつつ、候補の長さと件数を絞ってノイズ増加を抑制します。
3. Keep non-kanji candidates enabled (default). This preserves katakana and kana candidates (example: `にほん -> ニホン`).
4. Install to simulator app-group container:
   - `bash tools/install_simulator_kana_dictionary.sh`
5. The runtime loads the file as:
   - `ÉcrituPremierVocab.json`

## About Mozc-family Data
- Mozc OSS code is BSD-3 for Google-authored code.
- `src/data/dictionary_oss` is mixed-license (see upstream README in that directory).
- Before adopting Mozc-family vocabulary, verify and document every included source license.
- In this repository, Mozc-family vocabulary is currently investigation-only (not implemented).
- Do not ship private Apple framework extracted vocabulary.
