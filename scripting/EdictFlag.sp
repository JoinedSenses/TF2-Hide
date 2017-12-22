#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>

#define PLUGIN_VERSION  "1.0.0"

public Plugin:myinfo = 
{
	name = "Edict Flag Switcher",
	author = "JoinedSenses",
	description = "Changes edict flags, allowing for transmission hook",
	version = PLUGIN_VERSION
}
new String:g_saEntList[][] = {
	"weapon",
	"sprite",
	"projectile",
	"wearable",
	"info_particle"
};
public OnEntityCreated(entity, const String:classname[]){
	for (int i = 0; i<=sizeof(g_saEntList)-1; i++){	
		if (StrContains(classname, g_saEntList[i], false) != -1){
			SDKHook(entity, SDKHook_SetTransmit, Hook_Particle_SetTransmit);
		}
	}
}
public Action:Hook_Particle_SetTransmit(entity, client){
	if (GetEdictFlags(entity) & FL_EDICT_ALWAYS){
		SetEdictFlags(entity, (GetEdictFlags(entity) ^ FL_EDICT_ALWAYS));
	}
}