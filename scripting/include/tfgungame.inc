#if defined _tfgungame_included
	#endinput
#endif
#define _tfgungame_included

methodmap GGWeapon < ArrayList
{
	public native GGWeapon(KeyValues hKvWeapons);
	public static native void Init();
	public static native void InitSeries();
	public static native int Total();
	public static native int SeriesTotal();
	public static native GGWeapon GetFromIndex(int idx);
	public static native void PushToSeries(GGWeapon hWeapon);
	public static native GGWeapon GetFromSeries(int idx);
	public static native GGWeapon GetFromAll(int idx);
	public native int GetName(char[] strName, int maxlength);
	public native int GetClassname(char[] strName, int maxlength);
	public native bool GetAttributeOverride(char[] strName, int maxlength, int &bytes = 0);
	
	property int Index
	{
		public native get();
	}
	
	property TFClassType Class
	{
		public native get();
	}
	
	property int Slot
	{
		public native get();
	}
	
	property bool Disabled
	{
		public native get();
	}
	
	property int FlagsOverride
	{
		public native get();
	}
	
	property int ClipOverride
	{
		public native get();
	}
};

forward void OnGunGameWin(int client);
forward void OnGunGameRankUp(int attacker, int victim, int rank, GGWeapon weapon, GGWeapon oldweapon);
forward void OnGunGameRankDown(int attacker, int victim, int rank, GGWeapon weapon, GGWeapon oldweapon);

native int GetGunGameRank(int client);
native void ForceGunGameWin(int client);
native bool ForceGunGameRank(int client, int rank);
native bool ForceGunGameRankUp(int client);
native bool ForceGunGameRankDown(int client);

public SharedPlugin __pl_tfgungame =
{
	name = "tfgungame",
	file = "tfgungame.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_tfgungame_SetNTVOptional()
{
	MarkNativeAsOptional("GGWeapon.GGWeapon");
	MarkNativeAsOptional("GGWeapon.Init");
	MarkNativeAsOptional("GGWeapon.InitSeries");
	MarkNativeAsOptional("GGWeapon.Total");
	MarkNativeAsOptional("GGWeapon.SeriesTotal");
	MarkNativeAsOptional("GGWeapon.GetFromIndex");
	MarkNativeAsOptional("GGWeapon.PushToSeries");
	MarkNativeAsOptional("GGWeapon.GetFromSeries");
	MarkNativeAsOptional("GGWeapon.GetFromAll");
	MarkNativeAsOptional("GGWeapon.GetName");
	MarkNativeAsOptional("GGWeapon.GetClassname");
	MarkNativeAsOptional("GGWeapon.GetAttributeOverride");
	
	MarkNativeAsOptional("GGWeapon.Index.get");
	MarkNativeAsOptional("GGWeapon.Class.get");
	MarkNativeAsOptional("GGWeapon.Slot.get");
	MarkNativeAsOptional("GGWeapon.Disabled.get");
	MarkNativeAsOptional("GGWeapon.FlagsOverride.get");
	MarkNativeAsOptional("GGWeapon.ClipOverride.get");
	
	MarkNativeAsOptional("GetGunGameRank");
	MarkNativeAsOptional("ForceGunGameWin");
	MarkNativeAsOptional("ForceGunGameRank");
	MarkNativeAsOptional("ForceGunGameRankUp");
	MarkNativeAsOptional("ForceGunGameRankDown");
}
#endif