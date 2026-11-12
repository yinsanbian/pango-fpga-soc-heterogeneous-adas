import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { compactProcessResult } from './runtime.mjs';

const CRAM_SVF_PROPERTY = '0x40C4E';

function requiredText(value, name) {
  if (typeof value !== 'string' || !value.trim()) throw new Error(`${name} is required`);
  return value.trim();
}

function existingFile(value, name) {
  const supplied = requiredText(value, name);
  if (!path.isAbsolute(supplied)) throw new Error(`${name} must be an absolute path`);
  const file = path.resolve(supplied);
  if (!fs.existsSync(file) || !fs.statSync(file).isFile()) throw new Error(`${name} is unavailable: ${file}`);
  return file;
}

function outputFile(value, name, input, overwrite) {
  const supplied = requiredText(value, name);
  if (!path.isAbsolute(supplied)) throw new Error(`${name} must be an absolute path`);
  const file = path.resolve(supplied);
  if (input && file.toLowerCase() === input.toLowerCase()) throw new Error(`${name} must not replace the input file`);
  if (fs.existsSync(file) && !overwrite) throw new Error(`${name} already exists: ${file}. Set overwrite:true to replace it.`);
  const parent = path.dirname(file);
  if (!fs.existsSync(parent) || !fs.statSync(parent).isDirectory()) throw new Error(`${name} parent directory is unavailable: ${parent}`);
  return file;
}

function tclWord(value) {
  return `"${String(value).replace(/\\/g, '/').replace(/"/g, '\\"')
    .replace(/\$/g, '\\$').replace(/\[/g, '\\[').replace(/\]/g, '\\]')
    .replace(/\r/g, '\\r').replace(/\n/g, '\\n')}"`;
}

function svfProperty(value) {
  const raw = value === undefined || value === null ? CRAM_SVF_PROPERTY : String(value);
  if (!/^(?:0x)?[0-9a-f]+$/i.test(raw)) throw new Error('property must be a hexadecimal svf_property value');
  const bits = BigInt(raw.startsWith('0x') ? raw : `0x${raw}`);
  if (((bits >> 16n) & 3n) !== 0n) throw new Error('property selects a non-CRAM SVF mode; fpga_jtag_gen_svf only emits CRAM configuration SVF');
  return `0x${bits.toString(16).toUpperCase()}`;
}

function pdsBin(ctx, requested) {
  const configured = ctx.config?.pdsBin || (ctx.config?.pdsShell ? path.dirname(ctx.config.pdsShell) : '');
  const supplied = requested || configured;
  if (!supplied || !path.isAbsolute(supplied)) throw new Error('PDS bin is not configured: set PANGO_MCP_PDS_2025 or pass pdsBin');
  const bin = path.resolve(supplied);
  const exe = path.join(bin, 'cdt_cfg_shell.exe');
  if (!fs.existsSync(exe)) throw new Error(`cdt_cfg_shell.exe is unavailable: ${exe}`);
  return { bin, exe };
}

function timeout(value) {
  if (value === undefined || value === null) return 180;
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) throw new Error('timeoutSec must be positive');
  return Math.min(n, 3600);
}

function cleanTempDirectory(dir) {
  // Only remove regular files directly inside the unique directory we created.
  try {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      if (entry.isFile()) fs.unlinkSync(path.join(dir, entry.name));
    }
    fs.rmdirSync(dir);
  } catch { /* keep unexpected vendor output for inspection */ }
}

function scalarNet(value, name) {
  const net = requiredText(value, name);
  if (/[\r\n=]/.test(net)) throw new Error(`${name} contains a newline or equals sign`);
  return net;
}

function devicePart(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new Error('part must contain family, device, speedgrade, and package');
  }
  const family = requiredText(value.family ?? value.deviceFamily, 'part.family');
  const device = requiredText(value.device ?? value.deviceModel, 'part.device');
  const speedgrade = requiredText(value.speedgrade ?? value.deviceSpeedGrade, 'part.speedgrade');
  const packageName = requiredText(value.package ?? value.devicePackage, 'part.package');
  for (const [name, text] of Object.entries({ family, device, speedgrade, package: packageName })) {
    if (/[\r\n=]/.test(text)) throw new Error(`part.${name} contains a newline or equals sign`);
  }
  return { family, device, speedgrade, package: packageName };
}

export function offlineTools(ctx) {
  return [
    {
      name: 'fpga_jtag_gen_svf',
      description: 'Use the installed PDS cfg_one_step_create_svf command to generate a CRAM configuration SVF from a .sbit file. This is an offline conversion and does not open a JTAG cable.',
      inputSchema: { type: 'object', required: ['sbit'], properties: {
        sbit: { type: 'string', description: 'Absolute path to the input .sbit file.' },
        svf: { type: 'string', description: 'Absolute output path; defaults beside the .sbit file with suffix _cram.svf.' },
        pdsBin: { type: 'string', description: 'PDS bin directory containing cdt_cfg_shell.exe; defaults to configured PDS bin.' },
        license: { type: 'string', description: 'PDS license path; defaults to configured PANGO_LICENSE_FILE.' },
        property: { type: 'string', description: 'Hexadecimal -svf_property; defaults to 0x40C4E (CRAM mode). Other SVF modes are rejected.' },
        timeoutSec: { type: 'number', minimum: 1, maximum: 3600 },
        overwrite: { type: 'boolean', description: 'Allow replacing an existing .svf output.' },
      } },
      async run(args) {
        const sbit = existingFile(args.sbit, 'sbit');
        if (!/\.sbit$/i.test(sbit)) throw new Error('sbit must have a .sbit extension');
        const svf = outputFile(args.svf || sbit.replace(/\.sbit$/i, '_cram.svf'), 'svf', sbit, args.overwrite);
        const { exe } = pdsBin(ctx, args.pdsBin);
        const property = svfProperty(args.property);
        const license = args.license ? existingFile(args.license, 'license') : ctx.config?.pdsLicense;
        const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'pango-mcp-svf-'));
        const script = path.join(temp, 'command.tcl');
        const command = `cfg_one_step_create_svf -sbit ${tclWord(sbit)} -svf_file_name ${tclWord(svf)} -svf_property ${tclWord(property)}`;
        fs.writeFileSync(script, `set pango_mcp_command [list ${command}]\nset pango_mcp_code [catch {uplevel #0 $pango_mcp_command} pango_mcp_result]\nputs "PANGO_MCP_CODE=$pango_mcp_code"\nputs "PANGO_MCP_RESULT=$pango_mcp_result"\n`, 'utf8');
        let result;
        try {
          result = await ctx.runProcess(exe, ['-file', script], {
            cwd: temp, timeoutSec: timeout(args.timeoutSec),
            env: license ? { PANGO_LICENSE_FILE: license } : {},
          });
        } finally { cleanTempDirectory(temp); }
        const output = `${result.stdout || ''}\n${result.stderr || ''}`;
        const errors = output.split(/\r?\n/).filter(line => /^\s*(?:E:|\*\*\s+(?:Error|Fatal)|Error:)/i.test(line)).slice(0, 30);
        const code = output.match(/PANGO_MCP_CODE=(\d+)/)?.[1];
        const exists = fs.existsSync(svf) && fs.statSync(svf).isFile();
        return {
          ok: result.code === 0 && !result.timedOut && code === '0' && errors.length === 0 && exists,
          sbit, svf, property, outputExists: exists, errors,
          ...compactProcessResult(result, 'summary'),
          ...(!exists && errors.length === 0 ? { diagnostic: 'The PDS converter did not create the expected SVF output' } : {}),
        };
      },
    },
    {
      name: 'fpga_ila_generate_fic',
      description: 'Write a PDS Fabric Inserter .fic text file from a complete device part, post-synthesis scalar net names, and a post-synthesis clock net. The net names are not checked against a design.',
      inputSchema: { type: 'object', required: ['part', 'ficPath', 'signals', 'clockNet'], properties: {
        part: { type: 'object', required: ['family', 'device', 'speedgrade', 'package'], properties: {
          family: { type: 'string' }, device: { type: 'string' }, speedgrade: { type: 'string' }, package: { type: 'string' },
        } },
        ficPath: { type: 'string', description: 'Absolute output .fic path.' },
        signals: { type: 'array', minItems: 1, maxItems: 256, items: { type: 'string' }, description: 'Post-synthesis scalar net names, in capture order.' },
        clockNet: { type: 'string', description: 'Post-synthesis sample clock net.' },
        dataDepth: { type: 'integer', minimum: 32, maximum: 16384, description: 'Capture sample depth; defaults to 1024.' },
        designInputFile: { type: 'string', description: 'Optional absolute path to an existing synthesized .adf netlist.' },
        overwrite: { type: 'boolean', description: 'Allow replacing an existing .fic output.' },
      } },
      run(args) {
        const part = devicePart(args.part);
        const clockNet = scalarNet(args.clockNet, 'clockNet');
        if (!Array.isArray(args.signals) || args.signals.length < 1 || args.signals.length > 256) {
          throw new Error('signals must contain 1 to 256 post-synthesis scalar net names');
        }
        const signals = args.signals.map((signal, i) => scalarNet(signal, `signals[${i}]`));
        if (new Set(signals).size !== signals.length) throw new Error('signals contains duplicate net names');
        const depth = args.dataDepth === undefined ? 1024 : Number(args.dataDepth);
        if (!Number.isInteger(depth) || depth < 32 || depth > 16384 || (depth & (depth - 1)) !== 0) {
          throw new Error('dataDepth must be a power of two from 32 to 16384');
        }
        if (args.busGroups !== undefined) throw new Error('busGroups is not supported without a verified group format');
        const designInputFile = args.designInputFile ? existingFile(args.designInputFile, 'designInputFile') : '';
        if (designInputFile && !/\.adf$/i.test(designInputFile)) throw new Error('designInputFile must be a synthesized .adf file');
        const ficPath = outputFile(args.ficPath, 'ficPath', designInputFile, args.overwrite);
        if (!/\.fic$/i.test(ficPath)) throw new Error('ficPath must have a .fic extension');
        const lines = [
          '#Fabric Core Inserter Project File',
          `Project.device.designInputFile=${designInputFile.replace(/\\/g, '/')}`,
          'Project.device.ScanChain=1',
          'Project.device.UserJtag=0',
          `Project.device.deviceFamily=${part.family}`,
          `Project.device.deviceModel=${part.device}`,
          `Project.device.devicePackage=${part.package}`,
          `Project.device.deviceSpeedGrade=${part.speedgrade}`,
          'Project.Architecture=1 1 1',
          'Project.unit.dimension=1',
          `Project.unit<0>.clockChannel=${clockNet}`,
          'Project.unit<0>.clockEdge=Rising',
          `Project.unit<0>.dataDepth=${depth}`,
          'Project.unit<0>.dataEqualsTrigger=true',
          'Project.unit<0>.enablePowerOnInitData=false',
          'Project.unit<0>.enableStorageQualification=false',
          'Project.unit<0>.triggerSequencerLevels=1',
          'Project.unit<0>.enableMultiWindow=false',
          'Project.unit<0>.triggerPortCount=1',
          ...signals.map((signal, i) => `Project.unit<0>.triggerChannel<0><${i}>=${signal}`),
          'Project.unit<0>.triggerMatchCount<0>=1',
          'Project.unit<0>.triggerMatchCountWidth<0>=0',
          'Project.unit<0>.triggerMatchType<0>=1',
          'Project.unit<0>.triggerPortIsData<0>=true',
          `Project.unit<0>.triggerPortWidth<0>=${signals.length}`,
        ];
        fs.writeFileSync(ficPath, `${lines.join('\n')}\n`, { encoding: 'utf8', flag: args.overwrite ? 'w' : 'wx' });
        return { ok: true, ficPath, part, clockNet, signalCount: signals.length, dataDepth: depth,
          designInputFile: designInputFile || null, netNamesVerified: false,
          sourceFormat: 'PDS 2023.2 installed example .fic files',
          nextStep: 'Register this FIC in a matching PDS project, then build to validate net names and format.' };
      },
    },
  ];
}
