import SwiftUI

@main
struct EcrituApp: App {
    var body: some Scene {
        WindowGroup {
            RootLoadingView()
        }
    }
}

private struct RootLoadingView: View {
    @State private var shouldShowContentView = false

    var body: some View {
        Group {
            if shouldShowContentView {
                ContentView()
            } else {
                // ContentView 初期化中のトースト(loadingToastLabel)と見た目を揃え、
                // 起動→初期化の切り替わりで位置・形が動かないようにする。
                ZStack {
                    AppTheme.screenBackground
                        .ignoresSafeArea()

                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Loading... 起動準備中")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    guard !shouldShowContentView else {
                        return
                    }

                    // Delay ContentView creation by one frame so loading appears immediately.
                    await Task.yield()
                    shouldShowContentView = true
                }
            }
        }
    }
}
