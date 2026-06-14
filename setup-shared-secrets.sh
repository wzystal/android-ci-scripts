#!/usr/bin/env bash
# 交互式将蒲公英 API Key 与钉钉 Webhook 写入一个或多个 GitHub 仓库 Secrets。
# 需先: gh auth login -h github.com
#
# 用法:
#   ~/tools/scripts/setup-shared-secrets.sh
set -euo pipefail

DEFAULT_REPOS="wzystal/pdf-studio,wzystal/WeiqiGame,wzystal/AiChatHub,wzystal/BridgeGame"
SECRETS_ENV="${SECRETS_ENV:-$HOME/.config/android-release/secrets.env}"

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# 读取敏感输入：不回显明文，每输入一个字符显示一个 *
read_masked() {
  local prompt="$1"
  local __result_var="$2"
  local char
  local buf=""

  printf '%s' "$prompt"
  while true; do
    IFS= read -r -s -n 1 char 2>/dev/null || true
    if [[ -z "$char" || "$char" == $'\n' || "$char" == $'\r' ]]; then
      break
    fi
    if [[ "$char" == $'\003' ]]; then
      printf '\n'
      exit 130
    fi
    if [[ "$char" == $'\177' || "$char" == $'\b' ]]; then
      if [[ -n "$buf" ]]; then
        buf="${buf%?}"
        printf '\b \b'
      fi
      continue
    fi
    buf+="$char"
    printf '*'
  done
  printf '\n'
  printf -v "$__result_var" '%s' "$buf"
}

usage() {
  cat <<EOF
用法:
  setup-shared-secrets.sh [--repos owner/repo,owner/repo2]

交互式依次输入:
  1. PGYER_API_KEY（蒲公英后台 API 信息页）
  2. DINGTALK_WEBHOOK（钉钉机器人 Webhook 完整 URL）
  3. 目标仓库列表（owner/repo，逗号分隔；直接回车使用 --repos 或默认列表）

可选:
  --repos   指定目标仓库，逗号分隔
  环境变量文件 ~/.config/android-release/secrets.env（若存在则预填，格式 PGYER_API_KEY= / DINGTALK_WEBHOOK=）

默认仓库:
  $DEFAULT_REPOS

前置:
  gh auth login -h github.com
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

REPO_INPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repos) REPO_INPUT="$2"; shift 2 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -f "$SECRETS_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$SECRETS_ENV"
  echo "已加载: $SECRETS_ENV"
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "请先执行: gh auth login -h github.com" >&2
  exit 1
fi

echo "========================================"
echo "  配置蒲公英 & 钉钉 GitHub Secrets"
echo "========================================"
echo ""
echo "提示: 敏感字段输入时以 * 显示长度；留空可跳过该项。"
echo ""

# 1. PGYER_API_KEY
pgyer_key=""
while true; do
  echo "[1/3] 蒲公英 API Key"
  echo "      获取地址: https://www.pgyer.com/account/api"
  if [[ -n "${PGYER_API_KEY:-}" ]]; then
    echo "      （检测到环境变量 PGYER_API_KEY，直接回车沿用）"
  fi
  read_masked "      > " input_key
  if [[ -z "$input_key" && -n "${PGYER_API_KEY:-}" ]]; then
    pgyer_key="$(trim "$PGYER_API_KEY")"
    break
  fi
  input_key="$(trim "$input_key")"
  if [[ -z "$input_key" ]]; then
    echo "      已跳过 PGYER_API_KEY"
    break
  fi
  pgyer_key="$input_key"
  break
done

# 2. DINGTALK_WEBHOOK
dingtalk_webhook=""
while true; do
  echo ""
  echo "[2/3] 钉钉机器人 Webhook URL"
  echo "      示例: https://oapi.dingtalk.com/robot/send?access_token=..."
  if [[ -n "${DINGTALK_WEBHOOK:-}" ]]; then
    echo "      （检测到环境变量 DINGTALK_WEBHOOK，直接回车沿用）"
  fi
  read_masked "      > " input_hook
  if [[ -z "$input_hook" && -n "${DINGTALK_WEBHOOK:-}" ]]; then
    dingtalk_webhook="$(trim "$DINGTALK_WEBHOOK")"
    break
  fi
  input_hook="$(trim "$input_hook")"
  if [[ -z "$input_hook" ]]; then
    echo "      已跳过 DINGTALK_WEBHOOK"
    break
  fi
  if [[ "$input_hook" != https://* ]]; then
    echo "      Webhook 应以 https:// 开头，请重新输入。"
    continue
  fi
  dingtalk_webhook="$input_hook"
  break
done

if [[ -z "$pgyer_key" && -z "$dingtalk_webhook" ]]; then
  echo ""
  echo "未输入任何 Secret，已退出。"
  exit 0
fi

# 3. 目标仓库
echo ""
echo "[3/3] 目标 GitHub 仓库（owner/repo）"
echo "      多个仓库用英文逗号分隔；直接回车使用默认:"
echo "      $DEFAULT_REPOS"
printf "      > "
read -r repo_input || true
repo_input="$(trim "$repo_input")"
if [[ -z "$repo_input" ]]; then
  repo_input="${REPO_INPUT:-$DEFAULT_REPOS}"
fi

IFS=',' read -r -a repo_candidates <<< "$repo_input"

repos=()
for raw in "${repo_candidates[@]}"; do
  repo="$(trim "$raw")"
  [[ -z "$repo" ]] && continue
  if [[ "$repo" != */* ]]; then
    echo "跳过无效仓库名（须为 owner/repo）: $repo" >&2
    continue
  fi
  repos+=("$repo")
done

if [[ ${#repos[@]} -eq 0 ]]; then
  echo "没有有效的目标仓库，已退出。" >&2
  exit 1
fi

echo ""
echo "将写入以下仓库:"
for repo in "${repos[@]}"; do
  echo "  - $repo"
done
echo ""
printf "确认继续? [Y/n] "
read -r confirm || true
confirm="$(trim "${confirm:-Y}")"
if [[ "$confirm" =~ ^[Nn]$ ]]; then
  echo "已取消。"
  exit 0
fi

echo ""
ok_count=0
fail_count=0

for repo in "${repos[@]}"; do
  echo ">>> $repo"
  if ! gh repo view "$repo" --json name >/dev/null 2>&1; then
    echo "    跳过: 仓库不存在或无权限" >&2
    fail_count=$((fail_count + 1))
    continue
  fi

  repo_ok=true
  if [[ -n "$pgyer_key" ]]; then
    if gh secret set PGYER_API_KEY --repo "$repo" --body "$pgyer_key"; then
      echo "    ✓ PGYER_API_KEY"
    else
      echo "    ✗ PGYER_API_KEY 写入失败" >&2
      repo_ok=false
    fi
  fi

  if [[ -n "$dingtalk_webhook" ]]; then
    if gh secret set DINGTALK_WEBHOOK --repo "$repo" --body "$dingtalk_webhook"; then
      echo "    ✓ DINGTALK_WEBHOOK"
    else
      echo "    ✗ DINGTALK_WEBHOOK 写入失败" >&2
      repo_ok=false
    fi
  fi

  if $repo_ok; then
    ok_count=$((ok_count + 1))
  else
    fail_count=$((fail_count + 1))
  fi
done

echo ""
echo "========================================"
echo "完成: 成功 $ok_count 个仓库, 失败 $fail_count 个"
echo "验证示例: gh secret list --repo ${repos[0]}"
echo "========================================"

[[ "$fail_count" -eq 0 ]]
