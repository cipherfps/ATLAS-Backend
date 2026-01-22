# ATLAS

Atlas is a Fortnite backend for all versions of fortnite designed for trickshotters!
This backend has features such as the following:
- Straight Bloom Toggle
- CurveTable Toggle
- CurveTable Editor
- CurveTable Importer
- Arena Playlist/Points (22.40 and under)

If you want to contribute just fork this repository and make a pull request!

> [!TIP]
> Join the discord server for support and resources like this! https://discord.gg/G9MAF77V7R
### Feel free to give any suggestions on how to improve ATLAS!
> [!WARNING]
> We do not accept any liability for the misuse of this program. Epic Games strictly prohibits the presence of cosmetics not bought from the game's official item shop on private servers, as it breaches the End User License Agreement (EULA).

## Quick Start (Windows)

### First Time Setup

1. **Run the setup script** (This will install Bun if needed and install dependencies):
   ```bat
   install_packages.bat
   ```

2. **Start ATLAS**:
   ```bat
   start.bat
   ```

That's it! The setup script will guide you through installing Bun if you don't have it already.

### Manual Setup

If you prefer to install manually:

1. **Install Bun** from [bun.sh](https://bun.sh/docs/installation)

2. **Install dependencies**:
   ```bash
   bun install
   ```

3. **Run ATLAS**:
   ```bash
   bun run src/index.ts
   ```

### How To Connect To Someone Else's ATLAS Server

1. **Install [Reboot Launcher](https://github.com/Auties00/Reboot-Launcher/releases/latest)

2. **Head over to the Backend tab.**
- Change the type to :
   ```bash
   Remote
   ```
- Enter your Friend's [Radmin VPN](https://www.radmin-vpn.com/) IP in the **Host** box.
- Change the port to **3551** (if they haven't manually changed the port)

3. **Test it by pressing** ***Start Backend***.
- If it replies **"The backend was started correctly"**, then it worked! You're free to launch Fortnite.
- If it replies **"Cannot ping the remote backend"**, then it didn't work; You either have the wrong IP or port.

## Credits

- [andr1ww](https://github.com/andr1ww) ATLAS is a fork of [Nexa](https://github.com/andr1ww/Nexa)
- [Ralzify](https://github.com/Ralzify) ATLAS uses the CurveTable and Straight Bloom code from [FortBackend](https://github.com/Ralzify/FortBackend)

## To Do List
- Arena for Latest Versions
- Fix applying MCP
- XMPP
