import { app } from "..";
import fs from "node:fs";
import path from "node:path";
import { v4 as uuidv4 } from "uuid";
import getVersion from "../utils/handlers/getVersion";
import { Atlas } from "../utils/handlers/errors";
import { atlasDataPath, atlasDataReadPath } from "../config/paths";
import {
  loadBattlePassData,
  isBattlePassOffer,
  handleBattlePassPurchase,
  handleTierPurchase,
} from "../utils/handlers/battlepass";

const userpath = new Set();
const profilesDir = atlasDataPath("static", "profiles");
const MAP_DISCOVERY_QUEST_IDS = [
  "Quest:quest_s11_discover_landmarks",
  "Quest:quest_s11_discover_namedlocations",
  "Quest:quest_ch5s5_discover_landmarks",
  "Quest:quest_ch5s5_discover_namedlocations",
  "Quest:quest_rufus_discover_namedlocations",
] as const;
let mapDiscoveryQuestTemplates: Record<string, any> | null = null;

function parseJson(raw: string): any {
  return JSON.parse(raw.replace(/^\uFEFF/, ""));
}

function cloneDeep<T>(value: T): T {
  return JSON.parse(JSON.stringify(value));
}

function isPlainObject(value: unknown): value is Record<string, any> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function getMapDiscoveryQuestTemplates(): Record<string, any> {
  if (mapDiscoveryQuestTemplates) {
    return mapDiscoveryQuestTemplates;
  }

  mapDiscoveryQuestTemplates = {};

  try {
    const templatePath = atlasDataReadPath("static", "profiles", "profile_athena.json");
    const template = parseJson(fs.readFileSync(templatePath, "utf8"));
    const templateItems = isPlainObject(template?.items) ? template.items : {};

    for (const questId of MAP_DISCOVERY_QUEST_IDS) {
      const quest = templateItems[questId];
      if (isPlainObject(quest)) {
        mapDiscoveryQuestTemplates[questId] = quest;
      }
    }
  } catch (err) {
    console.error("[MCP] Failed to load map discovery quest templates:", err);
  }

  return mapDiscoveryQuestTemplates;
}

function ensureMapDiscoveryQuests(profile: any): boolean {
  if (!isPlainObject(profile)) return false;
  if (!isPlainObject(profile.items)) profile.items = {};

  const templates = getMapDiscoveryQuestTemplates();
  let changed = false;

  for (const questId of MAP_DISCOVERY_QUEST_IDS) {
    const template = templates[questId];
    if (!isPlainObject(template)) continue;

    const current = profile.items[questId];
    if (!isPlainObject(current)) {
      profile.items[questId] = cloneDeep(template);
      changed = true;
      continue;
    }

    if (current.templateId !== template.templateId) {
      current.templateId = template.templateId;
      changed = true;
    }

    if (current.quantity !== template.quantity) {
      current.quantity = template.quantity;
      changed = true;
    }

    const templateAttributes = isPlainObject(template.attributes) ? template.attributes : {};
    if (!isPlainObject(current.attributes)) {
      current.attributes = cloneDeep(templateAttributes);
      changed = true;
      continue;
    }

    for (const [attributeName, templateValue] of Object.entries(templateAttributes)) {
      const isDiscoveryCompletion =
        attributeName.startsWith("completion_visit_") ||
        attributeName.startsWith("completion_quest_");
      if (!isDiscoveryCompletion && Object.prototype.hasOwnProperty.call(current.attributes, attributeName)) {
        continue;
      }

      if (JSON.stringify(current.attributes[attributeName]) !== JSON.stringify(templateValue)) {
        current.attributes[attributeName] = cloneDeep(templateValue);
        changed = true;
      }
    }
  }

  return changed;
}

// In-memory cache to avoid repeated file reads
const profileCache = new Map();

export default function () {
  app.post(
    "/fortnite/api/game/v2/profile/:accountId/:type/:operation",
    async (c) => {
      const body = await c.req.json();
      let MultiUpdate: any = [];
      let Notifications: any = [];
      let profileChanges: any = [];
      let BaseRevision = 0;
      let profile: any;

      const query = c.req.query();
      const accountId = c.req.param("accountId");

      if (!query.profileId) {
        return c.text("Profile ID not found", 404);
      }

      const profileId = query.profileId;

      const accountProfilesDir = path.join(profilesDir, accountId);
      const profilePath = path.join(
        accountProfilesDir,
        `profile_${profileId}.json`
      );

      const cacheKey = `${accountId}_${profileId}`;
      
      // Check cache first
      if (profileCache.has(cacheKey)) {
        profile = JSON.parse(JSON.stringify(profileCache.get(cacheKey))); // Deep clone
      } else {
        // Load from disk only if not cached
        try {
          const profileData = await fs.promises.readFile(profilePath, "utf8");
          profile = parseJson(profileData);
          profileCache.set(cacheKey, profile);
        } catch (err) {
          // Profile doesn't exist, create it
          await fs.promises.mkdir(accountProfilesDir, { recursive: true });
          
          const templatePath = path.join(
            profilesDir,
            `profile_${profileId}.json`
          );
          try {
            const templateData = await fs.promises.readFile(templatePath, "utf8");
            profile = parseJson(templateData);
          } catch {
            // No template, create empty
            profile = {
              rvn: 0,
              items: {},
              stats: { attributes: {} },
              commandRevision: 0,
            };
          }
          
          // Save and cache the new profile
          await fs.promises.writeFile(profilePath, JSON.stringify(profile, null, 2));
          profileCache.set(cacheKey, profile);
        }
        
        profile = JSON.parse(JSON.stringify(profile)); // Deep clone for this request
      }
      if (!profile.rvn) profile.rvn = 0;
      if (!profile.items) profile.items = {};
      if (!profile.stats) profile.stats = {};
      if (!profile.stats.attributes) profile.stats.attributes = {};
      if (!profile.commandRevision) profile.commandRevision = 0;

      // Build template ID index for fast lookups
      const templateIdIndex = new Map();
      for (const itemId in profile.items) {
        const templateId = profile.items[itemId]?.templateId;
        if (templateId) {
          templateIdIndex.set(templateId.toLowerCase(), itemId);
        }
      }

      const resolveItemId = (itemRef: unknown): string => {
        if (typeof itemRef !== "string" || itemRef.length === 0) {
          return "";
        }

        if (profile.items[itemRef]) {
          return itemRef;
        }

        const normalized = itemRef.toLowerCase();
        const directId = Object.keys(profile.items).find((id) => id.toLowerCase() === normalized);
        if (directId) {
          return directId;
        }

        const indexedId = templateIdIndex.get(normalized);
        if (indexedId) {
          return indexedId;
        }

        for (const [itemId, item] of Object.entries(profile.items)) {
          const templateId = (item as any)?.templateId;
          if (typeof templateId === "string" && templateId.toLowerCase() === normalized) {
            return itemId;
          }
        }

        return "";
      };

      const getVariantPayload = (variants: any): Array<{ channel: string; active: any }> => {
        if (!Array.isArray(variants)) return [];

        return variants
          .filter(
            (variant) =>
              typeof variant === "object" &&
              variant !== null &&
              typeof variant.channel === "string" &&
              variant.channel.length > 0 &&
              Object.prototype.hasOwnProperty.call(variant, "active"),
          )
          .map((variant) => ({
            channel: variant.channel,
            active: variant.active,
          }));
      };

      const parseLoadoutAttributes = (value: any): any => {
        if (typeof value === "string") {
          try {
            const parsed = JSON.parse(value);
            if (parsed && typeof parsed === "object") {
              if (!Array.isArray(parsed.slots)) parsed.slots = [];
              return parsed;
            }
          } catch {
            return { slots: [] };
          }
        }

        if (value && typeof value === "object") {
          const parsed = JSON.parse(JSON.stringify(value));
          if (!Array.isArray(parsed.slots)) parsed.slots = [];
          return parsed;
        }

        return { slots: [] };
      };

      const getModularSlotTemplates = (category: string, slotIndex = 0): string[] => {
        switch (category) {
          case "Character":
            return ["CosmeticLoadoutSlotTemplate:LoadoutSlot_Character"];
          case "Backpack":
            return ["CosmeticLoadoutSlotTemplate:LoadoutSlot_Backpack"];
          case "Pickaxe":
            return ["CosmeticLoadoutSlotTemplate:LoadoutSlot_Pickaxe"];
          case "Glider":
            return ["CosmeticLoadoutSlotTemplate:LoadoutSlot_Glider"];
          case "SkyDiveContrail":
          case "Contrails":
            return ["CosmeticLoadoutSlotTemplate:LoadoutSlot_Contrails"];
          case "MusicPack":
            return ["CosmeticLoadoutSlotTemplate:LoadoutSlot_LobbyMusic"];
          case "LoadingScreen":
            return ["CosmeticLoadoutSlotTemplate:LoadoutSlot_LoadingScreen"];
          case "Dance":
            return [`CosmeticLoadoutSlotTemplate:LoadoutSlot_Emote_${Math.max(0, Math.min(5, slotIndex))}`];
          case "ItemWrap":
            if (slotIndex === -1) {
              return Array.from({ length: 7 }, (_, index) => `CosmeticLoadoutSlotTemplate:LoadoutSlot_Wrap_${index}`);
            }
            return [`CosmeticLoadoutSlotTemplate:LoadoutSlot_Wrap_${Math.max(0, Math.min(6, slotIndex))}`];
          default:
            return [`CosmeticLoadoutSlotTemplate:LoadoutSlot_${category}`];
        }
      };

      const getLoadoutTypeForCategory = (category: string): string => {
        switch (category) {
          case "Character":
          case "Backpack":
          case "Pickaxe":
          case "Glider":
          case "SkyDiveContrail":
          case "Contrails":
            return "CosmeticLoadout:LoadoutSchema_Character";
          case "Dance":
            return "CosmeticLoadout:LoadoutSchema_Emotes";
          case "MusicPack":
          case "LoadingScreen":
            return "CosmeticLoadout:LoadoutSchema_Platform";
          case "ItemWrap":
            return "CosmeticLoadout:LoadoutSchema_Wraps";
          default:
            return "";
        }
      };

      const getPresetLoadoutId = (loadoutType: string, presetId = "0"): string => {
        const presets = profile.stats.attributes.loadout_presets;
        const preset = presets?.[loadoutType];
        const value = preset?.[presetId] ?? preset?.[0];
        return typeof value === "string" ? value : "";
      };

      const buildSlotCustomizations = (variantPayload: Array<{ channel: string; active: any }>) =>
        variantPayload.map((variant) => ({
          channelTag: variant.channel,
          variantTag: String(variant.active),
          additionalData: "",
        }));

      const writeModularLockerSlot = (
        lockerItem: any,
        category: string,
        slotIndex: number,
        itemToSlotTemplate: string,
        variantPayload: Array<{ channel: string; active: any }>,
      ): boolean => {
        if (!lockerItem?.attributes) lockerItem.attributes = {};
        if (!Array.isArray(lockerItem.attributes.slots)) lockerItem.attributes.slots = [];

        const slots = lockerItem.attributes.slots;
        const slotTemplates = getModularSlotTemplates(category, slotIndex);
        const itemCustomizations = buildSlotCustomizations(variantPayload);

        for (const slotTemplate of slotTemplates) {
          let slot = slots.find((entry: any) => entry?.slot_template === slotTemplate || entry?.slotTemplate === slotTemplate);
          if (!slot) {
            slot = { slot_template: slotTemplate };
            slots.push(slot);
          }

          slot.slot_template = slotTemplate;
          slot.slotTemplate = slotTemplate;
          slot.equipped_item = itemToSlotTemplate;
          slot.equippedItemId = itemToSlotTemplate;

          if (itemCustomizations.length > 0) {
            slot.itemCustomizations = itemCustomizations;
            slot.item_customizations = itemCustomizations;
            slot.active_variants = [{ variants: variantPayload }];
          }
        }

        return slotTemplates.length > 0;
      };

      const getActiveLegacyLoadoutId = (): string => {
        const loadouts = profile.stats.attributes.loadouts;
        const index = Number.isInteger(profile.stats.attributes.active_loadout_index)
          ? profile.stats.attributes.active_loadout_index
          : 0;

        return (
          profile.stats.attributes.last_applied_loadout ||
          (Array.isArray(loadouts) ? loadouts[index] || loadouts[0] : "") ||
          "atlas-loadout"
        );
      };

      const writeLegacyLockerSlot = (
        category: string,
        slotIndex: number,
        itemToSlotTemplate: string,
        itemRef: string,
        variantPayload: Array<{ channel: string; active: any }>,
      ): boolean => {
        const legacyLoadoutId = getActiveLegacyLoadoutId();
        const legacyLoadout = profile.items[legacyLoadoutId];
        const lockerSlots = legacyLoadout?.attributes?.locker_slots_data?.slots;
        if (!lockerSlots) return false;

        const setSingleSlot = (slotName: string, favoriteKey: string) => {
          if (!lockerSlots[slotName]) lockerSlots[slotName] = { items: [""] };
          lockerSlots[slotName].items = [itemToSlotTemplate];
          profile.stats.attributes[favoriteKey] = itemRef;

          if (variantPayload.length > 0) {
            lockerSlots[slotName].activeVariants = [{ variants: variantPayload }];
          }
        };

        switch (category) {
          case "Character":
            setSingleSlot("Character", "favorite_character");
            break;
          case "Backpack":
            setSingleSlot("Backpack", "favorite_backpack");
            break;
          case "Pickaxe":
            setSingleSlot("Pickaxe", "favorite_pickaxe");
            break;
          case "Glider":
            setSingleSlot("Glider", "favorite_glider");
            break;
          case "SkyDiveContrail":
          case "Contrails":
            setSingleSlot("SkyDiveContrail", "favorite_skydivecontrail");
            break;
          case "MusicPack":
            setSingleSlot("MusicPack", "favorite_musicpack");
            break;
          case "LoadingScreen":
            setSingleSlot("LoadingScreen", "favorite_loadingscreen");
            break;
          case "Dance":
            if (!lockerSlots.Dance) lockerSlots.Dance = { items: ["", "", "", "", "", ""] };
            if (!Array.isArray(lockerSlots.Dance.items)) lockerSlots.Dance.items = ["", "", "", "", "", ""];
            if (!Array.isArray(profile.stats.attributes.favorite_dance)) profile.stats.attributes.favorite_dance = [];
            if (slotIndex >= 0 && slotIndex <= 5) {
              lockerSlots.Dance.items[slotIndex] = itemToSlotTemplate;
              profile.stats.attributes.favorite_dance[slotIndex] = itemRef;
            }
            break;
          case "ItemWrap":
            if (!lockerSlots.ItemWrap) lockerSlots.ItemWrap = { items: ["", "", "", "", "", "", ""], activeVariants: [] };
            if (!Array.isArray(lockerSlots.ItemWrap.items)) lockerSlots.ItemWrap.items = ["", "", "", "", "", "", ""];
            if (!Array.isArray(profile.stats.attributes.favorite_itemwraps)) profile.stats.attributes.favorite_itemwraps = [];
            if (slotIndex === -1) {
              for (let i = 0; i < 7; i++) {
                lockerSlots.ItemWrap.items[i] = itemToSlotTemplate;
                profile.stats.attributes.favorite_itemwraps[i] = itemRef;
              }
            } else if (slotIndex >= 0 && slotIndex <= 6) {
              lockerSlots.ItemWrap.items[slotIndex] = itemToSlotTemplate;
              profile.stats.attributes.favorite_itemwraps[slotIndex] = itemRef;
            }

            if (variantPayload.length > 0) {
              if (!Array.isArray(lockerSlots.ItemWrap.activeVariants)) lockerSlots.ItemWrap.activeVariants = [];
              const packed = { variants: variantPayload };
              if (slotIndex === -1) {
                for (let i = 0; i < 7; i++) lockerSlots.ItemWrap.activeVariants[i] = packed;
              } else if (slotIndex >= 0 && slotIndex <= 6) {
                lockerSlots.ItemWrap.activeVariants[slotIndex] = packed;
              }
            }
            break;
          default:
            return false;
        }

        profileChanges.push({
          changeType: "itemAttrChanged",
          itemId: legacyLoadoutId,
          attributeName: "locker_slots_data",
          attributeValue: legacyLoadout.attributes.locker_slots_data,
        });

        return true;
      };

      const syncLegacyFromModularLoadout = (loadoutType: string, loadoutAttributes: any) => {
        if (!Array.isArray(loadoutAttributes?.slots)) return;

        const slotMappings: Record<string, { category: string; index?: number }> = {
          "CosmeticLoadoutSlotTemplate:LoadoutSlot_Character": { category: "Character" },
          "CosmeticLoadoutSlotTemplate:LoadoutSlot_Backpack": { category: "Backpack" },
          "CosmeticLoadoutSlotTemplate:LoadoutSlot_Pickaxe": { category: "Pickaxe" },
          "CosmeticLoadoutSlotTemplate:LoadoutSlot_Glider": { category: "Glider" },
          "CosmeticLoadoutSlotTemplate:LoadoutSlot_Contrails": { category: "SkyDiveContrail" },
          "CosmeticLoadoutSlotTemplate:LoadoutSlot_LobbyMusic": { category: "MusicPack" },
          "CosmeticLoadoutSlotTemplate:LoadoutSlot_LoadingScreen": { category: "LoadingScreen" },
        };

        for (let i = 0; i < 6; i++) {
          slotMappings[`CosmeticLoadoutSlotTemplate:LoadoutSlot_Emote_${i}`] = { category: "Dance", index: i };
        }
        for (let i = 0; i < 7; i++) {
          slotMappings[`CosmeticLoadoutSlotTemplate:LoadoutSlot_Wrap_${i}`] = { category: "ItemWrap", index: i };
        }

        for (const slot of loadoutAttributes.slots) {
          const slotTemplate = slot?.slot_template ?? slot?.slotTemplate;
          const mapping = slotMappings[slotTemplate];
          const equippedItem = slot?.equipped_item ?? slot?.equippedItemId;
          if (!mapping || typeof equippedItem !== "string") continue;

          const variantPayload = Array.isArray(slot?.active_variants?.[0]?.variants)
            ? slot.active_variants[0].variants
            : [];
          const itemId = resolveItemId(equippedItem);
          writeLegacyLockerSlot(mapping.category, mapping.index ?? 0, equippedItem, itemId || equippedItem, variantPayload);
        }
      };

      BaseRevision = profile ? profile.rvn : 0;

      switch (c.req.param("operation")) {
        case "QueryProfile":
          if (profileId.toLowerCase() === "athena") {
            ensureMapDiscoveryQuests(profile);
          }

          // Clean any stale gift boxes from common_core profiles
          if (profile.items) {
            for (const [itemId, item] of Object.entries(profile.items)) {
              if ((item as any)?.templateId?.startsWith("GiftBox:")) {
                delete profile.items[itemId];
              }
            }
          }
          break;
        case "RedeemRealMoneyPurchases":
          break;
        case "SetHardcoreModifier":
          break;
        case "AthenaPinQuest":
          break;
        case "MarkNewQuestNotificationSent":
          break;
        case "SetMtxPlatform":
          break;
        case "ClientQuestLogin":
          if (profileId.toLowerCase() === "athena") {
            ensureMapDiscoveryQuests(profile);
          }
          break;
        case "RefreshExpeditions":
          break;
        case "RemoveGiftBox":
          {
            // Client may send giftBoxItemId (string) or giftBoxItemIds (array)
            const ids: string[] = [];
            if (typeof body.giftBoxItemId === "string") ids.push(body.giftBoxItemId);
            if (Array.isArray(body.giftBoxItemIds)) ids.push(...body.giftBoxItemIds);

            for (const gid of ids) {
              if (typeof gid === "string" && profile.items[gid]) {
                delete profile.items[gid];
                profileChanges.push({
                  changeType: "itemRemoved",
                  itemId: gid,
                });
              }
            }

            // Also remove any remaining GiftBox items (cleanup)
            for (const [itemId, item] of Object.entries(profile.items)) {
              if ((item as any)?.templateId?.startsWith("GiftBox:")) {
                delete profile.items[itemId];
                profileChanges.push({
                  changeType: "itemRemoved",
                  itemId,
                });
              }
            }

            if (profileChanges.length > 0) {
              profile.rvn += 1;
              profile.commandRevision += 1;
            }
            break;
          }
        case "PurchaseCatalogEntry":
          {
            const useragent: any = c.req.header("user-agent");
            if (!useragent) return c.json(Atlas.internal.invalidUserAgent);

            const ver = getVersion(c);

            const findOffer = (offerId: unknown) => {
              if (typeof offerId !== "string" || offerId.length === 0) {
                return null;
              }

              let shop: any = {};
              switch (true) {
                case ver.build >= 30.1:
                  shop = JSON.parse(
                    fs.readFileSync(path.join(__dirname, "../../static/shop/v3.json"), "utf8"),
                  );
                  break;
                case ver.build >= 26.3:
                  shop = JSON.parse(
                    fs.readFileSync(path.join(__dirname, "../../static/shop/v2.json"), "utf8"),
                  );
                  break;
                default:
                  shop = JSON.parse(
                    fs.readFileSync(path.join(__dirname, "../../static/shop/v1.json"), "utf8"),
                  );
                  break;
              }

              for (const storefront of shop.storefronts ?? []) {
                const found = storefront.catalogEntries?.find((i: any) => i.offerId === offerId);
                if (found) return { name: storefront.name, offerId: found };
              }

              return null;
            };

            const foundOffer = findOffer(body.offerId) as any;
            if (!foundOffer) return c.json(Atlas.storefront.invalidItem, 400);

            const notification: any = {
              type: "CatalogPurchase",
              primary: true,
              lootResult: {
                items: [],
              },
            };

            const athenaPath = path.join(accountProfilesDir, "profile_athena.json");
            let athena: any;

            try {
              athena = parseJson(await fs.promises.readFile(athenaPath, "utf8"));
            } catch {
              const athenaTemplatePath = path.join(profilesDir, "profile_athena.json");
              try {
                athena = parseJson(await fs.promises.readFile(athenaTemplatePath, "utf8"));
              } catch {
                athena = {
                  rvn: 0,
                  items: {},
                  stats: { attributes: {} },
                  commandRevision: 0,
                };
              }
              await fs.promises.writeFile(athenaPath, JSON.stringify(athena, null, 2));
            }

            if (!athena.rvn) athena.rvn = 0;
            if (!athena.items) athena.items = {};
            if (!athena.stats) athena.stats = {};
            if (!athena.stats.attributes) athena.stats.attributes = {};
            if (!athena.commandRevision) athena.commandRevision = 0;

            MultiUpdate.push({
              profileRevision: athena.rvn || 0,
              profileId: "athena",
              profileChangesBaseRevision: athena.rvn || 0,
              profileChanges: [],
              profileCommandRevision: athena.commandRevision || 0,
            });

            // --- Battle Pass purchase handling ---
            const bpData = loadBattlePassData(ver.season);
            const bpType = bpData ? isBattlePassOffer(bpData, body.offerId) : null;

            if (bpData && bpType) {
              // Check if this specific offer was already purchased
              const purchasedOffers = Array.isArray(athena.stats.attributes.purchased_bp_offers)
                ? athena.stats.attributes.purchased_bp_offers
                : [];

              // Prevent re-purchasing the same battle pass
              if (bpType === "battlepass" && purchasedOffers.includes(body.offerId)) {
                return c.json(Atlas.storefront.alreadyOwned, 400);
              }

              let lootList: any[] = [];

              if (bpType === "battlepass") {
                lootList = handleBattlePassPurchase(
                  athena,
                  profile,
                  bpData,
                  body.offerId,
                  ver.season,
                  profileChanges,
                  MultiUpdate[0].profileChanges
                );

                // Track the offer as purchased so DenyOnFulfillment works client-side
                if (!Array.isArray(athena.stats.attributes.purchased_bp_offers)) {
                  athena.stats.attributes.purchased_bp_offers = [];
                }
                if (!athena.stats.attributes.purchased_bp_offers.includes(body.offerId)) {
                  athena.stats.attributes.purchased_bp_offers.push(body.offerId);
                  MultiUpdate[0].profileChanges.push({
                    changeType: "statModified",
                    name: "purchased_bp_offers",
                    value: athena.stats.attributes.purchased_bp_offers,
                  });
                }
              } else if (bpType === "tier") {
                const purchaseQuantity = Number(body.purchaseQuantity ?? 1);
                lootList = handleTierPurchase(
                  athena,
                  profile,
                  bpData,
                  purchaseQuantity,
                  ver.season,
                  profileChanges,
                  MultiUpdate[0].profileChanges
                );
              }

              // Add gift box to common_core for the BP purchase animation
              const giftBoxId = uuidv4().replace(/-/g, "");
              const giftBoxTemplate = bpType === "battlepass"
                ? "GiftBox:gb_battlepasspurchased"
                : "GiftBox:gb_battlepass";

              profile.items[giftBoxId] = {
                templateId: giftBoxTemplate,
                attributes: {
                  fromAccountId: "",
                  lootList,
                },
                quantity: 1,
              };
              profileChanges.push({
                changeType: "itemAdded",
                itemId: giftBoxId,
                item: profile.items[giftBoxId],
              });

              notification.lootResult.items = lootList.map((l: any) => ({
                itemType: l.itemType,
                itemGuid: l.itemGuid,
                itemProfile: "athena",
                quantity: l.quantity,
              }));
              Notifications.push(notification);

              // Handle currency deduction for BP
              const offerPrice = Number(foundOffer.offerId?.prices?.[0]?.finalPrice ?? 0);
              const offerCurrencyType = String(foundOffer.offerId?.prices?.[0]?.currencyType ?? "").toLowerCase();

              if (offerCurrencyType === "mtxcurrency" && offerPrice > 0) {
                const totalCost = bpType === "tier"
                  ? offerPrice * (Number(body.purchaseQuantity ?? 1))
                  : offerPrice;
                let paid = false;
                const currentMtxPlatform = String(profile.stats?.attributes?.current_mtx_platform ?? "").toLowerCase();

                for (const key in profile.items) {
                  const item = profile.items[key];
                  const templateId = String(item?.templateId ?? "").toLowerCase();
                  if (!templateId.startsWith("currency:mtx")) continue;

                  const currencyPlatform = String(item?.attributes?.platform ?? "").toLowerCase();
                  if (currencyPlatform !== currentMtxPlatform && currencyPlatform !== "shared") continue;

                  if (Number(item?.quantity ?? 0) < totalCost) {
                    return c.json(Atlas.storefront.currencyInsufficient, 400);
                  }

                  profile.items[key].quantity -= totalCost;
                  profileChanges.push({
                    changeType: "itemQuantityChanged",
                    itemId: key,
                    quantity: profile.items[key].quantity,
                  });
                  paid = true;
                  break;
                }

                if (!paid) {
                  return c.json(Atlas.storefront.currencyInsufficient, 400);
                }
              }

              // Save athena
              athena.rvn += 1;
              athena.commandRevision += 1;
              athena.updated = new Date().toISOString();
              MultiUpdate[0].profileRevision = athena.rvn;
              MultiUpdate[0].profileCommandRevision = athena.commandRevision;

              await fs.promises.writeFile(athenaPath, JSON.stringify(athena, null, 2));
              profileCache.set(
                `${accountId}_athena`,
                JSON.parse(JSON.stringify(athena)),
              );

              if (profileChanges.length > 0) {
                profile.rvn += 1;
                profile.commandRevision += 1;
                profile.updated = new Date().toISOString();
              }

              break;
            }
            // --- End Battle Pass handling ---

            for (const value of foundOffer.offerId.itemGrants ?? []) {
              const itemExists = Object.values(athena.items).some(
                (item: any) =>
                  item &&
                  item.templateId &&
                  item.templateId.toLowerCase() === String(value.templateId).toLowerCase(),
              );

              if (itemExists) return c.json(Atlas.storefront.alreadyOwned, 400);

              const itemId = uuidv4();
              const item = {
                templateId: value.templateId,
                attributes: {
                  item_seen: false,
                  variants: [],
                },
                quantity: 1,
              };

              athena.items[itemId] = item;

              MultiUpdate[0].profileChanges.push({
                changeType: "itemAdded",
                itemId,
                item: athena.items[itemId],
              });

              notification.lootResult.items.push({
                itemType: item.templateId,
                itemGuid: itemId,
                itemProfile: "athena",
                quantity: 1,
              });
            }

            Notifications.push(notification);

            // Always push a profileChange for common_core so we never
            // accidentally fall into fullProfileUpdate
            const offerPrice = Number(foundOffer.offerId?.prices?.[0]?.finalPrice ?? 0);
            const offerCurrencyType = String(foundOffer.offerId?.prices?.[0]?.currencyType ?? "").toLowerCase();

            if (offerCurrencyType === "mtxcurrency") {
              let paid = false;
              const currentMtxPlatform = String(profile.stats?.attributes?.current_mtx_platform ?? "").toLowerCase();

              for (const key in profile.items) {
                const item = profile.items[key];
                const templateId = String(item?.templateId ?? "").toLowerCase();
                if (!templateId.startsWith("currency:mtx")) continue;

                const currencyPlatform = String(item?.attributes?.platform ?? "").toLowerCase();
                if (currencyPlatform !== currentMtxPlatform && currencyPlatform !== "shared") continue;

                if (Number(item?.quantity ?? 0) < offerPrice) {
                  return c.json(Atlas.storefront.currencyInsufficient, 400);
                }

                profile.items[key].quantity -= offerPrice;
                profileChanges.push({
                  changeType: "itemQuantityChanged",
                  itemId: key,
                  quantity: profile.items[key].quantity,
                });

                paid = true;
                break;
              }

              if (!paid && offerPrice > 0) {
                return c.json(Atlas.storefront.currencyInsufficient, 400);
              }
            }

            if (MultiUpdate[0].profileChanges.length > 0) {
              athena.rvn += 1;
              athena.commandRevision += 1;
              athena.updated = new Date().toISOString();

              MultiUpdate[0].profileRevision = athena.rvn;
              MultiUpdate[0].profileCommandRevision = athena.commandRevision;

              await fs.promises.writeFile(athenaPath, JSON.stringify(athena, null, 2));
              profileCache.set(
                `${accountId}_athena`,
                JSON.parse(JSON.stringify(athena)),
              );
            }

            if (profileChanges.length > 0) {
              profile.rvn += 1;
              profile.commandRevision += 1;
              profile.updated = new Date().toISOString();
            }

            break;
          }
        case "SetAffiliateName":
          const { affiliateName } = await c.req.json();
          profile.stats.attributes.mtx_affiliate_set_time =
            new Date().toISOString();
          profile.stats.attributes.mtx_affiliate = affiliateName;
          profileChanges.push({
            changeType: "statModified",
            name: "mtx_affiliate_set_time",
            value: profile.stats.attributes.mtx_affiliate_set_time,
          });

          profileChanges.push({
            changeType: "statModified",
            name: "mtx_affiliate",
            value: profile.stats.attributes.mtx_affiliate,
          });
          profile.rvn += 1;
          profile.commandRevision += 1;
          break;
        case "SetCosmeticLockerBanner": // br banner 2
          profile.stats.attributes.banner_icon = body.homebaseBannerIconId;
          profile.stats.attributes.banner_color = body.homebaseBannerColorId;

          profileChanges.push({
            changeType: "statModified",
            name: "banner_icon",
            value: profile.stats.attributes.banner_icon,
          });

          profileChanges.push({
            changeType: "statModified",
            name: "banner_color",
            value: profile.stats.attributes.banner_color,
          });
          profile.rvn += 1;
          profile.commandRevision += 1;
          break;
        case "SetBattleRoyaleBanner": // br banner 1
          profile.stats.attributes.banner_icon = body.homebaseBannerIconId;
          profile.stats.attributes.banner_color = body.homebaseBannerColorId;

          profileChanges.push({
            changeType: "statModified",
            name: "banner_icon",
            value: profile.stats.attributes.banner_icon,
          });

          profileChanges.push({
            changeType: "statModified",
            name: "banner_color",
            value: profile.stats.attributes.banner_color,
          });
          profile.rvn += 1;
          profile.commandRevision += 1;
          break;
        case "EquipBattleRoyaleCustomization": // br locker 1
          let statName;
          let itemToSlot;
          let itemToSlotID = resolveItemId(body.itemToSlot);
          const itemToSlotTemplate =
            itemToSlotID && profile.items[itemToSlotID]?.templateId
              ? profile.items[itemToSlotID].templateId
              : body.itemToSlot;

          switch (body.slotName) {
            case "Character":
              statName = "favorite_character";
              itemToSlot = body.itemToSlot;
              profile.stats.attributes[statName] = itemToSlot;
              profileChanges.push({
                changeType: "statModified",
                name: statName,
                value: profile.stats.attributes[statName],
              });
              break;
            case "Backpack":
              statName = "favorite_backpack";
              itemToSlot = body.itemToSlot;
              profile.stats.attributes[statName] = itemToSlot;
              profileChanges.push({
                changeType: "statModified",
                name: statName,
                value: profile.stats.attributes[statName],
              });
              break;
            case "Pickaxe":
              statName = "favorite_pickaxe";
              itemToSlot = body.itemToSlot;
              profile.stats.attributes[statName] = itemToSlot;
              profileChanges.push({
                changeType: "statModified",
                name: statName,
                value: profile.stats.attributes[statName],
              });
              break;
            case "Glider":
              statName = "favorite_glider";
              itemToSlot = body.itemToSlot;
              profile.stats.attributes[statName] = itemToSlot;
              profileChanges.push({
                changeType: "statModified",
                name: statName,
                value: profile.stats.attributes[statName],
              });
              break;
            case "SkyDiveContrail":
              statName = "favorite_skydivecontrail";
              itemToSlot = body.itemToSlot;
              profile.stats.attributes[statName] = itemToSlot;
              profileChanges.push({
                changeType: "statModified",
                name: statName,
                value: profile.stats.attributes[statName],
              });
              break;
            case "MusicPack":
              statName = "favorite_musicpack";
              itemToSlot = body.itemToSlot;
              profile.stats.attributes[statName] = itemToSlot;
              profileChanges.push({
                changeType: "statModified",
                name: statName,
                value: profile.stats.attributes[statName],
              });
              break;
            case "LoadingScreen":
              statName = "favorite_loadingscreen";
              itemToSlot = body.itemToSlot;
              profile.stats.attributes[statName] = itemToSlot;
              profileChanges.push({
                changeType: "statModified",
                name: statName,
                value: profile.stats.attributes[statName],
              });
              break;
            case "Dance":
            case "ItemWrap":
              const bIsDance = body.slotName === "Dance";
              statName = bIsDance ? "favorite_dance" : "favorite_itemwraps";
              let arr = profile.stats.attributes[statName] || [];
              if (body.indexWithinSlot === -1) {
                arr = [];
                for (let i = 0; i < (bIsDance ? 6 : 7); ++i) {
                  arr[i] = body.itemToSlot;
                }
              } else {
                arr[body.indexWithinSlot || 0] = body.itemToSlot;
              }
              for (let i = 0; i < arr.length; ++i) {
                if (arr[i] == null) {
                  arr[i] = "";
                }
              }
              profile.stats.attributes[statName] = arr;
              profileChanges.push({
                changeType: "statModified",
                name: statName,
                value: profile.stats.attributes[statName],
              });
              break;
            default:
              break;
          }
          let Variants = body.variantUpdates;
          if (Array.isArray(Variants) && itemToSlotID && profile.items[itemToSlotID]) {
            if (!profile.items[itemToSlotID].attributes) {
              profile.items[itemToSlotID].attributes = {};
            }
            if (!profile.items[itemToSlotID].attributes.variants) {
              profile.items[itemToSlotID].attributes.variants = [];
            }
            for (let i in Variants) {
              if (typeof Variants[i] != "object") continue;
              if (!Variants[i].channel) continue;
              if (!Variants[i].active) continue;

              let index = profile.items[
                itemToSlotID
              ].attributes.variants.findIndex(
                (x: any) => x.channel == Variants[i].channel
              );

              if (index === -1) {
                profile.items[itemToSlotID].attributes.variants.push({
                  channel: Variants[i].channel,
                  active: Variants[i].active,
                  owned: Variants[i].owned || [],
                });
              } else {
                profile.items[itemToSlotID].attributes.variants[index].active =
                  Variants[i].active;
              }
            }

            profileChanges.push({
              changeType: "itemAttrChanged",
              itemId: itemToSlotID,
              attributeName: "variants",
              attributeValue: profile.items[itemToSlotID].attributes.variants,
            });
          }

          const loadouts = Array.isArray(profile.stats?.attributes?.loadouts)
            ? profile.stats.attributes.loadouts
            : [];
          const activeLoadoutIndex =
            typeof profile.stats?.attributes?.active_loadout_index === "number"
              ? profile.stats.attributes.active_loadout_index
              : 0;
          const activeLoadoutId =
            loadouts[activeLoadoutIndex] || profile.stats?.attributes?.last_applied_loadout;
          const activeLoadout = activeLoadoutId ? profile.items[activeLoadoutId] : null;
          const activeSlots = activeLoadout?.attributes?.locker_slots_data?.slots;

          if (activeSlots && body.slotName) {
            let lockerSlotChanged = false;
            const variantPayload = getVariantPayload(Variants);

            switch (body.slotName) {
              case "Dance": {
                const indexWithinSlot = Number.isInteger(body.indexWithinSlot)
                  ? body.indexWithinSlot
                  : 0;

                if (
                  activeSlots.Dance &&
                  Array.isArray(activeSlots.Dance.items) &&
                  indexWithinSlot >= 0 &&
                  indexWithinSlot <= 5
                ) {
                  activeSlots.Dance.items[indexWithinSlot] = itemToSlotTemplate;
                  lockerSlotChanged = true;
                }
                break;
              }
              case "ItemWrap": {
                const indexWithinSlot = Number.isInteger(body.indexWithinSlot)
                  ? body.indexWithinSlot
                  : 0;

                if (activeSlots.ItemWrap && Array.isArray(activeSlots.ItemWrap.items)) {
                  if (indexWithinSlot >= 0 && indexWithinSlot <= 7) {
                    activeSlots.ItemWrap.items[indexWithinSlot] = itemToSlotTemplate;
                    lockerSlotChanged = true;
                  } else if (indexWithinSlot === -1) {
                    for (let i = 0; i < 7; i++) {
                      activeSlots.ItemWrap.items[i] = itemToSlotTemplate;
                    }
                    lockerSlotChanged = true;
                  }
                }

                if (variantPayload.length > 0 && activeSlots.ItemWrap) {
                  if (!Array.isArray(activeSlots.ItemWrap.activeVariants)) {
                    activeSlots.ItemWrap.activeVariants = [];
                  }

                  const packed = [{ variants: variantPayload }];

                  if (indexWithinSlot >= 0 && indexWithinSlot <= 7) {
                    activeSlots.ItemWrap.activeVariants[indexWithinSlot] = packed[0];
                  } else if (indexWithinSlot === -1) {
                    for (let i = 0; i < 7; i++) {
                      activeSlots.ItemWrap.activeVariants[i] = packed[0];
                    }
                  } else {
                    activeSlots.ItemWrap.activeVariants[0] = packed[0];
                  }
                  lockerSlotChanged = true;
                }
                break;
              }
              default:
                if (activeSlots[body.slotName] && Array.isArray(activeSlots[body.slotName].items)) {
                  activeSlots[body.slotName].items = [itemToSlotTemplate];
                  lockerSlotChanged = true;
                }

                if (variantPayload.length > 0 && activeSlots[body.slotName]) {
                  if (!Array.isArray(activeSlots[body.slotName].activeVariants)) {
                    activeSlots[body.slotName].activeVariants = [];
                  }
                  activeSlots[body.slotName].activeVariants[0] = {
                    variants: variantPayload,
                  };
                  lockerSlotChanged = true;
                }
                break;
            }

            if (lockerSlotChanged) {
              profileChanges.push({
                changeType: "itemAttrChanged",
                itemId: activeLoadoutId,
                attributeName: "locker_slots_data",
                attributeValue: activeLoadout.attributes.locker_slots_data,
              });
            }
          }
          profile.rvn += 1;
          profile.commandRevision += 1;
          break;
        case "SetCosmeticLockerSlot": // br locker 2
          if (body.category && body.lockerItem) {
            const lockerItem = profile.items[body.lockerItem];
            const lockerSlots = lockerItem?.attributes?.locker_slots_data?.slots;
            if (!lockerSlots) {
              if (!lockerItem?.templateId?.startsWith("CosmeticLoadout:")) {
                break;
              }

              const slotIndex = Number.isInteger(body.slotIndex) ? body.slotIndex : 0;
              let itemToSlot = body.itemToSlot;

              if (itemToSlot === undefined || itemToSlot === null) {
                const slotTemplate = getModularSlotTemplates(body.category, slotIndex)[0];
                const existingSlot = lockerItem.attributes?.slots?.find(
                  (slot: any) => slot?.slot_template === slotTemplate || slot?.slotTemplate === slotTemplate,
                );
                itemToSlot = existingSlot?.equipped_item ?? existingSlot?.equippedItemId ?? "";
              }

              const itemToSlotID = itemToSlot ? resolveItemId(itemToSlot) : "";
              const itemToSlotTemplate =
                itemToSlotID && profile.items[itemToSlotID]?.templateId
                  ? profile.items[itemToSlotID].templateId
                  : itemToSlot || "";

              const variantPayload = getVariantPayload(body.variantUpdates);
              if (Array.isArray(body.variantUpdates) && itemToSlotID) {
                const item = profile.items[itemToSlotID];
                if (item) {
                  if (!item.attributes) item.attributes = {};
                  if (!Array.isArray(item.attributes.variants)) item.attributes.variants = [];

                  for (const variant of body.variantUpdates) {
                    if (typeof variant !== "object" || !variant?.channel || !variant?.active) continue;

                    const index = item.attributes.variants.findIndex(
                      (entry: any) => entry.channel === variant.channel,
                    );

                    if (index === -1) {
                      item.attributes.variants.push({
                        channel: variant.channel,
                        active: variant.active,
                        owned: variant.owned || [],
                      });
                    } else {
                      item.attributes.variants[index].active = variant.active;
                    }
                  }

                  profileChanges.push({
                    changeType: "itemAttrChanged",
                    itemId: itemToSlotID,
                    attributeName: "variants",
                    attributeValue: item.attributes.variants,
                  });
                }
              }

              const changed = writeModularLockerSlot(
                lockerItem,
                body.category,
                slotIndex,
                itemToSlotTemplate,
                variantPayload,
              );

              writeLegacyLockerSlot(
                body.category,
                slotIndex,
                itemToSlotTemplate,
                itemToSlotID || itemToSlotTemplate,
                variantPayload,
              );

              if (changed) {
                profile.rvn += 1;
                profile.commandRevision += 1;

                profileChanges.push({
                  changeType: "itemAttrChanged",
                  itemId: body.lockerItem,
                  attributeName: "slots",
                  attributeValue: lockerItem.attributes.slots,
                });
              }

              break;
            }

            const slotIndex = Number.isInteger(body.slotIndex) ? body.slotIndex : 0;
            let itemToSlot = body.itemToSlot;

            if (itemToSlot === undefined || itemToSlot === null) {
              switch (body.category) {
                case "Dance":
                  if (Array.isArray(lockerSlots.Dance?.items)) {
                    itemToSlot = lockerSlots.Dance.items[slotIndex] ?? lockerSlots.Dance.items[0] ?? "";
                  }
                  break;
                case "ItemWrap":
                  if (Array.isArray(lockerSlots.ItemWrap?.items)) {
                    itemToSlot = lockerSlots.ItemWrap.items[slotIndex] ?? lockerSlots.ItemWrap.items[0] ?? "";
                  }
                  break;
                default:
                  if (Array.isArray(lockerSlots[body.category]?.items)) {
                    itemToSlot = lockerSlots[body.category].items[0] ?? "";
                  }
                  break;
              }
            }

            let itemToSlotID = "";

            if (body.itemToSlot) {
              itemToSlotID = resolveItemId(body.itemToSlot);
            } else if (itemToSlot) {
              itemToSlotID = resolveItemId(itemToSlot);
            }

            const itemToSlotTemplate =
              itemToSlotID && profile.items[itemToSlotID]?.templateId
                ? profile.items[itemToSlotID].templateId
                : itemToSlot;

            let Variants = body.variantUpdates;
            const variantPayload = getVariantPayload(Variants);
            if (Array.isArray(Variants) && itemToSlotID) {
              if (!profile.items[itemToSlotID]) {
                profile.items[itemToSlotID] = { attributes: { variants: [] } };
              }

              for (let i in Variants) {
                if (typeof Variants[i] != "object") continue;
                if (!Variants[i].channel) continue;
                if (!Variants[i].active) continue;

                if (profile.items[itemToSlotID]) {
                  let item = profile.items[itemToSlotID];
                  if (!item.attributes.variants) item.attributes.variants = [];

                  let index = item.attributes.variants.findIndex(
                    (x: any) => x.channel == Variants[i].channel
                  );

                  if (index == -1) {
                    item.attributes.variants.push({
                      channel: Variants[i].channel,
                      active: Variants[i].active,
                      owned: Variants[i].owned || []
                    });
                  } else {
                    item.attributes.variants[index].active = Variants[i].active;
                  }
                }
              }

              profileChanges.push({
                changeType: "itemAttrChanged",
                itemId: itemToSlotID,
                attributeName: "variants",
                attributeValue: profile.items[itemToSlotID] ? profile.items[itemToSlotID].attributes.variants : [],
              });
            }

            const writeSlotActiveVariants = () => {
              if (variantPayload.length === 0) return;

              switch (body.category) {
                case "ItemWrap":
                  if (lockerSlots.ItemWrap) {
                    if (!Array.isArray(lockerSlots.ItemWrap.activeVariants)) {
                      lockerSlots.ItemWrap.activeVariants = [];
                    }

                    const packed = { variants: variantPayload };
                    if (slotIndex >= 0 && slotIndex <= 7) {
                      lockerSlots.ItemWrap.activeVariants[slotIndex] = packed;
                    } else if (slotIndex === -1) {
                      for (let i = 0; i < 7; i++) {
                        lockerSlots.ItemWrap.activeVariants[i] = packed;
                      }
                    } else {
                      lockerSlots.ItemWrap.activeVariants[0] = packed;
                    }
                  }
                  break;
                case "Dance":
                  break;
                default:
                  if (lockerSlots[body.category]) {
                    if (!Array.isArray(lockerSlots[body.category].activeVariants)) {
                      lockerSlots[body.category].activeVariants = [];
                    }
                    lockerSlots[body.category].activeVariants[0] = {
                      variants: variantPayload,
                    };
                  }
                  break;
              }
            };

            writeSlotActiveVariants();

            switch (body.category) {
              case "Character":
                profile.items[
                  body.lockerItem
                ].attributes.locker_slots_data.slots.Character.items = [
                    itemToSlotTemplate,
                  ];
                profile.stats.attributes.favorite_character = itemToSlotID || itemToSlot;
                break;
              case "Backpack":
                profile.items[
                  body.lockerItem
                ].attributes.locker_slots_data.slots.Backpack.items = [
                    itemToSlotTemplate,
                  ];
                profile.stats.attributes.favorite_backpack = itemToSlotID || itemToSlot;
                break;
              case "Pickaxe":
                profile.items[
                  body.lockerItem
                ].attributes.locker_slots_data.slots.Pickaxe.items = [
                    itemToSlotTemplate,
                  ];
                profile.stats.attributes.favorite_pickaxe = itemToSlotID || itemToSlot;
                break;
              case "Glider":
                profile.items[
                  body.lockerItem
                ].attributes.locker_slots_data.slots.Glider.items = [
                    itemToSlotTemplate,
                  ];
                profile.stats.attributes.favorite_glider = itemToSlotID || itemToSlot;
                break;
              case "SkyDiveContrail":
                profile.items[
                  body.lockerItem
                ].attributes.locker_slots_data.slots.SkyDiveContrail.items = [
                    itemToSlotTemplate,
                  ];
                profile.stats.attributes.favorite_skydivecontrail = itemToSlotID || itemToSlot;
                break;
              case "MusicPack":
                profile.items[
                  body.lockerItem
                ].attributes.locker_slots_data.slots.MusicPack.items = [
                    itemToSlotTemplate,
                  ];
                profile.stats.attributes.favorite_musicpack = itemToSlotID || itemToSlot;
                break;
              case "LoadingScreen":
                profile.items[
                  body.lockerItem
                ].attributes.locker_slots_data.slots.LoadingScreen.items = [
                    itemToSlotTemplate,
                  ];
                profile.stats.attributes.favorite_loadingscreen = itemToSlotID || itemToSlot;
                break;
              case "Dance":
                const indexWithinSlot = slotIndex;
                if (indexWithinSlot >= 0 && indexWithinSlot <= 5) {
                  profile.items[
                    body.lockerItem
                  ].attributes.locker_slots_data.slots.Dance.items[
                    indexWithinSlot
                  ] = itemToSlotTemplate;

                  if (!profile.stats.attributes.favorite_dance) profile.stats.attributes.favorite_dance = [];
                  profile.stats.attributes.favorite_dance[indexWithinSlot] = itemToSlotID || itemToSlot;
                }
                break;
              case "ItemWrap":
                const indexWithinWrap = slotIndex;
                if (indexWithinWrap >= 0 && indexWithinWrap <= 7) {
                  profile.items[
                    body.lockerItem
                  ].attributes.locker_slots_data.slots.ItemWrap.items[
                    indexWithinWrap
                  ] = itemToSlotTemplate;

                  if (!profile.stats.attributes.favorite_itemwraps) profile.stats.attributes.favorite_itemwraps = [];
                  profile.stats.attributes.favorite_itemwraps[indexWithinWrap] = itemToSlotID || itemToSlot;
                } else if (indexWithinWrap === -1) {
                  for (let i = 0; i < 7; i++) {
                    profile.items[
                      body.lockerItem
                    ].attributes.locker_slots_data.slots.ItemWrap.items[i] = itemToSlotTemplate;

                    if (!profile.stats.attributes.favorite_itemwraps) profile.stats.attributes.favorite_itemwraps = [];
                    profile.stats.attributes.favorite_itemwraps[i] = itemToSlotID || itemToSlot;
                  }
                }
                break;
              default:
                break;
            }

            const modularLoadoutType = getLoadoutTypeForCategory(body.category);
            const modularLoadoutId = modularLoadoutType ? getPresetLoadoutId(modularLoadoutType) : "";
            if (modularLoadoutId && profile.items[modularLoadoutId]) {
              writeModularLockerSlot(
                profile.items[modularLoadoutId],
                body.category,
                slotIndex,
                itemToSlotTemplate,
                variantPayload,
              );

              profileChanges.push({
                changeType: "itemAttrChanged",
                itemId: modularLoadoutId,
                attributeName: "slots",
                attributeValue: profile.items[modularLoadoutId].attributes.slots,
              });
            }

            profile.rvn += 1;
            profile.commandRevision += 1;

            profileChanges.push({
              changeType: "itemAttrChanged",
              itemId: body.lockerItem,
              attributeName: "locker_slots_data",
              attributeValue:
                profile.items[body.lockerItem].attributes.locker_slots_data,
            });
          }
          break;
        case "ClaimMfaEnabled":
          break;
        case "PutModularCosmeticLoadout": // br locker 3
          const loadoutType = typeof body.loadoutType === "string" ? body.loadoutType : "";
          const presetId = body.presetId !== undefined && body.presetId !== null ? String(body.presetId) : "0";
          const loadoutAttributes = parseLoadoutAttributes(
            body.loadoutData ?? body.attributes ?? (Array.isArray(body.slots) ? { slots: body.slots } : undefined),
          );

          if (!loadoutType) {
            break;
          }

          if (!profile.stats.attributes.hasOwnProperty("loadout_presets")) {
            profile.stats.attributes.loadout_presets = {};

            profileChanges.push({
              changeType: "statModified",
              name: "loadout_presets",
              value: {},
            });
          }

          if (
            !profile.stats.attributes.loadout_presets.hasOwnProperty(
              loadoutType
            )
          ) {
            const newLoadout = uuidv4();

            profile.items[newLoadout] = {
              templateId: loadoutType,
              attributes: {},
              quantity: 1,
            };

            profileChanges.push({
              changeType: "itemAdded",
              itemId: newLoadout,
              item: profile.items[newLoadout],
            });

            profile.stats.attributes.loadout_presets[loadoutType] = {
              [presetId]: newLoadout,
            };

            profileChanges.push({
              changeType: "statModified",
              name: "loadout_presets",
              value: profile.stats.attributes.loadout_presets,
            });
          }

          if (!profile.stats.attributes.loadout_presets[loadoutType].hasOwnProperty(presetId)) {
            const newLoadout = uuidv4();

            profile.items[newLoadout] = {
              templateId: loadoutType,
              attributes: {},
              quantity: 1,
            };

            profile.stats.attributes.loadout_presets[loadoutType][presetId] = newLoadout;

            profileChanges.push({
              changeType: "itemAdded",
              itemId: newLoadout,
              item: profile.items[newLoadout],
            });

            profileChanges.push({
              changeType: "statModified",
              name: "loadout_presets",
              value: profile.stats.attributes.loadout_presets,
            });
          }

          const loadoutID =
            profile.stats.attributes.loadout_presets[loadoutType][presetId];
          if (profile.items[loadoutID]) {
            profile.items[loadoutID].attributes = loadoutAttributes;
            syncLegacyFromModularLoadout(loadoutType, loadoutAttributes);

            profileChanges.push({
              changeType: "itemAttrChanged",
              itemId: loadoutID,
              attributeName: "slots",
              attributeValue: profile.items[loadoutID].attributes.slots,
            });

            profile.rvn += 1;
            profile.commandRevision += 1;
          }
          break;
        default:
          break;
      }

      // For QueryProfile or if no changes were made, send full profile
      if (c.req.param("operation") === "QueryProfile" || profileChanges.length === 0) {
        profileChanges = [{
          changeType: "fullProfileUpdate",
          profile: profile,
        }];
      }

      const response = {
        profileRevision: profile ? profile.rvn || 0 : 0,
        profileId: query.profileId,
        profileChangesBaseRevision: BaseRevision,
        profileChanges: profileChanges,
        notifications: Notifications,
        profileCommandRevision: profile ? profile.commandRevision || 0 : 0,
        serverTime: new Date().toISOString(),
        multiUpdate: MultiUpdate,
        responseVersion: 1,
      };

      // Update cache and save profile asynchronously
      profileCache.set(cacheKey, JSON.parse(JSON.stringify(profile)));
      fs.promises.writeFile(profilePath, JSON.stringify(profile, null, 2))
        .catch(err => console.error(`[MCP] Failed to save profile for ${accountId}:`, err));

      userpath.add(profileId);

      return c.json(response);
    }
  );

  // Public profile endpoint - allows clients to see other players' cosmetics
  app.post(
    "/fortnite/api/game/v2/profile/:accountId/public/QueryProfile",
    async (c) => {
      const query = c.req.query();
      const accountId = c.req.param("accountId");

      if (!query.profileId) {
        return c.text("Profile ID not found", 404);
      }

      const profileId = query.profileId;
      const cacheKey = `${accountId}_${profileId}`;
      let profile: any;

      // Check cache first
      if (profileCache.has(cacheKey)) {
        profile = profileCache.get(cacheKey);
      } else {
        // Load from disk
        const accountProfilesDir = path.join(profilesDir, accountId);
        const profilePath = path.join(accountProfilesDir, `profile_${profileId}.json`);

        try {
          const profileData = await fs.promises.readFile(profilePath, "utf8");
          profile = parseJson(profileData);
          profileCache.set(cacheKey, profile);
        } catch {
          // No profile found, use template
          const templatePath = path.join(
            profilesDir,
            `profile_${profileId}.json`
          );
          try {
            const templateData = await fs.promises.readFile(templatePath, "utf8");
            profile = parseJson(templateData);
          } catch {
            profile = {
              rvn: 0,
              items: {},
              stats: { attributes: {} },
              commandRevision: 0,
            };
          }
        }
      }

      return c.json({
        profileRevision: profile.rvn || 0,
        profileId: profileId,
        profileChangesBaseRevision: profile.rvn || 0,
        profileChanges: [{ changeType: "fullProfileUpdate", profile: profile }],
        profileCommandRevision: profile.commandRevision || 0,
        serverTime: new Date().toISOString(),
        responseVersion: 1,
      });
    }
  );

  // Public profile endpoint (GET variant)
  app.get(
    "/fortnite/api/game/v2/profile/:accountId/public/QueryProfile",
    async (c) => {
      const query = c.req.query();
      const accountId = c.req.param("accountId");

      if (!query.profileId) {
        return c.text("Profile ID not found", 404);
      }

      const profileId = query.profileId;
      const cacheKey = `${accountId}_${profileId}`;
      let profile: any;

      // Check cache first
      if (profileCache.has(cacheKey)) {
        profile = profileCache.get(cacheKey);
      } else {
        // Load from disk
        const accountProfilesDir = path.join(profilesDir, accountId);
        const profilePath = path.join(accountProfilesDir, `profile_${profileId}.json`);

        try {
          const profileData = await fs.promises.readFile(profilePath, "utf8");
          profile = parseJson(profileData);
          profileCache.set(cacheKey, profile);
        } catch {
          // No profile found, use template
          const templatePath = path.join(
            profilesDir,
            `profile_${profileId}.json`
          );
          try {
            const templateData = await fs.promises.readFile(templatePath, "utf8");
            profile = parseJson(templateData);
          } catch {
            profile = {
              rvn: 0,
              items: {},
              stats: { attributes: {} },
              commandRevision: 0,
            };
          }
        }
      }

      return c.json({
        profileRevision: profile.rvn || 0,
        profileId: profileId,
        profileChangesBaseRevision: profile.rvn || 0,
        profileChanges: [{ changeType: "fullProfileUpdate", profile: profile }],
        profileCommandRevision: profile.commandRevision || 0,
        serverTime: new Date().toISOString(),
        responseVersion: 1,
      });
    }
  );

  // Endpoint to clear the profile cache (used when presets are applied)
  app.post("/atlas/clear-profile-cache", async (c) => {
    profileCache.clear();
    return c.json({ success: true, message: "Profile cache cleared" });
  });
}
