import { app } from "..";
import getVersion from "../utils/handlers/getVersion";
import { Atlas } from "../utils/handlers/errors";
import { atlasDataReadPath } from "../config/paths";
import fs from "node:fs";
import crypto from "crypto";

const ARENA_PLAYLISTS = [
  "playlist_showdownalt_solo",
  "playlist_showdownalt_duos",
  "playlist_showdownalt_trios",
] as const;

const ARENA_PLAYLIST_TITLES: Record<string, string> = {
  playlist_showdownalt_solo: "Arena Solo",
  playlist_showdownalt_duos: "Arena Duo",
  playlist_showdownalt_trios: "Arena Trio",
};

const DEFAULT_DISCOVERY_IMAGE =
  "https://raw.githubusercontent.com/cipherfps/ATLAS-Backend/refs/heads/gui/public/playlists/Late-Game-Arena.png";
const SEASON_29_PLUS_PRIMARY_PLAYLISTS = [
  "playlist_showdownalt_solo",
  "playlist_defaultsolo",
  "playlist_defaultduo",
  "playlist_trios",
  "playlist_defaultsquad",
] as const;

type DiscoveryLink = Record<string, any>;
type DiscoverySurface = Record<string, any>;

function readJsonFile(...parts: string[]): any {
  return JSON.parse(fs.readFileSync(atlasDataReadPath(...parts), "utf-8"));
}

function cloneDeep<T>(value: T): T {
  return JSON.parse(JSON.stringify(value));
}

type GeneratedPlaylistDefinition = {
  assetName: string;
  title: string;
  squadSize: number;
  gameType?: string;
  gameData?: string;
  lootTierData?: string;
  lootPackages?: string;
  missionGen?: string;
  minPlayers?: number;
  maxPlayers?: number;
  maxTeamCount?: number;
  allowSquadFill?: boolean;
  enforceSquadFill?: boolean;
  limitedTime?: boolean;
  defaultPlaylist?: boolean;
  releaseVersion?: string;
  gameplayTags?: string[];
  assetDataOverrides?: Record<string, any>;
};

const DEFAULT_BR_PLAYLIST_DATA = {
  gameData: "/Game/Athena/Playlists/AthenaCompositeGameData.AthenaCompositeGameData",
  lootTierData: "/Game/Athena/Playlists/AthenaCompositeLTD.AthenaCompositeLTD",
  lootPackages: "/Game/Athena/Playlists/AthenaCompositeLP.AthenaCompositeLP",
  missionGen: "/Game/World/MissionGens/Athena/MissionGen_Athena.MissionGen_Athena_C",
};

const GENERATED_PLAYLIST_DEFINITIONS: Record<string, GeneratedPlaylistDefinition> = {
  playlist_defaultsolo: {
    assetName: "Playlist_DefaultSolo",
    title: "Solo",
    squadSize: 1,
    minPlayers: 20,
    defaultPlaylist: true,
  },
  playlist_defaultduo: {
    assetName: "Playlist_DefaultDuo",
    title: "Duos",
    squadSize: 2,
    minPlayers: 20,
    defaultPlaylist: true,
  },
  playlist_trios: {
    assetName: "Playlist_Trios",
    title: "Trios",
    squadSize: 3,
    minPlayers: 20,
    maxTeamCount: 33,
    defaultPlaylist: true,
  },
  playlist_defaultsquad: {
    assetName: "Playlist_DefaultSquad",
    title: "Squads",
    squadSize: 4,
    minPlayers: 20,
    maxTeamCount: 25,
    defaultPlaylist: true,
  },
  playlist_quail: {
    assetName: "Playlist_Quail",
    title: "Remix: The Finale",
    squadSize: 1,
    minPlayers: 20,
    maxTeamCount: 100,
    limitedTime: false,
    defaultPlaylist: false,
    gameplayTags: [
      "Athena.Playlist.DefaultXP",
      "Athena.Playlist.Core",
      "Athena.Playlist.Solo",
    ],
    assetDataOverrides: {
      LootLevel: "1",
      MaxHumanAndBotParticipants: "100",
      RatingType: "fun",
      CustomGameChannel: "Squad",
      FriendlyFireType: "Off",
      MaxSquads: "-1",
      bIsTournament: false,
      RewardsPlacementThreshold: "3",
      EndOfMatchXpMultiplier: "20",
      bIsLargeTeamGame: false,
      bIsRankedMode: false,
      PlaylistId: "2",
      UIDisplaySubName: {
        Category: "Game",
        NativeCulture: "",
        Namespace: "",
        LocalizedStrings: [],
        bIsMinimalPatch: false,
        NativeString: "",
        Key: "",
      },
    },
  },
  playlist_showdownalt_solo: {
    assetName: "Playlist_ShowdownAlt_Solo",
    title: "Arena Solo",
    squadSize: 1,
    gameType: "BRArena",
    minPlayers: 80,
    allowSquadFill: false,
    enforceSquadFill: false,
    gameData: "/Game/Athena/Playlists/Showdown/AthenaCompositeGD_Showdown.AthenaCompositeGD_Showdown",
    lootTierData: "/Game/Athena/Playlists/Showdown/AthenaCompositeLTD_Showdown.AthenaCompositeLTD_Showdown",
    lootPackages: "/Game/Athena/Playlists/Showdown/AthenaCompositeLP_Showdown.AthenaCompositeLP_Showdown",
    releaseVersion: "6.30",
  },
  playlist_showdownalt_duos: {
    assetName: "Playlist_ShowdownAlt_Duos",
    title: "Arena Duos",
    squadSize: 2,
    gameType: "BRArena",
    minPlayers: 80,
    allowSquadFill: false,
    enforceSquadFill: false,
    gameData: "/Game/Athena/Playlists/Showdown/AthenaCompositeGD_Showdown.AthenaCompositeGD_Showdown",
    lootTierData: "/Game/Athena/Playlists/Showdown/AthenaCompositeLTD_Showdown.AthenaCompositeLTD_Showdown",
    lootPackages: "/Game/Athena/Playlists/Showdown/AthenaCompositeLP_Showdown.AthenaCompositeLP_Showdown",
    releaseVersion: "6.30",
  },
  playlist_showdownalt_trios: {
    assetName: "Playlist_ShowdownAlt_Trios",
    title: "Arena Trios",
    squadSize: 3,
    gameType: "BRArena",
    minPlayers: 80,
    maxTeamCount: 33,
    allowSquadFill: false,
    enforceSquadFill: false,
    gameData: "/Game/Athena/Playlists/Showdown/AthenaCompositeGD_Showdown.AthenaCompositeGD_Showdown",
    lootTierData: "/Game/Athena/Playlists/Showdown/AthenaCompositeLTD_Showdown.AthenaCompositeLTD_Showdown",
    lootPackages: "/Game/Athena/Playlists/Showdown/AthenaCompositeLP_Showdown.AthenaCompositeLP_Showdown",
    releaseVersion: "6.30",
  },
};

function shouldGenerateFortPlaylistAthenaAssets(ver: ReturnType<typeof getVersion>): boolean {
  return Math.abs(ver.build - 32.11) < 0.01 || ver.season === 32;
}

function requestPathLooksLikeSeason32(c: any): boolean {
  const path = c.req.path ?? "";
  return /(?:Release-|\/)32(?:[./-]|$)/i.test(path);
}

function normalizePlaylistAssetKey(name: string): string {
  return name.replace(/^FortPlaylistAthena:/i, "").toLowerCase();
}

function toPlaylistAssetName(name: string): string {
  const cleaned = name.replace(/^FortPlaylistAthena:/i, "");
  const known = Object.values(GENERATED_PLAYLIST_DEFINITIONS).find(
    (definition) => definition.assetName.toLowerCase() === cleaned.toLowerCase(),
  );
  if (known) {
    return known.assetName;
  }

  if (/^playlist_/i.test(cleaned)) {
    const suffix = cleaned.slice("playlist_".length);
    return `Playlist_${suffix
      .split("_")
      .filter(Boolean)
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join("_")}`;
  }

  return `Playlist_${cleaned
    .split("_")
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join("_")}`;
}

function inferPlaylistSquadSize(name: string): number {
  const lowerName = name.toLowerCase();
  if (lowerName.includes("solo")) {
    return 1;
  }
  if (lowerName.includes("duo")) {
    return 2;
  }
  if (lowerName.includes("trio")) {
    return 3;
  }
  if (lowerName.includes("squad")) {
    return 4;
  }

  return 1;
}

function titleFromPlaylistAssetName(assetName: string): string {
  const words = assetName
    .replace(/^Playlist_/i, "")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .split("_")
    .filter(Boolean);

  return words.length > 0 ? words.join(" ") : "Battle Royale";
}

function getGeneratedPlaylistDefinition(name: string): GeneratedPlaylistDefinition {
  const key = normalizePlaylistAssetKey(name);
  const knownDefinition =
    GENERATED_PLAYLIST_DEFINITIONS[key] ??
    Object.values(GENERATED_PLAYLIST_DEFINITIONS).find(
      (definition) => definition.assetName.toLowerCase() === key,
    );

  if (knownDefinition) {
    return knownDefinition;
  }

  const assetName = toPlaylistAssetName(name);
  return {
    assetName,
    title: titleFromPlaylistAssetName(assetName),
    squadSize: inferPlaylistSquadSize(assetName),
    defaultPlaylist: assetName.toLowerCase().includes("default"),
    limitedTime: !assetName.toLowerCase().includes("default"),
  };
}

function buildPlaylistTextProperty(text: string): Record<string, any> {
  return {
    Category: "Game",
    NativeCulture: "",
    Namespace: "",
    LocalizedStrings: [],
    bIsMinimalPatch: false,
    NativeString: text,
    Key: "",
  };
}

function buildGeneratedFortPlaylistAthenaAsset(playlistName: string): Record<string, any> {
  const definition = getGeneratedPlaylistDefinition(playlistName);
  const maxPlayers = definition.maxPlayers ?? 100;
  const maxTeamCount = definition.maxTeamCount ?? Math.max(1, Math.floor(maxPlayers / definition.squadSize));
  const allowSquadFill = definition.allowSquadFill ?? true;

  return {
    meta: {
      revision: 2,
      headRevision: 2,
      revisedAt: "2023-11-27T06:41:57.818Z",
      promotion: 3,
      promotedAt: "2023-11-27T06:43:00.452Z",
    },
    assetData: {
      PlaylistName: definition.assetName,
      UIDisplayName: buildPlaylistTextProperty(definition.title),
      UIDisplaySubName: buildPlaylistTextProperty(definition.title),
      UIDescription: buildPlaylistTextProperty(definition.title),
      MinPlayers: `${definition.minPlayers ?? 1}`,
      MaxPlayers: `${maxPlayers}`,
      MaxSquadSize: `${definition.squadSize}`,
      MaxTeamSize: `${definition.squadSize}`,
      MaxTeamCount: `${maxTeamCount}`,
      MaxSocialPartySize: `${definition.squadSize}`,
      GameType: definition.gameType ?? "BR",
      GameData: definition.gameData ?? DEFAULT_BR_PLAYLIST_DATA.gameData,
      LootTierData: definition.lootTierData ?? DEFAULT_BR_PLAYLIST_DATA.lootTierData,
      LootPackages: definition.lootPackages ?? DEFAULT_BR_PLAYLIST_DATA.lootPackages,
      PlaylistMissionGen: definition.missionGen ?? DEFAULT_BR_PLAYLIST_DATA.missionGen,
      bIsDefaultPlaylist: definition.defaultPlaylist ?? false,
      bLimitedTimeMode: definition.limitedTime ?? false,
      bAllowSquadFillOption: allowSquadFill,
      EnforceSquadFill: definition.enforceSquadFill ?? allowSquadFill,
      bAllowInGameMatchMaking: true,
      bAllowJoinInProgress: false,
      bAllowBackfill: false,
      bPreloadAthenaMapsForMatchmaking: true,
      bEnableCreativeMode: false,
      bRequireCrossplayEnabled: true,
      bRequirePickaxeInStartingInventory: true,
      bRewardsAllowXPProgression: true,
      bShouldSpreadTeams: true,
      bSkipAircraft: false,
      bUseDefaultSupplyDrops: true,
      primaryAssetId: `FortPlaylistAthena:${definition.assetName}`,
      FortReleaseVersion: {
        VersionName: definition.releaseVersion ?? "Legacy",
      },
      GameplayTagContainer: {
        GameplayTags: (definition.gameplayTags ?? [
          `Athena.Playlist.${definition.assetName.replace(/^Playlist_/i, "")}`,
        ]).map((TagName) => ({ TagName })),
      },
      ...(definition.assetDataOverrides ?? {}),
    },
  };
}

function buildFortPlaylistAthenaAssets(ver: ReturnType<typeof getVersion>): Record<string, any> {
  const assets: Record<string, any> = {};
  const playlistNames = new Set<string>();

  for (const playlistName of Object.keys(GENERATED_PLAYLIST_DEFINITIONS)) {
    playlistNames.add(playlistName);
  }

  for (const link of getMnemonicLinks(ver)) {
    const overridePlaylist = link?.metadata?.matchmaking?.override_playlist;
    if (typeof overridePlaylist === "string") {
      playlistNames.add(overridePlaylist);
    }
    if (link?.linkType === "BR:Playlist" && typeof link?.mnemonic === "string") {
      playlistNames.add(link.mnemonic);
    }
  }

  for (const playlistName of playlistNames) {
    const asset = buildGeneratedFortPlaylistAthenaAsset(playlistName);
    assets[asset.assetData.PlaylistName] = asset;
  }

  return assets;
}

function buildFortPlaylistAthenaDirectoryResponse(
  ver: ReturnType<typeof getVersion>,
  force = false,
): Record<string, any> {
  if (!force && !shouldGenerateFortPlaylistAthenaAssets(ver)) {
    return {};
  }

  return {
    FortPlaylistAthena: {
      meta: {
        promotion: 9,
      },
      assets: buildFortPlaylistAthenaAssets(ver),
    },
  };
}

function getNormalDiscoverySurface(): DiscoverySurface {
  return readJsonFile("static", "discovery", "menu.json");
}

function buildImageUrls(imageUrl: string): Record<string, string> {
  return {
    url_s: imageUrl,
    url_xs: imageUrl,
    url_m: imageUrl,
    url: imageUrl,
  };
}

function isArenaPlaylistMnemonic(mnemonic: unknown): mnemonic is (typeof ARENA_PLAYLISTS)[number] {
  return typeof mnemonic === "string" && (ARENA_PLAYLISTS as readonly string[]).includes(mnemonic);
}

function applyArenaImageMetadata(metadata?: Record<string, any> | null): Record<string, any> {
  const nextMetadata = metadata || {};
  nextMetadata.image_url = DEFAULT_DISCOVERY_IMAGE;
  nextMetadata.image_urls = buildImageUrls(DEFAULT_DISCOVERY_IMAGE);
  return nextMetadata;
}

function normalizeArenaLink(link: DiscoveryLink | null): DiscoveryLink | null {
  if (!link || !isArenaPlaylistMnemonic(link.mnemonic)) {
    return link;
  }

  link.metadata = applyArenaImageMetadata(link.metadata);
  return link;
}

function buildArenaPlaylistLink(
  mnemonic: string,
  template?: DiscoveryLink | null,
): DiscoveryLink {
  const link = template ? cloneDeep(template) : {};
  const title = ARENA_PLAYLIST_TITLES[mnemonic] || "Arena";

  link.namespace = "fn";
  link.accountId = link.accountId || "epic";
  link.creatorName = link.creatorName || "Epic";
  link.mnemonic = mnemonic;
  link.linkType = "BR:Playlist";
  link.active = true;
  link.disabled = false;
  link.version = link.version || 95;
  link.created = link.created || "2024-01-01T00:00:00.000Z";
  link.published = link.published || "2024-01-01T00:00:00.000Z";
  link.descriptionTags = Array.isArray(link.descriptionTags) ? link.descriptionTags : [];
  link.moderationStatus = link.moderationStatus || "Unmoderated";
  link.metadata = applyArenaImageMetadata(link.metadata);
  link.metadata.parent_set = "set_br_playlists";
  link.metadata.favorite_override = "set_br_playlists";
  link.metadata.play_history_override = "set_br_playlists";
  link.metadata.product_tag = "Product.BR.Build.Arena";
  link.metadata.matchmaking = {
    ...(link.metadata.matchmaking || {}),
    override_playlist: mnemonic,
  };
  link.metadata.alt_title = {
    ...(link.metadata.alt_title || {}),
    en: title,
  };
  link.metadata.title = title;
  link.metadata.video_vuid = link.metadata.video_vuid || "";
  link.metadata.tileSize = link.metadata.tileSize || "medium";

  return link;
}

function buildArenaModeSet(template?: DiscoveryLink | null): DiscoveryLink {
  const imageUrl = DEFAULT_DISCOVERY_IMAGE;

  return {
    namespace: "fn",
    accountId: "epic",
    creatorName: "Epic",
    mnemonic: "set_arena_playlists",
    linkType: "ModeSet",
    metadata: {
      image_url: imageUrl,
      image_urls: buildImageUrls(imageUrl),
      title: "Arena",
      locale: "en",
      video_vuid: "",
      sub_link_codes: [...ARENA_PLAYLISTS],
      default_sub_link_code: "playlist_showdownalt_solo",
      alt_title: {
        en: "Arena",
      },
    },
    version: 1,
    active: true,
    disabled: false,
    created: "2024-01-01T00:00:00.000Z",
    published: "2024-01-01T00:00:00.000Z",
    descriptionTags: [],
    moderationStatus: "Unmoderated",
    discoveryIntent: "PUBLIC",
  };
}

function buildHabaneroModeSet(template?: DiscoveryLink | null): DiscoveryLink {
  const modeSet = buildArenaModeSet(template);
  modeSet.mnemonic = "set_habanero_playlists";
  modeSet.metadata = {
    ...(modeSet.metadata || {}),
    title: "Arena",
    alt_title: {
      ...((modeSet.metadata && modeSet.metadata.alt_title) || {}),
      en: "Arena",
    },
    tagline: "Queue into Arena and climb the competitive ladder.",
    product_tag: "Product.BR.Build.Arena",
  };
  return modeSet;
}

function applyModernPrimaryModeSetOverride(
  modeSet: DiscoveryLink | null,
  arenaTemplate?: DiscoveryLink | null,
): void {
  if (!modeSet) {
    return;
  }

  const imageUrl = DEFAULT_DISCOVERY_IMAGE;

  modeSet.metadata = modeSet.metadata || {};
  modeSet.metadata.image_url = imageUrl;
  modeSet.metadata.image_urls = buildImageUrls(imageUrl);
  modeSet.metadata.title = "Arena";
  modeSet.metadata.locale = modeSet.metadata.locale || "en";
  modeSet.metadata.video_vuid = "";
  modeSet.metadata.tagline = "Queue into Arena and core Battle Royale playlists.";
  modeSet.metadata.default_sub_link_code = "playlist_showdownalt_solo";
  modeSet.metadata.sub_link_codes = [...SEASON_29_PLUS_PRIMARY_PLAYLISTS];
  modeSet.metadata.alt_title = {
    ...(modeSet.metadata.alt_title || {}),
    en: "Arena",
  };
}

function getLatestDiscoveryLinks(): DiscoveryLink[] {
  const latestMenu = readJsonFile("static", "discovery", "latest", "menu.json");
  const brPlaylist = readJsonFile("static", "discovery", "latest", "brplaylist.json");

  const links = [
    ...(Array.isArray(latestMenu) ? latestMenu : [latestMenu]),
    ...(Array.isArray(brPlaylist) ? brPlaylist : [brPlaylist]),
  ]
    .filter(Boolean)
    .map((link) => cloneDeep(link));

  for (const link of links) {
    normalizeArenaLink(link);
  }

  const arenaTemplate =
    links.find((link) => link?.mnemonic === "playlist_showdownalt_solo") ?? null;

  for (const mnemonic of ARENA_PLAYLISTS) {
    if (!links.some((link) => link?.mnemonic === mnemonic)) {
      links.push(buildArenaPlaylistLink(mnemonic, arenaTemplate));
    }
  }

  const battleRoyaleModeSet = links.find((link) => link?.mnemonic === "set_br_playlists");
  if (battleRoyaleModeSet?.metadata) {
    const subLinkCodes = Array.isArray(battleRoyaleModeSet.metadata.sub_link_codes)
      ? battleRoyaleModeSet.metadata.sub_link_codes.filter((value: unknown) => typeof value === "string")
      : [];

    for (const mnemonic of ARENA_PLAYLISTS) {
      if (!subLinkCodes.includes(mnemonic)) {
        subLinkCodes.push(mnemonic);
      }
    }

    battleRoyaleModeSet.metadata.sub_link_codes = subLinkCodes;
  }

  if (!links.some((link) => link?.mnemonic === "set_arena_playlists")) {
    links.push(buildArenaModeSet(arenaTemplate || battleRoyaleModeSet));
  }

  if (!links.some((link) => link?.mnemonic === "set_habanero_playlists")) {
    links.push(buildHabaneroModeSet(arenaTemplate || battleRoyaleModeSet));
  }

  return links;
}

function getSurfaceResults(surface: DiscoverySurface): any[] {
  const results = surface?.Panels?.[0]?.Pages?.[0]?.results;
  return Array.isArray(results) ? results : [];
}

function makeSurfaceEntry(link: DiscoveryLink): Record<string, any> {
  return {
    linkData: link,
    lastVisited: null,
    linkCode: link.mnemonic || link.linkCode || "",
    isFavorite: false,
  };
}

function findLinkByMnemonic(links: DiscoveryLink[], mnemonic: string): DiscoveryLink | null {
  return links.find((link) => link?.mnemonic === mnemonic) ?? null;
}

function findSurfaceLinkByMnemonic(surface: DiscoverySurface, mnemonic: string): DiscoveryLink | null {
  for (const result of getSurfaceResults(surface)) {
    if (result?.linkData?.mnemonic === mnemonic) {
      return result.linkData;
    }
  }

  return null;
}

function normalizeArenaSurface(surface: DiscoverySurface): DiscoverySurface {
  for (const result of getSurfaceResults(surface)) {
    const link = result?.linkData;
    const mnemonic = link?.mnemonic || result?.linkCode;
    if (!link || !isArenaPlaylistMnemonic(mnemonic)) {
      continue;
    }

    normalizeArenaLink(link);
  }

  return surface;
}

function ensureArenaDiscoverySurface(surface: DiscoverySurface, latestLinks: DiscoveryLink[]): DiscoverySurface {
  const results = getSurfaceResults(surface);
  if (results.length === 0) {
    return surface;
  }

  for (let index = results.length - 1; index >= 0; index -= 1) {
    const mnemonic = results[index]?.linkData?.mnemonic || results[index]?.linkCode;
    if (mnemonic === "set_arena_playlists") {
      results.splice(index, 1);
    }
  }

  const arenaTemplate =
    findLinkByMnemonic(latestLinks, "playlist_showdownalt_solo") ||
    findSurfaceLinkByMnemonic(surface, "playlist_showdownalt_solo");

  for (const mnemonic of ARENA_PLAYLISTS) {
    const exists = results.some(
      (result) => result?.linkData?.mnemonic === mnemonic || result?.linkCode === mnemonic,
    );
    if (exists) {
      continue;
    }

    const link =
      findLinkByMnemonic(latestLinks, mnemonic) || buildArenaPlaylistLink(mnemonic, arenaTemplate);
    results.push(makeSurfaceEntry(link));
  }

  return surface;
}

function populateModeSets(surface: DiscoverySurface, latestLinks: DiscoveryLink[]): DiscoverySurface {
  surface.ModeSets = {};

  for (const link of latestLinks) {
    if (link?.linkType === "ModeSet" && typeof link.mnemonic === "string") {
      surface.ModeSets[link.mnemonic] = cloneDeep(link);
    }
  }

  if (surface.ModeSets["set_arena_playlists"]) {
    delete surface.ModeSets["set_arena_playlists"];
  }

  return surface;
}

function buildDiscoverySurfaceResponse(ver: ReturnType<typeof getVersion>): DiscoverySurface {
  const normalSurface = getNormalDiscoverySurface();
  if (ver.season < 23) {
    return normalizeArenaSurface(normalSurface);
  }

  const latestLinks = getLatestDiscoveryLinks();
  const surface = normalizeArenaSurface(ensureArenaDiscoverySurface(cloneDeep(normalSurface), latestLinks));

  if (ver.season >= 27) {
    const populatedSurface = populateModeSets(surface, latestLinks);
    if (ver.season >= 29) {
      applyModernPrimaryModeSetOverride(
        populatedSurface.ModeSets?.["set_br_playlists"] ?? null,
        findLinkByMnemonic(latestLinks, "playlist_showdownalt_solo"),
      );
    }

    return populatedSurface;
  }

  surface.ModeSets = {};
  return surface;
}

function getMnemonicLinks(ver: ReturnType<typeof getVersion>): DiscoveryLink[] {
  const links =
    ver.season >= 27
      ? getLatestDiscoveryLinks()
      : getSurfaceResults(buildDiscoverySurfaceResponse(ver))
    .map((result) => result?.linkData)
    .filter(Boolean);

  if (ver.season >= 29) {
    const arenaTemplate = findLinkByMnemonic(links, "playlist_showdownalt_solo");
    const battleRoyaleModeSet = findLinkByMnemonic(links, "set_br_playlists");
    applyModernPrimaryModeSetOverride(battleRoyaleModeSet, arenaTemplate);
  }

  return links;
}

function buildApiV2SurfaceResponse(ver: ReturnType<typeof getVersion>): Record<string, any> {
  const links = getMnemonicLinks(ver);
  const availableMnemonics = new Set(
    links
      .map((link) => (typeof link?.mnemonic === "string" ? link.mnemonic : ""))
      .filter(Boolean),
  );

  const curatedHomebar = availableMnemonics.has("reference_byepicnocompetitive_5")
    ? ["reference_byepicnocompetitive_5"]
    : [];

  const preferredPanelCodes = (
    ver.season >= 29
      ? [
          ...SEASON_29_PLUS_PRIMARY_PLAYLISTS,
        ]
      : [
          "set_br_playlists",
          "playlist_showdownalt_solo",
          "playlist_showdownalt_duos",
          "playlist_showdownalt_trios",
          "playlist_defaultsolo",
          "playlist_defaultduo",
          "playlist_trios",
          "playlist_defaultsquad",
          "playlist_juno",
          "playlist_papaya",
          "playlist_durian",
        ]
  ).filter((mnemonic) => availableMnemonics.has(mnemonic));

  const fallbackCodes = links
    .map((link) => (typeof link?.mnemonic === "string" ? link.mnemonic : ""))
    .filter(
      (mnemonic) =>
        mnemonic &&
        mnemonic !== "reference_byepicnocompetitive_5" &&
        !preferredPanelCodes.includes(mnemonic),
    );

  const panelCodes = [...preferredPanelCodes, ...fallbackCodes].slice(0, 8);
  const makeSurfaceResult = (linkCode: string, globalCCU = 1) => ({
    lastVisited: null,
    linkCode,
    isFavorite: false,
    favoriteStatus: "NONE",
    globalCCU,
    lockStatus: "UNLOCKED",
    lockStatusReason: "NONE",
    isVisible: true,
  });

  return {
    panels: [
      {
        panelName: "Homebar_V3",
        panelDisplayName: "Test_EpicsPicksHomebar",
        featureTags: ["col:5", "homebar"],
        firstPage: {
          results: curatedHomebar.map((linkCode) => makeSurfaceResult(linkCode, -1)),
          hasMore: false,
          panelTargetName: null,
        },
        panelType: "CuratedList",
        playHistoryType: null,
      },
      {
        panelName: "ByEpicNoCompetitive",
        panelDisplayName: "By Epic",
        featureTags: ["col:5"],
        firstPage: {
          results: panelCodes.map((linkCode) => makeSurfaceResult(linkCode)),
          hasMore: false,
          panelTargetName: null,
        },
        panelType: "AnalyticsList",
        playHistoryType: null,
      },
    ],
  };
}

function buildGenericPlaylistLink(mnemonic: string): DiscoveryLink {
  return {
    namespace: "fn",
    accountId: "epic",
    creatorName: "Epic",
    mnemonic,
    linkType: "BR:Playlist",
    metadata: {
      image_url: "",
      image_urls: buildImageUrls(""),
      matchmaking: {
        override_playlist: mnemonic,
      },
    },
    version: 95,
    active: true,
    disabled: false,
    created: "2021-10-01T00:56:45.010Z",
    published: "2021-08-03T15:27:20.251Z",
    descriptionTags: [],
    moderationStatus: "Approved",
  };
}

function getDiscoveryLinkResponse(
  ver: ReturnType<typeof getVersion>,
  mnemonic: string,
): DiscoveryLink {
  const links = getMnemonicLinks(ver);
  const existing = findLinkByMnemonic(links, mnemonic);

  if (existing) {
    return existing;
  }

  if (ARENA_PLAYLISTS.includes(mnemonic as (typeof ARENA_PLAYLISTS)[number])) {
    const arenaTemplate = findLinkByMnemonic(links, "playlist_showdownalt_solo");
    return buildArenaPlaylistLink(mnemonic, arenaTemplate);
  }

  if (mnemonic === "set_arena_playlists") {
    const battleRoyaleModeSet = findLinkByMnemonic(links, "set_br_playlists");
    return buildArenaModeSet(battleRoyaleModeSet);
  }

  if (mnemonic === "set_habanero_playlists") {
    const battleRoyaleModeSet = findLinkByMnemonic(links, "set_br_playlists");
    return buildHabaneroModeSet(battleRoyaleModeSet);
  }

  return buildGenericPlaylistLink(mnemonic);
}

export default function () {
  app.get("/fortnite/api/discovery/accessToken/*", async (c) => {
    const useragent: any = c.req.header("user-agent");
    if (!useragent) return c.json(Atlas.internal.invalidUserAgent);
    const regex = useragent.match(/\+\+Fortnite\+Release-\d+\.\d+/);
    return c.json({
      branchName: regex[0],
      appId: "Fortnite",
      token: `${crypto.randomBytes(10).toString("hex")}=`,
    });
  });

  app.post("/api/v2/discovery/surface/*", async (c) => {
    return c.json(buildApiV2SurfaceResponse(getVersion(c)));
  });

  app.get("/api/v1/assets/Fortnite/:version/:cl/FortPlaylistAthena/:playlist", async (c) => {
    const ver = getVersion(c);
    if (!shouldGenerateFortPlaylistAthenaAssets(ver) && !requestPathLooksLikeSeason32(c)) {
      return c.notFound();
    }

    const playlistName = c.req.param("playlist").replace(/[^a-zA-Z0-9_.-]/g, "");
    return c.json(buildGeneratedFortPlaylistAthenaAsset(playlistName));
  });

  app.post("/api/v1/assets/Fortnite/*", async (c) => {
    const ver = getVersion(c);
    const playlistAssets = buildFortPlaylistAthenaDirectoryResponse(ver, requestPathLooksLikeSeason32(c));
    const assets = {
      ...playlistAssets,
      FortCreativeDiscoverySurface: {
        meta: {
          promotion: 26,
        },
        assets: {
          CreativeDiscoverySurface_Frontend: {
            meta: {
              revision: 32,
              headRevision: 32,
              revisedAt: "2023-04-25T19:30:52.489Z",
              promotion: 26,
              promotedAt: "2023-04-25T19:31:12.618Z",
            },
            assetData: {
              AnalyticsId: "v538",
              TestCohorts: [
                {
                  AnalyticsId: "c-1v2_v2_c727",
                  CohortSelector: "PlayerDeterministic",
                  PlatformBlacklist: [],
                  CountryCodeBlocklist: [],
                  ContentPanels: [
                    {
                      NumPages: 1,
                      AnalyticsId: "p1114",
                      PanelType: "AnalyticsList",
                      AnalyticsListName: "ByEpicNoBigBattle",
                      CuratedListOfLinkCodes: [],
                      ModelName: "",
                      PageSize: 7,
                      PlatformBlacklist: [],
                      PanelName: "ByEpicNoBigBattle6Col",
                      MetricInterval: "",
                      CountryCodeBlocklist: [],
                      SkippedEntriesCount: 0,
                      SkippedEntriesPercent: 0,
                      SplicedEntries: [],
                      PlatformWhitelist: [],
                      MMRegionBlocklist: [],
                      EntrySkippingMethod: "None",
                      PanelDisplayName: {
                        Category: "Game",
                        NativeCulture: "",
                        Namespace: "CreativeDiscoverySurface_Frontend",
                        LocalizedStrings: [],
                        bIsMinimalPatch: false,
                        NativeString: "LTMS",
                        Key: "ByEpicNoBigBattle6Col",
                      },
                      PlayHistoryType: "RecentlyPlayed",
                      bLowestToHighest: false,
                      PanelLinkCodeBlacklist: [],
                      CountryCodeAllowlist: [],
                      PanelLinkCodeWhitelist: [],
                      FeatureTags: [],
                      MMRegionAllowlist: [],
                      MetricName: "",
                    },
                    {
                      NumPages: 2,
                      AnalyticsId: "p969|88dba0c4e2af76447df43d1e31331a3d",
                      PanelType: "AnalyticsList",
                      AnalyticsListName: "EventPanel",
                      CuratedListOfLinkCodes: [],
                      ModelName: "",
                      PageSize: 25,
                      PlatformBlacklist: [],
                      PanelName: "EventPanel",
                      MetricInterval: "",
                      CountryCodeBlocklist: [],
                      SkippedEntriesCount: 0,
                      SkippedEntriesPercent: 0,
                      SplicedEntries: [],
                      PlatformWhitelist: [],
                      MMRegionBlocklist: [],
                      EntrySkippingMethod: "None",
                      PanelDisplayName: {
                        Category: "Game",
                        NativeCulture: "",
                        Namespace: "CreativeDiscoverySurface_Frontend",
                        LocalizedStrings: [],
                        bIsMinimalPatch: false,
                        NativeString: "Event LTMS",
                        Key: "EventPanel",
                      },
                      PlayHistoryType: "RecentlyPlayed",
                      bLowestToHighest: false,
                      PanelLinkCodeBlacklist: [],
                      CountryCodeAllowlist: [],
                      PanelLinkCodeWhitelist: [],
                      FeatureTags: ["col:6"],
                      MMRegionAllowlist: [],
                      MetricName: "",
                    },
                  ],
                  PlatformWhitelist: [],
                  SelectionChance: 0.1,
                  TestName: "testing",
                },
              ],
              GlobalLinkCodeBlacklist: [],
              SurfaceName: "CreativeDiscoverySurface_Frontend",
              TestName: "20.10_4/11/2022_hero_combat_popularConsole",
              primaryAssetId: "FortCreativeDiscoverySurface:CreativeDiscoverySurface_Frontend",
              GlobalLinkCodeWhitelist: [],
            },
          },
        },
      },
    };

    return c.json(assets);
  });

  app.post("/fortnite/api/game/v2/creative/discovery/surface/*", async (c) => {
    return c.json(buildDiscoverySurfaceResponse(getVersion(c)));
  });

  app.post("/api/v1/discovery/surface/*", async (c) => {
    return c.json(buildDiscoverySurfaceResponse(getVersion(c)));
  });

  app.post("/links/api/fn/mnemonic", async (c) => {
    const ver = getVersion(c);
    return c.json(getMnemonicLinks(ver));
  });

  app.get("/links/api/fn/mnemonic/:playlistId", async (c) => {
    const playlistId = c.req.param("playlistId");
    return c.json(getDiscoveryLinkResponse(getVersion(c), playlistId));
  });

  app.get("/links/api/fn/mnemonic/:playlistId/related", async (c) => {
    const playlistId = c.req.param("playlistId");
    const ver = getVersion(c);

    const links: Record<string, DiscoveryLink> = {
      [playlistId]: getDiscoveryLinkResponse(ver, playlistId),
    };

    const arenaMap: Record<string, string[]> = {
      playlist_defaultsolo: ["playlist_showdownalt_solo"],
      playlist_defaultduo: ["playlist_showdownalt_duos"],
      playlist_trios: ["playlist_showdownalt_trios"],
    };

    for (const mnemonic of arenaMap[playlistId] || []) {
      links[mnemonic] = getDiscoveryLinkResponse(ver, mnemonic);
    }

    return c.json({
      parentLinks: [],
      links,
    });
  });
}
