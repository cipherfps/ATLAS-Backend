import { readConfig } from "../../config/config";
import { networkInterfaces } from "node:os";

const DEFAULT_MATCHMAKER_PORT = 5555;
const DEFAULT_GAME_SERVER_HOST = "127.0.0.1";
const DEFAULT_GAME_SERVER_PORT = 7777;

export interface ParsedEndpoint {
  host: string;
  port: number;
}

function readMatchmakingSetting(...keys: string[]): string | undefined {
  const config = readConfig();

  for (const key of keys) {
    const value = config[key];
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }

    const envValue = process.env[key];
    if (typeof envValue === "string" && envValue.trim()) {
      return envValue.trim();
    }
  }

  return undefined;
}

function isUsableIpv4Address(address: string): boolean {
  return Boolean(address) && address !== "127.0.0.1" && !address.startsWith("169.254.");
}

export function getRadminVpnIp(): string | null {
  const interfaces = networkInterfaces();
  const radminAddresses: string[] = [];
  const radminRangeAddresses: string[] = [];

  for (const [name, addresses] of Object.entries(interfaces)) {
    if (!addresses) {
      continue;
    }

    for (const address of addresses) {
      if (String(address.family) !== "IPv4" || address.internal || !isUsableIpv4Address(address.address)) {
        continue;
      }

      if (/radmin/i.test(name)) {
        radminAddresses.push(address.address);
      } else if (address.address.startsWith("26.")) {
        radminRangeAddresses.push(address.address);
      }
    }
  }

  return radminAddresses[0] ?? radminRangeAddresses[0] ?? null;
}

export function getDefaultMatchmakingHost(): string {
  return getRadminVpnIp() ?? DEFAULT_GAME_SERVER_HOST;
}

export function parseHostPort(value: string): ParsedEndpoint | null {
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }

  try {
    if (trimmed.startsWith("ws://") || trimmed.startsWith("wss://")) {
      const url = new URL(trimmed);
      const port = Number(url.port || (url.protocol === "wss:" ? 443 : 80));
      if (!url.hostname || !Number.isFinite(port) || port <= 0) {
        return null;
      }

      return { host: url.hostname, port };
    }
  } catch {
    return null;
  }

  const [host, portValue] = trimmed.split(":");
  const port = Number(portValue);
  if (!host || !Number.isFinite(port) || port <= 0 || port > 65535) {
    return null;
  }

  return { host, port };
}

export function getConfiguredMatchmakerUrl(): string {
  const configured =
    readMatchmakingSetting(
      "MatchMakerService.MatchMakerIp",
      "MatchMakerIp",
      "MATCHMAKER_IP",
    ) ?? `ws://${getDefaultMatchmakingHost()}:${DEFAULT_MATCHMAKER_PORT}`;

  if (configured.startsWith("ws://") || configured.startsWith("wss://")) {
    return configured;
  }

  return `ws://${configured}`;
}

export function getConfiguredMatchmakerPort(): number {
  const parsed = parseHostPort(getConfiguredMatchmakerUrl());
  return parsed?.port ?? DEFAULT_MATCHMAKER_PORT;
}

export function getConfiguredGameServer(): ParsedEndpoint {
  const configured = readMatchmakingSetting(
    "MatchMakerService.GameServerIp",
    "GameServerIp",
    "GAMESERVER_IP",
    "GAME_SERVER_IP",
  );

  const parsed = configured ? parseHostPort(configured) : null;
  if (parsed) {
    return parsed;
  }

  return {
    host: getDefaultMatchmakingHost(),
    port: DEFAULT_GAME_SERVER_PORT,
  };
}
