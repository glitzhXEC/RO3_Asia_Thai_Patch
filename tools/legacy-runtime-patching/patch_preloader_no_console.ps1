$preloaderPath = "C:\Path\To\RO3 Asia Launcher\Client\BepInEx\core\BepInEx.Preloader.dll"
$cecilBytes = [System.IO.File]::ReadAllBytes("C:\Path\To\RO3 Asia Launcher\Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null
$bytes = [System.IO.File]::ReadAllBytes($preloaderPath)
$ms = New-Object System.IO.MemoryStream(,$bytes)
$assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)
$type = $assembly.MainModule.GetType("BepInEx.Preloader.Preloader")
$run = $type.Methods | Where-Object { $_.Name -eq "Run" }

# 命令 2 (ldc.i4.0), 3 (call ConsoleManager::Initialize), 4 (call AllocateConsole) を Nop に変更
$run.Body.Instructions[2].OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
$run.Body.Instructions[2].Operand = $null
$run.Body.Instructions[3].OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
$run.Body.Instructions[3].Operand = $null
$run.Body.Instructions[4].OpCode = [Mono.Cecil.Cil.OpCodes]::Nop
$run.Body.Instructions[4].Operand = $null

$outMs = New-Object System.IO.MemoryStream
$assembly.Write($outMs)
[System.IO.File]::WriteAllBytes($preloaderPath, $outMs.ToArray())
Write-Output "Patched Console calls out of Preloader.Run!"