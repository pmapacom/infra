// Cloudflare Worker — reverse proxy for the Telegram Bot API.
//
// Use when api.telegram.org is blocked from your server: deploy this Worker, then
// point the bot at it with  TELEGRAM_API_BASE=https://<name>.<subdomain>.workers.dev
// (Cloudflare's edge reaches Telegram, so no proxy container is needed).
//
// It forwards each request unchanged to api.telegram.org — path, method, body and
// headers preserved — so /bot<token>/getUpdates, /sendMessage, etc. work as-is.
// The bot token stays in the path, so only someone who already has your token
// could use this endpoint; the /bot guard keeps it from being a generic proxy.
export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith("/bot")) {
      return new Response("not found", { status: 404 });
    }
    url.hostname = "api.telegram.org";
    url.protocol = "https:";
    url.port = "";
    return fetch(new Request(url, request));
  },
};
