import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const objects = {};
const id = name => createHash('md5').update('INCY:' + name).digest('hex').slice(0, 24).toUpperCase();
function object(name, isa, fields) { const key = id(name); objects[key] = { isa, ...fields }; return key; }
const appSources = fs.readdirSync(path.join(root, 'App')).filter(f => f.endsWith('.swift')).map(f => 'App/' + f);
const shared = fs.readdirSync(path.join(root, 'Shared')).filter(f => f.endsWith('.swift')).map(f => 'Shared/' + f);
const tunnelSources = ['Tunnel/PacketTunnelProvider.swift', 'Native/PacketBridge.c', 'Native/HevBridge.c'];
const refs = {};
function file(p, type) {
  return refs[p] ??= object('file:' + p, 'PBXFileReference', { lastKnownFileType: type ?? (p.endsWith('.swift') ? 'sourcecode.swift' : p.endsWith('.c') ? 'sourcecode.c.c' : p.endsWith('.h') ? 'sourcecode.c.h' : 'text'), path: p, sourceTree: '<group>' });
}
function build(p, context, type) { return object('build:' + context + ':' + p, 'PBXBuildFile', { fileRef: file(p, type) }); }
const signing = file('Config/Signing.xcconfig', 'text.xcconfig');
const appProduct = object('product:app', 'PBXFileReference', { explicitFileType: 'wrapper.application', path: 'INCY.app', sourceTree: 'BUILT_PRODUCTS_DIR', includeInIndex: 0 });
const tunnelProduct = object('product:tunnel', 'PBXFileReference', { explicitFileType: 'wrapper.app-extension', path: 'PacketTunnel.appex', sourceTree: 'BUILT_PRODUCTS_DIR', includeInIndex: 0 });
const appID = id('target:app'), tunnelID = id('target:tunnel'), projectID = id('project');
const common = {
  SDKROOT: 'iphoneos', IPHONEOS_DEPLOYMENT_TARGET: '12.5', SWIFT_VERSION: '5.0',
  CLANG_ENABLE_MODULES: 'YES', CLANG_ENABLE_OBJC_ARC: 'YES', ENABLE_BITCODE: 'NO',
  CLANG_WARN_DOCUMENTATION_COMMENTS: 'YES', GCC_C_LANGUAGE_STANDARD: 'gnu11',
  ARCHS: 'arm64', TARGETED_DEVICE_FAMILY: '1', SUPPORTED_PLATFORMS: 'iphoneos',
  CODE_SIGN_STYLE: 'Automatic', ENABLE_USER_SCRIPT_SANDBOXING: 'NO',
};
function configs(context, settings) {
  const entries = ['Debug', 'Release'].map(name => object('config:' + context + ':' + name, 'XCBuildConfiguration', {
    ...(context === 'project' ? { baseConfigurationReference: signing } : {}),
    buildSettings: { ...settings, SWIFT_OPTIMIZATION_LEVEL: name === 'Debug' ? '-Onone' : '-O', DEBUG_INFORMATION_FORMAT: name === 'Debug' ? 'dwarf' : 'dwarf-with-dsym', ...(name === 'Debug' ? { SWIFT_ACTIVE_COMPILATION_CONDITIONS: 'DEBUG', GCC_PREPROCESSOR_DEFINITIONS: ['DEBUG=1', '$(inherited)'] } : {}) }, name,
  }));
  return object('configs:' + context, 'XCConfigurationList', { buildConfigurations: entries, defaultConfigurationIsVisible: 0, defaultConfigurationName: 'Release' });
}
function sources(context, list) { return object('sources:' + context, 'PBXSourcesBuildPhase', { buildActionMask: 2147483647, files: list.map(p => build(p, context)), runOnlyForDeploymentPostprocessing: 0 }); }
function frameworks(context, libraries) {
  const files = libraries.map(name => {
    const p = 'System/Library/Frameworks/' + name + '.framework';
    const ref = object('framework:' + name, 'PBXFileReference', { lastKnownFileType: 'wrapper.framework', path: p, sourceTree: 'SDKROOT' });
    return object('framework-build:' + context + name, 'PBXBuildFile', { fileRef: ref });
  });
  if (context === 'tunnel') {
    for (const p of ['Native/lib/libIncyXray.a', 'Native/lib/libHevTunnel.a']) files.push(build(p, context, 'archive.ar'));
  }
  return object('frameworks:' + context, 'PBXFrameworksBuildPhase', { buildActionMask: 2147483647, files, runOnlyForDeploymentPostprocessing: 0 });
}
const appResources = object('resources:app', 'PBXResourcesBuildPhase', { buildActionMask: 2147483647, files: [build('App/Assets.xcassets', 'app', 'folder.assetcatalog'), build('App/LaunchScreen.storyboard', 'app', 'file.storyboard')], runOnlyForDeploymentPostprocessing: 0 });
const emptyResources = object('resources:tunnel', 'PBXResourcesBuildPhase', { buildActionMask: 2147483647, files: [], runOnlyForDeploymentPostprocessing: 0 });
const embedBuild = object('embed:build', 'PBXBuildFile', { fileRef: tunnelProduct, settings: { ATTRIBUTES: ['RemoveHeadersOnCopy'] } });
const embed = object('embed', 'PBXCopyFilesBuildPhase', { buildActionMask: 2147483647, dstPath: '', dstSubfolderSpec: 13, files: [embedBuild], name: 'Embed App Extensions', runOnlyForDeploymentPostprocessing: 0 });
const proxy = object('dependency:proxy', 'PBXContainerItemProxy', { containerPortal: projectID, proxyType: 1, remoteGlobalIDString: tunnelID, remoteInfo: 'PacketTunnel' });
const dependency = object('dependency', 'PBXTargetDependency', { target: tunnelID, targetProxy: proxy });
object('target:app', 'PBXNativeTarget', {
  buildConfigurationList: configs('app', { PRODUCT_NAME: 'INCY', PRODUCT_BUNDLE_IDENTIFIER: '$(INCY_BUNDLE_BASE)', INFOPLIST_FILE: 'Config/App-Info.plist', CODE_SIGN_ENTITLEMENTS: 'Config/App.entitlements', ASSETCATALOG_COMPILER_APPICON_NAME: 'AppIcon', LD_RUNPATH_SEARCH_PATHS: ['$(inherited)', '@executable_path/Frameworks'] }),
  buildPhases: [sources('app', [...appSources, ...shared]), frameworks('app', ['UIKit', 'NetworkExtension', 'Security', 'AVFoundation']), appResources, embed], buildRules: [], dependencies: [dependency], name: 'INCY', productName: 'INCY', productReference: appProduct, productType: 'com.apple.product-type.application',
});
object('target:tunnel', 'PBXNativeTarget', {
  buildConfigurationList: configs('tunnel', { PRODUCT_NAME: 'PacketTunnel', PRODUCT_BUNDLE_IDENTIFIER: '$(INCY_BUNDLE_BASE).PacketTunnel', INFOPLIST_FILE: 'Config/Tunnel-Info.plist', CODE_SIGN_ENTITLEMENTS: 'Config/Tunnel.entitlements', SKIP_INSTALL: 'YES', APPLICATION_EXTENSION_API_ONLY: 'YES', SWIFT_OBJC_BRIDGING_HEADER: 'Native/include/IncyNative.h', HEADER_SEARCH_PATHS: ['$(inherited)', '$(SRCROOT)/Native/include', '$(SRCROOT)/Vendor/hev-socks5-tunnel/src', '$(SRCROOT)/Vendor/hev-socks5-tunnel/src/misc', '$(SRCROOT)/Vendor/hev-socks5-tunnel/src/core/include', '$(SRCROOT)/Vendor/hev-socks5-tunnel/third-part/lwip/src/include', '$(SRCROOT)/Vendor/hev-socks5-tunnel/third-part/lwip/src/ports/include', '$(SRCROOT)/Vendor/hev-socks5-tunnel/third-part/hev-task-system/include'], OTHER_LDFLAGS: ['$(inherited)', '-lresolv', '-framework', 'CoreFoundation'], LD_RUNPATH_SEARCH_PATHS: ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks'] }),
  buildPhases: [sources('tunnel', [...tunnelSources, ...shared]), frameworks('tunnel', ['NetworkExtension', 'Security']), emptyResources], buildRules: [], dependencies: [], name: 'PacketTunnel', productName: 'PacketTunnel', productReference: tunnelProduct, productType: 'com.apple.product-type.app-extension',
});
for (const p of ['Config/App-Info.plist', 'Config/Tunnel-Info.plist', 'Config/App.entitlements', 'Config/Tunnel.entitlements']) file(p, 'text.plist.xml');
file('Native/include/IncyNative.h');
const products = object('group:products', 'PBXGroup', { children: [appProduct, tunnelProduct], name: 'Products', sourceTree: '<group>' });
const mainGroup = object('group:main', 'PBXGroup', { children: [...Object.values(refs), products], sourceTree: '<group>' });
object('project', 'PBXProject', { attributes: { LastUpgradeCheck: '1430', TargetAttributes: { [appID]: { CreatedOnToolsVersion: '14.3' }, [tunnelID]: { CreatedOnToolsVersion: '14.3' } } }, buildConfigurationList: configs('project', common), compatibilityVersion: 'Xcode 14.0', developmentRegion: 'ru', hasScannedForEncodings: 0, knownRegions: ['ru', 'en', 'Base'], mainGroup, productRefGroup: products, projectDirPath: '', projectRoot: '', targets: [appID, tunnelID] });
function encode(value, level = 0) {
  const indent = '\t'.repeat(level);
  if (Array.isArray(value)) return '(\n' + value.map(v => indent + '\t' + encode(v, level + 1) + ',').join('\n') + '\n' + indent + ')';
  if (value && typeof value === 'object') return '{\n' + Object.entries(value).map(([k, v]) => indent + '\t' + (/^[A-Za-z0-9_]+$/.test(k) ? k : JSON.stringify(k)) + ' = ' + encode(v, level + 1) + ';').join('\n') + '\n' + indent + '}';
  return typeof value === 'number' ? String(value) : /^[A-Za-z0-9_]+$/.test(value) ? value : JSON.stringify(value);
}
const projectDir = path.join(root, 'INCY.xcodeproj'); fs.mkdirSync(projectDir, { recursive: true });
fs.writeFileSync(path.join(projectDir, 'project.pbxproj'), '// !$*UTF8*$!\n' + encode({ archiveVersion: 1, classes: {}, objectVersion: 56, objects, rootObject: projectID }) + '\n');
const schemeDir = path.join(projectDir, 'xcshareddata', 'xcschemes'); fs.mkdirSync(schemeDir, { recursive: true });
const appRef = `<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="${appID}" BuildableName="INCY.app" BlueprintName="INCY" ReferencedContainer="container:INCY.xcodeproj"/>`;
fs.writeFileSync(path.join(schemeDir, 'INCY.xcscheme'), `<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1430" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">${appRef}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">${appRef}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO"><BuildableProductRunnable runnableDebuggingMode="0">${appRef}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>\n`);
console.log('Created INCY.xcodeproj (iOS 12.5, arm64, app + PacketTunnel).');

