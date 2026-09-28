$bepDir = "C:\Path\To\RO3 Asia Launcher\Client\BepInEx"
$cecilBytes = [System.IO.File]::ReadAllBytes("$bepDir\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

# 1. Patch 0Harmony.dll
$harmonyPath = "$bepDir\core\0Harmony.dll"
$bytes = [System.IO.File]::ReadAllBytes($harmonyPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)
$type = $assembly.MainModule.GetType("HarmonyLib.AccessTools")
$method = $type.Methods | Where-Object { $_.Name -eq "Method" -and $_.Parameters.Count -eq 5 }

# AmbiguousMatchException(string) コンストラクタへの参照を取得
$mscorlib = $assembly.MainModule.TypeSystem.CoreLibrary
$exTypeDef = [Mono.Cecil.AssemblyDefinition]::ReadAssembly("C:\Path\To\RO3 Asia Launcher\Client\ro3_Data\Managed\mscorlib.dll")
$exType = $exTypeDef.MainModule.GetType("System.Reflection.AmbiguousMatchException")
$singleCtor = $exType.Methods | Where-Object { $_.IsConstructor -and $_.Parameters.Count -eq 1 }
$ctorRef = $assembly.MainModule.ImportReference($singleCtor)

$il = $method.Body.GetILProcessor()
for ($i = 0; $i -lt $method.Body.Instructions.Count; $i++) {
    $ins = $method.Body.Instructions[$i]
    if ($ins.OpCode.Name -eq "newobj" -and $ins.Operand.ToString() -like "*AmbiguousMatchException*") {
        # 直前にある第2引数（Exception）を pop するか、ロード命令を除去
        # newobj の前に pop を挿入し、operand を singleCtor に変更
        $pop = $il.Create([Mono.Cecil.Cil.OpCodes]::Pop)
        $il.InsertBefore($ins, $pop)
        $ins.Operand = $ctorRef
        Write-Output "Patched 0Harmony.dll AmbiguousMatchException ctor!"
        break
    }
}
$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($harmonyPath, $outMs.ToArray())

# 2. Patch BepInEx.Preloader.dll
$preloaderPath = "$bepDir\core\BepInEx.Preloader.dll"
$bytes = [System.IO.File]::ReadAllBytes($preloaderPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)

# SetPlatform の ARM/GetPEKind スキップ
$type = $assembly.MainModule.GetType("BepInEx.Preloader.PlatformUtils")
$method = $type.Methods | Where-Object { $_.Name -eq "SetPlatform" }
$targetIns = $method.Body.Instructions | Where-Object { $_.Offset -eq 0x01D6 }
$destIns = $method.Body.Instructions | Where-Object { $_.Offset -eq 0x01FF }
$targetIns.OpCode = [Mono.Cecil.Cil.OpCodes]::Br_S
$targetIns.Operand = $destIns
foreach ($ins in $method.Body.Instructions) {
    if ($ins.Offset -gt 0x01D6 -and $ins.Offset -lt 0x01FF) {
        $ins.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
        $ins.Operand = $null
    }
}

# Preloader.Run の HarmonyInteropFix と TraceLogSource スキップ
$preloaderType = $assembly.MainModule.GetType("BepInEx.Preloader.Preloader")
$run = $preloaderType.Methods | Where-Object { $_.Name -eq "Run" }
# HarmonyInteropFix::Apply を Nop
$run.Body.Instructions[1].OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
$run.Body.Instructions[1].Operand = $null

# TraceLogSource::CreateSource をスキップ
for ($i = 0; $i -lt $run.Body.Instructions.Count; $i++) {
    $ins = $run.Body.Instructions[$i]
    if ($ins.Operand -like "*TraceLogSource::CreateSource*") {
        $ins.OpCode = [Mono.Cecil.Cil.OpCodes]::Ldnull
        $ins.Operand = $null
        Write-Output "Patched TraceLogSource::CreateSource!"
        break
    }
}

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($preloaderPath, $outMs.ToArray())
Write-Output "Patched BepInEx.Preloader.dll!"