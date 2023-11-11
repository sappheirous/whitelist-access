#include <amxmodx>
#include <amxmisc>
#include <sqlx>

public stock const PluginName[] = "Whitelist Access"        
public stock const PluginVersion[] = "1.3"
public stock const PluginAuthor[] = "sappheirous"

#define ACCESS_LEVEL ADMIN_RCON

new const MSG_TAG[] = "[Whitelist]"
new const MSG_NO_ACCESS[] = "You do not have access to this server."
new const MSG_NO_SUBNET_MATCH[] = "Access denied. Your subnet does not match."

const MAX_DATE_LENGTH = 22

enum _:TABLE_ROWS 
{
    row_id,
    row_steamid,
    row_subnetip,
    row_username,
    row_has_access,
    row_last_updated_access
}

new Handle:g_database_tuple
new g_database_tablename[64]

enum _:CVARS_LIST
{
    whitelist_logs,
    whitelist_sql_host,
    whitelist_sql_user,
    whitelist_sql_pass,
    whitelist_sql_db,
    whitelist_sql_table,
    whitelist_sql_std_tuple,
    whitelist_contact,
    whitelist_ignore_admins,
    whitelist_subnet_matching
}

new g_cvars[CVARS_LIST]

// used to call the main menu when closing the menu with information about the player
new bool:g_find_client_called_from_menu[MAX_PLAYERS + 1]

public plugin_init() 
{
    register_plugin(PluginName, PluginVersion, PluginAuthor)
  
    register_concmd("whitelist_add", "concmd_whitelist_add", ACCESS_LEVEL, "<steamid>")
    register_concmd("whitelist_remove", "concmd_whitelist_remove", ACCESS_LEVEL, "<steamid>")
    register_concmd("whitelist_find", "concmd_whitelist_find", ACCESS_LEVEL, "<steamid>")
    register_concmd("whitelist_subnet_reset", "concmd_whitelist_subnet_reset", ACCESS_LEVEL, "<steamid>")

    register_clcmd("whitelist_menu", "clcmd_whitelist_menu", ACCESS_LEVEL)
    register_clcmd("say /whitelist", "clcmd_whitelist_menu", ACCESS_LEVEL)

    register_cvars()
}

public plugin_end()
{
    SQL_FreeHandle(g_database_tuple)
}

register_cvars()
{
    bind_pcvar_num(
        create_cvar(
            .name = "whitelist_logs",
            .string = "1",
            .flags = FCVAR_NONE,
            .description = "Writes log files",
            .has_min = true,
            .min_val = 0.0,
            .has_max = true,
            .max_val = 1.0
        ), g_cvars[whitelist_logs]
    )

    g_cvars[whitelist_sql_host] = create_cvar(
        .name = "whitelist_sql_host",
        .string = "",
        .flags = FCVAR_PROTECTED,
        .description = "SQL database host name"
    )

    g_cvars[whitelist_sql_user] = create_cvar(
        .name = "whitelist_sql_user",
        .string = "",
        .flags = FCVAR_PROTECTED,
        .description = "User name for connecting to the SQL database"
    )

    g_cvars[whitelist_sql_pass] = create_cvar(
        .name = "whitelist_sql_pass",
        .string = "",
        .flags = FCVAR_PROTECTED,
        .description = "User password for connecting to the SQL database"
    )

    g_cvars[whitelist_sql_db] = create_cvar(
        .name = "whitelist_sql_db",
        .string = "",
        .flags = FCVAR_PROTECTED,
        .description = "Name of the SQL database for access management"
    )

    g_cvars[whitelist_sql_table] = create_cvar(
        .name = "whitelist_sql_table",
        .string = "whitelist_access",
        .flags = FCVAR_PROTECTED,
        .description = "Name of the table in the SQL database for storing access information"
    )

    bind_pcvar_num(
        create_cvar(
            .name = "whitelist_sql_std_tuple",
            .string = "0",
            .flags = FCVAR_PROTECTED,
            .description = "Use this for making a standard DB Tuple, using AMXXs database info cvars",
            .has_min = true,
            .min_val = 0.0,
            .has_max = true,
            .max_val = 1.0
        ), g_cvars[whitelist_sql_std_tuple]
    )

    g_cvars[whitelist_contact] = create_cvar(
        .name = "whitelist_contact",
        .string = "Contact: ",
        .flags = FCVAR_NONE,
        .description = "Contact information for feedback or reference"
    )

    g_cvars[whitelist_ignore_admins] = create_cvar(
        .name = "whitelist_ignore_admins",
        .string = "cd",
        .flags = FCVAR_NONE,
        .description = "Ignore admins with the specified flags"
    )

    bind_pcvar_num(
        create_cvar(
            .name = "whitelist_subnet_matching",
            .string = "1",
            .flags = FCVAR_PROTECTED,
            .description = "Checking for client subnet change (kicking from the server in case of spoofing)",
            .has_min = true,
            .min_val = 0.0,
            .has_max = true,
            .max_val = 1.0
        ), g_cvars[whitelist_subnet_matching]
    )

    AutoExecConfig()
}

public concmd_whitelist_add(id, level, cid)
{
    if (!cmd_access(id, level, cid, 2))
        return PLUGIN_HANDLED
    
    new steamid[MAX_AUTHID_LENGTH]
    read_argv(1, steamid, charsmax(steamid))
    request_update_access(id, steamid, true)
    return PLUGIN_HANDLED
}

public concmd_whitelist_remove(id, level, cid)
{
    if (!cmd_access(id, level, cid, 2))
        return PLUGIN_HANDLED

    new steamid[MAX_AUTHID_LENGTH]
    read_argv(1, steamid, charsmax(steamid))
    request_update_access(id, steamid, false)
    return PLUGIN_HANDLED
}

public concmd_whitelist_find(id, level, cid)
{
    if (!cmd_access(id, level, cid, 2))
        return PLUGIN_HANDLED
    
    new steamid[MAX_AUTHID_LENGTH]
    read_argv(1, steamid, charsmax(steamid))
    request_find(id, steamid)
    return PLUGIN_HANDLED
}

public concmd_whitelist_subnet_reset(id, level, cid)
{
    if (!cmd_access(id, level, cid, 2))
        return PLUGIN_HANDLED
    
    new steamid[MAX_AUTHID_LENGTH]
    read_argv(1, steamid, charsmax(steamid))
    request_reset_subnet(id, steamid)
    return PLUGIN_HANDLED
}

public clcmd_whitelist_menu(id, level, cid)
{
    if (!cmd_access(id, level, cid, 0))
        return PLUGIN_HANDLED
    
    whitelist_menu(id)
    return PLUGIN_HANDLED
}

whitelist_menu(id)
{
    new menu = menu_create(fmt("\y%s^n\dVersion: %s^nAuthor: %s", PluginName, PluginVersion, PluginAuthor), "whitelist_menu_handler")
    
    menu_additem(menu, "Recent inserted players")
    menu_additem(menu, "Players with access")
    menu_addtext2(menu, "\d(SQL query may take some time)^n")
    menu_additem(menu, "Current players")
    menu_addtext2(menu, "\d(List of current players on the server)^n")
    menu_additem(menu, "Plugin information")
    menu_addblank2(menu)

    menu_display(id, menu)
}

public whitelist_menu_handler(id, menu, item)
{
    switch (item)
    {
        case 0: { request_recent_inserted_players(id); }
        case 1: { request_players_with_access(id); }
        case 3: { players_list_menu(id); }
        case 5: { request_whitelist_info(id); }
    }

    menu_destroy(menu)
    return PLUGIN_HANDLED
}

received_players_list_menu(id, Handle:query, const title[])
{
    new menu = menu_create(fmt("\y%s^n\d%s", PluginName, title), "players_list_menu_handler")
    new num_rows = SQL_AffectedRows(query)

    for (new i; i < num_rows; i++)
    {
        new steamid[MAX_AUTHID_LENGTH]
        new username[MAX_NAME_LENGTH]    

        SQL_ReadResult(query, row_steamid, steamid, charsmax(steamid))
        SQL_ReadResult(query, row_username, username, charsmax(username))

        strlen(username)
            ? menu_additem(menu, fmt("%s \d(username: %s)", steamid, username), steamid)
            : menu_additem(menu, steamid, steamid)

        SQL_NextRow(query)
    }

    menu_display(id, menu)
}

players_list_menu(id)
{
    new menu = menu_create(fmt("\y%s^n\dCurrent players", PluginName), "players_list_menu_handler")

    new players[MAX_PLAYERS], pnum
    get_players_ex(players, pnum, GetPlayers_ExcludeBots | GetPlayers_ExcludeHLTV)

    for (new i; i < pnum; i++)
    {
        new temp_id = players[i]
        menu_additem(menu, 
            fmt("%s \d(username: %s)", get_user_steamid(temp_id), get_user_username(temp_id)), 
            get_user_steamid(temp_id))
    }

    menu_display(id, menu)
}

public players_list_menu_handler(id, menu, item)
{
    if (item == MENU_EXIT)
    {
        if (is_user_connected(id))
            whitelist_menu(id)
    }
    else
    {
        new steamid[MAX_AUTHID_LENGTH]
        menu_item_getinfo(menu, item, .info = steamid, .infolen = charsmax(steamid))  
        request_find(id, steamid, true)   
    }

    menu_destroy(menu)
    return PLUGIN_HANDLED
}

player_info_menu(id, Handle:query)
{
    new steamid[MAX_AUTHID_LENGTH], username[MAX_NAME_LENGTH]
    new subnetip[MAX_IP_LENGTH], last_updated_access[22]

    SQL_ReadResult(query, row_steamid, steamid, charsmax(steamid))
    SQL_ReadResult(query, row_username, username, charsmax(username))
    SQL_ReadResult(query, row_subnetip, subnetip, charsmax(subnetip))
    SQL_ReadResult(query, row_last_updated_access, last_updated_access, charsmax(last_updated_access))

    new has_access = SQL_ReadResult(query, row_has_access)

    new menu = menu_create(fmt("\y%s^n\dPlayer Information^n^n%s%s%s%s%s", PluginName,
        fmt("Account: %s^n", steamid),
        fmt("Username: %s^n", strlen(username) ? username : "NULL"),
        fmt("Subnet IP: %s^n", strlen(subnetip) ? subnetip : "NULL"),
        fmt("Access: %s^n", has_access ? "Yes" : "No"),
        fmt("Last updated access: %s", last_updated_access)), 
        "player_info_menu_handler")

    menu_additem(menu, has_access ? "Remove access" : "Give access", steamid)
    menu_additem(menu, "Reset subnet", steamid)
    menu_addblank2(menu)
    menu_addtext2(menu, "\dRequest may take some time.")
    menu_addtext2(menu, "\dYou can see the result of the query in the console.") 

    menu_display(id, menu)
}

public player_info_menu_handler(id, menu, item)
{
    if (item == MENU_EXIT) 
    {
        if (is_user_connected(id)) 
        {
            if (g_find_client_called_from_menu[id]) {
                g_find_client_called_from_menu[id] = false
                whitelist_menu(id)
            }
        }
    }
    else
    {
        new steamid[MAX_AUTHID_LENGTH], itemname[32]
        menu_item_getinfo(menu, item, 
            .info = steamid, .infolen = charsmax(steamid), 
            .name = itemname, .namelen = charsmax(itemname))
        
        switch (item)
        {
            case 0: { request_update_access(id, steamid, bool:equal(itemname, "Give access")); }
            case 1: { request_reset_subnet(id, steamid); }
        }
    }

    menu_destroy(menu)
    return PLUGIN_HANDLED
}

information_menu(id, Handle:query)
{
    new menu = menu_create(fmt("\y%s^n\dPlugin information", PluginName), "information_menu_handler")

    new total_players = SQL_ReadResult(query, 0)
    new players_with_access = SQL_ReadResult(query, 1)

    menu_addtext2(menu, fmt("\dPlugin version: %s", PluginVersion))
    menu_addtext2(menu, fmt("\dPlugin author: %s", PluginAuthor))
    menu_addblank2(menu)
    menu_addtext2(menu, fmt("\dTable name: %s", g_database_tablename))
    menu_addtext2(menu, fmt("\dTotal players: %i", total_players))
    menu_addtext2(menu, fmt("\dPlayers with access: %i", players_with_access))
    menu_addtext2(menu, fmt("\dPlayers without access: %i", total_players - players_with_access))

    menu_display(id, menu)
}

public information_menu_handler(id, menu, item)
{
    if (is_user_connected(id))
        whitelist_menu(id)

    menu_destroy(menu)
    return PLUGIN_HANDLED
}

public OnConfigsExecuted()
{
    register_sql()

    new players[MAX_PLAYERS], pnum
    get_players_ex(players, pnum, GetPlayers_ExcludeBots | GetPlayers_ExcludeHLTV)

    for (new i; i < pnum; i++) 
        request_authorize(players[i])
}

register_sql()
{
    g_database_tuple = make_sql_tuple()
    
    get_pcvar_string(g_cvars[whitelist_sql_table], g_database_tablename, charsmax(g_database_tablename))

    new query[512]

    formatex(query, charsmax(query), "\
        CREATE TABLE IF NOT EXISTS `%s` \
        ( \
            `id`                    INT NOT NULL auto_increment PRIMARY KEY, \
            `steamid`               VARCHAR(%i) NULL DEFAULT NULL UNIQUE, \
            `subnetip`              VARCHAR(%i) NULL DEFAULT NULL, \
            `username`              VARCHAR(%i) NULL DEFAULT NULL, \
            `has_access`            TINYINT DEFAULT 0, \
            `last_updated_access`   VARCHAR(%i) NULL DEFAULT NULL \
        );", g_database_tablename, MAX_AUTHID_LENGTH, MAX_IP_LENGTH, MAX_NAME_LENGTH, MAX_DATE_LENGTH)

    SQL_SetCharset(g_database_tuple, "utf-8")
    SQL_ThreadQuery(g_database_tuple, "query_handler", query)
}

Handle:make_sql_tuple()
{
    if (g_cvars[whitelist_sql_std_tuple])
        return SQL_MakeStdTuple()

    new host[64], user[64], pass[64], db[64]

    get_pcvar_string(g_cvars[whitelist_sql_host], host, charsmax(host))
    get_pcvar_string(g_cvars[whitelist_sql_user], user, charsmax(user))
    get_pcvar_string(g_cvars[whitelist_sql_pass], pass, charsmax(pass))
    get_pcvar_string(g_cvars[whitelist_sql_db], db, charsmax(db))

    return SQL_MakeDbTuple(host, user, pass, db)
}

public client_putinserver(id)
{
    if (should_request_authorize(id))
        request_authorize(id)
}

public client_infochanged(id)
{
    if (is_user_connected(id) && !equal(get_userinfo_name(id), get_user_username(id)))
        request_update_username(id, true)
}

bool:should_request_authorize(id)
{
    return g_database_tuple && !is_user_hltv(id) && !is_user_bot(id)
}

request_authorize(id)
{
    new query[256], data[1]
    
    data[0] = id

    formatex(query, charsmax(query), "\
        SELECT `subnetip`, `has_access` \
        FROM `%s` \
        WHERE `steamid` = '%s'",
        g_database_tablename, get_user_steamid(id))

    SQL_ThreadQuery(g_database_tuple, "request_authorize_handler", query, data, sizeof(data))
}

public request_authorize_handler(failstate, Handle:query, error[], errnum, data[])
{
    if (is_sql_error(failstate, error, errnum))
        return

    new id = data[0]

    if (!is_user_connected(id))
        return

    new contact[64]
    get_pcvar_string(g_cvars[whitelist_contact], contact, charsmax(contact))

    new num_results = SQL_NumResults(query)
    if (num_results == 0)
        request_insert(id)
    else
    {
        request_update_username(id)

        new subnetip[MAX_IP_LENGTH]
        SQL_ReadResult(query, 0, subnetip, charsmax(subnetip))

        if (strlen(subnetip) == 0)
            request_update_subnetip(id)
        else
        {
            if (g_cvars[whitelist_subnet_matching] && !equal(subnetip, get_user_subnetip(id)))
            {
                if (g_cvars[whitelist_logs]) 
                {
                    log_to_file(get_log_filename(), "Client %n (%s) access denied. Subnet does not match (%s / %s)", 
                        id, get_user_steamid(id), subnetip, get_user_ipaddress(id))
                }

                user_kick(id, fmt("%s^n%s", MSG_NO_SUBNET_MATCH, contact))
                return
            }
        }

        new has_access = SQL_ReadResult(query, 1)
        if (has_access)
            return
    }

    new ignore_admins[32]
    get_pcvar_string(g_cvars[whitelist_ignore_admins], ignore_admins, charsmax(ignore_admins))

    if (strlen(ignore_admins) && has_flag(id, ignore_admins)) 
        return

    if (g_cvars[whitelist_logs])
        log_to_file(get_log_filename(), "Client %n (%s) access denied. Does not have access", id, get_user_steamid(id))

    user_kick(id, fmt("%s^n%s", MSG_NO_ACCESS, contact))
}

request_insert(id)
{
    new query[256]

    formatex(query, charsmax(query), "\
        INSERT INTO `%s` (`steamid`, `subnetip`, `username`, `last_updated_access`) \
        VALUES ('%s', '%s', '%s', '%s');", 
        g_database_tablename, get_user_steamid(id), get_user_subnetip(id), get_user_username(id), get_formatted_time())

    SQL_ThreadQuery(g_database_tuple, "query_handler", query)
}

request_update_username(id, bool:userinfo = false)
{
    new query[256]

    formatex(query, charsmax(query), "\
        UPDATE `%s` \
        SET `username` = '%s' \
        WHERE `steamid` = '%s'", 
        g_database_tablename, userinfo ? get_userinfo_name(id) : get_user_username(id), get_user_steamid(id))

    SQL_ThreadQuery(g_database_tuple, "query_handler", query)
}

request_update_subnetip(id)
{
    new query[256]

    formatex(query, charsmax(query), "\
        UPDATE `%s` \
        SET `subnetip` = '%s' \
        WHERE `steamid` = '%s'", 
        g_database_tablename, get_user_subnetip(id), get_user_steamid(id))

    SQL_ThreadQuery(g_database_tuple, "query_handler", query)
}

request_update_access(id, const steamid[], bool:has_access)
{
    enum _:params 
    { 
        param_id, 
        param_has_access, 
        param_steamid[MAX_AUTHID_LENGTH] 
    }

    new query[256], data[params]

    data[param_id] = id
    data[param_has_access] = has_access
    copy(data[param_steamid], charsmax(data[param_steamid]), steamid)

    formatex(query, charsmax(query), "\
        INSERT INTO `%s` (`steamid`, `has_access`, `last_updated_access`) \
        VALUES ('%s', %i, '%s') \
        ON DUPLICATE KEY UPDATE `has_access` = %i, `last_updated_access` = '%s';", 
        g_database_tablename, steamid, has_access, get_formatted_time(), has_access, get_formatted_time())

    SQL_ThreadQuery(g_database_tuple, "request_update_access_handler", query, data, sizeof(data))
}

public request_update_access_handler(failstate, Handle:query, error[], errnum, data[])
{
    enum { id, has_access, steamid[MAX_AUTHID_LENGTH] }

    if (is_sql_error(failstate, error, errnum))
        return

    if (data[id] && !is_user_connected(data[id]))
        return

    new msg_access[8] 
    formatex(msg_access, charsmax(msg_access), data[has_access] ? "added" : "removed")
    console_print(data[id], "%s Client %s has been successfully %s", MSG_TAG, data[steamid], msg_access)
    
    if (g_cvars[whitelist_logs])
    {
        data[id]
            ? log_to_file(get_log_filename(), "Client %s has been %s by %N<%s>", data[steamid], msg_access, data[id], get_user_ipaddress(data[id]))
            : log_to_file(get_log_filename(), "Client %s has been %s by server", data[steamid], msg_access)
    }
}

request_find(id, const steamid[], bool:called_from_menu = false)
{
    enum _:params
    {
        param_id,
        param_steamid[MAX_AUTHID_LENGTH]
    }

    new query[256], data[params]

    data[param_id] = id
    copy(data[param_steamid], charsmax(data[param_steamid]), steamid)

    g_find_client_called_from_menu[id] = called_from_menu

    formatex(query, charsmax(query), "\
        SELECT * \
        FROM `%s` \
        WHERE `steamid` = '%s'",
        g_database_tablename, steamid)
    
    SQL_ThreadQuery(g_database_tuple, "request_find_handler", query, data, sizeof(data))
}

public request_find_handler(failstate, Handle:query, error[], errnum, data[])
{
    enum { id, steamid[MAX_AUTHID_LENGTH] }

    if (is_sql_error(failstate, error, errnum))
        return

    if (data[id] && !is_user_connected(data[id]))
        return

    new num_results = SQL_NumResults(query)
    if (num_results == 0) {
        console_print(data[id], "%s Client %s has not been found", MSG_TAG, data[steamid])
        return
    }
    
    console_print(data[id], "%s Client %s has been found", MSG_TAG, data[steamid])

    if (data[id])
        player_info_menu(data[id], query)
}

request_reset_subnet(id, const steamid[])
{
    enum _:params
    {
        param_id,
        param_steamid[MAX_AUTHID_LENGTH]
    }

    new query[256], data[params]

    data[param_id] = id
    copy(data[param_steamid], charsmax(data[param_steamid]), steamid)

    formatex(query, charsmax(query), "\
        UPDATE `%s` \
        SET `subnetip` = NULL \
        WHERE `steamid` = '%s'",
        g_database_tablename, steamid)

    SQL_ThreadQuery(g_database_tuple, "request_reset_subnet_handler", query, data, sizeof(data))
}

public request_reset_subnet_handler(failstate, Handle:query, error[], errnum, data[])
{
    enum { id, steamid[MAX_AUTHID_LENGTH] }

    if (is_sql_error(failstate, error, errnum))
        return

    if (data[id] && !is_user_connected(data[id]))
        return

    console_print(data[id], "%s Client %s has successfully received a subnet reset", MSG_TAG, data[steamid])

    if (g_cvars[whitelist_logs])
    {
        data[id]
            ? log_to_file(get_log_filename(), "Client %s received a subnet reset by %N<%s>", data[steamid], data[id], get_user_ipaddress(data[id]))
            : log_to_file(get_log_filename(), "Client %s received a subnet reset by server", data[steamid])
    }
}

request_recent_inserted_players(id)
{
    new query[256], data[1]

    data[0] = id

    formatex(query, charsmax(query), "\
        SELECT * \
        FROM `%s` \
        ORDER BY `id` DESC \
        LIMIT 70;",
        g_database_tablename)

    SQL_ThreadQuery(g_database_tuple, "request_recent_inserted_players_handler", query, data, sizeof(data))
}

public request_recent_inserted_players_handler(failstate, Handle:query, error[], errnum, data[])
{
    if (is_sql_error(failstate, error, errnum))
        return

    new id = data[0]

    if (is_user_connected(id))
        received_players_list_menu(id, query, "Recent inserted players")
}

request_players_with_access(id)
{
    new query[256], data[1]

    data[0] = id

    formatex(query, charsmax(query), "\
        SELECT * \
        FROM `%s` \
        WHERE `has_access` = 1;",
        g_database_tablename)

    SQL_ThreadQuery(g_database_tuple, "request_players_with_access_handler", query, data, sizeof(data))
}

public request_players_with_access_handler(failstate, Handle:query, error[], errnum, data[])
{
    if (is_sql_error(failstate, error, errnum))
        return

    new id = data[0]

    if (is_user_connected(id))
        received_players_list_menu(id, query, "Players with access")
}

request_whitelist_info(id)
{
    new query[256], data[1]

    data[0] = id

    formatex(query, charsmax(query), "\
        SELECT COUNT(*) AS total_players, \
        COUNT(`has_access` = 1 OR NULL) AS players_with_access \
        FROM `%s`;", g_database_tablename)

    SQL_ThreadQuery(g_database_tuple, "request_whitelist_info_handler", query, data, sizeof(data))
}

public request_whitelist_info_handler(failstate, Handle:query, error[], errnum, data[])
{
    if (is_sql_error(failstate, error, errnum))
        return

    new id = data[0]

    if (is_user_connected(id))
        information_menu(id, query)
}

public query_handler(failstate, Handle:query, error[], errnum)
{
    if (is_sql_error(failstate, error, errnum))
        return
}

stock get_user_username(id)
{
    new username[MAX_NAME_LENGTH]
    get_user_name(id, username, charsmax(username))
    return username
}

stock get_user_ipaddress(id)
{
    new ipaddress[MAX_IP_LENGTH]
    get_user_ip(id, ipaddress, charsmax(ipaddress), 1)
    return ipaddress
}

stock get_user_steamid(id)
{
    new steamid[MAX_AUTHID_LENGTH]
    get_user_authid(id, steamid, charsmax(steamid))
    return steamid
}

stock get_user_subnetip(id)
{
    new subnetip[MAX_IP_LENGTH]
    get_user_ip(id, subnetip, charsmax(subnetip), 1)
    replace_string(subnetip, charsmax(subnetip), ".", " ") 
    
    new parts[2][4]
    parse(subnetip, 
        parts[0], charsmax(parts[]), 
        parts[1], charsmax(parts[])) 

    formatex(subnetip, charsmax(subnetip), "%s.%s.*.*", parts[0], parts[1])
    return subnetip
}

stock get_userinfo_name(id)
{
    new username[MAX_NAME_LENGTH]
    get_user_info(id, "name", username, charsmax(username))
    return username
}

stock get_log_filename()
{   
    static path[PLATFORM_MAX_PATH]

    if (strlen(path) == 0) 
    {
        new plugin_filename[128]
        new plugin_id = is_plugin_loaded(PluginName)
        get_plugin(plugin_id, plugin_filename, charsmax(plugin_filename))

        new directory[PLATFORM_MAX_PATH]    
        formatex(directory, charsmax(directory), "addons/amxmodx/logs/%s", plugin_filename)
        replace(directory, charsmax(directory), ".amxx", "")

        new formatted_time[8]
        get_time("%Y.%m", formatted_time, charsmax(formatted_time))

        if (!dir_exists(directory))
            mkdir(directory)

        formatex(path, charsmax(path), "%s/%s.log", directory, formatted_time)
    }

    return path
}

stock get_formatted_time()
{
    new formatted_time[MAX_DATE_LENGTH]
    get_time("%d.%m.%Y - %H:%M:%S", formatted_time, charsmax(formatted_time))
    return formatted_time
}

stock user_kick(id, const reason[])
{
    message_begin(MSG_ONE, SVC_DISCONNECT, _, id)
    write_string(reason)
    message_end()
}

stock bool:is_sql_error(failstate, error[], errnum)
{
    if (failstate == TQUERY_SUCCESS)
        return false

    log_amx("SQL error #%i - %s", errnum, error)
    return true
}