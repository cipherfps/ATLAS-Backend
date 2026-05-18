import { app } from "..";
import axios from "axios";
import path from "node:path";
import fs from "node:fs";
import { getConfiguredGameServer, getRadminVpnIp } from "../utils/matchmaking/config";
import { atlasDataPath } from "../config/paths";

const lockerFileName = "locker-v4.json";

const lockerLoadoutSlots: Record<string, string[]> = {
  "CosmeticLoadout:LoadoutSchema_Character": [
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Character",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Backpack",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Pickaxe",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Glider",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Contrails",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Aura",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Shoes",
  ],
  "CosmeticLoadout:LoadoutSchema_Emotes": Array.from(
    { length: 6 },
    (_, index) => `CosmeticLoadoutSlotTemplate:LoadoutSlot_Emote_${index}`,
  ),
  "CosmeticLoadout:LoadoutSchema_Platform": [
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Banner_Icon",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Banner_Color",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_LobbyMusic",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_LoadingScreen",
  ],
  "CosmeticLoadout:LoadoutSchema_Wraps": Array.from(
    { length: 7 },
    (_, index) => `CosmeticLoadoutSlotTemplate:LoadoutSlot_Wrap_${index}`,
  ),
  "CosmeticLoadout:LoadoutSchema_Vehicle": [
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Vehicle_Body",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Vehicle_Booster",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Vehicle_DriftSmoke",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Vehicle_Wheel",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Vehicle_Skin",
  ],
  "CosmeticLoadout:LoadoutSchema_Sparks": [
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Bass",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Guitar",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Drum",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Keyboard",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Microphone",
  ],
  "CosmeticLoadout:LoadoutSchema_Jam": Array.from(
    { length: 8 },
    (_, index) => `CosmeticLoadoutSlotTemplate:LoadoutSlot_JamSong${index}`,
  ),
  "CosmeticLoadout:LoadoutSchema_Vehicle_SUV": [
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Vehicle_Body_SUV",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Vehicle_Skin_SUV",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Vehicle_Wheel_SUV",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Vehicle_DriftSmoke_SUV",
    "CosmeticLoadoutSlotTemplate:LoadoutSlot_Vehicle_Booster_SUV",
  ],
};

function lockerPath(accountId: string): string {
  return atlasDataPath("static", "profiles", accountId, lockerFileName);
}

function createDefaultLocker(accountId: string, deploymentId: string): any {
  const now = new Date().toISOString();
  const loadouts = Object.fromEntries(
    Object.entries(lockerLoadoutSlots).map(([loadoutType, slotTemplates]) => [
      loadoutType,
      {
        loadoutSlots: slotTemplates.map((slotTemplate) => ({
          slotTemplate,
          equippedItemId: "",
          itemCustomizations: [],
        })),
        shuffleType: "DISABLED",
      },
    ]),
  );

  return {
    activeLoadoutGroup: {
      accountId,
      deploymentId,
      athenaItemId: "atlas-loadout",
      creationTime: now,
      updatedTime: now,
      loadouts,
      shuffleType: "DISABLED",
    },
    loadoutGroupPresets: [],
    loadoutPresets: [],
  };
}

function ensureDefaultLockerShape(accountId: string, deploymentId: string, locker: any): any {
  const defaults = createDefaultLocker(accountId, deploymentId);
  const defaultLoadouts = defaults.activeLoadoutGroup.loadouts as Record<
    string,
    { loadoutSlots: Array<{ slotTemplate: string; equippedItemId: string; itemCustomizations: any[] }>; shuffleType: string }
  >;

  if (!locker || typeof locker !== "object") {
    return defaults;
  }

  if (!locker.activeLoadoutGroup || typeof locker.activeLoadoutGroup !== "object") {
    locker.activeLoadoutGroup = defaults.activeLoadoutGroup;
  }

  if (!locker.activeLoadoutGroup.loadouts || typeof locker.activeLoadoutGroup.loadouts !== "object") {
    locker.activeLoadoutGroup.loadouts = defaults.activeLoadoutGroup.loadouts;
  }

  for (const [loadoutType, defaultLoadout] of Object.entries(defaultLoadouts)) {
    const loadout = locker.activeLoadoutGroup.loadouts[loadoutType];
    if (!loadout || typeof loadout !== "object") {
      locker.activeLoadoutGroup.loadouts[loadoutType] = defaultLoadout;
      continue;
    }

    if (!Array.isArray(loadout.loadoutSlots)) {
      loadout.loadoutSlots = [];
    }

    const existingSlots = new Set(
      loadout.loadoutSlots
        .map((slot: any) => slot?.slotTemplate)
        .filter((slotTemplate: unknown) => typeof slotTemplate === "string"),
    );

    for (const defaultSlot of defaultLoadout.loadoutSlots) {
      if (!existingSlots.has(defaultSlot.slotTemplate)) {
        loadout.loadoutSlots.push(defaultSlot);
      }
    }

    if (loadout.shuffleType === undefined) {
      loadout.shuffleType = "DISABLED";
    }
  }

  if (!Array.isArray(locker.loadoutGroupPresets)) locker.loadoutGroupPresets = [];
  if (!Array.isArray(locker.loadoutPresets)) locker.loadoutPresets = [];

  return locker;
}

async function readLocker(accountId: string, deploymentId: string): Promise<any> {
  const filePath = lockerPath(accountId);
  try {
    const raw = await fs.promises.readFile(filePath, "utf8");
    return ensureDefaultLockerShape(accountId, deploymentId, JSON.parse(raw));
  } catch {
    const locker = createDefaultLocker(accountId, deploymentId);
    await writeLocker(accountId, deploymentId, locker);
    return locker;
  }
}

async function writeLocker(accountId: string, deploymentId: string, locker: any): Promise<void> {
  const filePath = lockerPath(accountId);
  await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
  await fs.promises.writeFile(filePath, JSON.stringify(locker, null, 2));
}

export default function () {
  app.post("/datarouter/api/v1/public/data", async (c) => {
    return c.json([]);
  });

  app.get("/account/api/public/account/*/externalAuths", async (c) => {
    return c.json([]);
  });

  app.get("/launcher/api/public/distributionpoints", (c) => {
    return c.json({
      distributions: [
        "https://epicgames-download1.akamaized.net/",
        "https://download.epicgames.com/",
        "https://download2.epicgames.com/",
        "https://download3.epicgames.com/",
        "https://download4.epicgames.com/",
        "https://atlas.ol.epicgames.com/",
      ],
    });
  });

  app.post("/api/v1/fortnite-br/interactions/contentHash", async (c) => {
    const body: any = c.req.json();
    return c.json({
      sessionId: body.sessionId,
      sessionStartTimestamp: body.sessionStartTimestamp,
      surfaces: [
        {
          surfaceId: "br-motd",
          contentMeta: [
            '{"c93adbc7a8a9f94a916de62aa443e2d6":["93eff180-1465-496e-9be4-c02ef810ad82"]}',
          ],
          events: [
            {
              contentHash: "c93adbc7a8a9f94a916de62aa443e2d6",
              type: "impression",
              count: 1,
              timestamp: "2023-12-03T10:17:41.387Z",
              lastTimestamp: "2023-12-03T10:17:41.387Z",
            },
          ],
        },
      ],
    });
  });

  app.post("/api/v1/fortnite-br/interactions", async (c) => {
    return c.json({});
  });

  app.post("/api/v1/:namespace/channel/motd/target", async (c) => {
    return c.json({
      contentType: "collection",
      contentId: "fortnite-br-br-motd-collection",
      tcId: "atlas-br-motd-collection-tc",
      contentItems: [],
    });
  });

  app.post("/api/v1/:namespace/surfaces/:gameMode/target", async (c) => {
    return c.json({
      contentType: "collection",
      contentId: "fortnite-br-br-motd-collection",
      tcId: "atlas-br-motd-collection-tc",
      contentItems: [],
    });
  });

  app.get("/fortnite/api/game/v2/world/info", async (c) => {
    return c.json({});
  });

  app.get("/unknown", async (c) => {
    return c.json([]);
  });

  app.get("/app_installation/status", async (c) => {
    return c.json({
      status: "UP",
      backend: "atlas",
    });
  });

  app.get("/region", async (c) => {
    return c.json({
      continent: "NA",
      country: "US",
      region: "NAE",
    });
  });

  app.get("/api/local-ip", async (c) => {
    return c.json({
      ip: getRadminVpnIp() ?? getConfiguredGameServer().host,
    });
  });

  app.get("/gs", async (c) => {
    const server = getConfiguredGameServer();
    return c.json({
      host: server.host,
      port: server.port,
      address: `${server.host}:${server.port}`,
    });
  });

  app.get("/api/v2/interactions/aggregated/Fortnite/:accountId", async (c) => {
    return c.json([]);
  });

  app.get("/api/v2/interactions/latest/Fortnite/:accountId", async (c) => {
    return c.json({
      results: [],
      interactions: [],
    });
  });

  app.get("/api/content/v2/launch-data", async (c) => {
    return c.json({
      results: [],
      items: [],
      data: {},
    });
  });

  // Keep parental controls permissive so privacy settings are not locked.
  app.get("/content-controls/:accountId", async (c) => {
    return c.json({
      data: {
        ageGate: 0,
        controlsEnabled: false,
        maxEpicProfilePrivacy: "none",
        principalId: c.req.param("accountId"),
      },
    });
  });

  app.get("/content-controls/:accountId/rules/namespaces/fn", async (c) => {
    return c.json([]);
  });

  app.post("/content-controls/:accountId/verify-pin", async (c) => {
    return c.json({
      data: {
        pinCorrect: true,
      },
    });
  });

  app.get("/fortnite/api/game/v2/privacy/account/:accountId", async (c) => {
    return c.json({
      accountId: c.req.param("accountId"),
      optOutOfPublicLeaderboards: false,
    });
  });

  app.post("/region/check", async (c) => {
    return c.json({
      content_id: "AF9yLAAsklQALFTy",
      allowed: true,
      resolved: true,
      limit: "Res=656",
    });
  });

  app.all("/profile/play_region", async (c) => {
    return c.body(null, 204);
  });

  app.all("/profile/languages", async (c) => {
    return c.body(null, 204);
  });

  app.all("/profile/privacy_settings", async (c) => {
    return c.body(null, 204);
  });

  app.all("/v1/rebootrally/eligibility/friends", async (c) => {
    return c.body(null, 204);
  });

  app.get("/fortnite/api/game/v2/br-inventory/account", async (c) => {
    return c.json({
      stash: {
        globalcash: 69,
      },
    });
  });

  app.get(
    "/launcher/api/public/assets/:platform/:catalogItemId/:appName",
    async (c) => {
      const appName = c.req.param("appName");
      const catalogItemId = c.req.param("catalogItemId");
      const platform = c.req.param("platform");
      const label = c.req.query("label");
      return c.json({
        appName: appName,
        labelName: `${label}-${platform}`,
        buildVersion: `atlas`,
        catalogItemId: catalogItemId,
        expires: "9988-09-23T23:59:59.999Z",
        items: {
          MANIFEST: {
            signature: "atlas",
            distribution: "http://localhost:5535/",
            path: `Builds/Fortnite/Content/CloudDir/Atlas.manifest`,
            additionalDistributions: [],
          },
        },
        assetId: appName,
      });
    }
  );

  app.get("/presence/api/v1/_/:accountId/settings/subscriptions", async (c) => {
    return c.json([]);
  });

  app.get("/presence/api/v1/_/:accountId/last-online", async (c) => {
    return c.json({});
  });

  app.all("/presence/api/v1/*", async (c) => {
    return c.json([]);
  });

  app.get("/eulatracking/api/public/agreements/fn/account/*", async (c) => {
    return c.json([]);
  });

  app.post("/datarouter/api/v1/public/data/clients", async (c) => {
    return c.json([]);
  });

  app.post("/telemetry/data/datarouter/api/v1/public/data", async (c) => {
    return c.json([]);
  });

  app.get("/Builds/Fortnite/Content/CloudDir/*", async (c: any) => {
    c.header("Content-Type", "application/octet-stream");
    const manifest: any = await fs.promises.readFile(
      path.join(__dirname, "..", "..", "static", "assets", "Atlas.manifest")
    );
    return c.body(manifest);
  });

  app.get("/Builds/Fortnite/Content/CloudDir/*.ini", async (c: any) => {
    const ini: any = fs.readFileSync(
      path.join(__dirname, "..", "..", "static", "assets", "stuff.ini")
    );
    return c.body(ini);
  });

  app.get(
    "/Builds/Fortnite/Content/CloudDir/ChunksV4/:chunknum/*",
    async (c) => {
      const response = await axios.get(
        `https://epicgames-download1.akamaized.net${c.req.path}`,
        {
          responseType: "stream",
        }
      );
      c.header("Content-Type", "application/octet-stream");

      return c.body(response.data);
    }
  );

  app.post("/fortnite/api/game/v2/grant_access/*", async (c) => {
    c.json({});
    return c.status(204);
  });

  app.post("/fortnite/api/game/v2/profileToken/verify/:accountId", async (c) => {
    return c.body(null, 204);
  });

  app.get("/fortnite/api/game/v2/enabled_features", async (c) => {
    return c.json([]);
  });

  app.post("/fortnite/api/game/v2/tryPlayOnPlatform/account/*", async (c) => {
    c.header("Content-Type", "text/plain");
    return c.text("true");
  });

  // Newer clients call these endpoints before opening playlist details.
  // Return explicit unlocked results so discovery tiles do not show as gated.
  app.post("/api/v1/links/lock-status/:accountId/check", async (c) => {
    const body = await c.req.json().catch(() => ({} as any));
    const linkCodes = Array.isArray(body?.linkCodes)
      ? body.linkCodes.filter((value: unknown) => typeof value === "string")
      : [];

    return c.json({
      results: linkCodes.map((linkCode: string) => ({
        playerId: c.req.param("accountId"),
        linkCode,
        lockStatus: "UNLOCKED",
        lockStatusReason: "NONE",
        isVisible: true,
      })),
      hasMore: false,
    });
  });

  app.post("/api/v1/links/lock-status/ssd/check", async (c) => {
    const body = await c.req.json().catch(() => ({} as any));
    const linkCodes = Array.isArray(body?.linkCodes)
      ? body.linkCodes.filter((value: unknown) => typeof value === "string")
      : [];

    return c.json({
      results: linkCodes.map((linkCode: string) => ({
        linkCode,
        lockStatus: "UNLOCKED",
        lockStatusReason: "NONE",
        isVisible: true,
      })),
      hasMore: false,
    });
  });

  app.get("/fortnite/api/v2/versioncheck/*", async (c) => {
    return c.json({
      type: "NO_UPDATE",
    });
  });

  app.post("/api/v1/user/setting", async (c) => {
    return c.json({});
  });

  app.post("/api/v1/links/favorites/:accountId/check", async (c) => {
    return c.json({
      results: [],
      hasMore: false,
    });
  });

  app.post("/api/v1/links/history/:accountId/:mnemonic", async (c) => {
    return c.json({
      accountId: c.req.param("accountId"),
      mnemonic: c.req.param("mnemonic"),
      success: true,
    });
  });

  app.get("/statsproxy/api/statsv2/account/:accountId", async (c) => {
    return c.json({
      startTime: 0,
      endTime: 0,
      stats: {},
      accountId: c.req.param("accountId"),
    });
  });

  app.get("/api/locker/v4/:deploymentId/account/:accountId/items", async (c) => {
    const accountId = c.req.param("accountId");
    const deploymentId = c.req.param("deploymentId");
    const locker = await readLocker(accountId, deploymentId);
    const now = new Date().toISOString();

    locker.activeLoadoutGroup.accountId = accountId;
    locker.activeLoadoutGroup.deploymentId = deploymentId;
    locker.activeLoadoutGroup.updatedTime = now;

    await writeLocker(accountId, deploymentId, locker);
    return c.json(locker);
  });

  app.put("/api/locker/v4/:deploymentId/account/:accountId/active-loadout-group", async (c) => {
    const accountId = c.req.param("accountId");
    const deploymentId = c.req.param("deploymentId");
    const body = await c.req.json().catch(() => ({} as any));
    const locker = await readLocker(accountId, deploymentId);
    const now = new Date().toISOString();

    locker.activeLoadoutGroup.accountId = accountId;
    locker.activeLoadoutGroup.deploymentId = deploymentId;
    locker.activeLoadoutGroup.updatedTime = now;

    if (body?.equippedPresetId !== undefined) {
      locker.activeLoadoutGroup.equippedPresetId = body.equippedPresetId;
    }

    if (body?.shuffleType !== undefined) {
      locker.activeLoadoutGroup.shuffleType = body.shuffleType;
    }

    const loadouts = body?.loadouts ?? body?.activeLoadoutGroup?.loadouts;
    if (loadouts && typeof loadouts === "object") {
      locker.activeLoadoutGroup.loadouts = loadouts;
    }

    await writeLocker(accountId, deploymentId, locker);
    return c.json(locker.activeLoadoutGroup);
  });

  app.get("/fortnite/api/receipts/v1/account/*/receipts", async (c) => {
    return c.json([]);
  });

  app.get("/account/api/public/account/:accountId/externalAuths", async (c) => {
    c.status(204);
    return c.json({});
  });

  app.post("/fortnite/api/game/v2/tryPlayOnPlatform/account/*", async (c) => {
    c.header("Content-Type", "text/plain");
    return c.text("true");
  });

  app.get("/socialban/api/public/v1/:accountId", async (c) => {
    return c.json({});
  });

  app.post("/auth/v1/turn/credentials", async (c) => {
    const username = c.req.query("username") || "atlas";
    return c.json({
      username,
      password: "local-turn-password",
      ttl: 86400,
      uris: [
        "stun:127.0.0.1:3478",
        "turn:127.0.0.1:3478?transport=udp",
        "turn:127.0.0.1:3478?transport=tcp",
      ],
    });
  });

  app.get("/api/v1/public/accounts", async (c) => {
    const accountId = c.req.query("accountId") || "atlas";
    return c.json({
      accounts: [
        {
          accountId,
          tags: [],
        },
      ],
    });
  });

  app.get(
    "/party/api/v1/Fortnite/user/:accountId/notifications/undelivered/count",
    async (c) => {
      return c.json({
        count: 0,
      });
    }
  );

  app.get(
    "/party/api/v1/Fortnite/user/:accountId/settings/privacy",
    async (c) => {
      const accountId = c.req.param("accountId");
      return c.json({
        accountId,
        partyType: "Public",
        inviteRestriction: "AnyMember",
        onlyLeaderFriendsCanJoin: false,
        presencePermission: "Anyone",
        invitePermission: "Anyone",
        acceptingMembers: true,
        privacy: "PUBLIC",
      });
    }
  );

  app.get(
    "/eulatracking/api/public/agreements/fn/account/:accountId",
    async (c) => {
      return c.json({});
    }
  );

  app.get("/fortnite/api/game/v2/creative/*", async (c) => {
    return c.json({});
  });

  // Content controls endpoints moved to top of file (lines 65-86)
  // Duplicate endpoints removed to prevent conflicts

  app.get("/api/v1/namespace/fn/worlds/accessibleTo/:accountid", async (c) => {
    return c.json({});
  });

  app.get("/api/v1/namespace/fn/worlds/accessibleTo/:accountID", async (c) => {
    return c.json({});
  });

  app.post("/api/v1/namespace/fn/worlds/account/:accountId", async (c) => {
    return c.json({});
  });
}
