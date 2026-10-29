import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { isDeepStrictEqual } from 'node:util';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// Synthetic namespace for ad-hoc jailbreak signing, not an Apple Developer team.
// NetworkExtension strips the first component of application-identifier for IPC.
const jailbreakTeam = 'INCYJB0001';
const run = (file, args, options = {}) => execFileSync(file, args, { encoding: 'utf8', ...options });
const readPlist = file => JSON.parse(run('/usr/bin/plutil', ['-convert', 'json', '-o', '-', file]));
const writePlist = (file, value) => run('/usr/bin/plutil', ['-convert', 'xml1', '-o', file, '-'], { input: JSON.stringify(value) });

function entitlements(template, identifier, group) {
  const source = readPlist(path.join(root, 'Config', template));
  const resolve = value => {
    if (typeof value === 'string') return value.replaceAll('$(AppIdentifierPrefix)', '').replaceAll('$(INCY_BUNDLE_BASE)', group);
    if (Array.isArray(value)) return value.map(resolve);
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, resolve(item)]));
    return value;
  };
  const result = { ...resolve(source), 'application-identifier': `${jailbreakTeam}.${identifier}`, 'com.apple.developer.team-identifier': jailbreakTeam };
  if (JSON.stringify(result).includes('$(')) throw new Error(`${template}: unresolved Xcode entitlement variable`);
  if (!isDeepStrictEqual(result['com.apple.developer.networking.networkextension'], ['packet-tunnel-provider'])) {
    throw new Error(`${template}: missing packet-tunnel-provider entitlement`);
  }
  if (!isDeepStrictEqual(result['keychain-access-groups'], [group])) throw new Error(`${template}: incorrect shared Keychain group`);
  if (!isDeepStrictEqual(result['com.apple.developer.networking.vpn.api'], ['allow-vpn'])) throw new Error(`${template}: missing VPN API entitlement`);
  return result;
}

function sign(file, entitlementFile) {
  const args = ['--force', '--sign', '-', '--timestamp=none'];
  if (entitlementFile) args.push('--entitlements', entitlementFile);
  run('/usr/bin/codesign', [...args, file], { stdio: 'inherit' });
}

function signFrameworks(bundle) {
  const frameworks = path.join(bundle, 'Frameworks');
  if (!fs.existsSync(frameworks)) return;
  for (const item of fs.readdirSync(frameworks, { withFileTypes: true })) {
    const file = path.join(frameworks, item.name);
    if (item.isDirectory() && item.name.endsWith('.framework')) {
      signFrameworks(file);
      sign(file);
    } else if (item.name.endsWith('.dylib')) {
      sign(file);
    } else {
      throw new Error(`Unexpected embedded framework: ${file}`);
    }
  }
}

function verify(bundle, expected) {
  run('/usr/bin/codesign', ['--verify', '--deep', '--strict', '--verbose=2', bundle], { stdio: 'inherit' });
  const xml = run('/usr/bin/codesign', ['--display', '--entitlements', '-', '--xml', bundle]);
  const actual = JSON.parse(run('/usr/bin/plutil', ['-convert', 'json', '-o', '-', '-'], { input: xml }));
  if (!isDeepStrictEqual(actual, expected)) throw new Error(`${bundle}: signed entitlements do not match the requested VPN/Keychain permissions`);
  const bundleIdentifier = readPlist(path.join(bundle, 'Info.plist')).CFBundleIdentifier;
  const applicationIdentifier = actual['application-identifier'];
  const separator = applicationIdentifier.indexOf('.');
  if (separator !== 10 || applicationIdentifier.slice(separator + 1) !== bundleIdentifier || applicationIdentifier.slice(0, separator) !== actual['com.apple.developer.team-identifier']) {
    throw new Error(`${bundle}: NetworkExtension cannot derive its bundle identifier from the signed application identifier`);
  }
  console.log(JSON.stringify({ bundle: bundleIdentifier, entitlements: actual }, null, 2));
}

let staging;
try {
  if (process.platform !== 'darwin') throw new Error('Jailbreak IPA packaging requires macOS codesign (run the GitHub Actions workflow).');
  if (process.argv.length !== 4) throw new Error('Usage: node Scripts/package-jailbreak.mjs <INCY.app> <output.ipa>');
  const source = path.resolve(process.argv[2]);
  const output = path.resolve(process.argv[3]);
  if (!output.endsWith('.ipa') || output.startsWith(source + path.sep)) throw new Error('Output must be an IPA outside the input application.');
  const original = readPlist(path.join(source, 'Info.plist'));
  const base = original.CFBundleIdentifier;
  if (typeof base !== 'string' || !/^[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+$/.test(base)) throw new Error('Invalid source application bundle identifier');
  const originalTunnel = readPlist(path.join(source, 'PlugIns', 'PacketTunnel.appex', 'Info.plist'));
  if (originalTunnel.CFBundleIdentifier !== `${base}.PacketTunnel`) throw new Error('VPN extension does not belong to the input application');
  if (original.CFBundleVersion !== originalTunnel.CFBundleVersion) throw new Error('Application and VPN extension build numbers must match');

  staging = fs.mkdtempSync(path.join(os.tmpdir(), 'incy-jailbreak-'));
  const payload = path.join(staging, 'Payload');
  const app = path.join(payload, 'INCY.app');
  const tunnel = path.join(app, 'PlugIns', 'PacketTunnel.appex');
  fs.mkdirSync(payload);
  fs.cpSync(source, app, { recursive: true, preserveTimestamps: true });
  if (fs.existsSync(path.join(app, 'embedded.mobileprovision')) || fs.existsSync(path.join(tunnel, 'embedded.mobileprovision'))) {
    throw new Error('Use an unsigned archive without embedded Apple provisioning profiles for jailbreak packaging');
  }

  const identifier = `${base}.jailbreak`;
  const tunnelIdentifier = `${identifier}.PacketTunnel`;
  writePlist(path.join(app, 'Info.plist'), { ...original, CFBundleIdentifier: identifier, CFBundleDisplayName: 'INCY JB', CFBundleName: 'INCY JB' });
  writePlist(path.join(tunnel, 'Info.plist'), { ...originalTunnel, CFBundleIdentifier: tunnelIdentifier, CFBundleDisplayName: 'INCY JB Tunnel' });
  const appPermissions = entitlements('App.entitlements', identifier, identifier);
  const tunnelPermissions = entitlements('Tunnel.entitlements', tunnelIdentifier, identifier);
  const appEntitlements = path.join(staging, 'App.entitlements');
  const tunnelEntitlements = path.join(staging, 'Tunnel.entitlements');
  writePlist(appEntitlements, appPermissions);
  writePlist(tunnelEntitlements, tunnelPermissions);

  signFrameworks(tunnel);
  sign(tunnel, tunnelEntitlements);
  signFrameworks(app);
  sign(app, appEntitlements);
  verify(tunnel, tunnelPermissions);
  verify(app, appPermissions);
  run(process.execPath, [path.join(root, 'Scripts', 'check-ios-compatibility.mjs'), app], { stdio: 'inherit' });

  fs.mkdirSync(path.dirname(output), { recursive: true });
  const archive = path.join(staging, 'INCY-jailbreak.ipa');
  run('/usr/bin/zip', ['-qry', archive, 'Payload'], { cwd: staging });
  run('/usr/bin/unzip', ['-t', archive], { stdio: 'inherit' });
  fs.copyFileSync(archive, output);
  console.log(`Created ${output}: INCY JB build ${original.CFBundleVersion}. Install with AppSync; preserve its ad-hoc VPN signature.`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  if (staging) fs.rmSync(staging, { recursive: true, force: true });
}
