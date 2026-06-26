import http from 'node:http'
import process from 'node:process'
import { mkdir } from 'node:fs/promises'
import { setTimeout as sleep } from 'node:timers/promises'
import { createRequire } from 'node:module'

const BRIDGE_VERSION = 'hayase-webtorrent-bridge-v3'
const MAX_EVENTS = 40
const TORRENT_FETCH_TIMEOUT_MS = 30_000
const METADATA_TIMEOUT_MS = 90_000

const args = process.argv.slice(2)
const arg = (name, fallback) => {
  const index = args.indexOf(name)
  return index >= 0 && args[index + 1] ? args[index + 1] : fallback
}

const port = Number(arg('--port', '43817'))
const downloadPath = arg('--download-path', '')
const tempPath = arg('--temp-path', downloadPath)

let settings = null
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

function torrentPeerCount (torrent) {
  if (!torrent) return 0
  if (typeof torrent.numPeers === 'number') return torrent.numPeers
  if (typeof torrent._peersLength === 'number') return torrent._peersLength
  if (torrent._peers && typeof torrent._peers === 'object') return Object.keys(torrent._peers).length
  return 0
}

function refreshTorrentStatus () {
  const webtorrent = getInnerClient()
  const torrent = activeTorrent ?? webtorrent?.torrents?.[0]
  if (!torrent) {
    status.ready = false
    status.metadata = false
    status.peers = 0
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
  status.peers = torrentPeerCount(torrent)
  status.wires = torrent.wires?.length ?? 0
  status.files = torrent.files?.length ?? 0
  status.downloaded = Number(torrent.downloaded ?? 0)
  status.uploaded = Number(torrent.uploaded ?? 0)
  status.total = Number(torrent.length ?? 0)
  status.downloadSpeed = Number(torrent.downloadSpeed ?? 0)
  status.uploadSpeed = Number(torrent.uploadSpeed ?? 0)
  status.progress = Number(torrent.progress ?? 0)
  status.updatedAt = Date.now()
  return status
}

function shortStatus () {
  refreshTorrentStatus()
  const parts = [status.phase]
  if (status.sourceKind) parts.push(`source=${status.sourceKind}`)
  if (status.infoHash) parts.push(`hash=${status.infoHash}`)
  parts.push(`peers=${status.peers}`)
  parts.push(`wires=${status.wires}`)
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
    client = new TorrentClient({ ...settings, path: downloadPath }, tempPath)
    status.dht = settings?.torrentDHT === false
    status.pex = settings?.torrentPeX === false
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

async function handleRPC (payload) {
  const params = payload.params ?? {}

  if (payload.method === 'updateSettings') {
    settings = params.settings ?? {}
    status.dht = settings?.torrentDHT === false
    status.pex = settings?.torrentPeX === false
    if (client) client.updateSettings({ ...settings, path: downloadPath })
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
          activeClient.playTorrent(torrentID, params.mediaID ?? 0, params.episode ?? 0),
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
    case 'torrentInfo':
      return await activeClient.torrentInfo(params.hash)
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
    default:
      throw new Error(`Unknown WebTorrent bridge method: ${payload.method}`)
  }
}

process.on('unhandledRejection', error => {
  record('error', error?.message ?? error)
})

process.on('uncaughtException', error => {
  record('error', error?.message ?? error)
})

await mkdir(downloadPath || tempPath, { recursive: true })
await mkdir(tempPath || downloadPath, { recursive: true })
setPhase('listening')

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
}).listen(port, '127.0.0.1')
