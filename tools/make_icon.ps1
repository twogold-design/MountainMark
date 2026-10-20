Add-Type -AssemblyName System.Drawing
$iconBitmap = New-Object System.Drawing.Bitmap 256,256
$graphics = [System.Drawing.Graphics]::FromImage($iconBitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.ColorTranslator]::FromHtml('#172e34'))
$iconPen = New-Object System.Drawing.Pen ([System.Drawing.ColorTranslator]::FromHtml('#ecd9b0')),12
$iconPen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
$points = [System.Drawing.PointF[]]@([System.Drawing.PointF]::new(35,190),[System.Drawing.PointF]::new(102,67),[System.Drawing.PointF]::new(131,119),[System.Drawing.PointF]::new(156,77),[System.Drawing.PointF]::new(221,190))
$graphics.DrawLines($iconPen,$points)
$sunBrush=New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#eea568'))
$graphics.FillEllipse($sunBrush,184,41,26,26)
$memory=New-Object System.IO.MemoryStream
$iconBitmap.Save($memory,[System.Drawing.Imaging.ImageFormat]::Png)
$png=$memory.ToArray()
$stream=[System.IO.File]::Create((Join-Path (Get-Location) 'assets\icon.ico'))
$writer=New-Object System.IO.BinaryWriter($stream)
$writer.Write([UInt16]0); $writer.Write([UInt16]1); $writer.Write([UInt16]1)
$writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0); $writer.Write([byte]0)
$writer.Write([UInt16]1); $writer.Write([UInt16]32); $writer.Write([UInt32]$png.Length); $writer.Write([UInt32]22)
$writer.Write($png); $writer.Dispose(); $memory.Dispose(); $graphics.Dispose(); $iconBitmap.Dispose(); $iconPen.Dispose(); $sunBrush.Dispose()
