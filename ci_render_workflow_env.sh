#!/usr/bin/env bash
# 根据 ci-build-secrets.manifest 生成 workflow Build 步骤的 env 片段（供复制粘贴）。
#
# 用法:
#   ~/tools/scripts/ci_render_workflow_env.sh signing/ci-build-secrets.manifest
set -euo pipefail

MANIFEST="${1:-signing/ci-build-secrets.manifest}"

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

if [[ ! -f "$MANIFEST" ]]; then
  echo "未找到 $MANIFEST" >&2
  exit 1
fi

echo "# 粘贴到 .github/workflows/release-notify.yml 的 Build Release APK env:"
while IFS= read -r line || [[ -n "$line" ]]; do
  line="$(trim "$line")"
  [[ -z "$line" || "$line" == \#* ]] && continue
  IFS='|' read -r secret_name _ _ <<< "$line"
  secret_name="$(trim "${secret_name:-}")"
  [[ -z "$secret_name" ]] && continue
  echo "          ${secret_name}: \${{ secrets.${secret_name} }}"
done < "$MANIFEST"

echo ""
echo "# Build 步骤 run 片段:"
echo "          chmod +x gradlew"
echo "          _tools/ci_check_build_secrets.sh signing/ci-build-secrets.manifest"
echo "          ./gradlew assembleRelease"
