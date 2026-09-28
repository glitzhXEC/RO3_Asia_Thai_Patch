$preloaderPath = "C:\Path\To\RO3 Asia Launcher\Client\BepInEx\core\BepInEx.Preloader.dll"
$cecilBytes = [System.IO.File]::ReadAllBytes("C:\Path\To\RO3 Asia Launcher\Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null
$bytes = [System.IO.File]::ReadAllBytes($preloaderPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)
$type = $assembly.MainModule.GetType("BepInEx.Preloader.Preloader")
$m = $type.Methods | Where-Object { $_.Name -eq "GetUnityVersion" }

$m.Body.Instructions.Clear()
$il = $m.Body.GetILProcessor()
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ldstr, "2022.3.62f3")
$il.Emit([Mono.Cecil.Cil.OpCodes]::Ret)

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($preloaderPath, $outMs.ToArray())
Write-Output "Patched GetUnityVersion successfully!"