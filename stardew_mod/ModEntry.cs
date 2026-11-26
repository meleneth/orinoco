using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StardewModdingAPI;
using StardewValley;
using StardewValley.TerrainFeatures;

namespace Orinoco.Stardew;

public sealed class ModEntry : Mod
{
    private readonly HttpClient client = new(new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(5) };
    private readonly Queue<string> pending = new();
    private readonly object gate = new();
    private Config config = new();
    private bool sending;
    private string session = "", save = "", player = "";
    private long sequence;
    private string? lastState;
    private DateTime lastCapture;
    private const int QueueLimit = 32;
    private string observationDay = "";
    private bool onionPatchChecked;
    private int woodPeak;
    private readonly HashSet<string> introduced = new();

    public override void Entry(IModHelper helper)
    {
        config = helper.ReadConfig<Config>();
        if (!Uri.TryCreate(config.Endpoint, UriKind.Absolute, out var uri) ||
            !uri.IsLoopback || uri.Scheme != "http" || string.IsNullOrWhiteSpace(config.Token))
        {
            Monitor.Log("Configure a loopback Endpoint and Token in config.json; telemetry disabled.", LogLevel.Warn);
            return;
        }
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", config.Token);
        helper.Events.GameLoop.SaveLoaded += (_, _) => {
            if (!Context.IsMainPlayer) return;
            session = Guid.NewGuid().ToString("N");
            save = Hash(Game1.uniqueIDForThisGame.ToString());
            player = Hash(Game1.player.UniqueMultiplayerID.ToString());
            sequence = 0;
            lastState = null;
            observationDay = "";
            introduced.Clear();
            Capture("save_loaded", true);
        };
        helper.Events.GameLoop.DayStarted += (_, _) => Capture("day_started", true);
        helper.Events.GameLoop.DayEnding += (_, _) => Capture("day_ending", true);
        helper.Events.GameLoop.Saved += (_, _) => Capture("saved", true);
        helper.Events.GameLoop.ReturnedToTitle += (_, _) => {
            if (session.Length != 0) Enqueue("returned_to_title", null);
            session = "";
            lastState = null;
        };
        helper.Events.GameLoop.UpdateTicked += (_, e) => {
            if (!e.IsMultipleOf(120)) return;
            Capture("snapshot", false);
            StartSender();
        };
        helper.Events.Player.Warped += (_, e) => { if (e.IsLocalPlayer) Capture("warped", true); };
        helper.Events.Player.InventoryChanged += (_, e) => { if (e.IsLocalPlayer) Capture("inventory_changed", true); };
        helper.ConsoleCommands.Add("orinoco_snapshot", "Force a telemetry snapshot.", (_, _) => Capture("manual", true));
    }

    private static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();

    private void Capture(string reason, bool force)
    {
        if (!Context.IsWorldReady || !Context.IsMainPlayer || session.Length == 0) return;
        try
        {
            var farmer = Game1.player;
            var location = farmer.currentLocation;
            string dayKey = $"{Game1.year}:{Game1.currentSeason}:{Game1.dayOfMonth}";
            if (observationDay != dayKey) {
                observationDay = dayKey;
                onionPatchChecked = false;
                woodPeak = 0;
            }
            int tileX = (int)(farmer.Position.X / 64), tileY = (int)(farmer.Position.Y / 64);
            // Vanilla forest patch bounds; keep explicit and calibratable for map mods.
            if (location.Name == "Forest" && tileX >= 75 && tileX <= 110 && tileY >= 80 && tileY <= 110)
                onionPatchChecked = true;
            woodPeak = Math.Max(woodPeak, farmer.Items.Where(i => i != null && i.QualifiedItemId == "(O)388").Sum(i => i.Stack));
            foreach (var pair in farmer.friendshipData.Pairs)
                if (pair.Value.TalkedToToday || pair.Value.Points > 0) introduced.Add(pair.Key);
            var farmObjects = Game1.getFarm().Objects.Pairs.ToArray();
            var chests = new List<object>();
            var nearbyNpcs = new List<object>();
            foreach (var map in Game1.locations) {
                foreach (var npc in map.characters)
                    nearbyNpcs.Add(new { npc = npc.Name, location = map.NameOrUniqueName,
                        x = (int)(npc.Position.X / 64), y = (int)(npc.Position.Y / 64) });
                foreach (var pair in map.Objects.Pairs) {
                    if (pair.Value is not StardewValley.Objects.Chest chest || !chest.playerChest.Value) continue;
                    chests.Add(new { location = map.NameOrUniqueName, x = (int)pair.Key.X, y = (int)pair.Key.Y,
                        items = chest.Items.Where(i => i != null).Select(i => new {
                            id = i.QualifiedItemId, name = i.DisplayName, count = i.Stack,
                            quality = i is StardewValley.Object o ? o.Quality : 0
                        }).ToArray() });
                }
            }
            var crops = Game1.getFarm().terrainFeatures.Pairs
                .Where(p => p.Value is HoeDirt dirt && dirt.crop != null)
                .OrderBy(p => p.Key.X).ThenBy(p => p.Key.Y)
                .Select(p => {
                    var dirt = (HoeDirt)p.Value;
                    var crop = dirt.crop!;
                    return new {
                        x = (int)p.Key.X, y = (int)p.Key.Y,
                        harvest_id = crop.indexOfHarvest.Value,
                        phase = crop.currentPhase.Value,
                        phase_day = crop.dayOfCurrentPhase.Value,
                        watered = dirt.state.Value == 1,
                        ready = !crop.dead.Value && crop.currentPhase.Value >= crop.phaseDays.Count - 1 && (!crop.fullyGrown.Value || crop.dayOfCurrentPhase.Value <= 0),
                        dead = crop.dead.Value
                    };
                }).ToArray();
            var forest = Game1.getLocationFromName("Forest");
            var onions = forest != null
                ? forest.Objects.Pairs.Where(p => p.Value.QualifiedItemId == "(O)399")
                    .Select(p => new { x = (int)p.Key.X, y = (int)p.Key.Y }).ToArray()
                : null;
            var extras = new Dictionary<string, object?>();
            // Optional probes are isolated: a version-specific field must not
            // prevent the basic observation from being transmitted.
            void Probe(string key, Func<object?> read) {
                try { extras[key] = read(); }
                catch (Exception ex) { extras[key] = null; Monitor.Log($"Probe {key}: {ex.Message}", LogLevel.Trace); }
            }
            Probe("bundle_definitions", () => Helper.GameContent.Load<Dictionary<string, string>>("Data/Bundles"));
            Probe("gift_taste_definitions", () => Helper.GameContent.Load<Dictionary<string, string>>("Data/NPCGiftTastes"));
            Probe("active_bundles", () => Game1.netWorldState.Value.BundleData.ToDictionary(p => p.Key.ToString(), p => p.Value));
            Probe("bundle_progress", () => {
                var cc = Game1.getLocationFromName("CommunityCenter") as StardewValley.Locations.CommunityCenter;
                return cc?.bundles.Pairs.ToDictionary(p => p.Key.ToString(), p => p.Value.ToArray());
            });
            Probe("beach_bridge", () => (Game1.getLocationFromName("Beach") as StardewValley.Locations.Beach)?.bridgeFixed.Value);
            Probe("pets", () => Game1.locations.SelectMany(m => m.characters)
                .OfType<StardewValley.Characters.Pet>().Select(p => new {
                    name = p.Name, friendship = p.friendshipTowardFarmer.Value
                }).ToArray());
            Probe("gift_tastes_inventory", () => new[] { "Linus", "Caroline" }.ToDictionary(name => name, name => {
                var npc = Game1.getCharacterFromName(name);
                return farmer.Items.Where(i => i is StardewValley.Object)
                    .Select(i => new { id = i.QualifiedItemId, taste = npc?.getGiftTasteForThisItem(i) }).ToArray();
            }));
            Probe("quest_details", () => farmer.questLog.Where(q => q != null).Select(q => new {
                id = q.id.Value.ToString(), title = q.GetType().Name, completed = q.completed.Value,
                description = q.questDescription
            }).ToArray());
            var state = new {
                year = Game1.year, season = Game1.currentSeason, day = Game1.dayOfMonth,
                time = Game1.timeOfDay, raining = Game1.isRaining,
                gold = farmer.Money, energy = farmer.Stamina,
                location = location.NameOrUniqueName,
                tile_x = (int)(farmer.Position.X / 64), tile_y = (int)(farmer.Position.Y / 64),
                skills = new { farming = farmer.FarmingLevel, fishing = farmer.FishingLevel,
                    foraging = farmer.ForagingLevel, mining = farmer.MiningLevel, combat = farmer.CombatLevel },
                inventory = farmer.Items.Where(item => item != null).Select(item => new {
                    id = item.QualifiedItemId, name = item.DisplayName, count = item.Stack,
                    quality = item is StardewValley.Object obj ? obj.Quality : 0
                }).ToArray(),
                friendship = farmer.friendshipData.Pairs.OrderBy(p => p.Key).Select(p => new {
                    npc = p.Key, points = p.Value.Points, introduced = introduced.Contains(p.Key), talked_today = p.Value.TalkedToToday,
                    gifts_today = p.Value.GiftsToday, gifts_this_week = p.Value.GiftsThisWeek
                }).ToArray(),
                house_chest = Game1.getFarm().Objects.Pairs.Any(p => p.Value is StardewValley.Objects.Chest)
                    || (Game1.getLocationFromName("FarmHouse")?.Objects.Pairs.Any(p => p.Value is StardewValley.Objects.Chest) ?? false),
                wood_peak_today = woodPeak,
                spring_onion_patch_checked = onionPatchChecked,
                chests,
                npcs = nearbyNpcs,
                scarecrows = farmObjects.Where(p => p.Value.QualifiedItemId == "(BC)8" || p.Value.QualifiedItemId == "(BC)167").Select(p => new { x = (int)p.Key.X, y = (int)p.Key.Y, id = p.Value.QualifiedItemId }).ToArray(),
                recipes = farmer.craftingRecipes.Pairs.ToDictionary(p => p.Key, p => p.Value),
                mail_received = farmer.mailReceived.ToArray(),
                events_seen = farmer.eventsSeen.ToArray(),
                mine_floor = farmer.deepestMineLevel,
                daily_luck = farmer.DailyLuck,
                inventory_capacity = farmer.MaxItems,
                skill_xp = farmer.experiencePoints.ToArray(),
                tools = farmer.Items.OfType<Tool>().Select(t => new {
                    id = t.QualifiedItemId, name = t.DisplayName, upgrade_level = t.UpgradeLevel
                }).ToArray(),
                professions = farmer.professions.ToArray(),
                quests = farmer.questLog.Where(q => q != null).Select(q => new {
                    id = q.id.Value.ToString(), completed = q.completed.Value
                }).ToArray(),
                cooking_recipes = farmer.cookingRecipes.Pairs.ToDictionary(p => p.Key, p => p.Value),
                crops,
                extras,
                spring_onions = onions
            };
            string serialized = JsonSerializer.Serialize(state);
            bool heartbeat = DateTime.UtcNow - lastCapture >= TimeSpan.FromSeconds(30);
            if (!force && !heartbeat && serialized == lastState) return;
            Enqueue(reason, state);
            lastState = serialized;
            lastCapture = DateTime.UtcNow;
        }
        catch (Exception ex)
        {
            Monitor.Log($"Snapshot failed: {ex.GetType().Name}: {ex.Message}", LogLevel.Warn);
        }
    }

    private void Enqueue(string reason, object? state)
    {
        string json = JsonSerializer.Serialize(new {
            schema_version = 1, event_id = Guid.NewGuid().ToString("N"),
            session_id = session, save_id = save, player_id = player,
            sequence = ++sequence, occurred_at = DateTime.UtcNow.ToString("O"),
            reason, state
        });
        lock (gate)
        {
            if (pending.Count >= QueueLimit)
            {
                pending.Dequeue();
                Monitor.Log("Telemetry backlog full; oldest observation dropped.", LogLevel.Warn);
            }
            pending.Enqueue(json);
        }
        StartSender();
    }

    private void StartSender()
    {
        lock (gate)
        {
            if (sending || pending.Count == 0) return;
            sending = true;
        }
        _ = Task.Run(Drain);
    }

    private async Task Drain()
    {
        try
        {
            while (true)
            {
                string json;
                lock (gate)
                {
                    if (pending.Count == 0) return;
                    json = pending.Peek();
                }
                using var body = new StringContent(json, Encoding.UTF8, "application/json");
                using var response = await client.PostAsync(config.Endpoint, body);
                if (!response.IsSuccessStatusCode)
                {
                    Monitor.Log($"Orinoco HTTP {(int)response.StatusCode}; retrying.", LogLevel.Warn);
                    return;
                }
                lock (gate)
                {
                    if (pending.Count > 0 && pending.Peek() == json) pending.Dequeue();
                }
            }
        }
        catch (Exception ex)
        {
            Monitor.Log($"Orinoco unavailable: {ex.Message}", LogLevel.Debug);
        }
        finally { lock (gate) sending = false; }
    }

    public sealed class Config
    {
        public string Endpoint { get; set; } = "http://127.0.0.1:31050/stardew/telemetry";
        public string Token { get; set; } = "";
    }
}
