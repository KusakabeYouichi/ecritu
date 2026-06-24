import Foundation
import Darwin

// [MEMDIAG] メモリ内訳調査用の一時診断ユーティリティ。
// 不要になったらこのファイルを削除し、[MEMDIAG] マーカーの呼び出し行を取り除くこと。
enum KeyboardMemoryDiagnostics {
    // iOS の jetsam 判定に使われる phys_footprint(MB)。RSS とは別物で、こちらが上限超過の実値。
    static func physFootprintMB() -> Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return Double(info.phys_footprint) / (1024 * 1024)
    }

    static func residentMB() -> Double? {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), intPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }

        return Double(info.resident_size) / (1024 * 1024)
    }

    private static func format(_ value: Double?) -> String {
        guard let value else {
            return "?"
        }
        return String(format: "%.1f", value)
    }

    // footprint / RSS と、呼び出し側から渡された内訳(extra)を1行にまとめる。
    static func reportLine(trigger: String, extra: String) -> String {
        "[MEMDIAG] trigger=\(trigger) footprintMB=\(format(physFootprintMB())) rssMB=\(format(residentMB())) \(extra)"
    }
}
