using System.Text.Json;
using System.Threading.Channels;
using Microsoft.Extensions.FileProviders;

var root = Path.GetFullPath(Environment.GetEnvironmentVariable("WEBSHARE_ROOT") ?? Path.Combine(AppContext.BaseDirectory, ".."));
var port = int.Parse(Environment.GetEnvironmentVariable("WEBSHARE_PORT") ?? "8080");
var builder = WebApplication.CreateBuilder(args);
builder.WebHost.UseUrls($"http://127.0.0.1:{port}");
builder.WebHost.ConfigureKestrel(options => options.Limits.MaxRequestBodySize = 8192);
var app = builder.Build();
var jsonOptions = new JsonSerializerOptions(JsonSerializerDefaults.Web);
var catalog = new PageCatalog(root);
var stores = new Dictionary<string, PageStore>();
foreach (var (id, page) in catalog.Pages)
{
    if (page.Fields.Count > 0) stores.Add(id, new PageStore(page.Fields, Path.Combine(root, "data", id + ".json")));
}

app.Use(async (context, next) =>
{
    context.Response.Headers.CacheControl = "no-store";
    context.Response.Headers.XContentTypeOptions = "nosniff";
    await next(context);
});

app.MapGet("/api/health", () => Results.Json(new { status = "ready", pages = catalog.Pages.Count, sharedPages = stores.Count }, jsonOptions));
app.MapGet("/api/pages", () => Results.Json(catalog.Pages.OrderBy(entry => entry.Value.Order).Select(entry => new
{
    id = entry.Key, entry.Value.Title, entry.Value.Path, entry.Value.Description, shared = entry.Value.Fields.Count > 0
}), jsonOptions));
async Task<IResult> Home()
{
    var template = await File.ReadAllTextAsync(Path.Combine(root, "site", "index.html"));
    return Results.Content(template.Replace("<!-- page-navigation -->", catalog.RenderNavigation()), "text/html; charset=utf-8");
}
app.MapGet("/", Home);
app.MapGet("/index.html", Home);

app.MapGet("/api/state/{page}", async (string page, HttpContext context) =>
{
    if (!stores.TryGetValue(page, out var store)) return Results.NotFound();
    return Results.Json(await store.ReadAsync(context.RequestAborted), jsonOptions);
});

app.MapPatch("/api/state/{page}", async (string page, HttpContext context) =>
{
    if (!stores.TryGetValue(page, out var store)) return Results.NotFound();
    // 只接受同域网页提交的 JSON；公网 TLS 可由同机 frpc 终止。
    var origin = context.Request.Headers.Origin.ToString();
    if (origin.Length > 0 && (!Uri.TryCreate(origin, UriKind.Absolute, out var originUri) || originUri.Authority != context.Request.Host.Value))
        return Results.StatusCode(403);
    if (!context.Request.HasJsonContentType()) return Results.StatusCode(415);
    Change? change;
    try { change = await context.Request.ReadFromJsonAsync<Change>(context.RequestAborted); }
    catch (JsonException) { return Results.BadRequest(); }
    if (change is null || !store.IsValid(change.Key, change.Value)) return Results.BadRequest();
    try { return Results.Json(await store.SetAsync(change.Key!, change.Value, context.RequestAborted), jsonOptions); }
    catch (IOException ex)
    {
        app.Logger.LogError(ex, "Failed to persist shared state for {Page}", page);
        return Results.Problem("State could not be saved.");
    }
    catch (UnauthorizedAccessException ex)
    {
        app.Logger.LogError(ex, "Access denied while persisting state for {Page}", page);
        return Results.Problem("State could not be saved.");
    }
});

app.MapGet("/api/events/{page}", async (string page, HttpContext context) =>
{
    if (!stores.TryGetValue(page, out var store)) { context.Response.StatusCode = 404; return; }
    context.Response.ContentType = "text/event-stream";
    context.Response.Headers["X-Accel-Buffering"] = "no";
    var channel = await store.SubscribeAsync(context.RequestAborted);
    try
    {
        while (!context.RequestAborted.IsCancellationRequested)
        {
            using var heartbeat = CancellationTokenSource.CreateLinkedTokenSource(context.RequestAborted);
            heartbeat.CancelAfter(TimeSpan.FromSeconds(10));
            try
            {
                var snapshot = await channel.Reader.ReadAsync(heartbeat.Token);
                await context.Response.WriteAsync("data: " + JsonSerializer.Serialize(snapshot, jsonOptions) + "\n\n", context.RequestAborted);
            }
            catch (OperationCanceledException) when (!context.RequestAborted.IsCancellationRequested)
            {
                await context.Response.WriteAsync(": heartbeat\n\n", context.RequestAborted);
            }
            await context.Response.Body.FlushAsync(context.RequestAborted);
        }
    }
    catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested) { }
    finally { await store.UnsubscribeAsync(channel); }
});

var publicRoot = Path.Combine(root, "site");
// 发布目录只允许普通文件，避免目录联接将站外文件暴露出去。
foreach (var entry in Directory.EnumerateFileSystemEntries(publicRoot, "*", new EnumerationOptions { RecurseSubdirectories = true, AttributesToSkip = 0 }))
    if ((File.GetAttributes(entry) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Links are not allowed in the public directory.");
var files = new PhysicalFileProvider(publicRoot);
app.Lifetime.ApplicationStopped.Register(files.Dispose);
if (args.Contains("--check"))
{
    Console.WriteLine($"Configuration OK: {catalog.Pages.Count} pages, {stores.Count} shared pages; saved state loaded successfully.");
    await app.DisposeAsync();
    files.Dispose();
    return;
}
Directory.CreateDirectory(Path.Combine(root, "data"));
app.UseDefaultFiles(new DefaultFilesOptions { FileProvider = files });
app.UseStaticFiles(new StaticFileOptions
{
    FileProvider = files,
    OnPrepareResponse = context => context.Context.Response.Headers.CacheControl = "no-cache"
});
await app.RunAsync();

sealed record Change(string? Key, JsonElement Value);
sealed record Snapshot(long Revision, Dictionary<string, JsonElement> Values);

/// <summary>串行保存每页状态；落盘成功后才发布快照。</summary>
sealed class PageStore
{
    private readonly Dictionary<string, string> _fields;
    private readonly string _path;
    private readonly SemaphoreSlim _gate = new(1);
    private readonly HashSet<Channel<Snapshot>> _subscribers = [];
    private Snapshot _state;

    public PageStore(Dictionary<string, string> fields, string path)
    {
        _fields = fields;
        _path = path;
        var values = new Dictionary<string, JsonElement>();
        foreach (var (key, type) in fields)
        {
            if (type is not ("text" or "boolean")) throw new InvalidDataException("Unsupported field type.");
            values.Add(key, type == "boolean" ? JsonSerializer.SerializeToElement(false) : JsonSerializer.SerializeToElement(""));
        }
        _state = new Snapshot(0, values);
        if (!File.Exists(path)) return;
        var saved = JsonSerializer.Deserialize<Snapshot>(File.ReadAllText(path)) ?? throw new InvalidDataException($"Invalid state file: {path}");
        foreach (var (key, value) in saved.Values)
        {
            if (!IsValid(key, value)) throw new InvalidDataException($"State file '{path}': field '{key}' does not match pages.json.");
            values[key] = value.Clone();
        }
        _state = new Snapshot(saved.Revision, values);
    }

    public bool IsValid(string? key, JsonElement value) => key is not null && _fields.TryGetValue(key, out var type) && (type == "boolean" ? value.ValueKind is JsonValueKind.True or JsonValueKind.False : value.ValueKind == JsonValueKind.String && value.GetString()!.Length <= 1024);

    public async Task<Snapshot> ReadAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try { return _state; }
        finally { _gate.Release(); }
    }

    public async Task<Snapshot> SetAsync(string key, JsonElement value, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            var values = new Dictionary<string, JsonElement>(_state.Values) { [key] = value.Clone() };
            var next = new Snapshot(checked(_state.Revision + 1), values);
            // 同目录临时文件完成写入后替换，写入失败不发布或污染内存状态。
            await File.WriteAllTextAsync(_path + ".tmp", JsonSerializer.Serialize(next), cancellationToken);
            File.Move(_path + ".tmp", _path, true);
            _state = next;
            foreach (var subscriber in _subscribers)
                if (!subscriber.Writer.TryWrite(next)) throw new InvalidOperationException("Active subscriber channel is closed.");
            return next;
        }
        finally { _gate.Release(); }
    }

    public async Task<Channel<Snapshot>> SubscribeAsync(CancellationToken cancellationToken)
    {
        var channel = Channel.CreateBounded<Snapshot>(new BoundedChannelOptions(1) { FullMode = BoundedChannelFullMode.DropOldest, SingleReader = true });
        await _gate.WaitAsync(cancellationToken);
        try
        {
            // 注册与首个快照在同一临界区，防止初次连接漏掉更新。
            _subscribers.Add(channel);
            if (!channel.Writer.TryWrite(_state)) throw new InvalidOperationException("Initial snapshot could not be queued.");
        }
        finally { _gate.Release(); }
        return channel;
    }

    public async Task UnsubscribeAsync(Channel<Snapshot> channel)
    {
        await _gate.WaitAsync();
        try { _subscribers.Remove(channel); channel.Writer.Complete(); }
        finally { _gate.Release(); }
    }
}
