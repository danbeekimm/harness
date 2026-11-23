# 참고 하네스 대비 변경 사항

참고 하네스(`settings.local.json`, `code-reviewer.md`, `refactoring-specialist.md`, `sql-pro.md`, `revref/SKILL.md`, `db.sh`)와 새 웹 공용 하네스를 비교한 문서다.

구조와 리뷰 방식은 거의 그대로 가져왔다. 프로젝트 전용 내용을 걷어 내고, 기획안 파이프라인과 강제 장치를 새로 붙였다.

## 1. 파일별로 바뀐 것

| 원본 | 지금 | 바뀐 점 |
|------|------|---------|
| `code-reviewer.md` | 같은 이름 | 보고 조건과 `[P0]`~`[P3]` 형식은 그대로다. SAP RFC, TreeGrid, `resourceVersion.jsp`, `DDL_History.sql`, Java 8 같은 프로젝트 회귀 목록은 빼고 웹 기본 체크리스트 10개로 바꿨다. 프로젝트 고유 항목은 프로필을 참조한다. 계획 문서를 읽어 의도된 변경을 파악하는 단계와 `effort: high`를 추가했다. |
| `refactoring-specialist.md` | 같은 이름 | 조건과 `R1` 형식은 그대로다. `Utility`, `ContSupport` 같은 고유 모듈명 대신 프로필의 `재사용 우선 대상`을 참조한다. |
| `sql-pro.md` | `db-helper.md` | MariaDB·MyBatis·SAP 마스터 금지 등 고유 규칙을 뺐다. 접속 방법은 프로필의 `DB 접속`을 따르고, 쿼리 형태는 프로젝트의 데이터 접근 방식(JPA·MyBatis·SQL)에 맞춘다. 모델은 sonnet으로 지정했다. |
| `revref/SKILL.md` | 같은 이름 | 두 패스 동시 실행, 라운드 상한(최대 5회), 종료 조건, 보고 순서는 그대로다. JDK 경로가 박힌 Gradle 명령은 프로필의 `명령`으로 바꿨다. 프롬프트에 계획 문서 경로를 넘기고, 리뷰 반영을 항목별로 커밋하는 규칙을 추가했다. |
| `settings.local.json` | `settings.json` | 원본은 `allow`만 있었다. `python3`, `node`, `curl`, `ssh`, `find`, `awk`, 홈 디렉터리 전체 `Read`를 `allow`에서 뺐다. `ssh`·`curl`·`git reset` 등은 `ask`로, `git push`·`--amend`·`.env`·키 파일은 `deny`로 넣었다. 훅 3개도 여기에 등록했다. |
| `db.sh` | 없음 | MariaDB 전용이라 넣지 않았다. 프로젝트에서 추가하고 프로필에 사용법을 적는다. |

## 2. 새로 생긴 것

| 구분 | 파일 | 역할 |
|------|------|------|
| 일반론 | `CLAUDE.md` | 원본 파일들이 참조만 하던 문서를 새로 썼다. 보고 우선, 커밋 규칙, 리뷰 False Positive 정책 |
| 설계 | `HARNESS.md` | 하네스 전체 설계와 확정 사항 |
| 프로필 | `.claude/rules/project-profile.md` | 프로젝트마다 채우는 스택·명령·디렉터리·체크리스트 |
| 규칙 | `backend-spring.md` | Spring Boot 서버 규칙(고정) |
| 규칙 | `frontend.md`, `db.md`, `test.md` | 파일 종류별 규칙. `paths`로 대상 지정 |
| 스킬 | `/init-harness` | 프로젝트 시작 시 프로필 채우기, Playwright 준비 |
| 스킬 | `/plan` | 기획안 → 계획 문서, 결정 질문 |
| 스킬 | `/dev` | 계획 문서 → 작업 단위 구현·커밋 → 리뷰·테스트 → 보고 |
| 스킬 | `/verify` | 수용 기준 E2E 검증 |
| 에이전트 | `tester.md` | 수용 기준을 Playwright 시나리오로 작성·실행 |
| 훅 | `guard-paths.sh`, `forbidden-paths.txt` | 금지 경로 접근 차단 |
| 훅 | `check-edit.sh` | 수정 직후 문법 검사(json, xml, js, sh) |
| 훅 | `session-status.sh` | 세션 시작 시 진행 중인 기획안 표시 |
| 스크립트 | `extract_spec.py` | xlsx·pptx·docx·pdf 기획안을 텍스트로 추출 |
| 템플릿 | `docs/plans/_template/plan.md` | 계획 문서 양식 |
| 템플릿 | `.claude/templates/e2e/` | Playwright 설정과 예시 테스트 |
| 배포 | `install.sh` | 프로젝트로 복사(기존 파일은 덮어쓰지 않음) |

## 3. 동작 방식에서 달라진 것

| 항목 | 원본 | 지금 |
|------|------|------|
| 프로젝트 고유 내용의 위치 | 에이전트·스킬 본문에 직접 들어 있음 | 프로필 한 곳에만 있고, 에이전트는 섹션 이름으로 참조 |
| 금지의 강제 방식 | "열지 않는다"는 문장 | `deny`와 훅으로 차단 |
| 작업 단위 | 대화에서 수정한 파일 | `docs/plans/<slug>/plan.md`의 `status`와 미결 사항 개수로 단계 진입을 제어 |
| 커밋 | 에이전트는 커밋하지 않음 | 메인 세션이 작업 하나마다 커밋. 푸시는 차단 |
| 리뷰 뒤 단계 | 없음 | `/verify`로 E2E까지 확인(tester 최대 2회) |
| 스택 | Java 8, eGovFrame, MyBatis, MariaDB, SAP | 서버는 Spring Boot, E2E는 Playwright 고정. 나머지는 프로필 |
| 모델 지정 | 리뷰 에이전트만 fable | 리뷰 fable, 테스트·DB sonnet, effort도 지정 |

## 4. 그대로 가져온 것

- 리뷰를 결함 관점과 리팩터링 관점의 독립 서브에이전트 두 개로 나누는 방식
- 서브에이전트에 정확한 범위만 주고 서로의 결과를 넘기지 않는 원칙
- 리뷰 라운드 상한과 종료 조건, 최종 보고 순서
- "작성자가 알면 고칠 가능성이 높은가"라는 보고 기준과 결과 형식
- 보고 우선 규칙(미결 사항이 있으면 리뷰를 보류하고 먼저 보고)
- 계획과 개발을 다른 세션에서 진행하는 흐름
- 단계별로 모델을 다르게 쓰는 토큰 절약 방식

## 5. 참고 하네스에서 확인한 문제

| 위치 | 문제 | 새 하네스의 처리 |
|------|------|------------------|
| `settings.local.json` | `deny`가 없고 임의 코드 실행 명령과 홈 디렉터리 읽기가 열려 있어, 비밀 파일을 열지 말라는 지시가 강제되지 않는다 | 좁은 `allow`, `ask`, `deny`, 금지 경로 훅 |
| `db.sh` 읽기 전용 가드 | 주석을 지우는 정규식이 문자열 리터럴 안의 `#`, `--`까지 지워서 `SELECT '#'; DELETE ...` 같은 입력이 검사를 통과한다 | 스크립트를 넣지 않았다. 개발·운영 DB는 SELECT 전용 계정으로 접속하도록 안내 |
| 읽기 전용 에이전트 | `Bash`가 있어 "수정하지 않는다"가 지시로만 지켜진다 | 같은 한계가 남아 있다. `HARNESS.md` 9.3에 적어 두었다 |
