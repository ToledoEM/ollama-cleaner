# Changelog

All notable changes to this project are documented here.

Format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Dated subsections under each release mark when the work landed.

## [1.1] - 2026-08-22

Safety release. The chat deleter now refuses to wipe anything without an
explicit confirmation, and creates a backup by default.

### 2026-11-09

#### Changed

- Documentation site is now built with Zensical instead of Quarto. Config is
  `zensical.toml`, the page is `docs/index.md`, styles are in
  `docs/stylesheets/extra.css`, and the GoatCounter tag is kept through
  `overrides/main.html`. Output goes to `site/`.
- `img/` moved to `docs/img/`; `README.md` image paths updated.
- Remote repository renamed from `Delete_ollamahistory_chat` to
  `ollama-cleaner`. Site, repo and badge URLs in `zensical.toml`,
  `README.md`, `docs/index.md` and the changelog links now use the new name.

#### Removed

- Quarto files: `index.qmd`, `_quarto.yml`, `styles.css`.

### 2026-08-22

#### Added

- `index.qmd`, `_quarto.yml` and `styles.css` are now tracked in the repository.
  Previously they were gitignored, so the published Quarto site could not be
  rebuilt from a clone. (`2ef5102`, `e0d385a`)
- `img/DOC_logo.svg` tracked as a local asset. (`2ef5102`)

#### Changed

- Renamed the Quarto page source `readme.qmd` to `index.qmd`. It now renders
  straight to `_site/index.html` instead of `_site/readme.html` plus a
  meta-refresh redirect stub. (`2ef5102`)
- `_quarto.yml`: render target and navbar link point at `index.qmd`; navbar logo
  points at the local `img/DOC_logo.svg`. (`2ef5102`)
- `README.md` and `index.qmd` reference the local logo instead of the remote
  `toledoem.github.io/img/DOC_logo.png`. (`2ef5102`, `e0d385a`)

#### Fixed

- `.DS_Store` is now gitignored. It was present in the working tree and could
  have been committed by a `git add .`. (`e0d385a`)
- Whitespace drift between `README.md` and the Quarto page source. (`e0d385a`)

### 2026-06-05

#### Changed

- Added a link to a further open Ollama PR in the motivation section. (`b6b3085`)

### 2026-05-13

#### Removed

- Dropped Linux support. The Linux badge, the Debian/Ubuntu, Fedora and Arch
  `sqlite3` install instructions, and the "macOS and Linux" section heading were
  removed from the README — the path was untested. (`fb27e89`)

### 2026-05-12

#### Added

- README badges: MIT licence, macOS, Windows, last commit, and shell script. (`7395b6b`)

### 2026-05-05

#### Added

- Project logo in the README header. (`eab581f`)

### 2026-05-04

#### Added

- Quarto website scaffolding for publishing the documentation to GitHub Pages.
  Build artefacts and site sources were gitignored at this point. (`c37946a`)

#### Changed

- Expanded the motivation section with a Reddit thread, upstream Ollama pull
  requests, and further linked issues. Fixed the malformed link syntax. (`c37946a`, `2e0373c`)

#### Fixed

- README typo. (`ea8874f`)

## [1] - 2026-05-03

First tagged release. macOS and Windows scripts for wiping Ollama GUI chat
history and clearing the logs.

### 2026-04-13

#### Added

- MIT `LICENSE`. (`ead91f2`)

### 2026-04-04

#### Added

- Windows screenshots covering the winget install, the script run, and the
  before/after chat state. (`306e315`)
- README guidance for the winget certificate error `0x8A15005E`, and
  instructions for adding `sqlite3.exe` to `PATH` after a winget install, which
  winget does not do automatically. (`306e315`)
- Note on bypassing the PowerShell execution policy for a single run. (`306e315`)

#### Fixed

- `ollama_chat_deleter.ps1` now also matches the `ollama app` and `ollama_app`
  processes, so the tray app is stopped along with the server. (`306e315`)
- The script now waits up to 10 seconds for every Ollama process to exit instead
  of sleeping for a fixed second. (`306e315`)
- Removing a locked `-wal` or `-shm` sidecar file no longer aborts the run; a
  warning is logged and SQLite cleans the file on next open. (`306e315`)

### 2026-04-03

#### Added

- `ollama_chat_deleter.ps1` and `ollama_logs_deleter.ps1` — Windows PowerShell
  ports of both scripts, with `OLLAMA_DB`, `OLLAMA_BACKUP` and `OLLAMA_LOG_DIR`
  environment overrides, an optional backup prompt, and a `VACUUM` after the
  delete. (`1d3e3e3`)

### 2026-02-28

#### Added

- `ollama_chat_deleter.sh` — initial macOS and Linux script. Deletes chat
  history from the Ollama GUI SQLite database, leaving models, users and app
  settings untouched. Detects the database path per platform, validates that
  `sqlite3` and the expected tables are present, offers a backup, and runs
  `VACUUM` afterwards. `OLLAMA_DB` and `OLLAMA_BACKUP` override the defaults.
  (`37d1e23`)
- `ollama_logs_deleter.sh` — clears the Ollama log directory. Lists every file
  to be removed and requires an explicit `y`/`yes` confirmation.
  `OLLAMA_LOG_DIR` overrides the default `$HOME/.ollama/logs`. (`59a39b3`)
- Before/after screenshots and initial README. (`37d1e23`)

[1.1]: https://github.com/ToledoEM/ollama-cleaner/compare/v1...v1.1
[1]: https://github.com/ToledoEM/ollama-cleaner/releases/tag/v1
