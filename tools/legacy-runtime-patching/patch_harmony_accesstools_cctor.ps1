$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$dllPath = "Client\BepInEx\core\0Harmony.dll"
$bytes = [System.IO.File]::ReadAllBytes($dllPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

$type = $assembly.MainModule.GetType("HarmonyLib.AccessTools")
$cctor = $type.Methods | Where-Object { $_.Name -eq ".cctor" }

for ($i = 0; $i -lt $cctor.Body.Instructions.Count; $i++) {
    $inst = $cctor.Body.Instructions[$i]
    if ($inst.Offset -eq 0x004B) {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldnull
        $inst.Operand = $null
    } elseif ($inst.Offset -eq 0x0050 -or $inst.Offset -eq 0x0051) {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
        $inst.Operand = $null
    }
}

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($dllPath, $outMs.ToArray())
Write-Output "Successfully patched AccessTools..cctor in 0Harmony.dll!"
