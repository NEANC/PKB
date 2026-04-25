#!/bin/bash
# NUT UPS Push in DingTalk (With Sign)

# 加签密钥
DINGTALK_SECRET="dingtalk_secret"
DINGTALK_ACCESS_TOKEN="dingtalk_access_token"

# URL 拼接
API_URL="https://oapi.dingtalk.com/robot/send?access_token=${DINGTALK_ACCESS_TOKEN}"
NOTIFY_TYPE="$NOTIFYTYPE"
UPS_HOST="PVE"

# 事件消息配置
case "${NOTIFY_TYPE}" in
    ONLINE)
        TITLE="✅ 市电恢复"
        MSG_CONTENT="市电恢复，UPS 已退出电池模式"
        ;;
    ONBATT)
        TITLE="⚠️ 供电切换"
        MSG_CONTENT="市电中断，UPS 已切换为电池供电"
        ;;
    LOWBATT)
        TITLE="🔋 低电量警告"
        MSG_CONTENT="UPS 电池电量低，即将关机"
        ;;
    FSD)
        TITLE="🚨 强制关机"
        MSG_CONTENT="检测到 UPS 低电量/通信异常，开始关机"
        ;;
    SHUTDOWN)
        TITLE="💻 系统关机中"
        MSG_CONTENT="已开始执行关机流程，请等待关机完成"
        ;;
    *)
        TITLE="❓ 未知 UPS 事件"
        MSG_CONTENT="收到未知的 UPS 通知类型：${NOTIFY_TYPE}，请检查 NUT 配置"
        ;;
esac

# 构造消息内容（适配钉钉 Markdown 格式）
FINAL_CONTENT="**UPS 主机**：${UPS_HOST}  
**通知类型**：${NOTIFY_TYPE}  
**消息内容**：${MSG_CONTENT}  
**触发时间**：$(date +'%Y-%m-%d %H:%M:%S')"

# -------------------------- 钉钉加签核心逻辑 --------------------------
# 1. 生成毫秒级时间戳
timestamp=$(date +%s%3N)

# 2. 构造签名串（timestamp + "\n" + secret）
sign_string="${timestamp}\n${DINGTALK_SECRET}"

# 3. 计算签名（HmacSHA256 + Base64 + URL编码）
sign=$(echo -ne "${sign_string}" | openssl dgst -sha256 -hmac "${DINGTALK_SECRET}" -binary | openssl base64 | tr -d '\n' | sed 's/+/%2B/g; s/\//%2F/g; s/=/%3D/g')

# 4. 构造最终请求 URL（含 timestamp 和 sign）
FINAL_API_URL="${API_URL}&timestamp=${timestamp}&sign=${sign}"

# -------------------------- 发送钉钉消息 --------------------------
# 构造钉钉 Markdown 格式 JSON
JSON_DATA=$(cat <<EOF
{
  "msgtype": "markdown",
  "markdown": {
    "title": "${TITLE}",
    "text": "### ${TITLE}\n\n${FINAL_CONTENT//$'\n'/\\n}"
  }
}
EOF
)

# 发送请求并记录日志
curl -s -X POST "${FINAL_API_URL}" \
  -H "Content-Type: application/json" \
  -d "${JSON_DATA}" \
  --connect-timeout 10 >> /var/log/nut_dingtalk.log 2>&1

echo "[$(date +'%Y-%m-%d %H:%M:%S')] 触发${NOTIFY_TYPE}事件，推送标题：${TITLE}" >> /var/log/nut_dingtalk.log