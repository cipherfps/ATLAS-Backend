import app from "..";
import getVersion from "../utils/handlers/getVersion";
import fs from 'node:fs'
import path from 'node:path'
import ini from "ini";

export default function () {
    app.get("/api/v1/events/Fortnite/download/:accountId", async (c) => {
        const accountId = c.req.param("accountId");

        try {
            const ver = getVersion(c);
            
            // Arena is only available for versions 8.0+ (similar to Core-Backend)
            if (ver.season < 8) {
                return c.json([]);
            }

            const eventsData = await fs.readFileSync(
                path.join(__dirname, "..", "..", "static", "events", "events.json"),
                "utf-8",
            );
            const events = JSON.parse(eventsData);

            const arenaTemplatesData = await fs.readFileSync(
                path.join(__dirname, "..", "..", "static", "events", "template.json"),
                "utf-8",
            );
            const arenaTemplates = JSON.parse(arenaTemplatesData);

            // Load config to check if arena points should be saved
            const config = ini.parse(
                fs.readFileSync(path.join(__dirname, "..", "config", "config.ini"), "utf-8")
            );
            const saveArenaPoints = config.SaveArenaPoints === "true" || config.SaveArenaPoints === true;

            // Load player's arena points and division from their profile if save is enabled
            let arenaHype = 0;
            let arenaDivisions: string[] = [`ARENA_S${ver.season}_Division1`];
            if (saveArenaPoints) {
                try {
                    const profilePath = path.join(
                        __dirname, "..", "..", "static", "profiles", accountId, "profile_athena.json"
                    );
                    const profileData = fs.readFileSync(profilePath, "utf-8");
                    const profile = JSON.parse(profileData);
                    arenaHype = profile?.stats?.attributes?.arena_hype || 0;
                    
                    // Load divisions if they exist, otherwise default to Division1
                    const savedDivisions = profile?.stats?.attributes?.arena_divisions;
                    if (Array.isArray(savedDivisions) && savedDivisions.length > 0) {
                        arenaDivisions = savedDivisions;
                    }
                } catch (err) {
                    // Profile doesn't exist yet or doesn't have arena data, use defaults
                    arenaHype = 0;
                    arenaDivisions = [`ARENA_S${ver.season}_Division1`];
                }
            }
            const updatedEvents = events.concat([]).map((evt: any) => {
                const eventObj = JSON.parse(JSON.stringify(evt));
                if (typeof eventObj.eventId === "string") {
                    eventObj.eventId = eventObj.eventId.replace(/S13/g, `S${ver.season}`);
                }
                if (Array.isArray(eventObj.eventWindows)) {
                    eventObj.eventWindows = eventObj.eventWindows.map((window: any) => {
                        const windowObj = { ...window };
                        if (typeof windowObj.eventTemplateId === "string") {
                            windowObj.eventTemplateId = windowObj.eventTemplateId.replace(/S13/g, `S${ver.season}`);
                        }
                        if (typeof windowObj.eventWindowId === "string") {
                            windowObj.eventWindowId = windowObj.eventWindowId.replace(/S13/g, `S${ver.season}`);
                        }
                        if (Array.isArray(windowObj.requireAllTokens)) {
                            windowObj.requireAllTokens = windowObj.requireAllTokens.map((token: string) =>
                                token.replace(/S13/g, `S${ver.season}`)
                            );
                        }
                        if (Array.isArray(windowObj.requireNoneTokensCaller)) {
                            windowObj.requireNoneTokensCaller = windowObj.requireNoneTokensCaller.map((token: string) =>
                                token.replace(/S13/g, `S${ver.season}`)
                            );
                        }
                        return windowObj;
                    });
                }
                return eventObj;
            });

            const updatedTemplates = [
                ...arenaTemplates,
            ].map((template: any) => {
                const templateObj = { ...template };
                if (typeof templateObj.eventTemplateId === "string") {
                    templateObj.eventTemplateId = templateObj.eventTemplateId.replace(/S13/g, `S${ver.season}`);
                }
                return templateObj;
            });

            const arena = {
                events: updatedEvents,
                player: {
                    accountId: accountId,
                    gameId: "Fortnite",
                    groupIdentity: {},
                    pendingPayouts: [],
                    pendingPenalties: {},
                    persistentScores: {
                        Hype: arenaHype,
                    },
                    teams: {
                        [`epicgames_Arena_S${ver.season}_Solo:Arena_S${ver.season}_Division1_Solo`]: [accountId],
                        [`epicgames_Arena_S${ver.season}_Solo:Arena_S${ver.season}_Division2_Solo`]: [accountId],
                        [`epicgames_Arena_S${ver.season}_Solo:Arena_S${ver.season}_Division3_Solo`]: [accountId],
                        [`epicgames_Arena_S${ver.season}_Solo:Arena_S${ver.season}_Division4_Solo`]: [accountId],
                        [`epicgames_Arena_S${ver.season}_Solo:Arena_S${ver.season}_Division5_Solo`]: [accountId],
                        [`epicgames_Arena_S${ver.season}_Solo:Arena_S${ver.season}_Division6_Solo`]: [accountId],
                        [`epicgames_Arena_S${ver.season}_Solo:Arena_S${ver.season}_Division7_Solo`]: [accountId],
                        [`epicgames_Arena_S${ver.season}_Solo:Arena_S${ver.season}_Division8_Solo`]: [accountId],
                        [`epicgames_Arena_S${ver.season}_Solo:Arena_S${ver.season}_Division9_Solo`]: [accountId],
                        [`epicgames_Arena_S${ver.season}_Solo:Arena_S${ver.season}_Division10_Solo`]: [accountId],
                    },
                    tokens: arenaDivisions,
                },
                templates: updatedTemplates,
            }
            return c.json(arena);
        } catch (error) {
            console.error(error)
            return c.json([], 200)
        };
    });

    // Endpoint to update arena points (scores) after matches
    app.post("/api/v1/events/Fortnite/:eventId/:eventWindowId/:accountId", async (c) => {
        const accountId = c.req.param("accountId");
        
        try {
            const body = await c.req.json();
            
            // Load config to check if arena points should be saved
            const config = ini.parse(
                fs.readFileSync(path.join(__dirname, "..", "config", "config.ini"), "utf-8")
            );
            const saveArenaPoints = config.SaveArenaPoints === "true" || config.SaveArenaPoints === true;
            
            if (saveArenaPoints && body && typeof body.finalScores === 'object') {
                // Check if Hype score exists in the report
                if (body.finalScores.Hype !== undefined) {
                    const newHype = body.finalScores.Hype;
                    
                    // Load player profile
                    const profilesDir = path.join(__dirname, "..", "..", "static", "profiles");
                    const accountProfilesDir = path.join(profilesDir, accountId);
                    const profilePath = path.join(accountProfilesDir, "profile_athena.json");
                    
                    try {
                        // Create profile directory if it doesn't exist
                        await fs.promises.mkdir(accountProfilesDir, { recursive: true });
                        
                        let profile;
                        try {
                            const profileData = fs.readFileSync(profilePath, "utf-8");
                            profile = JSON.parse(profileData);
                        } catch {
                            // Profile doesn't exist, load from template
                            const templatePath = path.join(profilesDir, "profile_athena.json");
                            const templateData = fs.readFileSync(templatePath, "utf-8");
                            profile = JSON.parse(templateData);
                            profile.accountId = accountId;
                        }
                        
                        // Ensure stats.attributes exists
                        if (!profile.stats) profile.stats = {};
                        if (!profile.stats.attributes) profile.stats.attributes = {};
                        
                        // Update arena_hype
                        profile.stats.attributes.arena_hype = newHype;
                        
                        // Calculate division based on hype (similar to real Arena)
                        const ver = getVersion(c);
                        let divisions: string[] = [];
                        if (newHype > 15000) divisions.push(`ARENA_S${ver.season}_Division10`);
                        if (newHype >= 12000) divisions.push(`ARENA_S${ver.season}_Division9`);
                        if (newHype >= 9000) divisions.push(`ARENA_S${ver.season}_Division8`);
                        if (newHype >= 6500) divisions.push(`ARENA_S${ver.season}_Division7`);
                        if (newHype >= 4500) divisions.push(`ARENA_S${ver.season}_Division6`);
                        if (newHype >= 3000) divisions.push(`ARENA_S${ver.season}_Division5`);
                        if (newHype >= 1750) divisions.push(`ARENA_S${ver.season}_Division4`);
                        if (newHype >= 900) divisions.push(`ARENA_S${ver.season}_Division3`);
                        if (newHype >= 300) divisions.push(`ARENA_S${ver.season}_Division2`);
                        divisions.push(`ARENA_S${ver.season}_Division1`);
                        
                        profile.stats.attributes.arena_divisions = divisions;
                        
                        // Save profile
                        fs.writeFileSync(profilePath, JSON.stringify(profile, null, 2));
                    } catch (err) {
                        console.error(`\x1b[31m[ARENA]\x1b[0m Failed to save arena points for ${accountId}:`, err);
                    }
                }
            }
            
            // Return success response
            return c.json({ success: true });
        } catch (error) {
            console.error("[EVENTS] Error in score update:", error);
            return c.json({ success: false }, 500);
        }
    });

    // Arena history endpoint
    app.get("/api/v1/events/Fortnite/:eventId/history/:accountId", async (c) => {
        const accountId = c.req.param("accountId");
        const eventId = c.req.param("eventId");
        const ver = getVersion(c);
        
        // Return empty for versions before 8.0
        if (ver.season < 8) {
            return c.json([]);
        }
        
        return c.json([
            {
                eventId: eventId,
                eventWindowId: `Arena_S${ver.season}_Division1_Solo`,
                teamId: accountId,
                teamAccountIds: [accountId],
                sessionHistory: [],
                scoreKey: {
                    eventId: eventId,
                    eventWindowId: `Arena_S${ver.season}_Division1_Solo`,
                },
            },
        ]);
    });

    // Arena leaderboard endpoint
    app.get("/api/v1/leaderboards/Fortnite/:eventId/:eventWindowId/:accountId", async (c) => {
        const accountId = c.req.param("accountId");
        const eventId = c.req.param("eventId");
        const eventWindowId = c.req.param("eventWindowId");
        const ver = getVersion(c);
        
        // Return empty for versions before 8.0
        if (ver.season < 8) {
            return c.json({ entries: [], gameId: "Fortnite" });
        }
        
        return c.json({
            gameId: "Fortnite",
            eventId: eventId,
            eventWindowId: eventWindowId,
            page: 0,
            totalPages: 1,
            updatedTime: new Date().toISOString(),
            entries: [
                {
                    gameId: "Fortnite",
                    eventId: eventId,
                    eventWindowId: eventWindowId,
                    teamAccountIds: [accountId],
                    liveSessionId: "",
                    pointsEarned: 0,
                    score: 0,
                    rank: 1,
                    percentile: 0.0,
                    pointBreakdown: {},
                    sessionHistory: [],
                    tokens: [],
                },
            ],
        });
    });

    // Set subgroup endpoint (used in newer versions)
    app.post("/fortnite/api/game/v2/events/v2/setSubgroup/*", async (c) => {
        return c.json([]);
    });
}