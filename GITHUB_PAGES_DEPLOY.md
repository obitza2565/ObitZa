# GitHub Pages deployment

This project serves the static frontend from `exchange/`.

## One-time setup

1. Create an empty GitHub repository.
2. From this project folder, run:

```powershell
git init
git add exchange deploy GITHUB_PAGES_DEPLOY.md
git commit -m "Prepare OBZ frontend and API deployment"
git branch -M main
git remote add origin https://github.com/<YOUR_USER>/<YOUR_REPO>.git
git push -u origin main
```

3. In GitHub, open `Settings > Pages`.
4. Select `GitHub Actions` as the source.
5. The workflow in `.github/workflows/pages.yml` deploys the `exchange/` directory.

## Configure the API before pushing the final frontend

Set the real backend URL after the Hetzner VPS is ready:

```powershell
powershell -ExecutionPolicy Bypass -File deploy\set_api_base.ps1 -ApiBase "https://api.obzexchange.com"
```

Do not publish with `http://127.0.0.1:8080`; that only works on the local computer.

## Custom domain

In GitHub Pages, set the custom domain to `obzexchange.com`.
At the registrar, use the DNS records recommended by GitHub for the apex domain and add a CNAME for `www` to the GitHub Pages hostname.
Keep `api` as an A record pointing to the Hetzner VPS IPv4 address.
