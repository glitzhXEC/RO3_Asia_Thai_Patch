$cecilBytes = [System.IO.File]::ReadAllBytes("_TranslationWorkspace\Mono.Cecil.dll.orig")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$utilsPath = "Client\BepInEx\core\MonoMod.Utils.dll"
$utilsBytes = [System.IO.File]::ReadAllBytes($utilsPath)
$utilsAss = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((New-Object System.IO.MemoryStream(,$utilsBytes)))
$mod = $utilsAss.MainModule

$cilGenType = $mod.GetType("MonoMod.Utils.Cil.CecilILGenerator")
$mUnderField = $cilGenType.Methods | Where-Object { $_.Name -eq "_" -and $_.Parameters.Count -eq 1 -and $_.Parameters[0].ParameterType.Name -eq "FieldInfo" }
$mUnderType = $cilGenType.Methods | Where-Object { $_.Name -eq "_" -and $_.Parameters.Count -eq 1 -and $_.Parameters[0].ParameterType.Name -eq "Type" }

# Target constructors and methods to call:
$mscorlibAss = [Mono.Cecil.AssemblyDefinition]::ReadAssembly("Client\ro3_Data\Managed\mscorlib.dll")
$memberInfoType = $mscorlibAss.MainModule.GetType("System.Reflection.MemberInfo")
$mGetName = $mod.ImportReference(($memberInfoType.Methods | Where-Object { $_.Name -eq "get_Name" }))
$mGetDeclaringType = $mod.ImportReference(($memberInfoType.Methods | Where-Object { $_.Name -eq "get_DeclaringType" }))

$fieldInfoType = $mscorlibAss.MainModule.GetType("System.Reflection.FieldInfo")
$mGetFieldType = $mod.ImportReference(($fieldInfoType.Methods | Where-Object { $_.Name -eq "get_FieldType" }))

$cecilAss = [Mono.Cecil.AssemblyDefinition]::ReadAssembly((New-Object System.IO.MemoryStream(,$cecilBytes)))
$frType = $cecilAss.MainModule.GetType("Mono.Cecil.FieldReference")
$frCtor = $frType.Methods | Where-Object { $_.IsConstructor -and $_.Parameters.Count -eq 3 }
$frCtorRef = $mod.ImportReference($frCtor)

Write-Host "Rebuilding CecilILGenerator._(FieldInfo)..."
$mUnderField.Body.Instructions.Clear()
$il = $mUnderField.Body.GetILProcessor()

# 1. field.Name
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $mGetName))

# 2. this._(field.FieldType)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $mGetFieldType))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $mUnderType))

# 3. this._(field.DeclaringType)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_1))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $mGetDeclaringType))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call, $mUnderType))

# 4. new FieldReference(name, fieldType, declaringType)
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Newobj, $frCtorRef))
$il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))

$outMs = New-Object System.IO.MemoryStream
$utilsAss.Write($outMs)
[System.IO.File]::WriteAllBytes($utilsPath, $outMs.ToArray())
Write-Host "Successfully patched CecilILGenerator._(FieldInfo) in MonoMod.Utils.dll!"
