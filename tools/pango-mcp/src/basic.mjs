import fs from 'node:fs';
import path from 'node:path';
import { absolutePath, findExecutable, requiredString, compactProcessResult } from './runtime.mjs';
import { findSignal, parseVcd, renderWave } from './vcd.mjs';

const schema = (properties = {}, required = []) => ({ type: 'object', properties, required });
const str = description => ({ type: 'string', description });
const bool = description => ({ type: 'boolean', description });
const list = (description, items = { type: 'string' }) => ({ type: 'array', items, description });

function normalizeAssertion(entry) {
  if (typeof entry === 'string') {
    const match = entry.match(/^([a-z_]+)\s*:\s*(.+)$/);
    if (!match) throw new Error('Assertion string must be type: value');
    return { type: match[1], value: match[2] };
  }
  if (!entry || typeof entry !== 'object' || Array.isArray(entry)) throw new Error('Invalid assertion');
  if (entry.type) return entry;
  const keys = Object.keys(entry);
  if (keys.length === 1) return { type: keys[0], value: entry[keys[0]] };
  throw new Error('Assertion needs a type');
}

function expressionParts(assertion) {
  const value = assertion.value ?? assertion.expression;
  if (assertion.signal && Object.hasOwn(assertion, 'expected')) {
    return { signal: assertion.signal, expected: assertion.expected, time: assertion.time };
  }
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return { signal: value.signal, expected: value.value ?? value.expected, time: value.time };
  }
  const match = String(value ?? '').match(/^\s*(.+?)\s*==\s*(.+?)\s*$/);
  if (!match) throw new Error('VCD assertion must be signal == value');
  return { signal: match[1], expected: match[2], time: assertion.time };
}

function numericValue(value, actual = false) {
  const v = String(value).trim().replaceAll('_', '');
  if (/[xz]/i.test(v) && !/^0x/i.test(v)) return v.toLowerCase();
  const verilog = v.match(/^\d+'([bdho])([0-9a-f]+)$/i);
  if (verilog) {
    const radix = { b: 2, d: 10, h: 16, o: 8 }[verilog[1].toLowerCase()];
    return BigInt(parseInt(verilog[2], radix));
  }
  if (/^0x[0-9a-f]+$/i.test(v)) return BigInt(v);
  if (actual && /^[01]+$/.test(v)) return BigInt('0b' + v);
  if (/^-?\d+$/.test(v)) return BigInt(v);
  return v.toLowerCase();
}

function equalValue(actual, expected) {
  return numericValue(actual, true) === numericValue(expected, false);
}

export function evaluateAssertions({ log = '', vcdPath, assertions }) {
  if (!Array.isArray(assertions) || !assertions.length) {
    throw new Error('assertions must be a nonempty array');
  }
  let vcd;
  const results = assertions.map(raw => {
    const assertion = normalizeAssertion(raw);
    const type = assertion.type;
    const value = assertion.value ?? assertion.pattern;
    let passed;
    let actual;
    if (type.startsWith('log_')) {
      const haystack = String(log);
      const needle = String(value ?? '');
      if (!needle) throw new Error(type + ' needs a value');
      if (type === 'log_contains') passed = haystack.includes(needle);
      else if (type === 'log_not_contains') passed = !haystack.includes(needle);
      else if (type === 'log_regex') passed = new RegExp(needle).test(haystack);
      else if (type === 'log_not_regex') passed = !new RegExp(needle).test(haystack);
      else throw new Error('Unsupported assertion type: ' + type);
      actual = passed ? 'matched' : 'not matched';
    } else if (type.startsWith('vcd_')) {
      if (!vcdPath) throw new Error(type + ' requires vcdPath');
      vcd ??= parseVcd(vcdPath);
      const expr = expressionParts(assertion);
      const signal = findSignal(vcd, expr.signal);
      const events = signal.events;
      if (type === 'vcd_final_eq') {
        actual = events.at(-1)?.value;
        passed = actual !== undefined && equalValue(actual, expr.expected);
      } else if (type === 'vcd_at_eq') {
        const time = Number(expr.time);
        if (!Number.isFinite(time)) throw new Error('vcd_at_eq needs a numeric time');
        actual = events.filter(event => event.time <= time).at(-1)?.value;
        passed = actual !== undefined && equalValue(actual, expr.expected);
      } else if (type === 'vcd_never_eq') {
        const match = events.find(event => equalValue(event.value, expr.expected));
        actual = match ? { time: match.time, value: match.value } : 'never matched';
        passed = !match;
      } else {
        throw new Error('Unsupported assertion type: ' + type);
      }
    } else {
      throw new Error('Unsupported assertion type: ' + type);
    }
    return { type, passed, actual, assertion: raw };
  });
  const passed = results.filter(result => result.passed).length;
  const failed = results.length - passed;
  return { ok: failed === 0, passed, failed, results };
}

function extractLog(args) {
  if (args.log !== undefined && args.logPath !== undefined) throw new Error('Use log or logPath, not both');
  if (args.logPath) {
    const file = absolutePath(args.logPath, 'logPath', { kind: 'file' });
    if (fs.statSync(file).size > 16 * 1024 * 1024) throw new Error('Log exceeds 16 MiB');
    return fs.readFileSync(file, 'utf8');
  }
  return requiredString(args.log, 'log');
}

function summarizeLog(log, profile) {
  const lines = log.split(/\r?\n/);
  const findings = [];
  const patterns = profile === 'cdt'
    ? [/idcode/i, /done\s*bit/i, /verify/i, /error/i, /fail/i]
    : profile === 'sim'
      ? [/\*\*\s*(error|fatal)/i, /errors:\s*[1-9]/i, /\$fatal/i, /uvm_(error|fatal)/i, /\b(pass|fail)\b/i]
      : [/\bE:\b/i, /error/i, /critical/i, /timing/i, /slack/i, /lut/i, /ff\b/i, /bram/i, /bit.?stream/i, /route/i];
  for (let i = 0; i < lines.length; i++) {
    if (patterns.some(pattern => pattern.test(lines[i]))) {
      findings.push({ line: i + 1, text: lines[i].slice(0, 500) });
      if (findings.length >= 120) break;
    }
  }
  const failures = findings.filter(item => /\b(error|fatal|fail)\b|\bE:/i.test(item.text));
  return { ok: failures.length === 0, profile, lineCount: lines.length, findings, failures: failures.slice(0, 40) };
}

function toolchainInfo(config) {
  const pdsShell = config.pdsShell;
  const modelsimHome = config.modelsimHome;
  const modelsimVsim = modelsimHome ? path.join(modelsimHome, 'vsim.exe') : '';
  return {
    pds: {
      shell: pdsShell || null,
      available: !!pdsShell && fs.existsSync(pdsShell),
      license: config.pdsLicense || null,
      licenseAvailable: !!config.pdsLicense && fs.existsSync(config.pdsLicense),
    },
    modelsim: {
      home: modelsimHome || null,
      vsim: modelsimVsim || null,
      available: !!modelsimVsim && fs.existsSync(modelsimVsim),
      license: config.modelsimLicense || null,
      licenseAvailable: !!config.modelsimLicense && fs.existsSync(config.modelsimLicense),
    },
    iverilog: findExecutable('iverilog'),
    vvp: findExecutable('vvp'),
    verilator: findExecutable('verilator'),
    gcc: findExecutable('gcc'),
    node: process.execPath,
    platform: process.platform,
    boards: Object.keys(config.boards || {}),
    configuration: { envFile: config.envFile || null, configFile: config.configFile || null },
  };
}

async function runIcarus(ctx, args) {
  const workdir = absolutePath(args.workdir, 'workdir', { kind: 'directory' });
  const top = requiredString(args.top, 'top');
  if (!/^[A-Za-z_][A-Za-z0-9_$]*$/.test(top)) throw new Error('top is not a Verilog identifier');
  const iverilog = findExecutable('iverilog');
  const vvp = findExecutable('vvp');
  if (!iverilog || !vvp) {
    return { ok: false, error: 'Icarus Verilog (iverilog and vvp) is not installed on PATH; use fpga_msim_sim for this machine' };
  }
  const sources = Array.isArray(args.sources) && args.sources.length
    ? args.sources.map(file => path.resolve(workdir, file))
    : fs.readdirSync(workdir).filter(file => /\.(v|sv)$/i.test(file) && !/^[._]/.test(file))
      .map(file => path.join(workdir, file));
  if (!sources.length && !args.fileList) throw new Error('No Verilog sources found');
  for (const file of sources) absolutePath(file, 'source', { kind: 'file' });
  const outDir = path.join(workdir, '._fpga_sim');
  fs.mkdirSync(outDir, { recursive: true });
  const output = path.join(outDir, 'sim.vvp');
  const needsVcd = !!(args.wave || args.vcd || args.assertions?.some(a => JSON.stringify(a).includes('vcd_')));
  const vcdPath = args.vcdPath ? path.resolve(workdir, args.vcdPath) : path.join(outDir, 'sim.vcd');
  let simulationTop = top;
  if (needsVcd) {
    const wrapper = path.join(outDir, 'wave_wrapper.v');
    const vcdLiteral = JSON.stringify(vcdPath.replaceAll('\\', '/'));
    fs.writeFileSync(wrapper, 'module __pango_wave_wrapper;\n' + top +
      ' dut();\ninitial begin $dumpfile(' + vcdLiteral + '); $dumpvars(0,dut); end\nendmodule\n');
    sources.push(wrapper);
    simulationTop = '__pango_wave_wrapper';
  }
  const compileArgs = ['-g2012', '-s', simulationTop, '-o', output];
  if (args.fileList) compileArgs.push('-f', path.resolve(workdir, args.fileList));
  if (Array.isArray(args.iverilogArgs)) compileArgs.push(...args.iverilogArgs.map(String));
  compileArgs.push(...sources);
  const compile = await ctx.runProcess(iverilog, compileArgs, { cwd: workdir, timeoutSec: args.timeoutSec ?? 120 });
  const compileLog = [compile.stdout, compile.stderr].filter(Boolean).join('\n');
  if (compile.code !== 0 || compile.timedOut || /(^|\n).*\b(error|fatal):/im.test(compileLog)) {
    return { ok: false, phase: 'compile', ...compactProcessResult(compile, args.detail) };
  }
  const run = await ctx.runProcess(vvp, [output, ...(Array.isArray(args.runArgs) ? args.runArgs.map(String) : [])], {
    cwd: workdir, timeoutSec: args.timeoutSec ?? 120,
  });
  const log = [compileLog, run.stdout, run.stderr].filter(Boolean).join('\n');
  let ok = run.code === 0 && !run.timedOut && !/(^|\n).*\b(error|fatal):|\$fatal/i.test(log);
  const result = {
    ok, phase: 'simulate', exitCode: run.code, timedOut: run.timedOut,
    log: args.detail === 'full' ? log : log.slice(-16000),
    artifacts: { executable: output, ...(needsVcd && fs.existsSync(vcdPath) ? { vcd: vcdPath } : {}) },
  };
  if (args.assertions?.length) {
    result.assert = evaluateAssertions({ log, vcdPath: fs.existsSync(vcdPath) ? vcdPath : undefined, assertions: args.assertions });
    ok = ok && result.assert.ok;
    result.ok = ok;
  }
  if (args.wave && fs.existsSync(vcdPath)) {
    const rendered = renderWave({ vcdPath, signals: args.waveSignals, inlineSvg: false });
    result.artifacts = { ...result.artifacts, ...rendered.artifacts };
  }
  return result;
}

export function basicTools(ctx) {
  return [
    {
      name: 'fpga_env',
      description: 'Report available FPGA toolchains and configured PDS/ModelSim paths on this machine.',
      inputSchema: schema(),
      annotations: { readOnlyHint: true },
      run: async () => ({ ok: true, ...toolchainInfo(ctx.config) }),
    },
    {
      name: 'fpga_capabilities',
      description: 'List the implemented tool catalog and the server version of this local rebuild.',
      inputSchema: schema(),
      annotations: { readOnlyHint: true },
      run: async () => ({ ok: true, serverVersion: '0.1.0-local', tools: ctx.toolNames || [] }),
    },
    {
      name: 'fpga_assert',
      description: 'Evaluate declarative log and VCD assertions; returns a per-assertion pass/fail verdict.',
      inputSchema: schema({
        log: str('Simulation transcript text'),
        vcdPath: str('Absolute VCD path'),
        assertions: list('Assertions: type/value objects or type: value strings', { type: ['object', 'string'] }),
        knowledge: { type: 'object', description: 'Reserved for original knowledge vault integration' },
      }, ['assertions']),
      annotations: { readOnlyHint: true },
      run: async args => {
        const result = evaluateAssertions(args);
        if (args.knowledge) result.knowledge = { written: false, reason: 'Knowledge vault not part of this rebuild' };
        return result;
      },
    },
    {
      name: 'fpga_wave',
      description: 'Render a VCD into SVG and HTML timing diagrams, optionally opening the HTML viewer.',
      inputSchema: schema({
        vcdPath: str('Absolute VCD path'),
        signals: list('Signals to draw by full name or unique short name'),
        maxSignals: { type: 'integer', description: 'Default 40' },
        width: { type: 'integer', description: 'SVG width in pixels; default 1100' },
        inlineSvg: bool('Return SVG text in the result; default true'),
        open: bool('Open the generated HTML in the default browser'),
      }, ['vcdPath']),
      run: async args => renderWave(args),
    },
    {
      name: 'fpga_log_extract',
      description: 'Extract errors, timing, resource and status lines from PDS, CDT or simulation logs.',
      inputSchema: schema({
        log: str('Log text; exclusive with logPath'),
        logPath: str('Absolute log file path; exclusive with log'),
        profile: { type: 'string', enum: ['pds', 'cdt', 'sim'], description: 'Default pds' },
      }),
      annotations: { readOnlyHint: true },
      run: async args => summarizeLog(extractLog(args), args.profile || 'pds'),
    },
    {
      name: 'fpga_sim',
      description: 'Compile and run Verilog/SystemVerilog with Icarus Verilog and optional VCD, assertions, and waveform.',
      inputSchema: schema({
        workdir: str('Absolute working directory'),
        top: str('Top testbench module'),
        sources: list('Verilog/SystemVerilog files relative to workdir or absolute'),
        fileList: str('Optional Icarus file list'),
        iverilogArgs: list('Additional iverilog arguments'),
        runArgs: list('Additional vvp arguments'),
        vcd: bool('Generate VCD'),
        vcdPath: str('VCD output path'),
        wave: bool('Render VCD timing diagram'),
        waveSignals: list('Signals to draw'),
        assertions: list('Log/VCD assertions', { type: ['object', 'string'] }),
        timeoutSec: { type: 'number' },
        detail: { type: 'string', enum: ['summary', 'full'] },
      }, ['workdir', 'top']),
      run: async args => runIcarus(ctx, args),
    },
  ];
}
