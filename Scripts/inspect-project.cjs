// Optional static inspection on Windows. Pass a directory containing npm modules:
// node Scripts/inspect-project.cjs <path-to-node_modules>
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const modules = process.argv[2] || path.join(root,'node_modules');
const requireTool = require('node:module').createRequire(path.join(modules,'..','package.json'));
async function main() {
  const xcode = require(path.join(modules,'xcode'));
  const p = xcode.project(path.join(root,'INCY.xcodeproj/project.pbxproj')); p.parseSync();
  const objects = p.hash.project.objects;
  const native = Object.values(objects).filter(o=>o && typeof o==='object' && o.isa==='PBXNativeTarget');
  if(native.length!==2)throw Error('Expected application and PacketTunnel targets');
  console.log('Xcode project parses: app + PacketTunnel targets.');
  const ts = requireTool('web-tree-sitter');
  const Parser = ts.Parser || ts; await Parser.init();
  const Language = ts.Language || Parser.Language;
  const language = await Language.load(path.join(modules,'tree-sitter-wasms/out/tree-sitter-swift.wasm'));
  const parser = new Parser(); parser.setLanguage(language);
  const files = ['Package.swift',...['App','Shared','Tunnel','Tests/Profiles'].flatMap(dir=>fs.readdirSync(path.join(root,dir)).filter(f=>f.endsWith('.swift')).map(f=>dir+'/'+f))];
  let failures=0;
  for(const file of files) {
    const tree=parser.parse(fs.readFileSync(path.join(root,file),'utf8'));
    const problems=[];
    function visit(node){if(node.type==='ERROR'||node.isMissing===true||(typeof node.isMissing==='function'&&node.isMissing()))problems.push(`${node.startPosition.row+1}:${node.startPosition.column+1} ${node.type} ${node.text.slice(0,90)}`); for(const child of node.children)visit(child)}
    visit(tree.rootNode);
    if(problems.length){failures++;console.log(file,problems)}
    tree.delete();
  }
  if(failures)throw Error(`${failures} Swift files have syntax errors`);
  parser.delete();
  console.log(`${files.length} Swift files parse. This does not replace compilation with the Apple SDK.`);
}
main().catch(e=>{console.error(e);process.exitCode=1});

