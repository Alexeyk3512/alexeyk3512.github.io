# send2ereader (this fork)

A tiny web service for getting an ebook from your phone/laptop onto a **Kobo or Kindle**
over wifi, without cables, accounts or email. It is a copy of
[daniel-j/send2ereader](https://github.com/daniel-j/send2ereader).

It is **not** a static website. It is a Node.js HTTP server that accepts file
uploads, so it cannot run on GitHub Pages — see [Hosting](#hosting).

---

## How it works

Two pages, one server, a 4-character key:

1. On the **ereader**, open the server's root URL in the device's web browser.
   `index.js` sniffs the `User-Agent`; if it contains `Kobo` or `Kindle` it serves
   `download.html`, otherwise `upload.html`.
2. `download.html` immediately `POST`s to `/generate`. The server makes a random
   4-char key (alphabet `3469ACEGHLMNPRTY`), stores `{created, agent, file: null}`
   in an **in-memory `Map`**, and returns the key. The device displays it in huge
   type and then polls `GET /status/:key` **every 5 seconds**.
3. On your **phone or laptop**, open the same URL. You get `upload.html`: a form with
   the key, a file picker, and a "Kepubify" checkbox. It `POST`s to `/upload`.
4. The server validates the key, saves the upload to `uploads/`, re-checks the real
   file type with `file-type` (not just the browser's claimed MIME), optionally converts
   it, and attaches it to the key.
5. The device's next `/status/:key` poll returns the filename, and `download.html`
   reveals a link to `GET /download/:key`. Tap it and the book lands on the ereader.

### Conversion rules

| Upload | Device | Result |
| --- | --- | --- |
| EPUB | Kobo, checkbox ticked | `kepubify` → `.kepub.epub` (Kobo's native format) |
| EPUB | Kobo, checkbox unticked | sent as-is |
| EPUB | Kindle | `kindlegen` → `.mobi` |
| MOBI / PDF / CBZ / CBR / TXT / HTML | either | sent as-is |

### Expiry

Every `/status`, `/download` and `/upload` hit calls `expireKey()`, which resets a
**30-second** timer (`expireDelay`). So the key and the uploaded file survive only
while the ereader is awake, on wifi and polling. Close the browser, generate a new
key or drop wifi and the file is `unlink`ed about 30 seconds later. A key is also
hard-deleted after **1 hour** (`maxExpireDuration`) regardless.

### Routes

| Route | Purpose |
| --- | --- |
| `GET /` | `download.html` for Kobo/Kindle UA, else `upload.html` |
| `GET /receive` | force the ereader page |
| `GET /style.css` | the only static asset that is served |
| `POST /generate` | mint a key |
| `GET /status/:key` | poll for a waiting file (UA must match the key's) |
| `POST /upload` | multipart upload, field order `key` then `file` |
| `GET /download/:key` | download the file (UA must match the key's) |
| `DELETE /file/:key` | detach the file from the key |

Config lives in `index.js` as top-level constants, not environment variables:
`port = 3001`, `expireDelay = 30`, `maxExpireDuration = 3600`, `maxFileSize = 800 MB`.
Change the port by editing line 14 (or put a reverse proxy in front).

---

## Build and run it yourself

### Requirements

- **Node.js 20+** (verified here on v22). `file-type` 21 requires 20+. No build step,
  no bundler, no transpiler — it is plain CommonJS.
- **`kepubify`** on your `PATH` — only needed for the Kobo EPUB path, which is the
  default because the checkbox starts ticked.
- **`kindlegen`** on your `PATH` — only needed if you send EPUBs to a *Kindle*.
  Amazon discontinued it and no longer distributes it; see [Kindle](#kindle-and-kindlegen).

If you only have a Kobo, you only need Node and kepubify. If you untick the
checkbox, you only need Node.

### Steps

```bash
git clone https://github.com/alexeyk3512/alexeyk3512.github.io.git send2ereader
```

```bash
cd send2ereader && npm install
```

Install kepubify (Linux x86-64; see the [releases page](https://github.com/pgaskin/kepubify/releases)
for macOS/ARM builds):

```bash
sudo curl -L -o /usr/local/bin/kepubify https://github.com/pgaskin/kepubify/releases/download/v4.0.4/kepubify-linux-64bit && sudo chmod +x /usr/local/bin/kepubify
```

```bash
npm start
```

It listens on **http://localhost:3001**. Open it in a desktop browser and you should
see the upload form; the ereader page is at `/receive`.

### Testing without an ereader

The device side is just a `User-Agent` string, so you can drive the whole flow with curl:

```bash
KEY=$(curl -s -X POST http://localhost:3001/generate -A "Kobo Touch") && echo "$KEY"
```

```bash
curl -s -X POST http://localhost:3001/upload -F "key=$KEY" -F "file=@book.epub;type=application/epub+zip" -o /dev/null -w "%{http_code}\n"
```

```bash
curl -s "http://localhost:3001/status/$KEY" -A "Kobo Touch"
```

```bash
curl -s -o out.epub "http://localhost:3001/download/$KEY" -A "Kobo Touch"
```

Two things that will bite you when testing by hand:

- **`-F "file=@book.epub"` alone is rejected** as "Invalid file submitted". The upload
  filter checks the *client-declared* `Content-Type`, and curl defaults to
  `application/octet-stream`, which is not in `allowedTypes`. Append
  `;type=application/epub+zip`. Real browsers send the right type from the file
  extension, so this only affects curl.
- **The `User-Agent` must match** the one that generated the key. `/status` and
  `/download` return `404` otherwise. Pass the same `-A` string every time.

---

## Hosting

### GitHub Pages will not work

This repository is named `alexeyk3512.github.io`, which makes GitHub Pages serve it as
a static site. Pages only serves static files — no Node process, no `POST /upload`, no
writable disk. Pushing this code there gives you an unstyled `upload.html` whose form
posts into the void.

You need somewhere that can run a long-lived Node process with writable local disk.

### Option A: your own LAN (recommended)

This is the best fit for how the app actually works. Your ereader has to be on your
wifi to poll anyway, and files only exist for ~30 seconds, so there is no reason to put
it on the public internet. A Raspberry Pi, a NAS, or just your laptop works:

```bash
npm start
```

Then on the ereader browse to `http://<machine-lan-ip>:3001`. Give the host a static
DHCP lease so the address stops changing. No domain, no TLS, no firewall holes, and
nobody but your household can upload to it.

To keep it running on a Linux box, use systemd — `/etc/systemd/system/send2ereader.service`:

```ini
[Unit]
Description=send2ereader
After=network-online.target

[Service]
Type=simple
User=send2ereader
WorkingDirectory=/opt/send2ereader
ExecStart=/usr/bin/node index.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl enable --now send2ereader
```

`WorkingDirectory` matters: `uploads/`, `style.css` and the HTML files are all opened
by relative path, so the process must start in the repo directory.

### Option B: Docker

A `Dockerfile` and `docker-compose.yaml` are included. They install kepubify into the
image, so the only prerequisite is Docker itself:

```bash
docker compose up -d --build
```

```bash
docker compose logs -f
```

The compose file publishes port 3001 and sets `restart: unless-stopped`. Uploads stay
inside the container's ephemeral filesystem, which is correct here — the files are
meant to be short-lived.

### Option C: a VPS or container host

Any small VPS (Hetzner, DigitalOcean, Linode) or container platform (Fly.io, Render,
Railway, your own Dokku/Coolify) will run it. A 1 GB instance is plenty. Put a
reverse proxy in front for TLS — nginx:

```nginx
server {
    listen 443 ssl;
    server_name books.example.com;

    client_max_body_size 800M;
    proxy_read_timeout 300s;

    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header User-Agent $http_user_agent;
    }
}
```

Three things to get right:

- **`client_max_body_size`** must be at least as large as `maxFileSize` (800 MB) or
  nginx rejects big uploads with `413` before Node ever sees them.
- **Do not rewrite `User-Agent`.** The key↔device binding depends on it. Most proxies
  pass it through untouched; some CDNs and "optimisation" layers do not.
- **One instance only.** Keys live in a process-local `Map`, so you cannot run two
  replicas behind a load balancer and you cannot use a platform that scales to zero or
  cycles containers — the ereader would poll a process that has never heard of its key.
  A restart invalidates every outstanding key.

Serverless platforms (Vercel, Netlify Functions, Cloudflare Workers) are a poor fit for
the same reason, plus no persistent local disk.

#### Ereader browsers and HTTPS

Kobo and Kindle browsers are old and their CA stores are stale. A modern TLS config or a
recent Let's Encrypt chain can fail to load on older firmware, and a page served over
HTTPS cannot fetch an HTTP endpoint. Test on the actual device early. If TLS fights you,
plain HTTP on your LAN (Option A) sidesteps the whole problem.

### Kindle and kindlegen

Amazon retired KindleGen and no longer offers it for download, so the EPUB→MOBI path
has no official binary. Options, in order of sanity:

1. **Don't use it.** Upload MOBI/AZW3 files directly — they are passed through unconverted.
2. **Convert before uploading**, with [Calibre](https://calibre-ebook.com/) on your
   computer, then upload the result.
3. **Convert server-side with Calibre**, by installing Calibre on the host and editing
   the `kindlegen` branch in `index.js` to spawn `ebook-convert in.epub out.mobi`
   instead. The flags are not compatible, so this is a code change, not a rename.
4. Hunt down an archived kindlegen binary. Upstream's Dockerfile does this from a pinned
   third-party repository. It is unsigned, discontinued software from a mirror; decide
   for yourself.

---

## Notes on this fork

This copy predates current upstream. Differences worth knowing:

- No `Dockerfile`/`docker-compose.yaml` upstream now has (added here).
- No PDF margin cropping (upstream added a `pdfCropMargins` dependency); nothing in
  this `index.js` references it, so you do not need to install it.
- Dependencies were upgraded to clear every `npm audit` advisory: `koa` 2.16.4,
  `multer` 2 / `@koa/multer` 4, and `file-type` 21 (ESM-only, loaded with a dynamic
  `import()` so `index.js` stays CommonJS).
- `fs.rm('uploads', …)` originally lacked `force: true`, so **`npm start` crashed with
  `ENOENT: lstat 'uploads'` on a fresh clone**. Fixed here.

If you would rather track the maintained version, pull from upstream instead of building
on this snapshot.

### Known rough edges

- **A failing converter takes the whole server down.** If `kepubify` is missing from
  `PATH`, `spawn` raises an unhandled `error` event and the process exits with
  `Error: spawn kepubify ENOENT` mid-upload. `kepubify`'s non-zero exit rejects a promise
  that nothing catches, with the same result. Install the binary, and rely on
  `Restart=always`/`restart: unless-stopped` so a bad file does not leave the service dead.
- **Keys are generated with `Math.random()`**, not `crypto`, and the keyspace is
  16⁴ = 65,536. `/upload` checks only the key, not the `User-Agent`, so on a
  public instance a guessed key could push a file at someone's device. Another reason
  to prefer Option A.
- **Anyone who can reach it can upload 800 MB.** Do not expose it publicly without
  at least a firewall rule, basic auth on the proxy, or a VPN/Tailscale.
