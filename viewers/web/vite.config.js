import { fileURLToPath } from 'node:url';

const projectRoot = fileURLToPath(new URL('.', import.meta.url));

export default {
  root: projectRoot,
  publicDir: fileURLToPath(new URL('../../public', import.meta.url)),
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
};
