#pragma semicolon 1

#include <sourcemod>
#include <cstrike>
#include <chat-processor>
#include <csgocolors_fix.inc>

#pragma newdecls required

#define TYPE_MAINMENU 0
#define TYPE_SETTAG 1
#define TYPE_TAGCOLOR 2
#define TYPE_NAMECOLOR 3
#define TYPE_CHATCOLOR 4

ConVar g_Cvar_AllowTag;
ConVar g_Cvar_AllowName;
ConVar g_Cvar_AllowChat;

ConVar g_Cvar_DataMode;

bool g_bAllowTag;
bool g_bAllowName;
bool g_bAllowChat;

int g_iClientSelectMode[MAXPLAYERS+1];
int g_iDataMode;

bool g_bPlayerCommandInited[5] = false;

int g_iTargetSelected[MAXPLAYERS+1];

enum struct ClientCustomData
{
	int ChatColor_id;
	int NameColor_id;

	char CustomTag[64];
}

enum struct ColorData
{
	char color_name[16];
	char color_code[16];
	char color_tag[64];
}

ClientCustomData g_iClientData[MAXPLAYERS+1];
ColorData g_ColorData[72];

int g_iTotalColor;

public Plugin myinfo = 
{
	name = "[CSGO] Fully Customizable Chat",
	author = "Oylsister",
	description = "Allow client to have fancy color name",
	version = "1.0",
	url = "https://github.com/oylsister/"
};

public void OnPluginStart()
{
	g_Cvar_AllowChat = CreateConVar("sm_customchat_allowchat", "1.0", "Allow player to customize their chat color", _, true, 0.0, true, 1.0);
	g_Cvar_AllowName = CreateConVar("sm_customchat_allowname", "1.0", "Allow player to customize their name color", _, true, 0.0, true, 1.0);
	g_Cvar_AllowTag = CreateConVar("sm_customchat_allowtag", "1.0", "Allow player to customize their tag name and color", _, true, 0.0, true, 1.0);

	g_Cvar_DataMode = CreateConVar("sm_customchat_datamode", "1.0", "The place for storing player custom chat data (1 = Store in .cfg, 2 = Store in MySQL)", _, true, 1.0, true, 2.0);

	CreateCommand();

	HookConVarChange(g_Cvar_AllowChat, OnAllowChanged);
	HookConVarChange(g_Cvar_AllowName, OnAllowChanged);
	HookConVarChange(g_Cvar_AllowTag, OnAllowChanged);

	g_iDataMode = g_Cvar_DataMode.IntValue;

	AutoExecConfig(true, "csgo_customchat");
}

public void OnClientPostAdminCheck(int client)
{
	g_iClientData[client].ChatColor_id = -1;
	g_iClientData[client].NameColor_id = -1;
	g_iClientData[client].CustomTag[0] = '\0';

	char sPath[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, sPath, sizeof(sPath), "data/customchat/customchat.txt");

	KeyValues kv = CreateKeyValues("client_colors");
	FileToKeyValues(kv, sPath);

	char sAuth[128];
	GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth), false);

	if(IsClientVIP(client) || IsClientAdmin(client))
	{
		if(KvJumpToKey(kv, sAuth, false))
		{
			KvGetNum(kv, "chatcolor", g_iClientData[client].ChatColor_id);
			KvGetNum(kv, "namecolor", g_iClientData[client].NameColor_id);
			KvGetString(kv, "customtag", g_iClientData[client].CustomTag, 64);
		}
	}
	
	delete kv;
}

public void OnClientDisconnect(int client)
{
	g_iClientData[client].ChatColor_id = -1;
	g_iClientData[client].NameColor_id = -1;
	g_iClientData[client].CustomTag[0] = '\0';
}

public void OnAllowChanged(ConVar cvar, char[] newvalue, char[] oldvalue)
{
	CheckCvar();
}

void CheckCvar()
{
	g_bAllowChat = GetConVarBool(g_Cvar_AllowChat);
	g_bAllowName = GetConVarBool(g_Cvar_AllowName);
	g_bAllowTag = GetConVarBool(g_Cvar_AllowTag);
}

void CreateCommand()
{
	// Admin Command
	RegAdminCmd("sm_forcename", Command_ForceNameColor, ADMFLAG_KICK);
	RegAdminCmd("sm_forcechat", Command_ForceChatColor, ADMFLAG_KICK);
	RegAdminCmd("sm_forcetag", Command_ForceTagColor, ADMFLAG_KICK);

	// Player Command
	for(int i = 0; i < 5; i++)
	{
		g_bPlayerCommandInited[i] = false;
	}
	GetPlayerCustomCommand();
	LoadColorConfig();
}

public Action Command_ForceNameColor(int client, int args)
{
	if(args < 1 || args > 2)
	{
		ReplyToCommand(client, " \x04[CustomChat]\x01 Usage: sm_forcename <client> [color]");
		return Plugin_Handled;
	}

	char sArg1[128], sArg2[64];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	GetCmdArg(2, sArg2, sizeof(sArg2));

	int target = FindTarget(client, sArg1, true, false);

	if(!IsClientInGame(target))
	{
		ReplyToCommand(client, " \x04[CustomChat]\x01 Invalid user.");
		return Plugin_Handled;
	}

	g_iTargetSelected[client] = target;

	if(strlen(sArg2) <= 0)
	{
		ForceColorSelection(client, TYPE_NAMECOLOR, g_iTargetSelected[client]);
		return Plugin_Handled;
	}

	for(int i = 0; i < g_iTotalColor; i++)
	{
		if(StrEqual(sArg2, g_ColorData[i].color_name))
		{
			g_iClientData[target].NameColor_id = i;
			CPrintToChat(client, " \x04[CustomChat]\x01 You have changed \x05%N \x01name color to %s%s\x01.", g_iTargetSelected[client], g_ColorData[i].color_code, g_ColorData[i].color_name);
			return Plugin_Handled;
		}
	}

	return Plugin_Handled;
}

public Action Command_ForceChatColor(int client, int args)
{
	if(args < 1 || args > 2)
	{
		ReplyToCommand(client, " \x04[CustomChat]\x01 Usage: sm_forcename <client> [color]");
		return Plugin_Handled;
	}

	char sArg1[128], sArg2[64];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	GetCmdArg(2, sArg2, sizeof(sArg2));

	int target = FindTarget(client, sArg1, true, false);

	if(!IsClientInGame(target))
	{
		ReplyToCommand(client, " \x04[CustomChat]\x01 Invalid user.");
		return Plugin_Handled;
	}

	g_iTargetSelected[client] = target;

	if(strlen(sArg2) <= 0)
	{
		ForceColorSelection(client, TYPE_CHATCOLOR, g_iTargetSelected[client]);
		return Plugin_Handled;
	}

	for(int i = 0; i < g_iTotalColor; i++)
	{
		if(StrEqual(sArg2, g_ColorData[i].color_name))
		{
			g_iClientData[target].ChatColor_id = i;
			CPrintToChat(client, " \x04[CustomChat]\x01 You have changed \x05%N \x01chat color to %s%s\x01.", g_iTargetSelected[client], g_ColorData[i].color_code, g_ColorData[i].color_name);
			return Plugin_Handled;
		}
	}

	return Plugin_Handled;
}

public Action Command_ForceTagColor(int client, int args)
{
	if(args < 1 || args > 2)
	{
		ReplyToCommand(client, " \x04[CustomChat]\x01 Usage: sm_forcename <client> [color]");
		return Plugin_Handled;
	}

	char sArg1[128], sArg2[64];
	GetCmdArg(1, sArg1, sizeof(sArg1));
	GetCmdArg(2, sArg2, sizeof(sArg2));

	int target = FindTarget(client, sArg1, true, false);

	if(!IsClientInGame(target))
	{
		ReplyToCommand(client, " \x04[CustomChat]\x01 Invalid user.");
		return Plugin_Handled;
	}

	g_iTargetSelected[client] = target;

	if(strlen(sArg2) <= 0)
	{
		ForceColorSelection(client, TYPE_TAGCOLOR, g_iTargetSelected[client]);
		return Plugin_Handled;
	}

	for(int i = 0; i < g_iTotalColor; i++)
	{
		if(StrEqual(sArg2, g_ColorData[i].color_name))
		{
			for(int x = 0; x < g_iTotalColor; x++)
			{
				ReplaceString(g_iClientData[target].CustomTag, 64, g_ColorData[x].color_tag, "");
			}

			Format(g_iClientData[target].CustomTag, 64, "%s%s", g_ColorData[i].color_tag, g_iClientData[target].CustomTag);

			char sOutput[64];
			strcopy(sOutput, sizeof(sOutput), g_iClientData[g_iTargetSelected[client]].CustomTag);
			ProceedColor(sOutput, sizeof(sOutput));
			
			CPrintToChat(client, " \x04[CustomChat]\x01 You have changed \x05%N \x01tag to %s", g_iTargetSelected[client], sOutput);
			return Plugin_Handled;
		}
	}

	return Plugin_Handled;
}

public void ForceColorSelection(int client, int type, int target)
{
	g_iClientSelectMode[client] = type;
	Menu menu = new Menu(ForceColorSelectionHandler, MENU_ACTIONS_ALL);

	char stype[64];
	int thetype = GetMenuType(stype, 64, type);

	if(thetype != -1)
	{
		menu.SetTitle("[CustomChat] %s Select Menu \n For: %N", stype, target);
		for(int i = 0; i < g_iTotalColor; i++)
		{
			menu.AddItem(g_ColorData[i].color_name, g_ColorData[i].color_name);
		}
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else
	{
		CPrintToChat(client, " \x04[CustomChat]\x01 Invaild custom chat has been chosen!");
		return;
	}
}

public int ForceColorSelectionHandler(Menu menu, MenuAction action, int client, int param)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char info[64];
			menu.GetItem(param, info, sizeof(info));

			for(int i = 0; i < g_iTotalColor; i++)
			{
				if(StrEqual(info, g_ColorData[i].color_name, false))
				{
					if(g_iClientSelectMode[client] == TYPE_CHATCOLOR)
					{
						g_iClientData[g_iTargetSelected[client]].ChatColor_id = i;
						CPrintToChat(client, " \x04[CustomChat]\x01 You have changed \x05%N \x01chat color to %s%s\x01.", g_iTargetSelected[client], g_ColorData[i].color_code, g_ColorData[i].color_name);
					}
					else if(g_iClientSelectMode[client] == TYPE_NAMECOLOR)
					{
						g_iClientData[g_iTargetSelected[client]].NameColor_id = i;
						CPrintToChat(client, " \x04[CustomChat]\x01 You have changed \x05%N \x01name color to %s%s\x01.", g_iTargetSelected[client], g_ColorData[i].color_code, g_ColorData[i].color_name);
					}
					else
					{
						for(int x = 0; x < g_iTotalColor; x++)
						{
							ReplaceString(g_iClientData[g_iTargetSelected[client]].CustomTag, 64, g_ColorData[x].color_tag, "");
						}

						Format(g_iClientData[g_iTargetSelected[client]].CustomTag, 64, "%s%s", g_ColorData[i].color_tag, g_iClientData[g_iTargetSelected[client]].CustomTag);

						char sOutput[64];
						strcopy(sOutput, sizeof(sOutput), g_iClientData[g_iTargetSelected[client]].CustomTag);
						ProceedColor(sOutput, sizeof(sOutput));
						
						CPrintToChat(client, " \x04[CustomChat]\x01 You have changed \x05%N \x01tag to %s", g_iTargetSelected[client], sOutput);
					}
				}
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void GetPlayerCustomCommand()
{
	char sPath[PLATFORM_MAX_PATH];

	char commandname[128][5];

	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/customchat/settings.cfg");

	KeyValues kv = CreateKeyValues("settings");
	FileToKeyValues(kv, sPath);

	if(KvGotoFirstSubKey(kv))
	{
		if(KvJumpToKey(kv, "Command"))
		{
			KvGetString(kv, "mainmenu_cmd", commandname[0], 128);
			KvGetString(kv, "settag_cmd", commandname[1], 128);
			KvGetString(kv, "tagcolor_cmd", commandname[2], 128);
			KvGetString(kv, "namecolor_cmd", commandname[3], 128);
			KvGetString(kv, "chatcolor_cmd", commandname[4], 128);
		}
	}
	delete kv;

	for(int i = 0; i < 5; i++)
	{
		ProceedCreateCommand(commandname[i], i);
	}
}

void ProceedCreateCommand(const char[] command, int type)
{
	if(g_bPlayerCommandInited[type])
	{
		return;
	}

	if(command[0])
	{
		if(FindCharInString(command, ',') != -1)
		{
			int idx;
			int lastidx;
			while((idx = FindCharInString(command[lastidx], ',')) != -1)
			{
				char out[128];
				char fmt[128];
				Format(fmt, sizeof(fmt), "%%.%ds", idx);
				Format(out, sizeof(out), fmt, command[lastidx]);

				if(type == TYPE_MAINMENU)
					RegConsoleCmd(out, Command_MainMenu);
				
				else if(type == TYPE_SETTAG)
					RegConsoleCmd(out, Command_Settag);

				else if(type == TYPE_TAGCOLOR)
					RegConsoleCmd(out, Command_TagColor);

				else if(type == TYPE_NAMECOLOR)
					RegConsoleCmd(out, Command_NameColor);

				else
					RegConsoleCmd(out, Command_ChatColor);
				
				lastidx += ++idx;

				if(FindCharInString(command[lastidx], ',') == -1 && command[lastidx+1] != '\0')
				{
					if(type == TYPE_MAINMENU)
						RegConsoleCmd(command[lastidx], Command_MainMenu);
					
					else if(type == TYPE_SETTAG)
						RegConsoleCmd(command[lastidx], Command_Settag);

					else if(type == TYPE_TAGCOLOR)
						RegConsoleCmd(command[lastidx], Command_TagColor);

					else if(type == TYPE_NAMECOLOR)
						RegConsoleCmd(command[lastidx], Command_NameColor);

					else
						RegConsoleCmd(command[lastidx], Command_ChatColor);
				}
			}
		}
		else
		{
			if(type == TYPE_MAINMENU)
				RegConsoleCmd(command, Command_MainMenu);
					
			else if(type == TYPE_SETTAG)
				RegConsoleCmd(command, Command_Settag);

			else if(type == TYPE_TAGCOLOR)
				RegConsoleCmd(command, Command_TagColor);

			else if(type == TYPE_NAMECOLOR)
				RegConsoleCmd(command, Command_NameColor);

			else
				RegConsoleCmd(command, Command_ChatColor);
		}
	}
	g_bPlayerCommandInited[type] = true;
}


public Action Command_MainMenu(int client, int args)
{
	if(!IsClientAdmin(client) && !IsClientVIP(client))
		return Plugin_Handled;

	Menu menu = new Menu(ColorMainMenuHandler, MENU_ACTIONS_ALL);
	menu.SetTitle("[CustomChat] Main Menu");
	menu.AddItem("namecolor", "Set Name Color");
	menu.AddItem("chatcolor", "Set Chat Color");
	menu.AddItem("tagscolor", "Set Tags Color");

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int ColorMainMenuHandler(Menu menu, MenuAction action, int client, int param)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char info[64];
			menu.GetItem(param, info, sizeof(info));

			if(StrEqual(info, "namecolor"))
				ColorSelection(client, TYPE_NAMECOLOR);

			else if(StrEqual(info, "chatcolor"))
				ColorSelection(client, TYPE_CHATCOLOR);

			else
				ColorSelection(client, TYPE_TAGCOLOR);
		}

		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

public Action Command_Settag(int client, int args)
{
	if(!IsClientAdmin(client) && !IsClientVIP(client))
		return Plugin_Handled;

	if(!g_bAllowTag)
	{
		ReplyToCommand(client, " \x04[CustomChat]\x01 This feature is currently disabled.");
		return Plugin_Handled;
	}

	if(args == 0)
	{
		ReplyToCommand(client, " \x04[CustomChat]\x01 Usage: sm_tag <tagstring>");
		return Plugin_Handled;
	}

	char sArg[64];
	GetCmdArg(1, sArg, sizeof(sArg));
	ProceedColor(sArg, 64);
	Format(g_iClientData[client].CustomTag, 64, "%s", sArg);
	ReplyToCommand(client, " \x04[CustomChat]\x01 You have set your tag to %s", sArg);
	return Plugin_Handled;
}

public Action Command_TagColor(int client, int args)
{
	if(!IsClientAdmin(client) && !IsClientVIP(client))
		return Plugin_Handled;

	if(!g_bAllowTag)
	{
		ReplyToCommand(client, " \x04[CustomChat]\x01 This feature is currently disabled.");
		return Plugin_Handled;
	}

	ColorSelection(client, TYPE_TAGCOLOR);
	return Plugin_Handled;
}

public Action Command_NameColor(int client, int args)
{
	if(!IsClientAdmin(client) && !IsClientVIP(client))
		return Plugin_Handled;

	if(!g_bAllowName)
	{
		ReplyToCommand(client, " \x04[CustomChat]\x01 This feature is currently disabled.");
		return Plugin_Handled;
	}

	ColorSelection(client, TYPE_NAMECOLOR);
	return Plugin_Handled;
}

public Action Command_ChatColor(int client, int args)
{
	if(!IsClientAdmin(client) && !IsClientVIP(client))
		return Plugin_Handled;

	if(!g_bAllowChat)
		return Plugin_Handled;

	ColorSelection(client, TYPE_CHATCOLOR);
	return Plugin_Handled;
}

public void ColorSelection(int client, int type)
{
	g_iClientSelectMode[client] = type;
	Menu menu = new Menu(ColorSelectionHandler, MENU_ACTIONS_ALL);

	char stype[64];
	int thetype = GetMenuType(stype, 64, type);

	if(thetype != -1)
	{
		menu.SetTitle("[CustomChat] %s Select Menu", stype);
		for(int i = 0; i < g_iTotalColor; i++)
		{
			menu.AddItem(g_ColorData[i].color_name, g_ColorData[i].color_name);
		}
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	else
	{
		CPrintToChat(client, " \x04[CustomChat]\x01 Invaild custom chat has been chosen!");
		return;
	}
}

public int ColorSelectionHandler(Menu menu, MenuAction action, int client, int param)
{
	switch(action)
	{
		case MenuAction_Select:
		{
			char info[64];
			menu.GetItem(param, info, sizeof(info));

			for(int i = 0; i < g_iTotalColor; i++)
			{
				if(StrEqual(info, g_ColorData[i].color_name, false))
				{
					if(g_iClientSelectMode[client] == TYPE_CHATCOLOR)
					{
						g_iClientData[client].ChatColor_id = i;
						SetClientColorsData(client);
						CPrintToChat(client, " \x04[CustomChat]\x01 You have changed your chat color to %s%s\x01.", g_ColorData[i].color_code, g_ColorData[i].color_name);
					}
					else if(g_iClientSelectMode[client] == TYPE_NAMECOLOR)
					{
						g_iClientData[client].NameColor_id = i;
						SetClientColorsData(client);
						CPrintToChat(client, " \x04[CustomChat]\x01 You have changed your name color to %s%s\x01.", g_ColorData[i].color_code, g_ColorData[i].color_name);
					}
					else
					{
						for(int x = 0; x < g_iTotalColor; x++)
						{
							ReplaceString(g_iClientData[client].CustomTag, 64, g_ColorData[x].color_tag, "");
						}

						Format(g_iClientData[client].CustomTag, 64, "%s%s", g_ColorData[i].color_tag, g_iClientData[client].CustomTag);
						SetClientColorsData(client);

						char sOutput[64];
						strcopy(sOutput, sizeof(sOutput), g_iClientData[client].CustomTag);
						ProceedColor(sOutput, sizeof(sOutput));
						
						CPrintToChat(client, " \x04[CustomChat]\x01 You have changed your tag to %s", sOutput);
					}
				}
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

stock int GetMenuType(char[] typename, int maxlen, int type)
{
	if(type == TYPE_TAGCOLOR)
	{
		return strcopy(typename, maxlen, "Tag Color");
	}
	else if(type == TYPE_NAMECOLOR)
	{
		return strcopy(typename, maxlen, "Name Color");
	}
	else if(type == TYPE_CHATCOLOR)
	{
		return strcopy(typename, maxlen, "Chat Color");
	}
	return -1;
}

void ProceedColor(char[] buffer, int maxlen)
{
	for(int i = 0; i < g_iTotalColor; i++)
	{
		ReplaceString(buffer, maxlen, g_ColorData[i].color_tag, g_ColorData[i].color_code);
	}
}

public Action CP_OnChatMessage(int& author, ArrayList recipients, char[] flagstring, char[] name, char[] message, bool & processcolors, bool & removecolors)
{
	int chatcolor = g_iClientData[author].ChatColor_id;
	int namecolor = g_iClientData[author].NameColor_id;

	char clienttag[64];
	strcopy(clienttag, 64, g_iClientData[author].CustomTag);

	bool changed = false;

	if(chatcolor != -1)
	{
		processcolors = true;
		Format(message, 256, "%s%s", g_ColorData[chatcolor].color_code, message);
		changed = true;
	}

	if(namecolor != -1)
	{
		processcolors = true;
		Format(name, 256, "%s%s", g_ColorData[namecolor].color_code, name);
		changed = true;
	}

	if(strlen(clienttag) > 0)
	{
		processcolors = true;
		ProceedColor(clienttag, sizeof(clienttag));
		changed = true;
	}

	Format(name, 256, "%s%s", clienttag, name);

	if(changed)
		return Plugin_Changed;

	return Plugin_Continue;
}

void SetClientColorsData(int client)
{
	if(g_iDataMode == 1)
	{
		char sPath[PLATFORM_MAX_PATH];

		BuildPath(Path_SM, sPath, sizeof(sPath), "data/customchat/customchat.txt");

		KeyValues kv = CreateKeyValues("client_colors");
		FileToKeyValues(kv, sPath);

		char sAuth[128];
		GetClientAuthId(client, AuthId_Steam2, sAuth, sizeof(sAuth), false);

		if(KvJumpToKey(kv, sAuth, true))
		{
			KvSetNum(kv, "chatcolor", g_iClientData[client].ChatColor_id);
			KvSetNum(kv, "namecolor", g_iClientData[client].NameColor_id);
			KvSetString(kv, "customtag", g_iClientData[client].CustomTag);
		}

		delete kv;
	}
}

void LoadColorConfig()
{
	char sPath[PLATFORM_MAX_PATH];

	BuildPath(Path_SM, sPath, sizeof(sPath), "configs/customchat/colors.cfg");

	KeyValues kv = CreateKeyValues("colors");
	FileToKeyValues(kv, sPath);

	if(KvGotoFirstSubKey(kv))
	{
		g_iTotalColor = 0;

		do
		{
			KvGetSectionName(kv, g_ColorData[g_iTotalColor].color_name, 16);
			KvGetString(kv, "colorcode", g_ColorData[g_iTotalColor].color_code, 16);
			KvGetString(kv, "colortag", g_ColorData[g_iTotalColor].color_tag, 64);

			g_iTotalColor++;
		}
		while(KvGotoNextKey(kv));
	}
	delete kv;
}

bool IsClientVIP(int client)
{
	return CheckCommandAccess(client, "sm_vip", ADMFLAG_CUSTOM1);
}

bool IsClientAdmin(int client)
{
	return CheckCommandAccess(client, "sm_admin", ADMFLAG_GENERIC);
}





