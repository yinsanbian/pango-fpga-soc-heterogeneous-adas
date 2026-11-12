import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { spawn } from 'node:child_process';
import { evaluateAssertions } from './basic.mjs';
import { renderWave } from './vcd.mjs';

const HDL = /\.(?:v|vp|sv|svp|vhd|vhdl)$/i;
const VHDL = /\.(?:vhd|vhdl)$/i;
const EXE_ALLOWED = new Set(['vlib', 'vmap', 'vdir', 'vcover', 'wlf2vcd', 'vcd2wlf', 'vgencomp', 'vmake', 'vopt', 'sccom']);
const TOOL_TIMEOUT = 120;

const str = { type: 'string' };
const bool = { type: 'boolean' };
const strings = { type: 'array', items: str };
const seconds = { type: 'number', minimum: 1 };
const detail = { type: 'string', enum: ['summary', 'full'] };

function tool(name, description, properties, required, run) {
  return {
    name,
    description,
    inputSchema: { type: 'object', properties, required, additionalProperties: false },
    run: async (args = {}) => {
      try { return await run(args); }
      catch (error) { return { ok: false, error: error instanceof Error ? error.message : String(error) }; }
    },
  };
}

function need(condition, message) {
  if (!condition) throw new Error(message);
}

function array(value, name) {
  if (value === undefined) return [];
  need(Array.isArray(value) && value.every(x => typeof x === 'string'), `${name} 必须是字符串数组`);
  return value;
}

function posix(p) { return p.replaceAll('\\', '/'); }
function abs(base, p) { return path.isAbsolute(p) ? path.normalize(p) : path.resolve(base, p); }
async function fileExists(p) { try { return (await fs.stat(p)).isFile(); } catch { return false; } }

async function existingDir(p, name) {
  need(typeof p === 'string' && path.isAbsolute(p), `${name} 必须是绝对路径`);
  need((await fs.stat(p).catch(() => null))?.isDirectory(), `${name} 目录不存在: ${p}`);
  return path.resolve(p);
}

function validLib(name) {
  const lib = name || 'work';
  need(typeof lib === 'string' && /^[A-Za-z][A-Za-z0-9_]*$/.test(lib), 'lib 必须是 ModelSim 库名');
  return lib;
}

function parseIssues(output, code, timedOut) {
  const lines = String(output || '').split(/\r?\n/);
  const errors = lines.filter(line => /(?:^|\s)\*\*\s*(?:Error|Fatal|Failure)\b|\bError loading design\b|\bErrors:\s*[1-9]\d*/i.test(line));
  const warnings = lines.filter(line => /(?:^|\s)\*\*\s*Warning\b|\bWarnings:\s*[1-9]\d*/i.test(line));
  if (timedOut) errors.push('ModelSim 运行超时');
  if (code !== 0 && code !== null && !timedOut && errors.length === 0) errors.push(`ModelSim 退出码 ${code}`);
  if (code === null && !timedOut && errors.length === 0) errors.push('ModelSim 未返回退出码');
  return { ok: errors.length === 0, errors: errors.slice(0, 30), warnings: warnings.slice(0, 20) };
}

function childEnv(home, license) {
  const env = { ...process.env };
  const existingPath = env.Path || env.PATH || '';
  env.Path = `${home};${existingPath}`;
  env.PATH = env.Path;
  if (license) {
    env.LM_LICENSE_FILE = license;
    env.MGLS_LICENSE_FILE = license;
  }
  return env;
}

function modelsimConfig(ctx) {
  const home = ctx.config?.modelsimHome || process.env.PANGO_MCP_MODELSIM_HOME;
  need(home && path.isAbsolute(home), '请设置 PANGO_MCP_MODELSIM_HOME 为 ModelSim bin 绝对路径');
  const license = ctx.config?.modelsimLicense || process.env.PANGO_MCP_MODELSIM_LICENSE;
  return { home: path.resolve(home), license, env: childEnv(path.resolve(home), license) };
}

function licensedConfig(ctx) {
  const config = modelsimConfig(ctx);
  need(config.license, '运行 ModelSim 仿真需设置 PANGO_MCP_MODELSIM_LICENSE');
  return config;
}

async function runVendor(ctx, config, exeName, args, { cwd, timeoutSec = TOOL_TIMEOUT } = {}) {
  const executable = path.join(config.home, `${exeName}.exe`);
  need(await fileExists(executable), `ModelSim 可执行文件不存在: ${executable}`);
  const result = await ctx.runProcess(executable, args.map(String), {
    cwd: cwd || config.home, timeoutSec, env: config.env,
  });
  const output = [result.stdout, result.stderr].filter(Boolean).join('\n');
  return { ...result, output, ...parseIssues(output, result.code, result.timedOut) };
}

function tclWord(s) {
  return `"${String(s).replace(/["$\[\]\\]/g, '\\$&').replaceAll('\n', '\\n').replaceAll('\r', '\\r')}"`;
}

function tclPath(s) {
  return tclWord(posix(String(s)));
}

function safeRunArg(value) {
  const runArg = value === undefined ? '-all' : String(value).trim();
  need(runArg === '-all' || /^\d+(?:\.\d+)? ?(?:fs|ps|ns|us|ms|s)?$/i.test(runArg), 'runArg 只能是 -all 或定长时间，如 1us');
  return runArg;
}

function safePrelude(script) {
  const lines = String(script).split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  need(lines.length > 0, 'doBeforeRun 不能为空');
  for (const line of lines) {
    need(!/[;\[\]$\\{}#"\x00-\x1f]/.test(line), 'doBeforeRun 禁止 Tcl 替换、转义、分号和控制字符');
    const plain = line.replace(/^quietly\s+/, '');
    const allowed = /^force\s+[\w./*:-]+\s+[\w.'+/@:-]+(?:\s+[\w.'+/@:-]+)*$/i.test(plain)
      || /^add\s+wave(?:\s+[-\w./*:+@]+)+$/i.test(plain)
      || /^coverage\s+(?:clear|report)$/i.test(plain)
      || /^coverage\s+(?:exclude|attribute)\s+[-\w./*:+@ ]+$/i.test(plain);
    need(allowed, `doBeforeRun 不支持该命令: ${line.slice(0, 80)}`);
  }
  return lines.join('\n');
}

function trivialDo(script) {
  const lines = String(script).split(/\r?\n/).map(s => s.trim()).filter(Boolean);
  if (lines.length !== 1 || /[;\[\]$\\{}#'"\x00-\x1f]/.test(lines[0])) return false;
  const line = lines[0];
  return /^run\s+(?:-all|\d+(?:\.\d+)?\s*(?:fs|ps|ns|us|ms|s)?)$/i.test(line)
    || /^examine(?:\s+[-\w./*:+@]+)+$/i.test(line)
    || /^add\s+wave(?:\s+[-\w./*:+@]+)+$/i.test(line)
    || /^coverage\s+report$/i.test(line);
}

function guardedVsimArgs(args, confirmed = false) {
  const values = array(args, 'vsimArgs');
  if (confirmed) return values;
  for (let i = 0; i < values.length; i++) {
    const option = values[i];
    if (['-coverage', '-novopt', '-quiet'].includes(option)) continue;
    if (/^-voptargs=\+acc(?:=.*)?$/i.test(option)) continue;
    if (/^-[gG][A-Za-z_]\w*=[\w.+/-]+$/.test(option)) continue;
    if (/^\+UVM_TESTNAME=[A-Za-z_]\w*$/.test(option)) continue;
    if (option === '-L') {
      need(/^[A-Za-z_]\w*$/.test(values[++i] || ''), '-L 后必须是库名');
      continue;
    }
    if (option === '-t') {
      need(/^\d+(?:fs|ps|ns|us|ms|s)$/i.test(values[++i] || ''), '-t 后必须是时间精度');
      continue;
    }
    if (option === '-onfinish') {
      need(['ask', 'stop', 'exit', 'final'].includes(values[++i]), '-onfinish 模式无效');
      continue;
    }
    need(false, `vsimArgs 选项 ${option} 未列入安全参数；请使用 fpga_msim_do 并显式 confirm:true`);
  }
  return values;
}

function tokenizeFileList(text) {
  const tokens = [];
  for (const rawLine of text.replace(/\\\r?\n/g, ' ').split(/\r?\n/)) {
    const line = rawLine.replace(/^\s*(?:#|\/\/).*$/, '').replace(/\s+#.*$/, '').replace(/\s+\/\/.*$/, '').trim();
    if (!line) continue;
    for (const token of line.match(/"(?:\\.|[^"])*"|'(?:\\.|[^'])*'|\S+/g) || []) {
      tokens.push(/^['"]/.test(token) ? token.slice(1, -1) : token);
    }
  }
  return tokens;
}

async function expandFileList(filePath, visited = new Set()) {
  const full = path.resolve(filePath);
  need(!visited.has(full), `fileList 循环引用: ${full}`);
  need(await fileExists(full), `fileList 不存在: ${full}`);
  visited.add(full);
  const tokens = tokenizeFileList(await fs.readFile(full, 'utf8'));
  const result = { args: [], files: [full] };
  const base = path.dirname(full);
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (token === '-f' || token === '-F') {
      need(i + 1 < tokens.length, `${token} 缺少文件路径: ${full}`);
      const nested = await expandFileList(abs(base, tokens[++i]), visited);
      result.args.push(...nested.args); result.files.push(...nested.files);
    } else if (token === '-y' || token === '-v' || token === '-incdir') {
      need(i + 1 < tokens.length, `${token} 缺少路径: ${full}`);
      const p = abs(base, tokens[++i]);
      result.args.push(token, p);
      if (token === '-v') result.files.push(p);
    } else if (token.startsWith('+incdir+')) {
      const dirs = token.slice(8).split('+').filter(Boolean).map(p => posix(abs(base, p)));
      result.args.push(`+incdir+${dirs.join('+')}`);
    } else if (HDL.test(token) && !token.startsWith('+') && !token.startsWith('-')) {
      const p = abs(base, token);
      result.args.push(p); result.files.push(p);
    } else {
      result.args.push(token);
    }
  }
  visited.delete(full);
  return result;
}

async function inputFiles(args, workdir) {
  let sources;
  if (args.sources === undefined) {
    const entries = await fs.readdir(workdir, { withFileTypes: true });
    sources = entries.filter(e => e.isFile() && HDL.test(e.name) && !/^[._]/.test(e.name))
      .map(e => path.join(workdir, e.name)).sort();
  } else {
    sources = array(args.sources, 'sources').map(p => abs(workdir, p));
  }
  for (const source of sources) need(await fileExists(source), `HDL 源文件不存在: ${source}`);
  const list = args.fileList ? await expandFileList(abs(workdir, args.fileList)) : { args: [], files: [] };
  need(sources.length || list.args.length, '未找到 HDL 源文件，请传 sources 或 fileList');
  const libDirs = array(args.libDirs, 'libDirs').map(p => abs(workdir, p));
  for (const p of libDirs) await existingDir(p, 'libDirs');
  return { sources, list, libDirs };
}

async function sourceHash(files, semantics) {
  const hash = crypto.createHash('sha256').update(JSON.stringify(semantics));
  for (const p of [...new Set(files)].sort()) {
    hash.update(p);
    if (await fileExists(p)) hash.update(await fs.readFile(p));
    else hash.update('MISSING');
  }
  return hash.digest('hex');
}

async function prepareLibrary(ctx, config, workdir, lib, buildDir, timeoutSec) {
  await fs.mkdir(buildDir, { recursive: true });
  const localIni = path.join(workdir, 'modelsim.ini');
  const installIni = path.resolve(config.home, '..', 'modelsim.ini');
  const sourceIni = await fileExists(localIni) ? localIni : installIni;
  need(await fileExists(sourceIni), `缺少 modelsim.ini: ${localIni} / ${installIni}`);
  const ini = path.join(buildDir, 'modelsim.ini');
  await fs.copyFile(sourceIni, ini);
  const library = path.join(buildDir, lib);
  const vlib = await runVendor(ctx, config, 'vlib', [library], { cwd: workdir, timeoutSec });
  if (!vlib.ok) throw new Error(`vlib 失败: ${vlib.errors.join('; ') || vlib.output.slice(-1000)}`);
  const vmap = await runVendor(ctx, config, 'vmap', ['-modelsimini', posix(ini), lib, posix(library)], { cwd: workdir, timeoutSec });
  if (!vmap.ok) throw new Error(`vmap 失败: ${vmap.errors.join('; ') || vmap.output.slice(-1000)}`);
  return { ini, library };
}

function compileGroups(sources) {
  const groups = [];
  for (const source of sources) {
    const language = VHDL.test(source) ? 'vcom' : 'vlog';
    const previous = groups.at(-1);
    if (previous?.language === language) previous.files.push(source);
    else groups.push({ language, files: [source] });
  }
  return groups;
}

async function compileDesign(ctx, args, { uvm = false, coverage = false } = {}) {
  const config = modelsimConfig(ctx);
  const workdir = await existingDir(args.workdir, 'workdir');
  const lib = validLib(args.lib);
  const timeoutSec = args.timeoutSec ?? TOOL_TIMEOUT;
  const input = await inputFiles(args, workdir);
  const vlogArgs = array(args.vlogArgs, 'vlogArgs');
  const vcomArgs = array(args.vcomArgs, 'vcomArgs');
  const uvmSrc = path.resolve(config.home, '..', 'verilog_src', 'uvm-1.1b', 'src');
  if (uvm) need((await fs.stat(uvmSrc).catch(() => null))?.isDirectory(), `ModelSim UVM 源目录不存在: ${uvmSrc}`);
  const semantic = { sources: input.sources, list: input.list.args, libDirs: input.libDirs, vlogArgs, vcomArgs, lib, uvm, coverage, home: config.home };
  const localIni = path.join(workdir, 'modelsim.ini');
  const installIni = path.resolve(config.home, '..', 'modelsim.ini');
  const iniSource = await fileExists(localIni) ? localIni : installIni;
  const hashFiles = [...input.sources, ...input.list.files, iniSource];
  const hash = await sourceHash(hashFiles, semantic);
  const root = path.join(workdir, '._fpga_msim');
  await fs.mkdir(root, { recursive: true });
  const cacheFile = path.join(root, `compile-${hash}.json`);
  const hasIncludes = (await Promise.all([...new Set(hashFiles.filter(p => HDL.test(p)))].map(async p =>
    await fileExists(p) && /`include\b/.test(await fs.readFile(p, 'utf8'))))).some(Boolean);
  const cacheable = args.cache !== false && input.libDirs.length === 0
    && !hasIncludes
    && !input.list.args.some(x => x === '-y' || x.startsWith('+incdir+'))
    && !vlogArgs.some(x => x === '-y' || x.startsWith('+incdir+'));
  if (cacheable && await fileExists(cacheFile)) {
    const previous = JSON.parse(await fs.readFile(cacheFile, 'utf8'));
    if (await fileExists(path.join(previous.library, '_info')) && await fileExists(previous.ini)) {
      await fs.writeFile(path.join(root, 'current.json'), JSON.stringify(previous, null, 2));
      return { ...previous, cached: true, cacheable, hash, workdir, lib, root };
    }
  }
  const buildDir = path.join(root, `build-${hash.slice(0, 10)}-${crypto.randomUUID().slice(0, 8)}`);
  const { ini, library } = await prepareLibrary(ctx, config, workdir, lib, buildDir, timeoutSec);
  const output = [];
  let verdict = { ok: true, errors: [], warnings: [] };
  const groups = compileGroups(input.sources);
  if (input.list.args.length) groups.push({ language: 'vlog', files: [], fileList: true });
  for (const [index, group] of groups.entries()) {
    const stageLog = path.join(buildDir, `compile-${index}-${group.language}.log`);
    const common = ['-modelsimini', posix(ini), '-work', lib, '-l', posix(stageLog)];
    let processArgs;
    if (group.language === 'vcom') {
      processArgs = [...common, ...(coverage ? ['+cover=bcst'] : []), ...vcomArgs, ...group.files];
    } else {
      const hasSv = group.files.some(f => /\.(?:sv|svp)$/i.test(f))
        || (group.fileList && input.list.files.some(f => /\.(?:sv|svp)$/i.test(f))) || uvm;
      processArgs = [...common];
      if (hasSv) processArgs.push('-sv');
      if (uvm) processArgs.push(`+incdir+${posix(uvmSrc)}`, '-L', 'mtiUvm');
      if (coverage) processArgs.push('+cover=bcst');
      for (const dir of input.libDirs) processArgs.push('-y', dir);
      if (input.libDirs.length) processArgs.push('+libext+.v+.sv+.vp+.svp');
      processArgs.push(...vlogArgs, ...group.files);
      if (group.fileList) processArgs.push(...input.list.args);
    }
    const stage = await runVendor(ctx, config, group.language, processArgs, { cwd: workdir, timeoutSec });
    const fullOutput = await fileExists(stageLog) ? await fs.readFile(stageLog, 'utf8') : stage.output;
    const issues = parseIssues(`${fullOutput}\n${stage.output}`, stage.code, stage.timedOut);
    output.push(`=== ${group.language} ===\n${fullOutput}`);
    verdict.errors.push(...issues.errors);
    verdict.warnings.push(...issues.warnings);
    if (!issues.ok) { verdict.ok = false; break; }
  }
  const log = path.join(buildDir, 'compile.log');
  await fs.writeFile(log, output.join('\n'), 'utf8');
  const result = { ok: verdict.ok, errors: verdict.errors, warnings: verdict.warnings, ini, library, log, buildDir, hash, workdir, lib, root, cached: false, cacheable };
  if (result.ok) {
    await fs.writeFile(path.join(root, 'current.json'), JSON.stringify(result, null, 2));
    if (cacheable) await fs.writeFile(cacheFile, JSON.stringify(result, null, 2));
  }
  return result;
}

async function compileTool(ctx, args) {
  const built = await compileDesign(ctx, args);
  const result = {
    ok: built.ok, phase: 'compile', cached: built.cached, errors: built.errors, warnings: built.warnings,
    artifacts: { log: built.log, library: built.library, modelsimIni: built.ini },
  };
  if (args.detail === 'full') result.transcript = await fs.readFile(built.log, 'utf8');
  return result;
}

function uvmCounts(log) {
  const result = {};
  for (const severity of ['INFO', 'WARNING', 'ERROR', 'FATAL']) {
    const matches = [...log.matchAll(new RegExp(`UVM_${severity}\\s*:\\s*(\\d+)`, 'gi'))];
    result[severity.toLowerCase()] = matches.length ? Number(matches.at(-1)[1]) : 0;
  }
  return result;
}

function coverageSummary(log) {
  const metrics = {};
  for (const kind of ['branch', 'statement', 'condition', 'toggle']) {
    const match = log.match(new RegExp(`${kind}s?\\s*[:|]\\s*(\\d+)\\s*/\\s*(\\d+)\\s*\\(([\\d.]+)%\\)`, 'i'));
    if (match) metrics[kind] = { hits: Number(match[1]), bins: Number(match[2]), misses: Number(match[2]) - Number(match[1]), pct: Number(match[3]) };
  }
  return { metrics };
}

async function simTool(ctx, args) {
  licensedConfig(ctx);
  need(typeof args.top === 'string' && /^[A-Za-z_][\w$]*$/.test(args.top), 'top 必须是模块或实体名');
  const wantsAssertions = Array.isArray(args.assertions) && args.assertions.length > 0;
  const assertionNeedsVcd = wantsAssertions && args.assertions.some(a =>
    typeof a === 'string' ? a.trim().startsWith('vcd_')
      : Object.keys(a || {}).some(k => k.startsWith('vcd_')) || String(a?.type || '').startsWith('vcd_'));
  const makeVcd = !!(args.vcd || args.wave || assertionNeedsVcd);
  const beforeRun = args.doBeforeRun === undefined ? '' : safePrelude(args.doBeforeRun);
  const vsimArgs = guardedVsimArgs(args.vsimArgs);
  const built = await compileDesign(ctx, args, { uvm: !!args.uvm, coverage: !!args.coverage });
  if (!built.ok) return { ok: false, phase: 'compile', errors: built.errors, warnings: built.warnings, artifacts: { log: built.log } };
  const { detail: _detail, cache: _cache, waveOpen: _waveOpen, ...simOptions } = args;
  const simHash = crypto.createHash('sha256').update(JSON.stringify({ compile: built.hash, simOptions })).digest('hex');
  const simCache = path.join(built.root, `sim-${simHash}.json`);
  if (built.cacheable && !args.waveOpen && await fileExists(simCache)) {
    const previous = JSON.parse(await fs.readFile(simCache, 'utf8'));
    const artifactPaths = Object.values(previous.artifacts || {});
    const artifactsPresent = artifactPaths.length > 0 && artifactPaths.every(p => typeof p === 'string' && !!p && path.isAbsolute(p))
      && (await Promise.all(artifactPaths.map(fileExists))).every(Boolean);
    if (artifactsPresent && (!makeVcd || await fileExists(previous.artifacts.vcd))) {
      const result = { ...previous, cached: true };
      if (args.detail === 'full') result.transcript = await fs.readFile(previous.artifacts.log, 'utf8');
      return result;
    }
  }
  const config = licensedConfig(ctx);
  const timeoutSec = args.timeoutSec ?? TOOL_TIMEOUT;
  const shortHash = simHash.slice(0, 12);
  const transcript = path.join(built.buildDir, `sim-${shortHash}.log`);
  const vcdPath = makeVcd ? abs(built.workdir, args.vcdPath || path.join(built.buildDir, `sim-${shortHash}.vcd`)) : undefined;
  if (vcdPath) await fs.mkdir(path.dirname(vcdPath), { recursive: true });
  const ucdbPath = args.coverage ? path.join(built.buildDir, `coverage-${shortHash}.ucdb`) : undefined;
  await fs.rm(transcript, { force: true });
  if (vcdPath) await fs.rm(vcdPath, { force: true });
  if (ucdbPath) await fs.rm(ucdbPath, { force: true });
  const commands = ['onerror {quit -f -code 1}'];
  if (vcdPath) commands.push(`vcd file ${tclPath(vcdPath)}`, 'vcd add -r /*');
  if (beforeRun) commands.push(beforeRun);
  commands.push(`run ${safeRunArg(args.runArg)}`);
  if (vcdPath) commands.push('vcd flush');
  if (ucdbPath) commands.push('coverage report', `coverage save ${tclPath(ucdbPath)}`);
  commands.push('quit -f');
  const doFile = path.join(built.buildDir, `sim-${shortHash}.do`);
  await fs.writeFile(doFile, commands.join('\n') + '\n', 'utf8');
  const cli = ['-c', '-modelsimini', posix(built.ini), '-onfinish', 'stop'];
  if (args.coverage) cli.push('-coverage');
  if (makeVcd) cli.push('-voptargs=+acc');
  if (args.uvm) cli.push('-L', 'mtiUvm');
  if (args.uvmTest) cli.push(`+UVM_TESTNAME=${args.uvmTest}`);
  cli.push(...vsimArgs, `${built.lib}.${args.top}`, '-do', posix(doFile), '-l', posix(transcript));
  const stage = await runVendor(ctx, config, 'vsim', cli, { cwd: built.workdir, timeoutSec });
  const log = await fileExists(transcript) ? await fs.readFile(transcript, 'utf8') : stage.output;
  const issues = parseIssues([log, stage.output].join('\n'), stage.code, stage.timedOut);
  const uvm = args.uvm ? uvmCounts(log) : undefined;
  if (uvm && (uvm.error || uvm.fatal)) { issues.ok = false; issues.errors.push(`UVM_ERROR=${uvm.error}, UVM_FATAL=${uvm.fatal}`); }
  const result = {
    ok: issues.ok, phase: 'simulate', cached: false, compileCached: built.cached, errors: issues.errors, warnings: issues.warnings,
    artifacts: { log: transcript, compileLog: built.log, ...(vcdPath && await fileExists(vcdPath) ? { vcd: vcdPath } : {}), ...(ucdbPath && await fileExists(ucdbPath) ? { coverageUcdb: ucdbPath } : {}) },
  };
  if (uvm) result.uvm = uvm;
  if (args.coverage) result.coverage = coverageSummary(log);
  if (wantsAssertions) {
    try { result.assert = await evaluateAssertions({ log, vcdPath: result.artifacts.vcd, assertions: args.assertions }); }
    catch (error) { result.assert = { ok: false, error: error.message }; }
    if (result.assert?.ok === false || (result.assert?.failed ?? 0) > 0) result.ok = false;
  }
  if (args.wave && result.artifacts.vcd) {
    try { result.wave = await renderWave({ vcdPath: result.artifacts.vcd, signals: args.waveSignals, maxSignals: 40, width: 1200, inlineSvg: false, open: !!args.waveOpen }); }
    catch (error) { result.wave = { ok: false, error: error.message }; }
    if (result.wave?.ok === false) result.ok = false;
    if (result.wave?.artifacts) Object.assign(result.artifacts, result.wave.artifacts);
  }
  if (makeVcd && !result.artifacts.vcd) { result.ok = false; result.errors.push('VCD 未生成'); }
  if (built.cacheable && result.ok && !args.waveOpen) await fs.writeFile(simCache, JSON.stringify(result, null, 2));
  if (args.detail === 'full') result.transcript = log;
  return result;
}

async function currentBuild(workdir) {
  const current = path.join(workdir, '._fpga_msim', 'current.json');
  if (!await fileExists(current)) return null;
  const data = JSON.parse(await fs.readFile(current, 'utf8'));
  return await fileExists(data.ini) ? data : null;
}

async function doTool(ctx, args) {
  const workdir = await existingDir(args.workdir, 'workdir');
  const config = licensedConfig(ctx);
  need((args.commands === undefined) !== (args.doScript === undefined), 'commands 与 doScript 必须二选一');
  const userScript = args.doScript === undefined ? array(args.commands, 'commands').join('\n') : String(args.doScript);
  need(userScript.trim(), 'do 脚本不能为空');
  if (!trivialDo(userScript) && args.confirm !== true) return { ok: false, phase: 'confirm', error: '自定义 Tcl 可能访问宿主；请检查脚本并传 confirm:true 后重试' };
  const vsimArgs = guardedVsimArgs(args.vsimArgs, args.confirm === true);
  const built = await currentBuild(workdir);
  const root = path.join(workdir, '._fpga_msim');
  await fs.mkdir(root, { recursive: true });
  const id = crypto.randomUUID().slice(0, 8);
  const doFile = path.join(root, `custom-${id}.do`);
  const logFile = path.join(root, `custom-${id}.log`);
  await fs.writeFile(doFile, `onerror {quit -f -code 1}\n${userScript}\nquit -f\n`, 'utf8');
  const cli = ['-c'];
  if (built) cli.push('-modelsimini', posix(built.ini));
  cli.push(...vsimArgs);
  if (args.top) {
    need(typeof args.top === 'string' && /^[A-Za-z_][\w$]*$/.test(args.top), 'top 必须是模块或实体名');
    cli.push(`${validLib(args.lib || built?.lib)}.${args.top}`);
  }
  cli.push('-do', posix(doFile), '-l', posix(logFile));
  const stage = await runVendor(ctx, config, 'vsim', cli, { cwd: workdir, timeoutSec: args.timeoutSec ?? 300 });
  const log = await fileExists(logFile) ? await fs.readFile(logFile, 'utf8') : stage.output;
  const issues = parseIssues([log, stage.output].join('\n'), stage.code, stage.timedOut);
  const result = { ok: issues.ok, errors: issues.errors, warnings: issues.warnings, artifacts: { log: logFile, doScript: doFile } };
  if (args.detail === 'full') result.transcript = log;
  return result;
}

async function exeTool(ctx, args) {
  const config = modelsimConfig(ctx);
  need(typeof args.exe === 'string' && /^[A-Za-z][A-Za-z0-9_]*(?:\.exe)?$/i.test(args.exe), 'exe 必须是 bin 下的可执行文件名');
  const exe = args.exe.replace(/\.exe$/i, '').toLowerCase();
  const argv = array(args.args, 'args');
  const probing = argv.length === 1 && /^-(?:help|h|version|v)$/i.test(argv[0]);
  need(EXE_ALLOWED.has(exe) || probing, `${exe} 不在 ModelSim 工具白名单内；其他 exe 只允许 -help/-version 探测`);
  const cwd = args.cwd ? await existingDir(args.cwd, 'cwd') : config.home;
  const stage = await runVendor(ctx, config, exe, argv, { cwd, timeoutSec: args.timeoutSec ?? TOOL_TIMEOUT });
  const result = { ok: stage.ok, exe, exitCode: stage.code, errors: stage.errors, warnings: stage.warnings, output: args.detail === 'full' ? stage.output : stage.output.split(/\r?\n/).filter(Boolean).slice(-40).join('\n') };
  return result;
}

async function viewTool(ctx, args) {
  need(Boolean(args.vcdPath) !== Boolean(args.wlfPath), 'vcdPath 与 wlfPath 必须二选一');
  const config = licensedConfig(ctx);
  need(path.isAbsolute(args.vcdPath || args.wlfPath), 'vcdPath/wlfPath 必须是绝对路径');
  const source = path.resolve(args.vcdPath || args.wlfPath);
  need(await fileExists(source), `波形文件不存在: ${source}`);
  const viewDir = path.join(os.tmpdir(), 'pango-mcp-view');
  await fs.mkdir(viewDir, { recursive: true });
  const id = crypto.randomUUID().slice(0, 8);
  let wlf = source;
  let conversion;
  if (args.vcdPath) {
    wlf = path.join(viewDir, `view-${id}.wlf`);
    conversion = await runVendor(ctx, config, 'vcd2wlf', [source, wlf], { cwd: viewDir, timeoutSec: args.timeoutSec ?? TOOL_TIMEOUT });
    if (!conversion.ok || !await fileExists(wlf)) return { ok: false, phase: 'convert', errors: conversion.errors, output: conversion.output.slice(-2000) };
  }
  const radix = args.radix || 'hex';
  need(['hex', 'binary', 'unsigned', 'signed', 'decimal', 'ascii'].includes(radix), 'radix 无效');
  const commands = ['onerror {resume}'];
  if (args.groups !== undefined) {
    need(Array.isArray(args.groups), 'groups 必须是数组');
    for (const group of args.groups) {
      need(group && typeof group.name === 'string' && Array.isArray(group.signals), 'groups 元素需含 name 和 signals[]');
      for (const signal of group.signals) commands.push(`add wave -radix ${radix} -group ${tclWord(group.name)} ${tclWord(signal)}`);
    }
  } else if (args.signals !== undefined) {
    for (const signal of array(args.signals, 'signals')) commands.push(`add wave -radix ${radix} ${tclWord(signal)}`);
  } else commands.push(`add wave -radix ${radix} -r /*`);
  const doFile = path.join(viewDir, `view-${id}.do`);
  await fs.writeFile(doFile, commands.join('\n') + '\n', 'utf8');
  const command = [path.join(config.home, 'vsim.exe'), '-view', wlf, '-do', doFile];
  if (args.launch === false) return { ok: true, launched: false, command, artifacts: { wlf, doScript: doFile } };
  need(await fileExists(command[0]), `ModelSim GUI 不存在: ${command[0]}`);
  const child = spawn(command[0], command.slice(1), { cwd: path.dirname(source), env: config.env, detached: true, stdio: 'ignore', windowsHide: false, shell: false });
  await new Promise((resolve, reject) => { child.once('spawn', resolve); child.once('error', reject); });
  child.unref();
  return { ok: true, launched: true, pid: child.pid, artifacts: { wlf, doScript: doFile } };
}

function readTclWord(text, start) {
  let i = start;
  if (text[i] === '{') {
    let depth = 1; i++;
    const from = i;
    for (; i < text.length; i++) {
      if (text[i] === '\\') { i++; continue; }
      if (text[i] === '{') depth++;
      if (text[i] === '}' && --depth === 0) return [text.slice(from, i), i + 1];
    }
    return [text.slice(from), text.length];
  }
  const from = i;
  while (i < text.length && !/\s/.test(text[i])) i++;
  return [text.slice(from, i), i];
}

function parseHelp(text) {
  const records = [];
  let i = 0;
  while (i < text.length) {
    while (i < text.length && /\s/.test(text[i])) i++;
    if (i >= text.length) break;
    if (text[i] === '#') { while (i < text.length && text[i] !== '\n') i++; continue; }
    const words = [];
    for (let n = 0; n < 3 && i < text.length; n++) {
      while (i < text.length && /\s/.test(text[i])) i++;
      if (i >= text.length) break;
      const [word, next] = readTclWord(text, i);
      words.push(word); i = next;
    }
    if (words.length === 3) records.push({ command: words[0], description: words[1], arguments: words[2] });
  }
  return records;
}

let helpPromise;
async function loadHelp(config) {
  const root = path.resolve(config.home, '..', 'docs');
  const helpDir = path.join(root, 'cmd_help');
  const pdfDir = path.join(root, 'pdfdocs');
  const helpFiles = (await fs.readdir(helpDir).catch(() => [])).filter(x => x.endsWith('.txt'));
  const commands = new Map();
  for (const name of helpFiles) {
    for (const record of parseHelp(await fs.readFile(path.join(helpDir, name), 'utf8'))) {
      commands.set(record.command.toLowerCase(), { ...record, source: path.join(helpDir, name) });
    }
  }
  const manuals = [];
  for (const name of (await fs.readdir(pdfDir).catch(() => [])).filter(x => x.toLowerCase().endsWith('.pdf'))) {
    const full = path.join(pdfDir, name);
    const size = (await fs.stat(full)).size;
    manuals.push({ name, path: full, bytes: size, available: size > 1000 });
  }
  return { commands, manuals };
}

async function docTool(ctx, args) {
  const config = modelsimConfig(ctx);
  helpPromise ||= loadHelp(config);
  const { commands, manuals } = await helpPromise;
  const kind = args.kind || 'all';
  need(['all', 'command', 'manual'].includes(kind), 'kind 只能是 all、command、manual');
  const limit = Math.min(Math.max(1, Number(args.limit) || 10), 100);
  if (args.command) {
    const entry = commands.get(String(args.command).toLowerCase());
    return { ok: !!entry, command: entry || null, error: entry ? undefined : `未找到命令: ${args.command}` };
  }
  if (!args.query) return { ok: true, commandCount: commands.size, manuals };
  const words = String(args.query).toLowerCase().split(/\s+/).filter(Boolean);
  const score = text => words.reduce((n, word) => n + (String(text).toLowerCase().includes(word) ? 1 : 0), 0);
  const foundCommands = kind === 'manual' ? [] : [...commands.values()].map(item => ({ ...item, score: score(`${item.command} ${item.description} ${item.arguments}`) })).filter(item => item.score).sort((a, b) => b.score - a.score).slice(0, limit);
  const foundManuals = kind === 'command' ? [] : manuals.map(item => ({ ...item, score: score(item.name) })).filter(item => item.score).sort((a, b) => b.score - a.score).slice(0, limit);
  return { ok: true, commands: foundCommands, manuals: foundManuals };
}

export function modelsimTools(ctx) {
  return [
    tool('fpga_msim_compile', '仅编译 Verilog/SystemVerilog/VHDL，解析 ModelSim 错误并保存日志。', {
      workdir: str, sources: strings, fileList: str, libDirs: strings, lib: str, vlogArgs: strings, vcomArgs: strings,
      cache: bool, detail, timeoutSec: seconds, host: str,
    }, ['workdir'], args => {
      need(!args.host, '远程 ModelSim host 尚未配置');
      return compileTool(ctx, args);
    }),
    tool('fpga_msim_sim', '编译并运行 ModelSim 无界面仿真；以 transcript 错误和 UVM 计数判定结果，可输出 VCD、覆盖率和断言。', {
      workdir: str, top: str, sources: strings, fileList: str, libDirs: strings, lib: str, vlogArgs: strings, vcomArgs: strings, vsimArgs: strings,
      runArg: str, doBeforeRun: str, vcd: bool, vcdPath: str, wave: bool, waveOpen: bool, waveSignals: strings,
      coverage: bool, uvm: bool, uvmTest: str, assertions: { type: 'array', items: { anyOf: [{ type: 'object' }, str] } },
      cache: bool, detail, timeoutSec: seconds, host: str,
    }, ['workdir', 'top'], args => {
      need(!args.host, '远程 ModelSim host 尚未配置');
      return simTool(ctx, args);
    }),
    tool('fpga_msim_do', '在 vsim -c 中运行自定义 do/Tcl 命令，自动追加 quit -f；涉及宿主命令时需要 confirm:true。', {
      workdir: str, top: str, lib: str, commands: strings, doScript: str, vsimArgs: strings, confirm: bool, detail, timeoutSec: seconds, host: str,
    }, ['workdir'], args => {
      need(!args.host, '远程 ModelSim host 尚未配置');
      return doTool(ctx, args);
    }),
    tool('fpga_msim_exe', '运行 ModelSim 库、覆盖率、波形等 bin 工具；其他可执行文件仅允许 -help/-version 探测。', {
      exe: str, args: strings, cwd: str, detail, timeoutSec: seconds, host: str,
    }, ['exe'], args => {
      need(!args.host, '远程 ModelSim host 尚未配置');
      return exeTool(ctx, args);
    }),
    tool('fpga_msim_view', '把 VCD 转为 WLF，并在本机 ModelSim GUI 中交互查看波形；launch:false 只准备命令。', {
      vcdPath: str, wlfPath: str, signals: strings,
      groups: { type: 'array', items: { type: 'object', properties: { name: str, signals: strings }, required: ['name', 'signals'] } },
      radix: { type: 'string', enum: ['hex', 'binary', 'unsigned', 'signed', 'decimal', 'ascii'] }, launch: bool, timeoutSec: seconds,
    }, [], args => viewTool(ctx, args)),
    tool('fpga_msim_doc_search', '检索本机 ModelSim 命令帮助和 PDF 手册路径。', {
      command: str, query: str, kind: { type: 'string', enum: ['all', 'command', 'manual'] }, limit: { type: 'integer', minimum: 1, maximum: 100 },
    }, [], args => docTool(ctx, args)),
  ];
}
