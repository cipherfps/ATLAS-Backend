import app from "../..";
import fs from "node:fs";
import path from "node:path";

interface Version {
  season: number;
  build: number;
  CL: string;
  lobby: string;
}

export default function getVersion(c: any): Version {
  let ver: Version = { season: 0, build: 0.0, CL: "0", lobby: "" };

  if (c.req.header("user-agent")) {
    const userAgent = c.req.header("user-agent");
    let CL = "";
    let userAgentParts = userAgent.split("-");
    CL = userAgentParts[userAgentParts.length - 1].split(" ")[0].split(",")[0];

    let buildIndex = userAgent.indexOf("Release-");
    if (buildIndex !== -1) {
      let build = userAgent
        .substring(buildIndex + 8)
        .split("-")[0];
      let buildP = build.split(".");
      ver.season = parseInt(buildP[0], 10);
      ver.build = parseFloat(`${buildP[0]}.${buildP[1]}${buildP[2]}`);
      ver.CL = CL;
      ver.lobby = `LobbySeason${ver.season}`;
    } else {
      try {
        const logDir = path.join(__dirname, "../../../logs");
        if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });
        fs.appendFileSync(
          path.join(logDir, "ua-debug.log"),
          `[${new Date().toISOString()}] Missing Release- in user-agent: ${userAgent}\n`
        );
      } catch {
        // swallow logging errors
      }
    }
  } else {
    try {
      const logDir = path.join(__dirname, "../../../logs");
      if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });
      fs.appendFileSync(
        path.join(logDir, "ua-debug.log"),
        `[${new Date().toISOString()}] Missing user-agent header\n`
      );
    } catch {
      // swallow logging errors
    }
  }
  return ver;
}
