import SwiftUI

struct CleanupCandidatesView: View {
    @EnvironmentObject private var analyzer: StorageAnalyzer
    let openStorage: (StorageNode) -> Void
    let openApplication: (URL) -> Void
    let openFiles: () -> Void
    private var filtered: [CleanupCandidate] { analyzer.visibleCandidates }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("정리 후보").font(.largeTitle.bold())
                Spacer()
                Button("후보 위치 분석") { analyzer.analyzeCandidates() }.disabled(analyzer.isScanning)
            }
            Text("먼저 확인할 만한 항목입니다. 불필요하거나 안전하게 삭제할 수 있다고 판정한 목록은 아닙니다.")
                .foregroundStyle(.secondary)
            Text("현재 분석 범위에서 후보를 보여줍니다. ‘후보 위치 분석’은 다운로드·응용 프로그램·사용자 캐시·Xcode 빌드 데이터로 범위를 바꿉니다.")
                .font(.caption).foregroundStyle(.secondary)
            ScanProgressView()
            if analyzer.issueCount > 0 {
                HStack {
                    Text("접근 제한·지연·분석 한도가 있는 위치 \(analyzer.issueCount)개 · 아래 후보는 확인한 범위만 포함합니다.")
                        .font(.caption).foregroundStyle(.orange)
                    Button("미확인 위치 보기") {
                        if let node = analyzer.nodes.values.filter({ $0.measurement == .unavailable || $0.measurement == .excluded || $0.measurement == .partial && $0.note != nil }).sorted(by: { $0.path < $1.path }).first {
                            openStorage(node)
                        }
                    }
                }
            }
            HStack {
                Picker("분류", selection: $analyzer.candidateCategory) {
                    Text("전체").tag("전체")
                    ForEach(CleanupCandidate.Category.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                }.frame(maxWidth: 300)
                Toggle("이번 실행에서 보관한 항목 표시", isOn: $analyzer.showKeptCandidates).toggleStyle(.checkbox)
                Spacer()
                Text("\(filtered.count)개 · 크기순").font(.caption)
            }
            if analyzer.preparingCandidates { ProgressView("후보 분류 중…") }
            if filtered.isEmpty && !analyzer.preparingCandidates {
                Text(analyzer.isScanning ? "분석이 끝나거나 중지되면 확인한 범위에서 후보를 분류합니다." :
                     (analyzer.nodes.isEmpty ? "‘후보 위치 분석’으로 시작하세요. 자동으로 파일을 지우지 않습니다." :
                      "현재 범위·필터에서 조건에 맞는 후보가 없습니다. 정리할 공간이 없다는 뜻은 아닙니다."))
                    .foregroundStyle(.secondary).padding()
                if !analyzer.isScanning && !analyzer.preparingCandidates && !analyzer.nodes.isEmpty {
                    HStack {
                        if analyzer.candidateCategory != "전체" || !analyzer.keptCandidatePaths.isEmpty {
                            Button("모든 분류·보관 항목 보기") {
                                analyzer.candidateCategory = "전체"; analyzer.showKeptCandidates = true
                            }
                        }
                        Button("현재 범위의 큰 파일 보기", action: openFiles)
                    }
                }
            }
            HSplitView {
                ScrollViewReader { reader in
                List(selection: $analyzer.selectedCandidatePath) {
                    ForEach(filtered) { candidate in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(candidate.node.name).lineLimit(1)
                                Spacer()
                                Text(candidate.node.sizeText).monospacedDigit()
                            }
                            Text(candidate.category.rawValue + (analyzer.keptCandidatePaths.contains(candidate.id) ? " · 보관" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4).tag(candidate.id).id(candidate.id)
                    }
                }
                .onAppear { if let path = analyzer.selectedCandidatePath { reader.scrollTo(path, anchor: .center) } }
                .onChange(of: analyzer.selectedCandidatePath) { path in
                    if let path { reader.scrollTo(path, anchor: .center) }
                }
                }.frame(minWidth: 290)
                ScrollView {
                    if let candidate = filtered.first(where: { $0.id == analyzer.selectedCandidatePath }) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(candidate.node.name).font(.title2.bold())
                            Text(candidate.node.path).font(.caption.monospaced()).textSelection(.enabled)
                            Text("측정된 점유량: \(candidate.node.sizeText)").font(.headline)
                            if let modified = candidate.node.modifiedAt {
                                Text("마지막 수정: \(modified.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                            }
                            Text("후보로 표시한 이유").font(.headline)
                            Text(candidate.reason)
                            Text("정리하면 달라지는 점").font(.headline)
                            Text(candidate.impact)
                            Text(candidate.nextStep)
                            Text("측정값은 확보 보장량이 아닙니다. 부분 측정·공유 블록·재생성에 따라 실제 변화가 다릅니다.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("용도와 상세 보기") { openStorage(candidate.node) }
                            if candidate.category == .applications {
                                CandidateAppButton(url: URL(fileURLWithPath: candidate.id), action: openApplication)
                            } else {
                                Button("Finder에서 검토") { analyzer.reveal(path: candidate.id) }
                            }
                            Button(analyzer.keptCandidatePaths.contains(candidate.id) ? "보관 표시 해제" : "이번 실행에서는 보관") {
                                if analyzer.keptCandidatePaths.contains(candidate.id) { analyzer.keptCandidatePaths.remove(candidate.id) }
                                else { analyzer.keptCandidatePaths.insert(candidate.id) }
                            }
                            Text("보관 표시는 이 앱 실행 동안만 목록에서 숨깁니다. 파일은 변경하지 않습니다.").font(.caption).foregroundStyle(.secondary)
                        }.padding()
                    } else { Text("항목을 선택해 이유와 영향을 확인하세요.").foregroundStyle(.secondary).padding() }
                }.frame(minWidth: 300, idealWidth: 380, maxWidth: 480)
            }
        }.padding(20)
            .onAppear { analyzer.reconcileCandidateSelection() }
            .onChange(of: filtered.map(\.id)) { _ in analyzer.reconcileCandidateSelection() }
    }
}

private struct CandidateAppButton: View {
    @EnvironmentObject private var uninstaller: AppUninstaller
    let url: URL
    let action: (URL) -> Void
    var body: some View {
        Button("앱 관리에서 검토") { action(url) }.disabled(uninstaller.busy)
    }
}
