#pragma semicolon 1

#define L4D2UTIL_STOCKS_ONLY

#include <sourcemod>
#include <sdktools>
#include <builtinvotes>
#include <l4d2util>
#include <colors>  

#define STRING_SIZE 	32

new String:sLogPath[PLATFORM_MAX_PATH];
new String:sPluginRes[][] = 
{
    "Turn ON Addons Disabler?",     // 0 - Vote Box Header(on)
    "Switch OFF Addons Disabler?",  // 1 - Vote Box Header(off)
    "Addons Disabler is now ON",    // 2 - Vote Result(on)
    "Addons Disabler is now OFF",   // 3 - Vote Result(off)
    "http://step.l4dnation.com",    // 4 - Addons Disabler VPK url
    "logs/addons_checker.log"       // 5 - log file
};

new Handle:hCvarLog;
new Handle:hClientAecValues;
new Handle:hVote = INVALID_HANDLE;

new bool:bBlockVote = false;
new bool:bDisablerActive = false;

enum ClientsAecStruct {
    String:Client_SteamId[STRING_SIZE],
    Client_Aec_Value
};

public Plugin:myinfo =
{
    name        = "L4D2 Addons Eclipse Vote",
    description = "A better version of Addons Checker.",
    author      = "Visor, step",
    version     = "2.0b",
    url         = "https://github.com/Attano"
};

public OnPluginStart()
{
    hCvarLog = CreateConVar("sm_addons_checker_log", "1", "Log cases of unusual convar query replies", FCVAR_PLUGIN, true, 0.0, true, 1.0);
    CreateConVar("sm_addons_checker_version", "2.0a", "Addons Checker version", FCVAR_PLUGIN);

    HookEvent("player_team", OnTeamChange);

    RegConsoleCmd("sm_vpk", PlayersWithAec);
    RegConsoleCmd("sm_addon", AddonsDisablerVote);
    RegConsoleCmd("sm_addondisabler", AddonsDisablerVote);
    RegConsoleCmd("sm_noaddons", AddonsDisablerVote);

    hClientAecValues = CreateArray(_:ClientsAecStruct);

    //Build our log path
    BuildPath(Path_SM, sLogPath, sizeof(sLogPath), sPluginRes[5]);
}

public OnMapStart()
{
    bBlockVote = true;
    CreateTimer(60.0, EnableVote);
}

public Action:EnableVote(Handle:timer)
{
    bBlockVote = false;
}

public OnTeamChange(Handle:event, String:name[], bool:dontBroadcast)
{
    if (L4D2_Team:GetEventInt(event, "team") != L4D2Team_Spectator)
    {
        new client = GetClientOfUserId(GetEventInt(event, "userid"));
        if (client > 0) CreateTimer(0.1, QueryPlayer, client);
    }
}

public Action:QueryPlayer(Handle:timer, any:client)
{
    if (IsClientInGame(client) && !IsFakeClient(client))
    {
        QueryClientConVar(client, "addons_eclipse_content", ClientQueryCallback);
    }
}

public ClientQueryCallback(QueryCookie:cookie, client, ConVarQueryResult:result, const String:cvarName[], const String:cvarValue[])
{
    switch (result)
    {
        case 0:
        {
            if (bDisablerActive && !IsSpectator(client) && StrEqual(cvarValue, "0"))
            {
                ChangeClientTeam(client, _:L4D2Team_Spectator);
                PrintToChat(client, "\x05[Addons Disabler]\x01 You need \x04Addons Disabler\x01 to be allowed into competitive mode. Get it from \x03%s", sPluginRes[4]);
            }
            
            decl player[ClientsAecStruct];
            GetClientAuthString(client, player[Client_SteamId], STRING_SIZE);
            player[Client_Aec_Value] = _:StringToInt(cvarValue);
            
            new iIndex = FindStringInArray(hClientAecValues, player[Client_SteamId]);
            if (iIndex > -1)
                SetArrayArray(hClientAecValues, iIndex, player[0]);
            else
                PushArrayArray(hClientAecValues, player[0]);
        }
        case 1:
        {
            KickPlayer(client, "ConVarQuery_NotFound");
        }
        case 2:
        {
            KickPlayer(client, "ConVarQuery_NotValid");
        }
        case 3:
        {
            KickPlayer(client, "ConVarQuery_Protected");
        }
    }
}

public KickPlayer(client, String:reason[])
{
    KickClient(client, "Kicked for not responding to Addons Checker query correctly");
    CPrintToChatAll("{red}[Addons Disabler]{default} Kicked {green}%N{default} for using hacks!", client);

    if (GetConVarBool(hCvarLog))
        LogToFileEx(sLogPath, "Kicked %L for responding to the query with %s", client, reason);
}

public Action:PlayersWithAec(client, args) 
{
    decl player[ClientsAecStruct];
    new iClient;

    ReplyToCommand(client, "\x05[Addons Disabler]\x01 Players:");

    for (new i = 0; i < GetArraySize(hClientAecValues); i++) 
    {
        GetArrayArray(hClientAecValues, i, player[0]);
        
        iClient = GetClientBySteamId(player[Client_SteamId]);
        if (iClient < 0) continue;
        
        if (IsClientConnected(iClient)) 
        {
            ReplyToCommand(client, "\x03%N\x01 - %s", iClient, (player[Client_Aec_Value] == 1 ? "\x05On\x01" : "\x04Off\x01"));
        }
    }

    return Plugin_Handled;
}

public Action:AddonsDisablerVote(client, args) 
{
    if (bBlockVote || IsSpectator(client))
        return Plugin_Handled;

    if(StartVote(client, (bDisablerActive ? sPluginRes[1] : sPluginRes[0])))
        FakeClientCommand(client, "Vote Yes");

    return Plugin_Handled; 
}

bool:StartVote(client, const String:sVoteHeader[])
{
    if (IsNewBuiltinVoteAllowed())
    {
        new iNumPlayers;
        decl players[MaxClients];
        for (new i = 1; i <= MaxClients; i++)
        {
            if (!IsClientConnected(i) || !IsClientInGame(i)) continue;
            if (IsSpectator(i) || IsFakeClient(i)) continue;
            
            players[iNumPlayers++] = i;
        }
        
        hVote = CreateBuiltinVote(VoteActionHandler, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
        SetBuiltinVoteArgument(hVote, sVoteHeader);
        SetBuiltinVoteInitiator(hVote, client);
        SetBuiltinVoteResultCallback(hVote, VoteResultHandler);
        DisplayBuiltinVote(hVote, players, iNumPlayers, 20);
        return true;
    }

    PrintToChat(client, "\x05[Addons Disabler]\x01 Vote cannot be started now.");
    return false;
}

public VoteActionHandler(Handle:vote, BuiltinVoteAction:action, param1, param2)
{
    switch (action)
    {
        case BuiltinVoteAction_End:
        {
            hVote = INVALID_HANDLE;
            CloseHandle(vote);
        }
        case BuiltinVoteAction_Cancel:
        {
            DisplayBuiltinVoteFail(vote, BuiltinVoteFailReason:param1);
        }
    }
}

public VoteResultHandler(Handle:vote, num_votes, num_clients, const client_info[][2], num_items, const item_info[][2])
{
    for (new i = 0; i < num_items; i++)
    {
        if (item_info[i][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES)
        {
            if (item_info[i][BUILTINVOTEINFO_ITEM_VOTES] > (num_clients / 2))
            {
                bDisablerActive = !bDisablerActive;
                DisplayBuiltinVotePass(vote, (bDisablerActive ? sPluginRes[2] : sPluginRes[3]));
                PrintToChatAll("\x05[Addons Disabler]\x01 Plugin is now \x03%s", (bDisablerActive ? "activated" : "deactivated"));
                for (new j = 1; j <= MaxClients; j++)
                {
                    CreateTimer(0.1, QueryPlayer, j);
                }
                return;
            }
        }
    }
    DisplayBuiltinVoteFail(vote, BuiltinVoteFail_Loses);
}

stock GetClientBySteamId(const String:steamID[]) 
{
    decl String:tempSteamID[STRING_SIZE];

    for (new client = 1; client <= MaxClients; client++) 
    {
        if (!IsClientInGame(client)) continue;
        
        GetClientAuthString(client, tempSteamID, STRING_SIZE);
        if (StrEqual(steamID, tempSteamID))
            return client;
    }

    return -1;
}

bool:IsSpectator(client) 
    return L4D2_Team:GetClientTeam(client) == L4D2Team_Spectator;
