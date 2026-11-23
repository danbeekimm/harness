---
name: init-harness
description: 하네스를 설치한 프로젝트에서 처음 한 번 실행한다. 코드를 조사해 프로젝트 프로필을 채우고 Playwright E2E 환경을 준비한다.
disable-model-invocation: true
---

# /init-harness: 프로필 채우기와 E2E 준비

프로젝트에 하네스를 복사한 직후(`install.sh`) 한 번 실행한다. 다시 실행하면 빈 항목만 채운다.

## 1. 현재 상태 확인

- `.claude/rules/project-profile.md`를 읽는다. `<미입력>`이 남은 항목이 채울 대상이다. 이미 채워진 항목은 건드리지 않는다.
- git 저장소인지 확인한다. 아니면 사용자에게 알리고 `git init` 여부를 묻는다(커밋 규칙과 리뷰가 git에 기대고 있다).
- `node`가 있는지 확인한다. 없으면 훅(`guard-paths.sh`, `check-edit.sh`)과 Playwright가 동작하지 않는다고 알리고 멈춘다.

## 2. 코드 조사

프로필 항목을 코드에서 찾는다. 찾은 것은 근거 파일과 함께 채운다.

| 프로필 섹션 | 찾는 곳 |
|-------------|---------|
| 스택 | `build.gradle(.kts)`, `pom.xml`, `settings.gradle`, `package.json`, `application*.yml`·`.properties`(프로필 이름·DB 종류만. 비밀 값은 읽지 않는다) |
| 명령 | Gradle·Maven 래퍼, `package.json`의 `scripts`, `Makefile`, CI 설정 |
| 디렉터리 | 소스 트리. 컨트롤러·서비스·리포지토리·엔티티·매퍼·마이그레이션·화면 코드의 실제 위치 |
| 재사용 우선 대상 | 공용 유틸, 공통 응답·예외 처리, 공통 컴포넌트, 베이스 클래스. 여러 곳에서 import되는 것 |
| 리뷰 체크리스트 | 기존 코드에서 반복되는 프로젝트 고유 규칙(권한 어노테이션, 감사 컬럼, 소프트 삭제 등) |

서버가 Spring Boot가 아니면 이 하네스의 대상이 아니다. 그 사실을 알리고 계속할지 묻는다.

## 3. 사용자에게 묻기

코드로 알 수 없는 것만 묻는다. 한 번에 4개까지.

- **DB 접속**: 개발 DB에 SELECT 전용 계정으로 접속하는 방법. 접속 스크립트가 있으면 그 사용법. 없으면 "접속 없음"으로 둔다(이때 `db-helper`는 코드만 보고 답한다).
  - 비밀번호를 프로필에 적지 않는다. 환경 변수 이름이나 접속 스크립트 경로만 적는다.
  - 쓰기 권한이 있는 계정만 있다면 그 사실을 프로필에 적고, SELECT 전용 계정을 만들 것을 권한다.
- **E2E**: 기준 URL, 서버 기동 방법, 테스트 계정을 가져오는 방법(환경 변수 이름), 테스트 데이터 준비 방법.
- **금지 경로**: 기본 목록(`.claude/hooks/forbidden-paths.txt`) 외에 열면 안 되는 경로.
- 2단계에서 근거가 약했던 항목의 확인.

답이 없는 항목은 `<미입력>`으로 남기고, 그 항목이 필요한 단계(`/dev`, `/verify`)가 막힌다는 것을 알린다.

## 4. 프로필 쓰기

`.claude/rules/project-profile.md`를 채운다.

- 섹션 이름을 바꾸지 않는다. 에이전트와 스킬이 섹션 이름으로 참조한다.
- 명령은 그대로 복사해 실행할 수 있게 적는다. 실제로 한 번 실행해 확인한다(빌드, 테스트).
- 사용자가 준 금지 경로는 `.claude/hooks/forbidden-paths.txt` 맨 아래와 프로필의 `금지 경로`에 모두 적는다.

## 5. 규칙 파일의 대상 경로 맞추기

`.claude/rules/`의 `frontend.md`, `db.md`, `test.md`, `backend-spring.md`는 frontmatter의 `paths`로 적용 대상을 정한다. 프로필의 `디렉터리`와 다르면 `paths`를 실제 경로에 맞게 고친다. 화면 코드가 없는 프로젝트면 `frontend.md`는 그대로 둔다(대상 파일이 없으면 적용되지 않는다).

## 6. Playwright 준비

프로필의 E2E 디렉터리(기본 `e2e/`)가 없을 때만 한다. 있으면 건드리지 않는다.

1. `.claude/templates/e2e/`의 파일을 E2E 디렉터리로 복사한다.
2. `playwright.config.ts`의 `baseURL` 기본값을 프로필의 기준 URL로 맞춘다.
3. 사용자에게 알리고 설치한다(네트워크를 쓰고 시간이 걸린다).

   ```
   cd e2e && npm install && npx playwright install chromium
   ```

4. 서버가 떠 있으면 예시 테스트를 실행해 환경을 확인한다. 떠 있지 않으면 실행 방법만 알린다.
5. `.gitignore`에 `e2e/node_modules/`, `e2e/test-results/`, `e2e/playwright-report/`가 없으면 추가한다.

## 7. 커밋과 보고

변경을 커밋한다. 메시지: `chore: 하네스 프로필과 E2E 초기 설정`

보고 순서:

1. 채우지 못한 프로필 항목과 그 때문에 막히는 단계
2. 채운 항목 요약(스택, 명령, E2E)
3. 확인한 것: 빌드·테스트 명령 실행 결과, 예시 E2E 실행 결과
4. 다음 단계: 기획안이 있으면 `/plan <파일>`
