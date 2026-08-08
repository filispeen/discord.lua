local function parseUrl(url)
  local protocol, host, port, pathname = string.match(url, "^(wss?)://([^:/]+):?(%d*)(/?[^#]*)")
  if not protocol or not host or host == "" then
    return nil, "Invalid URL"
  end
  local tls
  if protocol == "ws" then
    port = tonumber(port) or 80
    tls = false
  elseif protocol == "wss" then
    port = tonumber(port) or 443
    tls = true
  else
    return nil, "Sorry, only ws:// or wss:// protocols supported"
  end
  if pathname == "" then
    pathname = "/"
  end
  return {
    host = host,
    port = port,
    tls = tls,
    pathname = pathname
  }
end

return {
  parseUrl = parseUrl
}