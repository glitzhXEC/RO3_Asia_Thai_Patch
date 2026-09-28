$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$bytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\BepInEx.dll")
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

$type = $assembly.MainModule.GetType("BepInEx.Bootstrap.Chainloader")
$m = $type.Methods | Where-Object { $_.Name -eq "Initialize" }

$noped = 0
for ($i = 0; $i -lt $m.Body.Instructions.Count; $i++) {
    $inst = $m.Body.Instructions[$i]
    if ($inst.Offset -ge 0x0079 -and $inst.Offset -le 0x008A) {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
        $inst.Operand = $null
        $noped++
    }
}

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes("Client\BepInEx\core\BepInEx.dll", $outMs.ToArray())
Write-Output ("Noped {0} instructions in Chainloader.Initialize" -f $noped)
