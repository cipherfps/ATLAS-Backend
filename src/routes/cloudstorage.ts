import { app } from "..";
import crypto from "crypto";
import fs from "node:fs";
import path from "node:path";
import getVersion from "../utils/handlers/getVersion";
import { atlasDataPath, atlasInstallPath } from "../config/paths";
import { readConfig } from "../config/config";
// Cache for hotfix files to avoid repeated disk reads
const hotfixCache = new Map<
  string,
  { content: string; mtimeMs: number; size: number }
>();

const TEXT_HOTFIX_SECTION = "[/Script/FortniteGame.FortTextHotfixConfig]";
const TEXT_HOTFIX_MIGRATION_ID = "atlas_text_hotfix_v2";
const TEXT_HOTFIX_MIGRATION_MARKER = ".atlas_text_hotfix_migration";
const ATLAS_TEXT_REPLACEMENTS = [
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="9F28701D47C7B91B048FEBA378ADDEAE", NativeString="Epic Games", LocalizedStrings=(("en","ATLAS")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="LoadingScreen", Key="Connecting", NativeString="CONNECTING", LocalizedStrings=(("en","CONNECTING TO ATLAS")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="FortLoginStatus", Key="LoggingIn", NativeString="Logging In...", LocalizedStrings=(("en","Logging Into ATLAS...")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="OnlineAccount", Key="DoQosPingTests", NativeString="Checking connection to datacenters...", LocalizedStrings=(("en","Checking connection to ATLAS...")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="37020CCD402F073607D9D4A9561EF035", NativeString="PLAY", LocalizedStrings=(("en","Play ATLAS")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="C8C6606D4ED4B816D4A358A42DFBDD59", NativeString="PLAY", LocalizedStrings=(("en","Play ATLAS")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="03875FFD49212D2F37B01788C09086B5", NativeString="Quit", LocalizedStrings=(("en","Quit ATLAS")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="1D20854C403FDD474AE7C8B929815DA2", NativeString="Quit", LocalizedStrings=(("en","Quit ATLAS")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="1FB7052F40BE8B647B5CA5A362BE8F21", NativeString="Quit", LocalizedStrings=(("en","Quit ATLAS")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="2E42C9FB4F551A859C05BF99F7E36FB1", NativeString="Quit", LocalizedStrings=(("en","Quit ATLAS")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="370415344EEEA09D8C01A48F4B8148D7", NativeString="Quit", LocalizedStrings=(("en","Quit ATLAS")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="", Key="538BD1FD46BCEFA4813E2FAFAA07E1A2", NativeString="Quit", LocalizedStrings=(("en","Quit ATLAS")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="FortOnlineAccount", Key="CreatingParty", NativeString="Creating party...", LocalizedStrings=(("en","Welcome to ATLAS")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="PartyContext", Key="BattleRoyaleInLobby", NativeString="Battle Royale - In Lobby", LocalizedStrings=(("en","ATLAS - Lobby")))',
  '+TextReplacements=(Category=Game, bIsMinimalPatch=True, Namespace="OnlineAccount", Key="TokenExpired", NativeString="Login Expired or Logged In Elsewhere", LocalizedStrings=(("en","Backend Restarted... Restart your game")))',
] as const;

const REMIX_QUAIL_FRONTEND_PLAYLIST =
  "+FrontEndPlaylistData=(PlaylistName=Playlist_Quail, PlaylistAccess=(bEnabled=True, bIsDefaultPlaylist=true, bVisibleWhenDisabled=false, bDisplayAsNew=false, CategoryIndex=0, bDisplayAsLimitedTime=false, DisplayPriority=5))";

function getConfiguredRemixStage(): number {
  const rawConfig = readConfig();
  const parsedStage = parseInt(String(rawConfig.RemixStage ?? ""), 10);
  if (Number.isFinite(parsedStage)) {
    return Math.max(1, Math.min(4, parsedStage));
  }

  return String(rawConfig.Season32Timeline ?? "remix").toLowerCase() === "base"
    ? 1
    : 4;
}

function insertFrontEndPlaylistData(defaultGameIni: string, playlistLine: string): string {
  if (defaultGameIni.includes(playlistLine)) {
    return defaultGameIni;
  }

  const newline = defaultGameIni.includes("\r\n") ? "\r\n" : "\n";
  const lines = defaultGameIni.split(/\r?\n/);
  const clearArrayIndex = lines.findIndex((line) => line.trim() === "!FrontEndPlaylistData=ClearArray");
  if (clearArrayIndex === -1) {
    return `${defaultGameIni}${defaultGameIni.endsWith(newline) ? "" : newline}${playlistLine}${newline}`;
  }

  let insertIndex = clearArrayIndex + 1;
  while (
    insertIndex < lines.length &&
    lines[insertIndex].trim().startsWith("+FrontEndPlaylistData=")
  ) {
    insertIndex += 1;
  }

  lines.splice(insertIndex, 0, playlistLine);
  return lines.join(newline);
}

function getBackendVersion(): string {
  if (process.env.npm_package_version) {
    return process.env.npm_package_version;
  }

  try {
    const packageJsonPath = atlasInstallPath("package.json");
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, "utf8")) as {
      version?: string;
    };

    if (packageJson.version) {
      return packageJson.version;
    }
  } catch {
    // Fall through to default below.
  }

  return "dev";
}

function normalizeAtlasTextHotfixSection(defaultGameIni: string): string {
  const newline = defaultGameIni.includes("\r\n") ? "\r\n" : "\n";
  const hadTrailingNewline = /\r?\n$/.test(defaultGameIni);
  let lines = defaultGameIni.split(/\r?\n/);

  const sectionRanges: Array<{ start: number; end: number }> = [];
  const existingSectionLines: string[] = [];

  for (let i = 0; i < lines.length; i++) {
    if (lines[i].trim() !== TEXT_HOTFIX_SECTION) continue;

    const start = i;
    i++;

    while (i < lines.length && !/^\[[^\r\n\]]+\]$/.test(lines[i].trim())) {
      existingSectionLines.push(lines[i].trimEnd());
      i++;
    }

    sectionRanges.push({ start, end: i });
    i--;
  }

  if (sectionRanges.length > 0) {
    const keptLines: string[] = [];
    let rangeIndex = 0;

    for (let i = 0; i < lines.length; ) {
      const currentRange = sectionRanges[rangeIndex];
      if (currentRange && i === currentRange.start) {
        i = currentRange.end;
        rangeIndex++;
        continue;
      }

      keptLines.push(lines[i]);
      i++;
    }

    lines = keptLines;
  }

  const mergedSectionLines: string[] = [];
  const seenSectionLine = new Set<string>();
  const addUniqueSectionLine = (line: string) => {
    if (!line) return;
    if (seenSectionLine.has(line)) return;
    seenSectionLine.add(line);
    mergedSectionLines.push(line);
  };

  for (const line of existingSectionLines) addUniqueSectionLine(line);
  for (const line of ATLAS_TEXT_REPLACEMENTS) addUniqueSectionLine(line);

  const sectionBlockLines = [TEXT_HOTFIX_SECTION, ...mergedSectionLines];
  const firstAssetHotfixIndex = lines.findIndex(
    (line) => line.trim() === "[AssetHotfix]"
  );

  let resultLines: string[];
  if (firstAssetHotfixIndex === -1) {
    resultLines = [...lines, ...sectionBlockLines];
  } else {
    resultLines = [
      ...lines.slice(0, firstAssetHotfixIndex),
      ...sectionBlockLines,
      ...lines.slice(firstAssetHotfixIndex),
    ];
  }

  let output = resultLines.join(newline);
  if (hadTrailingNewline && !output.endsWith(newline)) {
    output += newline;
  }

  return output;
}

function ensureAtlasTextHotfixInFile(filePath: string): void {
  try {
    if (!fs.existsSync(filePath)) return;

    const original = fs.readFileSync(filePath, "utf8");
    const patched = normalizeAtlasTextHotfixSection(original);

    if (patched !== original) {
      fs.writeFileSync(filePath, patched, "utf8");
    }
  } catch (err) {
    console.error(`Failed to apply text hotfix migration for ${filePath}:`, err);
  }
}

function runAtlasTextHotfixMigration(): void {
  const hotfixesDir = atlasDataPath("static", "hotfixes");
  const markerPath = path.join(hotfixesDir, TEXT_HOTFIX_MIGRATION_MARKER);
  const migrationToken = `${TEXT_HOTFIX_MIGRATION_ID}@${getBackendVersion()}`;

  try {
    if (fs.existsSync(markerPath)) {
      const existingToken = fs.readFileSync(markerPath, "utf8").trim();
      if (existingToken === migrationToken) {
        return;
      }
    }
  } catch (err) {
    console.error("Failed reading text hotfix migration marker:", err);
  }

  ensureAtlasTextHotfixInFile(path.join(hotfixesDir, "DefaultGame.ini"));
  ensureAtlasTextHotfixInFile(
    path.join(hotfixesDir, "DefaultGame Template", "DefaultGame.ini")
  );

  try {
    fs.writeFileSync(markerPath, `${migrationToken}\n`, "utf8");
  } catch (err) {
    console.error("Failed writing text hotfix migration marker:", err);
  }
}

export default function () {
  // One-time/idempotent migration per app version.
  runAtlasTextHotfixMigration();

  async function listSystemHotfixFiles() {
    const hotfixesDir = atlasDataPath("static", "hotfixes");
    const csFiles: any[] = [];

    // Note: `static/hotfixes` can contain folders (eg "DefaultGame Template") and local backups.
    // Only expose actual hotfix files to the game to avoid EISDIR crashes.
    const entries = await fs.promises.readdir(hotfixesDir, {
      withFileTypes: true,
    });

    for (const entry of entries) {
      if (!entry.isFile()) continue;

      const file = entry.name;
      // System hotfixes are INI files; ignore backups/strays (eg *.bak).
      if (!file.toLowerCase().endsWith(".ini")) continue;

      const filePath = path.join(hotfixesDir, file);
      try {
        const [f, fileStat] = await Promise.all([
          fs.promises.readFile(filePath),
          fs.promises.stat(filePath),
        ]);

        csFiles.push({
          uniqueFilename: file,
          filename: file,
          hash: crypto.createHash("sha1").update(f as any).digest("hex"),
          hash256: crypto.createHash("sha256").update(f as any).digest("hex"),
          length: fileStat.size,
          contentType: "application/octet-stream",
          uploaded: fileStat.mtime.toISOString(),
          storageType: "S3",
          storageIds: {},
          doNotCache: true,
        });
      } catch (err) {
        console.error(`Error reading hotfix file ${file}:`, err);
      }
    }

    return csFiles;
  }

  app.get("/fortnite/api/cloudstorage/system", async (c) => {
    try {
      const csFiles = await listSystemHotfixFiles();
      return c.json(csFiles);
    } catch (err) {
      console.error("Error fetching system cloudstorage:", err);
      // Be resilient: if something goes wrong, return "no files" instead of failing the client.
      return c.json([]);
    }
  });

  app.get("/fortnite/api/cloudstorage/system/config", async (c) => {
    try {
      const csFiles = await listSystemHotfixFiles();
      return c.json(csFiles);
    } catch (err) {
      console.error("Error fetching system config cloudstorage:", err);
      // Be resilient: if something goes wrong, return "no files" instead of failing the client.
      return c.json([]);
    }
  });

  app.get("/fortnite/api/cloudstorage/system/:file", async (c) => {
    try {
      const version = getVersion(c);
      const fileName = c.req.param("file");
      const filePath = atlasDataPath("static", "hotfixes", fileName);
      
      // Revalidate cache using file metadata so runtime edits are picked up.
      const fileStat = await fs.promises.stat(filePath);

      let fileContent: string;
      const cached = hotfixCache.get(fileName);
      if (
        cached &&
        cached.mtimeMs === fileStat.mtimeMs &&
        cached.size === fileStat.size
      ) {
        fileContent = cached.content;
      } else {
        // Load from disk and refresh cache.
        fileContent = await fs.promises.readFile(filePath, { encoding: "utf8" });
        hotfixCache.set(fileName, {
          content: fileContent,
          mtimeMs: fileStat.mtimeMs,
          size: fileStat.size,
        });
      }

      if (fileName === "DefaultGame.ini") {
        const replacements: {
          [key: number]: { find: string; replace: string };
        } = {
          7.3: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Low, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Low, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          7.4: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_High, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_High, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          8.51: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Med, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Med, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          9.4: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Higher, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Higher, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          9.41: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Higher, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Higher, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          10.4: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Highest, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Highest, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          11.3: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Lowest, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_Lowest, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          12.41: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_High, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Music_High, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
          12.61: {
            find: "+FrontEndPlaylistData=(PlaylistName=Playlist_Fritter_64, PlaylistAccess=(bEnabled=false, CategoryIndex=1, DisplayPriority=-999))",
            replace:
              "+FrontEndPlaylistData=(PlaylistName=Playlist_Fritter_64, PlaylistAccess=(bEnabled=true, CategoryIndex=1, DisplayPriority=-999))",
          },
        };

        const replacement = replacements[version.build];
        if (replacement) {
          fileContent = fileContent.replace(
            replacement.find,
            replacement.replace
          );
        }

        if (version.season === 32 && getConfiguredRemixStage() === 4) {
          fileContent = insertFrontEndPlaylistData(
            fileContent,
            REMIX_QUAIL_FRONTEND_PLAYLIST
          );
        }
      }

      if (fileName === "DefaultEngine.ini" && version.build >= 32.1 && version.build < 33) {
        const beaconPatch = [
          "",
          "[ConsoleVariables]",
          "FortMatchmakingV2.ContentBeaconFailureCancelsMatchmaking=0",
          "Fort.ShutdownWhenContentBeaconFails=0",
          "FortMatchmakingV2.EnableContentBeacon=0",
          "",
        ].join("\n");

        if (!fileContent.includes("FortMatchmakingV2.EnableContentBeacon=0")) {
          fileContent += beaconPatch;
        }
      }

      c.header("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
      c.header("Pragma", "no-cache");
      c.header("Expires", "0");
      return c.text(fileContent);
    } catch (err) {
      console.error("Error fetching system file:", err);
      return c.notFound();
    }
  });

  app.get("/fortnite/api/cloudstorage/user/:accountId", async (c) => {
    const accountId = c.req.param("accountId");
    try {
      const clientSettingsPath = path.join(
        atlasDataPath("static", "ClientSettings"),
        accountId
      );
      await fs.promises.mkdir(clientSettingsPath, { recursive: true });

      const ver = getVersion(c);

      const file = path.join(
        clientSettingsPath,
        `ClientSettings-${ver.season}.Sav`
      );

      try {
        const parsedFile = await fs.promises.readFile(file);
        const parsedStats = await fs.promises.stat(file);

        return c.json([
          {
            uniqueFilename: "ClientSettings.Sav",
            filename: "ClientSettings.Sav",
            hash: crypto.createHash("sha1").update(parsedFile).digest("hex"),
            hash256: crypto
              .createHash("sha256")
              .update(parsedFile)
              .digest("hex"),
            length: parsedStats.size,
            contentType: "application/octet-stream",
            uploaded: parsedStats.mtime,
            storageType: "S3",
            storageIds: {},
            accountId: accountId,
            doNotCache: false,
          },
        ]);
      } catch {
        // File doesn't exist
        return c.json([]);
      }
    } catch (err) {
      console.error("Error fetching user cloudstorage:", err);
      c.status(500);
      return c.json([]);
    }
  });

  app.put("/fortnite/api/cloudstorage/user/:accountId/:file", async (c) => {
    const filename = c.req.param("file");
    const accountId = c.req.param("accountId");

    const clientSettingsPath = path.join(
        atlasDataPath("static", "ClientSettings"),
        accountId
      );
    
    if (filename.toLowerCase() !== "clientsettings.sav") {
      return c.json([]);
    }

    const ver = getVersion(c);

    const file = path.join(
      clientSettingsPath,
      `ClientSettings-${ver.season}.Sav`
    );

    try {
      const body = await c.req.arrayBuffer();
      const buffer = Buffer.from(body);

      await fs.promises.mkdir(clientSettingsPath, { recursive: true });

      // Write atomically to avoid partial/corrupt saves if the process exits mid-write.
      const tmpFile = `${file}.${process.pid}.${Date.now()}.tmp`;
      try {
        await fs.promises.writeFile(tmpFile, buffer);
        await fs.promises.rename(tmpFile, file);
      } finally {
        // Best-effort cleanup (rename may fail and leave tmp behind).
        fs.promises.unlink(tmpFile).catch(() => {});
      }

      return c.json([]);
    } catch (error) {
      console.error("Error writing ClientSettings:", error);

      return c.json({ error: "Failed to save the settings" }, 500);
    }
  });

  app.get("/fortnite/api/cloudstorage/user/:accountId/:file", async (c) => {
    const accountId = c.req.param("accountId");
    const clientSettingsPath = path.join(
        atlasDataPath("static", "ClientSettings"),
        accountId
      );
    await fs.promises.mkdir(clientSettingsPath, { recursive: true });

    const ver = getVersion(c);

    const file = path.join(
      clientSettingsPath,
      `ClientSettings-${ver.season}.Sav`
    );

    try {
      const data = await fs.promises.readFile(file);
      return c.body(data as any);
    } catch {
      return c.json([]);
    }
  });
}
