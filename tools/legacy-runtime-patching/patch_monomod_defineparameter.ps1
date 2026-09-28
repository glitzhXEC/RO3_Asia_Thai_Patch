$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$dllPath = "Client\BepInEx\core\MonoMod.Utils.dll"
$bytes = [System.IO.File]::ReadAllBytes($dllPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

$type = $assembly.MainModule.GetType("MonoMod.Utils._DMDEmit")
$m = $type.Methods | Where-Object { $_.Name -eq "Generate" }

$noped = 0
for ($i = 0; $i -lt $m.Body.Instructions.Count; $i++) {
    $inst = $m.Body.Instructions[$i]
    # Nop out the DynamicMethod DefineParameter call and its arguments from 0x00AD to 0x00CA
    if ($inst.Offset -ge 0x00AD -and $inst.Offset -le 0x00CA) {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
        $inst.Operand = $null
        $noped++
    }
}

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($dllPath, $outMs.ToArray())
Write-Output ("Noped {0} instructions in _DMDEmit.Generate!" -f $noped)
