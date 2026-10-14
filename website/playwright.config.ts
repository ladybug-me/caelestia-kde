import { defineConfig, devices } from '@playwright/test';

/**
 * The browser tests are about the things a unit test cannot see: whether a drag
 * tracks the pointer 1:1, whether a flick commits, whether an interrupted
 * animation jumps, and whether the reduced-motion paths really are reduced.
 *
 * Chromium only: the site is a static document, and the three engines would
 * triple the runtime of a suite whose value is in the gesture assertions.
 */
export default defineConfig({
    testDir: 'tests/e2e',
    fullyParallel: true,
    forbidOnly: Boolean(process.env.CI),
    retries: process.env.CI ? 1 : 0,
    reporter: process.env.CI ? [['list'], ['github']] : [['list']],
    use: {
        baseURL: 'http://localhost:4321/caelestia-kde/',
        trace: 'retain-on-failure',
    },
    webServer: {
        command: 'npm run preview -- --port 4321',
        url: 'http://localhost:4321/caelestia-kde/',
        reuseExistingServer: !process.env.CI,
        timeout: 120_000,
    },
    projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
