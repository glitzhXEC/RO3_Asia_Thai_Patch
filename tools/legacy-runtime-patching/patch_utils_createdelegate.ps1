$cecilBytes = [System.IO.File]::ReadAllBytes("_TranslationWorkspace\Mono.Cecil.dll.orig")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$mscorlibAss = [Mono.Cecil.AssemblyDefinition]::ReadAssembly("Client\ro3_Data\Managed\mscorlib.dll")
$rmhType = $mscorlibAss.MainModule.GetType("System.RuntimeMethodHandle")
$rmhValueField = $rmhType.Fields | Where-Object { $_.Name -eq "value" }

$utilsPath = "Client\BepInEx\core\MonoMod.Utils.dll"
$utilsBytes = [System.IO.File]::ReadAllBytes($utilsPath)
$ass = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((New-Object System.IO.MemoryStream(,$utilsBytes)))
$mod = $ass.MainModule

$refRmhValue = $mod.ImportReference($rmhValueField)

# Add P/Invoke: mono_compile_method(IntPtr)
$monoModRef = New-Object Mono.Cecil.ModuleReference("mono-2.0-bdwgc.dll")
$mod.ModuleReferences.Add($monoModRef)

$intPtrType = $mod.TypeSystem.IntPtr
$pinvokeMethod = New-Object Mono.Cecil.MethodDefinition(
    "mono_compile_method",
    [Mono.Cecil.MethodAttributes]"Private, Static, HideBySig, PInvokeImpl",
    $intPtrType
)
$pinvokeMethod.Parameters.Add((New-Object Mono.Cecil.ParameterDefinition("method", [Mono.Cecil.ParameterAttributes]::None, $intPtrType)))
$pinvokeMethod.ImplAttributes = [Mono.Cecil.MethodImplAttributes]::PreserveSig
$pinvokeMethod.PInvokeInfo = New-Object Mono.Cecil.PInvokeInfo(
    [Mono.Cecil.PInvokeAttributes]"CallConvCdecl",
    "mono_compile_method",
    $monoModRef
)

$extType = $mod.GetType("MonoMod.Utils.Extensions")
$extType.Methods.Add($pinvokeMethod)

$m = $extType.Methods | Where-Object { $_.Name -eq "CreateDelegate" -and $_.Parameters.Count -eq 3 }
$il = $m.Body.GetILProcessor()
$patched = $false

for ($i = 0; $i -lt $m.Body.Instructions.Count; $i++) {
    $inst = $m.Body.Instructions[$i]
    if ($inst.Operand -ne $null -and $inst.Operand.ToString() -like "*GetFunctionPointer*") {
        # Replace: call GetFunctionPointer
        # With:
        # ldfld RuntimeMethodHandle::value
        # call mono_compile_method
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
        $inst.Operand = $refRmhValue
        $callCompile = $il.Create([Mono.Cecil.Cil.OpCodes]::Call, $pinvokeMethod)
        $il.InsertAfter($inst, $callCompile)
        $patched = $true
        Write-Host "Patched GetFunctionPointer -> mono_compile_method in Extensions.CreateDelegate!"
        break
    }
}

if (-not $patched) { throw "Failed to find GetFunctionPointer in Extensions.CreateDelegate" }

$outMs = New-Object System.IO.MemoryStream
$ass.Write($outMs)
[System.IO.File]::WriteAllBytes($utilsPath, $outMs.ToArray())
Write-Host "Successfully saved patched MonoMod.Utils.dll!"
