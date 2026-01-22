import { Hono } from "hono";
import path from "node:path";
import { loadRoutes } from "./utils/startup/loadRoutes";
import { Atlas } from "./utils/handlers/errors";
import logger from "./utils/logger/logger";
import Logger from "./utils/logger/logger";
import { cors } from "hono/cors";
import prompts from "prompts";
import fs from "node:fs";
import ini from "ini";
import { startMatchmakingWebSocket } from "./utils/matchmaking/websocket";

const PORT = process.env.PORT || 3551;
const app = new Hono({ strict: false });

// Store last status message
let lastStatusMessage = '';
let lastDisplayedMessage = '';
let shouldRefreshMenu = false;

// Export function to update status message from other modules
export function setStatusMessage(message: string) {
  // Add timestamp
  const now = new Date();
  let hours = now.getHours();
  const minutes = now.getMinutes().toString().padStart(2, '0');
  const seconds = now.getSeconds().toString().padStart(2, '0');
  const ampm = hours >= 12 ? 'PM' : 'AM';
  hours = hours % 12;
  hours = hours ? hours : 12; // the hour '0' should be '12'
  
  // Get timezone abbreviation
  const timezone = new Intl.DateTimeFormat('en-US', { timeZoneName: 'short' })
    .formatToParts(now)
    .find(part => part.type === 'timeZoneName')?.value || '';
  
  const timestamp = `${hours}:${minutes}:${seconds} ${ampm} ${timezone}`;
  
  lastStatusMessage = `${message} \x1b[90m- ${timestamp}\x1b[0m`;
  // If message changed, trigger menu refresh
  if (message !== lastDisplayedMessage) {
    lastDisplayedMessage = message;
    shouldRefreshMenu = true;
    
    // Immediately refresh the display
    console.clear();
    displayMenuContent();
  }
}

// Function to display the menu content (logo, status, options)
function displayMenuContent() {
  const terminalWidth = process.stdout.columns || 80;
  const logoLines = `\x1b[96m${addShadows(` █████╗ ████████╗██╗      █████╗ ███████╗
██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝
███████║   ██║   ██║     ███████║███████╗
██╔══██║   ██║   ██║     ██╔══██║╚════██║
██║  ██║   ██║   ███████╗██║  ██║███████║
╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝`)}
                                         
\x1b[37m${addShadowsBackend(`██████╗  █████╗  ██████╗██╗  ██╗███████╗███╗   ██╗██████╗ 
██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝████╗  ██║██╔══██╗
██████╔╝███████║██║     █████╔╝ █████╗  ██╔██╗ ██║██║  ██║
██╔══██╗██╔══██║██║     ██╔═██╗ ██╔══╝  ██║╚██╗██║██║  ██║
██████╔╝██║  ██║╚██████╗██║  ██╗███████╗██║ ╚████║██████╔╝
╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ `)}
                                                          
\x1b[0m`;
  
  const lines = logoLines.split('\n');
  const centeredLogo = lines.map(line => {
    const padding = Math.max(0, Math.floor((terminalWidth - line.replace(/\x1b\[[0-9;]*m/g, '').length) / 2));
    return ' '.repeat(padding) + line;
  }).join('\n');
  
  console.log(centeredLogo);
  console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on port ${PORT} | \x1b[33m[MATCHMAKING]\x1b[0m WebSocket on port 5555`);
  
  // Display last status message if exists
  if (lastStatusMessage) {
    console.log(lastStatusMessage);
  }
}

export default app;

app.use("*", cors());

app.notFound((c) => c.json(Atlas.basic.notFound, 404));

app.use(async (c, next) => {
  if (c.req.path === "/images/icons/gear.png" || c.req.path === "/favicon.ico") await next();
  else {
    await next();
    // Request logging disabled
  }
});

await loadRoutes(path.join(__dirname, "routes"), app);

// Show ATLAS logo immediately, centered in terminal
// Function to add gray color to shadow characters
const addShadows = (text: string) => {
  return text
    .replace(/╗/g, '\x1b[90m╗\x1b[96m')
    .replace(/╔/g, '\x1b[90m╔\x1b[96m')
    .replace(/═/g, '\x1b[90m═\x1b[96m')
    .replace(/╚/g, '\x1b[90m╚\x1b[96m')
    .replace(/╝/g, '\x1b[90m╝\x1b[96m')
    .replace(/║/g, '\x1b[90m║\x1b[96m');
};

const addShadowsBackend = (text: string) => {
  return text
    .replace(/╗/g, '\x1b[90m╗\x1b[37m')
    .replace(/╔/g, '\x1b[90m╔\x1b[37m')
    .replace(/═/g, '\x1b[90m═\x1b[37m')
    .replace(/╚/g, '\x1b[90m╚\x1b[37m')
    .replace(/╝/g, '\x1b[90m╝\x1b[37m')
    .replace(/║/g, '\x1b[90m║\x1b[37m');
};

const logo = `\x1b[96m${addShadows(` █████╗ ████████╗██╗      █████╗ ███████╗
██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝
███████║   ██║   ██║     ███████║███████╗
██╔══██║   ██║   ██║     ██╔══██║╚════██║
██║  ██║   ██║   ███████╗██║  ██║███████║
╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝`)}
                                         
\x1b[37m${addShadowsBackend(`██████╗  █████╗  ██████╗██╗  ██╗███████╗███╗   ██╗██████╗ 
██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝████╗  ██║██╔══██╗
██████╔╝███████║██║     █████╔╝ █████╗  ██╔██╗ ██║██║  ██║
██╔══██╗██╔══██║██║     ██╔═██╗ ██╔══╝  ██║╚██╗██║██║  ██║
██████╔╝██║  ██║╚██████╗██║  ██╗███████╗██║ ╚████║██████╔╝
╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ `)}
                                                          
\x1b[0m`;

// Center the logo in terminal
const terminalWidth = process.stdout.columns || 80;
const lines = logo.split('\n');
const centeredLogo = lines.map(line => {
  const padding = Math.max(0, Math.floor((terminalWidth - line.replace(/\x1b\[[0-9;]*m/g, '').length) / 2));
  return ' '.repeat(padding) + line;
}).join('\n');

console.log(centeredLogo);

// Function to toggle Straight Bloom
async function toggleStraightBloom() {
  try {
    const iniPath = path.join(__dirname, '../static/hotfixes/DefaultGame.ini');
    const sniperPath = path.join(__dirname, '../responses/sniper.json');
    
    let content = fs.readFileSync(iniPath, 'utf-8');
    const sniperData = JSON.parse(fs.readFileSync(sniperPath, 'utf-8'));
    const sniperSpreadLines = sniperData.lines;
    
    // Check if any sniper lines exist in the INI
    const hasLines = sniperSpreadLines.some(line => content.includes(line));
    
    if (hasLines) {
      // Remove all sniper lines
      sniperSpreadLines.forEach(line => {
        content = content.replace(line + '\n', '').replace(line, '');
      });
      // Clean up extra newlines
      content = content.replace(/\n\n+/g, '\n');
      lastStatusMessage = '\x1b[32m✓ Straight Bloom disabled!\x1b[0m';
    } else {
      // Add all sniper lines - find the last [AssetHotfix] section which should contain # Straight Bloom
      const lines = content.split('\n');
      let lastAssetHotfixIndex = -1;
      
      // Find the last [AssetHotfix] section
      for (let i = lines.length - 1; i >= 0; i--) {
        if (lines[i].trim() === '[AssetHotfix]') {
          lastAssetHotfixIndex = i;
          break;
        }
      }
      
      if (lastAssetHotfixIndex !== -1) {
        // Look for # Straight Bloom comment after this [AssetHotfix]
        let straightBloomIndex = -1;
        for (let i = lastAssetHotfixIndex + 1; i < lines.length; i++) {
          if (lines[i].trim() === '# Straight Bloom') {
            straightBloomIndex = i;
            break;
          }
        }
        
        if (straightBloomIndex !== -1) {
          // Insert after the # Straight Bloom comment
          lines.splice(straightBloomIndex + 1, 0, ...sniperSpreadLines);
          content = lines.join('\n');
        }
      }
      lastStatusMessage = '\x1b[32m✓ Straight Bloom enabled!\x1b[0m';
    }
    
    fs.writeFileSync(iniPath, content);
  } catch (error) {
    lastStatusMessage = `\x1b[31m✗ Failed to toggle Straight Bloom: ${error.message}\x1b[0m`;
  }
}

// Function to import CurveTables from DefaultGame.ini
async function importCurveTables() {
  try {
    const importsDir = path.join(__dirname, '../imports');
    
    // Check if imports directory exists
    if (!fs.existsSync(importsDir)) {
      fs.mkdirSync(importsDir, { recursive: true });
    }
    
    // Look for any .ini files in imports folder
    const files = fs.readdirSync(importsDir);
    const iniFiles = files.filter(file => {
      const stats = fs.statSync(path.join(importsDir, file));
      return stats.isFile() && file.toLowerCase().endsWith('.ini');
    });
    
    if (iniFiles.length === 0) {
      lastStatusMessage = '\x1b[33m✗ No .ini files found in imports folder. Please add a file first.\x1b[0m';
      return;
    }
    
    // Show available files
    console.log('\n\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
    console.log('\x1b[36m                 Available .ini Files\x1b[0m');
    console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
    iniFiles.forEach((file, index) => {
      console.log(`  \x1b[32m(${index + 1})\x1b[0m ${file}`);
    });
    console.log('  \x1b[32m(BACK)\x1b[0m Cancel and go back');
    console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m\n');
    
    const fileResponse = await prompts({
      type: 'text',
      name: 'fileIndex',
      message: '\x1b[32mSelect a file to import from:\x1b[0m',
      validate: (value) => {
        if (value.toLowerCase() === 'back') return true;
        const index = parseInt(value) - 1;
        return (index >= 0 && index < iniFiles.length) ? true : 'Please enter a valid file number or BACK';
      }
    });
    
    if (!fileResponse.fileIndex || fileResponse.fileIndex.toLowerCase() === 'back') {
      lastStatusMessage = '\x1b[33mImport cancelled.\x1b[0m';
      return;
    }
    
    const selectedFile = iniFiles[parseInt(fileResponse.fileIndex) - 1];
    const importFilePath = path.join(importsDir, selectedFile);
    const importContent = fs.readFileSync(importFilePath, 'utf-8');
    
    // Extract all CurveTable lines
    const curveTableRegex = /^\+CurveTable=(.+?);RowUpdate;(.+?);(\d+);(.+)$/gm;
    const matches = [...importContent.matchAll(curveTableRegex)];
    
    if (matches.length === 0) {
      lastStatusMessage = '\x1b[33m✗ No curvetables found in the selected file.\x1b[0m';
      return;
    }
    
    // Show found curvetables with better formatting
    console.log('\n\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
    console.log(`\x1b[36m          Found ${matches.length} CurveTable(s) to Import\x1b[0m`);
    console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
    matches.forEach((match, index) => {
      const key = match[2];
      const value = match[4];
      const displayKey = key.length > 45 ? '...' + key.slice(-42) : key;
      console.log(`  \x1b[90m${String(index + 1).padStart(2, ' ')}.\x1b[0m \x1b[96m${displayKey}\x1b[0m`);
      console.log(`      \x1b[90mValue:\x1b[0m ${value}`);
    });
    console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m\n');
    
    const confirmResponse = await prompts({
      type: 'text',
      name: 'confirm',
      message: `\x1b[32mImport all ${matches.length} curvetable(s)? (Y/N):\x1b[0m`,
      validate: (value) => ['y', 'Y', 'n', 'N'].includes(value) ? true : 'Please enter Y or N'
    });
    
    if (!confirmResponse.confirm || confirmResponse.confirm.toUpperCase() !== 'Y') {
      lastStatusMessage = '\x1b[33mImport cancelled.\x1b[0m';
      return;
    }
    
    // Read current backend's DefaultGame.ini and curves.json
    const iniPath = path.join(__dirname, '../static/hotfixes/DefaultGame.ini');
    const curvesPath = path.join(__dirname, '../responses/curves.json');
    let content = fs.readFileSync(iniPath, 'utf-8');
    const curves = JSON.parse(fs.readFileSync(curvesPath, 'utf-8'));
    
    let importedCount = 0;
    let updatedCount = 0;
    let enabledCount = 0;
    let skippedCount = 0;
    let customsAdded = 0;
    
    // Build a map of existing default curves by key
    const defaultCurvesByKey = new Map();
    Object.entries(curves).forEach(([id, curve]: any) => {
      defaultCurvesByKey.set(curve.key, { id, curve });
    });
    
    // Import each curvetable
    matches.forEach(match => {
      const fullLine = match[0];
      const pathPart = match[1];
      const key = match[2];
      const value = match[4];
      
      // Check if this exact line already exists in INI (avoid duplicates)
      const escapedKey = key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const escapedValue = value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const exactLineRegex = new RegExp(`^\\+CurveTable=.*;RowUpdate;${escapedKey};\\d+;${escapedValue}$`, 'gm');
      
      if (exactLineRegex.test(content)) {
        // Exact line already exists, skip it
        skippedCount++;
        return;
      }
      
      // Check if this is a default ATLAS curve
      if (defaultCurvesByKey.has(key)) {
        const defaultEntry = defaultCurvesByKey.get(key);
        const defaultCurve = defaultEntry.curve;
        
        // Check if line with this key exists in INI
        const keyExistsRegex = new RegExp(`^\\+CurveTable=.*;RowUpdate;${escapedKey};\\d+;.*$`, 'gm');
        
        if (keyExistsRegex.test(content)) {
          // Update existing value
          content = content.replace(keyExistsRegex, fullLine);
          updatedCount++;
        } else {
          // Enable this default curve with the imported value
          const assetHotfixIndex = content.indexOf('[AssetHotfix]');
          if (assetHotfixIndex !== -1) {
            const insertPoint = content.indexOf('\n', assetHotfixIndex) + 1;
            content = content.slice(0, insertPoint) + fullLine + '\n' + content.slice(insertPoint);
            enabledCount++;
          }
          
          // Clear deleted state if it exists
          if (defaultCurve.isDeleted) {
            delete defaultCurve.isDeleted;
            delete defaultCurve.deletedLine;
            curves[defaultEntry.id] = defaultCurve;
          }
        }
      } else {
        // This is a custom curve not in default list
        // Check if it already exists in INI with different value
        const keyExistsRegex = new RegExp(`^\\+CurveTable=.*;RowUpdate;${escapedKey};\\d+;.*$`, 'gm');
        
        if (keyExistsRegex.test(content)) {
          // Update existing custom curve
          content = content.replace(keyExistsRegex, fullLine);
          updatedCount++;
        } else {
          // Add as new custom curve with auto-generated name
          // Generate a readable name from the key
          const autoName = key
            .split('.')
            .pop() // Get last part after final dot
            .replace(/([A-Z])/g, ' $1') // Add space before capital letters
            .trim();
          
          // Find next available ID
          const maxId = Math.max(...Object.keys(curves).map(k => parseInt(k)).filter(n => !isNaN(n)), 0);
          const newId = String(maxId + 1);
          
          // Add to curves.json
          curves[newId] = {
            name: `Imported: ${autoName}`,
            key: key,
            value: value,
            pathPart: pathPart,
            type: 'custom',
            isCustom: true
          };
          
          // Add to INI file
          const assetHotfixIndex = content.indexOf('[AssetHotfix]');
          if (assetHotfixIndex !== -1) {
            const insertPoint = content.indexOf('\n', assetHotfixIndex) + 1;
            content = content.slice(0, insertPoint) + fullLine + '\n' + content.slice(insertPoint);
            customsAdded++;
          }
        }
      }
    });
    
    // Save updated INI and curves
    fs.writeFileSync(iniPath, content);
    fs.writeFileSync(curvesPath, JSON.stringify(curves, null, 2));
    
    // Build status message
    const statusParts = [];
    if (enabledCount > 0) statusParts.push(`${enabledCount} enabled`);
    if (customsAdded > 0) statusParts.push(`${customsAdded} custom added`);
    if (updatedCount > 0) statusParts.push(`${updatedCount} updated`);
    if (skippedCount > 0) statusParts.push(`${skippedCount} skipped (duplicates)`);
    
    lastStatusMessage = `\x1b[32m✓ Import complete! ${statusParts.join(', ')}.\x1b[0m`;
    
    // Optional: Ask if user wants to delete the imported file
    const deleteResponse = await prompts({
      type: 'text',
      name: 'delete',
      message: '\x1b[32mDelete the imported file? (Y/N):\x1b[0m',
      validate: (value) => ['y', 'Y', 'n', 'N'].includes(value) ? true : 'Please enter Y or N'
    });
    
    if (deleteResponse.delete && deleteResponse.delete.toUpperCase() === 'Y') {
      // Ask for confirmation before deleting
      const confirmResponse = await prompts({
        type: 'text',
        name: 'confirm',
        message: '\x1b[31mAre you sure you want to delete this file? (Y/N):\x1b[0m',
        validate: (value) => ['y', 'Y', 'n', 'N'].includes(value) ? true : 'Please enter Y or N'
      });
      
      if (confirmResponse.confirm && confirmResponse.confirm.toUpperCase() === 'Y') {
        fs.unlinkSync(importFilePath);
        lastStatusMessage += ' \x1b[90m(File deleted)\x1b[0m';
      } else {
        lastStatusMessage += ' \x1b[90m(File kept)\x1b[0m';
      }
    }
    
  } catch (error) {
    lastStatusMessage = `\x1b[31m✗ Failed to import curvetables: ${error.message}\x1b[0m`;
  }
}

// Function to display Arena Leaderboard
async function showArenaLeaderboard() {
  try {
    // Clear console and redisplay logo
    console.clear();
    
    // Redisplay centered logo using the global logo variable
    const terminalWidth = process.stdout.columns || 80;
    const lines = logo.split('\n');
    const centeredLogo = lines.map(line => {
      const padding = Math.max(0, Math.floor((terminalWidth - line.replace(/\x1b\[[0-9;]*m/g, '').length) / 2));
      return ' '.repeat(padding) + line;
    }).join('\n');
    
    console.log(centeredLogo);
    console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on port ${PORT}`);
    
    console.log('\n\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
    console.log('\x1b[36m                  Arena Leaderboard\x1b[0m');
    console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m\n');
    
    // Load all player profiles and their arena points
    const profilesDir = path.join(__dirname, '..', 'static', 'profiles');
    const leaderboard: Array<{accountId: string, name: string, points: number}> = [];
    
    try {
      const accounts = await fs.promises.readdir(profilesDir);
      
      for (const accountId of accounts) {
        const accountPath = path.join(profilesDir, accountId);
        const stats = await fs.promises.stat(accountPath);
        
        // Skip if not a directory or if it's the template file
        if (!stats.isDirectory()) continue;
        
        // Skip Host account from leaderboard
        if (accountId.toLowerCase() === 'host') continue;
        
        try {
          const profilePath = path.join(accountPath, 'profile_athena.json');
          const profileData = await fs.promises.readFile(profilePath, 'utf-8');
          const profile = JSON.parse(profileData);
          
          const arenaPoints = profile?.stats?.attributes?.arena_hype || 0;
          
          // Use the folder name (accountId) as the display name
          const displayName = accountId;
          
          leaderboard.push({
            accountId: accountId,
            name: displayName,
            points: arenaPoints
          });
        } catch (err) {
          // Skip profiles that can't be read
        }
      }
      
      // Sort by points (highest to lowest)
      leaderboard.sort((a, b) => b.points - a.points);
      
      if (leaderboard.length === 0) {
        console.log('\x1b[33m  No player profiles found.\x1b[0m\n');
      } else {
        // Display leaderboard
        console.log('  \x1b[90mRank  Name                                    Arena Points\x1b[0m');
        console.log('  \x1b[36m─────────────────────────────────────────────────────────\x1b[0m');
        
        leaderboard.forEach((player, index) => {
          const rank = String(index + 1).padStart(4, ' ');
          
          // Format display name with proper length
          let displayName = player.name || 'Unknown';
          if (displayName.length > 35) {
            displayName = displayName.substring(0, 32) + '...';
          } else if (displayName.length < 35) {
            displayName = displayName + ' '.repeat(35 - displayName.length);
          }
          
          const points = String(player.points).padStart(12, ' ');
          
          // Color code: Gold for 1st, Silver for 2nd, Bronze for 3rd
          let rankColor = '\x1b[0m';
          if (index === 0) rankColor = '\x1b[93m'; // Gold
          else if (index === 1) rankColor = '\x1b[37m'; // Silver
          else if (index === 2) rankColor = '\x1b[33m'; // Bronze
          
          console.log(`  ${rankColor}${rank}.\x1b[0m \x1b[96m${displayName}\x1b[0m \x1b[32m${points}\x1b[0m`);
        });
        
        console.log(`\n  \x1b[90mTotal Players: ${leaderboard.length}\x1b[0m`);
      }
    } catch (err) {
      console.log('\x1b[31m  Error loading profiles: ' + err.message + '\x1b[0m\n');
    }
    
    console.log('\n\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
    
    // Wait for user to press enter
    await prompts({
      type: 'text',
      name: 'continue',
      message: '\x1b[90mPress Enter to continue...\x1b[0m'
    });
    
  } catch (error) {
    console.error('\x1b[31mError displaying leaderboard:\x1b[0m', error);
    await prompts({
      type: 'text',
      name: 'continue',
      message: '\x1b[90mPress Enter to continue...\x1b[0m'
    });
  }
}

// Function for Other Settings menu
async function otherSettingsMenu() {
  let continueLoop = true;
  
  while (continueLoop) {
    try {
      // Clear console and redisplay logo
      console.clear();
      
      // Redisplay centered logo using the global logo variable
      const terminalWidth = process.stdout.columns || 80;
      const lines = logo.split('\n');
      const centeredLogo = lines.map(line => {
        const padding = Math.max(0, Math.floor((terminalWidth - line.replace(/\x1b\[[0-9;]*m/g, '').length) / 2));
        return ' '.repeat(padding) + line;
      }).join('\n');
      
      console.log(centeredLogo);
      console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on port ${PORT}`);
      
      // Display last status message if exists
      if (lastStatusMessage) {
        console.log(`\x1b[36m[BACKEND]\x1b[0m ${lastStatusMessage}`);
      }
      
      // Read current config
      const configPath = path.join(__dirname, 'config', 'config.ini');
      const config = ini.parse(fs.readFileSync(configPath, 'utf-8'));
      const arenaPointsEnabled = config.SaveArenaPoints === 'true' || config.SaveArenaPoints === true;
      const arenaStatus = arenaPointsEnabled ? '\x1b[32m[ON]\x1b[0m' : '\x1b[31m[OFF]\x1b[0m';
      
      console.log('\n\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
      console.log('\x1b[36m                     Other Settings\x1b[0m');
      console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
      console.log(`\x1b[32m(1)\x1b[0m Toggle Arena Point Saving ${arenaStatus}`);
      console.log('\x1b[32m(2)\x1b[0m Arena Leaderboard');
      console.log('\x1b[32m(BACK)\x1b[0m Return to main menu');
      console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
      
      const response = await prompts({
        type: 'text',
        name: 'choice',
        message: '\x1b[32mSelect an option (1/2/BACK):\x1b[0m',
        validate: (value) => {
          if (value.toLowerCase() === 'back') return true;
          const num = parseInt(value);
          return (num === 1 || num === 2) ? true : 'Please enter 1, 2, or BACK';
        }
      });
      
      if (!response.choice || response.choice.toLowerCase() === 'back') {
        lastStatusMessage = '';
        continueLoop = false;
        continue;
      }
      
      const choice = response.choice;
      
      switch (choice) {
        case '1':
          // Toggle Arena Point Saving
          const newValue = !arenaPointsEnabled;
          config.SaveArenaPoints = newValue.toString();
          fs.writeFileSync(configPath, ini.stringify(config));
          lastStatusMessage = `\x1b[32m✓ Arena Point Saving ${newValue ? 'enabled' : 'disabled'}! ${newValue ? 'Players will keep their arena points.' : 'Players will start at 0 arena points.'}\x1b[0m`;
          break;
        case '2':
          // Show Arena Leaderboard
          await showArenaLeaderboard();
          lastStatusMessage = '';
          break;
        default:
          break;
      }
      
    } catch (error) {
      lastStatusMessage = `\x1b[31m✗ Failed to update settings: ${error.message}\x1b[0m`;
      continueLoop = false;
    }
  }
}

// Function to modify CurveTables
async function modifyCurveTables() {
  let continueLoop = true;
  
  while (continueLoop) {
    try {
      // Clear console and redisplay logo
    console.clear();
    
    // Redisplay centered logo
    const terminalWidth = process.stdout.columns || 80;
    const logoLines = `\x1b[96m${addShadows(` █████╗ ████████╗██╗      █████╗ ███████╗
██╔══██╗╚══██╔══╝██║     ██╔══██╗██╔════╝
███████║   ██║   ██║     ███████║███████╗
██╔══██║   ██║   ██║     ██╔══██║╚════██║
██║  ██║   ██║   ███████╗██║  ██║███████║
╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚══════╝`)}
                                         
\x1b[37m${addShadowsBackend(`██████╗  █████╗  ██████╗██╗  ██╗███████╗███╗   ██╗██████╗ 
██╔══██╗██╔══██╗██╔════╝██║ ██╔╝██╔════╝████╗  ██║██╔══██╗
██████╔╝███████║██║     █████╔╝ █████╗  ██╔██╗ ██║██║  ██║
██╔══██╗██╔══██║██║     ██╔═██╗ ██╔══╝  ██║╚██╗██║██║  ██║
██████╔╝██║  ██║╚██████╗██║  ██╗███████╗██║ ╚████║██████╔╝
╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝╚═════╝ `)}
                                                          
\x1b[0m`;
    
    const lines = logoLines.split('\n');
    const centeredLogo = lines.map(line => {
      const padding = Math.max(0, Math.floor((terminalWidth - line.replace(/\x1b\[[0-9;]*m/g, '').length) / 2));
      return ' '.repeat(padding) + line;
    }).join('\n');
    
    console.log(centeredLogo);
    console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on port ${PORT}`);
    
    // Display last status message if exists
    if (lastStatusMessage) {
      console.log(`\x1b[36m[BACKEND]\x1b[0m ${lastStatusMessage}`);
    }
    
    const backupPath = path.join(__dirname, '../responses/modifications-backup.json');
    
    // Check if curvetables are toggled off
    if (fs.existsSync(backupPath)) {
      lastStatusMessage = '\x1b[33m✗ CurveTables are currently disabled. Toggle them on first to modify.\x1b[0m';
      return;
    }
    
    const curvesPath = path.join(__dirname, '../responses/curves.json');
    const iniPath = path.join(__dirname, '../static/hotfixes/DefaultGame.ini');
    const curves = JSON.parse(fs.readFileSync(curvesPath, 'utf-8'));
    let content = fs.readFileSync(iniPath, 'utf-8');
    
    console.log('\n\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
    console.log('\x1b[36m                 CurveTable Management\x1b[0m');
    console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
    console.log('\x1b[32m(1)\x1b[0m Add CurveTable');
    console.log('\x1b[32m(2)\x1b[0m Delete CurveTable');
    console.log('\x1b[32m(3)\x1b[0m List Current Values');
    console.log('\x1b[32m(4)\x1b[0m Add Custom CurveTable');
    console.log('\x1b[32m(5)\x1b[0m Import CurveTables from .ini file');
    console.log('\x1b[32m(6)\x1b[0m Clear All CurveTables');
    console.log('\x1b[32m(BACK)\x1b[0m Return to main menu');
    console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
    
    const actionResponse = await prompts({
      type: 'text',
      name: 'action',
      message: '\x1b[32mSelect an option (1/2/3/4/5/6/BACK):\x1b[0m',
      validate: (value) => (['1', '2', '3', '4', '5', '6'].includes(value) || value.toLowerCase() === 'back') ? true : 'Please enter 1, 2, 3, 4, 5, 6, or BACK'
    });
    
    const action = actionResponse.action?.toLowerCase();
    
    if (!action || action === 'back') {
      continueLoop = false;
      break;
    }
    
    if (action === '3') {
      // List current CurveTable values
      const curveTableRegex = /^\+CurveTable=(.+?);RowUpdate;(.+?);0;(.+)$/gm;
      const matches = [...content.matchAll(curveTableRegex)];
      
      if (matches.length > 0) {
        console.log('\n\x1b[36mCurrent CurveTable Values:\x1b[0m');
        matches.forEach(match => {
          console.log(`  \x1b[32m${match[2]}\x1b[0m = ${match[3]}`);
          console.log(`    Path: ${match[1]}`);
        });
        lastStatusMessage = '\x1b[36mCurveTable list displayed.\x1b[0m';
      } else {
        console.log('\n\x1b[33mNo active CurveTable modifications found.\x1b[0m');
        lastStatusMessage = '\x1b[33mNo active CurveTable modifications found.\x1b[0m';
      }
      console.log('');
      
      // Wait for user to press enter before returning to submenu
      await prompts({
        type: 'text',
        name: 'continue',
        message: '\x1b[90mPress Enter to continue...\x1b[0m'
      });
      
      // Continue loop to show submenu again
      continue;
    }
    
    if (action === '4') {
      // Add custom CurveTable
      const nameResponse = await prompts({
        type: 'text',
        name: 'name',
        message: '\x1b[32mEnter a name for this custom curvetable:\x1b[0m',
        validate: (value) => value.length > 0 ? true : 'Name cannot be empty'
      });
      
      if (!nameResponse.name) {
        // User cancelled
        continue;
      }
      
      const pasteResponse = await prompts({
        type: 'text',
        name: 'paste',
        message: '\x1b[32mPaste the curvetable string (e.g., +CurveTable=/Game/Athena/Balance/DataTables/AthenaGameData;RowUpdate;Default.TurboBuildInterval;0;0.002):\x1b[0m',
        validate: (value) => value.startsWith('+CurveTable=') ? true : 'String must start with +CurveTable='
      });
      
      if (!pasteResponse.paste) {
        // User cancelled
        continue;
      }
      
      // Parse the curvetable string
      const curveString = pasteResponse.paste.trim();
      const match = curveString.match(/^\+CurveTable=(.+?);RowUpdate;(.+?);(\d+);(.+)$/);
      
      if (!match) {
        lastStatusMessage = '\x1b[31m✗ Invalid curvetable format. Expected: +CurveTable=/path;RowUpdate;key;0;value\x1b[0m';
        continue;
      }
      
      const [_, path_part, key, zeroVal, value] = match;
      
      // Find next ID
      const maxId = Math.max(...Object.keys(curves).map(k => parseInt(k)).filter(n => !isNaN(n)), 0);
      const newId = String(maxId + 1);
      
      // Add to curves.json
      curves[newId] = {
        name: nameResponse.name,
        key: key,
        value: value,
        pathPart: path_part,
        type: 'custom',
        isCustom: true
      };
      
      fs.writeFileSync(curvesPath, JSON.stringify(curves, null, 2));
      
      // Add to INI file
      const assetHotfixIndex = content.indexOf('[AssetHotfix]');
      if (assetHotfixIndex !== -1) {
        const insertPoint = content.indexOf('\n', assetHotfixIndex) + 1;
        content = content.slice(0, insertPoint) + curveString + '\n' + content.slice(insertPoint);
      }
      
      fs.writeFileSync(iniPath, content);
      lastStatusMessage = '\x1b[32m✓ Custom curvetable added successfully!\x1b[0m';
      
      // Continue loop to show submenu again
      continue;
    }
    
    if (action === '5') {
      // Import CurveTables from DefaultGame.ini
      await importCurveTables();
      
      // Wait for user to press enter before returning to submenu
      await prompts({
        type: 'text',
        name: 'continue',
        message: '\x1b[90mPress Enter to continue...\x1b[0m'
      });
      
      // Continue loop to show submenu again
      continue;
    }
    
    if (action === '6') {
      // Clear all curvetables with confirmation
      const confirmResponse = await prompts({
        type: 'text',
        name: 'confirm',
        message: '\x1b[31mAre you sure you want to delete ALL curvetables? (Y/N):\x1b[0m',
        validate: (value) => ['y', 'Y', 'n', 'N'].includes(value) ? true : 'Please enter Y or N'
      });
      
      if (!confirmResponse.confirm) {
        // User cancelled
        lastStatusMessage = '\x1b[33mCancelled.\x1b[0m';
        continue;
      }
      
      if (confirmResponse.confirm?.toUpperCase() === 'Y') {
        // Remove all CurveTable lines from INI
        content = content.replace(/^\+CurveTable=.*$/gm, '');
        content = content.replace(/^\s*\n/gm, '');
        fs.writeFileSync(iniPath, content);
        
        // Remove all custom curvetables from JSON
        const customEntries = Object.keys(curves).filter(key => curves[key].isCustom);
        customEntries.forEach(key => {
          delete curves[key];
        });
        fs.writeFileSync(curvesPath, JSON.stringify(curves, null, 2));
        
        lastStatusMessage = '\x1b[32m✓ All curvetables cleared!\x1b[0m';
      } else {
        lastStatusMessage = '\x1b[33mCancelled.\x1b[0m';
      }
      
      // Continue loop to show submenu again
      continue;
    }
    
    // For Add (1) and Delete (2), show all curves including custom ones
    const allCurves = Object.entries(curves);
    
    console.log('\n\x1b[33mAvailable Curve Modifications:\x1b[0m');
    allCurves.forEach(([key, curve]: any) => {
      // Check if curve is currently in the INI file
      const escapedKey = curve.key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const regex = new RegExp(`^\\+CurveTable=.*;RowUpdate;${escapedKey};0;.*$`, 'gm');
      const isInUse = regex.test(content);
      
      const usageLabel = isInUse ? '\x1b[32m[USED]\x1b[0m' : '\x1b[90m[UNUSED]\x1b[0m';
      const customLabel = curve.isCustom ? ' \x1b[33m[CUSTOM]\x1b[0m' : '';
      console.log(`\x1b[36m(${key})\x1b[0m ${curve.name} ${usageLabel}${customLabel}`);
    });
    console.log('\x1b[36m(BACK)\x1b[0m Go back');
    console.log('');
    
    const curveResponse = await prompts({
      type: 'text',
      name: 'curve',
      message: '\x1b[32mChoose a curve:\x1b[0m',
      validate: (value) => {
        if (value.toLowerCase() === 'back') return true;
        return Object.keys(Object.fromEntries(allCurves)).includes(value) ? true : 'Please enter a valid curve number or BACK';
      }
    });
    
    if (!curveResponse.curve || curveResponse.curve?.toLowerCase() === 'back') {
      // Go back to submenu
      continue;
    }
    
    const selectedCurve = curves[curveResponse.curve];
    
    if (action === '2') {
      // Delete: Remove the CurveTable line and store it
      const escapedKey = selectedCurve.key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const regex = new RegExp(`^\\+CurveTable=.*;RowUpdate;${escapedKey};0;.*$`, 'gm');
      const match = content.match(regex);
      
      if (match && match[0]) {
        // Store the deleted line in the curve definition
        selectedCurve.deletedLine = match[0];
        selectedCurve.isDeleted = true;
        
        // Remove from INI file
        content = content.replace(regex, '').replace(/^\s*\n/gm, '');
        
        // Update curves.json to store the deleted state
        curves[curveResponse.curve] = selectedCurve;
        fs.writeFileSync(curvesPath, JSON.stringify(curves, null, 2));
        
        lastStatusMessage = '\x1b[32m✓ CurveTable removed successfully!\x1b[0m';
      } else {
        lastStatusMessage = '\x1b[33mCurveTable not found in INI file.\x1b[0m';
      }
    } else if (action === '1') {
      // Add: Prompt for value and add/update the line
      let newValue: string;
      if (selectedCurve.type === 'static') {
        newValue = selectedCurve.staticValue;
        console.log(`\x1b[32mUsing static value: ${newValue}\x1b[0m`);
      } else {
        const valueResponse = await prompts({
          type: 'text',
          name: 'value',
          message: `\x1b[32mEnter new value for ${selectedCurve.name}:\x1b[0m`,
          validate: (value) => !isNaN(Number(value)) ? true : 'Please enter a valid number'
        });
        
        if (!valueResponse.value && valueResponse.value !== '0') {
          // User cancelled
          continue;
        }
        
        newValue = valueResponse.value;
      }
      
      const pathPart = selectedCurve.pathPart || '/Game/Athena/Balance/DataTables/AthenaGameData';
      const curveLine = `+CurveTable=${pathPart};RowUpdate;${selectedCurve.key};0;${newValue}`;
      const escapedKey = selectedCurve.key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      const existingLineRegex = new RegExp(`\\+CurveTable=.*;RowUpdate;${escapedKey};0;.*`, 'g');
      
      if (existingLineRegex.test(content)) {
        // Update existing
        content = content.replace(existingLineRegex, curveLine);
      } else {
        // Add new
        const assetHotfixIndex = content.indexOf('[AssetHotfix]');
        if (assetHotfixIndex !== -1) {
          const insertPoint = content.indexOf('\n', assetHotfixIndex) + 1;
          content = content.slice(0, insertPoint) + curveLine + '\n' + content.slice(insertPoint);
        }
      }
      
      // Clear deleted state if it was previously deleted
      if (selectedCurve.isDeleted) {
        delete selectedCurve.isDeleted;
        delete selectedCurve.deletedLine;
        curves[curveResponse.curve] = selectedCurve;
        fs.writeFileSync(curvesPath, JSON.stringify(curves, null, 2));
      }
      
      lastStatusMessage = '\x1b[32m✓ CurveTable added/updated successfully!\x1b[0m';
    }
    
      fs.writeFileSync(iniPath, content);
      
      // Continue loop to show submenu again after add/delete
      continue;
    } catch (error) {
      lastStatusMessage = `\x1b[31m✗ Failed to modify CurveTables: ${error.message}\x1b[0m`;
      continue;
    }
  }
}

// Function to toggle all curvetable modifications
async function toggleAllModifications() {
  try {
    const iniPath = path.join(__dirname, '../static/hotfixes/DefaultGame.ini');
    const backupPath = path.join(__dirname, '../responses/modifications-backup.json');
    
    let content = fs.readFileSync(iniPath, 'utf-8');
    
    // Check if backup exists
    if (fs.existsSync(backupPath)) {
      // Restore from backup
      const backup = JSON.parse(fs.readFileSync(backupPath, 'utf-8'));
      
      // Restore curvetable lines
      if (backup.curveTableLines && backup.curveTableLines.length > 0) {
        backup.curveTableLines.forEach(line => {
          content = content.replace(`;${line}`, line);
        });
      }
      
      fs.writeFileSync(iniPath, content);
      fs.unlinkSync(backupPath);
      lastStatusMessage = '\x1b[32m✓ CurveTables restored!\x1b[0m';
    } else {
      // Create backup and disable
      const activeLines = {
        curveTableLines: [] as string[]
      };
      
      // Find and backup curvetable lines
      const curveTableRegex = /^\+CurveTable=.*;RowUpdate;.*$/gm;
      const matches = [...content.matchAll(curveTableRegex)];
      matches.forEach(match => {
        const line = match[0];
        if (!line.startsWith(';')) {
          activeLines.curveTableLines.push(line);
          content = content.replace(new RegExp(`^${line.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'gm'), `;${line}`);
        }
      });
      
      fs.writeFileSync(iniPath, content);
      fs.writeFileSync(backupPath, JSON.stringify(activeLines, null, 2));
      lastStatusMessage = '\x1b[32m✓ CurveTables disabled! Backup created.\x1b[0m';
    }
  } catch (error) {
    lastStatusMessage = `\x1b[31m✗ Failed to toggle modifications: ${error.message}\x1b[0m`;
  }
}

// Function to check if modifications are enabled
function areModificationsEnabled(): boolean {
  try {
    const backupPath = path.join(__dirname, '../responses/modifications-backup.json');
    return !fs.existsSync(backupPath);
  } catch {
    return true;
  }
}

async function runInteractiveCLI() {
  while (true) {
    // Clear console and display menu content
    console.clear();
    displayMenuContent();
  
  const iniPath = path.join(__dirname, '../static/hotfixes/DefaultGame.ini');
  const sniperPath = path.join(__dirname, '../responses/sniper.json');
  const backupPath = path.join(__dirname, '../responses/modifications-backup.json');
  const content = fs.readFileSync(iniPath, 'utf-8');
  const sniperData = JSON.parse(fs.readFileSync(sniperPath, 'utf-8'));
  const sniperSpreadLines = sniperData.lines;
  
  // Check if straight bloom is currently enabled
  const hasUncommentedSniperLines = sniperSpreadLines.some(line => content.includes(line) && !content.includes(`;${line}`));
  const bloomStatus = hasUncommentedSniperLines ? '\x1b[32m[ON]\x1b[0m' : '\x1b[31m[OFF]\x1b[0m';
  
  // Check if curvetables are enabled
  const curveTablesEnabled = !fs.existsSync(backupPath);
  const curveTableStatus = curveTablesEnabled ? '\x1b[32m[ON]\x1b[0m' : '\x1b[31m[OFF]\x1b[0m';

  console.log('\n\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
  console.log('\x1b[36m                Available Modifications\x1b[0m');
  console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
  console.log(`\x1b[32m(1)\x1b[0m Toggle Straight Bloom ${bloomStatus}`);
  console.log(`\x1b[32m(2)\x1b[0m Toggle CurveTables ${curveTableStatus}`);
  console.log('\x1b[32m(3)\x1b[0m Modify CurveTables');
  console.log('\x1b[32m(4)\x1b[0m Other Settings');
  console.log('\x1b[32m(5)\x1b[0m Refresh');
  console.log('\x1b[32m(6)\x1b[0m Exit');
  console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');

  // Check if we should auto-refresh due to new status message
  if (shouldRefreshMenu) {
    shouldRefreshMenu = false;
    await new Promise(resolve => setTimeout(resolve, 50)); // Brief pause to show the message
    continue; // Restart loop to refresh display
  }

  const response = await prompts({
    type: 'text',
    name: 'value',
    message: '\x1b[32mSelect an option (1/2/3/4/5/6):\x1b[0m',
    validate: (value) => {
      const num = parseInt(value);
      return (num >= 1 && num <= 6) ? true : 'Please enter a number between 1 and 6';
    }
  });

  const choice = response.value;

  switch (choice) {
    case '1':
      await toggleStraightBloom();
      break;
    case '2':
      await toggleAllModifications();
      break;
    case '3':
      await modifyCurveTables();
      break;
    case '4':
      await otherSettingsMenu();
      break;
    case '5':
      // Just continue loop to refresh
      break;
    case '6':
      console.log('Exiting...');
      process.exit(0);
      break;
  }

  // Loop continues to show menu again
  }
}

// Check for updates from GitHub
async function checkForUpdates() {
  try {
    // Get local git commit SHA if in a git repository
    const { execSync } = require('child_process');
    let localCommitSha = '';
    
    try {
      localCommitSha = execSync('git rev-parse --short HEAD', { 
        cwd: path.join(__dirname, '..'),
        encoding: 'utf-8' 
      }).trim();
    } catch {
      // Not a git repository or git not available
    }
    
    // Check for latest commit on main branch
    const response = await fetch('https://api.github.com/repos/Project-Nocturno/ATLAS-Backend/commits/main', {
      headers: {
        'User-Agent': 'ATLAS-Backend'
      }
    });
    
    if (response.ok) {
      const data = await response.json();
      const latestCommitSha = data.sha.substring(0, 7); // Short SHA
      const commitDate = new Date(data.commit.committer.date);
      
      // Format the commit date
      let hours = commitDate.getHours();
      const minutes = commitDate.getMinutes().toString().padStart(2, '0');
      const ampm = hours >= 12 ? 'PM' : 'AM';
      hours = hours % 12;
      hours = hours ? hours : 12;
      
      const timezone = new Intl.DateTimeFormat('en-US', { timeZoneName: 'short' })
        .formatToParts(commitDate)
        .find(part => part.type === 'timeZoneName')?.value || '';
      
      const month = (commitDate.getMonth() + 1).toString().padStart(2, '0');
      const day = commitDate.getDate().toString().padStart(2, '0');
      const year = commitDate.getFullYear();
      
      const formattedDate = `${month}/${day}/${year} ${hours}:${minutes} ${ampm} ${timezone}`;
      
      // Compare local commit with remote
      if (localCommitSha && localCommitSha !== latestCommitSha) {
        console.log(`\x1b[32m[UPDATE]\x1b[0m A new update is available! Check the GitHub to download the latest version. (Released: ${formattedDate})\n`);
        // Wait 5 seconds before continuing
        await new Promise(resolve => setTimeout(resolve, 5000));
      }
    }
  } catch (error) {
    // Silently fail if update check fails (no internet, etc.)
  }
}

// Start the server with Bun
const startServer = async () => {
  // Check for updates first before starting anything
  await checkForUpdates();
  
  // Start matchmaking WebSocket server
  startMatchmakingWebSocket(5555);
  
  Bun.serve({
    port: PORT,
    fetch: app.fetch,
  });
  
  // Wait for Bun's startup message to print
  await new Promise(resolve => setTimeout(resolve, 100));
  
  await runInteractiveCLI();
};

// Main execution
startServer();

