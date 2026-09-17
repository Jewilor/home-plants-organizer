param([Parameter(Mandatory=$true)][string]$InputDoc, [Parameter(Mandatory=$true)][string]$OutputPdf)
$ErrorActionPreference='Stop'
$word=New-Object -ComObject Word.Application
$word.Visible=$false
$word.DisplayAlerts=0
try {
 $doc=$word.Documents.Open($InputDoc,$false,$true)
 try { $doc.ExportAsFixedFormat($OutputPdf,17) } finally { $doc.Close(0) }
} finally { $word.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($word) }
