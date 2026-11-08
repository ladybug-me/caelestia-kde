pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import Caelestia
import Caelestia.Config
import qs.utils

Singleton {
    id: root

    readonly property string apiBase: "https://wallhaven.cc/api/v1"

    // The API's answers name a file on disk and are turned into a path, so they are
    // checked before use: an id is a plain name, and an extension has to be one of the
    // formats a wallpaper can be, never something the shell would load back as code.
    readonly property var wallpaperExts: ["jpg", "png", "webp", "gif", "bmp", "avif"]

    property string apiKey: GlobalConfig.services.wallhavenApiKey ?? ""

    property string lastQuery: ""
    property int currentPage: 1
    property int lastPage: 1
    property string lastSeed: ""
    property list<var> results
    property var currentWallpaper: null
    property string activeDownloadId: ""
    property real activeDownloadProgress: 0
    property bool activeDownloadRunning: false

    property var filters: {
        "categories": "111",
        "purity": "100",
        "sorting": "relevance",
        "order": "desc",
        "topRange": "1M",
        "atleast": "",
        "resolutions": "",
        "ratios": "",
        "colors": ""
    }

    signal searchComplete(var results, var meta)
    signal downloadProgress(string id, real progress)
    signal downloadComplete(string id, string path)
    signal downloadFailed(string id, string error)

    function resetDownloadState(id = "") {
        activeDownloadId = id;
        activeDownloadProgress = 0;
        activeDownloadRunning = id !== "";
    }

    function handleDownloadProgress(data) {
        if (!activeDownloadRunning || !activeDownloadId)
            return;

        const progressMatch = data.match(/^PROGRESS\s+([0-9]*\.?[0-9]+)$/);
        if (progressMatch) {
            const progress = Math.max(0, Math.min(1, parseFloat(progressMatch[1])));
            if (!isNaN(progress) && progress >= activeDownloadProgress) {
                activeDownloadProgress = progress;
                downloadProgress(activeDownloadId, progress);
            }
            return;
        }

        const match = data.match(/(\d{1,3}(?:\.\d+)?)%/);
        if (!match)
            return;

        const percent = Math.max(0, Math.min(100, parseFloat(match[1])));
        const progress = percent / 100;
        if (isNaN(progress) || progress < activeDownloadProgress)
            return;

        activeDownloadProgress = progress;
        downloadProgress(activeDownloadId, progress);
    }

    function buildUrl(path: string, params: var): string {
        let url = apiBase + path + "?";
        const paramList = [];

        for (const key in params) {
            if (params[key]) {
                paramList.push(`${key}=${encodeURIComponent(params[key])}`);
            }
        }

        if (apiKey) {
            paramList.push(`apikey=${apiKey}`);
        }

        return url + paramList.join("&");
    }

    function search(query: string, page: int): void {
        if (!query || query.trim() === "")
            return;

        if (!page || page < 1)
            page = 1;

        lastQuery = query;
        currentPage = page;

        const params = {
            "q": query,
            "categories": filters.categories,
            "purity": filters.purity,
            "sorting": filters.sorting,
            "order": filters.order,
            "page": page.toString()
        };

        if (filters.atleast)
            params.atleast = filters.atleast;
        if (filters.resolutions)
            params.resolutions = filters.resolutions;
        if (filters.ratios)
            params.ratios = filters.ratios;
        if (filters.colors)
            params.colors = filters.colors;

        const url = buildUrl("/search", params);
        Logger.log("Wallhaven search:", url.replace(/([?&])apikey=[^&]*/, "$1apikey=<redacted>"));

        runSearch(url);
    }

    function searchRandom(query: string): void {
        if (!query || query.trim() === "")
            return;

        lastQuery = query;
        currentPage = 1;

        const params = {
            "q": query,
            "categories": filters.categories,
            "purity": filters.purity,
            "sorting": "random",
            "page": "1"
        };

        const url = buildUrl("/search", params);
        Logger.log("Wallhaven random:", url.replace(/([?&])apikey=[^&]*/, "$1apikey=<redacted>"));

        runSearch(url);
    }

    function searchNextPage(): void {
        if (currentPage < lastPage && lastQuery) {
            if (filters.sorting === "random" && lastSeed) {
                currentPage++;
                const params = {
                    "q": lastQuery,
                    "categories": filters.categories,
                    "purity": filters.purity,
                    "sorting": "random",
                    "seed": lastSeed,
                    "page": currentPage.toString()
                };
                const url = buildUrl("/search", params);
                loadPage(url);
            } else {
                search(lastQuery, currentPage + 1);
            }
        }
    }

    function runSearch(url: string): void {
        Requests.get(url, text => {
            try {
                const json = JSON.parse(text);
                results = json.data || [];

                if (json.meta) {
                    lastPage = json.meta.last_page || 1;
                    lastSeed = json.meta.seed || "";
                }

                searchComplete(results, json.meta || {});
            } catch (e) {
                console.error("Wallhaven parse error:", e);
                searchComplete([], {});
            }
        }, () => searchComplete([], {}));
    }

    function loadPage(url: string): void {
        runSearch(url);
    }

    function setFilter(key: string, value: string): void {
        const newFilters = {
            "categories": filters.categories,
            "purity": filters.purity,
            "sorting": filters.sorting,
            "order": filters.order,
            "topRange": filters.topRange,
            "atleast": filters.atleast,
            "resolutions": filters.resolutions,
            "ratios": filters.ratios,
            "colors": filters.colors
        };
        newFilters[key] = value;
        filters = newFilters;
    }

    function setPurity(sfw: bool, sketchy: bool, nsfw: bool): void {
        if (!apiKey && (nsfw || sketchy)) {
            console.warn("Wallhaven: Sketchy/NSFW requires API key");
        }
        let p = (sfw ? "1" : "0") + (sketchy ? "1" : "0") + (nsfw && apiKey ? "1" : "0");
        setFilter("purity", p);
    }

    function setResolution(width: int, height: int): void {
        if (width > 0 && height > 0) {
            setFilter("atleast", `${width}x${height}`);
        } else {
            setFilter("atleast", "");
        }
    }

    function setSorting(sorting: string): void {
        setFilter("sorting", sorting);
    }

    function resetFilters(): void {
        filters = {
            "categories": "111",
            "purity": apiKey ? "110" : "100",
            "sorting": "relevance",
            "order": "desc",
            "topRange": "1M",
            "atleast": "",
            "resolutions": "",
            "ratios": "",
            "colors": ""
        };
    }

    function wallpaperExtension(path) {
        const match = /\.([A-Za-z0-9]{2,5})(?:\?|$)/.exec(path || "");
        if (!match)
            return "jpg";

        const ext = match[1].toLowerCase() === "jpeg" ? "jpg" : match[1].toLowerCase();
        return root.wallpaperExts.indexOf(ext) === -1 ? "jpg" : ext;
    }

    function isValidWallpaperId(id) {
        return typeof id === "string" && /^[A-Za-z0-9_-]+$/.test(id);
    }

    function downloadWallpaper(wallpaper: var): void {
        if (!wallpaper || !wallpaper.path) {
            console.error("Wallhaven: Invalid wallpaper data");
            return;
        }

        const id = String(wallpaper.id ?? "");
        if (!root.isValidWallpaperId(id)) {
            console.error("Wallhaven: refusing a wallpaper whose id is not a plain name:", id);
            return;
        }

        const fullPath = wallpaper.path || wallpaper.url || "";
        if (!/^https:\/\//i.test(fullPath)) {
            console.error("Wallhaven: refusing a wallpaper whose URL is not https:", fullPath);
            return;
        }

        const ext = root.wallpaperExtension(fullPath);
        const tmpPath = `${Paths.cache}/wallhaven-${id}.tmp`;
        const dstPath = `${Paths.wallsdir}/wallhaven-${id}.${ext}`;

        currentWallpaper = {
            id: id,
            ext: ext
        };
        if (activeDownloadRunning || downloadProc.running) {
            console.warn("Wallhaven: Download already in progress");
            return;
        }
        resetDownloadState(id);
        downloadProc.wallpaperId = id;
        downloadProc.tmpPath = tmpPath;
        downloadProc.dstPath = dstPath;

        Logger.log("Wallhaven: Downloading", wallpaper.path, "to", tmpPath);
        Logger.log("Wallhaven: Will move to", dstPath, "(ext:", ext, ")");

        // urllib follows redirects without asking, so a link that starts on wallhaven can
        // end anywhere this machine can reach. The script below holds every hop to the
        // rule the first url is already held to: https only, and only to an address that
        // is not this machine or its network. It is written one line per entry because a
        // program of this size stops being reviewable on a single line.
        downloadProc.command = [
            "python3",
            "-c",
            [
                'import ipaddress, math, os, socket, sys, urllib.parse, urllib.request',
                'url, tmp_path, dst_path = sys.argv[1:4]',
                'if urllib.parse.urlsplit(url).scheme != "https":',
                '    print("refusing a download that is not https: " + url, file=sys.stderr, flush=True)',
                '    sys.exit(1)',
                '',
                'def address_of(host):',
                '    try:',
                '        address = ipaddress.ip_address(host.split("%", 1)[0])',
                '    except ValueError:',
                '        return None',
                '    if address.version == 6 and address.ipv4_mapped is not None:',
                '        return address.ipv4_mapped',
                '    return address',
                '',
                'def is_public(address):',
                '    # is_global alone is not enough, since it is true for multicast too.',
                '    return address.is_global and not address.is_multicast',
                '',
                'def check_hop(hop):',
                '    parsed = urllib.parse.urlsplit(hop)',
                '    if parsed.scheme.lower() != "https":',
                '        raise ValueError("refusing a redirect that is not https: " + hop)',
                '    if not parsed.hostname:',
                '        raise ValueError("refusing a redirect that names no host: " + hop)',
                '    address = address_of(parsed.hostname)',
                '    if address is not None and not is_public(address):',
                '        raise ValueError("refusing a redirect to a loopback, private or metadata address: " + hop)',
                '',
                'class GuardedRedirects(urllib.request.HTTPRedirectHandler):',
                '    def redirect_request(self, req, fp, code, msg, headers, newurl):',
                '        check_hop(newurl)',
                '        return super().redirect_request(req, fp, code, msg, headers, newurl)',
                '',
                '# urllib resolves the name again when it connects, so filtering that answer is',
                '# what covers a name that is public but resolves to a private address.',
                'original_getaddrinfo = socket.getaddrinfo',
                'def guarded_getaddrinfo(host, port, *args, **kwargs):',
                '    allowed = []',
                '    for entry in original_getaddrinfo(host, port, *args, **kwargs):',
                '        address = address_of(entry[4][0])',
                '        if address is not None and is_public(address):',
                '            allowed.append(entry)',
                '    if not allowed:',
                '        raise socket.gaierror(str(host) + " does not resolve to a public address")',
                '    return allowed',
                '',
                'os.makedirs(os.path.dirname(dst_path), exist_ok=True)',
                'try:',
                '    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36"})',
                '    opener = urllib.request.build_opener(GuardedRedirects)',
                '    socket.getaddrinfo = guarded_getaddrinfo',
                '    try:',
                '        with opener.open(req) as response, open(tmp_path, "wb") as handle:',
                '            total = response.headers.get("Content-Length")',
                '            total = int(total) if total else 0',
                '            downloaded = 0',
                '            while True:',
                '                chunk = response.read(262144)',
                '                if not chunk:',
                '                    break',
                '                handle.write(chunk)',
                '                downloaded += len(chunk)',
                '                if total > 0:',
                '                    print(f"PROGRESS {downloaded / total:.6f}", flush=True)',
                '                else:',
                '                    pseudo = min(0.92, 1.0 - math.exp(-downloaded / 1200000.0))',
                '                    print(f"PROGRESS {pseudo:.6f}", flush=True)',
                '    finally:',
                '        socket.getaddrinfo = original_getaddrinfo',
                '    print("PROGRESS 1", flush=True)',
                '    os.replace(tmp_path, dst_path)',
                'except Exception as exc:',
                '    try:',
                '        if os.path.exists(tmp_path):',
                '            os.remove(tmp_path)',
                '    except OSError:',
                '        pass',
                '    print(str(exc), file=sys.stderr, flush=True)',
                '    sys.exit(1)'
            ].join("\n"),
            wallpaper.path,
            tmpPath,
            dstPath
        ];
        downloadProc.running = true;
    }
    IpcHandler {
        function doSearch(query: string): void {
            search(query);
        }

        function doRandom(query: string): void {
            searchRandom(query);
        }

        target: "wallhaven"
    }

    Process {
        id: downloadProc

        property string wallpaperId: ""
        property string tmpPath: ""
        property string dstPath: ""

        stdout: SplitParser {
            onRead: data => root.handleDownloadProgress(data)
        }

        stderr: StdioCollector {
            id: downloadErr
        }

        // qmllint disable signal-handler-parameters
        onExited: code => {
            if (code !== 0) {
                const errorText = downloadErr.text.trim();
                resetDownloadState();
                currentWallpaper = null;
                downloadFailed(wallpaperId, errorText ? errorText : ("Download failed: " + code));
                return;
            }
            if (currentWallpaper) {
                const dst = downloadProc.dstPath;
                activeDownloadProgress = 1;
                downloadProgress(wallpaperId, 1);
                Logger.log("Wallhaven: Download complete", dst);
                resetDownloadState();
                downloadComplete(wallpaperId, dst);
            }
            currentWallpaper = null;
        }
    }
}
