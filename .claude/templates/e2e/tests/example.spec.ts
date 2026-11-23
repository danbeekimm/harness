import { expect, test } from "@playwright/test";

// 환경 확인용 예시다. 기준 URL의 서버가 응답하는지만 본다.
// 실제 테스트는 /verify 가 tests/<slug>.spec.ts 로 만든다. 그때 이 파일은 지워도 된다.
//
// 작성 규칙 (.claude/rules/test.md)
// - 테스트 이름은 수용 기준 번호로 시작한다: "AC-1: ..."
// - 요소는 역할·라벨·텍스트로 찾는다: getByRole, getByLabel, getByText
// - waitForTimeout 을 쓰지 않는다
// - 계정은 환경 변수에서 가져온다: process.env.E2E_USER, process.env.E2E_PASSWORD

test("환경 확인: 기준 URL이 응답한다", async ({ page }) => {
  const response = await page.goto("/");

  expect(response, "기준 URL에서 응답을 받지 못했다").not.toBeNull();
  expect(response!.status(), "서버 오류 응답").toBeLessThan(500);
});

// 수용 기준 테스트의 형태
//
// test("AC-1: 취소 버튼을 누르면 주문 상태가 '취소됨'으로 바뀐다", async ({ page }) => {
//   await page.goto("/orders/1");
//   await page.getByRole("button", { name: "주문 취소" }).click();
//   await page.getByRole("button", { name: "확인" }).click();
//
//   await expect(page.getByText("취소됨")).toBeVisible();
// });
