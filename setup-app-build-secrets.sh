#!/usr/bin/env bash
# 根据项目 manifest 将构建密钥写入 GitHub Secrets（不提交到 Git）。
#
# 用法:
#   ~/tools/scripts/setup-app-build-secrets.sh --project-dir ~/work/AiChatHub
#   ~/tools/scripts/setup-app-build-secrets.sh --project-dir ~/work/Foo --manifest signing/ci-build-secrets.manifest wzystal/Foo
set -euo pipefail

PROJECT_DIR="$(pwd)"
MANIFEST="signing/ci-build-secrets.manifest"
REPO_ARGS=()

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# 去除控制字符（含 ESC 0x1b），避免写入 GitHub Secret 后导致 Authorization 头非法
sanitize_secret() {
  local raw="$1"
  printf '%s' "$raw" | LC_ALL=C tr -d '\000-\037\177'
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
  setup-app-build-secrets.sh --project-dir <路径> [--manifest <文件>] [owner/repo]

读取项目 signing/ci-build-secrets.manifest，将密钥写入 GitHub Secrets。

值来源（每条密钥，按优先级）:
  1. 同名环境变量（如 DEEPSEEK_API_KEY）
  2. local.properties 中 manifest 指定的键
  3. 交互输入（敏感项以 * 显示长度）

示例:
  setup-app-build-secrets.sh --project-dir ~/work/AiChatHub
  DEEPSEEK_API_KEY=sk-xxx setup-app-build-secrets.sh --project-dir ~/work/AiChatHub

新建项目: 复制 ~/tools/scripts/ci-build-secrets.manifest.example 到项目 signing/ci-build-secrets.manifest 并编辑。

前置: gh auth login -h github.com
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --manifest) MANIFEST="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) REPO_ARGS+=("$1"); shift ;;
  esac
done

PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
MANIFEST="$PROJECT_DIR/$MANIFEST"

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

if [[ ! -f "$MANIFEST" ]]; then
  echo "未找到 manifest: $MANIFEST" >&2
  echo "请复制模板: cp ~/tools/scripts/ci-build-secrets.manifest.example signing/ci-build-secrets.manifest" >&2
  exit 1
fi

REPO="$(resolve_repo)"
LOCAL_PROPS="$PROJECT_DIR/local.properties"

if ! gh repo view "$REPO" --json name >/dev/null 2>&1; then
  echo "仓库不存在或无权限: $REPO" >&2
  exit 1
fi

echo "项目目录: $PROJECT_DIR"
echo "Manifest:  $MANIFEST"
echo "目标仓库: $REPO"
echo ""

set_count=0
skip_count=0

parse_manifest_line() {
  local line="$1"
  secret_name=""
  local_key=""
  requirement=""
  label=""
  IFS='|' read -r secret_name local_key requirement label <<< "$line"
  secret_name="$(trim "${secret_name:-}")"
  local_key="$(trim "${local_key:-}")"
  requirement="$(trim "${requirement:-}")"
  label="$(trim "${label:-${secret_name:-secret}}")"
}

while IFS= read -r line || [[ -n "$line" ]]; do
  line="$(trim "$line")"
  [[ -z "$line" || "$line" == \#* ]] && continue

  parse_manifest_line "$line"

  [[ -z "$secret_name" ]] && continue

  value="$(printenv "$secret_name" 2>/dev/null || true)"
  value="$(trim "$value")"

  if [[ -z "$value" && -f "$LOCAL_PROPS" && -n "$local_key" ]]; then
    value="$(trim "$(grep -E "^${local_key}=" "$LOCAL_PROPS" 2>/dev/null | head -1 | cut -d= -f2- || true)")"
  fi

  if [[ -z "$value" ]]; then
    if [[ "${requirement:-}" == "required" ]]; then
      echo "[$secret_name] ${label:-$secret_name}（required）"
      read_masked "  > " value
      value="$(trim "$value")"
    else
      echo "[$secret_name] ${label:-$secret_name}（optional，回车跳过）"
      read_masked "  > " value
      value="$(trim "$value")"
    fi
  fi

  if [[ -z "$value" ]]; then
    if [[ "${requirement:-}" == "required" ]]; then
      echo "  跳过 required 密钥 $secret_name，整条 manifest 写入中止。" >&2
      exit 1
    fi
    echo "  已跳过 optional: $secret_name"
    skip_count=$((skip_count + 1))
    continue
  fi

  value="$(sanitize_secret "$value")"
  value="$(trim "$value")"

  if [[ -z "$value" ]]; then
    echo "  密钥 $secret_name 清洗后为空，已跳过。" >&2
    exit 1
  fi

  gh secret set "$secret_name" --repo "$REPO" --body "$value"
  echo "  ✓ $secret_name"
  set_count=$((set_count + 1))
done < "$MANIFEST"

echo ""
echo "完成: 写入 $set_count 项, 跳过 $skip_count 项"
echo "验证: gh secret list --repo $REPO"
