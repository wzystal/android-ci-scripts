#!/usr/bin/env bash
# 为单个 Android 项目完成 Release 本地签名 + GitHub Secrets 配置。
# 用法: setup-android-release.sh <项目目录> [owner/repo]
set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR=""
REPO_ARGS=()

usage() {
  cat <<EOF
用法:
  setup-android-release.sh <项目目录> [owner/repo]
  setup-android-release.sh <项目目录> <owner> <repo>

示例:
  setup-android-release.sh ~/work/AiChatHub
  setup-android-release.sh ~/work/BridgeGame wzystal/BridgeGame

步骤:
  1. 生成 Release keystore（若不存在）
  2. 写入 RELEASE_* GitHub Secrets
  3. 若已 export PGYER_API_KEY / DINGTALK_WEBHOOK，一并写入当前仓库

蒲公英 & 钉钉（多仓库）另执行:
  ~/tools/scripts/setup-shared-secrets.sh --repos owner/repo,owner/repo2
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    *)
      if [[ -z "$PROJECT_DIR" ]]; then
        PROJECT_DIR="$1"
      else
        REPO_ARGS+=("$1")
      fi
      shift
      ;;
  esac
done

[[ -n "$PROJECT_DIR" ]] || { usage >&2; exit 1; }
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

echo "========================================"
echo "  配置 Android Release: $(basename "$PROJECT_DIR")"
echo "========================================"

"$TOOLS_DIR/generate-release-keystore.sh" "$PROJECT_DIR"

if [[ ${#REPO_ARGS[@]} -eq 0 ]]; then
  "$TOOLS_DIR/setup-github-secrets.sh" --project-dir "$PROJECT_DIR"
else
  "$TOOLS_DIR/setup-github-secrets.sh" --project-dir "$PROJECT_DIR" "${REPO_ARGS[@]}"
fi

echo ""
echo "项目 $(basename "$PROJECT_DIR") 的 Release 签名已配置。"
echo "若尚未配置蒲公英/钉钉，请执行:"
echo "  ~/tools/scripts/setup-shared-secrets.sh --repos <owner/repo,...>"
