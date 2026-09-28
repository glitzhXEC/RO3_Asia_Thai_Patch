$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$mscorlibPath = "Client\ro3_Data\Managed\mscorlib.dll"
$bytes = [System.IO.File]::ReadAllBytes($mscorlibPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

$type = $assembly.MainModule.GetType("System.RuntimeMethodHandle")
$intPtrType = $assembly.MainModule.TypeSystem.IntPtr
$valueField = $type.Fields | Where-Object { $_.Name -eq "value" }

# 1. Add P/Invoke method: mono_compile_method(IntPtr) -> IntPtr
$monoModRef = New-Object Mono.Cecil.ModuleReference("mono-2.0-bdwgc.dll")
$assembly.MainModule.ModuleReferences.Add($monoModRef)

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
$type.Methods.Add($pinvokeMethod)

# 2. Add public IntPtr GetFunctionPointer()
$gfpMethod = New-Object Mono.Cecil.MethodDefinition(
    "GetFunctionPointer",
    [Mono.Cecil.MethodAttributes]"Public, HideBySig",
    $intPtrType
)
$gfpMethod.HasThis = $true
$il = $gfpMethod.Body.GetILProcessor()
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ldfld, $valueField)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Call, $pinvokeMethod)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ret)

$type.Methods.Add($gfpMethod)

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($mscorlibPath, $outMs.ToArray())
Write-Output "Successfully added GetFunctionPointer() to RuntimeMethodHandle in mscorlib.dll!"
