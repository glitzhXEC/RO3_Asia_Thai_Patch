$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$dllPath = "Client\BepInEx\plugins\XUnity.AutoTranslator\XUnity.AutoTranslator.Plugin.Core.dll"
$bytes = [System.IO.File]::ReadAllBytes($dllPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

$type = $assembly.MainModule.GetType("XUnity.AutoTranslator.Plugin.Core.Configuration.Settings")
$m = $type.Methods | Where-Object { $_.Name -eq "Configure" }

# In Configure, we want to replace from IL_0032 to IL_007C:
# We will set:
# ldstr "ro3"
# stsfld Settings::ApplicationName
# and nop the rest until 0x007E

$appNameField = $type.Fields | Where-Object { $_.Name -eq "ApplicationName" }

$startInst = $null
$endInst = $null

for ($i = 0; $i -lt $m.Body.Instructions.Count; $i++) {
    $inst = $m.Body.Instructions[$i]
    if ($inst.Offset -eq 0x0032) {
        $startInst = $i
    }
    if ($inst.Offset -eq 0x007E) {
        $endInst = $i
        break
    }
}

Write-Output ("Start index: {0}, End index: {1}" -f $startInst, $endInst)

# Clear exception handlers that cover this range
$handlersToRemove = @()
foreach ($handler in $m.Body.ExceptionHandlers) {
    if ($handler.TryStart.Offset -ge 0x0032 -and $handler.HandlerEnd.Offset -le 0x0080) {
        $handlersToRemove += $handler
    }
}
foreach ($h in $handlersToRemove) {
    $m.Body.ExceptionHandlers.Remove($h)
    Write-Output "Removed try-catch handler around ApplicationName"
}

# Replace startInst with ldstr "ro3"
$m.Body.Instructions[$startInst].OpCode = [Mono.Cecil.Cil.OpCodes]::Ldstr
$m.Body.Instructions[$startInst].Operand = "ro3"

# Replace startInst + 1 with stsfld ApplicationName
$m.Body.Instructions[$startInst + 1].OpCode = [Mono.Cecil.Cil.OpCodes]::Stsfld
$m.Body.Instructions[$startInst + 1].Operand = $appNameField

# Nop out the rest until endInst
for ($i = $startInst + 2; $i -lt $endInst; $i++) {
    $m.Body.Instructions[$i].OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
    $m.Body.Instructions[$i].Operand = $null
}

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($dllPath, $outMs.ToArray())
Write-Output "Successfully patched Settings.Configure in AutoTranslator!"
