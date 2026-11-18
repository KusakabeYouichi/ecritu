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

                    LoadingCapsule(message: "起動準備中")
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
