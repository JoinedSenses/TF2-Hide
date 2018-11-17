# TF2-Hide
An overhaul of [GNC] Matt's Hide Plugin

This plugin was specifically created with TF2 rocket jump and surf servers in mind.

### Commands:
* sm_hide
 
This player hides all other players and the sounds they generate.
 
The plugin also has a section for particles that are allowed, though if your server has a particle plugin, you must change the edict flags of both the particle and the parent.
```
void setFlags(int edict){
  if (GetEdictFlags(edict) & FL_EDICT_ALWAYS){
    SetEdictFlags(edict, (GetEdictFlags(edict) ^ FL_EDICT_ALWAYS));
  }
}
```
