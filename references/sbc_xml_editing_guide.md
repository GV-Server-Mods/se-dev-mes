# Space Engineers SBC & XML Editing Guide

Technical guide to editing Space Engineers `.sbc` files safely, configuring IDE environments, protecting `<Description>` blocks, and avoiding engine deserializer traps.

---

## 1. IDE Configuration (VS Code / Cursor / Cline)

To enable syntax highlighting, validation, and auto-completion for Space Engineers `.sbc` files:

### A. File Association (`settings.json`)
Add the following to your VS Code / workspace `.vscode/settings.json`:
```json
{
  "files.associations": {
    "*.sbc": "xml",
    "*.sbcB5": "xml"
  },
  "xml.format.splitAttributes": false,
  "xml.format.joinCDATALines": false
}
```

### B. Recommended Extensions
- **XML** (Red Hat / `redhat.vscode-xml`): Provides XML schema validation, closing tag completion, and linting.
- **DotXML** or **XML Tools**: Quick formatting and tree navigation.

---

## 2. The `<Description>` Tag Protection Rule

> [!CAUTION]
> **Standard XML Formatters Break MES**:
> In standard XML formatters (like Prettier or standard XML Tools), formatting an `.sbc` file will wrap or re-indent text inside `<Description>`.
> Because MES relies on clean line-by-line parsing of square-bracket tags (e.g. `[RivalAI Behavior]`), wrapping tags onto single lines or inserting indentation inside tag strings causes **parsing failure**.
>
> **The Rule**: Never run a blind global XML formatter on `.sbc` files. Always use the dedicated formatter `powershell scripts/Format-MesSbc.ps1`, which strictly isolates and protects `<Description>` content.

---

## 3. Ban on XML Comments Inside `<Description>`

Keen's XML deserializer reads `<Description>` elements using `XmlReader.ReadElementString()`. This method expects strictly plain text content.

```xml
<!-- FATAL: Crashes Keen with System.Xml.XmlException, MOD SKIPPED -->
<Description>
  [RivalAI Behavior]
  <!-- Zone Presence Tracking -->
  [BehaviorName:Passive]
</Description>

<!-- SAFE: Uses RivalAI comment tag syntax -->
<Description>
  [RivalAI Behavior]
  [//Zone Presence Tracking]
  [BehaviorName:Passive]
</Description>
```

- Any XML comment (`<!-- ... -->`) placed inside a `<Description>` tag causes Keen to throw `MOD_CRITICAL_ERROR` and abort loading the entire mod.
- Outside `<Description>`, standard XML comments are completely legal.
- Inside `<Description>`, always use `[//Comment]` syntax.

---

## 4. Encoding & BOM Integrity

- **Required Encoding**: **UTF-8** (without BOM or with standard UTF-8 BOM).
- **Avoid UTF-16**: Never save `.sbc` files in UTF-16 (Unicode in Windows Notepad), as Keen's deserializer will fail to read the root element.
- When generating or saving files via scripts, always specify `[System.Text.Encoding]::UTF8`.
- **Enforced by `audit_sbc.ps1` (Check 0)**: flags UTF-16 LE/BE BOMs and invalid UTF-8 byte sequences as critical errors. UTF-8 with or without BOM is accepted.

---

## 5. SubtypeId & Tag Casing Best Practices

- **Strict Case Sensitivity**: While NTFS is case-insensitive on Windows, Keen's internal dictionaries (`Dictionary<string, ...>`) and MES lookups are **case-sensitive** for profile SubtypeIds.
- **Prefix Standard**: Always use `ModPrefix-ProfileType-Name` (e.g. `GVK-Trigger-Damage-Cruiser`).
- **Single SubtypeId per `<Id>`**: Never place more than one `<SubtypeId>` in an `<Id>` block.

---

## 6. Deserializer Quirk Examples

### A. Strict Single `<SubtypeId>` per `<Id>` Block
Keen's XML deserializer strictly accepts **only one** `<SubtypeId>` per `<Id>` block:
```xml
<!-- INVALID: Second SubtypeId is discarded by deserializer; action fails to load -->
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>Trigger-OutsideZone</SubtypeId>
    <SubtypeId>Action-OutsideZone</SubtypeId>
  </Id>
</EntityComponent>

<!-- VALID: One definition per SubtypeId, each with its own <Id> block -->
<EntityComponent xsi:type="MyObjectBuilder_InventoryComponentDefinition">
  <Id>
    <TypeId>Inventory</TypeId>
    <SubtypeId>Trigger-OutsideZone</SubtypeId>
  </Id>
</EntityComponent>
```

### B. Strict Single `<Id>` per `<Prefab>` Block
Duplicate `<Id>` elements inside a `<Prefab>` cause Keen to read the first one and discard subsequent ones. Prefab headers are read by hand (`MyDefinitionManager.ReadPrefabHeader`), not by the serializer: only the first `<Id>` counts; if it has a `Type` attribute its attributes win, otherwise the LAST `<SubtypeId>` element inside it wins:
```xml
<!-- INVALID: Deserializer reads the first Id, registering prefab under wrong Subtype -->
<Prefab xsi:type="MyObjectBuilder_PrefabDefinition">
  <Id Type="MyObjectBuilder_PrefabDefinition" Subtype="NST Nav Tower" />
  <Id Type="MyObjectBuilder_PrefabDefinition" Subtype="NST Base Site Tower" />
  <CubeGrids>...</CubeGrids>
</Prefab>
```
Both are enforced by `audit_sbc.ps1` (Check 3, XML DOM duplicate detection).

### C. The General Rule: Repeats Are Dropped Silently [HARD]
Keen's definition loader (`MyObjectBuilderSerializerKeen`, pre-generated serializers) and MES's own XML files (`MyAPIGateway.Utilities.SerializeFromXML`) both use `XmlSerializer`. Nothing in SE hooks its `UnknownElement` event, so none of the cases below logs anything. Tested on .NET Framework 4.8.
- **A repeated list block keeps the LAST copy.** Two `<EntityComponents>` blocks in one `.sbc` (or two `<CubeBlocks>`, `<SpawnGroups>`, MES `<StoreItems>`): each copy is read and replaces the one before, so every definition in the earlier blocks silently never loads. Merge them into one block (`audit_sbc.ps1` check 8). The flat lists append instead: bare `<Definition>` and `<Environment>` entries under `<Definitions>`, `<Icon>` on a definition.
- **A repeated single value keeps the FIRST copy.** The reader marks each member as read the first time; a later element with the same name is skipped unread. `<MinAmount>1</MinAmount><MinAmount>2</MinAmount>` reads 1, and A (one `<SubtypeId>` per `<Id>`) is a case of this rule.
- **An attribute and an element for the same field**: the element wins (`<Id Subtype="A"><SubtypeId>B</SubtypeId></Id>` gives B), because attributes are read first. Prefab headers are the exception (B above).
- **A value that does not parse** (text in a number, `True` for a bool, a wrong-case enum, a comment inside the value) throws, and the whole file is dropped, not just that field. Keen logs `MOD SKIPPED, Cannot load definition file`, but only that file is lost; the rest of the mod loads.
- **Unknown element names** are ignored the same silent way, and names are case-sensitive, so a misspelled element keeps the field's default.
- **MES world configs (`Config-*.xml` in world storage)**: a value that does not parse makes MES use the default configuration (`Could Not Load Settings From Config-X.xml. Using Default Configuration.`, always logged), and its next save writes the defaults back over the file, so the hand edits are lost.

`<Description>` tags follow their own rule (the last copy of a single-value tag wins), see [`profiles_and_tags.md`](profiles_and_tags.md) §3. MES store-items files are audited by `audit_sbc.ps1` check 7 ([`economy_and_stores.md`](economy_and_stores.md) §1 Part 1).

