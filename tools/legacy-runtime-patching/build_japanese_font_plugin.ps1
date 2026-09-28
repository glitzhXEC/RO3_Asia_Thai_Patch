$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$src = "_TranslationWorkspace\JapaneseFontPlugin.cs"
$outDll = "Client\BepInEx\plugins\RO3.JapaneseFont.dll"

$refs = @(
    "Client\ro3_Data\Managed\mscorlib.dll",
    "Client\ro3_Data\Managed\System.dll",
    "Client\ro3_Data\Managed\System.Core.dll",
    "Client\ro3_Data\Managed\UnityEngine.CoreModule.dll",
    "Client\ro3_Data\Managed\UnityEngine.TextRenderingModule.dll",
    "Client\ro3_Data\Managed\Unity.TextMeshPro.dll",
    "Client\BepInEx\core\BepInEx.dll"
)

$refArgs = ($refs | ForEach-Object { "/r:`"$_`"" }) -join " "

$cmd = "& `"$csc`" /target:library /out:`"$outDll`" $refArgs `"$src`""
Write-Output "Compiling: $cmd"
Invoke-Expression $cmd

if (Test-Path $outDll) {
    Write-Output "Successfully compiled $outDll! Size: $((Get-Item $outDll).Length) bytes"
} else {
    Write-Error "Compilation failed!"
}
