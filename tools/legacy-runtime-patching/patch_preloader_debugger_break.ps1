$preloaderPath = "Client\BepInEx\core\BepInEx.Preloader.dll"
$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$bytes = [System.IO.File]::ReadAllBytes($preloaderPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)
$type = $assembly.MainModule.GetType("BepInEx.Preloader.Patching.AssemblyPatcher")
$m = $type.Methods | Where-Object { $_.Name -eq "PatchAndLoad" }

$count = 0
foreach ($inst in $m.Body.Instructions) {
    if ($inst.Operand -ne $null -and $inst.Operand.ToString().Contains("Debugger::Break")) {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
        $inst.Operand = $null
        $count++
    }
}

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($preloaderPath, $outMs.ToArray())
Write-Output ("Patched {0} Debugger::Break call(s) in AssemblyPatcher.PatchAndLoad!" -f $count)
