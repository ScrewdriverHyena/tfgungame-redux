#define TFGG_MAIN
#define PLUGIN_VERSION "1.4"

#include <sourcemod>
#include <sdkhooks>
#include <tf2>
#include <tf2_stocks>
#include <tf2items>
#include <tfgungame>

#pragma semicolon 1
#pragma newdecls required

#include "tfgungame_ggweapon.sp"

//#define DEBUG

public Plugin myinfo =
{
	name = "TFGunGame: Redux",
	author = "Frosty Scales",
	description = "GunGame - Run through a series of weapons, first person to get a kill with the final weapon wins.",
	version = PLUGIN_VERSION,
	url = "https://github.com/koopa516"
};

#define MAX_WEAPONS 64

stock const char LASTRANK_SOUND[] = ""; // TODO
stock const char WIN_SOUND[] = ""; // TODO
stock const char HUMILIATION_SOUND[] = ""; // TODO
stock const char strCleanTheseEntities[][256] = 
{
	"info_populator",
	"info_passtime_ball_spawn",
	"tf_logic_arena",
	"tf_logic_hybrid_ctf_cp",
	"tf_logic_koth",
	"tf_logic_mann_vs_machine",
	"tf_logic_medieval",
	"tf_logic_multiple_escort",
	"tf_logic_player_destruction",
	"tf_logic_robot_destruction",
	"team_control_point",
	"team_control_point_master",
	"team_control_point_round",
	"team_train_watcher",
	"item_teamflag",
	"trigger_capture_area",
	"trigger_passtime_ball",
	"trigger_rd_vault_trigger"
};

stock const int g_iClassMaxHP[view_as<int>(TFClassType)] =
{
	0,
	125,
	125,
	200,
	175,
	150,
	300,
	175,
	125,
	125
};

enum TFGGSpecialRoundType
{
	SpecialRound_None = 0,
	SpecialRound_Melee = 1,
	SpecialRound_MeleeToo = 2,
	SpecialRound_AllCrits = 3,
	
	TFGGSRT_COUNT
};

stock const char g_strSpecialRoundSeries[TFGGSRT_COUNT][PLATFORM_MAX_PATH] =
{
	"configs/gungame-series.cfg",
	"configs/gungame-series-melee-only.cfg",
	"configs/gungame-series-melee.cfg",
	"configs/gungame-series.cfg"
};

stock const char g_strSpecialRoundName[TFGGSRT_COUNT][32] =
{
	"None",
	"Melee Weapons Only",
	"Melee Weapons Enabled",
	"100% Critical Hits"
};

stock const char g_strArmModels[10][128] =
{
	"",
	"models/weapons/c_models/c_scout_arms.mdl",
	"models/weapons/c_models/c_sniper_arms.mdl",
	"models/weapons/c_models/c_soldier_arms.mdl",
	"models/weapons/c_models/c_demoman_arms.mdl",
	"models/weapons/c_models/c_medic_arms.mdl",
	"models/weapons/c_models/c_heavy_arms.mdl",
	"models/weapons/c_models/c_pyro_arms.mdl",
	"models/weapons/c_models/c_spy_arms.mdl",
	"models/weapons/c_models/c_engineer_arms.mdl"
};

const float HINT_REFRESH_INTERVAL = 5.0;

int g_iRank[MAXPLAYERS+1];
int g_iRankBuffer[MAXPLAYERS+1];
int g_iAssists[MAXPLAYERS+1];
int g_iViewmodelEnt[2049];
int g_iWorldmodelEnt[2049];
int g_iWearableOwner[2049];
int g_iTiedEnt[2049];
bool g_bOnlyVisIfActive[2049];
bool g_bHasWearableTied[2049];
bool g_bLate;
bool g_bRoundActive;

Handle g_hGetMaxAmmo;
Handle g_hGetMaxClip1;
Handle g_hEquipWearable;

Handle hFwdOnWin;
Handle hFwdRankUp;
Handle hFwdRankDown;

ConVar g_hCvarSpawnProtect;
ConVar g_hCvarAllowSuicide;
ConVar g_hCvarLastRankSound;
ConVar g_hCvarWinSound;
ConVar g_hCvarHumiliationSound;
ConVar g_hCvarSpecialRounds;
ConVar g_hCvarSpecialRoundChance;

TFGGSpecialRoundType g_eForceNextSpecial = SpecialRound_None;
TFGGSpecialRoundType g_eCurrentSpecial = SpecialRound_None;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	g_bLate = late;
	
	CreateNative("GGWeapon.GGWeapon", Native_GGWeapon);
	CreateNative("GGWeapon.Init", Native_GGWeaponInit);
	CreateNative("GGWeapon.InitSeries", Native_GGWeaponInitSeries);
	CreateNative("GGWeapon.Total", Native_GGWeaponTotal);
	CreateNative("GGWeapon.SeriesTotal", Native_GGWeaponSeriesTotal);
	CreateNative("GGWeapon.GetFromIndex", Native_GGWeaponGetFromIndex);
	CreateNative("GGWeapon.PushToSeries", Native_GGWeaponPushToSeries);
	CreateNative("GGWeapon.GetFromSeries", Native_GGWeaponGetFromSeries);
	CreateNative("GGWeapon.GetFromAll", Native_GGWeaponGetFromAll);
	CreateNative("GGWeapon.GetName", Native_GGWeaponGetName);
	CreateNative("GGWeapon.GetClassname", Native_GGWeaponGetClassname);
	CreateNative("GGWeapon.GetAttributeOverride", Native_GGWeaponGetAttributeOverride);
	CreateNative("GGWeapon.Index.get", Native_GGWeaponIndex);
	CreateNative("GGWeapon.Class.get", Native_GGWeaponClass);
	CreateNative("GGWeapon.Slot.get", Native_GGWeaponSlot);
	CreateNative("GGWeapon.Disabled.get", Native_GGWeaponDisabled);
	CreateNative("GGWeapon.FlagsOverride.get", Native_GGWeaponFlagsOverride);
	CreateNative("GGWeapon.ClipOverride.get", Native_GGWeaponClipOverride);
	CreateNative("GGWeapon.GetModelOverride", Native_GGWeaponGetModelOverride);
	CreateNative("GGWeapon.GetViewmodelOverride", Native_GGWeaponGetViewmodelOverride);
	CreateNative("GGWeapon.ModelIndex.get", Native_GGWeaponClipOverride);
	
	CreateNative("GetGunGameRank", Native_GetRank);
	CreateNative("ForceGunGameWin", Native_ForceWin);
	CreateNative("ForceGunGameRank", Native_ForceRank);
	CreateNative("ForceGunGameRankUp", Native_ForceRankUp);
	CreateNative("ForceGunGameRankDown", Native_ForceRankDown);
	
	hFwdOnWin = CreateGlobalForward("OnGunGameWin", ET_Ignore, Param_Cell);
	hFwdRankUp = CreateGlobalForward("OnGunGameRankUp", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	hFwdRankDown = CreateGlobalForward("OnGunGameRankDown", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("tfggr_version", PLUGIN_VERSION, "Plugin Version", FCVAR_ARCHIVE);
	g_hCvarSpawnProtect = 		CreateConVar("tfgg_spawnprotect_length", "-1.0", "Length of the spawn protection for players, set to 0.0 to disable and -1.0 for infinite length", true);
	g_hCvarAllowSuicide = 		CreateConVar("tfgg_allow_suicide", "0", "Set to 1 to not humiliate players when they suicide", _, true, 0.0, true, 1.0);
	g_hCvarLastRankSound = 		CreateConVar("tfgg_last_rank_sound", LASTRANK_SOUND, "Sound played when someone has hit the last rank");
	g_hCvarWinSound = 			CreateConVar("tfgg_win_sound", WIN_SOUND, "Sound played when someone wins the game");
	g_hCvarHumiliationSound = 	CreateConVar("tfgg_humiliation_sound", HUMILIATION_SOUND, "Sound played on humiliation");
	g_hCvarSpecialRounds = 		CreateConVar("tfgg_enable_special_rounds", "1", "Enable Special Rounds", _, true, 0.0, true, 1.0);
	g_hCvarSpecialRoundChance = CreateConVar("tfgg_special_round_chance", "25", "Special round chance; Should be a percent value out of 100", _, true, 0.0, true, 1.0);
	
	g_hCvarLastRankSound.AddChangeHook(OnChangeSound);
	g_hCvarWinSound.AddChangeHook(OnChangeSound);
	g_hCvarHumiliationSound.AddChangeHook(OnChangeSound);
	
	RegAdminCmd("sm_forcenextspecial", Command_ForceNextSpecial, ADMFLAG_ROOT, "Force the next special round. 0 - None, 1 - Melee, 2 - Double, 3 - Crits");
	
	GGWeapon.Init();
	HookEvent("teamplay_round_start", 			OnTFRoundStart);
	HookEvent("player_spawn", 					OnPlayerSpawn);
	HookEvent("post_inventory_application", 	OnReloadPlayerWeapons);
	HookEvent("player_death", 					OnPlayerDeath);
	HookEvent("player_death", 					OnPlayerDeathPre, 		EventHookMode_Pre);
	
	
	
	if (g_bLate)
	{
		ServerCommand("mp_restartgame 1");
		PrintToChatAll("\x07FFA500[GunGame]\x07FFFFFF Late-load detected! Restarting round...");
	}
	
	ServerCommand("mp_respawnwavetime 0");
	ServerCommand("tf_use_fixed_weaponspreads 1");
	ServerCommand("tf_damage_disablespread 1");
	ServerCommand("tf_weapon_criticals 0");
	ServerCommand("mp_autoteambalance 1");
	
	RegConsoleCmd("gg_help", Command_Help, "Sends a player a help panel");
	
	PrepSDK();
	
	LoadTranslations("tfgungame.phrases");
	
	//PrecacheSound(LASTRANK_SOUND, true);
	//PrecacheSound(WIN_SOUND, true);
	//PrecacheSound(HUMILIATION_SOUND, true);
}

stock int SuperPrecacheModel(char[] strModel, bool bPreload = false)
{
	if (!FileExists(strModel, true) || strlen(strModel) <= 1)
		return 0;
	
	char strDepFile[PLATFORM_MAX_PATH], strLine[PLATFORM_MAX_PATH];
	int iModel;
	Format(strDepFile, sizeof(strDepFile), "%s.dep", strModel);
	if (!FileExists(strDepFile, true))
	{
		PrintToServer("[GunGame] Precaching file: %s", strModel);
		iModel = PrecacheModel(strModel);
	}
	else
	{
		File hDepFile = OpenFile(strDepFile, "r", true);
		if (hDepFile == null)
			SetFailState("[GunGame] Dependency file %s is not readable! Check file permissions.", strDepFile);
		
		while (!hDepFile.EndOfFile())
		{
			hDepFile.ReadLine(strLine, sizeof(strLine));
			
			CleanString(strLine);
			
			if (!FileExists(strLine, true) || strlen(strModel) <= 1)
				SetFailState("[GunGame] Missing file %s listed as dependency!", strLine);
			
			PrintToServer("[GunGame] Precaching file: %s", strLine);
			
			if (StrContains(strLine, ".vmt", false) != -1)
				PrecacheDecal(strLine, true);
			else if (StrContains(strLine, ".mdl", false) != -1)
				iModel = PrecacheModel(strLine, true);
			
			AddFileToDownloadsTable(strLine);
		}
		
		delete hDepFile;
	}
	
	return iModel;
}

// Thanks TF2Items_GiveWeapon for the code
void CleanString(char[] strBuffer)
{
	// Cleanup any illegal characters
	int iLength = strlen(strBuffer);
	for (int iPos = 0; iPos < iLength; iPos++)
	{
		switch(strBuffer[iPos])
		{
			case '\r': strBuffer[iPos] = ' ';
			case '\n': strBuffer[iPos] = ' ';
			case '\t': strBuffer[iPos] = ' ';
		}
	}

	// Trim string
	TrimString(strBuffer);
}

public void OnMapStart()
{
	GGWeapon.Init();
	
	LoadTranslations("tfgungame.phrases");
	
	CleanLogicEntities();
}

public void OnEntityDestroyed(int iEntity)
{
	if (iEntity <= 0 || iEntity > 2048) return;
	
	g_iViewmodelEnt[iEntity] = 0;
	g_iWorldmodelEnt[iEntity] = 0;
	
	if (g_bHasWearableTied[iEntity])
	{
		int i = -1;
		while ((i = FindEntityByClassname(i, "tf_wearable*")) != -1)
		{
			if (iEntity != g_iTiedEnt[i]) continue;
			if (IsValidClient(g_iWearableOwner[iEntity]))
			{
				TF2_RemoveWearable(g_iWearableOwner[iEntity], i);
			}
			else
			{
				AcceptEntityInput(i, "Kill"); // This can cause graphical glitches
			}
		}
		
		g_bHasWearableTied[iEntity] = false;
	}
}

void CleanLogicEntities()
{
	for (int i = 0; i <= 2048; i++)
	{
		if (!IsValidEntity(i)) continue;
		
		char strClassname[255];
		GetEntityClassname(i, strClassname, sizeof(strClassname));
		
		for (int j = 0; j < sizeof(strCleanTheseEntities); j++)
		{
			if (StrEqual(strClassname, strCleanTheseEntities[j]))
			{
				AcceptEntityInput(i, "Kill");
			}
		}
	}
}

TFGGSpecialRoundType CheckSpecialRound()
{
	if (g_eForceNextSpecial != SpecialRound_None)
		return g_eForceNextSpecial;
	else if (!g_hCvarSpecialRounds.BoolValue)
		return SpecialRound_None;
	else
	{
		int iPercent = g_hCvarSpecialRoundChance.IntValue;
		
		if (GetRandomInt(1,100) > iPercent)
			return SpecialRound_None;
		else
			return view_as<TFGGSpecialRoundType>(GetRandomInt(1, view_as<int>(TFGGSRT_COUNT) - 1));
	}
}

public void OnChangeSound(ConVar hConVar, const char[] strOldValue, const char[] strNewValue)
{
	if (FileExists(strNewValue)) PrecacheSound(strNewValue);
	else
	{
		char strName[255];
		hConVar.GetName(strName, sizeof(strName));
		LogError("Invalid file location \"%s\" set in cvar \"%s\", resetting to previous value \"%s\"", strNewValue, strName, strOldValue);
		
		hConVar.SetString(strOldValue);
	}
}

void PrepSDK()
{
	Handle hGameData = LoadGameConfigFile("tf2gungame");
	
	if (hGameData == null)
		SetFailState("[GunGame] Unable to load GameData! (gamedata/tf2gungame.txt)");
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "CTFPlayer::GetMaxAmmo");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	
	g_hGetMaxAmmo = EndPrepSDKCall();
	if (g_hGetMaxAmmo == null)
		SetFailState("[GunGame] Couldn't load SDK Call CTFPlayer::GetMaxAmmo");
	
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "CTFWeaponBase::GetMaxClip1");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	
	g_hGetMaxClip1 = EndPrepSDKCall();
	if (g_hGetMaxClip1 == null)
		SetFailState("[GunGame] Couldn't load SDK Call CTFWeaponBase::GetMaxClip1");
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "CTFPlayer::EquipWearable");
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hEquipWearable = EndPrepSDKCall();
	if (g_hEquipWearable == null)
		SetFailState("[GunGame] Couldn't load SDK Call CTFPlayer::EquipWearable");

	delete hGameData;
}

void EquipWearable(int iClient, int iEnt)
{
	if (g_hEquipWearable == INVALID_HANDLE)
	{
		PrepSDK();
		LogError("[GunGame] SDK Call for EquipWearable is invalid!");
	}
	else
	{
		// TODO: SEE IF I REALLY NEED THIS SHIT
		SetEntProp(iEnt, Prop_Send, "m_bValidatedAttachedEntity", true);
		SDKCall(g_hEquipWearable, iClient, iEnt);
		SetEntProp(iEnt, Prop_Send, "m_bValidatedAttachedEntity", true);
	}
}


int GetMaxAmmo(int iClient, int iAmmoType, TFClassType iClass)
{ 
	if (iAmmoType == -1 || !iClass)
		return -1;
	
	if (g_hGetMaxAmmo == null)
	{
		LogError("[GunGame] SDK Call for GetMaxAmmo is invalid!");
		return -1;
	}
	
	return SDKCall(g_hGetMaxAmmo, iClient, iAmmoType, iClass);
}

stock int GetWeaponMaxAmmo(int iClient, int iWeapon)
{
	return GetMaxAmmo(iClient, GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType", 1), TF2_GetPlayerClass(iClient));
}

stock int GetSlotMaxAmmo(int iClient, int iSlot, TFClassType iClass = TFClass_Unknown)
{
	int iWep = GetPlayerWeaponSlot(iClient, iSlot);
	if (iWep == -1)
		return -1;
	
	if (iClass == TFClass_Unknown)
		iClass = TF2_GetPlayerClass(iClient);
	
	return GetMaxAmmo(iClient, GetEntProp(iWep, Prop_Send, "m_iPrimaryAmmoType", 1), iClass);
}

stock int GetMaxClip(int iWeapon)
{ 
	if (g_hGetMaxClip1 == INVALID_HANDLE)
	{
		LogError("[GunGame] SDK Call for GetMaxClip1 is invalid!");
		return -1;
	}
	
	return SDKCall(g_hGetMaxClip1, iWeapon);
}

public void OnClientPostAdminCheck(int iClient)
{
#if defined DEBUG
	if (IsFakeClient(iClient))
	{
		// Give joining bots a random rank for testing
		g_iRank[iClient] = GetRandomInt(0, GGWeapon.Total() - 1);
		
		
	}
#endif

	SDKHook(iClient, SDKHook_WeaponSwitchPost, OnWeaponSwitch);
}

public void OnWeaponSwitch(int iClient, int iWeapon)
{
	if (!IsValidEntity(iWeapon)) return;
	int i = -1;
	while ((i = FindEntityByClassname(i, "tf_wearable*")) != -1)
	{
		if (!g_bOnlyVisIfActive[i]) continue;
		if (iClient != g_iWearableOwner[i]) continue;
		int iEffects = GetEntProp(i, Prop_Send, "m_fEffects");
		if (iWeapon == g_iTiedEnt[i]) SetEntProp(i, Prop_Send, "m_fEffects", iEffects & ~32);
		else SetEntProp(i, Prop_Send, "m_fEffects", iEffects |= 32);
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!IsValidClient(client)) return Plugin_Continue;
	
	if (buttons & IN_ATTACK || buttons & IN_FORWARD || buttons & IN_BACK || buttons & IN_MOVELEFT || buttons & IN_MOVERIGHT || TF2_IsPlayerInCondition(client, TFCond_Taunting))
		if (TF2_IsPlayerInCondition(client, TFCond_Ubercharged))
			TF2_RemoveCondition(client, TFCond_Ubercharged);
	
	return Plugin_Continue;
}

public Action OnTFRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_eCurrentSpecial = CheckSpecialRound();
	if (g_eCurrentSpecial && g_eCurrentSpecial < TFGGSRT_COUNT)
		PrintToChatAll("\x07FFA500[GunGame]\x07FFFFFF SPECIAL ROUND ACTIVATED: %s", g_strSpecialRoundName[view_as<int>(g_eCurrentSpecial)]);
	
	g_eForceNextSpecial = SpecialRound_None;
	
	GenerateRoundWeps();
	
	for (int i = 1; i < MaxClients; i++)
	{
		if (!IsValidClient(i) || TF2_GetClientTeam(i) == TFTeam_Unassigned || TF2_GetClientTeam(i) == TFTeam_Spectator)
			continue;

		g_iRank[i] = 0;
		SetPlayerWeapon(i, g_iRank[i]);
	}
	
	g_bRoundActive = true;
	
	Handle hTimer = CreateTimer(HINT_REFRESH_INTERVAL, RefreshCheapHintText, _, TIMER_REPEAT);
	RefreshCheapHintText(hTimer);
	
	PrintToChatAll("\x07FFA500[GunGame]\x07FFFFFF PROTIP: You can type \x07FF5555!gg_help\x07FFFFFF for some information about the gamemode!");
	
	
	CreateTimer(5.0, CleanEnts);
	return Plugin_Continue;
}

public Action TF2_CalcIsAttackCritical(int iClient, int iWeapon, char[] strWeaponName, bool &result)
{
	if (g_eCurrentSpecial != SpecialRound_AllCrits)
	{
		result = false;
		return Plugin_Continue;
	}
	else
	{
		result = true; 
		return Plugin_Handled;
	}
}

public Action CleanEnts(Handle hTimer)
{
	CleanLogicEntities();
}

public Action RefreshCheapHintText(Handle hTimer)
{
	RefreshScores();
}

void RefreshScores()
{
	char strText[1024];
	for (int i = 1; i < MaxClients; i++)
	{
		if (!IsValidClient(i)) continue;
		
		TFTeam eTeam = TF2_GetClientTeam(i);
		if (eTeam == TFTeam_Unassigned || eTeam == TFTeam_Spectator) continue;

		char strWeps[3][48];
		char strNextWeps[216], strAssist[128];
		GGWeapon hWeapon;
		
		int iTotal = GGWeapon.SeriesTotal();
		
		if (g_iRank[i] >= iTotal)
			break;
		
		if (g_iRank[i] < iTotal - 3)
		{
			for (int j = 0; j < 3; j++)
			{
				hWeapon = GGWeapon.GetFromSeries(g_iRank[i] + (j + 1));
				hWeapon.GetName(strWeps[j], sizeof(strWeps[]));
			}
			
			Format(strNextWeps, sizeof(strNextWeps), "\n\nNext Weapons:\n%s\n%s\n%s", strWeps[0], strWeps[1], strWeps[2]);
		}
		else if (g_iRank[i] == iTotal - 3)
		{
			hWeapon = GGWeapon.GetFromSeries(g_iRank[i] + 1);
			hWeapon.GetName(strWeps[0], sizeof(strWeps[]));
			hWeapon = GGWeapon.GetFromSeries(g_iRank[i] + 2);
			hWeapon.GetName(strWeps[1], sizeof(strWeps[]));
			Format(strNextWeps, sizeof(strNextWeps), "\n\nNext Weapons:\n%s\n%s", strWeps[0], strWeps[1]);
		}
		else if (g_iRank[i] == iTotal - 2)
		{
			hWeapon = GGWeapon.GetFromSeries(g_iRank[i] + 1);
			hWeapon.GetName(strWeps[0], sizeof(strWeps[]));
			Format(strNextWeps, sizeof(strNextWeps), "\n\nNext Weapon:\n%s", strWeps[0]);
		}
		else
			Format(strNextWeps, sizeof(strNextWeps), "");
		
		char strWep[128];
		hWeapon = GGWeapon.GetFromSeries(g_iRank[i]);
		hWeapon.GetName(strWep, sizeof(strWep));
		Format(strAssist, sizeof(strAssist), "%s", (g_iAssists[i] == 1) ? "\n\nYou're one assist away from ranking up!" : "");
		Format(strText, sizeof(strText), "Current Weapon:\n%s%s%s", strWep, strNextWeps, strAssist);
		
		//for (int j = 1; j < MaxClients; j++)
		//	if (j != i && TF2_GetClientTeam(j) == TFTeam_Spectator && GetEntPropEnt(j, Prop_Send, "m_hObserverTarget") == i)
		//		PrintKeyHintText(j, strText);
		
		PrintKeyHintText(i, strText);
	}
}

void PrintKeyHintText(int client, char[] buffer)
{
	BfWrite hBuffer = view_as<BfWrite>(StartMessageOne("KeyHintText", client)); 
	hBuffer.WriteByte(1); 
	hBuffer.WriteString(buffer); 
	EndMessage();
	return;
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	// Get Client and check validity
	int iClient = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(iClient)) return Plugin_Handled;
	
	if (!IsFakeClient(iClient))
	{
		if (g_hCvarSpawnProtect.FloatValue == -1.0)
			TF2_AddCondition(iClient, TFCond_Ubercharged);
		else if (g_hCvarSpawnProtect.FloatValue > 0.0)
			TF2_AddCondition(iClient, TFCond_Ubercharged, g_hCvarSpawnProtect.FloatValue);
	}
	
	return Plugin_Continue;
}

public Action OnReloadPlayerWeapons(Event event, const char[] name, bool dontBroadcast)
{
	// Get Client and check validity
	int iClient = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(iClient)) return Plugin_Handled;
	
	SetPlayerWeapon(iClient, g_iRank[iClient]);
	
	return Plugin_Continue;
}

public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int iAttacker = GetClientOfUserId(event.GetInt("attacker"));
	int iVictim = GetClientOfUserId(event.GetInt("userid"));
	int iAssister = GetClientOfUserId(event.GetInt("assister"));
	int iCustomKill = event.GetInt("customkill");
	
	if (!IsValidClient(iAttacker)) return Plugin_Handled;
	
	if (iCustomKill == TF_CUSTOM_TRIGGER_HURT || !g_bRoundActive || 
		(iCustomKill == TF_CUSTOM_SUICIDE || iAttacker == iVictim) && g_hCvarAllowSuicide.IntValue)
			return Plugin_Continue;

	char strWeapon[128];
	event.GetString("weapon_logclassname", strWeapon, sizeof(strWeapon));

#if defined DEBUG
	PrintToChatAll(strWeapon);
#endif
	
	if (!(iCustomKill == TF_CUSTOM_SUICIDE || iAttacker == iVictim))
	{
		g_iRankBuffer[iAttacker]++;
		RequestFrame(RankUpBuffered, iAttacker);
		
		Call_StartForward(hFwdRankUp);
		Call_PushCell(iAttacker);
		Call_PushCell(iVictim);
		Call_PushCell(g_iRank[iAttacker]);
		Call_PushCell(GGWeapon.GetFromSeries(g_iRank[iAttacker]));
		Call_PushCell(GGWeapon.GetFromSeries(g_iRank[iAttacker] + 1));
		Call_Finish();
	}
	
	if (iAssister && IsValidClient(iAssister) && iAssister != iAttacker && iAssister != iVictim && !(iCustomKill == TF_CUSTOM_SUICIDE || iAttacker == iVictim))
	{
		if (g_iAssists[iAssister] == 1)
		{
			g_iAssists[iAssister] = 0;
			g_iRankBuffer[iAssister]++;
			RequestFrame(RankUpBuffered, iAssister);
			
			Call_StartForward(hFwdRankUp);
			Call_PushCell(iAssister);
			Call_PushCell(iVictim);
			Call_PushCell(g_iRank[iAssister]);
			Call_PushCell(GGWeapon.GetFromSeries(g_iRank[iAssister]));
			Call_PushCell(GGWeapon.GetFromSeries(g_iRank[iAssister] + 1));
			Call_Finish();
		}
		else
			g_iAssists[iAssister]++;
	}
	
	if (StrEqual(strWeapon, "sledgehammer") || (iCustomKill == TF_CUSTOM_SUICIDE || iAttacker == iVictim) && !g_hCvarAllowSuicide.IntValue)
	{
		if (g_iRank[iVictim] > 0)
			PrintToChat(iVictim, "\x07FFA500[GunGame] HUMILIATION! %t", "Humiliation");
		else
			PrintToChat(iVictim, "\x07FFA500[GunGame] HUMILIATION!");
		
		RequestFrame(RankDownBuffered, iVictim);
		
		char strSound[255];
		g_hCvarHumiliationSound.GetString(strSound, sizeof(strSound));
		EmitSoundToAll(strSound, .level = SNDLEVEL_ROCKET);
		
		Call_StartForward(hFwdRankDown);
		Call_PushCell(iAttacker);
		Call_PushCell(iVictim);
		Call_PushCell(g_iRank[iVictim]);
		Call_PushCell(GGWeapon.GetFromSeries(g_iRank[iVictim]));
		Call_PushCell(GGWeapon.GetFromSeries(g_iRank[iVictim] + 1));
		Call_Finish();
	}

	return Plugin_Continue;
}

public void OnPlayerDeathPre(Event event, const char[] name, bool dontBroadcast)
{
	int iVictim = GetClientOfUserId(event.GetInt("userid"));
	RequestFrame(Respawn, GetClientSerial(iVictim));
}

public void Respawn(any serial)
{
	//Instant Respawn
	int iClient = GetClientFromSerial(serial);
	if (iClient != 0)
	{
		int team = GetClientTeam(iClient);
		if (!IsPlayerAlive(iClient) && team != 1)
		{
			TF2_RespawnPlayer(iClient);
		}
	}
}

public void RankUpBuffered(int iAttacker)
{
	int iTotal = GGWeapon.SeriesTotal();
	int iAmt = g_iRankBuffer[iAttacker];
	g_iRankBuffer[iAttacker] = 0;

	if (RankUp(iAttacker, iAmt) <= iTotal - 1)
	{
		SetPlayerWeapon(iAttacker, g_iRank[iAttacker]);
		
		if (g_iRank[iAttacker] == iTotal - 1)
		{
			PrintToChatAll("\x07FFA500[GunGame] %N %t", iAttacker, "GoldenWrench");
			
			char strSound[255];
			g_hCvarLastRankSound.GetString(strSound, sizeof(strSound));
			EmitSoundToAll(strSound, .level = SNDLEVEL_ROCKET);
		}
	}
	else
		WinPlayer(iAttacker);
}

public void RankDownBuffered(int iVictim)
{
	if ((g_iRank[iVictim] - 1) >= 0)
	{
		RankUp(iVictim, -1);
		SetPlayerWeapon(iVictim, g_iRank[iVictim]);
	}
}

int RankUp(int iClient, int iAmount = 1)
{
	g_iRank[iClient] += iAmount;
	return g_iRank[iClient];
}

void WinPlayer(int iClient)
{
	PrintToChatAll("\x07FFA500[GunGame] %N %t", iClient, "WonMatch");
	
	char strSound[255];
	g_hCvarWinSound.GetString(strSound, sizeof(strSound));
	EmitSoundToAll(strSound, .level = SNDLEVEL_ROCKET);
	
	int iEnt = FindEntityByClassname(iEnt, "game_round_win");
	
	if (iEnt < 1)
	{
		iEnt = CreateEntityByName("game_round_win");
		if (IsValidEntity(iEnt))
			DispatchSpawn(iEnt);
		else
			ThrowError("[GunGame] Could not spawn round win entity!");
	}
	
	SetVariantInt(view_as<int>(TF2_GetClientTeam(iClient)));
	AcceptEntityInput(iEnt, "SetTeam");
	AcceptEntityInput(iEnt, "RoundWin");
	g_bRoundActive = false;
	
	Call_StartForward(hFwdOnWin);
	Call_PushCell(iClient);
	Call_Finish();
}

stock bool IsValidClient(int iClient)
{
	return !(iClient <= 0
			|| iClient > MaxClients
			|| !IsClientInGame(iClient)
			|| !IsClientConnected(iClient)
			|| GetEntProp(iClient, Prop_Send, "m_bIsCoaching")
			|| IsClientSourceTV(iClient)
			|| IsClientReplay(iClient));
}

void SetPlayerWeapon(int iClient, int iRank)
{
	if (!IsValidClient(iClient)) return;
	if (iRank >= GGWeapon.SeriesTotal()) return;
	
	GGWeapon hWeapon = GGWeapon.GetFromSeries(iRank);
	TFClassType eClass = hWeapon.Class;
	
	if (TF2_GetPlayerClass(iClient) != eClass)
		TF2_SetPlayerClass(iClient, eClass, _, true);
	
	SetEntityHealth(iClient, g_iClassMaxHP[view_as<int>(eClass)]);
	
	// Remove all weapons
	OnWeaponSwitch(iClient, GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon"));
	TF2_RemoveAllWeapons(iClient);
	
	char strClassname[128], strAttributes[128];
	hWeapon.GetClassname(strClassname, sizeof(strClassname));
	hWeapon.GetAttributeOverride(strAttributes, sizeof(strAttributes));
	
	int iWeapon = CreateWeapon(iClient, strClassname, hWeapon.Index, 1, 1, strAttributes, hWeapon.FlagsOverride);
	FlagWeaponDontDrop(iWeapon);
	bool bUsesCustomModel = HandleWeaponModel(hWeapon, iClient, iWeapon);
	
	if (hWeapon.ClipOverride)
		SetEntData(iWeapon, FindSendPropInfo("CTFWeaponBase", "m_iClip1"), hWeapon.ClipOverride, _, true);
	else if (hWeapon.Index == 741 || hWeapon.Index == 739) // Rainblower fix, thanks to Benoist3012
		SetEntProp(iWeapon, Prop_Send, "m_nModelIndexOverrides", GetEntProp(iWeapon, Prop_Send, "m_nModelIndexOverrides", _, 3), _, 0);
	
	SetMaxAmmo(iClient, iWeapon);
	EquipPlayerWeapon(iClient, iWeapon);
	if (bUsesCustomModel)
		SetEntProp(GetEntPropEnt(iClient, Prop_Send, "m_hViewModel"), Prop_Send, "m_fEffects", 32);
	
	// Create and equip homewrecker if melee not given, and not a bot
	if (hWeapon.Slot != 2 && !IsFakeClient(iClient))
		EquipPlayerWeapon(iClient, CreateWeapon(iClient, "tf_weapon_fireaxe", 153, 50, 6, ""));
	
	RefreshScores();
}

void GenerateRoundWeps()
{
	GGWeapon.InitSeries();

	KeyValues hKvConfig = new KeyValues("WeaponSeries");
	char strPath[PLATFORM_MAX_PATH];
	
	BuildPath(Path_SM, strPath, PLATFORM_MAX_PATH, g_strSpecialRoundSeries[view_as<int>(g_eCurrentSpecial)]);
	
	hKvConfig.ImportFromFile(strPath);
	
	if (hKvConfig == null)
		SetFailState("[GunGame] Config file not found or invalid!");
	
	char strSectionName[128];
	hKvConfig.GetSectionName(strSectionName, sizeof(strSectionName));
	if (!StrEqual("WeaponSeries", strSectionName))
		SetFailState("[GunGame] Config file is invalid!");
	
	if (!hKvConfig.GotoFirstSubKey())
		SetFailState("[GunGame] Config file has no weapons!");

	int j;
	do
	{
		GGWeapon hWeapon;
		int iIndex = hKvConfig.GetNum("index_override", 0);
		if (iIndex)
		{
			hWeapon = GGWeapon.GetFromIndex(iIndex);
		}
		else
		{
			ArrayList hTemp = new ArrayList();
			for (int i = 0; i < GGWeapon.Total(); i++)
			{
				hWeapon = GGWeapon.GetFromAll(i);
				if (hWeapon.Class == view_as<TFClassType>(hKvConfig.GetNum("class")) && hWeapon.Slot == hKvConfig.GetNum("slot") && !hWeapon.Disabled)
					hTemp.Push(hWeapon);
			}
			
			if (hTemp.Length == 0)
				hWeapon = view_as<GGWeapon>(INVALID_HANDLE);
			else
				hWeapon = view_as<GGWeapon>(hTemp.Get(GetRandomInt(0, hTemp.Length - 1)));
		}
		
		if (hWeapon != null)
		{
			j++;
			char strWeapon[128];
			hWeapon.GetName(strWeapon, 128);
			PrintToServer("[GunGame] Added Weapon %d: %d (%s)", j, hWeapon.Index, strWeapon);
			GGWeapon.PushToSeries(hWeapon);
		}
	}
	while (hKvConfig.GotoNextKey());
}

int CreateWeapon(int client, char[] sName, int index, int level = 1, int qual = 1, char[] att, int flags = OVERRIDE_ALL | PRESERVE_ATTRIBUTES)
{
	Handle hWeapon = TF2Items_CreateItem(flags);
	if (hWeapon == INVALID_HANDLE)
		return -1;
	
	TF2Items_SetItemIndex(hWeapon, index);
	TF2Items_SetLevel(hWeapon, level);
	TF2Items_SetQuality(hWeapon, qual);
	TF2Items_SetClassname(hWeapon, sName);

	char atts[32][32];
	int count = ExplodeString(att, " ; ", atts, 32, 32);
	if (count > 1)
	{
		TF2Items_SetNumAttributes(hWeapon, count/2);

		for (int j, i; i < count; i += 2, j++)
			TF2Items_SetAttribute(hWeapon, j, StringToInt(atts[i]), StringToFloat(atts[i+1]));
	}
	else if (flags & ~PRESERVE_ATTRIBUTES)
		TF2Items_SetNumAttributes(hWeapon, 0);

	int entity = TF2Items_GiveNamedItem(client, hWeapon);
	
	delete hWeapon;
	return entity;
}

void FlagWeaponDontDrop(int iWeapon)
{
	// Big thanks to Benoist3012 for this func
	int iItemOffset = GetEntSendPropOffs(iWeapon, "m_Item", true);
	if (iItemOffset <= 0) return;

	Address pWeapon = GetEntityAddress(iWeapon);
	if (pWeapon == Address_Null) return;

	StoreToAddress(view_as<Address>((view_as<int>(pWeapon)) + iItemOffset + 36), 0x23E173A2, NumberType_Int32);
	SetEntProp(iWeapon, Prop_Send, "m_bValidatedAttachedEntity", 1);
}

bool HandleWeaponModel(GGWeapon hWeapon, int iClient, int iWeapon)
{
	if (hWeapon == INVALID_HANDLE || !IsValidClient(iClient))
		return false;
	
	char strViewmodel[PLATFORM_MAX_PATH], strWorldmodel[PLATFORM_MAX_PATH];
	hWeapon.GetViewmodelOverride(strViewmodel, sizeof(strViewmodel));
	hWeapon.GetModelOverride(strWorldmodel, sizeof(strWorldmodel));
	
	if (!strlen(strWorldmodel) && !strlen(strViewmodel))
		return false;
	
	if (strlen(strWorldmodel) && !FileExists(strWorldmodel, true))
		SetFailState("[GunGame] MISSING WORLDMODEL FOR WEAPON: %s", strWorldmodel);
	else if (FileExists(strWorldmodel, true))
	{
		int iModel = hWeapon.ModelIndex;
		SetEntProp(iWeapon, Prop_Send, "m_iWorldModelIndex", iModel);
		SetEntProp(iWeapon, Prop_Send, "m_nModelIndexOverrides", iModel, _, 0);
		CreateWearable(iClient, strWorldmodel, false);
	}
	
	if (strlen(strViewmodel) && !FileExists(strViewmodel, true))
		SetFailState("[GunGame] MISSING VIEWMODEL FOR WEAPON: %s", strViewmodel);
	else if (FileExists(strViewmodel, true))
	{
		int iViewmodel = CreateAndEquipWearable(iClient, strViewmodel, true);
		if (iViewmodel > 0)
			g_iViewmodelEnt[iViewmodel] = iWeapon;
		
		int iClass = view_as<int>(TF2_GetPlayerClass(iClient));
		if (FileExists(g_strArmModels[iClass], true))
		{
			PrecacheModel(g_strArmModels[iClass], true);
			int iArms = CreateAndEquipWearable(iClient, g_strArmModels[iClass], true);
			if (iArms > 0)
				g_iViewmodelEnt[iArms] = iWeapon;
		}
		
		int iEffects = GetEntProp(iWeapon, Prop_Send, "m_fEffects");
		SetEntProp(iWeapon, Prop_Send, "m_fEffects", iEffects |= 32);
	}
	
	SetEntProp(iWeapon, Prop_Send, "m_bValidatedAttachedEntity", true);
	
	return true;
}

int CreateWearable(int iClient, char[] strModel, bool bViewmodel)
{
	int iEnt = CreateEntityByName(bViewmodel ? "tf_wearable_vm" : "tf_wearable");
	if (!IsValidEntity(iEnt)) return -1;
	SetEntProp(iEnt, Prop_Send, "m_nModelIndex", PrecacheModel(strModel));
	SetEntProp(iEnt, Prop_Send, "m_fEffects", 129);
	SetEntProp(iEnt, Prop_Send, "m_iTeamNum", GetClientTeam(iClient));
	SetEntProp(iEnt, Prop_Send, "m_usSolidFlags", 4);
	SetEntProp(iEnt, Prop_Send, "m_CollisionGroup", 11);
	DispatchSpawn(iEnt);
	SetVariantString("!activator");
	ActivateEntity(iEnt);
	EquipWearable(iClient, iEnt);
	return iEnt;
}

int CreateAndEquipWearable(int iClient, char[] strModel, bool bViewmodel, int iWeapon = 0, bool bVisActive = true)
{
	int iWearable = CreateWearable(iClient, strModel, bViewmodel);
	if (iWearable == -1)
		return -1;
	
	g_iWearableOwner[iWearable] = iClient;
	
	if (iWeapon > MaxClients)
	{
		g_iTiedEnt[iWearable] = iWeapon;
		g_bOnlyVisIfActive[iWearable] = bVisActive;
		
		g_bHasWearableTied[iWeapon] = true;
		
		int iEffects = GetEntProp(iWearable, Prop_Send, "m_fEffects");
		if (iWeapon == GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon"))
		{
			SetEntProp(iWearable, Prop_Send, "m_fEffects", iEffects & ~32);
			iEffects = GetEntProp(iWeapon, Prop_Send, "m_fEffects");
			SetEntProp(iWeapon, Prop_Send, "m_fEffects", iEffects |= 32);
		}
		else SetEntProp(iWearable, Prop_Send, "m_fEffects", iEffects |= 32);
	}
	
	return iWearable;
}

void SetMaxAmmo(int iClient, int iWeapon, int iForceAmmo = -1)
{
	int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
	int iMaxAmmo = GetWeaponMaxAmmo(iClient, iWeapon);
	
	if (iAmmoType != -1 && iMaxAmmo != -1)
		SetEntProp(iClient, Prop_Data, "m_iAmmo", (iForceAmmo == -1) ? iMaxAmmo : iForceAmmo, _, iAmmoType);
}

public Action TF2Items_OnGiveNamedItem(int iClient, char[] sClassname, int iIndex, Handle &hItem)
{
	// Dont generate weapons and cosmetics from client's loadout
	return Plugin_Handled;
}

public any Native_GetRank(Handle plugin, int numParams)
{
	return g_iRank[GetNativeCell(1)];
}

public any Native_ForceRank(Handle plugin, int numParams)
{
	int iRank = GetNativeCell(2);
	int iClient = GetNativeCell(1);
	
	if (iRank >= 0 && iRank < GGWeapon.SeriesTotal())
		return false;
	
	g_iRank[iClient] = iRank;
	return true;
}

public any Native_ForceWin(Handle plugin, int numParams)
{
	WinPlayer(GetNativeCell(1));
	return;
}

public any Native_ForceRankUp(Handle plugin, int numParams)
{
	int iClient = GetNativeCell(1);
	
	if (g_iRank[iClient]+1 >= GGWeapon.SeriesTotal())
		return false;
	
	RankUp(iClient);
	SetPlayerWeapon(iClient, g_iRank[iClient]);
	return true;
}

public any Native_ForceRankDown(Handle plugin, int numParams)
{
	int iClient = GetNativeCell(1);
	
	if (!g_iRank[iClient])
		return false;
	
	RankUp(iClient, -1);
	SetPlayerWeapon(iClient, g_iRank[iClient]);
	return true;
}

public Action Command_Help(int iClient, int iArgs)
{
	// {orange}[GunGame]{white} In GunGame the objective is to kill other players,
	// which changes your weapon to another one. The goal is to get through every 
	// weapon until you win! However, if you get hit by a melee weapon or kill yourself,
	// you get set back one rank.
	ReplyToCommand(iClient, "\x07FFA500[GunGame]\x07FFFFFF %t", "HelpString");
}

public Action Command_ForceNextSpecial(int iClient, int iArgs)
{
	TFGGSpecialRoundType eType;
	char strArg[4];
	GetCmdArg(1, strArg, sizeof(strArg));
	
	eType = view_as<TFGGSpecialRoundType>(StringToInt(strArg));
	
	if (eType >= TFGGSRT_COUNT || eType <= SpecialRound_None)
	{
		ReplyToCommand(iClient, "\x07FF0000Invalid special round specified!");
		return Plugin_Handled;
	}
	
	PrintToChat(iClient, "\x07FFA500[GunGame] An Admin has triggered a Special Round! The next round will be: %s", g_strSpecialRoundName[view_as<int>(eType)]);
	
	g_eForceNextSpecial = eType;
	return Plugin_Handled;
}
