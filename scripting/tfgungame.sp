#define TFGG_MAIN
#define PLUGIN_VERSION "1.5"

#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>
#include <tf2items>
#include <tfgungame>
#include <tf_econ_data>

#pragma semicolon 1
#pragma newdecls required

#include "tfgungame_ggweapon.sp"

//#define DEBUG

public Plugin myinfo =
{
	name = "TFGunGame: Redux",
	author = "Screwdriver (Jon S.)",
	description = "GunGame - Run through a series of weapons, first person to get a kill with the final weapon wins.",
	version = PLUGIN_VERSION,
	url = "https://github.com/koopa516"
};

#define MAX_WEAPONS		64

stock const char LASTRANK_SOUND[] = ""; // TODO
stock const char WIN_SOUND[] = ""; // TODO
stock const char HUMILIATION_SOUND[] = ""; // TODO
stock const char strCleanTheseEntities[][256] = 
{
	"info_passtime_ball_spawn",
	"tf_logic_arena",
	"tf_logic_hybrid_ctf_cp",
	"tf_logic_koth",
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

stock const int g_iClassMaxHP[view_as<int>(TFClass_Engineer) + 1] =
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

stock const char g_strSpecialRoundName[TFGGSRT_COUNT][32] =
{
	"None",
	"Melee Weapons Only",
	"Melee Weapons Enabled",
	"100% Critical Hits"
};

const float HINT_REFRESH_INTERVAL = 5.0;

enum struct TFGGPlayer
{
	int Rank;
	int RankBuffer;
	int Assists;
	bool Winner;
	
	void Clear()
	{
		this.Rank = 0;
		this.RankBuffer = 0;
		this.Assists = 0;
		this.Winner = false;
	}
}

TFGGPlayer g_PlayerData[MAXPLAYERS + 1];

bool g_bRoundActive;
float g_flRoundUnfreezeTime;

Handle g_hGetMaxAmmo;
Handle g_hGetMaxClip1;

Handle hFwdOnWin;
Handle hFwdRankUp;
Handle hFwdRankDown;

ConVar g_hCvarSpawnProtect;
ConVar g_hCvarAllowSuicide;
ConVar g_hCvarMaxKillsPerRankUp;
ConVar g_hCvarLastRankSound;
ConVar g_hCvarWinSound;
ConVar g_hCvarHumiliationSound;
ConVar g_hCvarSpecialRounds;
ConVar g_hCvarSpecialRoundChance;
ConVar g_hCvarUseScoreboard;

TFGGSpecialRoundType g_eForceNextSpecial = SpecialRound_None;
TFGGSpecialRoundType g_eCurrentSpecial = SpecialRound_None;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
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
	CreateNative("GGWeapon.ClipOverride.get", Native_GGWeaponClipOverride);
	
	CreateNative("GetGunGameRank", Native_GetRank);
	CreateNative("GetGunGamePlacements", Native_GetPlacements);
	CreateNative("ForceGunGameWin", Native_ForceWin);
	CreateNative("ForceGunGameRank", Native_ForceRank);
	CreateNative("ForceGunGameRankUp", Native_ForceRankUp);
	CreateNative("ForceGunGameRankDown", Native_ForceRankDown);
	
	hFwdOnWin = CreateGlobalForward("OnGunGameWin", ET_Ignore, Param_Cell);
	hFwdRankUp = CreateGlobalForward("OnGunGameRankUp", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	hFwdRankDown = CreateGlobalForward("OnGunGameRankDown", ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	
	RegPluginLibrary("tfgungame");
	
	return APLRes_Success;
}

public void OnPluginStart()
{
	CreateConVar("tfggr_version", PLUGIN_VERSION, "Plugin Version", FCVAR_ARCHIVE);
	g_hCvarSpawnProtect =		CreateConVar("tfgg_spawnprotect_length", "-1.0", "Length of the spawn protection for players, set to 0.0 to disable and -1.0 for infinite length", true);
	g_hCvarAllowSuicide =		CreateConVar("tfgg_allow_suicide", "0", "Set to 1 to not humiliate players when they suicide", _, true, 0.0, true, 1.0);
	g_hCvarMaxKillsPerRankUp =	CreateConVar("tfgg_max_kills_per_rankup", "3", "Maximum amount of kills registered toward the next rank. -1 for no limit.");
	g_hCvarLastRankSound =		CreateConVar("tfgg_last_rank_sound", LASTRANK_SOUND, "Sound played when someone has hit the last rank");
	g_hCvarWinSound =			CreateConVar("tfgg_win_sound", WIN_SOUND, "Sound played when someone wins the game");
	g_hCvarHumiliationSound =	CreateConVar("tfgg_humiliation_sound", HUMILIATION_SOUND, "Sound played on humiliation");
	g_hCvarSpecialRounds =		CreateConVar("tfgg_enable_special_rounds", "1", "Enable Special Rounds", _, true, 0.0, true, 1.0);
	g_hCvarSpecialRoundChance =	CreateConVar("tfgg_special_round_chance", "25", "Special round chance; Should be a percent value out of 100", _, true, 0.0, true, 100.0);
	g_hCvarUseScoreboard =		CreateConVar("tfgg_use_scoreboard", "1", "Shows ranks as score in the scoreboard", _, true, 0.0, true, 1.0);
	
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
	
	FindConVar("mp_respawnwavetime").IntValue = 0;
	FindConVar("tf_use_fixed_weaponspreads").IntValue = 1;
	FindConVar("tf_damage_disablespread").IntValue = 1;
	FindConVar("tf_weapon_criticals").IntValue = 0;
	FindConVar("mp_autoteambalance").IntValue = 1;
	
	RegConsoleCmd("gg_help", Command_Help, "Sends a player a help panel");
	
	AddCommandListener(OnJoinClass, "join_class");
	AddCommandListener(OnJoinClass, "joinclass");
	
	PrepSDK();
	
	LoadTranslations("tfgungame.phrases");
	
	//PrecacheSound(LASTRANK_SOUND, true);
	//PrecacheSound(WIN_SOUND, true);
	//PrecacheSound(HUMILIATION_SOUND, true);

	AutoExecConfig(_, "tfgungame");
	
	CreateTimer(HINT_REFRESH_INTERVAL, RefreshCheapHintText, _, TIMER_REPEAT);
	
	if (GetClientCount(true) > 0)
	{
		PrintToChatAll("\x07FFA500[GunGame]\x07FFFFFF Late-load detected! Restarting round...");
		MakeTeamWin(TFTeam_Unassigned);
	}
	
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsClientInGame(iClient))
			OnClientPutInServer(iClient);
	}
	
	int iEntity = -1;
	while ((iEntity = FindEntityByClassname(iEntity, "*")) != -1)
	{
		char strClassname[64];
		if (!GetEntityClassname(iEntity, strClassname, sizeof(strClassname)))
			continue;
		
		OnEntityCreated(iEntity, strClassname);
	}
}

public void OnMapStart()
{
	LoadTranslations("tfgungame.phrases");
	
	CleanLogicEntities();
	
	g_flRoundUnfreezeTime = 0.0;
}

void CleanLogicEntities()
{
	for (int i = 0; i <= GetMaxEntities(); i++)
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

public void OnEntityCreated(int iEntity, const char[] strClassname)
{
	if (!IsValidEdict(iEntity))
		return;
	
	if (StrEqual(strClassname, "tf_dropped_weapon"))
		RemoveEntity(iEntity);
	else if (StrEqual(strClassname, "tf_player_manager"))
		SDKHook(iEntity, SDKHook_ThinkPost, OnTFPlayerManagerThinkPost);	
}

void OnTFPlayerManagerThinkPost(int iEntity)
{
	if (!g_hCvarUseScoreboard.BoolValue)
		return;
	
	static int iScoreOffset = -1;
	if (iScoreOffset == -1)
		iScoreOffset = FindSendPropInfo("CTFPlayerResource", "m_iTotalScore");
	
	int iPlayerScores[MAXPLAYERS + 1];
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (IsValidClient(iClient))
			iPlayerScores[iClient] = g_PlayerData[iClient].Rank;
	}
	
	SetEntDataArray(iEntity, iScoreOffset, iPlayerScores, MaxClients + 1);
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

	delete hGameData;
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

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	
#if defined DEBUG
	if (IsFakeClient(client))
	{
		// Give joining bots a random rank for testing
		g_PlayerData[client].Rank = GetRandomInt(0, GGWeapon.Total() - 1);
	}
#endif
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if (!IsValidClient(client)) return Plugin_Continue;
	
	if (buttons & (IN_ATTACK | IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT) || TF2_IsPlayerInCondition(client, TFCond_Taunting))
		if (TF2_IsPlayerInCondition(client, TFCond_Ubercharged))
			TF2_RemoveCondition(client, TFCond_Ubercharged);
	
	return Plugin_Continue;
}

public Action OnTFRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!GameRules_GetProp("m_bInWaitingForPlayers"))
	{
		g_eCurrentSpecial = CheckSpecialRound();
		if (g_eCurrentSpecial && g_eCurrentSpecial < TFGGSRT_COUNT)
			PrintToChatAll("\x07FFA500[GunGame]\x07FFFFFF SPECIAL ROUND ACTIVATED: %s", g_strSpecialRoundName[view_as<int>(g_eCurrentSpecial)]);
		
		g_eForceNextSpecial = SpecialRound_None;
	}
	else
	{
		g_eCurrentSpecial = SpecialRound_None;
	}
	
	const float flFreezeTime = 5.0;
	g_flRoundUnfreezeTime = GetGameTime() + flFreezeTime;
	g_bRoundActive = true;
	
	GenerateRoundWeps();
	
	for (int i = 1; i <= MaxClients; i++)
	{
		g_PlayerData[i].Clear();
		
		if (!IsValidClient(i) || TF2_GetClientTeam(i) == TFTeam_Unassigned || TF2_GetClientTeam(i) == TFTeam_Spectator)
			continue;
		
		SetPlayerLoadout(i, 0);
	}
	
	// Don't refresh straight away because it risks players disconnecting
	// from net message buffer overflow
	CreateTimer(1.0, RefreshCheapHintText);
	
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

Action OnJoinClass(int iClient, const char[] strCommand, int iArgc)
{
	if (!IsValidClient(iClient) || !IsPlayerAlive(iClient))
		return Plugin_Continue;
	
	return Plugin_Handled;
}

Action OnTakeDamage(int iVictim, int &iAttacker, int &iInflictor, float &fDamage, int &iDamageType, int &iWeapon, float vecDamageForce[3], float vecDamagePos[3], int iDamageCustom)
{
	if (g_eCurrentSpecial == SpecialRound_AllCrits && iInflictor > MaxClients)
	{
		// Dragon's Fury does not care about TF2_CalcIsAttackCritical, so we apply crits from it here
		char strClassname[64];
		GetEntityClassname(iInflictor, strClassname, sizeof(strClassname));
		if (StrEqual(strClassname, "tf_projectile_balloffire"))
		{
			iDamageType |= DMG_CRIT;
			return Plugin_Changed;
		}
	}
	
	return Plugin_Continue;
}

public Action CleanEnts(Handle hTimer)
{
	CleanLogicEntities();
	return Plugin_Continue;
}

public Action RefreshCheapHintText(Handle hTimer)
{
	RefreshScores();
	return Plugin_Continue;
}

void RefreshScores()
{
	if (!g_bRoundActive)
		return;
	
	for (int iClient = 1; iClient <= MaxClients; iClient++)
		RefreshClientScore(iClient);
}

void RefreshClientScore(int iClient)
{
	if (!g_bRoundActive)
		return;
	
	if (!IsValidClient(iClient))
		return;
	
	TFTeam nTeam = TF2_GetClientTeam(iClient);
	if (nTeam == TFTeam_Unassigned || nTeam == TFTeam_Spectator)
		return;
	
	char strText[256], strWeaponBuffer[64];
	GGWeapon hWeapon;
	
	int iTotal = GGWeapon.SeriesTotal();
	int iPlayerRank = g_PlayerData[iClient].Rank;
	if (iPlayerRank >= iTotal)
		return;
	
	hWeapon = GGWeapon.GetFromSeries(iPlayerRank);
	hWeapon.GetName(strWeaponBuffer, sizeof(strWeaponBuffer));
	FormatEx(strText, sizeof(strText), "Current Weapon:\n- %s", strWeaponBuffer);
	
	const int iMaxWeapons = 3;
	int iCount = (iTotal - 1) - iPlayerRank;
	if (iCount > iMaxWeapons)
		iCount = iMaxWeapons;
	
	if (iCount > 0)
	{
		Format(strText, sizeof(strText), "%s\n\nNext Weapon%s:", strText, iCount == 1 ? "" : "s");
		for (int i = 0; i < iCount; i++)
		{
			hWeapon = GGWeapon.GetFromSeries(iPlayerRank + (i + 1));
			hWeapon.GetName(strWeaponBuffer, sizeof(strWeaponBuffer));
			
			Format(strText, sizeof(strText), "%s\n- %s", strText, strWeaponBuffer);
		}
	}
	
	if (CanClientGetAssistCredit(iClient) && g_PlayerData[iClient].Assists == 1)
		StrCat(strText, sizeof(strText), "\n\nYou're one assist away from ranking up!");
	
	PrintKeyHintText(iClient, strText);
}

void PrintKeyHintText(int client, char[] buffer)
{
	BfWrite hBuffer = view_as<BfWrite>(StartMessageOne("KeyHintText", client)); 
	hBuffer.WriteByte(1); 
	hBuffer.WriteString(buffer); 
	EndMessage();
	return;
}

ArrayList GetPlacementsArray()
{
	ArrayList hPlacements = new ArrayList(sizeof(TFGGPlacementInfo));
	TFGGPlacementInfo info;
	
	for (int iClient = 1; iClient <= MaxClients; iClient++)
	{
		if (!IsValidClient(iClient) || TF2_GetClientTeam(iClient) <= TFTeam_Spectator)
			continue;
		
		info.Client = iClient;
		info.Rank = g_PlayerData[iClient].Rank;
		info.Winner = g_PlayerData[iClient].Winner;
		
		hPlacements.PushArray(info);
	}
	
	int iLength = hPlacements.Length;
	if (iLength > 0)
	{
		hPlacements.Sort(Sort_Descending, Sort_Integer);
		
		int iLastRank = -1;
		int iPosition;
		
		for (int i = 0; i < iLength; i++)
		{
			int iRank = hPlacements.Get(i, TFGGPlacementInfo::Rank);
			if (iLastRank != iRank)
			{
				iPosition = i + 1;
				iLastRank = iRank;
			}
			
			hPlacements.Set(i, iPosition, TFGGPlacementInfo::Position);
			
			if (iPosition <= 1)
			{
				bool bWinner = hPlacements.Get(i, TFGGPlacementInfo::Winner);
				if (bWinner)
					hPlacements.SwapAt(0, i);
			}
		}
	}
	
	return hPlacements;
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	// Get Client and check validity
	int iClient = GetClientOfUserId(event.GetInt("userid"));
	if (!IsValidClient(iClient)) return Plugin_Handled;
	
	SetPlayerLoadout(iClient, g_PlayerData[iClient].Rank);

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
	
	SetPlayerLoadout(iClient, g_PlayerData[iClient].Rank);
	
	return Plugin_Continue;
}

public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int iAttacker = GetClientOfUserId(event.GetInt("attacker"));
	int iVictim = GetClientOfUserId(event.GetInt("userid"));
	int iAssister = GetClientOfUserId(event.GetInt("assister"));
	int iCustomKill = event.GetInt("customkill");
	
	if (!IsValidClient(iAttacker)) return Plugin_Handled;
	
	if (!g_bRoundActive)
		return Plugin_Continue;
	
	char strWeapon[128];
	event.GetString("weapon_logclassname", strWeapon, sizeof(strWeapon));

#if defined DEBUG
	PrintToChatAll(strWeapon);
#endif
	
	if (iAttacker != iVictim)
	{
		g_PlayerData[iAttacker].RankBuffer++;
		RequestFrame(RankUpBuffered, iAttacker);
		
		Call_StartForward(hFwdRankUp);
		Call_PushCell(iAttacker);
		Call_PushCell(iVictim);
		Call_PushCell(g_PlayerData[iAttacker].Rank);
		Call_PushCell(GGWeapon.GetFromSeries(g_PlayerData[iAttacker].Rank));
		Call_PushCell(GGWeapon.GetFromSeries(g_PlayerData[iAttacker].Rank + 1));
		Call_Finish();
	}
	
	if (iAssister && IsValidClient(iAssister) && iAssister != iAttacker && iAssister != iVictim && iAttacker != iVictim && CanClientGetAssistCredit(iAssister))
	{
		if (g_PlayerData[iAssister].Assists == 1)
		{
			g_PlayerData[iAssister].Assists = 0;
			g_PlayerData[iAssister].RankBuffer++;
			RequestFrame(RankUpBuffered, iAssister);
			
			Call_StartForward(hFwdRankUp);
			Call_PushCell(iAssister);
			Call_PushCell(iVictim);
			Call_PushCell(g_PlayerData[iAssister].Rank);
			Call_PushCell(GGWeapon.GetFromSeries(g_PlayerData[iAssister].Rank));
			Call_PushCell(GGWeapon.GetFromSeries(g_PlayerData[iAssister].Rank + 1));
			Call_Finish();
		}
		else
		{
			g_PlayerData[iAssister].Assists++;
			RefreshClientScore(iAssister);
		}
	}
	
	if (StrEqual(strWeapon, "necro_smasher") || (iCustomKill == TF_CUSTOM_SUICIDE && !g_hCvarAllowSuicide.IntValue))
	{
		if (g_PlayerData[iVictim].Rank > 0)
			PrintToChat(iVictim, "\x07FFA500[GunGame] HUMILIATION! %t", "Humiliation");
		else
			PrintToChat(iVictim, "\x07FFA500[GunGame] HUMILIATION!");
		
		if (g_PlayerData[iVictim].Rank > 0)
		{
			Call_StartForward(hFwdRankDown);
			Call_PushCell(iAttacker);
			Call_PushCell(iVictim);
			Call_PushCell(g_PlayerData[iVictim].Rank);
			Call_PushCell(GGWeapon.GetFromSeries(g_PlayerData[iVictim].Rank));
			Call_PushCell(GGWeapon.GetFromSeries(g_PlayerData[iVictim].Rank - 1));
			Call_Finish();
		}
		
		RequestFrame(RankDownBuffered, iVictim);
		
		char strSound[255];
		g_hCvarHumiliationSound.GetString(strSound, sizeof(strSound));
		
		if (strSound[0])
			EmitSoundToAll(strSound, .level = SNDLEVEL_ROCKET);
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
	int iAmt = (g_PlayerData[iAttacker].RankBuffer <= g_hCvarMaxKillsPerRankUp.IntValue || g_hCvarMaxKillsPerRankUp.IntValue == -1) ? g_PlayerData[iAttacker].RankBuffer : g_hCvarMaxKillsPerRankUp.IntValue;
	g_PlayerData[iAttacker].RankBuffer = 0;

	if (RankUp(iAttacker, iAmt) <= iTotal - 1)
	{
		SetPlayerLoadout(iAttacker, g_PlayerData[iAttacker].Rank);
		
		if (g_PlayerData[iAttacker].Rank == iTotal - 1)
		{
			PrintToChatAll("\x07FFA500[GunGame] %N %t", iAttacker, "GoldenWrench");
			
			char strSound[255];
			g_hCvarLastRankSound.GetString(strSound, sizeof(strSound));
			
			if (strSound[0])
				EmitSoundToAll(strSound, .level = SNDLEVEL_ROCKET);
		}
	}
	else
		WinPlayer(iAttacker);
}

public void RankDownBuffered(int iVictim)
{
	if ((g_PlayerData[iVictim].Rank - 1) >= 0)
	{
		RankUp(iVictim, -1);
		SetPlayerLoadout(iVictim, g_PlayerData[iVictim].Rank);
	}
}

int RankUp(int iClient, int iAmount = 1)
{
	g_PlayerData[iClient].Rank += iAmount;
	return g_PlayerData[iClient].Rank;
}

void WinPlayer(int iClient)
{
	g_PlayerData[iClient].Winner = true;
	
	PrintToChatAll("\x07FFA500[GunGame] %N %t", iClient, "WonMatch");
	
	Call_StartForward(hFwdOnWin);
	Call_PushCell(iClient);
	Call_Finish();
	
	char strSound[255];
	g_hCvarWinSound.GetString(strSound, sizeof(strSound));
	
	if (strSound[0])
		EmitSoundToAll(strSound, .level = SNDLEVEL_ROCKET);
	
	MakeTeamWin(TF2_GetClientTeam(iClient));
	g_bRoundActive = false;
}

void MakeTeamWin(TFTeam nTeam)
{
	int iEnt = FindEntityByClassname(-1, "game_round_win");
	if (iEnt < 1)
	{
		iEnt = CreateEntityByName("game_round_win");
		if (IsValidEntity(iEnt))
			DispatchSpawn(iEnt);
		else
			ThrowError("[GunGame] Could not spawn round win entity!");
	}
	
	SetVariantInt(view_as<int>(nTeam));
	AcceptEntityInput(iEnt, "SetTeam");
	AcceptEntityInput(iEnt, "RoundWin");
}

stock bool IsValidClient(int iClient)
{
	return !(!(0 < iClient <= MaxClients)
			|| !IsClientInGame(iClient)
			|| !IsClientConnected(iClient)
			|| GetEntProp(iClient, Prop_Send, "m_bIsCoaching")
			|| IsClientSourceTV(iClient)
			|| IsClientReplay(iClient));
}

void SetPlayerLoadout(int iClient, int iRank)
{
	if (iRank >= GGWeapon.SeriesTotal()) return;
	
	GGWeapon hWeapon = GGWeapon.GetFromSeries(iRank);
	TFClassType eClass = hWeapon.Class;

	TF2_RemoveCondition(iClient, TFCond_Taunting);
	
	if (TF2_GetPlayerClass(iClient) != eClass)
		TF2_SetPlayerClass(iClient, eClass, _, true);

	SetEntityHealth(iClient, g_iClassMaxHP[view_as<int>(eClass)]);
	TF2_RemoveAllWeapons(iClient);
	
	char strClassname[128], strAttributes[128];
	hWeapon.GetClassname(strClassname, sizeof(strClassname));
	hWeapon.GetAttributeOverride(strAttributes, sizeof(strAttributes));
	
	int iWeapon = CreateWeapon(iClient, strClassname, hWeapon.Index, 1, 1, strAttributes);
	FlagWeaponDontDrop(iWeapon);
	
	if (hWeapon.ClipOverride)
		SetEntData(iWeapon, FindSendPropInfo("CTFWeaponBase", "m_iClip1"), hWeapon.ClipOverride, _, true);
	else if (hWeapon.Index == 741 || hWeapon.Index == 739) // Rainblower fix, thanks to Benoist3012
		SetEntProp(iWeapon, Prop_Send, "m_nModelIndexOverrides", GetEntProp(iWeapon, Prop_Send, "m_nModelIndexOverrides", _, 3), _, 0);
	
	SetMaxAmmo(iClient, iWeapon);
	EquipPlayerWeapon(iClient, iWeapon);
	
	// Create and equip a necro smasher if melee not given, and not a bot
	if (hWeapon.Slot != 2 && !IsFakeClient(iClient))
		EquipPlayerWeapon(iClient, CreateWeapon(iClient, "tf_weapon_fireaxe", 1123, 50, 6, "1 ; 0.75"));
	
	if (GetGameTime() < g_flRoundUnfreezeTime)
		SetNextAttack(iClient, g_flRoundUnfreezeTime);
	
	RefreshClientScore(iClient);
}

void GenerateRoundWeps()
{
	GGWeapon.InitSeries();

	KeyValues hKvConfig = new KeyValues("WeaponSeries");
	char strPath[PLATFORM_MAX_PATH];
	
	BuildPath(Path_SM, strPath, PLATFORM_MAX_PATH, "configs/gungame-series.cfg");
	
	hKvConfig.ImportFromFile(strPath);
	
	if (hKvConfig == null)
		SetFailState("[GunGame] Config file not found or invalid!");
	
	char strSectionName[128];
	hKvConfig.GetSectionName(strSectionName, sizeof(strSectionName));
	if (!StrEqual("WeaponSeries", strSectionName))
		SetFailState("[GunGame] Config file is invalid!");
	
	if (!hKvConfig.JumpToKey("RoundModifiers"))
		SetFailState("[GunGame] Config file has no RoundModifiers node!");

	if (!hKvConfig.JumpToKey(g_strSpecialRoundName[view_as<int>(g_eCurrentSpecial)]))
		SetFailState("[GunGame] Config file is missing the \"%s\" RoundModifiers node!", g_strSpecialRoundName[view_as<int>(g_eCurrentSpecial)]);
	
	if (!hKvConfig.GotoFirstSubKey(false))
		SetFailState("[GunGame] Config file is missing sequences inside the \"%s\" RoundModifiers node!", g_strSpecialRoundName[view_as<int>(g_eCurrentSpecial)]);

	ArrayList hSeriesNames = new ArrayList(128);

	do
	{
		// Grab all sequences from the current round modifier
		char strName[128];
		hKvConfig.GetSectionName(strName, sizeof(strName));
		hSeriesNames.PushString(strName);
	}
	while (hKvConfig.GotoNextKey(false));
	
	hKvConfig.Rewind();
	if (!hKvConfig.JumpToKey("WeaponSequences"))
		SetFailState("[GunGame] Config file is missing the WeaponSequences node!");
	
	// Keep picking a random sequence until a valid one is found
	while (hSeriesNames.Length)
	{
		char strName[128];
		int iElement = GetRandomInt(0, hSeriesNames.Length - 1);
		hSeriesNames.GetString(iElement, strName, sizeof(strName));
		if (!hKvConfig.JumpToKey(strName))
		{
			hSeriesNames.Erase(iElement);
			PrintToServer("[GunGame] Warning! Config file is missing the WeaponSequence \"%s\" found in the RoundModifier \"%s\".", strName, g_strSpecialRoundName[view_as<int>(g_eCurrentSpecial)]);
			continue;
		}

		if (!hKvConfig.GotoFirstSubKey())
		{
			hKvConfig.GoBack();
			hSeriesNames.Erase(iElement);
			PrintToServer("[GunGame] Warning! Config file WeaponSequence \"%s\" is missing loadouts.", strName, g_strSpecialRoundName[view_as<int>(g_eCurrentSpecial)]);
			continue;
		}

		break;
	}

	if (!hSeriesNames.Length)
		SetFailState("[GunGame] Failed to find a valid sequence from the RoundModifiers node \"%s\"", g_strSpecialRoundName[view_as<int>(g_eCurrentSpecial)]);

	delete hSeriesNames;
	
	int j;
	ArrayList hUsedIndexes = new ArrayList();
	
	do
	{
		// Iterate through the randomly selected sequence and store each loadout
		GGWeapon hWeapon;
		int iIndex = hKvConfig.GetNum("index_override", -1);
		if (iIndex > -1)
		{
			TFClassType nClass = view_as<TFClassType>(hKvConfig.GetNum("class", view_as<int>(TFClass_Unknown)));
			hWeapon = GGWeapon.GetFromIndex(iIndex, nClass);
		}
		else
		{
			ArrayList hTemp = new ArrayList();
			for (int i = 0; i < GGWeapon.Total(); i++)
			{
				hWeapon = GGWeapon.GetFromAll(i);
				if (hUsedIndexes.FindValue(hWeapon.Index) > -1)
					continue;
				
				if (!hWeapon.Disabled && hWeapon.Class == view_as<TFClassType>(hKvConfig.GetNum("class")) && hWeapon.Slot == hKvConfig.GetNum("slot"))
					hTemp.Push(hWeapon);
			}
			
			if (hTemp.Length == 0)
				continue;
			else
				hWeapon = view_as<GGWeapon>(hTemp.Get(GetRandomInt(0, hTemp.Length - 1)));
			
			delete hTemp;
		}
		
		if (hWeapon != null)
		{
			j++;
			char strWeapon[128];
			hWeapon.GetName(strWeapon, 128);
			GGWeapon.PushToSeries(hWeapon);
			hUsedIndexes.Push(hWeapon.Index);

		#if defined DEBUG
			PrintToServer("[GunGame] Added Weapon %d: %d (%s)", j, hWeapon.Index, strWeapon);
		#endif
		}
	}
	while (hKvConfig.GotoNextKey());
	
	delete hUsedIndexes;
}

stock int CreateWeapon(int client, char[] sName, int index, int level = 1, int qual = 1, char[] att, int flags = OVERRIDE_ALL | PRESERVE_ATTRIBUTES | FORCE_GENERATION)
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

void SetMaxAmmo(int iClient, int iWeapon, int iForceAmmo = -1)
{
	int iAmmoType = GetEntProp(iWeapon, Prop_Send, "m_iPrimaryAmmoType");
	int iMaxAmmo = GetWeaponMaxAmmo(iClient, iWeapon);
	
	if (iAmmoType != -1 && iMaxAmmo != -1)
		SetEntProp(iClient, Prop_Data, "m_iAmmo", (iForceAmmo == -1) ? iMaxAmmo : iForceAmmo, _, iAmmoType);
}

void SetNextAttack(int iClient, float flNextAttack)
{
	int iWeapon;
	for (int iSlot = TFWeaponSlot_Primary; iSlot <= TFWeaponSlot_Melee; iSlot++)
	{
		iWeapon = GetPlayerWeaponSlot(iClient, iSlot);
		if (iWeapon > MaxClients && IsValidEntity(iWeapon))
		{
			SetEntPropFloat(iWeapon, Prop_Send, "m_flNextPrimaryAttack", flNextAttack);
			SetEntPropFloat(iWeapon, Prop_Send, "m_flNextSecondaryAttack", flNextAttack);
		}
	}
}

bool CanClientGetAssistCredit(int iClient)
{
	int iTotal = GGWeapon.SeriesTotal();
	int iRank = g_PlayerData[iClient].Rank;
	
	return (iRank < iTotal - 1);
}

public Action TF2Items_OnGiveNamedItem(int iClient, char[] sClassname, int iIndex, Handle &hItem)
{
	// Dont generate weapons and cosmetics from client's loadout
	return Plugin_Handled;
}

public any Native_GetRank(Handle plugin, int numParams)
{
	return g_PlayerData[GetNativeCell(1)].Rank;
}

public any Native_GetPlacements(Handle plugin, int numParams)
{
	ArrayList hPlacements = GetPlacementsArray();
	ArrayList hClone = view_as<ArrayList>(CloneHandle(hPlacements, plugin));
	
	delete hPlacements;
	return hClone;
}

public any Native_ForceRank(Handle plugin, int numParams)
{
	int iRank = GetNativeCell(2);
	int iClient = GetNativeCell(1);
	
	if (iRank < 0 || iRank >= GGWeapon.SeriesTotal())
		return false;
	
	g_PlayerData[iClient].Rank = iRank;
	SetPlayerLoadout(iClient, g_PlayerData[iClient].Rank);
	return true;
}

public any Native_ForceWin(Handle plugin, int numParams)
{
	WinPlayer(GetNativeCell(1));
	return 0;
}

public any Native_ForceRankUp(Handle plugin, int numParams)
{
	int iClient = GetNativeCell(1);
	
	if (g_PlayerData[iClient].Rank+1 >= GGWeapon.SeriesTotal())
		return false;
	
	RankUp(iClient);
	SetPlayerLoadout(iClient, g_PlayerData[iClient].Rank);
	return true;
}

public any Native_ForceRankDown(Handle plugin, int numParams)
{
	int iClient = GetNativeCell(1);
	
	if (!(g_PlayerData[iClient].Rank))
		return false;
	
	RankUp(iClient, -1);
	SetPlayerLoadout(iClient, g_PlayerData[iClient].Rank);
	return true;
}

public Action Command_Help(int iClient, int iArgs)
{
	// {orange}[GunGame]{white} In GunGame the objective is to kill other players,
	// which changes your weapon to another one. The goal is to get through every 
	// weapon until you win! However, if you get hit by a melee weapon or kill yourself,
	// you get set back one rank.
	
	ReplyToCommand(iClient, "\x07FFA500[GunGame]\x07FFFFFF %t", "HelpString1");
	ReplyToCommand(iClient, "\x07FFFFFF%t", "HelpString2");
	return Plugin_Handled;
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
