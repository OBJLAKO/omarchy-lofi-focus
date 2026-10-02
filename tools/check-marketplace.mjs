#!/usr/bin/env node
// Advisory local scan using the official policy modules supplied explicitly.
// This does not fabricate exact-commit publication evidence for an edited tree.
import { createHash } from 'node:crypto';
import { readdir, readFile, lstat, writeFile } from 'node:fs/promises';
import { dirname, resolve, relative, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const value = name => {
  const index = process.argv.indexOf(name);
  if (index < 0 || !process.argv[index + 1]) throw new Error(`Required: ${name}`);
  return process.argv[index + 1];
};
const scanner = resolve(value('--scanner'));
const output = resolve(value('--output'));
const { isSecurityScanPath } = await import(pathToFileURL(join(scanner, 'security-baseline-scope.mjs')));
const { detectElevatedCapabilities, detectUnsafeRemoteExecution } = await import(pathToFileURL(join(scanner, 'security-baseline-analysis.mjs')));
const { securityBaselineOutcome, securityBaselineVersion } = await import(pathToFileURL(join(scanner, 'security-baseline-policy.mjs')));
const manifest = JSON.parse(await readFile(join(root, 'manifest.json'), 'utf8'));
const required = new Set(Object.values(manifest.entryPoints));
const files = [];
const hashes = [];
let textBytes = 0;
let rustSourceFiles = 0;
async function walk(directory) {
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    if (['.git', 'target', '__pycache__', 'perf-results'].includes(entry.name)) continue;
    const absolute = join(directory, entry.name);
    const path = relative(root, absolute).replaceAll('\\', '/');
    const info = await lstat(absolute);
    if (info.isSymbolicLink()) throw new Error(`Plugin symlink: ${path}`);
    if (entry.isDirectory()) { await walk(absolute); continue; }
    if (!entry.isFile()) continue;
    if (path.endsWith('.rs')) rustSourceFiles++;
    const executable = Boolean(info.mode & 0o111);
    if (!executable && !required.has(path) && !isSecurityScanPath(path)) continue;
    const bytes = await readFile(absolute);
    hashes.push({ path, sha256: createHash('sha256').update(bytes).digest('hex') });
    const mode = executable ? '100755' : '100644';
    if (bytes.subarray(0, 4).equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]))) {
      files.push({ path, mode, binary: true, format: 'ELF', size: bytes.length });
    } else {
      if (bytes.includes(0) || bytes.length > 512 * 1024) throw new Error(`Unsupported or excessive runtime file: ${path}`);
      textBytes += bytes.length;
      files.push({ path, mode, content: bytes.toString('utf8'), size: bytes.length });
    }
    if (files.length > 1000 || textBytes > 8 * 1024 * 1024) throw new Error('Static scan size limit');
  }
}
await walk(root);
const findings = detectUnsafeRemoteExecution(files, 'objlako/omarchy-lofi-focus');
const capabilities = detectElevatedCapabilities(files, 'objlako/omarchy-lofi-focus');
const report = {
  mode: 'advisory-local-working-tree',
  scannerSourceCommit: '34cb24a8c543746065982c568e3929c3a0bb9e07',
  policyVersion: securityBaselineVersion,
  checkedAt: new Date().toISOString(),
  outcome: securityBaselineOutcome(findings, capabilities), findings, capabilities,
  selectedFiles: files.length, selectedTextBytes: textBytes, fileHashes: hashes,
  rustSourceFiles,
  note: 'Local static pattern analysis only; no exact-commit marketplace evidence or approval. Rust source needs separate review. No community runtime code was executed by this scan.',
};
await writeFile(output, JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({ outcome: report.outcome, findings: findings.map(f => f.id), capabilities: capabilities.map(c => c.id), selectedFiles: files.length, output }));
