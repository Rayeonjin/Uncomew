import AppKit
import SwiftUI

struct LargeItemsView: View {
    @EnvironmentObject private var analyzer: StorageAnalyzer
    let returnToCandidates: (() -> Void)?
    let openApplication: (URL) -> Void

    private var rows: [(node: StorageNode, depth: Int)] {
        let all = analyzer.nodes
        if analyzer.usesFlatBrowseList {
            let filtered = StorageRanking.top(all.values, limit: analyzer.browseDisplayLimit, byName: analyzer.browseSortByName) { node in
                analyzer.browseFilter.matches(node) &&
                (analyzer.browseIncludePackages || !node.insidePackage) &&
                (analyzer.browseSearch.isEmpty || node.name.localizedCaseInsensitiveContains(analyzer.browseSearch)) &&
                (analyzer.mode == .tree || (analyzer.mode == .folders ? node.isFolder : node.type == .file))
            }
            return filtered.map { ($0, 0) }
        }
        return StorageRanking.tree(nodes: all, roots: analyzer.roots, expanded: analyzer.expanded,
                                   selected: analyzer.selectedPath, limit: analyzer.browseDisplayLimit,
                                   byName: analyzer.browseSortByName, includePackages: analyzer.browseIncludePackages)
    }

    var body: some View {
        let displayedRows = rows
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("저장 공간").font(.largeTitle.bold())
                Spacer()
                if let returnToCandidates { Button("정리 후보로 돌아가기", action: returnToCandidates) }
                Button("폴더 선택…") { analyzer.chooseFolder() }.disabled(analyzer.isScanning)
            }
            Picker("보기", selection: $analyzer.mode) {
                ForEach(StorageAnalyzer.BrowseMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                Toggle("이름순", isOn: $analyzer.browseSortByName)
                Toggle("앱·보관함 내부 포함", isOn: $analyzer.browseIncludePackages)
            }.toggleStyle(.checkbox)
            HStack {
                if analyzer.mode != .folders {
                    Picker("종류", selection: $analyzer.browseFileKind) {
                        ForEach(BrowseFileKind.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(maxWidth: 240)
                }
                Picker("크기", selection: $analyzer.browseMinimumSize) {
                    ForEach(BrowseMinimumSize.allCases) { Text($0.title).tag($0) }
                }.frame(maxWidth: 230)
                if analyzer.hasBrowseFilters { Button("조건 초기화") { analyzer.clearBrowseFilters() } }
                Spacer()
            }
            if let folder = analyzer.browseFolder {
                HStack {
                    Text("폴더 안에서 찾기: " + folder).font(.caption).lineLimit(2).textSelection(.enabled)
                    Spacer()
                    Button("폴더 위치로 돌아가기") {
                        if let node = analyzer.nodes[folder] { analyzer.showInTree(node) }
                    }
                }
            }
            if analyzer.mode == .tree && analyzer.hasBrowseFilters {
                Text("조건에 맞는 항목을 펼친 목록입니다. 계층 구조는 ‘조건 초기화’ 후 확인할 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if analyzer.browseFileKind != .all {
                Text("확장자로 분류한 개별 파일입니다. 파일 내용을 읽지 않으며, 앱·보관함 내부는 기본적으로 제외합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("디스크 점유량 기준 · 부모와 자식 폴더는 중복되므로 목록의 용량을 합산하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            ScanProgressView()
            HSplitView {
                VStack {
                    ScrollViewReader { reader in
                    List(selection: $analyzer.selectedPath) {
                        ForEach(displayedRows, id: \.node.id) { entry in
                            HStack(spacing: 8) {
                                if !analyzer.usesFlatBrowseList {
                                    Button {
                                        if analyzer.expanded.contains(entry.node.path) { analyzer.expanded.remove(entry.node.path) }
                                        else { analyzer.expanded.insert(entry.node.path) }
                                    } label: {
                                        Image(systemName: analyzer.expanded.contains(entry.node.path) ? "chevron.down" : "chevron.right")
                                            .frame(width: 12)
                                    }.buttonStyle(.borderless)
                                        .disabled(!entry.node.isFolder || entry.node.type == .package && !analyzer.browseIncludePackages)
                                }
                                Image(systemName: entry.node.isFolder ? "folder" : "doc")
                                Text(entry.node.name).lineLimit(1)
                                Spacer()
                                Text(entry.node.sizeText).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .padding(.leading, CGFloat(min(entry.depth, 12)) * 14)
                            .tag(entry.node.path).id(entry.node.path)
                            .contextMenu {
                                if entry.node.isFolder {
                                    Button("이 폴더 안의 큰 파일 보기") { analyzer.browseFiles(in: entry.node) }
                                }
                                Button("트리에서 위치 보기") { analyzer.showInTree(entry.node) }
                                Button("Finder에서 보기") { analyzer.reveal(path: entry.node.path) }
                                    .disabled(ItemKnowledge.isSystemManaged(entry.node.path))
                            }
                        }
                    }.searchable(text: $analyzer.browseSearch, prompt: "이름으로 찾기")
                        .onAppear { if let path = analyzer.selectedPath { reader.scrollTo(path, anchor: .center) } }
                        .onChange(of: analyzer.selectedPath) { path in
                            if let path { reader.scrollTo(path, anchor: .center) }
                        }
                    }
                    if displayedRows.count == analyzer.browseDisplayLimit {
                        Button("더 보기 (선택 경로 포함 \(analyzer.browseDisplayLimit)개)") { analyzer.browseDisplayLimit += 300 }
                    }
                    if analyzer.nodes.isEmpty && !analyzer.isScanning {
                        Text("공간 사용을 분석하거나 폴더를 선택하세요.").foregroundStyle(.secondary)
                    } else if displayedRows.isEmpty && !analyzer.isScanning {
                        Text("현재 범위와 보기 조건에 맞는 항목이 없습니다.").foregroundStyle(.secondary)
                        if !analyzer.browseSearch.isEmpty {
                            Button("검색 지우기") { analyzer.browseSearch = "" }
                        }
                        if analyzer.mode != .tree {
                            Button("폴더 트리로 전체 결과 보기") {
                                analyzer.clearBrowseFilters(); analyzer.mode = .tree
                            }
                        }
                    }
                }.frame(minWidth: 320)
                ScrollView {
                    if let path = analyzer.selectedPath, let node = analyzer.nodes[path],
                       displayedRows.contains(where: { $0.node.path == path }) {
                        StorageDetailView(node: node, openApplication: openApplication) {
                            analyzer.showInTree(node)
                        }
                    } else {
                        Text("현재 목록에서 항목을 선택하면 용도와 확인할 점을 보여드립니다.")
                            .foregroundStyle(.secondary).padding()
                    }
                }.frame(minWidth: 250, idealWidth: 320, maxWidth: 400)
            }
        }.padding(20)
    }
}

struct StorageDetailView: View {
    @EnvironmentObject private var analyzer: StorageAnalyzer
    let node: StorageNode
    let openApplication: (URL) -> Void
    @EnvironmentObject private var uninstaller: AppUninstaller
    let showInTree: () -> Void
    private var info: ItemExplanation { ItemKnowledge.explanation(for: node) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(node.name).font(.title2.bold()).textSelection(.enabled)
            Text(node.path).font(.caption.monospaced()).textSelection(.enabled)
            Text("디스크 점유량: \(node.sizeText)").font(.headline)
            if let logical = node.logicalBytes {
                Text("논리 크기: \(ByteCountFormatter.string(fromByteCount: logical, countStyle: .file))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("압축·온라인 전용 파일·희소 파일은 논리 크기와 점유량이 다릅니다. APFS 공유 블록 때문에 합계는 실제 확보 가능한 공간과 다를 수 있습니다.")
                .font(.caption).foregroundStyle(.secondary)
            if let note = node.note { Text(note).font(.callout).foregroundStyle(.orange) }
            if node.measurement == .partial { Text("읽지 못했거나 아직 확인하지 않은 내용이 있어 합계가 불완전합니다.").font(.caption) }
            Divider()
            Text(info.title).font(.headline)
            Text(info.purpose)
            Text("정리 전 확인").font(.headline)
            Text(info.impact)
            Text(info.evidence).font(.caption).foregroundStyle(.secondary)
            if let source = info.source { Link("공식 도움말 열기", destination: source) }
            if let query = info.searchQuery, let url = ItemKnowledge.searchURL(query: query) {
                Divider()
                Text("웹 검색어: \(query)").font(.caption).textSelection(.enabled)
                Link("브라우저에서 용도 검색", destination: url)
                Text("클릭하면 위 검색어만 Google로 보냅니다. 전체 경로나 개인 파일명은 포함하지 않습니다. 검색 결과는 삭제 안전성의 근거가 아닙니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if node.type == .package && URL(fileURLWithPath: node.path).pathExtension.lowercased() == "app" && !ItemKnowledge.isSystemManaged(node.path) {
                Button("앱 관리에서 정리 검토") { openApplication(URL(fileURLWithPath: node.path)) }
                    .disabled(uninstaller.busy)
                if uninstaller.busy { Text("앱 관리에서 진행 중인 작업을 마친 뒤 선택하세요.").font(.caption) }
            }
            if node.isFolder {
                Button("이 폴더 안의 큰 파일 보기") { analyzer.browseFiles(in: node) }
            }
            if let parent = node.parent, let parentNode = analyzer.nodes[parent] {
                Button("상위 폴더 보기") { analyzer.showInTree(parentNode) }
            }
            Button("경로 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(node.path, forType: .string)
            }
            Button("트리에서 위치 보기", action: showInTree)
            Button("Finder에서 보기") { analyzer.reveal(path: node.path) }
                .disabled(ItemKnowledge.isSystemManaged(node.path))
        }.padding()
    }
}

struct ScanProgressView: View {
    @EnvironmentObject private var analyzer: StorageAnalyzer
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !analyzer.roots.isEmpty {
                Text("분석 범위: " + analyzer.roots.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            }
            if analyzer.resultsNeedRefresh {
                HStack {
                    Text("이 목록은 이전 분석 결과입니다. 외부 변경이나 휴지통 이동은 아직 반영되지 않았을 수 있습니다.").font(.caption).foregroundStyle(.orange)
                    Button("이 범위 다시 분석") { analyzer.reanalyze() }.disabled(analyzer.isScanning)
                }
            }
            HStack {
            if analyzer.isScanning { ProgressView().controlSize(.small) }
            Text(analyzer.statusText).font(.caption).lineLimit(2).textSelection(.enabled)
            Spacer()
            if analyzer.isScanning { Button("분석 중지") { analyzer.cancel() } }
            else if analyzer.state == .cancelled {
                Button("이 범위 다시 분석") { analyzer.reanalyze() }
            } else if case .failed = analyzer.state {
                Button("다시 시도") { analyzer.reanalyze() }
            }
            }
        }
    }
}
