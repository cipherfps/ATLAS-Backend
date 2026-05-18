import { app } from "..";
import { Atlas } from "../utils/handlers/errors";
import getVersion from "../utils/handlers/getVersion";
import logger from "../utils/logger/logger";

const keychain = await Bun.file("static/shop/keychain.json").json();
const sourceCatalogs = {
  v1: await Bun.file("static/shop/v1.json").json(),
  v2: await Bun.file("static/shop/v2.json").json(),
  v3: await Bun.file("static/shop/v3.json").json(),
};

function deepClone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value));
}

function dedupeCatalogEntries(entries: any[]) {
  const seen = new Set<string>();
  const deduped: any[] = [];

  for (const entry of entries) {
    const offerId =
      typeof entry?.offerId === "string" && entry.offerId.length > 0
        ? entry.offerId
        : JSON.stringify(entry?.itemGrants ?? entry ?? {});
    if (seen.has(offerId)) {
      continue;
    }
    seen.add(offerId);
    deduped.push(entry);
  }

  return deduped;
}

const dailyStorefrontNames = ["BRDailyStorefront", "BRSpecialDaily"];
const featuredStorefrontNames = ["BRWeeklyStorefront", "BRSpecialFeatured"];

function collectStorefrontEntries(catalogs: any[], names: string[]) {
  const entries: any[] = [];

  for (const catalog of catalogs) {
    const storefronts = Array.isArray(catalog?.storefronts)
      ? catalog.storefronts
      : [];

    for (const name of names) {
      const storefront = storefronts.find((entry: any) => entry?.name === name);
      if (
        storefront &&
        Array.isArray(storefront.catalogEntries) &&
        storefront.catalogEntries.length > 0
      ) {
        entries.push(...deepClone(storefront.catalogEntries));
      }
    }
  }

  return entries;
}

function upsertMetaInfo(entry: any, key: string, value: string) {
  if (!Array.isArray(entry.metaInfo)) {
    entry.metaInfo = [];
  }

  const existing = entry.metaInfo.find((item: any) => item?.key === key);
  if (existing) {
    existing.value = value;
    return;
  }

  entry.metaInfo.push({ key, value });
}

function prepareScrollableEntries(
  entries: any[],
  sectionId: "Featured" | "Daily",
  catalogGroupPriority: number
) {
  return entries.map((sourceEntry, index) => {
    const entry = deepClone(sourceEntry);
    entry.categories = [];
    entry.meta = entry.meta && typeof entry.meta === "object" ? entry.meta : {};
    entry.meta.SectionId = sectionId;
    entry.meta.LayoutId = entry.meta.LayoutId ?? `${sectionId}.${index + 1}`;
    entry.meta.TileSize = entry.meta.TileSize ?? "Size_1_x_1";
    entry.catalogGroupPriority = catalogGroupPriority;
    entry.sortPriority = index;

    upsertMetaInfo(entry, "SectionId", sectionId);
    upsertMetaInfo(entry, "LayoutId", entry.meta.LayoutId);
    upsertMetaInfo(entry, "TileSize", entry.meta.TileSize);

    return entry;
  });
}

function normalizeSharedCatalog(catalog: any, fallbackCatalogs: any[] = []) {
  const normalized = deepClone(catalog ?? {});
  const storefronts = Array.isArray(normalized.storefronts)
    ? normalized.storefronts
    : [];
  const sourceCatalogs = [normalized, ...fallbackCatalogs];

  const dailyEntries = dedupeCatalogEntries(
    collectStorefrontEntries(sourceCatalogs, dailyStorefrontNames)
  );
  const featuredEntries = dedupeCatalogEntries(
    collectStorefrontEntries(sourceCatalogs, featuredStorefrontNames)
  );

  const upsertStorefront = (name: string, entries: any[]) => {
    const existing = storefronts.find((entry: any) => entry?.name === name);
    if (existing) {
      existing.catalogEntries = deepClone(entries);
      return;
    }
    storefronts.push({
      name,
      catalogEntries: deepClone(entries),
    });
  };

  upsertStorefront("BRDailyStorefront", prepareScrollableEntries(dailyEntries, "Daily", 1));
  upsertStorefront(
    "BRWeeklyStorefront",
    prepareScrollableEntries(featuredEntries, "Featured", 0)
  );
  upsertStorefront("BRSeasonalStorefront", []);
  upsertStorefront("BRSpecialDaily", []);
  upsertStorefront("BRSpecialFeatured", []);

  normalized.storefronts = storefronts;
  normalized.expiration = "9999-12-31T23:59:59.999Z";

  return normalized;
}

const sharedCatalogs = {
  v1: normalizeSharedCatalog(sourceCatalogs.v1),
  v2: normalizeSharedCatalog(sourceCatalogs.v2, [sourceCatalogs.v1]),
  v3: normalizeSharedCatalog(sourceCatalogs.v3, [
    sourceCatalogs.v2,
    sourceCatalogs.v1,
  ]),
};

function selectSharedCatalog(c: any) {
  const version = getVersion(c);

  if (version.build >= 30.1) {
    return { catalog: sharedCatalogs.v3, label: "v3", version };
  }

  if (version.build >= 26.3) {
    return { catalog: sharedCatalogs.v2, label: "v2", version };
  }

  return { catalog: sharedCatalogs.v1, label: "v1", version };
}

export default function () {
  app.get("/fortnite/api/storefront/v2/keychain", async (c) => {
    return c.json(keychain);
  });

  app.get("/catalog/api/shared/bulk/offers", async (c) => {
    return c.json([]);
  });

  app.post("/catalog/api/shared/bulk/offers", async (c) => {
    return c.json([]);
  });

  app.post("/catalog/api/shared/namespace/:namespace/bulk/offers", async (c) => {
    return c.json([]);
  });

  app.get("/fortnite/api/storeaccess/v1/request_access/:accountId", async (c) => {
    return c.json([]);
  });

  app.get("/affiliate/api/public/affiliates/slug/:affiliateName", async (c) => {
    const affiliateName = c.req.param("affiliateName");
    return c.json({
      id: "aabbccddeeff11223344556677889900",
      slug: affiliateName,
      displayName: affiliateName,
      status: "ACTIVE",
      verified: true,
    });
  });

  app.get("/fortnite/api/storefront/v2/catalog", async (c) => {
    const useragent: any = c.req.header("user-agent");
    if (!useragent) return c.json(Atlas.internal.invalidUserAgent);

    const selected = selectSharedCatalog(c);
    const totalEntries = Array.isArray(selected.catalog.storefronts)
      ? selected.catalog.storefronts.reduce(
          (count: number, storefront: any) =>
            count +
            (Array.isArray(storefront?.catalogEntries)
              ? storefront.catalogEntries.length
              : 0),
          0
        )
      : 0;
    logger.debug(
      `[SHOP] shared catalog served version=${selected.version.build} catalog=${selected.label} storefronts=${selected.catalog.storefronts?.length ?? 0} entries=${totalEntries}`
    );

    return c.json(selected.catalog);
  });
}
