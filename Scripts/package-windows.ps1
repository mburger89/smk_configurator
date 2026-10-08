# Lays out a movable Windows build of the configurator in dist\ (cross-platform
# plan section 3):
#
#   dist\SMKConfigurator.exe                          the executable (release,
#                                                     or -Configuration debug)
#   dist\SMKConfigurator_SMKConfigurator.bundle\      the icons (Bundle.module;
#                                                     `.resources` under
#                                                     --build-system native)
#   dist\MetalUISDLShaders\                           MetalUI's compiled SDL GPU
#                                                     shaders (MetalUI PX-P: looked
#                                                     for beside the executable)
#   dist\SDL3.dll, dist\hidapi.dll                    the two native libraries
#
# AccessKit is linked statically. The Swift runtime is not copied: the user
# needs the Swift redistributable (or a Swift toolchain) installed.
#
# The flags are the build's own (SDL3, hidapi and AccessKit include and
# library paths, as .github/workflows/windows-build.yml passes them); the
# DLLs are looked for in -DllDirs, in order.
#
# Usage:
#   powershell -File Scripts\package-windows.ps1 -SwiftFlags $flags `
#     -DllDirs "$sdlRoot\lib\x64","vcpkg_installed\x64-windows\bin" [-Dist dist] [-ScratchPath .build]
param(
    [string[]] $SwiftFlags = @(),
    [string[]] $DllDirs = @(),
    [string] $Dist = "dist",
    [string] $ScratchPath = ".build",
    # release by default; debug is the fallback where the toolchain cannot
    # build release (gap MG-27)
    [ValidateSet("release", "debug")] [string] $Configuration = "release"
)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

& swift build -c $Configuration --scratch-path $ScratchPath @SwiftFlags
if ($LASTEXITCODE) { exit $LASTEXITCODE }
$bin = (& swift build -c $Configuration --scratch-path $ScratchPath @SwiftFlags --show-bin-path | Select-Object -Last 1).Trim()
$shaders = Join-Path $ScratchPath "checkouts\MetalUI\Backends\SDL\Shaders\compiled"
if (-not (Test-Path (Join-Path $shaders "SOURCE.sha256"))) { throw "no compiled shaders at $shaders" }

if (Test-Path $Dist) { Remove-Item -Recurse -Force $Dist }
New-Item -ItemType Directory -Force $Dist | Out-Null
Copy-Item (Join-Path $bin "SMKConfigurator.exe") $Dist
# Swift 6.4's default build system (swiftbuild) names the resource bundle
# `.bundle`; the native build system names it `.resources`. Bundle.module
# looks for that name beside the executable.
$bundles = @("bundle", "resources") | ForEach-Object { Join-Path $bin "SMKConfigurator_SMKConfigurator.$_" } | Where-Object { Test-Path $_ }
if (-not $bundles) { throw "no resource bundle in $bin" }
$bundles | ForEach-Object { Copy-Item -Recurse $_ $Dist }
Copy-Item -Recurse $shaders (Join-Path $Dist "MetalUISDLShaders")
foreach ($dll in @("SDL3.dll", "hidapi.dll")) {
    $found = $DllDirs | ForEach-Object { Join-Path $_ $dll } | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $found) { throw "$dll not found in: $($DllDirs -join ', ')" }
    Copy-Item $found $Dist
}
Write-Host "packaged into ${Dist}:"
Get-ChildItem $Dist | Select-Object -ExpandProperty Name
