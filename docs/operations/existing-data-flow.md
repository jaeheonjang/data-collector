# 기존 데이터 수집 타임라인

작성일: 2026-06-16

원본: `docs/operations/exist_guild.sh`

이 문서는 기존에 사람이 터미널을 나눠 수행하던 수동 데이터 수집/전송 흐름을 Confluence 이관용 Markdown으로 정리한 것이다. 민감한 내부 값은 placeholder로 치환한다.

## 핵심 흐름

```mermaid
flowchart TD
  start(["시작"])

  subgraph T1["터미널 1: 수집 서버 세션"]
    t1ssh["수집 서버 SSH 접속<br/>ssh ${COLLECTOR_USER}@${COLLECTOR_HOST}"]
    pf_on["port-forward ON<br/>kubectl port-forward --address 0.0.0.0 ${collector_pod} ${TRANSFER_PORT}:${TRANSFER_PORT}<br/>세션 유지"]
    pf_off["port-forward OFF<br/>모든 test_N cycle 완료 후 종료"]
  end

  subgraph T2["터미널 2: 수집 서버 작업"]
    t2ssh["수집 서버 SSH 접속"]
    route_on["route ON<br/>sudo ip route add ${TRANSFER_SUBNET_1}<br/>sudo ip route add ${TRANSFER_SUBNET_2}"]
    pod_enter["수집 pod 진입<br/>kubectl exec -it ${collector_pod}<br/>cd /tmp"]
    collect["수집 시작<br/>nohup ./run_srs_consumer ... & disown<br/>/tmp/out에 데이터 write"]
    monitor["파일 수/용량 확인<br/>100ms 간격 파일 생성 확인<br/>10G 초과 주의"]
    server["HTTP file server ON<br/>02_recursive_http_file_server.py<br/>/tmp/out 제공"]
    cleanup["정리<br/>rm -rf out<br/>pkill -9 run_srs_consumer"]
    route_off["route OFF<br/>sudo ip route del ..."]
  end

  subgraph T3["터미널 3: 다운로드 클라이언트"]
    t3ssh["다운로드 클라이언트 SSH 접속<br/>ssh ${DOWNLOAD_USER}@${DOWNLOAD_HOST}"]
    prepare["다운로드 준비<br/>날짜 디렉터리 생성<br/>downloader script 복사<br/>test directory 생성"]
    wait_collect["수집 완료 대기"]
    wait_server["file server 준비 확인"]
    download["다운로드 실행<br/>02_recursive_http_file_downloader.py<br/>--base-url http://${COLLECTOR_HOST}:${TRANSFER_PORT}<br/>--workers ${WORKERS}"]
    done["전송 완료"]
  end

  start --> t1ssh --> pf_on
  start --> t2ssh --> route_on --> pod_enter
  start --> t3ssh --> prepare

  pod_enter --> collect --> monitor --> server
  prepare --> wait_collect --> wait_server --> download --> done
  server --> wait_server
  download --> cleanup
  cleanup --> more{"다음 테스트 있음?"}
  more -- "yes: test_N+1" --> collect
  more -- "no" --> route_off --> pf_off --> finish(["완료"])
```

## 수동 절차를 웹앱 action으로 재구성

| 수동 터미널 기준 | 웹앱 action 기준 |
| --- | --- |
| 터미널 1 port-forward 유지 | 전송 준비 action의 하위 단계 |
| 터미널 2 route on/off | 전송 준비/원복 action의 하위 단계 |
| 터미널 2 수집 시작/중지 | 수집 action |
| 터미널 2 file server 실행 | 전송 action 내부 자동 실행 |
| 터미널 3 downloader 실행 | 전송 action 내부 자동 실행 |
| 터미널 2 정리 | 전송 성공 후 후처리 또는 사용자 선택 |

## 반복 cycle

```mermaid
flowchart LR
  cycle["test_N cycle"] --> collect["수집"]
  collect --> transfer["전송<br/>route + port-forward + server + downloader"]
  transfer --> cleanup["정리"]
  cleanup --> next{"다음 test?"}
  next -- "있음" --> cycle2["test_N+1 cycle"]
  cycle2 --> collect
  next -- "없음" --> rollback["원복<br/>port-forward off + route off"]
```

## 구현 반영 포인트

- 웹 UI는 터미널 1/2/3을 그대로 노출하지 않고 수집/전송/정리/원복 action으로 제공한다.
- port-forward와 route는 전송 action의 앞단과 뒷단으로 묶는다.
- file server와 downloader는 순서가 있지만 같은 전송 흐름으로 본다.
- server/downloader 파일은 내부 위치에서 복사하지 않고 repo의 `scripts/transfer/`에서 대상 환경으로 배포하는 방향을 선호한다.
- 실제 내부망 파일은 개발 환경에 없을 수 있으므로 웹앱 시작 시 존재 여부를 체크한다.
