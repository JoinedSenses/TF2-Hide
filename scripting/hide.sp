#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>

#define PLUGIN_VERSION  "0.1.7"


public Plugin:myinfo = 
{
	name = "Hide Players",
	author = "[GNC] Matt",
	description = "Adds commands to show/hide other players.",
	version = PLUGIN_VERSION,
	url = "http://www.mattsfiles.com"
}

new bool:g_bHide[MAXPLAYERS + 1], bool:g_bHooked;
new g_Team[MAXPLAYERS + 1];
new Handle:g_Entities;

new Handle:g_hExplosions = INVALID_HANDLE;
new bool:g_bExplosions = true;

new bool:g_bHideEnabled = false;

new String:g_saHidable[][] = {
	"obj_sentrygun",
	"obj_dispenser",
	"obj_teleporter",
	"projectile",
	"weapon",
	"wearable"
};
new String:g_saHidableParticles[][] = {
	"ghost_pumpkin",
	"rockettrail_fire",
	"flaregun_energyfield_blue",
	"critical_grenade_red",
	"critical_rocket_red",
	"critical_rocket_blue",
	"coin_large_blue",
	"superrare_beams1"
};
new String:g_sSoundHook[][] = 
{
	"regenerate",
	"ammo_pickup",
	"pain",
	"fall_damage",
	"grenade_jump",
	"fleshbreak",
};
public OnPluginStart()
{
	CreateConVar("sm_hide_version", PLUGIN_VERSION, "Hide Players Version.", FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	RegConsoleCmd("sm_hide", cmdHide, "Show/Hide Other Players");
	RegAdminCmd("sm_hide_reload", cmdReload, ADMFLAG_SLAY, "Execute if reloading plugin with players on server.");
	HookEvent("player_team", eventChangeTeam);
	g_Entities = CreateTrie();
	
	g_hExplosions = CreateConVar("sm_hide_explosions", "1", "Enable/Disable hiding explosions.", 0);
	HookConVarChange(g_hExplosions, cvarExplosions);
	
	AddNormalSoundHook(NormalSHook:SoundHook);
	AddTempEntHook("TFExplosion", TEHook:TEHookTest);
}

public cvarExplosions(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	g_bExplosions = bool:StringToInt(newVal);
}
CheckHooks()
{
	new bool:bShouldHook = false;
	
	for (new i = 1; i <= MaxClients; i++)
	{
		if (g_bHide[i])
		{
			bShouldHook = true;
			break;
		}
	}
	
	// Fake (un)hook because toggling actual hooks will cause server instability.
	g_bHooked = bShouldHook;
}
public Action:SoundHook(clients[64], &numClients, String:sample[PLATFORM_MAX_PATH], &entity, &channel, &Float:volume, &level, &pitch, &flags)
{

	for (new i = 0; i<=sizeof(g_sSoundHook)-1; i++)
	{
		if (StrContains(sample, g_sSoundHook[i], false) != -1)
		{
			//PrintToChatAll("STOPPING SOUND: %s - %i", sample, entity);
			return Plugin_Handled;
		}
	}
	if (g_bHooked)
	{
		decl i, j;
		for (i = 0; i < numClients; i++)
		{
			if (g_bHide[clients[i]])
			{
				// Remove the client from the array.
				for (j = i; j < numClients-1; j++)
				{
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

public Action:TEHookTest(const String:te_name[], const Players[], numClients, Float:delay)
{
	if(g_bExplosions)
		return Plugin_Stop;
	return Plugin_Continue;
}
public Action:cmdHide(client, args)
{
	g_bHide[client] = !g_bHide[client];
	CheckHooks();
	if(g_bHide[client])
	{
		ReplyToCommand(client, "\x05[Hide]\x01 Other players are now hidden.");
		g_bHideEnabled = true;
	}
	else
	{
		ReplyToCommand(client, "\x05[Hide]\x01 Other players are now visible.");
		
		g_bHideEnabled = false;
		for (new i=1; i<=MaxClients && !g_bHideEnabled; i++) {
			g_bHideEnabled = IsClientInGame(i) && g_bHide[i];
		}
	}

	return Plugin_Handled;
}

public Action:eventChangeTeam(Handle:event, const String:name[], bool:dontBroadcast)
{
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	new team = GetEventInt(event, "team");
	
	g_Team[client] = team;
}

public OnEntityCreated(entity, const String:classname[])
{
	if (StrContains(classname, "obj_") == 0) {
		SDKHook(entity, SDKHook_StartTouch, OnHidableTouched);
		SDKHook(entity, SDKHook_Touch, OnHidableTouched);
	}
	for(new i = 0; i < sizeof(g_saHidable); i++){
		if((StrContains(classname, g_saHidable[i], false) != -1) && IsValidEntity(entity)){
			setFlags(entity);
			SDKHook(entity, SDKHook_Spawn, OnHidableSpawned);
		}
	}
	if (StrEqual(classname, "info_particle_system")){
		setFlags(entity);
		SDKHook(entity, SDKHook_SetTransmit, Hook_Particle_SetTransmit);
	}
}
void setFlags(int edict)
{
	if (GetEdictFlags(edict) & FL_EDICT_ALWAYS)
	{
		SetEdictFlags(edict, (GetEdictFlags(edict) ^ FL_EDICT_ALWAYS));
	}
} 
public Action:Hook_Particle_SetTransmit(entity, client)
{
	setFlags(entity);
	decl String:effectname[32];	
	GetEntPropString(entity, Prop_Data, "m_iszEffectName", effectname, sizeof(effectname));
	for(new i = 0; i < sizeof(g_saHidableParticles); i++)
	{
		if (!StrContains(effectname, g_saHidableParticles[i]))
		{
			return Plugin_Continue;
		}
	}
	if(!g_bHide[client] || g_Team[client] == 1){
		return Plugin_Continue;
	} 
	else{
		return Plugin_Handled;
	}	
}
public OnEntityDestroyed(entity)
{
	new String:sEntity[10];
	IntToString(entity, sEntity, sizeof(sEntity));
	
	SDKUnhook(entity, SDKHook_SetTransmit, Hook_Entity_SetTransmit);
	RemoveFromTrie(g_Entities, sEntity);
}
public OnHidableSpawned(entity)
{
	setFlags(entity);
	decl String:sClassName[32];
	GetEntityClassname(entity, sClassName, sizeof(sClassName));
	new owner = GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity");
	if(StrContains(sClassName, "obj_") != 0 && (owner < 1 || owner > MaxClients))
	//if(owner < 1 || owner > MaxClients)
		return;
	
	new String:sEntity[10];
	IntToString(entity, sEntity, sizeof(sEntity));
	
	SetTrieValue(g_Entities, sEntity, owner);
	SDKHook(entity, SDKHook_SetTransmit, Hook_Entity_SetTransmit);
}

public Action:OnHidableTouched(iEntity, iOther) {
	if (0 < iOther && iOther <= MaxClients) {
		if (g_bHide[iOther]) {
			return Plugin_Handled;
		}
	}
	
	return Plugin_Continue;
}

public Action:Hook_Entity_SetTransmit(entity, client)
{
	setFlags(entity);
	new String:sEntity[10];
	IntToString(entity, sEntity, sizeof(sEntity));

	new owner;
	if(!GetTrieValue(g_Entities, sEntity, owner))
		return Plugin_Continue;
		

	if(owner == client || !g_bHide[client] || g_Team[client] == 1)
		return Plugin_Continue;

	else{
		return Plugin_Handled;
	}
}


public Action:cmdReload(client, args)
{
	for(new i = 1; i <= MaxClients; i++)
	{
		g_bHide[i] = false;
		
		if (IsClientInGame(i)) {
			SDKUnhook(i, SDKHook_SetTransmit, Hook_Client_SetTransmit); 
			SDKHook(i, SDKHook_SetTransmit, Hook_Client_SetTransmit);
		}
	}
	ReplyToCommand(client, "\x05[Hide]\x01 Reloaded");
	return Plugin_Handled;
}

public OnClientPutInServer(client)
{
	g_bHide[client] = false;
	SDKHook(client, SDKHook_SetTransmit, Hook_Client_SetTransmit);
}
public OnClientDisconnect_Post(client)
{
    g_bHide[client] = false;
    CheckHooks();
}
public Action:Hook_Client_SetTransmit(entity, client)
{
	if(entity == client || !g_bHide[client] || g_Team[client] == 1)
		return Plugin_Continue;
	else {
		return Plugin_Handled;
	}
}