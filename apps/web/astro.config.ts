import react from '@astrojs/react';
import tailwindcss from '@tailwindcss/vite';
import { defineConfig, envField } from 'astro/config';

export default defineConfig({
  output: 'static',
  site: 'https://plainsong.shikakun.com',
  trailingSlash: 'always',
  integrations: [react()],
  env: {
    schema: {
      GOOGLE_ANALYTICS_MEASUREMENT_ID: envField.string({
        context: 'client',
        access: 'public',
        optional: true,
      }),
    },
  },
  vite: {
    plugins: [tailwindcss()],
  },
});
