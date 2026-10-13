<#
  YouTube live chat bridge for Nico Comments.

  Reads a YouTube live chat (no API key; same requests the popout chat page makes) and serves new
  messages to the overlay at http://localhost:<Port>/chat. Started automatically by nico-comments.lua.

  -Target  @handle, channel URL/ID, video URL or video ID. Channels follow whatever stream is live.
  -Test    Print chat to the console instead of serving it (for troubleshooting).
#>
param(
  [Parameter(Mandatory = $true)][string]$Target,
  [int]$Port = 39391,
  [switch]$Test
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Net.Http
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$LogFile = Join-Path $PSScriptRoot 'youtube-chat.log'
function Log([string]$msg) {
  $line = '{0:HH:mm:ss} {1}' -f (Get-Date), $msg
  if ($Test) { Write-Host $line -ForegroundColor DarkGray }
  try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch {}
}
try { Set-Content -LiteralPath $LogFile -Value "YouTube chat bridge started for '$Target'" -Encoding UTF8 } catch {}

# ------------------------------------------------------------------ HTTP client

$handler = New-Object System.Net.Http.HttpClientHandler
$handler.AutomaticDecompression = [System.Net.DecompressionMethods]'GZip, Deflate'
$handler.CookieContainer = New-Object System.Net.CookieContainer
# Skip the EU cookie-consent interstitial
$handler.CookieContainer.Add((New-Object System.Net.Cookie('SOCS', 'CAI', '/', '.youtube.com')))
$handler.CookieContainer.Add((New-Object System.Net.Cookie('CONSENT', 'YES+1', '/', '.youtube.com')))
$http = New-Object System.Net.Http.HttpClient($handler)
$http.Timeout = [TimeSpan]::FromSeconds(15)
$http.DefaultRequestHeaders.Add('User-Agent', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36')
$http.DefaultRequestHeaders.Add('Accept-Language', 'en-US,en;q=0.9')

function Get-Text([string]$url) { $http.GetStringAsync($url).GetAwaiter().GetResult() }

# ------------------------------------------------------------------ YouTube

function Resolve-VideoId([string]$t) {
  $t = $t.Trim()
  if ($t -match '^[\w-]{11}$') { return $t }
  if ($t -match '[?&]v=([\w-]{11})') { return $Matches[1] }
  if ($t -match 'youtu\.be/([\w-]{11})') { return $Matches[1] }
  if ($t -match 'youtube\.com/live/([\w-]{11})') { return $Matches[1] }

  # A channel: find the stream it's live on right now.
  if ($t -match 'youtube\.com/((?:@|channel/|c/|user/)[^/?#]+)') { $path = $Matches[1] }
  elseif ($t -match '^UC[\w-]{22}$') { $path = "channel/$t" }
  elseif ($t.StartsWith('@')) { $path = $t }
  else { $path = "@$t" }
  $html = Get-Text "https://www.youtube.com/$path/live"
  if ($html -match '<link rel="canonical" href="https://www\.youtube\.com/watch\?v=([\w-]{11})"') { return $Matches[1] }
  return $null
}

function Start-Chat([string]$videoId) {
  $html = Get-Text "https://www.youtube.com/live_chat?is_popout=1&v=$videoId"
  $state = @{ video = $videoId; key = $null; ver = '2.20240101.00.00'; cont = $null; delay = 2000 }
  if ($html -match '"INNERTUBE_API_KEY":"([^"]+)"') { $state.key = $Matches[1] }
  if ($html -match '"INNERTUBE_CLIENT_VERSION":"([^"]+)"') { $state.ver = $Matches[1] }

  # Prefer the "Live chat" (all messages) view over "Top chat".
  $m = [regex]::Match($html, '(?:window\["ytInitialData"\]|var ytInitialData)\s*=\s*(\{.+?\});\s*</script>', 'Singleline')
  if ($m.Success) {
    try {
      $data = $m.Groups[1].Value | ConvertFrom-Json
      $lcr = $data.contents.liveChatRenderer
      $items = $lcr.header.liveChatHeaderRenderer.viewSelector.sortFilterSubMenuRenderer.subMenuItems
      if ($items -and $items.Count -ge 2) { $state.cont = $items[1].continuation.reloadContinuationData.continuation }
      if (-not $state.cont -and $lcr.continuations) {
        $c = $lcr.continuations[0]
        foreach ($k in 'invalidationContinuationData', 'timedContinuationData', 'reloadContinuationData') {
          if ($c.$k) { $state.cont = $c.$k.continuation; break }
        }
      }
    } catch { Log "Couldn't parse chat page data: $($_.Exception.Message)" }
  }
  if (-not $state.cont -and $html -match '"continuation":"([^"]+)"') { $state.cont = $Matches[1] }
  if (-not $state.cont) { throw "No live chat found for video $videoId (chat off, or stream not live?)" }
  return $state
}

$script:seen = New-Object 'System.Collections.Generic.HashSet[string]'

# Fetch the next batch of chat messages. Returns @(@{user; text}, ...).
function Get-ChatBatch($state) {
  $body = @{ context = @{ client = @{ clientName = 'WEB'; clientVersion = $state.ver; hl = 'en' } }; continuation = $state.cont } |
    ConvertTo-Json -Depth 6 -Compress
  $url = 'https://www.youtube.com/youtubei/v1/live_chat/get_live_chat?prettyPrint=false'
  if ($state.key) { $url += "&key=$($state.key)" }
  $content = New-Object System.Net.Http.StringContent($body, [Text.Encoding]::UTF8, 'application/json')
  $resp = $http.PostAsync($url, $content).GetAwaiter().GetResult()
  $json = $resp.Content.ReadAsStringAsync().GetAwaiter().GetResult()
  if (-not $resp.IsSuccessStatusCode) { throw "YouTube returned HTTP $([int]$resp.StatusCode)" }

  $lcc = ($json | ConvertFrom-Json).continuationContents.liveChatContinuation
  if (-not $lcc -or -not $lcc.continuations) { $state.cont = $null; return @() }   # chat has ended

  $c = $lcc.continuations[0]
  $next = $null
  foreach ($k in 'invalidationContinuationData', 'timedContinuationData', 'reloadContinuationData') {
    if ($c.$k) { $next = $c.$k; break }
  }
  $state.cont = $next.continuation
  $state.delay = if ($next.timeoutMs) { [Math]::Max(1000, [Math]::Min(5000, [int]$next.timeoutMs)) } else { 2000 }

  $out = @()
  foreach ($a in @($lcc.actions)) {
    $item = $a.addChatItemAction.item
    if (-not $item) { continue }
    $r = $item.liveChatTextMessageRenderer
    if (-not $r) { $r = $item.liveChatPaidMessageRenderer }
    if (-not $r -or -not $r.message -or -not $script:seen.Add([string]$r.id)) { continue }
    $text = (@($r.message.runs) | ForEach-Object {
      if ($_.text) { $_.text }
      elseif ($_.emoji -and -not $_.emoji.isCustomEmoji) { $_.emoji.emojiId }   # standard emoji = the character itself
    }) -join ''
    if ($text.Trim()) { $out += @{ user = [string]$r.authorName.simpleText; text = $text } }
  }
  return $out
}

# ------------------------------------------------------------------ main loop

$messages = New-Object System.Collections.ArrayList
$script:lastId = 0
$script:status = 'starting'
$script:videoId = $null
$script:lastHit = [DateTime]::UtcNow
$script:quit = $false
$session = [guid]::NewGuid().ToString('N')   # lets the overlay notice when the bridge restarts

function Add-Messages($batch) {
  foreach ($m in $batch) {
    $script:lastId++
    [void]$messages.Add(@{ id = $script:lastId; user = $m.user; text = $m.text })
    if ($Test) { Write-Host ("{0}: {1}" -f $m.user, $m.text) }
  }
  while ($messages.Count -gt 300) { $messages.RemoveAt(0) }
}

function Send-Response($ctx) {
  $script:lastHit = [DateTime]::UtcNow
  $req = $ctx.Request; $res = $ctx.Response
  try {
    $res.Headers.Add('Access-Control-Allow-Origin', '*')
    $res.Headers.Add('Access-Control-Allow-Private-Network', 'true')
    if ($req.HttpMethod -eq 'OPTIONS') { $res.StatusCode = 204; return }
    if ($req.Url.AbsolutePath -eq '/quit') { $script:quit = $true; return }

    $after = -1
    [void][int]::TryParse([string]$req.QueryString['after'], [ref]$after)
    # First request (after=-1) gets no backlog, just the current position.
    $new = if ($after -lt 0) { @() } else { @($messages | Where-Object { $_.id -gt $after }) }
    $payload = @{ session = $session; last = $script:lastId; status = $script:status; video = $script:videoId; messages = $new } |
      ConvertTo-Json -Depth 4 -Compress
    $bytes = [Text.Encoding]::UTF8.GetBytes($payload)
    $res.ContentType = 'application/json; charset=utf-8'
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
  } finally {
    $res.Close()
  }
}

$listener = $null
if (-not $Test) {
  for ($i = 0; $i -lt 10; $i++) {
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$Port/")
    try { $listener.Start(); break } catch {
      # Port taken, most likely by an older bridge (e.g. the channel was changed): ask it to stop.
      try { [void](New-Object System.Net.WebClient).DownloadString("http://localhost:$Port/quit") } catch {}
      Start-Sleep -Milliseconds 700
    }
  }
  if (-not $listener.IsListening) { Log "Port $Port is in use by another program."; exit 1 }
  Log "Listening on http://localhost:$Port/"
  $pending = $listener.GetContextAsync()
}

$state = $null
$nextPoll = [DateTime]::UtcNow
$testUntil = [DateTime]::UtcNow.AddSeconds(45)

while (-not $script:quit) {
  if ($listener) {
    if ($pending.Wait(100)) {
      Send-Response $pending.Result
      $pending = $listener.GetContextAsync()
    }
    # The overlay polls every second (slower if Chromium throttles it); if it's been gone this long OBS has closed.
    if (([DateTime]::UtcNow - $script:lastHit).TotalSeconds -gt 180) { Log 'Overlay stopped asking for chat; exiting.'; break }
  } else {
    Start-Sleep -Milliseconds 100
    if ([DateTime]::UtcNow -gt $testUntil) { break }
  }

  if ([DateTime]::UtcNow -lt $nextPoll) { continue }
  try {
    if (-not $state) {
      $script:videoId = Resolve-VideoId $Target
      if (-not $script:videoId) {
        if ($script:status -ne 'not live') { Log "'$Target' isn't live right now; checking again every 30s." }
        $script:status = 'not live'
        $nextPoll = [DateTime]::UtcNow.AddSeconds(30)
        continue
      }
      $state = Start-Chat $script:videoId
      [void](Get-ChatBatch $state)   # first batch is recent history; don't replay it on screen
      $script:status = 'connected'
      $script:lastErr = $null
      Log "Connected to live chat of video $($script:videoId)"
    }
    Add-Messages (Get-ChatBatch $state)
    if (-not $state.cont) {
      Log 'Chat ended; looking for the next stream.'
      $state = $null; $script:status = 'ended'
      $nextPoll = [DateTime]::UtcNow.AddSeconds(15)
    } else {
      $nextPoll = [DateTime]::UtcNow.AddMilliseconds($state.delay)
    }
  } catch {
    $err = $_.Exception.Message
    if ($err -ne $script:lastErr) { Log "Error: $err (retrying every 10s)" }
    $script:lastErr = $err
    $state = $null; $script:status = 'error'
    $nextPoll = [DateTime]::UtcNow.AddSeconds(10)
  }
}

if ($listener) { $listener.Stop() }
Log 'Stopped.'
