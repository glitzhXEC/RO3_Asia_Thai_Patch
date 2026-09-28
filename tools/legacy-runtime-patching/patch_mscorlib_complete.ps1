$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$origPath = "Client\ro3_Data\Managed\mscorlib.dll.orig"
$targetPath = "Client\ro3_Data\Managed\mscorlib.dll"

$bytes = [System.IO.File]::ReadAllBytes($origPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)
$mod = $assembly.MainModule

# ========================================================
# 1. System.RuntimeMethodHandle -> GetFunctionPointer()
# ========================================================
$rmhType = $mod.GetType("System.RuntimeMethodHandle")
$intPtrType = $mod.TypeSystem.IntPtr
$valueField = $rmhType.Fields | Where-Object { $_.Name -eq "value" }

$monoModRef = New-Object Mono.Cecil.ModuleReference("mono-2.0-bdwgc.dll")
$mod.ModuleReferences.Add($monoModRef)

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
$rmhType.Methods.Add($pinvokeMethod)

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
$rmhType.Methods.Add($gfpMethod)

# ========================================================
# 2. System.Reflection.MethodBody
# ========================================================
$mb = $mod.GetType("System.Reflection.MethodBody")
$f_clauses = $mb.Fields | Where-Object { $_.Name -eq "clauses" }
$f_locals = $mb.Fields | Where-Object { $_.Name -eq "locals" }
$f_il = $mb.Fields | Where-Object { $_.Name -eq "il" }
$f_init_locals = $mb.Fields | Where-Object { $_.Name -eq "init_locals" }
$f_sig_token = $mb.Fields | Where-Object { $_.Name -eq "sig_token" }
$f_max_stack = $mb.Fields | Where-Object { $_.Name -eq "max_stack" }

# GetILAsByteArray()
$byteArrType = New-Object Mono.Cecil.ArrayType($mod.TypeSystem.Byte)
$m_gil = New-Object Mono.Cecil.MethodDefinition(
    "GetILAsByteArray",
    [Mono.Cecil.MethodAttributes]"Public, Virtual, HideBySig, NewSlot",
    $byteArrType
)
$il = $m_gil.Body.GetILProcessor()
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $f_il))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))
$mb.Methods.Add($m_gil)

# Types needed for generic collections
$ilistTypeDef = $mod.GetType('System.Collections.Generic.IList`1')
$lviType = $mod.GetType("System.Reflection.LocalVariableInfo")
$ehcType = $mod.GetType("System.Reflection.ExceptionHandlingClause")

$ilistLviType = New-Object Mono.Cecil.GenericInstanceType($ilistTypeDef)
$ilistLviType.GenericArguments.Add($lviType)

$ilistEhcType = New-Object Mono.Cecil.GenericInstanceType($ilistTypeDef)
$ilistEhcType.GenericArguments.Add($ehcType)

$arrayType = $mod.GetType("System.Array")
$asReadOnlyMethod = $arrayType.Methods | Where-Object { $_.Name -eq "AsReadOnly" -and $_.GenericParameters.Count -eq 1 }

$asReadOnlyLvi = New-Object Mono.Cecil.GenericInstanceMethod($asReadOnlyMethod)
$asReadOnlyLvi.GenericArguments.Add($lviType)

$asReadOnlyEhc = New-Object Mono.Cecil.GenericInstanceMethod($asReadOnlyMethod)
$asReadOnlyEhc.GenericArguments.Add($ehcType)

# get_LocalVariables()
$m_glv = New-Object Mono.Cecil.MethodDefinition(
    "get_LocalVariables",
    [Mono.Cecil.MethodAttributes]"Public, Virtual, HideBySig, NewSlot, SpecialName",
    $ilistLviType
)
$il = $m_glv.Body.GetILProcessor()
$lblHasLocals = $il.Create([Mono.Cecil.Cil.OpCodes]::Call, $asReadOnlyLvi)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $f_locals))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Dup))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brtrue_S, $lblHasLocals))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Pop))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Newarr, $lviType))
$il.Append($lblHasLocals)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))
$mb.Methods.Add($m_glv)

$prop_lv = New-Object Mono.Cecil.PropertyDefinition("LocalVariables", [Mono.Cecil.PropertyAttributes]::None, $ilistLviType)
$prop_lv.GetMethod = $m_glv
$mb.Properties.Add($prop_lv)

# get_ExceptionHandlingClauses()
$m_gehc = New-Object Mono.Cecil.MethodDefinition(
    "get_ExceptionHandlingClauses",
    [Mono.Cecil.MethodAttributes]"Public, Virtual, HideBySig, NewSlot, SpecialName",
    $ilistEhcType
)
$il = $m_gehc.Body.GetILProcessor()
$lblHasClauses = $il.Create([Mono.Cecil.Cil.OpCodes]::Call, $asReadOnlyEhc)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $f_clauses))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Dup))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brtrue_S, $lblHasClauses))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Pop))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Newarr, $ehcType))
$il.Append($lblHasClauses)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))
$mb.Methods.Add($m_gehc)

$prop_ehc = New-Object Mono.Cecil.PropertyDefinition("ExceptionHandlingClauses", [Mono.Cecil.PropertyAttributes]::None, $ilistEhcType)
$prop_ehc.GetMethod = $m_gehc
$mb.Properties.Add($prop_ehc)

# get_MaxStackSize()
$m_maxstk = New-Object Mono.Cecil.MethodDefinition(
    "get_MaxStackSize",
    [Mono.Cecil.MethodAttributes]"Public, Virtual, HideBySig, NewSlot, SpecialName",
    $mod.TypeSystem.Int32
)
$il = $m_maxstk.Body.GetILProcessor()
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $f_max_stack))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))
$mb.Methods.Add($m_maxstk)

$prop_maxstk = New-Object Mono.Cecil.PropertyDefinition("MaxStackSize", [Mono.Cecil.PropertyAttributes]::None, $mod.TypeSystem.Int32)
$prop_maxstk.GetMethod = $m_maxstk
$mb.Properties.Add($prop_maxstk)

# get_InitLocals()
$m_initloc = New-Object Mono.Cecil.MethodDefinition(
    "get_InitLocals",
    [Mono.Cecil.MethodAttributes]"Public, Virtual, HideBySig, NewSlot, SpecialName",
    $mod.TypeSystem.Boolean
)
$il = $m_initloc.Body.GetILProcessor()
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $f_init_locals))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))
$mb.Methods.Add($m_initloc)

$prop_initloc = New-Object Mono.Cecil.PropertyDefinition("InitLocals", [Mono.Cecil.PropertyAttributes]::None, $mod.TypeSystem.Boolean)
$prop_initloc.GetMethod = $m_initloc
$mb.Properties.Add($prop_initloc)

# get_LocalSignatureMetadataToken()
$m_sig = New-Object Mono.Cecil.MethodDefinition(
    "get_LocalSignatureMetadataToken",
    [Mono.Cecil.MethodAttributes]"Public, Virtual, HideBySig, NewSlot, SpecialName",
    $mod.TypeSystem.Int32
)
$il = $m_sig.Body.GetILProcessor()
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $f_sig_token))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))
$mb.Methods.Add($m_sig)

$prop_sig = New-Object Mono.Cecil.PropertyDefinition("LocalSignatureMetadataToken", [Mono.Cecil.PropertyAttributes]::None, $mod.TypeSystem.Int32)
$prop_sig.GetMethod = $m_sig
$mb.Properties.Add($prop_sig)

# ========================================================
# 3. System.Reflection.ExceptionHandlingClause
# ========================================================
$ehc = $mod.GetType("System.Reflection.ExceptionHandlingClause")
$f_ehc_flags = $ehc.Fields | Where-Object { $_.Name -eq "flags" }
$f_ehc_try_offset = $ehc.Fields | Where-Object { $_.Name -eq "try_offset" }
$f_ehc_try_length = $ehc.Fields | Where-Object { $_.Name -eq "try_length" }
$f_ehc_filter_offset = $ehc.Fields | Where-Object { $_.Name -eq "filter_offset" }
$f_ehc_handler_offset = $ehc.Fields | Where-Object { $_.Name -eq "handler_offset" }
$f_ehc_handler_length = $ehc.Fields | Where-Object { $_.Name -eq "handler_length" }
$f_ehc_catch_type = $ehc.Fields | Where-Object { $_.Name -eq "catch_type" }

function Add-Getter($type, $propName, $retType, $field) {
    $m = New-Object Mono.Cecil.MethodDefinition("get_$propName",
        [Mono.Cecil.MethodAttributes]"Public, Virtual, HideBySig, NewSlot, SpecialName",
        $retType)
    $il = $m.Body.GetILProcessor()
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $field))
    $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))
    $type.Methods.Add($m)
    
    $p = New-Object Mono.Cecil.PropertyDefinition($propName, [Mono.Cecil.PropertyAttributes]::None, $retType)
    $p.GetMethod = $m
    $type.Properties.Add($p)
}

$ehcoType = $mod.GetType("System.Reflection.ExceptionHandlingClauseOptions")
$typeType = $mod.GetType("System.Type")

Add-Getter $ehc "Flags" $ehcoType $f_ehc_flags
Add-Getter $ehc "TryOffset" $mod.TypeSystem.Int32 $f_ehc_try_offset
Add-Getter $ehc "TryLength" $mod.TypeSystem.Int32 $f_ehc_try_length
Add-Getter $ehc "FilterOffset" $mod.TypeSystem.Int32 $f_ehc_filter_offset
Add-Getter $ehc "HandlerOffset" $mod.TypeSystem.Int32 $f_ehc_handler_offset
Add-Getter $ehc "HandlerLength" $mod.TypeSystem.Int32 $f_ehc_handler_length
Add-Getter $ehc "CatchType" $typeType $f_ehc_catch_type

# ========================================================
# 4. System.Reflection.Module -> ResolveField(int), ResolveMember(int)
# ========================================================
$modType = $mod.GetType("System.Reflection.Module")
$fieldInfoType = $mod.GetType("System.Reflection.FieldInfo")
$memberInfoType = $mod.GetType("System.Reflection.MemberInfo")

$rf3 = $modType.Methods | Where-Object { $_.Name -eq "ResolveField" -and $_.Parameters.Count -eq 3 }
$rm3 = $modType.Methods | Where-Object { $_.Name -eq "ResolveMember" -and $_.Parameters.Count -eq 3 }

$rf1 = New-Object Mono.Cecil.MethodDefinition("ResolveField",
    [Mono.Cecil.MethodAttributes]"Public, HideBySig",
    $fieldInfoType)
$rf1.HasThis = $true
$rf1.Parameters.Add((New-Object Mono.Cecil.ParameterDefinition("metadataToken", [Mono.Cecil.ParameterAttributes]::None, $mod.TypeSystem.Int32)))
$il = $rf1.Body.GetILProcessor()
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ldarg_1)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ldnull)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ldnull)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Callvirt, $rf3)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ret)
$modType.Methods.Add($rf1)

$rm1 = New-Object Mono.Cecil.MethodDefinition("ResolveMember",
    [Mono.Cecil.MethodAttributes]"Public, HideBySig",
    $memberInfoType)
$rm1.HasThis = $true
$rm1.Parameters.Add((New-Object Mono.Cecil.ParameterDefinition("metadataToken", [Mono.Cecil.ParameterAttributes]::None, $mod.TypeSystem.Int32)))
$il = $rm1.Body.GetILProcessor()
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ldarg_1)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ldnull)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ldnull)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Callvirt, $rm3)
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ret)
$modType.Methods.Add($rm1)

# ========================================================
# Save to target
# ========================================================
$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($targetPath, $outMs.ToArray())
Write-Output "Successfully built complete patched mscorlib.dll from orig!"
