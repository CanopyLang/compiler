import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { resolve } from 'path';

export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'src/main.tsx'),
        background: resolve(__dirname, 'src/background.ts'),
        content: resolve(__dirname, 'src/content.ts'),
        devtools: resolve(__dirname, 'src/devtools.ts'),
        injected: resolve(__dirname, 'src/injected.ts')
      },
      output: {
        entryFileNames: '[name].js',
        chunkFileNames: '[name].js',
        assetFileNames: 'assets/[name].[ext]'
      }
    },
    sourcemap: true,
    minify: false
  },
  css: {
    modules: false
  }
});
