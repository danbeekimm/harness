#!/usr/bin/env bash
# 하네스를 대상 프로젝트로 복사한다. 이미 있는 파일은 덮어쓰지 않는다.
#
# 사용법:
#   ./install.sh <대상 프로젝트 디렉터리>
#
# 복사 대상:
#   CLAUDE.md
#   .claude/          (settings.local.json 제외)
#   docs/plans/_template/
#
# 복사 후 대상 프로젝트에서 Claude Code를 열고 /init-harness 를 실행한다.

set -euo pipefail

src="$(cd "$(dirname "$0")" && pwd)"
target="${1:-}"

if [ -z "$target" ]; then
  echo "사용법: $0 <대상 프로젝트 디렉터리>" >&2
  exit 1
fi
if [ ! -d "$target" ]; then
  echo "대상 디렉터리가 없다: $target" >&2
  exit 1
fi

target="$(cd "$target" && pwd)"

if [ "$src" = "$target" ]; then
  echo "대상이 하네스 저장소 자신이다. 다른 프로젝트 디렉터리를 지정한다." >&2
  exit 1
fi

copied=0
skipped=0
skipped_list=""

copy_file() {
  local rel="$1"
  local from="$src/$rel"
  local to="$target/$rel"

  if [ -e "$to" ]; then
    skipped=$((skipped + 1))
    skipped_list="${skipped_list}  ${rel}
"
    return
  fi

  mkdir -p "$(dirname "$to")"
  cp "$from" "$to"
  copied=$((copied + 1))
  echo "복사: $rel"
}

copy_file "CLAUDE.md"

while IFS= read -r file; do
  rel="${file#"$src"/}"
  case "$rel" in
    .claude/settings.local.json) continue ;;
  esac
  copy_file "$rel"
done < <(find "$src/.claude" "$src/docs/plans/_template" -type f | LC_ALL=C sort)

chmod +x "$target"/.claude/hooks/*.sh 2>/dev/null || true

echo
echo "복사 ${copied}개, 건너뜀 ${skipped}개"

if [ "$skipped" -gt 0 ]; then
  echo
  echo "이미 있어서 건너뛴 파일(덮어쓰지 않았다. 필요하면 직접 비교해 합친다):"
  printf '%s' "$skipped_list"
fi

if ! command -v node >/dev/null 2>&1; then
  echo
  echo "주의: node를 찾을 수 없다. 훅(guard-paths.sh, check-edit.sh)과 Playwright에 node가 필요하다."
fi

if [ ! -d "$target/.git" ]; then
  echo
  echo "주의: 대상이 git 저장소가 아니다. 커밋 규칙과 리뷰가 git에 기대고 있다."
fi

echo
echo "다음 단계: 대상 프로젝트에서 Claude Code를 열고 /init-harness 를 실행한다."
