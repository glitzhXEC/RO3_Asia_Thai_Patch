$preloaderPath = "C:\Path\To\RO3 Asia Launcher\Client\BepInEx\core\BepInEx.Preloader.dll"
$cecilBytes = [System.IO.File]::ReadAllBytes("C:\Path\To\RO3 Asia Launcher\Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null
$bytes = [System.IO.File]::ReadAllBytes($preloaderPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)
$type = $assembly.MainModule.GetType("BepInEx.Preloader.Preloader")
$run = $type.Methods | Where-Object { $_.Name -eq "Run" }
$ins = $run.Body.Instructions[1]
$ins.OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
$ins.Operand = $null
$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($preloaderPath, $outMs.ToArray())
Write-Output "Patched successfully!"