# Data Collector Web App Development Context

이 문서는 다른 세션 또는 서브 에이전트가 현재 설계 상태를 빠르게 이어받기 위한 컨텍스트 문서다.

민감한 내부 IP, 계정, 경로는 placeholder로 표기한다. 실제 값은 내부망 실행 환경의 `.env` 또는 별도 설정 파일에서 주입한다.

## 목표

회사 내부망에서 실행할 데이터 수집/전송 테스트 웹앱을 만든다.

로컬 개발 환경에서는 실제 서버 접속을 하지 않고 코드 생산, mock/dry-run 검증, 문서화를 수행한다. 실제 route, SSH, Kubernetes, 다운로드 검증은 내부망에서 pull 후 진행한다.

## 현재 설계 상태

- UI는 터미널 기준이 아니라 `수집 action`과 `전송 action` 중심으로 구성한다.
- 수집은 collector toggle과 모니터링 중심이다.
- 전송은 테스트 이름을 입력하고 `전송 시작`을 누르면 route, port-forward, server, downloader, 정리, 원복을 자동 orchestration한다.
- 수집 fatal은 자동 중지하지 않고 사용자에게 `계속 진행` 또는 `수집 정지`를 선택하게 한다.
- 다운로드 실패는 server/downloader를 다시 시작해 3회까지 자동 retry한다.
- 3회 retry 이후에는 사용자가 `정지` 또는 `다시 시도`를 선택한다. `다시 시도` 횟수 제한은 두지 않는다.
- `auto_delete_after_transfer`는 기본 `true`다. off이면 전송 성공 후 수동 삭제 버튼을 제공한다.
- server/downloader는 블랙박스로 취급한다. partial 파일 삭제나 이어받기 성공을 앱이 가정하지 않는다.
- 기존 수동 흐름 참고 HTML은 `docs/existing-data-flow.html`에 sanitized 형태로 둔다.

## 실행 환경

- 웹앱 실행 위치: 웹 제어 호스트
- 수집 서버: Kubernetes와 dpp pod가 있는 서버
- 다운로드 클라이언트: 다운로드를 수행하는 클라이언트
- SSH 인증: password 기반, env 설정 사용
- sudo 인증: password 필요, env에서 읽어 stdin으로 전달하는 방식 검토
- 기술 스택: FastAPI + React/Vite

## 기존 수동 흐름

기존 작업자는 터미널을 3개로 나눠 수행했다.

- 터미널 1: 웹 제어 호스트에서 수집 서버에 접속 후 dpp pod `port-forward` 유지
- 터미널 2: 웹 제어 호스트에서 수집 서버에 접속 후 route on, dpp pod 진입, 수집, file server, 정리, route off
- 터미널 3: 웹 제어 호스트에서 다운로드 클라이언트에 접속 후 다운로드 준비와 downloader 실행

이 수동 흐름은 `docs/existing-data-flow.html`에 push 가능한 sanitized 참고본으로 도식화되어 있다. 실제 IP/계정/내부 경로는 placeholder 상태를 유지해야 한다.

## 웹앱 조작 모델

웹 UI는 터미널 1/2/3 기준으로 만들지 않는다. 터미널 분리는 사람이 수동 실행하기 위한 구조였고, 웹앱에서는 action 중심으로 재구성한다.

### 수집 action

- collector 시작/중지: toggle 버튼
- 파일 생성 확인: 기본 1초마다 확인
- 정상 기준: 1초 동안 파일 10개 증가, 각 파일명 timestamp가 100ms 간격이면 정상
- fatal 기준: 1초 체크에서 파일 10개 증가 또는 100ms timestamp 간격이 한 번이라도 어긋나면 fatal error 상태
- 용량 확인: 수집 정상 여부가 아니라 경고 기준
- 용량 주의: 10G 초과 시 주의 알림 표시
- 산출물 정리: 수집 action이 아니라 전송 성공 후 후처리로 분류

### 전송 action

사용자는 테스트 이름을 입력하고 `전송 시작`을 누른다. 내부적으로는 다음 단계를 자동 orchestration한다.

1. route on
2. port-forward on
3. 전송 서버 시작
4. 다운로드 실행
5. 전송 서버 중지
6. 다운로드 성공 시 auto delete toggle 확인
7. auto delete가 on이면 산출물 정리
8. auto delete가 off이면 수동 삭제 버튼 제공
9. port-forward off
10. route off

각 내부 단계는 UI에 진행 상태와 로그로 표시한다.

성공 또는 retry 3회 실패로 전송 cycle이 완료되면 port-forward와 route는 무조건 원복한다.

전송 옵션:

- `auto_delete_after_transfer`: 기본 `true`
- `true`: 다운로드 성공 후 수집 서버/pod 산출물 자동 삭제
- `false`: 다운로드 성공 후 산출물 보존, UI에 수동 삭제 버튼 제공

## 테스트 입력 기본값

각 값은 기본값을 제공하되 UI에서 수정 가능해야 한다.

| 항목 | 기본값 | 설명 |
| --- | --- | --- |
| `test_name` | 필수 입력 | 다운로드 대상 테스트 디렉터리 이름 |
| `download_date` | 오늘 날짜, `yymmdd` | 다운로드 클라이언트에서 날짜별 저장 경로를 만들 때 사용 |
| `download_root_dir` | env 설정 | 다운로드 클라이언트에서 `download_date/test_name`을 만들 상위 디렉터리. 거의 변경되지 않는 값 |
| `workers` | `8` | downloader worker 수 |
| `cell-id` | `1` | collector 실행 인자 |
| `poll-interval` | `5` | collector 실행 인자 |
| `slot-step` | `2` | collector 실행 인자 |
| `slot-count` | `10` | collector 실행 인자 |

`download_base_dir`라는 표현은 모호하므로 사용하지 않는다. 이 값은 다운로드 클라이언트의 저장 상위 경로라는 의미로 `download_root_dir`라고 부른다.

## 블랙박스 전송 정책

`02_recursive_http_file_server.py`와 `02_recursive_http_file_downloader.py`의 내부 구현은 모르는 블랙박스로 취급한다.

따라서 앱은 가장 보수적인 방식으로 동작한다.

- downloader가 부분 파일을 안전하게 처리한다고 가정하지 않는다.
- downloader가 이어받기를 지원한다고 가정하지 않는다.
- downloader가 이미 받은 파일을 정확히 skip한다고 가정하지 않는다.
- 다운로드 실패 시 산출물 정리를 수행하지 않는다.
- 실패한 다운로드 결과물은 보존하거나, 명확한 대상 파일을 알 수 있을 때만 제거한다.
- partial 파일 제거는 downloader의 파일명/임시파일 규칙을 확인하기 전까지 자동 수행하지 않는다.

## 다운로드 실패 모델

전송 실패는 최소 세 종류로 구분한다.

1. 전송 서버/연결 실패
   - server가 시작되지 않음
   - HTTP 연결 실패
   - port-forward 또는 route 문제 가능성

2. 다음 파일 요청 실패
   - 일부 파일은 받았지만 다음 파일 목록 조회 또는 다운로드 요청 실패
   - downloader가 재실행 시 이미 받은 파일을 어떻게 처리하는지 확인 필요

3. 단일 파일 부분 다운로드 실패
   - 파일 하나를 받는 중간에 끊김
   - partial 파일이 남을 수 있음
   - downloader 규칙을 모르므로 자동 삭제는 보류

## Retry 및 원복 정책

기본 정책:

1. 다운로드 실패 감지
2. 전송 서버 중지
3. 전송 서버 재기동
4. 다운로드 재시도
5. 최대 3회 반복
6. 성공 시 후처리와 port-forward/route 원복
7. 3회 실패 시 `정지` 또는 `다시 시도` 선택 박스 표시
8. `정지` 선택 시 port-forward/route 원복 후 에러 표시
9. `다시 시도` 선택 시 추가 retry cycle 실행

원복은 전송 성공/실패 여부와 관계없이 best-effort로 시도한다. 원복 실패는 높은 우선순위 경고로 표시한다.

## Fatal 수집 상태 정책

수집 모니터링 fatal이 발생해도 collector를 자동 중지하지 않는다.

이유:

- 상황에 따라 데이터 수집을 계속 유지한 채 서버 설정을 확인해야 할 수 있다.
- 수집 중지를 자동화하면 원인 분석 기회를 잃을 수 있다.
- 사용자가 상태를 보고 관계자와 상의한 뒤 toggle off 여부를 결정해야 한다.

UI 동작:

- 수집 상태를 fatal error로 표시
- 문제 설명 박스를 표시
- 사용자가 `계속 진행` 또는 `수집 정지` 중 선택
- `계속 진행`: fatal 상태를 인지한 상태로 전송 시작 허용
- `수집 정지`: collector toggle off 실행
- fatal 발생 시각, 마지막 정상 파일명, 기대 파일 수, 실제 파일 수를 로그에 기록

## 전송 실패 보수 정책

server/downloader는 블랙박스이므로 파일 중간 실패를 앱이 직접 복구하지 않는다.

현재 가정:

- 파일 중간 다운로드 실패는 일반적인 케이스가 아니라고 본다.
- 실패하면 전송 서버와 downloader를 다시 시작한다.
- downloader가 이미 받은 파일을 이어받거나 skip하는지 여부는 블랙박스로 둔다.
- 다운로드 폴더를 자동 삭제하지 않는다.

정책:

- 다운로드 실패 시 전송 서버 중지
- 전송 서버 재기동
- downloader 재실행
- 최대 3회 retry
- 3회 실패 시 사용자에게 `정지` 또는 `다시 시도` 선택 박스 표시
- `정지`: port-forward/route 원복 후 에러 표시
- `다시 시도`: 추가 retry cycle 실행
- 다운로드 결과 디렉터리는 보존하고 에러 메시지 표시

원복 실패:

- port-forward 또는 route 원복이 실패하면 메시지 박스를 표시한다.
- 메시지 박스에는 사용자가 직접 실행할 원복 명령을 보여준다.
- 원복 실패 상태는 수동 조치 필요로 남긴다.

## 스크립트 배포

기존 가이드에서는 server/downloader 스크립트를 내부 위치에서 복사한다. 웹앱 구현에서는 repo에 포함된 파일을 대상 위치로 복사하는 방식을 선호한다.

- repo 내 위치 추천: `scripts/transfer/`
- server script: `scripts/transfer/02_recursive_http_file_server.py`
- downloader script: `scripts/transfer/02_recursive_http_file_downloader.py`
- server script 배포: 수집 서버를 통해 dpp pod 내부 작업 디렉터리로 복사
- downloader script 배포: 다운로드 클라이언트의 테스트 작업 디렉터리로 복사

실제 파일이 내부망에서 전달될 예정이면 개발 중에는 dummy placeholder를 둘 수 있다. 단, 인터페이스와 실행 인자는 실제 파일과 맞춰야 한다.

웹앱 시작 시 확인:

- `scripts/transfer/02_recursive_http_file_server.py` 존재 여부
- `scripts/transfer/02_recursive_http_file_downloader.py` 존재 여부
- 없으면 앱 상태를 setup error로 표시
- 전송 시작 버튼 비활성화
- 어떤 파일이 누락됐는지 명확히 표시

## 프로세스 추적 정책

MVP에서는 파일 기반 state를 사용한다.

추천 구조:

```text
runtime/processes.json
runs/{run_id}/state.json
runs/{run_id}/events.jsonl
runs/{run_id}/logs/{step_id}.log
```

`runtime/processes.json`에는 현재 살아 있어야 하는 유지형 실행 상태만 기록한다.

예시:

```json
{
  "collector": {
    "status": "running",
    "host": "collector",
    "pid": null,
    "started_at": "2026-06-11T00:00:00+09:00"
  },
  "port_forward": {
    "status": "running",
    "host": "collector",
    "pid": 12345,
    "run_id": "run_..."
  },
  "file_server": {
    "status": "running",
    "host": "pod",
    "pid": null,
    "run_id": "run_..."
  }
}
```

주의:

- 로컬 PID는 웹앱이 직접 실행한 로컬 프로세스에만 신뢰한다.
- SSH 원격 프로세스와 pod 내부 프로세스의 PID는 우선 신뢰하지 않는다.
- 원격/pod 유지형 프로세스는 SSH 실행 세션 상태를 우선 신호로 본다.
- 앱 재시작 시 `runtime/processes.json`을 읽고 각 프로세스 상태를 재확인한다.
- 앱이 만들지 않은 기존 프로세스가 감지되면 "외부 프로세스 감지, 수동 확인 필요"로 표시한다.

프로세스 상태 확인은 "SSH로 실행한 명령이 아직 연결되어 있는지, 정상 종료됐는지, 비정상 종료됐는지"를 우선 상태 신호로 사용한다.

유지형 프로세스는 SSH 실행 세션이 살아 있으면 실행 중으로 보고, 세션이 끊기거나 명령이 종료되면 stdout/stderr와 exit status를 기준으로 상태를 판단한다.

보조 확인 명령은 앱 재시작, 상태 불일치, 수동 개입 이후처럼 실행 세션만으로 판단하기 어려울 때만 사용한다.

예시:

```bash
# 수집 서버에서 dpp pod 확인
kubectl -n default get pods

# 수집 서버에서 port-forward 프로세스 확인
pgrep -af "kubectl.*port-forward.*18818"

# dpp pod 내부 collector 확인
kubectl -n default exec ${DPP_POD} -- pgrep -af run_srs_consumer

# dpp pod 내부 file server 확인
kubectl -n default exec ${DPP_POD} -- pgrep -af 02_recursive_http_file_server.py

# 수집 서버 route 확인
ip route show
ip route get ${DOWNLOAD_HOST}
```

이 명령들은 필요할 때만 사용하는 보조 확인용이며, 구현 시 allowlist에 넣고 임의 명령 입력은 허용하지 않는다.

## 환경 설정 예시

MVP env 예시:

```env
COLLECTOR_HOST=...
COLLECTOR_USER=...
COLLECTOR_PASSWORD=...
COLLECTOR_SUDO_PASSWORD=...
COLLECTOR_POD_NAME_PATTERN=dpp
DOWNLOAD_HOST=...
DOWNLOAD_USER=...
DOWNLOAD_PASSWORD=...
DOWNLOAD_ROOT_DIR=...
```

정책:

- MVP에서는 별도 admin token 없이 내부망 접근 전제로 시작
- SSH/sudo password는 화면과 로그에 출력하지 않음
- 로그 마스킹 대상: password, full SSH URL, 민감 경로
- backend는 allowlist action만 실행
- 사용자가 shell command를 자유 입력하는 기능은 만들지 않음
- `.env`는 git에 포함하지 않음

## 로그와 상태 저장

MVP 추천:

- JSONL 파일 기반 이벤트 로그
- run 상태 JSON 파일
- 단계별 stdout/stderr 로그 파일

예상 구조:

```text
runs/{run_id}/state.json
runs/{run_id}/events.jsonl
runs/{run_id}/logs/{step_id}.log
```

SQLite는 검색/필터/이력 조회가 필요해질 때 도입한다.

## 확정된 세부 정책

### SSH 세션/명령 상태 UI 매핑

- SSH 세션 연결 중: `running`
- exit code 0: `completed`
- exit code != 0: `failed`
- SSH 연결 끊김: `needs_check`
- stderr 출력이 있지만 exit code 0: `completed_with_warning`

### 정리 실패 메시지

auto delete 실패 시:

- 실패 원인을 표시한다.
- `재시도`, `취소` 버튼을 제공한다.
- `재시도`: 같은 정리 명령을 다시 실행한다.
- `취소`: "직접 삭제하려면 취소 후 수동 처리하세요." 안내를 표시한다.

### 원복 실패 메시지

port-forward 또는 route off 실패 시:

- 사용자가 직접 실행할 원복 명령을 메시지 박스에 표시한다.
- 사용자가 수동 처리한 뒤 누를 수 있는 `상태 재확인` 버튼을 제공한다.

route off 메시지 예:

```text
원복 실패: route off

수집 서버에서 아래 명령을 직접 실행하세요.

sudo ip route del ${TRANSFER_SUBNET_1} via ${COLLECTOR_GATEWAY}
sudo ip route del ${TRANSFER_SUBNET_2} via ${COLLECTOR_GATEWAY}

직접 처리 후 [상태 재확인]을 눌러주세요.
```

### 스크립트 배포 overwrite 정책

- 대상 위치에 server/downloader 파일이 있어도 repo 파일을 우선한다.
- MVP에서는 항상 overwrite한다.
- overwrite 결과는 배포 로그에 남긴다.
- 백업은 MVP 범위에서 제외한다.

## 남은 결정사항

1. 내부망 검증 후 조정
   - 실제 SSH/pod 명령 출력 확인
   - file server/downloader 실제 exit code와 stderr 패턴 확인
   - route/port-forward 실패 케이스 확인

## 로컬 관리 파일

- `DEVELOPMENT_STATUS.local.html`: 메인 채팅이 관리하는 개발 진행판. 배포 산출물이 아니라 진행 확인용 문서.
- `docs/existing-data-flow.html`: push 가능한 sanitized 기존 수동 흐름 참고 도식.
