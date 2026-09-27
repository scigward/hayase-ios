import http from 'node:http'
import process from 'node:process'
import { mkdir } from 'node:fs/promises'
import { writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { setTimeout as sleep } from 'node:timers/promises'
import { createRequire } from 'node:module'

const BRIDGE_VERSION = 'hayase-webtorrent-bridge-v7'
const MAX_EVENTS = 40
const TORRENT_FETCH_TIMEOUT_MS = 30_000
const METADATA_TIMEOUT_MS = 90_000

// torrent-client's playTorrent() now requires a sessionID (added alongside
// a background-download/session-priority system: see sessions Map,
// torrentState Map, updateTorrentPriority(), evictOrphan() in index.ts).
// Each bridge process is always exactly one Hayase playback session, so one
// stable ID for the whole process lifetime is the correct mapping — this
// is NOT a per-request or per-torrent value. Without this, the previous
// bridge version silently passed `undefined` as the sessionID; that mostly
// happened to work for evicting the previous torrent when switching
// episodes (since torrent-client's `sessions` Map treats `undefined` as a
// valid, if unintended, key), but doesn't correctly participate in the new
// priority system that governs which torrent's pieces actually get
// selected for download — which is what streaming depends on.
//
// No crypto dependency here on purpose: this value only needs to be a
// stable, distinct key within this one process's lifetime, not
// cryptographically random or globally unique, so there's no reason to
// depend on node:crypto for it.
const sessionID = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`

const args = process.argv.slice(2)
const arg = (name, fallback) => {
  const index = args.indexOf(name)
  return index >= 0 && args[index + 1] && !args[index + 1].startsWith('--')
    ? args[index + 1] : fallback
}

const port = Number(arg('--port', '43817'))
const startupErrorPath = arg('--startup-error-path', '')
let downloadPath = arg('--download-path', '')
let tempPath = arg('--temp-path', downloadPath)

const DEFAULT_SETTINGS = Object.freeze({
  torrentPersist: false,
  torrentDHT: false,
  torrentStreamedDownload: true,
  torrentSpeed: 40,
  maxConns: 55,
  torrentPort: 0,
  dhtPort: 0,
  torrentPeX: false,
  nzbDomain: '',
  nzbLogin: '',
  nzbPassword: '',
  nzbPort: 0,
  nzbPoolSize: 0,
  path: ''
})

let settings = { ...DEFAULT_SETTINGS }
let client = null
let loadError = null
let clientObserversInstalled = false
let addPatched = false
let activeTorrent = null

const events = []
const status = {
  version: BRIDGE_VERSION,
  phase: 'booting',
  sourceKind: null,
  source: null,
  infoHash: null,
  ready: false,
  metadata: false,
  peers: 0,
  discoveredPeers: 0,
  wires: 0,
  files: 0,
  downloaded: 0,
  uploaded: 0,
  total: 0,
  downloadSpeed: 0,
  uploadSpeed: 0,
  progress: 0,
  dht: null,
  pex: null,
  webRTC: false,
  lastWarning: null,
  lastError: null,
  updatedAt: Date.now()
}

// esbuild's ESM output still uses a CommonJS require helper for Node builtins
// and some dependencies. NodeMobile runs this file as ESM, so provide a real
// require rooted at the bundled torrent-client before importing the bundle.
globalThis.require = createRequire(new URL('./torrent-client/index.js', import.meta.url))

function isHTTPURL (value) {
  return typeof value === 'string' && /^https?:\/\//i.test(value)
}

function isMagnet (value) {
  return typeof value === 'string' && /^magnet:/i.test(value)
}

function preview (value) {
  if (!value) return null
  const string = String(value)
  return string.length > 180 ? string.slice(0, 177) + '...' : string
}

function clampedInteger (value, fallback, min, max) {
  const number = Number(value)
  if (!Number.isFinite(number)) return fallback
  return Math.min(Math.max(Math.round(number), min), max)
}

function normalizedSettings (value = {}) {
  const merged = { ...DEFAULT_SETTINGS, ...(value ?? {}) }
  return {
    ...merged,
    torrentPersist: Boolean(merged.torrentPersist),
    torrentDHT: Boolean(merged.torrentDHT),
    torrentStreamedDownload: merged.torrentStreamedDownload !== false,
    torrentSpeed: clampedInteger(merged.torrentSpeed, DEFAULT_SETTINGS.torrentSpeed, 1, 999),
    maxConns: clampedInteger(merged.maxConns, DEFAULT_SETTINGS.maxConns, 1, 512),
    torrentPort: clampedInteger(merged.torrentPort, DEFAULT_SETTINGS.torrentPort, 0, 65535),
    dhtPort: clampedInteger(merged.dhtPort, DEFAULT_SETTINGS.dhtPort, 0, 65535),
    torrentPeX: Boolean(merged.torrentPeX),
    nzbDomain: String(merged.nzbDomain ?? ''),
    nzbLogin: String(merged.nzbLogin ?? ''),
    nzbPassword: String(merged.nzbPassword ?? ''),
    nzbPort: clampedInteger(merged.nzbPort, DEFAULT_SETTINGS.nzbPort, 0, 65535),
    nzbPoolSize: clampedInteger(merged.nzbPoolSize, DEFAULT_SETTINGS.nzbPoolSize, 0, 128),
    path: String(merged.path ?? '')
  }
}

function clientSettings () {
  return normalizedSettings({ ...settings, path: downloadPath })
}

function sourceDescription (id) {
  if (id && typeof id === 'object') {
    if (id.kind === 'torrentFileBase64') {
      return { kind: 'torrent-file', source: preview(id.source ?? 'base64 payload') }
    }
    return { kind: String(id.kind ?? 'object'), source: preview(id.source ?? '[object]') }
  }

  if (isMagnet(id)) return { kind: 'magnet', source: preview(id) }
  if (isHTTPURL(id)) return { kind: 'torrent-url', source: preview(id) }
  if (typeof id === 'string') return { kind: 'info-hash', source: preview(id) }
  return { kind: typeof id, source: preview(id) }
}

function setPhase (phase) {
  status.phase = phase
  status.updatedAt = Date.now()
}

function record (level, message, detail = {}) {
  const text = message instanceof Error ? message.message : String(message)
  const event = {
    time: Date.now(),
    level,
    message: text,
    ...detail
  }
  events.push(event)
  if (events.length > MAX_EVENTS) events.splice(0, events.length - MAX_EVENTS)

  if (level === 'error') status.lastError = text
  if (level === 'warning') status.lastWarning = text
  status.updatedAt = Date.now()

  const logger = level === 'error' ? console.error : level === 'warning' ? console.warn : console.log
  logger(`[WebTorrentBridge] ${text}`)
}

function getInnerClient () {
  if (!client) return null
  const clientSymbol = Object.getOwnPropertySymbols(client).find(symbol => symbol.description === 'client')
  return clientSymbol ? client[clientSymbol] : null
}

function torrentWires (torrent) {
  return Array.isArray(torrent?.wires) ? torrent.wires : []
}

function discoveredPeerCount (torrent) {
  if (!torrent) return 0
  if (typeof torrent._peersLength === 'number') return torrent._peersLength
  if (torrent._peers && typeof torrent._peers === 'object') return Object.keys(torrent._peers).length
  if (typeof torrent.numPeers === 'number') return torrent.numPeers
  return 0
}

function numericValue (value) {
  const resolved = typeof value === 'function' ? value() : value
  const number = Number(resolved ?? 0)
  return Number.isFinite(number) ? Math.max(0, Math.round(number)) : 0
}

function torrentByHash (hash) {
  const webtorrent = getInnerClient()
  if (!webtorrent) return null
  if (hash) {
    const normalized = String(hash).toLowerCase()
    const match = webtorrent.torrents?.find(torrent => String(torrent.infoHash ?? '').toLowerCase() === normalized)
    if (match) return match
  }
  return activeTorrent ?? webtorrent.torrents?.[0] ?? null
}

function statsFromTorrent (torrent) {
  if (!torrent) throw new Error('Torrent not found')

  const wires = torrentWires(torrent)
  const seeders = wires.filter(wire => Boolean(wire?.isSeeder)).length
  const leechers = Math.max(0, wires.length - seeders)
  const pieces = Array.isArray(torrent.pieces) ? torrent.pieces : []
  const total = numericValue(torrent.length)
  const downloaded = numericValue(torrent.downloaded)

  return {
    hash: String(torrent.infoHash ?? ''),
    name: String(torrent.name ?? torrent.infoHash ?? 'WebTorrent'),
    progress: total > 0 ? Math.max(0, Math.min(downloaded / total, 1)) : numericValue(torrent.progress),
    speed: {
      down: numericValue(torrent.downloadSpeed),
      up: numericValue(torrent.uploadSpeed)
    },
    size: {
      downloaded,
      uploaded: numericValue(torrent.uploaded),
      total
    },
    time: {
      remaining: Number.isFinite(Number(torrent.timeRemaining)) ? Number(torrent.timeRemaining) : 0,
      elapsed: Math.max(0, (Date.now() - (torrent.__hayaseStartedAt ?? Date.now())) / 1000)
    },
    peers: {
      seeders,
      leechers,
      wires: wires.length
    },
    pieces: {
      total: pieces.length,
      size: numericValue(torrent.pieceLength)
    }
  }
}

function refreshTorrentStatus () {
  const webtorrent = getInnerClient()
  const torrent = activeTorrent ?? webtorrent?.torrents?.[0]
  if (!torrent) {
    status.ready = false
    status.metadata = false
    status.peers = 0
    status.discoveredPeers = 0
    status.wires = 0
    status.files = 0
    status.downloaded = 0
    status.uploaded = 0
    status.total = 0
    status.downloadSpeed = 0
    status.uploadSpeed = 0
    status.progress = 0
    status.infoHash = null
    return status
  }

  activeTorrent = torrent
  status.infoHash = torrent.infoHash ?? status.infoHash
  status.ready = Boolean(torrent.ready)
  status.metadata = Boolean(torrent.metadata || torrent.ready || torrent.files?.length)
  const stats = statsFromTorrent(torrent)
  status.peers = stats.peers.wires
  status.discoveredPeers = discoveredPeerCount(torrent)
  status.wires = stats.peers.wires
  status.files = torrent.files?.length ?? 0
  status.downloaded = stats.size.downloaded
  status.uploaded = stats.size.uploaded
  status.total = stats.size.total
  status.downloadSpeed = stats.speed.down
  status.uploadSpeed = stats.speed.up
  status.progress = stats.progress
  status.updatedAt = Date.now()
  return status
}

function shortStatus () {
  refreshTorrentStatus()
  const parts = [status.phase]
  if (status.sourceKind) parts.push(`source=${status.sourceKind}`)
  if (status.infoHash) parts.push(`hash=${status.infoHash}`)
  parts.push(`connected=${status.wires}`)
  parts.push(`discovered=${status.discoveredPeers}`)
  if (status.lastWarning) parts.push(`lastWarning=${status.lastWarning}`)
  if (status.lastError) parts.push(`lastError=${status.lastError}`)
  return parts.join(', ')
}

function statusPayload () {
  refreshTorrentStatus()
  return { ...status, events: events.slice(-12) }
}

async function removeRunningTorrents (hashes) {
  const webtorrent = getInnerClient()
  if (!webtorrent || !Array.isArray(hashes) || hashes.length === 0) return

  const wanted = new Set(hashes)
  const torrents = webtorrent.torrents?.filter(torrent => wanted.has(torrent.infoHash)) ?? []
  for (const torrent of torrents) {
    await new Promise((resolve, reject) => {
      webtorrent.remove(torrent, { destroyStore: true }, error => {
        if (error) reject(error)
        else resolve()
      })
    })
    if (activeTorrent === torrent) activeTorrent = null
  }
}

function observeTorrent (torrent) {
  if (!torrent || torrent.__hayaseObserved) return torrent
  torrent.__hayaseObserved = true
  torrent.__hayaseStartedAt = Date.now()
  activeTorrent = torrent
  refreshTorrentStatus()

  const update = phase => {
    if (phase) setPhase(phase)
    refreshTorrentStatus()
  }

  torrent.on?.('metadata', () => update('metadata-received'))
  torrent.on?.('ready', () => update('ready'))
  torrent.on?.('done', () => update('done'))
  torrent.on?.('wire', () => update('peer-connected'))
  torrent.on?.('noPeers', announceType => {
    record('warning', `No peers from ${announceType ?? 'tracker/DHT'}`)
    update('metadata-pending')
  })
  torrent.on?.('warning', error => {
    record('warning', error?.message ?? error)
    refreshTorrentStatus()
  })
  torrent.on?.('error', error => {
    record('error', error?.message ?? error)
    refreshTorrentStatus()
  })

  return torrent
}

function installClientObservers () {
  const webtorrent = getInnerClient()
  if (!webtorrent || clientObserversInstalled) return
  clientObserversInstalled = true

  webtorrent.on?.('torrent', torrent => observeTorrent(torrent))
  webtorrent.on?.('warning', error => record('warning', error?.message ?? error))
  webtorrent.on?.('error', error => record('error', error?.message ?? error))

  if (!addPatched && typeof webtorrent.add === 'function') {
    const originalAdd = webtorrent.add.bind(webtorrent)
    webtorrent.add = (...addArgs) => {
      const torrent = originalAdd(...addArgs)
      setPhase('metadata-pending')
      return observeTorrent(torrent)
    }
    addPatched = true
  }
}

async function withTimeout (promise, timeoutMs, message) {
  const controller = new AbortController()
  const timeout = sleep(timeoutMs, undefined, { signal: controller.signal })
    .then(() => { throw new Error(message()) })
  try {
    return await Promise.race([promise, timeout])
  } finally {
    controller.abort()
  }
}

async function fetchTorrentFile (url) {
  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), TORRENT_FETCH_TIMEOUT_MS)
  try {
    const response = await fetch(url, {
      redirect: 'follow',
      signal: controller.signal,
      headers: {
        'user-agent': 'curl/7.81.0',
        'accept': 'application/x-bittorrent,*/*;q=0.8'
      }
    })
    if (!response.ok) {
      throw new Error(`Torrent file request failed with HTTP ${response.status}`)
    }
    const data = new Uint8Array(await response.arrayBuffer())
    if (!data.byteLength) throw new Error('Torrent file request returned an empty body')
    return data
  } finally {
    clearTimeout(timer)
  }
}

function torrentFileFromBase64 (value) {
  const buffer = Buffer.from(value, 'base64')
  if (!buffer.byteLength) throw new Error('Torrent file payload is empty')
  return new Uint8Array(buffer)
}

async function resolveTorrentID (id) {
  const source = sourceDescription(id)
  status.sourceKind = source.kind
  status.source = source.source
  status.lastError = null
  status.lastWarning = null
  setPhase('resolving-source')
  record('info', `Resolved WebTorrent source: ${source.kind}`, { source: source.source })

  if (id && typeof id === 'object') {
    if (id.kind === 'torrentFileBase64') {
      setPhase('using-torrent-file')
      return torrentFileFromBase64(id.data ?? '')
    }
    throw new Error(`Unsupported torrent source: ${id.kind ?? 'unknown'}`)
  }

  if (!isHTTPURL(id)) return id

  setPhase('fetching-torrent-file')
  try {
    return await fetchTorrentFile(id)
  } catch (error) {
    record('warning', `Torrent URL prefetch failed; handing URL to WebTorrent: ${error?.message ?? error}`)
    return id
  }
}

async function readBody (request) {
  const chunks = []
  for await (const chunk of request) chunks.push(chunk)
  return Buffer.concat(chunks).toString('utf8')
}

async function loadTorrentClient () {
  if (client) return client
  if (loadError) throw loadError

  try {
    setPhase('loading-client')
    const module = await import('./torrent-client/index.js')
    const TorrentClient = module.default
    const initialSettings = clientSettings()
    client = new TorrentClient(initialSettings, tempPath)
    status.dht = initialSettings.torrentDHT === false
    status.pex = initialSettings.torrentPeX === false
    status.webRTC = false
    installClientObservers()
    setPhase('idle')
    return client
  } catch (error) {
    loadError = new Error(`Hayase torrent-client bundle is missing or invalid: ${error.message}`)
    status.lastError = loadError.message
    setPhase('failed')
    throw loadError
  }
}

// Casting (Chromecast/DLNA) — mirrors interface's native.getDisplays /
// native.castPlay / native.castClose contract (see chromecast.ts + native.ts
// in the "interface" reference). torrent-client's TorrentClient already does
// real mDNS/SSDP discovery and Chromecast/DLNA playback internally
// (listenDisplay/playDisplay/closeDisplay); this bridge just exposes a
// request/response-shaped snapshot of that over RPC, since our transport is
// plain HTTP rather than a push channel.
function listCurrentDisplays (client) {
  return [
    ...Object.values(client.chromecasts?.casts ?? {}),
    ...Object.values(client.dlnas?.displays ?? {})
  ]
}

async function handleRPC (payload) {
  const params = payload.params ?? {}

  if (payload.method === 'updateSettings') {
    settings = normalizedSettings(params.settings ?? {})
    const currentSettings = clientSettings()
    status.dht = currentSettings.torrentDHT === false
    status.pex = currentSettings.torrentPeX === false
    if (client) client.updateSettings(currentSettings)
    return {}
  }

  const activeClient = await loadTorrentClient()
  installClientObservers()

  switch (payload.method) {
    case 'playTorrent': {
      const torrentID = await resolveTorrentID(params.id)
      setPhase('adding-torrent')
      try {
        const files = await withTimeout(
          // 4th arg is torrent-client's new required sessionID (see note at
          // top of file); 5th is `background`, left false — this bridge only
          // ever plays one thing at a time in the foreground, there's no
          // Hayase-side concept of a background download to route through
          // here yet.
          activeClient.playTorrent(torrentID, params.mediaID ?? 0, params.episode ?? 0, sessionID, false),
          METADATA_TIMEOUT_MS,
          () => `Timed out while fetching torrent metadata (${shortStatus()})`
        )
        setPhase('ready')
        status.files = files.length
        refreshTorrentStatus()
        return files
      } catch (error) {
        status.lastError = error?.message ?? String(error)
        setPhase('failed')
        throw new Error(`${status.lastError} (${shortStatus()})`)
      }
    }
    case 'library':
      return await activeClient.library()
    case 'torrentInfo': {
      return statsFromTorrent(torrentByHash(params.hash))
    }
    case 'peerInfo':
      return await activeClient.peerInfo(params.hash)
    case 'fileInfo':
      return await activeClient.fileInfo(params.hash)
    case 'trackers':
      return await activeClient.trackers(params.hash)
    case 'protocolStatus':
      return await activeClient.protocolStatus(params.hash)
    case 'deleteTorrents': {
      const hashes = params.hashes ?? []
      await removeRunningTorrents(hashes)
      await activeClient.deleteTorrents(hashes)
      activeTorrent = null
      refreshTorrentStatus()
      return {}
    }
    case 'rescanTorrents':
      await activeClient.rescanTorrents(params.hashes ?? [])
      return {}
    case 'cachedTorrents':
      return await activeClient.cached()
    case 'listDisplays':
      return listCurrentDisplays(activeClient)
    case 'playDisplay': {
      const { host, hash, id, media } = params
      if (!host || !media) throw new Error('playDisplay requires a host and media payload')
      // Deliberately not awaited: torrent-client's playDisplay() (chromecasts.play)
      // only resolves once the cast session itself ends, which on a plain
      // request/response HTTP transport would hold this call open for the
      // entire watch session. The bridge fires it and keeps running in the
      // background; the client is expected to call closeDisplay explicitly
      // to end the session, same as interface's Stop button does via
      // native.castClose (castplayer.svelte).
      activeClient.playDisplay(host, hash ?? '', id ?? 0, media)
        .catch(error => record('warning', `Cast session for ${host} ended: ${error?.message ?? error}`))
      return {}
    }
    case 'closeDisplay': {
      if (!params.host) throw new Error('closeDisplay requires a host')
      await activeClient.closeDisplay(params.host)
      return {}
    }
    default:
      throw new Error(`Unknown WebTorrent bridge method: ${payload.method}`)
  }
}

function reportStartupError (error) {
  const message = error?.stack ?? error?.message ?? String(error)
  if (startupErrorPath) {
    try { writeFileSync(startupErrorPath, message) } catch { /* device log remains available */ }
  }
  record('error', message)
  process.exitCode = 1
}

process.on('unhandledRejection', error => {
  if (status.phase === 'booting') {
    reportStartupError(error)
    return
  }
  record('error', error?.message ?? error)
})

process.on('uncaughtException', error => {
  if (status.phase === 'booting') {
    reportStartupError(error)
    return
  }
  record('error', error?.message ?? error)
})

// A failed directory preflight used to be swallowed by the global exception
// handler. Node then drained its event loop and returned code 0, hiding the
// actual startup failure from the app. Use the writable temp directory when a
// configured location is unavailable, and keep the real error if that fails.
const fallbackPath = join(tmpdir(), 'HayaseWebTorrent')
async function usableDirectory (candidate, fallback, label) {
  try {
    await mkdir(candidate, { recursive: true })
    return candidate
  } catch (error) {
    record('warning', `${label} unavailable (${error?.message ?? error}); using ${fallback}`)
    await mkdir(fallback, { recursive: true })
    return fallback
  }
}
downloadPath = await usableDirectory(downloadPath || fallbackPath, fallbackPath, 'Download directory')
tempPath = await usableDirectory(tempPath || downloadPath, downloadPath, 'Temporary directory')

http.createServer(async (request, response) => {
  try {
    if (request.method === 'GET' && request.url === '/health') {
      response.writeHead(200, { 'content-type': 'application/json' })
      response.end(JSON.stringify({ ok: true, version: BRIDGE_VERSION, phase: status.phase }))
      return
    }

    if (request.method === 'GET' && request.url === '/status') {
      response.writeHead(200, { 'content-type': 'application/json' })
      response.end(JSON.stringify({ ok: true, result: statusPayload() }))
      return
    }

    if (request.method === 'GET' && request.url === '/logs') {
      response.writeHead(200, { 'content-type': 'application/json' })
      response.end(JSON.stringify({ ok: true, result: events }))
      return
    }

    if (request.method !== 'POST' || request.url !== '/rpc') {
      response.writeHead(404, { 'content-type': 'application/json' })
      response.end(JSON.stringify({ ok: false, error: { message: 'Not found' } }))
      return
    }

    const body = await readBody(request)
    const payload = JSON.parse(body)
    const result = await handleRPC(payload)
    response.writeHead(200, { 'content-type': 'application/json' })
    response.end(JSON.stringify({ ok: true, result }))
  } catch (error) {
    response.writeHead(200, { 'content-type': 'application/json' })
    response.end(JSON.stringify({
      ok: false,
      error: { message: error?.message ?? String(error) }
    }))
  }
}).on('error', reportStartupError).listen(port, '127.0.0.1', () => setPhase('listening'))
