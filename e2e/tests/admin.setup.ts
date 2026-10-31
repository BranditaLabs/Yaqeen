import { expect, test as setup } from '@playwright/test';
import { fixture, totp } from './fixture';

setup('admin signs in with password + authenticator code', async ({ page }) => {
  const f = fixture();
  await page.goto('/');
  await expect(page).toHaveURL(/\/login/); // the dashboard is closed without a session

  const signIn = async (code: string) => {
    // The form resets after each attempt (React form action), so fill every field each time.
    await page.getByLabel('البريد الإلكتروني').fill(f.email);
    await page.getByLabel('كلمة المرور').fill(f.password);
    await page.getByLabel(/رمز التحقق/).fill(code);
    await page.getByRole('button', { name: 'دخول' }).click();
  };
  await signIn('000000');
  await expect(page.getByText('بيانات الدخول غير صحيحة')).toBeVisible(); // a wrong code is refused

  // The refused attempt's form reset can race the next fill; one retry with a fresh code keeps
  // this from flaking (a real rejection fails both attempts).
  for (let attempt = 0; ; attempt++) {
    await signIn(totp(f.totpSecret));
    try {
      await expect(page).not.toHaveURL(/\/login/, { timeout: 8_000 });
      break;
    } catch (e) {
      if (attempt >= 1) throw e;
    }
  }
  await page.context().storageState({ path: '.auth/admin.json' });
});
