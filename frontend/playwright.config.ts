import { defineConfig, devices } from '@playwright/test';

const isCI = !!process.env['CI'];
const baseURL = process.env['PLAYWRIGHT_BASE_URL'] ?? 'http://localhost:4200';

/**
 * Playwright harness for keepup.
 *
 * This is the harness, not the suite: it holds a single smoke test proving the
 * app boots and the root route renders. Real end-to-end journeys land later.
 */
export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: isCI,
  retries: isCI ? 2 : 0,
  workers: isCI ? 1 : undefined,
  reporter: isCI ? 'line' : 'list',

  use: {
    baseURL,
    trace: 'on-first-retry',
  },

  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],

  // Boots `ng serve` for the run. Locally an already-running dev server is reused.
  webServer: {
    command: 'npm start -- --port 4200',
    url: baseURL,
    reuseExistingServer: !isCI,
    timeout: 120_000,
  },
});
