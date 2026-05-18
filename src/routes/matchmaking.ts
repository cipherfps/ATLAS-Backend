import { app, setStatusMessage } from "..";
import jwt from "jsonwebtoken";
import getVersion from "../utils/handlers/getVersion";
import {
  getConfiguredGameServer,
  getConfiguredMatchmakerUrl,
} from "../utils/matchmaking/config";

interface MatchmakingSessionInfo {
  buildUniqueId: string;
  serverAddress: string;
  serverPort: number;
  playlistName: string;
  region: string;
}

interface DedicatedSessionInfo extends MatchmakingSessionInfo {
  id: string;
  ownerId: string;
  ownerName: string;
  serverName: string;
  maxPublicPlayers: number;
  maxPrivatePlayers: number;
  openPublicPlayers: number;
  openPrivatePlayers: number;
  sortWeight: number;
  started: boolean;
  publicPlayers: string[];
  privatePlayers: string[];
  attributes: Record<string, any>;
  lastUpdated: string;
}

const matchmakingSessions: Record<string, MatchmakingSessionInfo> = {};
const dedicatedSessions: Record<string, DedicatedSessionInfo> = {};
const matchmakingEncryptionKey = "AOJEv8uTFmUh7XM2328kq9rlAzeQ5xzWzPIiyKn2s7s=";
const contentBeaconPort = 15009;

function getAccountIdFromRequest(c: any): string {
  const token = c.req.header("Authorization")?.replace("bearer ", "");
  if (!token) {
    return "default";
  }

  try {
    const decoded = jwt.verify(token, "LVe51Izk03lzceNf1ZGZs0glGx5tKh7f") as any;
    return decoded.accountId || "default";
  } catch {
    return "default";
  }
}

function getStoredSessionInfo(accountId: string): MatchmakingSessionInfo {
  const stored = matchmakingSessions[accountId];
  if (stored) {
    return stored;
  }

  const configuredServer = getConfiguredGameServer();
  return {
    buildUniqueId: "0",
    serverAddress: configuredServer.host,
    serverPort: configuredServer.port,
    playlistName: "Playlist_DefaultSolo",
    region: "NAE",
  };
}

function compactUuid(): string {
  return crypto.randomUUID().replace(/-/gi, "");
}

function getString(value: unknown, fallback: string): string {
  return typeof value === "string" && value.length > 0 ? value : fallback;
}

function getNumber(value: unknown, fallback: number): number {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function getBoolean(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function getStringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((entry): entry is string => typeof entry === "string")
    : [];
}

function normalizeAttributes(value: unknown): Record<string, any> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? { ...(value as Record<string, any>) }
    : {};
}

function getLatestDedicatedSession(): DedicatedSessionInfo | null {
  const sessions = Object.values(dedicatedSessions).sort((a, b) =>
    b.lastUpdated.localeCompare(a.lastUpdated),
  );
  return sessions[0] ?? null;
}

function createDedicatedSession(body: Record<string, any>): DedicatedSessionInfo {
  const configuredServer = getConfiguredGameServer();
  const attributes = normalizeAttributes(body.attributes);
  const id = getString(body.id, compactUuid());
  const serverAddress = getString(
    body.serverAddress,
    getString(attributes.SERVERADDRESS_s, configuredServer.host).split(":")[0],
  );
  const serverPort = getNumber(
    body.serverPort,
    getNumber(attributes.SERVERPORT_i, configuredServer.port),
  );
  const playlistName = getString(
    attributes.PLAYLISTNAME_s,
    getString(body.playlistName, "Playlist_DefaultSolo"),
  );
  const region = getString(attributes.REGION_s, getString(body.region, "NAE"));

  return {
    id,
    buildUniqueId: getString(body.buildUniqueId, "0"),
    serverAddress,
    serverPort,
    playlistName,
    region,
    ownerId: getString(body.ownerId, compactUuid()),
    ownerName: getString(body.ownerName, "[DS]atlas-local"),
    serverName: getString(body.serverName, "[DS]atlas-local"),
    maxPublicPlayers: getNumber(body.maxPublicPlayers, 220),
    maxPrivatePlayers: getNumber(body.maxPrivatePlayers, 0),
    openPublicPlayers: getNumber(body.openPublicPlayers, 220),
    openPrivatePlayers: getNumber(body.openPrivatePlayers, 0),
    sortWeight: getNumber(body.sortWeight, 0),
    started: getBoolean(body.started, false),
    publicPlayers: getStringArray(body.publicPlayers),
    privatePlayers: getStringArray(body.privatePlayers),
    attributes,
    lastUpdated: new Date().toISOString(),
  };
}

function mergeDedicatedSession(
  session: DedicatedSessionInfo,
  body: Record<string, any>,
): DedicatedSessionInfo {
  const attributes = normalizeAttributes(body.attributes);
  const mergedAttributes =
    Object.keys(attributes).length > 0 ? attributes : session.attributes;

  return {
    ...session,
    buildUniqueId: getString(body.buildUniqueId, session.buildUniqueId),
    serverAddress: getString(body.serverAddress, session.serverAddress),
    serverPort: getNumber(body.serverPort, session.serverPort),
    playlistName: getString(mergedAttributes.PLAYLISTNAME_s, session.playlistName),
    region: getString(mergedAttributes.REGION_s, session.region),
    ownerId: getString(body.ownerId, session.ownerId),
    ownerName: getString(body.ownerName, session.ownerName),
    serverName: getString(body.serverName, session.serverName),
    maxPublicPlayers: getNumber(body.maxPublicPlayers, session.maxPublicPlayers),
    maxPrivatePlayers: getNumber(body.maxPrivatePlayers, session.maxPrivatePlayers),
    openPublicPlayers: getNumber(body.openPublicPlayers, session.openPublicPlayers),
    openPrivatePlayers: getNumber(body.openPrivatePlayers, session.openPrivatePlayers),
    sortWeight: getNumber(body.sortWeight, session.sortWeight),
    started: getBoolean(body.started, session.started),
    publicPlayers: Array.isArray(body.publicPlayers)
      ? getStringArray(body.publicPlayers)
      : session.publicPlayers,
    privatePlayers: Array.isArray(body.privatePlayers)
      ? getStringArray(body.privatePlayers)
      : session.privatePlayers,
    attributes: mergedAttributes,
    lastUpdated: new Date().toISOString(),
  };
}

function sessionResponse(sessionId: string, sessionInfo: MatchmakingSessionInfo | DedicatedSessionInfo) {
  const now = new Date().toISOString();
  const dedicated = sessionInfo as Partial<DedicatedSessionInfo>;
  const joinEndpoint = getConfiguredGameServer();
  const addressWithPort = `${joinEndpoint.host}:${joinEndpoint.port}`;
  const beaconAddressWithPort = `${joinEndpoint.host}:${contentBeaconPort}`;
  const linkId = `${sessionInfo.playlistName.toLowerCase()}?v=95`;
  const attributes = {
    ...(dedicated.attributes ?? {}),
    REGION_s: sessionInfo.region,
    GAMEMODE_s: "FORTATHENA",
    MATCHMAKINGPOOL_s: "Any",
    PLAYLISTNAME_s: sessionInfo.playlistName,
    TENANT_s: "Fortnite",
    tenant_s: "Fortnite",
    DEPLOYMENT_s: "Fortnite",
    deployment_s: "Fortnite",
    LASTUPDATED_s: now,
    lastUpdated_s: now,
    LINKID_s: linkId,
    LINKTYPE_s: "BR:Playlist",
    SERVERADDRESS_s: addressWithPort,
    serverAddress_s: addressWithPort,
    ADDRESS_s: addressWithPort,
    HOSTNAME_s: joinEndpoint.host,
    SERVERHOST_s: joinEndpoint.host,
    SERVERPORT_i: joinEndpoint.port,
    serverPort_i: joinEndpoint.port,
    PORT_i: joinEndpoint.port,
    BEACONADDRESS_s: beaconAddressWithPort,
    beaconAddress_s: beaconAddressWithPort,
    BEACONPORT_i: contentBeaconPort,
    beaconPort_i: contentBeaconPort,
    GAMESERVERIP_s: joinEndpoint.host,
    GAMESERVERPORT_i: joinEndpoint.port,
    NETWORKMODULE_b: true,
    ALLOWMIGRATION_s: "false",
    allowMigration_s: false,
    ALLOWREADBYID_s: "false",
    allowReadById_s: false,
    REJOINAFTERKICK_s: "OPEN",
    rejoinAfterKick_s: "OPEN",
    CHECKSANCTIONS_s: "false",
    checkSanctions_s: false,
    BUCKET_s: "",
    bucket_s: "",
  };

  return {
    id: sessionId,
    ownerId: dedicated.ownerId ?? compactUuid().toUpperCase(),
    ownerName: dedicated.ownerName ?? "[DS]fortnite-liveeugcec1c2e30ubrcore0a-z8hj-1968",
    serverName: dedicated.serverName ?? "[DS]fortnite-liveeugcec1c2e30ubrcore0a-z8hj-1968",
    serverAddress: joinEndpoint.host,
    serverPort: joinEndpoint.port,
    beaconPort: contentBeaconPort,
    maxPublicPlayers: dedicated.maxPublicPlayers ?? 220,
    openPublicPlayers: dedicated.openPublicPlayers ?? 175,
    maxPrivatePlayers: dedicated.maxPrivatePlayers ?? 0,
    openPrivatePlayers: dedicated.openPrivatePlayers ?? 0,
    attributes,
    publicPlayers: dedicated.publicPlayers ?? [],
    privatePlayers: dedicated.privatePlayers ?? [],
    totalPlayers: dedicated.publicPlayers?.length ?? 1,
    allowJoinInProgress: true,
    shouldAdvertise: true,
    isDedicated: false,
    usesStats: true,
    allowInvites: true,
    usesPresence: true,
    allowJoinViaPresence: false,
    allowJoinViaPresenceFriendsOnly: false,
    buildUniqueId: sessionInfo.buildUniqueId,
    lastUpdated: now,
    started: dedicated.started ?? false,
  };
}

function dedicatedSessionResponse(session: DedicatedSessionInfo) {
  return {
    ...sessionResponse(session.id, session),
    sessionId: session.id,
    sortWeight: session.sortWeight,
    isDedicated: true,
  };
}

function gameSessionTokenResponse(accountId: string, sessionId: string) {
  const sessionInfo =
    dedicatedSessions[sessionId] ?? getLatestDedicatedSession() ?? getStoredSessionInfo(accountId);
  const joinEndpoint = getConfiguredGameServer();
  const now = Math.floor(Date.now() / 1000);
  const token = jwt.sign(
    {
      accountId,
      sessionId,
      playlistName: sessionInfo.playlistName,
      serverAddress: joinEndpoint.host,
      serverPort: joinEndpoint.port,
      exp: now + 60 * 60 * 4,
      iat: now,
    },
    "LVe51Izk03lzceNf1ZGZs0glGx5tKh7f",
  );

  return {
    accountId,
    sessionId,
    token,
    serverAddress: joinEndpoint.host,
    serverPort: joinEndpoint.port,
    key: matchmakingEncryptionKey,
  };
}

export default function () {
  app.get("/waitingroom/api/waitingroom", async (c) => {
    return c.json([]);
  });
  app.get("/fortnite/api/matchmaking/session/findPlayer/:id", async (c) => {
    return c.json([]);
  });

  app.get("/fortnite/api/game/v2/matchmakingservice/ticket/player/*", async (c) => {
    const bucketId = c.req.query("bucketId") ?? "";
    const playerMatchmakingKey = c.req.query("player.option.customKey");
    const bucketParts = bucketId.split(":");
    const playerPlaylist = bucketParts[3] || "Playlist_DefaultSolo";
    const playerRegion = bucketParts[2] || "NAE";
    const ver = getVersion(c);
    const accountId = getAccountIdFromRequest(c);

    const configuredServer = getConfiguredGameServer();
    const selectedServer = configuredServer;

    matchmakingSessions[accountId] = {
      buildUniqueId: bucketParts[0] || "0",
      serverAddress: selectedServer.host,
      serverPort: selectedServer.port,
      playlistName: playerPlaylist,
      region: playerRegion,
    };

    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Ticket created for ${accountId}`);

    const mmData = jwt.sign(
      {
        region: playerRegion,
        playlist: playerPlaylist,
        type: "local",
        key: playerMatchmakingKey,
        bucket: bucketId,
        version: `${ver.build}`,
        accountId: accountId,
      },
      "LVe51Izk03lzceNf1ZGZs0glGx5tKh7f",
    );
    var data = mmData.split(".");
    return c.json({
      serviceUrl: getConfiguredMatchmakerUrl(),
      ticketType: "mms-player",
      payload: data[0],
      signature: "account",
    });
  });

  app.post("/fortnite/api/matchmaking/session/:SessionId/join", async (c) => {
    return c.body(null, 204);
  });

  app.get("/fortnite/api/matchmaking/session/matchMakingRequest", async (c) => {
    setStatusMessage("\x1b[33m[MATCHMAKING]\x1b[0m Request received");
    return c.json([]);
  });

  app.post("/fortnite/api/matchmaking/session", async (c) => {
    const body = await c.req.json().catch(() => ({} as Record<string, any>));
    const session = createDedicatedSession(body);
    dedicatedSessions[session.id] = session;
    setStatusMessage(
      `\x1b[33m[MATCHMAKING]\x1b[0m Dedicated session ${session.id} registered on ${session.serverAddress}:${session.serverPort}`,
    );
    return c.json(dedicatedSessionResponse(session));
  });

  app.post("/fortnite/api/matchmaking/session/:sessionId/players", async (c) => {
    const sessionId = c.req.param("sessionId");
    const session = dedicatedSessions[sessionId];
    if (!session) {
      return c.json(sessionResponse(sessionId, getStoredSessionInfo(getAccountIdFromRequest(c))));
    }

    const body = await c.req.json().catch(() => ({} as Record<string, any>));
    dedicatedSessions[sessionId] = mergeDedicatedSession(session, {
      publicPlayers: body.publicPlayers,
      privatePlayers: body.privatePlayers,
    });
    return c.json(dedicatedSessionResponse(dedicatedSessions[sessionId]));
  });

  app.post("/fortnite/api/matchmaking/session/:sessionId/heartbeat", async (c) => {
    const sessionId = c.req.param("sessionId");
    const session = dedicatedSessions[sessionId];
    if (!session) {
      return c.json(sessionResponse(sessionId, getStoredSessionInfo(getAccountIdFromRequest(c))));
    }

    session.lastUpdated = new Date().toISOString();
    return c.json(dedicatedSessionResponse(session));
  });

  app.post("/fortnite/api/matchmaking/session/:sessionId/start", async (c) => {
    const sessionId = c.req.param("sessionId");
    const session = dedicatedSessions[sessionId];
    if (!session) {
      return c.json(sessionResponse(sessionId, getStoredSessionInfo(getAccountIdFromRequest(c))));
    }

    session.started = true;
    session.lastUpdated = new Date().toISOString();
    return c.json(dedicatedSessionResponse(session));
  });

  app.post("/fortnite/api/matchmaking/session/:sessionId/stop", async (c) => {
    const sessionId = c.req.param("sessionId");
    const session = dedicatedSessions[sessionId];
    if (session) {
      delete dedicatedSessions[sessionId];
      return c.json(dedicatedSessionResponse({ ...session, started: false }));
    }

    return c.json(sessionResponse(sessionId, getStoredSessionInfo(getAccountIdFromRequest(c))));
  });

  const updateDedicatedSession = async (c: any) => {
    const sessionId = c.req.param("sessionId");
    const session = dedicatedSessions[sessionId];
    const body = await c.req.json().catch(() => ({} as Record<string, any>));

    if (!session) {
      const created = createDedicatedSession({ ...body, id: sessionId });
      created.id = sessionId;
      dedicatedSessions[sessionId] = created;
      return c.json(dedicatedSessionResponse(created));
    }

    dedicatedSessions[sessionId] = mergeDedicatedSession(session, body);
    return c.json(dedicatedSessionResponse(dedicatedSessions[sessionId]));
  };

  app.post("/fortnite/api/matchmaking/session/:sessionId", updateDedicatedSession);
  app.put("/fortnite/api/matchmaking/session/:sessionId", updateDedicatedSession);

  app.get("/fortnite/api/matchmaking/session/:sessionId", async (c) => {
    const sessionId = c.req.param("sessionId");
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Joining session...`);

    const accountId = getAccountIdFromRequest(c);
    const sessionInfo =
      dedicatedSessions[sessionId] ?? getLatestDedicatedSession() ?? getStoredSessionInfo(accountId);
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Connecting to server...`);

    return c.json(sessionResponse(sessionId, sessionInfo));
  });

  app.get("/fortnite/api/game/v2/matchmakingservice/ticket/session/:sessionId", async (c) => {
    const sessionId = c.req.param("sessionId");
    const bucketIds = c.req.query("bucketIds") ?? c.req.query("bucketId") ?? "";
    const signature = jwt.sign(
      {
        sessionId,
        bucketIds,
        exp: Math.floor(Date.now() / 1000) + 60 * 60 * 4,
      },
      "LVe51Izk03lzceNf1ZGZs0glGx5tKh7f",
    );

    return c.json({
      serviceUrl: getConfiguredMatchmakerUrl(),
      ticketType: "Xenon-Sessions",
      payload: sessionId,
      signature,
    });
  });

  app.get("/fortnite/api/game/v2/matchmaking/account/:accountId/session/:sessionId", async (c) => {
    const accountId = c.req.param("accountId");
    const sessionId = c.req.param("sessionId");
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Session validation`);
    
    return c.json({
      accountId: accountId,
      sessionId: sessionId,
      key: matchmakingEncryptionKey,
    });
  });

  app.post("/fortnite/api/game/v2/matchmaking/account/:accountId/session/:sessionId", async (c) => {
    const accountId = c.req.param("accountId");
    const sessionId = c.req.param("sessionId");
    setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Session confirmed`);
    
    return c.json({
      accountId: accountId,
      sessionId: sessionId,
      key: matchmakingEncryptionKey,
    });
  });

  app.post("/fortnite/api/gamesession/v2/account/:accountId/token/:sessionId", async (c) => {
    const accountId = c.req.param("accountId");
    const sessionId = c.req.param("sessionId");
    return c.json(gameSessionTokenResponse(accountId, sessionId));
  });

  app.get("/fortnite/api/gamesession/v2/account/:accountId/token/:sessionId", async (c) => {
    const accountId = c.req.param("accountId");
    const sessionId = c.req.param("sessionId");
    return c.json(gameSessionTokenResponse(accountId, sessionId));
  });
}
