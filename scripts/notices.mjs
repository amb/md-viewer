import fs from 'node:fs';
import path from 'node:path';

let text = 'MD View — third-party notices\n\n';
const lock = JSON.parse(fs.readFileSync('package-lock.json'));
const sources = fs.readFileSync('Resources/THIRD-PARTY-SOURCES.txt', 'utf8');
const elkVersion = lock.packages['node_modules/elkjs']?.version;
if (elkVersion && !sources.includes(`elkjs ${elkVersion}\n`)) {
  throw new Error('Update the elkjs source availability notice for the locked version.');
}
for (const dir of Object.keys(lock.packages).filter(Boolean).sort()) {
  if (!fs.existsSync(dir)) continue;
  const pkg = JSON.parse(fs.readFileSync(path.join(dir, 'package.json')));
  text += `\n${pkg.name} ${pkg.version} (${pkg.license ?? 'see below'})\n`;
  for (const name of fs.readdirSync(dir).filter(n => /^(licen[cs]e|copying|notice)(\.|$)/i.test(n))) {
    const file = path.join(dir, name);
    if (fs.statSync(file).isFile()) text += fs.readFileSync(file, 'utf8') + '\n';
  }
}
for (const [name, files] of [
  ['Swift Markdown 0.9.0', ['.build/checkouts/swift-markdown/LICENSE.txt', '.build/checkouts/swift-markdown/NOTICE.txt']],
  ['Swift cmark 0.9.0', ['.build/checkouts/swift-cmark/COPYING']]
]) {
  text += '\n' + name + '\n';
  for (const file of files) text += fs.readFileSync(file, 'utf8') + '\n';
}
text += '\nCatppuccin palette 1.8.0\n' + fs.readFileSync('Resources/Catppuccin-LICENSE.txt', 'utf8');
text += '\nThird-party source availability\n\n' + sources;
fs.writeFileSync('Resources/THIRD-PARTY-NOTICES.txt', text);
