# 웹 공용 하네스 설계

Spring Boot 웹 프로젝트에서 Claude Code로 "기획안 → 계획 → 개발 → 리뷰 → 검증"을 진행하기 위한 하네스의 설계와 확정 사항이다. 참고 하네스와 무엇이 달라졌는지는 `CHANGES.md`에 있다.

## 1. 목적과 원칙

참고 하네스의 리뷰 방식(두 관점의 독립 서브에이전트, 보고 조건, 라운드 상한)을 유지하면서, 한 프로젝트에 묶여 있던 내용을 걷어 내고 여러 웹 프로젝트에 그대로 복사해 쓸 수 있게 만든다.

1. **프로젝트 고유 내용은 프로필 한 곳에만 둔다.** 에이전트와 스킬 본문에는 프로젝트 이름, 모듈명, 명령, 경로를 적지 않고 프로필의 섹션 이름으로 참조한다.
2. **금지는 문장이 아니라 장치로 강제한다.** "열지 않는다"는 지시에 더해 권한 설정의 `deny`와 훅으로 차단한다.
3. **단계 진입은 계획 문서의 상태로 제어한다.** 대화의 흐름이 아니라 `status`와 미결 사항 개수가 다음 단계로 갈 수 있는지를 정한다.
4. **보고가 진행보다 먼저다.** 사용자의 결정이 필요한 문제는 추측으로 넘기지 않고 멈춰서 보고한다.
5. **작업 하나에 커밋 하나.** 메인 세션이 커밋하고, 푸시는 차단한다.

## 2. 구성

```
CLAUDE.md                          일반 지침: 작업 흐름, 보고 우선, 커밋 규칙, 리뷰 False Positive 정책
HARNESS.md                         이 문서
CHANGES.md                         참고 하네스 대비 변경 사항
install.sh                         대상 프로젝트로 복사(기존 파일은 덮어쓰지 않음)
.claude/
  settings.json                    권한(allow, ask, deny)과 훅 등록
  rules/
    project-profile.md             프로젝트마다 채우는 프로필
    backend-spring.md              Spring Boot 서버 규칙(고정)
    frontend.md  db.md  test.md    파일 종류별 규칙. paths로 대상 지정
  agents/
    code-reviewer.md               결함 리뷰            fable, effort high
    refactoring-specialist.md      리팩터링 리뷰        fable, effort high
    db-helper.md                   스키마 확인·조회     sonnet, effort medium
    tester.md                      수용 기준 E2E        sonnet, effort medium
  skills/
    init-harness/                  프로필 채우기, Playwright 준비
    plan/                          기획안 → 계획 문서, 결정 질문
    dev/                           계획 문서 → 구현·커밋 → 리뷰·테스트 → 보고
    revref/                        두 관점 리뷰와 반영(최대 5라운드)
    verify/                        수용 기준 E2E 검증(tester 최대 2회)
  hooks/
    guard-paths.sh                 PreToolUse: 금지 경로 접근 차단
    forbidden-paths.txt            금지 경로 목록
    check-edit.sh                  PostToolUse: 수정 직후 문법 검사(json, xml, js, sh)
    session-status.sh              SessionStart: 진행 중인 기획안 표시
  scripts/
    extract_spec.py                xlsx·pptx·docx·pdf 기획안을 텍스트로 추출
  templates/
    e2e/                           Playwright 설정과 예시 테스트
docs/plans/
  _template/plan.md                계획 문서 양식
  <slug>/plan.md                   기획안별 계획 문서
```

## 3. 프로필

`.claude/rules/project-profile.md`는 `paths`가 없는 규칙 파일이라 모든 세션에 항상 로드된다. 섹션은 다음과 같고, 이름이 곧 참조 키다.

| 섹션 | 내용 | 참조하는 곳 |
|------|------|-------------|
| 스택 | Spring Boot·Java 버전, 데이터 접근 방식, DBMS, 마이그레이션 도구, 화면 | 전체 |
| 명령 | 빌드, 테스트, 서버 기동, E2E 실행 | `/dev`, `revref`, `/verify`, `tester` |
| 디렉터리 | 계층별 코드 위치 | 리뷰 에이전트, 규칙 파일의 `paths` |
| DB 접속 | 접속 방법, 계정 권한 | `db-helper` |
| 재사용 우선 대상 | 공용 유틸·컴포넌트 | `refactoring-specialist`, `/dev` |
| 리뷰 체크리스트 | 프로젝트 고유 점검 항목 | `code-reviewer` |
| 금지 경로 | 프로젝트 고유 금지 경로 | `guard-paths.sh`(목록 파일에도 추가) |
| E2E | 기준 URL, 계정, 데이터 준비 | `tester`, `/verify` |

채워지지 않은 항목은 `<미입력>`으로 표시한다. `<미입력>`이 남아 있으면 `/plan`과 `/dev`는 시작하지 않는다.

## 4. 파이프라인

```
/init-harness   (프로젝트당 한 번)
      │
기획안 파일 ──▶ /plan ──▶ plan.md (draft ⇄ 결정 질문 ⇄ ready)
                               │            ── 세션을 새로 연다 ──
                               ▼
                            /dev ──▶ 작업마다 구현·테스트·커밋
                               │         └▶ revref (두 패스 동시, 최대 5라운드, 지적마다 커밋)
                               │         └▶ 전체 테스트
                               ▼
                          implemented
                               │
                               ▼
                           /verify ──▶ tester (최대 2회)
                               │
                               ▼
                           verified ──▶ 사용자가 검토 후 푸시
```

- `/plan`은 코드를 쓰지 않는다. 기획안과 코드만으로 정할 수 없는 것을 미결 사항으로 뽑아 선택지·권장안과 함께 묻는다.
- `/dev`는 작업 목록을 위에서 아래로 진행하며 항목 하나마다 커밋한다. 결정이 필요한 문제를 만나면 미결 사항에 추가하고 멈춘다.
- `/verify`는 수용 기준마다 Playwright 테스트를 만들어 실행한다. 실패하면 고치고 한 번 더 검증한다.

## 5. 계획 문서와 상태

계획 문서는 `docs/plans/<slug>/plan.md`이고 양식은 `docs/plans/_template/plan.md`다. frontmatter의 `status`와 `미결 사항` 절의 체크 안 된 항목 수가 단계 진입을 제어한다.

| status | 뜻 | 바꾸는 스킬 | 다음으로 가는 조건 |
|--------|----|-------------|--------------------|
| `draft` | 계획 작성 중 | `/plan` | 미결 사항 0건, 수용 기준·작업 목록 작성 |
| `ready` | 개발을 시작할 수 있음 | `/plan` | `/dev` 시작 |
| `in-progress` | 개발 중 | `/dev` | 작업 목록 완료, 남은 P0~P2 없음, 전체 테스트 통과, 미결 사항 0건 |
| `implemented` | 구현·리뷰·테스트 완료 | `/dev` | 수용 기준 E2E 전부 통과 |
| `verified` | 검증 완료 | `/verify` | 끝 |

- 개발 중에 미결 사항이 생기면 `status`는 `in-progress`에 머물고, 미결 사항이 0건이 될 때까지 리뷰 단계로 가지 않는다.
- `session-status.sh`가 세션을 시작할 때 `verified`가 아닌 계획의 상태, 미결 건수, 작업 진행 수, 다음에 실행할 스킬을 보여 준다.
- 계획 문서의 `의도된 변경`은 리뷰어가 의도적인 변경을 결함으로 지적하지 않게 하는 장치다.

## 6. 리뷰

- 리뷰는 **결함 관점**(`code-reviewer`)과 **리팩터링 관점**(`refactoring-specialist`)의 독립 서브에이전트 두 개로 나눈다. 한 메시지에서 동시에 호출한다.
- 서브에이전트에는 **정확한 범위**(커밋 범위)와 계획 문서 경로만 준다. 서로의 결과, 이전 라운드의 지적, 메인 세션의 예상은 넘기지 않는다. 가설을 받은 리뷰어는 그 가설을 확인해 주는 쪽으로 기운다.
- 보고 기준은 하나다. **"작성자가 알면 고칠 가능성이 높은가."** 이번 변경이 만든 문제이고, 구체적인 상황을 댈 수 있고, 코드로 확인했고, 취향이 아닌 것만 보고한다.
- 결과 형식: 결함은 `[P0]`~`[P3]`, 리팩터링은 `R1`~.
- 메인 세션은 지적을 직접 확인한 뒤 반영, 반영 안 함(False Positive·의도된 변경·범위 밖), 미결로 분류한다. `[P0]`·`[P1]`은 코드로 확인한 반증 없이 넘기지 않는다.
- 반영은 **지적 하나마다 커밋**한다.
- 라운드는 **최대 5회**다. 반영한 것이 없거나, 반영한 것이 `[P3]`·리팩터링뿐이거나, 미결이 생기면 끝낸다. 2라운드부터는 직전 라운드의 반영 커밋만 본다.
- 최종 보고 순서: 미결 사항 → 남은 지적 → 반영한 것 → 반영하지 않은 것과 이유 → 검증 → 라운드 수.
- 리뷰 뒤에는 `/verify`가 수용 기준을 E2E로 확인한다. `tester` 호출은 계획 하나에 최대 2회다.

## 7. 권한과 훅

### 7.1 권한 (`.claude/settings.json`)

| 구분 | 내용 |
|------|------|
| `allow` | 읽기성 git 명령, `git add`·`git commit`, Gradle·Maven 래퍼, `npx playwright test`, `extract_spec.py` 실행 등 파이프라인에 필요한 좁은 범위 |
| `ask` | `ssh`, `scp`, `curl`, `wget`, `git reset`·`rebase`·`checkout`·`restore`·`clean`·`stash`·`merge`, `rm`, `npm install`, `npx playwright install` |
| `deny` | `git push`, `git commit --amend`, `.env`·키·인증서·자격 증명 파일의 `Read`와 `Edit` |

- 임의 코드 실행 명령(`python3`, `node`)과 `find`, `awk`, 홈 디렉터리 전체 `Read`는 `allow`에 넣지 않았다. 목록에 없는 명령은 실행 전에 사용자에게 묻는다.
- `python3`은 `extract_spec.py` 실행에 한해서만 허용한다.
- `.env.example`처럼 값이 없는 예시 파일도 `.env.*` 패턴에 걸려 차단된다. `deny`에는 예외를 둘 수 없으므로, 예시 파일은 사용자가 직접 관리하거나 `env.example`처럼 패턴에 걸리지 않는 이름을 쓴다.
- 개인 설정은 `.claude/settings.local.json`에 둔다. 이 파일은 `install.sh`가 복사하지 않고 `.gitignore`에 들어 있다. 팀 공용 `deny`를 개인 `allow`로 풀 수 없다(`deny`가 우선한다).

### 7.2 훅

| 훅 | 시점 | 동작 | 실패 시 |
|----|------|------|---------|
| `guard-paths.sh` | PreToolUse (Read, Edit, Write, NotebookEdit, Glob, Grep, Bash, PowerShell) | 도구 입력의 경로와 명령 토큰을 `forbidden-paths.txt`의 glob과 대조 | 종료 코드 2로 호출 차단, 사유를 모델에 전달 |
| `check-edit.sh` | PostToolUse (Edit, Write) | 수정한 파일의 문법 검사: json, js, sh, xml(xmllint가 있을 때) | 종료 코드 2로 오류를 모델에 전달 |
| `session-status.sh` | SessionStart | 진행 중인 계획의 상태 출력 | 출력 없음 |

훅은 `bash`와 `node`가 필요하다. `node`는 Playwright 때문에 어차피 필요하므로 훅의 JSON 처리도 `node`로 한다. Windows에서는 Git Bash가 있어야 한다.

`guard-paths.sh`는 `node`가 없거나 입력을 해석하지 못하면 차단한다(닫힌 쪽으로 실패). `check-edit.sh`는 검사 도구가 없으면 통과시킨다.

## 8. 모델 배정

단계마다 필요한 만큼의 모델을 쓴다.

| 역할 | 모델 | effort | 이유 |
|------|------|--------|------|
| `code-reviewer`, `refactoring-specialist` | fable | high | 놓친 결함의 비용이 가장 크다 |
| `tester` | sonnet | medium | 수용 기준이 정해져 있고 실행 결과로 검증된다 |
| `db-helper` | sonnet | medium | 조회와 초안 작성. 결과를 메인 세션이 다시 확인한다 |
| 메인 세션(`/plan`, `/dev`, `/verify`) | 세션에서 선택 | | 계획과 개발을 다른 세션으로 나누므로 세션마다 다르게 고를 수 있다 |

계획과 개발을 다른 세션에서 진행하는 것도 같은 목적이다. 계획 세션에서 쌓인 탐색 내용을 개발 세션이 다시 읽지 않는다.

## 9. 알려진 한계

### 9.1 금지 경로 훅은 우회할 수 있다

`guard-paths.sh`는 셸 명령을 토큰으로 나눠 경로처럼 보이는 것을 대조한다. 변수 치환, 와일드카드(`cat .e*`), 인코딩, 스크립트 파일을 거친 접근은 잡지 못한다. 반대로 커밋 메시지나 검색어에 `.env` 같은 단어가 들어가면 잘못 차단한다.

이 훅은 실수로 여는 것을 막는 장치이지 격리가 아니다. 1차 방어선은 `deny`와 좁은 `allow`(임의 코드 실행 명령을 허용하지 않음)이고, 정말 보호해야 하는 비밀은 작업 디렉터리에 두지 않는다.

### 9.2 DB 읽기 전용은 계정 권한으로만 보장된다

참고 하네스의 `db.sh`는 쿼리 문자열에서 주석을 지운 뒤 금지어를 찾는 방식으로 읽기 전용을 강제했다. 주석을 지우는 정규식이 문자열 리터럴 안의 `#`, `--`까지 지워서 `SELECT '#'; DELETE ...` 같은 입력이 검사를 통과했다.

쿼리 문자열 검사로 읽기 전용을 보장하려면 SQL 파서가 필요하고, 그래도 방언마다 구멍이 남는다. 그래서 스크립트를 넣지 않았다. 개발·운영 DB에는 **SELECT 전용 계정**으로 접속하도록 프로필의 `DB 접속`에 적는다. `db-helper`의 "읽기 전용 문만 실행한다"는 지시일 뿐 보호 장치가 아니다.

### 9.3 읽기 전용 에이전트에 Bash가 있다

`code-reviewer`, `refactoring-specialist`, `db-helper`는 `Edit`·`Write` 도구가 없지만 `git diff`와 DB 접속을 위해 `Bash`를 가진다. `Bash`로 파일을 고치거나 저장소 상태를 바꿀 수 있으므로 "수정하지 않는다"는 여전히 지시로만 지켜진다. 참고 하네스와 같은 한계다.

줄이는 장치는 있다. 서브에이전트의 명령도 같은 권한 설정과 훅을 거치므로 `allow`에 없는 명령은 사용자 확인을 받고, `git push`와 금지 경로는 차단된다. 없애려면 리뷰 에이전트에서 `Bash`를 빼고 메인 세션이 diff를 파일로 만들어 넘겨야 하는데, 리뷰어가 변경 주변 코드를 이력과 함께 볼 수 없게 되어 채택하지 않았다.

### 9.4 그 밖에

- `check-edit.sh`는 문법만 본다. Java·TypeScript 컴파일 오류는 빌드 명령이 잡는다.
- `extract_spec.py`는 이미지 안의 글자를 읽지 못한다. 화면 설계가 이미지뿐인 기획안은 `/plan`이 그 사실을 알리고 멈춘다.
- 규칙 파일의 `paths`는 흔한 구조를 기본값으로 둔 것이다. `/init-harness`가 프로젝트 구조에 맞게 고친다.
- `db.sh` 같은 DB 접속 스크립트는 들어 있지 않다. 프로젝트에서 추가하고 프로필의 `DB 접속`에 사용법을 적는다.

## 10. 확정 사항

| 번호 | 확정 내용 |
|------|-----------|
| 1 | 서버는 Spring Boot, E2E는 Playwright로 고정한다. 나머지 스택은 프로필에 적는다 |
| 2 | 프로젝트 고유 내용은 프로필 한 곳에만 두고, 에이전트·스킬은 섹션 이름으로 참조한다 |
| 3 | 리뷰는 결함·리팩터링 두 관점의 독립 서브에이전트로 하고, 서로의 결과를 넘기지 않는다 |
| 4 | 리뷰 라운드는 최대 5회, `tester` 호출은 최대 2회다 |
| 5 | 커밋은 메인 세션이 작업 하나·지적 하나마다 한다. 서브에이전트는 커밋하지 않는다 |
| 6 | 푸시와 `--amend`는 `deny`로 차단한다. 푸시는 사용자가 한다 |
| 7 | 단계 진입은 계획 문서의 `status`와 미결 사항 개수로 제어한다 |
| 8 | 계획과 개발은 다른 세션에서 진행한다 |
| 9 | 모델은 리뷰 fable, 테스트·DB sonnet으로 지정하고 effort도 지정한다 |
| 10 | DB 접속 스크립트는 넣지 않는다. 읽기 전용은 SELECT 전용 계정으로 보장한다 |
| 11 | 금지 경로는 `deny`와 훅으로 강제한다 |
| 12 | `install.sh`는 기존 파일을 덮어쓰지 않는다 |

## 11. 설치

```
./install.sh <대상 프로젝트 디렉터리>
```

`CLAUDE.md`, `.claude/`(`settings.local.json` 제외), `docs/plans/_template/`를 복사한다. 이미 있는 파일은 건너뛰고 목록으로 보여 준다. 복사한 뒤 대상 프로젝트에서 Claude Code를 열고 `/init-harness`를 실행한다.

필요한 것: git, bash(Windows는 Git Bash), node. 기획안이 xlsx·pptx·docx·pdf면 Python 3, pdf면 `pypdf` 또는 `pdftotext`도 필요하다.
