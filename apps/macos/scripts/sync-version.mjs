import { readFile, writeFile } from 'node:fs/promises';

const packageJsonUrl = new URL('../package.json', import.meta.url);
const projectYmlUrl = new URL('../project.yml', import.meta.url);

const { version } = JSON.parse(await readFile(packageJsonUrl, 'utf8'));
const projectYml = await readFile(projectYmlUrl, 'utf8');

const marketingVersionPattern = /^(\s*MARKETING_VERSION: )"([^"]*)"$/m;
const buildNumberPattern = /^(\s*CURRENT_PROJECT_VERSION: )"(\d+)"$/m;

const marketingVersion = projectYml.match(marketingVersionPattern)?.[2];
const buildNumber = projectYml.match(buildNumberPattern)?.[2];
if (marketingVersion === undefined || buildNumber === undefined) {
  throw new Error('MARKETING_VERSION or CURRENT_PROJECT_VERSION not found in project.yml');
}

if (marketingVersion !== version) {
  const updated = projectYml
    .replace(marketingVersionPattern, `$1"${version}"`)
    .replace(buildNumberPattern, `$1"${Number(buildNumber) + 1}"`);
  await writeFile(projectYmlUrl, updated);
}
