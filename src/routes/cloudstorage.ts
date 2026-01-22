import app from "..";
import crypto from "crypto";
import fs from "node:fs";
import path from "node:path";
import getVersion from "../utils/handlers/getVersion";

// Cache for hotfix files to avoid repeated disk reads
const hotfixCache = new Map<string, string>();

export default function () {
  app.get("/fortnite/api/cloudstorage/system", async (c) => {
    try {
      const hotfixesDir = path.join(__dirname, "../../static/hotfixes");
      const csFiles: any = [];

      const files = await fs.promises.readdir(hotfixesDir);
      for (const file of files) {
        const filePath = path.join(hotfixesDir, file);
        const [f, fileStat] = await Promise.all([
          fs.promises.readFile(filePath),
          fs.promises.stat(filePath)
        ]);

        csFiles.push({
          uniqueFilename: file,
          filename: file,
          hash: crypto.createHash("sha1").update(f as any).digest("hex"),
          hash256: crypto.createHash("sha256").update(f as any).digest("hex"),
          length: fileStat.size,
          contentType: "application/octet-stream",
          uploaded: new Date().toISOString(),
          storageType: "S3",
          storageIds: {},
          doNotCache: true,
        });
      }

      return c.json(csFiles);
    } catch (err) {
      console.error("Error fetching system cloudstorage:", err);
      return c.status(500);
    }
  });

  app.get("/fortnite/api/cloudstorage/system/config", async (c) => {
    try {
      const hotfixesDir = path.join(__dirname, "../../static/hotfixes");
      const csFiles: any = [];

      const files = await fs.promises.readdir(hotfixesDir);
      for (const file of files) {
        const filePath = path.join(hotfixesDir, file);
        const [f, fileStat] = await Promise.all([
          fs.promises.readFile(filePath),
          fs.promises.stat(filePath)
        ]);

        csFiles.push({
          uniqueFilename: file,
          filename: file,
          hash: crypto.createHash("sha1").update(f as any).digest("hex"),
          hash256: crypto.createHash("sha256").update(f as any).digest("hex"),
          length: fileStat.size,
          contentType: "application/octet-stream",
          uploaded: new Date().toISOString(),
          storageType: "S3",
          storageIds: {},
          doNotCache: true,
        });
      }

      return c.json(csFiles);
    } catch (err) {
      console.error("Error fetching system config cloudstorage:", err);
      return c.status(500);
    }
  });

  app.get("/fortnite/api/cloudstorage/system/:file", async (c) => {
    try {
      const version = getVersion(c);
      const fileName = c.req.param("file");
      const filePath = path.join(
        __dirname,
        "../../static/hotfixes",
        fileName
      );
      
      // Check cache first
      let fileContent: string;
      if (hotfixCache.has(fileName)) {
        fileContent = hotfixCache.get(fileName)!;
      } else {
        // Load from disk and cache
        fileContent = await fs.promises.readFile(filePath, { encoding: "utf8" });
        hotfixCache.set(fileName, fileContent);
      }

      // For Season 5-6, strip all DataTable modifications to prevent crashes
      if (fileName === "DefaultGame.ini" && version.season <= 6) {
        // Remove all +DataTable and +CurveTable lines
        const lines = fileContent.split('\n');
        const filteredLines = lines.filter(line => {
          const trimmed = line.trim();
          // Keep everything except DataTable/CurveTable hotfixes
          return !trimmed.startsWith('+DataTable=') && 
                 !trimmed.startsWith('+CurveTable=');
        });
        fileContent = filteredLines.join('\n');
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
      }

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
        __dirname,
        "..",
        "..",
        "static",
        "ClientSettings",
        accountId
      );
      await fs.promises.mkdir(clientSettingsPath, { recursive: true });

      const ver = getVersion(c);

      const file = path.join(
        clientSettingsPath,
        `ClientSettings-${ver.season}.Sav`
      );

      try {
        const ParsedFile = await fs.promises.readFile(file, "latin1");
        const ParsedStats = await fs.promises.stat(file);

        return c.json([
          {
            uniqueFilename: "ClientSettings.Sav",
            filename: "ClientSettings.Sav",
            hash: crypto.createHash("sha1").update(ParsedFile).digest("hex"),
            hash256: crypto
              .createHash("sha256")
              .update(ParsedFile)
              .digest("hex"),
            length: Buffer.byteLength(ParsedFile),
            contentType: "application/octet-stream",
            uploaded: ParsedStats.mtime,
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
        __dirname,
        "..",
        "..",
        "static",
        "ClientSettings",
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

      // Respond immediately, save in background
      const response = c.json([]);
      
      // Save file asynchronously without blocking
      fs.promises.mkdir(clientSettingsPath, { recursive: true })
        .then(() => fs.promises.writeFile(file, buffer as any, "latin1"))
        .catch(error => console.error("Error writing ClientSettings:", error));

      return response;
    } catch (error) {
      console.error("Error writing the file:", error);

      return c.json({ error: "Failed to save the settings" }, 500);
    }
  });

  app.get("/fortnite/api/cloudstorage/user/:accountId/:file", async (c) => {
    const accountId = c.req.param("accountId");
    const clientSettingsPath = path.join(
        __dirname,
        "..",
        "..",
        "static",
        "ClientSettings",
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
