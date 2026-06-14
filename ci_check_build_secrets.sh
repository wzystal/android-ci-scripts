#!/usr/bin/env bash
# CI Release 构建前检查 manifest 中的 required 密钥是否已通过环境变量注入。
#
# 用法（在 workflow Build 步骤中，assembleRelease 之前）:
#   _tools/ci_check_build_secrets.sh signing/ci-build-secrets.manifest
set -euo pipefail

MANIFEST="${1:-signing/ci-build-secrets.manifest}"

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

if [[ ! -f "$MANIFEST" ]]; then
  echo "未找到 $MANIFEST，跳过构建密钥检查"
  exit 0
fi

missing=()
optional_empty=()

while IFS= read -r line || [[ -n "$line" ]]; do
  line="$(trim "$line")"
  [[ -z "$line" || "$line" == \#* ]] && continue

  IFS='|' read -r secret_name local_key requirement label <<< "$line"
  secret_name="$(trim "${secret_name:-}")"
  requirement="$(trim "${requirement:-}")"
  label="$(trim "${label:-$secret_name}")"

  [[ -z "$secret_name" ]] && continue

  value="$(printenv "$secret_name" 2>/dev/null || true)"
  value="$(trim "$value")"

  if [[ -z "$value" ]]; then
    if [[ "$requirement" == "required" ]]; then
      missing+=("$secret_name ($label)")
    else
      optional_empty+=("$secret_name")
    fi
  fi
done < "$MANIFEST"

if [[ ${#optional_empty[@]} -gt 0 ]]; then
  echo "可选密钥未配置（将使用 Gradle 默认值）: ${optional_empty[*]}"
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "::error::以下 required 构建密钥未配置: ${missing[*]}"
  echo "请在本机执行: ~/tools/scripts/setup-app-build-secrets.sh --project-dir <项目目录>"
  exit 1
fi

echo "构建密钥检查通过 ($MANIFEST)"
