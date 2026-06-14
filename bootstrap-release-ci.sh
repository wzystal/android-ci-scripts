#!/usr/bin/env bash
# 为 Android 项目接入 Release CI 工作流（脚本统一放在 ~/tools/scripts）。
set -euo pipefail

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SCRIPTS_REPO="${SHARED_SCRIPTS_REPO:-wzystal/android-ci-scripts}"

usage() {
  cat <<EOF
用法:
  bootstrap-release-ci.sh <项目目录> [--expo]

示例:
  bootstrap-release-ci.sh ~/work/AiChatHub
  bootstrap-release-ci.sh ~/work/BridgeGame --expo

说明:
  - CI 运行时从 GitHub 仓库 ${SHARED_SCRIPTS_REPO} 拉取共享脚本
  - 本地签名: ~/tools/scripts/generate-release-keystore.sh <项目>
  - 本地 Secrets: ~/tools/scripts/setup-github-secrets.sh --project-dir <项目>
  - 共享 Secrets: ~/tools/scripts/setup-shared-secrets.sh
EOF
}

TARGET=""
EXPO=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --expo) EXPO=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      [[ -z "$TARGET" ]] || { echo "未知参数: $1" >&2; usage >&2; exit 1; }
      TARGET="$1"
      shift
      ;;
  esac
done

[[ -n "$TARGET" ]] || { usage >&2; exit 1; }
TARGET="$(cd "$TARGET" && pwd)"

mkdir -p "$TARGET/signing"
if [[ ! -f "$TARGET/signing/README.md" ]]; then
  cat > "$TARGET/signing/README.md" <<EOF
# Release 签名（本地）

脚本统一放在 \`~/tools/scripts/\`，不在各项目中重复维护。

\`\`\`bash
~/tools/scripts/generate-release-keystore.sh "$TARGET"
~/tools/scripts/setup-github-secrets.sh --project-dir "$TARGET"
~/tools/scripts/setup-shared-secrets.sh
\`\`\`
EOF
fi

echo "项目: $TARGET"
echo "类型: $([ "$EXPO" = true ] && echo Expo/RN || echo 原生 Android)"
echo ""
echo "共享脚本目录: $TOOLS_DIR"
echo "CI 脚本仓库:  $SHARED_SCRIPTS_REPO"
echo ""
echo "请确保 .github/workflows/release-notify.yml 已配置 checkout ${SHARED_SCRIPTS_REPO}。"
echo "下一步:"
echo "  ~/tools/scripts/generate-release-keystore.sh \"$TARGET\""
