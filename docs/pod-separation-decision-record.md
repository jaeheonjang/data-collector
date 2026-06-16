# Pod 분리 방안 도출 과정

작성일: 2026-06-16

## 1. 목적

기존 Pod A는 그대로 유지하면서, shared memory ringbuffer 데이터를 읽고 처리하는 consumer 역할을 별도 Pod로 분리하는 방안을 검토했다.

Pod 분리의 목적은 다음과 같다.

- Pod A 내부 구조와 배포 방식을 최대한 변경하지 않는다.
- Pod A 내부에서 consumer가 CPU 등 리소스를 사용하지 않도록 분리한다.
- Pod A가 본래 작업에 리소스를 온전히 사용할 수 있게 한다.
- Pod A의 `/dev/shm`에 작성되는 ringbuffer 데이터를 실시간으로 읽어야 한다.
- 100ms마다 약 700KB 수준의 데이터가 생성되므로 지연과 누락 가능성을 최소화해야 한다.

## 2. 핵심 제약

| 제약 | 의미 |
| --- | --- |
| Pod A 유지 | 기존 Helm chart, 기존 container 구성, 기존 writer 동작을 직접 수정하지 않는 방향을 우선한다. |
| 별도 작업 공간 | consumer를 Pod A 내부가 아니라 별도 Pod/작업 공간에서 실행하고 싶다. |
| 실시간 shm read | 파일화 이후 배치 처리보다, shm ringbuffer에 쓰인 데이터를 즉시 읽는 구조가 필요하다. |
| 리소스 분리 | Pod A CPU/메모리를 consumer 처리에 쓰지 않게 하고 싶다. |
| 기존 consumer protocol 유지 | ringbuffer read pointer, sequence, partial frame 방지 등 기존 읽기 규칙을 유지해야 한다. |

## 3. 검토 흐름 요약

처음에는 Kubernetes 관점에서 가장 일반적인 구조부터 검토했다.

1. 같은 Pod 안에 sidecar container 추가
2. shared memory를 Kubernetes volume으로 공유
3. Pod 간 gRPC/NATS/Kafka/Redis/PVC 같은 전달 계층 사용
4. Pod A를 변경하지 않고 기존 `/dev/shm`을 외부 Pod에서 직접 접근
5. `/proc/<PID>/root/dev/shm` 경로를 이용한 접근 방식 검토
6. 직접 hostPath mount 실패 후, privileged Pod에서 host `/proc`를 mount하고 runtime 접근하는 방식으로 정리

## 4. 초기 제안: sidecar container 방식

초기에는 sidecar 방식이 가장 자연스러운 Kubernetes 패턴으로 검토되었다.

```text
Pod A
  writer container
    /dev/shm 또는 memory volume에 ringbuffer write

  consumer sidecar container
    같은 Pod 내부에서 shared volume 또는 shared IPC를 통해 ringbuffer read
```

### 장점

- Kubernetes에서 같은 Pod 내부 container는 같은 lifecycle과 scheduling 단위를 가진다.
- `emptyDir.medium: Memory` 같은 tmpfs volume을 두 container가 함께 mount할 수 있다.
- 서로 다른 Pod 간 `/dev/shm` 접근보다 훨씬 정석적인 구조다.
- network hop 없이 memory 기반 read가 가능하다.

### 제외한 이유

- Pod A를 그대로 유지해야 한다는 제약과 충돌한다.
- 기존 Helm chart와 Pod spec에 sidecar, volumeMount, volume 정의를 추가해야 한다.
- consumer가 여전히 Pod A와 같은 Pod 리소스 범위 안에서 동작하게 된다.
- 목적 중 하나였던 “Pod A가 리소스를 온전히 사용하도록 consumer를 분리”하는 조건을 충분히 만족하지 못한다.

## 5. 일반적인 Pod 간 전달 대안

초기 검토에서는 shared memory 직접 접근보다 Kubernetes 친화적인 전달 계층도 검토했다.

| 방식 | 장점 | 제외 또는 보류 이유 |
| --- | --- | --- |
| gRPC streaming | Pod 간 실시간 전달에 자연스럽고 구현이 명확하다. | Pod A writer 또는 consumer 구조 변경이 필요하다. ack/retry/checkpoint를 직접 설계해야 한다. |
| NATS JetStream | ack, replay, durable consumer가 가능하고 Kafka보다 가볍다. | 별도 메시징 인프라와 publish 로직 추가가 필요하다. |
| Kafka | 장기 보존, 재처리, consumer group에 강하다. | 운영 복잡도가 높고 현재 목적에는 과할 수 있다. |
| Redis | 최신 데이터 공유나 pub/sub 구조가 단순하다. | 모든 chunk 보존, 순서 보장, 재처리에는 약하다. |
| PVC/RWX | 파일 기반 계약에는 잘 맞는다. | shm ringbuffer 실시간 read 목적과 다르고, partial write/rename/lock 정책이 필요하다. |

이 대안들은 구조적으로는 더 Kubernetes 친화적이지만, 현재 조건에서는 Pod A 변경 또는 별도 인프라 추가가 필요하다. 따라서 “Pod A를 그대로 유지하면서 shm 데이터를 읽는다”는 목표에는 즉시 맞지 않았다.

## 6. Pod 간 shared memory 직접 접근 검토

서로 다른 Kubernetes Pod가 기존 Pod의 `/dev/shm`, POSIX shared memory, SysV shared memory에 직접 접근하는 방식은 일반적인 Kubernetes 패턴이 아니다.

Pod는 기본적으로 격리된 namespace와 lifecycle을 가진다. Docker에서는 `--ipc=container:<container>` 같은 방식으로 특정 container의 IPC namespace에 붙는 모델을 생각할 수 있지만, Kubernetes에서는 임의의 새 Pod가 기존 Pod의 IPC namespace에 붙는 구조가 일반적이지 않다.

`hostIPC: true` 같은 선택지도 있지만, Node IPC namespace 공유는 보안 격리를 크게 약화시키므로 일반적인 운영 대안으로 보기 어렵다.

## 7. `/proc/<PID>/root/dev/shm` 접근 아이디어

Pod A를 변경하지 않고 별도 Pod에서 shm 데이터를 읽기 위해, Linux procfs를 이용한 접근을 검토했다.

Linux에서 container는 host kernel 위에서 namespace와 cgroup으로 격리된 프로세스다. 따라서 Pod A 안의 container도 Node에서 보면 하나 이상의 Linux process이며 host 기준 PID를 가진다.

host의 `/proc/<PID>/root`는 해당 PID 프로세스가 자신의 root filesystem으로 보고 있는 경로를 가리킨다. 그래서 host에서 `/proc/<PID>/root/dev/shm`을 따라가면, 그 프로세스가 container 내부에서 `/dev/shm`으로 보고 있는 경로에 접근할 수 있다.

즉 이 경로는 복사본이 아니라, Pod A container의 mount namespace와 root filesystem 관점으로 `/dev/shm`을 찾아 들어가는 우회 경로다.

## 8. 방식 1: 직접 hostPath mount

먼저 검토한 방식은 외부에서 Pod A의 host PID를 찾고, 해당 경로를 Pod B에 hostPath로 직접 mount하는 방식이었다.

```yaml
volumes:
  - name: pod-a-shm
    hostPath:
      path: /proc/<POD_A_PID>/root/dev/shm
      type: Directory
```

### 기대한 장점

- Pod B가 host `/proc` 전체를 볼 필요가 없다.
- Pod B를 privileged 없이 실행할 가능성이 있다.
- Pod B consumer는 `/pod-a-shm`만 읽으면 되므로 구현이 단순하다.

### 실제 결과

직접 hostPath mount 테스트에서 container 생성 단계가 실패했다.

```text
Error: failed to create containerd task: failed to create shim task:
OCI runtime create failed: runc create failed:
error mounting "/proc/<PID>/root/dev/shm" to rootfs at "/dpp/shm":
mount /proc/<PID>/root/dev/shm:/dpp/shm (...), flags: 0x5001:
invalid argument
```

### 판단

`/proc/<PID>/root/dev/shm`는 일반적인 정적 host directory와 성격이 다르다. 특정 프로세스의 root와 mount namespace를 통해 해석되는 procfs 기반 경로이며, 그 안쪽의 `/dev/shm`은 tmpfs/mount namespace와 연결된다. 이 경로를 container runtime이 새 container rootfs 안으로 bind mount하는 과정에서 안정적으로 처리하지 못할 수 있다.

따라서 직접 hostPath mount 방식은 현재 환경에서 보류한다.

## 9. 방식 2: privileged Pod + host `/proc` mount

직접 hostPath mount가 실패한 뒤, 현재 방향은 Pod B에서 host `/proc`를 read-only로 mount하고 runtime에 대상 PID 경로를 직접 읽는 방식으로 정리했다.

```text
Pod B
  privileged: true
  hostPID: true
  /proc -> /host/proc 로 readOnly mount

consumer
  Pod A container PID 탐색
  /host/proc/<PID>/root/dev/shm/<ringbuffer-file> read
  필요 시 /dev/shm/<ringbuffer-file> symlink 생성
```

### 선택 이유

- Pod A를 수정하지 않는다.
- consumer를 Pod A 외부의 별도 Pod/작업 공간으로 분리할 수 있다.
- Pod A 내부 consumer 리소스 사용을 제거할 수 있다.
- shm ringbuffer 데이터를 실시간에 가깝게 읽을 수 있다.
- Pod A 재시작 시 PID를 다시 찾아 복구하는 자동화 여지가 있다.

### 단점과 주의점

- `privileged: true`, `hostPID: true`, host `/proc` mount가 필요하므로 보안 리스크가 크다.
- Pod A와 Pod B는 같은 Node에 있어야 한다.
- Pod A container 재시작 시 host PID가 바뀌므로 PID 재탐색 로직이 필요하다.
- ringbuffer read protocol은 기존 consumer와 동일하게 지켜야 한다.

## 10. 최종 의사결정

현재 제약에서의 결론은 다음과 같다.

| 항목 | 판단 |
| --- | --- |
| sidecar 방식 | Kubernetes 관점에서는 가장 자연스럽지만 Pod A 유지와 리소스 분리 목적에 맞지 않아 제외 |
| gRPC/NATS/Kafka/Redis/PVC | 장기적으로는 더 표준적이나 Pod A 변경 또는 별도 인프라가 필요해 즉시 적용 제외 |
| `/proc/<PID>/root/dev/shm` 직접 hostPath mount | 권한 축소 측면에서 매력적이었으나 runc `invalid argument`로 실패 |
| privileged Pod + host `/proc` mount | 현재 조건에서 Pod A를 유지하고 consumer를 분리하기 위한 현실적인 선택 |

## 11. Confluence용 한 문단 요약

Pod A를 변경하지 않고 consumer를 별도 작업 공간으로 분리하기 위해 여러 대안을 검토했다. 초기에는 Kubernetes에서 자연스러운 sidecar container와 memory `emptyDir` 공유 방식이 제안되었지만, 이는 Pod A spec 변경이 필요하고 consumer가 여전히 Pod A의 리소스 범위 안에서 동작하므로 “Pod A를 그대로 유지하고 리소스를 온전히 사용하게 한다”는 목적과 맞지 않았다. gRPC, NATS, Kafka, Redis, PVC 같은 Pod 간 전달 구조도 검토했지만 Pod A 변경 또는 별도 인프라 추가가 필요했다. 이후 Pod A container의 host PID를 기준으로 `/proc/<PID>/root/dev/shm`에 접근하는 방식을 검토했고, 직접 hostPath mount는 runc `invalid argument`로 실패했다. 최종적으로는 별도 Pod를 privileged로 실행하고 host `/proc`를 read-only mount한 뒤, runtime에 Pod A PID를 찾아 `/host/proc/<PID>/root/dev/shm` 경로에서 ringbuffer 데이터를 읽는 방향으로 정리했다.
