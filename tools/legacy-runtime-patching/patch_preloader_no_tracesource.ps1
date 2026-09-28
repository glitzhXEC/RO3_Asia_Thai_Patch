$preloaderPath = "C:\Path\To\RO3 Asia Launcher\Client\BepInEx\core\BepInEx.Preloader.dll"
$cecilBytes = [System.IO.File]::ReadAllBytes("C:\Path\To\RO3 Asia Launcher\Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null
$bytes = [System.IO.File]::ReadAllBytes($preloaderPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)
$type = $assembly.MainModule.GetType("BepInEx.Preloader.Preloader")
$run = $type.Methods | Where-Object { $_.Name -eq "Run" }

for ($i = 0; $i -lt $run.Body.Instructions.Count; $i++) {
    $ins = $run.Body.Instructions[$i]
    if ($ins.Offset -ge 0x0035 -and $ins.Offset -le 0x003F) {
        $ins.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
        $ins.Operand = $null
        Write-Output "Noped: $($ins.Offset)"
    }
}

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($preloaderPath, $outMs.ToArray())
Write-Output "Patched out LogSource Add successfully!"