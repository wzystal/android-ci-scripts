#!/usr/bin/env bash
# 将指定 Android 项目的 Release 签名写入 GitHub Secrets。
# 需先: gh auth login -h github.com
#
# 用法:
#   setup-github-secrets.sh [owner/repo]
#   setup-github-secrets.sh --project-dir ~/work/foo [owner/repo]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"
REPO_ARGS=()

usage() {
  cat <<EOF
用法:
  setup-github-secrets.sh [--project-dir <路径>] [owner/repo]
  setup-github-secrets.sh [--project-dir <路径>] <owner> <repo>

示例:
  cd ~/work/pdf-studio && ~/tools/scripts/setup-github-secrets.sh
  ~/tools/scripts/setup-github-secrets.sh --project-dir ~/work/AiChatHub wzystal/AiChatHub

环境变量（可选，与 setup-shared-secrets.sh 配合）:
  PGYER_API_KEY      蒲公英 API Key
  DINGTALK_WEBHOOK   钉钉 Webhook

前置:
  gh auth login -h github.com
  ~/tools/scripts/generate-release-keystore.sh <项目目录>
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      REPO_ARGS+=("$1")
      shift
      ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
SECRETS_FILE="$PROJECT_DIR/signing/secrets.local.properties"
KEYSTORE="$PROJECT_DIR/signing/release.jks"

detect_repo_from_git() {
  local url owner repo
  url="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$url" ]]; then
    echo "无法从 git remote 推断仓库，请显式传入 owner/repo" >&2
    return 1
  fi
  if [[ "$url" =~ git@github.com:([^/]+)/(.+)\.git$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ https://github.com/([^/]+)/(.+)\.git$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]}"
  elif [[ "$url" =~ https://github.com/([^/]+)/([^/]+)/?$ ]]; then
    owner="${BASH_REMATCH[1]}"
    repo="${BASH_REMATCH[2]%.git}"
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
        usage >&2
        exit 1
      fi
      echo "${REPO_ARGS[0]}"
      ;;
    2) echo "${REPO_ARGS[0]}/${REPO_ARGS[1]}" ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

if ! gh auth status >/dev/null 2>&1; then
  echo "请先执行: gh auth login -h github.com" >&2
  exit 1
fi

if [[ ! -f "$SECRETS_FILE" ]] || [[ ! -f "$KEYSTORE" ]]; then
  echo "缺少 signing/release.jks 或 signing/secrets.local.properties" >&2
  echo "请先执行: $SCRIPT_DIR/generate-release-keystore.sh \"$PROJECT_DIR\"" >&2
  exit 1
fi

REPO="$(resolve_repo)"

if ! gh repo view "$REPO" --json name >/dev/null 2>&1; then
  echo "仓库不存在或无权限: $REPO" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$SECRETS_FILE"

echo "项目目录: $PROJECT_DIR"
echo "目标仓库: $REPO"
echo "写入 Release 签名 Secrets..."

gh secret set RELEASE_KEYSTORE_BASE64 --repo "$REPO" --body "$(base64 -i "$KEYSTORE" | tr -d '\n')"
gh secret set RELEASE_STORE_PASSWORD --repo "$REPO" --body "$STORE_PASSWORD"
gh secret set RELEASE_KEY_ALIAS --repo "$REPO" --body "$KEY_ALIAS"
gh secret set RELEASE_KEY_PASSWORD --repo "$REPO" --body "$KEY_PASSWORD"

echo "已写入: RELEASE_KEYSTORE_BASE64, RELEASE_STORE_PASSWORD, RELEASE_KEY_ALIAS, RELEASE_KEY_PASSWORD"

if [[ -n "${PGYER_API_KEY:-}" ]]; then
  gh secret set PGYER_API_KEY --repo "$REPO" --body "$PGYER_API_KEY"
  echo "已写入: PGYER_API_KEY"
else
  echo ""
  echo "未设置 PGYER_API_KEY。可执行: ~/tools/scripts/setup-shared-secrets.sh"
fi

if [[ -n "${DINGTALK_WEBHOOK:-}" ]]; then
  gh secret set DINGTALK_WEBHOOK --repo "$REPO" --body "$DINGTALK_WEBHOOK"
  echo "已写入: DINGTALK_WEBHOOK"
else
  echo ""
  echo "未设置 DINGTALK_WEBHOOK。可执行: ~/tools/scripts/setup-shared-secrets.sh"
fi

echo ""
echo "完成。验证: gh secret list --repo $REPO"
