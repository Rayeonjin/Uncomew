import SwiftUI

struct SystemView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("폴더 분석은 확인할 수 있는 파일의 디스크 점유량을 집계합니다. macOS의 볼륨 사용량에는 스냅샷, 파일시스템 메타데이터, 다른 사용자 및 접근할 수 없는 영역도 포함될 수 있습니다.")
            Text("APFS는 여러 볼륨과 파일이 공간을 공유할 수 있습니다. 폴더 합계와 사용량의 차이를 그대로 ‘숨은 파일’ 또는 ‘정리 가능 공간’으로 계산하지 않습니다.")
            Text("VM·swap은 가상 메모리, Preboot는 부팅 지원 영역이며 macOS가 관리합니다. 직접 삭제하지 마세요. 재시동 후 swap 사용량이 줄어들 수 있습니다.")
            Text("이번 분석의 대상과 볼륨 전체는 범위가 다릅니다. 다른 볼륨과 패키지 내부의 표시 여부, 부분 분석 상태를 확인하세요.")
            Link("Apple 저장 공간 도움말", destination: URL(string: "https://support.apple.com/102624")!)
        }.font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
    }
}
