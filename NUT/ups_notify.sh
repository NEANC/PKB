#!/bin/bash
# NUT UPS Push in ServerChan
SENDKEY="your_serverchan_sendkey"
API_URL="https://sctapi.ftqq.com/${SENDKEY}.send"

NOTIFY_TYPE="$NOTIFYTYPE"
UPS_HOST="PVE"

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

FINAL_CONTENT="
**UPS 主机**：${UPS_HOST}  
**通知类型**：${NOTIFY_TYPE}  
**消息内容**：${MSG_CONTENT}  
**触发时间**：$(date +'%Y-%m-%d %H:%M:%S')"

curl -s -X POST "${API_URL}" \
  --data-urlencode "title=${TITLE}" \
  --data-urlencode "desp=${FINAL_CONTENT}" \
  --connect-timeout 10 >> /var/log/nut_serverchan.log 2>&1

echo "[$(date +'%Y-%m-%d %H:%M:%S')] 触发${NOTIFY_TYPE}事件，推送标题：${TITLE}" >> /var/log/nut_serverchan.log