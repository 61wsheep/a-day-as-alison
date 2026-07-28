---
name: godot-docs-search
description: Search and apply the local Godot documentation that matches this project's engine version before using the web. Use when answering Godot engine questions, checking API behavior, looking up node or class usage, verifying C# or GDScript patterns, or making architecture decisions for this 3D Third Person Shooter project.
allowed-tools: 
disable: false
---

# Godot Docs Search

Use this skill whenever the task depends on Godot knowledge that should be verified from the local docs first.

This skill bundles one or more local copies of the official Godot docs under `references/godot-docs-<VERSION>/` (e.g. `references/godot-docs-4.6/`). Treat the copy that matches the project's engine version as the primary source of truth before using web search.

## Resolve The Docs Path First

Before searching, resolve a concrete docs root called `$DOCS` using this algorithm:

1. **Read engine version** from the project's `project.godot`:
   - Look at `[application]` -> `config/features=PackedStringArray("4.6", ...)`.
   - The first pure `MAJOR.MINOR` string (e.g. `"4.6"`, `"4.4"`, `"4.3"`) is the engine version.
2. **Pick the exact match** if it exists:
   - `$DOCS = references/godot-docs-<version>`
3. **Fallback** in this priority, if the exact version directory is missing:
   1. Same major, highest minor available under `references/` (e.g. request `4.5` -> fall back to `4.6` if it is the closest same-major copy).
   2. Any directory matching `references/godot-docs-*`, picking the newest by version number.
   3. Legacy unversioned `references/godot-docs/` if present.
4. **Fail loud** if no docs copy exists under `references/`. Do not silently switch to web search without telling the user.

Always perform searches against `$DOCS`. Never hardcode a specific version in answers or citations — read it from `project.godot` each session.

### PowerShell Resolver Snippet

Run this once (from the skill folder or project root) to compute `$DOCS` before any search:

```powershell
# Locate project.godot starting from the current directory upward
$projFile = Get-ChildItem -Path . -Filter project.godot -Recurse -Depth 3 -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $projFile) { throw "project.godot not found; cannot determine engine version." }

# Parse engine version from config/features
$raw = Get-Content -LiteralPath $projFile.FullName -Raw
$version = $null
if ($raw -match 'config/features\s*=\s*PackedStringArray\(([^)]*)\)') {
    $items = $matches[1] -split ','
    foreach ($it in $items) {
        $t = $it.Trim().Trim('"')
        if ($t -match '^\d+\.\d+$') { $version = $t; break }
    }
}
if (-not $version) { throw "Could not parse engine version from project.godot." }

# Skill references root (relative to this SKILL.md)
$refsRoot = Join-Path $PSScriptRoot 'references'
if (-not (Test-Path $refsRoot)) { $refsRoot = '.codebuddy/skills/godot-docs-search/references' }

# Prefer exact match, then same-major highest-minor, then any versioned, then legacy
$exact = Join-Path $refsRoot "godot-docs-$version"
if (Test-Path $exact) {
    $DOCS = $exact
} else {
    $major = ($version -split '\.')[0]
    $candidates = Get-ChildItem -LiteralPath $refsRoot -Directory -Filter 'godot-docs-*' -ErrorAction SilentlyContinue |
        ForEach-Object {
            $v = $_.Name -replace '^godot-docs-', ''
            if ($v -match '^(\d+)\.(\d+)$') {
                [pscustomobject]@{ Path = $_.FullName; Major = [int]$matches[1]; Minor = [int]$matches[2] }
            }
        }
    $sameMajor = $candidates | Where-Object { $_.Major -eq [int]$major } | Sort-Object Minor -Descending | Select-Object -First 1
    if ($sameMajor) {
        $DOCS = $sameMajor.Path
    } else {
        $any = $candidates | Sort-Object Major, Minor -Descending | Select-Object -First 1
        if ($any) {
            $DOCS = $any.Path
        } else {
            $legacy = Join-Path $refsRoot 'godot-docs'
            if (Test-Path $legacy) { $DOCS = $legacy } else { throw "No Godot docs copy under $refsRoot." }
        }
    }
}
Write-Host "Using Godot docs: $DOCS"
```

After this snippet, every command in this skill that references `$DOCS` becomes concrete.

## Required Search Order

Follow this order strictly:

1. Search `$DOCS/getting_started/` and `$DOCS/tutorials/` for concepts, patterns, and workflows.
2. Search `$DOCS/classes/` for API and node class details.
3. Use the web only if the local docs do not answer the question.

If local docs are enough, do not browse.

## Search Workflow

Prefer `rg` for fast lookup. If `rg` is unavailable, use PowerShell `Select-String`.

Run commands from the skill folder (or project root) so `$DOCS` resolves cleanly.

### Concept Search

Use this when the user asks about a system, pattern, or engine feature:

```powershell
rg -n "signal|autoload|resource|scene tree" "$DOCS/getting_started" "$DOCS/tutorials" -g "*.rst"
```

Fallback:

```powershell
Get-ChildItem "$DOCS/getting_started", "$DOCS/tutorials" -Recurse -Filter *.rst |
  Select-String -Pattern "signal|autoload|resource|scene tree"
```

### Class Search

Use this when the user asks about a specific node, resource, or API type:

```powershell
rg -n "CharacterBody3D|Camera3D|NavigationAgent3D|AnimationTree" "$DOCS/classes" -g "*.rst"
```

Fallback:

```powershell
Get-ChildItem "$DOCS/classes" -Recurse -Filter *.rst |
  Select-String -Pattern "CharacterBody3D|Camera3D|NavigationAgent3D|AnimationTree"
```

### Tutorial Search

Use this when the user needs implementation guidance rather than raw API details:

```powershell
rg -n "third person|shooter|aim|recoil|raycast|state machine" "$DOCS/tutorials" -g "*.rst"
```

## How To Read Results

- Use `classes/` for inheritance, properties, methods, signals, and caveats.
- Use `tutorials/` for setup sequence, recommended workflow, and architectural guidance.
- Use `getting_started/first_3d_game/` when the user needs fundamentals of 3D scenes, nodes, signals, resources, or scripting basics.
- When both class docs and tutorials exist, combine them: use tutorial guidance for the approach, then confirm exact API usage in class docs.

## 3D TPS Priority Topics

For this project (Third Person Shooter, 3D), check these areas first when relevant:

- Player movement and collision: `CharacterBody3D`, `CollisionShape3D`, `CapsuleShape3D`
- Camera and aiming: `Camera3D`, `SpringArm3D`, input mapping for mouse/gamepad look
- Combat and hit detection: `RayCast3D`, `Area3D`, physics layers and masks
- Weapons and projectiles: `RigidBody3D`, `RayCast3D`, signal-driven hits
- Animation and aiming pose: `AnimationPlayer`, `AnimationTree`, `StateMachine`, blend spaces
- AI and navigation: `NavigationAgent3D`, navmesh baking, `NavigationRegion3D`
- World and environment: `WorldEnvironment`, lighting, reflection probes
- UI and HUD: `Control`, `CanvasLayer`, anchors, crosshair and health UI
- Data and persistence: `Resource`, file IO, settings save/load
- Global systems: autoload singletons (this project uses `Settings` via `res://menu/settings.gd`)
- Input: `InputEventKey`, `InputEventJoypadButton`, `InputEventJoypadMotion`, deadzones

## Answering Rules

- Base the answer on the local docs when possible.
- Mention the exact doc file(s) you used when the answer depends on a specific API behavior or workflow.
- Cite docs using a version-neutral placeholder path like `references/godot-docs-<VERSION>/classes/class_characterbody3d.rst` so the citation stays meaningful after a docs upgrade; the concrete version can be read from `project.godot`.
- If the local docs are incomplete, say that explicitly before using the web.
- Prefer Godot-native 3D TPS patterns over generic engine-agnostic advice.
- Keep explanations practical and implementation-oriented for this project.

## Useful Starting Points

These exist in `godot-docs-4.6`; in other versions the equivalent files should exist with the same relative paths (adjust if a version rename occurs):

- `$DOCS/classes/class_characterbody3d.rst`
- `$DOCS/classes/class_camera3d.rst`
- `$DOCS/classes/class_springarm3d.rst`
- `$DOCS/classes/class_raycast3d.rst`
- `$DOCS/classes/class_area3d.rst`
- `$DOCS/classes/class_navigationagent3d.rst`
- `$DOCS/classes/class_animationtree.rst`
- `$DOCS/getting_started/first_3d_game/index.rst`
- `$DOCS/tutorials/physics/physics_introduction.rst`
- `$DOCS/tutorials/physics/ray-casting.rst`
- `$DOCS/tutorials/navigation/navigation_introduction_3d.rst`
- `$DOCS/tutorials/navigation/navigation_using_navigationagents.rst`
- `$DOCS/tutorials/scripting/resources.rst`
- `$DOCS/tutorials/scripting/singletons_autoload.rst`
- `$DOCS/tutorials/3d/` (whole folder — camera, lighting, world setup)
- `$DOCS/tutorials/animation/` (state machine, blend spaces)

## Practical Default

When a Godot question arrives, do this:

1. Resolve `$DOCS` using the algorithm above.
2. Identify whether it is a concept question, class question, or workflow question.
3. Search the matching subfolder under `$DOCS` first.
4. Open the most relevant `.rst` files and extract only the details needed for the task.
5. Apply the result in a Godot-native 3D TPS way for this project.

## Portability

This skill is intended to be copied as a standalone folder.

- Keep `SKILL.md` together with at least one `references/godot-docs-<VERSION>/` copy.
- Do not assume the destination repo has a root-level `godot-docs/` folder.
- Multiple `godot-docs-<VERSION>/` copies may coexist; the resolver picks the best match for the project.
- If storage matters, you may prune images (`*.webp`, `*.png`, `*.gif`, `*.svg`) later, but keep all `.rst` files for searchability.

## Troubleshooting

- `project.godot` missing or version unparsable -> tell the user which line you expected and ask for the engine version explicitly.
- `references/` empty or no `godot-docs-*` directory -> say the local docs are unavailable and fall back to the web (with the user's consent when possible).
- Searching yields no matches but topic clearly exists -> expand the pattern, drop `-g "*.rst"` temporarily, or search from `$DOCS` root to catch index pages.
