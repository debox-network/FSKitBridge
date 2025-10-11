import SwiftUI

@main
struct FSKitBridge: App {
    private let silent = CommandLine.arguments.contains("-s")

    init() {
        if silent {
            NSApplication.shared.setActivationPolicy(.prohibited)
            DispatchQueue.main.async { NSApp.terminate(nil) }
        } else {
            NSApplication.shared.setActivationPolicy(.regular)
        }
    }

    var body: some Scene {
        WindowGroup {
            if silent {
                EmptyView()
            } else {
                ContentView()
                    .frame(width: 320, height: 160)
                    .onAppear { NSApp.activate(ignoringOtherApps: true) }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text(LocalizedStringKey("setup_title"))
                .font(.headline)

            Spacer()
                .frame(height: 16)

            Text(LocalizedStringKey("setup_message"))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(height: 32, alignment: .top)

            Spacer()

            HStack(alignment: .bottom) {
                Text(LocalizedStringKey("footer_powered"))
                    .font(.footnote)
                    .foregroundColor(.secondary)

                Spacer()

                Button(LocalizedStringKey("button_done")) {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(4)
        }
        .padding(16)
    }
}
