import { expect, test } from '@playwright/test';

test.describe('application shell', () => {
  test('renders the root route', async ({ page }) => {
    // Given a dev server serving the Angular app

    // When a visitor loads the root route
    await page.goto('/');

    // Then the routed shell is mounted and the root route has rendered
    await expect(page.getByTestId('app-shell')).toBeVisible();
    await expect(page.getByTestId('home-heading')).toHaveText('keepup');
  });
});
