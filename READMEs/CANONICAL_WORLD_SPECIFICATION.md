# ARCCROSS — Canonical World Specification

Authoritative narrative and setting contract for lore implementation.
Gameplay systems, UI, and content should treat this as the hidden world bible —
not as player-facing exposition.

**Chronology:** [World Timeline Codex](WORLD_TIMELINE_CODEX.md) is the
**official** era timeline. It supersedes any older era bullets or Alpha
narrative chronology in this file or elsewhere. This document owns factions,
systems, eviction framing, and design principles — not competing dates.

**Audience:** design and implementation. Players learn fragments only through
environmental storytelling, artifacts, dialogue, dreams, and ruins.

---

## Core Premise

ARCCROSS is a historical setting spanning nine numbered eras plus Pre / Primal
prehistory. The player never controls legendary historical figures. The player
always controls an ordinary Catalyst Agent whose seemingly insignificant
actions unknowingly enable a Catalyst to change history.

The game is set in **Era 9 — The Glitch**: after Era 8’s long decay,
civilization concentrated into Central; fragments of past eras appear in the
present. Chronology:
[World Timeline Codex](WORLD_TIMELINE_CODEX.md).

---

## Narrative Structure

Every era contains:

- **Catalyst** — Historical figure remembered by history.
  Example: King Baric (Era III), 7th X Delta (Eras VI–VII).
- **Catalyst Agent** — Ordinary individual. POV character. Unaware of larger
  history. Makes logical decisions that unknowingly enable the Catalyst.
- **Primal Consciousness** — Player identity. Refused The Transcendence, built
  Arccross to endure, remains after the Mist wipe of Primal Civilization.
  In play: never named; only nudges Catalyst Agents into believable choices.
  See Codex Primal / Pre sections.

---

## Hidden Lore

The complete cosmic lore is hidden from players.

Only environmental storytelling, artifacts, dialogue, dreams, and ruins reveal
fragments.

Never explicitly explain:

- Primal Civilization / The Transcendence
- Primal Consciousness as a named player identity
- Complete Core purpose
- Earth connection
- Full chronology
- True loop mechanics

Official dates and era beats:
[World Timeline Codex](WORLD_TIMELINE_CODEX.md).

---

## World Layout

Five Core regions exist:

- North
- West
- East
- South
- Central

Five is a recurring structural motif throughout civilization.

Examples:

- Five Cores
- Five-man squads
- Xander teams of five

This pattern exists naturally inside civilization.
Characters never explicitly explain it.

---

## Eras

**Authoritative chronology:** [World Timeline Codex](WORLD_TIMELINE_CODEX.md).
The pocket summary below is orientation only; do not invent era beats that
contradict the Codex.

| Era | Pocket |
| --- | --- |
| Pre / Primal | Transcendence; PC builds Arccross; Pre begins after Mist wipe |
| I | Central opens; Automations; North shares Mark |
| II | First Council; Guild logistics; Handle “liberation”; fear Arcborn |
| III | Converter bureaucracy; Northern catastrophe; Vey founds Wardens |
| IV | Dual rebuild; Patches; Baricans discover Crystal Valley |
| V | Hardened northern frontier; contracts; Man-Eater Gaps; Zeta |
| VI | Prosperous peak; SAP/Xander ideology; Delta; Passing sealed |
| VII | Scarcity wars; Delta seals Man-Eater and dies; West/East Cores fade |
| VIII | Crux last empire; narrow high tech; slow collapse into Central |
| IX | **The Glitch**; eviction; four-Core restoration in any order |

Era 9 playable framing continues in the eviction section below.

---

## Era 9 Opening Scenario — Eviction (Player Contract)

**Status:** canonical story framing for the first playable campaign arc.

The eviction is shown inside an ordinary Central administration office. A
visible civil clerk delivers the order with bureaucratic indifference; this NPC
is not The Operator. The scene establishes Central as a lived-in institution
before access is revoked and the player chooses a departure gate.
Systems that enforce Central lock / endgame return are **deferred** until the
Central and North content spine exists; see
[Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md)
(Act 1 build bible) and
[Macro World Overhaul](design/MACRO_WORLD_OVERHAUL.md) (Node Web lore).

### Situation

The Central node houses the last standing Core and its residual population.
Shelter, calories, water, and administrative slots are finite. Maximum capacity
has been reached. Immediately outside, tents, huts, displaced people, improvised
settlements, and extreme nutrient recovery from poor or dead soil make the
survival cost visible.

The player character is an ordinary resident (Catalyst Agent), not a chosen
savior. Through bureaucratic triage — insufficient resources, quota math,
paperwork — they are **selected for eviction**.

### Player consequence

- After the eviction beat, the **Central node is locked to this character**
  until the **four regional Cores are reassembled**.
- Regaining Central access is the **main endgame** reward of Core restoration,
  not a mid-act home base loop.
- Tone: institutional indifference and scarcity. Never frame eviction as a
  heroic quest briefing.

### What the player may know

- Central is overcrowded and rationing.
- Outer arms lead toward dead or sealed Core approaches.
- Restoring regional Cores is spoken of as infrastructure / survival work, not
  destiny.

### What the player must not be told

- Primal Consciousness, full Core metaphysics, Earth dreams as exposition, or
  why “five” recurs.

### Design implication

Build Central as a dense, believable population seat first (art, districts,
exploration detail). The four Route 1 arms are valid openings and the four
regional Cores may be restored in **any order**; Central remains the place you
were cast out of until all four are restored. The current alpha implements the
open Route 1 starter ring but only the North deep-content spine. That content
limitation is temporary and must not be mistaken for North-first campaign
canon. Shipping checklist:
[Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md).

---

## Civilization

Society is bureaucratic.

Technology resembles Earth industrial eras (Era 9 material culture is mostly
rotting **Era VI peak** plus scarce Era VIII carbon — see Codex tech strata).

Not fantasy.

Not high sci-fi utopia.

Jobs exist.

Paperwork exists.

Institutions dominate daily life.

Era VI peak society is prosperous and stable enough for ordinary life to be
worth mourning. Its power is distributed unevenly:

- **Central** is shared, no-owner territory. Its rotating Council/Court predates
  Guild dominance and administers Core power, standards, certification,
  bureaucracy, courts/arbitration, and shared infrastructure. Citizens come to
  work, serve, study, or administer, then return home.
- **Crux**, Merchant Guild headquarters beside the Great Sea and its barriers,
  is civilization's pinnacle and Great Exchange. Finance, logistics,
  technology, circulation, contracts, and anti-waste function as near-religious
  civic values.
- Guild influence runs deeper than Council terms through finance, logistics,
  contractors, technology, and institutions. Hundreds of Master Traders
  cooperate in Crux while competing and projecting power elsewhere.
- The **Western Coalition** controls Man-Eater minerals, steel, construction
  inputs, and heavy industry. It is brutalist but prosperous, with strong worker
  and public amenities.
- Eastern royal Houses wield culture, status, patronage, allegiance, and
  populations rather than superior technology. Arcborn may be entertainers,
  servants, athletes, retainers, workers, and prestige assets; some royal
  circles maintain lethal Arcborn sports.
- South/Guild dominates technology, Handler systems, technical institutions,
  and logistics. Northern energy extraction and much Central infrastructure are
  heavily Guild-linked.

Era IX tone: ordinary workers living through historical collapse / The Glitch.

---

## Arcborn

Mutated humans capable of Arc manipulation.

Properties:

- Taken at birth.
- Sterile.
- Raised in academies.
- Never know biological families.
- Family = academy cohort.

Society identifies Arcborn by Mark instead of personal identity.

Constitutional discrimination exists.

Arcborn experience constitutional discrimination. Respect varies by role:
Council SAP members can be publicly revered while House retainers, industrial
laborers, academy cohorts, and ordinary controlled Arcborn remain exploited.

---

## Marks

Mark = permanent specialization.

Assigned after academy.

Cannot normally change.

Power depends on:

- Arc aptitude
- Intelligence

Examples:

- SAP
- Healer
- Arc Mechanic
- Warden
- Logistics
- Other occupations

### Generic Mark

Age: 16–19

Trial period.

Final specialization determined afterward.

---

## Free Mark

Natural Mark evolution.

Associated with **Crystal Valley** (discovered and settled by Baricans late Era
IV; extraction keystone from Era V onward; see Codex).

Allows owner to shape their own specialization.

Knell's Handle-control empire views Free Mark as an existential threat. The
Merchant Guild is not politically unified; some Master Traders are already
preparing for a possible post-Handle economy.

---

## Handler

Human-operated control device.

**First working Handle:** Era II South (Codex). Later ages turn it into
institutional Handler Units (Era III+).

Interfaces directly with Mark.

Allows governments to control Arcborn.

Destroying a Handler normally kills its owner.

Delta survives destroying his own (Era VII).

---

## Xander Program

Nine teams fielded at Era VI peak. Xander is not mecha in Era VI: it is the
pinnacle and poster-child of Handle ideology, pushing high-affinity Arcborn to
extreme performance through Handler technology. The public celebrates these
super-units as war-ending forces, while deployment remains politically
controlled and powerful interests may prefer conflicts unresolved. Later Era
VII/VIII mecha evolution is reserved for future expansion.

| Teams | Region |
| --- | --- |
| 1st X, 2nd X | Central |
| 3rd X, 4th X | East |
| 5th X, 6th X | West |
| 7th X, 8th X | South |
| 9th X | Contingency / later crisis use |

Each X team contains five high-affinity Arcborn:

| Callsign | Role |
| --- | --- |
| Alpha | Primary offense |
| Beta | Defense |
| Charlie | Support |
| Delta | Specialist |
| Echo | Recon |

---

## 7th X Delta

Officially present on public Xander rosters and trading cards with a generic,
boring, low-interest profile. That obscurity is camouflage, not nonexistence.

Knell alone effectively knows Delta's erased history and real experiment: an
adaptive, changeable Mark. Delta eliminated witnesses to his creation/program,
leaving his origin inaccessible even to most Guild authorities.

### Era VI — Northern mission (Codex end of Era VI)

Knell descends from the lineage/business that developed the first Handle. His
commercial empire depends on Arcborn/Handler control technology, and Barican
Free Mark is its antithesis. He assigns Delta to **deny Barican legitimacy**,
not to destroy Crystal Valley.

Mission shape (interior chapters may expand later):

- Break arrangements that could legitimize Barican sovereignty
- Preserve Knell's Handle-centered market against Free Mark
- Conduct Crystal Valley / northern operations as required to that end

**Outcome:** An unintended collateral cascade tears **huge Gaps** across the
North and releases massive **Craven** hordes. Humanity **reseals The Passing**.
Knell wanted Barican illegitimacy, not the loss of Crystal Valley or northern
Arc-snow access.

### Era VII — Aftermath and Western end (Codex Era VII)

North Arc-snow access is gone and scarcity destabilizes civilization. Delta
returns with Free Mark knowledge and a regained personal identity.

- Initial goal: kill Knell and find a safe way to break Handles for other
  Arcborn.
- Develops or helps spread safe Handle removal.
- After confronting his past, stops using his Mark to intentionally harm and
  shifts toward helping and liberating others.
- Does not become a long-lived revolutionary messiah.

Western campaign:

- Gap and Craven pressure inside Man-Eater risks spilling across Arccross.
- Delta uses his adaptive Mark and the **Western Core** to focus a massive Core
  release successfully, sealing Man-Eater without the extreme continental
  terraforming caused by the failed Era III Northern focus.
- Western Core power fades afterward.
- Delta dies mid Era VII and remains buried beneath the collapsed mountain.
  Keep him dead.

---

## King Baric

**Era III** Northern ruler (Codex).

Refuses Core-grid cooperation; Central marches north.

Dies in the Northern Core catastrophe that terraforms the North. Central
deliberately collapses the Passing to contain the expanding storm.

The **Barican movement** forms during Era IV and takes his name as a political
symbol, not a literal continuation of his reign. Its near-suicidal crossing of
No Man's Land discovers and settles Crystal Valley late in Era IV.

Philosophy the Baricans inherit:

- Arcborn treated as sacred / not livestock
- Rejects Handler system
- Northern sovereignty and rejection of Central/Guild imposed authority
- Free Mark as the alternative to Handle control

---

## Merchant Guild

True long-game power through logistics and bureaucracy, but not a unified
political actor. Hundreds of Master Traders share Crux while competing through
regional projects and proxies.

**Era II:** first roots; enables logistics; profits from East–West war; invents
Handle path.  
**Era III–V:** favor politics, puppets, transit and extraction contracts,
conditional recognition, proxy interests, and manipulated raids.
**Era VI:** deep institutional influence without owning Central; Knell and his
cohorts remain a secret commercial cabal, not rulers of the whole Guild.
**Era VIII:** Crux/South forms the last empire beside still-surviving Central;
its defenses eventually fail.
Destroyed by collapse rather than conquest.

---

## Regions

Dialect and history summaries for art/systems. Dates defer to Codex.

### North

Era III catastrophe → arctic Patches and No Man's Land; Central collapses the
Passing. Vey's Wardens connect survivors. Baricans cross the blizzard and settle
**Crystal Valley** late Era IV. Era V hardened routes enable extraction. Era VI
Passing seals after Delta's unintended cascade. Era IX ruins resolve into
Warden/Barican/frontier history when stabilized.

### West

Western Coalition: minerals, steel, construction inputs, and heavy industry;
brutalist prosperity with worker/public amenities. Man-Eater Mountain consumes
Arcborn labor. Era V Gaps → **Zeta Corps**. Era VII Core power fades after Delta
seals the mountain and dies.

### East

Royal Houses govern through patronage, culture, status, allegiance, and
populations. Arcborn serve many controlled social roles and as prestige assets;
lethal sports exist in some circles. East is not the superior technology/
academy region. Fragmented wars and Red Mist pressure collapse East; its Core
is lost or fades by Era VII's end.

### South

Guild and Handle origin; technology, logistics, and technical-institution
center. Crux becomes Era VIII's advanced last empire before Red Mist consumes
South.

### Central

Shared no-owner administrative seat governed by rotating Council/Court. Era IX
overcrowded remnant after inward flight; eviction origin and only remaining
functioning civil Core seat.

---

## Wardens

**Origin (Codex):** Human warden/Handler **Orin Vey** gathers mixed survivors by
the collapsed Passing after the Era III catastrophe. After the Coldest Night he
organizes routes, shelters, communication, and survival across scattered
Patches. Wardens evolve from that connective function.

Wardens own northern navigation, frontier security, and the infrastructure that
makes passage through No Man's Land possible. North remains outside SAP
jurisdiction.

Rarely return.

Story focus: **Warden Unit 17** (Era VI Catalyst beat; interior TBD).

---

## SAP

**SAP = Special Arcborn Platoon.** Central Council-controlled elite Arcborn
peacekeepers paired with Handler Units.

- Jurisdiction: Central, East, West, and South. North is an explicit no-go;
  Wardens own frontier/navigation/security there.
- Mission: rescue, containment, civil protection, peacekeeping, and
  extraordinary Arc incidents. SAP does not fight wars or conduct campaigns
  against terror sects; human armies handle organized military threats.
- Public status: socially revered as the **shield of mankind**. Their prestige
  is used ideologically to normalize Handle technology.
- Strategic limit: Arcborn are a small percentage of humanity, so human armies
  dominate war numerically and attrition still matters.

Political violence remains fragmented into Eastern, Western, Southern, and
other local sects/cells. There is no unified **Severant** organization. Some
Southern anti-Arcborn cells are covertly funded by Knell-aligned Master Traders
to increase fear and justify Handler/security spending.

---

## Zetans / Zeta Corps

**Zeta Corps** founded end of Era V to combat Cravens after Man-Eater Gaps
(Codex).

Western mining / anti-Craven organization.

Failed academy graduates and Western Arcborn often assigned to Man-Eater —
disposable depth labor in doctrine and proverb.

Death-sentence reputation.

### Zetan Squad Doctrine

Standard size: 5

Composition:

- 1 Arc Cell Bearer
- 4 Operators

All members tethered together.

Arc Cell powers: lights, communications, sensors, equipment.

Light equals survival.

Darkness is avoided.

Never separate from tether.

Saying (Codex / lore): *Feed the mountain men and you will get things to
destroy more men.*

---

## Man-Eater Mountain

Largest mineral deposit.

Foundation of Western industry.

Immense cave system. Depth unknown.

Era V: Gaps discovered here — humanity realizes the crisis is not only
northern.

Era VII: sealed when Delta focuses the Western Core release and dies beneath the
collapse.

---

## Earth Dreams

Catalyst Agents repeatedly dream completely mundane Earth lives.

Examples: office worker, farmer, dog owner.

Dreams are never explained.

Purpose: emotional contrast. Ordinary life becomes mythical.

Classified backdrop (Codex): Transcendence / Earth-familiar residue — never UI
exposition. Hidden ending canon: a restored Central system aims a beam toward
Earth, reveals the Blue Marble, then approaches a generic silhouette using the
same device category as the actual player (PC, console, or phone). Never use a
webcam or player likeness.

The title begins as **ARCCROSS**. After the ending a comma appears:
**ARCCROSS,**. Its eight letters represent the eight historical civilization
eras; the comma represents Era IX, the game/player transition, and continuation
of the loop. It is not a final period. Do not overexplain this player-facing.

---

## Non-linear Core Campaign

- Restore North, East, West, and South Cores in **any order**. Central remains
  locked until all four are restored.
- Starting Arm landscapes may read as ambiguous, corrupted generic
  post-apocalypse because Glitch and failed barriers obscure history.
- Core activation is not time travel and does not restore pristine history. It
  stabilizes the Arm into its authentic ruin dialect: Warden/Barican, House,
  Western industrial/Zeta, or Guild/Crux/Xander remnants become legible.
- Meta progression may permanently change Red Mist, barrier state, and world
  presentation.

Each restored Core introduces a major simulation layer:

| Core | Layer | Examples |
| --- | --- | --- |
| North | Network / Logistics | Routes, Warden relays, caravans, navigation, settlement connection |
| East | People / Community / Identity | Relationships, recruitment, factions, training, Arcborn/social systems |
| West | Industry / Fabrication | Workshops, refinement, production, crafting, construction |
| South | Economy / Commerce | Trade, contracts, pricing, credit, merchant organizations, specialization |

Pair directions:

| Combination | Emergent system |
| --- | --- |
| North + West | Supply chains |
| North + East | Migration and social networks |
| North + South | Trade routes |
| East + West | Professions and skilled production |
| East + South | Organizations, employment, and faction economy |
| West + South | Mass production and commodity economy |

Triple combinations create larger settlement/civilization systems. All four
produce a civilization-level phase change and open Central re-entry/Core
convergence. Exact mechanics remain design direction until implemented.

---

## Tone

Never portray protagonists as heroes.

They are workers.

Examples: Warden, Navigator, Zetan, Mechanic, Clerk.

History remembers Catalysts.

Story follows Catalyst Agents.

Era 9 tone: bureaucracy refusing apocalypse; Glitch fragments without
lectures.

---

## Design Principles

Always prioritize:

- institution
- routine
- bureaucracy
- equipment
- daily life
- environmental storytelling

Avoid:

- chosen one narrative
- exposition dumps
- cosmic explanations

Player should experience history from ground level.

---

## Cross-links

- **Official chronology:**
  [World Timeline Codex](WORLD_TIMELINE_CODEX.md)
- Campaign implementation bible:
  [Central Core Campaign Overhaul](design/CENTRAL_CORE_CAMPAIGN_OVERHAUL.md)
- Campaign / zone shipping lore:
  [Macro World Overhaul](design/MACRO_WORLD_OVERHAUL.md)
- Hex visual generation language:
  [Hex Dressing Templates](design/HEX_DRESSING_TEMPLATES.md)
- Graph and persistence ownership:
  [System Architecture](SYSTEM_ARCHITECTURE.md) (Directional Node Web)
