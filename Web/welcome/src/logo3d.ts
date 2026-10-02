/**
 * （這個檔案複製自 studiox.tw 網站（studio_website）的 src/scripts/logo3d.ts，兩邊要一起改；在這裡用於 App 的歡迎頁，見 ./welcome.ts）
 *
 * 首頁 3D Logo（three.js）：清透玻璃 —— 攝影棚柔光箱的反光、邊緣才出現的彩虹色散。
 * 幾何與 src/components/Logo.astro 相同：大三角形＋方塊（沿對角線一半品牌橘）。
 *
 * 動態沒有固定路線：三塊積木（大三角形、方塊的兩個半邊）各自掛在彈簧上，
 * 自己在「散開漂浮」與「貼齊組合」之間循環；每次離開哪幾塊、方向、距離、翻面與停留時間都是隨機的。
 *   - 游標：推動整體視角（帶一點彈性）
 *   - 捲動：干擾視角，並讓積木立刻組合起來
 * 畫布是滿版的，Logo 的位置與大小對齊 stage 元素（.hero__stage，由 CSS 排版）。
 */
import * as THREE from 'three';
import { toCreasedNormals } from 'three/addons/utils/BufferGeometryUtils.js';

type V2 = [number, number];

export interface Logo3DState {
  /** 滑鼠位置 -1 ~ 1 */
  mx: number;
  my: number;
  /** 最後一次捲動的時間（performance.now） */
  scrollAt: number;
  /** 捲動速度（px / frame），用來干擾視角 */
  scrollV: number;
}

// ---- 幾何（32 單位的方格，與 SVG 相同） ----
const S0 = 16.849;
const TRI: V2[] = [
  [2, 2],
  [30, 2],
  [2, 30],
];
const SQ_INK: V2[] = [
  [S0, S0],
  [30, S0],
  [30, 30],
];
const SQ_ACCENT: V2[] = [
  [S0, S0],
  [30, 30],
  [S0, 30],
];

const DEPTH = 2.8;
const BEVEL = 1.35; // 倒角大一點，邊緣像厚玻璃的圓邊，才拉得出長條反光

/** 凸多邊形往內縮 d（讓加上倒角後的外框與 2D 版一致） */
function inset(poly: V2[], d: number): V2[] {
  const n = poly.length;
  let area = 0;
  for (let i = 0; i < n; i++) {
    const [x1, y1] = poly[i];
    const [x2, y2] = poly[(i + 1) % n];
    area += x1 * y2 - x2 * y1;
  }
  const sign = area > 0 ? 1 : -1;
  const lines = poly.map((p, i) => {
    const q = poly[(i + 1) % n];
    const dx = q[0] - p[0];
    const dy = q[1] - p[1];
    const len = Math.hypot(dx, dy);
    const nx = (-dy / len) * sign;
    const ny = (dx / len) * sign;
    return { p: [p[0] + nx * d, p[1] + ny * d] as V2, dir: [dx, dy] as V2 };
  });
  return lines.map((l, i) => {
    const prev = lines[(i - 1 + n) % n];
    const [x1, y1] = prev.p;
    const [dx1, dy1] = prev.dir;
    const [x2, y2] = l.p;
    const [dx2, dy2] = l.dir;
    const den = dx1 * dy2 - dy1 * dx2;
    const t = ((x2 - x1) * dy2 - (y2 - y1) * dx2) / den;
    return [x1 + dx1 * t, y1 + dy1 * t] as V2;
  });
}

/** SVG 座標（y 向下）→ three 座標（y 向上、以方格中心為原點），角落稍微圓角 */
function toShape(poly: V2[], r: number, origin: V2): THREE.Shape {
  const pts = poly.map(([x, y]) => new THREE.Vector2(x - 16 - origin[0], 16 - y - origin[1]));
  const shape = new THREE.Shape();
  const n = pts.length;
  for (let i = 0; i < n; i++) {
    const prev = pts[(i - 1 + n) % n];
    const cur = pts[i];
    const next = pts[(i + 1) % n];
    const a = prev.clone().sub(cur).normalize();
    const b = next.clone().sub(cur).normalize();
    const ang = Math.acos(THREE.MathUtils.clamp(a.dot(b), -1, 1));
    const t = r / Math.tan(ang / 2);
    const p1 = cur.clone().add(a.clone().multiplyScalar(t));
    const p2 = cur.clone().add(b.clone().multiplyScalar(t));
    if (i === 0) shape.moveTo(p1.x, p1.y);
    else shape.lineTo(p1.x, p1.y);
    shape.quadraticCurveTo(cur.x, cur.y, p2.x, p2.y);
  }
  shape.closePath();
  return shape;
}

function centroid(poly: V2[]): V2 {
  const x = poly.reduce((s, p) => s + p[0], 0) / poly.length;
  const y = poly.reduce((s, p) => s + p[1], 0) / poly.length;
  return [x - 16, 16 - y];
}

function extrude(poly: V2[], origin: V2): THREE.BufferGeometry {
  const geo = new THREE.ExtrudeGeometry(toShape(inset(poly, BEVEL), 0.3, origin), {
    depth: DEPTH,
    bevelEnabled: true,
    bevelThickness: 1.5,
    bevelSize: BEVEL,
    bevelSegments: 12,
    curveSegments: 10,
  });
  geo.translate(0, 0, -DEPTH / 2);
  // 預設法線是一格一格的平面，倒角會出現階梯狀的「斷層」；改成平滑（大於 50° 的轉角才保留硬邊）
  return toCreasedNormals(geo, THREE.MathUtils.degToRad(50));
}


// ---- 動態 ----
const TAU = Math.PI * 2;
const rand = (a: number, b: number) => a + Math.random() * (b - a);
const easeOut = (t: number) => 1 - Math.pow(1 - t, 3);

/** 最接近的「正面朝前」角度；轉得夠快時順著原本的方向轉完，不倒退 */
const upright = (a: number, v = 0) => {
  const k = a / TAU;
  return (Math.abs(v) > 1.2 ? (v > 0 ? Math.ceil(k) : Math.floor(k)) : Math.round(k)) * TAU;
};

/** 彈簧（半隱式歐拉）：k 越大越快，zeta < 1 會有一點回彈 */
function spring(x: THREE.Vector3, v: THREE.Vector3, target: THREE.Vector3, k: number, zeta: number, dt: number) {
  const c = 2 * Math.sqrt(k) * zeta;
  v.x += (k * (target.x - x.x) - c * v.x) * dt;
  v.y += (k * (target.y - x.y) - c * v.y) * dt;
  v.z += (k * (target.z - x.z) - c * v.z) * dt;
  x.addScaledVector(v, dt);
}

interface Body {
  obj: THREE.Group;
  /** 組合完成時的位置 */
  base: THREE.Vector3;
  /** 散開的主要方向（單位向量） */
  dir: THREE.Vector2;
  /** 這一輪留在原地、只微微晃動 */
  calm: boolean;
  seed: number;
  /** 相對 base 的位移與歐拉角，以及它們的速度、目標 */
  pos: THREE.Vector3;
  vel: THREE.Vector3;
  rot: THREE.Vector3;
  rvel: THREE.Vector3;
  tPos: THREE.Vector3;
  tRot: THREE.Vector3;
  /** 正被游標抓著；grip 是平滑過渡用的 0 ~ 1 */
  held: boolean;
  grip: number;
  /** 碰撞用：塞在形狀裡的一排小球（本地座標）與每一幀換算後的位置 */
  pts: THREE.Vector3[];
  wpts: THREE.Vector3[];
}

/** 碰撞用的小球半徑：積木厚度約 5.8，平面上從外框往內縮 COL_INSET 放球心 */
const COL_R = 2.4;
const COL_INSET = 2;

/** 在三角形裡以固定間距撒點（含三個角），當作碰撞用的球心 */
function collisionPoints(poly: V2[], origin: V2): THREE.Vector3[] {
  const tri = inset(poly, COL_INSET).map(([x, y]) => new THREE.Vector2(x - 16 - origin[0], 16 - y - origin[1]));
  const [a, b, c] = tri;
  const cross = (p: THREE.Vector2, q: THREE.Vector2, r: THREE.Vector2) => (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x);
  const inside = (p: THREE.Vector2) => {
    const d1 = cross(a, b, p);
    const d2 = cross(b, c, p);
    const d3 = cross(c, a, p);
    return (d1 >= 0 && d2 >= 0 && d3 >= 0) || (d1 <= 0 && d2 <= 0 && d3 <= 0);
  };
  const pts = tri.map((p) => new THREE.Vector3(p.x, p.y, 0));
  const minX = Math.min(a.x, b.x, c.x);
  const maxX = Math.max(a.x, b.x, c.x);
  const minY = Math.min(a.y, b.y, c.y);
  const maxY = Math.max(a.y, b.y, c.y);
  const step = 3.2;
  for (let x = minX; x <= maxX; x += step) {
    for (let y = minY; y <= maxY; y += step) {
      const p = new THREE.Vector2(x, y);
      if (inside(p)) pts.push(new THREE.Vector3(x, y, 0));
    }
  }
  return pts;
}

export interface Logo3DController {
  /** 開始動畫（載入動畫收起之後才呼叫，進場的飛入才不會在布幕後面播完） */
  play(): void;
  dispose(): void;
}

/**
 * 建立場景並先畫出第一格（這時會編譯 shader，最花時間），畫好後呼叫 onReady。
 * 動畫要等 play() 才開始。
 */
export function initLogo3D(
  canvas: HTMLCanvasElement,
  stage: HTMLElement,
  state: Logo3DState,
  reduced = false,
  onReady?: () => void,
): Logo3DController {
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  // 不做色調映射：透過玻璃看到的背景要和頁面底色一模一樣（才通透），燈條的高光直接過曝成純白
  renderer.toneMapping = THREE.NoToneMapping;
  // 滿版畫布＋玻璃要多畫一次折射，像素數量設上限
  const MAX_PIXELS = 3.4e6;

  const scene = new THREE.Scene();

  // ---- 攝影棚環境（深淺色各一套）----
  // 深色：黑色攝影棚＋細長燈條 —— 玻璃裡外都拉出白色亮線（暗場打光）
  // 淺色：亮灰攝影棚＋兩側黑卡 —— 玻璃邊緣折射出俐落的深色線條（亮場打光）
  const buildStudio = (dark: boolean) => {
    const studio = new THREE.Scene();
    const domeGeo = new THREE.SphereGeometry(90, 48, 24);
    const colors: number[] = [];
    const p = domeGeo.attributes.position;
    for (let i = 0; i < p.count; i++) {
      const y = p.getY(i) / 90; // -1 ~ 1
      const v = dark
        ? 0.008 + 0.09 * Math.pow(Math.max(y, 0), 2) + 0.015 * Math.max(-y, 0)
        : 0.62 + 0.3 * Math.max(y, 0) - 0.2 * Math.max(-y, 0);
      colors.push(v, v, v * 1.03);
    }
    domeGeo.setAttribute('color', new THREE.Float32BufferAttribute(colors, 3));
    studio.add(new THREE.Mesh(domeGeo, new THREE.MeshBasicMaterial({ vertexColors: true, side: THREE.BackSide })));

    const panel = (w: number, h: number, at: [number, number, number], color: THREE.ColorRepresentation, intensity = 1) => {
      const m = new THREE.Mesh(
        new THREE.PlaneGeometry(w, h),
        new THREE.MeshBasicMaterial({ color: new THREE.Color(color).multiplyScalar(intensity), side: THREE.DoubleSide }),
      );
      m.position.set(...at);
      m.lookAt(0, 0, 0);
      studio.add(m);
    };

    if (dark) {
      panel(44, 6, [-4, 38, 22], '#ffffff', 9); // 頂部燈條：上緣與正面的長條反光
      panel(4, 54, [-42, 2, 12], '#ffffff', 10); // 左側燈條
      panel(3, 48, [44, -4, 8], '#ffffff', 8); // 右側燈條
      panel(2.5, 46, [-22, 0, -44], '#ffffff', 12); // 後方燈條：透過玻璃看到的亮線
      panel(2.5, 40, [26, 6, -40], '#ffffff', 10);
      panel(40, 2.5, [0, -30, -34], '#ffffff', 8);
      panel(40, 30, [18, 20, 58], '#ffffff', 0.5); // 正面很淡的大面補光：玻璃正面的光澤
      panel(36, 2.5, [0, -40, 10], '#ffffff', 4); // 下緣反光
    } else {
      panel(44, 8, [-4, 38, 22], '#ffffff', 2.4); // 頂部燈條
      panel(40, 30, [18, 20, 58], '#ffffff', 1.25); // 正面補光
      panel(10, 60, [-40, 0, 6], '#000000'); // 左側黑卡：左緣的深色線條
      panel(8, 54, [42, -4, 2], '#000000'); // 右側黑卡
      panel(50, 8, [0, -36, 6], '#101010'); // 底部黑卡：下緣的深色線條
      panel(3, 44, [-20, 0, -44], '#000000'); // 後方黑條：透過玻璃看到的深色線
      panel(3, 40, [24, 4, -42], '#000000');
    }
    return pmrem.fromScene(studio, 0.01).texture;
  };
  const pmrem = new THREE.PMREMGenerator(renderer);
  const envs = { dark: buildStudio(true), light: buildStudio(false) };

  const camera = new THREE.PerspectiveCamera(26, 1, 1, 600);
  const tanHalf = Math.tan(THREE.MathUtils.degToRad(camera.fov / 2));

  // ---- 彩虹色散：只在「交界」—— 倒角接正面、倒角接側牆的細縫上，而且要有亮光經過才分出顏色 ----
  const rainbow = { value: 1 };
  // 折射的環境光：深色模式疊加亮線，淺色模式以深色線條壓暗
  const inner = { add: { value: 0.55 }, mix: { value: 0 } };
  const withEdgeSpectrum = (mat: THREE.MeshPhysicalMaterial, strength: number, neighbors: THREE.Texture, neighborAmt: number) => {
    mat.onBeforeCompile = (shader) => {
      shader.uniforms.uRainbow = rainbow;
      shader.uniforms.uRainbowStrength = { value: strength };
      shader.uniforms.uInnerAdd = inner.add;
      shader.uniforms.uInnerMix = inner.mix;
      shader.uniforms.uNeighbors = { value: neighbors };
      shader.uniforms.uNeighborAmt = { value: neighborAmt };
      // 擠出方向是本地 z：正面 |z| = 1、側牆 |z| = 0，倒角介於兩者之間
      shader.vertexShader = shader.vertexShader
        .replace('void main() {', 'varying float vFaceZ;\nvoid main() {')
        .replace('#include <beginnormal_vertex>', '#include <beginnormal_vertex>\nvFaceZ = abs(objectNormal.z);');
      shader.fragmentShader = shader.fragmentShader
        .replace(
          'void main() {',
          `uniform float uRainbow;
uniform float uRainbowStrength;
uniform float uInnerAdd;
uniform float uInnerMix;
uniform samplerCube uNeighbors;
uniform float uNeighborAmt;
varying float vFaceZ;
vec3 spectrum(float x) {
  // 近似可見光譜：藍 → 青 → 黃 → 紅
  return clamp(vec3(
    abs(x * 6.0 - 3.0) - 1.0,
    2.0 - abs(x * 6.0 - 2.0),
    2.0 - abs(x * 6.0 - 4.0)
  ), 0.0, 1.0);
}
void main() {`,
        )
        .replace(
          '#include <transmission_fragment>',
          `#include <transmission_fragment>
#ifdef ENVMAP_TYPE_CUBE_UV
{
  // 透過玻璃看到的攝影棚：沿著折射方向取環境光，燈條會在玻璃「裡面」拉出亮線，轉動時跟著流動
  vec3 vDir = normalize(vViewPosition);
  vec3 rDir = refract(-vDir, normal, 1.0 / 1.5);
  rDir = normalize(rDir - normal * 0.45);
  rDir = transformDirectionByInverseViewMatrix(rDir, viewMatrix);
  vec3 innerEnv = textureCubeUV(envMap, envMapRotation * rDir, 0.0).rgb * envMapIntensity * diffuseColor.rgb;
  totalDiffuse += innerEnv * uInnerAdd;
  // 淺色：只有倒角與側牆（不是正面）折射出深色線條，正面保持清透
  float edgeW = 1.0 - smoothstep(0.82, 0.97, vFaceZ);
  totalDiffuse = mix(totalDiffuse, totalDiffuse * min(innerEnv * 1.3, vec3(1.0)), uInnerMix * edgeW);
}
#endif`,
        )
        .replace(
          '#include <opaque_fragment>',
          `{
  float ndv = clamp(dot(normal, normalize(vViewPosition)), 0.0, 1.0);
  float seam = smoothstep(0.55, 0.8, vFaceZ) * (1.0 - smoothstep(0.86, 0.97, vFaceZ))
             + smoothstep(0.03, 0.1, vFaceZ) * (1.0 - smoothstep(0.14, 0.26, vFaceZ));
  float lum = dot(outgoingLight, vec3(0.2126, 0.7152, 0.0722));
  float hi = smoothstep(0.3, 1.4, lum);
  vec3 band = spectrum(fract(vFaceZ * 2.4 + ndv * 0.8));
  outgoingLight = mix(outgoingLight, band * lum * 1.5, clamp(seam * hi * uRainbowStrength * uRainbow, 0.0, 1.0));
}
{
  // 旁邊的玻璃：小立方體相機拍到的另外兩塊，依角度疊上去（斜看最明顯，正對時很淡，和真的玻璃一樣）
  vec3 toCam = normalize(vViewPosition);
  vec3 rw = inverseTransformDirection(reflect(-toCam, normal), viewMatrix);
  vec4 nb = textureCube(uNeighbors, rw, 0.6);
  // 菲涅耳：正對時只反射一點點，越斜越像鏡子（倒角、側邊最明顯）
  float fresnel = 0.08 + 0.92 * pow(1.0 - clamp(dot(normal, toCam), 0.0, 1.0), 4.0);
  outgoingLight = mix(outgoingLight, nb.rgb, clamp(nb.a * fresnel * uNeighborAmt, 0.0, 1.0));
}
#include <opaque_fragment>`,
        );
    };
  };

  // ---- 互相反射：每一塊玻璃帶一台小的立方體相機，只拍另外兩塊的「替身」（layer 1，主畫面看不到） ----
  // 替身是簡化的樣子：清玻璃只有邊緣亮（淺色模式是深色線），橘色那塊整片是橘色；透明底，玻璃只疊有東西的地方
  const NEIGHBOR_LAYER = 1;
  const neighborTargets = [0, 1, 2].map(
    () => new THREE.WebGLCubeRenderTarget(256, { type: THREE.HalfFloatType, generateMipmaps: true, minFilter: THREE.LinearMipmapLinearFilter }),
  );
  const standIn = (color: string, body: number, edge: number) =>
    new THREE.ShaderMaterial({
      uniforms: { uColor: { value: new THREE.Color(color) }, uBody: { value: body }, uEdge: { value: edge } },
      vertexShader: `varying vec3 vN;
varying vec3 vW;
void main() {
  vec4 w = modelMatrix * vec4(position, 1.0);
  vW = w.xyz;
  vN = normalize(mat3(modelMatrix) * normal);
  gl_Position = projectionMatrix * viewMatrix * w;
}`,
      fragmentShader: `uniform vec3 uColor;
uniform float uBody;
uniform float uEdge;
varying vec3 vN;
varying vec3 vW;
void main() {
  float ndv = abs(dot(normalize(vN), normalize(cameraPosition - vW)));
  float edge = pow(1.0 - ndv, 3.0);
  gl_FragColor = vec4(uColor, clamp(uBody + edge * uEdge, 0.0, 1.0));
}`,
    });
  // 清玻璃本身幾乎是透明的：反射裡只看得到它的邊；橘色那塊整片都看得到
  const standIns = [standIn('#ffffff', 0, 0.8), standIn('#ffffff', 0, 0.8), standIn('#ff5a1f', 0.85, 0.15)];

  // ---- 玻璃：清透、無粗糙度、真實折射與色散 ----
  // 雙面：three.js 會把每塊玻璃的背面畫進透射層，透過一塊玻璃看得到後面那一塊（原本只看得到背景）
  const makeClear = (neighbors: THREE.Texture) => {
    const m = new THREE.MeshPhysicalMaterial({
      color: 0xffffff,
      metalness: 0,
      roughness: 0,
      transmission: 1,
      thickness: 4,
      ior: 1.5,
      dispersion: 0.7, // 太大會讓整片玻璃偏綠、偏紫
      specularIntensity: 1,
      envMapIntensity: 1.2,
      side: THREE.DoubleSide,
    });
    withEdgeSpectrum(m, 0.7, neighbors, 1);
    return m;
  };
  const clearGlass = [makeClear(neighborTargets[0]!.texture), makeClear(neighborTargets[1]!.texture)];

  const glassAccent = new THREE.MeshPhysicalMaterial({
    color: new THREE.Color('#ffb592'),
    metalness: 0,
    roughness: 0.02,
    transmission: 0.95,
    thickness: 4,
    ior: 1.5,
    dispersion: 0.5,
    attenuationColor: new THREE.Color('#ff6a2b'),
    attenuationDistance: 5,
    envMapIntensity: 1.1,
    emissive: new THREE.Color('#ff5a1f'),
    emissiveIntensity: 0,
    side: THREE.DoubleSide,
  });
  withEdgeSpectrum(glassAccent, 0.35, neighborTargets[2]!.texture, 0.6);

  // ---- 玻璃後面的背景：與頁面底色相同，Logo 後方一團很淡的柔光（玻璃才有東西可以折射） ----
  const backCanvas = document.createElement('canvas');
  const backdropTex = new THREE.CanvasTexture(backCanvas);
  backdropTex.colorSpace = THREE.SRGBColorSpace;
  const backdrop = new THREE.Mesh(
    new THREE.PlaneGeometry(1, 1),
    new THREE.MeshBasicMaterial({ map: backdropTex, toneMapped: false }),
  );
  backdrop.position.z = -40;
  scene.add(backdrop);

  /** Logo 在畫布上的位置（0 ~ 1）與大小（佔畫布寬度的比例），resize 時更新 */
  const spot = { x: 0.5, y: 0.5, size: 0.4 };

  const paintBackdrop = () => {
    const dark = document.documentElement.dataset.theme === 'dark';
    const aspect = camera.aspect || 1;
    const W = aspect >= 1 ? 1024 : Math.round(1024 * aspect);
    const H = aspect >= 1 ? Math.round(1024 / aspect) : 1024;
    if (backCanvas.width !== W || backCanvas.height !== H) {
      backCanvas.width = W;
      backCanvas.height = H;
    }
    const ctx = backCanvas.getContext('2d')!;
    const css = getComputedStyle(document.documentElement);
    const bg = css.getPropertyValue('--bg').trim() || (dark ? '#0d0d0c' : '#f2f0eb');
    const accent = css.getPropertyValue('--accent').trim() || '#ff5a1f';
    ctx.globalAlpha = 1;
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, W, H);
    const R = spot.size * W;
    // 漸層要淡出到「同色、透明」，淡出到 transparent（黑色）會在周圍留下一圈灰
    const clear = (color: string) => {
      ctx.fillStyle = color;
      const hex = String(ctx.fillStyle);
      if (!hex.startsWith('#')) return 'rgba(255,255,255,0)';
      const n = parseInt(hex.slice(1), 16);
      return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},0)`;
    };
    const orb = (dx: number, dy: number, r: number, color: string, alpha: number) => {
      const x = spot.x * W + dx * R;
      const y = spot.y * H + dy * R;
      const g = ctx.createRadialGradient(x, y, 0, x, y, r * R);
      g.addColorStop(0, color);
      g.addColorStop(1, clear(color));
      ctx.globalAlpha = alpha;
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, W, H);
      ctx.globalAlpha = 1;
    };
    // 中性的底：只留一點點品牌色，玻璃才會是透明無色的
    orb(0.2, -0.16, 0.9, accent, dark ? 0.1 : 0.1);
    orb(0.05, -0.08, 0.62, '#ffffff', dark ? 0.09 : 0.3); // Logo 正後方的一盞柔光：透過玻璃被折射、錯位，看得出厚度
    // 深色：Logo 正後方幾團很淡、邊緣全糊的柔光，只有透過玻璃被折射時才看得出來（空白處不放光點）
    if (dark) {
      const glows: [number, number, number, number][] = [
        [-0.2, -0.2, 0.16, 0.035],
        [0.22, 0.05, 0.13, 0.04],
        [0.02, 0.3, 0.14, 0.03],
      ];
      for (const [bx, by, br, ba] of glows) {
        const x = spot.x * W + bx * R;
        const y = spot.y * H + by * R;
        const g = ctx.createRadialGradient(x, y, 0, x, y, br * R);
        g.addColorStop(0, 'rgba(255,255,255,1)');
        g.addColorStop(0.45, 'rgba(255,255,255,0.45)');
        g.addColorStop(1, 'rgba(255,255,255,0)');
        ctx.globalAlpha = ba;
        ctx.fillStyle = g;
        ctx.fillRect(x - br * R, y - br * R, br * R * 2, br * R * 2);
        ctx.globalAlpha = 1;
      }
    }
    // 地面陰影
    ctx.save();
    ctx.translate(spot.x * W, spot.y * H + R * 0.62);
    ctx.scale(1, 0.14);
    const sh = ctx.createRadialGradient(0, 0, 0, 0, 0, R * 0.55);
    sh.addColorStop(0, `rgba(0,0,0,${dark ? 0.65 : 0.14})`);
    sh.addColorStop(1, 'rgba(0,0,0,0)');
    ctx.fillStyle = sh;
    ctx.fillRect(-W, -H * 8, W * 2, H * 16);
    ctx.restore();
    backdropTex.needsUpdate = true;
  };

  let baseEnv = 1.2;
  let rainbowBase = 1;
  const applyTheme = () => {
    const dark = document.documentElement.dataset.theme === 'dark';
    paintBackdrop();
    // 淺色底上的清玻璃幾乎看不見：加一點冷灰色的厚度感，反光也稍強
    scene.environment = dark ? envs.dark : envs.light;
    inner.add.value = dark ? 0.55 : 0;
    inner.mix.value = dark ? 0 : 0.85;
    // 玻璃是雙面的：光線穿過正面與背面，顏色吸收算兩次，所以淺色模式的吸收距離加倍，顏色才和原本一樣
    for (const g of clearGlass) {
      g.attenuationColor.set(dark ? '#ffffff' : '#dde3ec');
      g.attenuationDistance = dark ? Infinity : 48;
    }
    glassAccent.attenuationDistance = dark ? 5 : 10;
    glassAccent.color.set(dark ? '#ffb592' : '#ffcab0');
    // 替身：深色時清玻璃的邊緣是亮的，淺色時是深色線條
    for (const m of standIns.slice(0, 2)) {
      m.uniforms.uColor.value.set(dark ? '#ffffff' : '#2a2d33');
      m.uniforms.uEdge.value = dark ? 0.8 : 0.55;
    }
    rainbowBase = dark ? 1 : 0.75;
    glassAccent.emissiveIntensity = dark ? 0.22 : 0.04;
    baseEnv = dark ? 1.2 : 1;
  };

  // ---- 三塊積木：大三角形、方塊的兩個半邊（各自獨立活動） ----
  const logo = new THREE.Group();
  scene.add(logo);

  const makeBody = (poly: V2[], mat: THREE.Material, dx: number, dy: number, shift = 0): Body => {
    const origin = centroid(poly);
    const base = new THREE.Vector3(...origin, 0);
    const obj = new THREE.Group();
    obj.add(new THREE.Mesh(extrude(poly, origin), mat));
    // 倒角把邊緣修圓後，縫隙看起來比平面版寬很多：組合時往大三角靠近一點
    base.x -= shift * Math.SQRT1_2;
    base.y += shift * Math.SQRT1_2;
    obj.position.copy(base);
    logo.add(obj);
    const pts = collisionPoints(poly, origin);
    return {
      obj,
      base,
      dir: new THREE.Vector2(dx, dy).normalize(),
      calm: false,
      seed: rand(0, 100),
      pos: new THREE.Vector3(),
      vel: new THREE.Vector3(),
      rot: new THREE.Vector3(),
      rvel: new THREE.Vector3(),
      tPos: new THREE.Vector3(),
      tRot: new THREE.Vector3(),
      held: false,
      grip: 0,
      pts,
      wpts: pts.map((p) => p.clone()),
    };
  };
  const bodies = [
    makeBody(TRI, clearGlass[0]!, -1, 1), // 大三角形往左上
    makeBody(SQ_INK, clearGlass[1]!, 1.3, -0.2, 1.1), // 方塊右上半往右
    makeBody(SQ_ACCENT, glassAccent, 0.2, -1.3, 1.1), // 方塊左下半（品牌橘）往下
  ];

  // 替身跟著各自的玻璃走；立方體相機放在每塊玻璃的中心，拍的時候先把自己的替身藏起來
  const standInMeshes = bodies.map((b, i) => {
    const m = new THREE.Mesh((b.obj.children[0] as THREE.Mesh).geometry, standIns[i]!);
    m.layers.set(NEIGHBOR_LAYER);
    b.obj.add(m);
    return m;
  });
  const cubeCams = neighborTargets.map((target) => {
    const cam = new THREE.CubeCamera(0.5, 300, target);
    for (const c of cam.children) c.layers.set(NEIGHBOR_LAYER);
    scene.add(cam);
    return cam;
  });
  const savedClear = new THREE.Color();
  let reflectTurn = 0;
  /** 更新反射：平常每一格輪一塊（三格一輪），第一次畫與減少動態時三塊一起 */
  const updateReflections = (all: boolean) => {
    const alpha = renderer.getClearAlpha();
    renderer.getClearColor(savedClear);
    renderer.setClearColor(0x000000, 0);
    const which = all ? bodies.map((_, i) => i) : [reflectTurn++ % bodies.length];
    for (const i of which) {
      standInMeshes[i]!.visible = false;
      bodies[i]!.obj.getWorldPosition(cubeCams[i]!.position);
      cubeCams[i]!.update(renderer, scene);
      standInMeshes[i]!.visible = true;
    }
    renderer.setClearColor(savedClear, alpha);
  };
  let framesDrawn = 0;

  // ---- 尺寸：Logo 的 32 單位方格剛好蓋在 stage 上 ----
  const anchor = new THREE.Vector3();
  const resize = () => {
    const w = canvas.clientWidth;
    const h = canvas.clientHeight;
    if (!w || !h) return;
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2, Math.sqrt(MAX_PIXELS / (w * h))));
    renderer.setSize(w, h, false);
    camera.aspect = w / h;

    const c = canvas.getBoundingClientRect();
    const r = stage.getBoundingClientRect();
    const unit = r.width > 0 ? r.width / 32 : Math.min(w, h) / 48; // 每單位幾 px
    camera.position.z = h / unit / 2 / tanHalf;
    const cx = r.left + r.width / 2 - c.left;
    const cy = r.top + r.height / 2 - c.top;
    anchor.set((cx - w / 2) / unit, (h / 2 - cy) / unit, 0);
    camera.updateProjectionMatrix();

    // 背景剛好填滿畫面，柔光跟著 Logo
    const dist = camera.position.z - backdrop.position.z;
    const vh = 2 * dist * tanHalf;
    backdrop.scale.set(vh * camera.aspect * 1.02, vh * 1.02, 1);
    spot.x = cx / w;
    spot.y = cy / h;
    spot.size = (r.width || w * 0.4) / w;
    paintBackdrop();
  };

  // ---- 散開、漫遊、組合 ----
  type Mode = 'apart' | 'together';
  let mode: Mode = 'apart';
  let modeUntil = 0;
  let retargetAt = 0;
  let forced = false; // 被捲動強制組合
  let arrived = false;
  let snapAt = -10;
  let loose = 1; // 1 = 散開時的自由漂浮，0 = 組合時鎖緊
  let assembleAt = -10;

  /** 沿各自的方向散開，再加上隨機的橫向、前後偏移與翻面 */
  const scatter = (b: Body, far = 1, calm = b.calm) => {
    if (b.held) return;
    const along = (calm ? rand(0.4, 1.2) : rand(2.2, 5.2)) * far;
    const across = calm ? rand(-0.6, 0.6) : rand(-3.2, 3.2);
    b.tPos.set(
      b.dir.x * along - b.dir.y * across,
      b.dir.y * along + b.dir.x * across,
      calm ? rand(-1, 1) : rand(-5, 5),
    );
    const flip = !calm && Math.random() < 0.5 ? Math.PI * (Math.random() < 0.5 ? 1 : -1) : 0;
    const onY = Math.random() < 0.6;
    const spread = calm ? 0.25 : 0.65;
    b.tRot.set(
      upright(b.rot.x) + rand(-spread, spread) + (onY ? 0 : flip),
      upright(b.rot.y) + rand(-spread, spread) + (onY ? flip : 0),
      upright(b.rot.z) + rand(-spread * 0.7, spread * 0.7),
    );
  };

  /** 漂浮中換個方向：位置往新的隨機點移一段，角度小幅改變，偶爾再翻一次面 */
  const wander = (b: Body) => {
    if (b.held) return;
    const prev = b.tPos.clone();
    scatter(b);
    b.tPos.lerp(prev, 0.35);
    b.tRot.set(
      b.tRot.x + rand(-0.35, 0.35),
      b.tRot.y + rand(-0.35, 0.35) + (Math.random() < 0.18 ? Math.PI : 0),
      b.tRot.z + rand(-0.25, 0.25),
    );
  };

  const gather = (b: Body) => {
    if (b.held) return;
    b.tPos.set(0, 0, 0);
    b.tRot.set(upright(b.rot.x, b.rvel.x), upright(b.rot.y, b.rvel.y), upright(b.rot.z, b.rvel.z));
  };

  const breakApart = (now: number) => {
    mode = 'apart';
    arrived = false;
    // 每一輪離開的組合都不同：全部散開、只走一塊、或走兩塊；留下的只微微晃動
    const r = Math.random();
    const leaving = r < 0.45 ? 3 : r < 0.75 ? 1 : 2;
    const order = [...bodies].sort(() => Math.random() - 0.5);
    order.forEach((b, i) => (b.calm = i >= leaving));
    bodies.forEach((b) => scatter(b));
    modeUntil = now + rand(6, 10.5);
    retargetAt = now + rand(1.4, 2.6);
  };

  const assemble = (now: number, hold: number) => {
    if (mode !== 'together') assembleAt = now;
    mode = 'together';
    bodies.forEach(gather);
    modeUntil = now + hold;
  };

  // 一開始三塊從遠處飛進來，稍後自己組合
  bodies.forEach((b) => {
    scatter(b, 1.3);
    b.pos.copy(b.tPos).multiplyScalar(1.2);
    b.rot.copy(b.tRot);
  });
  modeUntil = 2.4;
  retargetAt = 99;

  if (reduced) {
    mode = 'together';
    bodies.forEach((b) => {
      b.pos.set(0, 0, 0);
      b.rot.set(0, 0, 0);
    });
    loose = 0;
  }

  // ---- 視角：基本角度（看得到厚度）＋游標＋捲動干擾，用彈簧追，所以會晃一下再停 ----
  const view = new THREE.Vector3(-0.2, 0.32, 0);
  const viewVel = new THREE.Vector3();
  const viewTarget = new THREE.Vector3();

  // ---- 碰撞：撞到會彈開、被撞偏的一側會轉一下 ----
  const normal = new THREE.Vector3();
  const hitA = new THREE.Vector3();
  const hitB = new THREE.Vector3();
  const tmp = new THREE.Vector3();
  const spin = (b: Body, hit: THREE.Vector3, impulse: number) => {
    // 力矩 = 力臂 × 衝量；沒撞在重心上就會轉
    tmp.subVectors(hit, b.obj.position).cross(normal).multiplyScalar(impulse * 0.035);
    b.rvel.add(tmp);
  };
  const collide = (now: number) => {
    // 散開時一律會撞；自己組合的前 1.2 秒也會（捲動強制組合時直接穿過，才夠快）
    const on = mode === 'apart' || grabbed !== null || (!forced && now - assembleAt < 1.2);
    if (!on) return;
    for (const b of bodies) {
      b.obj.updateMatrix();
      b.pts.forEach((p, i) => b.wpts[i].copy(p).applyMatrix4(b.obj.matrix));
    }
    for (let i = 0; i < bodies.length; i++) {
      for (let j = i + 1; j < bodies.length; j++) {
        const A = bodies[i];
        const B = bodies[j];
        // 兩塊都在自己的位置上（本來就貼在一起）就不算
        if (A.pos.length() < 1.5 && B.pos.length() < 1.5) continue;
        let depth = 0;
        for (const pa of A.wpts) {
          for (const pb of B.wpts) {
            const d = pa.distanceTo(pb);
            const pen = COL_R * 2 - d;
            if (pen > depth) {
              depth = pen;
              normal.subVectors(pb, pa).divideScalar(d || 1);
              hitA.copy(pa);
              hitB.copy(pb);
            }
          }
        }
        if (depth <= 0) continue;
        // 被抓著的那塊像無限重：只有另一塊被推開
        const wA = A.held ? 0 : B.held ? 1 : 0.5;
        const wB = 1 - wA;
        // 推開到剛好不重疊
        tmp.copy(normal).multiplyScalar(depth);
        A.pos.addScaledVector(tmp, -wA);
        A.obj.position.addScaledVector(tmp, -wA);
        B.pos.addScaledVector(tmp, wB);
        B.obj.position.addScaledVector(tmp, wB);
        // 漂浮中的目標也跟著讓開，才不會一直互推
        if (mode === 'apart') {
          if (!A.held) A.tPos.addScaledVector(normal, -depth);
          if (!B.held) B.tPos.addScaledVector(normal, depth);
        }
        // 反彈：相對速度沿法線反向（彈性 0.7），再多給一點點彈開的力
        const approach = tmp.subVectors(B.vel, A.vel).dot(normal);
        if (approach < 0.2) {
          const impulse = -(1 + 0.7) * Math.min(approach, 0) + 1.6;
          A.vel.addScaledVector(normal, -impulse * wA);
          B.vel.addScaledVector(normal, impulse * wB);
          spin(A, hitA, -impulse * wA);
          spin(B, hitB, impulse * wB);
        }
      }
    }
  };

  // ---- 拖曳：抓住積木移動（會推開其他積木，放開後甩出去再自己回位）；拖空白處轉動整個 Logo ----
  const raycaster = new THREE.Raycaster();
  const ndc = new THREE.Vector2();
  const dragPlane = new THREE.Plane();
  const planeHit = new THREE.Vector3();
  const grabOffset = new THREE.Vector3();
  const camDir = new THREE.Vector3();
  const dragView = new THREE.Vector2();
  const dragVel = new THREE.Vector2();
  const holdRot = new THREE.Vector3();
  let grabbed: Body | null = null;
  let orbiting = false;
  let pointerId = -1;
  let downX = 0;
  let downY = 0;
  let downT = 0;
  let lastX = 0;
  let lastY = 0;
  let lastT = 0;
  let clock = 0;

  const aim = (e: PointerEvent) => {
    const r = canvas.getBoundingClientRect();
    ndc.set(((e.clientX - r.left) / r.width) * 2 - 1, -((e.clientY - r.top) / r.height) * 2 + 1);
    raycaster.setFromCamera(ndc, camera);
  };
  const pick = () => {
    const hit = raycaster.intersectObjects(
      bodies.map((b) => b.obj),
      true,
    )[0];
    if (!hit) return null;
    const body = bodies.find((b) => b.obj === hit.object.parent);
    return body ? { body, point: hit.point.clone() } : null;
  };

  const onDown = (e: PointerEvent) => {
    if (!playing || reduced || e.button !== 0 || pointerId !== -1) return;
    aim(e);
    const hit = pick();
    pointerId = e.pointerId;
    canvas.setPointerCapture(e.pointerId);
    downX = lastX = e.clientX;
    downY = lastY = e.clientY;
    downT = lastT = performance.now();
    dragVel.set(0, 0);
    if (hit) {
      grabbed = hit.body;
      grabbed.held = true;
      holdRot.copy(grabbed.rot);
      arrived = false; // 放回去的時候會再「喀」一下
      camera.getWorldDirection(camDir);
      dragPlane.setFromNormalAndCoplanarPoint(camDir.negate(), hit.point);
      grabOffset.copy(logo.worldToLocal(hit.point)).sub(grabbed.obj.position);
      canvas.style.cursor = 'grabbing';
    } else {
      orbiting = true;
    }
  };

  const onMove = (e: PointerEvent) => {
    const now = performance.now();
    if (e.pointerId === pointerId && grabbed) {
      aim(e);
      if (raycaster.ray.intersectPlane(dragPlane, planeHit)) {
        const local = logo.worldToLocal(planeHit).sub(grabOffset);
        grabbed.tPos.set(local.x - grabbed.base.x, local.y - grabbed.base.y, local.z - grabbed.base.z);
      }
    } else if (e.pointerId === pointerId && orbiting) {
      const dt = Math.max((now - lastT) / 1000, 1 / 120);
      const rx = (e.clientY - lastY) * 0.006;
      const ry = (e.clientX - lastX) * 0.008;
      dragView.x = THREE.MathUtils.clamp(dragView.x + rx, -1.2, 1.2);
      dragView.y += ry;
      dragVel.lerp(new THREE.Vector2(rx / dt, ry / dt), 0.5);
    } else if (pointerId === -1 && e.pointerType === 'mouse' && playing) {
      // 游標移到積木上時變成「抓」的手
      aim(e);
      canvas.style.cursor = pick() ? 'grab' : '';
    }
    lastX = e.clientX;
    lastY = e.clientY;
    lastT = now;
  };

  const onUp = (e: PointerEvent) => {
    if (e.pointerId !== pointerId) return;
    pointerId = -1;
    const tap = Math.hypot(e.clientX - downX, e.clientY - downY) < 6 && performance.now() - downT < 300;
    if (grabbed) {
      const b = grabbed;
      b.held = false;
      grabbed = null;
      if (tap) {
        // 點一下：被彈一下、轉一圈
        b.vel.add(new THREE.Vector3(rand(-5, 5), rand(5, 9), rand(3, 7)));
        b.rvel.add(new THREE.Vector3(rand(-7, 7), rand(-9, 9), rand(-3, 3)));
      }
      if (mode === 'together') {
        // 甩出去之後自己飛回來、貼齊
        gather(b);
        modeUntil = Math.max(modeUntil, clock + 2.5);
      } else {
        b.tRot.set(b.rot.x, b.rot.y, b.rot.z);
      }
    }
    if (orbiting && tap) dragVel.set(0, 0);
    orbiting = false;
    canvas.style.cursor = '';
  };

  if (!reduced) {
    canvas.addEventListener('pointerdown', onDown);
    canvas.addEventListener('pointermove', onMove);
    canvas.addEventListener('pointerup', onUp);
    canvas.addEventListener('pointercancel', onUp);
  }

  let t0 = performance.now();
  let last = t0;
  let raf = 0;
  let running = false;
  let playing = false;
  let visible = true;

  const render = () => {
    const ms = performance.now();
    const now = (ms - t0) / 1000;
    clock = now;
    const dt = Math.min((ms - last) / 1000, 1 / 30);
    last = ms;

    if (!reduced) {
      const sinceScroll = performance.now() - state.scrollAt;
      const scrolling = sinceScroll < 160;
      if (scrolling) {
        // 開始捲動：立刻組合，捲動期間一直保持
        if (!forced || mode !== 'together') assemble(now, 2.4);
        forced = true;
        modeUntil = Math.max(modeUntil, now + 2.4);
      }

      if (now > modeUntil) {
        if (mode === 'apart') {
          assemble(now, rand(2.2, 4));
        } else if (window.scrollY > innerHeight * 0.3) {
          // 已經往下看內容了：維持組合好的樣子
          modeUntil = now + 1;
        } else {
          forced = false;
          breakApart(now);
        }
      }
      if (mode === 'apart' && now > retargetAt) {
        bodies.forEach(wander);
        retargetAt = now + rand(1.6, 3.2);
      }

      // 彈簧：散開時鬆、慢、帶回彈；組合時越靠近吸得越緊（像磁鐵），捲動時最快
      for (const b of bodies) {
        let k: number;
        let zeta: number;
        let rk: number;
        if (b.held) {
          // 跟著游標走，但仍是彈簧，甩動時會有一點慣性與傾斜
          k = 160;
          zeta = 0.85;
          rk = 20;
          // 以抓起時的角度為準，只隨甩動的方向傾斜一點
          b.tRot.set(
            holdRot.x - THREE.MathUtils.clamp(b.vel.y * 0.02, -0.5, 0.5),
            holdRot.y + THREE.MathUtils.clamp(b.vel.x * 0.02, -0.5, 0.5),
            holdRot.z,
          );
        } else if (mode === 'apart') {
          k = 5.5;
          zeta = 0.42;
          rk = 5;
        } else {
          const d = b.pos.length();
          k = (forced ? 60 : 11) * (1 + 3 * Math.exp(-d * 0.8));
          zeta = 0.92;
          rk = forced ? 48 : 14;
        }
        spring(b.pos, b.vel, b.tPos, k, zeta, dt);
        spring(b.rot, b.rvel, b.tRot, rk, mode === 'apart' ? 0.5 : 0.8, dt);
        b.grip += ((b.held ? 1 : 0) - b.grip) * Math.min(dt * 8, 1);
      }

      // 貼齊的瞬間：彈一下、閃一下，角度歸零避免越轉越大
      if (mode === 'together' && !arrived) {
        const done = bodies.every(
          (b) => b.pos.length() < 0.08 && b.rot.distanceTo(b.tRot) < 0.03 && b.vel.length() < 1.5,
        );
        if (done) {
          arrived = true;
          snapAt = now;
          bodies.forEach((b) => {
            b.rot.sub(b.tRot);
            b.tRot.set(0, 0, 0);
          });
        }
      }
      loose += ((mode === 'apart' ? 1 : 0) - loose) * Math.min(dt * 2.5, 1);
    }

    // 套用到積木：彈簧位置＋散開時的漂浮
    for (const b of bodies) {
      const s = b.seed;
      const f = reduced ? 0 : loose * (1 - b.grip);
      b.obj.position.set(
        b.base.x + b.pos.x + (Math.sin(now * 0.71 + s) * 0.7 + Math.sin(now * 1.37 + s * 2) * 0.25) * f,
        b.base.y + b.pos.y + (Math.cos(now * 0.83 + s) * 0.7 + Math.sin(now * 1.19 + s * 3) * 0.25) * f,
        b.pos.z + Math.sin(now * 0.52 + s) * 1.2 * f,
      );
      b.obj.rotation.set(
        b.rot.x + Math.sin(now * 0.61 + s) * 0.1 * f,
        b.rot.y + Math.cos(now * 0.47 + s) * 0.12 * f,
        b.rot.z + Math.sin(now * 0.53 + s * 2) * 0.06 * f,
      );
    }
    if (!reduced) collide(now);

    // 視角
    if (reduced) {
      logo.rotation.set(view.x, view.y, 0);
    } else {
      const sv = performance.now() - state.scrollAt < 140 ? THREE.MathUtils.clamp(state.scrollV, -60, 60) : 0;
      // 拖曳空白處轉動：放開後帶著慣性再轉一下，然後慢慢轉回原本的角度（最近的整圈）
      if (!orbiting) {
        dragView.x += dragVel.x * dt;
        dragView.y += dragVel.y * dt;
        dragVel.multiplyScalar(Math.exp(-dt * 3.5));
        const homeY = Math.round(dragView.y / TAU) * TAU;
        const back = 1 - Math.exp(-dt * 1.3);
        dragView.x += (0 - dragView.x) * back;
        dragView.y += (homeY - dragView.y) * back;
      }
      viewTarget.set(
        -0.2 + state.my * 0.26 + sv * 0.012 + dragView.x,
        0.32 + state.mx * 0.36 + Math.sin(now * 0.3) * 0.08 + dragView.y,
        -state.mx * 0.04 + sv * 0.003,
      );
      spring(view, viewVel, viewTarget, orbiting ? 70 : 9, orbiting ? 0.9 : 0.45, dt);
      logo.rotation.set(view.x, view.y, view.z);
    }

    const since = now - snapAt;
    const pulse = since < 0.9 ? Math.exp(-since * 7) * Math.sin(since * 26) : 0;
    const intro = reduced ? 1 : easeOut(Math.min(now / 1.4, 1));
    logo.position.set(anchor.x, anchor.y + (reduced ? 0 : Math.sin(now * 0.9) * 0.35), 0);
    logo.scale.setScalar((1 + pulse * 0.035) * (0.88 + 0.12 * intro));

    // 貼齊瞬間反光變強
    const flash = Math.max(pulse, 0) * 2 + (since < 0.35 ? (0.35 - since) * 3 : 0);
    for (const g of clearGlass) g.envMapIntensity = baseEnv + flash;
    glassAccent.envMapIntensity = baseEnv - 0.1 + flash;
    rainbow.value = rainbowBase + flash * 0.4;

    updateReflections(reduced || framesDrawn++ < 3);
    renderer.render(scene, camera);
  };

  const loop = () => {
    render();
    if (running) raf = requestAnimationFrame(loop);
  };
  const start = () => {
    if (running || reduced || !playing || !visible) return;
    running = true;
    last = performance.now(); // 暫停期間的時間不算進彈簧
    raf = requestAnimationFrame(loop);
  };
  const stop = () => {
    running = false;
    cancelAnimationFrame(raf);
  };

  applyTheme();
  const themeObserver = new MutationObserver(() => {
    applyTheme();
    if (reduced) render();
  });
  themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });

  const ro = new ResizeObserver(() => {
    resize();
    if (reduced) render();
  });
  ro.observe(canvas);
  ro.observe(stage);
  resize();

  // 看不到的時候不畫
  const io = new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    if (visible) start();
    else stop();
  });
  io.observe(canvas);

  // 先在背景編譯 shader（支援的瀏覽器不會卡住畫面，載入動畫才不會頓），
  // 再畫出第一格；下一格畫面真的出現後才算準備好
  renderer
    .compileAsync(scene, camera)
    .catch(() => {
      /* 不支援就在第一次繪製時同步編譯 */
    })
    .then(() => {
      render();
      requestAnimationFrame(() => onReady?.());
    });

  return {
    play() {
      if (playing) return;
      playing = true;
      // 時間從這一刻重新算起，進場的飛入與第一次組合才會被看到
      t0 = performance.now();
      last = t0;
      if (reduced) render();
      else start();
    },
    dispose() {
      stop();
      io.disconnect();
      ro.disconnect();
      themeObserver.disconnect();
      renderer.dispose();
    },
  };
}
