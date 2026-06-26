import http from 'node:http'
import process from 'node:process'
import { mkdir } from 'node:fs/promises'
import { setTimeout as sleep } from 'node:timers/promises'
import { createRequire } from 'node:module'

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

// esbuild's ESM output still uses a CommonJS require helper for Node builtins
// and some dependencies. NodeMobile runs this file as ESM, so provide a real
// require rooted at the bundled torrent-client before importing the bundle.
globalThis.require = createRequire(new URL('./torrent-client/index.js', import.meta.url))


const TORRENT_FETCH_TIMEOUT_MS = 30_000
const METADATA_TIMEOUT_MS = 90_000

function isHTTPURL (value) {
  return typeof value === 'string' && /^https?:\/\//i.test(value)
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
        // Some torrent indexes reject Node's default undici user agent.
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

async function resolveTorrentID (id) {
  // Prefer explicit .torrent bytes for http(s) links because it gives us
  // headers, redirects, and a clear timeout. Some iOS/Node Mobile builds can
  // still fail Node's fetch path for otherwise usable torrent URLs, so fall
  // back to WebTorrent's native URL handling instead of failing immediately.
  if (!isHTTPURL(id)) return id

  try {
    return await fetchTorrentFile(id)
  } catch (error) {
    console.error(`Torrent URL prefetch failed, falling back to WebTorrent URL handling: ${error?.message ?? error}`)
    return id
  }
}

function currentTorrentStatus () {
  if (!client) return 'client not initialized'
  const clientSymbol = Object.getOwnPropertySymbols(client).find(symbol => symbol.description === 'client')
  const webtorrent = clientSymbol ? client[clientSymbol] : null
  const torrent = webtorrent?.torrents?.[0]
  if (!torrent) return 'no active torrent'

  const peers = torrent._peersLength ?? torrent.numPeers ?? 0
  const wires = torrent.wires?.length ?? 0
  const ready = torrent.ready ? 'ready' : 'metadata pending'
  const hash = torrent.infoHash ? ` hash=${torrent.infoHash}` : ''
  return `${ready}, peers=${peers}, wires=${wires}${hash}`
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
    const module = await import('./torrent-client/index.js')
    const TorrentClient = module.default
    client = new TorrentClient({ ...settings, path: downloadPath }, tempPath)
    return client
  } catch (error) {
    loadError = new Error(`Hayase torrent-client bundle is missing or invalid: ${error.message}`)
    throw loadError
  }
}

async function handleRPC (payload) {
  const params = payload.params ?? {}

  if (payload.method === 'updateSettings') {
    settings = params.settings ?? {}
    if (client) client.updateSettings({ ...settings, path: downloadPath })
    return {}
  }

  const activeClient = await loadTorrentClient()

  switch (payload.method) {
    case 'playTorrent': {
      const torrentID = await resolveTorrentID(params.id)
      return await withTimeout(
        activeClient.playTorrent(torrentID, params.mediaID ?? 0, params.episode ?? 0),
        METADATA_TIMEOUT_MS,
        () => `Timed out while fetching torrent metadata (${currentTorrentStatus()})`
      )
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
    case 'deleteTorrents':
      return await activeClient.deleteTorrents(params.hashes ?? [])
    case 'rescanTorrents':
      return await activeClient.rescanTorrents(params.hashes ?? [])
    case 'cachedTorrents':
      return await activeClient.cached()
    default:
      throw new Error(`Unknown WebTorrent bridge method: ${payload.method}`)
  }
}

await mkdir(downloadPath || tempPath, { recursive: true })
await mkdir(tempPath || downloadPath, { recursive: true })

http.createServer(async (request, response) => {
  try {
    if (request.method === 'GET' && request.url === '/health') {
      response.writeHead(200, { 'content-type': 'application/json' })
      response.end(JSON.stringify({ ok: true }))
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
