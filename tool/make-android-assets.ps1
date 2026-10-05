# 从 tool/artwork 的两张原图生成 Android 的图标与启动遮罩。
#
# 原图是「圆角矩形磁贴 + 透明背景」——透明是抠出来的（微信传图会把透明区
# 烧成 243/255 的淡棋盘格，需要先用 DoG 找磁贴边界再裁成圆角矩形）。
# 所以裁剪框直接取磁贴边界，不再预留呼吸留白。
#
# 改图后重跑：
#   powershell -ExecutionPolicy Bypass -File tool/make-android-assets.ps1
#
# 一次跑完会产出四处，不需要任何手工步骤：
#   android/…/mipmap-*/ic_launcher.png            传统图标（方形，Android 7 及以下）
#   android/…/mipmap-*/ic_launcher_foreground.png 自适应前景（必须让开圆形蒙版）
#   android/…/drawable-nodpi/splash.png           系统启动遮罩（windowBackground）
#   assets/splash.png                             App 内遮罩（Flutter 首帧前的 _SplashOverlay）
# 并顺带把探测到的遮罩均色写回 values/colors.xml。
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

$tool   = $PSScriptRoot
$root   = Split-Path -Parent $tool
$res    = Join-Path $root 'android\app\src\main\res'
$art    = Join-Path $tool 'artwork'
$assets = Join-Path $root 'assets'

# 自适应前景里内容的占比。
#
# 限制来自磁贴的**角**：圆角矩形的角比圆形/圆角方形蒙版更“尖”，会先顶到。
#
# 两档参考蒙版（都是 108dp 画布里的中心可见区）：
#     圆形（Pixel 等）      可见圆直径 72dp，半径 36dp
#     圆角方（MuMu、三星等）可见区 72dp，圆角约 22%
#
# 角到中心的距离 = (a/2 - r)·√2 + r，其中 a = fill·108、r 为圆角半径。
# 磁贴圆角约占边长 9%（源图 120/1324）：
#     磁贴角 = fill·108·(0.5 - 0.09)·√2 + 0.09·fill·108 = 0.6697·fill·108
#     ⇒ 圆角方蒙版（角点 44.35dp）：fill ≤ 0.613
#     ⇒ 圆形蒙版（半径 36dp）：  fill ≤ 0.498
# 取 0.61 是因为目标环境是 MuMu 的圆角方蒙版：磁贴刚好顶住蒙版边缘。
# 代价：在圆形蒙版的桌面上磁贴四角会被削掉一小块（约 3dp），
# 想两边都兼容就把这里降到 0.49。
$adaptiveFill = 0.61

$iconSrc   = Join-Path $art 'icon_source.png'
$splashSrc = Join-Path $art 'splash_source.png'

# 图标裁剪框（像素，基于 1402×1403 的新版原图）。
#   磁贴边界：左 40 / 上 29 / 右 1361 / 下 1356（宽 1321 / 高 1327）
#   取正方 1324 居中，各边切掉一点磁贴的羽化边
#   圆角半径约 120px（占边长 9%，下面算自适应前景的 fill 时要用到）
$cropX = 38
$cropY = 30
$cropSide = 1324

function New-IconPng {
    param(
        [string]$Src, [string]$Dst,
        [int]$Canvas,
        [double]$Fill,      # 内容占画布的比例：传统图标=1.0，自适应前景=$adaptiveFill
        [int]$CropX, [int]$CropY, [int]$CropSide,
        [string]$Backdrop    # 垫底色（如 #D1F2E7）。不传则保留透明
    )
    $img = [System.Drawing.Image]::FromFile($Src)
    $bmp = New-Object System.Drawing.Bitmap $Canvas, $Canvas
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    if ($Backdrop) {
        $g.Clear([System.Drawing.ColorTranslator]::FromHtml($Backdrop))
    } else {
        $g.Clear([System.Drawing.Color]::Transparent)
    }

    $inner = [int][Math]::Round($Canvas * $Fill)
    $off = [int][Math]::Round(($Canvas - $inner) / 2)
    $dest = New-Object System.Drawing.Rectangle $off, $off, $inner, $inner
    $g.DrawImage($img, $dest, $CropX, $CropY, $CropSide, $CropSide,
                 [System.Drawing.GraphicsUnit]::Pixel)

    $dir = Split-Path -Parent $Dst
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $bmp.Save($Dst, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose(); $img.Dispose()
    Write-Output ("  {0}  {1}x{1}" -f (Split-Path -Leaf $Dst), $Canvas)
}

# dp → px（1x/1.5x/2x/3x/4x）
$plan = @(
    @{ d = 'mdpi';    legacy = 48;  adaptive = 108 },
    @{ d = 'hdpi';    legacy = 72;  adaptive = 162 },
    @{ d = 'xhdpi';   legacy = 96;  adaptive = 216 },
    @{ d = 'xxhdpi';  legacy = 144; adaptive = 324 },
    @{ d = 'xxxhdpi'; legacy = 192; adaptive = 432 }
)

Write-Output '传统图标 ic_launcher.png：'
foreach ($p in $plan) {
    New-IconPng -Src $iconSrc -Dst (Join-Path $res ("mipmap-{0}\ic_launcher.png" -f $p.d)) `
        -Canvas $p.legacy -Fill 1.0 -CropX $cropX -CropY $cropY -CropSide $cropSide `
        -Backdrop '#D1F2E7'   # 与 colors.xml 的 ic_launcher_background 一致

}

Write-Output ("自适应图标前景 ic_launcher_foreground.png（Fill={0}）：" -f $adaptiveFill)
foreach ($p in $plan) {
    New-IconPng -Src $iconSrc -Dst (Join-Path $res ("mipmap-{0}\ic_launcher_foreground.png" -f $p.d)) `
        -Canvas $p.adaptive -Fill $adaptiveFill -CropX $cropX -CropY $cropY -CropSide $cropSide
}

# 启动遮罩：缩到 1080 宽即可（窗口背景本来就按屏幕拉伸，再大只是白占体积）
$sp = [System.Drawing.Image]::FromFile($splashSrc)
$h = [int][Math]::Round($sp.Height * 1080.0 / $sp.Width)
$out = Join-Path $res 'drawable-nodpi\splash.png'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
$bmp = New-Object System.Drawing.Bitmap 1080, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($sp, 0, 0, 1080, $h)
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# App 内遮罩（assets/splash.png）：Flutter 侧用 BoxFit.fill 铺满整屏。
# 缩到 1/4 面积就够——1080p 屏上是 2 倍下采样看不出来，体积却小得多。
$inApp = Join-Path $assets 'splash.png'
New-Item -ItemType Directory -Force -Path $assets | Out-Null
$iw = 540
$ih = [int][Math]::Round($sp.Height * $iw / $sp.Width)
$bmp = New-Object System.Drawing.Bitmap $iw, $ih
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$g.DrawImage($sp, 0, 0, $iw, $ih)
$bmp.Save($inApp, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

# 取遮罩整体均色，供 windowBackground 兜底（拉伸留白时不会露出杂色）
$probe = New-Object System.Drawing.Bitmap 1, 1
$pg = [System.Drawing.Graphics]::FromImage($probe)
$pg.DrawImage($sp, 0, 0, 1, 1)
$mid = $probe.GetPixel(0, 0)
$pg.Dispose(); $probe.Dispose()
$sp.Dispose()

# 均色直接写回 colors.xml。以前是「脚本打印一个值、人工粘到另一个文件」，
# 换图后极易漏改，窗口兜底色就会跟遮罩对不上。
$hex = '{0}{1:X2}{2:X2}{3:X2}' -f '#', $mid.R, $mid.G, $mid.B
$colorsPath = Join-Path $res 'values\colors.xml'
$colorsText = [System.IO.File]::ReadAllText($colorsPath)
$colorsNew  = $colorsText -replace '(?<="splash_background">)#[0-9A-Fa-f]{6}(?=</color>)', $hex
if ($colorsNew -ne $colorsText) {
    # 无 BOM 写回：原文件就没 BOM，保持一致
    [System.IO.File]::WriteAllText($colorsPath, $colorsNew, (New-Object System.Text.UTF8Encoding $false))
    Write-Output ("已更新 colors.xml：splash_background → {0}" -f $hex)
} else {
    Write-Output ("colors.xml 的 splash_background 已是 {0}，无需改动" -f $hex)
}

Write-Output ''
Write-Output ("系统遮罩 drawable-nodpi\splash.png   1080x{0}" -f $h)
Write-Output ("App 内遮罩 assets\splash.png         {0}x{1}" -f $iw, $ih)
Write-Output ("遮罩整体均色 → {0}" -f $hex)
