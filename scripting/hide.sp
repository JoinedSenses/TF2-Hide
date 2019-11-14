#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <hide>
#include <sdkhooks>
#include <tf2_stocks>

#define PLUGIN_VERSION  "0.2.8"
#define PLUGIN_DESCRIPTION "Adds commands to show/hide other players."

// --------------------------------- Global Variables

bool
	  g_bHide[MAXPLAYERS+1]
	, g_bHooked
	, g_bIntelPickedUp
	, g_bLateLoad;
int
	  g_iTeam[MAXPLAYERS+1];
ConVar
	  cvarExplosions;

//Sounds to block.
char g_sSoundHook[][] = {
	"regenerate",
	"ammo_pickup",
	"pain",
	"fall_damage",
	"grenade_jump",
	"fleshbreak"
};

//Entities to get m_hOwnerEntity net prop for
char g_sOwnerList[][] = {
	"projectile_rocket",
	"projectile_energy_ball",
	"weapon",
	"wearable",
	// conc uses prop_physics
	"prop_physics"
};

//Entities to hide.
char g_sGeneralList[][] = {
	"projectile",
	"tf_ammo_pack"
};

public Plugin myinfo = {
	name = "Hide Players",
	author = "[GNC] Matt, patched/maintained by JoinedSenses",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "http://github.com/JoinedSenses"
};

// --------------------------------- SM API

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errorMax) {
	g_bLateLoad = late;
	RegPluginLibrary("hide");
	CreateNative("Hide_IsClientHiding", Native_IsClientHiding);
	return APLRes_Success;
}

public void OnPluginStart() {
	CreateConVar("sm_hide_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY).SetString(PLUGIN_VERSION);
	cvarExplosions = CreateConVar("sm_hide_explosions", "1", "Enable/Disable hiding explosions.", 0);
	
	RegConsoleCmd("sm_hide", cmdHide, "Show/Hide Other Players");
	
	HookEvent("player_team", eventChangeTeam);
	HookEvent("teamplay_flag_event", eventIntel, EventHookMode_Pre);

	AddNormalSoundHook(hookSound);

	AddTempEntHook("TFExplosion", hookTempEnt);
	AddTempEntHook("TFBlood", hookTempEnt);
	AddTempEntHook("TFParticleEffect", hookTempEnt);

	if (g_bLateLoad) {
		for (int i = 1; i <= MaxClients; i++) {
			if (IsValidClient(i)) {
				g_iTeam[i] = GetClientTeam(i);
				SDKHook(i, SDKHook_SetTransmit, hookSetTransmitClient);
			}
		}
		int ent = -1;
		while((ent = FindEntityByClassname(ent, "item_teamflag")) != -1) {
			SDKHook(ent, SDKHook_SetTransmit, hookSetTransmitIntel);
		}
	}
}

public void OnClientPutInServer(int client) {
	g_bHide[client] = false;
	SDKHook(client, SDKHook_SetTransmit, hookSetTransmitClient);
}

public void OnClientDisconnect_Post(int client) {
    g_bHide[client] = false;
    g_bHooked = checkHooks();
}

public void OnEntityCreated(int entity, const char[] classname) {
	if (StrContains(classname, "tf_projectile_pipe") != -1) {
		SDKHook(entity, SDKHook_SetTransmit, hookSetTransmitPipes);
		return;
	}

	for (int i = 0; i < sizeof(g_sOwnerList); i++) {
		if (StrContains(classname, g_sOwnerList[i]) != -1) {
			SDKHook(entity, SDKHook_SetTransmit, hookSetTransmitOwnerEntity);
			return;
		}
	}

	//Find owner of vgui screen and sentry rockets, which will be the sentry or dispenser.		
	if (StrContains(classname, "vgui_screen") != -1 || StrContains(classname, "sentryrocket") != -1) {
		int building;
		if ((building = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity")) < 1) {
			return;
		}
		char className2[32];
		GetEntityClassname(building, className2, sizeof(className2));
		if (StrContains(className2, "obj_") != -1) {
			SDKHook(entity, SDKHook_SetTransmit, hookSetTransmitObjects);
			return;
		}
	}

	for (int i = 0; i < sizeof(g_sGeneralList); i++) {
		if (StrContains(classname, g_sGeneralList[i]) != -1) {
			SDKHook(entity, SDKHook_SetTransmit, hookSetTransmitProjectiles);
			return;
		}
	}

	//Touch hook on Engineer buildings.
	if (StrContains(classname, "obj_") == 0) {
		SDKHook(entity, SDKHook_StartTouch, hookTouch);
		SDKHook(entity, SDKHook_Touch, hookTouch);
		SDKHook(entity, SDKHook_SetTransmit, hookSetTransmitObjects);
		return;
	}

	//Seperate hook for particles.
	if (StrEqual(classname, "info_particle_system")) {
		SDKHook(entity, SDKHook_SetTransmit, hookSetTransmitParticle);
		return;
	}

	if (StrEqual(classname, "teamflag")) {
		SDKHook(entity, SDKHook_SetTransmit, hookSetTransmitIntel);
		return;
	}
}

// --------------------------------- Natives

public int Native_IsClientHiding(Handle plugin, int numParams) {
	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index (%d)", client);
	}
	if (!IsClientConnected(client)) {
		return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not connected", client);
	}
	return IsHiding(client);
}

// ---------------------------------  Events

public Action eventChangeTeam(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	//Team change check to see if client is a spectator or not.	
	g_iTeam[client] = event.GetInt("team"); 
}

public Action eventIntel(Event event,  const char[] name, bool dontBroadcast) {	
	event.BroadcastDisabled = true;
	int eventType = event.GetInt("eventtype");
	int client = event.GetInt("player");
	
	//Check event type to prevent hiding when intel is not carried.
	if (eventType == 1) {
		setFlags(client);
		g_bIntelPickedUp = true;
	}
	else if (eventType > 1) {
		g_bIntelPickedUp = false;
	}
	return Plugin_Continue;
}

// --------------------------------- Commands

public Action cmdHide(int client, int args) {
	g_bHide[client] = !g_bHide[client];
	g_bHooked = checkHooks();
	PrintToChat(client, "\x05[Hide]\x01 Other players are now\x03 %s\x01.", IsHiding(client) ? "hidden" : "visible");
	return Plugin_Handled;
}

// --------------------------------- Hooks

public Action hookSound(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags) {
	//Block sounds within g_sSoundHook list.
	for (int i = 0; i <= sizeof(g_sSoundHook)-1; i++) {
		if (StrContains(sample, g_sSoundHook[i], false) != -1) {
			return Plugin_Stop; 
		}
	}
	
	if (!g_bHooked) {
		return Plugin_Continue;
	}
	
	int owner;
	char className[32];

	GetEntityClassname(entity, className, sizeof(className));
	//Get ownership of sound for sentry rockets.
	if (StrContains(className, "obj_") != -1) {
		owner = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
	}
	else if (StrContains(className, "prop_physics") != -1) {
		owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	}
	for (int i = 0; i < numClients; i++) {
		int client = clients[i];
		if (IsHiding(client) && client != entity && client != owner && g_iTeam[client] != 1) {
			//Remove the client from the array if they have hide toggled, if they are not the creator of the sound, and if they are not in spectate.
			for (int j = i; j < numClients-1; j++) {
				clients[j] = clients[j+1];
			}
			numClients--;
			i--;
		}
	}
	
	return numClients ? Plugin_Changed : Plugin_Stop;
}

public Action hookSetTransmitClient(int entity, int client) {
	setFlags(entity);
	//Transmit hook on player models.
	if (entity == client || !IsHiding(client) || g_iTeam[client] == 1) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookSetTransmitPipes(int entity, int client) {
	if (!IsHiding(client) || g_iTeam[client] == 1) {
		return Plugin_Continue;
	}

	int owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
	return (owner == client) ? Plugin_Continue : Plugin_Handled;
}

public Action hookSetTransmitOwnerEntity(int entity, int client) {
	setFlags(entity);
	if (!IsHiding(client) || g_iTeam[client] == 1) {
		return Plugin_Continue;
	}
	int owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	return (owner == client) ? Plugin_Continue : Plugin_Handled;
}

public Action hookSetTransmitObjects(int entity, int client) {
	if (!IsHiding(client) || g_iTeam[client] == 1) {
		return Plugin_Continue;
	}

	int owner = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
	return (owner == client) ? Plugin_Continue : Plugin_Handled;
}

public Action hookSetTransmitProjectiles(int entity, int client) {
	if (!IsHiding(client) || g_iTeam[client] == 1) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookSetTransmitParticle(int entity, int client) {
	setFlags(entity);
	return Plugin_Continue;
}

public Action hookSetTransmitIntel(int entity, int client) {
	setFlags(entity);
	if (!IsHiding(client) || g_iTeam[client] == 1) {
		return Plugin_Continue;
	}
	return g_bIntelPickedUp ? Plugin_Handled : Plugin_Continue;
}

public Action hookTempEnt(const char[] te_name, const int[] players, int numClients, float delay) {
	if (cvarExplosions.BoolValue) {
		//Remove explosion, blood, and cow mangler temp ents from game.
		if (StrEqual(te_name, "TFExplosion") || StrEqual(te_name, "TFBlood")) {
			return Plugin_Handled;
		}

		if (StrContains(te_name, "ParticleEffect") != -1) {
			switch (TE_ReadNum("m_iParticleSystemIndex")) {
				case 1138, 1147, 1153, 1154: {
					return Plugin_Handled;
				}
			}
		}
	}
	return Plugin_Continue;
}

public Action hookTouch(int entity, int other) {
	//If valid client and hide is toggled, prevent them from touching buildings
	if (0 < other <= MaxClients && IsHiding(other)) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

// --------------------------------- Internal Functions

bool checkHooks() {	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i) && IsHiding(i)) {
			return true;
		}
	}
	//Fake (un)hook because toggling actual hooks will cause server instability.
	return false;
}

void setFlags(int edict) {
	//Function for allowing transmit hook for entities set to always transmit
	if (GetEdictFlags(edict) & FL_EDICT_ALWAYS) {
		SetEdictFlags(edict, (GetEdictFlags(edict) & ~FL_EDICT_ALWAYS));
	}
}

bool IsHiding(int client) {
	return g_bHide[client];
}

bool IsValidClient(int client) {
	return (0 < client <= MaxClients && IsClientInGame(client));
}