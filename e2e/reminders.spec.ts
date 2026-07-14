import { expect, test } from '@playwright/test';

test('chores list supports recurrence and auto-advances on completion', async ({ page }) => {
  const consoleErrors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });

  await page.goto('/');
  await page.getByRole('tab', { name: 'Lists' }).click();

  await page.getByText('Chores', { exact: true }).click();
  await expect(page.getByText('+ Add')).toBeVisible();

  await page.getByText('+ Add').click();
  await expect(page.getByText('New Reminder')).toBeVisible();

  await page.getByPlaceholder('What needs to get done?').fill('Take out trash');
  await expect(page.getByText('Repeat every (days)')).toBeVisible();
  await page.getByPlaceholder('One-off (leave blank)').fill('3');

  await page.getByText('Save', { exact: true }).click();
  await expect(page.getByText('New Reminder')).toBeHidden();

  await expect(page.getByText('Take out trash')).toBeVisible();
  await expect(page.getByText('repeats every 3d')).toBeVisible();

  // Completing a recurring chore should auto-advance its deadline instead of staying checked off.
  const checkbox = page.getByRole('checkbox', { name: 'Mark Take out trash as complete' });
  await checkbox.click();
  await expect(page.getByRole('checkbox', { name: 'Mark Take out trash as complete' })).toBeVisible();
  await expect(page.getByRole('checkbox', { name: 'Mark Take out trash as incomplete' })).toHaveCount(0);

  expect(consoleErrors).toEqual([]);
});

test('tasks list does not offer a recurrence option', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('tab', { name: 'Lists' }).click();

  await page.getByText('Tasks', { exact: true }).click();
  await page.getByText('+ Add').click();
  await expect(page.getByText('New Reminder')).toBeVisible();

  await expect(page.getByText('Repeat every (days)')).toHaveCount(0);

  await page.getByText('Cancel', { exact: true }).click();
});

test('an item due today surfaces on the Today tab', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('tab', { name: 'Lists' }).click();

  await page.getByText('Tasks', { exact: true }).click();
  await page.getByText('+ Add').click();
  await page.getByPlaceholder('What needs to get done?').fill('Pay electric bill');
  await page.getByRole('switch').click(); // toggling the deadline switch on defaults it to right now
  await page.getByText('Save', { exact: true }).click();
  await expect(page.getByText('New Reminder')).toBeHidden();

  // The list detail screen is pushed above the tab bar, so back out to it first.
  await page.getByRole('button', { name: 'Back' }).click();
  await page.getByRole('tab', { name: 'Today' }).click();
  await expect(page.getByText('Pay electric bill')).toBeVisible();
});

test('title is required before saving', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('tab', { name: 'Lists' }).click();
  await page.getByText('Chores', { exact: true }).click();

  await page.getByText('+ Add').click();
  await expect(page.getByText('New Reminder')).toBeVisible();

  const saveButton = page.getByText('Save', { exact: true });
  await saveButton.click();
  await expect(page.getByText('New Reminder')).toBeVisible();
});
