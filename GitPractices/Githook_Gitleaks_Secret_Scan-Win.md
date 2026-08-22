# 在 WIN 部署 Gitleaks 扫描来阻止提交秘密

> [!NOTE]
> 基于 Gitleaks v8.30.1

## 1. 安装 Gitleaks

```bash
# 使用 Winget 安装
winget install Gitleaks.Gitleaks

# 或者使用 Scoop 安装
scoop install gitleaks

# 验证版本
gitleaks --version
```

## 2. 部署 Git Hook

> [!IMPORTANT]
> 本节需要在 Git Bash 中配置

### 2.1 配置 Git Hook

```bash
# 创建文件夹
mkdir -p ~/.git-global-hooks

# 配置 hook 路径
git config --global core.hooksPath ~/.git-global-hooks

# 验证配置是否生效
git config --global core.hooksPath
```

### 2.2 创建脚本

```bash
cat > ~/.git-global-hooks/pre-commit <<'EOF'
#!/bin/sh

# 终端颜色自适应
# 仅在交互终端下启用颜色，非终端/不支持环境自动降级为纯文本
if [ -t 1 ] && [ "$TERM" != "dumb" ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  BLUE='\033[0;34m'
  BOLD='\033[1m'
  GREY='\033[90m'
  RESET='\033[0m'
else
  RED=''
  GREEN=''
  BLUE=''
  BOLD=''
  GREY=''
  RESET=''
fi

printf "%b\n" "${BOLD}${GREY}───────────────────────────────────────────${RESET}"
printf "%b\n" "${BOLD}${GREY}  🔍 Gitleaks 敏感信息检测${RESET}"
printf "%b\n" "${BOLD}${GREY}───────────────────────────────────────────${RESET}"

# 1. 检查 gitleaks 是否安装
if ! command -v gitleaks >/dev/null 2>&1; then
  echo "❌ 错误：未检测到 Gitleaks，请检查环境变量或安装路径"
  exit 1
fi

# 2. 提取暂存区变更内容，通过管道传给 gitleaks 扫描
# --diff-filter=ACM：只扫新增/修改的文件，排除删除文件
# -U0：无多余上下文，只扫变更行，提升效率
# --no-banner 关闭 Gitleaks LOGO 显示

# 秘钥内容打码 80%
git diff --cached --diff-filter=ACM -U0 | gitleaks stdin --no-banner -v --redact=80

# 全打码
# git diff --cached --diff-filter=ACM -U0 | gitleaks stdin --no-banner -v --redact
EXIT_CODE=$?

# 3. 分场景处理结果
if [ ${EXIT_CODE} -eq 1 ]; then
  # 检测到敏感信息：分层告警样式
  echo ""
  printf "%b\n" "${BOLD}${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  printf "%b\n" "${BOLD}${RED}  ❌ 警告：检测到敏感信息/密钥被提交${RESET}"
  printf "%b\n" "${BOLD}${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  printf "%b\n" "${BLUE}📌 处理建议：${RESET}"
  echo "  1. 删除代码中的密钥、Token、密码等敏感内容"
  echo "  2. 如确定提交，请在项目 .gitleaks.toml 中添加白名单规则"
  echo "  3. 请勿使用 git commit --no-verify 绕过检查，避免泄露敏感信息"
  echo ""
  exit 1
elif [ ${EXIT_CODE} -ne 0 ]; then
  # 扫描执行失败（参数错误、环境异常等）
  printf "%b\n" "${BOLD}${RED}❌ Gitleaks 扫描执行失败，请检查环境和仓库状态${RESET}"
  exit 1
fi

# 扫描通过
printf "%b\n" "${GREEN}✅ Gitleaks scan passed${RESET}"
exit 0
EOF

# 添加执行权限
chmod +x ~/.git-global-hooks/pre-commit
```

---

## 3. 测试是否生效

> [!IMPORTANT]
> 本节需要在 PWSH 中进行，请勿使用 CMD 或 Git Bash

### 3.1 创建测试仓库

```bash
# 进入临时目录
cd Z:\Temp\

# 创建并进入文件夹
mkdir test-commit-hook && cd test-commit-hook

# 初始化仓库
git init
```

### 3.2 创建测试文件

```pwsh
# 在 pwsh7 中使用管道直接写入文件
$content = @'
AWS_SECRET="AKIAIOSF5DNNM0oPq1rS"
token='ghp_wA9mK2pLxN4vRtQzY6bC8dEfGhslM0oPq1rS'
gh_token=ghp_aBcDeFgHiJkLmNoPqRsTuwwXyZ0123456789
'@ | Out-File secret.txt -Encoding utf8NoBOM

# 在 pwsh5.1 中分步写入文件
# 请修改 $filePath 变量的路径
$content = @'
AWS_SECRET="AKIAIOSF5DNNM0oPq1rS"
token='ghp_wA9mK2pLxN4vRtQzY6bC8dEfGhslM0oPq1rS'
gh_token=ghp_aBcDeFgHiJkLmNoPqRsTuwwXyZ0123456789
'@
$filePath = "Z:\Temp\test-commit-hook\secret.txt"
[System.IO.File]::WriteAllText("$filePath", $content, [System.Text.UTF8Encoding]::new($false))
```

### 3.2 提交测试文件

```bash
git add secret.txt
git commit -m "test hook"
```

## 3.3 Gitleaks 扫描结果

```bash
───────────────────────────────────────────
  🔍 Gitleaks 敏感信息检测
───────────────────────────────────────────
Finding:     +AWS_SECRET = "AKIAIOS..."
Secret:      AKIAIOS...
RuleID:      generic-api-key
Entropy:     3.921928

Finding:     +token = "ghp_wA9mK2pLxN...
Secret:      ghp_wA9mK2pLxN...
RuleID:      github-pat
Entropy:     5.221928

Finding:     +gh_token = "ghp_aBcDeFgHiJ...
Secret:      ghp_aBcDeFgHiJ...
RuleID:      github-pat
Entropy:     5.221928

6:30AM INF scanned ~1715 bytes (1.72 KB) in 100ms
6:30AM WRN leaks found: 3

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  ❌ 提交被阻止：检测到敏感信息/密钥泄漏
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📌 处理建议：
 1. 删除代码中的密钥、Token、密码等敏感内容
 2. 如确定提交，请在项目 .gitleaks.toml 中添加白名单规则
 3. 请勿使用 git commit --no-verify 绕过检查，避免泄露敏感信息
```

---

## 附录

### PS.1 Gitleaks 常用命令

```bash
# 扫描某个文件
gitleaks dir -v <path/to/dir>

# 扫描本地仓库的全部历史提交
gitleaks detect --source .

# 扫描所有分支的完整历史
gitleaks detect --source . --log-opts="--all --full-history"

# 扫描最近 N 次提交
gitleaks detect --source . --depth=50

# 按提交哈希范围扫描
gitleaks detect --source . --commit-from=abc123 --commit-to=def456

# 按时间范围扫描
gitleaks detect --source . --commit-since=2023-01-01 --commit-until=2024-01-01

# 扫描远程仓库
gitleaks detect --repo-url=https://github.com/your-org/your-repo
```

### PS.2 配置 PowerShell 5.1 颜色显示

```pwsh
Set-ItemProperty -Path "HKCU:\Console" -Name "VirtualTerminalLevel" -Value 1 -Type DWord
```
