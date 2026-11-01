#!/usr/bin/env node
// Creates an Apple Music developer token (ES256 JWT) and writes it to config.js.
// Usage:
//   node make-token.mjs --team TEAMID1234 --key KEYID12345 --p8 ./AuthKey_KEYID12345.p8 \
//        [--origin http://localhost:3000,https://your-site.netlify.app] [--days 180]
// Needs Node 18+. No packages to install. Keep the .p8 file private; never put it on a website.
import { readFileSync, writeFileSync } from 'node:fs';
import { createPrivateKey, sign } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const args = {};
const argv = process.argv.slice(2);
for (let i = 0; i < argv.length; i++) if (argv[i].startsWith('--')) args[argv[i].slice(2)] = argv[i + 1];
const { team, key, p8 } = args;
if (!team || !key || !p8) {
  console.error('Usage: node make-token.mjs --team <Team ID> --key <Key ID> --p8 <path to AuthKey_XXXX.p8> [--origin url1,url2] [--days 180]');
  process.exit(1);
}
const days = Math.min(Number(args.days || 180), 182);
const now = Math.floor(Date.now() / 1000);
const header = { alg: 'ES256', kid: key };
const payload = { iss: team, iat: now, exp: Math.min(now + days * 86400, now + 15777000 - 60) };
if (args.origin) payload.origin = args.origin.split(',').map(s => s.trim()).filter(Boolean);
const b64 = obj => Buffer.from(JSON.stringify(obj)).toString('base64url');
const unsigned = `${b64(header)}.${b64(payload)}`;
const privateKey = createPrivateKey(readFileSync(p8));
const signature = sign('sha256', Buffer.from(unsigned), { key: privateKey, dsaEncoding: 'ieee-p1363' }).toString('base64url');
const token = `${unsigned}.${signature}`;
const out = join(dirname(fileURLToPath(import.meta.url)), 'config.js');
writeFileSync(out, `// Apple Music developer token. Expires ${new Date(payload.exp * 1000).toDateString()}.\nwindow.SELECTOR_CONFIG = ${JSON.stringify({ developerToken: token })};\n`);
console.log(`Wrote ${out}`);
console.log(`Token expires ${new Date(payload.exp * 1000).toDateString()}${payload.origin ? `; works only on ${payload.origin.join(', ')}` : '; works on any website (add --origin before you publish it)'}.`);
