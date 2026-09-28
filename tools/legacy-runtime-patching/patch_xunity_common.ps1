Add-Type -Path 'Client\BepInEx\core\Mono.Cecil.dll'

$targetPath = 'Client\BepInEx\core\XUnity.Common.dll'
$asm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($targetPath)

$count = 0
foreach ($t in $asm.MainModule.GetTypes()) {
    $toRemove = @()
    foreach ($ca in $t.CustomAttributes) {
        if ($ca.AttributeType.FullName -eq 'System.Diagnostics.DebuggerTypeProxyAttribute') {
            $toRemove += $ca
        }
    }
    foreach ($ca in $toRemove) {
        $t.CustomAttributes.Remove($ca)
        Write-Host "Removed DebuggerTypeProxyAttribute from $($t.FullName)"
        $count++
    }
}

Write-Host "Total removed attributes: $count"

$tempPath = 'Client\BepInEx\core\XUnity.Common.tmp.dll'
$asm.Write($tempPath)
$asm.Dispose()

Move-Item -Path $tempPath -Destination $targetPath -Force
Write-Host "Saved patched XUnity.Common.dll successfully."
