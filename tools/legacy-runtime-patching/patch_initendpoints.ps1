$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$dllPath = "Client\BepInEx\plugins\XUnity.AutoTranslator\XUnity.AutoTranslator.Plugin.Core.dll"
$bytes = [System.IO.File]::ReadAllBytes($dllPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

$type = $assembly.MainModule.GetType("XUnity.AutoTranslator.Plugin.Core.TranslationManager")
$m = $type.Methods | Where-Object { $_.Name -eq "InitializeEndpoints" }

# In InitializeEndpoints, replace from 0x017D up to 0x020E with NOPs:
$noped = 0
for ($i = 0; $i -lt $m.Body.Instructions.Count; $i++) {
    $inst = $m.Body.Instructions[$i]
    if ($inst.Offset -ge 0x017D -and $inst.Offset -lt 0x020E) {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
        $inst.Operand = $null
        $noped++
    }
}

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($dllPath, $outMs.ToArray())
Write-Output ("Noped {0} instructions in TranslationManager.InitializeEndpoints!" -f $noped)
