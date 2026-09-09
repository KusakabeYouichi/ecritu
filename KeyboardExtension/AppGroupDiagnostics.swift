import Foundation

// App Group の実体を診断ログへ出すための共通ヘルパ(App/拡張/Tests の 3 ターゲットに登録。2844)。
// ベータテスター調査(2026-09-09)で「拡張だけ containermanagerd に not entitled で拒否」が起き、手作業で
// embedded.mobileprovision を読んでもらった。以後は両側のログが自分で吐く
enum AppGroupDiagnostics {
    // 埋め込みプロファイル(embedded.mobileprovision)の Entitlements → com.apple.security.application-groups。
    // プロファイルが無い(App Store 配布/シミュレーター)なら nil
    static func profileApplicationGroups(in bundle: Bundle = .main) -> [String]? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url),
            let startRange = data.range(of: Data("<?xml".utf8)),
            let endRange = data.range(of: Data("</plist>".utf8), in: startRange.lowerBound..<data.count) else {
            return nil
        }
        let plistData = data.subdata(in: startRange.lowerBound..<endRange.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
            let entitlements = plist["Entitlements"] as? [String: Any] else {
            return nil
        }
        return entitlements["com.apple.security.application-groups"] as? [String] ?? []
    }

    // 「group=… container=<末尾2要素 or なし> profileGroups=[…]」の 1 行
    static func summaryLine(groupID: String) -> String {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        let containerText = container.map { url -> String in
            let parts = url.pathComponents.suffix(2)
            return parts.joined(separator: "/")
        } ?? "なし"
        let profileText = profileApplicationGroups().map { "[\($0.joined(separator: ","))]" } ?? "(プロファイルなし)"
        return "group=\(groupID) container=\(containerText) profileGroups=\(profileText) bundle=\(Bundle.main.bundleIdentifier ?? "?")"
    }
}
