$bepDir = "C:\Path\To\RO3 Asia Launcher\Client\BepInEx"
$cecilBytes = [System.IO.File]::ReadAllBytes("$bepDir\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

$harmonyPath = "$bepDir\core\0Harmony.dll"
$bytes = [System.IO.File]::ReadAllBytes($harmonyPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)
$type = $assembly.MainModule.GetType("HarmonyLib.AccessTools")
$method = $type.Methods | Where-Object { $_.Name -eq "Method" -and $_.Parameters.Count -eq 4 }

$exTypeDef = [Mono.Cecil.AssemblyDefinition]::ReadAssembly("C:\Path\To\RO3 Asia Launcher\Client\ro3_Data\Managed\mscorlib.dll")
$exType = $exTypeDef.MainModule.GetType("System.Reflection.AmbiguousMatchException")
$singleCtor = $exType.Methods | Where-Object { $_.IsConstructor -and $_.Parameters.Count -eq 1 }
$ctorRef = $assembly.MainModule.ImportReference($singleCtor)

$il = $method.Body.GetILProcessor()
for ($i = 0; $i -lt $method.Body.Instructions.Count; $i++) {
    $ins = $method.Body.Instructions[$i]
    if ($ins.OpCode.Name -eq "newobj" -and $ins.Operand.ToString() -like "*AmbiguousMatchException*") {
        $pop = $il.Create([Mono.Cecil.Cil.OpCodes]::Pop)
        $il.InsertBefore($ins, $pop)
        $ins.Operand = $ctorRef
        Write-Output "Patched 0Harmony.dll AmbiguousMatchException ctor successfully!"
        break
    }
}
$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($harmonyPath, $outMs.ToArray())