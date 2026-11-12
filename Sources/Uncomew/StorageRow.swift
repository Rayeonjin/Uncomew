import SwiftUI

struct StorageRow: View {
    @EnvironmentObject private var analyzer: StorageAnalyzer
    let item: StorageItem

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 30)
                .foregroundStyle(item.safety == .systemManaged ? .secondary : .primary)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(item.name).font(.headline)
                    Text(item.kind.rawValue).font(.caption).padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Text(item.path).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                Text(item.explanation).font(.callout).foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)
            VStack(alignment: .trailing, spacing: 8) {
                Text(item.formattedSize).font(.headline.monospacedDigit())
                if item.canRevealInFinder {
                    Button("Show in Finder") { analyzer.reveal(item) }
                } else {
                    Text("Managed by macOS").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 7)
    }

    private var icon: String {
        switch item.kind {
        case .user: return "person.crop.circle"
        case .application: return "app.dashed"
        case .developer: return "hammer"
        case .system: return "gearshape.2"
        case .cache: return "clock.arrow.circlepath"
        case .backup: return "externaldrive.badge.timemachine"
        case .other: return "folder"
        }
    }
}
