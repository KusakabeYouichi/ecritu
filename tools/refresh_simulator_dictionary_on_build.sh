#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Release(Archive)ではネットワーク取得と対話ダイアログを既定で無効にする(2785)。
# 素材(tmp/)が無ければ copy_into_bundle_if_exists が警告し、提出前の verify_archive_artifacts.sh が
# 同梱 sqlite の行数検査で止める。開発ビルド(Debug)は従来どおり自動取得・確認ダイアログ。
if [[ "${CONFIGURATION:-}" == "Release" ]]; then
  AUTO_FETCH_SUDACHI_ON_BUILD="${ECRITU_AUTO_FETCH_SUDACHI_ON_BUILD:-0}"
  PROMPT_ON_SUDACHI_FALLBACK="${ECRITU_PROMPT_ON_SUDACHI_FALLBACK:-0}"
else
  AUTO_FETCH_SUDACHI_ON_BUILD="${ECRITU_AUTO_FETCH_SUDACHI_ON_BUILD:-1}"
  PROMPT_ON_SUDACHI_FALLBACK="${ECRITU_PROMPT_ON_SUDACHI_FALLBACK:-1}"
fi
AUTO_FETCH_SUDACHI_INCLUDE_FULL="${ECRITU_AUTO_FETCH_SUDACHI_INCLUDE_FULL:-0}"
SUDACHI_FALLBACK_NONINTERACTIVE_DEFAULT="${ECRITU_SUDACHI_FALLBACK_NONINTERACTIVE_DEFAULT:-continue}"

is_simulator_build=false
if [[ "${PLATFORM_NAME:-}" == *simulator* ]]; then
  is_simulator_build=true
fi

cd "$ROOT_DIR"

TMP_PREMIER="$ROOT_DIR/tmp/ÉcrituPremierVocab.json"
TMP_SECOND="$ROOT_DIR/tmp/ÉcrituSecondVocab.json"
TMP_INITIAL_AJOUT="$ROOT_DIR/tmp/InitialAjoutVocabMigration.json"
TMP_INITIAL_MISC="$ROOT_DIR/tmp/InitialMiscVocabMigration.json"
TMP_INITIAL_SUPPR="$ROOT_DIR/tmp/InitialSupprVocabMigration.json"
TMP_INITIAL_SUPPR_HIDDEN="$ROOT_DIR/tmp/InitialSupprHiddenVocabMigration.json"
TMP_SECOND_INFLECTIONS="$ROOT_DIR/tmp/references_second_inflections.json"
TMP_INITIAL_AJOUT_INFLECTIONS="$ROOT_DIR/tmp/references_sacoche_inflections.json"
TMP_INITIAL_MISC_INFLECTIONS="$ROOT_DIR/tmp/references_misc_inflections.json"
TMP_SOURCES="$ROOT_DIR/tmp/kana_kanji_candidate_sources.json"
TMP_INFLECTIONS="$ROOT_DIR/tmp/kana_kanji_inflection_dictionary.json"
TMP_COSTS="$ROOT_DIR/tmp/kana_kanji_word_costs.json"
TMP_WORD_LM="$ROOT_DIR/tmp/word_lm.json"
TMP_EMOJI_READING="$ROOT_DIR/tmp/EmojiReadingVocab.json"
TMP_LATIN_SUPPL="$ROOT_DIR/tmp/LatinSuggestionSupplemental.txt"
TMP_SQLITE="$ROOT_DIR/tmp/kana_kanji_dictionary.sqlite"

REF_RYUKYU_PLIST="$ROOT_DIR/references/ryukyu.plist"
REF_VIN_PLIST="$ROOT_DIR/references/vin.plist"
REF_IT_PLIST="$ROOT_DIR/references/it.plist"
REF_SACOCHE_PLIST="$ROOT_DIR/references/sacoche.plist"
REF_MISC_PLIST="$ROOT_DIR/references/misc.plist"
REF_COMPENSER_PLIST="$ROOT_DIR/references/compenser.plist"
REF_SUPPR_PLIST="$ROOT_DIR/references/suppr.plist"
REF_POUBELLE_PLIST="$ROOT_DIR/references/poubelle.plist"
REF_PERSONNALITES_PLIST="$ROOT_DIR/references/personnalités.plist"
REF_DRAPEAUX_PLIST="$ROOT_DIR/references/drapeaux.plist"
REF_MONNAIES_PLIST="$ROOT_DIR/references/monnaies.plist"
REF_EMOJI_PLIST="$ROOT_DIR/references/emoji.plist"
REF_ADJECTIVE_GARU_ALLOWLIST="$ROOT_DIR/references/adjective_garu_allowlist.json"
REF_WORD_LM_GZ="$ROOT_DIR/references/word_lm.json.gz"

SUDACHI_CSV_FILES=()

discover_sudachi_csv_files() {
  SUDACHI_CSV_FILES=()
  while IFS= read -r csv_file; do
    SUDACHI_CSV_FILES+=("$csv_file")
  done < <(find "$ROOT_DIR/tmp/sudachi_raw" -type f -name '*_lex.csv' 2>/dev/null | sort)
}

is_truthy() {
  case "$1" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

seed_entry_count() {
  ROOT_DIR="$ROOT_DIR" python3 - <<'PY'
from pathlib import Path
import os
import re

seed_path = Path(os.environ["ROOT_DIR"]) / "KeyboardExtension" / "KanaKanjiSeedDictionary.swift"

try:
    text = seed_path.read_text(encoding="utf-8")
except OSError:
    print("108")
    raise SystemExit(0)

entries = len(re.findall(r'"[^"]+"\s*:\s*\[', text))
print(entries if entries > 0 else 108)
PY
}

confirm_seed_fallback_continue() {
  local entry_count="$1"
  local prompt_message="Sudachiデータの取得に失敗したので、フォールバック用の${entry_count}エントリーだけの辞書でビルドを継続しますか?"
  local osascript_result=""

  if ! is_truthy "$PROMPT_ON_SUDACHI_FALLBACK"; then
    return 0
  fi

  if [[ -t 0 && -t 1 ]]; then
    local answer=""
    read -r -p "[dict] ${prompt_message} [y/N] " answer
    case "$answer" in
      y|Y|yes|YES)
        return 0
        ;;
      *)
        return 1
        ;;
    esac
  fi

  if command -v osascript >/dev/null 2>&1 && [[ -z "${CI:-}" ]]; then
    osascript_result="$(osascript \
      -e 'set promptText to item 1 of argv' \
      -e 'set dialogResult to display dialog promptText buttons {"中止", "継続"} default button "中止" with title "écritu Dictionary Build" with icon caution' \
      -e 'button returned of dialogResult' \
      "$prompt_message" 2>/dev/null || true)"

    if [[ "$osascript_result" == "継続" ]]; then
      return 0
    fi

    if [[ "$osascript_result" == "中止" ]]; then
      return 1
    fi

    echo "[dict] Warning: フォールバック確認ダイアログを表示できませんでした。非対話既定値(${SUDACHI_FALLBACK_NONINTERACTIVE_DEFAULT})を使用します。"
  fi

  case "$SUDACHI_FALLBACK_NONINTERACTIVE_DEFAULT" in
    abort|ABORT|stop|STOP)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

discover_sudachi_csv_files

if ((${#SUDACHI_CSV_FILES[@]} == 0)) && is_truthy "$AUTO_FETCH_SUDACHI_ON_BUILD"; then
  echo "[dict] Sudachi CSV が見つからないため自動取得を試行します..."
  if is_truthy "$AUTO_FETCH_SUDACHI_INCLUDE_FULL"; then
    FETCH_SUDACHI_CMD=(bash tools/fetch_sudachi_raw.sh --include-full)
  else
    FETCH_SUDACHI_CMD=(bash tools/fetch_sudachi_raw.sh)
  fi

  if "${FETCH_SUDACHI_CMD[@]}"; then
    discover_sudachi_csv_files
    echo "[dict] Sudachi CSV 自動取得に成功しました。"
  else
    echo "[dict] Warning: Sudachi CSV 自動取得に失敗しました。従来どおり同梱プレースホルダー辞書で継続します。"
  fi
fi

# Build supplemental and initial-migration vocab first so SQLite regeneration
# can include the latest plist-derived entries (e.g. it.plist additions).
python3 tools/build_second_vocab_from_references.py \
  --input-plist "$REF_RYUKYU_PLIST" \
  --input-plist "$REF_VIN_PLIST" \
  --input-plist "$REF_IT_PLIST" \
  --input-plist "$REF_PERSONNALITES_PLIST" \
  --input-plist "$REF_DRAPEAUX_PLIST" \
  --input-plist "$REF_MONNAIES_PLIST" \
  --output "$TMP_SECOND" \
  --output-inflections "$TMP_SECOND_INFLECTIONS"

# sacoche = コンテナアプリの「追加語彙」に初期表示される実語彙(従来の void の可視分)。
python3 tools/build_second_vocab_from_references.py \
  --input-plist "$REF_SACOCHE_PLIST" \
  --output "$TMP_INITIAL_AJOUT" \
  --output-inflections "$TMP_INITIAL_AJOUT_INFLECTIONS"

# misc = 変換対策の単語追加(初期投入されるが「追加語彙」には表示しない)。
# compenser = sacoche から分離した作者手作業の補完語彙(2026-09-05)。misc と同じ立ち位置(curated、UI非表示)で
# 同じ JSON(InitialMiscVocabMigration)に合流する。
python3 tools/build_second_vocab_from_references.py \
  --input-plist "$REF_MISC_PLIST" \
  --input-plist "$REF_COMPENSER_PLIST" \
  --output "$TMP_INITIAL_MISC" \
  --output-inflections "$TMP_INITIAL_MISC_INFLECTIONS"

# 抑制語彙(区切りコメント付き plist を源泉に JSON を生成)。2系統:
#   poubelle → InitialSuppr(アプリ移行で ÉcrituSuppr_Vocab へ=抑制語彙UIに初期表示)
#   suppr    → InitialSupprHidden(キーボードが直接読む=UI非表示。変換抑制は対等)
python3 tools/build_second_vocab_from_references.py \
  --input-plist "$REF_POUBELLE_PLIST" \
  --output "$TMP_INITIAL_SUPPR"

python3 tools/build_second_vocab_from_references.py \
  --input-plist "$REF_SUPPR_PLIST" \
  --output "$TMP_INITIAL_SUPPR_HIDDEN"

# 欧文サジェストの追加語彙側索引(2770)。補助語彙 JSON から実行時と同一のフィルタ・折り畳みで
# key\tcandidate\t0 をキーのバイト順に前計算する(実行時構築の fp +8MB ピークを無くす)。
# references/vin-acronyme.plist(欧文専用: shortcut がキー、phrase が候補)もここで合流する。
# swift スクリプトの起動は約2秒なので、補助語彙が前回から変わっていないときは飛ばす。
latin_suppl_stamp="$ROOT_DIR/tmp/.LatinSuggestionSupplemental.src.sha"
REF_VIN_ACRONYME_PLIST="$ROOT_DIR/references/vin-acronyme.plist"
latin_suppl_src_sha="$(shasum -a 256 "$TMP_SECOND" "$REF_VIN_ACRONYME_PLIST" tools/build_latin_suggestion_supplemental.swift | shasum -a 256 | cut -d' ' -f1)"
if [[ ! -f "$TMP_LATIN_SUPPL" || ! -f "$latin_suppl_stamp" || "$(cat "$latin_suppl_stamp")" != "$latin_suppl_src_sha" ]]; then
  # Xcode のビルド環境は SDKROOT が iOS SDK を指すため、スクリプト実行は macOS SDK を明示する
  if SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" swift tools/build_latin_suggestion_supplemental.swift "$TMP_SECOND" "$TMP_LATIN_SUPPL" "$REF_VIN_ACRONYME_PLIST"; then
    echo "$latin_suppl_src_sha" > "$latin_suppl_stamp"
  else
    echo "[dict] Warning: 欧文サジェスト索引の前計算に失敗しました。同梱済みの前回分で継続します。"
  fi
else
  echo "[dict] 欧文サジェスト索引は最新(補助語彙に変更なし)。"
fi

# 絵文字の読み(emoji.plist=CLDR由来を整備したもの)→ 読み→[絵文字] JSON。
# 絵文字候補(emojiCandidateDisplayEnabled配下)専用で、通常のかな漢字変換(sqlite)には入れない。
if [[ -f "$REF_EMOJI_PLIST" ]]; then
  python3 tools/build_second_vocab_from_references.py \
    --input-plist "$REF_EMOJI_PLIST" \
    --output "$TMP_EMOJI_READING"
fi

needs_sudachi_regeneration() {
  ROOT_DIR="$ROOT_DIR" python3 - <<'PY'
from pathlib import Path
import os

root = Path(os.environ["ROOT_DIR"])

inputs = [
    *sorted(root.glob("tmp/sudachi_raw/**/*_lex.csv")),
  root / "tools" / "refresh_simulator_dictionary_on_build.sh",
  root / "tools" / "build_sudachi_index.py",
  root / "references" / "adjective_garu_allowlist.json",
]

outputs = [
    root / "tmp" / "ÉcrituPremierVocab.json",
    root / "tmp" / "kana_kanji_candidate_sources.json",
    root / "tmp" / "kana_kanji_inflection_dictionary.json",
    root / "tmp" / "kana_kanji_word_costs.json",
]

if not inputs or any(not out.exists() for out in outputs):
    print("1")
    raise SystemExit(0)

newest_input = max(path.stat().st_mtime for path in inputs if path.exists())
oldest_output = min(path.stat().st_mtime for path in outputs)
print("1" if newest_input > oldest_output else "0")
PY
}

needs_sqlite_regeneration() {
  if [[ ! -f "$TMP_SQLITE" ]]; then
    return 0
  fi

  if [[ "$TMP_PREMIER" -nt "$TMP_SQLITE" ]] \
    || [[ "$TMP_SECOND" -nt "$TMP_SQLITE" ]] \
    || [[ "$ROOT_DIR/tools/build_kana_kanji_sqlite.py" -nt "$TMP_SQLITE" ]] \
    || [[ "$ROOT_DIR/tools/refresh_simulator_dictionary_on_build.sh" -nt "$TMP_SQLITE" ]]; then
    return 0
  fi

  if [[ -f "$TMP_SOURCES" && "$TMP_SOURCES" -nt "$TMP_SQLITE" ]]; then
    return 0
  fi

  if [[ -f "$TMP_INFLECTIONS" && "$TMP_INFLECTIONS" -nt "$TMP_SQLITE" ]]; then
    return 0
  fi

  if [[ -f "$TMP_WORD_LM" && "$TMP_WORD_LM" -nt "$TMP_SQLITE" ]]; then
    return 0
  fi

  # 活用クラス(plist の pos)と追加語彙は、語彙 JSON の中身が変わらないまま更新される
  # ことがある(既存語に pos を足しただけの編集)。これらを判定に入れないと
  # inflection_classes が古いまま残り、サ変名詞を足しても「〜する」が出ない
  # (再醗酵する が出なかった原因。2666)
  for inflection_source in \
    "$TMP_SECOND_INFLECTIONS" \
    "$TMP_INITIAL_AJOUT_INFLECTIONS" \
    "$TMP_INITIAL_MISC_INFLECTIONS" \
    "$TMP_INITIAL_AJOUT" \
    "$TMP_INITIAL_MISC"; do
    if [[ -f "$inflection_source" && "$inflection_source" -nt "$TMP_SQLITE" ]]; then
      return 0
    fi
  done

  return 1
}

regenerate_sqlite_if_possible() {
  # 連文節変換用の単語 n-gram LM は references/word_lm.json.gz にコミットしてある。
  # gz が tmp より新しい(または未展開)ときだけ展開し、mtime を安定させて無駄な再生成を防ぐ。
  if [[ -f "$REF_WORD_LM_GZ" ]] && { [[ ! -f "$TMP_WORD_LM" ]] || [[ "$REF_WORD_LM_GZ" -nt "$TMP_WORD_LM" ]]; }; then
    echo "[dict] Decompressing word LM ($(du -h "$REF_WORD_LM_GZ" | cut -f1)) -> tmp/word_lm.json ..."
    gunzip -c "$REF_WORD_LM_GZ" > "$TMP_WORD_LM"
  fi

  if [[ ! -f "$TMP_PREMIER" || ! -f "$TMP_SECOND" ]]; then
    if [[ -f "$TMP_SQLITE" ]]; then
      echo "[dict] Warning: sqlite再生成に必要な語彙JSONが不足しているため、古いSQLiteを削除してJSONフォールバックを優先します。"
      rm -f "$TMP_SQLITE"
    else
      echo "[dict] Skip sqlite regeneration (missing vocab json: $TMP_PREMIER or $TMP_SECOND)."
    fi
    return
  fi

  if ! needs_sqlite_regeneration; then
    # 再生成の途中失敗が空のDBを残すと、mtime 判定では「最新」に見えて空辞書を配ってしまう
    # (2026-08-31: plist 編集とビルドが競合して 86KB の空DBが実機にバンドルされ fallback=1 で変換退化)。
    # 中身を数えて薄すぎれば作り直す
    local existing_rows
    existing_rows=$(sqlite3 "$TMP_SQLITE" "SELECT count(*) FROM dictionary_entries;" 2>/dev/null || echo 0)
    if [[ "${existing_rows:-0}" -ge 100000 ]]; then
      echo "[dict] Skip sqlite regeneration (kana_kanji_dictionary.sqlite is up-to-date, rows=$existing_rows)."
      return
    fi
    echo "[dict] Warning: 既存SQLiteの行数が異常に少ない(rows=$existing_rows)。再生成します。"
  fi

  local sqlite_args=(
    python3 tools/build_kana_kanji_sqlite.py
    --vocab-json "$TMP_SECOND"
    --vocab-json "$TMP_PREMIER"
    --output "$TMP_SQLITE"
  )

  if [[ -f "$TMP_SOURCES" ]]; then
    sqlite_args+=(--sources-json "$TMP_SOURCES")
  fi

  if [[ -f "$TMP_INFLECTIONS" ]]; then
    sqlite_args+=(--inflections-json "$TMP_INFLECTIONS")
  fi

  if [[ -f "$TMP_COSTS" ]]; then
    sqlite_args+=(--costs-json "$TMP_COSTS")
  fi

  if [[ -f "$TMP_WORD_LM" ]]; then
    sqlite_args+=(--word-lm-json "$TMP_WORD_LM")
  fi

  if [[ -f "$TMP_SECOND_INFLECTIONS" ]]; then
    sqlite_args+=(--inflections-json "$TMP_SECOND_INFLECTIONS")
  fi

  if [[ -f "$TMP_INITIAL_AJOUT_INFLECTIONS" ]]; then
    sqlite_args+=(--inflections-json "$TMP_INITIAL_AJOUT_INFLECTIONS")
  fi

  if [[ -f "$TMP_INITIAL_MISC_INFLECTIONS" ]]; then
    sqlite_args+=(--inflections-json "$TMP_INITIAL_MISC_INFLECTIONS")
  fi

  # 追加語彙(sacoche/misc とも)は dictionary_entries には入れないが、活用クラスは保持する。
  if [[ -f "$TMP_INITIAL_AJOUT" ]]; then
    sqlite_args+=(--inflection-extra-vocab-json "$TMP_INITIAL_AJOUT")
  fi

  if [[ -f "$TMP_INITIAL_MISC" ]]; then
    sqlite_args+=(--inflection-extra-vocab-json "$TMP_INITIAL_MISC")
  fi

  if "${sqlite_args[@]}"; then
    local regenerated_rows
  regenerated_rows=$(sqlite3 "$TMP_SQLITE" "SELECT count(*) FROM dictionary_entries;" 2>/dev/null || echo 0)
  if [[ "${regenerated_rows:-0}" -lt 100000 ]]; then
    echo "[dict] error: SQLite regeneration produced too few rows (rows=$regenerated_rows). Failing the build to avoid bundling a broken dictionary." >&2
    rm -f "$TMP_SQLITE"
    exit 1
  fi
  echo "[dict] SQLite regeneration complete (rows=$regenerated_rows)."
  else
    echo "[dict] Warning: sqlite regeneration failed. Keeping previous artifacts if present."
  fi
}

if ((${#SUDACHI_CSV_FILES[@]} > 0)); then
  if [[ "$(needs_sudachi_regeneration)" == "1" ]]; then
    echo "[dict] Regenerating Sudachi-derived dictionary artifacts..."

    sudachi_args=(
      python3 tools/build_sudachi_index.py
      --input-glob "tmp/sudachi_raw/**/*_lex.csv"
      --output "$TMP_PREMIER"
      --output-sources "$TMP_SOURCES"
      --output-inflections "$TMP_INFLECTIONS"
      --output-costs "$TMP_COSTS"
      --max-candidates 24
      --min-reading-len 1
      --max-reading-len 10
      --max-candidate-len 20
      --single-reading-max-candidates 21
      --single-reading-max-candidate-len 1
    )

    if [[ -f "$REF_ADJECTIVE_GARU_ALLOWLIST" ]]; then
      sudachi_args+=(--adjective-garu-allowlist "$REF_ADJECTIVE_GARU_ALLOWLIST")
    fi

    if "${sudachi_args[@]}"; then
      echo "[dict] Sudachi regeneration complete."
    else
      echo "[dict] Warning: Sudachi regeneration failed. Keeping previous artifacts if present."
    fi
  else
    echo "[dict] Skip Sudachi regeneration (tmp artifacts are up-to-date)."
  fi
else
  SEED_ENTRY_COUNT="$(seed_entry_count)"
  if ! confirm_seed_fallback_continue "$SEED_ENTRY_COUNT"; then
    echo "[dict] Sudachi CSV が未取得のためビルドを中止しました。"
    echo "[dict] Hint: run 'bash tools/fetch_sudachi_raw.sh' and retry build."
    exit 1
  fi

  echo "[dict] フォールバック seed 辞書(${SEED_ENTRY_COUNT}エントリー)でビルドを継続します。"
  echo "[dict] Skip regeneration (tmp/sudachi_raw/**/*_lex.csv not found)."
  if is_truthy "$AUTO_FETCH_SUDACHI_ON_BUILD"; then
    echo "[dict] Hint: network or access restriction may block auto-fetch; run 'bash tools/fetch_sudachi_raw.sh' manually."
  else
    echo "[dict] Hint: auto-fetch is disabled (ECRITU_AUTO_FETCH_SUDACHI_ON_BUILD=$AUTO_FETCH_SUDACHI_ON_BUILD)."
    echo "[dict] Hint: run 'bash tools/fetch_sudachi_raw.sh' manually or enable auto-fetch."
  fi
fi

regenerate_sqlite_if_possible

if [[ -n "${TARGET_BUILD_DIR:-}" && -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  BUNDLE_RESOURCES_DIR="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
  mkdir -p "$BUNDLE_RESOURCES_DIR"

  copy_into_bundle_if_exists() {
    local src_path="$1"
    local dst_name="$2"

    if [[ ! -f "$src_path" ]]; then
      echo "[dict] Skip bundle overwrite (missing): $src_path"
      return
    fi

    cp -f "$src_path" "$BUNDLE_RESOURCES_DIR/$dst_name"
    echo "[dict] Overwrote bundle resource: $dst_name"
  }

  # ÉcrituPremierVocab.json / kana_kanji_candidate_sources.json / kana_kanji_inflection_dictionary.json は
  # sqlite に全量焼き込まれるフォールバック専用データ(計約93MB)のため同梱しない(2026-08-31、#4)。
  # App Store 配布はバンドル署名で整合性が保証され、壊れた sqlite が届く経路はない。開発ビルドの
  # 事故は行数ガード(exit 1)で遮断済み。sqlite が開けない場合は劣化運転せず fallback 表示に任せる。
  # ÉcrituSecondVocab.json(補助語彙)だけは通常経路の常用層なので残す。
  copy_into_bundle_if_exists "$TMP_SECOND" "ÉcrituSecondVocab.json"
  copy_into_bundle_if_exists "$TMP_INITIAL_AJOUT" "InitialAjoutVocabMigration.json"
  copy_into_bundle_if_exists "$TMP_INITIAL_MISC" "InitialMiscVocabMigration.json"
  copy_into_bundle_if_exists "$TMP_INITIAL_SUPPR" "InitialSupprVocabMigration.json"
  copy_into_bundle_if_exists "$TMP_INITIAL_SUPPR_HIDDEN" "InitialSupprHiddenVocabMigration.json"
  copy_into_bundle_if_exists "$TMP_SQLITE" "kana_kanji_dictionary.sqlite"
  copy_into_bundle_if_exists "$TMP_EMOJI_READING" "EmojiReadingVocab.json"
  copy_into_bundle_if_exists "$TMP_LATIN_SUPPL" "LatinSuggestionSupplemental.txt"
else
  echo "[dict] Skip bundle overwrite (TARGET_BUILD_DIR/UNLOCALIZED_RESOURCES_FOLDER_PATH not set)."
fi

if [[ "$is_simulator_build" == "true" ]]; then
  if [[ -f "$TMP_PREMIER" && -f "$TMP_SQLITE" ]]; then
    if bash tools/install_simulator_kana_dictionary.sh; then
      echo "[dict] App Group dictionary sync complete."
    else
      echo "[dict] Warning: App Group dictionary sync failed; build continues with bundled resources."
    fi
  else
    echo "[dict] Skip App Group sync (tmp dictionary artifacts are missing)."
  fi
else
  echo "[dict] Skip App Group sync (PLATFORM_NAME=${PLATFORM_NAME:-unknown})."
fi

# 実機ビルド時: 再インストール後のstaleプラグイン参照(直前までécrituをホストしていた
# 常駐アプリが旧拡張プロセスへの接続を持ち残し、初回キーボード要求が launch failed →
# 純正キーボードが1回出る)を防ぐため、ホストアプリを畳む。スキームのpre-actionにも
# 同じ仕掛けがあるが、スキーム変更が読み込まれていない環境でも効くようビルドフェーズ
# からも呼ぶ(実測: pre-action未実行のまま⌘Rされ再発した 2026-08-14 18:19)。
if [[ "${PLATFORM_NAME:-}" == iphoneos* ]]; then
  bash tools/refresh_keyboard_hosts_after_install.sh || true
fi

