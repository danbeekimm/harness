#!/usr/bin/env bash
# PostToolUse 훅(Edit, Write): 수정 직후 문법 검사.
# 대상: json, xml, js(mjs, cjs), sh. 실패하면 종료 코드 2와 함께 오류를 stderr로 돌려준다.
# 검사 도구가 없으면 조용히 넘어간다(막지 않는다).

command -v node >/dev/null 2>&1 || exit 0

file=$(node -e '
let d = {};
try { d = JSON.parse(require("fs").readFileSync(0, "utf8")); } catch (e) {}
process.stdout.write((d.tool_input && d.tool_input.file_path) || "");
')

[ -n "$file" ] || exit 0
file=${file//\\//}
[ -f "$file" ] || exit 0

name=$(basename "$file")
lower=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')

fail() {
  {
    echo "check-edit: $file 문법 오류. 고친 뒤 다음 작업으로 넘어간다."
    echo "$1"
  } >&2
  exit 2
}

case "$lower" in
  tsconfig*.json|jsconfig*.json|*.jsonc)
    # 주석을 허용하는 JSON은 검사하지 않는다.
    ;;
  *.json)
    out=$(node -e '
      try { JSON.parse(require("fs").readFileSync(process.argv[1], "utf8").replace(/^﻿/, "")); }
      catch (e) { console.error(e.message); process.exit(1); }
    ' "$file" 2>&1) || fail "$out"
    ;;
  *.js|*.mjs|*.cjs)
    out=$(node --check "$file" 2>&1) || fail "$out"
    ;;
  *.sh)
    out=$(bash -n "$file" 2>&1) || fail "$out"
    ;;
  *.xml)
    if command -v xmllint >/dev/null 2>&1; then
      out=$(xmllint --noout "$file" 2>&1) || fail "$out"
    fi
    ;;
esac

exit 0
