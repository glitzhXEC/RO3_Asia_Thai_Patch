$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$dllPath = "Client\BepInEx\core\0Harmony.dll"
$bytes = [System.IO.File]::ReadAllBytes($dllPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

$type = $assembly.MainModule.GetType("HarmonyLib.AccessTools")
$cctor = $type.Methods | Where-Object { $_.Name -eq ".cctor" }

# Find fields:
$fNetFramework = $type.Fields | Where-Object { $_.Name -match "IsNetFrameworkRuntime" }
$fNetCore = $type.Fields | Where-Object { $_.Name -match "IsNetCoreRuntime" }

# In cctor, instructions from 0x0065 up to 0x00DA:
# We want to replace with:
# ldc.i4.0
# stsfld IsNetFrameworkRuntime
# ldc.i4.0
# stsfld IsNetCoreRuntime
# and nop the rest until 0x00DA

$startIdx = -1
$endIdx = -1
for ($i = 0; $i -lt $cctor.Body.Instructions.Count; $i++) {
    $inst = $cctor.Body.Instructions[$i]
    if ($inst.Offset -eq 0x0065) { $startIdx = $i }
    if ($inst.Offset -eq 0x00DA) { $endIdx = $i; break }
}

Write-Output ("Start index: {0}, End index: {1}" -f $startIdx, $endIdx)

$cctor.Body.Instructions[$startIdx].OpCode = [Mono.Cecil.Cil.OpCodes]::Ldc_I4_0
$cctor.Body.Instructions[$startIdx].Operand = $null

$cctor.Body.Instructions[$startIdx + 1].OpCode = [Mono.Cecil.Cil.OpCodes]::Stsfld
$cctor.Body.Instructions[$startIdx + 1].Operand = $fNetFramework

$cctor.Body.Instructions[$startIdx + 2].OpCode = [Mono.Cecil.Cil.OpCodes]::Ldc_I4_0
$cctor.Body.Instructions[$startIdx + 2].Operand = $null

$cctor.Body.Instructions[$startIdx + 3].OpCode = [Mono.Cecil.Cil.OpCodes]::Stsfld
$cctor.Body.Instructions[$startIdx + 3].Operand = $fNetCore

for ($i = $startIdx + 4; $i -lt $endIdx; $i++) {
    $cctor.Body.Instructions[$i].OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
    $cctor.Body.Instructions[$i].Operand = $null
}

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($dllPath, $outMs.ToArray())
Write-Output "Successfully patched RuntimeInformation in 0Harmony.dll!"
