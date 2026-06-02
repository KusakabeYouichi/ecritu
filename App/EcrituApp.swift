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
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)

                    Text("Loading... 起動準備中")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
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
