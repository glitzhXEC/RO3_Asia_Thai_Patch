$ErrorActionPreference = "Stop"

$bepCore = "Client\BepInEx\core"
$cecilOrigPath = "_TranslationWorkspace\Mono.Cecil.dll.orig"
$cecilBytes = [System.IO.File]::ReadAllBytes($cecilOrigPath)
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$mscorlibAss = [Mono.Cecil.AssemblyDefinition]::ReadAssembly("Client\ro3_Data\Managed\mscorlib.dll")
$harmonyOrigPath = "_TranslationWorkspace\0Harmony.dll.orig"
$harmonyDestPath = "$bepCore\0Harmony.dll"

$harmonyBytes = [System.IO.File]::ReadAllBytes($harmonyOrigPath)
$harmonyAss = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((New-Object System.IO.MemoryStream(,$harmonyBytes)))
$mod = $harmonyAss.MainModule

# ==============================================================================
# 1. Patch AccessTools..cctor
# ==============================================================================
Write-Host "=== 1. Patching AccessTools..cctor ==="
$accessToolsType = $mod.GetType("HarmonyLib.AccessTools")
$cctor = $accessToolsType.Methods | Where-Object { $_.Name -eq ".cctor" }

$fAll = $accessToolsType.Fields | Where-Object { $_.Name -eq "all" }
$fAllDeclared = $accessToolsType.Fields | Where-Object { $_.Name -eq "allDeclared" }
$fPrep1 = $accessToolsType.Fields | Where-Object { $_.Name -eq "m_PrepForRemoting" }
$fPrep2 = $accessToolsType.Fields | Where-Object { $_.Name -eq "PrepForRemoting" }
$fMono = $accessToolsType.Fields | Where-Object { $_.Name -like "*IsMonoRuntime*" }
$fNetFw = $accessToolsType.Fields | Where-Object { $_.Name -like "*IsNetFrameworkRuntime*" }
$fNetCore = $accessToolsType.Fields | Where-Object { $_.Name -like "*IsNetCoreRuntime*" }
$fCache = $accessToolsType.Fields | Where-Object { $_.Name -eq "addHandlerCache" }
$fLock = $accessToolsType.Fields | Where-Object { $_.Name -eq "addHandlerCacheLock" }

$dictCtor = ($cctor.Body.Instructions | Where-Object { $_.OpCode.Name -eq "newobj" -and $_.Operand.ToString() -like "*Dictionary*" }).Operand
$lockCtor = ($cctor.Body.Instructions | Where-Object { $_.OpCode.Name -eq "newobj" -and $_.Operand.ToString() -like "*ReaderWriterLock*" }).Operand

$cctor.Body.Instructions.Clear()
$cctor.Body.Variables.Clear()
$il = $cctor.Body.GetILProcessor()

$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4, 15420))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $fAll))

$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4, 15422))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $fAllDeclared))

$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $fPrep1))

$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $fPrep2))

$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_1))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $fMono))

$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $fNetFw))

$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $fNetCore))

$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Newobj, $dictCtor))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $fCache))

$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Newobj, $lockCtor))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $fLock))

$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))
Write-Host "AccessTools..cctor rebuilt successfully!"

# ==============================================================================
# 2. Patch AccessTools.Method AmbiguousMatchException
# ==============================================================================
Write-Host "=== 2. Patching AccessTools.Method AmbiguousMatchException ==="
$methodMethod = $accessToolsType.Methods | Where-Object { $_.Name -eq "Method" -and $_.Parameters.Count -eq 4 }
$ambType = $mscorlibAss.MainModule.GetType("System.Reflection.AmbiguousMatchException")
$ctor1 = $ambType.Methods | Where-Object { $_.IsConstructor -and $_.Parameters.Count -eq 1 -and $_.Parameters[0].ParameterType.FullName -eq "System.String" }
$ctor1Ref = $mod.ImportReference($ctor1)

$patchedAmb = $false
for ($i = 0; $i -lt $methodMethod.Body.Instructions.Count; $i++) {
    $inst = $methodMethod.Body.Instructions[$i]
    if ($inst.OpCode.Name -eq "newobj" -and $inst.Operand.ToString() -like "*AmbiguousMatchException*") {
        $prev = $inst.Previous
        $prev.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
        $prev.Operand = $null
        $inst.Operand = $ctor1Ref
        $patchedAmb = $true
        Write-Host "Patched AmbiguousMatchException in AccessTools.Method!"
        break
    }
}
if (-not $patchedAmb) { throw "Failed to find AmbiguousMatchException in AccessTools.Method" }

# ==============================================================================
# 3. Patch PatchInfoSerialization.Deserialize
# ==============================================================================
Write-Host "=== 3. Patching PatchInfoSerialization.Deserialize ==="
$serType = $mod.GetType("HarmonyLib.PatchInfoSerialization")
$deserMethod = $serType.Methods | Where-Object { $_.Name -eq "Deserialize" }
$bfType = $mscorlibAss.MainModule.GetType("System.Runtime.Serialization.Formatters.Binary.BinaryFormatter")
$fBinder = $bfType.Fields | Where-Object { $_.Name -eq "m_binder" }
$fBinderRef = $mod.ImportReference($fBinder)

$patchedBinder = $false
for ($i = 0; $i -lt $deserMethod.Body.Instructions.Count; $i++) {
    $inst = $deserMethod.Body.Instructions[$i]
    if ($inst.Operand -is [Mono.Cecil.MethodReference] -and $inst.Operand.Name -eq "set_Binder") {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Stfld
        $inst.Operand = $fBinderRef
        $patchedBinder = $true
        Write-Host "Patched set_Binder -> stfld m_binder in PatchInfoSerialization.Deserialize!"
        break
    }
}
if (-not $patchedBinder) { throw "Failed to find set_Binder in PatchInfoSerialization.Deserialize" }

# ==============================================================================
# 4. Patch MethodBaseExtensions.HasMethodBody
# ==============================================================================
Write-Host "=== 4. Patching MethodBaseExtensions.HasMethodBody ==="
$mbeType = $mod.GetType("HarmonyLib.MethodBaseExtensions")
$hasMbMethod = $mbeType.Methods | Where-Object { $_.Name -eq "HasMethodBody" }
$mbType = $mscorlibAss.MainModule.GetType("System.Reflection.MethodBody")
$fIl = $mbType.Fields | Where-Object { $_.Name -eq "il" }
$fIlRef = $mod.ImportReference($fIl)

$patchedMb = $false
for ($i = 0; $i -lt $hasMbMethod.Body.Instructions.Count; $i++) {
    $inst = $hasMbMethod.Body.Instructions[$i]
    if ($inst.Operand -is [Mono.Cecil.MethodReference] -and $inst.Operand.Name -eq "GetILAsByteArray") {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
        $inst.Operand = $fIlRef
        $patchedMb = $true
        Write-Host "Patched GetILAsByteArray -> ldfld il in MethodBaseExtensions.HasMethodBody!"
        break
    }
}
if (-not $patchedMb) { throw "Failed to find GetILAsByteArray in MethodBaseExtensions.HasMethodBody" }

# ==============================================================================
# 5. Patch AccessTools.MethodDelegate (GetFunctionPointer)
# ==============================================================================
Write-Host "=== 5. Patching AccessTools.MethodDelegate (GetFunctionPointer) ==="
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
$accessToolsType.Methods.Add($pinvokeMethod)

$rmhType = $mscorlibAss.MainModule.GetType("System.RuntimeMethodHandle")
$rmhValueField = $rmhType.Fields | Where-Object { $_.Name -eq "value" }
$refRmhValue = $mod.ImportReference($rmhValueField)

$methodDelegate = $accessToolsType.Methods | Where-Object { $_.Name -eq "MethodDelegate" }
$patchedGfp = $false
$ilMd = $methodDelegate.Body.GetILProcessor()
for ($i = 0; $i -lt $methodDelegate.Body.Instructions.Count; $i++) {
    $inst = $methodDelegate.Body.Instructions[$i]
    if ($inst.Operand -is [Mono.Cecil.MethodReference] -and $inst.Operand.Name -eq "GetFunctionPointer") {
        $inst.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldfld
        $inst.Operand = $refRmhValue
        $callCompile = $ilMd.Create([Mono.Cecil.Cil.OpCodes]::Call, $pinvokeMethod)
        $ilMd.InsertAfter($inst, $callCompile)
        $patchedGfp = $true
        Write-Host "Patched GetFunctionPointer -> mono_compile_method in AccessTools.MethodDelegate!"
        break
    }
}
if (-not $patchedGfp) { throw "Failed to find GetFunctionPointer in AccessTools.MethodDelegate" }

# ==============================================================================
# 6. Patch StackTraceFixes.Install (Bypass in Unity)
# ==============================================================================
Write-Host "=== 6. Patching StackTraceFixes.Install ==="
$stFixesType = $mod.GetType("HarmonyLib.Internal.RuntimeFixes.StackTraceFixes")
$stInstall = $stFixesType.Methods | Where-Object { $_.Name -eq "Install" }
$stInstall.Body.Instructions.Clear()
$stInstall.Body.Variables.Clear()
$stInstall.Body.ExceptionHandlers.Clear()
$ilSt = $stInstall.Body.GetILProcessor()
$ilSt.Append($ilSt.Create([Mono.Cecil.Cil.OpCodes]::Ret))
Write-Host "StackTraceFixes.Install bypassed with immediate ret!"

# ==============================================================================
# 7. Patch ILHookExtensions (.cctor & GetCurrentTarget)
# ==============================================================================
Write-Host "=== 7. Patching ILHookExtensions ==="
$ilHookExtType = $mod.GetType("HarmonyLib.Internal.Util.ILHookExtensions")
$cctorIlHook = $ilHookExtType.Methods | Where-Object { $_.Name -eq ".cctor" }
$fGetAppliedDetour = $ilHookExtType.Fields | Where-Object { $_.Name -eq "GetAppliedDetour" }

# In .cctor, keep IL_0000 to IL_0023 (SetIsApplied initialization), then set GetAppliedDetour = null and ret
$cctorInstructions = $cctorIlHook.Body.Instructions
$idxStartDmd = -1
for ($i = 0; $i -lt $cctorInstructions.Count; $i++) {
    if ($cctorInstructions[$i].Offset -eq 0x0028) {
        $idxStartDmd = $i
        break
    }
}
if ($idxStartDmd -ge 0) {
    while ($cctorInstructions.Count -gt $idxStartDmd) {
        $cctorInstructions.RemoveAt($cctorInstructions.Count - 1)
    }
    $ilH = $cctorIlHook.Body.GetILProcessor()
    $ilH.Append($ilH.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))
    $ilH.Append($ilH.Create([Mono.Cecil.Cil.OpCodes]::Stsfld, $fGetAppliedDetour))
    $ilH.Append($ilH.Create([Mono.Cecil.Cil.OpCodes]::Ret))
    Write-Host "ILHookExtensions..cctor: bypassed DMD generation!"
}

# In GetCurrentTarget(ILHook hook), return hook.Method directly
$detourAss = [Mono.Cecil.AssemblyDefinition]::ReadAssembly("Client\BepInEx\core\MonoMod.RuntimeDetour.dll")
$ilHookType = $detourAss.MainModule.GetType("MonoMod.RuntimeDetour.ILHook")
$fHookMethod = $ilHookType.Fields | Where-Object { $_.Name -eq "Method" }
$fHookMethodRef = $mod.ImportReference($fHookMethod)

$getCurrentTarget = $ilHookExtType.Methods | Where-Object { $_.Name -eq "GetCurrentTarget" }
$getCurrentTarget.Body.Instructions.Clear()
$ilGct = $getCurrentTarget.Body.GetILProcessor()
$ilGct.Append($ilGct.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$ilGct.Append($ilGct.Create([Mono.Cecil.Cil.OpCodes]::Ldfld, $fHookMethodRef))
$ilGct.Append($ilGct.Create([Mono.Cecil.Cil.OpCodes]::Ret))
Write-Host "ILHookExtensions.GetCurrentTarget: patched to return hook.Method directly!"

# ==============================================================================
# Write output
# ==============================================================================
Write-Host "Writing patched 0Harmony.dll..."
$outMs = New-Object System.IO.MemoryStream
$harmonyAss.Write($outMs)
[System.IO.File]::WriteAllBytes($harmonyDestPath, $outMs.ToArray())
Write-Host "Successfully written patched 0Harmony.dll!"
