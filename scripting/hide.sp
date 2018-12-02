#pragma newdecls required
#pragma semicolon 1

#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>

#define PLUGIN_VERSION  "0.2.5"

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

//Entities to hide.
char g_sHideable[][] = {
	"obj_sentrygun",
	"obj_dispenser",
	"obj_teleporter",
	"vgui_screen",
	"teamflag",
	"projectile",
	"weapon",
	"wearable",
	"tf_ammo_pack"
};

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
char g_sOwner[][] = {
	"weapon",
	"wearable",
	"projectile_rocket",
	"projectile_energy_ball"
};

public Plugin myinfo = {
	name = "Hide Players",
	author = "[GNC] Matt, patched by JoinedSenses",
	description = "Adds commands to show/hide other players.",
	version = PLUGIN_VERSION,
	url = "http://github.com/JoinedSenses"
};

// --------------------------------- SM API

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errorMax) {
	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	CreateConVar("sm_hide_version", PLUGIN_VERSION, "Hide Players Version.", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
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
	//Touch hook on Engineer buildings.
	if (StrContains(classname, "obj_") == 0) {
		SDKHook(entity, SDKHook_StartTouch, hookTouch);
		SDKHook(entity, SDKHook_Touch, hookTouch);
	}
	//Check g_sHideable list for entities to hide.
	for (int i = 0; i < sizeof(g_sHideable); i++) {
		if ((StrContains(classname, g_sHideable[i], false) != -1) && IsValidEntity(entity) && IsValidEdict(entity)) {
			SDKHook(entity, SDKHook_SetTransmit, hookSetTransmitEntity);
		}
	}
	//Seperate hook for particles.
	if (StrEqual(classname, "info_particle_system")) {
		SDKHook(entity, SDKHook_SetTransmit, hookSetTransmitParticle);
	}
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
	PrintToChat(client, "\x05[Hide]\x01 Other players are now\x03 %s\x01.", g_bHide[client] ? "hidden" : "visible");
	return Plugin_Handled;
}

// --------------------------------- Hooks

public Action hookSound(int clients[64], int& numClients, char sample[PLATFORM_MAX_PATH], int& entity, int& channel, float& volume, int& level, int& pitch, int& flags) {
	//Block sounds within g_sSoundHook list.
	for (int i = 0; i <= sizeof(g_sSoundHook)-1; i++) {
		if (StrContains(sample, g_sSoundHook[i], false) != -1) {
			return Plugin_Stop; 
		}
	}
	
	if (g_bHooked) {
		int builder;
		char className[32];

		GetEntityClassname(entity, className, sizeof(className));
		//Get ownership of sound for sentry rockets.
		if (StrContains(className, "obj_") != -1) {
			builder = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
		}
		for (int i = 0; i < numClients; i++) {
			if (g_bHide[clients[i]] && clients[i] != entity && clients[i] != builder && g_iTeam[clients[i]] != 1) {
				//Remove the client from the array if they have hide toggled, if they are not the creator of the sound, and if they are not in spectate.
				for (int j = i; j < numClients-1; j++) {
					clients[j] = clients[j+1];
				}
				numClients--;
				i--;
			}
		}
		return (numClients > 0) ? Plugin_Changed : Plugin_Stop;
	}
	return Plugin_Continue;
}

public Action hookTempEnt(const char[] te_name, const int[] players, int numClients, float delay) {
	if (cvarExplosions.BoolValue) {
		//Remove explosion, blood, and cow mangler temp ents from game.
		if (StrEqual(te_name, "TFExplosion") || StrEqual(te_name, "TFBlood")) {
			return Plugin_Handled;
		}
		else if (StrContains(te_name, "ParticleEffect") != -1) {
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
	if (0 < other <= MaxClients && g_bHide[other]) {
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action hookSetTransmitParticle(int entity, int client) {
	setFlags(entity);
	return Plugin_Continue;
}

public Action hookSetTransmitClient(int entity, int client) {
	setFlags(entity);
	//Transmit hook on player models.
	if (entity == client || !g_bHide[client] || g_iTeam[client] == 1) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

public Action hookSetTransmitEntity(int entity, int client) {
	setFlags(entity);
	if (!g_bHide[client] || g_iTeam[client] == 1) {
		return Plugin_Continue;
	}

	int owner = -1;
	int building = -1;
	char className[32];
	
	GetEntityClassname(entity, className, sizeof(className));
	
	//Hide intel when picked up and the player carrying intel.
	if (StrContains(className, "teamflag") != -1 && g_bHide[client]) {
		return g_bIntelPickedUp ? Plugin_Handled : Plugin_Continue;
	}
	//Find owner of items within g_sOwner list.
	for (int i = 0; i < sizeof(g_sOwner); i++) {
		if (StrContains(className, g_sOwner[i]) != -1) {
			owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		}
	}
	//Find owner of Engineer buildings.
	if (StrContains(className, "obj_") != -1) {
		owner = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
	}
	//Find owner of pipes and stickies
	else if (StrContains(className, "tf_projectile_pipe") != -1) {
		owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
	}
	//Find owner of vgui screen and sentry rockets, which will be the sentry or dispenser.		
	else if (StrContains(className, "vgui_screen") != -1 || StrContains(className, "sentryrocket") != -1) {
		char className2[32];
		building = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		if (building < 0) {
			return Plugin_Continue;
		}
		GetEntityClassname(building, className2, sizeof(className2));
		if (StrContains(className2, "obj_") != -1) {
			owner = GetEntPropEnt(building, Prop_Send, "m_hBuilder");
		}
	}
	
	//Ownership check - prevents client from hiding their own entities, hide toggle check, and spectator check.
	if (owner == client) {
		return Plugin_Continue;
	}
	return Plugin_Handled;
}

// --------------------------------- Internal Functions

bool checkHooks() {	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsValidClient(i) && g_bHide[i]) {
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

bool IsValidClient(int client) {
	return (0 < client <= MaxClients && IsClientInGame(client));
}