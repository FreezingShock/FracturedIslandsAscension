# FX Guide

How ability effects are designed, built and checked in Fractured Islands. Read this before you design or change any effect.
The code lives in `src/Client/Combat/AbilityController.client.lua` (builders) and the numbers in
`src/Shared/Modules/Combat/AbilityConfig.lua` (`AbilityConfig.fx`, `AbilityConfig.sounds`, `AbilityConfig.fxLimits`).

## 1. Principles

These are the rules every effect has to pass. They come from the references in section 9, applied to this game.

1. **Readability first.** An effect is the brightest thing on screen for half a second, so it must say what the ability
   does. Shape carries the mechanic: a circle means area, a line means a projectile, a ring means a shockwave, a column
   means a strike from above. Colour carries the element. Scale and brightness carry the power.
2. **The effect belongs to the ability.** Ask what the ability is in the fiction (a storm, a judgement, a blink, a frozen
   field) and build from that. Overload is embers falling on you, not a generic ring.
3. **Every effect has a timeline.** Anticipation (cast), impact (the hit frame), sustain (the zone or line while it lasts),
   and resolve (fade and linger). Each part has its own layers. A zone with no impact flash feels mushy; an impact with no
   sustain feels cheap.
4. **Never one fill.** An effect is at least three visuals from different families: a body (disc, slab, ring), a detail
   (rune ring, cracks, shards), and motion (particles, sparks). A single flat disc is a bug, not a design.
5. **Everything moves.** Nothing is static for its whole life. Use easing (section 4). Shockwaves race out (`outCubic`),
   growths overshoot (`outBack`), drops accelerate (`inCubic`). Linear motion looks like a placeholder.
6. **Residue.** Anything that travels through space leaves something behind for 1 to 3 seconds: a trail, a scorch, a
   fading slab. Gale Lance's cut is the reference: it hangs in the air after the lance is gone.
7. **Colour rules.**
   - Use at least two colours per effect: a core and an edge, or a body and a spark.
   - With `LightEmission = 1` (additive), dark colours turn invisible. Use dark colours only with `LightEmission` near 0
     (smoke, shadows, scorch).
   - Element palettes: fire orange to deep red; frost cyan to white; lightning blue-white; holy gold to white; poison lime
     to purple; wind pale cyan; earth brown to ochre with a hot orange crack.
8. **Sync to the game.** Repeating zones pulse on their tick (`every = tickInterval`). Chain strikes flash on each target
   point. Cast and impact timing comes from `hitFrame`, `castTime` and `delay`, so the visual matches the damage.
9. **Ground vs body.** Ground layers sit on the floor (`anchor - FEET`). Body layers sit at the caster's centre. Set
   `height` and `lift` deliberately; a disc at body height is a bug.
10. **Light sparingly.** At most one spotlight per effect. Flicker only on sustained effects, never on a one-shot.
11. **Budget.** A cast uses about 10 to 30 parts and at most 3 to 4 emitters. Limits live in `AbilityConfig.fxLimits`.
    Past the cap a layer is skipped, so a busy fight looks thinner, not broken. Do not raise the caps without a reason.
12. **Configure, do not hard-code.** Colours, counts, timings and easings go in `AbilityConfig.fx`. Builders take their
    numbers from the spec. Add a builder only when no existing kind can express the idea.

## 2. Anatomy of a layer

A layer is one entry in `layers`. Every entry has a `kind` (the builder) and the numbers that builder reads.

Shared fields, read by most builders:

| field | meaning |
|---|---|
| `kind` | which builder draws it (section 3) |
| `color` / `colors` | one colour, or a list spread evenly around the element (`colors` alternates on glyphs, gradients on particles) |
| `scale` | multiplies the ability's shape radius (`shape.radius`, `reach` or `length`) |
| `radius` | absolute studs. Overrides `scale`. Use it for small effects on big abilities (Gale's impact ring) |
| `delay` | seconds after the cast before the layer starts |
| `time` | how long the layer's motion takes (shockwave growth, fade, bolt hold) |
| `height` / `lift` | offset above the anchor (`height`, for body effects) or above the floor (`lift`, for ground effects) |
| `at` | `"end"` puts the layer at the end of a line (the lance tip, the dash destination) |
| `ease` | easing name (section 4) |

Timing reference: a layer with `delay` and `time` keeps its handle alive until `delay + time`. A zone keeps the handle for
the zone's duration. Anything that ends before that is faded out and returned to the pool after `LINGER` (2.5 s).

## 3. Layer kinds

Current builders. Each lists its fields and what it is for.

| kind | draws | key fields | use it for |
|---|---|---|---|
| `disc` | flat cylinder on the floor, breathes | `color`, `transparency`, `pulse`, `pulseAmount`, `material` (`ForceField` default) | a ground body: a scorch, a frozen field, an electric pool |
| `glyph` | ring of short neon runes that turn, each shimmering | `colors`, `count`, `length`, `width`, `spin` (deg/s, sign = direction), `radius`, `time` | magic circles, halos, impact runes |
| `spot` | spotlight from above, pointing down | `color`, `range`, `angle`, `brightness`, `flicker`, `height` | the light of an effect; use one per effect |
| `motes` | box emitter that drifts over the area | `colors`, `rate`, `lifetime`, `speed`, `size`, `direction`, `spread`, `acceleration`, `drag`, `texture`, `lightEmission`, `height` | sparkles rising, embers falling, spores, snow, mist |
| `burst` | one puff, fired once after `delay` | `colors`, `count`, `speed`, `lifetime`, `size`, `spread`, `acceleration`, `texture`, `lightEmission` | a cast pop, debris dust, impact sparks |
| `shock` | ring on the floor that races out, then fades | `color`, `time`, `scale`/`radius`, `height` (thickness) | a single shockwave |
| `pulse` | the same ring, repeating every `every` seconds | `every`, `time`, `ease`, `lift` | a zone's tick pulse |
| `cracks` | straight ground cracks from the impact | `color`, `count`, `width`, `time`, `delay` | the ground splitting |
| `rays` | fan of bars; can tilt up and turn | `colors`, `count`, `tilt` (deg), `spin` (deg/s), `lift`, `width`, `time`, `ease` | holy rays, frost cracks, ground fissures with a lift |
| `pillar` | column from the floor; `descend` drops it from the sky | `color`, `height`, `width`, `time`, `ease`, `descend` | a strike from above, a thunder column, a judgement beam |
| `orb` | glowing ball with a halo; grows or `shrink`s | `color`, `glowColor`, `size`, `time`, `ease`, `shrink`, `perPoint`, `at` | a blink flash, a chain's strike points |
| `shards` | crystal spikes in a ring, grow with overshoot, can turn | `colors`, `count`, `height`, `width`, `time`, `spin`, `material` (`Glass`) | frost, ice, crystal walls |
| `debris` | chunks thrown on arcs, gravity, spin, land and fade | `colors`, `count`, `size`, `speed`, `up`, `gravity`, `flight`, `material` (`Slate`) | rock, shrapnel, shattered ground |
| `beam` | straight neon bolt, static | `color`, `glowColor`, `width`, `glowWidth`, `glowTransparency`, `time` | a line that is already there (legacy-style) |
| `bolt` | straight neon bolt that grows along the path | as `beam`, plus `grow` (s) and `ease` | a projectile's visible path, with a tween |
| `streaks` | emitter that rides the line and blows backwards | `colors`, `rate`, `lifetime`, `speed`, `time`, `spread` | wind, a lance's trail |
| `trail` | slabs along the path that appear as the front passes and fade | `color`, `count`, `width`, `height`, `time`, `fade`, `material` | residue, afterimages |
| `lightning` | jagged bolts, re-rolled every `refresh` seconds | `color`, `segments`, `jitter`, `width`, `time`, `refresh`, `arcs` (random arcs) or chain points | chain lightning, thunder arcs |

Legacy kinds (`nova`, `zone`, `frost`, `dash`, `chain`) still exist in `AbilityController` but no ability uses them now.
Do not add new uses. They go in a later cleanup.

## 4. Motion and easing

Every moving layer takes `ease`. Names live in `AbilityController` (`EASE`):

| name | shape | use it for |
|---|---|---|
| `outCubic` (default) | fast start, slow end | shockwaves, bolts reaching a target, things settling |
| `outQuad` | softer version of outCubic | pulses and tick rings |
| `outBack` | overshoots, then settles | growth that should feel like it pops (rune rings, spikes, orbs) |
| `inCubic` | starts slow, accelerates | drops, implosions, anything falling |
| `inOutSine` | smooth both ends | slow breathing motion |
| `linear` | constant | almost never; only for timers |

Rule of thumb for "satisfying": the impact frame has the fastest motion, the sustain is slow and breathing, and the fade is
long enough to read (0.3 to 0.6 s). Lerp positions between points; do not teleport a part from one place to another.

## 5. Ability design sheets

Each sheet gives the fiction, the timeline and the layer stack. Numbers match `AbilityConfig.fx`. When you change an
ability, update its sheet here too.

### Venomfang: Venom Cloud (`X`, zone 8 s, pinned, tick 2 s)
- **Fiction:** a cloud of venom that lingers where it lands and burns whatever is inside it.
- **Shape language:** circle on the floor (the area), spores falling from above, glyph rings (magic, poison).
- **Timeline:**
  - Cast (0 s): a burst of lime sparkles pops upward.
  - Sustain (0.3 s onward): two rune rings turn in opposite directions, the disc breathes, sparkles rise, spores fall.
  - Resolve (8 s): everything fades over 0.35 s and lingers for 2.5 s.
- **Stack:** scorch disc (dark green) + inner glow disc (lime) + outer rune ring (lime to yellow-green) + inner rune ring
  (purple) + outer hairline rim (green) + cast burst + spot (flickering) + rising sparkles (yellow to green to dark green)
  + falling spores (purple to green, `LightEmission` kept at 1 so the purple stays visible).
- **Why it works:** the bright rune ring marks the area, the spores show what the cloud does (they fall), the spot ties
  the effect to the ground. Flagged by playtest as good; keep this structure.

### Earthshatter (`RMB`, one hit at 0.6 s, knockback 60)
- **Fiction:** a heavy slam that splits the ground and throws it up.
- **Shape language:** circle (the impact), radial cracks (the ground breaking), debris on arcs (the weight), dust (the cost).
- **Timeline:**
  - Anticipation (0 s): hot cracks and fissures start.
  - Impact (0.02 s): the first shockwave races out, debris launches, dust puffs.
  - Settle (0.1 s): a second, smaller, slower shockwave; sparks; the spot flashes.
  - Resolve: debris lands and fades over about 2 s, dust drifts up over 2 s.
- **Stack:** shock 1 (warm gold) + shock 2 (burnt orange, delayed) + cracks (orange) + ground fissures (`rays`, gold) +
  debris (slate: browns and ochre, gravity 38) + dust (smoke texture, rising) + sparks (gold-white) + spot.
- **Note:** this was flat before, and the debris, dust and fissures are the added depth. Confirm in playtest.

### Gale Lance (`V`, line 30 studs, 4 s cooldown)
- **Fiction:** a thrown spear that cuts through the air and leaves a wind cut behind.
- **Shape language:** line (the projectile), streaks (the wind), residue (the cut), impact ring and rune (the tip).
- **Timeline:**
  - Launch (0 s): the bolt grows from the caster to the tip (`outCubic`, 0.15 s), streaks ride with it.
  - Residue (0 to 2.4 s): the cut slabs appear as the front passes them and fade slowly.
  - Impact (0.28 s, at the tip): an impact ring (`shock`, 3 studs), a rune ring, and a sparkle burst.
- **Stack:** residue trail (pale cyan) + grow bolt (white core, cyan glow) + streaks (white to blue) + tip rune ring +
  tip shock + tip burst.
- **Note:** the playtest said it looked good and should leave more residue and feel more tweened. The residue and the
  eased growth are the answer.

### Holy Nova (`Z`, radius 18, knockback 40)
- **Fiction:** a judgement from above: a column of light drops, then the light breaks out in a ring.
- **Shape language:** column (the drop), ring (the release), rays (the radiance), halo (the holiness).
- **Timeline:**
  - Anticipation (0 to 0.25 s): the light column drops from 18 studs with `inCubic` (it accelerates like a falling sword).
  - Impact (0.2 s): two shockwaves (gold, then white), the rays fan out tilted 12 degrees up and turning at 40 deg/s.
  - Sustain (0.2 to 0.8 s): a halo of runes turns above the caster; a burst of white and gold sparkles.
  - Resolve: the spot fades with the handle.
- **Stack:** descending pillar (warm white) + shock (gold) + shock (white, delayed) + rays (gold/white, tilted, turning) +
  halo runes (gold/white, 4.5 studs up) + burst (white/gold) + spot (gold).

### Overload (`RMB`, zone 9 s, follows the caster, radius 50, tick 3 s)
- **Fiction:** you call an embers storm down on the area around you.
- **Shape language:** large circle (the area), falling embers (the storm), rising flames (the heat), pulses on each tick.
- **Timeline:**
  - Cast (0 to 0.45 s): a fire column rises from the ground, a burst of embers blows out.
  - Sustain (0.45 s to 9 s): a scorch disc breathes, two rune rings turn, flames rise from the floor, embers fall across
    the whole area, a ring pulses every 3 seconds in time with the damage tick.
  - Resolve: fade and linger.
- **Stack:** rising fire column (orange) + cast embers burst (yellow, orange, red; fire texture) + scorch disc (dark red)
  + inner glow disc (orange) + outer rune ring (orange) + inner rune ring (yellow) + tick pulse (orange) + falling embers
  (yellow to red) + rising flames (fire texture) + spot (warm).

### Blink Dash (`RMB`, line 22 studs, 5 s cooldown)
- **Fiction:** you snap through the space in front of you, leaving afterimages.
- **Shape language:** line (the dash), afterimages (the path you took), flash (the start and end points).
- **Timeline:**
  - Start (0 s): the bright orb implodes into the caster (0.2 s).
  - Dash (0 to 0.25 s): the bolt shoots forward (0.12 s grow), afterimages appear as the front passes them and fade over
    0.45 s, streaks blow backwards.
  - End (0.3 s): an orb blooms at the destination, sparks burst.
- **Stack:** afterimage trail (pale gold, upright slabs) + imploding orb (cream, gold glow) + grow bolt (cream core, gold
  glow) + streaks (cream to gold) + destination orb (cream, gold glow) + destination burst.

### Chain Lightning (`RMB`, chain of 4 jumps, 7 s cooldown)
- **Fiction:** a bolt that jumps from target to target, crackling.
- **Shape language:** jagged line (the lightning), flash at each target (the strike), sparks at the caster (the start).
- **Timeline:**
  - Start (0 s): spot and spark burst at the caster.
  - Strike (0.25 s, from the server's points): the lightning links the caster to each target and re-rolls its shape every
    0.05 s, fading over 0.3 s. A flash orb pops at each point and shrinks.
- **Stack:** spot (blue-white) + spark burst (white to blue) + jagged lightning (pale blue, 5 segments, re-rolled) + flash
  orb per point (pale blue, blue glow).

### Thunder Clap (`Z`, radius 14, slow and burn, 9 s cooldown)
- **Fiction:** a thunderclap that shocks everything around you, with arcs crackling out.
- **Shape language:** rings (the sound wave), column (the strike), arcs (the electricity), electric pool (the field).
- **Timeline:**
  - Impact (0 s): a fast white-blue shockwave, a second slower one at 0.06 s, a short column rises (0.2 s).
  - Arcs (0.02 s): seven random arcs out of the caster, re-rolled every 0.04 s, fade over 0.35 s.
  - Resolve: an electric pool breathes for 0.5 s, sparks burst upward and fall with gravity.
- **Stack:** shock (white-blue) + shock (blue, delayed) + column (white-blue) + random lightning arcs (white) + electric
  pool (blue, ForceField) + spark burst (white and blue, falling) + spot (blue-white).

### Frost Nova (`RMB`, zone 6 s, pinned, radius 20, tick 1.5 s, slows)
- **Fiction:** a freezing field that stays where you cast it, with frost spreading out and snow falling.
- **Shape language:** circle (the field), spikes (the frost wall), cracks (the ice spreading), pulses (the cold tick),
  snow and mist (the atmosphere).
- **Timeline:**
  - Cast (0 to 0.6 s): spikes grow up out of the ground with overshoot, cracks spread across the floor.
  - Sustain (6 s): the field breathes, spikes turn slowly, a cold pulse goes out every 1.5 s, snow falls, low mist drifts.
  - Resolve: fade and linger.
- **Stack:** field disc (cyan, ForceField) + inner field disc (white) + frost cracks (white-cyan) + frost spikes (cyan to
  white, glass, turning) + cold pulse ring (pale cyan) + snow motes (white to ice blue, falling) + mist (smoke texture,
  low) + spot (cyan).

## 6. Process

1. **Brief.** Write the fiction, the shape language and the timeline (section 5) before you touch code.
2. **Greybox.** Use one or two layers for the timing (a ring and a spot). Check the rhythm first, the way Sunstrike
   recommends: anticipation, impact, fade.
3. **Dress it.** Add the detail layers (runes, cracks, debris), then the motion (streaks, residue), then the sparks.
4. **Check the stack** against the rules (section 1). Count the colour families, the parts and the emitters.
5. **Playtest.** Use `/fia-verify`, cast the ability, capture from third person (about 12 studs up, 22 back), and at about
   60 studs. Check the impact frame lands with the damage, and the effect clears before the next cast.
6. **Update this guide** if the ability's fiction, timeline or stack changed.

## 7. Checklist

- [ ] The fiction is in the design sheet, and the effect reads as that fiction at a glance.
- [ ] At least three colour families or visuals (body, detail, motion).
- [ ] Every moving layer has an `ease` other than `linear`.
- [ ] Residue for anything that travels, lasting 1 to 3 seconds.
- [ ] Dark colours are used only with `LightEmission` near 0.
- [ ] Repeating effects sync to their tick (`every`).
- [ ] At most one `spot`; flicker only on sustained effects.
- [ ] A cast stays under about 30 parts and 4 emitters.
- [ ] All numbers are in `AbilityConfig.fx`.
- [ ] `AbilityConfig.sounds` has an entry for the cast sound (silent until a real id is uploaded).
- [ ] Playtest: no new errors in the log, and the effect clears after its duration.

## 8. Known gaps

- **Weapon-only abilities have no FX.** Magic Missile and Mana Shield (Apprentice Staff) and Pierce Shot (Wooden Bow) are
  not in `AbilityConfig`, so they have no effect. Move them into the library to give them one.
- **Sounds are silent.** Every `sound` id is `""` until a real sound is uploaded.
- **Legacy kinds remain in code** (section 3). Remove them in a cleanup pass.
- **ForceField and Glass rendering** were chosen by reading, not yet verified in every lighting setup. Check in playtest.

## 9. References

Used for the principles above. Only the parts marked as read were checked in full.

- **Sunstrike Studios, "VFX for Games: How Studios Build and Outsource Effects" (2026).** Read in full. Source of: readability
  under gameplay, timing tied to game feel, style match, and the pipeline of brief, timing greybox, look development.
- **Riot Games, "So You Wanna Make Games?? Episode 7: Game VFX".** Read the chapter list only. Topics: gameplay
  communication, shape language, colour in effects, timing and energy. Watch it for the full reasoning.
- **Game Design Skills, "VFX in Games: Meaning, Artist, Examples".** Read in full. Source of: design around purpose, not
  nature; response and feedback effects; examples of residue and weapon trails (God of War's ice trail, Ziggs' ground
  circle, Street Fighter's hit sparks, Final Fantasy XVI's elemental lightning).
- **Roblox Creator Hub, ParticleEmitter reference.** Read in full. Source of: `LightEmission` as additive blending,
  darker colours becoming transparent with `LightEmission > 0`, `Emit` for one-shot bursts, `Drag` and `Acceleration`,
  `EmissionDirection` and `ZOffset`, and the advice to use a `PointLight` for light that actually lights the scene.
- **TrendyV2, "ROBLOX VFX Guide #1: Particles" and "#2: Trails & Beams".** Chapter lists only (tween, particles, emitter
  properties, fire effect; trails and beams). Watch for the Roblox-specific workflow.

The rules in section 1 are our synthesis of these sources for this game. Where a rule is a judgement call (for example
the colour families, the part budget), it is ours, and playtest decides.
