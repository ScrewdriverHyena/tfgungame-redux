#if !defined TFGG_MAIN
	#error Don't compile this file, compile tfgungame.sp instead!
#endif

static StringMap g_hIndexToWeapon;
static ArrayList g_hWeapons;
static ArrayList g_hWeaponSeries;

enum eWeaponProperties
{
	WEAPON_NAME = 0,
	WEAPON_INDEX,
	WEAPON_TFCLASS,
	WEAPON_SLOT,
	WEAPON_CLASSNAME,
	WEAPON_DISABLED,
	WEAPON_ATT,
	WEAPON_CLIP,
	
	WEAPONPROP_COUNT
};

public any Native_GGWeapon(Handle plugin, int numParams)
{
	KeyValues hKvWeapons = view_as<KeyValues>(GetNativeCell(1));
	
	char strSectionName[128];
	hKvWeapons.GetSectionName(strSectionName, sizeof(strSectionName));

	int i = g_hWeapons.Length;

	int iIndex = hKvWeapons.GetNum("index", -1);
	if (iIndex == -1)
		SetFailState("[GunGame] Index not found for weapon %d!", i);
	
	TFClassType eClass = view_as<TFClassType>(hKvWeapons.GetNum("tfclass", 0));
	if (eClass == TFClass_Unknown)
		SetFailState("[GunGame] TFClass not found for weapon %d!", i);
	
	bool bSelectOverride = view_as<bool>(hKvWeapons.GetNum("select_override", 0));
	
	char strAttOverride[128];
	hKvWeapons.GetString("att_override", strAttOverride, sizeof(strAttOverride));
	
	int iClipOverride = hKvWeapons.GetNum("clip_override", 0);
	char strClassname[128];
	TF2Econ_GetItemClassName(iIndex, strClassname, sizeof(strClassname));
	TF2Econ_TranslateWeaponEntForClass(strClassname, sizeof(strClassname), eClass);
	
	ArrayList hWeapon = new ArrayList(128, WEAPONPROP_COUNT);
	hWeapon.SetString(WEAPON_NAME, strSectionName);
	hWeapon.Set(WEAPON_INDEX, iIndex);
	hWeapon.Set(WEAPON_TFCLASS, eClass);
	hWeapon.Set(WEAPON_SLOT, TF2Econ_GetItemLoadoutSlot(iIndex, eClass));
	hWeapon.SetString(WEAPON_CLASSNAME, strClassname);
	hWeapon.Set(WEAPON_DISABLED, bSelectOverride);
	hWeapon.SetString(WEAPON_ATT, strAttOverride);
	hWeapon.Set(WEAPON_CLIP, iClipOverride);
	
	char strKey[32];
	FormatEx(strKey, sizeof(strKey), "%d_%s", iIndex, g_strClassNames[eClass]);
	g_hIndexToWeapon.SetValue(strKey, hWeapon);
	return view_as<GGWeapon>(hWeapon);
}

public any Native_GGWeaponInit(Handle plugin, int numParams)
{
	delete g_hIndexToWeapon;
	g_hIndexToWeapon = new StringMap();
	
	delete g_hWeapons;
	g_hWeapons = new ArrayList();
	
	delete g_hWeaponSeries;
	g_hWeaponSeries = new ArrayList();

	KeyValues hKvWeapons = new KeyValues("WeaponData");
	char strPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, strPath, PLATFORM_MAX_PATH, "data/gungame-data.txt");
	hKvWeapons.ImportFromFile(strPath);
	if (hKvWeapons == null)
		SetFailState("[GunGame] Weapon Data file not found or invalid!");
	
	char strSectionName[128];
	hKvWeapons.GetSectionName(strSectionName, sizeof(strSectionName));
	if (!StrEqual("WeaponData", strSectionName))
		SetFailState("[GunGame] Weapon Data file is invalid!");
	
	if (!hKvWeapons.GotoFirstSubKey())
		SetFailState("[GunGame] Weapon Data file has no weapons!");

	do
	{
		GGWeapon hWeapon = new GGWeapon(hKvWeapons);
		if (hWeapon == null) ThrowError("[GunGame] Invalid Weapon at %d", g_hWeapons.Length + 1);
		
		g_hWeapons.Push(hWeapon);
	}
	while (hKvWeapons.GotoNextKey());
	return 0;
}

public any Native_GGWeaponInitSeries(Handle plugin, int numParams)
{
	g_hWeaponSeries.Clear();
	delete g_hWeaponSeries;
	g_hWeaponSeries = new ArrayList();
	return 0;
}

public any Native_GGWeaponTotal(Handle plugin, int numParams) { return g_hWeapons.Length; }
public any Native_GGWeaponSeriesTotal(Handle plugin, int numParams) { return g_hWeaponSeries.Length; }

public any Native_GGWeaponGetFromIndex(Handle plugin, int numParams)
{
	int idx = GetNativeCell(1);
	TFClassType nClass = GetNativeCell(2);
	char strKey[32];
	GGWeapon hWeapon;
	
	// Class not specified
	if (nClass == TFClass_Unknown)
	{
		for (TFClassType nSearchClass = TFClass_Scout; nSearchClass <= TFClass_Engineer; nSearchClass++)
		{
			FormatEx(strKey, sizeof(strKey), "%d_%s", idx, g_strClassNames[nSearchClass]);
			if (g_hIndexToWeapon.GetValue(strKey, hWeapon))
				return hWeapon;
		}
	}
	else
	{
		FormatEx(strKey, sizeof(strKey), "%d_%s", idx, g_strClassNames[nClass]);
		if (g_hIndexToWeapon.GetValue(strKey, hWeapon))
			return hWeapon;
	}
	
	char strErrorBuffer[128];
	if (nClass != TFClass_Unknown)
		FormatEx(strErrorBuffer, sizeof(strErrorBuffer), " or index-class combination (class %d)", nClass);
	
	Format(strErrorBuffer, sizeof(strErrorBuffer), "[GunGame] Invalid index %d%s passed to GetFromIndex! This weapon will be skipped.", idx, strErrorBuffer);
	LogError(strErrorBuffer);
	return hWeapon;
}

public any Native_GGWeaponPushToSeries(Handle plugin, int numParams)
{
	if (g_hWeaponSeries == null) g_hWeaponSeries = new ArrayList();
	g_hWeaponSeries.Push(GetNativeCell(1));
	return 0;
}

public any Native_GGWeaponGetFromSeries(Handle plugin, int numParams)
{
	int idx = GetNativeCell(1);
	if (idx < GGWeapon.SeriesTotal())
		return view_as<GGWeapon>(g_hWeaponSeries.Get(idx));
	else
		return view_as<GGWeapon>(null);
}

public any Native_GGWeaponGetFromAll(Handle plugin, int numParams)
{
	int idx = GetNativeCell(1);
	if (idx < GGWeapon.Total())
	{
		GGWeapon hWeapon = view_as<GGWeapon>(g_hWeapons.Get(idx));
		if (hWeapon == null)
			ThrowError("[GunGame] Invalid index %d passed to GetFromAll! Null Handle", idx);
		
		return hWeapon;
	}
	else
	{
		ThrowError("[GunGame] Invalid index %d passed to GetFromAll!", idx);
		return view_as<GGWeapon>(INVALID_HANDLE);
	}
}

public any Native_GGWeaponGetName(Handle plugin, int numParams)
{
	ArrayList hThis = view_as<ArrayList>(GetNativeCell(1));
	int maxlength = GetNativeCell(3);
	char[] strBuf = new char[maxlength];
	hThis.GetString(WEAPON_NAME, strBuf, maxlength);
	
	int bytes;
	SetNativeString(2, strBuf, maxlength, _, bytes);
	return bytes;
}

public any Native_GGWeaponGetClassname(Handle plugin, int numParams)
{
	ArrayList hThis = view_as<ArrayList>(GetNativeCell(1));
	int maxlength = GetNativeCell(3);
	char[] strBuf = new char[maxlength];
	hThis.GetString(WEAPON_CLASSNAME, strBuf, maxlength);
	
	int bytes;
	SetNativeString(2, strBuf, maxlength, _, bytes);
	return bytes;
}

public any Native_GGWeaponGetAttributeOverride(Handle plugin, int numParams)
{
	ArrayList hThis = view_as<ArrayList>(GetNativeCell(1));
	int maxlength = GetNativeCell(3);
	char[] strBuf = new char[maxlength];
	hThis.GetString(WEAPON_ATT, strBuf, maxlength);
	
	if (!strBuf[0]) return false;
	
	int bytes;
	SetNativeString(2, strBuf, maxlength, _, bytes);
	SetNativeCellRef(4, bytes);
	return true;
}

public any Native_GGWeaponIndex(Handle plugin, int numParams) { return (view_as<ArrayList>(GetNativeCell(1))).Get(WEAPON_INDEX); }
public any Native_GGWeaponClass(Handle plugin, int numParams) { return (view_as<ArrayList>(GetNativeCell(1))).Get(WEAPON_TFCLASS); }
public any Native_GGWeaponSlot(Handle plugin, int numParams)  { return (view_as<ArrayList>(GetNativeCell(1))).Get(WEAPON_SLOT); }
public any Native_GGWeaponDisabled(Handle plugin, int numParams) { return (view_as<ArrayList>(GetNativeCell(1))).Get(WEAPON_DISABLED); }
public any Native_GGWeaponClipOverride(Handle plugin, int numParams) { return (view_as<ArrayList>(GetNativeCell(1))).Get(WEAPON_CLIP); }