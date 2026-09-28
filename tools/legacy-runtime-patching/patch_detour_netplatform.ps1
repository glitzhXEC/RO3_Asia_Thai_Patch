$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$detourPath = "Client\BepInEx\core\MonoMod.RuntimeDetour.dll"
$bytes = [System.IO.File]::ReadAllBytes($detourPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$ass = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

$netPlatform = $ass.MainModule.GetType("MonoMod.RuntimeDetour.Platforms.DetourRuntimeNETPlatform")
$ilPlatform = $ass.MainModule.GetType("MonoMod.RuntimeDetour.Platforms.DetourRuntimeILPlatform")
$gfpIl = $ilPlatform.Methods | Where-Object { $_.Name -eq "GetFunctionPointer" -and $_.Parameters.Count -eq 2 }

$m = $netPlatform.Methods | Where-Object { $_.Name -eq "GetFunctionPointer" }
$replaced = 0
foreach ($inst in $m.Body.Instructions) {
    if ($inst.Operand -is [Mono.Cecil.MethodReference] -and $inst.Operand.Name -eq "GetFunctionPointer") {
        # Redirect to DetourRuntimeILPlatform::GetFunctionPointer
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Call
        $inst.Operand = $gfpIl
        $replaced++
        Write-Host "Replaced GetFunctionPointer call in DetourRuntimeNETPlatform!"
        break
    }
}

if ($replaced -gt 0) {
    $outMs = New-Object System.IO.MemoryStream
    $ass.Write($outMs)
    [System.IO.File]::WriteAllBytes($detourPath, $outMs.ToArray())
    Write-Host "Successfully patched MonoMod.RuntimeDetour.dll NETPlatform!"
} else {
    Write-Host "No GetFunctionPointer call found to replace."
}
