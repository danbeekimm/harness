#!/usr/bin/env bash
# SessionStart 훅: 진행 중인 기획안을 세션 컨텍스트에 표시한다.
# docs/plans/<slug>/plan.md 의 status, 미결 사항 수, 남은 작업 수를 한 줄씩 출력한다.
# status가 verified 인 계획과 _template 은 건너뛴다.

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
plans="$root/docs/plans"

[ -d "$plans" ] || exit 0

lines=""
for plan in "$plans"/*/plan.md; do
  [ -f "$plan" ] || continue
  slug=$(basename "$(dirname "$plan")")
  [ "$slug" = "_template" ] && continue

  summary=$(awk '
    BEGIN { fm = 0; status = "?"; section = ""; open = 0; todo = 0; done = 0 }
    { sub(/\r$/, "") }
    /^---[ \t]*$/ { fm++; next }
    fm == 1 && /^status:/ { s = $0; sub(/^status:[ \t]*/, "", s); sub(/[ \t]+#.*$/, "", s); status = s; next }
    /^## / {
      if ($0 ~ /미결 사항/) section = "open"
      else if ($0 ~ /작업 목록/) section = "task"
      else section = ""
      next
    }
    section == "open" && /^[ \t]*- \[ \]/ { open++ }
    section == "task" && /^[ \t]*- \[ \]/ { todo++ }
    section == "task" && /^[ \t]*- \[[xX]\]/ { done++ }
    END { printf "%s\t%d\t%d\t%d", status, open, todo, done }
  ' "$plan")

  status=$(printf '%s' "$summary" | cut -f1)
  open=$(printf '%s' "$summary" | cut -f2)
  todo=$(printf '%s' "$summary" | cut -f3)
  done_count=$(printf '%s' "$summary" | cut -f4)

  [ "$status" = "verified" ] && continue

  case "$status" in
    draft)
      if [ "$open" -gt 0 ]; then next="미결 사항 결정 필요 (/plan $slug)"; else next="status를 ready로 올릴 수 있음 (/plan $slug)"; fi ;;
    ready)        next="/dev $slug" ;;
    in-progress)  next="/dev $slug (이어서)" ;;
    implemented)  next="/verify $slug" ;;
    *)            next="status 값 확인 필요" ;;
  esac

  lines="${lines}- ${slug}: status=${status}, 미결 ${open}건, 작업 ${done_count}/$((todo + done_count)) 완료 → ${next}
"
done

if [ -n "$lines" ]; then
  echo "진행 중인 기획안 (docs/plans):"
  printf '%s' "$lines"
fi

exit 0
