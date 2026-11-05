# Atelier's own images, drawn with GDI+ (System.Drawing, part of Windows): the achievement
# progress. Text is set in the theme's Atelier Caps, loaded from its font file, as
# outlines filled with anti-aliasing, the way an SVG renderer draws it. The images carry
# a marker in a PNG text chunk right after the header, which tells them apart from the
# user's own and saves drawing them again when nothing changed.

. ([IO.Path]::Combine($PSScriptRoot, 'base.ps1'))
Add-Type -AssemblyName System.Drawing

$ImagesFontFile = [IO.Path]::Combine($AtelierTheme, 'core', 'fonts', 'AtelierCaps-Medium.ttf')
$ImagesCache = @{}

function Get-ImageFont {
  if (-not $ImagesCache.fonts) {
    $fonts = [Drawing.Text.PrivateFontCollection]::new()
    $fonts.AddFontFile($ImagesFontFile)
    $ImagesCache.fonts = $fonts
  }
  return $ImagesCache.fonts.Families[0]
}

function New-Canvas([int]$width, [int]$height) {
  $bitmap = [Drawing.Bitmap]::new($width, $height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [Drawing.Graphics]::FromImage($bitmap)
  $g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.CompositingQuality = [Drawing.Drawing2D.CompositingQuality]::HighQuality
  $g.Clear([Drawing.Color]::Transparent)
  return @{ bitmap = $bitmap; g = $g }
}

# The outline of a line of text with its baseline at y, starting at x, ending at x
# (end) or centred on it (middle), as SVG's text-anchor places it
function New-TextPath([string]$text, [double]$size, [double]$x, [double]$y, [string]$anchor = 'start') {
  $family = Get-ImageFont
  $style = [Drawing.FontStyle]::Regular
  $ascent = $size * $family.GetCellAscent($style) / $family.GetEmHeight($style)
  if ($anchor -ne 'start') {
    $advance = Measure-TextAdvance $text $size
    $x -= if ($anchor -eq 'end') { $advance } else { $advance / 2 }
  }
  # Filled by the nonzero rule, as SVG fills it: the outlines of a glyph may overlap
  $path = [Drawing.Drawing2D.GraphicsPath]::new([Drawing.Drawing2D.FillMode]::Winding)
  $path.AddString($text, $family, [int]$style, [single]$size, [Drawing.PointF]::new([single]$x, [single]($y - $ascent)), [Drawing.StringFormat]::GenericTypographic)
  return $path
}

# How far a line of text advances, and how far its ink reaches, from where it starts
function Measure-TextAdvance([string]$text, [double]$size) {
  $font = [Drawing.Font]::new((Get-ImageFont), [single]$size, [Drawing.FontStyle]::Regular, [Drawing.GraphicsUnit]::Pixel)
  $probe = [Drawing.Bitmap]::new(1, 1)
  $g = [Drawing.Graphics]::FromImage($probe)
  $g.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAlias
  try {
    return [double]$g.MeasureString($text, $font, [Drawing.PointF]::Empty, [Drawing.StringFormat]::GenericTypographic).Width
  } finally {
    $g.Dispose()
    $probe.Dispose()
    $font.Dispose()
  }
}
function Measure-TextInk([string]$text, [double]$size) {
  $path = New-TextPath $text $size 0 $size
  try {
    $path.Flatten()
    return $path.GetBounds()
  } finally {
    $path.Dispose()
  }
}

# The PNG bytes of a canvas, with a marker in a tEXt chunk after the header
function ConvertTo-MarkedPng($canvas, [string]$marker) {
  $stream = [IO.MemoryStream]::new()
  $canvas.bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
  $png = $stream.ToArray()
  $data = [Text.Encoding]::GetEncoding(28591).GetBytes("Software`0$marker")
  $chunk = [byte[]]::new(12 + $data.Length)
  $length = [BitConverter]::GetBytes([uint32]$data.Length)
  [Array]::Reverse($length)
  [Array]::Copy($length, 0, $chunk, 0, 4)
  [Array]::Copy([Text.Encoding]::ASCII.GetBytes('tEXt'), 0, $chunk, 4, 4)
  [Array]::Copy($data, 0, $chunk, 8, $data.Length)
  $crc = [BitConverter]::GetBytes([Atelier.Crc]::Compute($chunk, 4, 4 + $data.Length, 0))
  [Array]::Reverse($crc)
  [Array]::Copy($crc, 0, $chunk, 8 + $data.Length, 4)
  $out = [byte[]]::new($png.Length + $chunk.Length)
  [Array]::Copy($png, 0, $out, 0, 33)
  [Array]::Copy($chunk, 0, $out, 33, $chunk.Length)
  [Array]::Copy($png, 33, $out, 33 + $chunk.Length, $png.Length - 33)
  return , $out
}

# The start of a file as text, to find a marker in
function Read-FileHead([string]$file, [int]$bytes) {
  try {
    $f = [IO.File]::OpenRead($file)
    try {
      $head = [byte[]]::new($bytes)
      $n = $f.Read($head, 0, $bytes)
      return [Text.Encoding]::GetEncoding(28591).GetString($head, 0, $n)
    } finally {
      $f.Dispose()
    }
  } catch {
    return ''
  }
}

function Close-Canvas($canvas) {
  $canvas.g.Dispose()
  $canvas.bitmap.Dispose()
}
