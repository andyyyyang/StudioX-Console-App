// Xena 的水滴：從後台的 CSS（atelier-cms 的 copilot/styles.ts 的 ORB_BALL_CSS、admin/_components/OrbIcon.tsx）
// 直接畫出 App 用的圖（Assets.xcassets 的 Xena/orb-*.png 五層、XenaOrb 小圖示），App 只負責照網頁的節奏動。
// 用法：npm i playwright-core && node Web/assets/xena-orb.mjs（要有 Chromium；atelier-cms 在旁邊的資料夾）
import { chromium } from 'playwright-core'
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const repo = process.env.APP_REPO ?? join(here, '../..')
const cms = process.env.ATELIER_CMS ?? join(repo, '../atelier-cms')
const assets = join(repo, 'StudioXConsole/Assets.xcassets')
const chrome = process.env.CHROMIUM ?? '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'

const styles = readFileSync(join(cms, 'src/app/_components/copilot/styles.ts'), 'utf8')
const ballCSS = styles.match(/export const ORB_BALL_CSS = `([\s\S]*?)`\n/)[1]
const iconCSS = readFileSync(join(cms, 'src/app/admin/_components/OrbIcon.tsx'), 'utf8').match(/const CSS = `([\s\S]*?)`/)[1]

const only = (layer) => {
  const hide = { halo: ['.cp-orb__ball'], ball: ['.cp-orb__halo', '.cp-orb__ball > i'], core: ['.cp-orb__halo', '.cp-orb__flow', '.cp-orb__glass'], flow: ['.cp-orb__halo', '.cp-orb__core', '.cp-orb__glass'], glass: ['.cp-orb__halo', '.cp-orb__core', '.cp-orb__flow'] }[layer]
  const bare = layer === 'ball' || layer === 'halo' ? '' : '.cp-orb__ball{background:none!important;box-shadow:none!important}'
  return `${hide.map((s) => `${s}{visibility:hidden!important}`).join('')}${bare}${layer === 'flow' ? '.cp-orb__flow{opacity:1!important}' : ''}`
}
const page = (css, body, size) => `<!doctype html><html><head><style>html,body{margin:0;background:transparent}
.cp-orb{transform:none!important;animation:none!important}.cp-orb i,.xena-orb i{animation:none!important}
.wrap{display:grid;place-items:center;width:${size}px;height:${size}px}${css}</style></head><body><div class="wrap" id="w">${body}</div></body></html>`

const browser = await chromium.launch({ executablePath: chrome })
const contents = (files) => JSON.stringify({ images: files, info: { author: 'xcode', version: 1 } }, null, 2) + '\n'

// 五層：畫布 680、水珠 400（App 裡畫框是水珠的 1.7 倍）
mkdirSync(join(assets, 'Xena'), { recursive: true })
writeFileSync(join(assets, 'Xena/Contents.json'), JSON.stringify({ info: { author: 'xcode', version: 1 }, properties: { 'provides-namespace': true } }, null, 2) + '\n')
for (const layer of ['halo', 'ball', 'core', 'flow', 'glass']) {
  const p = await browser.newPage({ viewport: { width: 680, height: 680 } })
  await p.setContent(page(ballCSS + only(layer), '<span class="cp-orb is-css" style="--size:400px"><i class="cp-orb__halo"></i><i class="cp-orb__ball"><i class="cp-orb__core"></i><i class="cp-orb__flow"></i><i class="cp-orb__glass"></i></i></span>', 680))
  const dir = join(assets, `Xena/orb-${layer}.imageset`)
  mkdirSync(dir, { recursive: true })
  await p.locator('#w').screenshot({ path: join(dir, `orb-${layer}.png`), omitBackground: true })
  writeFileSync(join(dir, 'Contents.json'), contents([{ filename: `orb-${layer}.png`, idiom: 'universal' }]))
}

// 小圖示（tab bar、頭像）：後台側欄的 OrbIcon，畫布 100、水珠 76
const iconDir = join(assets, 'XenaOrb.imageset')
mkdirSync(iconDir, { recursive: true })
for (const scale of [2, 3]) {
  const p = await browser.newPage({ viewport: { width: 100, height: 100 }, deviceScaleFactor: scale })
  await p.setContent(page(iconCSS, '<span class="xena-orb" style="width:76px;height:76px"><i class="xena-orb__core"></i><i class="xena-orb__glass"></i></span>', 100))
  await p.locator('#w').screenshot({ path: join(iconDir, `xena-orb@${scale}x.png`), omitBackground: true })
}
writeFileSync(join(iconDir, 'Contents.json'), JSON.stringify({
  images: [{ idiom: 'universal', scale: '1x' }, { filename: 'xena-orb@2x.png', idiom: 'universal', scale: '2x' }, { filename: 'xena-orb@3x.png', idiom: 'universal', scale: '3x' }],
  info: { author: 'xcode', version: 1 },
  properties: { 'template-rendering-intent': 'original' },
}, null, 2) + '\n')
await browser.close()
console.log('→', assets)
