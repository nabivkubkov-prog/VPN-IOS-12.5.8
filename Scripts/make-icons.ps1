$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path -Parent $PSScriptRoot
$iconRoot = Join-Path $projectRoot 'App/Assets.xcassets/AppIcon.appiconset'
New-Item -ItemType Directory -Path $iconRoot -Force | Out-Null
$master = New-Object System.Drawing.Bitmap(1024,1024)
$graphics = [Drawing.Graphics]::FromImage($master)
$graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([Drawing.Color]::FromArgb(10,12,22))
$background = New-Object Drawing.Drawing2D.LinearGradientBrush([Drawing.Point]::new(0,0),[Drawing.Point]::new(1024,1024),[Drawing.Color]::FromArgb(40,30,68),[Drawing.Color]::FromArgb(11,14,23))
$graphics.FillRectangle($background,0,0,1024,1024)
$ringBrush = New-Object Drawing.Drawing2D.LinearGradientBrush([Drawing.Point]::new(250,250),[Drawing.Point]::new(800,800),[Drawing.Color]::FromArgb(166,122,255),[Drawing.Color]::FromArgb(100,237,201))
$pen = New-Object Drawing.Pen($ringBrush,30)
$pen.StartCap = [Drawing.Drawing2D.LineCap]::Round
$pen.EndCap = [Drawing.Drawing2D.LineCap]::Round
$graphics.DrawArc($pen,255,285,514,514,305,290)
$graphics.DrawLine($pen,512,214,512,485)
$entries = @(@{size=20;scale=2},@{size=20;scale=3},@{size=29;scale=2},@{size=29;scale=3},@{size=40;scale=2},@{size=40;scale=3},@{size=60;scale=2},@{size=60;scale=3},@{size=1024;scale=1})
$images = @()
foreach ($entry in $entries) {
    $pixels = $entry.size * $entry.scale
    $filename = "icon-$($entry.size)@$($entry.scale)x.png"
    $image = New-Object Drawing.Bitmap($pixels,$pixels)
    $canvas = [Drawing.Graphics]::FromImage($image)
    $canvas.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $canvas.DrawImage($master,0,0,$pixels,$pixels)
    $image.Save((Join-Path $iconRoot $filename),[Drawing.Imaging.ImageFormat]::Png)
    $canvas.Dispose(); $image.Dispose()
    $idiom = if ($entry.size -eq 1024) {'ios-marketing'} else {'iphone'}
    $images += @{idiom=$idiom;size="$($entry.size)x$($entry.size)";scale="$($entry.scale)x";filename=$filename}
}
$json = @{images=$images;info=@{version=1;author='xcode'}} | ConvertTo-Json -Depth 4
[IO.File]::WriteAllText((Join-Path $iconRoot 'Contents.json'),$json,[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $projectRoot 'App/Assets.xcassets/Contents.json'),'{"info":{"version":1,"author":"xcode"}}',[Text.UTF8Encoding]::new($false))
$pen.Dispose(); $ringBrush.Dispose(); $background.Dispose(); $graphics.Dispose(); $master.Dispose()
Write-Output 'App icons created (40–1024 px).'

