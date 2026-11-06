
param(
    [string]$Ordner = (Get-Location).Path
)

$Ordner = (Resolve-Path -LiteralPath $Ordner).Path
$LaengsterPfad = $Ordner

Get-ChildItem -LiteralPath $Ordner -Recurse -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
        if ($_.FullName.Length -gt $LaengsterPfad.Length) {
            $LaengsterPfad = $_.FullName
        }
    }

Write-Host "`nLängster Pfad: $LaengsterPfad"
Write-Host "Pfadlänge: $($LaengsterPfad.Length) Zeichen"

if ($LaengsterPfad.Length -ge 260) {
    Write-Warning "Der Pfad erreicht oder überschreitet MAX_PATH (260 Zeichen)."
}
