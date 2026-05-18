import { app, setStatusMessage } from "..";
import { Atlas } from "../utils/handlers/errors";
import jwt from "jsonwebtoken";
import logger from "../utils/logger/logger";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { atlasDataPath } from "../config/paths";

interface requestBody {
  [key: string]: any;
}

const authLogDir = atlasDataPath("logs");
const authLogPath = path.join(authLogDir, "auth-debug.log");

function ensureAuthLogDir() {
  if (!fs.existsSync(authLogDir)) {
    fs.mkdirSync(authLogDir, { recursive: true });
  }
}

function safeValue(value: unknown) {
  if (typeof value === "string") {
    if (value.length > 64) {
      return `${value.slice(0, 16)}...${value.slice(-16)}`;
    }
    return value;
  }
  return value;
}

function logAuth(message: string, data?: Record<string, unknown>) {
  try {
    ensureAuthLogDir();
    const timestamp = new Date().toISOString();
    const payload = data
      ? JSON.stringify(
          Object.fromEntries(
            Object.entries(data).map(([key, value]) => [key, safeValue(value)])
          )
        )
      : "";
    const logSuffix = payload ? ` ${payload}` : "";
    logger.debug(`[AUTH] ${message}${logSuffix}`);
    fs.appendFileSync(authLogPath, `[${timestamp}] ${message} ${payload}\n`);
  } catch (err) {
    logger.error(`Failed to write auth debug log: ${err}`);
  }
}

const eosFeatures = [
  "AntiCheat",
  "Connect",
  "ContentService",
  "Ecom",
  "EpicConnect",
  "Inventories",
  "LockerService",
  "Matchmaking Service",
  "ExchangeCodeCreation",
  "Achievements",
  "Leaderboards",
  "Matchmaking",
  "Metrics",
  "PlayerReports",
  "Sanctions",
  "Stats",
  "TitleStorage",
  "Voice",
  "CommerceService",
  "FNResonanceService",
  "MagpieService",
  "PCBService",
  "QuestService",
];

function normalizeAccountId(value: unknown, fallback = "atlas") {
  let accountId = typeof value === "string" && value.trim() ? value.trim() : fallback;
  if (accountId.includes("@")) {
    accountId = accountId.split("@")[0];
  }
  return accountId || fallback;
}

function decodeTokenLoose(token: string): jwt.JwtPayload {
  const cleanToken = token.replace(/^eg1~/, "");
  const decoded = jwt.decode(cleanToken);
  if (decoded && typeof decoded === "object") {
    return decoded as jwt.JwtPayload;
  }

  return jwt.verify(cleanToken, "AtlasKey") as jwt.JwtPayload;
}

function safeDecodeTokenLoose(token: unknown): jwt.JwtPayload | null {
  if (typeof token !== "string" || !token.trim()) {
    return null;
  }

  try {
    return decodeTokenLoose(token);
  } catch {
    return null;
  }
}

export default function () {
  app.post("/account/api/oauth/token", async (c) => {
    const body: requestBody = await c.req.parseBody();
    const userAgent = c.req.header("user-agent") || "";
    logAuth("oauth/token request", {
      userAgent,
      grantType: body.grant_type,
      username: body.username,
      hasPassword: typeof body.password === "string",
    });
    let accountId = normalizeAccountId(body.username);

    // Only log actual player logins, not default/system accounts
    if (body.username && accountId !== "atlas") {
      const versionMatch = userAgent.match(/(?:Fortnite|UEFN)[^0-9]*([0-9]+(?:\.[0-9]+){1,3})/i);
      const versionLabel = versionMatch ? versionMatch[1] : "unknown";
      setStatusMessage(`[BACKEND] ${accountId} logged in on version ${versionLabel}`);
    }

    let t = jwt.sign(
      {
        email: accountId,
        password: "Atlaspassword",
        type: "access",
      },
      "AtlasKey"
    );

    logAuth("oauth/token issued", { accountId });
    return c.json({
      access_token: `eg1~${t}`,
      expires_in: 28800,
      expires_at: "9999-12-02T01:12:01.100Z",
      token_type: "bearer",
      refresh_token: `eg1~${t}`,
      refresh_expires: 86400,
      refresh_expires_at: "9999-12-02T01:12:01.100Z",
      account_id: accountId,
      client_id: "clientId",
      internal_client: true,
      client_service: "fortnite",
      display_name: accountId,
      displayName: accountId,
      app: "fortnite",
      in_app_id: accountId,
      device_id: "deviceId",
    });
  });

  app.post("/auth/v1/oauth/token", async (c) => {
    const userAgent = c.req.header("user-agent") || "";
    const body: requestBody = await c.req.parseBody().catch(() => ({}));
    const grantType = body.grant_type || "client_credentials";
    const deploymentId = body.deployment_id || "62a9473a2dca46b29ccf17577fcf42d7";
    const nonce = body.nonce || "";
    logAuth("auth/v1/oauth/token request", { userAgent, grantType });

    const sign = (claims: Record<string, unknown>) =>
      jwt.sign(
        {
          ...claims,
          iat: Math.floor(Date.now() / 1000),
          exp: 2147483647,
          jti: crypto.randomUUID().replace(/-/g, ""),
        },
        "AtlasKey",
        {
          header: { alg: "HS256", kid: "2022-06-14T06:17:57.047928700Z" },
        },
      );

    if (grantType === "external_auth") {
      const externalClaims = safeDecodeTokenLoose(body.external_auth_token) ?? {};
      const accountId = normalizeAccountId(
        externalClaims.sub || externalClaims.email || body.account_id,
      );
      const displayName = normalizeAccountId(
        externalClaims.dn || externalClaims.displayName || accountId,
      );

      const accessToken = sign({
        clientId: "ec684b8c687f479fadea3cb2ad83f5c6",
        role: "GameClient",
        productId: "prod-fn",
        iss: "eos",
        env: "prod",
        nonce,
        organizationId: "o-aa83a0a9bc45e98c80c1b1c9d92e9e",
        features: eosFeatures,
        productUserId: accountId,
        organizationUserId: "000185f80b9a4dc3aaf1ca83611c2bf5",
        clientIp: c.req.header("x-forwarded-for") || "127.0.0.1",
        deploymentId,
        sandboxId: "fn",
        tokenType: "userToken",
        account: {
          idp: "epicgames",
          displayName,
          id: accountId,
          plf: "other",
        },
      });

      const idToken = sign({
        aud: "ec684b8c687f479fadea3cb2ad83f5c6",
        sub: accountId,
        pfsid: "fn",
        act: {
          pltfm: "other",
          eaid: displayName,
          eat: "epicgames",
        },
        pfdid: deploymentId,
        iss: "http://atlas/auth/v1/oauth",
        tokenType: "idToken",
        pfpid: "prod-fn",
      });

      return c.json({
        access_token: accessToken,
        token_type: "bearer",
        expires_at: "9999-12-31T23:59:59.999Z",
        nonce,
        features: eosFeatures,
        organization_id: "o-aa83a0a9bc45e98c80c1b1c9d92e9e",
        product_id: "prod-fn",
        sandbox_id: "fn",
        deployment_id: deploymentId,
        organization_user_id: "000185f80b9a4dc3aaf1ca83611c2bf5",
        product_user_id: accountId,
        product_user_id_created: false,
        id_token: idToken,
        expires_in: 3599,
      });
    }

    if (grantType === "refresh_token") {
      const refreshClaims = safeDecodeTokenLoose(body.refresh_token) ?? {};
      const accountId = normalizeAccountId(refreshClaims.sub || refreshClaims.email);
      const displayName = normalizeAccountId(refreshClaims.dn || accountId);
      const accessToken = sign({
        sub: accountId,
        pfsid: "fn",
        iss: "http://atlas/epic/oauth/v2",
        dn: displayName,
        pfpid: "prod-fn",
        aud: "ec684b8c687f479fadea3cb2ad83f5c6",
        pfdid: deploymentId,
        t: "epic_id_r",
        appid: "fghi4567FNFBKFz3E4TROb0bmPS8h1GW",
        scope: "basic_profile friends_list openid offline_access presence",
      });

      return c.json({
        access_token: accessToken,
        expires_in: 15552000,
        expires_at: "9999-12-31T23:59:59.999Z",
        token_type: "bearer",
        refresh_token: accessToken,
        refresh_expires: 15552000,
        refresh_expires_at: "9999-12-31T23:59:59.999Z",
        account_id: accountId,
        client_id: "3e13c5c57f594a578abe516eecb673fe",
        internal_client: true,
        client_service: "3fd15bc288014f698cca1a3d1f01c7af",
        scope: ["basic_profile", "friends_list", "openid", "offline_access", "presence"],
        displayName,
        app: "3fd15bc288014f698cca1a3d1f01c7af",
        in_app_id: accountId,
        device_id: "ATLAS",
        product_id: "3fd15bc288014f698cca1a3d1f01c7af",
        sandbox_id: "fn",
        deployment_id: deploymentId,
        application_id: "fghi4567UG3ZXlhvevzKJI65wfTUoYBC",
        acr: "urn:epic:loa:aal1",
        auth_time: new Date().toISOString(),
      });
    }

    let access_token = sign(
      {
        clientId: "ec684b8c687f479fadea3cb2ad83f5c6",
        role: "GameClient",
        productId: "prod-fn",
        iss: "eos",
        env: "prod",
        organizationId: "o-aa83a0a9bc45e98c80c1b1c9d92e9e",
        features: eosFeatures,
        deploymentId,
        sandboxId: "fn",
        tokenType: "clientToken",
      },
    );
    return c.json({
      access_token: access_token,
      token_type: "bearer",
      expires_at: "9999-12-31T23:59:59.999Z",
      features: eosFeatures,
      organization_id: "o-aa83a0a9bc45e98c80c1b1c9d92e9e",
      product_id: "prod-fn",
      sandbox_id: "fn",
      deployment_id: deploymentId,
      expires_in: 3599,
    });
  });

  app.post("/publickey/v2/publickey", async (c) => {
    const body: requestBody = await c.req.parseBody().catch(() => ({}));
    const accountId = normalizeAccountId(body.account_id || body.accountId || body.username, "");
    const key = typeof body.key === "string" ? body.key : "";
    logAuth("publickey request", { accountId, hasKey: key.length > 0 });

    const token = jwt.sign(
      {
        account_id: accountId,
        generated: 1731795408,
        key_guid: "2e57bba7-4a7a-423c-b4b4-853acfcf019c",
        kid: "20230621",
        key,
        expiration: "9999-12-31T23:59:59.999Z",
        type: "legacy",
      },
      "AtlasKey",
      {
        header: { alg: "HS256", kid: "20230621" },
      },
    );

    return c.json({
      key,
      account_id: accountId,
      key_guid: "2e57bba7-4a7a-423c-b4b4-853acfcf019c",
      kid: "20230621",
      expiration: "9999-12-31T23:59:59.999Z",
      jwt: token,
      type: "legacy",
    });
  });

  app.post("/epic/oauth/v2/token", async (c) => {
    const body: any = await c.req.parseBody();
    const refreshToken = body.refresh_token || "";
    logAuth("epic/oauth/v2/token request", {
      grantType: body.grant_type,
      hasRefresh: typeof refreshToken === "string" && refreshToken.length > 0,
      refreshLength: typeof refreshToken === "string" ? refreshToken.length : 0,
    });
    const decoded = safeDecodeTokenLoose(refreshToken);
    if (!decoded) {
      logAuth("epic/oauth/v2/token using local fallback account");
    }
    const decodedAccountId = normalizeAccountId(
      decoded?.email || decoded?.sub || decoded?.account_id || body.account_id || body.username,
    );
    const decodedDisplayName = normalizeAccountId(
      decoded?.dn || decoded?.displayName || decodedAccountId,
      decodedAccountId,
    );

    let access_token = jwt.sign(
      {
        sub: decodedAccountId,
        pfsid: "fn",
        iss: "https://api.epicgames.dev/epic/oauth/v1",
        dn: decodedDisplayName,
        nonce: "n-01/jkXYh/9P5JimUEpSisDyK3Xw=",
        pfpid: "prod-fn",
        sec: 1,
        aud: "ec684b8c687f479fadea3cb2ad83f5c6",
        pfdid: "62a9473a2dca46b29ccf17577fcf42d7",
        t: "epic_id",
        scope: body.scope || c.req.query("scope") || "basic_profile friends_list openid presence",
        appid: "fghi4567FNFBKFz3E4TROb0bmPS8h1GW",
        exp: 9668536326,
        iat: 1668529126,
        jti: "c01f29504dcd42f9b68cf55759392928",
      },
      "AtlasKey"
    );

    let refresh_token = jwt.sign(
      {
        sub: decodedAccountId,
        pfsid: "fn",
        iss: "https://api.epicgames.dev/epic/oauth/v1",
        dn: decodedDisplayName,
        pfpid: "prod-fn",
        aud: "ec684b8c687f479fadea3cb2ad83f5c6",
        pfdid: "62a9473a2dca46b29ccf17577fcf42d7",
        t: "epic_id",
        appid: "fghi4567FNFBKFz3E4TROb0bmPS8h1GW",
        scope: body.scope || c.req.query("scope") || "basic_profile friends_list openid presence",
        exp: 9668557926,
        iat: 1668529126,
        jti: "c01f29504dcd42f9b68cf55759392928",
      },
      "AtlasKey"
    );

    let id_token = jwt.sign(
      {
        sub: decodedAccountId,
        pfsid: "fn",
        iss: "https://api.epicgames.dev/epic/oauth/v1",
        dn: decodedDisplayName,
        nonce: "n-e3Kcqw0hulXkbebFRBL8o5AwL3M=",
        pfpid: "prod-fn",
        aud: "ec684b8c687f479fadea3cb2ad83f5c6",
        pfdid: "62a9473a2dca46b29ccf17577fcf42d7",
        t: "id_token",
        appid: "fghi4567FNFBKFz3E4TROb0bmPS8h1GW",
        exp: 9668536326,
        iat: 1668529126,
        jti: "c01f29504dcd42f9b68cf55759392928",
      },
      "AtlasKey"
    );

    return c.json({
      scope: "basic_profile friends_list openid presence",
      token_type: "bearer",
      acr: "AAL1",
      access_token: "eg1~" + access_token,
      expires_in: 7200,
      expires_at: "9999-12-31T23:59:59.999Z",
      refresh_token: "eg1~" + refresh_token,
      refresh_expires_in: 28800,
      refresh_expires_at: "9999-12-31T23:59:59.999Z",
      account_id: decodedAccountId,
      client_id: "ec684b8c687f479fadea3cb2ad83f5c6",
      application_id: "fghi4567FNFBKFz3E4TROb0bmPS8h1GW",
      selected_account_id: decodedAccountId,
      id_token: id_token,
      merged_accounts: [],
      auth_time: new Date().toISOString(),
    });
  });

  app.post("/epic/oauth/v2/tokenInfo", async (c) => {
    const authorization = c.req.header("authorization") ?? "";
    const clientId = authorization.toLowerCase().startsWith("basic ")
      ? (() => {
          try {
            return Buffer.from(authorization.slice(6), "base64").toString("utf8").split(":")[0] || "clientId";
          } catch {
            return "clientId";
          }
        })()
      : "clientId";

    return c.json({
      active: true,
      scope: "basic_profile friends_list openid presence",
      token_type: "bearer",
      expires_in: 2147483647,
      expires_at: "9999-12-31T23:59:59.999Z",
      account_id: "atlas",
      client_id: clientId,
      application_id: "fghi4567FNFBKFz3E4TROb0bmPS8h1GW",
    });
  });

  app.get("/account/api/oauth/verify", async (c) => {
    const authorization = c.req.header("authorization");
    let accountId = "Atlas";
    if (authorization) {
      try {
        const claims = decodeTokenLoose(authorization.replace(/^bearer\s+/i, ""));
        accountId = normalizeAccountId(claims.email || claims.sub || claims.account_id, accountId);
      } catch {
        // Keep the local fallback.
      }
    }
    logAuth("oauth/verify request", { hasAuthHeader: !!authorization, accountId });

    return c.json({
      token: authorization,
      session_id: "9a1f5e80b47d2c3e6f8a0dc592b4fe7d",
      token_type: "bearer",
      client_id: "clientId",
      internal_client: true,
      client_service: "fortnite",
      account_id: accountId,
      expires_in: 28800,
      expires_at: "9999-12-02T01:12:01.100Z",
      auth_method: "exchange_code",
      displayName: accountId,
      app: "fortnite",
      in_app_id: accountId,
      device_id: "deviceId",
    });
  });

  app.delete("/account/api/oauth/sessions/kill/*", async (c) => {
    logAuth("oauth/sessions/kill");
    c.status(204);
    return c.json({});
  });

  app.get("/account/api/public/account/:accountId", async (c) => {
    let accountId = c.req.param("accountId");

    if (accountId.includes("@")) {
      accountId = accountId.split("@")[0];
    }

    return c.json({
      id: accountId,
      displayName: accountId,
      name: accountId,
      email: accountId + "@atlas.com",
      failedLoginAttempts: 0,
      lastLogin: new Date().toISOString(),
      numberOfDisplayNameChanges: 0,
      ageGroup: "UNKNOWN",
      headless: false,
      country: "US",
      lastName: "Server",
      preferredLanguage: "en",
      canUpdateDisplayName: false,
      tfaEnabled: false,
      emailVerified: true,
      minorVerified: false,
      minorExpected: false,
      minorStatus: "NOT_MINOR",
      cabinedMode: false,
      hasHashedEmail: false,
    });
  });

  app.get("/account/api/public/account", async (c) => {
    const response = [];

    const query = c.req.query("accountId");

    if (typeof query === "string") {
      let accountId = query;
      if (accountId.includes("@")) {
        accountId = accountId.split("@")[0];
      }
      response.push({
        id: accountId,
        displayName: accountId,
        externalAuths: {},
      });
    }

    if (Array.isArray(query)) {
      for (let accountId of query) {
        if (accountId.includes("@")) {
          accountId = accountId.split("@")[0];
        }
        response.push({
          id: accountId,
          displayName: accountId,
          externalAuths: {},
        });
      }
    }

    return c.json(response);
  });
}
