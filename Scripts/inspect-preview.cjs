// Optional browser verification using playwright-core and an installed Chrome.
// node Scripts/inspect-preview.cjs <path-to-node_modules> <chrome-executable>
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const root = path.resolve(__dirname,'..');
async function main(){
  const {chromium}=require(path.join(process.argv[2],'playwright-core'));
  const browser=await chromium.launch({executablePath:process.argv[3],headless:true});
  try{
    const page=await browser.newPage({viewport:{width:1200,height:880},deviceScaleFactor:1});
    const errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.goto(pathToFileURL(path.join(root,'Preview/index.html')).href);
    await page.locator('#power').click();assert.equal(await page.locator('#connection-title').textContent(),'Демо: подключено');
    await page.locator('#power').click();
    await page.locator('[data-page=settings]').click();await page.locator('[data-dns="9.9.9.9"]').click();
    await page.locator('[data-page=home]').click();assert.equal(await page.locator('#dns').textContent(),'9.9.9.9');
    await page.locator('[data-import]').first().click();await page.locator('#uri').fill('vless://11111111-1111-4111-8111-111111111111@192.0.2.1:443?security=reality#Preview%20Test');
    await page.locator('#import').click();assert.equal(await page.locator('#server-name').textContent(),'Preview Test');
    assert.equal(await page.locator('#protocol-tag').textContent(),'VLESS · REALITY');
    await page.reload();fs.mkdirSync(path.join(root,'Preview'),{recursive:true});
    await page.screenshot({path:path.join(root,'Preview/desktop.png'),fullPage:true});
    await page.setViewportSize({width:375,height:667});
    const dimensions=await page.evaluate(()=>({width:document.documentElement.scrollWidth,viewport:innerWidth}));
    assert.equal(dimensions.width,dimensions.viewport,'Mobile layout must not overflow horizontally');
    await page.screenshot({path:path.join(root,'Preview/iphone6.png'),fullPage:true});
    assert.deepEqual(errors,[]);
    console.log('Preview verified: navigation, demo connection, DNS selection, profile import, 375×667 layout; screenshots saved.');
  }finally{await browser.close()}
}
main().catch(e=>{console.error(e);process.exitCode=1});

