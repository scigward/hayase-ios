import http from 'node:http'
import process from 'node:process'
import { mkdir } from 'node:fs/promises'

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
    case 'playTorrent':
      return await activeClient.playTorrent(params.id, params.mediaID ?? 0, params.episode ?? 0)
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
