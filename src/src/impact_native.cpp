#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#include <stdint.h>
#include <cstring>
#include "MinHook.h"

// Phoenix capture: thiscall motion update(this=motion, actor, channel), ret 8.
using Playback = void (__thiscall*)(void*, void*, int);
static Playback original = nullptr;
static void* entry = nullptr;
static volatile LONG player = 0;
struct ActorPause { volatile LONG actor=0, deadline=0, skipped=0, pending=0, started=0, begun=0; };
static ActorPause slots[64];
static volatile LONG playerCalls = 0, stoppedCalls = 0;
static int state = 0;

using FxTree=void (__thiscall*)(void*);
static FxTree fxPauseTree=nullptr,fxResumeTree=nullptr;
static void** fxManagerPointer=nullptr;
static bool effectSync=false;
struct FxHold { void* root=nullptr;void* owner=nullptr;void* resource=nullptr; };
static FxHold fxHolds[128];
static unsigned fxHeldCount=0;
static bool fxReadable(const void* p,size_t n) {
 MEMORY_BASIC_INFORMATION info{};
 if(!p||!VirtualQuery(p,&info,sizeof(info))||info.State!=MEM_COMMIT||(info.Protect&(PAGE_NOACCESS|PAGE_GUARD)))return false;
 return reinterpret_cast<uintptr_t>(p)+n<=reinterpret_cast<uintptr_t>(info.BaseAddress)+info.RegionSize;
}
static void syncEffects(void* actor,bool pause) {
 if(!pause){
  if(!fxHeldCount)return;
  if(actor){bool held=false;for(auto& hold:fxHolds)if(hold.root&&hold.owner==actor){held=true;break;}if(!held)return;}
 }
 if(!fxPauseTree||!fxResumeTree||!fxReadable(fxManagerPointer,4)||!fxReadable(*fxManagerPointer,0xD54))return;
 auto task=*reinterpret_cast<unsigned char**>(reinterpret_cast<unsigned char*>(*fxManagerPointer)+0xD50);
 for(unsigned guard=0;task&&guard<8192;guard++) {
  if(!fxReadable(task,0x34))break;
  auto next=*reinterpret_cast<unsigned char**>(task+0x0C);
  if(pause&&effectSync&&fxReadable(task,0x84)&&*reinterpret_cast<uint32_t*>(task+0x1C)==0x4D730000 &&
   *reinterpret_cast<void**>(task+0x40)==actor) {
   bool descendant=false;
   auto parent=*reinterpret_cast<unsigned char**>(task+0x10);
   for(unsigned depth=0;parent&&depth<32;depth++) {
    if(!fxReadable(parent,0x84))break;
    if(*reinterpret_cast<uint32_t*>(parent+0x1C)==0x4D730000&&*reinterpret_cast<void**>(parent+0x40)==actor){descendant=true;break;}
    parent=*reinterpret_cast<unsigned char**>(parent+0x10);
   }
   if(!descendant) {
    FxHold* freeSlot=nullptr;bool held=false;
    for(auto& hold:fxHolds){if(hold.root==task)held=true;else if(!hold.root&&!freeSlot)freeSlot=&hold;}
    if(!held&&freeSlot){freeSlot->root=task;freeSlot->owner=actor;freeSlot->resource=*reinterpret_cast<void**>(task+0x80);fxHeldCount++;fxPauseTree(task);}
   }
  } else if(!pause) {
   for(auto& hold:fxHolds)if(hold.root==task&&(!actor||hold.owner==actor)) {
    if(fxReadable(task,0x84)&&*reinterpret_cast<void**>(task+0x40)==hold.owner&&*reinterpret_cast<void**>(task+0x80)==hold.resource)fxResumeTree(task);
    hold={};fxHeldCount--;
   }
  }
  task=next;
 }
 if(!pause)for(auto& hold:fxHolds)if(hold.root&&(!actor||hold.owner==actor)){hold={};fxHeldCount--;} // discard destroyed roots without dereferencing them
}
static unsigned char* findFx(unsigned char* module,const unsigned char* pattern,const char* mask,size_t length) {
 auto dos=reinterpret_cast<IMAGE_DOS_HEADER*>(module);auto nt=reinterpret_cast<IMAGE_NT_HEADERS*>(module+dos->e_lfanew);
 auto sections=IMAGE_FIRST_SECTION(nt);unsigned char* found=nullptr;
 for(unsigned sec=0;sec<nt->FileHeader.NumberOfSections;sec++){
  if(!(sections[sec].Characteristics&IMAGE_SCN_MEM_EXECUTE))continue;
  auto code=module+sections[sec].VirtualAddress;size_t size=sections[sec].Misc.VirtualSize;
  for(size_t pos=0;pos+length<=size;pos++){
   if(code[pos]!=pattern[0])continue;bool match=true;
   for(size_t j=1;j<length;j++)if(mask[j]=='x'&&code[pos+j]!=pattern[j]){match=false;break;}
   if(match){if(found)return nullptr;found=code+pos;}
  }
 }
 return found;
}
static void initializeEffects(unsigned char* module) {
    const unsigned char fxPausePattern[]={0x56,0x57,0x8B,0xF9,0x8B,0x77,0x24,0x85,0xF6,0x74,0x0E,0x8B,0xCE,0xE8,0xEE,0xFF,0xFF,0xFF,0x8B,0x76,0x28,0x85,0xF6,0x75,0xF2,0x66,0xFF,0x47,0x22,0x5F};
    auto fxPauseAddress=findFx(module,fxPausePattern,"xxxxxxxxxxxxxx????xxxxxxxxxxxx",sizeof(fxPausePattern));
    const unsigned char fxResumePattern[]={0x56,0x57,0x8B,0xF9,0x8B,0x77,0x24,0x85,0xF6,0x74,0x0E,0x8B,0xCE,0xE8,0xEE,0xFF,0xFF,0xFF,0x8B,0x76,0x28,0x85,0xF6,0x75,0xF2,0x66,0x8B,0x47,0x22,0x66,0x85,0xC0,0x76,0x05,0x48};
    auto fxResumeAddress=findFx(module,fxResumePattern,"xxxxxxxxxxxxxx????xxxxxxxxxxxxxxxxx",sizeof(fxResumePattern));
    const unsigned char fxManagerPattern[]={0xA1,0x40,0xD1,0x3A,0x05,0x56,0x8B,0xB0,0x4C,0x0D,0x00,0x00,0x89,0x88,0x4C,0x0D,0x00,0x00,0x8B,0x01,0xFF,0x50,0x20,0x8B,0x0D,0x40,0xD1,0x3A,0x05,0x89,0xB1,0x4C,0x0D,0x00,0x00};
    auto fxManagerAddress=findFx(module,fxManagerPattern,"x????xxxxxxxxxxxxxxxxxxxx????xxxxxx",sizeof(fxManagerPattern));
 if(!fxPauseAddress||!fxResumeAddress||!fxManagerAddress)return;
 fxPauseTree=reinterpret_cast<FxTree>(fxPauseAddress);fxResumeTree=reinterpret_cast<FxTree>(fxResumeAddress);
 fxManagerPointer=*reinterpret_cast<void***>(fxManagerAddress+1);
}
extern "C" __declspec(dllexport) int __cdecl impact_effect_sync_available(){return fxPauseTree&&fxResumeTree&&fxManagerPointer?1:0;}
extern "C" __declspec(dllexport) void __cdecl impact_set_effect_sync(int enabled){if(!enabled)syncEffects(nullptr,false);effectSync=enabled!=0;}
extern "C" __declspec(dllexport) int __cdecl impact_effect_holds(){return static_cast<int>(fxHeldCount);}

static void __fastcall playback(void* motion, void*, void* actor, int channel) {
    const LONG address = static_cast<LONG>(reinterpret_cast<uintptr_t>(actor));
    if (address && address == InterlockedCompareExchange(&player,0,0))
        InterlockedIncrement(&playerCalls);
    if (address) for (auto& slot:slots) {
        if (address!=InterlockedCompareExchange(&slot.actor,0,0)) continue;
        const LONG duration=InterlockedExchange(&slot.pending,0);
        if(duration>0) {
            const DWORD now=GetTickCount();
            InterlockedExchange(&slot.started,static_cast<LONG>(now));
            InterlockedExchange(&slot.deadline,static_cast<LONG>(now+duration));
            InterlockedExchange(&slot.begun,1);
            syncEffects(actor,true);
        }
        if (static_cast<int32_t>(GetTickCount()-static_cast<DWORD>(InterlockedCompareExchange(&slot.deadline,0,0)))<0) {
            InterlockedIncrement(&slot.skipped);InterlockedIncrement(&stoppedCalls);
            return;
        }
        break;
    }
    syncEffects(actor,false);
    original(motion,actor,channel);
}
static int attach(void* target) {
    if (entry) return state;
    auto status=MH_Initialize();
    if (status!=MH_OK && status!=MH_ERROR_ALREADY_INITIALIZED) return state=-4;
    status=MH_CreateHook(target,reinterpret_cast<void*>(&playback),reinterpret_cast<void**>(&original));
    if (status!=MH_OK) { MH_Uninitialize();return state=-5; }
    status=MH_EnableHook(target);
    if (status!=MH_OK) { MH_RemoveHook(target);MH_Uninitialize();return state=-6; }
    entry=target;state=1;
    return state;
}
extern "C" __declspec(dllexport) int __cdecl impact_initialize() {
    if (entry) return state;
    auto module=reinterpret_cast<unsigned char*>(GetModuleHandleW(L"FFXiMain.dll"));
    if (!module) return state=-1;
    auto dos=reinterpret_cast<IMAGE_DOS_HEADER*>(module);
    auto nt=reinterpret_cast<IMAGE_NT_HEADERS*>(module+dos->e_lfanew);
    if (dos->e_magic!=IMAGE_DOS_SIGNATURE || nt->Signature!=IMAGE_NT_SIGNATURE) return state=-2;
    auto sections=IMAGE_FIRST_SECTION(nt);
    unsigned char* match=nullptr;
    const unsigned char signature[]={0xD8,0x05,0,0,0,0,0xEB,0x0C,0xE8,0,0,0,0,0xD8,0x4C,0x24,0x10};
    for (unsigned s=0;s<nt->FileHeader.NumberOfSections;++s) {
        if (!(sections[s].Characteristics & IMAGE_SCN_MEM_EXECUTE)) continue;
        const size_t size=sections[s].Misc.VirtualSize;
        auto data=module+sections[s].VirtualAddress;
        for (size_t i=0;i+sizeof(signature)<=size;++i) {
            bool same=true;
            for (size_t j=0;j<sizeof(signature);++j) {
                if ((j>=2 && j<=5)||(j>=9 && j<=12)) continue;
                if (data[i+j]!=signature[j]) { same=false;break; }
            }
            if (same) {
                if (match) return state=-2; // Never guess when signature is ambiguous.
                if (i<0xC3 || i+0x1B3+3>size) return state=-3;
                match=data+i;
            }
        }
    }
    if (!match) return state=-2;
    auto target=match-0xC3;
    const unsigned char prologue[]={0x83,0xEC,0x0C,0x56,0x8B,0xF1,0x57,0x8B,0x46,0x34,0x8D,0x7E,0x34,0x85,0xC0};
    const unsigned char writeFrame[]={0xD9,0x5E,0x24,0xD9,0x46,0x24};
    const unsigned char actorUse[]={0x8B,0x4C,0x24,0x18,0x6A,0x01,0x8B,0x01,0xFF,0x90,0xFC,0x01,0x00,0x00};
    if (memcmp(target,prologue,sizeof(prologue)) || memcmp(match+0x14,writeFrame,sizeof(writeFrame)) ||
        memcmp(match+0x6E,actorUse,sizeof(actorUse))) return state=-3;
    // Keep the helper mapped for the game session, including addon reloads.
    HMODULE pinned=nullptr;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
        reinterpret_cast<LPCWSTR>(&impact_initialize),&pinned)) return state=-7;
    initializeEffects(module);
    int result=attach(target);
    return result;
}
extern "C" __declspec(dllexport) void __cdecl impact_set_player(uint32_t actor) {
    InterlockedExchange(&player,static_cast<LONG>(actor));
}
extern "C" __declspec(dllexport) int __cdecl impact_pause(uint32_t actor,int milliseconds) {
    if (state!=1 || !actor || milliseconds<=0 || milliseconds>1000) return 0;
    const LONG address=static_cast<LONG>(actor);
    ActorPause* chosen=nullptr;
    for (auto& slot:slots) if (InterlockedCompareExchange(&slot.actor,0,0)==address) {chosen=&slot;break;}
    if (!chosen) for (auto& slot:slots) {
        const LONG old=InterlockedCompareExchange(&slot.actor,0,0);
        if (!old || (InterlockedCompareExchange(&slot.pending,0,0)==0 &&
            static_cast<int32_t>(GetTickCount()-static_cast<DWORD>(InterlockedCompareExchange(&slot.deadline,0,0)))>=0)) {
            // Publish the deadline first; actor=0 prevents transient matching.
            InterlockedExchange(&slot.actor,0);InterlockedExchange(&slot.skipped,0);
            chosen=&slot;break;
        }
    }
    if (!chosen) return 0;
    InterlockedExchange(&chosen->begun,0);
    InterlockedExchange(&chosen->deadline,static_cast<LONG>(GetTickCount()));
    InterlockedExchange(&chosen->pending,milliseconds);
    InterlockedExchange(&chosen->actor,address);
    return 1;
}
extern "C" __declspec(dllexport) void __cdecl impact_cancel_actor(uint32_t actor) {
    syncEffects(reinterpret_cast<void*>(actor),false);
    for (auto& slot:slots) if (InterlockedCompareExchange(&slot.actor,0,0)==static_cast<LONG>(actor)) {
        InterlockedExchange(&slot.pending,0);InterlockedExchange(&slot.begun,0);
        InterlockedExchange(&slot.deadline,static_cast<LONG>(GetTickCount()));
    }
}
extern "C" __declspec(dllexport) int __cdecl impact_actor_pause_age(uint32_t actor) {
    for(auto& slot:slots) if(InterlockedCompareExchange(&slot.actor,0,0)==static_cast<LONG>(actor)) {
        if(!InterlockedCompareExchange(&slot.begun,0,0))return -1;
        return static_cast<int32_t>(GetTickCount()-static_cast<DWORD>(InterlockedCompareExchange(&slot.started,0,0)));
    }
    return -1;
}
extern "C" __declspec(dllexport) uint32_t __cdecl impact_actor_stopped(uint32_t actor) {
    for (auto& slot:slots) if (InterlockedCompareExchange(&slot.actor,0,0)==static_cast<LONG>(actor))
        return static_cast<uint32_t>(InterlockedCompareExchange(&slot.skipped,0,0));
    return 0;
}
extern "C" __declspec(dllexport) void __cdecl impact_cancel() {
    syncEffects(nullptr,false);
    for (auto& slot:slots) {
        InterlockedExchange(&slot.pending,0);InterlockedExchange(&slot.begun,0);
        InterlockedExchange(&slot.deadline,static_cast<LONG>(GetTickCount()));
    }
}
extern "C" __declspec(dllexport) uint32_t __cdecl impact_player_calls() { return static_cast<uint32_t>(InterlockedCompareExchange(&playerCalls,0,0)); }
extern "C" __declspec(dllexport) uint32_t __cdecl impact_stopped_calls() { return static_cast<uint32_t>(InterlockedCompareExchange(&stoppedCalls,0,0)); }
extern "C" __declspec(dllexport) void __cdecl impact_shutdown() {
    impact_cancel();InterlockedExchange(&player,0);
    if (entry) { MH_DisableHook(entry);MH_RemoveHook(entry);MH_Uninitialize();entry=nullptr;original=nullptr;state=0; }
}
#ifdef IMPACT_TEST
extern "C" int impact_attach_test(void* target) { return attach(target); }
#endif
