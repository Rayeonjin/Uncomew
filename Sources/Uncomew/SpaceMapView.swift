import SwiftUI

struct SpaceMapView: View {
    @EnvironmentObject private var analyzer: StorageAnalyzer
    let openApplication: (URL) -> Void
    @EnvironmentObject private var uninstaller: AppUninstaller
    private var folder: String? { analyzer.mapFolder }
    @State private var listLimit = 100
    private var current: StorageNode? { folder.flatMap { analyzer.nodes[$0] } }
    private var children: [StorageNode] {
        let paths = folder == nil ? analyzer.roots : (current?.children ?? [])
        return paths.compactMap { analyzer.nodes[$0] }.sorted {
            if $0.allocatedBytes != $1.allocatedBytes { return ($0.allocatedBytes ?? 0) > ($1.allocatedBytes ?? 0) }
            return $0.path < $1.path
        }
    }
    private var trail: [StorageNode] {
        var result: [StorageNode] = []
        var cursor = current
        var seen = Set<String>()
        while let node = cursor, seen.insert(node.path).inserted {
            result.insert(node, at: 0)
            cursor = node.parent.flatMap { analyzer.nodes[$0] }
        }
        return result
    }
    private func enter(_ node: StorageNode) {
        guard node.type == .folder else { return }
        analyzer.enterMapFolder(node); listLimit = 100
    }
    private func color(_ node: StorageNode) -> Color {
        if ItemKnowledge.isSystemManaged(node.path) { return .gray }
        if node.type == .package { return .purple }
        return node.isFolder ? .teal : .blue
    }
    var body: some View {
        let children = self.children
        let positive = children.filter { ($0.allocatedBytes ?? 0) > 0 }
        let visible = Array(positive.prefix(40))
        let remainder = positive.dropFirst(40).reduce(0.0) { $0 + Double($1.allocatedBytes ?? 0) }
        let measured = positive.reduce(0.0) { $0 + Double($1.allocatedBytes ?? 0) }
        let unassigned = current.map { max(0, Double($0.allocatedBytes ?? 0) - measured) } ?? 0
        let weights = visible.map { Double($0.allocatedBytes ?? 0) } + [remainder, unassigned]
        let total = weights.reduce(0, +)
        let selected = children.first { $0.path == analyzer.mapSelectedPath }
        return VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("상위 폴더") { analyzer.mapGoUp(); listLimit = 100 }
                        .disabled(folder == nil)
                    Button("분석 범위") { analyzer.mapFolder = nil; analyzer.mapSelectedPath = nil; listLimit = 100 }
                    ForEach(trail) { node in
                        Image(systemName: "chevron.right").font(.caption)
                        Button(node.name) { enter(node) }.disabled(node.path == folder)
                    }
                }
            }
            Text("블록을 선택하면 상세 정보가 나옵니다. 폴더는 두 번 클릭하거나 ‘폴더 안으로’를 누르세요.")
                .font(.callout)
            Text("면적 = 측정된 점유량 · 청록: 폴더 / 파랑: 파일 / 보라: 앱·보관함 / 회색: 시스템 관리·기타. 색은 삭제 안전 등급이 아닙니다.")
                .font(.caption).foregroundStyle(.secondary)
            ScanProgressView()
            if analyzer.issueCount > 0 || children.contains(where: { $0.measurement != .complete }) {
                Text("미확인·부분 분석 항목이 있습니다. 지도는 확인한 크기만 표현하며, 빈 공간이나 삭제 가능량을 뜻하지 않습니다.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button(folder == nil ? "정리 후 다시 확인" : "이 폴더만 다시 확인") {
                    analyzer.refreshMapFolder()
                }.disabled(analyzer.isScanning)
                if analyzer.resultsNeedRefresh {
                    Text("Finder에서 변경했다면 다시 확인하세요. 표시된 크기는 이전 분석 결과입니다.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            HSplitView {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            if total <= 0 {
                                Text(analyzer.isScanning ? "폴더 크기를 확인하고 있습니다…" : "면적으로 표시할 크기가 없습니다. 아래 목록의 측정 상태를 확인하세요.")
                                    .foregroundStyle(.secondary).padding()
                            }
                            ForEach(SpaceMapLayout.tiles(weights: weights, in: CGRect(origin: .zero, size: geometry.size))) { tile in
                                let node = tile.id < visible.count ? visible[tile.id] : nil
                                let label = node?.name ?? (tile.id == visible.count ? "나머지 \(positive.count - visible.count)개 · 아래 목록" : "폴더 자체·미분류 점유량")
                                SpaceMapTile(label: label,
                                             sizeText: node?.sizeText ?? ByteCountFormatter.string(fromByteCount: Int64(weights[tile.id]), countStyle: .file),
                                             color: node.map { color($0) } ?? Color.gray,
                                             selected: node != nil && node?.path == analyzer.mapSelectedPath,
                                             rect: tile.rect,
                                             select: { analyzer.mapSelectedPath = node?.path },
                                             enter: { if let node { enter(node) } })

                            }
                        }
                    }.frame(minHeight: 120, maxHeight: .infinity)
                    Text("현재 위치 \(children.count)개 · 작은 항목과 크기 미확인 항목도 목록에서 선택할 수 있습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    List(selection: $analyzer.mapSelectedPath) {
                        ForEach(Array(children.prefix(listLimit))) { node in
                            HStack {
                                Image(systemName: node.isFolder ? "folder" : "doc").foregroundStyle(color(node))
                                Text(node.name).lineLimit(1)
                                Spacer()
                                Text(node.sizeText).monospacedDigit()
                                if node.type == .folder {
                                    Button { enter(node) } label: { Image(systemName: "chevron.right") }
                                        .buttonStyle(.borderless).help("폴더 안으로")
                                }
                            }.tag(node.path)
                        }
                        if children.count > listLimit {
                            Button("항목 더 보기") { listLimit += 100 }
                        }
                    }.frame(height: 120)
                }.frame(minWidth: 310)
                ScrollView {
                    if let node = selected {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(node.name).font(.title2.bold())
                            Text(node.path).font(.caption).textSelection(.enabled)
                            Text(node.sizeText).font(.title.bold())
                            if total > 0, let bytes = node.allocatedBytes {
                                Text(String(format: "현재 지도에서 측정된 점유량의 %.1f%%", Double(bytes) / total * 100))
                            }
                            Text(ItemKnowledge.explanation(for: node).title).font(.headline)
                            Text(ItemKnowledge.explanation(for: node).purpose).font(.callout)
                            if node.type == .folder {
                                Button("폴더 안으로") { enter(node) }
                            }
                            Button("Finder에서 내용 확인") { analyzer.reveal(path: node.path) }
                                .disabled(ItemKnowledge.isSystemManaged(node.path))
                            if node.type == .package && URL(fileURLWithPath: node.path).pathExtension.lowercased() == "app" {
                                Button("앱 관리에서 검토") { openApplication(URL(fileURLWithPath: node.path)) }
                                    .disabled(uninstaller.busy)
                            }
                            if let candidate = analyzer.candidates.first(where: { $0.id == node.path }) {
                                DisclosureGroup("보관·정리 판단 기록") {
                                    CandidateDecisionPanel(candidate: candidate)
                                        .id(candidate.id + CandidateDecisionStore.fingerprint(candidate.node))
                                }
                            }
                            if node.type == .package {
                                Text("앱·보관함은 하나의 묶음으로 표시합니다. 내부 파일을 따로 삭제하지 마세요.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("큰 항목이라고 불필요한 것은 아닙니다. 내용을 확인한 뒤 정리 여부를 결정하세요.")
                                .font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("용도·주의사항 자세히") {
                                StorageDetailView(node: node, openApplication: openApplication) { analyzer.showInTree(node) }
                            }
                        }.padding()
                    } else {
                        Text("큰 블록부터 선택해 보세요.\n폴더 안을 살펴보고 필요한 자료인지 확인할 수 있습니다.")
                            .foregroundStyle(.secondary).padding()
                    }
                }.frame(minWidth: 240, idealWidth: 280, maxWidth: 350)
            }
        }
        .onChange(of: analyzer.mapFolder) { _ in listLimit = 100 }
        .onChange(of: analyzer.nodes.isEmpty) { empty in if empty { listLimit = 100 } }
    }
}

private struct SpaceMapTile: View {
    let label: String
    let sizeText: String
    let color: Color
    let selected: Bool
    let rect: CGRect
    let select: () -> Void
    let enter: () -> Void
    var body: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(color.opacity(0.72))
            .frame(width: max(0, rect.width - 3), height: max(0, rect.height - 3))
            .overlay(alignment: .topLeading) {
                if rect.width > 65 && rect.height > 35 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(label).font(.callout.bold()).lineLimit(2)
                        if rect.height > 65 { Text(sizeText).font(.caption).lineLimit(1) }
                    }.foregroundStyle(.white).padding(8)
                }
            }
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 5).stroke(Color.primary, lineWidth: 3) }
            }

            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: enter)
            .onTapGesture(perform: select)
            .help(label + " · " + sizeText)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label + " · " + sizeText)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { select() }
            .offset(x: rect.minX, y: rect.minY)
    }
}
