# SwiftLint-Auswertung

Stand nach Codebereinigung am 17. Oktober 2026: Alle 26 normalen Befunde und
alle 13 Analyzer-Befunde sind behoben. Beide SwiftLint-Läufe bestehen mit null
Befunden; die Analyse liefert auch keine Compiler-/SourceKit-Warnungen mehr.
Die Formatprüfung sowie die Package- und Simulator-Tests bestehen. Der zusätzliche
WLAN-Gerätelauf ergibt 51 bestandene und fünf fehlgeschlagene Snapshot-Tests;
Einzelheiten stehen im Abschnitt zum Gerätelauf unten. Die 129 normalen Regeln,
die zwei Analyzer-Regeln und ihre Optionen bleiben unverändert. Es wurden keine
Inline-Ausnahmen oder Befund-Baselines eingeführt.

Die folgenden Vergleichsmessungen beschreiben den Stand **vor** dieser
Codebereinigung. Die ursprünglichen Befunde und ihre Begründungen bleiben zur
Nachvollziehbarkeit erhalten.

Ergebnis der Regelauswahl: 129 explizite Lint-Regeln und zwei separat ausgeführte
Analyzer-Regeln. Grundlage ist die gemessene Konfiguration mit 133 normalen
Regeln. Nach Einzelprüfung entfallen daraus genau vier Regeln; 37 der zuvor
pauschal entfernten 41 Regeln sind wieder aktiv. Diese Kombination meldet 26
Stellen im normalen Lint-Lauf und weitere 13 Stellen bei der Build-gestützten
Analyse vor der anschließenden Codebereinigung.

Die frühere Empfehlung von 92 Regeln war nicht ausreichend begründet:
39 der 41 entfernten Regeln hatten keine aktuellen Treffer, konnten aber
weiterhin zukünftige Probleme erkennen. Zwei Meldungen weniger rechtfertigen
diese Einschränkung nicht. Eine Regel bleibt nicht allein deshalb deaktiviert,
weil sie heute nichts meldet oder als „idiomatic“ statt „lint“ klassifiziert ist.

Basis ist Commit `450f6c9` auf `codex/adopt-swift-format`. Der neue Branch heißt
`codex/evaluate-swiftlint-strictness` und wurde vor der PR-Erstellung auf den
aktuellen Main-Stand nach Merge von PR #122 gesetzt. Gemessen wurde mit SwiftLint 0.65.1 und
Xcode 27.0, Build 27A266a. Die Auswahl beschreibt die begründeten Vorgaben dieses
Projekts, keinen allgemein gültigen Swift-Standard und keine nachgewiesen
optimale Regelanzahl.

Während der Konfigurationsevaluation wurde vor jeder Stufe die ursprüngliche SwiftLint-Konfiguration im Arbeitsbaum
wiederhergestellt und anschließend durch den nächsten Kandidaten ersetzt.
Es gab keine Zwischencommits, keinen Hard-Reset anderer Dateien, keine
Autokorrektur und keine Änderungen an App-, Package- oder Testcode.
Dateiprüfsummen sichern den unveränderten Ausgangsstand ab.

## Vergleich der normalen Lint-Läufe

Alle Läufe verwendeten `--strict --no-cache --reporter json`.
Die Kandidaten prüften im Ausgangsstand 67 versionierte Swift-Dateien einschließlich `Package.swift`;
die ursprüngliche Konfiguration prüft die 66 Dateien in App, Sources und Tests.

| Stufe | Normale Regeln | Produktion | Tests | Meldungen | Bewertung |
| --- | ---: | ---: | ---: | ---: | --- |
| Maximal hart: alle optionalen Regeln | 250 | 4.286 | 4.377 | 8.663 | Verworfen: Formatierungskonflikte und sehr viele allgemeine Stilvorschriften |
| Hart: ohne die erkannten Formatter-Überschneidungen | 162 | 1.368 | 1.695 | 3.063 | Verworfen: explizite Typen, Zugriffsstufen und Zahlenkonstanten dominieren |
| Praktisch streng | 136 | 28 | 46 | 74 | Mehrere wenig hilfreiche Meldungen zu legitimen Framework- und TCA-Mustern |
| Angepasste Qualitätsschwellen | 133 | 5 | 21 | 26 | Ausgangspunkt für die Einzelprüfung |
| Frühere, zurückgenommene Empfehlung | 92 | 5 | 19 | 24 | 41 Abschaltungen für nur zwei Meldungen weniger waren zu pauschal |
| Aktuell: Einzelprüfung auf Basis der 133 Regeln | 129 | 5 | 21 | 26 | Nur vier einzeln begründete Ausnahmen, keine Unterdrückung der beiden Testhinweise |
| Leicht: überwiegend Risikoprüfungen | 30 | 3 | 11 | 14 | Lässt zusätzliche Aufräum- und Strukturhinweise aus |
| Ursprüngliche Konfiguration | 4 | 0 | 0 | 0 | Zu wenig Abdeckung für das gewünschte Ziel |

Die normalen Läufe dauerten auf diesem Rechner ungefähr 0,1 bis 0,7 Sekunden
einschließlich der Erfassung der aktivierten Regeln. Vor der Codebereinigung
wurde die ausgewählte Konfiguration erneut ausgeführt: 129 aktivierte normale
Regeln, 26 Meldungen, keine Konfigurationsdiagnosen. Zu diesem Zeitpunkt bestand
nur die ursprüngliche Vier-Regel-Konfiguration den Lauf; die anderen Stufen
lieferten wegen `--strict` den Exitcode 2. Nach den Korrekturen besteht auch die
129-Regel-Konfiguration mit null Befunden.

Die größten Beiträge zur maximal harten Stufe waren `indentation_width` mit
2.800 Meldungen, `contrasted_opening_brace` mit 2.015, `explicit_type_interface`
mit 1.057, `no_magic_numbers` mit 697 und `explicit_acl` mit 611.
Insbesondere die ersten beiden Regeln passen nicht zu unserem Formatter.

## Die vier Abschaltungen gegenüber der 133er-Basis

| Regel | Einzelbegründung | Bewusste Grenze |
| --- | --- | --- |
| `comment_spacing` | Verlangt zusätzliche Leerzeichen nach den Kommentar-Slashes. Das ist eine reine Formatkonvention für Kommentartext. | swift-format normalisiert diese Leerzeichen **nicht** vollständig. Die Regel entfällt als zusätzliche Stilvorgabe, nicht als vermeintliche Doppelprüfung. |
| `mark` | Erzwingt eine bestimmte Schreibweise und Abstände von `MARK`-Kommentaren. | Auch diese Prüfung fehlt in swift-format. Es wird bewusst keine zusätzliche redaktionelle Kommentar-Konvention erzwungen. |
| `object_literal` | Fordert `#imageLiteral` und `#colorLiteral`, während die aktive Formatter-Regel `NoPlaygroundLiterals` genau diese Literale verbietet. | Nachgewiesener Regelwiderspruch; der Formatter-Lint prüft die gewählte Richtung. Die Literale werden nicht automatisch durch den Format-Befehl ersetzt. |
| `redundant_void_return` | Funktions- und Protokollsignaturen mit `-> Void` prüft bereits `NoVoidReturnOnFunctionSignature`. | SwiftLint würde zusätzlich explizite `Void`-Rückgabetypen an Closures beanstanden. Diese zusätzliche Stilprüfung entfällt bewusst; der Formatter deckt sie nicht ab. |

Die Formatter-Zuständigkeiten wurden mit isolierten Beispielen geprüft, ohne
Projektcode zu ändern. Besonders wichtig: `swift-format format` und
`swift-format lint` decken nicht dieselben automatischen Korrekturen ab.
Die Regeln sind in der [offiziellen swift-format-Dokumentation](https://github.com/swiftlang/swift-format/blob/main/Documentation/RuleDocumentation.md)
beschrieben; maßgeblich für die Messung ist die lokal verwendete Xcode-Version.

`empty_string` und `large_tuple` bleiben aktiv. Ihre beiden aktuellen Hinweise
betreffen einen exakten Vergleich eines optionalen Testwerts mit `""` sowie
eine benannte Testtabelle mit fünf Feldern. Beide Stellen können begründbar sein;
das allein rechtfertigt aber keine projektweite Abschaltung. Es wurden weder
Dateien ausgeschlossen noch Inline-Ausnahmen oder eine Befund-Baseline angelegt.

## Begründungen der übernommenen Schwellen und Ausnahmen

- `swift-format` bleibt für Layout zuständig. Die Empfehlung enthält keine
  konkurrierenden Regeln für Einrückung, Klammerplatzierung, Importreihenfolge,
  Semikolons oder allgemeine Zeilenlänge.
- TCA verschachtelt `State`, `Action` und weitere Enums absichtlich. Deshalb ist
  `nesting.type_level` auf 2 statt auf 1 gesetzt. Die 14 ursprünglichen
  Verschachtelungsmeldungen sind damit keine Aufforderung mehr, zusammengehörige
  Feature-Typen auseinanderzuziehen.
- Pauschale Datei-, Typ-, Funktions- und Closure-Längenvorgaben wurden entfernt.
  Sie trafen unter anderem Testtabellen, Test-Suites und TCA-Reducer.
  `cyclomatic_complexity` bleibt mit 15/25 und ohne einzelne Switch-Cases aktiv.
  Die zentrale Netzwerkfunktion mit Komplexität 12 wird dadurch nicht allein
  wegen ihrer expliziten Validierungszweige beanstandet.
- `no_empty_block` erlaubt Initializer, Funktions-Stubs und No-op-Closures.
  Das ist unter anderem für `package init()`, `URLProtocol.stopLoading()` und
  injizierte Test-Callbacks nötig. Leere Statement-Blöcke, etwa ein leerer
  `catch`, bleiben eine Meldung.
- `legacy_objc_type` erlaubt gezielt `NSString`. Die Paste-Integration verwendet
  damit die Objektprotokolle von `NSItemProvider`. Andere Typen wie `NSNumber`
  werden weiterhin beanstandet.
- `accessibility_label_for_image` wurde nicht übernommen. Mindestens bei
  `HomeMenu` und `UnsealButton` berücksichtigt die Regel das bereits vorhandene
  Label des übergeordneten Controls nicht ausreichend. Das beweist nicht, dass
  alle acht ursprünglichen Accessibility-Hinweise falsch sind; diese sollten
  bei einer tatsächlichen Accessibility-Prüfung betrachtet werden.
- `static_over_final_class` ist hier eine Stilentscheidung. Sowohl die
  bestehenden `override class func`-Signaturen als auch die vorgeschlagenen
  `override static func`-Varianten wurden isoliert erfolgreich typgeprüft.
  Die ursprünglichen Signaturen sind deshalb kein nachgewiesener Fehler.
- `large_tuple` bleibt mit den bereits getesteten Schwellen 4/6 aktiv.
  Die vorhandene Testtabelle wird weiterhin gemeldet. Die Regel ist ein
  Strukturhinweis, kein Beweis für einen funktionalen Fehler.
- `missing_docs` bleibt für öffentliche/offene APIs aktiv, ebenso die
  zusätzlichen Typnamenprüfungen der 133er-Basis. Keine dieser Regeln verlangt
  Dokumentation für jeden internen Helfer oder explizite Typen für jede Variable.
- `prefer_nimble` bleibt deaktiviert, weil die Regel eine zusätzliche Bibliothek
  verlangen würde. Die konfliktfreie `nimble_operator`-Regel sowie die drei
  Quick-Schutzregeln bleiben dagegen aktiv: Ohne diese Bibliotheken melden sie
  nichts; ihre Aktivierung fügt keine Abhängigkeit hinzu.

Die Ausnahmen wurden zusätzlich an isolierten Beispielen geprüft: leere
Initializer, Callback-Stubs und `NSString` bleiben erlaubt; ein leerer `catch`
und ein unnötiger `NSNumber`-Typ werden weiterhin erkannt.

## Die 26 ursprünglichen normalen Meldungen

| Regel | Anzahl | Einordnung |
| --- | ---: | --- |
| `force_unwrapping` | 7 | Präventionsregel. Drei Meldungen liegen im Produktionscode, vier in festen Test-Fixtures. Bestehende Vorbedingungen sichern diese Stellen ab; es wurde kein konkreter Absturz nachgewiesen. |
| `unused_parameter` | 7 | Unbenutzte Parameter in Overrides, Test-Doubles und einem Wiederholungstest. Ein `_` würde die beabsichtigte Nichtverwendung deutlich machen. |
| `unneeded_throws_rethrows` | 6 | Testfunktionen propagieren keinen Fehler; die Signatur enthält trotzdem `throws`. |
| `unneeded_escaping` | 2 | Zwei URLSession-Delegate-Callbacks werden synchron aufgerufen. Die Signaturen mit und ohne `@escaping` wurden isoliert erfolgreich typgeprüft. |
| `empty_count` | 1 | Bei der Korrektur als Fehlmeldung erkannt: `CallCounter.count` ist ein Integer-Aufrufzähler, keine Collection. Die Property heißt nun eindeutig `callCount`; der Vergleich mit null bleibt erhalten. |
| `array_init` | 1 | Eine Identitätsabbildung wandelt nur Dictionary-Keys in ein Array um. `Array(...)` würde die Absicht direkter ausdrücken. |
| `large_tuple` | 1 | Benannte Testtabelle mit fünf Feldern in `HomeViewStateTests.swift:12`; ein prüfbarer Strukturhinweis, kein nachgewiesener Fehler. |
| `empty_string` | 1 | Exakter Vergleich des optionalen `localizedFallbackTitle` mit `""` in `LiveSealbreakClientTests.swift:34`. Eine Alternative muss weiterhin `nil` von einem leeren String unterscheiden. |

Die drei Produktionsmeldungen zu `!` betreffen
`InstanceSetupFeature.swift:108` (zweimal) und `Models.swift:92`.
Bei der URL-Auswertung garantiert bereits `ServerProfile` die gültige Origin;
beim Port schützt eine Kurzschlussbedingung den Zugriff. Diese Meldungen sind
bewusst sichtbare Prüfhinweise und keine Behauptung, die Stellen seien aktuell
unsicher. Die zwei weiteren Produktionsmeldungen betreffen die Delegate-Callbacks
in `SealServerClient.swift:11` und `SealServerClient.swift:19`.

## Build-gestützte Analyse

Für die Analyse wurden ein vollständiger iOS-Build für Tests und ein separater
Build der Swift-Package-Tests erfolgreich ausgeführt. Es wurden keine Tests
gestartet. Zusammen liefern die Builds Compilerargumente für alle 66 App- und
Testdateien. `Package.swift` wird durch den normalen Linter geprüft, aber nicht
als App-/Testdatei durch diese Analyse erfasst.

| Variante, jeweils mit denselben 66 Dateien | Importmeldungen | Unbenutzte Deklarationen | Gesamt |
| --- | ---: | ---: | ---: |
| Hart: direkte Imports erzwingen, öffentliche Deklarationen einbeziehen | 73 | 6 | 79 |
| Empfohlen: TCA-Reexports erlauben, keine pauschalen direkten Imports | 7 | 6 | 13 |

Die harte Variante enthält 64 Forderungen nach weiteren direkten Imports,
beispielsweise für `CoreFoundation`, `ObjectiveC` und `UIUtilities`, sowie neun
als unbenutzt gemeldete Imports. Zwei dieser neun Importmeldungen entstehen
durch die Nutzung der absichtlich von TCA exportierten Module.

Die Empfehlung verwendet deshalb `require_explicit_imports: false` und erlaubt
für `ComposableArchitecture` genau die 13 in TCA 1.26.2 dokumentierten Reexports
aus `Internal/Exports.swift`. Das ist keine pauschale Ausnahme über
`always_keep_imports`: Ein tatsächlich ungenutzter TCA-Import kann weiterhin
gemeldet werden. Öffentliche und offene Deklarationen werden nicht pauschal
auf interne Nutzung reduziert.

Die sieben ursprünglichen Importmeldungen waren:

| Datei | Import |
| --- | --- |
| `Sources/SealbreakCore/Domain/StoredProfile.swift:1` | `Foundation` |
| `Sources/SealbreakAppModule/Features/Home/SealStatusMotion.swift:1` | `Foundation` |
| `Sources/SealbreakAppModule/Features/Home/Components/SealStatusIndicator.swift:1` | `SealbreakCore` |
| `Sources/SealbreakAppModule/Features/Home/Components/SealStatusMotionViews.swift:1` | `SealbreakCore` |
| `Sources/SealbreakAppModule/Features/Home/Components/UnsealButton.swift:1` | `SealbreakCore` |
| `Sources/SealbreakAppModule/Features/Home/Components/ServerStatusCard.swift:1` | `SealbreakCore` |
| `Tests/SealbreakInfrastructureTests/KeychainAccessControlTests.swift:1` | `Foundation` |

Die sechs ursprünglichen Deklarationsmeldungen waren:

| Datei | Unbenutzte Deklaration |
| --- | --- |
| `Sources/SealbreakAppModule/App/SensitiveDraftGuard.swift:29` | `clearSensitiveDraftOnPrivacyChange` |
| `Tests/SealbreakCoreTests/FeatureTests.swift:1746` | Nicht optionale Überladung von `localizedContains` |
| `Tests/SealbreakCoreTests/FeatureTests.swift:1766` | `setProtectOutcome` |
| `Tests/SealbreakCoreTests/FeatureTests.swift:1768` | `setRemoveOutcome` |
| `Tests/SealbreakCoreTests/FeatureTests.swift:1779` | `setInsertError` |
| `Tests/SealbreakCoreTests/FeatureTests.swift:1781` | `setDeleteShareError` |

Die Testreferenzen sind wesentlich: Die zunächst nur mit den iOS-Zielen
ausgeführte Analyse beanstandete auch drei tatsächlich in Package-Tests genutzte
Deklarationen. Mit den zusätzlichen Compilerargumenten verschwinden diese
Meldungen. Die Makros werden in der empfohlenen Messung erfolgreich geladen.

Die Analyse liefert weiterhin drei zusätzliche SourceKit-Warnungen zur
Actor-Isolation von UIKit-Zugriffen. Beide tatsächlichen Builds waren erfolgreich.
Diese Warnungen werden getrennt von den 13 Analyzer-Meldungen behandelt.

Der gültige Kontrolllauf vor der Codebereinigung bestätigte exakt dieselben
sieben Import- und sechs Deklarationsmeldungen. Es gab dabei keine Compiler-/
Makrofehler; die drei genannten SourceKit-Warnungen bestanden zu diesem Zeitpunkt
weiter. Nach den Codekorrekturen liefert die Analyse null Befunde und keine
Compiler-/SourceKit-Warnungen mehr.

## Wiederholung und Artefakte

Der schnelle Lauf mit der empfohlenen Konfiguration:

```bash
swiftlint lint --config .swiftlint.yml --strict --no-cache
```

Die vollständige Analyse einschließlich frischer Builds startet über denselben
Hook wie in CI:

```bash
pre-commit run swiftlint-analyze --all-files
```

Alternativ direkt: `bash scripts/ci/analyze.sh`.
Voraussetzungen sind macOS, ein ausgewähltes vollständiges Xcode und
SwiftLint. Der erste Lauf benötigt Zugriff auf die gepinnten Package-Abhängigkeiten.
Jeder Lauf kopiert die kanonischen Xcode-Pins in die ignorierte `Package.resolved`
im Projektstamm und löst den Package-Graphen für das ausgewählte Xcode auf.
Versionierte Manifeste von TCA können bei neueren Swift-Versionen zusätzliche
Abhängigkeiten benötigen; das Auflösungsprotokoll bleibt erhalten. Der folgende
Package-Build verwendet die so aufgelösten Versionen mit `--force-resolved-versions`.
Die kanonische Xcode-Lockdatei wird nicht angepasst; eine Änderung durch Xcode
führt zum Fehler und muss separat geprüft werden.
Danach bereinigt und baut der Hook in `build/SwiftLintAnalyze/` die Package-Testziele
sowie iOS-App und gehostete Tests neu; Tests werden dabei nicht ausgeführt.
Abhängigkeitsdownloads bleiben wiederverwendbar. App-Signing ist abgeschaltet.
Die Analyse verlängert einen Swift-Commit daher um beide Builds und die
SourceKit-Analyse.

Der Hook läuft einmal pro Commit, auch bei reinen Löschungen: Das Löschen der
letzten Verwendung kann eine Deklaration in einer unveränderten Datei unbenutzt
machen. Er prüft projektweit und erhält keine Liste einzelner geänderter Dateien.
CI führt ihn über `pre-commit run --all-files --show-diff-on-failure` aus.

Der Shell-Ablauf übergibt beide vollständigen Build-Protokolle direkt an den
nativen SwiftLint-Aufruf `analyze --strict --compiler-log-path`. Ein eigener
Compilerargument-Parser und eine selbst erzeugte Datenbank entfallen.
Das iOS-Protokoll steht zuerst, damit SwiftLint für gemeinsam gebaute Dateien
die iOS-Argumente verwendet. Eine `sed`-Ersetzung entpackt ausschließlich Xcodes
maskierte `#`-Trennzeichen in Makro-Pluginpfaden; ohne diese entstehen mit
SwiftLint 0.65.1 falsche Meldungen über fehlende TCA-Makros.
Diese Ersetzung ist ein lokal reproduzierter Workaround: Mit den aufbereiteten
Protokollen besteht der native Hook für alle 65 Dateien. Die anschließende Web-
und GitHub-Suche ergab keinen unabhängigen öffentlichen Bericht zu genau dieser
Ersetzung bei SwiftLint Analyze mit TCA; sie ist keine dokumentierte TCA-Vorgabe.
Die Abschlussmeldung muss ebenso viele analysierte Dateien nennen, wie Swift-
Dateien unter `Sealbreak/`, `Sources/` und `Tests/` vorhanden sind. Das verhindert
auch einen scheinbar erfolgreichen Lauf mit null oder nur den 55 iOS-Dateien.
Buildfehler, SwiftLint-Befunde und Compiler-/SourceKit-Warnungen oder -Fehler führen
zum Fehlschlag. `Package.swift` bleibt beim normalen Lint-Lauf. Der Ablauf ist in
[lint-analysis.puml](lint-analysis.puml) dokumentiert.

Die historische Analyzer-Messung kann mit den erhaltenen lokalen Build-Artefakten
wiederholt werden:

```bash
swiftlint analyze --config .swiftlint.yml --strict \
  --compile-commands build/LintFixes-08z93qkb/compile_commands-complete.json
```

Diese Datenbank enthält aufbereitete SourceKit-Argumente ohne Compilerprogramm,
mit expandierten Swift-Dateilisten und korrekt entpackten Makropfaden.
Die absoluten Pfade gelten nur für diesen Checkout und diese Builds. Nach
Änderungen am Quellcode oder nach dem Löschen der Builds ist sie neu zu erzeugen.

Alle getesteten Konfigurationen, JSON-Befunde, Regelzählungen und Build-Protokolle
liegen im ignorierten Verzeichnis `build/LintEvaluation-2apdk76d/`.
`recommended-findings.csv` und `recommended-findings.json` enthalten alle 39
Fundstellen vor der Codebereinigung einschließlich ihrer damaligen Einordnung. Die früheren 37
Fundstellen sind separat als `09-recommended-findings.*` erhalten.
`10-individual-rule-audit.*` enthält den aktuellen normalen Lint-Lauf,
`analyzer-07-individual-rule-audit.*` dessen separat wiederholte Analyzer-Prüfung.
`individual-rule-decisions.json` enthält die unten dokumentierten Entscheidungen
auch maschinenlesbar. Die historischen Kandidaten wurden nicht überschrieben.

Frühe Analyzer-Läufe mit fehlerhaft gelesenen Makropfaden beziehungsweise einer
verworfenen Reexport-Konfigurationssyntax sind ebenfalls als Diagnoseartefakte
erhalten. Sie zählen nicht zu den gültigen Vergleichsmessungen oben. Die finale
Regelkonfiguration wurde ausdrücklich auf Konfigurationswarnungen geprüft.

Auch `analyzer-06-individual-rule-audit.*` ist ungültig: Die Ausführungs-Sandbox
verhinderte den Start der Compiler-Makroprozesse (`sandbox_apply: Operation not
permitted`). Daraus entstanden 462 Compilerdiagnosen und scheinbar 64 unbenutzte
Deklarationen. Diese Zahlen werden nicht als Codebefunde gewertet. Der Lauf
wurde außerhalb dieser zusätzlichen Ausführungs-Sandbox mit identischem
Quellcode, derselben Konfiguration und denselben Compilerargumenten wiederholt.

Während des Konfigurationsexperiments wurden die zwei Analyzer-Regeln separat
getestet. Inzwischen sind sie mit frischen Builds über den oben beschriebenen Hook
in Pre-commit und CI eingebunden. Vor der Codebereinigung schlug der normale Hook
wegen der 26 Meldungen fehl; nach den Korrekturen besteht er.
SwiftLint ist in CI derzeit nicht versionsgebunden; die Messergebnisse gelten
für die hier verwendete Version 0.65.1.

Während der Konfigurationsevaluation wurden ausschließlich die Lint-Konfiguration
und dieser Bericht geändert. Die anschließenden Codekorrekturen sind unten
beschrieben. Eine Änderung an `THREAT_MODEL.md` ist dafür nicht nötig und wurde
nicht vorgenommen. Während der Evaluation gab es keine Zwischencommits oder Pushes.

## Anschließende Codebereinigung

- Sieben unbenutzte Imports und fünf unreferenzierte Test-Helfer wurden entfernt.
  Der unbenutzte Einstiegspunkt `clearSensitiveDraftOnPrivacyChange` und sein
  ebenfalls ausschließlich dort referenzierter `SensitiveDraftGuard` wurden
  vollständig entfernt. Kein View und kein Test verwendete diesen Modifier.
- Die Host-Auswertung im Setup prüft Optional-Werte und meldet einen ungültigen
  Zustand über den vorhandenen Fehlerpfad. Die Portprüfung erlaubt weiterhin
  keinen Port oder einen Port von 1 bis 65535, ohne erzwungenes Unwrapping.
- Test-Fixtures verwenden `try #require` statt `!`. Unbenutzte Parameter werden
  mit `_` markiert, sechs überflüssige `throws`-Annotationen entfallen und die
  benannte Testtabelle verwendet einen eigenen `StatusPresentationCase`-Typ.
  Der optionale leere Text wird weiterhin ausdrücklich von `nil` unterschieden.
- Der Aufrufzähler heißt `callCount`; die Keychain-Testprüfung erzeugt ihr Set
  direkt aus Dictionary-Keys statt über eine Identitätsabbildung.
- Die URLSession-Callbacks werden synchron aufgerufen und benötigen kein
  `@escaping`. Das gilt auch für die weiterleitende Delegate-Methode.
- Die injizierten UIKit-Zustandsabfragen sind explizit `@MainActor`-Closures.
  Sie wurden bereits zuvor ausschließlich im MainActor-isolierten Controller
  ausgeführt; die Typen dokumentieren diese Anforderung nun ebenfalls.

Die Änderungen wurden auf Auswirkungen auf `THREAT_MODEL.md` geprüft:
Zielvalidierung, Transportpolitik, Biometrie-/Keychain-Bedingungen und aktive
Privacy-Unterbrechungen bleiben erhalten. Es ändern sich keine Vertrauensgrenzen
oder Datenflüsse. Die entfernte Privacy-Komponente war unreferenziert; die
weiterhin genutzten Privacy-Pfade bleiben Gegenstand der bestehenden Tests.

### Verifikation nach den Korrekturen

| Prüfung | Ergebnis |
| --- | --- |
| `swiftlint lint --strict --no-cache` | 0 Befunde, Exitcode 0 |
| `swiftlint analyze --strict` mit frischen Compilerargumenten | 0 Befunde, 0 Compilerfehler, 0 Compiler-/SourceKit-Warnungen, Exitcode 0 |
| `pre-commit run swiftlint --all-files` | Bestanden |
| `pre-commit run swift-format-lint --all-files` | Bestanden |
| YAML-Prüfung und `git diff --check` | Bestanden |
| Frischer iOS-Build einschließlich Testzielen | Bestanden |
| Core-/Infrastructure-Package-Tests | 161 Tests in 10 Suites bestanden |
| iOS-AppModule-Tests im Simulator: iPhone 17 mit iOS 26.5 | 55 bestanden, 0 fehlgeschlagen, 1 wie vorgesehen übersprungen |
| Zusätzlicher WLAN-Gerätelauf: iPhone 18 Pro Max mit iOS 27.0.1 | 51 bestanden, 5 fehlgeschlagen, 0 übersprungen |

Der im Simulator übersprungene Test `atomicLifecycleWritesKeepCompleteFileAndDirectoryProtection`
benötigt ein physisches iPhone: Der Simulator liefert die geprüften
Dateischutzattribute nicht. Auf dem physischen iPhone besteht dieser Test.
Die Snapshot- und Privacy-Tests sind im Simulator bestanden; die Einschränkung
des Snapshot-Dateipfads auf dem Gerät ist unten beschrieben.

Für die Abschlussanalyse wurden iOS-App und Testziele frisch gebaut sowie die
Package-Tests nach Bereinigung ihrer Build-Artefakte neu gebaut und ausgeführt.
Die Compiler-Datenbank erfasst alle 65 verbliebenen App- und Testdateien.
`Package.swift` wird weiterhin nur durch den normalen Linter geprüft.
Der temporäre Testsimulator wurde anschließend entfernt.

Die neuen Protokolle und Resultate liegen in `build/LintFixes-08z93qkb/`:
`lint-after.json`, `analyze-after.json`, `analyze-after.result.json`,
`ios-build.log`, `package-tests.log`, `ios-tests-summary.json` und
`AppModuleTests-02.xcresult`. Der erste iOS-Teststart scheiterte vor der
Testausführung an einer abweichenden Paket-Cache-Auswahl. Die Wiederholung mit
dem Cache des erfolgreichen Builds bestand; die versionierten Dependency-Dateien
blieben unverändert. Die früheren Auswertungsartefakte bleiben erhalten.

### Zusätzlicher WLAN-Gerätelauf

Die Tests wurden anschließend auf dem gekoppelten iPhone 18 Pro Max mit
iOS 27.0.1 ausgeführt. CoreDevice bestätigte `transportType: localNetwork` und
einen verbundenen TCP-Tunnel. Die Test-App wurde mit einer separaten App-ID
signiert und installiert. Nach Abschluss wurde ausschließlich diese neue
Test-App wieder entfernt. Projektcode, Signierungseinstellungen im Projekt und
Dependencies wurden für diesen Lauf nicht geändert.

Die 161 Core-/Infrastructure-Package-Tests wurden erneut ausgeführt und bestanden.
Der erste vollständige iPhone-Lauf ergab 38 bestandene und 18 fehlgeschlagene
Tests: Der Privacy-Schutz blieb sichtbar, und iOS verweigerte den Zugriff auf die
Zwischenablage. Nach ausdrücklichem Vordergrundstart der Test-App bestanden alle
acht gezielt wiederholten Tests. Die anschließende vollständige Wiederholung
ergab **51 bestandene, fünf fehlgeschlagene und null übersprungene Tests**.
Insbesondere bestehen beide Plattformtests zu Backup-Ausschluss und vollständigem
Datei-/Verzeichnisschutz sowie alle Zwischenablage-Tests.

Die fünf verbleibenden fehlgeschlagenen Methoden sind:

- `PrivacyViewTests.testActualDetailsViewRequiresAuthorizationAndShowsOnlyTransientFragment`
- `PrivacyViewTests.testBackgroundAndCaptureDismissDetailsAndRejectDelayedAuthorization`
- `PrivacyViewTests.testPresentedSheetsStayPresentedAndConcealOnInactive`
- `PrivacyViewTests.testPrivacyGateMapsPhaseAndCaptureEnvironmentToConcealment`
- `PrivacyViewTests.testRootHomeIsVisiblyConcealedAndReturnsWithPositiveContent`

Alle Fehlermeldungen der letzten Wiederholung betreffen Dateisystemberechtigungen
für `__Snapshots__`. Der Snapshot-Helfer verwendet standardmäßig den über
`#filePath` bestimmten Mac-Quellpfad. Auf dem iPhone kann SnapshotTesting diesen
Pfad nicht als Referenzverzeichnis anlegen. Diese Snapshot-Tests sind damit in
ihrer aktuellen Form nicht vollständig auf dem Gerät ausführbar. Weder wurden
sie abgeschaltet noch Referenzbilder oder Produktcode für ein grünes Ergebnis
verändert.

Die neuen Protokolle liegen in `build/DeviceTests-954o4smc/`. Maßgeblich sind
`device-tests-02-summary.json`, `device-tests-02.log` und
`DeviceTests-02.xcresult`. `device-tests-foreground-summary.json` dokumentiert
die erfolgreiche gezielte Wiederholung; die ursprünglichen Fehlversuche bleiben
ebenfalls zur Nachvollziehbarkeit erhalten.

## Einzelentscheidung zu allen 41 früheren Abschaltungen

„Heute keine Meldung“ ist kein Abschaltgrund. Die folgenden Entscheidungen
prüfen Zweck, aktive Formatter-Regeln und die konkreten Projektmuster.
37 Regeln werden wieder aktiviert, vier bleiben aus den oben einzeln genannten
Gründen aus. Die Zahlen beziehen sich auf den normalen Lauf der 133er-Basis.

| Regel | Aktuelle Entscheidung | Meldungen in der 133er-Basis | Einzelbegründung |
| --- | --- | ---: | --- |
| `comment_spacing` | Deaktiviert | 0 | Nur Leerzeichen im Kommentartext. swift-format normalisiert diese nicht vollständig; bewusst keine zusätzliche Kommentar-Formatvorschrift. Keine behauptete Doppelprüfung. |
| `convenience_type` | Wieder aktiv | 0 | Verhindert versehentlich instanziierbare reine Namensräume; nicht vom Formatter abgedeckt. |
| `empty_string` | Wieder aktiv | 1 | Leerheitsprüfung bleibt als Hinweis aktiv. Ein optionaler Testvergleich ist ein begründbarer Einzelfall, kein Grund, die Regel projektweit abzuschalten. |
| `enum_case_associated_values_count` | Wieder aktiv | 0 | Macht überladene Enum-Cases sichtbar; ergänzt die TCA-Action-Prüfung, ohne aktuell anzuschlagen. |
| `expiring_todo` | Wieder aktiv | 0 | Erkennt abgelaufene explizit datierte TODO/FIXME-Kommentare; setzt keinen Termin für undatierte Kommentare. |
| `fallthrough` | Wieder aktiv | 0 | Macht implizites Weiterlaufen in den nächsten Switch-Zweig sichtbar; strenger als die Formatter-Prüfung auf ausschließlich fallthrough enthaltende Cases. |
| `file_name_no_space` | Wieder aktiv | 0 | Verhindert unnötige Probleme mit Dateipfaden in Werkzeugen und Skripten. |
| `for_where` | Wieder aktiv | 0 | Vereinfacht reine Filter-Schleifen. UseWhereClausesInForLoops ist beim Formatter hier deaktiviert; keine Doppelprüfung. |
| `function_parameter_count` | Wieder aktiv | 0 | Erkennt künftig überladene Schnittstellen; derzeit keine Meldung und kein Grund für eine pauschale Abschaltung. |
| `generic_type_name` | Wieder aktiv | 0 | Prüft verständliche generische Typnamen zusätzlich zur reinen Großschreibung des Formatters. |
| `is_disjoint` | Wieder aktiv | 0 | Drückt disjunkte Mengen direkt aus und vermeidet unnötiges Berechnen einer Schnittmenge. |
| `joined_default_parameter` | Wieder aktiv | 0 | Entfernt ein redundantes Standardargument bei joined; nicht vom Formatter übernommen. |
| `large_tuple` | Wieder aktiv | 1 | Prüft große Tupel weiter mit den bereits getesteten Schwellen 4/6. Die benannte Testtabelle bleibt als überprüfbarer Hinweis sichtbar. |
| `legacy_swiftui_aspect_ratio` | Wieder aktiv | 0 | Erkennt die veraltete SwiftUI-Schreibweise statt eine spätere API-Migration unbemerkt zu lassen. |
| `mark` | Deaktiviert | 0 | Erzwingt Schreibweise und Abstände von MARK-Kommentaren. swift-format prüft das nicht; diese zusätzliche redaktionelle Formatvorschrift gehört nicht zur Qualitätsprüfung. |
| `missing_docs` | Wieder aktiv | 0 | Verlangt Dokumentation für öffentliche/offene APIs, nicht für jeden internen Helfer. Die entsprechende swift-format-Regel ist deaktiviert. |
| `nimble_operator` | Wieder aktiv | 0 | Aktuell ohne Nimble wirkungslos, aber konfliktfrei. Keine neue Bibliothek wird verlangt; ein fehlender heutiger Treffer rechtfertigt die Entfernung nicht. |
| `object_literal` | Deaktiviert | 0 | Fordert #imageLiteral/#colorLiteral. Die aktive swift-format-Regel NoPlaygroundLiterals verbietet genau diese Literale: nachgewiesener Widerspruch. |
| `prefer_condition_list` | Wieder aktiv | 0 | Prüft übersichtliche Bedingungslisten; der Formatter ersetzt && nicht automatisch durch Kommas. |
| `prefer_type_checking` | Wieder aktiv | 0 | Bevorzugt eine direkte Typprüfung statt eines unnötigen Casts mit anschließender nil-Prüfung. |
| `prohibited_interface_builder` | Wieder aktiv | 0 | Bewahrt die dokumentierte SwiftUI-Ausrichtung und macht neu eingeführte Interface-Builder-Attribute sichtbar. |
| `quick_discouraged_call` | Wieder aktiv | 0 | Schützt bei späterer Quick-Nutzung vor problematischen Aufrufen; aktuell keine Quick-Abhängigkeit und kein Konflikt. |
| `quick_discouraged_focused_test` | Wieder aktiv | 0 | Würde versehentlich fokussierte Quick-Tests erkennen, die andere Tests auslassen. |
| `quick_discouraged_pending_test` | Wieder aktiv | 0 | Würde versehentlich deaktivierte Quick-Tests erkennen. |
| `redundant_final` | Wieder aktiv | 0 | Entfernt unnötige final-Modifikatoren; kein Gegenstück in der aktiven Formatter-Konfiguration. |
| `redundant_nil_coalescing` | Wieder aktiv | 0 | Erkennt wirkungslose nil-Ersatzwerte und damit unnötige Logik. |
| `redundant_objc_attribute` | Wieder aktiv | 0 | Erkennt überflüssige Objective-C-Attribute ohne eine neue Architekturvorgabe einzuführen. |
| `redundant_set_access_control` | Wieder aktiv | 0 | Erkennt unnötige Zugriffseinschränkungen an Settern. |
| `redundant_string_enum_value` | Wieder aktiv | 0 | Erkennt String-Raw-Values, die bereits automatisch abgeleitet werden. |
| `redundant_type_annotation` | Wieder aktiv | 0 | Erkennt offensichtlich wiederholte Typinformationen; Erzwingen sämtlicher expliziter Typen bleibt separat deaktiviert. |
| `redundant_void_return` | Deaktiviert | 0 | Funktions-/Protokollsignaturen prüft bereits NoVoidReturnOnFunctionSignature. Die zusätzliche SwiftLint-Prüfung expliziter Void-Closure-Rückgabetypen entfällt bewusst; diese Annotation kann Typinferenz verdeutlichen. |
| `shorthand_optional_binding` | Wieder aktiv | 0 | Bevorzugt die vorhandene Swift-Kurzform bei identischer Optional-Bindung; nicht vom Formatter normalisiert. |
| `static_operator` | Wieder aktiv | 0 | Prüft die idiomatische Deklaration von Operatoren; kein aktueller Konflikt. |
| `todo` | Wieder aktiv | 0 | Macht offene TODO/FIXME/XXX-Aufgaben sichtbar. Zusammen mit --strict sind sie bewusst vor einem Commit zu bewerten. |
| `toggle_bool` | Wieder aktiv | 0 | Erkennt die unnötig wiederholte Negationszuweisung und schlägt toggle() vor. |
| `type_name` | Wieder aktiv | 0 | Prüft zusätzlich zur Formatter-Großschreibung Länge und zulässige Typnamen. |
| `unneeded_break_in_switch` | Wieder aktiv | 0 | Erkennt überflüssige break-Anweisungen in Switch-Zweigen; kein Formatter-Gegenstück. |
| `untyped_error_in_catch` | Wieder aktiv | 0 | Erkennt eine unnötige explizite Error-Typannotation in catch. |
| `unused_enumerated` | Wieder aktiv | 0 | Erkennt unnötiges enumerated(), wenn dessen Zusatzwert nicht verwendet wird. |
| `void_function_in_ternary` | Wieder aktiv | 0 | Macht einen Ternär-Ausdruck mit reinem Seiteneffekt sichtbar; eine reguläre Verzweigung beschreibt die Absicht besser. |
| `yoda_condition` | Wieder aktiv | 0 | Verhindert unnötig umgedrehte Vergleiche; konfliktfreie Lesbarkeitsregel, keine Layout-Prüfung. |

## Alle weiteren deaktivierten normalen Regeln

Diese 117 Regeln waren bereits in der 133er-Basis nicht enthalten. Auch ihre
Abwesenheit ist hier ausdrücklich begründet. Zusammen mit den vier Ausnahmen
oben sind damit alle 121 deaktivierten normalen Regeln von SwiftLint 0.65.1
erfasst. Eine bewusste Stilentscheidung ist nicht als Fehlmeldung oder als
vollständige Formatter-Abdeckung ausgewiesen. Die Gründe sind Projektvorgaben,
keine allgemeine Behauptung, diese Regeln seien nutzlos.

| Regel | Einzelbegründung |
| --- | --- |
| `accessibility_label_for_image` | Die Syntaxregel berücksichtigt Labels übergeordneter Controls in HomeMenu/UnsealButton nicht ausreichend. Die acht früheren Hinweise sind keine vollständige Accessibility-Prüfung; mögliche echte Lücken müssen separat geprüft werden. |
| `anonymous_argument_in_multiline_closure` | Verbietet Kurzargumente pauschal in mehrzeiligen Closures; die 135 Treffer betreffen auch normale SwiftUI-/TCA-Ausdrücke. Kein nachgewiesener Defekt. |
| `attribute_name_spacing` | Zusätzliche Abstandsregel für Attribute; Layout bleibt beim Formatter. |
| `attributes` | Erzwingt eine zweite Vorgabe für Zeilenumbrüche an Attributen; der Formatter entscheidet diese bereits. |
| `closing_brace` | Abstände und Zeilenumbrüche vor schließenden Klammern übernimmt der Formatter. |
| `closure_body_length` | Pauschale Zeilenlimits treffen deklarative SwiftUI-Views und TCA-Reducer. Komplexität und Modulgrenzen werden getrennt geprüft. |
| `closure_end_indentation` | Einrückung schließender Closure-Klammern übernimmt der Formatter. |
| `closure_parameter_position` | Position und Umbruch der Closure-Parameter bleiben Formatter-Layout. |
| `closure_spacing` | Leerzeichen innerhalb von Closures übernimmt der Formatter. |
| `collection_alignment` | Zusätzliche vertikale Ausrichtung von Collections kann Formatter-Umbrüchen widersprechen. |
| `colon` | Leerzeichen um Doppelpunkte übernimmt der Formatter. |
| `comma` | Leerzeichen um Kommata übernimmt der Formatter. |
| `comma_inheritance` | Abstände in Vererbungslisten übernimmt der Formatter. |
| `computed_accessors_order` | Zusätzliche Reihenfolgevorgabe für get/set, kein nachgewiesener Funktionsfehler. Keine neue Sortierkonvention neben dem Formatter. |
| `conditional_returns_on_newline` | Eigene Umbruchvorgabe für return in Bedingungen; Layout bleibt beim Formatter. |
| `contrasted_opening_brace` | Erzwingt öffnende Klammern auf eigener Zeile und widerspricht dem verwendeten Formatter-Stil; zuvor 2.015 Meldungen. |
| `control_statement` | NoParensAroundConditions übernimmt die überflüssigen Klammern an Kontrollbedingungen. |
| `custom_rules` | Keine projektspezifische Regex-Regel definiert. Ohne konkretes Prüfmuster gibt es hier keine zusätzliche Prüfung. |
| `direct_return` | Erzwingt das Entfernen benannter Zwischenergebnisse. Diese können Validierungsschritte verständlich machen; kein pauschaler Gewinn. |
| `discouraged_default_parameter` | Verbietet Standardargumente abhängig von der Zugriffsstufe; Defaults gehören hier bewusst zu Package-/Client-APIs. |
| `discouraged_none_name` | Pauschales Verbot des Namens none. Der vorhandene nicht optionale Motion-Effect beschreibt damit sinnvoll keinen Effekt; keine konkrete Optional-Verwechslung belegt. |
| `discouraged_object_literal` | NoPlaygroundLiterals erkennt dieselben Bild-/Farbliterale bereits im Formatter-Lint. |
| `discouraged_optional_boolean` | Die Servermodelle unterscheiden absichtlich fehlende Bool-Felder von false. Die Regel würde diese Information pauschal verbieten. |
| `discouraged_optional_collection` | Die Keychain-Test-Doubles unterscheiden bewusst noch keinen Aufruf (nil) von einem Aufruf mit leerem Dictionary. |
| `duplicate_imports` | OrderedImports übernimmt doppelte Imports bereits; kein zweiter Eigentümer für den Importblock. |
| `empty_enum_arguments` | Optionale Kürzung unbenutzter Enum-Associated-Value-Muster; kein neuer globaler Musterstil neben dem Formatter. |
| `empty_parameters` | Zusätzliche Schreibweisenregel für leere Closure-Parameter. Nicht vom lokalen Formatter abgedeckt; bewusst keine zweite allgemeine Syntaxstilvorgabe. |
| `empty_parentheses_with_trailing_closure` | NoEmptyTrailingClosureParentheses entfernt diese leeren Klammern bereits. |
| `explicit_acl` | Erzwingt explizite Zugriffsstufen auch bei sicheren Sprachdefaults; 611 Treffer ohne entsprechenden Abgrenzungsfehler. |
| `explicit_enum_raw_value` | Verlangt auch bei passenden Swift-Defaults explizite Raw-Values und konkurriert mit redundant_string_enum_value. Wire-Formate werden über Modell-/Vertragstests abgesichert. |
| `explicit_init` | Verbietet .init() pauschal; kontextabhängige Typinferenz ist in SwiftUI/TCA beabsichtigt. |
| `explicit_top_level_acl` | Erzwingt explizite Zugriffsstufen für alle Top-Level-Deklarationen statt die Sprachdefaults zuzulassen. |
| `explicit_type_interface` | Erzwingt explizite Typen auch bei eindeutigen Initialisierungen; 1.057 Treffer, keine entsprechende Fehlerlage. |
| `extension_access_modifier` | Widerspricht der aktiven Formatter-Regel NoAccessLevelOnExtensionDeclaration. |
| `file_header` | Es gibt keinen vorgeschriebenen Datei-Header, den diese Regel prüfen sollte. |
| `file_length` | Pauschales Dateizeilenlimit trifft Test-Suites und Tabellen; die Modulaufteilung folgt docs/architecture.md statt Zeilenzahlen. |
| `file_name` | Dateien enthalten absichtlich mehrere zusammengehörige Typen, etwa Models.swift und FeatureTests.swift; kein Eins-zu-eins-Dateinamenzwang. |
| `file_types_order` | Zusätzliche globale Sortiervorgabe für Typen; Zusammenhang und Lesefluss dürfen die Reihenfolge bestimmen. |
| `function_body_length` | Pauschale Zeilenlimits bewerten ausführliche Validierung und tabellarische Tests als Länge. cyclomatic_complexity bleibt als ergänzender Hinweis aktiv. |
| `function_default_parameter_at_end` | Benannte Parameter sind hier fachlich geordnet, etwa URL, Query und Body; ihre Reihenfolge wird nicht allein wegen eines Defaults geändert. |
| `function_name_whitespace` | Abstände in Funktionssignaturen übernimmt der Formatter. |
| `implicit_getter` | UseSingleLinePropertyGetter übernimmt die redundante get-Schreibweise bereits. |
| `implicit_optional_initialization` | Erzwingt eine Stilentscheidung zwischen implizitem nil und = nil; die Sprachsemantik ist identisch. |
| `implicit_return` | OmitExplicitReturns ist beim Formatter ausdrücklich deaktiviert; keine zweite, widersprechende Return-Stilvorgabe. |
| `inclusive_language` | Keine projektspezifisch abgestimmte Wortliste. Die rein lexikalische Standardliste ist kein Ersatz für die kontextbezogene Prüfung von Bezeichnungen. |
| `indentation_width` | Einrückung übernimmt der Formatter mit zwei Leerzeichen; die frühere Standardregel erzeugte 2.800 Meldungen. |
| `leading_whitespace` | Führende Leerzeilen und Einrückung übernimmt der Formatter. |
| `let_var_whitespace` | Erzwingt zusätzliche Leerzeilen um Variablen statt das Formatter-Layout zu verwenden. |
| `line_length` | lineLength: 100 ist bereits Formatter-Ziel. Lange Literale/URLs sind nicht immer sinnvoll umbrechbar; kein zusätzliches hartes Zeichenlimit. |
| `literal_expression_end_indentation` | Einrückung schließender Collection-Klammern übernimmt der Formatter. |
| `modifier_order` | Zusätzliche Modifier-Sortierkonvention ohne nachgewiesenen semantischen Gewinn; keine neue Layout-/Reihenfolgevorgabe. |
| `multiline_arguments` | Der Formatter entscheidet Umbrüche anhand Breite und bestehender Zeilen; keine zusätzliche Ein-Argument-pro-Zeile-Pflicht. |
| `multiline_arguments_brackets` | Position von Argumentklammern bleibt beim Formatter. |
| `multiline_call_arguments` | Erzwingt ein zweites Schema für Argumentumbrüche und Argumentzahlen pro Zeile. |
| `multiline_function_chains` | Umbruch von Aufrufketten übernimmt der Formatter. |
| `multiline_literal_brackets` | Position der Collection-Klammern übernimmt der Formatter. |
| `multiline_parameters` | Parameterumbrüche übernimmt der Formatter. |
| `multiline_parameters_brackets` | Position von Parameterklammern übernimmt der Formatter. |
| `multiple_closures_with_trailing_closure` | OnlyOneTrailingClosureArgument übernimmt die zusätzliche Vorgabe zu mehreren Closure-Argumenten. |
| `no_extension_access_modifier` | NoAccessLevelOnExtensionDeclaration übernimmt diese Einschränkung bereits. |
| `no_fallthrough_only` | NoCasesWithOnlyFallthrough übernimmt diese Prüfung bereits. Die breitere fallthrough-Regel bleibt zusätzlich aktiv. |
| `no_grouping_extension` | Zusammengehörige Extensions strukturieren hier Implementierungen und Tests bewusst; die Regel verbietet dieses Organisationsmittel pauschal. |
| `no_magic_numbers` | 697 Treffer einschließlich Animationen, Protokollwerten und Test-Fixtures. Nicht jede Zahl erhält durch eine zusätzliche Konstante mehr Bedeutung. |
| `no_space_in_method_call` | Abstand zwischen Funktionsname und Aufrufklammer übernimmt der Formatter. |
| `non_overridable_class_declaration` | Zusätzliche Explizitheitsvorgabe für ohnehin nicht überschreibbare Member. Die Compiler-Semantik sichert die Nichtüberschreibbarkeit bereits. |
| `number_separator` | GroupNumericLiterals übernimmt die Zahlengruppierung bereits. |
| `one_declaration_per_file` | Widerspricht zusammengehörigen Feature-, State-, Action- und Test-Helfertypen; keine künstliche Dateiaufteilung. |
| `opening_brace` | Position und Abstand öffnender Klammern übernimmt der Formatter. |
| `operator_usage_whitespace` | Abstände um Operatoren übernimmt der Formatter. |
| `optional_enum_case_matching` | Optionale Syntaxverkürzung bei Enum-Matching; keine zusätzliche globale Musterschreibweise vorgeschrieben. |
| `pattern_matching_keywords` | Bevorzugt außen stehendes let in Mustern; widerspricht UseLetInEveryBoundCaseVariable des Formatters. |
| `period_spacing` | Abstände an Punkten übernimmt der Formatter. |
| `prefer_asset_symbols` | Die beanstandete SwiftUI-View liegt im Package, das Asset im App-Target. Generierte App-Asset-Symbole sind dort nicht automatisch verfügbar; zuerst Ressourcen-/Modulkonzept klären. |
| `prefer_key_path` | Einzelne Property-Closures durch Keypaths zu ersetzen ist hier eine optionale Schreibweise ohne nachgewiesenen Fehler; keine zusätzliche globale Vorgabe. |
| `prefer_nimble` | Würde eine nicht vorhandene Testbibliothek statt XCTest verlangen; das Projekt nutzt XCTest und Swift Testing. |
| `prefer_self_in_static_references` | Erzwingt Self statt eines expliziten Typnamens. Die Lesbarkeit hängt vom Kontext ab; keine pauschale Umbenennung. |
| `prefer_self_type_over_type_of_self` | Zusätzliche Schreibweisenregel für dynamische/statische Typreferenzen, ohne aktuelle Fehlerbelege; nicht Teil der gewählten Projektvorgaben. |
| `prefer_zero_over_explicit_init` | Erzwingt .zero statt eines expliziten Null-Initializers; beide können die jeweilige fachliche Absicht verständlich ausdrücken. |
| `prefixed_toplevel_constant` | Erzwingt k-Präfixe und widerspricht der verwendeten Swift-Namenskonvention. |
| `private_over_fileprivate` | FileScopedDeclarationPrivacy übernimmt den überlappenden Top-Level-Fall. Für Member wird keine zusätzliche, über Compiler-Sichtbarkeit hinausgehende Access-Level-Stilregel eingeführt. |
| `protocol_property_accessors_order` | Zusätzliche Sortierung von get/set ohne eigenes Projektbedürfnis; kein funktionaler Fehler. |
| `redundant_discardable_let` | Schreibweise für bewusst verworfene Rückgabewerte; keine neue Formatkonvention neben dem Formatter. |
| `redundant_self` | Syntax allein versteht erforderliche self-Bindung in Closures/Makros nicht vollständig; keine pauschale Entfernung. Die ebenfalls deaktivierte explicit_self-Regel würde das Gegenteil erzwingen. |
| `required_deinit` | Erzwingt selbst bei Klassen ohne Aufräumarbeit ein leeres deinit; kein Nachweis eines Ressourcenlecks. |
| `return_arrow_whitespace` | Abstand und Umbruch des Rückgabepfeils übernimmt der Formatter. |
| `self_binding` | Zusätzliche Namenskonvention für self-Rebindings; keine neue Vorgabe für bereits verständliche TCA-/Closure-Bindungen. |
| `shorthand_argument` | Beschränkt Kurzargumente syntaktisch nach Entfernung/Anzahl; die bestehende SwiftUI-/TCA-Lesbarkeit wird kontextbezogen bewertet. |
| `shorthand_operator` | Erzwingt += usw. statt ausgeschriebener Zuweisung; optionale Schreibweise ohne belegten Fehler. |
| `single_test_class` | Mehrere zusammengehörige Testtypen/Suites pro Datei sind beabsichtigt; kein XCTest-/Quick-Dateizwang. |
| `sorted_enum_cases` | Alphabetische Sortierung kann fachliche Reihenfolge und implizite numerische Raw-Values verändern; keine pauschale Sortierung. |
| `sorted_imports` | OrderedImports übernimmt die Importreihenfolge bereits. |
| `statement_position` | Position von else/catch übernimmt der Formatter. |
| `static_over_final_class` | SDK-Overrides von URLProtocol sind als override class func gültig. Beide Varianten wurden typgeprüft; kein Funktionsgewinn durch pauschales static. |
| `strict_fileprivate` | Verbietet sämtliche fileprivate-Deklarationen; dateiweite Test-Helfer und Zugriff zwischen zusammengehörigen Typen sind hier beabsichtigt. |
| `superfluous_else` | UseEarlyExits ist beim Formatter deaktiviert; explizite symmetrische Fehler-/Erfolgszweige bleiben erlaubt. |
| `switch_case_alignment` | Switch-Einrückung übernimmt der Formatter mit indentSwitchCaseLabels: false. |
| `switch_case_on_newline` | OneCasePerLine und die normale Switch-Formatierung übernehmen die Zeilenaufteilung. |
| `syntactic_sugar` | UseShorthandTypeNames übernimmt die Swift-Kurzformen bereits. |
| `trailing_closure` | Erzwingt Trailing-Closures überall, während OnlyOneTrailingClosureArgument diese begrenzt. Kein zweiter pauschaler Closure-Stil. |
| `trailing_comma` | Trailing-Commas übernimmt der Formatter entsprechend Collection- und Umbruchkonfiguration. |
| `trailing_newline` | Der Formatter und der bestehende end-of-file-fixer prüfen das Dateiende bereits. |
| `trailing_semicolon` | DoNotUseSemicolons übernimmt diese Prüfung bereits. |
| `trailing_whitespace` | Der Formatter und der bestehende trailing-whitespace-Hook prüfen diese Leerzeichen bereits. |
| `type_body_length` | Pauschale Zeilenlimits treffen zusammengehörige Feature- und Testtypen; kein Zwang zur rein metrischen Aufteilung. |
| `type_contents_order` | Eine globale Member-Sortierung würde fachliche Gruppierungen ersetzen; keine neue Strukturkonvention eingeführt. |
| `unneeded_parentheses_in_closure_argument` | Optionale Klammern um Closure-Parameter sind kein Funktionsfehler. Der lokale Formatter lässt sie stehen; bewusst keine weitere Syntaxstilvorgabe. |
| `unneeded_synthesized_initializer` | UseSynthesizedInitializer übernimmt diese Prüfung bereits. |
| `unused_optional_binding` | UseExplicitNilCheckInConditions übernimmt die nil-Prüfung bereits. |
| `variable_shadowing` | Die 31 Treffer umfassen absichtliche lokale Snapshots von self.client und self.continuation. Die pauschale Regel unterscheidet diese TCA-/Nebenläufigkeitsmuster nicht ausreichend von versehentlichem Shadowing. |
| `vertical_parameter_alignment` | Vertikale Ausrichtung von Parametern übernimmt der Formatter. |
| `vertical_parameter_alignment_on_call` | Vertikale Ausrichtung von Aufrufargumenten übernimmt der Formatter. |
| `vertical_whitespace` | maximumBlankLines: 1 liegt bereits beim Formatter. |
| `vertical_whitespace_between_cases` | Erzwingt eine zusätzliche Leerzeile zwischen jedem Switch-Case; keine zweite Layoutvorgabe. |
| `vertical_whitespace_closing_braces` | NoEmptyLinesOpeningClosingBraces ist beim Formatter deaktiviert; keine zweite Regel erzwingt diese zusätzliche Leerzeilenkonvention. |
| `vertical_whitespace_opening_braces` | NoEmptyLinesOpeningClosingBraces ist beim Formatter deaktiviert; keine zweite Regel erzwingt diese zusätzliche Leerzeilenkonvention. |
| `void_return` | ReturnVoidInsteadOfEmptyTuple übernimmt die Schreibweise Void statt () bereits. |
| `xct_specific_matcher` | Die 13 Hinweise betreffen eine zusätzliche XCTest-Assertion-Schreibweise, während neue Tests Swift Testing verwenden. Keine pauschale Assertion-Umschreibung; Testinhalte bleiben unverändert. |

## Nicht aktivierte Analyzer-Regeln

Neben `unused_import` und `unused_declaration` enthält SwiftLint 0.65.1 drei
weitere Analyzer-Regeln. Sie waren nicht Teil der 133 normalen Regeln und werden
hier nicht stillschweigend als nutzlos bewertet.

| Regel | Einzelbegründung |
| --- | --- |
| `capture_variable` | Zusätzliche SourceKit-Regel für Capture-Bindungen wurde nicht mit der 133er-Basis evaluiert. Bleibt explizit außerhalb dieser Änderung; nicht als nachgewiesen nutzlos bewertet. |
| `explicit_self` | Würde explizites self auch jenseits der Compileranforderungen erzwingen; keine solche projektweite Stilvorgabe. |
| `typesafe_array_init` | Prüft map { $0 } gegenüber Array(...) mit Typinformationen. Die aktive normale Regel array_init erfasst die aktuelle Stelle bereits; die zusätzliche, nicht separat evaluierte Analyzer-Variante wird nicht als vollständig identisch oder nutzlos bewertet. |

Die Vollständigkeit der Tabellen wurde gegen die installierte SwiftLint-Regelliste
geprüft: 250 normale Regeln = 129 aktiv + 121 einzeln begründet nicht aktiv;
fünf Analyzer-Regeln = zwei aktiv + drei separat begründet nicht aktiv.
`only_rules` erhält diesen geprüften Umfang auch dann, wenn eine spätere
SwiftLint-Version neue Standardregeln mitbringt. Neue Regeln benötigen dann eine
bewusste Prüfung. Die Regelbeschreibungen stammen aus `swiftlint rules <rule>`
der Version 0.65.1; die [offizielle Regelreferenz](https://realm.github.io/SwiftLint/rule-directory.html)
beschreibt Zweck, Beispiele und Optionen.
