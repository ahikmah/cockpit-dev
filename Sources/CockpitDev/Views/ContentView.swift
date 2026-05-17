import SwiftUI

/// Root content view that will be replaced with the full navigation structure.
struct ContentView: View {
    var body: some View {
        NavigationSplitView {
            Text("Workspaces")
                .font(.headline)
                .padding()
        } detail: {
            Text("Select a workspace to get started")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ContentView()
}
