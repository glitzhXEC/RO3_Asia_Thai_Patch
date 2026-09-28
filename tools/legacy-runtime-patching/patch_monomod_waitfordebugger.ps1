$cecilBytes = [System.IO.File]::ReadAllBytes("Client\BepInEx\core\Mono.Cecil.dll")
[System.Reflection.Assembly]::Load($cecilBytes) | Out-Null

foreach ($dllName in @("MonoMod.Utils.dll", "MonoMod.RuntimeDetour.dll")) {
    $dllPath = "Client\BepInEx\core\$dllName"
    $bytes = [System.IO.File]::ReadAllBytes($dllPath)
    $ms = New-Object System.IO.MemoryStream(,$bytes)
    $assembly = [Mono.Cecil.AssemblyDefinition]::ReadAssembly($ms)
    $type = $assembly.MainModule.GetType("MonoMod.MMDbgLog")
    if ($type -ne $null) {
        $m = $type.Methods | Where-Object { $_.Name -eq "WaitForDebugger" }
        if ($m -ne $null) {
            $m.Body.Instructions.Clear()
            $il = $m.Body.GetILProcessor()
            $il.Emit([Mono.Cecil.Cil.OpCodes]::Ret)
            $outMs = New-Object System.IO.MemoryStream
            $assembly.Write($outMs)
            [System.IO.File]::WriteAllBytes($dllPath, $outMs.ToArray())
            Write-Output ("Patched WaitForDebugger in " + $dllName)
        }
    }
}
