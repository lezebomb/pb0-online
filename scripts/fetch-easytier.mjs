import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const root = new URL('../', import.meta.url);
const tag = 'v2.6.4';
const expected = '27af91e270e554709b048bd32327fefd2dfce5062ae1e8701af7550c6f525f84';
const asset = `easytier-windows-x86_64-${tag}.zip`;
const url = `https://github.com/EasyTier/EasyTier/releases/download/${tag}/${asset}`;
await mkdir(new URL('downloads/', root), {recursive:true});
const dest = new URL(`downloads/${asset}`, root);
let bytes;
try { bytes = await readFile(dest); } catch {
  const response = await fetch(url);
  if (!response.ok) throw new Error(`Download: ${response.status}`);
  bytes = Buffer.from(await response.arrayBuffer());
}
const sha256 = createHash('sha256').update(bytes).digest('hex');
if (sha256 !== expected) throw new Error(`SHA256 mismatch: ${sha256}`);
await writeFile(dest, bytes);
await writeFile(new URL('downloads/easytier-source.json', root), JSON.stringify({tag,url,sha256},null,2));
console.log(`Verified ${asset}: ${sha256}`);
