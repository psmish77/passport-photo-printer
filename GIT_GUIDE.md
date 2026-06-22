# 🌿 Git Guide for Beginners
### Everything you need to know — explained simply

---

## 🤔 What is Git?

Think of Git like a **save system for your code** — like quicksave in a game.
- Every time you save (called a **commit**), Git remembers exactly what your code looked like
- You can go back to any previous save, anytime
- GitHub is where you upload those saves online so they're safe and shareable

---

## ⚙️ One-Time Setup (do this only once)

```powershell
# Tell Git who you are
git config --global user.name "psmish77"
git config --global user.email "your@email.com"
```

---

## 📁 Starting a Project

```powershell
# Turn a folder into a Git project (only do once per project)
git init
```

> You already did this for Panditji Passport! ✅

---

## 💾 The 3 Steps to Save Your Work

Every time you make changes, you do these 3 steps:

```
1. Check what changed  →  git status
2. Stage the changes   →  git add -A
3. Save (commit)       →  git commit -m "describe what you changed"
```

### In practice:

```powershell
# Step 1: See what files you changed
git status

# Step 2: Stage ALL changed files (the -A means "all")
git add -A

# Step 3: Save with a message describing what you did
git commit -m "fix: background removal now uses remove.bg API"
```

> 💡 Think of `git add` as putting files in a box, and `git commit` as sealing the box with a label.

---

## ☁️ Uploading to GitHub (Push)

```powershell
# Upload your commits to GitHub
git push private master:main     # → push to your PRIVATE repo
git push public public:main      # → push to your PUBLIC repo
```

### Breaking it down:
- `git push` = upload
- `private` = the name of the remote (GitHub repo)
- `master:main` = "take my local `master` branch and push it as `main` on GitHub"

---

## 📥 Downloading from GitHub (Pull)

If you edited something on GitHub.com directly, or on another computer:

```powershell
# Download the latest changes from GitHub
git pull private main      # pull from private repo
```

---

## 🌿 Branches — Working on Different Versions

Branches let you work on two versions of the same project at the same time.

```powershell
# See which branch you're on
git branch

# Switch to a different branch
git checkout master       # switch to master (private version)
git checkout public       # switch to public version

# Create a new branch
git checkout -b new-feature
```

> 📌 **Your branches:**
> - `master` = your private app (Panditji Hotel, API key, map address)
> - `public` = the open-source version (no address, no private URL)

---

## 📋 Checking History

```powershell
# See all your past commits (saves)
git log --oneline

# Example output:
# 9f9e381 ci: add GitHub Actions workflow
# 1f0836e feat: public release
# 15eea01 feat: initial commit
```

---

## 🔗 Remotes — Where Does Your Code Live Online?

A "remote" is just a shortcut name for a GitHub URL.

```powershell
# See your remotes
git remote -v

# Add a new remote
git remote add NAME https://github.com/username/repo.git

# Your remotes right now:
# private → https://github.com/psmish77/panditji-printing-private.git
# public  → https://github.com/psmish77/passport-photo-printer.git
```

---

## 🔄 Your Daily Workflow (Most Common)

When you make code changes in VS Code / your editor:

```powershell
# 1. Check what changed
git status

# 2. Stage everything
git add -A

# 3. Commit with a message
git commit -m "what I changed"

# 4. Push to private repo (GitHub Actions will auto-build APK!)
git checkout master
git push private master:main
```

---

## 🆘 Oops Commands — Fix Mistakes

```powershell
# Undo changes to a file (BEFORE committing) — restores it to last commit
git restore filename.dart

# Undo ALL uncommitted changes (careful — cannot be undone!)
git restore .

# Undo the LAST commit but keep the changes
git reset --soft HEAD~1

# See what changed in a file
git diff lib/main.dart
```

---

## 🏷️ Quick Reference Card

| Command | What it does |
|---|---|
| `git status` | See what files changed |
| `git add -A` | Stage all changes |
| `git commit -m "msg"` | Save with a message |
| `git push private master:main` | Upload to private GitHub repo |
| `git push public public:main` | Upload to public GitHub repo |
| `git pull private main` | Download latest from GitHub |
| `git log --oneline` | See commit history |
| `git branch` | See all branches |
| `git checkout master` | Switch to master branch |
| `git checkout public` | Switch to public branch |
| `git remote -v` | See GitHub repo connections |
| `git diff` | See exact line-by-line changes |
| `git restore .` | Undo all unsaved changes |

---

## 🎯 Commit Message Tips

Write commit messages like a sentence describing WHAT changed:

| ✅ Good | ❌ Bad |
|---|---|
| `fix: background removal now works` | `fixed stuff` |
| `feat: add credits display in settings` | `update` |
| `ui: change app title to Passport Printer` | `asdf` |
| `ci: add GitHub Actions APK build` | `new file` |

**Prefixes to use:**
- `feat:` — new feature
- `fix:` — bug fix
- `ui:` — visual/design change
- `ci:` — build/deployment change
- `docs:` — documentation update

---

## 🔐 Personal Access Token (GitHub Password)

GitHub doesn't accept your account password for `git push`. You need a **token**:

1. GitHub → avatar → **Settings**
2. Scroll to bottom → **Developer Settings**
3. **Personal access tokens** → **Tokens (classic)**
4. **Generate new token (classic)**
5. Set **No expiration**, tick ✅ `repo`
6. **Generate** → copy the token immediately!

When `git push` asks for password → paste this token.

> 💡 Save the token in Notepad somewhere safe — it's only shown once!

---

## 📦 Your Project's Git Structure

```
panditji_printing_app/
│
├── 📁 .git/              ← Git lives here (don't touch this folder!)
├── 📁 .github/
│   └── workflows/
│       └── build-apk.yml ← Auto-builds APK when you push
├── 📁 lib/               ← Your Flutter code
├── .gitignore            ← Files Git ignores (build outputs, keys)
├── README.md             ← Project description
└── vercel.json           ← Vercel deployment config

Branches:
  master  → pushed to → github.com/psmish77/panditji-printing-private (🔒 Private)
  public  → pushed to → github.com/psmish77/passport-photo-printer    (🌐 Public)
```

---

*Made for Panditji Passport Photo Printer project — psmish77*
