param (
    [string] $ArchivePath
)

if (-not (Test-Path symstore-venv))
{
    python -m venv symstore-venv
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Command exited with code $LASTEXITCODE"
    }
}
$symstoreVersion = "0.3.4"
if (-not (Test-Path symstore-venv\Scripts\symstore.exe) -or -not ((symstore-venv\Scripts\pip show symstore | Select-String '(?<=Version: ).*').Matches.Value -eq $symstoreVersion))
{
    symstore-venv\Scripts\pip install symstore==$symstoreVersion
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Command exited with code $LASTEXITCODE"
    }
}

function ProcessDirectory {
    param (
        [string] $DirectoryPath
    )

    $artifacts = Get-ChildItem -Recurse -File $DirectoryPath | Where-Object { $_.Extension -in (".dll", ".exe", ".pdb") } | ForEach-Object { Resolve-Path -Relative $_.FullName }

    symstore-venv\Scripts\symstore --compress .\SymStore @artifacts
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Command exited with code $LASTEXITCODE"
    }
}

if (Test-Path $ArchivePath -PathType Leaf)
{
    try {
        New-Item -ItemType Directory temp-symbols

        7z x -r $ArchivePath -otemp-symbols *.dll *.exe *.pdb -y
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Command exited with code $LASTEXITCODE"
        }

        ProcessDirectory temp-symbols
    }
    finally {
        Remove-Item -Recurse temp-symbols
    }
} elseif (Test-Path $ArchivePath -PathType Container) {
    ProcessDirectory $ArchivePath
} else {
    Write-Error "$ArchivePath does not exist."
}
