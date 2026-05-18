import { app } from "../index";
import axios from "axios";
import getVersion from "../utils/handlers/getVersion";
import fs from "fs";
import path from "path";
import crypto from "crypto";
import logger from "../utils/logger/logger";
import { atlasDataPath, atlasDataReadPath } from "../config/paths";

interface CmsVersionInfo {
  season: number;
  build: number;
  CL?: string;
}

interface ReleaseInfo {
  season: number;
  minor: number;
  patch: number;
}

function parseReleaseInfo(userAgent: string): ReleaseInfo {
  const releaseMatches = [
    ...userAgent.matchAll(/Release-(\d+)\.(\d+)(?:\.(\d+))?/g),
  ];

  if (releaseMatches.length === 0) {
    return { season: 0, minor: 0, patch: 0 };
  }

  let selected: ReleaseInfo = { season: 0, minor: 0, patch: 0 };
  for (const match of releaseMatches) {
    const candidate: ReleaseInfo = {
      season: Number(match[1]),
      minor: Number(match[2]),
      patch: Number(match[3] ?? 0),
    };

    if (
      candidate.season > selected.season ||
      (candidate.season === selected.season &&
        candidate.minor > selected.minor) ||
      (candidate.season === selected.season &&
        candidate.minor === selected.minor &&
        candidate.patch > selected.patch)
    ) {
      selected = candidate;
    }
  }

  return selected;
}

function getResolvedSeason(version: CmsVersionInfo, userAgent: string): number {
  const release = parseReleaseInfo(userAgent);
  if (release.season > 0) {
    return release.season;
  }
  return version.season > 0 ? version.season : 0;
}

function getResolvedMinor(version: CmsVersionInfo, userAgent: string): number {
  const release = parseReleaseInfo(userAgent);
  const resolvedSeason = getResolvedSeason(version, userAgent);

  if (
    release.season === resolvedSeason &&
    (release.minor > 0 || release.patch > 0)
  ) {
    return release.minor;
  }

  if (version.season !== resolvedSeason) {
    return 0;
  }

  if (!Number.isFinite(version.build)) {
    return 0;
  }

  const fractional = Number(
    (version.build - Math.trunc(version.build)).toFixed(3)
  );
  return Math.round(fractional * 100);
}

function readCmsJson<T = any>(fileName: string): T {
  return JSON.parse(
    fs.readFileSync(atlasDataReadPath("static", "cms", fileName), "utf8")
  ) as T;
}

const atlasDiscordUrl = "https://discord.gg/GqgakxU6bm";
const atlasBannerImage =
  "https://raw.githubusercontent.com/cipherfps/ATLAS-Backend/main/public/images/ATLAS-Backend-Banner.png";
const atlasBannerSlimImage =
  "https://raw.githubusercontent.com/cipherfps/ATLAS-Backend/main/public/images/ATLAS-Backend-Banner-Slim.png";
const atlasNoticeBody =
  '@cipherfps\nDiscord: https://discord.gg/GqgakxU6bm\nClick (F8) and type "open 127.0.0.1" to join.';
const atlasNewsBody = "@cipherfps\nDiscord: https://discord.gg/GqgakxU6bm\nClick (F8) and type \"open 127.0.0.1\" to join.";
const remixSeason32LobbyBackground =
  "https://cdn2.unrealengine.com/mkart-fnbr-quail-lobby-3264x1836-b157b2252db6.jpg";

function createDynamicMotdCollection(targetIslandCode: string): any {
  const contentId = "atlas-br-motd-item";
  const tcId = "atlas-br-motd-tc";
  const contentFields = {
    Buttons: [
      {
        Action: {
          _type: "MotdDiscoveryAction",
          category: targetIslandCode,
          islandCode: targetIslandCode,
          shouldOpen: true,
        },
        Style: "0",
        Text: "Play Now",
        _type: "Button",
      },
    ],
    FullScreenBackground: {
      Image: [
        {
          width: 1920,
          height: 1080,
          url: atlasBannerImage,
        },
        {
          width: 960,
          height: 540,
          url: atlasBannerImage,
        },
      ],
      _type: "FullScreenBackground",
    },
    FullScreenBody: atlasNewsBody,
    FullScreenTitle: "ATLAS",
    FullScreenBackgroundImageLink: atlasBannerImage,
    TeaserBackground: {
      Image: [
        {
          width: 1024,
          height: 512,
          url: atlasBannerSlimImage,
        },
      ],
      _type: "TeaserBackground",
    },
    TeaserBackgroundImageLink: atlasBannerSlimImage,
    TeaserTitle: "ATLAS",
    VerticalTextLayout: false,
  };

  const contentHash = crypto
    .createHash("sha256")
    .update(JSON.stringify(contentFields))
    .digest("hex");

  return {
    contentType: "collection",
    contentId: "fortnite-br-br-motd-collection",
    tcId: "atlas-br-motd-collection-tc",
    contentMeta: JSON.stringify({ [contentHash]: [contentId] }),
    contentItems: [
      {
        contentType: "content-item",
        contentId,
        tcId,
        contentFields,
        contentSchemaName: "DynamicMotd",
        contentHash,
      },
    ],
  };
}

function applyAtlasLobbyMessaging(content: any): void {
  content.emergencynotice = {
    news: {
      _type: "Battle Royale News",
      platform_messages: [],
      messages: [
        {
          _type: "CommonUI Simple Message Base",
          title: "ATLAS",
          body: atlasNoticeBody,
          hidden: false,
          spotlight: false,
          subgame: "br",
        },
      ],
    },
    _title: "emergencynotice",
    _noIndex: false,
    alwaysShow: true,
    _activeDate: "1970-01-01T00:00:00.000Z",
    lastModified: "9999-12-31T23:59:59.999Z",
    _locale: "en-US",
  };

  content.emergencynoticev2 = {
    "jcr:isCheckedOut": true,
    _title: "emergencynoticev2",
    _noIndex: false,
    emergencynotices: {
      _type: "Emergency Notices",
      emergencynotices: [
        {
          _type: "CommonUI Emergency Notice Base",
          title: "ATLAS",
          body: atlasNoticeBody,
          hidden: false,
          gamemodes: [],
        },
      ],
    },
    _activeDate: "1970-01-01T00:00:00.000Z",
    lastModified: "9999-12-31T23:59:59.999Z",
    _locale: "en-US",
  };

  const battleroyalenewsv2 = { ...(content.battleroyalenewsv2 ?? {}) };
  const battleroyalenewsv2News = { ...(battleroyalenewsv2.news ?? {}) };
  const battleroyalenewsv2Motds = Array.isArray(battleroyalenewsv2News.motds)
    ? battleroyalenewsv2News.motds
    : [];
  const existingBattleroyalev2Motd =
    battleroyalenewsv2Motds.length > 0
      ? { ...battleroyalenewsv2Motds[0] }
      : {};
  battleroyalenewsv2News._type = "Battle Royale News v2";
  battleroyalenewsv2News.platform_messages = [];
  battleroyalenewsv2News.platform_motds = [];
  battleroyalenewsv2News.motds = [
    {
      _type: "CommonUI Simple Message MOTD",
      id: existingBattleroyalev2Motd.id ?? "AtlasNewsBRv2",
      entryType: "Website",
      title: "ATLAS",
      body: atlasNewsBody,
      tabTitleOverride: "ATLAS",
      sortingPriority: 0,
      image: atlasBannerImage,
      tileImage: atlasBannerSlimImage,
      hidden: false,
      spotlight: false,
      videoMute: false,
      videoLoop: false,
      videoStreamingEnabled: false,
      videoAutoplay: false,
      videoFullscreen: false,
      websiteButtonText: "Join our discord",
      websiteURL: atlasDiscordUrl,
    },
  ];
  battleroyalenewsv2.news = battleroyalenewsv2News;
  battleroyalenewsv2["jcr:isCheckedOut"] = true;
  battleroyalenewsv2._title = "battleroyalenewsv2";
  battleroyalenewsv2.header = battleroyalenewsv2.header ?? "";
  battleroyalenewsv2.style = "None";
  battleroyalenewsv2._noIndex = false;
  battleroyalenewsv2.alwaysShow = false;
  battleroyalenewsv2._activeDate = "1970-01-01T00:00:00.000Z";
  battleroyalenewsv2.lastModified = "9999-12-31T23:59:59.999Z";
  battleroyalenewsv2._locale = "en-US";
  content.battleroyalenewsv2 = battleroyalenewsv2;
}

function applyRemixShopCmsFallback(content: any): void {
  const sectionNames = ["Featured", "Daily"];
  const shopSections = sectionNames.map((name) => ({
    _type: "ShopSection",
    sectionId: name,
    sectionDisplayName: name,
    landingPriority: name === "Featured" ? 0 : 1,
    bEnableToastNotification: true,
    bHidden: false,
    bShowIneligibleOffers: true,
    bShowIneligibleOffersIfGiftable: true,
    bShowTimer: true,
    bSortOffersByOwnership: false,
    background: {
      _type: "DynamicBackground",
      key: "vault",
      stage: "default",
    },
  }));
  const mpSections = sectionNames.map((name) => ({
    _type: "MP Item Shop - Section",
    sectionID: name,
    sectionName: name,
    bShowTimer: true,
    offerGroups: [],
  }));

  if (!content.shopSections) {
    content.shopSections = {
      _title: "shop-sections",
      sectionList: {
        _type: "ShopSectionList",
        sections: shopSections,
      },
      _noIndex: false,
      _activeDate: "1970-01-01T00:00:00.000Z",
      lastModified: "9999-12-31T23:59:59.999Z",
      _locale: "en-US",
      _templateName: "FortniteGameShopSections",
    };
  } else {
    content.shopSections.sectionList = {
      _type: "ShopSectionList",
      sections: shopSections,
    };
  }

  if (!content.mpItemShop) {
    content.mpItemShop = {
      shopData: {
        _type: "MP Item Shop - Data Root",
        sections: mpSections,
      },
      _title: "mpItemShop",
      _noIndex: false,
      _activeDate: "1970-01-01T00:00:00.000Z",
      lastModified: "9999-12-31T23:59:59.999Z",
      _locale: "en-US",
      _templateName: "FortniteGameMPItemShop",
    };
  } else {
    content.mpItemShop.shopData = {
      _type: "MP Item Shop - Data Root",
      sections: mpSections,
    };
  }
}

function setCmsNoCacheHeaders(c: any): void {
  c.header("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
  c.header("Pragma", "no-cache");
  c.header("Expires", "0");
  c.header("Surrogate-Control", "no-store");
  c.header("Vary", "User-Agent");
}

function appendCmsDebugLog(line: string): void {
  try {
    const logDir = atlasDataPath("logs");
    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }
    fs.appendFileSync(path.join(logDir, "cms-debug.log"), `${line}\n`);
  } catch {
    // ignore log write failures
  }
}

function sendCmsResponse(
  c: any,
  content: any,
  version: CmsVersionInfo,
  userAgent: string,
  source: string
) {
  setCmsNoCacheHeaders(c);

  const season = getResolvedSeason(version, userAgent);
  const minor = getResolvedMinor(version, userAgent);
  c.header("X-ATLAS-CMS-SEASON", String(season));
  c.header("X-ATLAS-CMS-MINOR", String(minor));
  c.header("X-ATLAS-CMS-SOURCE", source);

  const now = new Date().toISOString();
  if (content && typeof content === "object") {
    content.lastModified = now;
    if (content.dynamicbackgrounds && typeof content.dynamicbackgrounds === "object") {
      content.dynamicbackgrounds.lastModified = now;
    }
    if (content.lobby && typeof content.lobby === "object") {
      content.lobby.lastModified = now;
    }
  }

  const stage = content?.dynamicbackgrounds?.backgrounds?.backgrounds?.[0]?.stage ?? "";
  const backgroundimage =
    content?.dynamicbackgrounds?.backgrounds?.backgrounds?.[0]?.backgroundimage ??
    content?.lobby?.backgroundimage ??
    "";
  appendCmsDebugLog(
    `[${now}] source=${source} resolved=${season}.${minor} rawSeason=${version.season} rawBuild=${version.build} stage=${stage} bg=${backgroundimage} ua=${userAgent}`
  );
  logger.debug(
    `CMS served: ${source} resolved=${season}.${minor} rawSeason=${version.season} rawBuild=${version.build} stage=${stage || "none"} bg=${backgroundimage || "none"}`
  );

  return c.json(content);
}

function applySeasonSpecificBackground(
  content: any,
  version: CmsVersionInfo,
  userAgent: string
): void {
  const backgrounds = content?.dynamicbackgrounds?.backgrounds?.backgrounds;
  if (!Array.isArray(backgrounds) || backgrounds.length === 0) {
    return;
  }

  const primary = backgrounds[0];
  const secondary = backgrounds.length > 1 ? backgrounds[1] : null;
  const season = getResolvedSeason(version, userAgent);
  const minor = getResolvedMinor(version, userAgent);

  const setPrimary = (stage: string, backgroundimage: string) => {
    primary.stage = stage;
    primary.backgroundimage = backgroundimage;
    if (!content.lobby || typeof content.lobby !== "object") {
      content.lobby = {};
    }
    content.lobby.stage = stage;
    content.lobby.backgroundimage = backgroundimage;
  };

  switch (season) {
    case 8:
      setPrimary("season8", "");
      return;
    case 9:
      setPrimary("season9", "");
      return;
    case 10:
      setPrimary(minor === 40 ? "blackmonday" : "seasonx", "");
      return;
    case 11:
      setPrimary(minor === 31 || minor === 40 ? "Winter19" : "season11", "");
      return;
    case 12:
      setPrimary("season12", "");
      return;
    case 13:
      setPrimary("season13", "");
      return;
    case 14:
      setPrimary("season14", "");
      return;
    case 15:
      setPrimary(
        "season15",
        "https://static.wikia.nocookie.net/fortnite/images/c/cf/Chapter_2_Season_5_-_Lobby_Background_-_Fortnite.png/revision/latest?cb=20210331061751"
      );
      if (secondary) {
        secondary.stage = "season15";
      }
      return;
    case 16:
      setPrimary("season16", "");
      return;
    case 17:
      setPrimary("season17", "");
      return;
    case 18:
      setPrimary("season18", "");
      return;
    case 19:
      if (minor === 1) {
        setPrimary(
          "winter2021",
          "https://cdn2.unrealengine.com/t-bp19-lobby-xmas-2048x1024-f85d2684b4af.png"
        );
      } else {
        setPrimary("season19", "");
      }
      return;
    case 20:
      if (minor === 40) {
        setPrimary(
          "season20",
          "https://cdn2.unrealengine.com/t-bp20-40-armadillo-glowup-lobby-2048x2048-2048x2048-3b83b887cc7f.jpg"
        );
      } else {
        setPrimary(
          "season20",
          "https://cdn2.unrealengine.com/s20-landscapev4-2048x1024-2494a103ae6c.png"
        );
      }
      return;
    case 21:
      if (minor === 30) {
        setPrimary(
          "season2130",
          "https://cdn2.unrealengine.com/nss-lobbybackground-2048x1024-f74a14565061.jpg"
        );
      } else {
        setPrimary(
          "season2100",
          "https://cdn2.unrealengine.com/s21-lobby-background-2048x1024-2e7112b25dc3.jpg"
        );
      }
      return;
    case 22:
      setPrimary(
        "defaultnotris",
        "https://cdn2.unrealengine.com/t-bp22-lobby-square-2048x2048-2048x2048-e4e90c6e8018.jpg"
      );
      return;
    case 23:
      if (minor === 10) {
        setPrimary(
          "defaultnotris",
          "https://cdn2.unrealengine.com/t-bp23-winterfest-lobby-square-2048x2048-2048x2048-277a476e5ca6.png"
        );
      } else {
        setPrimary(
          "defaultnotris",
          "https://cdn2.unrealengine.com/t-bp23-lobby-2048x1024-2048x1024-26f2c1b27f63.png"
        );
      }
      return;
    case 24:
      setPrimary(
        "defaultnotris",
        "https://static.wikia.nocookie.net/fortnite/images/e/e7/Chapter_4_Season_2_-_Lobby_Background_-_Fortnite.png"
      );
      return;
    case 25:
      setPrimary(
        "defaultnotris",
        "https://static.wikia.nocookie.net/fortnite/images/c/ca/Chapter_4_Season_3_-_Lobby_Background_-_Fortnite.png"
      );
      return;
    case 26:
      if (minor === 30) {
        setPrimary(
          "season2630",
          "https://cdn2.unrealengine.com/s26-lobby-timemachine-final-2560x1440-a3ce0018e3fa.jpg"
        );
      } else {
        setPrimary(
          "season2600",
          "https://cdn2.unrealengine.com/0814-ch4s4-lobby-2048x1024-2048x1024-e3c2cf8d342d.png"
        );
      }
      return;
    case 27:
      if (minor === 11) {
        setPrimary(
          "defaultnotris",
          "https://cdn2.unrealengine.com/durianlobby2-4096x2048-242a51b6a8ee.jpg"
        );
      } else {
        setPrimary("season2700", "");
      }
      return;
    case 28:
      if (minor === 20) {
        setPrimary(
          "defaultnotris",
          "https://cdn2.unrealengine.com/s28-tmnt-lobby-4096x2048-e6c06a310c05.jpg"
        );
      } else {
        setPrimary(
          "defaultnotris",
          "https://cdn2.unrealengine.com/ch5s1-lobbybg-3640x2048-0974e0c3333c.jpg"
        );
      }
      return;
    case 29:
      if (minor === 20) {
        setPrimary(
          "defaultnotris",
          "https://cdn2.unrealengine.com/iceberg-lobby-3840x2160-217bb6ea8af9.jpg"
        );
      } else if (minor === 40) {
        setPrimary(
          "defaultnotris",
          "https://cdn2.unrealengine.com/mkart-2940-sw-fnbr-lobby-3840x2160-4f1f1486a54a.jpg"
        );
      } else {
        setPrimary(
          "defaultnotris",
          "https://cdn2.unrealengine.com/br-lobby-ch5s2-4096x2304-a0879ccdaafc.jpg"
        );
      }
      return;
    case 30:
      setPrimary(
        "season3000",
        "https://cdn2.unrealengine.com/ch5s3-lobby-3030-4096x2048-eecf04243faa.jpg"
      );
      return;
    case 31:
      setPrimary(
        "season3100",
        "https://cdn2.unrealengine.com/ch5s4-lobbybg-final-2136x1202-e5885322faf1.jpg"
      );
      return;
    case 32:
      setPrimary("defaultnotris", remixSeason32LobbyBackground);
      return;
    default:
      setPrimary("", "");
  }
}

export default function () {
  app.get("/content/api/pages/fortnite-game", async (c) => {
    const version = getVersion(c);
    const userAgent = c.req.header("user-agent") ?? "";
    const season = getResolvedSeason(version, userAgent);
    logger.debug(
      `CMS request UA="${userAgent}" season=${version.season} build=${version.build} CL=${version.CL ?? "unknown"}`
    );

    if (season > 0 && season <= 6) {
      return sendCmsResponse(
        c,
        readCmsJson("fortnite-game_s6.json"),
        version,
        userAgent,
        "legacy-s6"
      );
    }
    if (season === 7) {
      const content = readCmsJson("contentpages_s7.json");
      applySeasonSpecificBackground(content, version, userAgent);
      return sendCmsResponse(c, content, version, userAgent, "contentpages-s7");
    }
    if (season === 10) {
      const content = readCmsJson("contentpages_s10.json");
      applySeasonSpecificBackground(content, version, userAgent);
      return sendCmsResponse(c, content, version, userAgent, "contentpages-s10");
    }
    if (season === 15) {
      const content = readCmsJson("contentpages_s15.json");
      applyAtlasLobbyMessaging(content);
      applySeasonSpecificBackground(content, version, userAgent);
      return sendCmsResponse(c, content, version, userAgent, "contentpages-s15");
    }

    const game: any = await axios.get(
      "https://fortnitecontent-website-prod07.ol.epicgames.com/content/api/pages/fortnite-game"
    );
    let content: any = game.data;

    content = Object.assign(
      {},
      content,
      {
        emergencynotice: {
          news: {
            platform_messages: [],
            _type: "Battle Royale News",
            messages: [
              {
                hidden: false,
                _type: "CommonUI Simple Message Base",
                subgame: "br",
                body: "@cipherfps\nDiscord: https://discord.gg/GqgakxU6bm\nClick (F8) and type \"open 127.0.0.1\" to join.",
                title: "ATLAS",
                spotlight: false,
              },
            ],
          },
          "jcr:isCheckedOut": true,
          _title: "emergencynotice",
          _noIndex: false,
          alwaysShow: true,
          "jcr:baseVersion":
            "a7ca237317f1e761d4ee60-7c40-45a8-aa3e-bb0a2ffa9bb5",
          _activeDate: "2018-08-06T19:00:26.217Z",
          lastModified: "2020-10-30T04:50:59.198Z",
          _locale: "en-US",
        },
      },
      {
        emergencynoticev2: {
          "jcr:isCheckedOut": true,
          _title: "emergencynoticev2",
          _noIndex: false,
          emergencynotices: {
            _type: "Emergency Notices",
            emergencynotices: [
              {
                hidden: false,
                _type: "CommonUI Emergency Notice Base",
                title: "ATLAS",
                body: "@cipherfps\nDiscord: https://discord.gg/GqgakxU6bm\nClick (F8) and type \"open 127.0.0.1\" to join.",
              },
            ],
          },
          _activeDate: "2018-08-06T19:00:26.217Z",
          lastModified: "2021-03-17T15:07:27.924Z",
          _locale: "en-US",
        },
        battleroyalenewsv2: {
          news: {
            motds: [
              {
                entryType: "Website",
                image:
                  "https://raw.githubusercontent.com/cipherfps/ATLAS-Backend/main/public/images/ATLAS-Backend-Banner.png",
                imageURL:
                  "https://raw.githubusercontent.com/cipherfps/ATLAS-Backend/main/public/images/ATLAS-Backend-Banner.png",
                tileImage:
                  "https://raw.githubusercontent.com/cipherfps/ATLAS-Backend/main/public/images/ATLAS-Backend-Banner-Slim.png",
                tileImageURL:
                  "https://raw.githubusercontent.com/cipherfps/ATLAS-Backend/main/public/images/ATLAS-Backend-Banner-Slim.png",
                videoMute: false,
                hidden: false,
                tabTitleOverride: "ATLAS",
                _type: "CommonUI Simple Message MOTD",
                title: "ATLAS",
                body: "@cipherfps\nDiscord: https://discord.gg/GqgakxU6bm\nClick (F8) and type \"open 127.0.0.1\" to join.",
                videoLoop: false,
                videoStreamingEnabled: false,
                sortingPriority: 0,
                id: "AtlasNewsBR",
                videoAutoplay: false,
                videoFullscreen: false,
                spotlight: false,
                websiteURL: "https://discord.gg/GqgakxU6bm",
                websiteButtonText: "Join our discord",
              },
            ],
          },
          "jcr:isCheckedOut": true,
          _title: "battleroyalenewsv2",
          header: "",
          style: "None",
          _noIndex: false,
          alwaysShow: false,
          "jcr:baseVersion":
            "a7ca237317f1e704b1a186-6846-4eaa-a542-c2c8ca7e7f29",
          _activeDate: "2020-01-21T14:00:00.000Z",
          lastModified: "2021-02-10T23:57:48.837Z",
          _locale: "en-US",
        },
      }
    );

    if (version.build == 7.4) {
      const playlist = content.playlistinformation.playlist_info.playlists;

      for (let i = 0; i < playlist.length; i++) {
        if (
          playlist[i].image ===
            "https://cdn2.unrealengine.com/Fortnite/fortnite-game/playlistinformation/v12/12BR_Cyclone_Astronomical_PlaylistTile_Main-1024x512-ab95f8d30d0742ba1759403320a08e4ea6f0faa0.jpg" &&
          playlist[i].playlist_name === "Playlist_Music_High" &&
          playlist[i].description ===
            "Drop into Sweaty Sands for the ride of your life. (Photosensitivity Warning)" &&
          playlist[i].display_name === "Travis Scott’s Astronomical"
        ) {
          playlist[i].image = "https://i.imgur.com/3xoXe4R.png";
          playlist[i].description =
            "Fan-made Fortnite Live Event. Not endorsed by Epic Games. Drop into the water planet and enjoy the show.\nEvent Made by bigboitaj2005tajypoo(@jalzod), sizzyleaks & Era Dev Team(@ProjectEraFN)";
          playlist[i].display_name = "ERA FESTIVAL";
        }
      }
    }

    if (version.build == 8.51) {
      const playlist = content.playlistinformation.playlist_info.playlists;

      for (let i = 0; i < playlist.length; i++) {
        if (
          playlist[i].image ===
            "https://cdn2.unrealengine.com/Fortnite/fortnite-game/playlistinformation/v12/12BR_Cyclone_Astronomical_PlaylistTile_Main-1024x512-ab95f8d30d0742ba1759403320a08e4ea6f0faa0.jpg" &&
          playlist[i].playlist_name === "Playlist_Music_High" &&
          playlist[i].description ===
            "Drop into Sweaty Sands for the ride of your life. (Photosensitivity Warning)" &&
          playlist[i].display_name === "Travis Scott’s Astronomical"
        ) {
          playlist[i].image =
            "https://static.wikia.nocookie.net/fortnite/images/1/1b/Breakthrough_%28Full%29_-_Loading_Screen_-_Fortnite.png/revision/latest/scale-to-width-down/1000?cb=20211112181350";
          playlist[i].description = "The choice is yours!";
          playlist[i].display_name = "The Unvaulting";
        }
      }
    }

    if (version.build == 9.4 || version.build == 9.41) {
      const playlist = content.playlistinformation.playlist_info.playlists;

      for (let i = 0; i < playlist.length; i++) {
        if (
          playlist[i].image ===
            "https://cdn2.unrealengine.com/Fortnite/fortnite-game/playlistinformation/v12/12BR_Cyclone_Astronomical_PlaylistTile_Main-1024x512-ab95f8d30d0742ba1759403320a08e4ea6f0faa0.jpg" &&
          playlist[i].playlist_name === "Playlist_Music_High" &&
          playlist[i].description ===
            "Drop into Sweaty Sands for the ride of your life. (Photosensitivity Warning)" &&
          playlist[i].display_name === "Travis Scott’s Astronomical"
        ) {
          playlist[i].image =
            "https://i.kinja-img.com/image/upload/c_fit,q_60,w_1315/c0wwjgqh8weurqve8zkb.jpg0";
          playlist[i].description =
            "Initiate Island Defense Protocol. Emergency hyperfuel jetpacks have been granted. Take to the skies and find cover on sky platforms.";
          playlist[i].display_name = "The Final Showdown";
        }
      }
    }

    applyAtlasLobbyMessaging(content);
    applySeasonSpecificBackground(content, version, userAgent);
    if (season === 32) {
      applyRemixShopCmsFallback(content);
    }

    return sendCmsResponse(c, content, version, userAgent, "live-fortnite-game");
  });

  app.get("/content/api/pages/ALL", async (c) => {
    const version = getVersion(c);
    const userAgent = c.req.header("user-agent") ?? "";
    const content = {
      _title: "ALL",
      _noIndex: false,
      _activeDate: "1970-01-01T00:00:00.000Z",
      lastModified: new Date().toISOString(),
      _locale: "en-US",
    };
    return sendCmsResponse(c, content, version, userAgent, "contentpages-all");
  });

  app.get("/content/api/pages/fortnite-game/spark-tracks", async (c) => {
    const version = getVersion(c);
    const userAgent = c.req.header("user-agent") ?? "";
    const content = {
      _title: "spark-tracks",
      _noIndex: false,
      tracks: [],
      _activeDate: "1970-01-01T00:00:00.000Z",
      lastModified: new Date().toISOString(),
      _locale: "en-US",
    };
    return sendCmsResponse(c, content, version, userAgent, "spark-tracks");
  });

  app.get("/content/api/pages/fortnite-game/media-events-v2", async (c) => {
    const version = getVersion(c);
    const userAgent = c.req.header("user-agent") ?? "";
    const season = getResolvedSeason(version, userAgent) || 32;
    const now = new Date().toISOString();
    const content: any = {
      _title: "media-events-v2",
      _noIndex: false,
      _activeDate: "2022-01-12T01:43:01.626Z",
      lastModified: now,
      _locale: "en-US",
      _templateName: "FortniteMediaEvents",
      _suggestedPrefetch: [],
    };
    const soloEventId = `epicgames_Arena_S${season}_Solo`;
    const duosEventId = `epicgames_Arena_S${season}_Duos`;
    content[`arenaS${season}Solo`] = {
      _type: "Fortnite - Media Event",
      _title: `arenaS${season}Solo`,
      _noIndex: false,
      _activeDate: "2020-01-01T00:00:00.000Z",
      lastModified: now,
      _locale: "en-US",
      eventId: soloEventId,
      event_id: soloEventId,
    };
    content[`arenaS${season}Duos`] = {
      _type: "Fortnite - Media Event",
      _title: `arenaS${season}Duos`,
      _noIndex: false,
      _activeDate: "2020-01-01T00:00:00.000Z",
      lastModified: now,
      _locale: "en-US",
      eventId: duosEventId,
      event_id: duosEventId,
    };
    return sendCmsResponse(c, content, version, userAgent, "media-events-v2");
  });

  app.get("/content/api/pages/*", async (c) => {
    const version = getVersion(c);
    const userAgent = c.req.header("user-agent") ?? "";
    const season = getResolvedSeason(version, userAgent);
    logger.debug(
      `ContentPages request UA="${userAgent}" season=${version.season} build=${version.build} CL=${version.CL ?? "unknown"}`
    );

    if (season > 0 && season <= 6) {
      return sendCmsResponse(
        c,
        readCmsJson("fortnite-game_s6.json"),
        version,
        userAgent,
        "wildcard-legacy-s6"
      );
    }
    if (season === 7) {
      const content = readCmsJson("contentpages_s7.json");
      applySeasonSpecificBackground(content, version, userAgent);
      return sendCmsResponse(c, content, version, userAgent, "wildcard-contentpages-s7");
    }
    if (season === 10) {
      const content = readCmsJson("contentpages_s10.json");
      applySeasonSpecificBackground(content, version, userAgent);
      return sendCmsResponse(c, content, version, userAgent, "wildcard-contentpages-s10");
    }
    if (season === 15) {
      const content = readCmsJson("contentpages_s15.json");
      applyAtlasLobbyMessaging(content);
      applySeasonSpecificBackground(content, version, userAgent);
      return sendCmsResponse(c, content, version, userAgent, "wildcard-contentpages-s15");
    }

    const game: any = await axios.get(
      "https://fortnitecontent-website-prod07.ol.epicgames.com/content/api/pages/fortnite-game"
    );
    const content: any = game.data;
    applyAtlasLobbyMessaging(content);
    applySeasonSpecificBackground(content, version, userAgent);
    if (season === 32) {
      applyRemixShopCmsFallback(content);
    }
    return sendCmsResponse(c, content, version, userAgent, "wildcard-live");
  });
  // credits to neonite / hybridfnbr
  app.post("/api/v1/fortnite-br/surfaces/*/target", async (c) => {
    const version = getVersion(c);
    const userAgent = c.req.header("user-agent") ?? "";
    const season = getResolvedSeason(version, userAgent);
    const targetIslandCode = "set_br_playlists";

    if (season === 15) {
      const motd = readCmsJson("fortnite-game_s15.json");
      const body = await c.req.json().catch(() => ({} as any));
      const tags = body?.tags ?? body?.parameters?.tags ?? [];

      if (Array.isArray(tags) && tags.length > 0) {
        motd.contentItems.forEach((item: any) => {
          item.placements = [];
          tags.forEach((tag: string) => {
            item.placements.push({
              trackingId: "atlas-tracking",
              tag,
              position: 0,
            });
          });
        });
      }

      return c.json(motd);
    }

    setCmsNoCacheHeaders(c);
    return c.json(createDynamicMotdCollection(targetIslandCode));
  });
}
