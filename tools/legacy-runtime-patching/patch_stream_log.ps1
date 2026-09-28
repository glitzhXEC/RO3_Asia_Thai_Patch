$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null
$preloaderPath = "Client\BepInEx\core\BepInEx.Preloader.dll"
$bytes = [System.IO.File]::ReadAllBytes($preloaderPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)
$type = $assembly.MainModule.GetType("BepInEx.Preloader.PreloaderConsoleListener")
$m = $type.Methods | Where-Object { $_.Name -eq "LogEvent" }

$il = $m.Body.GetILProcessor()
$lastRet = $m.Body.Instructions[$m.Body.Instructions.Count - 1]

$appendMethod = [System.IO.File].GetMethod("AppendAllText", [type[]]@([string], [string]))
$appendRef = $assembly.MainModule.ImportReference($appendMethod)
$toStrMethod = [System.Object].GetMethod("ToString", [type[]]@())
$toStrRef = $assembly.MainModule.ImportReference($toStrMethod)
$concatMethod = [System.String].GetMethod("Concat", [type[]]@([string], [string]))
$concatRef = $assembly.MainModule.ImportReference($concatMethod)

$il.InsertBefore($lastRet, $il.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "preloader_stream.log"))
$il.InsertBefore($lastRet, $il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_2))
$il.InsertBefore($lastRet, $il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt, $toStrRef))
$il.InsertBefore($lastRet, $il.Create([Mono.Cecil.Cil.OpCodes]::Ldstr, "`r`n"))
$il.InsertBefore($lastRet, $il.Create([Mono.Cecil.Cil.OpCodes]::Call, $concatRef))
$il.InsertBefore($lastRet, $il.Create([Mono.Cecil.Cil.OpCodes]::Call, $appendRef))

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($preloaderPath, $outMs.ToArray())
Write-Output "Injected stream logger into PreloaderConsoleListener.LogEvent!"
