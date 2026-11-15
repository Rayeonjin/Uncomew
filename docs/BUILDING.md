# Uncomew 설치·업데이트·복구

언커뮤는 완성된 앱 대신 소스를 배포합니다. 아래 순서대로 따라 하면 자신의 Mac에서 빌드하고 설치할 수 있습니다. 터미널이 익숙하지 않아도 명령을 한 줄씩 실행하면 됩니다.

## 준비

- macOS 13 이상
- Swift 5.9 이상을 포함한 Apple Command Line Tools
- 소스를 내려받고 개발 도구를 설치할 인터넷 연결과 빌드에 필요한 여유 공간

**전체 Xcode 앱과 유료 개발자 계정은 필요 없습니다.** 지금 사용하는 Mac의 칩에 맞춰 빌드합니다. 실제로 확인한 환경은 [테스트 안내](TESTING.md)를 참고하세요.

## 1. 릴리스 소스 받기

[GitHub Releases](https://github.com/Rayeonjin/Uncomew/releases)에서 설치할 버전의 **Source code (zip)**을 받아 압축을 풉니다. `Code → Download ZIP`에는 개발 중인 변경이 들어갈 수 있으므로 릴리스 ZIP을 권장합니다.

현재 공개 버전은 **v0.2.0-alpha.1**입니다. 안정판이 아닌 초기 공개 테스트 버전이므로, 릴리스의 알려진 문제도 확인해 주세요.

## 2. 터미널과 빌드 도구 준비하기

`⌘ Command + Space`를 누르고 **터미널**을 검색해 실행합니다.

```bash
xcrun swift --version
```

Swift 5.9 이상이 나오면 다음 단계로 넘어가세요. 도구가 없다는 오류가 나오면 아래 명령으로 Command Line Tools를 설치합니다.

```bash
xcode-select --install
```

명령 이름에 `xcode`가 들어가지만 전체 Xcode 앱을 설치하는 명령은 아닙니다. 설치가 끝나면 `xcrun swift --version`을 다시 확인하세요.

## 3. 소스 폴더로 이동하기

터미널에 `cd `를 입력합니다. 뒤에 공백 하나를 넣고, Finder에서 압축을 푼 폴더를 터미널 창으로 끌어다 놓은 뒤 Enter를 누릅니다.

```bash
pwd
ls setup.sh
```

압축을 푼 폴더의 경로와 `setup.sh`가 나오면 준비됐습니다.

## 4. 빌드하고 설치하기

실행 중인 Uncomew를 종료한 뒤 실행하세요. `sudo`는 사용하지 않습니다.

```bash
bash setup.sh
```

스크립트가 빌드·로컬 서명·앱 검증을 마치면 `~/Applications/Uncomew.app`에 설치합니다. 처음 빌드는 시간이 걸릴 수 있으니 완료 안내를 기다려 주세요.

## 5. 앱 열기

설치 후 앱은 자동으로 열리지 않습니다. 다음 명령으로 실행하세요.

```bash
open "$HOME/Applications/Uncomew.app"
```

처음에는 **정리할 곳 찾기**를 누르거나 필요한 폴더만 직접 선택해 보세요. 일반 파일 분석은 읽기 전용입니다.

개인정보 보호 영역을 읽지 못한 경우 **시스템 설정 → 개인정보 보호 및 보안 → 전체 디스크 접근 권한**에서 설치된 Uncomew를 추가하고 앱을 완전히 종료한 뒤 다시 실행할 수 있습니다. 권한을 줘도 일부 시스템 경로는 읽을 수 없으며, 업데이트 후 권한을 다시 확인해야 할 수 있습니다.

평소에는 `~/Applications/Uncomew.app`을 실행하세요. 개발 폴더의 `dist/Uncomew.app`은 별도 복사본입니다. 기존 DiskScope 앱은 자동으로 지우거나 교체하지 않습니다.

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

Swift/SDK가 호환되지 않는다는 오류가 나면 `xcrun swift --version`, `xcrun --show-sdk-path`, `xcode-select -p`로 현재 도구를 확인하세요. 설치된 macOS에 맞는 Apple 개발 도구로 업데이트하거나 설치 상태를 점검하세요. 개발 중 도구와 SDK 버전이 맞지 않아 빌드가 실패한 적이 있습니다. 다른 사람의 SDK 경로를 그대로 복사하기보다 자신의 설치 상태를 먼저 확인해 주세요.

## 설치 중 오류

- **실행 중인 앱:** Uncomew를 종료한 뒤 재시도하세요. 스크립트가 앱을 강제로 종료하지 않습니다.
- **검증 실패:** 새 앱을 설치하지 않습니다. 복사·교체 중 일반적인 오류가 발생하면 기존 앱과 백업을 복원하도록 시도합니다.
- **다른 앱·심볼릭 링크:** 같은 설치 이름에 다른 식별자의 앱이 있거나 설치 경로에 심볼릭 링크가 있으면 교체를 거부합니다. 기존 항목을 직접 확인하세요.
- **잠금:** `.uncomew-install.lock`은 중복 설치/복구를 막습니다. 다른 작업이 진행 중이면 기다리세요.
- **강제 종료·전원 차단:** SIGKILL 또는 전원 차단은 자동 복구를 보장하지 않습니다. 잠금이나 `.uncomew-stage.*` 폴더가 남으면 임의로 지우지 마세요. 먼저 실행 중인 설치가 없는지 확인하고, `Uncomew.app`, `Uncomew.previous.app`, stage의 `current.app`·`older.app` 상태를 보존한 채 복구해야 합니다. 자동 복구에 실패한 경우에도 stage 경로를 출력하고 보존합니다.

문제 제보는 [텔레그램 · Rayeonjin](https://t.me/Rayeonjin)으로 보내주세요. Uncomew 관련 문의임을 적고 macOS 버전, 칩 종류, Uncomew 버전과 실패 단계/메시지를 포함하세요. 개인 경로와 파일명은 공유 전에 가리세요.

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

개발 중 설치 위치를 바꾸려면 아래처럼 전체 경로를 지정하세요. 복구할 때도 같은 경로를 사용해야 합니다.

```bash
UNCOMEW_APPLICATIONS_DIR="/absolute/path/Applications" bash setup.sh
UNCOMEW_APPLICATIONS_DIR="/absolute/path/Applications" bash rollback.sh
```

이 검사는 앱 파일과 설치 절차를 확인합니다. 실제 화면 조작이나 전체 디스크 분석은 별도로 확인해야 합니다.

### 임시 경로에서 개발 테스트하기

일반 사용자는 Downloads 등 일반 폴더에 소스를 풀어 빌드하세요. 개발 검사를 `/tmp`·`/var` 계열에서 실행하면 macOS 경로 별칭/심볼릭 링크 때문에 제거 안전 검사가 일회용 테스트 데이터를 거부할 수 있습니다. 안전 검사를 완화하지 말고, 심볼릭 링크를 포함하지 않는 개발 폴더를 일회용 테스트 데이터 위치로 지정하세요. 지정 폴더의 `.build` 아래에 UUID 이름의 일회용 데이터만 만들고 정리합니다.

```bash
UNCOMEW_TEST_ROOT="$HOME/Projects/Uncomew" bash test-workflow.sh
UNCOMEW_TEST_ROOT="$HOME/Projects/Uncomew" bash test-flow.sh
UNCOMEW_TEST_ROOT="$HOME/Projects/Uncomew" bash test-improvements.sh
```

위 경로는 예시이며 실제 개발 폴더로 바꿔야 합니다. 앱 빌드·실행에 필요한 설정은 아닙니다.
