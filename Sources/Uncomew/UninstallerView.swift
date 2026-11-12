import AppKit
import SwiftUI

struct UninstallerView: View {
    @EnvironmentObject private var uninstaller: AppUninstaller
    let openOverview: () -> Void
    @EnvironmentObject private var analyzer: StorageAnalyzer
    @State private var confirmationFilename = ""
    private var listedApplications: [ApplicationEntry] {
        let runningApps = NSWorkspace.shared.runningApplications
        let running = Set(runningApps.compactMap { $0.bundleURL?.standardizedFileURL.path })
        let runningIDs = Set(runningApps.compactMap(\.bundleIdentifier))
        return ApplicationRanking.sorted(uninstaller.applications, nodes: analyzer.nodes, largestFirst: uninstaller.inventoryLargestFirst)
            .filter { uninstaller.inventorySearch.isEmpty || $0.name.localizedCaseInsensitiveContains(uninstaller.inventorySearch) }
            .filter { ApplicationUsage.matches($0, filter: uninstaller.usageFilter,
                                               bytes: analyzer.nodes[$0.url.path]?.allocatedBytes,
                                               kept: uninstaller.isKept($0), running: running.contains($0.url.standardizedFileURL.path) || (!$0.bundleID.isEmpty && runningIDs.contains($0.bundleID))) }
    }
    private var appExplanation: ItemExplanation? {
        guard let url = uninstaller.selectedAppURL else { return nil }
        var node = StorageNode(path: url.path, parent: nil, type: .package, insidePackage: false)
        node.bundleID = uninstaller.bundleIdentifier
        node.appName = uninstaller.appName
        return ItemKnowledge.explanation(for: node)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("앱 관리").font(.largeTitle.bold())
                Spacer()
                Button("목록 새로 확인") { uninstaller.loadApplications() }.disabled(uninstaller.busy)
                Button("다른 앱 선택…") { uninstaller.chooseApplication() }.disabled(uninstaller.busy)
            }
            Text("앱을 선택해 본체와 관련 파일을 살펴보세요. 관련 데이터는 조회만 하며 설치된 앱 본체 하나만 휴지통으로 옮길 수 있습니다.").foregroundStyle(.secondary)
            HStack {
                Button("목록의 앱 크기 분석") { analyzer.analyze(roots: uninstaller.applications.map { $0.url.path }) }
                    .disabled(uninstaller.busy || analyzer.isScanning || uninstaller.inventoryLoading || uninstaller.applications.isEmpty)
                Toggle("크기순", isOn: $uninstaller.inventoryLargestFirst).toggleStyle(.checkbox)
                Text("앱 본체만 비교 · 미측정 항목은 아래에 표시").font(.caption).foregroundStyle(.secondary)
            }
            ScanProgressView()
            Picker("사용 기록", selection: $uninstaller.usageFilter) {
                ForEach(ApplicationUsage.Filter.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu).disabled(uninstaller.busy)
            Text("큰 앱은 본체 100 MB 이상입니다. 오래된 사용 기록 필터는 크기가 측정된 앱 중 실행 중·보관 앱을 제외합니다. 기록 없음은 미사용을 뜻하지 않습니다.")
                .font(.caption).foregroundStyle(.secondary)
            Text("사용 기록 확인 \(uninstaller.applications.filter { ApplicationUsage.validatedDate($0.lastUsedDate) != nil }.count)개 · 전체 \(uninstaller.applications.count)개 앱 중 현재 조건 \(listedApplications.count)개")
                .font(.caption).foregroundStyle(.secondary)
            HSplitView {
                VStack {
                    TextField("앱 이름 검색", text: $uninstaller.inventorySearch).disabled(uninstaller.busy).textFieldStyle(.roundedBorder).padding(.horizontal, 8)
                    if uninstaller.inventoryLoading { ProgressView("앱 목록 확인 중") }
                    List(listedApplications) { app in
                        Button { uninstaller.scan(app.url) } label: {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(app.name).fontWeight(uninstaller.selectedAppURL == app.url ? .bold : .regular)
                                    Spacer()
                                    Text(analyzer.nodes[app.url.path]?.sizeText ?? "미측정").font(.caption).monospacedDigit()
                                }
                                Text(app.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text(usageText(app)).font(.caption).foregroundStyle(.secondary)
                                if uninstaller.isKept(app) { Text("보관 · 오래된 앱 검토에서 제외").font(.caption).foregroundStyle(.secondary) }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).disabled(uninstaller.busy)
                            .contextMenu {
                                Button(uninstaller.isKept(app) ? "보관 해제" : "계속 보관 · 오래된 앱 검토에서 제외") {
                                    uninstaller.setKept(!uninstaller.isKept(app), app: app)
                                }.disabled(uninstaller.busy)
                            }
                    }
                    if listedApplications.isEmpty && !uninstaller.inventoryLoading {
                        Text("조건에 맞는 앱이 없습니다. 미측정 앱은 크기 분석 후 확인하세요.").font(.caption).foregroundStyle(.secondary).padding(8)
                        if uninstaller.usageFilter == .older90 || uninstaller.usageFilter == .older180 {
                            Text("오래 안 쓴 앱이 없다는 뜻은 아닙니다. 사용 기록을 확인할 수 없는 앱도 있습니다.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
                            Button("기록 확인 불가 앱 보기") { uninstaller.usageFilter = .unknown; uninstaller.inventorySearch = "" }
                        }
                        Button("모든 앱 보기") { uninstaller.usageFilter = .all; uninstaller.inventorySearch = "" }
                    }
                    Text("/Applications · ~/Applications\n크기는 마지막 저장 공간 분석 결과입니다. 목록 크기 분석은 기존 탐색 결과를 교체합니다.")
                        .font(.caption).foregroundStyle(.secondary).padding(8)
                }.frame(minWidth: 220, idealWidth: 240, maxWidth: 280)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if uninstaller.isScanning {
                            HStack {
                                ProgressView("앱 크기와 관련 파일 확인 중…")
                                Button("분석 중지") { uninstaller.cancelScan() }
                            }
                        }
                        if let url = uninstaller.selectedAppURL {
                            if !listedApplications.contains(where: { $0.url == url }) {
                                Text("아래는 이전에 선택했거나 별도로 연 앱입니다. 현재 목록 조건에는 포함되지 않습니다.")
                                    .font(.callout).foregroundStyle(.orange)
                                Button("목록 조건 초기화") {
                                    uninstaller.usageFilter = .all; uninstaller.inventorySearch = ""
                                }.disabled(uninstaller.busy)
                            }
                            Text(uninstaller.appName).font(.title2.bold())
                            Text(uninstaller.bundleIdentifier.isEmpty ? "앱 식별자 없음" : uninstaller.bundleIdentifier)
                                .font(.caption.monospaced()).textSelection(.enabled)
                            Text(url.path).font(.caption).textSelection(.enabled)
                            Button("Finder에서 앱 보기") { uninstaller.reveal(path: url.path) }
                            if let app = uninstaller.applications.first(where: { $0.url == url }) {
                                Text(usageText(app)).font(.callout)
                                Text("macOS에 기록된 마지막 열기 시점입니다. 모든 실행·사용 시간·사용 빈도를 포함하는 기록은 아니며, 삭제해도 된다는 뜻이 아닙니다.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Button(uninstaller.isKept(app) ? "보관 해제 · 검토에 다시 포함" : "계속 보관 · 오래된 앱 검토에서 제외") {
                                    uninstaller.setKept(!uninstaller.isKept(app), app: app)
                                }.disabled(uninstaller.busy)
                                Text("보관 설정은 이 Mac에 저장되며 ‘모든 앱’에서 바꿀 수 있습니다.").font(.caption).foregroundStyle(.secondary)
                            }
                            if let info = appExplanation {
                                Text(info.title).font(.headline)
                                Text(info.purpose).font(.callout)
                                Text(info.impact).font(.caption).foregroundStyle(.secondary)
                                Text(info.evidence).font(.caption).foregroundStyle(.secondary)
                                if let source = info.source { Link("공식 용도·관리 안내", destination: source) }
                            }
                            if ItemKnowledge.validBundleID(uninstaller.bundleIdentifier),
                               let searchURL = ItemKnowledge.searchURL(query: uninstaller.bundleIdentifier + " mac app official") {
                                Text("추가 정보는 앱 식별자로 검색할 수 있습니다.").font(.callout)
                                Text("검색어: \(uninstaller.bundleIdentifier) mac app official").font(.caption).textSelection(.enabled)
                                Link("브라우저에서 용도 검색", destination: searchURL)
                                Text("클릭하면 위 검색어를 Google로 보냅니다. 앱 경로는 보내지 않습니다.").font(.caption).foregroundStyle(.secondary)
                            }
                            Divider()
                            Toggle("앱 본체 선택 · \(uninstaller.appSize.map { size($0) } ?? "확인 불가")", isOn: $uninstaller.includeApplication)
                                .disabled(uninstaller.busy || !uninstaller.canSelectApplication)
                            Text("관련 파일").font(.headline)
                            Text("Bundle ID와 이름이 같은 경로입니다. 문서·설정·동기화 데이터가 포함될 수 있어 앱 안에서는 이동할 수 없습니다. 독점 소유라고 판단하지 마세요.")
                                .font(.caption).foregroundStyle(.secondary)
                            if uninstaller.relatedFiles.isEmpty && !uninstaller.isScanning {
                                Text("표시할 관련 파일이 없습니다. 관련 파일이 전혀 없다는 뜻은 아닙니다.").foregroundStyle(.secondary)
                            }
                            ForEach(uninstaller.relatedFiles) { file in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(file.name) · \(file.formattedSize)").font(.callout)
                                    Text(file.path).font(.caption.monospaced()).textSelection(.enabled)
                                    Button("Finder에서 보기") { uninstaller.reveal(path: file.path) }
                                }.padding(.vertical, 4)
                            }
                            Button("선택 항목 검토…") { uninstaller.prepareReview() }
                                .buttonStyle(.borderedProminent)
                                .disabled(uninstaller.busy || !uninstaller.includeApplication)
                        } else {
                            Text("왼쪽 목록에서 앱을 선택하세요.").font(.title2).foregroundStyle(.secondary)
                        }
                        if uninstaller.isTrashing { ProgressView("휴지통으로 이동 중…") }
                        if let status = uninstaller.statusMessage { Text(status).font(.callout).textSelection(.enabled) }
                        if !uninstaller.restorableItems.isEmpty {
                            Divider()
                            Text("이번 실행에서 휴지통으로 옮긴 항목").font(.headline)
                            Text("원래 위치로 복원합니다. 기존 항목은 덮어쓰지 않습니다. 앱을 종료하면 이 목록은 사라지지만 Finder의 휴지통은 그대로 남습니다.").font(.caption).foregroundStyle(.secondary)
                            ForEach(uninstaller.restorableItems) { receipt in
                                Text(receipt.originalPath).font(.caption).textSelection(.enabled)
                                Button("이 항목 원래 위치로 복원") { uninstaller.restore(receipt) }.disabled(uninstaller.busy)
                            }
                        }
                        if uninstaller.removalRevision > 0 {
                            Button("요약에서 남은 공간 확인", action: openOverview)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding()
                }.frame(minWidth: 380)
            }
        }.padding(20)
            .task { if uninstaller.applications.isEmpty { uninstaller.loadApplications() } }
            .sheet(item: $uninstaller.review) { plan in
                VStack(alignment: .leading, spacing: 16) {
                    Text("선택한 항목을 휴지통으로 이동할까요?").font(.title2.bold())
                    Text("앱 본체 1개 · 측정된 크기 \(size(plan.bytes))")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(plan.candidates) { item in Text(item.path).font(.callout.monospaced()).textSelection(.enabled) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("앱 안의 데이터가 포함될 수 있습니다. 위 경로의 앱 본체만 이동하며 관련 Library 데이터는 이동하지 않습니다. 휴지통은 자동으로 비우지 않습니다.")
                    TextField("확인: 앱 파일명 전체 입력", text: $confirmationFilename)
                        .textFieldStyle(.roundedBorder)
                    Text("확인할 파일명: \(plan.candidates.first.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? "")")
                        .font(.caption).textSelection(.enabled)
                    HStack {
                        Button("취소") { confirmationFilename = ""; uninstaller.review = nil }.keyboardShortcut(.cancelAction)
                        Spacer()
                        Button("앱 본체를 휴지통으로 이동", role: .destructive) {
                            uninstaller.moveReviewedToTrash(confirmedFilename: confirmationFilename)
                            confirmationFilename = ""
                        }.disabled(confirmationFilename != plan.candidates.first.map { URL(fileURLWithPath: $0.path).lastPathComponent })
                    }
                }.padding(24).frame(width: 600, height: 430)
            }
            .onChange(of: uninstaller.review?.id) { newValue in
                confirmationFilename = ""
                if newValue == nil { uninstaller.includeApplication = false }
            }
    }
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    private func usageText(_ app: ApplicationEntry) -> String {
        guard let date = ApplicationUsage.validatedDate(app.lastUsedDate) else { return "사용 기록 확인 불가" }
        return "마지막 사용 기록: " + date.formatted(date: .abbreviated, time: .omitted)
    }
}
