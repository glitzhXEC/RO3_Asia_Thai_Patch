$cecilBytes = [System.IO.File]::ReadAllBytes('Client\BepInEx\core\Mono.Cecil.dll')
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$mscorlibAss = [Mono.Cecil.AssemblyDefinition]::ReadAssembly('_TranslationWorkspace\mscorlib.dll.orig')
$mscorlibMod = $mscorlibAss.MainModule

# ==============================================================================
# 1. Patch MonoMod.RuntimeDetour.dll
# ==============================================================================
Write-Host '=== Patching MonoMod.RuntimeDetour.dll ==='
$detourPath = 'Client\BepInEx\core\MonoMod.RuntimeDetour.dll'
$detourOrigPath = '_TranslationWorkspace\MonoMod.RuntimeDetour.dll.orig'
if (-not (Test-Path $detourOrigPath)) {
    Copy-Item $detourPath $detourOrigPath -Force
}

$detourBytes = [System.IO.File]::ReadAllBytes($detourOrigPath)
$detourAss = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((New-Object System.IO.MemoryStream(,$detourBytes)))
$detourMod = $detourAss.MainModule

$ilPlatformType = $detourMod.GetType('MonoMod.RuntimeDetour.Platforms.DetourRuntimeILPlatform')

# Add P/Invoke: mono_compile_method(IntPtr)
$monoModRef = New-Object Mono.Cecil.ModuleReference('mono-2.0-bdwgc.dll')
$detourMod.ModuleReferences.Add($monoModRef)

$intPtrType = $detourMod.TypeSystem.IntPtr
$pinvokeMethod = New-Object Mono.Cecil.MethodDefinition(
    'mono_compile_method',
    [Mono.Cecil.MethodAttributes]'Private, Static, HideBySig, PInvokeImpl',
    $intPtrType
)
$pinvokeMethod.Parameters.Add((New-Object Mono.Cecil.ParameterDefinition('method', [Mono.Cecil.ParameterAttributes]::None, $intPtrType)))
$pinvokeMethod.ImplAttributes = [Mono.Cecil.MethodImplAttributes]::PreserveSig
$pinvokeMethod.PInvokeInfo = New-Object Mono.Cecil.PInvokeInfo(
    [Mono.Cecil.PInvokeAttributes]'CallConvCdecl',
    'mono_compile_method',
    $monoModRef
)
$ilPlatformType.Methods.Add($pinvokeMethod)

# Import RuntimeMethodHandle.value field
$rmhType = $mscorlibMod.GetType('System.RuntimeMethodHandle')
$rmhValueField = $rmhType.Fields | Where-Object { $_.Name -eq 'value' }
$refRmhValue = $detourMod.ImportReference($rmhValueField)

# Patch GetFunctionPointer(MethodBase, RuntimeMethodHandle)
$gfpMethod = $ilPlatformType.Methods | Where-Object { $_.Name -eq 'GetFunctionPointer' -and $_.Parameters.Count -eq 2 }
$gfpMethod.Body.Instructions.Clear()
$il = $gfpMethod.Body.GetILProcessor()
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarga_S, $gfpMethod.Parameters[1]))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $refRmhValue))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $pinvokeMethod))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))
Write-Host 'Patched DetourRuntimeILPlatform.GetFunctionPointer to use mono_compile_method!'

# Save MonoMod.RuntimeDetour.dll
$outMs = New-Object System.IO.MemoryStream
$detourAss.Write($outMs)
[System.IO.File]::WriteAllBytes($detourPath, $outMs.ToArray())
Write-Host 'Saved patched MonoMod.RuntimeDetour.dll.'

# ==============================================================================
# 2. Patch MonoMod.Utils.dll
# ==============================================================================
Write-Host '
=== Patching MonoMod.Utils.dll ==='
$utilsPath = 'Client\BepInEx\core\MonoMod.Utils.dll'
$utilsOrigPath = '_TranslationWorkspace\MonoMod.Utils.dll.orig'
if (-not (Test-Path $utilsOrigPath)) {
    Copy-Item $utilsPath $utilsOrigPath -Force
}

$utilsBytes = [System.IO.File]::ReadAllBytes($utilsOrigPath)
$utilsAss = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((New-Object System.IO.MemoryStream(,$utilsBytes)))
$utilsMod = $utilsAss.MainModule

# Import fields from mscorlib.orig
$mbType = $mscorlibMod.GetType('System.Reflection.MethodBody')
$f_il = $utilsMod.ImportReference(($mbType.Fields | Where-Object { $_.Name -eq 'il' }))
$f_locals = $utilsMod.ImportReference(($mbType.Fields | Where-Object { $_.Name -eq 'locals' }))
$f_clauses = $utilsMod.ImportReference(($mbType.Fields | Where-Object { $_.Name -eq 'clauses' }))

$ehcType = $mscorlibMod.GetType('System.Reflection.ExceptionHandlingClause')
$f_flags = $utilsMod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'flags' }))
$f_try_offset = $utilsMod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'try_offset' }))
$f_try_length = $utilsMod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'try_length' }))
$f_filter_offset = $utilsMod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'filter_offset' }))
$f_handler_offset = $utilsMod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'handler_offset' }))
$f_handler_length = $utilsMod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'handler_length' }))
$f_catch_type = $utilsMod.ImportReference(($ehcType.Fields | Where-Object { $_.Name -eq 'catch_type' }))

# Patch DynamicMethodDefinition._CopyMethodToDefinition
$dmdType = $utilsMod.GetType('MonoMod.Utils.DynamicMethodDefinition')
$copyMethod = $dmdType.Methods | Where-Object { $_.Name -eq '_CopyMethodToDefinition' }

$replacedCount = 0
foreach ($inst in $copyMethod.Body.Instructions) {
    if ($inst.Operand -is [Mono.Cecil.MethodReference]) {
        $mr = $inst.Operand
        $mName = $mr.Name
        $tName = $mr.DeclaringType.FullName

        if ($tName -like '*MethodBody*' -and $mName -eq 'GetILAsByteArray') {
            $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
            $inst.Operand = $f_il
            $replacedCount++
        }
        elseif ($tName -like '*MethodBody*' -and $mName -eq 'get_LocalVariables') {
            $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
            $inst.Operand = $f_locals
            $replacedCount++
        }
        elseif ($tName -like '*MethodBody*' -and $mName -eq 'get_ExceptionHandlingClauses') {
            $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
            $inst.Operand = $f_clauses
            $replacedCount++
        }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_Flags') {
            $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
            $inst.Operand = $f_flags
            $replacedCount++
        }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_TryOffset') {
            $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
            $inst.Operand = $f_try_offset
            $replacedCount++
        }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_TryLength') {
            $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
            $inst.Operand = $f_try_length
            $replacedCount++
        }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_FilterOffset') {
            $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
            $inst.Operand = $f_filter_offset
            $replacedCount++
        }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_HandlerOffset') {
            $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
            $inst.Operand = $f_handler_offset
            $replacedCount++
        }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_HandlerLength') {
            $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
            $inst.Operand = $f_handler_length
            $replacedCount++
        }
        elseif ($tName -like '*ExceptionHandlingClause*' -and $mName -eq 'get_CatchType') {
            $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
            $inst.Operand = $f_catch_type
            $replacedCount++
        }
    }
}
Write-Host ('Replaced ' + $replacedCount + ' method calls with direct field accesses in _CopyMethodToDefinition!')

# Patch MMReflectionImporter.ImportReference
# Skip generic field resolution (ResolveField):
# From IL_005E (brfalse.s IL_007b) change to jump directly to IL_007C
$importerType = $utilsMod.GetType('MonoMod.Utils.MMReflectionImporter')
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
    Write-Host 'Bypassed Module.ResolveField in MMReflectionImporter.ImportReference!'
}

# Save MonoMod.Utils.dll
$outMs2 = New-Object System.IO.MemoryStream
$utilsAss.Write($outMs2)
[System.IO.File]::WriteAllBytes($utilsPath, $outMs2.ToArray())
Write-Host 'Saved patched MonoMod.Utils.dll.'
Write-Host '
All patches applied successfully!'
