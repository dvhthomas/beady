import SwiftUI

struct WelcomeView: View {
    let session: AppSession

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "circle.hexagongrid.circle")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Beady")
                    .font(.largeTitle.weight(.semibold))
                Text("A read-only window onto a beads (bd) database.")
                    .foregroundStyle(.secondary)
            }
            Button("Open Beads Workspace…") { session.chooseWorkspace() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            if let error = session.openError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            if !session.recentPaths.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent")
                        .font(.headline)
                    ForEach(session.recentPaths, id: \.self) { path in
                        Button {
                            session.open(URL(fileURLWithPath: path))
                        } label: {
                            Label(path, systemImage: "folder")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .buttonStyle(.link)
                    }
                }
                .frame(maxWidth: 480, alignment: .leading)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
