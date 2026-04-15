#!/bin/bash

# PocketID GeoLite2 数据库下载脚本
# 脚本会下载 GeoLite2-City.mmdb 数据库文件到 pocket-id/data 目录下
# 使用说明：
# 1. 进入PocketID文件夹：cd PocketID
# 2. 下载脚本：wget https://raw.githubusercontent.com/NEANC/PKB/main/Docker-Compose/PocketID/download_geolite2.sh
# 3. 赋予执行权限：chmod +x download_geolite2.sh
# 4. 运行脚本：bash download_geolite2.sh ；脚本会自动下载 GeoLite2-City.mmdb 文件到 pocket-id/data/ 目录下
# 5. 设置计划任务：
##  crontab -e
##  0 3 * * * /bin/bash /download_geolite2.sh >> /var/log/geolite2.log 2>&1

# 自动获取脚本所在目录
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# 目标文件夹：自动拼接 pocket-id/data
TARGET_DIR="${SCRIPT_DIR}/data"
TARGET_FILE="${TARGET_DIR}/GeoLite2-City.mmdb"

# 下载地址
PRIMARY_URL="https://ghfast.top/github.com/P3TERX/GeoLite.mmdb/releases/latest/download/GeoLite2-City.mmdb"
BACKUP_URL="https://github.com/P3TERX/GeoLite.mmdb/raw/download/GeoLite2-City.mmdb"

# 日志输出
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 确保 data 目录存在
mkdir -p "${TARGET_DIR}"

# 下载函数（wget -q 静默模式）
download() {
    local url="$1"
    log "正在下载: $url"
    wget -q --timeout=60 --tries=3 -O "${TARGET_FILE}.tmp" "$url"

    if [ $? -eq 0 ] && [ -s "${TARGET_FILE}.tmp" ]; then
        mv -f "${TARGET_FILE}.tmp" "${TARGET_FILE}"
        return 0
    else
        rm -f "${TARGET_FILE}.tmp"
        return 1
    fi
}

# 主逻辑
if download "${PRIMARY_URL}"; then
    log "主链接下载完成"
elif download "${BACKUP_URL}"; then
    log "备用链接下载完成"
else
    log "下载失败"
    exit 1
fi

log "文件已保存到: ${TARGET_FILE}"
