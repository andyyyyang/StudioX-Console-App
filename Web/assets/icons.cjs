// 把後台用的 Heroicons（@heroicons/react 24/outline）輸出成 App 的向量圖示（asset catalog，template）
// 用法（在 atelier-cms 裝好套件之後）：NODE_PATH=../atelier-cms/node_modules node Web/assets/icons.cjs StudioXConsole/Assets.xcassets/Icons
const fs = require('fs'), path = require('path')
const React = require('react')
const { renderToStaticMarkup } = require('react-dom/server')
const out = process.argv[2]
const names = `Home GlobeAlt InboxStack Inbox ShoppingBag UserCircle Cog6Tooth Sparkles ChatBubbleLeftRight ChatBubbleOvalLeftEllipsis
ArrowTopRightOnSquare CheckCircle XCircle ExclamationTriangle ExclamationCircle InformationCircle ArrowUp Stop ChevronRight ChevronDown
MagnifyingGlass Bell BellAlert Truck Banknotes CursorArrowRays Users User ClipboardDocumentList ClipboardDocumentCheck ArrowPath
ArrowUturnLeft Envelope PencilSquare ArrowRightStartOnRectangle Squares2X2 BuildingStorefront DocumentText Newspaper Clock Phone
MapPin CreditCard Tag Plus XMark EllipsisHorizontal ArrowsRightLeft Link Key ShieldCheck HandRaised LightBulb ChartBar
PresentationChartLine Eye PaperAirplane Check Moon Sun PuzzlePiece Bolt ArrowTrendingUp ArrowTrendingDown Cube Printer
DevicePhoneMobile ComputerDesktop ReceiptRefund Bars3 AdjustmentsHorizontal LockClosed Calendar Funnel ChatBubbleBottomCenterText`.split(/\s+/).filter(Boolean)
// Heroicons 的檔名：Bars3 → bars-3、Squares2X2 → squares-2x2、Cog6Tooth → cog-6-tooth
const kebab = (s) => s.replace(/([a-z])([A-Z0-9])/g, '$1-$2').replace(/([0-9])([A-Z])(?![0-9])/g, '$1-$2').replace(/([A-Z])([A-Z][a-z])/g, '$1-$2').toLowerCase()
fs.mkdirSync(out, { recursive: true })
fs.writeFileSync(path.join(out, 'Contents.json'), JSON.stringify({ info: { author: 'xcode', version: 1 }, properties: { 'provides-namespace': false } }, null, 2) + '\n')
for (const n of names) {
  const Icon = require(`@heroicons/react/24/outline/${n}Icon.js`)
  let svg = renderToStaticMarkup(React.createElement(Icon, { width: 24, height: 24 }))
  svg = svg.replace(/currentColor/g, '#000000').replace(/ aria-hidden="true"| data-slot="icon"/g, '')
  const name = `hi-${kebab(n)}`
  const dir = path.join(out, `${name}.imageset`)
  fs.mkdirSync(dir, { recursive: true })
  fs.writeFileSync(path.join(dir, `${name}.svg`), svg + '\n')
  fs.writeFileSync(path.join(dir, 'Contents.json'), JSON.stringify({
    images: [{ filename: `${name}.svg`, idiom: 'universal' }],
    info: { author: 'xcode', version: 1 },
    properties: { 'preserves-vector-representation': true, 'template-rendering-intent': 'template' },
  }, null, 2) + '\n')
}
console.log(names.length, 'icons →', out)
