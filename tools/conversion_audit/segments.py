#!/usr/bin/env python3
"""一括検査の b(期待は候補に有るが先頭でない)を「並び」と「区切り」に分ける(3696、ユーザ指定)。
使い方: python3 -I tools/conversion_audit/segments.py <trace.log> <結果ディレクトリ>
  <trace.log>: b_logic.tsv の行(読み・期待)を testDiagnosticConversionAudit に TEST_RUNNER_MULTI_TRACE=1 で通したログ
               (手順は ReadMe の 3b)。連文節の格子のノード(読み→表記)が読みごとに出ている
  <結果ディレクトリ>: classify.py の出力。b_logic.tsv を b_logic.tsv(並び)と b_segment.tsv(区切り)に書き分ける
判定: 先頭の候補の読みの切れ目(連文節の最良経路。先頭が後処理で変わっていれば、格子のノードで作れる最も少ない切れ目)
  で、期待の表記も格子のノードの並びとして作れれば「並び」(同じ区切りで語の選び方が違う: 来たからの/北からの、粉/Kona)、
  作れなければ「区切り」(文節の切り方ごと違う: 中に走らない/中には知らない、保存しか/保存紙か)。
  期待の表記が格子で作れない行(書きかえ・かな書き等の後処理、4 字未満で連文節を回さない読み)は「並び」に残す
"""
import os
import re
import sys

NODE = re.compile(r'^MULTITRACE node\[\d+\] ([^→]+)→(.*) cum=-?\d+ prev=')
HEAD = re.compile(r'^MULTITRACE reading=(\S+) bestTotal=')
MAX_ALIGNMENTS = 200


def load_lattices(path):
    """読み → ({(読みの断片, 表記)}, 最良経路の [(読みの断片, 表記)])。同じ読みが何度も出たら最初の塊を使う"""
    lattices = {}
    current = None
    for line in open(path, encoding='utf-8', errors='replace'):
        m = HEAD.match(line)
        if m:
            reading = m.group(1)
            current = None if reading in lattices else (set(), [])
            if current is not None:
                lattices[reading] = current
            continue
        if current is None:
            continue
        m = NODE.match(line)
        if m:
            current[0].add((m.group(1), m.group(2)))
            if line.rstrip().endswith('*PATH'):
                current[1].append((m.group(1), m.group(2)))
    return lattices


def path_cuts(reading, surface, path):
    """最良経路が読み全体と先頭の表記をそのまま作るなら、その切れ目"""
    if ''.join(r for r, _ in path) != reading or ''.join(s for _, s in path) != surface:
        return None
    cuts, position = [], 0
    for r, _ in path:
        position += len(r)
        cuts.append(position)
    return tuple(cuts)


def fits(reading, cuts, surface, pairs):
    """読みを cuts で切った断片ごとに格子の表記を選んで surface を作れるか"""
    pieces, start = [], 0
    for cut in cuts:
        pieces.append(reading[start:cut])
        start = cut
    by_reading = {}
    for r, s in pairs:
        by_reading.setdefault(r, set()).add(s)
    positions = {0}
    for piece in pieces:
        positions = {j + len(s) for j in positions for s in by_reading.get(piece, ()) if s and surface.startswith(s, j)}
        if not positions:
            return False
    return len(surface) in positions


def alignments(reading, surface, pairs):
    """reading と surface を同じ数の断片に切り、各組が pairs に有るときの、読みの切れ目(位置の組)の集合"""
    by_reading = {}
    for r, s in pairs:
        by_reading.setdefault(r, set()).add(s)
    max_len = max((len(r) for r in by_reading), default=0)
    memo = {}

    def walk(i, j):
        if (i, j) in memo:
            return memo[(i, j)]
        if i == len(reading):
            result = {()} if j == len(surface) else set()
            memo[(i, j)] = result
            return result
        result = set()
        for length in range(1, min(max_len, len(reading) - i) + 1):
            piece = reading[i:i + length]
            for s in by_reading.get(piece, ()):
                if s and surface.startswith(s, j):
                    for rest in walk(i + length, j + len(s)):
                        result.add((i + length,) + rest)
                        if len(result) >= MAX_ALIGNMENTS:
                            break
        memo[(i, j)] = result
        return result

    return walk(0, 0)


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    trace_path, result_dir = sys.argv[1:3]
    lattices = load_lattices(trace_path)
    src = os.path.join(result_dir, 'b_logic.tsv')
    lines = open(src, encoding='utf-8').read().splitlines()
    header, rows = lines[0], lines[1:]
    cols = header.split('\t')
    i_reading, i_expected, i_top = cols.index('読み'), cols.index('期待'), cols.index('先頭')
    order, segment, unknown = [], [], 0
    for line in rows:
        c = line.split('\t')
        reading, expected, top = c[i_reading], c[i_expected], c[i_top]
        lattice = lattices.get(reading)
        if not lattice or not lattice[0]:
            unknown += 1
            order.append(line)
            continue
        pairs, path = lattice
        top_cut = path_cuts(reading, top, path)
        if top_cut is None:
            top_alignments = alignments(reading, top, pairs)
            top_cut = min(top_alignments, key=len) if top_alignments else None
        if top_cut is None or not alignments(reading, expected, pairs):
            unknown += 1
            order.append(line)
        elif fits(reading, top_cut, expected, pairs):
            order.append(line)
        else:
            segment.append(line)
    with open(src, 'w', encoding='utf-8') as f:
        f.write('\n'.join([header] + order) + '\n')
    with open(os.path.join(result_dir, 'b_segment.tsv'), 'w', encoding='utf-8') as f:
        f.write('\n'.join([header] + segment) + '\n')
    print(f'並び {len(order)}(うち判定できず {unknown})、区切り {len(segment)}')


if __name__ == '__main__':
    main()
