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
                Toggle("보관한 항목도 보기", isOn: $analyzer.showKeptCandidates).toggleStyle(.checkbox)
                Spacer()
                Text("\(filtered.count)개 · 확인 우선순위").font(.caption)
            }
            HStack {
                Picker("판단 기록", selection: $analyzer.candidateDecisionFilter) {
                    Text("전체").tag("전체")
                    Text("정리 검토").tag(CandidateDecision.review.rawValue)
                    Text("나중에 검토").tag(CandidateDecision.later.rawValue)
                }.frame(maxWidth: 300)
                Text("설치 파일 → 빌드 데이터 → 앱 → 내용 확인이 필요한 항목. 같은 단계에서는 크기순입니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if analyzer.resultsNeedRefresh {
                Text("정리 후 결과가 바뀌었을 수 있습니다. 다시 분석한 뒤 판단을 기록하세요.")
                    .foregroundStyle(.orange)
            }
            if analyzer.preparingCandidates { ProgressView("후보 분류 중…") }
            if filtered.isEmpty && !analyzer.preparingCandidates {
                Text(analyzer.isScanning ? "분석이 끝나거나 중지되면 확인한 범위에서 후보를 분류합니다." :
                     (analyzer.nodes.isEmpty ? "‘후보 위치 분석’으로 시작하세요. 자동으로 파일을 지우지 않습니다." :
                      "현재 범위·필터에서 조건에 맞는 후보가 없습니다. 정리할 공간이 없다는 뜻은 아닙니다."))
                    .foregroundStyle(.secondary).padding()
                if !analyzer.isScanning && !analyzer.preparingCandidates && !analyzer.nodes.isEmpty {
                    HStack {
                        if analyzer.candidateCategory != "전체" || analyzer.candidateDecisionFilter != "전체" || !analyzer.keptCandidatePaths.isEmpty {
                            Button("모든 분류·보관 항목 보기") {
                                analyzer.candidateCategory = "전체"; analyzer.candidateDecisionFilter = "전체"; analyzer.showKeptCandidates = true
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
                            Text(candidate.category.rawValue + (analyzer.decision(for: candidate).map { " · " + $0.rawValue } ?? ""))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(candidate.priorityReason).font(.caption).foregroundStyle(.secondary)
                            if analyzer.hasChangedDecision(for: candidate) {
                                Text("항목 변경됨 · 다시 판단").font(.caption).foregroundStyle(.orange)
                            }
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
                            CandidateDecisionPanel(candidate: candidate)
                                .id(candidate.id + CandidateDecisionStore.fingerprint(candidate.node))

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

struct CandidateDecisionPanel: View {
    @EnvironmentObject private var analyzer: StorageAnalyzer
    let candidate: CleanupCandidate
    @State private var answers = Set<Int>()
    private var disabled: Bool {
        analyzer.isScanning || analyzer.preparingCandidates || analyzer.resultsNeedRefresh
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("정리를 검토하기 전에").font(.headline)
            Text("답하기 어렵다면 보관하거나 나중에 검토하세요. 체크는 사용자의 확인 기록이며, 앱이 안전성을 검사한 결과가 아닙니다.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(Array(candidate.questions.enumerated()), id: \.offset) { index, question in
                Toggle(question, isOn: Binding(
                    get: { answers.contains(index) },
                    set: { if $0 { answers.insert(index) } else { answers.remove(index) } }
                )).toggleStyle(.checkbox).disabled(disabled)
            }
            if candidate.node.measurement != .complete {
                Text("일부만 분석된 항목입니다. 다시 분석하기 전에는 정리 검토로 표시할 수 없습니다.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let decision = analyzer.decision(for: candidate) {
                Text("저장한 판단: \(decision.rawValue)").font(.headline)
            } else if analyzer.hasChangedDecision(for: candidate) {
                Text("이전 기록 이후 항목 정보가 바뀌었습니다. 다시 확인해 주세요.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("계속 보관") { analyzer.setDecision(.keep, for: candidate) }
                Button("나중에 검토") { analyzer.setDecision(.later, for: candidate) }
            }.disabled(disabled)
            Button("정리 검토에 담기") { analyzer.setDecision(.review, for: candidate, confirmedQuestions: answers) }
                .disabled(disabled || answers.count != candidate.questions.count ||
                          candidate.node.measurement != .complete)
            if analyzer.decision(for: candidate) != nil || analyzer.hasChangedDecision(for: candidate) {
                Button("판단 기록 지우기") {
                    analyzer.setDecision(nil, for: candidate)
                    answers.removeAll()
                }.disabled(disabled)
            }
            Text("판단은 이 Mac에 저장됩니다. 파일을 이동하거나 삭제하지 않으며, 이후 삭제 확인을 대신하지 않습니다. 항목의 식별 정보·크기·수정 정보가 바뀌면 다시 판단합니다.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
