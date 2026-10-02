// 打包歡迎頁：src/welcome.ts（＋ three.js、logo3d.ts）→ StudioXConsole/Welcome/welcome.js，連同 HTML 與字型一起放進 App。
// 用法：cd Web/welcome && npm install && npm run build
import { build } from 'esbuild'
import { copyFileSync, mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const out = join(here, '../../StudioXConsole/Welcome')
mkdirSync(out, { recursive: true })

await build({
  entryPoints: [join(here, 'src/welcome.ts')],
  bundle: true,
  format: 'iife',
  minify: true,
  target: ['safari17'],
  legalComments: 'eof',
  outfile: join(out, 'welcome.js'),
})
copyFileSync(join(here, 'src/welcome.html'), join(out, 'welcome.html'))
copyFileSync(join(here, 'fonts/inter-tight-latin.woff2'), join(out, 'inter-tight-latin.woff2'))
copyFileSync(join(here, 'fonts/OFL.txt'), join(out, 'Inter-Tight-OFL.txt'))
console.log('→', out)
