//
// Xena 的 3D 水珠：studiox.tw 的 Xena 介紹頁（studio_website 的 src/scripts/orb3d.ts）同一段著色器，
// 從 WebGL 搬到 Metal（SwiftUI 的 colorEffect）。一顆清澈的水珠：
//   - 外形像失重漂浮的水珠：只有很低頻的起伏；說話時晃得大一點，表面多一層細小的漣漪
//   - 後面的底色透過水珠被放大、越靠邊緣彎得越厲害（紅綠藍稍微錯開成很淡的彩虹邊）
//   - 中間一團會發光、會旋轉的彩色光核；左上一扇柔和的窗光；底下一圈會呼吸的淡淡光暈
// 網頁版會把水珠後面的頁面畫成貼圖；App 裡水珠後面就是底色加上 Xena 的光（XenaOrb.swift 的 XenaLight），
// 這裡直接算出同一個樣子（backdrop），折射過去的顏色和外面接得起來。
// 動態（能量、各種相位）由 XenaOrb.swift 的 OrbMotion 算好傳進來；這裡只負責畫。
//
#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// 頁面在水珠後面多遠（水珠半徑 = 1）：水珠貼著頁面
constant float PLANE = 1.0;
// 比真的水（1.33）弱一點：中間放大約 1.5 倍，像一滴水放在螢幕上
constant float IOR = 1.2;

namespace xena {

struct Orb {
    float time;
    float morph;
    float swirl;
    float flow;
    float energy;
    float breath;
    float grow;
    float k;
    float halo;
    float haloScale;
    float2 stretch;
    float3 bg;
    /// Xena 的光的半徑（畫布半寬的幾倍）；0 = 沒有
    float light;
};

float2x2 rot(float a) {
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

// 外形：很低頻的起伏——整顆慢慢拉成一點橢圓再換個方向；說話時多一層細小漣漪
float radiusAt(float3 d, Orb o) {
    float m = o.morph;
    float3 A = normalize(float3(sin(m * 0.71), cos(m * 0.53), sin(m * 0.37 + 1.0)));
    float3 B = normalize(float3(cos(m * 0.43 + 2.0), sin(m * 0.61 + 0.5), cos(m * 0.57)));
    float a = dot(d, A);
    float b = dot(d, B);
    float r = 1.0 + mix(0.04, 0.07, o.energy) * (0.85 + 0.3 * o.breath) * (a * a - 0.333);
    r += mix(0.01, 0.028, o.energy) * (b * b * b - 0.6 * b);
    r += o.energy * 0.007 * sin(dot(d, float3(6.0, 4.5, 3.0)) + o.time * 7.0);
    return r;
}

// 出場時整顆從一個點長出來（grow 0 → 1，中間會稍微超過一點再彈回來）
float sdf(float3 p, Orb o) {
    float g = max(o.grow, 0.02);
    p /= g;
    p.x /= o.stretch.x;
    p.y /= o.stretch.y;
    float l = length(p);
    return (l - radiusAt(p / max(l, 0.0001), o)) * 0.9 * g;
}

float3 normalAt(float3 p, Orb o) {
    const float h = 0.002;
    const float2 k = float2(1.0, -1.0);
    return normalize(k.xyy * sdf(p + k.xyy * h, o) + k.yyx * sdf(p + k.yyx * h, o) +
                     k.yxy * sdf(p + k.yxy * h, o) + k.xxx * sdf(p + k.xxx * h, o));
}

// 四周：跟著底色，上方較亮、下方較暗；左上一扇大而柔的窗光
float3 env(float3 d, Orb o) {
    float3 col = mix(o.bg * 0.55, o.bg, smoothstep(-0.7, 0.0, d.y));
    col = mix(col, mix(o.bg, float3(1.0), 0.7), smoothstep(0.0, 0.8, d.y));
    float3 L = normalize(float3(-0.55, 0.68, 0.45));
    float3 r = normalize(cross(float3(0.0, 1.0, 0.0), L));
    float3 u = cross(L, r);
    float c = dot(d, L);
    float2 q = float2(dot(d, r), dot(d, u)) / max(c, 0.05) / float2(0.7, 0.46);
    col += 10.0 * (1.0 - smoothstep(0.1, 1.0, length(q))) * step(0.0, c);
    // 說話時：背後一道光繞著邊緣跑
    float3 sw = normalize(float3(cos(o.flow) * 0.62, sin(o.flow) * 0.62, -0.78));
    col += mix(0.5, 2.6, o.energy) * pow(max(dot(d, sw), 0.0), 14.0) * float3(1.0, 0.78, 0.95);
    return col;
}

// 水珠下面那圈會呼吸的光暈：亮在水珠邊緣底下、中間是空的（透過水珠看，邊緣帶顏色、中間清澈）
float4 glow(float2 w, Orb o) {
    float r = length(w) / (o.haloScale * max(o.grow, 0.05));
    float3 col = mix(float3(1.0, 0.53, 0.84), float3(0.55, 0.42, 1.0), smoothstep(0.5, 1.0, r));
    col = mix(col, float3(0.38, 0.81, 1.0), smoothstep(1.0, 1.5, r));
    float x = (r - 0.95) / 0.48;
    return float4(col, o.halo * 0.22 * exp(-x * x) * clamp(o.grow, 0.0, 1.0));
}

// 水珠後面：底色＋ Xena 的光（和 XenaLight 同一組顏色：紫 → 粉 → 透明，畫布座標）
float3 backdrop(float2 uv, Orb o) {
    float3 c = o.bg;
    if (o.light <= 0.0) return c;
    float d = length(uv) / o.light;
    const float3 purple = float3(132.0, 92.0, 255.0) / 255.0;
    const float3 pink = float3(255.0, 107.0, 209.0) / 255.0;
    float t = clamp(d / 0.45, 0.0, 1.0);
    float3 col = mix(purple, pink, t);
    float a = d < 0.45 ? mix(0.2, 0.07, t) : mix(0.07, 0.0, clamp((d - 0.45) / 0.25, 0.0, 1.0));
    return mix(c, col, a);
}

// 光線穿出水珠後打到後面的哪一點（碰不到的當成看向很遠的地方）
float3 page(float3 p, float3 dir, Orb o) {
    if (dir.z > -0.08) dir = normalize(float3(dir.xy, -0.08));
    float3 h = p + dir * ((-PLANE - p.z) / dir.z);
    float2 uv = h.xy / (o.k * (4.0 + PLANE));
    float3 c = backdrop(uv, o);
    float4 g = glow(h.xy, o);
    return mix(c, g.rgb, g.a);
}

// 中間發光的彩色光核：四團顏色在裡面旋轉、被扭成漩渦
float4 core(float3 p, Orb o) {
    const float R = 0.78;
    float3 q = p / R;
    q.xz = rot(o.swirl) * q.xz;
    q.xy = rot(o.swirl * 0.37 + 0.4) * q.xy;
    q += 0.22 * sin(q.yzx * 2.6 + o.morph * float3(0.9, 1.1, 0.7));
    const float ss = 1.0 / (0.46 * 0.46);
    float3 d1 = q - float3(-0.42, 0.34, 0.12);
    float3 d2 = q - float3(0.44, 0.3, -0.14);
    float3 d3 = q - float3(0.36, -0.42, 0.16);
    float3 d4 = q - float3(-0.38, -0.4, -0.12);
    float w1 = exp(-dot(d1, d1) * ss);
    float w2 = exp(-dot(d2, d2) * ss);
    float w3 = exp(-dot(d3, d3) * ss);
    float w4 = exp(-dot(d4, d4) * ss);
    float body = 1.0 - smoothstep(0.25, 1.0, length(p) / R);
    float wisp = 0.72 + 0.28 * sin(q.x * 5.0 + q.y * 4.0 + o.morph * 1.3) * sin(q.z * 4.5 - o.morph);
    float3 col = float3(1.0, 0.42, 0.82) * w1 + float3(0.25, 0.8, 1.0) * w2 + float3(1.0, 0.6, 0.25) * w3 +
                 float3(0.52, 0.36, 1.0) * w4 + float3(0.8, 0.62, 1.0) * 0.12;
    return float4(col, body * wisp);
}

float hash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

} // namespace xena

using namespace xena;

/// size：畫布（點）；phase：time、morph、swirl、flow；state：energy、breath、grow、halo；
/// shape：stretch x、stretch y、haloScale、Xena 的光的半徑；bg：底色；scale：螢幕的倍率
[[ stitchable ]] half4 xenaOrb(float2 position, half4 color, float2 size, float4 phase, float4 state, float4 shape,
                               half4 bg, float scale) {
    Orb o;
    o.time = phase.x;
    o.morph = phase.y;
    o.swirl = phase.z;
    o.flow = phase.w;
    o.energy = state.x;
    o.breath = state.y;
    o.grow = state.z;
    o.halo = state.w;
    o.stretch = shape.xy;
    o.haloScale = shape.z;
    o.light = shape.w;
    o.bg = float3(bg.rgb);
    // 畫布是水珠框的 1.8 倍：水珠的輪廓剛好佔框的 94%
    o.k = tan(asin(0.25)) / (0.94 / 1.8);

    // 畫布上的點 → -1…1（y 往上，和 WebGL 一樣）
    float2 uv = float2(position.x / size.x * 2.0 - 1.0, 1.0 - position.y / size.y * 2.0);
    float2 px2 = position * scale;
    float3 ro = float3(0.0, 0.0, 4.0);
    float3 rd = normalize(float3(uv * o.k, -1.0));

    // 水珠外面：只有光暈
    float4 g = glow(uv * o.k * (4.0 + PLANE), o);
    float4 outside = float4(g.rgb * g.a, g.a);
    float b = dot(ro, rd);
    float BR = 1.3 * max(o.grow, 1.0);
    float h = b * b - dot(ro, ro) + BR * BR;
    if (h < 0.0) return half4(outside);
    float t = -b - sqrt(h);
    float tEnd = -b + sqrt(h);
    float m = 1e9;
    float tm = t;
    bool hit = false;
    for (int i = 0; i < 32; i++) {
        float d = sdf(ro + rd * t, o);
        if (d < m) { m = d; tm = t; }
        if (d < 0.0006) { hit = true; break; }
        t += max(d, 0.003);
        if (t > tEnd) break;
    }
    // 邊緣抗鋸齒：沒打中但很接近的像素給部分覆蓋
    float pxw = 1.3 * 8.0 * o.k / max(size.y * scale, 1.0);
    float cover = hit ? 1.0 : 1.0 - smoothstep(0.0, pxw, m);
    if (cover <= 0.0) return half4(outside);

    float3 p = ro + rd * (hit ? t : tm);
    float3 n = normalAt(p, o);
    float cosT = clamp(dot(n, -rd), 0.0, 1.0);
    float F = 0.04 + 0.96 * pow(1.0 - cosT, 5.0);

    // 進入水珠，找到另一側的出口
    float3 ri = refract(rd, n, 1.0 / IOR);
    float bb = dot(p, ri);
    float tx = -bb + sqrt(max(bb * bb - dot(p, p) + o.grow * o.grow, 0.0));
    for (int k = 0; k < 3; k++) {
        float3 e = p + ri * tx;
        tx -= sdf(e, o) / 0.9 / max(dot(normalize(e), ri), 0.2);
    }
    float3 e = p + ri * tx;
    float3 ne = normalAt(e, o);

    // 穿出來打到後面；紅、綠、藍折射得稍微不一樣
    float3 o1 = refract(ri, -ne, IOR - 0.005);
    float3 o2 = refract(ri, -ne, IOR);
    float3 o3 = refract(ri, -ne, IOR + 0.006);
    float3 tir = page(e, reflect(ri, -ne), o);
    float3 back;
    back.r = dot(o1, o1) > 0.0 ? page(e, o1, o).r : tir.r;
    back.g = dot(o2, o2) > 0.0 ? page(e, o2, o).g : tir.g;
    back.b = dot(o3, o3) > 0.0 ? page(e, o3, o).b : tir.b;

    // 光核：在水裡發光（深色底上看得到光），也把後面染上顏色（淺色底上看得到顏色）
    float dt = tx / 16.0;
    float bright = 3.4 * (1.0 + 0.35 * o.energy) * (0.9 + 0.2 * o.breath);
    float3 acc = float3(0.0);
    float T = 1.0;
    float j = hash(px2) * 0.6;
    for (int i = 0; i < 16; i++) {
        float4 c = core((p + ri * ((float(i) + 0.2 + j) * dt)) / max(o.grow, 0.02), o);
        acc += T * c.rgb * c.a * bright * dt;
        T *= exp(-c.a * 2.6 * dt);
    }
    acc = 1.0 - exp(-acc);
    float cz = pow(max(dot(normalize(e), normalize(float3(0.42, -0.82, -0.3))), 0.0), 6.0);
    float dark = 1.0 - dot(o.bg, float3(0.3, 0.59, 0.11));
    float3 hue = acc / max(max(acc.r, acc.g), max(acc.b, 0.001));
    float3 inside = back * mix(float3(1.0), hue, (1.0 - T) * 0.85) + acc * mix(0.3, 1.0, dark) +
                    float3(1.0, 0.85, 0.95) * cz * 0.3;

    // 表面反射：越靠邊緣越像鏡子，邊緣帶一點彩虹色
    float3 refl = env(reflect(rd, n), o);
    float3 ir = 0.5 + 0.5 * cos(6.2831 * (float3(0.0, 0.33, 0.67) + cosT * 1.4 + o.time * 0.02));
    refl *= mix(float3(1.0), 0.6 + 0.8 * ir, 0.25 * (1.0 - cosT));
    float3 rgb = mix(inside, refl, F);

    rgb += (hash(px2.yx) - 0.5) / 255.0;
    float4 out = float4(clamp(rgb, 0.0, 1.0), 1.0) * cover + outside * (1.0 - cover);
    return half4(out);
}
