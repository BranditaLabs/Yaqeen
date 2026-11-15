// Runs the admin's Next standalone build (as in its Docker image) on any OS: copies the static
// assets next to server.js, then starts it in this process.
import { cpSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const admin = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'apps', 'admin');
const standalone = join(admin, '.next', 'standalone', 'apps', 'admin');
cpSync(join(admin, '.next', 'static'), join(standalone, '.next', 'static'), { recursive: true });
cpSync(join(admin, 'public'), join(standalone, 'public'), { recursive: true });
process.chdir(standalone);
await import(pathToFileURL(join(standalone, 'server.js')).href);
