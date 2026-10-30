import fs from 'node:fs';
import path from 'node:path';

const maxIOS = (12 << 16) | (5 << 8) | 8;
const formatVersion = version => `${version >>> 16}.${(version >>> 8) & 255}.${version & 255}`;

function inspect(executable) {
  const data = fs.readFileSync(executable);
  const fail = message => { throw new Error(`${executable}: ${message}`); };
  if (data.length < 32 || data.readUInt32LE(0) !== 0xfeedfacf || data.readUInt32LE(4) !== 0x0100000c) {
    fail('expected an arm64 Mach-O executable');
  }
  const commands = data.readUInt32LE(16);
  const commandEnd = 32 + data.readUInt32LE(20);
  if (commandEnd > data.length) fail('invalid load-command region');
  let offset = 32;
  let minimum;
  const requiredLibraries = [];
  for (let index = 0; index < commands; index++) {
    if (offset + 8 > commandEnd) fail('truncated load command');
    const command = data.readUInt32LE(offset);
    const size = data.readUInt32LE(offset + 4);
    if (size < 8 || offset + size > commandEnd) fail('invalid load-command size');
    if (command === 0x32) {
      if (size < 24 || data.readUInt32LE(offset + 8) !== 2) fail('expected the iOS device platform');
      minimum = data.readUInt32LE(offset + 12);
    } else if (command === 0x25) {
      if (size < 16) fail('invalid minimum-iOS command');
      minimum = data.readUInt32LE(offset + 8);
    } else if ([0x0c, 0x8000001f, 0x80000023].includes(command)) {
      if (size < 24) fail('invalid library command');
      const nameOffset = data.readUInt32LE(offset + 8);
      const end = data.indexOf(0, offset + nameOffset);
      if (nameOffset < 24 || nameOffset >= size || end < 0 || end >= offset + size) fail('invalid library name');
      requiredLibraries.push(data.toString('utf8', offset + nameOffset, end));
    }
    offset += size;
  }
  if (offset !== commandEnd) fail('load-command count does not match its region');
  if (minimum === undefined || minimum > maxIOS) fail('requires a system newer than iOS 12.5.8');
  const swiftUI = requiredLibraries.find(library => library.includes('SwiftUI.framework/') || /(?:^|\/)libswiftSwiftUI\./.test(library));
  if (swiftUI) fail(`requires ${swiftUI}; SwiftUI is unavailable on iOS 12`);
  return { executable, architecture: 'arm64', minimumIOS: formatVersion(minimum), requiredLibraries };
}

try {
  if (process.argv.length !== 3) throw new Error('Usage: node Scripts/check-ios-compatibility.mjs <INCY.app>');
  const app = path.resolve(process.argv[2]);
  const result = ['INCY', 'PlugIns/PacketTunnel.appex/PacketTunnel'].map(file => inspect(path.join(app, file)));
  console.log(JSON.stringify(result, null, 2));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
