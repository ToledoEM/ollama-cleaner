# Ollama GUI chat-history wipe script (Windows)
# Deletes ONLY chat data (chats/messages/tool_calls/attachments)
# Keeps settings, users, models intact
# Requires typing DELETE to confirm (OLLAMA_FORCE=yes skips the prompt)
# Optional backup (default: backup created)
#
# Usage:
#   .\ollama_chat_deleter.ps1
#   $env:OLLAMA_DB = "C:\path\to\db.sqlite"; .\ollama_chat_deleter.ps1
#   $env:OLLAMA_BACKUP = "no";               .\ollama_chat_deleter.ps1
#   $env:OLLAMA_FORCE = "yes";               .\ollama_chat_deleter.ps1

$ErrorActionPreference = "Stop"

function Get-DefaultDbPath {
    $candidates = @(
        "$env:APPDATA\Ollama\db.sqlite",
        "$env:LOCALAPPDATA\Ollama\db.sqlite"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c -PathType Leaf) { return $c }
    }
    return $candidates[0]
}

function Write-Log { param([string]$msg) Write-Host $msg }

function Should-CreateBackup {
    $choice = $env:OLLAMA_BACKUP
    if ($choice) {
        switch ($choice.ToLower()) {
            { $_ -in "1","y","yes","true" } { return $true }
            { $_ -in "0","n","no","false" } { return $false }
            default {
                Write-Log "ERROR: OLLAMA_BACKUP must be one of: 1,0,yes,no,true,false"
                exit 1
            }
        }
    }

    # Non-interactive runs default to creating a backup.
    if ([Console]::IsInputRedirected) { return $true }

    # Interactive prompt. Empty answer keeps the safe default (yes).
    $answer = Read-Host "Create DB backup before deleting chats? [Y/n]"
    return (-not ($answer.ToLower() -in "n","no"))
}

function Confirm-Wipe {
    # OLLAMA_FORCE=1 skips the prompt for automation.
    if ($env:OLLAMA_FORCE -and ($env:OLLAMA_FORCE.ToLower() -in "1","y","yes","true")) {
        return $true
    }

    if ([Console]::IsInputRedirected) {
        Write-Log "ERROR: refusing to wipe non-interactively. Set OLLAMA_FORCE=yes to proceed."
        exit 1
    }

    $chats = sqlite3 $DB "SELECT COUNT(*) FROM chats;"
    if ($LASTEXITCODE -ne 0) { Write-Log "ERROR: could not count chats in $DB"; exit 1 }

    Write-Log "About to permanently delete $chats chat(s) and all their messages from:"
    Write-Log "  $DB"
    $answer = Read-Host "Type DELETE to confirm"
    return ($answer -ceq "DELETE")
}

# ---- Resolve DB path ----
$DB = if ($env:OLLAMA_DB) { $env:OLLAMA_DB } else { Get-DefaultDbPath }

if ([string]::IsNullOrWhiteSpace($DB)) {
    Write-Log "ERROR: database path is empty."
    exit 1
}

Write-Log "Using DB path: $DB"

# ---- Check DB exists ----
if (-not (Test-Path $DB -PathType Leaf)) {
    Write-Log "ERROR: db not found: $DB"
    Write-Log "If your db is elsewhere, run like:"
    Write-Log '  $env:OLLAMA_DB = "C:\full\path\to\db.sqlite"; .\ollama_chat_deleter.ps1'
    exit 1
}

# ---- Check sqlite3 installed ----
if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
    Write-Host "sqlite3 not found."
    Write-Host ""
    Write-Host "Install sqlite3 with:"
    Write-Host "  winget install SQLite.SQLite"
    Write-Host "  OR download from https://sqlite.org/download.html"
    Write-Host "  and add sqlite3.exe to your PATH."
    exit 1
}

# ---- Stop Ollama process ----
$ollamaProcs = Get-Process -Name "ollama","Ollama","ollama app","ollama_app" -ErrorAction SilentlyContinue
if ($ollamaProcs) {
    Write-Log "Stopping Ollama..."
    $ollamaProcs | Stop-Process -Force
    # Wait until all ollama processes are gone (up to 10s)
    $waited = 0
    while ((Get-Process -Name "ollama","Ollama","ollama app","ollama_app" -ErrorAction SilentlyContinue) -and $waited -lt 10) {
        Start-Sleep -Seconds 1
        $waited++
    }
}

# ---- Validate expected tables ----
# Runs before the confirmation prompt so a malformed DB fails without asking,
# and so the chat count in the prompt is safe to read.
# @(...) forces an array: a single-row result is a string, and -contains on a
# string is always false.
$tables = @(sqlite3 $DB "SELECT name FROM sqlite_master WHERE type='table';")
if ($LASTEXITCODE -ne 0) {
    Write-Log "ERROR: could not read schema from $DB"
    exit 1
}

foreach ($t in @("chats","messages","tool_calls","attachments")) {
    if ($tables -notcontains $t) {
        Write-Log "ERROR: expected table '$t' not found."
        Write-Log "Tables present: $($tables -join ', ')"
        exit 1
    }
}

# ---- Confirm the wipe ----
# Asked before the backup prompt so cancelling costs nothing.
if (-not (Confirm-Wipe)) {
    Write-Log "Cancelled. Nothing deleted."
    exit 0
}

# ---- Optional backup ----
if (Should-CreateBackup) {
    $ts  = (Get-Date -Format "yyyyMMdd-HHmmss")
    $bak = "$DB.bak.$ts"
    Copy-Item $DB $bak
    Write-Log "Backup created: $bak"
} else {
    Write-Log "Skipping backup."
}

# ---- Delete chat history ----
$sql = @"
PRAGMA foreign_keys=ON;
BEGIN IMMEDIATE;
DELETE FROM attachments;
DELETE FROM tool_calls;
DELETE FROM messages;
DELETE FROM chats;
COMMIT;
"@

# sqlite3 is a native exe: it sets $LASTEXITCODE instead of throwing, so a
# try/catch here would never fire.
$sql | sqlite3 $DB
if ($LASTEXITCODE -ne 0) {
    Write-Log "WARN: strict delete failed; retrying compatibility delete."
    @"
DELETE FROM attachments;
DELETE FROM tool_calls;
DELETE FROM messages;
DELETE FROM chats;
"@ | sqlite3 $DB
    if ($LASTEXITCODE -ne 0) {
        Write-Log "ERROR: delete failed."
        exit 1
    }
}

# WAL/SHM cleanup only runs if VACUUM succeeded — removing an active WAL that
# still holds committed data would lose it.
sqlite3 $DB "VACUUM;"
if ($LASTEXITCODE -ne 0) {
    Write-Log "WARN: VACUUM failed; DB is still valid. Leaving WAL/SHM files in place."
} else {
    foreach ($ext in "-wal","-shm") {
        $f = "$DB$ext"
        if (Test-Path $f) {
            try { Remove-Item $f -Force -ErrorAction Stop }
            catch { Write-Log "WARN: could not remove $f (still locked) - safe to ignore, SQLite will clean it on next open." }
        }
    }
}

Write-Log "Done. Chat history wiped from: $DB"
