# Whitelist Access
AMX Mod X plugin that restricts server access to only whitelisted players

## Features
- Authorizes players based on SteamID and subnet details.
- Allows addition, removal, and finding of whitelisted players.
- Provides an interactive menu for managing whitelist information.
- Ensures secure access control for server administrators.

## Usage
- `whitelist_add <steamid>` - Add a player to the whitelist.
- `whitelist_remove <steamid>` - Remove a player from the whitelist.
- `whitelist_find <steamid>` - Find a player in the whitelist.
- `whitelist_subnet_reset <steamid>` - Reset a player's subnet details.
- `whitelist_menu` (or say `/whitelist`) - Open the whitelist menu.
  
## Configuration
The plugin utilizes SQL for managing whitelist information. The configuration involves setting up SQL server details and adjusting various cvars to manage the plugin's behavior.

## Installation
1. Place the plugin in the appropriate AMX Mod X plugins directory.
2. Start the server to automatically create the plugin configuration file.
3. Configure sql cvars in the `plugin-whitelist-access.cfg` file located at `addons/amxmodx/configs/plugins/`.

## Notes
- Make sure to configure the plugin before use by setting up SQL details and adjusting cvars as needed.
- Ensure proper permissions for accessing the SQL database for the plugin to function correctly.
  
For detailed command usage and configurations, refer to the plugin's source code.