#!/usr/bin/env bash
# PreToolUse 훅: 금지 경로 접근 차단.
# 표준 입력으로 받은 도구 호출 JSON에서 경로 후보를 뽑아 forbidden-paths.txt와 대조한다.
# 일치하면 종료 코드 2로 호출을 막고 사유를 stderr로 돌려준다.
#
# 한계: 셸 명령은 토큰 단위로만 검사한다. 변수 치환이나 인코딩으로 경로를 조립하면
# 통과한다. 1차 방어선은 settings.json의 deny이고, 이 훅은 그 위에 얹는 보조 장치다.

dir="$(cd "$(dirname "$0")" && pwd)"
list="$dir/forbidden-paths.txt"

[ -f "$list" ] || exit 0

if ! command -v node >/dev/null 2>&1; then
  echo "guard-paths: node를 찾을 수 없어 금지 경로 검사를 할 수 없다. node를 설치하거나 PATH를 확인한다." >&2
  exit 2
fi

script=$(cat <<'EOF'
const fs = require("fs");

const listFile = process.argv[1];

let raw = "";
try { raw = fs.readFileSync(0, "utf8"); } catch (e) { /* 입력 없음 */ }

let input;
try {
  input = JSON.parse(raw);
} catch (e) {
  console.error("guard-paths: 훅 입력을 해석하지 못해 호출을 차단한다.");
  process.exit(2);
}

const patterns = fs.readFileSync(listFile, "utf8")
  .split(/\r?\n/)
  .map((s) => s.trim())
  .filter((s) => s && !s.startsWith("#"));

function toRegex(glob) {
  let re = "";
  for (let i = 0; i < glob.length; i++) {
    const c = glob[i];
    if (c === "*") {
      if (glob[i + 1] === "*") {
        i++;
        if (glob[i + 1] === "/") { i++; re += "(?:.*/)?"; }
        else re += ".*";
      } else {
        re += "[^/]*";
      }
    } else if (c === "?") {
      re += "[^/]";
    } else {
      re += c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
    }
  }
  return new RegExp("(?:^|/)" + re + "(?:/|$)", "i");
}

const rules = patterns.map((p) => ({ pattern: p, regex: toRegex(p) }));

const toolInput = input.tool_input || {};
const candidates = [];

for (const key of ["file_path", "notebook_path", "path", "glob"]) {
  if (typeof toolInput[key] === "string") candidates.push(toolInput[key]);
}
if (input.tool_name === "Glob" && typeof toolInput.pattern === "string") {
  candidates.push(toolInput.pattern);
}
if (typeof toolInput.command === "string") {
  for (const token of toolInput.command.split(/[\s"'`=<>|;&(),:{}\[\]$]+/)) {
    if (token) candidates.push(token);
  }
}

for (const candidate of candidates) {
  const normalized = candidate.replace(/\\/g, "/");
  for (const rule of rules) {
    if (rule.regex.test(normalized)) {
      console.error(
        "guard-paths: 금지 경로 접근을 차단했다. 대상 '" + candidate +
        "' 이(가) 패턴 '" + rule.pattern + "' 에 해당한다. " +
        "이 경로는 열거나 수정하지 않는다. 꼭 필요하면 사용자에게 보고하고 지시를 기다린다. " +
        "(목록: .claude/hooks/forbidden-paths.txt)"
      );
      process.exit(2);
    }
  }
}
process.exit(0);
EOF
)

node -e "$script" "$list"
