# Welcome to Stuff

Stuff lets you organize stuff and get stuff done, in your own way.

## How it works



## Getting Started

For now, Stuff setup is manual. CLI tooling will be available in the future.

First, ensure `yq` is available in your `PATH`.

To turn a folder into a Stuff repo, create this directory structure within it:

```
your-folder/
 ├─ .stuff/
 │   ├─ src/
 │   └─ stuff.yaml
 ├─ .stuff-compiled/
 │   ├─ morphs/
 │   ├─ views/
 │   └─ data.json
 ├─ .stuff-static/
 └─ .stuff-manifest.yaml
```

The `.stuff/stuff.yaml` file should have the following structure:

```yaml
stuff: 0.1.0
scope: a-unique-name-of-your-choosing-for-all-your-stuff-anywhere
name: a-name-for-this-particular-stuff-repo
validate: a-command-that-checks-whether-all-required-consistency-checks-hold
test: a-command-with-more-consistency-checks-for-your-morphs-and-views
morphs:
  morph-name:
    load: a-command-that-creates-a-morph-from-data.json
    save: a-command-that-saves-that-morph-back-to-data.json
  another-morph-name:
    load: a-command-that-creates-another-morph-from-data.json
    save: a-command-that-saves-that-other-morph-back-to-data.json
views:
  view-name:
    load: a-command-that-creates-a-view-from-data.json
  another-view-name:
    load: a-command-that-creates-another-view-from-data.json

```

The `.stuff/src/` directory is suggested as the place for the code of the commands listed in `stuff.yaml`.
Further directories are allowed as well, so feel free to use Node.js, Python, Git, Nix flakes, etc. to manage your stuff repo at your leisure.

`.stuff-compiled/` is outside of `.stuff/` as a way to separate the stuff-related code from the actual data.

`.stuff-static/` is for data that is not transformed by the stuff toolset, but merely referenced, e.g. by file name.
Typically this is binary data such as image files.

TODO: explain the purpose of `.stuff-manifest.yaml`
TODO: what else?
