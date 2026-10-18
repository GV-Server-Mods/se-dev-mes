# Dialogue Banks, Chat Profiles & Chatter Triggers Reference

How NPC chat actually runs: dialogue banks, the shared chat profile behind them, chance rolls, tokens, broadcast range, and the trigger patterns that drive "radio chatter". Everything here is generic: any number marked **[SOFT]** is an illustrative starting point to tune per server, not a rule.

**Classification**: **[HARD]** = read in the MES source (paths under `Data/Scripts/ModularEncountersSystems/`, MES `b8f86a2` / 2.74.06 dev, rechecked for the target-edge and recipient-filter items against `bc71965` (master after 2.75.01); line numbers drift between builds, so search by function name if a line is off). **[SOFT]** = inferred, a design recommendation, or not yet measured in play. Each item says what it "Fails as" so it can be used as a pitfall line.

---

## 1. The Dialogue Pipeline

```text
Behavior : [DialogueBanks:MyBank]                      (one tag line per bank)
Action   : [PlayDialogueCue:true] [DialogueCueId:Attacked]
Bank file: <mod>/Data/DialogueBanks/MyBank             (XML, not an .sbc profile)
```

```xml
<DialogueBank>
  <ChatProfileId>ModPrefix-Chat-Radio</ChatProfileId>      <!-- a registered [RivalAI Chat] profile -->
  <DialogueCue>
    <DialogueCueId>Attacked</DialogueCueId>
    <Entries>                                               <!-- first matching <Entries> block wins -->
      <EventConditionId>ModPrefix-EventCondition-SomeState</EventConditionId>
      <Entry><Message>Taking fire!</Message><AudioId></AudioId><Weights>1</Weights></Entry>
    </Entries>
    <Entries>                                               <!-- no EventConditionId = fallback; list it last -->
      <Entry><Message>Contact.</Message><AudioId></AudioId><Weights>1</Weights></Entry>
    </Entries>
  </DialogueCue>
</DialogueBank>
```

- **[HARD] Loading**: `ProfileManager.GetDialogueBank` reads `Data\DialogueBanks\{name}` from the first loaded mod that has the file (the tag value is the literal file name, extension included) and caches the bank by name.
- **[HARD] One bank per grid**: `CoreBehavior.cs` (`Beginning DialogueBank setup`) picks one of the behavior's listed banks at random and keeps it for the grid's life.
- **[HARD] Entry choice**: `DialogueBank.GetChatProfile` walks the cue's `<Entries>` blocks in order and uses the first whose `<EventConditionId>` is empty or a currently-true `[MES Event Condition]`; then picks one `<Entry>` by `<Weights>`.
- **[HARD] Everything fails silent in play.** The only trace is one game-log line at load:
  - Missing bank file: `Could Not Add DialogueBank To Behavior: [name]` (`TriggerSystem.cs`, `[DialogueBanks:` parse). The behavior keeps an empty bank, so every cue does nothing.
  - Unknown `<ChatProfileId>`: `Chat Profile Not Registered in Profile Manager: [id]` (`DialogueBank.init`). `GetChatProfile` then returns false for every cue.
  - Unknown cue id, no `<Entries>` block that passes, or an `<EventConditionId>` that isn't registered (that block is skipped): no broadcast, no log.
  - Audit: `audit_mes_references.ps1` checks the bank file and chat profile; `audit_mes_tags.ps1` checks the chat profile settings (section 2).

---

## 2. Dialogue Banks Share One Chat Profile

- **[HARD] A bank's chat profile is one shared object.** `ProfileManager.GetDialogueBank` caches each bank by name, `DialogueBank.init()` builds one `_chatProfile` per bank, and `GetChatProfile` hands that same object to `ActionSystem.cs` (`PlayDialogueCue` → `_broadcast.BroadcastRequest`). State on the profile is shared by every grid using that bank file, server-wide.
- **[HARD] `[MaxChats:]` becomes a server-wide lifetime cap.** `ChatProfile.ProcessChat`: `ChatSentCount >= MaxChats` sets `UseChat = false` on the shared copy. **Fails as**: the first grids to speak use up the voice for everyone until restart. Never set it on a bank's chat profile (default `-1` is fine).
- **[HARD] `[MinTime:]`/`[MaxTime:]` is a shared timer.** `ProcessChat` drops a line while `SecondsUntilChat` hasn't elapsed (`Chat Timer Not Ready`, not queued) and rerolls the window after each send. **Fails as**: a long window silences the whole voice. The defaults (`MinTime 0`, `MaxTime 1`) mean no wait. Also: `ChatProfile.InitTags` lowers `MinTime` to `MaxTime` when it is larger, and the default `MaxTime` is `1`, so `[MinTime:30]` alone gives a 1 s window with no error; set both (`audit_mes_tags.ps1` check 18). The window is `Rnd.Next(MinTime, MaxTime)`, which excludes `MaxTime`: `[MinTime:30]` + `[MaxTime:60]` waits 30-59 s.
- **[SOFT] A short shared timer works as a squad throttle.** A window of a few seconds allows one line per bank however many grids react to the same event (for example a squad acquiring one target). Tune to squad size, grids per bank and desired chattiness. Trade-off: a rare, important line is dropped if another grid on the bank spoke just before.
- **[HARD] The first grid's custom author name sticks.** `BroadcastSystem.BroadcastRequest` sets `chat.CheckForCustomNames = true` once and copies `Npc.ChatAuthorName` (from a manipulation's `[CustomChatAuthorName:]`) into the shared `chat.Author`. **Fails as**: every later grid on that bank uses the first grid's name. Leave `[CustomChatAuthorName:]` off grids whose behavior has a bank.
- **[HARD] The bank is per behavior and cannot use `{Faction}`.** `[DialogueBanks:]` is read as a literal file name. **Fails as**: a behavior shared by several factions' spawn groups speaks one voice for all of them. Make one behavior copy per faction.
- **[HARD] Chance and range live on the chat profile**, and a bank names exactly one `<ChatProfileId>`, so chance and range are per bank file. **[SOFT]** Generate tiered bank files (for example one per chat range) from one source draft instead of duplicating lines by hand.
- **[HARD] Same-line suppression is per grid.** `LastChatMessageSent` lives on each grid's `BroadcastSystem`; one grid never repeats its previous line unless `[AllowDuplicatedMessages:true]`.

---

## 3. Chance Rolls

- **[HARD] Two independent rolls multiply.** `ActionSystem.cs` rolls the action's `[Chance:]` (skipped at 100); `BroadcastSystem.BroadcastRequest` rolls the chat profile's `[Chance:]` per broadcast (skipped at 100). **Technique**: for per-cue chance, set the chat profile to `100` and put a chance on each cue's action.
- **[HARD] A failed action roll skips the whole action** (`ActionSystem.cs` returns before any tag runs). **Fails as**: a chance on an action that also does essential work (points, despawn, spawns) randomly skips that work. **[SOFT]** Put chat in its own action and list both actions with `[ActionExecution:All]`.
- **[HARD] A failed roll still uses the trigger's cooldown.** The trigger is already `Triggered` before the action rolls. **Fails as**: a lower chance gives a longer average interval (cooldown ÷ chance), not a retry.
- **[HARD] Order inside one action**: `PlayDialogueCue` runs before `ManuallyActivateTrigger` and the `[ChatData:]` broadcast. A last-words cue in an action that also triggers a despawn goes out first.

---

## 4. Tokens in Chat Messages

- **[HARD] Available** (`BroadcastSystem.cs`): `{GridName}`, `{AntennaName}`, `{Faction}` (the speaking NPC); `{GPS}` (a GPS point at the NPC); then `IdsReplacer` tokens (custom strings, counters, sandbox variables, `{SpawnGroupName}`).
- **[HARD] `{PlayerName}` and `{PlayerFactionName}` are filled in per recipient**, inside the per-player send loop. Every reader sees their own name, so the NPC appears to address each reader personally.
- **[HARD] There is no token for the target's or attacker's name.** No such replacement exists in `BroadcastSystem.cs` or `IdsReplacer.ReplaceId`.

---

## 5. Broadcast Range

- **[HARD] With `[IgnoreAntennaRequirement:true]`, `[IgnoredAntennaRangeOverride:]` is the broadcast radius** (`BroadcastSystem.cs` sets `HighestRadius` from it, then skips players beyond it). **Fails as**: `9999999` sends the line to every player on the server. **[SOFT]** That value is a common copy-paste default in chat profiles.
- **[HARD, 2.75.00 and master `bc71965`] `[SendToAllOnlinePlayers:true]` now skips players with no character.** The NPC-check migration turned `!SendToAll && (IsBot || Character == null)` into `!SendToAll && IsIdentityNPC(...) || Character == null`, so a dead or respawning player no longer receives it (`BroadcastSystem.cs`, recipient filter; tracking: se-dev-mes#8).

---

## 6. Triggers & Targeting for Chatter

- **[HARD] `[ElseActions:]` also runs when the trigger's own type check fails**, not only when its conditions fail (`TriggerProfile.ActivateTrigger`: any `!Triggered` with `UseElseActions`, gated only by cooldown; `TriggerSystem.cs` then runs `ElseActions`). **Fails as**: on a Timer, AcquiredTarget or Damage trigger the else actions fire on every check with no event. **[SOFT]** Only use ElseActions on Manual triggers.
- **If/else chains with Manual triggers.**
  - **[HARD] mechanism**: `ManuallyActivatedTriggerNames` only searches the behavior's own `Triggers` list, so Manual triggers must be attached to the behavior. TriggerGroups don't nest (`TriggerGroupProfile.cs` only reads `[Triggers:]`).
  - **[SOFT] pattern** (not yet play-tested): event trigger → action activates Manual trigger A (a condition), whose `ElseActions` activate Manual trigger B, and so on, ending in a fallback action. Example: target-type callouts checking static > aircraft > on foot > fast > far > generic.
- **[HARD] Target conditions** (`ConditionProfile.cs`): `IsTargetStatic`, `IsTargetPlayer` (a player character, i.e. on foot), `IsTargetGrid`, `TargetAltitudeCheck` (height above terrain per `PlanetEntity.cs`; not yet play-tested, and the cutoff for "is an aircraft" is a per-server choice), `CheckTargetSpeed`, `CheckTargetDistance`. There is no condition for the target's grid size, name or block types. **Fails as**: `CheckGridSize` tests the NPC's **own** grid, not the target.
- **[HARD] `AcquiredTarget` fires once per new lock** (`TriggerChecks.CheckAcquiredTarget` returns and clears `TargetAcquired`). **Fails as**: with `[MaxActions:1]` a grid only ever reacts to its first target. For repeat callouts use `[MaxActions:-1]` with a cooldown.

### Target-state edges and debouncing

- **[HARD] `NoTarget` fires whenever the grid has no target, including before its first lock** (`CheckNoTarget` is `!HasTarget()`). Edge flags come from `TargetingSystem.cs`: `TargetAcquired` (none → some), `TargetLost` (some → none), `TargetSwitched` (A → B). **Fails as**: a "lost contact" line on `NoTarget` plays shortly after spawn. Use `LostTarget` for "had one, lost it".
- **[HARD] Edge flags last one trigger pass; an edge during a cooldown is dropped, not delayed.** `TriggerSystem.cs` clears `TargetAcquired`, `TargetLost`, `TargetSwitched`, `TargetChanged` and `BehaviorTriggerA`-`G` at the end of every pass, and `ValidateTrigger` skips the type check while on cooldown. **Fails as**: a `LostTarget`, `AcquiredTarget` or `BehaviorTrigger*` trigger with a cooldown misses any edge that happens during it. Keep such triggers cooldown-free and rate-limit in what they arm instead.
- **[HARD] Before MES master `d6e5e43` (PR #405, after 2.75.01), the first `AcquiredTarget`, `LostTarget`, `SwitchedTarget` or `ChangedTarget` trigger to check its flag also cleared it**, so in one pass only the first such trigger in the behavior's list order saw the edge. **Fails as** (older builds): a chatter trigger listed before a behavior-switching trigger of the same type silently steals the edge from it. From `d6e5e43` every trigger of that type sees the edge in the same pass. On older builds give each grid one trigger per edge type, or make the other consumers state-based (`aircraft_behaviors_and_tuning.md` §2).
- **[HARD] `[ConditionCheckResetsTimer:true]` resets the cooldown only when the trigger's conditions fail, not when its type check fails** (`TriggerProfile.ValidateTrigger`). **Technique**: to require a state to hold for N seconds in a row, use `[Type:Timer]` with a condition for the state, for example `[NoTarget:true]`, plus `[ConditionCheckResetsTimer:true]`.
- **[SOFT] Pattern: "lost contact" only after a real loss** (not yet confirmed in play). A `LostTarget` trigger arms a disabled `Timer` trigger with `[EnableTriggers:]` and `[ResetCooldownTimeOfTriggers:]`; the Timer trigger uses the debounce above, plays the chatter and disables itself. Put the disable in its own action (section 3) so a failed chance roll can't leave the trigger armed. A cooldown on the `LostTarget` trigger is a per-server choice; it caps how often one grid can say the line. Before `d6e5e43` this `LostTarget` trigger takes the edge from any later `LostTarget` trigger on the grid (above), so switch the grid back to patrol with a `NoTarget` timer, not `LostTarget`.
