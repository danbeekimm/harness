import { defineConfig, devices } from "@playwright/test";

// 기준 URL은 환경 변수 E2E_BASE_URL로 바꾼다. 기본값은 프로필의 'E2E > 기준 URL'과 맞춘다.
const baseURL = process.env.E2E_BASE_URL ?? "http://localhost:8080";

export default defineConfig({
  testDir: "./tests",
  timeout: 30_000,
  expect: { timeout: 5_000 },
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  // 재시도로 불안정한 테스트를 덮지 않는다(.claude/rules/test.md).
  retries: 0,
  reporter: [["list"], ["html", { open: "never" }]],
  use: {
    baseURL,
    locale: "ko-KR",
    timezoneId: "Asia/Seoul",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],

  // 서버를 Playwright가 직접 띄우게 하려면 주석을 풀고 명령을 프로필의 '서버 기동(로컬)'로 바꾼다.
  // webServer: {
  //   command: "cd .. && ./gradlew bootRun",
  //   url: baseURL,
  //   reuseExistingServer: true,
  //   timeout: 120_000,
  // },
});
