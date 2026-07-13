import SwiftUI
import TLGLauncherCore

struct BackupsView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingRestore: BackupRecord?
    @State private var pendingDelete: BackupRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Backups").font(.title2.bold())
                Spacer()
                StatusBadge(running: model.gameRunning)
                Button("Back Up Now") {
                    Task { await model.createBackup() }
                }
                .disabled(model.isBusy)
            }
            .padding()

            Text("Complete copies of the TLG user directory (saves, configuration, fonts, mods). One is taken automatically before every update.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if model.backupList.isEmpty {
                ContentUnavailableView(
                    "No backups yet",
                    systemImage: "externaldrive.badge.timemachine",
                    description: Text("Use “Back Up Now”, or install an update — a backup is taken automatically first.")
                )
            } else {
                List(model.backupList) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(record.reason)
                            HStack(spacing: 12) {
                                Text(record.createdAt, format: .dateTime.day().month().year().hour().minute())
                                if let size = record.sizeBytes {
                                    Text(ByteCountFormatter.file.string(fromByteCount: size))
                                }
                                if let tag = record.gameVersionTag {
                                    Text("game \(tag.replacingOccurrences(of: "cataclysm-tlg-", with: ""))")
                                        .monospaced()
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                [model.backups.payloadDir(for: record)]
                            )
                        }
                        .buttonStyle(.link)
                        Button("Restore…") { pendingRestore = record }
                            .disabled(model.isBusy || model.gameRunning)
                        Button(role: .destructive) {
                            pendingDelete = record
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(model.isBusy)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .confirmationDialog(
            "Restore backup from \(pendingRestore.map { $0.createdAt.formatted(.dateTime.day().month().hour().minute()) } ?? "")?",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            )
        ) {
            Button("Restore", role: .destructive) {
                if let record = pendingRestore {
                    Task { await model.restore(record) }
                }
                pendingRestore = nil
            }
        } message: {
            Text("The current TLG user directory is replaced by this backup. A safety copy of the current data is taken first, so this can be undone. Restoring data is separate from rolling back the application — match the backup to the game version it was made with.")
        }
        .confirmationDialog(
            "Delete this backup permanently?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let record = pendingDelete {
                    model.deleteBackup(record)
                }
                pendingDelete = nil
            }
        }
    }
}
