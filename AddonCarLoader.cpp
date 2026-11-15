// SPDX-License-Identifier: GPL-3.0-only
// AddonCarLoaderCE.asi for GTA IV Complete Edition 1.2.0.59:
//  1. loads update\common\data\addoncars.ide after every vanilla .ide, so add-on cars take the last model
//     slots and vanilla slots (stored by savegames for pickups) never move;
//  2. applies per-car sound settings, a port of fastman92 limit adjuster's GTA IV vehicle audio loader.
// INI format, file paths and struct layouts come from fastman92 limit adjuster 7.6
// (Copyright (C) fastman92, MIT License). Addresses below were found for 1.2.0.59 only.
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <unordered_map>
#include <vector>

#define VALIDATE_SIZE(s, n) static_assert(sizeof(s) == (n), #s " has wrong size")
struct tVehicleAudioSettings_base {};
#include "structs_from_fla.inc"
using namespace Game_GTAIV;
VALIDATE_SIZE(tVehicleAudioSettings, 0x164);

// ---- game addresses (1.2.0.59, preferred base 0x400000; the exe uses ASLR) ----
static uintptr_t g_base;
static uintptr_t A(uintptr_t va) { return va - 0x400000 + g_base; }

enum eListOfSounds { SOUND_LIST_SOUNDS, SOUND_LIST_CURVES, SOUND_LIST_GAME, SOUND_LIST_COUNT };
static const uintptr_t kContainers[SOUND_LIST_COUNT] = { 0x115DC18, 0x115DA04, 0x115DC74 };

typedef uint32_t(__cdecl* tHash)(const char* str, uint32_t initial);           // atStringHash, lower-case
typedef void* (__fastcall* tByHash)(void* container, void* edx, uint32_t hash); // thiscall
typedef void* (__fastcall* tByName)(void* audioMgr, void* edx, const char* name);
typedef void* (__cdecl* tGetModelInfo)(const char* name, int* pIndex);
typedef void(__cdecl* tVoid)();
typedef void(__cdecl* tLoadIde)(const char* path);

static tHash Hash;
static tByHash GetByHash;
static tByName GetByName;
static tGetModelInfo GetModelInfo;
static tVoid SortModelInfoHashes;
static tLoadIde LoadIde;
static void* g_audioMgr;
static void** g_modelInfoPtrs;
static uint32_t* g_episode;      // 0 = IV, 1 = TLAD, 2 = TBoGT
static void** g_vehStructPool;   // CVehicleModelInfo::CVehicleStructure::m_pInfoPool
static uintptr_t g_retCar, g_retHeli, g_retBoat;

// ---- loaded settings ----
static std::vector<tVehicleAudioSettings> g_entries;
static std::unordered_map<int, size_t> g_modelToEntry;
static char g_root[MAX_PATH];
static const char* g_curFile;

static void Msg(const char* fmt, ...)
{
	char buf[512];
	va_list va;
	va_start(va, fmt);
	vsnprintf(buf, sizeof(buf), fmt, va);
	va_end(va);
	MessageBoxA(NULL, buf, "Add-on Car Loader CE", MB_OK | MB_ICONWARNING);
}

// INI readers: same Win32 calls and parsing as FLA's CIniReader, so mods behave identically.
static void Str(const char* s, const char* k, char* out, DWORD n) { GetPrivateProfileStringA(s, k, "", out, n, g_curFile); }
static int Int(const char* s, const char* k) { char b[100]; Str(s, k, b, sizeof(b)); return b[0] ? atoi(b) : 0; }
static float Float(const char* s, const char* k) { char b[100]; Str(s, k, b, sizeof(b)); return b[0] ? (float)atof(b) : 0.0f; }

static uint32_t HashOf(const char* s, const char* k, eListOfSounds list)
{
	char name[128];
	Str(s, k, name, sizeof(name));
	if (!strcmp(name, "NULL"))
		return 0;
	if (!memcmp(name, "HASH_", 5))
		return strtoul(name + 5, NULL, 16);	// FLA used strtol, which clamps hashes >= 0x80000000

	uint32_t hash = Hash(name, 0);
	void* container = (void*)A(kContainers[list]);
	bool listLoaded = *(int32_t*)((char*)container + 0x3C) > 0;	// entry count
	if (name[0] && listLoaded && !GetByHash(container, NULL, hash))
		Msg("%s: sound with specified name does not exist.\n[%s] -> %s", g_curFile, s, k);
	return hash;
}

#define I(f)       p->f = Int(n, #f)
#define I100(f)    p->f = Int(n, #f) * 100
#define F(f)       p->f = Float(n, #f)
#define F100(f)    p->f = (int)(Float(n, #f) * 100)
#define F1200(f)   p->f = (int)(Float(n, #f) * 1200)
#define HS(f)      p->f = HashOf(n, #f, SOUND_LIST_SOUNDS)
#define HC(f)      p->f = HashOf(n, #f, SOUND_LIST_CURVES)
#define HG(f)      p->f = HashOf(n, #f, SOUND_LIST_GAME)

static void ReadCarBike(const char* n, tVehicleAudioSettingsCarBike* p)
{
	I(field_1); I(flags);
	F100(floatAsInt_A); F100(floatAsInt_E);
	HS(engineLowSound); HS(engineHighSound); HS(exhaustLowSound); HS(exhaustHighSound); HS(revsOffSound);
	F(field_26); F(field_2A); F100(floatAsInt_2E); F100(floatAsInt_32); F(field_36); F(field_3A);
	F100(floatAsInt_3E); F100(floatAsInt_42); F(field_46); F(field_4A); F100(floatAsInt_4E); F100(floatAsInt_52);
	F(field_56); F(field_5A); F100(floatAsInt_5E); F100(floatAsInt_62); F100(floatAsInt_66); F(field_6A); F(field_6E);
	F100(floatAsInt_72); F100(floatAsInt_76);
	HC(engineWaveShape); F100(floatAsInt_7E); HC(exhaustWaveShape); F100(floatAsInt_86);
	F1200(floatAsInt_multiplier1200_8A); F1200(floatAsInt_multiplier1200_8E);
	HS(engineIdleLoopSound); HS(exhaustIdleLoopSound);
	F1200(floatAsInt_multiplier1200_9A); F1200(floatAsInt_multiplier1200_9E);
	HS(transmissionSound); F100(floatAsInt_A6); F100(floatAsInt_AA); HS(sound_AE); F100(floatAsInt_B2); F100(floatAsInt_B6);
	HS(exhaustPopSound); HS(airIntakeSound);
	F1200(floatAsInt_multiplier1200_C2); F1200(floatAsInt_multiplier1200_C6);
	HS(dumpValveSound); HS(startSound); HS(hornSound); HS(openSound); HS(closeSound); HS(trunkOpenSound); HS(trunkCloseSound);
	F(field_E6); HS(suspensionUpSound); HS(suspensionDownSound); F(field_F2); F(field_F6);
	HS(policeScannerManufacturerSound); HS(policeScannerModelSound); HS(policeScannerVehicleCategorySound);
	HS(gearTransmissionSound);
	F1200(floatAsInt_multiplier1200_10A); F1200(floatAsInt_multiplier1200_10E); F1200(floatAsInt_multiplier1200_112);
	F100(floatAsInt_116); I(field_11A); F100(floatAsInt_11E); F100(floatAsInt_122); F100(floatAsInt_126);
	HS(jumpLandSound); I(field_12E); I(field_132); HS(ignitionSound); HS(engineShutDownSound);
	I(field_13E); I(field_13F); I(field_140); I(field_141);
	HS(indicatorVehicleOn); HS(indicatorVehicleOff); HS(engineCoolingFan); HS(handbrakeSound_14E);
	HS(sound_152); HS(sound_156); HS(handbrakeSound_15A);
	I(field_15E); I(field_15F); I(field_160);
}

static void ReadHeli(const char* n, tVehicleAudioSettingsHeli* p)
{
	I(field_1); I(flags);
	HS(rotorSound); HS(rearRotorSound); HS(exHaustSound); HS(bankSound); HS(internalCabinToneSound); F(field_1E);
	HC(bankAngleVolumeSound); HC(bankThrottleVolumeSound); HC(bankThrottlePitchCurveSound);
	HC(rotorThrottleVolumeSound); HC(rotorThrottlePitchCurveSound); HC(rotorThrottleGapSound);
	HC(rearRotorThrottleVolumeSound); HC(exhaustThrottleVolumeSound); HC(exhaustThrottlePitchCurveSound);
	I(field_46); I(field_48); F100(floatAsInt_4A); I(field_4C); I(field_4E); F100(floatAsInt_50);
	I(field_52); I(field_54); F100(floatAsInt_56); F(field_58); F(field_5C);
	HC(throttleResonance1Sound); F(field_64); F(field_68); HC(throttleResonance2Sound); HC(bankingResonanceCurveSound);
	HC(rotorVolumeStartupCurveSound); HC(bladeVolumeStartupCurveSound); HC(rotorPitchStartupCurveSound);
	HC(rearRotorVolumeStartupCurveSound); HC(exhaustVolumeStartupCurveSound); HC(rotorGapStartupCurveSound);
	HS(shotStartSound);
	I(field_90); I(field_92); F100(floatAsInt_94); I(field_96); I(field_98);
	I100(floatAsInt_9A);	// FLA reads this one as int * 100; kept identical
	HS(policeScannerManufacturerSound); HS(policeScannerModelSound); HS(policeScannerVehicleCategorySound);
	I(field_A8); I(field_A9);
	HS(doorOpenSound); HS(doorCloseSound); HS(doorLimitSound); HS(damageLoopSound);
}

static void ReadBoat(const char* n, tVehicleAudioSettingsBoat* p)
{
	I(field_1); I(flags);
	HS(engineLoopSound); HC(engineVolumeSound); HC(enginePitchSound_12);
	HS(engine2loopSound); HC(engine2volumeSound); HC(enginePitchSound_1E);
	HS(lowResonanceLoopSound); HC(resonanceVolumeSound); HC(enginePitchSound_2A);
	HS(idleLoopSound); HC(idleResonanceVolumeSound); HC(enginePitchSound_36);
	HS(waterTurbulanceSound); HC(waterTurbulanceVolumeSound);
	I(field_42); F(field_46); F(field_4A); F100(floatAsInt_4E); F100(floatAsInt_52); F(field_56); F(field_5A);
	F100(floatAsInt_5E); F100(floatAsInt_62); F(field_66); F(field_6A); F100(floatAsInt_6E); F100(floatAsInt_72);
	F(field_76); F(field_7A); F100(floatAsInt_7E); F100(floatAsInt_82); F100(floatAsInt_86); F(field_8A); F(field_8E);
	F100(floatAsInt_92); F100(floatAsInt_96);
	HC(linearRise_9A); I(field_9E); HC(linearRise_A2); I(field_A6);
	HS(policeScannerManufacturerSound); HS(policeScannerModelSound); HS(policeScannerVehicleCategorySound);
	I(field_B6); I(field_B7);
	HS(hornSound); HG(materialSound); HS(ignitionSound); HS(shutDownSound); I(field_C8);
}

static void LoadFile(const char* relPath)
{
	// A copy in the update\ overload folder wins, like it does for game files
	char path[MAX_PATH * 2];
	snprintf(path, sizeof(path), "%s\\update\\%s", g_root, relPath);
	if (GetFileAttributesA(path) == INVALID_FILE_ATTRIBUTES)
	{
		snprintf(path, sizeof(path), "%s\\%s", g_root, relPath);
		if (GetFileAttributesA(path) == INVALID_FILE_ATTRIBUTES)
			return;
	}
	g_curFile = path;

	std::vector<char> names(1 << 16);
	GetPrivateProfileSectionNamesA(names.data(), (DWORD)names.size(), path);

	for (const char* n = names.data(); *n; n += strlen(n) + 1)
	{
		int modelIndex = -1;
		if (!GetModelInfo(n, &modelIndex))
		{
			Msg("%s: model with name %s does not exist.", relPath, n);
			continue;
		}

		tVehicleAudioSettings s;
		memset(&s, 0, sizeof(s));
		int structType = Int(n, "structType");
		s.carBike.structType = (char)structType;

		if (structType == 0)
			ReadCarBike(n, &s.carBike);
		else if (structType == 4)
			ReadHeli(n, &s.heli);
		else if (structType == 7)
			ReadBoat(n, &s.boat);
		else
		{
			Msg("%s: model with name %s has structType %d which is unknown.", relPath, n, structType);
			continue;
		}

		g_modelToEntry[modelIndex] = g_entries.size();
		g_entries.push_back(s);
	}
}

// One INI per car: every *.ini in relDir, from update\ and the game folder (update\ wins on equal names)
static void LoadFolder(const char* relDir)
{
	std::vector<std::string> names;
	for (const char* prefix : { "update\\", "" })
	{
		char pattern[MAX_PATH * 2];
		snprintf(pattern, sizeof(pattern), "%s\\%s%s\\*.ini", g_root, prefix, relDir);
		WIN32_FIND_DATAA fd;
		HANDLE h = FindFirstFileA(pattern, &fd);
		if (h == INVALID_HANDLE_VALUE)
			continue;
		do
		{
			bool seen = false;
			for (const auto& n : names)
				seen |= !_stricmp(n.c_str(), fd.cFileName);
			if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && !seen)
				names.push_back(fd.cFileName);
		} while (FindNextFileA(h, &fd));
		FindClose(h);
	}
	for (const auto& n : names)
		LoadFile((std::string(relDir) + "\\" + n).c_str());	// LoadFile picks the update\ copy first
}

static void __cdecl LoadAll()
{
	g_entries.clear();
	g_modelToEntry.clear();
	SortModelInfoHashes();	// GetModelInfo binary-searches this table; no-op when already sorted

	LoadFile("pc\\audio\\Config\\gtaiv_vehicleAudioSettings.ini");
	LoadFile("pc\\audio\\Config\\addedVehicleAudioSettings.ini");
	LoadFolder("pc\\audio\\Config\\vehicleAudio");

	// CE keeps episodes in TLAD\ and TBoGT\ next to the exe (same as FusionFix's currentEpisodePath)
	if (*g_episode == 1)
		LoadFile("TLAD\\pc\\audio\\config\\TLAD_vehicleAudioSettings.ini");
	else if (*g_episode == 2)
		LoadFile("TBoGT\\pc\\audio\\config\\TBoGT_vehicleAudioSettings.ini");
}

// Returns our settings for the vehicle's model, else what the game would have returned.
static void* __cdecl GetSettings(uint8_t* audioEntity, uint32_t vehicleOffset)
{
	uint8_t* vehicle = *(uint8_t**)(audioEntity + vehicleOffset);
	int modelIndex = *(int16_t*)(vehicle + 0x2E);

	auto it = g_modelToEntry.find(modelIndex);
	if (it != g_modelToEntry.end())
		return &g_entries[it->second];

	const char* gameName = (const char*)g_modelInfoPtrs[modelIndex] + 0x60;
	return GetByName(g_audioMgr, NULL, gameName);
}

// 0x98BA80: car/bike lookup, ecx = audio entity, vehicle at +0x820
__declspec(naked) static void StubCar()
{
	__asm {
		push 820h
		push ecx
		call GetSettings
		add esp, 8
		jmp g_retCar
	}
}

// 0x98C1A9: helicopter lookup, ecx = audio entity, vehicle at +0x820; game still falls back to DEFAULT_HELI
__declspec(naked) static void StubHeli()
{
	__asm {
		push 820h
		push ecx
		call GetSettings
		add esp, 8
		jmp g_retHeli
	}
}

// 0xC27A81: boat lookup, esi = audio entity, vehicle at +0x250
__declspec(naked) static void StubBoat()
{
	__asm {
		push 250h
		push esi
		call GetSettings
		add esp, 8
		jmp g_retBoat
	}
}

// 0xA7B115: replaces "mov [m_pInfoPool], eax; ret" after vehicle model infos are set up (FLA's load point)
__declspec(naked) static void StubLoad()
{
	__asm {
		mov ecx, g_vehStructPool
		mov [ecx], eax
		push eax
		call LoadAll
		pop eax
		ret
	}
}

// Replaces the model-table sort right after the last vanilla .ide (0x9D6497, in IV and both episodes).
// Add-on cars registered here get the highest model slots, so no vanilla slot moves: savegames store
// pickups by slot, and cars added to vehicles.ide shift every later model (seagulls load as rail cars).
static void __cdecl LoadAddonIdeThenSort()
{
	LoadIde("common:/data/addoncars.ide");	// update\common\data\addoncars.ide via the overload folder; missing file is skipped
	SortModelInfoHashes();
}

// ---- add-on car names: update\common\data\addoncars.fxt, FLA FXT syntax "GXT_KEY  Text", '#' comments ----
// The HUD shows TheText.Get(gameName) (5th column of the .ide line); add-on keys are not in the game's .gxt.
static std::unordered_map<std::string, std::wstring> g_texts;
static void* g_textGetOriginal;	// trampoline: the 8 relocated prologue bytes + jmp back

static void LoadTexts()
{
	for (const char* prefix : { "update\\", "" })
	{
		char path[MAX_PATH * 2];
		snprintf(path, sizeof(path), "%s\\%scommon\\data\\addoncars.fxt", g_root, prefix);
		FILE* f = NULL;
		if (fopen_s(&f, path, "rb") || !f)
			continue;
		char line[1024];
		while (fgets(line, sizeof(line), f))
		{
			char* p = line + (memcmp(line, "\xEF\xBB\xBF", 3) ? 0 : 3);	// UTF-8 BOM
			while (*p == ' ' || *p == '\t') p++;
			if (!*p || *p == '#' || *p == '\r' || *p == '\n')
				continue;
			char* key = p;
			while (*p && *p != ' ' && *p != '\t' && *p != '\r' && *p != '\n') p++;
			std::string k(key, p);
			while (*p == ' ' || *p == '\t') p++;
			char* end = p + strlen(p);
			while (end > p && (end[-1] == '\r' || end[-1] == '\n' || end[-1] == ' ' || end[-1] == '\t')) end--;
			for (auto& c : k) c = (char)toupper((unsigned char)c);
			int n = MultiByteToWideChar(CP_UTF8, 0, p, (int)(end - p), NULL, 0);
			std::wstring w(n, L'\0');
			MultiByteToWideChar(CP_UTF8, 0, p, (int)(end - p), &w[0], n);
			g_texts[k] = w;
		}
		fclose(f);
		return;	// update\ copy wins
	}
}

static const wchar_t* __cdecl LookupText(const char* key)
{
	if (!key || g_texts.empty())
		return NULL;
	char up[64];
	size_t i = 0;
	for (; key[i] && i < sizeof(up) - 1; i++)
		up[i] = (char)toupper((unsigned char)key[i]);
	up[i] = 0;
	auto it = g_texts.find(up);
	return it == g_texts.end() ? NULL : it->second.c_str();
}

// 0x8C5BE0 CText::Get(const char* key), thiscall, ret 4
__declspec(naked) static void HookTextGet()
{
	__asm {
		push ecx
		push dword ptr [esp + 8]
		call LookupText
		add esp, 4
		pop ecx
		test eax, eax
		jz original
		ret 4
	original:
		jmp g_textGetOriginal
	}
}

// "??" matches any byte; absolute addresses are relocated under ASLR so they are left as wildcards.
static bool Match(uintptr_t va, const char* hex)
{
	const uint8_t* p = (const uint8_t*)A(va);
	for (; *hex; hex += (hex[2] ? 3 : 2), p++)
		if (hex[0] != '?' && *p != (uint8_t)strtoul(std::string(hex, 2).c_str(), NULL, 16))
			return false;
	return true;
}

static void Branch(uintptr_t va, void* to, uint8_t opcode)
{
	uint8_t* at = (uint8_t*)A(va);
	DWORD old;
	VirtualProtect(at, 5, PAGE_EXECUTE_READWRITE, &old);
	at[0] = opcode;
	*(int32_t*)(at + 1) = (int32_t)((uintptr_t)to - (uintptr_t)at - 5);
	VirtualProtect(at, 5, old, &old);
	FlushInstructionCache(GetCurrentProcess(), at, 5);
}

// File version of the game's exe ("1.2.0.59"); empty when it has none.
static std::string ExeVersion()
{
	char path[MAX_PATH];
	GetModuleFileNameA(NULL, path, MAX_PATH);
	DWORD unused, size = GetFileVersionInfoSizeA(path, &unused);
	std::vector<char> info(size);
	VS_FIXEDFILEINFO* v;
	UINT len;
	if (!size || !GetFileVersionInfoA(path, 0, size, info.data()) || !VerQueryValueA(info.data(), "\\", (void**)&v, &len))
		return "";
	char s[64];
	snprintf(s, sizeof(s), "%u.%u.%u.%u", HIWORD(v->dwFileVersionMS), LOWORD(v->dwFileVersionMS),
		HIWORD(v->dwFileVersionLS), LOWORD(v->dwFileVersionLS));
	return s;
}

// The ASI loader reads plugins from the game folder, plugins\ and scripts\.
static bool HasAsi(const char* name)
{
	for (const char* dir : { "plugins\\", "scripts\\", "" })
	{
		char path[MAX_PATH * 2];
		snprintf(path, sizeof(path), "%s\\%s%s", g_root, dir, name);
		if (GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES)
			return true;
	}
	return false;
}

static void Install()
{
	g_base = (uintptr_t)GetModuleHandleA(NULL);

	std::string version = ExeVersion();
	if (version != "1.2.0.59")
	{
		Msg("This plugin needs GTA IV Complete Edition 1.2.0.59. This game is %s.\nAdd-on car loading and sounds are disabled.",
			version.empty() ? "an unknown version" : version.c_str());
		return;
	}
	// FusionFix loads the cars' .img archives from update\; the rest still works without it
	if (!HasAsi("GTAIV.EFLC.FusionFix.asi"))
		Msg("GTAIV.EFLC.FusionFix.asi was not found.\nAdd-on cars need FusionFix to load their models from the update folder.");

	bool ok =
		Match(0xA7B115, "A3 ?? ?? ?? ?? C3") &&
		Match(0x98BA80, "E8 1B 11 00 00 50 B9 ?? ?? ?? ?? E8 30 94 F0 FF") &&
		Match(0x98C1A9, "E8 F2 09 00 00 50 B9 ?? ?? ?? ?? E8 07 8D F0 FF") &&
		Match(0xC27A81, "50 B9 ?? ?? ?? ?? E8 34 D4 C6 FF") &&
		Match(0x9DC6F0, "51 FF 74 24 08 E8 56 87 EF FF") &&
		Match(0x9DDF00, "80 3D ?? ?? ?? ?? 00 75 2B") &&
		Match(0x899740, "51 53 8B 5C 24 0C 55 56 8B C1 57 8B 70 3C") &&
		Match(0x894EC0, "81 C1 D4 02 00 00 E9 F5 48 00 00") &&
		Match(0x9D6497, "E8 64 7A 00 00") &&	// call 0x9DDF00 (model-table sort) after the last .ide
		Match(0x9D7BD0, "81 EC 0C 01 00 00") &&	// .ide file loader
		*(uintptr_t*)A(0xA7B116) == A(0x12FA84C);
	if (!ok)
	{
		Msg("Another mod already patched the code this plugin hooks (or this plugin is installed twice).\nAdd-on car loading and sounds are disabled.");
		return;
	}

	Hash = (tHash)A(0x40BA60);
	GetByHash = (tByHash)A(0x899740);
	GetByName = (tByName)A(0x894EC0);
	GetModelInfo = (tGetModelInfo)A(0x9DC6F0);
	SortModelInfoHashes = (tVoid)A(0x9DDF00);
	LoadIde = (tLoadIde)A(0x9D7BD0);
	g_audioMgr = (void*)A(0x115D9A0);
	g_modelInfoPtrs = (void**)A(0x1295CD8);
	g_episode = (uint32_t*)A(0x11D6FD0);
	g_vehStructPool = (void**)A(0x12FA84C);

	g_retCar = A(0x98BA90);
	g_retHeli = A(0x98C1B9);
	g_retBoat = A(0xC27A8C);

	// Names are optional: a mismatch here (another mod hooking CText::Get first) only skips this part
	if (Match(0x8C5BE0, "83 EC 44 A1 ?? ?? ?? ?? 33 C4"))
	{
		LoadTexts();
		uint8_t* tramp = (uint8_t*)VirtualAlloc(NULL, 16, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
		memcpy(tramp, (void*)A(0x8C5BE0), 8);	// sub esp,44h; mov eax,[__security_cookie] (already relocated)
		tramp[8] = 0xE9;
		*(int32_t*)(tramp + 9) = (int32_t)(A(0x8C5BE8) - (uintptr_t)(tramp + 8) - 5);
		g_textGetOriginal = tramp;
		Branch(0x8C5BE0, &HookTextGet, 0xE9);
	}

	Branch(0x9D6497, &LoadAddonIdeThenSort, 0xE8);	// call
	Branch(0xA7B115, &StubLoad, 0xE9);			// jmp
	Branch(0x98BA80, &StubCar, 0xE9);
	Branch(0x98C1A9, &StubHeli, 0xE9);
	Branch(0xC27A81, &StubBoat, 0xE9);
}

BOOL WINAPI DllMain(HINSTANCE, DWORD reason, LPVOID)
{
	if (reason == DLL_PROCESS_ATTACH)
	{
		GetModuleFileNameA(NULL, g_root, MAX_PATH);
		if (char* slash = strrchr(g_root, '\\'))
			*slash = 0;
		Install();
	}
	return TRUE;
}
