import app from "..";
import getVersion from "../utils/handlers/getVersion";
import fs from 'node:fs'
import path from 'node:path'

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
                        Hype: 575,
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
}