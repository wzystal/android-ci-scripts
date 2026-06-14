#!/usr/bin/env bash
# 将 DeepSeek API Key 写入 AiChatHub 等项目的 GitHub Secret（不提交到 Git）。
#
# 用法:
#   ~/tools/scripts/setup-deepseek-secret.sh --project-dir ~/work/AiChatHub
#   ~/tools/scripts/setup-deepseek-secret.sh --project-dir ~/work/AiChatHub wzystal/AiChatHub
set -euo pipefail

PROJECT_DIR="$(pwd)"
REPO_ARGS=()

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

read_masked() {
  local prompt="$1"
  local __result_var="$2"
  local char
  local value=""

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
      if [[ -n "$value" ]]; then
        value="${value%?}"
        printf '\b \b'
      fi
      continue
    fi
    value+="$char"
    printf '*'
  done
  printf '\n'
  printf -v "$__result_var" '%s' "$value"
}

usage() {
  cat <<EOF
用法:
  setup-deepseek-secret.sh [--project-dir <路径>] [owner/repo]

将 DEEPSEEK_API_KEY 写入 GitHub Secrets，供 CI Release 构建时注入 BuildConfig。

密钥来源（按优先级）:
  1. 环境变量 DEEPSEEK_API_KEY
  2. 项目 local.properties 中的 deepseek.api.key
  3. 交互输入（以 * 显示长度）

示例:
  ~/tools/scripts/setup-deepseek-secret.sh --project-dir ~/work/AiChatHub
  DEEPSEEK_API_KEY=sk-xxx ~/tools/scripts/setup-deepseek-secret.sh --project-dir ~/work/AiChatHub wzystal/AiChatHub

前置: gh auth login -h github.com
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) REPO_ARGS+=("$1"); shift ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

detect_repo_from_git() {
  local url owner repo
  url="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    echo "无法从 git remote 推断仓库，请显式传入 owner/repo" >&2
    return 1
  fi
  if [[ "$url" =~ git@github.com:([^/]+)/(.+)\.git$ ]]; then
    owner="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ https://github.com/([^/]+)/(.+)\.git$ ]]; then
    owner="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ https://github.com/([^/]+)/([^/]+)/?$ ]]; then
    owner="${BASH_REMATCH[1]}"; repo="${BASH_REMATCH[2]%.git}"
  else
    echo "无法解析 remote URL: $url" >&2
    return 1
  fi
  echo "${owner}/${repo}"
}

resolve_repo() {
  case ${#REPO_ARGS[@]} in
    0) detect_repo_from_git ;;
    1)
      if [[ "${REPO_ARGS[0]}" != */* ]]; then
        echo "单个参数须为 owner/repo 格式" >&2
        exit 1
      fi
      echo "${REPO_ARGS[0]}"
      ;;
    2) echo "${REPO_ARGS[0]}/${REPO_ARGS[1]}" ;;
    *) usage >&2; exit 1 ;;
  esac
}

if ! gh auth status >/dev/null 2>&1; then
  echo "请先执行: gh auth login -h github.com" >&2
  exit 1
fi

REPO="$(resolve_repo)"
LOCAL_PROPS="$PROJECT_DIR/local.properties"

api_key="$(trim "${DEEPSEEK_API_KEY:-}")"

if [[ -z "$api_key" && -f "$LOCAL_PROPS" ]]; then
  api_key="$(trim "$(grep -E '^deepseek\.api\.key=' "$LOCAL_PROPS" 2>/dev/null | head -1 | cut -d= -f2- || true)")"
fi

if [[ -z "$api_key" ]]; then
  echo "未找到 DEEPSEEK_API_KEY / local.properties 中的 deepseek.api.key"
  read_masked "请输入 DeepSeek API Key > " api_key
  api_key="$(trim "$api_key")"
fi

if [[ -z "$api_key" ]]; then
  echo "未提供 API Key，已退出。" >&2
  exit 1
fi

if ! gh repo view "$REPO" --json name >/dev/null 2>&1; then
  echo "仓库不存在或无权限: $REPO" >&2
  exit 1
fi

echo "项目目录: $PROJECT_DIR"
echo "目标仓库: $REPO"
echo "写入 DEEPSEEK_API_KEY ..."

gh secret set DEEPSEEK_API_KEY --repo "$REPO" --body "$api_key"

echo "完成。验证: gh secret list --repo $REPO | grep DEEPSEEK"
echo "下次 push main 或手动触发 Release workflow 即可打出可用包。"
