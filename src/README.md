# Impact Frames native helper source

Source for `impact_native_release_v1.dll`, shipped with Impact Frames for Ashita v4, addon release 1.2.1. The same native binary has been used throughout the release series; recent UI, race-scope and knockback changes are in the Lua addon.

This archive contains no compiled DLL or object files. It includes the exact release C++ source, the complete vendored MinHook dependency and its license, and a build script. It is intended for review and approval; it is not an addon installation package.

## Build

Requirements: Windows, Visual Studio C++ build tools (x86 compiler/libraries), and a Windows SDK. No dependency download is performed by the build script.

Open an **x86 Native Tools Command Prompt for Visual Studio**, change to this source folder, and run:

```powershell
powershell -NoProfile -File .\build.ps1
```

The output is `build/impact_native_release_v1.dll`. This must be **32-bit**, even on 64-bit Windows, because FFXI's process is 32-bit. MinHook is compiled into the helper; a separate MinHook DLL is not needed.

The original release was built using clang-cl 20 with MSVC 14.44.35207 libraries and Windows SDK 10.0.26100.0. To use clang-cl instead of cl.exe, provide its path through `-Compiler`. If its bundled headers are not found automatically, supply `-ClangResourceDirectory` too. MSVC SDK/library environment variables must still be configured for x86.

`RELEASE_REFERENCE.json` records the shipped binary hash, source hash, original build flags, dependency commit, architecture and exported functions. Different compiler versions, timestamps and linker settings can produce different binary hashes; the reference hash identifies the distributed binary rather than promising a byte-identical rebuild with any toolchain.

## What the DLL does

- Finds the loaded FFXI client animation-update routine through unique signatures and validates surrounding code before hooking it with MinHook.
- Temporarily skips playback updates for actor pointers explicitly queued by the Lua addon. Each requested pause is capped at 1000 ms and begins on the first intercepted playback call.
- Optionally pauses/resumes actor-owned WS effect task trees through client functions. Stored task identities are checked against the live list before resuming.
- Supports cancelling one actor's hold or all holds, and removes its hook on shutdown. The DLL remains mapped for the game session to protect callback lifetime.

It does modify client executable code to install the animation hook. It has no networking implementation, does not parse or alter packets, does not write player coordinates, and contains no experimental audio hook or appearance changer.

The Lua addon decides when freezes are queued and when your own character's reported knockback cancels them. Review the accompanying addon source as well if approval covers the complete addon rather than this DLL alone. No game executable, game DAT asset, character configuration, or capture is bundled here.

## Files

- `src/impact_native.cpp`: release helper implementation.
- `third_party/minhook/`: vendored MinHook source at commit `c3fcafdc10146beb5919319d0683e44e3c30d537`, including `LICENSE.txt`.
- `build.ps1`: x86 release build script.
- `RELEASE_REFERENCE.json`: distributed binary metadata.
- `BUILD_VERIFICATION.json`: result of rebuilding this packaged source with its build script; the rebuilt code section matches the distributed DLL.
- `MANIFEST.sha256`: source archive file checksums.

Addon author: Zarianna (100% vibe coded).
