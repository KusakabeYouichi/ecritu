import XCTest

// ★時限デバッグ装置(2611)の検証。KeyboardMemoryForensics.swift を剥がすときは
// このファイルも一緒に削除する(grep MEMFORENSICS)。
// libmalloc の introspection / task_vm_info / sqlite3_memory_used は macOS 共通なので
// Mac 上で仕掛けの健全性(クラッシュしない・意味のある数字が出る)を確認できる。
final class MemoryForensicsTests: XCTestCase {
    func testSummaryLineProducesFields() {
        let line = MemoryForensics.summaryLine()
        XCTAssertTrue(line.contains("sqliteMB="), "line=\(line)")
        XCTAssertTrue(line.contains("fp="), "line=\(line)")
        XCTAssertTrue(line.contains("internal="), "line=\(line)")
    }

    func testHeapAnatomyReportsPagesAndBlocks() {
        // アリーナを確実に育ててから解剖する: 8MB 確保→解放で dirty ページを作る
        var junk: [[UInt8]] = []
        for _ in 0..<64 {
            junk.append([UInt8](repeating: 0xA5, count: 128 * 1024))
        }
        junk.removeAll()

        let line = MemoryForensics.heapAnatomySummary(ignoreThrottle: true)
        print("FORENSICS \(MemoryForensics.summaryLine())")
        print("FORENSICS \(line)")
        XCTAssertTrue(line.contains("anatomy regions="), "line=\(line)")
        XCTAssertTrue(line.contains("dirty内訳"), "line=\(line)")
        // ブロック数と生存量が正の値で出ること(列挙が実際に走った証拠)
        let blocks = Self.intValue(after: "blocks=", in: line)
        XCTAssertGreaterThan(blocks ?? -1, 100, "line=\(line)")
        let liveMB = Self.doubleValue(after: "liveMB=", in: line)
        XCTAssertGreaterThan(liveMB ?? -1, 0.1, "line=\(line)")
    }

    func testWatermarkLedgerEmitsOnGrowth() {
        var captured: [String] = []
        MemoryForensics.logSink = { captured.append($0) }
        defer { MemoryForensics.logSink = nil }

        // 1回目はベースラインとして必ず出る(既に他テストで出ていれば成長分で出す)
        MemoryForensics.noteOperation("テスト基準")
        // 4MB を保持したまま高水位を押し上げる
        let ballast = [UInt8](repeating: 0x5A, count: 4 * 1_048_576)
        withExtendedLifetime(ballast) {
            MemoryForensics.noteOperation("テスト成長")
        }
        XCTAssertFalse(captured.isEmpty, "captured=\(captured)")
        XCTAssertTrue(captured.allSatisfy { $0.contains("MEMFORENSICS高水位") }, "captured=\(captured)")
        XCTAssertTrue(captured.last?.contains("op=テスト") ?? false, "captured=\(captured)")
    }

    private static func intValue(after prefix: String, in line: String) -> Int? {
        guard let range = line.range(of: prefix) else { return nil }
        return Int(line[range.upperBound...].prefix(while: { $0.isNumber }))
    }

    private static func doubleValue(after prefix: String, in line: String) -> Double? {
        guard let range = line.range(of: prefix) else { return nil }
        return Double(line[range.upperBound...].prefix(while: { $0.isNumber || $0 == "." }))
    }
}
