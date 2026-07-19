import SwiftUI
import UIKit
import CoreFoundation
import Darwin
import Contacts

extension ContentView {
    func clearLegacyKeyboardDebugLogKeysIfNeeded() {
        guard let defaults = Self.sharedDefaults,
            !defaults.bool(forKey: SettingsKeys.legacyKeyboardDebugLogCleanupCompleted) else {
            return
        }

        let legacyKeys = [
            "keyboardLayoutDebugLines",
            "keyboardLayoutDebugHeartbeat",
            "keyboardLayoutDebugReporterBundleID",
            "keyboardLayoutDebugReporterAppGroupID",
            "keyboardLayoutDebugLastEvent",
            "keyboardInputProbeCount",
            "keyboardInputProbeHeartbeat",
            "keyboardInputProbeLastEvent",
            "keyboardInputProbeLastText"
        ]

        for key in legacyKeys {
            defaults.removeObject(forKey: key)
        }

        defaults.set(true, forKey: SettingsKeys.legacyKeyboardDebugLogCleanupCompleted)
    }

    func keyboardExtensionBundleForDiagnostics() -> Bundle? {
        guard let pluginsURL = Bundle.main.builtInPlugInsURL,
            let pluginURLs = try? FileManager.default.contentsOfDirectory(
                at: pluginsURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
            return nil
        }

        for pluginURL in pluginURLs where pluginURL.pathExtension == "appex" {
            guard let bundle = Bundle(url: pluginURL),
                let bundleID = bundle.bundleIdentifier else {
                continue
            }

            if bundleID.hasSuffix(".keyboard") {
                return bundle
            }
        }

        guard let firstPluginURL = pluginURLs.first(where: { $0.pathExtension == "appex" }) else {
            return nil
        }

        return Bundle(url: firstPluginURL)
    }

    func keyboardDiagnosticsInstallMarkerForCurrentBuild() -> String {
        let bundle = keyboardExtensionBundleForDiagnostics() ?? Bundle.main
        let bundleID = bundle.bundleIdentifier ?? "unknown.keyboard.bundle"
        let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "?"
        return "\(bundleID)|\(buildNumber)|build"
    }

    func clearKeyboardDiagnosticsIfInstallChanged() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let currentMarker = keyboardDiagnosticsInstallMarkerForCurrentBuild()
        let savedMarker = defaults.string(forKey: SettingsKeys.keyboardDiagnosticsInstallMarker)

        if savedMarker != currentMarker {
            // criticalLogLines は消さない(installをまたいで重大イベントの証拠を残す)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLogLines)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsFlightRecorderEvents)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsSessionActive)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsSessionOwnerToken)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastHeartbeat)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastEvent)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastSessionID)
            defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsFailSafeProfile)
            defaults.set(currentMarker, forKey: SettingsKeys.keyboardDiagnosticsInstallMarker)
        }

        keyboardDiagnosticsInstallMarker = currentMarker
    }

    func loadKeyboardDiagnosticsState() {
        guard let defaults = Self.sharedDefaults else {
            keyboardDiagnosticsLogLines = []
            keyboardDiagnosticsCriticalLogLines = []
            keyboardDiagnosticsInstallMarker = ""
            keyboardDiagnosticsSessionActive = false
            keyboardDiagnosticsLastHeartbeatDate = nil
            keyboardDiagnosticsLastEvent = ""
            keyboardDiagnosticsLastSessionID = ""
            keyboardDiagnosticsFailSafeProfile = "normal"
            return
        }

        keyboardDiagnosticsLogLines = decodeStringArray(
            forKey: SettingsKeys.keyboardDiagnosticsLogLines,
            defaults: defaults
        )
        keyboardDiagnosticsCriticalLogLines = decodeStringArray(
            forKey: SettingsKeys.keyboardDiagnosticsCriticalLogLines,
            defaults: defaults
        )
        keyboardDiagnosticsInstallMarker = defaults.string(
            forKey: SettingsKeys.keyboardDiagnosticsInstallMarker
        ) ?? ""
        keyboardDiagnosticsSessionActive = defaults.bool(
            forKey: SettingsKeys.keyboardDiagnosticsSessionActive
        )

        let heartbeatRawValue = defaults.double(forKey: SettingsKeys.keyboardDiagnosticsLastHeartbeat)
        keyboardDiagnosticsLastHeartbeatDate = heartbeatRawValue > 0
            ? Date(timeIntervalSince1970: heartbeatRawValue)
            : nil

        keyboardDiagnosticsLastEvent = defaults.string(
            forKey: SettingsKeys.keyboardDiagnosticsLastEvent
        ) ?? ""
        keyboardDiagnosticsLastSessionID = defaults.string(
            forKey: SettingsKeys.keyboardDiagnosticsLastSessionID
        ) ?? ""

        let failSafeRawValue = defaults.string(
            forKey: SettingsKeys.keyboardDiagnosticsFailSafeProfile
        ) ?? "normal"
        keyboardDiagnosticsFailSafeProfile = normalizedKeyboardDiagnosticsFailSafeProfile(
            failSafeRawValue
        )
    }

    func clearKeyboardDiagnosticsState() {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLogLines)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsCriticalLogLines)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsFlightRecorderEvents)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsSessionActive)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsSessionOwnerToken)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastHeartbeat)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastEvent)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsLastSessionID)
        defaults.removeObject(forKey: SettingsKeys.keyboardDiagnosticsFailSafeProfile)

        if let flightFileURL = keyboardDiagnosticsFlightFileURL() {
            try? FileManager.default.removeItem(at: flightFileURL)
        }

        loadKeyboardDiagnosticsState()
    }

    func normalizedKeyboardDiagnosticsFailSafeProfile(_ rawValue: String) -> String {
        switch rawValue {
        case "normal", "elevated", "critical":
            return rawValue
        default:
            return "normal"
        }
    }

    func keyboardDiagnosticsLastHeartbeatText() -> String {
        guard let keyboardDiagnosticsLastHeartbeatDate else {
            return "記録なし"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: keyboardDiagnosticsLastHeartbeatDate)
    }

    // キーボード拡張が書く「落ちても残る」フライトレコーダファイル。
    // ファイル名は KeyboardViewController+Diagnostics.swift 側の定義と一致させること。
    static let keyboardDiagnosticsFlightFileName = "keyboard_diagnostics_flight.log"

    func keyboardDiagnosticsFlightFileURL() -> URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SettingsKeys.appGroupID
        )?.appendingPathComponent(Self.keyboardDiagnosticsFlightFileName)
    }

    func keyboardDiagnosticsFlightFileTailLines(maxLines: Int = 200) -> [String] {
        guard let url = keyboardDiagnosticsFlightFileURL(),
            let data = try? Data(contentsOf: url),
            !data.isEmpty,
            let text = String(data: data, encoding: .utf8) else {
            return []
        }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.suffix(maxLines).map(String.init)
    }

    func keyboardDiagnosticsExportText() -> String {
        var sections: [String] = []
        sections.append("installMarker: \(keyboardDiagnosticsInstallMarker)")
        sections.append("sessionActive: \(keyboardDiagnosticsSessionActive ? "true" : "false")")
        sections.append("failSafeProfile: \(keyboardDiagnosticsFailSafeProfile)")
        sections.append("lastHeartbeat: \(keyboardDiagnosticsLastHeartbeatText())")
        sections.append("lastSessionID: \(keyboardDiagnosticsLastSessionID)")
        sections.append("lastEvent: \(keyboardDiagnosticsLastEvent)")
        sections.append("--- critical events (ローテ保護) ---")
        if keyboardDiagnosticsCriticalLogLines.isEmpty {
            sections.append("(記録なし)")
        } else {
            sections.append(contentsOf: keyboardDiagnosticsCriticalLogLines)
        }
        sections.append("--- logs ---")
        sections.append(contentsOf: keyboardDiagnosticsLogLines)
        sections.append("--- flight file (crash-safe) ---")
        let flightLines = keyboardDiagnosticsFlightFileTailLines()
        if flightLines.isEmpty {
            sections.append("(記録なし)")
        } else {
            sections.append(contentsOf: flightLines)
        }
        return sections.joined(separator: "\n")
    }

    func copyKeyboardDiagnosticsToPasteboard() {
#if os(iOS)
        UIPasteboard.general.string = keyboardDiagnosticsExportText()
#endif
    }

    func containerDiagnosticsProcessLabel() -> String {
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown.container.bundle"
        let processName = ProcessInfo.processInfo.processName
        return "\(bundleID)(\(processName))"
    }

    func containerCurrentResidentMemoryBytes() -> UInt64? {
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

        return UInt64(info.resident_size)
    }

    func containerResidentMemoryMBText() -> String {
        guard let bytes = containerCurrentResidentMemoryBytes() else {
            return "unknown"
        }

        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f", mb)
    }

    func appendContainerDiagnosticsLog(
        _ event: String,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        guard let defaults = Self.sharedDefaults else {
            return
        }

        let sourceFile = (file as NSString).lastPathComponent
        let timestamp = Self.diagnosticsTimestampFormatter.string(from: Date())
        let context =
            "process=\(containerDiagnosticsProcessLabel()) rssMB=\(containerResidentMemoryMBText())"
        let entry =
            "\(timestamp) [container:\(containerDiagnosticsSessionID)] \(event) {\(context)} (\(sourceFile):\(line) \(function))"

        var lines = decodeStringArray(
            forKey: SettingsKeys.keyboardDiagnosticsLogLines,
            defaults: defaults
        )
        lines.append(entry)

        let maxLineCount = 320
        if lines.count > maxLineCount {
            lines.removeFirst(lines.count - maxLineCount)
        }

        saveStringArray(lines, forKey: SettingsKeys.keyboardDiagnosticsLogLines, defaults: defaults)
    }

    func containerDiagnosticsElapsedMilliseconds(since start: CFAbsoluteTime) -> Int {
        max(0, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
    }
}
