import 'dart:math' as math;
import 'dart:ui' show Color;

/// OKLCH → sRGB 颜色转换（CSS Color 4 规范）。
///
/// 设计稿 `pi-remote-app.html` 里所有颜色都写成 `oklch(L% C H)`，Flutter 没有这个
/// 色彩空间，所以在这里复刻规范定义的转换链：
///
/// ```
/// oklch ──▶ oklab ──▶ LMS' ──▶ linear sRGB ──▶ sRGB
///  (极坐标→直角)  (矩阵)     (矩阵)          (gamma 传递函数)
/// ```
///
/// 为什么不在 Dart 里直接写死算好的十六进制：设计稿靠着 60 多个颜色 token 表达
/// 「同一束光打在同一块软胶上」的层次，任何一个偏一点点，整套材质的凸凹关系就乱了。
/// 保持与设计稿同构的写法，改 token 时改的是同一个数字，不需要手算、也不会抄错。
///
/// [l] 明度 0..1（设计稿写 `93.5%` 就是 `0.935`）；
/// [c] 彩度，一般 0..0.4；
/// [h] 色相角，单位度；
/// [alpha] 透明度 0..1。
Color oklch(double l, double c, double h, [double alpha = 1.0]) {
  // 1) oklch → oklab：把极坐标 (C, H) 展成直角坐标 (a, b)
  final hr = h * math.pi / 180.0;
  final a = c * math.cos(hr);
  final b = c * math.sin(hr);

  // 2) oklab → LMS'：先得到立方根域的三个分量
  final lp = l + 0.3963377774 * a + 0.2158037573 * b;
  final mp = l - 0.1055613458 * a - 0.0638541728 * b;
  final sp = l - 0.0894841775 * a - 1.2914855480 * b;

  // 立方回线性域
  final l3 = lp * lp * lp;
  final m3 = mp * mp * mp;
  final s3 = sp * sp * sp;

  // 3) LMS → linear sRGB
  final rLin = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3;
  final gLin = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3;
  final bLin = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3;

  // 4) linear → sRGB（gamma 编码）后量化为 8 位
  return Color.fromARGB(
    (alpha.clamp(0.0, 1.0) * 255).round(),
    _encodeGamma(rLin),
    _encodeGamma(gLin),
    _encodeGamma(bLin),
  );
}

/// linear sRGB 分量 → 0..255 的 sRGB 值。
///
/// 超出 sRGB 色域的分量（oklch 能表示比 sRGB 更广的颜色）在这里被截断 ——
/// 设计稿本身挑选的色值都在 sRGB 内，截断只是兜底，避免出现 NaN 或溢出。
int _encodeGamma(double linear) {
  final v = linear <= 0.0031308
      ? 12.92 * linear
      : 1.055 * math.pow(linear.clamp(0.0, 1.0), 1 / 2.4) - 0.055;
  return (v.clamp(0.0, 1.0) * 255).round();
}
