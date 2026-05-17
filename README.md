# EwoMail-plus

A modernised fork of [EwoMail](https://github.com/gyxuehu/EwoMail) that runs on
current Debian releases (no more CentOS 7), drops every dependency on the
defunct `npm.ewomail.com` CDN, and ships a visual admin panel for the parts
that used to need command-line work: firewall, Nginx vhosts and Let's Encrypt
certificates.

## At a glance

| | Original | EwoMail-plus |
|---|---|---|
| Target OS               | CentOS 7/8                                | Debian 12 / 13                                       |
| Package source          | Custom RPMs on `npm.ewomail.com`          | Debian apt + upstream GitHub releases only           |
| PHP                     | 7.2                                       | 8.2 (Debian 12) / 8.4 (Debian 13)                    |
| Webmail                 | Rainloop (abandoned 2022)                 | SnappyMail (maintained fork)                         |
| DB admin                | phpMyAdmin                                | Adminer (single PHP file)                            |
| SSL                     | manual self-signed                        | acme.sh + Let's Encrypt, one-click in panel          |
| Admin URL               | `:8010` / `:7010`                         | `https://mail.<domain>/<random-path>/`               |
| DB admin URL            | `:8020`                                   | `https://mail.<domain>/<random-path>/` (toggleable)  |
| Public web ports        | 8000, 7000, 8010, 7010, 8020              | 80 + 443 only (everything else stays on 127.0.0.1)   |
| Default admin password  | `admin / ewomail123` (hardcoded)          | `admin / <random 20-char>` (per install)             |
| Firewall                | `iptables` / hand-rolled `firewall-cmd`   | `firewalld` zone `ewomail` + visual page             |
| Installer               | one-shot shell script                     | interactive: progress, DNS pre-check, DKIM print-out |

## Requirements

A **clean** Debian 12 or 13 VPS, dedicated to this project (the installer
refuses to run if a conflicting MTA / web server / DB is already installed).

- 1 vCPU, 2 GB RAM, 20 GB disk — minimum
- Public IPv4 reachable on 25 / 80 / 443 / 465 / 587 / 993 / 995
- A bare domain you control (e.g. `example.com`, *not* `mail.example.com`)
- Reverse DNS (PTR) → `mail.<domain>` configured at your VPS provider

## Install

```bash
apt update && apt -y install git
git clone https://github.com/Null404-0/EwoMail-plus.git
cd EwoMail-plus
./install/install.sh
```

The installer is interactive: it asks for your domain, admin email and a few
toggles, then runs through 14 stages with progress reporting. Total install
time is ~10 minutes on a 2 GB VPS.

## Update

After the first install, to pick up fixes / new features from upstream:

```bash
cd ~/EwoMail-plus
bash update.sh
```

`update.sh`:

- Pulls the latest commit from `origin/master` (`--ff-only`; aborts on divergence).
- Backs up the current configs to `/ewomail/.update-backup/<timestamp>/`.
- Re-syncs the admin code into `/ewomail/www/ewomail-admin/`, preserving
  user data (mailboxes, attachments, Smarty cache, sessions).
- Re-renders all service config templates (Postfix / Dovecot / Nginx / amavis /
  PHP-FPM / fail2ban / privilege helper).
- Applies any new idempotent DB additions (new panel-setting columns, new
  Server-menu rows, etc.) — never drops or overwrites your data.
- Runs `nginx -t` before reloading; rolls back the vhost on failure.
- Reloads (or restarts when reload is unavailable) only the affected services.

Flags:

- `--code-only` — skip service-config re-render, just sync admin code and
  bump PHP-FPM. Useful when you only want UI/PHP changes without touching
  Postfix/Dovecot/etc.
- `--no-git-pull` — use whatever is already checked out (e.g. after a manual
  `git fetch` and `git checkout <tag>`).

When it finishes you get:

- A randomly generated admin password
- Random URL paths for the admin panel and Adminer
- A `/ewomail/credentials.txt` (mode 0600, root-only) with everything you need
- DKIM / SPF / DMARC records printed and ready to paste into your DNS

## After install — DNS records

Publish these on the domain you used (the installer prints exact values for
your install at the end):

```
A      mail              <server-ipv4>
MX     @                 mail.<domain>.   priority 10
TXT    @                 "v=spf1 mx ~all"
TXT    _dmarc            "v=DMARC1; p=quarantine; rua=mailto:postmaster@<domain>"
TXT    dkim._domainkey   "v=DKIM1; k=rsa; p=<key-from-credentials-file>"
```

…and a PTR record at your VPS provider pointing `<server-ipv4>` → `mail.<domain>`.

## Admin panel walkthrough

Once DNS is live, navigate to:

```
https://mail.<domain>/<random-admin-path>/
```

Log in as `admin` with the password printed at install time (also in
`/ewomail/credentials.txt`).

Left navigation includes a **Server** section with:

- **Firewall** — open / close ports, block / unblock IPv4 addresses via the
  firewalld `ewomail` zone. Changes are persisted (`--permanent`) and applied
  immediately (`--reload`).
- **Nginx** — list vhost files, inline edit with auto rollback when
  `nginx -t` fails, enable / disable each site.
- **SSL** — issue, renew, and install Let's Encrypt certificates via acme.sh
  (HTTP-01 webroot). acme.sh auto-renews every 60 days via the cron entry it
  installs.
- **Settings** — rotate the admin URL path, rotate the database admin URL,
  toggle the database admin entry on/off, change the admin password.

## Uninstall

EwoMail-plus is designed for a dedicated VPS. To remove it, reinstall the OS.
This is intentional: mixing it with another stack on the same machine — or
trying to peel it off — is what broke previous attempts. If the VPS is
disposable (it should be), this constraint costs you nothing.

## File layout

```
EwoMail-plus/
├── install/
│   ├── install.sh         entry point (interactive)
│   ├── lib/*.sh           per-stage logic
│   └── templates/         service config templates (rendered at install)
└── ewomail-admin/         PHP/Smarty admin panel
    ├── module/Center/     routes (Firewall / Nginx / Cert / Setting added)
    └── templates/Center/  views
```

> SnappyMail itself isn't vendored in this repo; the installer downloads the
> latest release ZIP (currently 2.38.3) at install time.

## Reporting issues

Open an issue with:

1. Output of `/var/log/ewomail-install.log` (tail 200 lines).
2. `cat /etc/os-release`.
3. The exact step where the installer failed (the brackets `[N/14]`).

## License

Inherits the original EwoMail license; see `LICENSE`.
