Add-Type -Path 'Client\BepInEx\core\Mono.Cecil.dll'

$dllPath = "Client\BepInEx\plugins\XUnity.AutoTranslator\XUnity.AutoTranslator.Plugin.Core.dll"
$bytes = [System.IO.File]::ReadAllBytes($dllPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)
$mod = $assembly.MainModule

$trm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly('Client\ro3_Data\Managed\UnityEngine.TextRenderingModule.dll')
$fontType = $trm.MainModule.GetType('UnityEngine.Font')
$m_createFont = $fontType.Methods | Where-Object { $_.Name -eq 'CreateDynamicFontFromOSFont' -and $_.Parameters.Count -eq 2 -and $_.Parameters[0].ParameterType.Name -eq 'String' }

$tmp = [Mono.Cecil.AssemblyDefinition]::ReadAssembly('Client\ro3_Data\Managed\Unity.TextMeshPro.dll')
$tmpFontType = $tmp.MainModule.GetType('TMPro.TMP_FontAsset')
$m_createTmp = $tmpFontType.Methods | Where-Object { $_.Name -eq 'CreateFontAsset' -and $_.Parameters.Count -eq 1 }

$ucm = [Mono.Cecil.AssemblyDefinition]::ReadAssembly('Client\ro3_Data\Managed\UnityEngine.CoreModule.dll')
$objType = $ucm.MainModule.GetType('UnityEngine.Object')
$m_dontDestroy = $objType.Methods | Where-Object { $_.Name -eq 'DontDestroyOnLoad' }

$ref_createFont = $mod.ImportReference($m_createFont)
$ref_createTmp = $mod.ImportReference($m_createTmp)
$ref_dontDestroy = $mod.ImportReference($m_dontDestroy)

$stringType = $mod.TypeSystem.String
$m_isNullOrEmpty = ($mod.TypeSystem.String.Resolve().Methods | Where-Object { $_.Name -eq 'IsNullOrEmpty' })
$ref_isNullOrEmpty = $mod.ImportReference($m_isNullOrEmpty)

# Target method: FontHelper.GetTextMeshProFont(string)
$fhType = $mod.GetType('XUnity.AutoTranslator.Plugin.Core.Fonts.FontHelper')
$targetMethod = $fhType.Methods | Where-Object { $_.Name -eq 'GetTextMeshProFont' }

$targetMethod.Body.Instructions.Clear()
$targetMethod.Body.Variables.Clear()
$targetMethod.Body.ExceptionHandlers.Clear()

$fontVar = New-Object Mono.Cecil.Cil.VariableDefinition($ref_createFont.ReturnType)
$tmpVar = New-Object Mono.Cecil.Cil.VariableDefinition($ref_createTmp.ReturnType)
$targetMethod.Body.Variables.Add($fontVar)
$targetMethod.Body.Variables.Add($tmpVar)

$il = $targetMethod.Body.GetILProcessor()

$lblHasName = $il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0)
$lblGotFont = $il.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_0)
$lblMakeTmp = $il.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_0)
$lblDone = $il.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_1)

# Check if fontName is null or empty
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $ref_isNullOrEmpty))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brfalse_S, $lblHasName))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "Yu Gothic UI"))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Starg_S, $targetMethod.Parameters[0]))

# CreateDynamicFontFromOSFont(fontName, 28)
$il.Append($lblHasName)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_S, [sbyte]28))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $ref_createFont))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stloc_0))

# Fallback to Meiryo if font is null
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brtrue_S, $lblGotFont))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "Meiryo"))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldc_I4_S, [sbyte]28))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $ref_createFont))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stloc_0))

# Check font != null
$il.Append($lblGotFont)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brtrue_S, $lblMakeTmp))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldnull))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))

# Make TMP FontAsset
$il.Append($lblMakeTmp)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $ref_dontDestroy))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $ref_createTmp))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Stloc_1))

# DontDestroyOnLoad(tmp)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_1))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Brfalse_S, $lblDone))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_1))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $ref_dontDestroy))

$il.Append($lblDone)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($dllPath, $outMs.ToArray())
Write-Output "Successfully patched FontHelper.GetTextMeshProFont in AutoTranslator!"
