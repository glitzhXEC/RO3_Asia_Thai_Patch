$cecilBytes = [System.IO.File]::ReadAllBytes("_TranslationWorkspace\Mono.Cecil.dll.orig")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$mscorlibAss = [Mono.Cecil.AssemblyDefinition]::ReadAssembly("Client\ro3_Data\Managed\mscorlib.dll")
$rmhType = $mscorlibAss.MainModule.GetType("System.RuntimeMethodHandle")
$rmhValueField = $rmhType.Fields | Where-Object { $_.Name -eq "value" }

$utilsOrigPath = "_TranslationWorkspace\MonoMod.Utils.dll.orig"
$utilsPath = "Client\BepInEx\core\MonoMod.Utils.dll"

# Start fresh from orig
$utilsBytes = [System.IO.File]::ReadAllBytes($utilsOrigPath)
$ass = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((New-Object System.IO.MemoryStream(,$utilsBytes)))
$mod = $ass.MainModule

# 1. Apply native patches (CopyMethodToDefinition & ImportReference)
$mbType = $mscorlibAss.MainModule.GetType('System.Reflection.MethodBody')
$f_il = $mod.ImportReference(($mbType.Fields | Where-Object { $_.Name -eq 'il' }))
$f_locals = $mod.ImportReference(($mbType.Fields | Where-Object { $_.Name -eq 'locals' }))
$f_clauses = $mod.ImportReference(($mbType.Fields | Where-Object { $_.Name -eq 'clauses' }))

$ehcType = $mscorlibAss.MainModule.GetType('System.Reflection.ExceptionHandlingClause')
$f_flags = $mod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'flags' }))
$f_try_offset = $mod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'try_offset' }))
$f_try_length = $mod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'try_length' }))
$f_filter_offset = $mod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'filter_offset' }))
$f_handler_offset = $mod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'handler_offset' }))
$f_handler_length = $mod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'handler_length' }))
$f_catch_type = $mod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'catch_type' }))

$dmdType = $mod.GetType('MonoMod.Utils.DynamicMethodDefinition')
$copyMethod = $dmdType.Methods | Where-Object { $_.Name -eq '_CopyMethodToDefinition' }

foreach ($inst in $copyMethod.Body.Instructions) {
    if ($inst.Operand -is [Mono.Cecil.MethodReference]) {
        $mr = $inst.Operand
        $mName = $mr.Name
        $tName = $mr.DeclaringType.FullName

        if ($tName -like '*MethodBody*' -and $mName -eq 'GetILAsByteArray') { $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld; $inst.Operand = $f_il }
        elseif ($tName -like '*MethodBody*' -and $mName -eq 'get_LocalVariables') { $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld; $inst.Operand = $f_locals }
        elseif ($tName -like '*MethodBody*' -and $mName -eq 'get_ExceptionHandlingClauses') { $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld; $inst.Operand = $f_clauses }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_Flags') { $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld; $inst.Operand = $f_flags }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_TryOffset') { $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld; $inst.Operand = $f_try_offset }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_TryLength') { $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld; $inst.Operand = $f_try_length }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_FilterOffset') { $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld; $inst.Operand = $f_filter_offset }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_HandlerOffset') { $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld; $inst.Operand = $f_handler_offset }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_HandlerLength') { $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld; $inst.Operand = $f_handler_length }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_CatchType') { $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld; $inst.Operand = $f_catch_type }
    }
}

# Bypass Module.ResolveField in MMReflectionImporter.ImportReference
$importerType = $mod.GetType('MonoMod.Utils.MMReflectionImporter')
$importFieldMethod = $importerType.Methods | Where-Object { $_.Name -eq 'ImportReference' -and $_.Parameters.Count -eq 2 }
$targetInst = $null
$destInst = $null
foreach ($inst in $importFieldMethod.Body.Instructions) {
    if ($inst.Offset -eq 0x005E) { $targetInst = $inst }
    if ($inst.Offset -eq 0x007C) { $destInst = $inst }
}
if ($targetInst -and $destInst) {
    $targetInst.OpCode = [Mono.Cecil.Cil.OpCodes]::Br_S
    $targetInst.Operand = $destInst
}

# 2. Apply DefineParameter patch in _DMDEmit.Generate
$dmdEmitType = $mod.GetType("MonoMod.Utils._DMDEmit")
$mGen = $dmdEmitType.Methods | Where-Object { $_.Name -eq "Generate" }
for ($i = 0; $i -lt $mGen.Body.Instructions.Count; $i++) {
    $inst = $mGen.Body.Instructions[$i]
    if ($inst.Offset -ge 0x00AD -and $inst.Offset -le 0x00CA) {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
        $inst.Operand = $null
    }
}

# 3. Add MonoNative class with mono_compile_method P/Invoke
$monoModRef = New-Object Mono.Cecil.ModuleReference("mono-2.0-bdwgc.dll")
$mod.ModuleReferences.Add($monoModRef)

$nativeClass = New-Object Mono.Cecil.TypeDefinition(
    "MonoMod.Utils",
    "MonoNative",
    [Mono.Cecil.TypeAttributes]"Public, Abstract, Sealed, BeforeFieldInit",
    $mod.TypeSystem.Object
)
$mod.Types.Add($nativeClass)

$intPtrType = $mod.TypeSystem.IntPtr
$pinvokeMethod = New-Object Mono.Cecil.MethodDefinition(
    "mono_compile_method",
    [Mono.Cecil.MethodAttributes]"Public, Static, HideBySig, PInvokeImpl",
    $intPtrType
)
$pinvokeMethod.Parameters.Add((New-Object Mono.Cecil.ParameterDefinition("method", [Mono.Cecil.ParameterAttributes]::None, $intPtrType)))
$pinvokeMethod.ImplAttributes = [Mono.Cecil.MethodImplAttributes]::PreserveSig
$pinvokeMethod.PInvokeInfo = New-Object Mono.Cecil.PInvokeInfo(
    [Mono.Cecil.PInvokeAttributes]"CallConvCdecl",
    "mono_compile_method",
    $monoModRef
)
$nativeClass.Methods.Add($pinvokeMethod)

# 4. Patch Extensions.CreateDelegate(MethodBase, Type, Object)
$extType = $mod.GetType("MonoMod.Utils.Extensions")
$mCd = $extType.Methods | Where-Object { $_.Name -eq "CreateDelegate" -and $_.Parameters.Count -eq 3 }
$refRmhValue = $mod.ImportReference($rmhValueField)
$ilCd = $mCd.Body.GetILProcessor()

for ($i = 0; $i -lt $mCd.Body.Instructions.Count; $i++) {
    $inst = $mCd.Body.Instructions[$i]
    if ($inst.Operand -ne $null -and $inst.Operand.ToString() -like "*GetFunctionPointer*") {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
        $inst.Operand = $refRmhValue
        $callCompile = $ilCd.Create([Mono.Cecil.Cil.OpCodes]::Call, $pinvokeMethod)
        $ilCd.InsertAfter($inst, $callCompile)
        Write-Host "Patched GetFunctionPointer in Extensions.CreateDelegate!"
        break
    }
}

$outMs = New-Object System.IO.MemoryStream
$ass.Write($outMs)
[System.IO.File]::WriteAllBytes($utilsPath, $outMs.ToArray())
Write-Host "MonoMod.Utils.dll cleanly patched and saved!"
