import { setStatusMessage } from "../../index";

interface MatchmakingPayload {
  region?: string;
  playlist?: string;
  type?: string;
  key?: string;
  bucket?: string;
  version?: string;
}

export function startMatchmakingWebSocket(port: number = 5555) {
  Bun.serve({
    port,
    fetch(req, server) {
      const success = server.upgrade(req);
      if (success) {
        return undefined;
      }
      return new Response("WebSocket upgrade failed", { status: 500 });
    },
    websocket: {
      open(ws) {
        setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Connected`);
        
        // Generate IDs
        const ticketId = crypto.randomUUID().replace(/-/gi, "").toUpperCase();
        const matchId = crypto.randomUUID().replace(/-/gi, "").toUpperCase();
        const sessionId = crypto.randomUUID().replace(/-/gi, "").toUpperCase();
        
        // Voltronite's matchmaking sequence
        const events = [
          { 
            delay: 200, 
            name: "StatusUpdate", 
            payload: { state: "Connecting" } 
          },
          {
            delay: 1000,
            name: "StatusUpdate",
            payload: { totalPlayers: 1, connectedPlayers: 1, state: "Waiting" },
          },
          {
            delay: 2000,
            name: "StatusUpdate",
            payload: {
              ticketId,
              queuedPlayers: 0,
              estimatedWaitSec: 0,
              status: {},
              state: "Queued",
            },
          },
          {
            delay: 6000,
            name: "StatusUpdate",
            payload: { matchId, state: "SessionAssignment" },
          },
          {
            delay: 8000,
            name: "Play",
            payload: { matchId, sessionId, joinDelaySec: 1 },
          },
        ];

        events.forEach(({ delay, name, payload }) => {
          setTimeout(() => {
            if (ws.readyState === 1) { // 1 = OPEN
              ws.send(JSON.stringify({ name, payload }));
              setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m ${payload.state || name}`);
            }
          }, delay);
        });
      },
      message(ws, message) {
        try {
          const payload = JSON.parse(message as string);
          setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Message received`);
        } catch (error) {
          console.error(`[Matchmaking] Error processing message: ${error}`);
        }
      },
      close(ws) {
        setStatusMessage(`\x1b[33m[MATCHMAKING]\x1b[0m Disconnected`);
      },
      error(ws, error) {
        console.error(`[Matchmaking] WebSocket error: ${error}`);
      },
    },
  });
}
