# Development Progress

작성일: 2026-06-16

이 문서는 `docs/project/development-progress.html`의 Confluence 이관용 Markdown 요약본이다.

## 현재 프로젝트 역할

- 메인 채팅: 구현 사항 결정, 선택 사항 결정, 개발 전반 설계, 진행판 관리
- 서브 에이전트: 실제 구현 작업 담당 예정
- 로컬 작업 환경: 코드 생산, mock/dry-run 검증, 문서화
- 실제 실행/테스트: 회사 내부망에서 pull 받아 수행

## 확정된 기본 조건

| 항목 | 결정 |
| --- | --- |
| 초기 기술 스택 | FastAPI + React/Vite |
| SSH 접속 | password 기반, env로 설정 |
| 웹앱 실행 위치 | 별도 웹 제어 호스트 |
| sudo route | password 필요, env에서 읽어 stdin 전달 검토 |
| 수집 명령 | 기존 스크립트 경로를 설정으로 제공받아 실행 |
| 웹앱 역할 | 단계별 클릭 실행, 활성화 확인, one-call 실행/종료, 검증 스크립트 로그 출력 |

## Action 중심 조작 모델

### 수집 Action

- 수집 시작/중지는 toggle 버튼으로 제공한다.
- 수집 모니터링은 기본 1초마다 확인한다.
- 정상 판단은 1초 동안 파일 10개 증가, 각 파일명 timestamp가 100ms 간격인지로 판단한다.
- 한 번이라도 어긋나면 fatal error로 표시한다.
- fatal 발생 시 자동 중지하지 않고, 사용자가 계속 진행 또는 수집 정지를 선택한다.
- 용량 10G 초과는 수집 정상 여부가 아니라 주의 알림 기준으로 사용한다.

### 전송 Action

- 사용자가 test name을 입력하고 전송 시작을 누르면 cycle을 시작한다.
- 전송 준비는 route on과 port-forward on을 포함한다.
- 전송 준비 이후 file server를 자동 실행한다.
- file server가 시작되면 downloader를 자동 실행한다.
- downloader 종료 후 file server를 자동 중지한다.
- cycle 성공 또는 실패 완료 후 port-forward와 route는 항상 원복한다.

### Retry / 실패 정책

- 다운로드 실패 시 다운로드 폴더를 자동 삭제하지 않는다.
- server/downloader를 재시작해서 최대 3회 자동 retry한다.
- 3회 실패 후에는 사용자가 정지 또는 다시 시도를 선택한다.
- 다시 시도 횟수에는 제한을 두지 않는다.
- 원복 실패 시 직접 실행할 명령과 상태 재확인 버튼을 제공한다.

## 주요 문서

| 문서 | 용도 |
| --- | --- |
| `docs/project/development-context.md` | 다른 세션 인계를 위한 전체 설계 컨텍스트 |
| `docs/project/development-progress.html` | 로컬 확인용 진행판 |
| `docs/operations/existing-data-flow.html` | 기존 수동 데이터 수집 흐름 HTML |
| `docs/operations/existing-data-flow.md` | Confluence 이관용 기존 수동 흐름 |
| `docs/architecture/k8s-pod-shm-access-summary.html` | shm/proc 접근 기술 검토 HTML |
| `docs/architecture/k8s-pod-shm-access-summary.md` | Confluence 이관용 shm/proc 접근 기술 검토 |
| `docs/decisions/pod-separation-decision-record.html` | Pod 분리 의사결정 기록 HTML |
| `docs/decisions/pod-separation-decision-record.md` | Confluence 이관용 Pod 분리 의사결정 기록 |

## 진행 로그

| 일시 | 내용 |
| --- | --- |
| 2026-06-10 12:03 KST | 기존 데이터 수집 타임라인을 HTML로 분리하고, 웹 조작 단위를 action 중심으로 확정 |
| 2026-06-11 10:02 KST | 프로세스 상태 판단을 SSH session/exit status 중심으로 수정, admin token은 MVP에서 제외 |
| 2026-06-15 18:42 KST | `/proc/<PID>/root/dev/shm` 접근 원리와 직접 hostPath mount 실패 사례 추가 |
| 2026-06-16 10:48 KST | Pod 분리 방안 도출 과정을 HTML/MD로 신규 정리 |
| 2026-06-16 11:03 KST | 진행판 파일명을 `docs/project/development-progress.html`로 정리 |
| 2026-06-16 11:44 KST | Confluence 이관용 Markdown 대응본과 Mermaid 도식 추가, 문서 구조를 성격별 디렉토리로 재정리 |
