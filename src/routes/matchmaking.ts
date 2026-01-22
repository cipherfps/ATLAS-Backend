import app, { setStatusMessage } from "..";
import jwt from "jsonwebtoken";
import getVersion from "../utils/handlers/getVersion";
import logger from "../utils/logger/logger";

// Store buildId per account like Reload-Backend does
const buildUniqueId: { [key: string]: string } = {};

export default function () {
  app.get("/waitingroom/api/waitingroom", async (c) => {
    return c.json([]);
  });
  app.get("/fortnite/api/matchmaking/session/findPlayer/:id", async (c) => {
    return c.json([]);
  });

  app.get("/fortnite/api/game/v2/matchmakingservice/ticket/player/*", async (c) => {
    const bucketId: any = c.req.query("bucketId");
    const playerMatchmakingKey = c.req.query("player.option.customKey");
    const playerPlaylist = bucketId.split(":")[3];
    const playerRegion = bucketId.split(":")[2];
    const ver = getVersion(c);
    
    // Get accountId from JWT token
    const token = c.req.header("Authorization")?.replace("bearer ", "");
    let accountId = "default";
    if (token) {
      try {
        const decoded = jwt.verify(token, "LVe51Izk03lzceNf1ZGZs0glGx5tKh7f") as any;
        accountId = decoded.accountId || "default";
      } catch {}
    }
    
    // Store buildId for this account like Reload-Backend does
    buildUniqueId[accountId] = bucketId.split(":")[0];
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Ticket created for ${accountId}`);

    const mmData = jwt.sign(
      {
        region: playerRegion,
        playlist: playerPlaylist,
        type: typeof playerMatchmakingKey === "string" ? "custom" : "normal",
        key: typeof playerMatchmakingKey === "string" ? playerMatchmakingKey : undefined,
        bucket: bucketId,
        version: `${ver.build}`,
        accountId: accountId,
      },
      "LVe51Izk03lzceNf1ZGZs0glGx5tKh7f",
    );
    var data = mmData.split(".");
    return c.json({
      serviceUrl: "ws://127.0.0.1:5555",
      ticketType: "mms-player",
      payload: data[0],
      signature: "account",
    });
  });

  app.post("/fortnite/api/matchmaking/session/:SessionId/join", async (c) => {
    return c.json([]);
  });

  app.get("/fortnite/api/matchmaking/session/:sessionId", async (c) => {
    const sessionId = c.req.param("sessionId");
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Joining session...`);
    
    const serverAddress = "127.0.0.1:7777";
    
    // Get accountId from token
    const token = c.req.header("Authorization")?.replace("bearer ", "");
    let accountId = "default";
    if (token) {
      try {
        const decoded = jwt.verify(token, "LVe51Izk03lzceNf1ZGZs0glGx5tKh7f") as any;
        accountId = decoded.accountId || "default";
      } catch {}
    }
    
    // Get stored build ID for this account, default to "0" like Reload-Backend
    const storedBuildId = buildUniqueId[accountId] || "0";
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Connecting to server...`);
    
    return c.json({
      id: sessionId,
      ownerId: crypto.randomUUID().replace(/-/gi, "").toUpperCase(),
      ownerName: "[DS]fortnite-liveeugcec1c2e30ubrcore0a-z8hj-1968",
      serverName: "[DS]fortnite-liveeugcec1c2e30ubrcore0a-z8hj-1968",
      serverAddress: "127.0.0.1",
      serverPort: 7777,
      maxPublicPlayers: 220,
      openPublicPlayers: 175,
      maxPrivatePlayers: 0,
      openPrivatePlayers: 0,
      attributes: {
        REGION_s: "NAE",
        GAMEMODE_s: "FORTATHENA",
        ALLOWBROADCASTING_b: true,
        SUBREGION_s: "GB",
        DCID_s: "FORTNITE-LIVEEUGCEC1C2E30UBRCORE0A-14840880",
        tenant_s: "Fortnite",
        MATCHMAKINGPOOL_s: "Any",
        STORMSHIELDDEFENSETYPE_i: 0,
        HOTFIXVERSION_i: 0,
        PLAYLISTNAME_s: "Playlist_DefaultSolo",
        SESSIONKEY_s: crypto.randomUUID().replace(/-/gi, "").toUpperCase(),
        TENANT_s: "Fortnite",
        BEACONPORT_i: 15009,
        ALLOWMIGRATION_s: "false",
        REJOINAFTERKICK_s: "OPEN",
        CHECKSANCTIONS_s: "false",
        BUCKET_s: "",
        DEPLOYMENT_s: "Fortnite",
        LASTUPDATED_s: new Date().toISOString(),
        LINKID_s: "playlist_defaultsolo?v=95",
        allowMigration_s: false,
        ALLOWREADBYID_s: "false",
        SERVERADDRESS_s: serverAddress,
        NETWORKMODULE_b: true,
        lastUpdated_s: new Date().toISOString(),
        allowReadById_s: false,
        serverAddress_s: serverAddress,
        LINKTYPE_s: "BR:Playlist",
        deployment_s: "Fortnite",
        ADDRESS_s: serverAddress,
        bucket_s: "",
        checkSanctions_s: false,
        rejoinAfterKick_s: "OPEN",
      },
      publicPlayers: [],
      privatePlayers: [],
      totalPlayers: 45,
      allowJoinInProgress: false,
      shouldAdvertise: false,
      isDedicated: false,
      usesStats: false,
      allowInvites: false,
      usesPresence: false,
      allowJoinViaPresence: true,
      allowJoinViaPresenceFriendsOnly: false,
      buildUniqueId: storedBuildId,
      lastUpdated: new Date().toISOString(),
      started: false,
    });
  });

  app.get("/fortnite/api/matchmaking/session/matchMakingRequest", async (c) => {
    setStatusMessage("\x1b[33m[MATCHMAKING]\x1b[0m Request received");
    return c.json([]);
  });

  app.get("/fortnite/api/game/v2/matchmaking/account/:accountId/session/:sessionId", async (c) => {
    const accountId = c.req.param("accountId");
    const sessionId = c.req.param("sessionId");
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Session validation`);
    
    return c.json({
      accountId: accountId,
      sessionId: sessionId,
      key: "none",
    });
  });

  app.post("/fortnite/api/game/v2/matchmaking/account/:accountId/session/:sessionId", async (c) => {
    const accountId = c.req.param("accountId");
    const sessionId = c.req.param("sessionId");
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Session confirmed`);
    
    return c.json({
      accountId: accountId,
      sessionId: sessionId,
      key: crypto.randomUUID().replace(/-/gi, ""),
    });
  });
}
