import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var analyzer: StorageAnalyzer
    @EnvironmentObject private var uninstaller: AppUninstaller
    private let capacityRefresh = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var selection: SidebarItem? = .overview
    @State private var cameFromCandidates = false
    @State private var cameFromMap = false
    enum SidebarItem: String, CaseIterable, Identifiable {
        case overview = "요약", candidates = "정리 후보", storage = "저장 공간", applications = "앱 관리"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overview: return "internaldrive"
            case .candidates: return "checklist"
            case .storage: return "folder"
            case .applications: return "app"
            }
        }
    }
    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }.navigationTitle("Uncomew")
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview:
                    OverviewView(openStorage: { mode in
                                    cameFromCandidates = false
                                    if !analyzer.hasDefaultScope && !analyzer.isScanning { analyzer.analyze() }
                                    analyzer.showCurrentRanking(mode); selection = .storage
                                 },
                                 openCurrentResults: { mode in
                                    cameFromCandidates = false
                                    if mode == .tree { analyzer.mode = mode }
                                    else { analyzer.showCurrentRanking(mode) }
                                    selection = .storage
                                 },
                                 openApplications: { cameFromMap = false; selection = .applications },
                                 openCandidates: {
                                    if !analyzer.hasCandidateScope && !analyzer.isScanning { analyzer.analyzeCandidates() }
                                    selection = .candidates
                                 },
                                 chooseFolder: {
                                    if analyzer.chooseFolder() { cameFromCandidates = false; analyzer.mode = .map; selection = .storage }
                                 })
                case .candidates:
                    CleanupCandidatesView(openStorage: { node in
                                            analyzer.showInTree(node); cameFromCandidates = true; selection = .storage
                                          },
                                          openApplication: { url in
                        guard !uninstaller.busy else { return }
                        cameFromMap = false; uninstaller.scan(url); selection = .applications
                    }, openFiles: {
                        analyzer.showCurrentRanking(.files); cameFromCandidates = true; selection = .storage
                    })
                case .storage: LargeItemsView(returnToCandidates: cameFromCandidates ? { selection = .candidates } : nil,
                                               openApplication: { url in
                    guard !uninstaller.busy else { return }
                    cameFromMap = analyzer.mode == .map
                    uninstaller.scan(url)
                    selection = .applications
                })
                case .applications: UninstallerView(openOverview: { analyzer.refreshCapacity(); selection = .overview })
                }
            }.toolbar {
                if selection == .applications && cameFromMap {
                    ToolbarItem {
                        Button("공간 지도로 돌아가기") { analyzer.mode = .map; selection = .storage; cameFromMap = false }
                    }
                }
                if selection == .storage {
                    ToolbarItem {
                        Button(analyzer.roots.isEmpty ? "공간 사용 확인" : "이 범위 다시 분석") { analyzer.reanalyze() }.disabled(analyzer.isScanning)
                    }
                }
            }
        }.task { analyzer.refreshCapacity() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            analyzer.refreshCapacity()
        }
        .onReceive(capacityRefresh) { _ in
            guard NSApp.isActive else { return }
            analyzer.refreshCapacity()
        }
        .onChange(of: uninstaller.removalRevision) { _ in
            analyzer.markResultsForReview()
            analyzer.refreshCapacity()
        }
        .onChange(of: selection) { selected in
            if selected == .overview { analyzer.refreshCapacity() }
            if selected == .overview || selected == .applications { cameFromCandidates = false }
            if analyzer.state == .idle {
                if selected == .candidates { analyzer.analyzeCandidates() }
                if selected == .storage { analyzer.analyze() }
            }
        }
    }
}
