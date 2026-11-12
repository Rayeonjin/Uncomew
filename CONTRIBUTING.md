# Uncomew 기여 안내

현재는 직접 빌드하는 초기 공개 테스트 버전을 개발하고 있습니다. 버그·사용성 제보와 작은 수정부터 환영합니다.

## 제보

[GitHub Issues](https://github.com/Rayeonjin/Uncomew/issues)의 오류 제보/사용성 피드백 양식을 사용하세요. macOS·칩·앱 버전, 기대한 결과와 실제 결과를 적어주세요. 공개 이슈에 개인 경로, 파일명, 앱 목록, 토큰을 올리지 마세요.

## 개발

[빌드 안내](docs/BUILDING.md)를 따라 `bash build-app.sh`를 실행합니다. 변경과 관련된 검사를 실행하고 PR에 결과와 미검증 환경을 적어주세요.

```bash
bash test-core.sh
bash test-workflow.sh
bash test-flow.sh
bash test-journeys.sh
bash test-improvements.sh
```

일반 테스트는 사용자 파일을 휴지통으로 옮기지 않습니다. `test-improvements.sh --trash`는 별도로 선택하는 실제 휴지통/복원 fixture 검사입니다. 중요한 데이터로 삭제 동작을 시험하지 마세요.

## 변경 원칙

- 미측정·접근 불가 크기를 0이나 정리 가능 공간으로 표시하지 않습니다.
- 관련 Library 데이터는 조회 전용입니다. 일반 파일 자동 삭제, 영구 삭제, 휴지통 비우기는 추가하지 않습니다.
- 앱 본체 이동은 사용자 선택·정확한 경로 검토·파일명 확인·실행 상태 및 파일 식별 재검사를 유지합니다.
- 파일 내용이나 개인 경로를 자동 전송하지 않습니다.
- 동작을 바꾸면 해당 사용 흐름과 알려진 한계를 문서에도 반영합니다.
