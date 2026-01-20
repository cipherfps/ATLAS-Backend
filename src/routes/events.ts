import app from "..";
import getVersion from "../utils/handlers/getVersion";
import fs from 'node:fs'
import path from 'node:path'
import ini from "ini";

export default function () {
    app.get("/api/v1/events/Fortnite/download/:accountId", async (c) => {
        const accountId = c.req.param("accountId");

        try {
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

            // Load player's arena points from their profile if save is enabled
            let arenaHype = 0;
            if (saveArenaPoints) {
                try {
                    const profilePath = path.join(
                        __dirname, "..", "..", "static", "profiles", accountId, "profile_athena.json"
                    );
                    const profileData = fs.readFileSync(profilePath, "utf-8");
                    const profile = JSON.parse(profileData);
                    arenaHype = profile?.stats?.attributes?.arena_hype || 0;
                } catch (err) {
                    // Profile doesn't exist yet or doesn't have arena_hype, default to 0
                    arenaHype = 0;
                }
            }

            const ver = getVersion(c);
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
                    tokens: [
                        `ARENA_S${ver.season}_Division1`,
                    ],
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
                        
                        // Save profile
                        fs.writeFileSync(profilePath, JSON.stringify(profile, null, 2));
                        
                        console.log(`\x1b[32m[ARENA]\x1b[0m ${accountId} earned arena points! New total: \x1b[33m${newHype}\x1b[0m`);
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
}