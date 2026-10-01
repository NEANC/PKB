#!/bin/bash
# =============================================================
# Git 镜像加速节点自动化部署脚本
# 版本: 1.1
# 功能:
#   - 创建 git 用户与目录结构
#   - 安装 git-mirror-sync.sh（代理 → 直连 → SSH 三级回退）
#   - 安装 update-github-hosts.sh（自动刷新 GitHub hosts）
#   - 安装 git-access-hook.sh（屏蔽 owner/repo 完整路径）
#   - 配置 git-daemon systemd 服务
#   - 注册 cron 定时任务（同步 + hosts 刷新）
# =============================================================
set -euo pipefail

# ---------- 默认配置 ----------
REPOS=""
REPOS_FILE=""
GITHUB_TOKEN=""
PROXY_URL=""
ENABLE_SSH="no"
SSH_KEY="/home/git/.ssh/id_ed25519_mirror"
CRON_SCHEDULE="0 * * * *"
ENABLE_CRON="yes"
GIT_PORT="9418"
LISTEN_ADDRESS="0.0.0.0"
MIRROR_ROOT="/srv/git-mirror"
CONF_DIR="/etc/git-mirror"
LOG_DIR="/var/log/git-mirror"
SCRIPTS_DIR="/usr/local/bin"
SYNC_SCRIPT="${SCRIPTS_DIR}/git-mirror-sync.sh"
HOOK_SCRIPT="${SCRIPTS_DIR}/git-access-hook.sh"
HOSTS_SCRIPT="${SCRIPTS_DIR}/update-github-hosts.sh"
HOSTS_LOG="/var/log/git-mirror/hosts.log"
HOSTS_CRON="0 3 * * *"
HOSTS_URL="https://cdn.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts"
HOSTS_URL_FALLBACK="https://raw.hellogithub.com/hosts"
ENABLE_HOSTS_UPDATE="yes"
SERVICE_FILE="/etc/systemd/system/git-daemon.service"
GIT_USER="git"

# ---------- 颜色输出 ----------
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

必选（两者选一）:
  --repos "owner/repo[,owner/repo2]"  简单仓库列表（完整镜像）
  --repos-file /path/repos.list        按行配置仓库和分支

仓库文件格式:
  owner/repo                          完整镜像（所有 refs）
  owner/repo master                   只同步一个分支
  owner/repo master,next,stable       只同步多个分支

可选:
  --github-token "github_pat_xxx"    GitHub Fine-grained PAT（提高限额）
  --proxy "socks5h://ip:port"        代理地址（留空禁用）
  --ssh yes|no                       是否启用 SSH 回退（默认 no）
  --ssh-key /path/to/key             SSH 私钥路径
  --cron "0 * * * *"                 同步 cron 表达式（默认每小时）
  --no-cron                           不配置同步和 hosts cron
  --scripts-dir /usr/local/bin       生成脚本安装目录
  --port 9418                        Git 协议直连端口（默认 9418）
  --listen 0.0.0.0                   Git 监听地址（默认所有 IPv4 接口）
  --hosts yes|no                     是否启用自动刷新 hosts（默认 yes）
  --hosts-cron "0 3 * * *"           hosts 刷新 cron 表达式
  --hosts-url "https://..."          hosts 主数据源 URL
  -h, --help                         显示帮助

示例:
  $0 --repos "git/git,LmeSzinc/AzurLaneAutoScript" \\
     --github-token "github_pat_xxx" \\
     --port 9418
EOF
    exit 0
}

# ---------- 参数解析 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --repos)          REPOS="${2:?--repos 缺少参数}"; shift 2 ;;
        --repos-file)     REPOS_FILE="${2:?--repos-file 缺少参数}"; shift 2 ;;
        --github-token)   GITHUB_TOKEN="$2"; shift 2 ;;
        --proxy)          PROXY_URL="$2"; shift 2 ;;
        --ssh)            ENABLE_SSH="$2"; shift 2 ;;
        --ssh-key)        SSH_KEY="$2"; shift 2 ;;
        --cron)           CRON_SCHEDULE="$2"; shift 2 ;;
        --no-cron)        ENABLE_CRON="no"; shift ;;
        --scripts-dir)    SCRIPTS_DIR="${2:?--scripts-dir 缺少参数}"; shift 2 ;;
        --port)           GIT_PORT="${2:?--port 缺少参数}"; shift 2 ;;
        --listen)         LISTEN_ADDRESS="${2:?--listen 缺少参数}"; shift 2 ;;
        --hosts)          ENABLE_HOSTS_UPDATE="$2"; shift 2 ;;
        --hosts-cron)     HOSTS_CRON="$2"; shift 2 ;;
        --hosts-url)      HOSTS_URL="$2"; shift 2 ;;
        -h|--help)        usage ;;
        *) error "未知参数: $1"; usage ;;
    esac
done

# ---------- 前置检查 ----------
[[ $EUID -ne 0 ]] && { error "请以 root 运行（或 sudo）"; exit 1; }

if [[ -z "$REPOS" && -z "$REPOS_FILE" ]]; then
    error "必须指定 --repos 或 --repos-file"
    exit 1
fi
if [[ -n "$REPOS" && -n "$REPOS_FILE" ]]; then
    error "--repos 与 --repos-file 不能同时使用"
    exit 1
fi
if [[ -n "$REPOS_FILE" && ! -f "$REPOS_FILE" ]]; then
    error "仓库配置文件不存在：$REPOS_FILE"
    exit 1
fi
if [[ "$SCRIPTS_DIR" != /* || "$SCRIPTS_DIR" == */ || "$SCRIPTS_DIR" == *$'\n'* ]]; then
    error "--scripts-dir 必须是绝对目录路径，且不能以 / 结尾"
    exit 1
fi
SYNC_SCRIPT="${SCRIPTS_DIR}/git-mirror-sync.sh"
HOOK_SCRIPT="${SCRIPTS_DIR}/git-access-hook.sh"
HOSTS_SCRIPT="${SCRIPTS_DIR}/update-github-hosts.sh"

if [[ ! "$GIT_PORT" =~ ^[0-9]{1,5}$ ]]; then
    error "--port 必须是 1 到 65535 的整数"
    exit 1
fi
GIT_PORT=$((10#$GIT_PORT))
if (( GIT_PORT < 1 || GIT_PORT > 65535 )); then
    error "--port 必须是 1 到 65535 的整数"
    exit 1
fi
if [[ -z "$LISTEN_ADDRESS" || "$LISTEN_ADDRESS" == *[!a-zA-Z0-9.:_-]* ]]; then
    error "--listen 必须是有效的监听地址，不能包含空白或控制字符"
    exit 1
fi

info "========== Git 镜像节点部署开始 =========="
info "仓库来源      : ${REPOS_FILE:-命令行参数}"
info "脚本目录      : $SCRIPTS_DIR"
info "定时任务      : $ENABLE_CRON${ENABLE_CRON:+（同步：$CRON_SCHEDULE）}"
info "Git 监听地址  : $LISTEN_ADDRESS"
info "Git 直连端口  : $GIT_PORT"
info "代理          : ${PROXY_URL:-（无）}"
info "SSH 回退      : $ENABLE_SSH"
info "cron 状态     : $ENABLE_CRON"
info "hosts 刷新    : $ENABLE_HOSTS_UPDATE（cron: $HOSTS_CRON）"
info "访问方式      : 客户端直接连接 git-daemon"
echo

# 1. 系统依赖
info "[1/9] 检查系统依赖 ..."

if ! command -v git >/dev/null 2>&1; then
    info "安装 git ..."
    if command -v apt >/dev/null 2>&1; then
        apt update -qq && apt install -y git curl
    elif command -v yum >/dev/null 2>&1; then
        yum install -y git curl
    else
        error "无法识别包管理器，请手动安装 git 和 curl"; exit 1
    fi
fi

if ! command -v curl >/dev/null 2>&1; then
    if command -v apt >/dev/null 2>&1; then
        apt install -y curl
    else
        yum install -y curl
    fi
fi

ok "系统依赖就绪"

# 2. 创建 git 用户
info "[2/9] 创建 git 用户 ..."

if id "$GIT_USER" >/dev/null 2>&1; then
    ok "用户 $GIT_USER 已存在"
else
    adduser --system --group --home "/home/$GIT_USER" "$GIT_USER"
    ok "已创建用户 $GIT_USER"
fi

# 3. 创建目录结构
info "[3/9] 创建目录结构 ..."

mkdir -p "$MIRROR_ROOT" "$CONF_DIR" "$LOG_DIR" "$SCRIPTS_DIR" "/var/lock"
mkdir -p "/home/$GIT_USER/.ssh"

chown -R "$GIT_USER:$GIT_USER" "$MIRROR_ROOT" "$CONF_DIR" "$LOG_DIR"
chown "$GIT_USER:$GIT_USER" "/home/$GIT_USER/.ssh"

chmod 755 "$MIRROR_ROOT" "$LOG_DIR"
chmod 750 "$CONF_DIR"
chmod 700 "/home/$GIT_USER/.ssh"

touch "/var/lock/git-mirror-sync.lock"
chown "$GIT_USER:$GIT_USER" "/var/lock/git-mirror-sync.lock"

ok "目录结构就绪"

# 4. 写入配置文件
info "[4/9] 写入配置文件 ..."

cat > "$CONF_DIR/mirror.env" <<EOF
PROXY_URL="$PROXY_URL"
GITHUB_TOKEN="$GITHUB_TOKEN"
ENABLE_SSH="$ENABLE_SSH"
SSH_KEY="$SSH_KEY"
EOF
chown "$GIT_USER:$GIT_USER" "$CONF_DIR/mirror.env"
chmod 600 "$CONF_DIR/mirror.env"

cat > "$CONF_DIR/install.paths" <<EOF
SCRIPTS_DIR="$SCRIPTS_DIR"
SYNC_SCRIPT="$SYNC_SCRIPT"
HOOK_SCRIPT="$HOOK_SCRIPT"
HOSTS_SCRIPT="$HOSTS_SCRIPT"
ENABLE_CRON="$ENABLE_CRON"
EOF
chown root:root "$CONF_DIR/install.paths"
chmod 640 "$CONF_DIR/install.paths"

if [[ -n "$REPOS_FILE" ]]; then
    cp -- "$REPOS_FILE" "$CONF_DIR/repos.list"
else
    : > "$CONF_DIR/repos.list"
    IFS=',' read -ra _repos <<< "$REPOS"
    for r in "${_repos[@]}"; do
        r="$(echo "$r" | xargs)"
        [[ -z "$r" ]] && continue
        printf '%s\n' "$r" >> "$CONF_DIR/repos.list"
    done
fi
chown "$GIT_USER:$GIT_USER" "$CONF_DIR/repos.list"
chmod 640 "$CONF_DIR/repos.list"

ok "配置文件写入完成"

# 5. 安装同步脚本
info "[5/9] 安装同步脚本 ..."

cat > "$SYNC_SCRIPT" <<'SYNC_SCRIPT_EOF'
#!/bin/bash
set -uo pipefail

ENV_FILE="/etc/git-mirror/mirror.env"
REPO_LIST="/etc/git-mirror/repos.list"
MIRROR_ROOT="/srv/git-mirror"
LOG_DIR="/var/log/git-mirror"
LOG_FILE="${LOG_DIR}/sync.log"
LOCK_FILE="/var/lock/git-mirror-sync.lock"

exec 9>"$LOCK_FILE"
flock -n 9 || { echo "[$(date '+%F %T')] 已有同步任务在运行，跳过"; exit 0; }

[ -f "$ENV_FILE" ] && source "$ENV_FILE"

PROXY_URL="${PROXY_URL:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
ENABLE_SSH="${ENABLE_SSH:-no}"
SSH_KEY="${SSH_KEY:-}"

mkdir -p "$LOG_DIR"

log() {
    local msg="[$(date '+%F %T')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

# 仅隐藏格式明确的正常引用更新行，其他输出及回车进度即时透传。
filter_fetch_output() {
    local char buffer="" at_start=yes candidate=no
    local new_ref='^[[:blank:]]\*[[:blank:]]+\[new (branch|tag|ref)\][[:blank:]]+[^[:space:]]+[[:blank:]]+->[[:blank:]]+[^[:space:]]+[[:blank:]]*$'
    local fast_forward='^[[:blank:]]+[[:xdigit:]]+\.\.[[:xdigit:]]+[[:blank:]]+[^[:space:]]+[[:blank:]]+->[[:blank:]]+[^[:space:]]+[[:blank:]]*$'
    local forced='^[[:blank:]]\+[[:blank:]]+[[:xdigit:]]+\.\.\.[[:xdigit:]]+[[:blank:]]+[^[:space:]]+[[:blank:]]+->[[:blank:]]+[^[:space:]]+[[:blank:]]+\(forced update\)[[:blank:]]*$'
    local deleted='^[[:blank:]]-[[:blank:]]+\[deleted\][[:blank:]]+\(none\)[[:blank:]]+->[[:blank:]]+[^[:space:]]+[[:blank:]]*$'
    local unchanged='^[[:blank:]]=[[:blank:]]+\[up to date\][[:blank:]]+[^[:space:]]+[[:blank:]]+->[[:blank:]]+[^[:space:]]+[[:blank:]]*$'
    local tag_update='^[[:blank:]]t[[:blank:]]+\[tag update\][[:blank:]]+[^[:space:]]+[[:blank:]]+->[[:blank:]]+[^[:space:]]+[[:blank:]]*$'
    while IFS= read -r -N 1 char; do
        if [ "$candidate" = yes ]; then
            if [ "$char" = $'\n' ]; then
                if [[ ! "$buffer" =~ $new_ref && ! "$buffer" =~ $fast_forward && ! "$buffer" =~ $forced && ! "$buffer" =~ $deleted && ! "$buffer" =~ $unchanged && ! "$buffer" =~ $tag_update ]]; then
                    printf '%s\n' "$buffer"
                fi
                buffer=""
                candidate=no
                at_start=yes
            elif [ "$char" = $'\r' ]; then
                # 回车刷新不是引用明细，不等待换行或进程结束。
                printf '%s\r' "$buffer"
                buffer=""
                candidate=no
                at_start=yes
            else
                buffer+="$char"
            fi
        elif [ "$at_start" = yes ] && [[ "$char" == ' ' || "$char" == $'\t' ]]; then
            candidate=yes
            buffer="$char"
        else
            printf '%s' "$char"
            if [[ "$char" == $'\n' || "$char" == $'\r' ]]; then
                at_start=yes
            else
                at_start=no
            fi
        fi
    done
    # 未以换行结束的内容原样保留，不猜测其是否为完整明细。
    printf '%s' "$buffer"
    return 0
}

# 先追加完整日志，再筛选终端展示；保留原命令的退出状态。
run_cmd() {
    "$@" 2>&1 | tee -a "$LOG_FILE" | filter_fetch_output
    return "${PIPESTATUS[0]}"
}

build_https_url() {
    local repo="$1"
    if [ -n "$GITHUB_TOKEN" ]; then
        echo "https://${GITHUB_TOKEN}@github.com/${repo}.git"
    else
        echo "https://github.com/${repo}.git"
    fi
}

build_ssh_url() { echo "git@github.com:${1}.git"; }

run_git() {
    local mode="$1"; shift
    local -a proxy_args=()
    local -a ssh_env=()
    case "$mode" in
        proxy)
            [ -z "$PROXY_URL" ] && return 1
            proxy_args=(-c "http.proxy=${PROXY_URL}" -c "https.proxy=${PROXY_URL}") ;;
        noproxy)
            proxy_args=(-c "http.proxy=" -c "https.proxy=") ;;
        ssh)
            [ "$ENABLE_SSH" != "yes" ] && return 1
            [ -z "$SSH_KEY" ] && return 1
            [ ! -f "$SSH_KEY" ] && return 1
            ssh_env=(GIT_SSH_COMMAND="ssh -i $SSH_KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new") ;;
        *) return 1 ;;
    esac
    env "${ssh_env[@]}" git "${proxy_args[@]}" "$@"
}

# 同步函数开始
# 解析仓库行；空行或注释返回空 REPO，非法配置返回非零状态。
parse_repo_line() {
    local line="${1%$'\r'}" extra branch
    local -a selected=()
    REPO=""
    BRANCHES=""
    line="${line%%#*}"
    read -r REPO BRANCHES extra <<< "$line"
    [ -z "$REPO" ] && return 0
    REPO="${REPO%.git}"
    if [[ ! "$REPO" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*/[a-zA-Z0-9_][a-zA-Z0-9._-]*$ || -n "$extra" ]]; then
        return 1
    fi
    if [ -n "$BRANCHES" ]; then
        case "$BRANCHES" in
            ,*|*,|*,,*) return 1 ;;
        esac
        IFS=',' read -r -a selected <<< "$BRANCHES"
        for branch in "${selected[@]}"; do
            [[ "$branch" == -* || "$branch" == HEAD ]] && return 1
            git check-ref-format "refs/heads/$branch" >/dev/null 2>&1 || return 1
        done
    fi
    return 0
}

# 按完整镜像或指定分支配置 fetch，禁止隐式获取额外标签。
configure_fetch() {
    local dir="$1" branches="$2" branch status
    local -a selected=()
    if git --git-dir="$dir" config --unset-all remote.origin.fetch; then
        :
    else
        status=$?
        [ "$status" -eq 5 ] || return "$status"
    fi
    git --git-dir="$dir" config remote.origin.tagOpt --no-tags || return 1
    if [ -z "$branches" ]; then
        git --git-dir="$dir" config remote.origin.mirror true || return 1
        git --git-dir="$dir" config --unset-all remote.origin.tagOpt 2>/dev/null || true
        git --git-dir="$dir" config --add remote.origin.fetch '+refs/*:refs/*' || return 1
    else
        git --git-dir="$dir" config remote.origin.mirror false || return 1
        git --git-dir="$dir" config remote.origin.tagOpt --no-tags || return 1
        IFS=',' read -r -a selected <<< "$branches"
        for branch in "${selected[@]}"; do
            git --git-dir="$dir" config --add remote.origin.fetch "+refs/heads/$branch:refs/heads/$branch" || return 1
        done
    fi
    return 0
}

# 仅在成功拉取后删除范围外引用，并将 HEAD 指向首个所选分支。
prune_unselected_refs() {
    local dir="$1" branches="$2" ref branch keep refs
    local -a selected=()
    [ -z "$branches" ] && return 0
    IFS=',' read -r -a selected <<< "$branches"
    for branch in "${selected[@]}"; do
        git --git-dir="$dir" show-ref --verify --quiet "refs/heads/$branch" || return 1
    done
    refs=$(git --git-dir="$dir" for-each-ref --format='%(refname)') || return 1
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        keep=no
        for branch in "${selected[@]}"; do
            if [ "$ref" = "refs/heads/$branch" ]; then
                keep=yes
                break
            fi
        done
        if [ "$keep" = no ]; then
            git --git-dir="$dir" update-ref -d "$ref" || return 1
        fi
    done <<< "$refs"
    git --git-dir="$dir" symbolic-ref HEAD "refs/heads/${selected[0]}" || return 1
    return 0
}
# 同步函数结束

# 初始化裸仓库后按指定范围同步，不先下载完整镜像。
clone_repo() {
    local repo="$1" dir="$2" branches="${3:-}"
    git init --bare --quiet "$dir" || return 1
    git --git-dir="$dir" remote add origin "https://github.com/${repo}.git" || return 1
    if update_repo "$repo" "$dir" "$branches"; then
        return 0
    fi
    log "首次同步失败，保留未发布的裸仓库以便下次重试：$repo"
    return 1
}

# 按代理、直连、SSH 顺序拉取，仅成功后更新发布范围。
update_repo() {
    local repo="$1" dir="$2" branches="${3:-}" mode url remote_head line
    local -a modes=()
    configure_fetch "$dir" "$branches" || return 1
    [ -n "$PROXY_URL" ] && modes+=(proxy)
    modes+=(noproxy)
    [ "$ENABLE_SSH" = yes ] && modes+=(ssh)
    for mode in "${modes[@]}"; do
        if [ "$mode" = ssh ]; then
            url=$(build_ssh_url "$repo")
        else
            url=$(build_https_url "$repo")
        fi
        log "同步($mode) $repo；分支：${branches:-全部 refs}"
        if run_cmd run_git "$mode" --git-dir="$dir" -c "remote.origin.url=$url" fetch --progress --atomic --prune origin; then
            prune_unselected_refs "$dir" "$branches" || return 1
            if [ -z "$branches" ]; then
                if remote_head=$(run_git "$mode" --git-dir="$dir" -c "remote.origin.url=$url" ls-remote --symref origin HEAD); then
                    while IFS= read -r line; do
                        if [[ "$line" == 'ref: refs/heads/'* ]]; then
                            read -r _ remote_head _ <<< "$line"
                            git --git-dir="$dir" symbolic-ref HEAD "$remote_head" || return 1
                            break
                        fi
                    done <<< "$remote_head"
                else
                    log "无法查询上游默认分支，保留当前 HEAD：$repo"
                fi
            fi
            touch "$dir/git-daemon-export-ok" || return 1
            log "同步成功($mode) $repo"
            return 0
        fi
    done
    log "同步失败，未清理范围外引用：$repo"
    return 1
}

build_flat_links() {
    cd "$MIRROR_ROOT" || return
    find . -mindepth 2 -maxdepth 2 -type d -name '*.git' | while read -r path; do
        local repo link
        repo="$(basename "$path")"
        link="./${repo}"
        if [ -e "$link" ] || [ -L "$link" ]; then continue; fi
        ln -s "$path" "$link"
        chown -h git:git "$link" 2>/dev/null || true
    done
}

# 分支报告开始
# 按仓库分组，以短哈希、摘要和独立时间行报告分支头，失败时明确标记本地缓存。
print_branch_commits() {
    local repo="$1" dir="$2" branches="${3:-}" status="${4:-failed}"
    local branch branch_list details short_hash commit_time subject
    local -a selected=()
    if [ "$status" = success ]; then
        log "$repo 分支提交（本次同步成功）"
    else
        log "$repo 分支提交（本次同步失败；仅本地缓存，未确认上游最新）"
    fi

    if [ -n "$branches" ]; then
        IFS=',' read -r -a selected <<< "$branches"
    else
        if ! branch_list=$(git --git-dir="$dir" for-each-ref --sort=refname --format='%(refname:lstrip=2)' refs/heads/); then
            log "  无法读取本地分支列表"
            return 0
        fi
        if [ -z "$branch_list" ]; then
            log "  没有本地分支可报告"
            return 0
        fi
        while IFS= read -r branch; do
            selected+=("$branch")
        done <<< "$branch_list"
    fi

    for branch in "${selected[@]}"; do
        if details=$(git --git-dir="$dir" log -1 --abbrev=12 --format='%h%n%cI%n%s' "refs/heads/$branch" -- 2>/dev/null) && [ -n "$details" ]; then
            short_hash="${details%%$'\n'*}"
            details="${details#*$'\n'}"
            commit_time="${details%%$'\n'*}"
            subject="${details#*$'\n'}"
            log "  ↳ $branch: $short_hash $subject"
            log "    提交时间：$commit_time"
        else
            log "  ↳ $branch: 本地不存在或无法读取提交"
        fi
    done
    return 0
}
# 分支报告结束

log "========== 同步任务开始 =========="

[ ! -f "$REPO_LIST" ] && { log "仓库列表不存在: $REPO_LIST"; exit 1; }

total=0; ok=0; fail=0

while IFS= read -r line || [ -n "$line" ]; do
    if ! parse_repo_line "$line"; then
        log "非法仓库配置，跳过：$line"
        total=$((total + 1))
        fail=$((fail + 1))
        continue
    fi
    [ -z "$REPO" ] && continue
    repo="$REPO"
    branches="$BRANCHES"
    dir="${MIRROR_ROOT}/${repo}.git"
    total=$((total + 1))

    if [ -d "$dir" ]; then
        if update_repo "$repo" "$dir" "$branches"; then
            ok=$((ok + 1))
            print_branch_commits "$repo" "$dir" "$branches" success
        else
            fail=$((fail + 1))
            print_branch_commits "$repo" "$dir" "$branches" failed
        fi
    else
        mkdir -p "$(dirname "$dir")"
        if clone_repo "$repo" "$dir" "$branches"; then
            touch "$dir/git-daemon-export-ok"
            ok=$((ok + 1))
            print_branch_commits "$repo" "$dir" "$branches" success
        else
            fail=$((fail + 1))
            print_branch_commits "$repo" "$dir" "$branches" failed
        fi
    fi
    chown -R git:git "$dir" 2>/dev/null || true
done < "$REPO_LIST"

build_flat_links

log "========== 同步结束：总计 ${total}，成功 ${ok}，失败 ${fail} =========="

[ "$fail" -gt 0 ] && exit 1
exit 0
SYNC_SCRIPT_EOF

chown "$GIT_USER:$GIT_USER" "$SYNC_SCRIPT"
chmod 750 "$SYNC_SCRIPT"
ok "同步脚本安装完成"

# 5.5 安装 GitHub hosts 自动刷新脚本
if [[ "$ENABLE_HOSTS_UPDATE" == "yes" ]]; then
    info "[5.5/9] 安装 GitHub hosts 自动刷新脚本 ..."

    cat > "$HOSTS_SCRIPT" <<'HOSTS_SCRIPT_EOF'
#!/bin/bash
set -uo pipefail

HOSTS_URL="${HOSTS_URL:-https://cdn.jsdelivr.net/gh/521xueweihan/GitHub520@main/hosts}"
HOSTS_URL_FALLBACK="${HOSTS_URL_FALLBACK:-https://raw.hellogithub.com/hosts}"
LOG_FILE="${HOSTS_LOG:-/var/log/git-mirror/hosts.log}"
TMP_HOSTS="/tmp/github_hosts_new.$$"
HOSTS_FILE="/etc/hosts"
MARK_START="# GitHub520 Host Start"
MARK_END="# GitHub520 Host End"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    local msg="[$(date '+%F %T')] $*"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE"
}

download_hosts() {
    local url="$1" out="$2"
    if curl -fsSL --connect-timeout 10 --max-time 30 "$url" -o "$out" 2>/dev/null; then
        if grep -q 'github\.com' "$out"; then
            return 0
        fi
    fi
    return 1
}

log "========== 开始更新 GitHub hosts =========="

if ! download_hosts "$HOSTS_URL" "$TMP_HOSTS"; then
    log "主源失败，尝试备用源: $HOSTS_URL_FALLBACK"
    if ! download_hosts "$HOSTS_URL_FALLBACK" "$TMP_HOSTS"; then
        log "所有数据源均失败，保持现有 hosts 不变"
        rm -f "$TMP_HOSTS"
        exit 1
    fi
fi

cp -f "$HOSTS_FILE" "${HOSTS_FILE}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
ls -1t "${HOSTS_FILE}".bak.* 2>/dev/null | tail -n +6 | xargs -r rm -f

sed -i "/${MARK_START}/,/${MARK_END}/d" "$HOSTS_FILE"
sed -i '/github\.com\|githubusercontent\.com\|githubassets\.com\|fastly\.net\|codeload\.github\.com\|raw\.githubusercontent\.com/d' "$HOSTS_FILE"

{
    echo ""
    echo "$MARK_START"
    cat "$TMP_HOSTS"
    echo "$MARK_END"
} >> "$HOSTS_FILE"

rm -f "$TMP_HOSTS"

if command -v systemd-resolve >/dev/null 2>&1; then
    systemd-resolve --flush-caches >/dev/null 2>&1 || true
elif command -v resolvectl >/dev/null 2>&1; then
    resolvectl flush-caches >/dev/null 2>&1 || true
elif command -v nscd >/dev/null 2>&1; then
    nscd restart >/dev/null 2>&1 || true
fi

count=$(grep -cE 'github\.com' "$HOSTS_FILE" 2>/dev/null || echo 0)
log "更新完成，/etc/hosts 中包含 $count 条 github.com 记录"

grep -E '^\S+\s+(github\.com|api\.github\.com)' "$HOSTS_FILE" | head -3 | while read -r line; do
    log "  $line"
done

log "========== GitHub hosts 更新结束 =========="
HOSTS_SCRIPT_EOF

    chmod 755 "$HOSTS_SCRIPT"
    chown root:root "$HOSTS_SCRIPT"

    HOSTS_URL="$HOSTS_URL" HOSTS_URL_FALLBACK="$HOSTS_URL_FALLBACK" HOSTS_LOG="$HOSTS_LOG" \
        "$HOSTS_SCRIPT" || warn "首次 hosts 刷新失败（不影响部署）"

    ok "hosts 更新脚本安装完成"
else
    info "[5.5/9] 跳过 hosts 自动刷新（--hosts no）"
fi

# 6. 安装 access-hook 脚本
info "[6/9] 安装 access-hook ..."

cat > "$HOOK_SCRIPT" <<'HOOK_EOF'
#!/bin/bash
set -euo pipefail

# 只允许镜像根目录下的仓库短名读取，不接受完整路径或写入请求。
SERVICE="${1:-}"
REPO_PATH="${2:-}"
MIRROR_ROOT="/srv/git-mirror"
if [[ "$SERVICE" != "upload-pack" || "$REPO_PATH" != "$MIRROR_ROOT/"* ]]; then
    echo "Access denied"
    exit 1
fi
REPO_NAME="${REPO_PATH#"$MIRROR_ROOT/"}"
if [[ ! "$REPO_NAME" =~ ^[a-zA-Z0-9_][a-zA-Z0-9._-]*\.git$ ]]; then
    echo "Access denied"
    exit 1
fi
exit 0
HOOK_EOF

chown "$GIT_USER:$GIT_USER" "$HOOK_SCRIPT"
chmod 750 "$HOOK_SCRIPT"
ok "access-hook 安装完成"

# 7. 配置 systemd 服务
info "[7/9] 配置 git-daemon systemd 服务 ..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Git daemon for GitHub mirror
After=network.target

[Service]
User=$GIT_USER
Group=$GIT_USER
# 避免 Git 读取被 ProtectHome 隔离的用户配置目录。
Environment=HOME=/nonexistent
Environment=XDG_CONFIG_HOME=/nonexistent
ExecStart=/usr/bin/git daemon \\
    --reuseaddr \\
    --base-path=$MIRROR_ROOT \\
    --no-informative-errors \\
    --access-hook=$HOOK_SCRIPT \\
    --max-connections=20 \\
    --verbose \\
    --listen=$LISTEN_ADDRESS \\
    --port=$GIT_PORT --disable=receive-pack --forbid-override=receive-pack $MIRROR_ROOT
Restart=on-failure
RestartSec=5

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadOnlyPaths=$MIRROR_ROOT

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable git-daemon >/dev/null 2>&1
ok "systemd 服务已配置"

# 8. 首次同步
info "[8/9] 执行首次同步（大仓库可能耗时较长） ..."

sudo -u "$GIT_USER" -H "$SYNC_SCRIPT" || warn "首次同步有失败项，请查看 $LOG_DIR/sync.log"

systemctl restart git-daemon
sleep 2
systemctl --no-pager status git-daemon | head -10 || true

if [[ "$ENABLE_CRON" == "yes" ]]; then
    info "配置定时同步及 hosts 刷新任务 ..."

    # git 用户的同步任务
    EXISTING_CRON="$(crontab -u "$GIT_USER" -l 2>/dev/null | grep -v "$SYNC_SCRIPT" || true)"
    {
        echo "$EXISTING_CRON"
        echo "$CRON_SCHEDULE $SYNC_SCRIPT >/dev/null 2>&1"
    } | grep -v '^$' | crontab -u "$GIT_USER" -
    ok "同步 cron 任务已配置（$GIT_USER）：$CRON_SCHEDULE"

    # root 的 hosts 刷新任务（写 /etc/hosts 需 root）
    if [[ "$ENABLE_HOSTS_UPDATE" == "yes" ]]; then
        ROOT_EXISTING="$(crontab -l 2>/dev/null | grep -v "$HOSTS_SCRIPT" || true)"
        {
            echo "$ROOT_EXISTING"
            echo "$HOSTS_CRON HOSTS_URL=\"$HOSTS_URL\" HOSTS_URL_FALLBACK=\"$HOSTS_URL_FALLBACK\" HOSTS_LOG=\"$HOSTS_LOG\" $HOSTS_SCRIPT >/dev/null 2>&1"
        } | grep -v '^$' | crontab -
        ok "hosts 刷新 cron 任务已配置（root）：$HOSTS_CRON"
    fi
else
    info "跳过 cron 配置（--no-cron）"
fi

# 完成
echo
ok "部署完成"
echo

FIRST_FLAT="$(awk '
    { sub(/\r$/, ""); sub(/#.*/, "") }
    NF {
        n = split($1, parts, "/")
        repo = parts[n]
        sub(/\.git$/, "", repo)
        print repo
        exit
    }
' "$CONF_DIR/repos.list")"

# IPv4 连接提示开始
# 从启用网卡读取 IPv4，结合监听范围打印命令，不查询公网地址或修改网络。
print_connection_commands() {
    local listen="$1" port="$2" repo="$3" rows addresses address
    info "验证命令："
    printf "  sudo ss -tlnp 'sport = :%s'\n" "$port"
    if [[ ! "$listen" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        warn "连接提示仅处理 IPv4；当前监听地址不是 IPv4，跳过地址命令。"
        return 0
    fi
    if [ -z "$repo" ]; then
        warn "未检测到仓库名称，跳过 Git 连接命令。"
        return 0
    fi
    if [[ "$listen" == 127.* ]]; then
        printf '  git ls-remote git://%s:%s/%s.git HEAD\n' "$listen" "$port" "$repo"
        warn "当前监听地址仅本机访问，不提供远程克隆命令。"
        return 0
    fi
    if [ "$listen" = 0.0.0.0 ]; then
        printf '  git ls-remote git://127.0.0.1:%s/%s.git HEAD\n' "$port" "$repo"
    fi
    if ! command -v ip >/dev/null 2>&1; then
        warn "未检测到 ip 命令，无法获取网卡 IPv4；请安装 iproute2。"
        return 0
    fi
    if ! rows=$(ip -o -4 addr show up); then
        warn "读取网卡 IPv4 失败，跳过客户端克隆命令。"
        return 0
    fi
    addresses=$(printf '%s\n' "$rows" | awk -v listen="$listen" '
        $3 == "inet" && / scope global / {
            split($4, cidr, "/")
            addr = cidr[1]
            if (split(addr, octets, ".") != 4) next
            valid = 1
            for (i = 1; i <= 4; i++) {
                if (octets[i] !~ /^[0-9]+$/ || octets[i] > 255) valid = 0
            }
            if (!valid || octets[1] == 0 || octets[1] == 127 || octets[1] >= 224) next
            if (octets[1] == 169 && octets[2] == 254) next
            if (listen != "0.0.0.0" && addr != listen) next
            if (!seen[addr]++) print addr
        }
    ')
    if [ -z "$addresses" ]; then
        warn "未检测到与监听范围匹配的可用网卡 IPv4，跳过客户端克隆命令。"
        return 0
    fi
    if [ "$listen" != 0.0.0.0 ]; then
        printf '  git ls-remote git://%s:%s/%s.git HEAD\n' "$listen" "$port" "$repo"
    fi
    echo
    info "客户端克隆（网卡 IPv4，按客户端可达网络选择）："
    while IFS= read -r address; do
        printf '  git clone git://%s:%s/%s.git\n' "$address" "$port" "$repo"
    done <<< "$addresses"
    warn "以上为本机网卡地址，不代表公网可达；请确认路由、防火墙及必要的端口映射。"
    return 0
}
# IPv4 连接提示结束

print_connection_commands "$LISTEN_ADDRESS" "$GIT_PORT" "$FIRST_FLAT"
echo
info "关键文件："
echo "  配置    : $CONF_DIR/mirror.env, $CONF_DIR/repos.list"
echo "  同步脚本: $SYNC_SCRIPT"
echo "  服务    : $SERVICE_FILE"
echo "  日志    : $LOG_DIR/sync.log"
echo
if [[ "$ENABLE_HOSTS_UPDATE" == "yes" ]]; then
    info "GitHub hosts 自动刷新："
    echo "  脚本: $HOSTS_SCRIPT"
    echo "  cron: $HOSTS_CRON（root）"
    echo "  日志: $HOSTS_LOG"
    echo "  手动执行: sudo $HOSTS_SCRIPT"
    echo
fi
warn "需手动完成："
echo "  1) 本机防火墙与云安全组（VPS供应商防火墙）按需放行 TCP $GIT_PORT"
echo "  2) 如需域名访问，请配置 DDNS 后再测试能否拉取仓库"
echo "  3) 通过其他主机测试是否能正常拉取仓库"
warn "git:// 不提供身份认证或传输加密，只应发布允许匿名读取的仓库"