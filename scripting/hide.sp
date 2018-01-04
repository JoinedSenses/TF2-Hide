#pragma newdecls required
#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>

#define PLUGIN_VERSION  "0.1.9"


public Plugin myinfo = {
	name = "Hide Players",
	author = "[GNC] Matt, patched by JoinedSenses",
	description = "Adds commands to show/hide other players.",
	version = PLUGIN_VERSION,
	url = "http://www.mattsfiles.com"
}

bool g_bHide[MAXPLAYERS + 1], g_bHooked, g_bIntelPickedUp;
int g_Team[MAXPLAYERS + 1];

Handle g_hExplosions = INVALID_HANDLE;
bool g_bExplosions = true;

char g_saHidable[][] = {
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
char g_saParticles[][] = {
	"ghost_pumpkin",
	"rockettrail_fire",
	"flaregun_energyfield_blue",
	"critical_grenade_red",
	"critical_rocket_red",
	"critical_rocket_blue",
	"coin_large_blue",
	"superrare_beams1",
	"tf_glow"
};
char g_sSoundHook[][] = {
	"regenerate",
	"ammo_pickup",
	"pain",
	"fall_damage",
	"grenade_jump",
	"fleshbreak"
};
char g_saOwner[][] = {
	"weapon",
	"wearable",
	"projectile_rocket"
};
public void OnPluginStart(){
	CreateConVar("sm_hide_version", PLUGIN_VERSION, "Hide Players Version.", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	RegConsoleCmd("sm_hide", cmdHide, "Show/Hide Other Players");
	RegAdminCmd("sm_hide_reload", cmdReload, ADMFLAG_SLAY, "Execute if reloading plugin with players on server.");
	HookEvent("player_team", eventChangeTeam);
	HookEvent("teamplay_flag_event", Event_Intel, EventHookMode_Pre);
	
	g_hExplosions = CreateConVar("sm_hide_explosions", "1", "Enable/Disable hiding explosions.", 0);
	HookConVarChange(g_hExplosions, cvarExplosions);
	
	AddNormalSoundHook(SoundHook);
	AddTempEntHook("TFExplosion", TEHookTest);
	AddTempEntHook("TFBlood", TEHookTest);
}

public void cvarExplosions(ConVar cvar, const char[] oldVal, const char[] newVal){
	g_bExplosions = view_as<bool>(StringToInt(newVal));
}
void CheckHooks(){
	bool bShouldHook = false;
	
	for (int i = 1; i <= MaxClients; i++){
		if (g_bHide[i]){
			bShouldHook = true;
			break;
		}
	}
	
	// Fake (un)hook because toggling actual hooks will cause server instability.
	g_bHooked = bShouldHook;
}
public Action SoundHook(int clients[64], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags){
	for (int i = 0; i <= sizeof(g_sSoundHook)-1; i++){
		if (StrContains(sample, g_sSoundHook[i], false) != -1){
			//PrintToChatAll("STOPPING SOUND: %s - %i", sample, entity);
			return Plugin_Handled;
		}
	}
	int builder;
	char sClassName[32];
	GetEntityClassname(entity, sClassName, sizeof(sClassName));
	//PrintToChatAll("Class name of origin of %s is %s", sample, sClassName);
	if (StrContains(sClassName, "obj_") != -1){
		builder = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
	}
	if (g_bHooked){
		for (int i = 0; i < numClients; i++){
			if (g_bHide[clients[i]] && clients[i] != entity && clients[i] != builder && g_Team[clients[i]] != 1){
				// Remove the client from the array.
				for (int j = i; j < numClients-1; j++){
					clients[j] = clients[j+1];
				}
				numClients--;
				i--;
			}
		}
		return (numClients > 0) ? Plugin_Changed : Plugin_Stop;
	}
	//PrintToChatAll("ALLOWING SOUND: %s - %i", sample, entity);
	return Plugin_Continue;
}

public Action TEHookTest(const char[] te_name, const int[] Players, int numClients, float delay){
	if (g_bExplosions)
		return Plugin_Stop;
	return Plugin_Continue;
}
public Action Event_Intel(Event event,  const char[] name, bool dontBroadcast){	
	int iEventType = GetEventInt(event, "eventtype");
	int client = GetEventInt(event, "player");
	//Check event type to prevent hiding when intel is not carried.
	if (iEventType == 1){
		setFlags(client);
		g_bIntelPickedUp = true;
	}
	else if (iEventType > 1){
		g_bIntelPickedUp = false;
	}
	return Plugin_Continue;
}
public Action cmdHide(int client, int args){
	g_bHide[client] = !g_bHide[client];
	CheckHooks();
	if (g_bHide[client]){
		ReplyToCommand(client, "\x05[Hide]\x01 Other players are now hidden.");
	}
	else{
		ReplyToCommand(client, "\x05[Hide]\x01 Other players are now visible.");
	}

	return Plugin_Handled;
}

public Action eventChangeTeam(Event event, const char[] name, bool dontBroadcast){
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int team = GetEventInt(event, "team");
	
	g_Team[client] = team;
}

public void OnEntityCreated(int entity, const char[] classname){
	if (StrContains(classname, "obj_") == 0) {
		SDKHook(entity, SDKHook_StartTouch, OnHidableTouched);
		SDKHook(entity, SDKHook_Touch, OnHidableTouched);
	}
	for (int i = 0; i < sizeof(g_saHidable); i++){
		if ((StrContains(classname, g_saHidable[i], false) != -1) && IsValidEntity(entity) && IsValidEdict(entity)){
			setFlags(entity);
			SDKHook(entity, SDKHook_SetTransmit, Hook_Entity_SetTransmit);
		}
	}
	if (StrEqual(classname, "info_particle_system")){
		setFlags(entity);
		SDKHook(entity, SDKHook_SetTransmit, Hook_Particle_SetTransmit);
	}
}
void setFlags(int edict){
	if (GetEdictFlags(edict) & FL_EDICT_ALWAYS){
		SetEdictFlags(edict, (GetEdictFlags(edict) ^ FL_EDICT_ALWAYS));
	}
} 
public Action Hook_Particle_SetTransmit(int entity, int client){
	setFlags(entity);
	char effectname[32];	
	GetEntPropString(entity, Prop_Data, "m_iszEffectName", effectname, sizeof(effectname));
	for (int i = 0; i < sizeof(g_saParticles); i++){
		if (StrContains(effectname, g_saParticles[i]) == -1){
			return Plugin_Continue;
		}
	}
	if (!g_bHide[client] || g_Team[client] == 1){
		return Plugin_Continue;
	} 
	else{
		return Plugin_Handled;
	}	
}
public void OnEntityDestroyed(int entity){	
	SDKUnhook(entity, SDKHook_SetTransmit, Hook_Entity_SetTransmit);
}
public Action OnHidableTouched(int entity, int other) {
	if (0 < other && other <= MaxClients) {
		if (g_bHide[other]) {
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}
public Action Hook_Entity_SetTransmit(int entity, int client){
	setFlags(entity);
	
	char sClassName[32];
	GetEntityClassname(entity, sClassName, sizeof(sClassName));
	
	int owner = -1;
	int building = -1;
	
	if (StrContains(sClassName, "teamflag") != -1 && g_bHide[client]){
		if (g_bIntelPickedUp)
			return Plugin_Handled;
		return Plugin_Continue;
	}	
	for (int i = 0; i < sizeof(g_saOwner); i++){
		if (StrContains(sClassName, g_saOwner[i]) != -1){
			owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		}
	}
	if (StrContains(sClassName, "obj_") != -1){
		owner = GetEntPropEnt(entity, Prop_Send, "m_hBuilder");
	}
	else if (StrContains(sClassName, "tf_projectile_pipe") != -1){
		owner = GetEntPropEnt(entity, Prop_Send, "m_hThrower");
	}
	else if (StrContains(sClassName, "vgui_screen") != -1 || StrContains(sClassName, "sentryrocket") != -1){
		building = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
		char sBuildingClassName[32];
		GetEntityClassname(building, sBuildingClassName, sizeof(sBuildingClassName));
		if (StrContains(sBuildingClassName, "obj_") != -1){
			owner = GetEntPropEnt(building, Prop_Send, "m_hBuilder");
		}
	}
	//PrintToChatAll("Class: %s, Owner: %i, Client: %i, Entity: %i", sClassName, owner, client, entity);
	if (owner == client || !g_bHide[client] || g_Team[client] == 1){
		return Plugin_Continue;
	}
	else{
		return Plugin_Handled;
	}
}
public Action cmdReload(int client, int args){
	for (int i = 1; i <= MaxClients; i++){
		g_bHide[i] = false;
		
		if (IsClientInGame(i)) {
			SDKUnhook(i, SDKHook_SetTransmit, Hook_Client_SetTransmit); 
			SDKHook(i, SDKHook_SetTransmit, Hook_Client_SetTransmit);
		}
	}
	ReplyToCommand(client, "\x05[Hide]\x01 Reloaded");
	return Plugin_Handled;
}

public void OnClientPutInServer(int client){
	g_bHide[client] = false;
	SDKHook(client, SDKHook_SetTransmit, Hook_Client_SetTransmit);
}
public void OnClientDisconnect_Post(int client){
    g_bHide[client] = false;
    CheckHooks();
}
public Action Hook_Client_SetTransmit(int entity, int client){
	setFlags(entity);
	if (entity == client || !g_bHide[client] || g_Team[client] == 1)
		return Plugin_Continue;
	else {
		return Plugin_Handled;
	}
}