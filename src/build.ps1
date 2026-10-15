[CmdletBinding()]
param(
    [string]$Compiler = 'cl.exe',
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'build'),
    [string]$ClangResourceDirectory = ''
)
$ErrorActionPreference = 'Stop'
if ($env:VSCMD_ARG_TGT_ARCH -and $env:VSCMD_ARG_TGT_ARCH -ne 'x86') {
    throw 'Use a Visual Studio x86 developer environment, not x64.'
}
$tool = Get-Command $Compiler -ErrorAction Stop
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$outputPath = (Resolve-Path -LiteralPath $OutputDirectory).Path
$minhook = Join-Path $PSScriptRoot 'third_party\minhook'
$arguments = @('/nologo', '/MT', '/O2', '/EHsc', '/W4', '/LD', "/I$minhook\include")
if ($tool.Name -like '*clang-cl*') {
    $arguments += '--target=i686-pc-windows-msvc'
    if ($ClangResourceDirectory) { $arguments += "/clang:-resource-dir=$ClangResourceDirectory" }
}
$arguments += @(
    (Join-Path $PSScriptRoot 'src\impact_native.cpp'),
    (Join-Path $minhook 'src\buffer.c'),
    (Join-Path $minhook 'src\hook.c'),
    (Join-Path $minhook 'src\trampoline.c'),
    (Join-Path $minhook 'src\hde\hde32.c'),
    '/Fe:impact_native_release_v1.dll', '/link', '/MACHINE:X86'
)
Push-Location -LiteralPath $outputPath
try {
    & $tool.Source @arguments
    if ($LASTEXITCODE -ne 0) { throw "Compiler failed with exit code $LASTEXITCODE." }
    Write-Output "Built: $(Join-Path $outputPath 'impact_native_release_v1.dll')"
} finally {
    Pop-Location
}
