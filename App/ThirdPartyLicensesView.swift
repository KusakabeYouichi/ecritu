import SwiftUI

private struct ThirdPartyLicenseDocument: Identifiable {
    let id: String
    let title: String
    let summary: String
    let resourceName: String
    let resourceExtension: String?
}

private enum ThirdPartyLicenseCatalog {
    static let documents: [ThirdPartyLicenseDocument] = [
        ThirdPartyLicenseDocument(
            id: "open-source-notices",
            title: "Open Source Notices",
            summary: "このアプリで同梱する辞書データの概要と参照先です。",
            resourceName: "APP_STORE_OPEN_SOURCE_NOTICES",
            resourceExtension: "md"
        ),
        ThirdPartyLicenseDocument(
            id: "sudachidict-license",
            title: "SudachiDict Apache License 2.0",
            summary: "SudachiDict 本体のライセンス本文です。",
            resourceName: "LICENSE-2.0",
            resourceExtension: "txt"
        ),
        ThirdPartyLicenseDocument(
            id: "sudachidict-legal",
            title: "SudachiDict LEGAL",
            summary: "SudachiDict に付随する第三者由来データの法的表示です。",
            resourceName: "LEGAL",
            resourceExtension: nil
        )
    ]

    static func loadText(for document: ThirdPartyLicenseDocument) -> String {
        guard
            let url = Bundle.main.url(
                forResource: document.resourceName,
                withExtension: document.resourceExtension
            )
        else {
            return "ライセンス文書が見つかりません: \(document.resourceName)"
        }

        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            return "ライセンス文書の読み込みに失敗しました: \(error.localizedDescription)"
        }
    }
}

struct ThirdPartyLicensesSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("オープンソースライセンス")
                .font(.headline)

            NavigationLink {
                ThirdPartyLicensesListView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .foregroundStyle(.secondary)
                    Text("ライセンス表示を開く")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Text("App Store 配布時に必要となる SudachiDict 関連のライセンス文書を確認できます。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.94))
        )
    }
}

private struct ThirdPartyLicensesListView: View {
    var body: some View {
        List(ThirdPartyLicenseCatalog.documents) { document in
            NavigationLink {
                ThirdPartyLicenseDetailView(document: document)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(document.title)
                        .font(.body.weight(.semibold))
                    Text(document.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .navigationTitle("ライセンス")
    }
}

private struct ThirdPartyLicenseDetailView: View {
    let document: ThirdPartyLicenseDocument

    var body: some View {
        ScrollView {
            Text(ThirdPartyLicenseCatalog.loadText(for: document))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .background(Color(white: 0.98))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .navigationTitle(document.title)
    }
}

#Preview {
    NavigationStack {
        ThirdPartyLicensesListView()
    }
}
