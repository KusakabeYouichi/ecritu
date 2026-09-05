import CryptoKit
import Foundation
import Security

// 連絡先キャッシュの暗号化(2026-08-31)。氏名・読みの対応表を共有defaultsへ平文で
// 置かない(端末外送信はもともと無いが、バックアップ等での可読性を断つ)。
// 鍵は両ターゲット共有のKeychain(kSecAttrAccessibleAfterFirstUnlock)に置き、
// 本体は AES-GCM で封緘して App Group defaults に保存する。
// 以前はアプリ側(ContentView+Bootstrap.swift)と拡張側(KanaKanjiTypes.swift)に同じ enum を
// 2 重に持っていた。両ターゲットに同梱する 1 ファイルへ集約(2805 リファクタ)
enum ContactCacheCipher {
    static let keychainService = "com.kusakabe.ecritu.contactCache"
    static let keychainAccount = "aes-256-key"

    static func seal(_ dictionary: [String: [String]], key: SymmetricKey) -> Data? {
        guard let json = try? JSONEncoder().encode(dictionary),
            let sealed = try? AES.GCM.seal(json, using: key).combined else {
            return nil
        }
        return sealed
    }

    static func open(_ data: Data, key: SymmetricKey) -> [String: [String]]? {
        guard let box = try? AES.GCM.SealedBox(combined: data),
            let json = try? AES.GCM.open(box, using: key),
            let dictionary = try? JSONDecoder().decode([String: [String]].self, from: json) else {
            return nil
        }
        return dictionary
    }

    static func keychainKey(createNew: Bool) -> SymmetricKey? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        guard createNew else {
            return nil
        }
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        query.removeValue(forKey: kSecReturnData as String)
        query.removeValue(forKey: kSecMatchLimit as String)
        query[kSecValueData as String] = keyData
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        // iCloud キーチェーンには同期しない(既定 false だが意図を明示。2785)
        query[kSecAttrSynchronizable as String] = false
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess || addStatus == errSecDuplicateItem else {
            return nil
        }
        if addStatus == errSecDuplicateItem {
            return keychainKey(createNew: false)
        }
        return key
    }

    // 連絡先候補をオフにしたとき、対応表と一緒に鍵も消す(鍵だけ残す理由が無い。2785)
    static func deleteKeychainKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
