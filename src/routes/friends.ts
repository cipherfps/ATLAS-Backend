import { app } from "..";

const emptyList: unknown[] = [];
const defaultSettings = {
  acceptInvites: "friends",
  invitePermission: "all",
  mutualPrivacy: "all",
  inviteTimeoutSeconds: 0,
};

export default function () {
  app.get("/friends/api/public/friends/:accountId", async (c) => {
    return c.json(emptyList);
  });

  app.get("/friends/api/public/blocklist/:accountId", async (c) => {
    return c.json(emptyList);
  });

  app.get("/friends/api/public/list/fortnite/:accountId/recentPlayers", async (c) => {
    return c.json(emptyList);
  });

  app.get("/friends/api/v1/:accountId/settings", async (c) => {
    return c.json(defaultSettings);
  });

  app.get("/friends/api/v1/:accountId/summary", async (c) => {
    const accountId = c.req.param("accountId");
    return c.json({
      accountId,
      friends: [],
      incoming: [],
      outgoing: [],
      blocklist: [],
      suggested: [],
      settings: defaultSettings,
    });
  });
}
