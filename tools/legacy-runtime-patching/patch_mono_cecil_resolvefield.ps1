$bepCore = "Client\BepInEx\core"
$cecilPath = "$bepCore\Mono.Cecil.dll"
$cecilOrigPath = "_TranslationWorkspace\Mono.Cecil.dll.orig"

if (-not (Test-Path $cecilOrigPath)) {
    Copy-Item $cecilPath $cecilOrigPath -Force
    Write-Host "Backed up Mono.Cecil.dll to $cecilOrigPath"
}

$cecilBytes = [System.IO.File]::ReadAllBytes($cecilOrigPath)
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$ms = New-Object System.IO.MemoryStream(,$cecilBytes)
$ass = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

$type = $ass.MainModule.GetType("Mono.Cecil.DefaultReflectionImporter")
$m = $type.Methods | Where-Object { $_.Name -eq "ResolveFieldDefinition" }

Write-Host "Rebuilding ResolveFieldDefinition in Mono.Cecil.dll..."
$m.Body.Instructions.Clear()
$il = $m.Body.GetILProcessor()
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))

$outMs = New-Object System.IO.MemoryStream
$ass.Write($outMs)
[System.IO.File]::WriteAllBytes($cecilPath, $outMs.ToArray())
Write-Host "Successfully patched Mono.Cecil.dll!"
