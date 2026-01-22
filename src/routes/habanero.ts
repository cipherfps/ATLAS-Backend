import app from "..";
import getVersion from "../utils/handlers/getVersion";

export default function () {
  app.get("/api/v1/games/fortnite/trackprogress/:accountId", async (c) => {
    // Get game version - ranked was added in Season 24.40
    const ver = getVersion(c);
    
    // Return empty array for versions before 24.40 (ranked didn't exist)
    if (ver.season < 24 || (ver.season === 24 && ver.build < 24.4)) {
      return c.json([]);
    }
    
    return c.json([
      {
        gameId: "fortnite",
        trackguid: "hEKWqj",
        accountId: c.req.param("accountId"),
        rankingType: "ranked-zb",
        lastUpdated: "1970-01-01T00:00:00Z",
        currentDivision: 0,
        highestDivision: 0,
        promotionProgress: 0,
        currentPlayerRanking: null,
      },
      {
        gameId: "fortnite",
        trackguid: "OiK9k9",
        accountId: c.req.param("accountId"),
        rankingType: "ranked-br",
        lastUpdated: "2023-11-05T19:51:28.002Z",
        currentDivision: 9,
        highestDivision: 18,
        promotionProgress: 0.88,
        currentPlayerRanking: null,
      },
    ]);
  });
}
