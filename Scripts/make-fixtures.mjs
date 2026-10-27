import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const uuid = '11111111-1111-4111-8111-111111111111';
const key = Buffer.alloc(32, 1).toString('base64url');
const cases = [
  ['vless-reality', 'vless', {vnext:[{address:'192.0.2.1',port:443,users:[{id:uuid,encryption:'none',flow:'xtls-rprx-vision'}]}]}, {network:'tcp',security:'reality',realitySettings:{serverName:'www.example.com',fingerprint:'chrome',publicKey:key,shortId:'abcd',spiderX:'/'}}],
  ['vless-ws', 'vless', {vnext:[{address:'192.0.2.1',port:443,users:[{id:uuid,encryption:'none'}]}]}, {network:'ws',security:'tls',tlsSettings:{serverName:'example.com',fingerprint:'chrome',allowInsecure:false},wsSettings:{path:'/ws',headers:{Host:'example.com'}}}],
  ['vless-grpc', 'vless', {vnext:[{address:'192.0.2.1',port:443,users:[{id:uuid,encryption:'none'}]}]}, {network:'grpc',security:'tls',tlsSettings:{serverName:'example.com'},grpcSettings:{serviceName:'grpc'}}],
  ['vless-h2', 'vless', {vnext:[{address:'192.0.2.1',port:443,users:[{id:uuid,encryption:'none'}]}]}, {network:'http',security:'tls',tlsSettings:{serverName:'example.com'},httpSettings:{host:['example.com'],path:'/'}}],
  ['vmess', 'vmess', {vnext:[{address:'192.0.2.1',port:443,users:[{id:uuid,alterId:0,security:'auto'}]}]}, {network:'tcp',security:'tls',tlsSettings:{serverName:'example.com'}}],
  ['trojan', 'trojan', {servers:[{address:'192.0.2.1',port:443,password:'fixture-only'}]}, {network:'tcp',security:'tls',tlsSettings:{serverName:'example.com'}}],
  ['shadowsocks', 'shadowsocks', {servers:[{address:'192.0.2.1',port:8388,method:'aes-128-gcm',password:'fixture-only'}]}, {network:'tcp',security:'none'}],
  ['shadowsocks-2022', 'shadowsocks', {servers:[{address:'192.0.2.1',port:8388,method:'2022-blake3-aes-128-gcm',password:Buffer.alloc(16,1).toString('base64')}]}, {network:'tcp',security:'none'}],
  ['socks5', 'socks', {servers:[{address:'192.0.2.1',port:1080,users:[{user:'test',pass:'fixture-only'}]}]}, {network:'tcp',security:'none'}],
  ['http', 'http', {servers:[{address:'192.0.2.1',port:8080,users:[{user:'test',pass:'fixture-only'}]}]}, {network:'tcp',security:'none'}],
];
const dir = path.join(root, 'Core/engine/testdata'); fs.mkdirSync(dir, {recursive:true});
for (const [name, protocol, settings, streamSettings] of cases) {
  const config = {log:{loglevel:'none'},inbounds:[{tag:'tun-socks',listen:'127.0.0.1',port:10808,protocol:'socks',settings:{auth:'noauth',udp:true,ip:'127.0.0.1'}}],outbounds:[{tag:'proxy',protocol,settings,streamSettings,mux:{enabled:false}}],policy:{levels:{'0':{handshake:8,connIdle:120,uplinkOnly:2,downlinkOnly:2,bufferSize:4}}}};
  if (protocol === 'http') {
    config.dns = {servers:['https://1.1.1.1/dns-query'],disableCache:true,tag:'dns-query'};
    config.outbounds.push({tag:'dns-out',protocol:'dns',settings:{network:'tcp',address:'1.1.1.1',port:53,nonIPQuery:'skip'},proxySettings:{tag:'proxy'}});
    config.routing = {domainStrategy:'AsIs',rules:[{type:'field',inboundTag:['tun-socks'],port:'53',outboundTag:'dns-out'}]};
  }
  fs.writeFileSync(path.join(dir, name+'.json'), JSON.stringify(config,null,2)+'\n');
}
fs.mkdirSync(path.join(root,'Examples'),{recursive:true});
fs.writeFileSync(path.join(root,'Examples/profiles.txt'), '# TEST DATA ONLY — 192.0.2.x addresses are reserved and do not connect.\n'+[
  `vless://${uuid}@192.0.2.1:443?security=reality&sni=www.example.com&fp=chrome&pbk=${key}&sid=abcd&flow=xtls-rprx-vision&type=tcp#VLESS%20Reality`,
  `vless://${uuid}@192.0.2.1:443?security=tls&sni=example.com&type=ws&path=%2Fws&host=example.com#VLESS%20WebSocket`,
  'vmess://'+Buffer.from(JSON.stringify({v:2,ps:'VMess',add:'192.0.2.1',port:443,id:uuid,aid:0,net:'tcp',tls:'tls',sni:'example.com'})).toString('base64'),
  'trojan://fixture-only@192.0.2.1:443?sni=example.com#Trojan',
  'ss://'+Buffer.from('aes-128-gcm:fixture-only').toString('base64url')+'@192.0.2.1:8388#Shadowsocks',
  'socks://test:fixture-only@192.0.2.1:1080#SOCKS5',
  'http://test:fixture-only@192.0.2.1:8080#HTTP',
].join('\n')+'\n');
console.log('10 protocol fixtures and example share links created.');

