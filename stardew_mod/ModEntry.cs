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
                        dead = crop.dead.Value
                    };
                }).ToArray();
            var onions = location.Name == "Forest"
                ? location.Objects.Pairs.Where(p => p.Value.QualifiedItemId == "(O)399")
                    .Select(p => new { x = (int)p.Key.X, y = (int)p.Key.Y }).ToArray()
                : null;
            var state = new {
                year = Game1.year, season = Game1.currentSeason, day = Game1.dayOfMonth,
                time = Game1.timeOfDay, raining = Game1.isRaining,
                gold = farmer.Money, energy = farmer.Stamina,
                location = location.NameOrUniqueName,
                tile_x = (int)(farmer.Position.X / 64), tile_y = (int)(farmer.Position.Y / 64),
                skills = new { farming = farmer.FarmingLevel, fishing = farmer.FishingLevel,
                    foraging = farmer.ForagingLevel, mining = farmer.MiningLevel, combat = farmer.CombatLevel },
                inventory = farmer.Items.Where(item => item != null).Select(item => new {
                    id = item.QualifiedItemId, count = item.Stack,
                    quality = item is StardewValley.Object obj ? obj.Quality : 0
                }).ToArray(),
                friendship = farmer.friendshipData.Pairs.OrderBy(p => p.Key).Select(p => new {
                    npc = p.Key, points = p.Value.Points, talked_today = p.Value.TalkedToToday,
                    gifts_today = p.Value.GiftsToday, gifts_this_week = p.Value.GiftsThisWeek
                }).ToArray(),
                crops,
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
