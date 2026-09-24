# Kalypso dev environment

Setup for working on Kalypso from any machine, including the server that
erases the home folder at logout. The work lives on GitHub in
[serial-optimizer/kalypso](https://github.com/serial-optimizer/kalypso)
on branch `shivansh/dev`. Hojae's original repo is `Goodluck-hojae/Kalypso`.

## Start of every session

Paste this into a terminal:

```bash
curl -fsSL -o ~/work.sh https://raw.githubusercontent.com/serial-optimizer/kalypso/refs/heads/shivansh/dev/devenv/work.sh && bash ~/work.sh setup
```

This does, skipping anything already done:

1. Makes git work. On the server it uses Xcode's git directly, because the
   normal `git` command is blocked until an admin accepts the Xcode license.
2. Installs the GitHub CLI (`gh`) into `~/bin` after checking its checksum.
3. Logs in to GitHub. **This is the one manual step:** copy the code it shows,
   press Enter, and approve it in the browser.
4. Sets the commit author to your GitHub account, using GitHub's private
   noreply email.
5. Clones the fork to `~/Kalypso`, or updates it if it's already there, and
   switches to `shivansh/dev`. Hojae's repo is added as `upstream`.
6. Adds `~/bin` to PATH for new terminals and installs the `work` command.

Then open a **new terminal** so the `work` command is found.

## During the day

| Command | What it does |
|---|---|
| `work save "what changed"` | Commits every change and pushes it to GitHub. Without a message it uses a timestamp. |
| `work status` | Shows whether anything isn't on GitHub yet. **Run before logging out.** |
| `work sync` | Merges hojae's latest `main` into `shivansh/dev` and pushes. |
| `work setup` | Re-runs setup. It's safe to run any time. |

`work save` refuses to commit files over 50 MB, and files that look like
secrets (`.env`, `*.pem`, `*.key`, SSH keys), because this fork is **public**.
Add them to `.gitignore` instead.

## On another machine

The same command works on any macOS or Linux machine. It uses the git and `gh`
already installed, if they work. To use a different folder or branch:

```bash
WORK_DIR=~/src/kalypso WORK_BRANCH=shivansh/dev bash ~/work.sh setup
```

## Notes

- **Anything not pushed is lost at logout on the server.** Run
  `work save` often.
- VS Code's Source Control panel uses the blocked system git on the server.
  Use `work save`, or set VS Code's `git.path` setting to `~/bin/git`.
- This `devenv/` folder is personal tooling. Leave it out of any pull request
  to hojae's repo.
