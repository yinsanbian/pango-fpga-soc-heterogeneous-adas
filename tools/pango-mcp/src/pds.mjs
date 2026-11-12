import fs from 'node:fs/promises';
import { constants as fsConstants, statSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import { spawn, execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const TARGETS = [
  'compile', 'synthesize', 'dev_map', 'pnr', 'report_timing',
  'report_power', 'gen_bit_stream', 'gen_netlist',
];
const BUILD_DIRS = [
  'compile', 'synthesize', 'device_map', 'place_route',
  'report_timing', 'report_power', 'generate_bitstream', 'generate_netlist',
];
const SUCCESS = {
  compile: /(?:Action compile: Export DB successfully|Executing\s*:\s*compile\b[^\r\n]*successfully)/i,
  synthesize: /(?:Action synthesize: Export DB successfully|successfully synthesized to architecture-specific objects)/i,
  dev_map: /(?:Action dev_map: Export DB successfully|Executing\s*:\s*dev_map\b[^\r\n]*successfully)/i,
  pnr: /(?:Action route_optimize: Export DB successfully|Executing\s*:\s*pnr\b[^\r\n]*successfully)/i,
  report_timing: /(?:Report timing is finished successfully|Action report_timing: Export DB successfully)/i,
  report_power: /(?:Action report_power\b[^\r\n]*successfully|Report power is finished successfully)/i,
  gen_bit_stream: /(?:Generating Programming File done\.|Executing\s*:\s*gen_bit_stream\b[^\r\n]*successfully)/i,
  gen_netlist: /(?:Action gen_netlist\b[^\r\n]*successfully|Executing\s*:\s*gen_netlist\b[^\r\n]*successfully)/i,
};

const obj = (properties, required = []) => ({ type: 'object', properties, required, additionalProperties: false });
const str = (description) => ({ type: 'string', description });
const bool = (description) => ({ type: 'boolean', description });
const num = (description, minimum, maximum) => ({ type: 'number', description, minimum, maximum });
const abs = (value, label) => {
  if (typeof value !== 'string' || !path.isAbsolute(value)) throw new Error(`${label} must be an absolute path`);
  return path.resolve(value);
};
const exists = async (p) => fs.access(p).then(() => true, () => false);
const read = async (p, max = 8_000_000) => {
  try {
    const stat = await fs.stat(p);
    if (stat.size > max) return (await fs.readFile(p, 'utf8')).slice(-max);
    return await fs.readFile(p, 'utf8');
  } catch { return ''; }
};
const unique = (items) => [...new Set(items)];
const norm = (p) => process.platform === 'win32' ? p.toLowerCase() : p;
const isInside = (child, root) => {
  const rel = path.relative(norm(root), norm(child));
  return rel === '' || (rel !== '..' && !rel.startsWith(`..${path.sep}`) && !path.isAbsolute(rel));
};
async function ensureDirectChildDir(parent, name, root = parent) {
  const candidate = path.join(parent, name);
  try { await fs.mkdir(candidate); } catch (e) { if (e.code !== 'EEXIST') throw e; }
  const stat = await fs.lstat(candidate);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new Error(`Refusing a linked or non-directory output path: ${candidate}`);
  const realParent = await fs.realpath(parent);
  const realCandidate = await fs.realpath(candidate);
  const realRoot = await fs.realpath(root);
  if (norm(path.dirname(realCandidate)) !== norm(realParent) || !isInside(realCandidate, realRoot))
    throw new Error(`Output path escapes the project directory: ${candidate}`);
  return candidate;
}
const validateToken = (value, label) => {
  if (typeof value !== 'string' || !/^[A-Za-z_][A-Za-z0-9_]*$/.test(value)) throw new Error(`${label} must be a simple identifier`);
  return value;
};
const validatePart = (value, label) => {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_+.-]+$/.test(value)) throw new Error(`${label} contains unsupported characters`);
  return value;
};
const tclPath = (value) => {
  if (/[{}\r\n]/.test(value)) throw new Error('Path contains unsupported Tcl brace or newline');
  return `{${value.replaceAll('\\', '/')}}`;
};
const plainError = (error) => ({ ok: false, error: error instanceof Error ? error.message : String(error) });
const wrap = (fn) => async (args = {}) => {
  try { return await fn(args ?? {}); } catch (e) { return plainError(e); }
};

function balanced(text) {
  let depth = 0, quoted = false, escaped = false, comment = false;
  for (const c of text) {
    if (comment) { if (c === '\n') comment = false; continue; }
    if (escaped) { escaped = false; continue; }
    if (c === '\\') { escaped = true; continue; }
    if (c === '"') { quoted = !quoted; continue; }
    if (quoted) continue;
    if (c === '#') { comment = true; continue; }
    if (c === '(') depth++;
    if (c === ')') { depth--; if (depth < 0) return false; }
  }
  return depth === 0 && !quoted;
}

async function projectInfo(pdsPath) {
  const file = abs(pdsPath, 'pdsPath');
  if (path.extname(file).toLowerCase() !== '.pds') throw new Error('pdsPath must point to a .pds file');
  const body = await fs.readFile(file, 'utf8');
  const setup = body.split(/\(_task\s+tsk_compile\b/i)[0];
  const part = (name) => setup.match(new RegExp(`\\(_${name}\\s+([^\\s()]+)`, 'i'))?.[1] ?? null;
  const top = body.match(/\(_option\s+top_module\s+\(_string\s+"([^"]+)"/i)?.[1] ?? null;
  const sources = [], constraints = [], ficFiles = [];
  for (const match of setup.matchAll(/\(_file\s+"([^"]+)"/g)) {
    const filePath = path.resolve(path.dirname(file), match[1]);
    if (/\.(?:fdc|pcf|sdc)$/i.test(filePath)) constraints.push(filePath);
    else sources.push(filePath);
  }
  for (const match of setup.matchAll(/\(_ip\s+"([^"]+)"/g)) sources.push(path.resolve(path.dirname(file), match[1]));
  const ficWidgetStart = body.search(/\(_widget\s+wgt_my_fic_src\b/);
  if (ficWidgetStart >= 0) {
    const widget = body.slice(ficWidgetStart, sexprEnd(body, ficWidgetStart));
    for (const match of widget.matchAll(/\(_file\s+"([^"]+\.fic)"/gi))
      ficFiles.push(path.resolve(path.dirname(file), match[1]));
  }
  const missing = [];
  for (const p of unique([...sources, ...constraints, ...ficFiles])) if (!(await exists(p))) missing.push(p);
  return {
    ok: balanced(body), pdsPath: file, name: path.basename(file, '.pds'),
    family: part('family'), device: part('device'), speedgrade: part('speedgrade'), package: part('package'),
    top, sources: unique(sources), constraints: unique(constraints), ficFiles: unique(ficFiles), missing,
    parenthesesBalanced: balanced(body),
    workDir: body.match(/\(_option\s+prj_work_dir\s+\(_string\s+"([^"]+)"/i)?.[1] ?? '.',
    implDir: body.match(/\(_option\s+prj_impl_dir\s+\(_string\s+"([^"]+)"/i)?.[1] ?? '.',
  };
}

const errorsIn = (text) => unique([...text.matchAll(/^(?:E:|Error:|Fatal:|\*\* Error:|\*\* Fatal:)\s*(.+)$/gmi)].map((m) => m[0].trim()));
function resourceLines(text) {
  const fields = {
    luts: /Total LUTs:\s*([\d.]+)\s+of\s+([\d.]+)/i,
    registers: /Total Registers:\s*([\d.]+)\s+of\s+([\d.]+)/i,
    latches: /Total Latches:\s*([\d.]+)(?:\s+of\s+([\d.]+))?/i,
    drm18k: /Total DRM18Ks\s*=\s*([\d.]+)\s+of\s+([\d.]+)/i,
    apm: /Total APMs\s*=\s*([\d.]+)\s+of\s+([\d.]+)/i,
    io: /Total I\/O ports\s*=\s*([\d.]+)\s+of\s+([\d.]+)/i,
  };
  const out = {};
  for (const [name, pattern] of Object.entries(fields)) {
    const m = text.match(pattern);
    if (m) out[name] = { used: Number(m[1]), total: m[2] ? Number(m[2]) : null, percent: m[2] && Number(m[2]) ? 100 * Number(m[1]) / Number(m[2]) : null };
  }
  return out;
}
function timingSummary(text) {
  if (!text) return null;
  const verdict = text.match(/Design Summary\s*:\s*([^\r\n]+)/i)?.[1]?.trim() ?? null;
  const performance = [...text.matchAll(/([\d.]+)\s+MHz\s+([\d.]+)\s+MHz/g)];
  const corners = {};
  for (const m of text.matchAll(/(Setup|Hold) Summary\(([^)]+)\):([\s\S]*?)(?=(?:Setup|Hold|Recovery|Removal|Minimum Pulse Width) Summary\(|$)/g)) {
    const rows = [...m[3].matchAll(/^\s*\S+\s+\S+\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(\d+)\s+(\d+)\s*$/gm)];
    if (rows.length) corners[`${m[1].toLowerCase()}_${m[2].toLowerCase().replace(/\W+/g, '_')}`] = {
      worstSlackNs: Math.min(...rows.map((r) => Number(r[1]))),
      totalNegativeSlackNs: Math.min(...rows.map((r) => Number(r[2]))),
      failingEndpoints: Math.max(...rows.map((r) => Number(r[3]))),
    };
  }
  const slack = Object.entries(corners);
  const setup = slack.filter(([k]) => k.startsWith('setup_')).map(([, v]) => v.worstSlackNs);
  const hold = slack.filter(([k]) => k.startsWith('hold_')).map(([, v]) => v.worstSlackNs);
  return {
    verdict, met: verdict ? /All Constraints Met/i.test(verdict) : null,
    fmaxMhz: performance.length ? Number(performance[0][2]) : null,
    requestedMhz: performance.length ? Number(performance[0][1]) : null,
    setupWorstNs: setup.length ? Math.min(...setup) : null,
    holdWorstNs: hold.length ? Math.min(...hold) : null,
    corners,
  };
}
async function listDirFiles(dir, ext) {
  try {
    return (await fs.readdir(dir, { withFileTypes: true }))
      .filter((x) => x.isFile() && ext.some((s) => x.name.toLowerCase().endsWith(s)))
      .map((x) => path.join(dir, x.name));
  } catch { return []; }
}
async function newest(paths) {
  let best = null, time = -1;
  for (const p of paths) {
    try { const st = await fs.stat(p); if (st.mtimeMs > time) { best = p; time = st.mtimeMs; } } catch { /* absent */ }
  }
  return best;
}
async function reportsFor(projectDir, detail = 'summary') {
  const timingFile = await newest((await listDirFiles(path.join(projectDir, 'report_timing'), ['.rtr'])).filter((p) => !/_exception\.rtr$/i.test(p)));
  const bitstreams = await listDirFiles(path.join(projectDir, 'generate_bitstream'), ['.sbit', '.sfc']);
  const logPaths = [
    path.join(projectDir, 'run.log'), path.join(projectDir, 'flow.log'),
    path.join(projectDir, 'synthesize', 'run.log'), path.join(projectDir, 'report_timing', 'run.log'),
    path.join(projectDir, 'generate_bitstream', 'run.log'),
  ];
  const files = await Promise.all(logPaths.map(async (p) => ({ path: p, text: await read(p) })));
  const combined = files.map((x) => x.text).join('\n');
  const timingText = timingFile ? await read(timingFile) : '';
  const summary = {
    ok: files.some((x) => x.text) && errorsIn(combined).length === 0,
    projectDir, errors: errorsIn(combined).slice(0, 30), errorCount: errorsIn(combined).length,
    utilization: resourceLines((files.find((x) => /synthesize[\\/]run\.log$/i.test(x.path))?.text ?? '') + '\n' + combined),
    timing: timingSummary(timingText), timingReport: timingFile,
    bitstreams, logs: files.filter((x) => x.text).map((x) => x.path),
  };
  if (detail === 'full') summary.full = { logs: Object.fromEntries(files.filter((x) => x.text).map((x) => [x.path, x.text])), timingReport: timingText };
  return summary;
}

function guiRunning() {
  if (process.platform !== 'win32') return false;
  try {
    const out = execFileSync('tasklist.exe', ['/FI', 'IMAGENAME eq pds.exe', '/FO', 'CSV', '/NH'], { encoding: 'utf8', timeout: 5000, windowsHide: true });
    return /"pds\.exe"\s*,/i.test(out);
  } catch (e) { throw new Error(`Cannot verify that the PDS GUI is closed: ${e.message}`); }
}
function pdsShellRunning() {
  if (process.platform !== 'win32') return false;
  try {
    const out = execFileSync('tasklist.exe', ['/FI', 'IMAGENAME eq pds_shell.exe', '/FO', 'CSV', '/NH'], { encoding: 'utf8', timeout: 5000, windowsHide: true });
    return /"pds_shell\.exe"\s*,/i.test(out);
  } catch (e) { throw new Error(`Cannot verify that PDS shell is idle: ${e.message}`); }
}

function sexprEnd(text, start) {
  let depth = 0, quoted = false, escaped = false, comment = false;
  for (let i = start; i < text.length; i++) {
    const c = text[i];
    if (comment) { if (c === '\n') comment = false; continue; }
    if (escaped) { escaped = false; continue; }
    if (c === '\\') { escaped = true; continue; }
    if (c === '"') { quoted = !quoted; continue; }
    if (quoted) continue;
    if (c === '#') { comment = true; continue; }
    if (c === '(') depth++;
    if (c === ')') { depth--; if (depth === 0) return i + 1; }
  }
  throw new Error('Unterminated PDS S-expression');
}
function oneForm(text, pattern, within = [0, text.length]) {
  const matches = [...text.slice(within[0], within[1]).matchAll(pattern)];
  if (matches.length !== 1) throw new Error(`Expected exactly one ${pattern} form; found ${matches.length}`);
  const start = within[0] + matches[0].index;
  const end = sexprEnd(text, start);
  if (end > within[1]) throw new Error('PDS form extends outside its expected parent');
  return { start, end, text: text.slice(start, end), headerLength: matches[0][0].length };
}
function localTimestamp(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}
async function registerFic(args) {
  const pdsPath = abs(args.pdsPath, 'pdsPath');
  const ficPath = abs(args.ficPath, 'ficPath');
  if (path.extname(pdsPath).toLowerCase() !== '.pds' || path.extname(ficPath).toLowerCase() !== '.fic')
    throw new Error('pdsPath must be .pds and ficPath must be .fic');
  if (guiRunning() || pdsShellRunning()) throw new Error('PDS GUI or shell is active; close it before editing the project');
  const pdsStat = await fs.lstat(pdsPath), ficStat = await fs.lstat(ficPath);
  if (!pdsStat.isFile() || pdsStat.isSymbolicLink() || !ficStat.isFile() || ficStat.isSymbolicLink())
    throw new Error('PDS and FIC inputs must be regular files, not symlinks');
  const root = await fs.realpath(path.dirname(pdsPath));
  if (norm(path.dirname(await fs.realpath(pdsPath))) !== norm(root)) throw new Error('PDS file escapes its project directory');
  const original = await fs.readFile(pdsPath);
  const body = new TextDecoder('utf-8', { fatal: true }).decode(original);
  if (!/^\s*\(_flow\s+\S+\s+"2023\.2-SP3"/.test(body))
    throw new Error('Only the locally verified PDS 2023.2-SP3 S-expression project format is supported');
  if (!balanced(body)) throw new Error('PDS project has unbalanced S-expressions');
  const info = await projectInfo(pdsPath);
  if (!info.top || !info.family || !info.device || !info.package || !info.speedgrade)
    throw new Error('PDS project is missing top or target information');
  const fic = new TextDecoder('utf-8', { fatal: true }).decode(await fs.readFile(ficPath));
  if (!/^#Fabric Core Inserter Project File\s*$/m.test(fic) || fic.includes('\0'))
    throw new Error('FIC file does not have the Fabric Core Inserter project header');
  const ficField = (name) => fic.match(new RegExp(`^Project\\.device\\.${name}=(.+)$`, 'm'))?.[1]?.trim() ?? null;
  for (const [field, expected] of [
    ['deviceFamily', info.family], ['deviceModel', info.device],
    ['devicePackage', info.package], ['deviceSpeedGrade', info.speedgrade],
  ]) {
    const actual = ficField(field);
    if (!actual || actual.toLowerCase() !== expected.toLowerCase())
      throw new Error(`FIC ${field} (${actual ?? 'missing'}) does not match PDS target (${expected})`);
  }
  const input = ficField('designInputFile');
  if (!input) throw new Error('FIC designInputFile is missing');
  const netlist = path.isAbsolute(input) ? path.resolve(input) : path.resolve(path.dirname(ficPath), input);
  const expectedNetlist = path.resolve(root, info.workDir, 'synthesize', `${info.top}_syn.adf`);
  if (!isInside(expectedNetlist, root)) throw new Error('PDS synthesis directory is outside the project');
  if (norm(netlist) !== norm(expectedNetlist) || !(await exists(netlist)))
    throw new Error(`FIC designInputFile does not point to this project's synthesized netlist: ${expectedNetlist}`);
  const synthesis = oneForm(body, /\(_task\s+tsk_synthesis\b/g);
  const widget = oneForm(body, /\(_widget\s+wgt_my_fic_src\b/g, [synthesis.start, synthesis.end]);
  const contents = widget.text.slice(widget.headerLength, -1);
  const inputs = [...contents.matchAll(/\(_input\b/g)];
  let previousFic = null, previousTimespec = null;
  if (inputs.length > 1) throw new Error('FIC widget has multiple input forms; edit manually');
  if (inputs.length === 1) {
    const inputStart = inputs[0].index;
    const inputEnd = sexprEnd(contents, inputStart);
    if (contents.slice(0, inputStart).trim() || contents.slice(inputEnd).trim())
      throw new Error('FIC widget has extra data; refusing to replace it');
    const oldInput = contents.slice(inputStart, inputEnd);
    if (!/^\(_input\s+\(_file\s+"[^"]+"\s+\(_format\s+text\)\s+\(_timespec\s+"[^"]+"\)\s*\)\s*\)$/s.test(oldInput))
      throw new Error('Existing FIC input has an unsupported structure');
    const files = [...oldInput.matchAll(/\(_file\s+"([^"]+)"/g)];
    if (files.length !== 1) throw new Error('FIC widget does not contain exactly one registered file');
    previousFic = path.resolve(root, files[0][1]);
    previousTimespec = oldInput.match(/\(_timespec\s+"([^"]+)"/)?.[1] ?? null;
  } else if (contents.trim()) throw new Error('FIC widget has an unsupported structure');
  const ficReal = await fs.realpath(ficPath);
  const relative = path.relative(root, ficReal);
  const storedPath = isInside(ficReal, root) ? relative.replaceAll('\\', '/') : ficReal.replaceAll('\\', '/');
  if (/[\r\n"\0]/.test(storedPath)) throw new Error('FIC path cannot be represented in the PDS project');
  const timespec = localTimestamp(ficStat.mtime);
  if (previousFic && norm(previousFic) === norm(ficReal) && previousTimespec === timespec)
    return { ok: true, changed: false, pdsPath, ficPath: ficReal, previousFic, backup: null };
  const eol = body.includes('\r\n') ? '\r\n' : '\n';
  const lineStart = body.lastIndexOf('\n', widget.start - 1) + 1;
  const indent = body.slice(lineStart, widget.start);
  if (!/^\s*$/.test(indent)) throw new Error('Cannot determine FIC widget indentation');
  const newWidget = [
    '(_widget wgt_my_fic_src',
    `${indent}    (_input`,
    `${indent}        (_file "${storedPath}"`,
    `${indent}            (_format text)`,
    `${indent}            (_timespec "${timespec}")`,
    `${indent}        )`,
    `${indent}    )`,
    `${indent})`,
  ].join(eol);
  const edited = body.slice(0, widget.start) + newWidget + body.slice(widget.end);
  if (!balanced(edited)) throw new Error('Edited PDS project would have unbalanced S-expressions');
  if (oneForm(edited, /\(_widget\s+wgt_my_fic_src\b/g).text.match(/\(_file\s+"([^"]+)"/)?.[1] !== storedPath)
    throw new Error('Edited PDS project did not retain the FIC path');
  if (guiRunning() || pdsShellRunning()) throw new Error('PDS GUI or shell became active; project was not changed');
  if (!(await fs.readFile(pdsPath)).equals(original)) throw new Error('PDS project changed during registration; retry');
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backup = `${pdsPath}.bak_${stamp}_${process.pid}`;
  const temp = `${pdsPath}.tmp_${stamp}_${process.pid}`;
  await fs.copyFile(pdsPath, backup, fsConstants.COPYFILE_EXCL);
  if (!(await fs.readFile(backup)).equals(original) || !(await fs.readFile(pdsPath)).equals(original))
    throw new Error(`PDS project changed while backing up; original backup is ${backup}`);
  try {
    await fs.writeFile(temp, edited, { encoding: 'utf8', flag: 'wx' });
    await fs.rename(temp, pdsPath);
  } finally { await fs.unlink(temp).catch((e) => { if (e.code !== 'ENOENT') throw e; }); }
  return { ok: true, changed: true, pdsPath, ficPath: ficReal, storedPath, previousFic, backup, format: 'PDS 2023.2-SP3 S-expression' };
}
async function digestProject(info) {
  const hash = createHash('sha256');
  const files = [info.pdsPath, ...info.sources, ...info.constraints, ...(info.ficFiles ?? [])];
  for (const file of unique(files)) {
    hash.update(file);
    try { hash.update(await fs.readFile(file)); } catch { hash.update('<missing>'); }
  }
  return hash.digest('hex');
}
async function backupOutputs(dir, target) {
  const limit = TARGETS.indexOf(target);
  const toMove = BUILD_DIRS.filter((_, i) => limit >= 0 && i <= (target === 'pnr' ? 3 : Math.max(0, limit)));
  const existing = [];
  const realRoot = await fs.realpath(dir);
  for (const name of toMove) {
    const source = path.join(dir, name);
    if (!(await exists(source))) continue;
    const stat = await fs.lstat(source);
    const realSource = await fs.realpath(source);
    if (!stat.isDirectory() || stat.isSymbolicLink() || norm(path.dirname(realSource)) !== norm(realRoot))
      throw new Error(`Refusing to move linked or external PDS output: ${source}`);
    existing.push(name);
  }
  if (!existing.length) return null;
  const meta = await ensureDirectChildDir(dir, '.pango-mcp');
  const backups = await ensureDirectChildDir(meta, 'backups', dir);
  const dest = await ensureDirectChildDir(backups, new Date().toISOString().replace(/[:.]/g, '-') + `-${process.pid}`, dir);
  for (const name of existing) {
    const source = path.join(dir, name), targetPath = path.join(dest, name);
    if (!isInside(path.resolve(source), path.resolve(dir)) || !isInside(path.resolve(targetPath), path.resolve(dir)))
      throw new Error('Backup move would escape the project directory');
    await fs.rename(source, targetPath);
  }
  return dest;
}
async function runPds(ctx, args, preset) {
  if (args.host) throw new Error('Remote PDS execution is unavailable in this local reconstruction');
  const runTarget = args.runTarget ?? preset;
  if (!TARGETS.includes(runTarget)) throw new Error(`runTarget must be one of ${TARGETS.join(', ')}`);
  const info = await projectInfo(args.pdsPath);
  if (!info.parenthesesBalanced) throw new Error('PDS project parentheses are unbalanced');
  if (info.missing.length) throw new Error(`PDS project has missing source or constraint files: ${info.missing.join(', ')}`);
  if (!ctx.config?.pdsShell || !(await exists(ctx.config.pdsShell))) throw new Error('PDS shell is unavailable; configure pdsShell');
  if (args.pdsVersion && !String(ctx.config.pdsShell).toLowerCase().includes(String(args.pdsVersion).toLowerCase()))
    throw new Error(`Requested PDS version ${args.pdsVersion} is not the configured installation`);
  if (guiRunning()) throw new Error('PDS GUI pds.exe is running; close it before a batch build to avoid project corruption');
  const dir = path.dirname(info.pdsPath);
  const metaDir = await ensureDirectChildDir(dir, '.pango-mcp');
  const cacheFile = path.join(metaDir, `cache-${runTarget}.json`);
  const hash = await digestProject(info);
  if (args.cache !== false) {
    try {
      const cached = JSON.parse(await fs.readFile(cacheFile, 'utf8'));
      if (cached.hash === hash && cached.result?.ok && (runTarget !== 'gen_bit_stream' || cached.result.bitstreams?.every((p) => p && requireExistsSync(p))))
        return { ...cached.result, cached: true };
    } catch { /* stale cache */ }
  }
  const backupDir = args.backupOldBuildDirs === false ? null : await backupOutputs(dir, runTarget);
  const start = Date.now();
  const timeoutSec = Math.min(Math.max(Number(args.timeoutSec ?? 900), 1), 86400);
  const env = ctx.config.pdsLicense ? { PANGO_LICENSE_FILE: ctx.config.pdsLicense } : {};
  const result = await ctx.runProcess(ctx.config.pdsShell, ['-project', info.pdsPath, '-run', runTarget], { cwd: dir, timeoutSec, env });
  const stdout = String(result.stdout ?? ''), stderr = String(result.stderr ?? '');
  const logPath = path.join(metaDir, `run-${runTarget}-${new Date(start).toISOString().replace(/[:.]/g, '-')}.log`);
  await fs.writeFile(logPath, `${stdout}\n${stderr}`, 'utf8');
  const report = await reportsFor(dir, args.detail);
  const logCandidates = [path.join(dir, 'run.log'), path.join(dir, 'flow.log')];
  if (runTarget === 'compile') logCandidates.push(path.join(dir, 'compile', 'run.log'));
  if (runTarget === 'synthesize') logCandidates.push(path.join(dir, 'synthesize', 'run.log'));
  if (runTarget === 'dev_map') logCandidates.push(path.join(dir, 'device_map', 'run.log'));
  if (runTarget === 'pnr') logCandidates.push(path.join(dir, 'place_route', 'run_route_optimize.log'));
  if (runTarget === 'report_timing') logCandidates.push(path.join(dir, 'report_timing', 'run.log'));
  if (runTarget === 'gen_bit_stream') logCandidates.push(path.join(dir, 'generate_bitstream', 'run.log'));
  let fresh = `${stdout}\n${stderr}`;
  for (const p of logCandidates) {
    try { if ((await fs.stat(p)).mtimeMs >= start - 3000) fresh += `\n${await read(p)}`; } catch { /* absent */ }
  }
  const errors = errorsIn(fresh);
  const stageSucceeded = SUCCESS[runTarget].test(fresh);
  const freshBitstream = runTarget !== 'gen_bit_stream' || (await Promise.all(report.bitstreams.map(async (p) => {
    try { return (await fs.stat(p)).mtimeMs >= start - 3000; } catch { return false; }
  }))).some(Boolean);
  const ok = result.code === 0 && !result.timedOut && errors.length === 0 && stageSucceeded && freshBitstream;
  const verdict = {
    ok, pdsPath: info.pdsPath, runTarget, exitCode: result.code, timedOut: !!result.timedOut,
    stageSucceeded, errors: errors.slice(0, 30), errorCount: errors.length,
    timing: report.timing, utilization: report.utilization,
    bitstreams: report.bitstreams, timingReport: report.timingReport,
    logPath, backupDir, cached: false,
    diagnostics: [
      ...(!stageSucceeded ? [`PDS did not report successful completion of ${runTarget}`] : []),
      ...(!freshBitstream ? ['No newly generated .sbit or .sfc was found'] : []),
      ...(report.timing && report.timing.met === false ? ['Timing constraints are not met'] : []),
    ],
  };
  if (args.detail === 'full') verdict.full = { stdout, stderr, reports: report.full };
  if (ok) {
    const postHash = await digestProject(await projectInfo(info.pdsPath));
    await fs.writeFile(cacheFile, JSON.stringify({ hash: postHash, result: verdict }, null, 2));
  }
  return verdict;
}
function requireExistsSync(p) { try { return !!p && statSync(p).isFile(); } catch { return false; } }

async function createProject(ctx, args, blink = false) {
  const projectDir = abs(args.projectDir, 'projectDir');
  const name = validateToken(args.name ?? (blink ? 'fab_blink' : 'fpga_mcp_demo'), 'name');
  const top = validateToken(args.top ?? 'top', 'top');
  const board = args.board ? ctx.config?.boards?.[args.board] : null;
  if (args.board && !board) throw new Error(`Unknown board profile: ${args.board}`);
  const spec = Object.fromEntries(['family', 'device', 'speedgrade', 'package'].map((k) => [k, args[k] ?? board?.[k]]));
  const missing = Object.entries(spec).filter(([, v]) => !v).map(([k]) => k);
  if (missing.length) throw new Error(`Missing target fields: ${missing.join(', ')}`);
  for (const [key, value] of Object.entries(spec)) spec[key] = validatePart(value, key);
  if (blink && (!args.clkPin || !Array.isArray(args.ledPins) || !args.ledPins.length))
    throw new Error('Blink project requires clkPin and a nonempty ledPins array');
  const rtlFile = path.join(projectDir, `${top}.v`);
  const fdcFile = path.join(projectDir, `${top}.fdc`);
  const tclFile = path.join(projectDir, `${name}.tcl`);
  const pdsFile = path.join(projectDir, `${name}.pds`);
  let rtl, fdc = '';
  if (blink) {
    const clkPin = validatePart(args.clkPin, 'clkPin');
    const ledPins = args.ledPins.map((p, i) => validatePart(p, `ledPins[${i}]`));
    const freq = Number(args.clkFreqMhz ?? 50);
    const counterBit = Number(args.counterBit ?? 24);
    if (!(freq > 0 && freq <= 1000)) throw new Error('clkFreqMhz must be between 0 and 1000');
    if (!Number.isInteger(counterBit) || counterBit < 0 || counterBit > 62) throw new Error('counterBit must be an integer from 0 to 62');
    const ioStandard = validatePart(args.ioStandard ?? 'LVCMOS33', 'ioStandard');
    const vccio = Number(args.vccio ?? 3.3);
    if (!(vccio > 0 && vccio <= 5)) throw new Error('vccio must be a voltage between 0 and 5');
    const bits = Math.max(counterBit + ledPins.length, 26);
    rtl = `module ${top}(input wire clk, output wire [${ledPins.length - 1}:0] led);\n  reg [${bits - 1}:0] counter = 0;\n  always @(posedge clk) counter <= counter + 1'b1;\n  assign led = counter[${counterBit + ledPins.length - 1}:${counterBit}];\nendmodule\n`;
    fdc = `create_clock -name {clk} [get_ports {clk}] -period {${(1000 / freq).toFixed(3)}}\n`;
    const pinLine = (signal, pin, direction) =>
      `define_attribute {p:${signal}} {PAP_IO_DIRECTION} {${direction}}\n` +
      `define_attribute {p:${signal}} {PAP_IO_LOC} {${pin}}\n` +
      `define_attribute {p:${signal}} {PAP_IO_VCCIO} {${vccio}}\n` +
      `define_attribute {p:${signal}} {PAP_IO_STANDARD} {${ioStandard}}\n`;
    fdc += pinLine('clk', clkPin, 'INPUT');
    ledPins.forEach((pin, i) => { fdc += pinLine(`led[${i}]`, pin, 'OUTPUT'); });
  } else {
    rtl = `module ${top}(input wire clk, output wire led);\n  reg [25:0] counter = 0;\n  always @(posedge clk) counter <= counter + 1'b1;\n  assign led = counter[25];\nendmodule\n`;
    const pins = board?.pins ?? {};
    const names = args.pinNames ?? Object.keys(pins);
    for (const name of names) {
      if (!/^(clk|led)$/.test(name)) throw new Error(`Generic project only exposes clk and led; unsupported pinName: ${name}`);
      const pin = pins[name];
      if (!pin) throw new Error(`Board profile has no pin named ${name}`);
      const loc = typeof pin === 'string' ? pin : pin.loc ?? pin.pin;
      if (!loc) throw new Error(`Board pin ${name} has no loc`);
      fdc += `define_attribute {p:${name}} {PAP_IO_DIRECTION} {${name === 'clk' ? 'INPUT' : 'OUTPUT'}}\n`;
      fdc += `define_attribute {p:${name}} {PAP_IO_LOC} {${validatePart(loc, `pins.${name}.loc`)}}\n`;
      if (pin.ioStandard) fdc += `define_attribute {p:${name}} {PAP_IO_STANDARD} {${validatePart(pin.ioStandard, 'ioStandard')}}\n`;
      if (pin.vccio) fdc += `define_attribute {p:${name}} {PAP_IO_VCCIO} {${Number(pin.vccio)}}\n`;
    }
    const freq = Number(board?.clkFreqMhz ?? board?.clockMhz);
    if (freq > 0 && names.includes('clk')) fdc = `create_clock -name {clk} [get_ports {clk}] -period {${(1000 / freq).toFixed(3)}}\n` + fdc;
    if (!fdc) fdc = '# Add board timing and pin constraints before generating a bitstream.\n';
  }
  const tcl = `set_arch -family ${spec.family} -device ${spec.device} -speedgrade ${spec.speedgrade} -package ${spec.package}\nadd_design ${tclPath(rtlFile)}\nadd_constraint ${tclPath(fdcFile)}\nputs {PANGO_MCP_PROJECT_CREATED}\n`;
  if (!ctx.config?.pdsShell || !(await exists(ctx.config.pdsShell)))
    throw new Error('PDS shell is unavailable; configure pdsShell before creating a project');
  if (guiRunning()) throw new Error('PDS GUI is open; close it before creating a .pds project');
  const existing = await fs.readdir(projectDir).catch((e) => { if (e.code === 'ENOENT') return []; throw e; });
  if (existing.length && !args.force) throw new Error('projectDir is not empty; pass force:true to preserve old generated files in a backup');
  await fs.mkdir(projectDir, { recursive: true });
  if (args.force) {
    const generated = [rtlFile, fdcFile, tclFile, pdsFile].filter((p) => existing.includes(path.basename(p)));
    if (generated.length) {
      const meta = await ensureDirectChildDir(projectDir, '.pango-mcp');
      const backups = await ensureDirectChildDir(meta, 'create-backups', projectDir);
      const backup = await ensureDirectChildDir(backups, new Date().toISOString().replace(/[:.]/g, '-'), projectDir);
      for (const p of generated) {
        const stat = await fs.lstat(p);
        if (stat.isSymbolicLink() || !stat.isFile() || !isInside(await fs.realpath(p), await fs.realpath(projectDir)))
          throw new Error(`Refusing to replace linked or external generated file: ${p}`);
        await fs.rename(p, path.join(backup, path.basename(p)));
      }
    }
    await backupOutputs(projectDir, 'gen_bit_stream');
  }
  await Promise.all([fs.writeFile(rtlFile, rtl), fs.writeFile(fdcFile, fdc), fs.writeFile(tclFile, tcl)]);
  const result = await ctx.runProcess(ctx.config.pdsShell, ['-file', tclFile, '-work_dir', projectDir], {
    cwd: projectDir, timeoutSec: 120,
    env: ctx.config.pdsLicense ? { PANGO_LICENSE_FILE: ctx.config.pdsLicense } : {},
  });
  const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}\n${await read(path.join(projectDir, 'run.log'))}`;
  const errors = errorsIn(output);
  const ok = result.code === 0 && !result.timedOut && errors.length === 0 && await exists(pdsFile);
  return {
    ok, pdsPath: await exists(pdsFile) ? pdsFile : null,
    files: [rtlFile, fdcFile, tclFile], target: spec, top,
    errors, diagnostics: ok ? [] : ['PDS did not confirm creation of the .pds project'],
    note: blink ? 'Pin mapping and clock frequency came from the supplied arguments' : (!board ? 'No board pin or clock assumptions were made; complete the FDC before bitstream generation' : undefined),
  };
}

async function batchPds(ctx, args) {
  if (!Array.isArray(args.variants) || !args.variants.length) throw new Error('variants must be a nonempty array');
  const specs = await Promise.all(args.variants.map(async (v, i) => {
    const pdsPath = abs(v.pdsPath, `variants[${i}].pdsPath`);
    const info = await projectInfo(pdsPath);
    const dir = await fs.realpath(path.dirname(pdsPath));
    for (const [key, rel] of [['prj_work_dir', info.workDir], ['prj_impl_dir', info.implDir]]) {
      const target = path.resolve(dir, rel);
      if (!isInside(target, dir)) throw new Error(`Variant ${i} has external ${key}: ${rel}`);
    }
    const tasks = path.join(dir, 'prj_tasks');
    if (await exists(tasks) && !isInside(await fs.realpath(tasks), dir)) throw new Error(`Variant ${i} has external prj_tasks`);
    return { ...v, pdsPath, dir };
  }));
  for (let i = 0; i < specs.length; i++) for (let j = i + 1; j < specs.length; j++) {
    if (isInside(specs[i].dir, specs[j].dir) || isInside(specs[j].dir, specs[i].dir))
      throw new Error(`Variants ${i} and ${j} have identical or nested project directories`);
  }
  const concurrency = Math.min(Math.max(Math.floor(Number(args.maxParallel ?? 2)), 1), 2);
  const results = new Array(specs.length);
  let next = 0;
  await Promise.all(Array.from({ length: Math.min(concurrency, specs.length) }, async () => {
    while (next < specs.length) {
      const i = next++;
      results[i] = await wrap((v) => runPds(ctx, v, args.runTarget ?? 'gen_bit_stream'))({
        ...specs[i], cache: specs[i].cache ?? args.cache,
        timeoutSec: specs[i].timeoutSec ?? args.timeoutSec,
        backupOldBuildDirs: specs[i].backupOldBuildDirs ?? args.backupOldBuildDirs,
        detail: specs[i].detail ?? 'summary',
      });
    }
  }));
  return { ok: results.every((x) => x.ok), count: results.length, results };
}

async function tcpOpen(port) {
  return new Promise((resolve) => {
    const socket = net.createConnection({ host: '127.0.0.1', port });
    socket.setTimeout(700);
    socket.once('connect', () => { socket.destroy(); resolve(true); });
    socket.once('error', () => { socket.destroy(); resolve(false); });
    socket.once('timeout', () => { socket.destroy(); resolve(false); });
  });
}
async function removeScanScratch(scratch) {
  const tmpRoot = await fs.realpath(os.tmpdir());
  const stat = await fs.lstat(scratch);
  const realScratch = await fs.realpath(scratch);
  if (!stat.isDirectory() || stat.isSymbolicLink() ||
      !path.basename(scratch).startsWith('pango-mcp-scan-') ||
      !path.basename(realScratch).startsWith('pango-mcp-scan-') ||
      norm(path.dirname(realScratch)) !== norm(tmpRoot) ||
      norm(path.resolve(scratch)) !== norm(realScratch)) {
    throw new Error(`Refusing recursive cleanup outside the scan scratch directory: ${scratch}`);
  }
  for (let attempt = 0; attempt < 5; attempt++) {
    try { await fs.rm(scratch, { recursive: true, force: true }); return; }
    catch (e) {
      if (!['EBUSY', 'EPERM'].includes(e.code) || attempt === 4) throw e;
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
  }
}
async function scanPds(ctx, args) {
  if (args.host) throw new Error('Remote JTAG scan is unavailable in this local reconstruction');
  const bin = ctx.config?.pdsBin ?? (ctx.config?.pdsShell ? path.dirname(ctx.config.pdsShell) : null);
  if (!bin) throw new Error('PDS bin directory is not configured');
  const cfg = path.join(bin, 'cdt_cfg.exe'), js = path.join(bin, 'cdt_js.exe');
  if (!(await exists(cfg)) || !(await exists(js))) throw new Error('PDS cdt_cfg.exe or cdt_js.exe is missing');
  const port = Number(args.port ?? 65420);
  if (!Number.isInteger(port) || port < 1024 || port > 65535) throw new Error('port must be 1024..65535');
  const scratch = await fs.mkdtemp(path.join(os.tmpdir(), 'pango-mcp-scan-'));
  let server = null;
  let serverError = null;
  try {
    if (!(await tcpOpen(port))) {
      server = spawn(js, ['-port', String(port), '-work_dir', scratch], { cwd: scratch, windowsHide: true, stdio: 'ignore' });
      server.once('error', (e) => { serverError = e; });
      let ready = false;
      for (let i = 0; i < 30; i++) {
        if (server.exitCode !== null || serverError) break;
        await new Promise((resolve) => setTimeout(resolve, 300));
        if (await tcpOpen(port)) { ready = true; break; }
      }
      if (!ready) throw new Error(`JtagServer did not open its TCP port${serverError ? `: ${serverError.message}` : ''}`);
    }
    const script = path.join(scratch, 'scan.tcl');
    await fs.writeFile(script, `cfg_connect -ip 127.0.0.1 -port ${port}\ncfg_scan_chain\ncfg_disconnect\n`, 'utf8');
    const result = await ctx.runProcess(cfg, ['-file', script, '-work_dir', scratch], { cwd: scratch, timeoutSec: Math.min(Math.max(Number(args.timeoutSec ?? 30), 1), 120), env: {} });
    const output = `${result.stdout ?? ''}\n${result.stderr ?? ''}\n${await read(path.join(scratch, 'log', 'cfg.log'))}`;
    const errors = errorsIn(output);
    const devices = unique([...output.matchAll(/^\s*(PGL\w+|PG\w+|PGA\w+|0x[\da-f]{8})\s*$/gmi)].map((m) => m[1]));
    const scanSuccess = /Executing\s*:\s*cfg_scan_chain successfully/i.test(output);
    return {
      ok: result.code === 0 && !result.timedOut && errors.length === 0 && scanSuccess,
      readOnly: true, devices, idcodes: unique([...output.matchAll(/\b0x[0-9a-f]{8}\b/gi)].map((m) => m[0])),
      errors, scanSuccess, log: output.slice(-8000),
      note: devices.length && !/\b0x[0-9a-f]{8}\b/i.test(output) ? 'This PDS version reports device names but no IDCODE in cfg_scan_chain output' : undefined,
    };
  } finally {
    if (server) {
      server.kill();
      if (server.exitCode === null) await Promise.race([
        new Promise((resolve) => server.once('close', resolve)),
        new Promise((resolve) => setTimeout(resolve, 1500)),
      ]);
    }
    await removeScanScratch(scratch);
  }
}

const runProps = {
  pdsPath: str('Absolute path to an existing .pds project'),
  runTarget: { type: 'string', enum: TARGETS, description: 'PDS -run target' },
  cache: bool('Reuse a successful build when project and source contents are unchanged'),
  detail: { type: 'string', enum: ['summary', 'full'] },
  pdsVersion: str('Configured PDS version label'),
  timeoutSec: num('Build timeout in seconds', 1, 86400),
  backupOldBuildDirs: bool('Move previous build output directories into .pango-mcp/backups before running'),
  host: str('Remote host id; unavailable in this local reconstruction'),
};
const createProps = {
  projectDir: str('Absolute output directory'), name: str('Project name'), top: str('Top module name'),
  family: str('PDS target family'), device: str('PDS target device'),
  speedgrade: str('PDS speed grade'), package: str('PDS package'),
  board: str('Named complete board profile in server config'),
  pinNames: { type: 'array', items: { type: 'string' } },
  force: bool('Allow nonempty directory; back up generated files before replacement'),
};

export function pdsTools(ctx) {
  return [
    {
      name: 'fpga_project_info', description: 'Read a PDS project file: device, top, sources, constraints, and structural validity.',
      inputSchema: obj({ pdsPath: str('Absolute path to .pds project') }, ['pdsPath']),
      run: wrap(({ pdsPath }) => projectInfo(pdsPath)),
    },
    {
      name: 'fpga_pds_reports', description: 'Read PDS logs, timing report, utilization and bitstream paths without invoking PDS.',
      inputSchema: obj({ pdsPath: str('Absolute path to .pds project'), projectDir: str('Absolute PDS output directory'), detail: { type: 'string', enum: ['summary', 'full'] } }),
      run: wrap(async (args) => {
        if (!args.pdsPath && !args.projectDir) throw new Error('Provide pdsPath or projectDir');
        return reportsFor(args.projectDir ? abs(args.projectDir, 'projectDir') : path.dirname(abs(args.pdsPath, 'pdsPath')), args.detail);
      }),
    },
    {
      name: 'fpga_pds_run', description: 'Run a selected PDS flow stage and return parsed errors, timing, utilization, and artifacts.',
      inputSchema: obj(runProps, ['pdsPath', 'runTarget']),
      run: wrap((args) => runPds(ctx, args)),
    },
    {
      name: 'fpga_pds_compile', description: 'Run PDS through bitstream generation; report a failed build when logs or output contradict exit code.',
      inputSchema: obj(runProps, ['pdsPath']),
      run: wrap((args) => runPds(ctx, args, 'gen_bit_stream')),
    },
    {
      name: 'fpga_pds_batch', description: 'Run up to two independent PDS project clones in parallel and retain every variant result.',
      inputSchema: obj({
        variants: { type: 'array', minItems: 1, items: obj({ ...runProps, name: str('Variant name') }, ['pdsPath']) },
        runTarget: { type: 'string', enum: TARGETS }, cache: bool('Use per-project cache'),
        timeoutSec: num('Per-variant timeout in seconds', 1, 86400), maxParallel: { type: 'integer', minimum: 1, maximum: 2 },
        backupOldBuildDirs: bool('Back up previous build directories'),
      }, ['variants']),
      run: wrap((args) => batchPds(ctx, args)),
    },
    {
      name: 'fpga_pds_create_project', description: 'Generate minimal RTL/FDC/Tcl and use PDS to create a .pds project for an explicitly supplied target.',
      inputSchema: obj(createProps, ['projectDir']),
      run: wrap((args) => createProject(ctx, args)),
    },
    {
      name: 'fpga_pds_create_blink_project', description: 'Generate an LED blink PDS project using the exact target, clock pin and LED pins supplied by the caller.',
      inputSchema: obj({
        ...createProps, clkPin: str('Clock input package pin'),
        ledPins: { type: 'array', minItems: 1, items: { type: 'string' } },
        clkFreqMhz: num('Board clock frequency in MHz', 0.001, 1000),
        counterBit: { type: 'integer', minimum: 0, maximum: 62 },
        vccio: num('I/O supply voltage', 0.1, 5), ioStandard: str('PDS I/O standard'),
      }, ['projectDir', 'family', 'device', 'speedgrade', 'package', 'clkPin', 'ledPins']),
      run: wrap((args) => createProject(ctx, args, true)),
    },
    {
      name: 'fpga_pds_register_fic', description: 'Register a validated Fabric Inserter .fic in a PDS 2023.2-SP3 project, backing up the original .pds first.',
      inputSchema: obj({ pdsPath: str('Absolute path to a PDS 2023.2-SP3 .pds project'), ficPath: str('Absolute path to a generated .fic file for this project') }, ['pdsPath', 'ficPath']),
      run: wrap(registerFic),
    },
    {
      name: 'fpga_pds_scan', description: 'Read the local JTAG chain with PDS cfg_scan_chain; does not program the device.',
      inputSchema: obj({ port: { type: 'integer', minimum: 1024, maximum: 65535 }, timeoutSec: num('Scan timeout in seconds', 1, 120), host: str('Remote host id; unavailable locally') }),
      run: wrap((args) => scanPds(ctx, args)),
    },
  ];
}
