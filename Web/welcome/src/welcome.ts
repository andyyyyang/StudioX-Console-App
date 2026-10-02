/**
 * App 歡迎頁：和 console 的網頁登入（atelier-cms 的 auth/AuthScreen.tsx）同一個上半部 ——
 * 大字品牌名＋ 3D 玻璃 Logo（studiox.tw 首頁的 logo3d.ts：三塊積木各自散開漂浮又組合起來，可以用手指抓著玩）。
 * 下半部的登入面板是 App 自己畫的（SwiftUI），疊在這一頁上面。
 *
 * 和 App 溝通：
 *   App → 這裡：window.studiox.setSheet(px)（下方被面板蓋住多高，Logo 擺在剩下的空間正中間）
 *              window.studiox.assemble()（積木立刻組合起來，例如按下登入時）
 *   這裡 → App：webkit.messageHandlers.welcome.postMessage('ready' | 'flat')
 * 不支援 WebGL、軟體繪圖或減少動態時，改顯示平面 Logo（和網頁一樣）。
 */
import { initLogo3D, type Logo3DController, type Logo3DState } from './logo3d'

type Bridge = { postMessage(message: string): void }
const post = (message: 'ready' | 'flat') => {
  const handler = (window as unknown as { webkit?: { messageHandlers?: { welcome?: Bridge } } }).webkit?.messageHandlers?.welcome
  handler?.postMessage(message)
}

// 3D Logo 看 <html data-theme> 決定深淺色打光：跟著系統設定（App 的深淺色）
const root = document.documentElement
const dark = matchMedia('(prefers-color-scheme: dark)')
const syncTheme = () => { root.dataset.theme = dark.matches ? 'dark' : 'light' }
syncTheme()
dark.addEventListener('change', syncTheme)

const hero = document.querySelector<HTMLElement>('.au-hero')!
const canvas = document.querySelector<HTMLCanvasElement>('.au-canvas')!
const stage = document.querySelector<HTMLElement>('.au-stage-box')!
const word = document.querySelector<HTMLElement>('.au-word')!

/** 大字品牌名撐滿寬度：量字寬，縮放到容器的 90%（最大 260px） */
const fitWord = () => {
  word.style.fontSize = '100px'
  const w = word.scrollWidth
  const box = hero.clientWidth - 36
  if (w > 0 && box > 0) word.style.fontSize = `${Math.min(260, (100 * box * 0.9) / w)}px`
}
fitWord()
new ResizeObserver(fitWord).observe(hero)
void document.fonts?.ready.then(fitWord)

/** 軟體繪圖（沒有顯示卡）時 3D 會卡，改用平面 Logo。和 studiox.tw 的判斷相同 */
function canRender3D(): boolean {
  if (!('WebGL2RenderingContext' in window)) return false
  // 截圖測試用（無頭瀏覽器一定是軟體繪圖）：welcome.html?force3d
  if (location.search.includes('force3d')) return true
  try {
    const gl = document.createElement('canvas').getContext('webgl2', { failIfMajorPerformanceCaveat: true })
    if (!gl) return false
    const info = gl.getExtension('WEBGL_debug_renderer_info')
    const name = String(gl.getParameter(info ? info.UNMASKED_RENDERER_WEBGL : gl.RENDERER))
    gl.getExtension('WEBGL_lose_context')?.loseContext()
    return !/swiftshader|llvmpipe|softpipe|software|basic render/i.test(name)
  } catch {
    return false
  }
}

const state: Logo3DState = { mx: 0, my: 0, scrollAt: -1e9, scrollV: 0 }
addEventListener('pointermove', (e) => {
  state.mx = (e.clientX / innerWidth) * 2 - 1
  state.my = (e.clientY / innerHeight) * 2 - 1
}, { passive: true })

let ctrl: Logo3DController | null = null
const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
if (!reduced && canRender3D()) {
  ctrl = initLogo3D(canvas, stage, state, false, () => {
    hero.classList.add('is-3d')
    ctrl?.play()
    post('ready')
  })
} else {
  post('flat')
}

;(window as unknown as { studiox: unknown }).studiox = {
  setSheet(px: number) {
    root.style.setProperty('--sheet', `${Math.max(0, Math.round(px))}px`)
  },
  assemble() {
    // logo3d 把「剛捲動過」當成要立刻組合
    state.scrollAt = performance.now()
    state.scrollV = 0
  },
}
