$cecilBytes = [System.IO.File]::ReadAllBytes("_TranslationWorkspace\Mono.Cecil.dll.orig")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$ms = New-Object System.IO.MemoryStream(,$cecilBytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

# 1. Patch ModuleWriter.Write
$typeWriter = $assembly.MainModule.GetType("Mono.Cecil.ModuleWriter")
$mWrite = $typeWriter.Methods | Where-Object { $_.Name -eq "Write" -and $_.Parameters.Count -eq 3 }
$patchedCount = 0

for ($i = 0; $i -lt $mWrite.Body.Instructions.Count; $i++) {
    $inst = $mWrite.Body.Instructions[$i]
    if ($inst.Offset -ge 0x00B9 -and $inst.Offset -le 0x00D0) {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
        $inst.Operand = $null
        $patchedCount++
    }
    if ($inst.Offset -ge 0x0131 -and $inst.Offset -le 0x0147) {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
        $inst.Operand = $null
        $patchedCount++
    }
}
Write-Output ("Noped {0} instructions in ModuleWriter.Write" -f $patchedCount)

# 2. Patch BaseAssemblyResolver.GetCorlib
$typeResolver = $assembly.MainModule.GetType("Mono.Cecil.BaseAssemblyResolver")
$mCorlib = $typeResolver.Methods | Where-Object { $_.Name -eq "GetCorlib" }
$patchedCorlib = 0
for ($i = 0; $i -lt $mCorlib.Body.Instructions.Count; $i++) {
    $inst = $mCorlib.Body.Instructions[$i]
    if ($inst.Operand -ne $null -and $inst.Operand.ToString().Contains("get_MajorRevision")) {
        # Instead of calling get_MajorRevision() on Version, pop Version and push 0
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Pop
        $inst.Operand = $null
        $il = $mCorlib.Body.GetILProcessor()
        $il.InsertAfter($inst, $il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
        $patchedCorlib++
    }
}
Write-Output ("Patched {0} get_MajorRevision in BaseAssemblyResolver.GetCorlib" -f $patchedCorlib)

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes("Client\BepInEx\core\Mono.Cecil.dll", $outMs.ToArray())
Write-Output "Successfully updated Mono.Cecil.dll!"
