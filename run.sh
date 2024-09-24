#!/bin/bash
# ==================================
# リストア・マイグレーション・e2eテスト・負荷試験・採点の順で実施してくれるスクリプト。
# ==================================

check_job_existence() {
    local IS_EXISTS=$1
    local JOB_ID=$2

    if [[ "$IS_EXISTS" == true ]]; then
        echo -e "\n\n===================================================\n\n"
        echo -e "既に負荷試験のリクエストを受け取っています"
        echo -e "負荷試験が完了してから再度リクエストを行ってください"
        echo -e "負荷試験のステータスは下記コマンドで確認できます"
        echo -e "bash get_test_status.sh $JOB_ID"
        echo -e "\n\n===================================================\n\n"
        exit 0
    fi
}

# 負荷試験のリクエストが残っているか確認
if [[ $HOSTNAME == app-* ]]; then
    if [[ -f ./.da/.initBenchmarker ]]; then
        RESPONSE=$(curl -s -G https://benchmarker.ftt2407.dabaas.net/api/check-existence --data-urlencode "teamId=$HOSTNAME")

        IS_EXISTS=$(echo "$RESPONSE" | jq -r '.isExists')
        JOB_ID=$(echo "$RESPONSE" | jq -r '.jobId')

        check_job_existence $IS_EXISTS $JOB_ID
    fi
fi

# リストア
(cd webapp && bash ./restore_and_migration.sh)
if [ $? -ne 0 ]; then
    echo -e "採点フローを中断します。"
    exit 1
fi

# e2eテスト
if [[ $HOSTNAME == app-* ]]; then
    (cd webapp/e2e)
    datetime=$(date +%s)
    docker run --name e2e --rm --network webapp-network \
        -v $(pwd)/tokens:/usr/src/e2e/tokens \
        -e BASE_URL="https://${HOSTNAME}.ftt2407.dabaas.net" \
        -it hirouniv2409.azurecr.io/e2e:production \
        bash ./run_e2e_test.sh $datetime
    # 署名付きタイムスタンプをBase64にエンコード
    timestamp=$(openssl base64 -in ./tokens/${datetime}.bin | tr -d '\n')
else
    (cd webapp/e2e && bash ./run_e2e_test.sh)
fi

if [ $? -ne 0 ]; then
    echo -e "採点フローを中断します。"
    exit 1
fi

# 負荷試験 & 採点開始
if [[ $HOSTNAME != app-* ]]; then
    (cd benchmarker && bash ./run_k6_and_score.sh)
    if [ $? -ne 0 ]; then
        echo -e "採点フローを中断します。"
        exit 1
    fi
    # CPU使用率をリセットするためコンテナを再起動
    echo "バックエンドサーバのCPU使用率をリセットするためにコンテナを再起動します"
    docker compose -f webapp/docker-compose.local.yml restart backend
    exit 0
fi

echo "負荷試験を開始するためのリクエストを送信します。"

COMMIT_ID=$(git rev-parse HEAD)
data="{\"teamId\":\"$HOSTNAME\", \"commitId\":\"$COMMIT_ID\", \"datetime\":\"$datetime\", \"timestamp\":\"$timestamp\"}"

RESPONSE=$(curl -s -X POST https://benchmarker.ftt2407.dabaas.net/api/queuing_trigger \
    -H "Content-Type: application/json" \
    -d "$data")
JOB_ID=$(echo "$RESPONSE" | jq -r '.jobId' 2>/dev/null)

if [ -z "$JOB_ID" ] || [ "$JOB_ID" = "null" ]; then
    echo -e "\n\n===================================================\n\n"
    echo -e "負荷試験のリクエストに失敗しました。メンターに報告してください。"
    echo $RESPONSE
    echo -e "\n\n===================================================\n\n"
    exit 1
fi

IS_EXISTS=$(echo "$RESPONSE" | jq -r '.isExists' 2>/dev/null)
check_job_existence $IS_EXISTS $JOB_ID

touch ./.da/.initBenchmarker
echo -e "\n\n===================================================\n\n"
echo -e "負荷試験のリクエストに成功しました。"
echo -e "ジョブID: $JOB_ID"
echo -e "上記のジョブIDをもとに負荷試験のステータスを確認できます"
echo -e "bash get_test_status.sh $JOB_ID"
echo -e "\n\n===================================================\n\n"