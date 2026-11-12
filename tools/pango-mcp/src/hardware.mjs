import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { compactProcessResult } from './runtime.mjs';

const SAFE_PDS_EXES = new Set([
  'ip_generate', 'ip_compiler', 'ip_tar', 'cdt_bts', 'ppc', 'ppp',
  'rf_analyzer', 'evp', 'pne', 'state', 'de', 'pce', 'ta',
]);

function pdsBin(config) {
  const bin = config?.pdsBin || (config?.pdsShell ? path.dirname(config.pdsShell) : '');
  if (!bin || !path.isAbsolute(bin)) throw new Error('PDS is not configured: set PANGO_MCP_PDS_2025 to pds_shell.exe');
  if (!fs.existsSync(bin) || !fs.statSync(bin).isDirectory()) throw new Error(`PDS bin directory is unavailable: ${bin}`);
  return bin;
}

function localOnly(args, config) {
  if (args.host) throw new Error('Remote hosts are not configured in this local rebuild');
  if (args.pdsVersion) {
    const installed = path.basename(path.resolve(pdsBin(config), '..')).toLowerCase();
    if (!installed.includes(String(args.pdsVersion).toLowerCase())) {
      throw new Error(`pdsVersion ${args.pdsVersion} does not match the configured PDS install (${installed})`);
    }
  }
}

function inputFile(value, name) {
  if (typeof value !== 'string' || !path.isAbsolute(value)) throw new Error(`${name} must be an absolute file path`);
  const file = path.resolve(value);
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) throw new Error(`${name} does not exist: ${file}`);
  return file;
}

function inputFiles(value, name, minimum = 1) {
  if (!Array.isArray(value) || value.length < minimum || value.length > 32) {
    throw new Error(`${name} must be an array of ${minimum} to 32 absolute file paths`);
  }
  return value.map((file, i) => inputFile(file, `${name}[${i}]`));
}

function outputFile(value, fallback, inputs, overwrite = false) {
  const supplied = value ?? fallback;
  if (typeof supplied !== 'string' || !path.isAbsolute(supplied)) throw new Error('Output must be an absolute file path');
  const out = path.resolve(supplied);
  const parent = path.dirname(out);
  if (!fs.existsSync(parent) || !fs.statSync(parent).isDirectory()) throw new Error(`Output directory does not exist: ${parent}`);
  if (inputs.some(file => file.toLowerCase() === out.toLowerCase())) throw new Error('Output must not overwrite an input file');
  if (fs.existsSync(out) && !overwrite) throw new Error(`Output already exists: ${out}. Set overwrite:true to replace it.`);
  return out;
}

function tclWord(value) {
  // Tcl's double-quoted word permits spaces after escaping substitutions.
  return `"${String(value).replace(/\\/g, '/').replace(/"/g, '\\"')
    .replace(/\$/g, '\\$').replace(/\[/g, '\\[').replace(/\]/g, '\\]')
    .replace(/\r/g, '\\r').replace(/\n/g, '\\n')}"`;
}

function tclList(values) {
  return `[list ${values.map(tclWord).join(' ')}]`;
}

function hexAddress(value, name) {
  if (typeof value !== 'string' || !/^(?:0x)?[0-9a-f]+$/i.test(value)) {
    throw new Error(`${name} must be a hexadecimal address string`);
  }
  return value;
}

function timeout(value, fallback = 120) {
  if (value === undefined || value === null) return fallback;
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) throw new Error('timeoutSec must be positive');
  return Math.min(n, 3600);
}

function detectErrors(text) {
  return text.split(/\r?\n/).filter(line => /^\s*(?:E:|\*\*\s+(?:Error|Fatal)|Error:)/i.test(line)).slice(0, 30);
}

async function runOffline(ctx, command, expectedOutput, options = {}) {
  const bin = pdsBin(ctx.config);
  const executable = path.join(bin, 'cdt_cfg_shell.exe');
  if (!fs.existsSync(executable)) throw new Error(`cdt_cfg_shell.exe is unavailable: ${executable}`);
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'pango-mcp-offline-'));
  const script = path.join(temporary, 'command.tcl');
  // catch is necessary because cdt_cfg_shell may exit 0 after a Tcl error.
  fs.writeFileSync(script, `set pango_mcp_command [list ${command}]\nset pango_mcp_code [catch {uplevel #0 $pango_mcp_command} pango_mcp_result]\nputs "PANGO_MCP_CODE=$pango_mcp_code"\nputs "PANGO_MCP_RESULT=$pango_mcp_result"\n`, 'utf8');
  let processResult;
  try {
    processResult = await ctx.runProcess(executable, ['-file', script], {
      cwd: temporary,
      timeoutSec: timeout(options.timeoutSec),
      env: ctx.config.pdsLicense ? { PANGO_LICENSE_FILE: ctx.config.pdsLicense } : {},
    });
  } finally {
    try { fs.unlinkSync(script); } catch { /* script may not have been created */ }
    try { fs.rmdirSync(temporary); } catch { /* keep unexpected vendor output for inspection */ }
  }
  const output = `${processResult.stdout || ''}\n${processResult.stderr || ''}`;
  const errors = detectErrors(output);
  const tclCode = output.match(/PANGO_MCP_CODE=(\d+)/)?.[1];
  const outputExists = !!expectedOutput && fs.existsSync(expectedOutput) && fs.statSync(expectedOutput).isFile();
  const summary = compactProcessResult(processResult, options.detail === 'full' ? 'full' : 'summary');
  return {
    ok: processResult.code === 0 && !processResult.timedOut && tclCode === '0' && errors.length === 0 && outputExists,
    outputPath: expectedOutput,
    outputExists,
    errors,
    ...summary,
    ...(!outputExists && errors.length === 0 ? { diagnostic: 'The converter did not create the expected output file' } : {}),
  };
}

function unsupportedCurrentOptions(args, names) {
  for (const name of names) {
    if (args[name] !== undefined && args[name] !== false && args[name] !== null) {
      throw new Error(`${name} is not supported by the configured PDS 2023.2 cfg_gen command`);
    }
  }
}

const localFields = {
  pdsVersion: { type: 'string', description: 'Must match the configured PDS installation.' },
  timeoutSec: { type: 'number', minimum: 1, maximum: 3600 },
  overwrite: { type: 'boolean', description: 'Allow replacing an existing output file; never permits replacing an input.' },
  detail: { type: 'string', enum: ['summary', 'full'] },
};

export function hardwareTools(ctx) {
  return [
    {
      name: 'fpga_gen_sfc',
      description: 'Offline conversion of an installed-PDS .sbit file to an .sfc flash image via cfg_gen_sfc. Does not connect to a board.',
      inputSchema: { type: 'object', required: ['sbit'], properties: {
        sbit: { type: 'string' }, sfc: { type: 'string' }, deviceName: { type: 'string' },
        opcode: { oneOf: [{ type: 'integer' }, { type: 'string' }] },
        sbitStartAddress: { type: 'string' }, isX8: { type: 'boolean' }, fastMode: { type: 'boolean' },
        fileList: { type: 'array', items: { type: 'string' } },
        userAddressList: { type: 'array', items: { type: 'string' } },
        writeChecksum: { type: 'boolean', description: 'Unsupported by the configured 2023.2 converter.' },
        extraByte: { type: 'boolean', description: 'Unsupported by the configured 2023.2 converter.' },
        ...localFields,
      } },
      async run(args) {
        localOnly(args, ctx.config);
        unsupportedCurrentOptions(args, ['writeChecksum', 'extraByte']);
        const sbit = inputFile(args.sbit, 'sbit');
        const dataFiles = args.fileList ? inputFiles(args.fileList, 'fileList') : [];
        const addresses = args.userAddressList || [];
        if (!Array.isArray(addresses) || addresses.length !== dataFiles.length) {
          throw new Error('userAddressList must have one hexadecimal address per fileList entry');
        }
        const sfc = outputFile(args.sfc, sbit.replace(/\.sbit$/i, '') + '.sfc', [sbit, ...dataFiles], args.overwrite);
        const words = ['cfg_gen_sfc', '-sbit', tclWord(sbit), '-sfc', tclWord(sfc)];
        if (args.sbitStartAddress !== undefined) words.push('-sbit_start_address', tclWord(hexAddress(args.sbitStartAddress, 'sbitStartAddress')));
        if (args.opcode !== undefined) {
          const opcode = Number(args.opcode);
          if (![11, 59, 107, 12, 60, 108].includes(opcode)) throw new Error('opcode must be 0x0B, 0x3B, 0x6B, 0x0C, 0x3C, or 0x6C');
          words.push('-opcode', String(opcode));
        }
        if (args.deviceName) words.push('-device_name', tclWord(args.deviceName));
        if (args.fastMode !== undefined) words.push('-fast_mode', args.fastMode ? 'TRUE' : 'FALSE');
        if (args.isX8 !== undefined) words.push('-is_x8', args.isX8 ? 'TRUE' : 'FALSE');
        if (dataFiles.length) words.push('-file_list', tclList(dataFiles), '-user_address_list', tclList(addresses.map((a, i) => hexAddress(a, `userAddressList[${i}]`))));
        return runOffline(ctx, words.join(' '), sfc, args);
      },
    },
    {
      name: 'fpga_gen_multi_file',
      description: 'Offline combination of two or more .sbit files into a PDS multiboot or upgrade stream via cfg_gen_multi_file. Does not connect to a board.',
      inputSchema: { type: 'object', required: ['type', 'infile'], properties: {
        type: { type: 'integer', minimum: 0, maximum: 5 }, infile: { type: 'array', minItems: 2, maxItems: 32, items: { type: 'string' } },
        outfile: { type: 'string' }, sbitStartAddress: { type: 'array', items: { type: 'string' } },
        goldenOutFile: { type: 'string', description: 'Unsupported by the configured 2023.2 converter.' },
        appliedOutFile: { type: 'string', description: 'Unsupported by the configured 2023.2 converter.' },
        ...localFields,
      } },
      async run(args) {
        localOnly(args, ctx.config);
        unsupportedCurrentOptions(args, ['goldenOutFile', 'appliedOutFile']);
        const files = inputFiles(args.infile, 'infile', 2);
        const type = Number(args.type);
        if (!Number.isInteger(type) || type < 0 || type > 5) throw new Error('type must be an integer from 0 to 5');
        const fallback = files[0].replace(/\.sbit$/i, '') + '.multi.sbit';
        const out = outputFile(args.outfile, fallback, files, args.overwrite);
        const words = ['cfg_gen_multi_file', '-infile', tclList(files), '-outfile', tclWord(out), '-type', String(type)];
        if (args.sbitStartAddress !== undefined) {
          if (!Array.isArray(args.sbitStartAddress) || args.sbitStartAddress.length !== files.length) {
            throw new Error('sbitStartAddress must have one hexadecimal address per infile');
          }
          words.push('-sbit_start_address', tclList(args.sbitStartAddress.map((a, i) => hexAddress(a, `sbitStartAddress[${i}]`))));
        }
        return runOffline(ctx, words.join(' '), out, args);
      },
    },
    {
      name: 'fpga_gen_chain_file',
      description: 'Offline combination of two or more .sbit files into a PDS SPI chain file via cfg_gen_chain_file. Does not connect to a board.',
      inputSchema: { type: 'object', required: ['infile'], properties: {
        infile: { type: 'array', minItems: 2, maxItems: 32, items: { type: 'string' } },
        outfile: { type: 'string' }, createBinFile: { type: 'boolean' },
        reverseBitInAByte: { type: 'boolean' }, reverseByteInAWord: { type: 'boolean' },
        ...localFields,
      } },
      async run(args) {
        localOnly(args, ctx.config);
        const files = inputFiles(args.infile, 'infile', 2);
        const fallback = files[0].replace(/\.sbit$/i, '') + '.chain.sbit';
        const out = outputFile(args.outfile, fallback, files, args.overwrite);
        const words = ['cfg_gen_chain_file', '-infile', tclList(files), '-outfile', tclWord(out)];
        if (args.createBinFile) words.push('-create_bin_file');
        if (args.reverseBitInAByte) words.push('-reverse_bit_in_a_byte');
        if (args.reverseByteInAWord) words.push('-reverse_byte_in_a_word');
        return runOffline(ctx, words.join(' '), out, args);
      },
    },
    {
      name: 'fpga_exe',
      description: 'Run an installed PDS build or analysis executable from an allowlist. Pass args such as -help or -version to inspect usage. Device/JTAG and GUI executables are excluded.',
      inputSchema: { type: 'object', required: ['exe'], properties: {
        exe: { type: 'string' }, args: { type: 'array', items: { type: 'string' } },
        cwd: { type: 'string' }, host: { type: 'string' },
        pdsVersion: localFields.pdsVersion, timeoutSec: localFields.timeoutSec, detail: localFields.detail,
      } },
      async run(args) {
        localOnly(args, ctx.config);
        const name = String(args.exe || '').toLowerCase().replace(/\.exe$/, '');
        if (!SAFE_PDS_EXES.has(name)) throw new Error(`Executable is outside the build/analysis allowlist: ${args.exe}`);
        const executable = path.join(pdsBin(ctx.config), `${name}.exe`);
        if (!fs.existsSync(executable)) throw new Error(`Executable is unavailable in this PDS installation: ${executable}`);
        const argv = args.args ?? [];
        if (!Array.isArray(argv) || argv.some(item => typeof item !== 'string')) throw new Error('args must be an array of strings');
        let cwd = ctx.config.stateDir || os.tmpdir();
        if (args.cwd !== undefined) {
          if (typeof args.cwd !== 'string' || !path.isAbsolute(args.cwd) || !fs.existsSync(args.cwd) || !fs.statSync(args.cwd).isDirectory()) {
            throw new Error('cwd must be an existing absolute directory');
          }
          cwd = path.resolve(args.cwd);
        } else fs.mkdirSync(cwd, { recursive: true });
        const result = await ctx.runProcess(executable, argv, {
          cwd, timeoutSec: timeout(args.timeoutSec),
          env: ctx.config.pdsLicense ? { PANGO_LICENSE_FILE: ctx.config.pdsLicense } : {},
        });
        const summary = compactProcessResult(result, args.detail === 'full' ? 'full' : 'summary');
        const errors = detectErrors(`${result.stdout || ''}\n${result.stderr || ''}`);
        return { ok: result.code === 0 && !result.timedOut && errors.length === 0,
          executable, cwd, errors, ...summary };
      },
    },
  ];
}
