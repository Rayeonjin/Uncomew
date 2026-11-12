# Uncomew 설치·업데이트·복구

Uncomew는 소스를 내려받아 자신의 Mac에서 빌드하는 방식으로 배포할 예정입니다. 초기 공개 테스트 버전이며 안정판은 아닙니다. 아래 절차는 로컬 소스에서도 사용할 수 있습니다.

## 준비

- macOS 13 이상
- Swift 5.9 이상을 포함한 Apple Command Line Tools (전체 Xcode와 유료 개발자 계정 불필요)
- 현재 Mac의 아키텍처에 맞춰 빌드: Apple Silicon 또는 Intel. 실제 검증 환경은 [테스트 안내](TESTING.md)를 참고하세요.

터미널에서 개발 도구를 설치합니다.

```bash
xcode-select --install
```

설치가 끝나면 확인합니다.

```bash
xcrun swift --version
```

## 설치

[GitHub Releases](https://github.com/Rayeonjin/Uncomew/releases)에서 원하는 버전의 **Source code ZIP**을 받습니다. 기본 브랜치 ZIP에는 개발 중 변경이 포함될 수 있습니다. 압축을 풀고 터미널에 `cd `를 입력한 뒤 압축을 푼 폴더를 끌어다 놓고 Enter를 누릅니다.

실행 중인 Uncomew를 종료하고 다음 명령을 실행합니다. `sudo`는 사용하지 않습니다.

```bash
bash setup.sh
```

스크립트는 빌드·로컬 서명을 수행하고 앱 식별자, 실행 파일, 아키텍처, 서명을 검증합니다. 검증된 앱을 `~/Applications/Uncomew.app`에 설치합니다. 관리자 권한은 요구하지 않습니다. 앱은 자동으로 실행되지 않습니다.

```bash
open "$HOME/Applications/Uncomew.app"
```

스캔에서 개인정보 보호 영역의 접근 거부가 보고되면 **시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한**에 설치된 Uncomew를 추가하고 앱을 완전히 종료한 뒤 다시 실행하세요. 권한을 줘도 일부 macOS 보호 경로는 읽을 수 없습니다. 직접 빌드한 앱은 업데이트 후 권한을 다시 확인해야 할 수 있습니다.

기존 DiskScope 앱은 설치 대상이 아니며 자동으로 삭제하거나 교체하지 않습니다. 설치된 앱과 `dist/Uncomew.app`을 혼동하지 않도록 일반 사용은 위의 설치 경로에서 실행하세요.

## 업데이트

새 릴리스 소스를 **별도 폴더**에 풀고 Uncomew를 종료한 뒤 실행합니다.

```bash
bash setup.sh
```

현재 설치된 앱을 `~/Applications/Uncomew.previous.app`으로 보관한 뒤 새 앱을 사용합니다. 이전 앱은 한 개만 유지하며, 그보다 오래된 백업은 정상 업데이트 완료 후 정리합니다. 같은 버전을 재설치해도 백업은 직전에 설치되어 있던 앱으로 바뀝니다.

업데이트를 자동으로 확인하거나 설치하지 않습니다. GitHub Releases에서 새 버전을 확인하세요. 설정과 사용자 파일은 설치 스크립트가 변경하지 않습니다.

## 이전 버전으로 복구

Uncomew를 종료하고 소스 폴더에서 실행합니다.

```bash
bash rollback.sh
open "$HOME/Applications/Uncomew.app"
```

현재 앱과 이전 앱이 서로 바뀝니다. 복구에는 새 빌드가 필요하지 않습니다. 이전 앱이 없으면 과거 릴리스 소스를 내려받아 `bash setup.sh`로 설치하세요. 앱 버전 복구는 사용자 데이터나 설정을 과거 시점으로 되돌리는 기능이 아닙니다.

## 검증 환경과 빌드 도구 문제

2026-11-12 Apple Silicon에서 새 임시 소스 폴더의 `bash build-app.sh`가 별도 SDK 지정 없이 성공했습니다. 다른 Mac 및 모든 macOS 버전을 검증한 결과는 아닙니다.

Swift/SDK가 호환되지 않는다는 오류가 나면 `xcrun swift --version`, `xcrun --show-sdk-path`, `xcode-select -p`로 현재 도구를 확인하세요. 설치된 macOS에 맞는 Apple 개발 도구로 업데이트하거나 설치 상태를 점검하세요. 과거 개발 환경에서는 SDK/컴파일러 불일치가 있었으므로 특정 SDK 경로를 모든 사용자에게 강제로 지정하지 않습니다.

## 설치 중 오류

- **실행 중인 앱:** Uncomew를 종료한 뒤 재시도하세요. 스크립트가 앱을 강제로 종료하지 않습니다.
- **검증 실패:** 새 앱을 설치하지 않습니다. 복사·교체 중 일반적인 오류가 발생하면 기존 앱과 백업을 복원하도록 시도합니다.
- **다른 앱·심볼릭 링크:** 같은 설치 이름에 다른 식별자의 앱이 있거나 설치 경로에 심볼릭 링크가 있으면 교체를 거부합니다. 기존 항목을 직접 확인하세요.
- **잠금:** `.uncomew-install.lock`은 중복 설치/복구를 막습니다. 다른 작업이 진행 중이면 기다리세요.
- **강제 종료·전원 차단:** SIGKILL 또는 전원 차단은 자동 복구를 보장하지 않습니다. 잠금이나 `.uncomew-stage.*` 폴더가 남으면 임의로 지우지 마세요. 먼저 실행 중인 설치가 없는지 확인하고, `Uncomew.app`, `Uncomew.previous.app`, stage의 `current.app`·`older.app` 상태를 보존한 채 복구해야 합니다. 자동 복구에 실패한 경우에도 stage 경로를 출력하고 보존합니다.

문제 제보는 [Telegram · Rayeonjin](https://t.me/Rayeonjin)으로 보내주세요. Uncomew 관련 문의임을 적고 macOS 버전, 칩 종류, Uncomew 버전과 실패 단계/메시지를 포함하세요. 개인 경로와 파일명은 공유 전에 가리세요.

## 개발용 빌드·검증

설치하지 않고 빌드하기:

```bash
bash build-app.sh
bash scripts/validate_app.sh dist/Uncomew.app
bash run-app.sh
```

테스트:

```bash
bash test-core.sh
bash test-workflow.sh
bash test-flow.sh
bash test-journeys.sh
bash test-improvements.sh
bash Tests/Installation/test_installation.sh
```

설치 검사는 임시 폴더와 테스트용 앱 복사본만 사용합니다. 정상 설치·업데이트·복구, 교체 실패 복원, 잘못된 앱/서명/심볼릭 링크, 실행 중 앱 보호, 한글·공백 경로에서의 소스 빌드를 검사합니다. 설치 검사 실행 전 Uncomew를 종료하세요.

개발/테스트 목적의 설치 위치 변경은 절대 경로로 지정할 수 있습니다. 복구할 때도 같은 값을 지정해야 합니다.

```bash
UNCOMEW_APPLICATIONS_DIR="/absolute/path/Applications" bash setup.sh
UNCOMEW_APPLICATIONS_DIR="/absolute/path/Applications" bash rollback.sh
```

이 검증은 앱 번들 무결성과 설치 절차에 관한 것입니다. 실제 GUI 실행·전체 디스크 스캔 성공을 보장하는 검사는 아닙니다.

### 임시 경로에서 개발 테스트하기

일반 사용자는 Downloads 등 일반 폴더에 소스를 풀어 빌드하세요. 개발 검사를 `/tmp`·`/var` 계열에서 실행하면 macOS 경로 별칭/심볼릭 링크 때문에 제거 안전 검사가 fixture를 거부할 수 있습니다. 안전 검사를 완화하지 말고, 심볼릭 링크를 포함하지 않는 개발 폴더를 fixture 위치로 지정하세요. 지정 폴더의 `.build` 아래에 UUID 이름의 일회용 데이터만 만들고 정리합니다.

```bash
UNCOMEW_TEST_ROOT="$HOME/Projects/Uncomew" bash test-workflow.sh
UNCOMEW_TEST_ROOT="$HOME/Projects/Uncomew" bash test-flow.sh
UNCOMEW_TEST_ROOT="$HOME/Projects/Uncomew" bash test-improvements.sh
```

위 경로는 예시이며 실제 개발 폴더로 바꿔야 합니다. 앱 빌드·실행에 필요한 설정은 아닙니다.
