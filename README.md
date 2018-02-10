# TF2-Hide
A modification to GNC Matt's Hide Plugin

This plugin was specifically created with TF2 rocket jump and surf servers in mind.

## Commands:
* sm_hide
* sm_hide_reload
 
This player hides all other players and the sounds they generate.
 
The plugin also has a section for particles that are allowed, though if your server has a particle plugin, you must change the edict flags of both the particle and the parent.
```
void setFlags(int edict){
  if (GetEdictFlags(edict) & FL_EDICT_ALWAYS){
    SetEdictFlags(edict, (GetEdictFlags(edict) ^ FL_EDICT_ALWAYS));
  }
}
```
You must then modify the particle list within the hide source to prevent specific particles from behind hidden by their owners. They will hide if the parent is hidden.
