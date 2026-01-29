import app from "..";
import getVersion from "../utils/handlers/getVersion";
import fs from "node:fs";
import path from "node:path";
import ini from "ini";

export default function () {
  app.get("/api/v1/games/fortnite/trackprogress/:accountId", async (c) => {
    // Get game version - ranked was added in Season 24.40
    const ver = getVersion(c);
    const accountId = c.req.param("accountId");
    
    // Return empty array for versions before 24.40 (ranked didn't exist)
    if (ver.season < 24 || (ver.season === 24 && ver.build < 24.4)) {
      return c.json([]);
    }
    
    // Try to load actual arena data from profile
    let currentDivision = 0;
    let highestDivision = 0;
    let promotionProgress = 0;
    
    try {
      const config = ini.parse(
        fs.readFileSync(path.join(__dirname, "..", "config", "config.ini"), "utf-8")
      );
      const saveArenaPoints = config.SaveArenaPoints === "true" || config.SaveArenaPoints === true;
      
      if (saveArenaPoints) {
        const profilePath = path.join(
          __dirname, "..", "..", "static", "profiles", accountId, "profile_athena.json"
        );
        const profileData = fs.readFileSync(profilePath, "utf-8");
        const profile = JSON.parse(profileData);
        const arenaHype = profile?.stats?.attributes?.arena_hype || 0;
        
        // Calculate division based on hype (0-9 for ranked system)
        if (arenaHype >= 15000) currentDivision = highestDivision = 9;
        else if (arenaHype >= 12000) currentDivision = highestDivision = 8;
        else if (arenaHype >= 9000) currentDivision = highestDivision = 7;
        else if (arenaHype >= 6500) currentDivision = highestDivision = 6;
        else if (arenaHype >= 4500) currentDivision = highestDivision = 5;
        else if (arenaHype >= 3000) currentDivision = highestDivision = 4;
        else if (arenaHype >= 1750) currentDivision = highestDivision = 3;
        else if (arenaHype >= 900) currentDivision = highestDivision = 2;
        else if (arenaHype >= 300) currentDivision = highestDivision = 1;
        
        // Calculate promotion progress within division
        const divisionThresholds = [0, 300, 900, 1750, 3000, 4500, 6500, 9000, 12000, 15000, 999999];
        const currentThreshold = divisionThresholds[currentDivision];
        const nextThreshold = divisionThresholds[currentDivision + 1];
        promotionProgress = (arenaHype - currentThreshold) / (nextThreshold - currentThreshold);
        promotionProgress = Math.max(0, Math.min(1, promotionProgress));
      }
    } catch (err) {
      // Profile doesn't exist or error reading, use defaults
    }
    
    return c.json([
      {
        gameId: "fortnite",
        trackguid: "hEKWqj",
        accountId: accountId,
        rankingType: "ranked-zb",
        lastUpdated: new Date().toISOString(),
        currentDivision: currentDivision,
        highestDivision: highestDivision,
        promotionProgress: promotionProgress,
        currentPlayerRanking: null,
      },
      {
        gameId: "fortnite",
        trackguid: "OiK9k9",
        accountId: accountId,
        rankingType: "ranked-br",
        lastUpdated: new Date().toISOString(),
        currentDivision: currentDivision,
        highestDivision: highestDivision,
        promotionProgress: promotionProgress,
        currentPlayerRanking: null,
      },
    ]);
  });
}
