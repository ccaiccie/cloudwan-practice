# AWS Cloud WAN for Network Engineers

Offline practice files for a three-unit course on AWS Cloud WAN for network engineers.

Playlist: coming soon

Everything in this repository runs offline on your own computer. No AWS account is needed, and nothing here contacts AWS or changes anything in an account.

## Units

| Unit | Title | Folder |
| --- | --- | --- |
| 1 | Cloud WAN basics | [unit01](unit01/) |
| 2 | BGP communities refresher | [unit02](unit02/) |
| 3 | BGP communities on Direct Connect attachments | [unit03](unit03/) |

## How to run the labs

Units 1 and 2 are reading exercises. Open the files in any text editor. Unit 1 is the core network policy from the lesson and six questions in `EXERCISE.md`. Unit 2 is an illustrative route policy, the routes it is applied to, and eight questions. Neither unit needs a router, a lab, or an AWS account. Nothing in those folders contacts AWS or any other host.

Unit 3 is a small teaching simulator (`cwsim`). It reads JSON files and prints results. It never calls AWS, needs no AWS account, and costs nothing. Use Bash, or PowerShell 7. Both print the same output, line for line, and should end with `12 passed, 0 failed`.

Run the commands from the `unit03` folder.

### Bash

Linux, macOS, WSL, or Git Bash. Needs `bash` and `jq` 1.6 or later. Install jq with `sudo apt install jq`, `brew install jq`, or `winget install jqlang.jq`.

```bash
bash tests/run-tests.sh
```

### PowerShell 7

Windows. Nothing else to install. If scripts are blocked, run this once in `unit03`:

```powershell
Unblock-File -Path .\bin\*.ps1, .\tests\*.ps1
```

```powershell
pwsh -File tests/run-tests.ps1
```

Each unit's README has the file list. Unit 3 also includes `EXERCISE.md` and an optional `MANUAL-GUIDE.md` for evaluating the same flows by hand, with no scripts.
