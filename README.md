# Should I Slab This

Mobile-first Flutter web app for scanning Pokemon cards, generating card passports, and saving cards to Binder collections.

## Run Locally

For local development against the Hugging Face backend:

```sh
flutter run -d web-server \
  --web-hostname 0.0.0.0 \
  --web-port 8080 \
  --dart-define=SIST_API_BASE_URL=https://marvanier-sistapp.hf.space
```

To run against a local backend instead, start the backend first:

```sh
cd /Users/marionvanier/Desktop/sist-jetson-backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
./scripts/run-dev.sh
```

Then start Flutter without the Hugging Face URL:

```sh
flutter run -d web-server \
  --web-hostname 0.0.0.0 \
  --web-port 8080
```

If `SIST_API_BASE_URL` is not set, the app calls the current browser host on
port `8000`. That works for both `localhost:8080` and
`http://<your-mac-wifi-ip>:8080` as long as the backend is listening on
`0.0.0.0:8000`.

Open on this Mac:

```text
http://localhost:8080
```

Open on an iPhone connected to the same Wi-Fi:

```text
http://<your-mac-wifi-ip>:8080
```

On this run, the detected Wi-Fi URL was:

```text
http://192.168.0.141:8080
```

If the IP changes, run:

```sh
ipconfig getifaddr en0
```

## Current App

- Home screen is tuned for mobile browser height with search, scan, sample passport, and bottom navigation.
- Search uses the TCGTracking Open TCG API for Pokemon category data.
- Search accepts card names, set hints plus card names, card names plus numbers, or set/card/number combinations such as `SSP Pikachu 238`.
- Tapping Scan lets users take a photo or upload an image, then calls the SIST backend scan pipeline.
- The scan flow supports segmentation quality checks, manual boundary correction, backend rectification, card identification/manual confirmation, passport generation, Binder saving, and share-card rendering.
- Binder supports collections containing both lookup cards and scanned passports.

## Frontend Environment

Build-time values:

```text
SIST_API_BASE_URL=
SIST_API_TOKEN=
```

`SIST_API_TOKEN` is optional and only useful for local/private deployments. Do not treat a Flutter Web `--dart-define` token as a public-web secret.

## Hugging Face Backend

For a Hugging Face Docker Space, set backend secrets in the Space settings and build Flutter with the public Space URL:

```sh
flutter build web --pwa-strategy=none \
  --dart-define=SIST_API_BASE_URL=https://YOUR-USER-SISTAPP.hf.space
```

The current production backend is:

```text
https://marvanier-sistapp.hf.space
```

## GitHub Pages

The included workflow deploys the Flutter web build to GitHub Pages from the
`main` branch. It builds with:

```sh
flutter build web --pwa-strategy=none \
  --base-href /SISTAPP/ \
  --dart-define=SIST_API_BASE_URL=https://marvanier-sistapp.hf.space
```

For a project Pages site, the expected URL is:

```text
https://vaniermar.github.io/SISTAPP/
```
