#!/usr/bin/env python3
"""連文節変換(案A2)用: Sudachi の連接行列 matrix.def を品詞シグネチャ単位へ畳み込む。

- 入力: Sudachi lex CSV(context id -> 品詞シグネチャの導出)と matrix.def(左文脈×右文脈のコスト)
- 出力:
  - connection_matrix.bin : int16, numClasses × numClasses 行優先。M[a][b] = クラス a(左文脈)×クラス b(右文脈)の平均連接コスト
  - connection_classes.json: {"numClasses": C, "idToClass": [C個... id 0..maxId], "signatures": [...]}

連接コスト(前語 prev と次語 next の間) = M[ idToClass[prev.right_id] ][ idToClass[next.left_id] ]。
BOS/EOS は context id 0(専用クラス)。CSV に現れない id は UNKNOWN クラス。
"""
import csv
import glob
import json
import struct
import sys
from collections import Counter, defaultdict

import numpy as np


def build_id_to_signature(csv_glob):
    # context id -> 品詞シグネチャ(品詞1-4 + 活用型 + 活用形)の最頻値
    left_sig_counts = defaultdict(Counter)
    right_sig_counts = defaultdict(Counter)
    max_id = 0
    for fp in sorted(glob.glob(csv_glob, recursive=True)):
        for row in csv.reader(open(fp, encoding="utf-8")):
            if len(row) < 11:
                continue
            try:
                li = int(row[1])
                ri = int(row[2])
            except ValueError:
                continue
            sig = "/".join(row[5:11])
            if li >= 0:
                left_sig_counts[li][sig] += 1
                max_id = max(max_id, li)
            if ri >= 0:
                right_sig_counts[ri][sig] += 1
                max_id = max(max_id, ri)
    # 左右どちらの観測も使って id -> 代表シグネチャ
    id_sig = {}
    all_ids = set(left_sig_counts) | set(right_sig_counts)
    for i in all_ids:
        c = Counter()
        c.update(left_sig_counts.get(i, {}))
        c.update(right_sig_counts.get(i, {}))
        id_sig[i] = c.most_common(1)[0][0]
    return id_sig, max_id


def main():
    csv_glob = "tmp/sudachi_raw/**/*_lex.csv"
    matrix_path = "tmp/sudachi_raw/matrix.def"
    out_bin = "tmp/connection_matrix.bin"
    out_json = "tmp/connection_classes.json"

    id_sig, max_id = build_id_to_signature(csv_glob)

    # クラス割当: 実シグネチャ(ソート) + 特殊(BOS/EOS, UNKNOWN)
    signatures = sorted(set(id_sig.values()))
    BOS_EOS = "__BOS_EOS__"
    UNKNOWN = "__UNKNOWN__"
    class_list = signatures + [BOS_EOS, UNKNOWN]
    sig_to_index = {s: i for i, s in enumerate(class_list)}
    bos_index = sig_to_index[BOS_EOS]
    unk_index = sig_to_index[UNKNOWN]
    num_classes = len(class_list)

    # matrix.def ヘッダから context 数
    with open(matrix_path, encoding="utf-8") as f:
        header = f.readline().split()
    lsize, rsize = int(header[0]), int(header[1])
    num_ids = max(lsize, rsize)

    id_to_class = np.full(num_ids, unk_index, dtype=np.int32)
    id_to_class[0] = bos_index  # context id 0 = BOS/EOS
    for i, sig in id_sig.items():
        if 0 <= i < num_ids:
            id_to_class[i] = sig_to_index[sig]

    print(f"[conn] classes={num_classes} (sig={len(signatures)}) ids={num_ids} max_id={max_id}", file=sys.stderr)

    # matrix.def 読み込み(行優先: l r cost)。全トークンを一括パースしコスト列を抽出。
    print("[conn] loading matrix.def ...", file=sys.stderr)
    with open(matrix_path, encoding="utf-8") as f:
        f.readline()  # skip header
        flat = np.fromstring(f.read(), dtype=np.int32, sep=" ")
    triples = flat.reshape(-1, 3)
    assert triples.shape[0] == lsize * rsize, (triples.shape, lsize, rsize)
    # M[l][r] を行優先で復元(l=左文脈, r=右文脈)
    M = triples[:, 2].astype(np.int64).reshape(lsize, rsize)

    # 行(左文脈 l)をクラスへ集約 -> (num_classes, rsize)
    print("[conn] aggregating rows ...", file=sys.stderr)
    row_sum = np.zeros((num_classes, rsize), dtype=np.int64)
    np.add.at(row_sum, id_to_class[:lsize], M)
    row_cnt = np.zeros((num_classes, rsize), dtype=np.int64)
    np.add.at(row_cnt, id_to_class[:lsize], np.ones_like(M))

    # 列(右文脈 r)をクラスへ集約 -> (num_classes, num_classes)
    print("[conn] aggregating cols ...", file=sys.stderr)
    sum_mat = np.zeros((num_classes, num_classes), dtype=np.int64)
    np.add.at(sum_mat.T, id_to_class[:rsize], row_sum.T)
    cnt_mat = np.zeros((num_classes, num_classes), dtype=np.int64)
    np.add.at(cnt_mat.T, id_to_class[:rsize], row_cnt.T)

    # 平均。観測の無いクラス対は既定の高コスト(接続しにくい)。
    DEFAULT_COST = 3000
    with np.errstate(invalid="ignore", divide="ignore"):
        avg = np.where(cnt_mat > 0, np.rint(sum_mat / np.maximum(cnt_mat, 1)), DEFAULT_COST)
    avg = np.clip(avg, -32768, 32767).astype(np.int16)

    # 出力
    with open(out_bin, "wb") as f:
        f.write(struct.pack("<i", num_classes))
        f.write(avg.tobytes(order="C"))
    json.dump(
        {"numClasses": num_classes, "idToClass": id_to_class.tolist(), "signatures": class_list},
        open(out_json, "w", encoding="utf-8"),
        ensure_ascii=False,
    )
    print(f"[conn] wrote {out_bin} ({avg.nbytes} bytes) and {out_json}", file=sys.stderr)

    # サニティ: BOS->名詞普通名詞, 名詞->助詞格助詞を, 動詞連用->助詞 などのコスト目安
    def cls(sig_substr):
        for i, s in enumerate(class_list):
            if sig_substr in s:
                return i
        return None
    print("[conn] sample avg costs:", file=sys.stderr)
    for label, a, b in [
        ("BOS->名詞普通名詞", bos_index, cls("名詞/普通名詞/一般")),
        ("名詞普通名詞->助詞格助詞", cls("名詞/普通名詞/一般"), cls("助詞/格助詞")),
        ("名詞普通名詞->EOS", cls("名詞/普通名詞/一般"), bos_index),
    ]:
        if a is not None and b is not None:
            print(f"    {label}: {int(avg[a][b])}", file=sys.stderr)


if __name__ == "__main__":
    main()
