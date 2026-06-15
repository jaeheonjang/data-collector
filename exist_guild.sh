# 기존 수동 데이터 수집/전송 흐름 가이드 (sanitized)
# 실제 값은 .env 또는 내부망 운영 환경에서 주입한다.
# 이 파일은 참고용 절차 문서이며, 그대로 실행하는 목적의 스크립트가 아니다.

# 수집 서버 접속
ssh ${COLLECTOR_USER}@${COLLECTOR_HOST}

# 터미널 1
# 포트포워딩 on - 세션 유지, 전체 완료 이후 종료
collector_pod=$(kubectl -n default get pods | grep "${COLLECTOR_POD_NAME_PATTERN}" | grep -v Evicted | awk '{print $1}')
kubectl -n default port-forward --address 0.0.0.0 \
    ${collector_pod} ${TRANSFER_PORT}:${TRANSFER_PORT}

# 터미널 2
ssh ${COLLECTOR_USER}@${COLLECTOR_HOST}

# 라우팅 on
sudo ip route add ${TRANSFER_SUBNET_1} via ${COLLECTOR_GATEWAY}
sudo ip route add ${TRANSFER_SUBNET_2} via ${COLLECTOR_GATEWAY}

# 수집 pod 접속
collector_pod=$(kubectl -n default get pods | grep "${COLLECTOR_POD_NAME_PATTERN}" | grep -v Evicted | awk '{print $1}')
kubectl -n default exec -it ${collector_pod} -- /bin/bash

cd /tmp

# 데이터 수집 loop -----------------------------------------------------------
# 데이터 수집 on - 단말에서 데이터가 들어오는지 확인 필요
nohup ./run_srs_consumer \
    --cell-id ${CELL_ID} \
    --poll-interval ${POLL_INTERVAL} \
    --slot-step ${SLOT_STEP} \
    --slot-count ${SLOT_COUNT} \
    --batch \
    > nohup.out 2>&1 & disown

# 파일 수 확인
# ls -l /tmp/out/srs_${CELL_ID}/ | wc -l
# 100ms 마다 파일 추가 확인
ls -l /tmp/out/srs_${CELL_ID}/
# 예시:
# -rw-r--r-- 1 root root ${FILE_SIZE} ${DATE_TEXT} ue_0_batch_${TIMESTAMP}.bin
# -rw-r--r-- 1 root root ${FILE_SIZE} ${DATE_TEXT} ue_0_batch_${TIMESTAMP_PLUS_100}.bin

# 용량 10G 넘는지 확인
du -sh /tmp/out/srs_${CELL_ID}/

# 데이터 수집 완료 시 server on - 세션 유지, 완료 후 종료
python3 ./02_recursive_http_file_server.py \
    --bind 0.0.0.0 \
    --port ${TRANSFER_PORT} \
    --rout-dir /tmp/out

# 데이터 정리
rm -rf out

# 데이터 수집 off
pkill -9 run_srs_consumer
# --------------------------------------------------------------------------

# 라우팅 off
sudo ip route del ${TRANSFER_SUBNET_1} via ${COLLECTOR_GATEWAY}
sudo ip route del ${TRANSFER_SUBNET_2} via ${COLLECTOR_GATEWAY}

# 터미널 3
ssh ${DOWNLOAD_USER}@${DOWNLOAD_HOST}

# 데이터 다운로드 준비
mkdir -p ${DOWNLOAD_ROOT_DIR}/${DOWNLOAD_DATE}
cp ${DOWNLOAD_ROOT_DIR}/${PREVIOUS_DOWNLOAD_DATE}/02_recursive_http_file_downloader.py \
    ${DOWNLOAD_ROOT_DIR}/${DOWNLOAD_DATE}/
cd ${DOWNLOAD_ROOT_DIR}/${DOWNLOAD_DATE}/

# 데이터 다운로드 loop --------------------------------------------------------
mkdir ${TEST_NAME}

# 데이터 다운로드 on - 완료되면 종료
python3 ./02_recursive_http_file_downloader.py \
    --base-url http://${COLLECTOR_HOST}:${TRANSFER_PORT} \
    --dest-dir ./${TEST_NAME} \
    --workers ${WORKERS}
# --------------------------------------------------------------------------
