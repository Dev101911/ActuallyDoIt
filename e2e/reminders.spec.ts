import { expect, test } from '@playwright/test';

test('creates a reminder with all optional fields and can reopen it for editing', async ({ page }) => {
  const consoleErrors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });

  await page.goto('/');
  await expect(page.getByText('+ Add')).toBeVisible();

  await page.getByText('+ Add').click();
  await expect(page.getByText('New Reminder')).toBeVisible();

  await page.getByPlaceholder('What needs to get done?').fill('Finish taxes');
  await page.getByPlaceholder('Optional notes').fill('Gather W2s and receipts');

  const optionalMinuteInputs = page.getByPlaceholder('Optional', { exact: true });
  await optionalMinuteInputs.nth(0).fill('45'); // expected time to complete
  await optionalMinuteInputs.nth(1).fill('30'); // alert frequency

  await page.getByText('High', { exact: true }).click();

  await page.getByRole('switch').click();
  await page.getByRole('switch').click();

  await page.getByText('Save', { exact: true }).click();
  await expect(page.getByText('New Reminder')).toBeHidden();

  await expect(page.getByText('Finish taxes')).toBeVisible();
  await expect(page.getByText('Gather W2s and receipts')).toBeVisible();
  await expect(page.getByText('45 min')).toBeVisible();
  await expect(page.getByText('every 30 min')).toBeVisible();
  await expect(page.getByText('High', { exact: true })).toBeVisible();

  await page.getByText('Finish taxes').click();
  await expect(page.getByText('Edit Reminder')).toBeVisible();
  await expect(page.getByPlaceholder('What needs to get done?')).toHaveValue('Finish taxes');
  await expect(page.getByPlaceholder('Optional notes')).toHaveValue('Gather W2s and receipts');

  await page.getByText('Cancel', { exact: true }).click();

  expect(consoleErrors).toEqual([]);
});

test('title is required before saving', async ({ page }) => {
  await page.goto('/');
  await page.getByText('+ Add').click();
  await expect(page.getByText('New Reminder')).toBeVisible();

  const saveButton = page.getByText('Save', { exact: true });
  await saveButton.click();
  await expect(page.getByText('New Reminder')).toBeVisible();
});
