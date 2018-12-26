#if defined _hide_included_
  #endinput
#endif
#define _hide_included_

public SharedPlugin __pl_hide = {
	name = "hide",
	file = "hide.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
}

/**
 * Checks if client has hidden other players
 *
 * @param client	Client index
 * @return			Bool value - Is client hiding other players?
 */
native bool Hide_IsClientHiding(int client);