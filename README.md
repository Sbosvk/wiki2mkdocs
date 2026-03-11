# wiki2mkdocs

Sync a GitHub Wiki into a clean MkDocs structure and deploy it to GitHub Pages, automatically.

This repo gives you:
- a dispatcher workflow for wiki edits
- a Pages build/deploy workflow
- sync/normalize/generation scripts
- a baseline MkDocs config

## What This Solves

GitHub Wikis are easy to contribute to, but hard to navigate and search at scale.  
`wiki2mkdocs` keeps the wiki as the editing source while publishing a better docs site with MkDocs.

## Repo Roles (Important)

You need **2 repositories**:

1. **Source repo**: the normal GitHub repo that has the Wiki tab (for example `acme/project`).
   - People edit wiki pages there.
   - This repo runs the wiki-dispatch workflow on wiki changes (`gollum` event).

2. **Pages repo**: the repo that hosts/builds Pages (for example `acme/acme.github.io` or another Pages-enabled repo).
   - This repo runs sync + MkDocs build + deploy.

Wiki content itself is cloned from `acme/project.wiki` by the Pages workflow.

## File Placement

Copy these from this repo into your repos:

### In source repo (`acme/project`)

Create:
- `.github/workflows/wiki-pages-dispatch.yml`

Copy from:
- [`workflows/wiki/wiki-pages-dispatch.yml`](workflows/wiki/wiki-pages-dispatch.yml)

### In pages repo (`acme/acme.github.io`)

Create:
- `.github/workflows/build-from-wiki.yml`
- `mkdocs/requirements.txt`
- `mkdocs/mkdocs.base.yml`
- `mkdocs/scripts/sync_wiki_to_mkdocs.sh`
- `mkdocs/scripts/generate_wiki_sync_map.pl`
- `mkdocs/scripts/generate_mkdocs_yml.pl`
- `mkdocs/scripts/normalize_wiki_links.pl`
- `mkdocs/scripts/normalize_admonitions.pl`
- `mkdocs/scripts/check_internal_links.sh`

Copy from:
- [`workflows/pages/build-from-wiki.yml`](workflows/pages/build-from-wiki.yml)
- [`mkdocs/requirements.txt`](mkdocs/requirements.txt)
- [`mkdocs/mkdocs.base.yml`](mkdocs/mkdocs.base.yml)
- [`mkdocs/scripts/`](mkdocs/scripts)

## GitHub Settings You Must Configure

### In source repo (`acme/project`)

Settings -> Secrets and variables -> Actions

- Variable: `PAGES_TARGET_REPO`  
  Value: `<owner>/<pages-repo>` (example: `acme/acme.github.io`)

- Secret: `PAGES_REPO_DISPATCH_TOKEN`  
  Value: PAT token that can call repository dispatch on the pages repo.

### In pages repo (`acme/acme.github.io`)

Settings -> Secrets and variables -> Actions

- Variable: `WIKI_SOURCE_REPO`  
  Value: `<owner>/<source-repo>.wiki` (example: `acme/project.wiki`)

- Variable: `WIKI_SOURCE_BRANCH`  
  Value: `master` (or your wiki branch)

Settings -> Pages

- Build and deployment -> Source: `GitHub Actions`

## PAT Token Setup (for cross-repo dispatch)

Create a token from the account that will trigger dispatch:

1. GitHub -> Settings -> Developer settings -> Personal access tokens.
2. Create token (classic `repo` scope is simplest), or fine-grained with access to the Pages repo.
3. Save token as `PAGES_REPO_DISPATCH_TOKEN` secret in the **source repo**.

## End-to-End Flow

1. Contributor edits wiki page in source repo Wiki tab.
2. `wiki-pages-dispatch.yml` runs on `gollum` in source repo.
3. It sends `repository_dispatch` (`wiki_updated`) to pages repo.
4. Pages repo workflow starts (`build-from-wiki.yml`).
5. Workflow clones the wiki repo (`WIKI_SOURCE_REPO`) into `wiki-src`.
6. It runs `SOURCE_ROOT=wiki-src ./mkdocs/scripts/sync_wiki_to_mkdocs.sh`.
7. Sync script runs:
   - `generate_wiki_sync_map.pl` to build a deterministic mapping TSV
   - copy wiki markdown into `mkdocs/docs` structure
   - copy wiki `images/` into `mkdocs/docs/images` and `mkdocs/docs/assets/images`
   - `normalize_admonitions.pl` to convert GitHub alerts (`> [!NOTE]`, etc.) to MkDocs admonitions
   - `normalize_wiki_links.pl` to rewrite wiki links and normalize extensionless internal links
   - `generate_mkdocs_yml.pl` to regenerate `mkdocs/mkdocs.yml` from base config + generated map
8. Workflow runs `check_internal_links.sh` (fails if `.md` links remain).
9. MkDocs build runs with `--strict`.
10. Site artifact is uploaded and deployed with `actions/deploy-pages`.

## Wiki Filename Convention (Important)

The sync pipeline builds folder paths and nav from wiki markdown filenames.
Use this pattern for predictable output:

`Section---Subsection---Page-Title.md`

Rules:
- Use `---` between hierarchy segments.
- Use `-` inside words.
- Filename must end with `.md`.
- `Home.md` is special and maps to `index.md` (site root page).
- `_Sidebar.md` and `_Footer.md` are ignored by sync.

Ordering rules:
- Optional numeric prefix per segment controls nav order:
  - `1_Getting-Started---2_Installation---1_Requirements.md`
- `N_` is stripped from displayed labels and URL slugs.
- At each nav level, items with `N_` come first (sorted by number).
- Remaining items without `N_` come after, sorted alphabetically.

Examples:
- `Home.md`
- `1_Getting-Started---1_Installation---1_Requirements.md`
- `1_Getting-Started---1_Installation---2_Install.md`
- `2_User-Guide---1_Main-Interface---1_Home.md`

What this becomes (roughly):
- `getting-started/installation/requirements.md`
- `getting-started/installation/install.md`
- `user-guide/main-interface/home.md`

## MkDocs Base Config (`mkdocs.base.yml`)

`mkdocs.base.yml` is your stable template for non-nav settings:
- `site_name`, `repo_url`, theme, markdown extensions, etc.

`generate_mkdocs_yml.pl` appends generated `nav:` to this base and writes:
- `mkdocs/mkdocs.yml`

So:
- edit `mkdocs.base.yml` for general MkDocs behavior
- do **not** hand-maintain nav in `mkdocs.yml` (it is regenerated)

### Required Base Config Edits

After copying `mkdocs/mkdocs.base.yml` into your pages repo, update the placeholder values:

- `site_name`: your docs/site title.
- `site_description`: short description shown in metadata/search previews.
- `repo_url`: URL of your source code repo (usually non-wiki repo), for example `https://github.com/acme/project`.
- `repo_name`: `owner/repo` label, for example `acme/project`.
- `edit_uri`: URL prefix for editing wiki pages, for example `https://github.com/acme/project.wiki/blob/master/`.

Notes:
- These are intentionally blank in this template so you must set them.
- If `edit_uri` is wrong, "Edit this page" links in MkDocs will point to the wrong place.
- Theme/markdown extension defaults are safe to keep as-is unless you want custom behavior.

## Local Test (Pages Repo)

```bash
git clone --depth 1 --branch master https://github.com/<owner>/<source-repo>.wiki.git wiki-src
SOURCE_ROOT=wiki-src ./mkdocs/scripts/sync_wiki_to_mkdocs.sh
./mkdocs/scripts/check_internal_links.sh
cd mkdocs && mkdocs build --strict
```

## Troubleshooting

- `Missing secret PAGES_REPO_DISPATCH_TOKEN`:
  Add it as an Actions **secret** in the source repo (not variable).
- Dispatch returns 404:
  `PAGES_TARGET_REPO` must be full `owner/repo`.
- `Mapped source is missing: Home.md` in pages repo:
  You forgot `SOURCE_ROOT=wiki-src` or wiki clone step.
- Link check says `.md` links remain:
  run sync again and inspect `normalize_wiki_links.pl` behavior for that page pattern.
