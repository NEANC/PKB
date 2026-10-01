#!/bin/bash
# =============================================================
# Git 镜像加速节点卸载脚本
# 版本: 1.0
# 功能:
#   - 停止并移除 git-daemon systemd 服务
#   - 删除同步脚本、access-hook、hosts 刷新脚本
#   - 删除配置、镜像仓库、日志
#   - 清理 git 用户与 root 的 cron 任务
#   - 可选清理 /etc/hosts 中的 GitHub520 段
#   - 可选删除 git 用户
# =============================================================
set -uo pipefail

# ---------- 默认配置 ----------
MIRROR_ROOT="/srv/git-mirror"
CONF_DIR="/etc/git-mirror"
INSTALL_PATHS_FILE="${CONF_DIR}/install.paths"
LOG_DIR="/var/log/git-mirror"
SYNC_SCRIPT="/usr/local/bin/git-mirror-sync.sh"
HOOK_SCRIPT="/usr/local/bin/git-access-hook.sh"
HOSTS_SCRIPT="/usr/local/bin/update-github-hosts.sh"
SERVICE_FILE="/etc/systemd/system/git-daemon.service"
LOCK_FILE="/var/lock/git-mirror-sync.lock"
GIT_USER="git"

# ---------- 行为开关 ----------
ASSUME_YES="no"           # --yes 跳过所有确认
REMOVE_USER="no"          # --remove-user 删除 git 用户
CLEAN_HOSTS="yes"         # --keep-hosts 关闭
CLEAN_DATA="yes"          # --keep-data 关闭

# ---------- 颜色 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[FAIL]${NC} $*" >&2; }

# ---------- 使用说明 ----------
usage() {
    cat <<EOF
用法: $0 [选项]

默认行为（未指定选项时）:
  - 停止并移除 git-daemon 服务
  - 删除所有脚本、配置、镜像、日志
  - 清理 git 用户与 root 的 cron 任务
  - 清理 /etc/hosts 中的 GitHub520 段
  - 保留 git 系统用户（需显式 --remove-user 才删除）

选项:
  --yes                  跳过所有交互确认（危险，用于自动化）
  --remove-user          同时删除 git 系统用户
  --keep-user            保留 git 用户（默认行为，显式声明用）
  --keep-hosts           不修改 /etc/hosts
  --keep-data            保留镜像仓库与日志（仅移除服务/脚本/配置）
  -h, --help             显示帮助

示例:
  # 交互式卸载，删除一切
  $0

  # 完全静默卸载，包括用户
  $0 --yes --remove-user

  # 只停服务与脚本，保留数据和用户
  $0 --keep-data --keep-user

  # 保留 hosts、镜像和日志，移除服务、脚本和配置
  $0 --keep-hosts --keep-data
EOF
    exit 0
}

# ---------- 解析参数 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --yes)              ASSUME_YES="yes"; shift ;;
        --remove-user)      REMOVE_USER="yes"; shift ;;
        --keep-user)        REMOVE_USER="no"; shift ;;
        --keep-hosts)       CLEAN_HOSTS="no"; shift ;;
        --keep-data)        CLEAN_DATA="no"; shift ;;
        -h|--help)          usage ;;
        *) error "未知参数: $1"; usage ;;
    esac
done

# ---------- 前置检查 ----------
[[ $EUID -ne 0 ]] && { error "请以 root 运行（或 sudo）"; exit 1; }

# 读取部署时记录的实际脚本路径；文件由部署脚本以 root 创建。
if [[ -f "$INSTALL_PATHS_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$INSTALL_PATHS_FILE"
fi
for path_var in SYNC_SCRIPT HOOK_SCRIPT HOSTS_SCRIPT; do
    path_value="${!path_var:-}"
    if [[ "$path_value" != /* || "$path_value" == *$'\n'* ]]; then
        error "安装路径配置无效：$path_var"
        exit 1
    fi
done

# ---------- 交互确认 ----------
confirm() {
    local msg="$1"
    if [[ "$ASSUME_YES" == "yes" ]]; then
        return 0
    fi
    read -r -p "$msg [y/N] " ans
    case "$ans" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------- 卸载摘要 ----------
info "========== Git 镜像节点卸载 =========="
echo "将执行以下操作："
echo "  - 停止并禁用 git-daemon 服务"
echo "  - 删除 unit 文件: $SERVICE_FILE"
echo "  - 删除同步脚本:   $SYNC_SCRIPT"
echo "  - 删除 access-hook: $HOOK_SCRIPT"
echo "  - 删除 hosts 脚本:  $HOSTS_SCRIPT"
echo "  - 删除配置目录:   $CONF_DIR"
[[ "$CLEAN_DATA" == "yes" ]] && echo "  - 删除镜像仓库:   $MIRROR_ROOT"
[[ "$CLEAN_DATA" == "yes" ]] && echo "  - 删除日志目录:   $LOG_DIR"
[[ "$CLEAN_DATA" == "no"  ]] && warn "  ↳ --keep-data：镜像仓库与日志将保留"
echo "  - 清理 git 与 root 的 cron 任务"
if [[ "$CLEAN_HOSTS" == "yes" ]]; then
    echo "  - 清理 /etc/hosts 中的 GitHub520 段"
else
    echo "  - 跳过 /etc/hosts 清理（--keep-hosts）"
fi
if [[ "$REMOVE_USER" == "yes" ]]; then
    warn "  - 删除 git 系统用户及其 home 目录"
else
    echo "  - 保留 git 系统用户"
fi
echo

if ! confirm "确认执行卸载？"; then
    info "已取消"
    exit 0
fi

# 在任何删除操作前获取同步锁，已有同步任务运行时不进行卸载。
if ! command -v flock >/dev/null 2>&1; then
    error "未找到 flock，无法安全确认同步状态，已中止卸载"
    exit 1
fi
if [[ -L "$LOCK_FILE" ]]; then
    error "同步锁文件不能是符号链接，已中止卸载"
    exit 1
fi
# 已有锁只读打开，避免共享目录的文件保护阻止 root 以创建方式打开。
# 缺失时排他创建，不覆盖其他进程刚创建的锁文件。
if [[ ! -e "$LOCK_FILE" ]]; then
    if ! (umask 022; set -o noclobber; : > "$LOCK_FILE"); then
        error "创建同步锁失败，已中止卸载"
        exit 1
    fi
fi
if [[ ! -f "$LOCK_FILE" || -L "$LOCK_FILE" ]]; then
    error "同步锁不是普通文件，已中止卸载"
    exit 1
fi
if ! exec 9<"$LOCK_FILE"; then
    error "读取同步锁失败，已中止卸载"
    exit 1
fi
if ! flock -n 9; then
    error "同步任务仍在运行，请等待其结束后重新卸载"
    exit 1
fi
ok "已获取同步锁，卸载期间阻止新的同步任务"

echo


# 1. 停止并移除 systemd 服务

info "[1/8] 处理 git-daemon 服务 ..."

if systemctl list-unit-files | grep -q "^git-daemon.service"; then
    if ! systemctl stop git-daemon; then
        error "停止 git-daemon 失败，已中止卸载"
        exit 1
    fi
    if ! systemctl disable git-daemon; then
        error "禁用 git-daemon 失败，已中止卸载"
        exit 1
    fi
    ok "已停止并禁用 git-daemon"
else
    info "git-daemon 服务未注册"
fi

if [[ -f "$SERVICE_FILE" ]]; then
    rm -f "$SERVICE_FILE"
    ok "已删除 $SERVICE_FILE"
fi

systemctl daemon-reload
systemctl reset-failed 2>/dev/null || true

# 只停止本部署的 systemd 服务，不操作其他 Git 服务进程。


# 2. 删除脚本文件

info "[2/8] 删除脚本文件 ..."

for f in "$SYNC_SCRIPT" "$HOOK_SCRIPT" "$HOSTS_SCRIPT"; do
    if [[ -f "$f" ]]; then
        rm -f "$f"
        ok "已删除 $f"
    else
        info "不存在: $f"
    fi
done


# 3. 删除锁文件

info "[3/8] 删除锁文件 ..."

if [[ -f "$LOCK_FILE" ]]; then
    info "同步锁已由卸载流程持有，清理完成后再删除锁文件"
else
    info "不存在: $LOCK_FILE"
fi


# 4. 清理 cron 任务

info "[4/8] 清理 cron 任务 ..."

# git 用户的 crontab
if id "$GIT_USER" >/dev/null 2>&1; then
    if crontab -u "$GIT_USER" -l 2>/dev/null | grep -qE "$SYNC_SCRIPT|$HOSTS_SCRIPT"; then
        if ! crontab -u "$GIT_USER" -l \
            | awk -v sync="$SYNC_SCRIPT" -v hosts="$HOSTS_SCRIPT" 'index($0, sync) == 0 && index($0, hosts) == 0' \
            | crontab -u "$GIT_USER" -; then
            error "清理 git 用户 cron 失败，已中止卸载"
            exit 1
        fi
        ok "已清理 git 用户的 cron"
    else
        info "git 用户无相关 cron"
    fi
else
    info "git 用户不存在，跳过"
fi

# root 的 crontab（hosts 刷新）
if crontab -l 2>/dev/null | grep -qE "$HOSTS_SCRIPT"; then
    if ! crontab -l \
        | awk -v hosts="$HOSTS_SCRIPT" 'index($0, hosts) == 0' \
        | crontab -; then
        error "清理 root 的 hosts 刷新 cron 失败，已中止卸载"
        exit 1
    fi
    ok "已清理 root 的 hosts 刷新 cron"
else
    info "root 无相关 cron"
fi


# 6. 清理 /etc/hosts

info "[6/8] 处理 /etc/hosts ..."

if [[ "$CLEAN_HOSTS" == "yes" ]]; then
    if grep -q "# GitHub520 Host Start" /etc/hosts 2>/dev/null; then
        # 备份
        cp -f /etc/hosts "/etc/hosts.bak.uninstall.$(date +%Y%m%d%H%M%S)"

        sed -i '/# GitHub520 Host Start/,/# GitHub520 Host End/d' /etc/hosts

        # 刷新 DNS 缓存
        if command -v resolvectl >/dev/null 2>&1; then
            resolvectl flush-caches >/dev/null 2>&1 || true
        elif command -v systemd-resolve >/dev/null 2>&1; then
            systemd-resolve --flush-caches >/dev/null 2>&1 || true
        elif command -v nscd >/dev/null 2>&1; then
            nscd restart >/dev/null 2>&1 || true
        fi

        ok "已清理 /etc/hosts 中的 GitHub520 段"
    else
        info "/etc/hosts 中无 GitHub520 段，跳过"
    fi
else
    info "跳过 /etc/hosts 清理（--keep-hosts）"
fi


# 7. 删除配置、镜像、日志

info "[7/8] 删除数据目录 ..."

if [[ -d "$CONF_DIR" ]]; then
    rm -rf "$CONF_DIR"
    ok "已删除 $CONF_DIR"
else
    info "不存在: $CONF_DIR"
fi

if [[ "$CLEAN_DATA" == "yes" ]]; then
    if [[ -d "$MIRROR_ROOT" ]]; then
        # 显示占用体积，便于用户确认
        size="$(du -sh "$MIRROR_ROOT" 2>/dev/null | awk '{print $1}')"
        info "镜像仓库体积: ${size:-未知}"
        rm -rf "$MIRROR_ROOT"
        ok "已删除 $MIRROR_ROOT"
    else
        info "不存在: $MIRROR_ROOT"
    fi

    if [[ -d "$LOG_DIR" ]]; then
        rm -rf "$LOG_DIR"
        ok "已删除 $LOG_DIR"
    else
        info "不存在: $LOG_DIR"
    fi
else
    info "保留镜像与日志（--keep-data）"
    [[ -d "$MIRROR_ROOT" ]] && info "  $MIRROR_ROOT 保留"
    [[ -d "$LOG_DIR" ]]    && info "  $LOG_DIR 保留"
fi


# 8. 处理 git 用户

info "[8/8] 处理 git 用户 ..."

if id "$GIT_USER" >/dev/null 2>&1; then
    if [[ "$REMOVE_USER" == "yes" ]]; then
        # git 用户可能由其他服务共享，存在运行中进程时拒绝删除。
        if pgrep -u "$GIT_USER" >/dev/null 2>&1; then
            error "git 用户仍有进程运行，拒绝删除用户；请确认其他服务的使用情况"
            exit 1
        fi

        if ! userdel -r "$GIT_USER"; then
            error "删除 git 用户失败，请手动检查；不会强制终止其他进程"
            exit 1
        fi
        if id "$GIT_USER" >/dev/null 2>&1; then
            error "删除 git 用户失败，可能仍被占用"
        else
            ok "已删除 git 用户"
        fi
    else
        info "保留 git 用户（如需删除，使用 --remove-user）"
    fi
else
    info "git 用户不存在，跳过"
fi


# 完成

echo
ok "========== 卸载完成 =========="
echo

# 定时任务和同步脚本清理后，删除仍由本进程持有的锁文件。
if ! rm -f -- "$LOCK_FILE"; then
    error "删除同步锁文件失败"
    exit 1
fi
ok "已删除同步锁文件"

# 残留检查
echo "残留检查："
residual=0
for path in "$SYNC_SCRIPT" "$HOOK_SCRIPT" "$HOSTS_SCRIPT" "$SERVICE_FILE" "$LOCK_FILE"; do
    if [[ -e "$path" ]]; then
        warn "  仍存在: $path"
        residual=1
    fi
done
[[ -d "$CONF_DIR" ]] && { warn "  仍存在: $CONF_DIR"; residual=1; }
[[ "$CLEAN_DATA" == "yes" && -d "$MIRROR_ROOT" ]] && { warn "  仍存在: $MIRROR_ROOT"; residual=1; }
[[ "$CLEAN_DATA" == "yes" && -d "$LOG_DIR" ]] && { warn "  仍存在: $LOG_DIR"; residual=1; }

if [[ "$residual" -eq 0 ]]; then
    ok "无残留，卸载干净"
else
    warn "存在残留项，请手动检查上面列出的路径"
fi

echo
info "如果之前配置了云安全组/防火墙，请手动关闭以下端口："
echo "  - Git 直连 TCP 端口（默认 9418；如部署时使用 --port，请关闭对应端口）"