#!/usr/bin/env bash
# 兼容入口：转调通用 setup-app-build-secrets.sh（需项目含 signing/ci-build-secrets.manifest）
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARGS=()
PROJECT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; ARGS+=(--project-dir "$2"); shift 2 ;;
    -h|--help)
      exec "$SCRIPT_DIR/setup-app-build-secrets.sh" --help
      ;;
    *) ARGS+=("$1"); shift ;;
  esac
done

if [[ -z "$PROJECT_DIR" ]]; then
  PROJECT_DIR="${PWD}"
  ARGS=(--project-dir "$PROJECT_DIR" "${ARGS[@]}")
fi

exec "$SCRIPT_DIR/setup-app-build-secrets.sh" "${ARGS[@]}"
