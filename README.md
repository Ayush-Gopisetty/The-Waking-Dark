# The Waking Dark

First-person survival horror in Godot 4.7 (GDScript). This repo currently holds a
**gray-box Act 1**: the west wing of Ashgrove Manor under the pale moon, built to answer
one question: is hiding from spirits in the dark with a dying flashlight actually scary?

## Play the demo

- **In the editor:** open `project.godot` in Godot 4.7.2 and press F5.
- **macOS build:** `builds/macos/The Waking Dark.app`. It's ad-hoc signed, so on another
  Mac you have to right-click it and choose Open the first time.
- **Windows build:** `builds/windows/TheWakingDark.exe`. It's a single file. SmartScreen
  will warn because it's unsigned: click "More info", then "Run anyway".

**Goal (Act 1, following the plan's "Act 1 in detail"):** recover your name, meet
Daniel, and open the east wing door. Three spirits patrol the west wing. If one catches
you in the dark, you lose (with a retry from the last checkpoint).

1. **Abandoned room:** wake on the floor. The flashlight is on the bed. The door is stuck,
   so push it twice.
2. **Servants' hall:** a long corridor with side rooms and one slow spirit. Battery #1 is
   on a shelf. The **furnace key** hangs in the storage room behind the spirit's route.
   Hide in the storage room, the kitchen pantry or the servants' quarters.
3. **Furnace room:** the half-burned ID (Jason holds it up and reads it, then flashback 1).
   Then the spirit blocks the door, and the bright beam drives it off.
4. **Servants' quarters:** the **stairs key** is on the table between the beds. The service
   stairs are locked without it.
5. **Parlour:** at the top of the stairs. Candle-lit from end to end, so no spirit comes in.
   **Daniel** is waiting here (cutscene) and keeps watch by the door afterwards.
6. **Foyer:** dark, with two candle-lit pockets and a spirit circling. A mirror, battery #2
   and a wardrobe; the front doors are chained.
7. **Gallery:** east of the foyer. Portraits, moonlight, and the **study key** on a plinth.
8. **Study** (off the corridor, locked): the **drawer key** is tucked into the bookshelf and
   only shows up in the bright beam. **Dining room** (opposite): a battery and a wardrobe.
9. **Library:** case file 1 (Emily Carter) and a child's drawing on the desk, and humming
   behind the wall. The **east wing key** is in a locked glass case that the drawer key
   opens. Taking it sets off a chase back to the foyer.
10. **East wing door:** Daniel is waiting. The moon turns orange. "After you." End of Act 1.

**Hiding:** inside a wardrobe you look out through the gap between the doors and the slats.
You can switch the flashlight on in there, but a spirit close by will see the light and
come for you.

| Key | Action |
|---|---|
| WASD | Move |
| Shift | Sprint (limited stamina) |
| C / Ctrl | Crouch (quieter, harder to see) |
| E | Interact / hide / step out |
| F | Flashlight on/off |
| Right mouse / Space (hold) | Bright beam: drains fast, weakens the spirit and drives it off |
| Esc | Free the mouse |
| F3 | Debug readout (battery, exposure, spirit state) |
| F11 | Fullscreen |

## How the systems fit together

- **Flashlight** (`scripts/flashlight.gd`): normal and bright modes, battery drain, and a
  faint glow at 0% so the screen never goes fully black.
- **Darkness exposure** (also in `flashlight.gd`): builds while you're unlit. At 8 s the
  spirit senses roughly where you are; at 15 s it hunts you. It decays in light or while
  hidden.
- **Lit areas**: the moonlit abandoned room and the furnace glow. The spirit won't enter
  them and can't catch you inside them.
- **Spirit** (`scripts/spirit.gd`): patrol → investigate → chase → search → retreat. It
  senses by sight, by noise, and through the darkness channel. It is a physical
  demon (`scripts/monster_body.gd`, model `assets/monster/spirit.glb`): doors block its sight and its body, but it
  shoves unlocked doors open. Light is its weakness: the bright beam burns it and
  drives it off, and it won't enter lit areas. If it sees you climb into a
  wardrobe, it pulls you out.
- **Noise** (`scripts/player.gd`): each footstep emits a radius of 1.5 m crouched,
  6 m walking or 12 m sprinting. Rattling a locked door is loud too.
- **Level** (`scripts/level.gd`): the gray-box rooms are built in code, with an ASCII
  map at the top of the file. Each spirit patrols its own zone (hall, foyer, library).
  Locked doors are walls to the navmesh, and it rebakes when one is unlocked so spirits
  can follow you through.
- **Key graph** (`tools/validate_keys.tscn`): checks your plan's rule that no key is
  locked behind its own door and that the east wing can be reached. The smoke test runs
  it too.
- **Memory fragments** (`data/memory_fragments.json`): the flashback text, editable
  without touching code.
- **Placeholder audio** (`scripts/audio_gen.gd`): synthesised at startup, so the repo has
  no sound files yet.

## Tuning

Every starting value from the plan is an `@export` variable. Select the Player,
Flashlight or Spirit in `scenes/` and change it in the Inspector:

| Setting | Where | Now (plan's start value) |
|---|---|---|
| Battery life, normal / bright | Flashlight | 480 s / 30 s (300 / 20) |
| Flashlight start charge | Flashlight `battery` | 100% (plan: ~60%) |
| Battery pickups | Pickup `battery_amount` | 4 × +60% (plan: 4 × +35%) |
| Walk / sprint, stamina, refill | Player | 2.5 / 4.8 m/s, 8 s, 5 s (2.5 / 4.5, 5 s) |
| Spirit patrol / chase | Spirit | 1.2 / 2.6 m/s (1.5 / 3.2) |
| Spirit notices you after / sight range | Spirit | 0.9 s / 8 m (4 m crouched) |
| Bright beam to weaken, retreat | Spirit | 0.8 s, 10 s (1.5 s, 6 s) |
| Exposure sense / hunt | Flashlight | 15 s / 30 s (8 / 15); only spirits within 18 m hunt |
| Noise, crouch / walk / sprint | Player | 1.5 / 4 / 9 m |

**Checkpoints:** picking up a key item or unlocking a door saves progress ("Progress
saved" bottom right). When you're caught, **Retry from checkpoint** restores your position,
items and doors. Each death since the last checkpoint gives back more battery (at least 55%,
then 70%, ...). Spirits that would start right next to you are moved away. Checkpoints live
in memory for now; your plan's JSON saves come later.

Each run appends a line to `playtest_log.csv` in Godot's user folder
(`~/Library/Application Support/Godot/app_userdata/The Waking Dark/` on macOS). It
records the result, the time taken and the battery at death, which is the number the
plan says to track.

## Test and export

```sh
GODOT=~/Applications/Godot.app/Contents/MacOS/Godot

# Headless smoke test: drives every system and plays Act 1's critical path
$GODOT --headless --path . res://tests/smoke_test.tscn

# Key graph check (exits non-zero if a key is locked behind its own door)
$GODOT --headless --path . res://tools/validate_keys.tscn

# Top-down map render of the level (opens a window)
$GODOT --path . res://tools/map_preview.tscn -- /tmp/map.png

# Builds
$GODOT --headless --path . --export-release "macOS"   builds/macos/TheWakingDark.zip
$GODOT --headless --path . --export-release "Windows" builds/windows/TheWakingDark.exe
```

## The spirit's body

The spirit is a rigged, skinned model, `assets/monster/spirit.glb`. It was built in
Blender on an MPFB (MakeHuman) base: emaciated and long-armed, with a sculpted ribcage,
deep eye sockets, a jaw bone, and a painted wet grey skin. It is animated procedurally
by `scripts/monster_body.gd`, which writes each pose as "pivot" rotations (every limb
hanging straight down) and maps them onto the skeleton's bones. The Blender source is
kept with the character files (`spirit/spirit.blend`, collection `MPFB_Spirit`).
To check a change:

```sh
$GODOT --path . res://tools/monster_preview.tscn -- /tmp/shots   # full-body renders
```

The old signed-distance sculpt (`tools/bake_monster.gd`, the `.res` parts in
`assets/monster/`, `tools/head_preview.tscn`) is no longer used by the game.

The preview tools open a window, so don't cover it while they render.

## Look and characters

- **Environment art** (`scripts/level.gd`): wallpaper and floorboard textures with normal
  maps are generated at startup (`_wallpaper_texture`, `_plank_textures`). Walls get
  skirting, wainscot, chair rail and crown moulding (`_wall_trim`). Dust motes drift around
  the player. Fog, SSAO and glow are tuned in `scenes/main.tscn`.
- **Characters** (`scripts/character_rig.gd`): Daniel and Jason are the Blender models in
  `assets/models/` (`daniel.glb`, `jason.glb`). They have no baked animations, so the rig
  poses them in code with IK on the arms and legs: relaxed arms, breathing, weight
  shifts, a walk cycle, head look-at and cutscene gestures (`talk`, `calm`, `startle`,
  `show_hand`, `point`, `touch_head`, `after_you`). Jason's body is attached to the
  player (`player.gd`), so you see your legs, hands and shadow in first person. His head
  is hidden in first person and only shows in cutscenes. Preview the poses:
  `$GODOT --path . res://tools/daniel_preview.tscn -- /tmp/shots`.
- **Cutscenes** (`scripts/cutscene_director.gd`): `"style": "scene"` fragments cut to a
  third-person camera with letterbox bars. Each line in `data/memory_fragments.json` can
  set `"shot"` (wide, daniel, jason, daniel_close, jason_close, jason_right, hand, moon, door),
  gestures (`"daniel"`, `"jason"`), `"at"` (a named point to point at) and `"approach"`.
  Capture every line of the real cutscenes:
  `$GODOT --path . res://tools/cutscene_shots.tscn -- /tmp/cuts`.
- `tools/scene_shots.tscn` renders a few views of the real level.

## Repo notes

- `.godot/` and `builds/` are git-ignored.
- `.gitattributes` routes images, audio, `.glb` and `.blend` files through Git LFS.
  Install it before adding art (`brew install git-lfs && git lfs install`).
