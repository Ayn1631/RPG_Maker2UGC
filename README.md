# RPG Maker → Lua → UGC

English | [简体中文](README.zh-CN.md)

RPG_Maker2UGC converts compatible RPG Maker MV/MZ projects into a self-contained `levelScript.lua` for UGC. Conversion and bundling run offline: game logic, static data, resource bindings, and registered extensions are compiled into one Lua file.

This repository contains the builder source and the [`rpg-maker-to-lua` migration Skill](skills/rpg-maker-to-lua/SKILL.md). It does not include game projects, game assets, target UI template catalogs, example projects, or test fixtures. Bring a source project and the resource/template bindings you are authorized to use.

## What it supports

- Maps, events, movement, dialogue, choices, switches, variables, and common RPG Maker gameplay data.
- RPG systems and interfaces such as party, inventory, equipment, skills, items, shops, menus, and supported turn-based or TPB battle flows.
- Offline resource processing, explicit template/resource bindings, and a modular Lua runtime for the UGC host.
- A typed extension SDK. JavaScript plugins need an explicit adapter; arbitrary plugins are not translated automatically.
- Inspection and build diagnostics, single-file output, and optional local deployment with backups.

Implemented modules do not imply that every engine version, plugin, parameter, or target template has been verified. Missing or unsupported inputs should be treated as build gaps, not replaced with guessed resources. A successful build does not confirm that the official editor loaded, ran, accepted, or published the result.

## Save support

Save/load is not implemented yet because my current UGC creator level is not high enough to develop it. I plan to add it later.

## Requirements

- Lua 5.3.
- LuaFileSystem (`lfs`) is used by workflows that create directories and by some asset/deployment operations. With `lfs` unavailable, prepare required output directories before running commands that need them.
- Python is only needed for the optional UI-template catalog importer.

Core conversion does not require network access. The target UGC editor and game are separate from this command-line build process.

## Quick start

Run commands from the repository root. Initialize a project from your own RPG Maker project:

```sh
lua tools/r2u.lua init --source "path/to/your-rpg-maker-project" --game-id my-game
```

Review `projects/my-game/project.lua`. Fill in the target-specific template IDs and explicit resource, audio, and extension bindings required by your project. Then inspect and build:

```sh
lua tools/r2u.lua inspect --project projects/my-game/project.lua
lua tools/r2u.lua build --project projects/my-game/project.lua --json
```

The generated script is written under `dist/my-game/levelScript.lua`; the build also writes a report with diagnostics and source mappings. The source project is read as input; the generated configuration, reports, and output stay in local ignored directories.

To copy a build to a local target file, use an existing destination directory:

```sh
lua tools/r2u.lua deploy --project projects/my-game/project.lua --target "path/to/ugc/levelScript.lua"
```

`deploy` builds once and manages backups for its target. It does not load the file into the editor or publish it. Run `lua tools/r2u.lua help` for the current command summary.

## Commands

| Command | Purpose |
| --- | --- |
| `init` | Inspect a source project and create a project configuration and onboarding notes. |
| `inspect` | Check project structure, events, rules, bindings, and registered extensions. |
| `build` | Convert and bundle the project into a single Lua file with diagnostics. |
| `deploy` | Build once, then update a managed local Lua target with backups. |
| `export-tiles`, `export-characters` | Export selected source graphics and binding manifests. |
| `export-primitives` | Create an editable library of explicitly selected primitive assets. |
| `verify` | Check an existing build using explicitly selected local test cases or supplied traces. This repository does not include test fixtures. |
| `release-check` | Check existing build and evidence records; it does not run a game or publish. |

For a different UI template set, `tools/import-ui-templates.py` can import a catalog from a compatible save file. This optional step requires Python; ordinary conversion uses Lua.

## Repository layout

| Path | Contents |
| --- | --- |
| `src/converter/` | RPG Maker source inspection and conversion. |
| `src/build/` | Bundling, project initialization, deployment, verification, and release checks. |
| `src/runtime/` | Game, world, RPG, UI, and audio runtime modules. |
| `src/platform/ugc/` | UGC host integration and UI lifecycle. |
| `src/sdk/` | Extension contracts and runtime registration. |
| `tools/` | Builder entry point and module/tool manifests. |
| `skills/rpg-maker-to-lua/` | Full migration Skill, including its references and templates. |

## Migration Skill

Read [SKILL.md](skills/rpg-maker-to-lua/SKILL.md) or use the [Skill ZIP](skills/rpg-maker-to-lua.zip). It guides an agent through source-project intake, binding discovery, explicit plugin adaptation, verification, and deployment. The Skill does not contain the builder, game assets, target template IDs, or permission to publish.

## License

The repository is licensed under [GNU GPL version 3](LICENSE). The vendored compression library includes its own license and provenance notices under `src/vendor/`.
