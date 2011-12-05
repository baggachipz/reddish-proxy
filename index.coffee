process.title = 'reddish-proxy'

optimist = require('optimist')
redis = require('redis')
url = require('url')

net = require 'net'
tls = require 'tls'

argv = optimist
  .usage("Usage: #{process.title} --url [url] --key [key]")
  .demand(['url', 'key'])
  .default('url', 'redis://127.0.0.1:6379')
  .alias('url', 'u')
  .describe('url', 'A formatted redis url')
  .describe('key', 'Your Reddish connection key')
  .alias('key', 'k')
  .argv

key = argv.key
key_regex = /^[a-f0-9]{40}$/i

unless key_regex.test(key)
  console.error 'Invalid connection key', key
  return

{ port: redis_port, hostname: redis_hostname } = url.parse(argv.url)
reddish_port = 8000
reddish_hostname = if process.env.NODE_ENV is 'production' then 'reddish.freeflow.io' else 'dev.freeflow.io'
handshaken = false

console.log 'Redis client connecting...', redis_port, redis_hostname
redis_client = net.createConnection redis_port, redis_hostname, ->
  console.log "Redis client connected to #{redis_hostname}:#{redis_port}"

console.log 'Reddish client connecting...', reddish_port, reddish_hostname
reddish_client = tls.connect reddish_port, reddish_hostname, {}, ->
  console.log "Handshaking with #{reddish_hostname}:#{reddish_port}...", key
  reddish_client.write(data = JSON.stringify(key: key))

redis_client.on 'data', (data) -> reddish_client.write(data) if handshaken

redis_client.on 'close', (err) ->
  console.error 'Redis client closed' if err
  console.error 'Closing Reddish client'
  reddish_client.end()

redis_client.on 'error', (err) ->
  console.error 'Redis client error', err?.message if err

reddish_client.on 'data', (data) ->
  unless handshaken
    try
      json = JSON.parse(data.toString())

      if err = json?.error
        console.error 'Handshake failed:', err
        return

      console.log 'Handshake succeeded'
      console.log "Proxying redis@#{redis_hostname}:#{redis_port} to reddish@#{reddish_hostname}:#{reddish_port}..."
      handshaken = true
    catch err then console.error 'Handshake failed:', err
    return

  redis_client.write(data)

reddish_client.on 'close', (err) ->
  console.error 'Reddish client closed' if err
  console.error 'Closing Redis client'
  redis_client.end()

reddish_client.on 'error', (err) ->
  console.error 'Reddish client error', err?.message if err
