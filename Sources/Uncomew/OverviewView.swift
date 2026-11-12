import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var analyzer: StorageAnalyzer
    @EnvironmentObject private var uninstaller: AppUninstaller
    let openStorage: (StorageAnalyzer.BrowseMode) -> Void
    let openCurrentResults: (StorageAnalyzer.BrowseMode) -> Void
    let openApplications: () -> Void
    let openCandidates: () -> Void
    let chooseFolder: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("어디에 공간이 쓰이고 있을까요?").font(.largeTitle.bold())
                Text("큰 항목의 용도를 확인하고, 필요한 것만 정리하세요.").foregroundStyle(.secondary)
                Text("무엇부터 확인할까요?").font(.title2.bold())
                HStack(alignment: .top, spacing: 12) {
                    entry("정리할 곳 찾기", "다운로드·앱·캐시에서 먼저 검토할 항목을 찾습니다.", icon: "checklist", disabled: analyzer.isScanning, action: openCandidates)
                    entry("전체 사용량 보기", "큰 폴더와 파일부터 저장 공간을 살펴봅니다.", icon: "internaldrive", disabled: analyzer.isScanning) {
                        openStorage(.folders)
                    }
                    entry("폴더 직접 선택", "이미 의심되는 폴더만 분석합니다.", icon: "folder", disabled: analyzer.isScanning, action: chooseFolder)
                }
                Text("분석은 파일의 크기·위치 정보를 읽으며, 선택만으로 파일을 지우지 않습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("이 Mac의 홈 폴더가 있는 볼륨").font(.caption).foregroundStyle(.secondary)
                        if analyzer.capacityLoaded {
                            HStack(alignment: .top, spacing: 24) {
                                capacityValue("Finder 기준 · 사용 가능(추정)", value: analyzer.summary.finderComparableBytes,
                                              detail: "필요할 때 macOS가 확보할 수 있는 공간 포함")
                                capacityValue("언커뮤 기준 · 현재 비어 있음", value: analyzer.summary.availableBytes,
                                              detail: "추가 정리 없이 현재 비어 있는 공간")
                            }
                            if let extra = analyzer.summary.additionalAvailableBytes {
                                Text("두 기준의 차이: \(size(extra)) · macOS의 추가 확보 가능량 추정입니다. 지금 비어 있거나 직접 삭제할 수 있다는 뜻은 아닙니다.")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("macOS의 사용 가능량 추정을 확인하지 못했습니다. 현재 비어 있는 공간만 표시합니다.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Text("전체 \(size(analyzer.summary.totalBytes)) 중 \(size(analyzer.summary.usedBytes)) 사용 중·예약됨")
                            ProgressView(value: analyzer.summary.usedRatio)
                            if uninstaller.removalRevision > 0, let initial = analyzer.initialAvailableBytes {
                                let change = analyzer.summary.availableBytes - initial
                                Text("이번 실행의 첫 확인 대비 빈 공간: \(change >= 0 ? "+" : "−")\(size(abs(change)))")
                                    .font(.callout).monospacedDigit()
                                Text("다른 앱의 저장·다운로드와 macOS 작업도 포함한 변화입니다. 언커뮤로 확보한 용량을 뜻하지 않습니다.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let date = analyzer.capacityDate {
                                Text("최근 확인 \(date.formatted(date: .abbreviated, time: .standard))").font(.caption).foregroundStyle(.secondary)
                            }
                        } else { Text("저장 공간 정보 확인 중…") }
                        if let error = analyzer.capacityError { Text("용량 확인 실패: \(error)").foregroundStyle(.orange) }
                        Button("남은 공간 새로 확인") { analyzer.refreshCapacity() }
                        DisclosureGroup("숫자의 기준과 분석 범위") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Finder 기준은 macOS의 사용 가능량 추정 API로 조회합니다. Finder 화면을 직접 읽는 값은 아니며, 갱신 시점·반올림에 따라 다를 수 있습니다. 앱 사용 중 30초마다 함께 갱신합니다. (1 GB = 10억 바이트)")
                                Text("전체 분석 범위: 내 홈 폴더, 응용 프로그램, 공용 Library, 시스템 작업 데이터. 정리 후보 찾기는 그중 자주 점검하는 위치만 확인합니다.")
                            }.font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                ScanProgressView()
                if !analyzer.nodes.isEmpty {
                    HStack(alignment: .top, spacing: 12) {
                        entry("큰 파일", "현재 분석 결과의 단일 파일을 봅니다.", icon: "doc") { openCurrentResults(.files) }
                        entry("큰 폴더", "현재 분석 결과의 폴더를 봅니다.", icon: "folder") { openCurrentResults(.folders) }
                        entry("앱 관리", "앱 본체와 관련 경로를 봅니다.", icon: "app", action: openApplications)
                    }
                    Text("먼저 살펴볼 큰 항목").font(.title2.bold())
                    Text("크기는 삭제 추천을 의미하지 않습니다. 분석 중인 용량은 계속 달라질 수 있습니다.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(largest) { node in
                        Button {
                            analyzer.selectedPath = node.path
                            analyzer.showInTree(node)
                            openCurrentResults(.tree)
                        } label: {
                            HStack {
                                Image(systemName: node.isFolder ? "folder" : "doc")
                                VStack(alignment: .leading) {
                                    Text(node.name).font(.headline)
                                    Text(ItemKnowledge.explanation(for: node).title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(node.sizeText).monospacedDigit()
                                Image(systemName: "chevron.right")
                            }.padding(10).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
                if analyzer.issueCount > 0 {
                    GroupBox("확인하지 못한 내용이 있습니다") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(analyzer.issueCount)개 위치에서 접근 제한·제외·분석 한도가 보고됐습니다. 확인한 결과는 계속 살펴볼 수 있습니다.")
                            Button("트리에서 확인") { analyzer.clearBrowseFilters(); openCurrentResults(.tree) }
                            if analyzer.suggestsPrivacyAccess {
                                Text("개인정보 보호 영역을 읽지 못했습니다. 전체 디스크 접근 권한이 도움이 될 수 있지만, 권한이 꺼져 있다는 뜻은 아닙니다.")
                                Button("전체 디스크 접근 설정") { analyzer.openPrivacySettings() }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }
                DisclosureGroup("분석한 크기와 macOS 사용량이 다른 이유") { SystemView() }
                Text("휴지통으로 옮긴 파일은 휴지통을 비우기 전까지 공간을 차지할 수 있습니다. 정리 후 ‘남은 공간 새로 확인’으로 실제 상태를 확인하세요.")
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
    private func capacityValue(_ title: String, value: Int64?, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(value.map { size($0) } ?? "확인 불가")
                .font(.system(size: 28, weight: .bold, design: .rounded)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var largest: [StorageNode] {
        StorageRanking.top(analyzer.nodes.values, limit: 5) { node in
            !node.insidePackage && node.parent.map { analyzer.roots.contains($0) } == true && node.allocatedBytes != nil
        }
    }
    private func size(_ value: Int64) -> String { value == 0 ? "0 B" : ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    private func entry(_ title: String, _ text: String, icon: String, disabled: Bool = false,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: icon).font(.headline)
                Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }.frame(maxWidth: .infinity, minHeight: 75, alignment: .leading).padding()
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain).disabled(disabled)
    }
}
