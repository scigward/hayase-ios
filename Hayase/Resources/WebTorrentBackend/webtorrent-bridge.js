import http from 'node:http'
import { timingSafeEqual } from 'node:crypto'
import process from 'node:process'
import { access, constants, mkdir } from 'node:fs/promises'
import { writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { setTimeout as sleep } from 'node:timers/promises'
import { createRequire } from 'node:module'

const BRIDGE_VERSION = 'hayase-webtorrent-bridge-v11'
const MAX_EVENTS = 200
const TORRENT_FETCH_TIMEOUT_MS = 30_000
const METADATA_TIMEOUT_MS = 90_000
const MAX_BODY_BYTES = 32 * 1024 * 1024
const MAX_TORRENT_FILE_BYTES = 20 * 1024 * 1024

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
// Per-launch secret from the app; every request must present it.
const expectedAuthorization = Buffer.from(`Bearer ${arg('--token', '')}`)
const startupErrorPath = arg('--startup-error-path', '')
let downloadPath = arg('--download-path', '')
let tempPath = arg('--temp-path', downloadPath)

const DEFAULT_SETTINGS = Object.freeze({
  torrentPersist: false,
  torrentDHT: false,
  torrentStreamedDownload: true,
  torrentSpeed: 40,
  maxConns: 80,
  torrentPort: 0,
  dhtPort: 0,
  torrentPeX: false,
  nzbDomain: '',
  nzbLogin: '',
  nzbPassword: '',
  nzbPort: 119,
  nzbPoolSize: 4,
  path: ''
})

let settings = { ...DEFAULT_SETTINGS }
let settingsRevision = 0
let client = null
let loadError = null
let clientObserversInstalled = false
let addPatched = false

// A foreground load that has not finished yet, by the request that started it. Cancelling one
// rolls the session back to what was playing before it.
const plays = new Set()
// Requests whose cancel arrived before the load itself did.
const cancelledPlays = new Set()
// What the session owns once a load succeeded, and the request that loaded it.
let settledHash = null
let settledPlayID = null
// Chromecast/DLNA sessions by host: the play RPC returns at once, the session runs on.
const casts = new Map()

const events = []
let eventSequence = 0
const isolatedNZBManagers = new WeakSet()
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
    torrentSpeed: Number.isFinite(Number(merged.torrentSpeed))
      ? Math.min(Math.max(Number(merged.torrentSpeed), 1), 999) : DEFAULT_SETTINGS.torrentSpeed,
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
    id: ++eventSequence,
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

// NZB is an optional webseed, never a prerequisite for peer streaming.
// torrent-client's initTorrent awaits register(), which itself awaits pool.ready.
// Keep registration running, but do not let an unavailable NNTP pool reject or
// delay playTorrent. Scope this to the manager, not arbitrary torrent failures.
function nzbManager () {
  const key = Object.getOwnPropertySymbols(client ?? {}).find(symbol => symbol.description === 'nzb')
  return key ? client[key] : null
}

function isolateOptionalNZB () {
  const manager = nzbManager()
  if (!manager || isolatedNZBManagers.has(manager)) return
  isolatedNZBManagers.add(manager)
  const reported = new Set()
  const report = error => {
    const message = error?.message ?? String(error)
    if (reported.has(message)) return
    reported.add(message)
    record('error', message, { userFacing: true, title: 'Failed to add NZB' })
  }
  // Attach immediately: the pool may reject before any torrent is opened.
  Promise.resolve(manager.pool?.ready).catch(report)
  const register = manager.register.bind(manager)
  manager.register = torrent => {
    Promise.resolve().then(() => register(torrent)).catch(report)
    return Promise.resolve()
  }
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
  if (!hash) return null
  const normalized = String(hash).toLowerCase()
  return getInnerClient()?.torrents?.find(torrent => String(torrent.infoHash ?? '').toLowerCase() === normalized) ?? null
}

// The foreground torrent is the one this process's session owns, as `server.active` is in
// interface, and not whichever torrent was added first or last.
function foregroundHash () {
  return client?.sessions?.get(sessionID) ?? null
}

// torrent-client's getStats, with its numbers made whole: the native side decodes them as
// unsigned integers and rejects a fractional rate (speedometer rates are fractional).
function normalizedStats (stats) {
  const remaining = Number(stats.time?.remaining)
  return {
    ...stats,
    name: String(stats.name ?? stats.hash ?? ''),
    progress: Number.isFinite(stats.progress) ? stats.progress : 0,
    speed: { down: numericValue(stats.speed?.down), up: numericValue(stats.speed?.up) },
    size: {
      downloaded: numericValue(stats.size?.downloaded),
      uploaded: numericValue(stats.size?.uploaded),
      total: numericValue(stats.size?.total)
    },
    time: { remaining: Number.isFinite(remaining) ? remaining : 0, elapsed: numericValue(stats.time?.elapsed) },
    peers: {
      seeders: numericValue(stats.peers?.seeders),
      leechers: numericValue(stats.peers?.leechers),
      wires: numericValue(stats.peers?.wires)
    },
    pieces: { total: numericValue(stats.pieces?.total), size: numericValue(stats.pieces?.size) }
  }
}

function refreshTorrentStatus () {
  const torrent = torrentByHash(foregroundHash())
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

  const connected = torrentWires(torrent).length
  const total = numericValue(torrent.length)
  const downloaded = numericValue(torrent.downloaded)
  status.infoHash = torrent.infoHash ?? status.infoHash
  status.ready = Boolean(torrent.ready)
  status.metadata = Boolean(torrent.metadata || torrent.ready || torrent.files?.length)
  status.peers = connected
  status.discoveredPeers = discoveredPeerCount(torrent)
  status.wires = connected
  status.files = torrent.files?.length ?? 0
  status.downloaded = downloaded
  status.uploaded = numericValue(torrent.uploaded)
  status.total = total
  status.downloadSpeed = numericValue(torrent.downloadSpeed)
  status.uploadSpeed = numericValue(torrent.uploadSpeed)
  status.progress = total > 0 ? Math.max(0, Math.min(downloaded / total, 1)) : (Number(torrent.progress) || 0)
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

// `after` is the id of the last event the caller has seen, so nothing it has not is dropped
// between two polls; without it, only the latest few events come back.
function statusPayload (after) {
  refreshTorrentStatus()
  const pending = Number.isFinite(after) ? events.filter(event => event.id > after) : events.slice(-12)
  return { ...status, events: pending, cast: Object.fromEntries(casts) }
}

function observeTorrent (torrent) {
  if (!torrent || torrent.__hayaseObserved) return torrent
  torrent.__hayaseObserved = true
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
  webtorrent.on?.('error', error => record('error', error?.message ?? error, { userFacing: true }))

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

async function readLimited (stream, limit) {
  const chunks = []
  let size = 0
  for await (const chunk of stream ?? []) {
    size += chunk.byteLength
    if (size > limit) throw new Error('Torrent file is too large')
    chunks.push(chunk)
  }
  return new Uint8Array(Buffer.concat(chunks))
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
    const data = await readLimited(response.body, MAX_TORRENT_FILE_BYTES)
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

function isAuthorized (request) {
  const given = Buffer.from(request.headers.authorization ?? '')
  return expectedAuthorization.length > 'Bearer '.length &&
    given.length === expectedAuthorization.length &&
    timingSafeEqual(given, expectedAuthorization)
}

async function readBody (request) {
  const chunks = []
  let size = 0
  for await (const chunk of request) {
    size += chunk.length
    if (size > MAX_BODY_BYTES) throw new Error('Request body too large')
    chunks.push(chunk)
  }
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
    isolateOptionalNZB()
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

class PlayCancelled extends Error {
  constructor () {
    super('Torrent request was cancelled')
    this.name = 'PlayCancelled'
  }
}

// torrent-client claims the session for the new hash before it is ready and only evicts the
// previous torrent once it is, so a load that never finishes leaves its torrent behind.
async function releaseOrphan (activeClient, hash) {
  if (!hash || [...activeClient.sessions.values()].includes(hash)) return
  if (activeClient.torrentState.has(hash)) {
    await activeClient.evictOrphan(hash)
    return
  }
  // Still waiting for metadata: nothing is registered yet, so evictOrphan cannot see it.
  const pending = torrentByHash(hash)
  if (pending) {
    await new Promise(resolve => getInnerClient().remove(pending, { destroyStore: !activeClient.persist }, resolve))
  }
}

// Drops a load: the session goes back to what was playing before it, unless a newer load has
// taken it over, and the torrent it added goes away unless something else owns it.
async function abandonPlay (activeClient, play) {
  play.cancelled = true
  const superseded = [...plays].some(other => other !== play && !other.cancelled)
  if (!superseded && activeClient.sessions.get(sessionID) === play.hash) {
    if (settledHash) activeClient.sessions.set(sessionID, settledHash)
    else activeClient.sessions.delete(sessionID)
  }
  await releaseOrphan(activeClient, play.hash)
}

async function playTorrent (activeClient, params) {
  const requestID = typeof params.requestID === 'string' ? params.requestID : null
  if (requestID && cancelledPlays.delete(requestID)) throw new PlayCancelled()

  const torrentID = await resolveTorrentID(params.id)
  const play = { id: requestID, hash: null, cancelled: false, cancel: () => {} }
  const cancellation = new Promise((resolve, reject) => { play.cancel = () => reject(new PlayCancelled()) })
  cancellation.catch(() => {})
  // Only one thing plays in the foreground: a new load replaces any that is still pending.
  plays.add(play)
  for (const other of plays) {
    if (other === play) continue
    other.cancelled = true
    other.cancel()
  }

  setPhase('adding-torrent')
  try {
    play.hash = (await activeClient.toInfoHash(torrentID)) ?? null
    if (play.cancelled) throw new PlayCancelled()
    const files = await withTimeout(
      // 4th arg is torrent-client's sessionID (see note at top of file); 5th is `background`,
      // left false: this bridge only plays one thing at a time in the foreground.
      Promise.race([
        activeClient.playTorrent(torrentID, params.mediaID ?? 0, params.episode ?? 0, sessionID, false),
        cancellation
      ]),
      METADATA_TIMEOUT_MS,
      () => 'Timed out while fetching torrent metadata'
    )
    if (play.cancelled) throw new PlayCancelled()
    const previous = settledHash
    settledHash = play.hash
    settledPlayID = play.id
    // torrent-client only evicts what the session held when this load began, which is a pending
    // load's torrent if one was replaced on the way.
    if (previous && previous !== play.hash) await releaseOrphan(activeClient, previous)
    setPhase('ready')
    status.files = files.length
    refreshTorrentStatus()
    // Match interface/client.ts: storage warnings must never delay playback.
    Promise.resolve().then(() => activeClient.checkAvailableSpace()).then(space => {
      if (space >= 1e9 || !Number.isFinite(space)) return
      const units = [' B', ' kB', ' MB', ' GB', ' TB']
      const exponent = space < 1 ? 0 : Math.min(Math.floor(Math.log(space) / Math.log(1000)), units.length - 1)
      const available = Number((space / Math.pow(1000, exponent)).toFixed(1)) + units[exponent]
      record('error', `${available} available, 1GB is the recommended minimum. Consider freeing up some space otherwise issues may occur.`,
        { userFacing: true, title: 'Low disk space' })
    }).catch(error => record('warning', error?.message ?? error))
    return files
  } catch (error) {
    await abandonPlay(activeClient, play)
    if (error instanceof PlayCancelled) {
      setPhase(settledHash ? 'ready' : 'idle')
    } else {
      status.lastError = error?.message ?? String(error)
      setPhase('failed')
    }
    // Keep upstream wording intact; diagnostics remain in /status and /logs.
    throw error
  } finally {
    plays.delete(play)
  }
}

async function handleRPC (payload) {
  const params = payload.params ?? {}

  if (payload.method === 'updateSettings') {
    const revision = ++settingsRevision
    const updated = normalizedSettings(params.settings ?? {})
    const before = JSON.stringify(clientSettings())
    if (updated.path && updated.path !== downloadPath) {
      // Folder selection affects the next torrent; existing stores keep their path.
      await verifiedDirectory(updated.path)
      if (revision !== settingsRevision) return {}
      downloadPath = updated.path
    }
    globalThis.hayaseDebugNamespaces = typeof params.debug === 'string' ? params.debug : ''
    globalThis.hayaseSetDebug?.(globalThis.hayaseDebugNamespaces)
    settings = updated
    const currentSettings = clientSettings()
    status.dht = currentSettings.torrentDHT === false
    status.pex = currentSettings.torrentPeX === false
    // torrent-client rebuilds its Usenet pool and store on every call, dropping the pool's
    // connections, and every play sends the settings: leave it be when nothing changed.
    if (client && JSON.stringify(currentSettings) !== before) {
      const previous = nzbManager()
      client.updateSettings(currentSettings)
      isolateOptionalNZB()
      const next = nzbManager()
      // The new pool does not know the torrents that are already open.
      if (next && next !== previous) {
        for (const { torrent } of client.torrentState.values()) {
          if (!torrent.destroyed) next.register(torrent)
        }
      }
    }
    return {}
  }

  const activeClient = await loadTorrentClient()
  installClientObservers()

  switch (payload.method) {
    case 'playTorrent':
      return await playTorrent(activeClient, params)
    case 'cancelPlay': {
      const play = [...plays].find(candidate => candidate.id && candidate.id === params.requestID)
      if (play) {
        play.cancelled = true
        play.cancel()
      } else if (typeof params.requestID === 'string') {
        cancelledPlays.add(params.requestID)
        if (cancelledPlays.size > 32) cancelledPlays.delete(cancelledPlays.values().next().value)
      }
      return {}
    }
    case 'stopSession': {
      // A player that was replaced must not take the torrent of the one that replaced it down
      // with it, so only the load that owns the session may release it. No request releases
      // whatever the session holds.
      if (params.requestID && (params.requestID !== settledPlayID ||
          activeClient.sessions.get(sessionID) !== settledHash)) return {}
      await activeClient.stopSession(sessionID)
      settledHash = null
      settledPlayID = null
      refreshTorrentStatus()
      return {}
    }
    case 'library':
      return await activeClient.library()
    case 'torrentInfo':
      return normalizedStats(await activeClient.torrentInfo(params.hash || foregroundHash()))
    case 'peerInfo':
      // speedometer returns fractional bytes/sec. Swift's UInt64 decoding rejects
      // the WHOLE peer array if even one rate is fractional. Normalize at the
      // native transport boundary, just as normalizedStats does for Overview.
      return (await activeClient.peerInfo(params.hash)).map(peer => ({
        ...peer,
        seeder: Boolean(peer.seeder),
        speed: { down: numericValue(peer.speed.down), up: numericValue(peer.speed.up) },
        size: { downloaded: numericValue(peer.size.downloaded), uploaded: numericValue(peer.size.uploaded) }
      }))
    case 'fileInfo':
      return await activeClient.fileInfo(params.hash)
    case 'trackers':
      return await activeClient.trackers(params.hash)
    case 'protocolStatus':
      return await activeClient.protocolStatus(params.hash)
    case 'deleteTorrents':
      // torrent-client skips what the session owns, as it does for interface.
      await activeClient.deleteTorrents(params.hashes ?? [])
      refreshTorrentStatus()
      return {}
    case 'rescanTorrents':
      await activeClient.rescanTorrents(params.hashes ?? [])
      return {}
    // interface's native.createNZB / createHTTPWebSeed
    case 'createNZB':
      await activeClient.createNZBWebSeed(params.hash, params.url)
      return {}
    case 'createHTTPWebSeed':
      await activeClient.createHTTPWebSeed(params.hash, params.url, params.authorization, params.index, params.rateLimit)
      return {}
    case 'cachedTorrents':
      return await activeClient.cached()
    // interface's native.checkIncomingConnections, which the network step of the setup asks
    case 'checkIncomingConnections':
      if (typeof activeClient.checkIncomingConnections !== 'function') {
        throw new Error('This torrent-client cannot check incoming connections')
      }
      return Boolean(await activeClient.checkIncomingConnections(Number(params.port ?? 0)))
    case 'listDisplays':
      return listCurrentDisplays(activeClient)
    case 'playDisplay': {
      const { host, hash, id, media } = params
      if (!host || !media) throw new Error('playDisplay requires a host and media payload')
      // Not awaited: torrent-client's playDisplay() only resolves once the cast session itself
      // ends, which would hold this request open for the whole watch. The session's outcome is
      // reported in /status instead, and the client ends it with closeDisplay, as interface's
      // Stop button does through native.castClose.
      const session = { state: 'playing', error: null }
      casts.set(host, session)
      Promise.resolve(activeClient.playDisplay(host, hash ?? '', id ?? 0, media)).then(
        () => { session.state = 'ended' },
        error => {
          session.state = 'error'
          session.error = error?.stack ?? error?.message ?? String(error)
          record('warning', `Cast session for ${host} failed: ${session.error}`)
        })
      return {}
    }
    case 'closeDisplay': {
      if (!params.host) throw new Error('closeDisplay requires a host')
      await activeClient.closeDisplay(params.host)
      casts.delete(params.host)
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
  record('error', error?.message ?? error, { userFacing: true })
})

process.on('uncaughtException', error => {
  if (status.phase === 'booting') {
    reportStartupError(error)
    return
  }
  record('error', error?.message ?? error, { userFacing: true })
})

// A failed directory preflight used to be swallowed by the global exception
// handler. Node then drained its event loop and returned code 0, hiding the
// actual startup failure from the app. Use the writable temp directory when a
// configured location is unavailable, and keep the real error if that fails.
const fallbackPath = join(tmpdir(), 'HayaseWebTorrent')

// The directory has to exist and be readable and writable, as torrent-client's
// verifyDirectoryPermissions requires.
async function verifiedDirectory (path) {
  await mkdir(path, { recursive: true })
  try {
    await access(path, constants.R_OK | constants.W_OK)
  } catch {
    throw new Error(`Insufficient permissions to access directory: ${path}`)
  }
  return path
}

async function usableDirectory (candidate, fallback, label) {
  try {
    return await verifiedDirectory(candidate)
  } catch (error) {
    record('warning', `${label} unavailable (${error?.message ?? error}); using ${fallback}`,
      { userFacing: true, title: 'Storage location unavailable' })
    return await verifiedDirectory(fallback)
  }
}
downloadPath = await usableDirectory(downloadPath || fallbackPath, fallbackPath, 'Download directory')
tempPath = await usableDirectory(tempPath || downloadPath, downloadPath, 'Temporary directory')

http.createServer(async (request, response) => {
  try {
    if (!isAuthorized(request)) {
      response.writeHead(401, { 'content-type': 'application/json' })
      response.end(JSON.stringify({ ok: false, error: { message: 'Unauthorized' } }))
      return
    }

    const url = new URL(request.url ?? '/', 'http://127.0.0.1')

    if (request.method === 'GET' && url.pathname === '/health') {
      response.writeHead(200, { 'content-type': 'application/json' })
      response.end(JSON.stringify({ ok: true, version: BRIDGE_VERSION, phase: status.phase }))
      return
    }

    if (request.method === 'GET' && url.pathname === '/status') {
      const after = url.searchParams.has('after') ? Number(url.searchParams.get('after')) : undefined
      response.writeHead(200, { 'content-type': 'application/json' })
      response.end(JSON.stringify({ ok: true, result: statusPayload(after) }))
      return
    }

    if (request.method === 'GET' && url.pathname === '/logs') {
      response.writeHead(200, { 'content-type': 'application/json' })
      response.end(JSON.stringify({ ok: true, result: events }))
      return
    }

    if (request.method !== 'POST' || url.pathname !== '/rpc') {
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
