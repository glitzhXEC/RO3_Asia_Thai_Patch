$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$dllPath = "Client\BepInEx\core\BepInEx.dll"
$bytes = [System.IO.File]::ReadAllBytes($dllPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

$type = $assembly.MainModule.GetType("BepInEx.Bootstrap.Chainloader")
$m = $type.Methods | Where-Object { $_.Name -eq "get_IsHeadless" }

$m.Body.Instructions.Clear()
$il = $m.Body.GetILProcessor()
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ret)

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($dllPath, $outMs.ToArray())
Write-Output "Successfully patched Chainloader.get_IsHeadless to return false!"
