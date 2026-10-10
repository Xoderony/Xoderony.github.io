using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

/// <summary>集中加载页面导航与共享字段定义，启动前报告可定位的配置错误。</summary>
sealed class PageCatalog
{
    public Dictionary<string, PageDefinition> Pages { get; }

    public PageCatalog(string root)
    {
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web) { UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow };
        Pages = JsonSerializer.Deserialize<Dictionary<string, PageDefinition>>(File.ReadAllText(Path.Combine(root, "pages.json")), options)
            ?? throw new InvalidDataException("pages.json: expected a page dictionary.");
        foreach (var (id, page) in Pages)
        {
            if (!Regex.IsMatch(id, "^[a-z0-9][a-z0-9-]{0,63}$")) throw new InvalidDataException($"pages.json: invalid page ID '{id}'.");
            if (page is null || string.IsNullOrWhiteSpace(page.Title)) throw new InvalidDataException($"pages.json: page '{id}' needs a title.");
            if (page.Path is null || !Regex.IsMatch(page.Path, "^/[a-zA-Z0-9_/-]+(?:\\.html)?$" ) || page.Path.Contains("//"))
                throw new InvalidDataException($"pages.json: page '{id}' needs a local directory or HTML path.");
            var file = Path.Combine(root, "site", page.Path.TrimStart('/').Replace('/', Path.DirectorySeparatorChar));
            if (page.Path.EndsWith('/')) file = Path.Combine(file, "index.html");
            if (!File.Exists(file)) throw new InvalidDataException($"pages.json: page '{id}' target '{page.Path}' does not exist.");
            if (page.Fields is null) throw new InvalidDataException($"pages.json: page '{id}' fields must be an object.");
            foreach (var (key, type) in page.Fields)
                if (string.IsNullOrWhiteSpace(key) || type is not ("text" or "boolean"))
                    throw new InvalidDataException($"pages.json: page '{id}', field '{key}' must use text or boolean.");
        }
    }

    public string RenderNavigation() => string.Concat(Pages.OrderBy(entry => entry.Value.Order).Select(entry =>
    {
        var page = entry.Value;
        return $"<li><a class=\"entry\" href=\"{WebUtility.HtmlEncode(page.Path)}\"><h2>{WebUtility.HtmlEncode(page.Title)}</h2><p>{WebUtility.HtmlEncode(page.Description)}</p><span class=\"open\">打开页面</span></a></li>";
    }));
}

sealed class PageDefinition
{
    public string Title { get; init; } = "";
    public string Path { get; init; } = "";
    public string Description { get; init; } = "";
    public int Order { get; init; }
    public Dictionary<string, string> Fields { get; init; } = [];
}
