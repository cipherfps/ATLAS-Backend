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
import CheckForUpdate from "./utils/checkforupdate";

const PORT = process.env.PORT || 3551;
const app = new Hono({ strict: false });

// Version: 1.0.1 - Update notification system is now working!

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
  console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on Port ${PORT}`);
  
  // Display last status message if exists
  if (lastStatusMessage) {
    console.log(lastStatusMessage);
  }
}

export default app;

app.use("*", cors());

app.notFound((c) => c.json(Atlas.basic.notFound, 404));

app.use(async (c, next) => {
  if (c.req.path === "/images/icons/gear.png" || c.req.path === "/favicon.ico") {
    await next();
  } else {
    await next();
  }

  if (c.req.path === "/unknown" && c.req.method === "GET") {
    setStatusMessage("\x1b[36m[BACKEND]\x1b[0m ATLAS Backend was pinged by Launcher");
    return c.text("OK"); // Return a response and prevent further logging
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

// Don't display logo here - will display during startup

const CURVE_TABLE_COMMENT = '# CurveTables';
const STRAIGHT_BLOOM_COMMENT = '# Straight Bloom';

function findInsertPoint(fileContent: string, commentLabel: string): number {
  const commentIndex = fileContent.indexOf(commentLabel);
  if (commentIndex !== -1) {
    const newlineAfterComment = fileContent.indexOf('\n', commentIndex);
    return newlineAfterComment === -1 ? fileContent.length : newlineAfterComment + 1;
  }

  const assetIndex = fileContent.indexOf('[AssetHotfix]');
  if (assetIndex !== -1) {
    const newlineAfterAsset = fileContent.indexOf('\n', assetIndex);
    return newlineAfterAsset === -1 ? fileContent.length : newlineAfterAsset + 1;
  }

  return fileContent.length;
}

function ensureAssetSection(
  fileContent: string,
  commentLabel: string,
  preferPrepend = false
): { content: string; insertPoint: number } {
  let content = fileContent;

  if (!content.includes(commentLabel)) {
    const assetIndex = content.indexOf('[AssetHotfix]');
    if (assetIndex !== -1) {
      if (preferPrepend) {
        // Insert a dedicated section before the first [AssetHotfix]
        content = `${content.slice(0, assetIndex)}[AssetHotfix]\n${commentLabel}\n${content.slice(assetIndex)}`;
      } else {
        const newlineAfterAsset = content.indexOf('\n', assetIndex);
        const insertAt = newlineAfterAsset === -1 ? content.length : newlineAfterAsset + 1;
        content = content.slice(0, insertAt) + `${commentLabel}\n` + content.slice(insertAt);
      }
    } else {
      content = `${content.trimEnd()}\n[AssetHotfix]\n${commentLabel}\n`;
    }
  }

  const insertPoint = findInsertPoint(content, commentLabel);
  return { content, insertPoint };
}

function normalizeCurveTablePlacement(fileContent: string): string {
  const curveLines = [...fileContent.matchAll(/^\+CurveTable=.*$/gm)].map(m => m[0]);
  if (curveLines.length === 0) return fileContent;

  let content = fileContent.replace(/^\+CurveTable=.*$/gm, '').replace(/^\s*\n/gm, '');
  const ensured = ensureAssetSection(content, CURVE_TABLE_COMMENT, true);
  content = ensured.content;
  const insertPoint = ensured.insertPoint;
  return content.slice(0, insertPoint) + curveLines.join('\n') + '\n' + content.slice(insertPoint);
}

// Function to toggle Straight Bloom
async function toggleStraightBloom() {
  try {
    const iniPath = path.join(__dirname, '../static/hotfixes/DefaultGame.ini');
    const sniperPath = path.join(__dirname, '../responses/sniper.json');
    
    let content = fs.readFileSync(iniPath, 'utf-8');
    const sniperData = JSON.parse(fs.readFileSync(sniperPath, 'utf-8'));
    const sniperSpreadLines = sniperData.lines;
    
    // Check if any sniper lines exist in the INI
    const hasLines = sniperSpreadLines.some((line: string) => content.includes(line));
    
    if (hasLines) {
      // Remove all sniper lines
      sniperSpreadLines.forEach((line: string) => {
        content = content.replace(line + '\n', '').replace(line, '');
      });
      // Clean up extra newlines
      content = content.replace(/\n\n+/g, '\n');
      lastStatusMessage = '\x1b[32m✓ Straight Bloom disabled!\x1b[0m';
    } else {
      const ensured = ensureAssetSection(content, STRAIGHT_BLOOM_COMMENT);
      content = ensured.content;
      const insertPoint = ensured.insertPoint;
      content = content.slice(0, insertPoint) + sniperSpreadLines.join('\n') + '\n' + content.slice(insertPoint);
      lastStatusMessage = '\x1b[32m✓ Straight Bloom enabled!\x1b[0m';
    }
    
    fs.writeFileSync(iniPath, content);
  } catch (error) {
    lastStatusMessage = `\x1b[31m✗ Failed to toggle Straight Bloom: ${(error instanceof Error ? error.message : String(error))}\x1b[0m`;
  }
}

// Function to import CurveTables from DefaultGame.ini
async function importCurveTables() {
  try {
    const importsDir = path.join(__dirname, '../exports/DefaultGame');
    
    // Check if imports directory exists
    if (!fs.existsSync(importsDir)) {
      lastStatusMessage = '\x1b[33m\u2717 No DefaultGame.ini found in exports folder. Please export data first.\x1b[0m';
      return;
    }
    
    // Look for any .ini files in imports folder
    const files = fs.readdirSync(importsDir);
    const iniFiles = files.filter(file => {
      const stats = fs.statSync(path.join(importsDir, file));
      return stats.isFile() && file.toLowerCase().endsWith('.ini');
    });
    
    if (iniFiles.length === 0) {
      lastStatusMessage = '\x1b[33m✗ No .ini files found in exports/DefaultGame folder.\x1b[0m';
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
      validate: (value: string) => {
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
      validate: (value: string) => ['y', 'Y', 'n', 'N'].includes(value) ? true : 'Please enter Y or N'
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

    // Ensure CurveTables section exists and normalize placement before importing
    const ensuredCurve = ensureAssetSection(content, CURVE_TABLE_COMMENT, true);
    content = normalizeCurveTablePlacement(ensuredCurve.content);
    
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
          const insertPoint = findInsertPoint(content, CURVE_TABLE_COMMENT);
          content = content.slice(0, insertPoint) + fullLine + '\n' + content.slice(insertPoint);
          enabledCount++;
          
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
            .pop() ?? '' // Get last part after final dot
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
          const insertPoint = findInsertPoint(content, CURVE_TABLE_COMMENT);
          content = content.slice(0, insertPoint) + fullLine + '\n' + content.slice(insertPoint);
          customsAdded++;
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
      validate: (value: string) => ['y', 'Y', 'n', 'N'].includes(value) ? true : 'Please enter Y or N'
    });
    
    if (deleteResponse.delete && deleteResponse.delete.toUpperCase() === 'Y') {
      // Ask for confirmation before deleting
      const confirmResponse = await prompts({
        type: 'text',
        name: 'confirm',
        message: '\x1b[31mAre you sure you want to delete this file? (Y/N):\x1b[0m',
        validate: (value: string) => ['y', 'Y', 'n', 'N'].includes(value) ? true : 'Please enter Y or N'
      });
      
      if (confirmResponse.confirm && confirmResponse.confirm.toUpperCase() === 'Y') {
        fs.unlinkSync(importFilePath);
        lastStatusMessage += ' \x1b[90m(File deleted)\x1b[0m';
      } else {
        lastStatusMessage += ' \x1b[90m(File kept)\x1b[0m';
      }
    }
    
  } catch (error) {
    lastStatusMessage = `\x1b[31m✗ Failed to import curvetables: ${(error instanceof Error ? error.message : String(error))}\x1b[0m`;
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
    console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on Port ${PORT}`);
    
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
      console.log('\x1b[31m  Error loading profiles: ' + (err instanceof Error ? err.message : String(err)) + '\x1b[0m\n');
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

// Helper function to copy directory recursively
function copyDirRecursive(src: string, dest: string): void {
  if (!fs.existsSync(src)) return;
  if (!fs.existsSync(dest)) {
    fs.mkdirSync(dest, { recursive: true });
  }
  
  const items = fs.readdirSync(src);
  items.forEach(item => {
    const srcPath = path.join(src, item);
    const destPath = path.join(dest, item);
    const stat = fs.statSync(srcPath);
    
    if (stat.isDirectory()) {
      copyDirRecursive(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  });
}

// Function to export data
async function exportData() {
  try {
    const exportsDir = path.join(__dirname, '../exports');
    const defaultGameExportDir = path.join(exportsDir, 'DefaultGame');
    const profilesExportDir = path.join(exportsDir, 'Profiles');
    const clientSettingsExportDir = path.join(exportsDir, 'ClientSettings');
    
    // Check if any export directories already exist with content
    const hasExistingData = (
      (fs.existsSync(defaultGameExportDir) && fs.readdirSync(defaultGameExportDir).length > 0) ||
      (fs.existsSync(profilesExportDir) && fs.readdirSync(profilesExportDir).length > 0) ||
      (fs.existsSync(clientSettingsExportDir) && fs.readdirSync(clientSettingsExportDir).length > 0)
    );
    
    if (hasExistingData) {
      console.clear();
      const terminalWidth = process.stdout.columns || 80;
      const lines = logo.split('\n');
      const centeredLogo = lines.map(line => {
        const padding = Math.max(0, Math.floor((terminalWidth - line.replace(/\x1b\[[0-9;]*m/g, '').length) / 2));
        return ' '.repeat(padding) + line;
      }).join('\n');
      
      console.log(centeredLogo);
      console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on Port ${PORT}`);
      console.log('');
      console.log('\x1b[33m⚠  Exported data already exists!\x1b[0m');
      console.log('\x1b[33mPlease clear exported data before exporting again.\x1b[0m');
      console.log('');
      
      await prompts({
        type: 'text',
        name: 'continue',
        message: '\x1b[90mPress Enter to continue...\x1b[0m'
      });
      
      return;
    }
    
    // Create export directories if they don't exist
    fs.mkdirSync(defaultGameExportDir, { recursive: true });
    fs.mkdirSync(profilesExportDir, { recursive: true });
    fs.mkdirSync(clientSettingsExportDir, { recursive: true });
    
    console.clear();
    const terminalWidth = process.stdout.columns || 80;
    const lines = logo.split('\n');
    const centeredLogo = lines.map(line => {
      const padding = Math.max(0, Math.floor((terminalWidth - line.replace(/\x1b\[[0-9;]*m/g, '').length) / 2));
      return ' '.repeat(padding) + line;
    }).join('\n');
    
    console.log(centeredLogo);
    console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on Port ${PORT}`);
    console.log('');
    console.log('\x1b[36mExporting data...\x1b[0m');
    
    // Export DefaultGame.ini
    const iniSourcePath = path.join(__dirname, '../static/hotfixes/DefaultGame.ini');
    const iniDestPath = path.join(defaultGameExportDir, 'DefaultGame.ini');
    if (fs.existsSync(iniSourcePath)) {
      fs.copyFileSync(iniSourcePath, iniDestPath);
      console.log(`\x1b[32m✓\x1b[0m DefaultGame.ini exported`);
    } else {
      console.log(`\x1b[33m✗\x1b[0m DefaultGame.ini not found`);
    }
    
    // Export Profiles folders
    const profilesSourceDir = path.join(__dirname, '../static/profiles');
    if (fs.existsSync(profilesSourceDir)) {
      const profileItems = fs.readdirSync(profilesSourceDir);
      let profileCount = 0;
      profileItems.forEach(item => {
        const itemPath = path.join(profilesSourceDir, item);
        const stat = fs.statSync(itemPath);
        if (stat.isDirectory()) {
          copyDirRecursive(itemPath, path.join(profilesExportDir, item));
          profileCount++;
        }
      });
      console.log(`\x1b[32m✓\x1b[0m ${profileCount} profile folder(s) exported`);
    } else {
      console.log(`\x1b[33m✗\x1b[0m Profiles source directory not found`);
    }
    
    // Export ClientSettings folders
    const clientSettingsSourceDir = path.join(__dirname, '../static/ClientSettings');
    if (fs.existsSync(clientSettingsSourceDir)) {
      const clientItems = fs.readdirSync(clientSettingsSourceDir);
      let clientCount = 0;
      clientItems.forEach(item => {
        const itemPath = path.join(clientSettingsSourceDir, item);
        const stat = fs.statSync(itemPath);
        if (stat.isDirectory()) {
          copyDirRecursive(itemPath, path.join(clientSettingsExportDir, item));
          clientCount++;
        }
      });
      console.log(`\x1b[32m✓\x1b[0m ${clientCount} ClientSettings folder(s) exported`);
    } else {
      console.log(`\x1b[33m✗\x1b[0m ClientSettings source directory not found`);
    }
    
    console.log('');
    lastStatusMessage = '\x1b[32m✓ Data exported successfully!\x1b[0m';
    
    await prompts({
      type: 'text',
      name: 'continue',
      message: '\x1b[90mPress Enter to continue...\x1b[0m'
    });
    
  } catch (error) {
    lastStatusMessage = `\x1b[31m✗ Export failed: ${(error instanceof Error ? error.message : String(error))}\\x1b[0m`;
    await prompts({
      type: 'text',
      name: 'continue',
      message: '\x1b[90mPress Enter to continue...\x1b[0m'
    });
  }
}

// Function to import data
async function importData() {
  try {
    const exportsDir = path.join(__dirname, '../exports');
    const defaultGameExportDir = path.join(exportsDir, 'DefaultGame');
    const profilesExportDir = path.join(exportsDir, 'Profiles');
    const clientSettingsExportDir = path.join(exportsDir, 'ClientSettings');
    
    console.clear();
    const terminalWidth = process.stdout.columns || 80;
    const lines = logo.split('\n');
    const centeredLogo = lines.map(line => {
      const padding = Math.max(0, Math.floor((terminalWidth - line.replace(/\x1b\[[0-9;]*m/g, '').length) / 2));
      return ' '.repeat(padding) + line;
    }).join('\n');
    
    console.log(centeredLogo);
    console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on Port ${PORT}`);
    console.log('');
    
    // Confirm import
    const confirmResponse = await prompts({
      type: 'text',
      name: 'confirm',
      message: '\x1b[31mAre you sure you want to import data? This will overwrite existing files. (Y/N):\x1b[0m',
      validate: (value: string) => ['y', 'Y', 'n', 'N'].includes(value) ? true : 'Please enter Y or N'
    });
    
    if (!confirmResponse.confirm || confirmResponse.confirm.toUpperCase() !== 'Y') {
      lastStatusMessage = '\x1b[33mImport cancelled.\x1b[0m';
      return;
    }
    
    console.log('\x1b[36mImporting data...\x1b[0m');
    
    // Import Profiles folders
    const profilesDestDir = path.join(__dirname, '../static/profiles');
    if (fs.existsSync(profilesExportDir)) {
      const profileItems = fs.readdirSync(profilesExportDir);
      let profileCount = 0;
      profileItems.forEach(item => {
        const itemPath = path.join(profilesExportDir, item);
        const stat = fs.statSync(itemPath);
        if (stat.isDirectory()) {
          copyDirRecursive(itemPath, path.join(profilesDestDir, item));
          profileCount++;
        }
      });
      console.log(`\x1b[32m✓\x1b[0m ${profileCount} profile folder(s) imported`);
    } else {
      console.log(`\x1b[33m✗\x1b[0m Profiles not found in exports`);
    }
    
    // Import ClientSettings folders
    const clientSettingsDestDir = path.join(__dirname, '../static/ClientSettings');
    if (fs.existsSync(clientSettingsExportDir)) {
      const clientItems = fs.readdirSync(clientSettingsExportDir);
      let clientCount = 0;
      clientItems.forEach(item => {
        const itemPath = path.join(clientSettingsExportDir, item);
        const stat = fs.statSync(itemPath);
        if (stat.isDirectory()) {
          copyDirRecursive(itemPath, path.join(clientSettingsDestDir, item));
          clientCount++;
        }
      });
      console.log(`\x1b[32m✓\x1b[0m ${clientCount} ClientSettings folder(s) imported`);
    } else {
      console.log(`\x1b[33m✗\x1b[0m ClientSettings not found in exports`);
    }
    
    console.log('');
    lastStatusMessage = '\x1b[32m✓ Data imported successfully!\x1b[0m';
    
    await prompts({
      type: 'text',
      name: 'continue',
      message: '\x1b[90mPress Enter to continue...\x1b[0m'
    });
    
  } catch (error) {
    lastStatusMessage = `\x1b[31m✗ Import failed: ${(error instanceof Error ? error.message : String(error))}\\x1b[0m`;
    await prompts({
      type: 'text',
      name: 'continue',
      message: '\x1b[90mPress Enter to continue...\x1b[0m'
    });
  }
}

// Helper function to delete directory recursively
function deleteDirRecursive(dirPath: string): void {
  if (!fs.existsSync(dirPath)) return;
  
  const items = fs.readdirSync(dirPath);
  items.forEach(item => {
    const itemPath = path.join(dirPath, item);
    const stat = fs.statSync(itemPath);
    
    if (stat.isDirectory()) {
      deleteDirRecursive(itemPath);
    } else {
      fs.unlinkSync(itemPath);
    }
  });
  
  fs.rmdirSync(dirPath);
}

// Function to clear exported data
async function clearExportedData() {
  try {
    const exportsDir = path.join(__dirname, '../exports');
    
    console.clear();
    const terminalWidth = process.stdout.columns || 80;
    const lines = logo.split('\n');
    const centeredLogo = lines.map(line => {
      const padding = Math.max(0, Math.floor((terminalWidth - line.replace(/\x1b\[[0-9;]*m/g, '').length) / 2));
      return ' '.repeat(padding) + line;
    }).join('\n');
    
    console.log(centeredLogo);
    console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on Port ${PORT}`);
    console.log('');
    
    // Confirm clear
    const confirmResponse = await prompts({
      type: 'text',
      name: 'confirm',
      message: '\x1b[31mAre you sure you want to clear all exported data? (Y/N):\x1b[0m',
      validate: (value: string) => ['y', 'Y', 'n', 'N'].includes(value) ? true : 'Please enter Y or N'
    });
    
    if (!confirmResponse.confirm || confirmResponse.confirm.toUpperCase() !== 'Y') {
      lastStatusMessage = '\x1b[33mClear cancelled.\x1b[0m';
      return;
    }
    
    console.log('\x1b[32m✓\x1b[0m\x1b[31m Clearing exported data...\x1b[0m');
    
    if (fs.existsSync(exportsDir)) {
      deleteDirRecursive(exportsDir);
      console.log(`\x1b[32m✓\x1b[0m Exported data cleared`);
    } else {
      console.log(`\x1b[33m✗\x1b[0m No exported data found`);
    }
    
    console.log('');
    lastStatusMessage = '\x1b[32m✓ Exported data cleared successfully!\x1b[0m';
    
    await prompts({
      type: 'text',
      name: 'continue',
      message: '\x1b[90mPress Enter to continue...\x1b[0m'
    });
    
  } catch (error) {
    lastStatusMessage = `\x1b[31m✗ Clear failed: ${(error instanceof Error ? error.message : String(error))}\\x1b[0m`;
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
      console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on Port ${PORT}`);
      
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
      console.log('\x1b[32m(3)\x1b[0m Manage Data');
      console.log('\x1b[32m(BACK)\x1b[0m Return to main menu');
      console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
      
      const response = await prompts({
        type: 'text',
        name: 'choice',
        message: '\x1b[32mSelect an option (1/2/3/BACK):\x1b[0m',
        validate: (value: string) => {
          if (value.toLowerCase() === 'back') return true;
          const num = parseInt(value);
          return (num === 1 || num === 2 || num === 3) ? true : 'Please enter 1, 2, 3, or BACK';
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
        case '3':
          // Manage Data
          await manageDataMenu();
          lastStatusMessage = '';
          break;
        default:
          break;
      }
      
    } catch (error) {
      lastStatusMessage = `\x1b[31m✗ Failed to update settings: ${(error instanceof Error ? error.message : String(error))}\x1b[0m`;
      continueLoop = false;
    }
  }
}

// Function to manage data (export, import, clear)
async function manageDataMenu() {
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
      console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on Port ${PORT}`);
      
      console.log('\n\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
      console.log('\x1b[36m                     Manage Data\x1b[0m');
      console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
      console.log('\x1b[32m(1)\x1b[0m Export Data');
      console.log('\x1b[32m(2)\x1b[0m Import Data');
      console.log('\x1b[32m(3)\x1b[0m Clear Exported Data');
      console.log('\x1b[32m(BACK)\x1b[0m Return to other settings');
      console.log('\x1b[36m═══════════════════════════════════════════════════════════\x1b[0m');
      
      const response = await prompts({
        type: 'text',
        name: 'choice',
        message: '\x1b[32mSelect an option (1/2/3/BACK):\x1b[0m',
        validate: (value: string) => {
          if (value.toLowerCase() === 'back') return true;
          const num = parseInt(value);
          return (num === 1 || num === 2 || num === 3) ? true : 'Please enter 1, 2, 3, or BACK';
        }
      });
      
      if (!response.choice || response.choice.toLowerCase() === 'back') {
        continueLoop = false;
        continue;
      }
      
      const choice = response.choice;
      
      switch (choice) {
        case '1':
          // Export Data
          await exportData();
          break;
        case '2':
          // Import Data
          await importData();
          break;
        case '3':
          // Clear Exported Data
          await clearExportedData();
          break;
        default:
          break;
      }
      
    } catch (error) {
      console.log(`\x1b[31m✗ Error: ${(error instanceof Error ? error.message : String(error))}\x1b[0m`);
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
    console.log(`\x1b[36m[BACKEND]\x1b[0m ATLAS started on Port ${PORT}`);
    
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
    content = normalizeCurveTablePlacement(content);
    
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
      validate: (value: string) => (['1', '2', '3', '4', '5', '6'].includes(value) || value.toLowerCase() === 'back') ? true : 'Please enter 1, 2, 3, 4, 5, 6, or BACK'
    });
    
    const action = actionResponse.action?.toLowerCase();

    if (!action || action === 'back') {
      lastStatusMessage = '';
      continueLoop = false;
      continue;
    }

    if (action === '4') {
      const nameResponse = await prompts({
        type: 'text',
        name: 'name',
        message: '\x1b[32mEnter a name for the custom CurveTable:\x1b[0m',
        validate: (value: string) => value.trim().length > 0 ? true : 'Name cannot be empty'
      });

      if (!nameResponse.name) {
        lastStatusMessage = '\x1b[33mCancelled.\x1b[0m';
        continue;
      }

      let isStatic = false;
      let staticValue: string | undefined;
      let multiLine = false;
      let multiLines: string[] = [];

      const staticResponse = await prompts({
        type: 'text',
        name: 'isStatic',
        message: `\x1b[32mIs this custom CurveTable static? (Y/N):\x1b[0m`,
        validate: (value: string) => ['y','Y','n','N'].includes(value) ? true : 'Please enter Y or N'
      });
      isStatic = staticResponse.isStatic && staticResponse.isStatic.toUpperCase() === 'Y';

      let curveString = '';
      let key = '';
      let value = '';
      let path_part = '';
      const pasteResponse = await prompts({
        type: 'text',
        name: 'block',
        message: '\x1b[32mPaste CurveTable line(s) (comma or newline separated):\x1b[0m'
      });

      const rawBlock = pasteResponse.block || '';
      let parsedLines = rawBlock.split(/[\r\n,]+/).map((l: string) => l.trim()).filter(Boolean);
      // Fallback: if lines were pasted with no separators, split on repeated +CurveTable markers
      if (parsedLines.length <= 1 && rawBlock.includes('+CurveTable=')) {
        const byMarker = rawBlock.split(/(?=\+CurveTable=)/).map((l: string) => l.trim()).filter(Boolean);
        if (byMarker.length > parsedLines.length) parsedLines = byMarker;
      }

      if (parsedLines.length === 0) {
        lastStatusMessage = '\x1b[33mCancelled.\x1b[0m';
        continue;
      }

      multiLine = parsedLines.length > 1;
      if (multiLine) {
        multiLines = parsedLines;
        curveString = multiLines.join('\n');
      } else {
        curveString = parsedLines[0];
      }

      const match = parsedLines[0].match(/^\+CurveTable=(.+?);RowUpdate;(.+?);(\d+);(.+)$/);
      if (!match) {
        lastStatusMessage = '\x1b[31m✗ Invalid curvetable format. Expected: +CurveTable=/path;RowUpdate;key;0;value\x1b[0m';
        continue;
      }

      [, path_part, key, , value] = match;
      if (isStatic) staticValue = value;
      
      // Find next ID
      const maxId = Math.max(...Object.keys(curves).map(k => parseInt(k)).filter(n => !isNaN(n)), 0);
      const newId = String(maxId + 1);
      
      // Add to curves.json
      curves[newId] = {
        name: nameResponse.name,
        key: key,
        value: value,
        pathPart: path_part,
        type: isStatic ? 'static' : 'custom',
        isCustom: true,
        ...(isStatic && staticValue !== undefined ? { staticValue } : {}),
        ...(multiLine && multiLines.length > 0 ? { multiLines } : {})
      };
      
      fs.writeFileSync(curvesPath, JSON.stringify(curves, null, 2));
      
      // Add to INI file under the CurveTables section
      const insertPoint = findInsertPoint(content, CURVE_TABLE_COMMENT);
      content = content.slice(0, insertPoint) + curveString + '\n' + content.slice(insertPoint);
      
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
        validate: (value: string) => ['y', 'Y', 'n', 'N'].includes(value) ? true : 'Please enter Y or N'
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

    // List current CurveTable values without modifying anything
    if (action === '3') {
      const activeCurveRegex = /^\+CurveTable=(.+?);RowUpdate;(.+?);(\d+);(.+)$/gm;
      const activeMatches = [...content.matchAll(activeCurveRegex)];

      console.log('\n\x1b[33mList of CurveTables Enabled:\x1b[0m');
      if (activeMatches.length === 0) {
        console.log('\x1b[90m(no CurveTables found)\x1b[0m');
        await prompts({
          type: 'text',
          name: 'continue',
          message: '\x1b[90mPress Enter to continue...\x1b[0m'
        });
        lastStatusMessage = '';
        continue;
      }

      // Group entries by key to handle multi-line curves
      const entriesMap = new Map<string, any>();
      
      activeMatches.forEach(match => {
        const [, pathPart, key, rowValue, value] = match;
        const curveEntry = Object.values(curves as Record<string, any>).find((c: any) => c.key === key);
        const nameLabel = curveEntry ? curveEntry.name : '';
        const isCustom = !!curveEntry?.isCustom;
        const isMultiLine = !!curveEntry?.multiLines;
        
        // Use key+pathPart as unique identifier for grouping
        const uniqueKey = `${pathPart}:${key}`;
        
        if (!entriesMap.has(uniqueKey)) {
          entriesMap.set(uniqueKey, { 
            pathPart, 
            key, 
            rowValue, 
            value, 
            nameLabel, 
            isCustom,
            isMultiLine,
            lineCount: 1
          });
        } else if (isMultiLine) {
          // For multi-line curves, just increment the count
          entriesMap.get(uniqueKey).lineCount++;
        }
      });

      const entries = Array.from(entriesMap.values());

      entries.forEach((entry, index) => {
        const displayName = entry.nameLabel || entry.key;
        const customTag = entry.isCustom ? ' \x1b[33m[CUSTOM]\x1b[0m' : '';
        console.log(`\x1b[36m(${index + 1})\x1b[0m ${displayName}${customTag}`);
      });
      console.log('\x1b[36m(BACK)\x1b[0m Go back');

      const detailResponse = await prompts({
        type: 'text',
        name: 'detail',
        message: '\x1b[32mChoose a curve to view details:\x1b[0m',
        validate: (value: string) => {
          if (value.toLowerCase() === 'back') return true;
          const num = parseInt(value, 10);
          return num >= 1 && num <= entries.length ? true : `Enter 1-${entries.length} or BACK`;
        }
      });

      if (!detailResponse.detail || detailResponse.detail.toLowerCase() === 'back') {
        lastStatusMessage = '';
        continue;
      }

      const idx = parseInt(detailResponse.detail, 10) - 1;
      const entry = entries[idx];

      console.log('\n\x1b[33mCurveTable Details:\x1b[0m');
      
      // If it's a multi-line curve, show each line separately with full details
      if (entry.isMultiLine && entry.lineCount > 1) {
        // Find and display all matching lines
        const allLinesRegex = new RegExp(`^\\+CurveTable=${entry.pathPart.replace(/[.*+?^${}()|[\]\\]/g, '\\\\$&')};RowUpdate;${entry.key.replace(/[.*+?^${}()|[\]\\]/g, '\\\\$&')};(\\d+);(.+)$`, 'gm');
        const allMatches = [...content.matchAll(allLinesRegex)];
        allMatches.forEach((match, i) => {
          if (i > 0) console.log(''); // Add blank line between entries
          console.log(`\x1b[36mNAME \x1b[0m: ${entry.nameLabel} (${i + 1})`);
          console.log(`\x1b[32mKEY  \x1b[0m: ${entry.key}`);
          console.log(`\x1b[35mPATH \x1b[0m: ${entry.pathPart}`);
          console.log(`\x1b[33mVALUE\x1b[0m: ${match[2]}`);
        });
      } else {
        if (entry.nameLabel) {
          console.log(`\x1b[36mNAME \x1b[0m: ${entry.nameLabel}`);
        }
        console.log(`\x1b[32mKEY  \x1b[0m: ${entry.key}`);
        console.log(`\x1b[35mPATH \x1b[0m: ${entry.pathPart}`);
        console.log(`\x1b[33mVALUE\x1b[0m: ${entry.value}`);
      }

      await prompts({
        type: 'text',
        name: 'continue',
        message: '\x1b[90mPress Enter to continue...\x1b[0m'
      });

      lastStatusMessage = '';
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
      validate: (value: string) => {
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
      const regex = new RegExp(`^\\+CurveTable=.*;RowUpdate;${escapedKey};\\d+;.*$`, 'gm');
      const matches = content.match(regex);

      if (matches && matches.length > 0) {
        // Store all deleted lines for restoration
        selectedCurve.deletedLine = matches.join('\n');
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
      // Add/update: handle single-line and multi-line curves, respecting static curves without prompting
      if (selectedCurve.multiLines && selectedCurve.multiLines.length > 0) {
        let linesToUse = selectedCurve.multiLines as string[];

        // Allow updating multi-line content for non-static curves
        if (selectedCurve.type !== 'static') {
          const blockResponse = await prompts({
            type: 'text',
            name: 'block',
            message: '\x1b[32mPaste new CurveTable lines (comma or newline separated, leave empty to reuse stored):\x1b[0m'
          });
          if (blockResponse.block && blockResponse.block.trim()) {
            let parsed = blockResponse.block
              .split(/[\r\n,]+/)
              .map((l: string) => l.trim())
              .filter(Boolean);

            if (parsed.length <= 1 && blockResponse.block.includes('+CurveTable=')) {
              const byMarker = blockResponse.block.split(/(?=\+CurveTable=)/).map((l: string) => l.trim()).filter(Boolean);
              if (byMarker.length > parsed.length) parsed = byMarker;
            }

            linesToUse = parsed;

            const firstMatch = linesToUse[0]?.match(/^\+CurveTable=(.+?);RowUpdate;(.+?);(\d+);(.+)$/);
            if (firstMatch) {
              selectedCurve.pathPart = firstMatch[1];
              selectedCurve.key = firstMatch[2];
              selectedCurve.value = firstMatch[4];
            }
            selectedCurve.multiLines = linesToUse;
            curves[curveResponse.curve] = selectedCurve;
            fs.writeFileSync(curvesPath, JSON.stringify(curves, null, 2));
          }
        }

        const escapedKey = selectedCurve.key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const regex = new RegExp(`^\\+CurveTable=.*;RowUpdate;${escapedKey};\\d+;.*$`, 'gm');
        content = content.replace(regex, '').replace(/^\s*\n/gm, '');

        const insertPoint = findInsertPoint(content, CURVE_TABLE_COMMENT);
        content = content.slice(0, insertPoint) + linesToUse.join('\n') + '\n' + content.slice(insertPoint);

        // Clear deleted state if it was previously deleted
        if (selectedCurve.isDeleted) {
          delete selectedCurve.isDeleted;
          delete selectedCurve.deletedLine;
          curves[curveResponse.curve] = selectedCurve;
          fs.writeFileSync(curvesPath, JSON.stringify(curves, null, 2));
        }

        lastStatusMessage = '\x1b[32m✓ CurveTable added/updated successfully!\x1b[0m';
      } else {
        // Single-line path (existing behavior) with static-value shortcut
        let newValue: string;
        if (selectedCurve.type === 'static') {
          newValue = selectedCurve.staticValue;
          console.log(`\x1b[32mUsing static value: ${newValue}\x1b[0m`);
        } else {
          const valueResponse = await prompts({
            type: 'text',
            name: 'value',
            message: `\x1b[32mEnter new value for ${selectedCurve.name}:\x1b[0m`,
            validate: (value: string) => !isNaN(Number(value)) ? true : 'Please enter a valid number'
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
          const insertPoint = findInsertPoint(content, CURVE_TABLE_COMMENT);
          content = content.slice(0, insertPoint) + curveLine + '\n' + content.slice(insertPoint);
        }

        // Clear deleted state if it was previously deleted and restore all deleted lines
        if (selectedCurve.isDeleted) {
          if (selectedCurve.deletedLine) {
            const linesToRestore = selectedCurve.deletedLine.split('\n');
            const insertPoint = findInsertPoint(content, CURVE_TABLE_COMMENT);
            content = content.slice(0, insertPoint) + linesToRestore.join('\n') + '\n' + content.slice(insertPoint);
          }
          delete selectedCurve.isDeleted;
          delete selectedCurve.deletedLine;
          curves[curveResponse.curve] = selectedCurve;
          fs.writeFileSync(curvesPath, JSON.stringify(curves, null, 2));
        }

        lastStatusMessage = '\x1b[32m✓ CurveTable added/updated successfully!\x1b[0m';
      }
    }
    
      fs.writeFileSync(iniPath, content);
      
      // Continue loop to show submenu again after add/delete
      continue;
    } catch (error) {
      lastStatusMessage = `\x1b[31m✗ Failed to modify CurveTables: ${(error instanceof Error ? error.message : String(error))}\x1b[0m`;
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
        backup.curveTableLines.forEach((line: string) => {
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
    lastStatusMessage = `\x1b[31m✗ Failed to toggle modifications: ${(error instanceof Error ? error.message : String(error))}\x1b[0m`;
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
  const hasUncommentedSniperLines = sniperSpreadLines.some((line: string) => content.includes(line) && !content.includes(`;${line}`));
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
    validate: (value: string) => {
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
  console.clear();
  
  // Display logo first
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
  console.log(''); // Empty line for spacing
  
  try {
    // Read local version
    const packagePath = path.join(__dirname, '../package.json');
    const localPackage = JSON.parse(fs.readFileSync(packagePath, 'utf-8'));
    const currentVersion = localPackage.version || '0.0.0';
    
    // Wait a moment for server startup messages to display first
    await new Promise(resolve => setTimeout(resolve, 500));
    
    const updateAvailable = await CheckForUpdate.checkForUpdate(currentVersion);
    if (updateAvailable) {
      // Get latest version from GitHub
      const response = await fetch(`https://raw.githubusercontent.com/cipherfps/ATLAS-Backend/main/package.json?t=${Date.now()}`);
      const remotePackage = await response.json();
      const latestVersion = remotePackage.version;

      const downloadUrl = 'https://github.com/cipherfps/ATLAS-Backend/releases/latest';
      console.log(`\x1b[92m[UPDATE]\x1b[0m New version available: v${latestVersion} (current: v${currentVersion})`);
      console.log(`\x1b[33mPlease update before continuing.\x1b[0m`);
      console.log(`\x1b[36mDownload here: ${downloadUrl}\x1b[0m`);
      console.log("\x1b[90mPress Enter to continue...\x1b[0m");
      if (process.stdin.isTTY) {
        // Remove all previous listeners to avoid stacking
        process.stdin.removeAllListeners('data');
        process.stdin.setRawMode(true);
        process.stdin.resume();
        process.stdin.once('data', () => {
          process.stdin.setRawMode(false);
          process.stdin.pause();
          process.exit(0);
        });
        // Prevent function from continuing
        return false;
      } else {
        // If not a TTY, print message and do not exit automatically
        console.log("\x1b[31mCannot detect user input in this terminal. Please close the window manually after updating.\x1b[0m");
        return false;
      }
    } else {
      console.log(`\x1b[32m✓\x1b[0m Backend is up to date (v${currentVersion})`);
      console.log(`\x1b[90mContinuing in 1 second...\x1b[0m`);
      await new Promise(resolve => setTimeout(resolve, 1000));
      return true;
    }
  } catch (error) {
    console.log(`\x1b[31m✗\x1b[0m Update check failed. Continuing...`);
    await new Promise(resolve => setTimeout(resolve, 2000));
    return true;
  }
}

// Start the server with Bun
const startServer = async () => {
  const canContinue = await checkForUpdates();
  if (!canContinue) return;
  // Now clear and start the server
  console.clear();
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
