# TFGunGame: Redux
## Description
  A new multiplayer sourcemod plugin for Team Fortress 2: Play in a deathmatch against other players in which your
 weapon progresses through a series of weapons, and the first to get to the end of the series wins the round! This mod is mainly made for `gg_` maps, however, it should work on other maps as well, just not as well.
 
 *__**TODO:**__ Add downloads to the known gg_ maps here.
 
## Credits
**Screwdriver (FKA Frosty Scales)** - Programmer    
**wo** - Programmer

**Benoist3012** - French Translation & Lots of programming help, overall mentoring me in SourcePawn coding    
**42** - gg_burgstadt and major fixes for lag-related issues    
**Alex Turtle** - French Translation    
**Heroin Hero** - Finnish Translation    
**PestoVerde** - Italian Translation    
**unitgon** - Dutch Translation    
**NotPaddy** - German Translation    
**RatX** - Spanish Translation    

 
## ConVars
| ConVar | Default Value | Description |
|---|---|---|
| tfgg_spawnprotect_length | -1.0 | Length of the spawn protection for players, set to 0.0 to disable and -1.0 for infinite length |
| tfgg_allow_suicide | 0 | Set to 1 to not humiliate players when they suicide |
| tfgg_max_kills_per_rankup | 3 | Maximum amount of kills registered toward the next rank. -1 for no limit. |
| tfgg_last_rank_sound |  | Sound played when someone has hit the last rank |
| tfgg_win_sound |  | Sound played when someone wins the game |
| tfgg_humiliation_sound |  | Sound played to a player when they've been humiliated |

## Configs
### Weapon Data
  This plugin does **not** depend on TF2II or TF2IDB, rather, it gets its weapon information and weapon pool from a data file I've included with the plugin. Here's an example:
```
	"The Cow Mangler 5000"
	{
		"index" "441"
		"tfclass" "3"
		"slot" "0"
		"classname" "tf_weapon_particle_cannon"
	}
```

  It's fairly self-explanatory, and most, if not all, the information needed can be found on the AlliedModders wiki.
Another example, this time of a weapon that can't be selected unless it's forced by the series config:
```
	"Rocket Launcher"
	{
		"index" "18"
		"tfclass" "3"
		"slot" "0"
		"select_override" "1"
		"classname" "tf_weapon_rocketlauncher"
	}
```

  It also supports "custom" weapons, as in weapons with custom attributes. Here's a replication of The Army of One, a rocket launcher that fires a single, slow speed nuke:
```
	"The Army of One"
	{
		"index" "228"
		"tfclass" "3"
		"slot" "0"
		"classname" "tf_weapon_rocketlauncher"
		"select_override" "1"
		"att_override" "2 ; 5.0 ; 99 ; 3.0 ; 521 ; 1.0 ; 3 ; 0.25 ; 104 ; 0.3 ; 77 ; 0.0 ; 16 ; 0.0"
		"flags_override" "31"
		"clip_override" "1"
	}
```
It uses `att_override` as an attributes string, with attributes to be applied followed by their values. `flags_override` will override the flags the weapon is granted with, such as FORCE_GENERATION and OVERRIDE_ALL. These need to be set with their numeric values, however. `clip_override` will override the max clip of the weapon.

*__**TODO:**__ Add a model override setting for fully customized weapons.

### Weapon Series
  There are a few settings to be played with here. Let's take a look at the file:
```
	"1"
	{
		"index_override" "18"
	}
```
  This is the first weapon in the config. The `"1"` label however, is purely descriptive, and will still work regardless of what it's set to. The `index_override` forces the first weapon in the series to index 18 (Rocket Launcher). Another example:
```
	"2"
	{
		"class" "4"
		"slot" "0"
	}
```
  This example will pick a random weapon from class 4 (DemoMan), and slot 0 (Primary).

## API
  An include file comes with the mod, if you know what you're doing feel free to tinker with it. Here's some documentation:
  
### GGWeapon
  The properties in this methodmap mirror the properties in the weapon data file.
  
### Forwards
| Forward | Description |
|---|---|
| `void OnGunGameWin(int client)` | Called whenever a player wins a round of GunGame |
| `void OnGunGameRankUp(int attacker, int victim, int rank, GGWeapon weapon, GGWeapon oldweapon)` | Called whenever a player ranks up, along with handles for the weapons, the rank, the victim, and the attacker |
| `void OnGunGameRankDown(int attacker, int victim, int rank, GGWeapon weapon, GGWeapon oldweapon)` | Same as the above, however, it's called whenever a player ranks down |

### Natives
| Native | Description |
|---|---|
| `native int GetGunGameRank(int client)` | Returns the current rank of the player |
| `void ForceGunGameWin(int client)` | Force a player to win, will call `OnGunGameWin()` |
| `bool ForceGunGameRank(int client, int rank)` | Force a player to a certain rank, returns `false` if the rank is invalid |
| `bool ForceGunGameRankUp(int client)` | Force a player to rank up, returns `false` if the rank is invalid |
| `bool ForceGunGameRankDown(int client)` | Force a player to rank down, returns `false` if the rank is invalid |
  
