import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    environment: 'node',
    // The *.db.test.ts files share one Postgres database and reset it in beforeAll.
    fileParallelism: false,
  },
});
