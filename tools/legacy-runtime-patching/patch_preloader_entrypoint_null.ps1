$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$preloaderPath = "Client\BepInEx\core\BepInEx.Preloader.dll"
$bytes = [System.IO.File]::ReadAllBytes($preloaderPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

$type = $assembly.MainModule.GetType("BepInEx.Preloader.Preloader")
$m = $type.Methods | Where-Object { $_.Name -eq "PatchEntrypoint" }

# Find the OpCodes.Call followed by AccessTools.PropertyGetter
$il = $m.Body.GetILProcessor()
$found = $false

for ($i = 0; $i -lt $m.Body.Instructions.Count; $i++) {
    $inst = $m.Body.Instructions[$i]
    if ($inst.Operand -ne $null -and $inst.Operand.ToString().Contains("AccessTools::PropertyGetter")) {
        Write-Output ("Found AccessTools call at index: " + $i)
        
        # In lines before and after:
        # Instruction at 205 (IL_02BD): ldsfld OpCodes::Call -> change to ldsfld OpCodes::Ldnull
        # Instruction at 214 (IL_02E2): callvirt Create(OpCode, MethodReference) -> change to callvirt Create(OpCode)
        # Instructions 206 to 213: replace with Nop
        
        # Let's find index of ldsfld Call before PropertyGetter
        $callFieldInst = $null
        for ($j = $i - 1; $j -ge 0; $j--) {
            if ($m.Body.Instructions[$j].OpCode -eq [Mono.Cecil.Cil.OpCodes]::Ldsfld) {
                $callFieldInst = $m.Body.Instructions[$j]
                break
            }
        }
        
        # Change ldsfld Call to ldsfld Ldnull
        $ldnullField = [Mono.Cecil.Cil.OpCodes].GetField("Ldnull")
        $callFieldInst.Operand = $assembly.MainModule.ImportReference($ldnullField)
        
        # Find callvirt Create(OpCode, MethodReference) after PropertyGetter
        $createInst = $null
        for ($j = $i + 1; $j -lt $m.Body.Instructions.Count; $j++) {
            if ($m.Body.Instructions[$j].OpCode -eq [Mono.Cecil.Cil.OpCodes]::Callvirt -and $m.Body.Instructions[$j].Operand.ToString().Contains("Create")) {
                $createInst = $m.Body.Instructions[$j]
                break
            }
        }
        
        # Change Create(OpCode, MethodReference) to Create(OpCode)
        $createMethod = [Mono.Cecil.Cil.ILProcessor].GetMethod("Create", [type[]]@([Mono.Cecil.Cil.OpCode]))
        $createInst.Operand = $assembly.MainModule.ImportReference($createMethod)
        
        # Nop all instructions between callFieldInst and createInst
        $startNop = $m.Body.Instructions.IndexOf($callFieldInst) + 1
        $endNop = $m.Body.Instructions.IndexOf($createInst) - 1
        for ($k = $startNop; $k -le $endNop; $k++) {
            $m.Body.Instructions[$k].OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
            $m.Body.Instructions[$k].Operand = $null
        }
        $found = $true
        Write-Output ("Noped from index {0} to {1}" -f $startNop, $endNop)
        break
    }
}

if ($found) {
    $outMs = New-Object System.IO.MemoryStream
    $assembly.Write($outMs)
    [System.IO.File]::WriteAllBytes($preloaderPath, $outMs.ToArray())
    Write-Output "Patched PatchEntrypoint to use Ldnull directly!"
} else {
    Write-Output "AccessTools not found in PatchEntrypoint!"
}
