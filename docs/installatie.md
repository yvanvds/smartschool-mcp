# Smartschool in Claude Desktop

Met de Smartschool-extensie werkt Claude Desktop met je Smartschool-account.
Je vraagt het gewoon in een gesprek:

- **Berichten:** bekijken, lezen, doorzoeken, samenvatten, als gelezen of
  ongelezen markeren, een gekleurde vlag geven, archiveren, naar de
  prullenbak verplaatsen, beantwoorden en nieuwe berichten versturen. Een
  bericht vertrekt, en een bericht gaat naar de prullenbak, pas nadat jij het
  goedgekeurd hebt.
- **Intradesk:** documenten zoeken op naam, mappen bekijken en bestanden
  lezen. Een nieuwe map, een weblink of bestanden van je pc in een map
  zetten, en mappen, bestanden of weblinks naar de prullenbak van Intradesk
  verplaatsen. Telkens pas nadat jij het goedgekeurd hebt.
- **Planner:** je eigen planner bekijken, en die van klassen, collega's en
  lokalen: lessen, toetsen en taken, en lege lesuren. Per dag zien welke
  toetsen en taken een klas al heeft, om een moment voor een nieuwe toets te
  kiezen, en die toets of taak dan plannen. Je lesfiches uit de module
  Lesfiches lezen, met hun weblinks en bijlagen. Je eigen lesuren invullen
  met lessen of met je lesfiches, die lessen aanpassen en een lesuur weer
  leegmaken. Een toets of taak naar de prullenbak van de planner verplaatsen.
  Telkens pas nadat jij het goedgekeurd hebt.
- **Bestanden bewaren:** bijlagen en Intradesk-bestanden op je pc zetten, zodat
  Claude of jijzelf ze kan openen.
- **Skore**, alleen voor wie er de rechten voor puntenbeheer heeft, zoals een
  Skore-beheerder: de klassen bekijken, de vakken van een klas met de
  leerkrachten die eraan gekoppeld zijn, en de leerkrachten. Een leerkracht
  aan een vak van een klas koppelen, of een lesopdracht een andere
  leerkracht geven. Een puntenboek delen met andere leerkrachten, of dat
  delen stoppen. Telkens pas nadat jij het goedgekeurd hebt. Dat zet je aan
  met **Skore-beheer**.
- **Aanwezigheden**, alleen voor wie de halve-dagaanwezigheden van klassen
  registreert, zoals de afwezigheidsbeheerder of het leerlingensecretariaat:
  per klas en dag zien wat er voor elke leerling 's morgens en 's middags
  geregistreerd is. Leerlingen als te laat markeren, of weer als aanwezig.
  Telkens pas nadat jij het goedgekeurd hebt. Dat zet je aan met
  **Aanwezigheden**.

Gebruik je de ChatGPT-app in plaats van Claude Desktop? Volg dan de
[installatiegids voor ChatGPT](installatie-chatgpt.md).

Deze gids legt uit hoe je de extensie installeert, test, gebruikt, bijwerkt en
weer verwijdert. Lees zeker ook [Veiligheid en privacy](#8-veiligheid-en-privacy)
voor je begint.

De extensie is niet officieel: ze is niet gemaakt door Smartschool en er ook
niet mee verbonden.

## Inhoud

1. [Wat heb je nodig?](#1-wat-heb-je-nodig)
2. [Je 2FA-sleutel opzoeken](#2-je-2fa-sleutel-opzoeken) (alleen met
   tweestapsverificatie)
3. [De extensie installeren](#3-de-extensie-installeren)
4. [Testen](#4-testen)
5. [Wat kun je vragen?](#5-wat-kun-je-vragen)
6. [Bijwerken naar een nieuwe versie](#6-bijwerken-naar-een-nieuwe-versie)
7. [Problemen oplossen](#7-problemen-oplossen)
8. [Veiligheid en privacy](#8-veiligheid-en-privacy)
9. [Verwijderen](#9-verwijderen)
10. [Hulp nodig?](#10-hulp-nodig)

## 1. Wat heb je nodig?

- **Een Windows-pc** die alleen jij gebruikt, met je eigen Windows-account. De
  extensie werkt niet op een Mac.
- **Claude Desktop**, het programma van Claude voor Windows
  ([downloaden](https://claude.ai/download)), en een Claude-account.
- **Een Smartschool-account waarmee je inlogt met een gebruikersnaam en een
  wachtwoord.** Kun je alleen inloggen via Microsoft of Google, dan werkt de
  extensie niet.
- **Tweestapsverificatie met een authenticator-app** op je telefoon, zoals
  Microsoft Authenticator of Google Authenticator, als je account
  tweestapsverificatie gebruikt. Voor leerkrachten is dat zo. Gebruik je nog
  geen authenticator-app, dan stel je er een in bij stap 2. Log je in met
  alleen je wachtwoord, zonder code uit een app, zoals de meeste leerlingen?
  Dan heb je geen authenticator-app nodig.

## 2. Je 2FA-sleutel opzoeken

**Alleen als je tweestapsverificatie gebruikt.** Vraagt Smartschool na je
wachtwoord geen code uit een app, zoals bij de meeste leerlingen? Sla deze
stap dan over en laat de **2FA-sleutel** in stap 3 leeg.

Bij het inloggen vraagt Smartschool een code van zes cijfers uit je
authenticator-app. De extensie logt zelf voor je in en maakt die code zelf.
Daarvoor heeft ze de **2FA-sleutel** nodig: de geheime sleutel waarmee je app
de codes maakt. Dat is een lange reeks letters en cijfers, niet de code van
zes cijfers.

Smartschool toont die sleutel alleen op het moment dat je een
authenticator-app toevoegt. Heb je tweestapsverificatie al ingesteld met een
app op je telefoon, dan stel je ze dus opnieuw in. Je zet dezelfde sleutel
daarna in je telefoonapp én in de extensie, zodat ze allebei werken.

> **Tip:** doe stap 2 en 3 na elkaar, zonder tussendoor iets anders te
> kopiëren. Dan staat de sleutel nog op je klembord als je het formulier van
> de extensie invult.

1. Log in op Smartschool in je browser, op de pc waarop je de extensie
   installeert.
2. Open je **profiel** en kies **Tweestapsverificatie**.
3. Kies om een **authenticator-app toe te voegen**.
4. Smartschool toont een QR-code. Scan die niet, maar kies de optie voor als
   je **geen camera** hebt. Smartschool toont dan de sleutel.
5. Selecteer de sleutel en kopieer hem (Ctrl+C).
6. Neem je telefoon en open je authenticator-app. Voeg een account toe en kies
   om een sleutel **zelf in te voeren**, in plaats van een QR-code te scannen.
   Geef het account een naam, bijvoorbeeld Smartschool, en typ de sleutel
   over.
7. Smartschool vraagt een code van zes cijfers om te bevestigen. Typ de code
   die je telefoonapp nu toont.

De knoppen kunnen in jouw Smartschool iets anders heten.

<!-- SCHERMAFBEELDING (#33): het profiel met Tweestapsverificatie, een
authenticator-app toevoegen, de QR-code met de optie zonder camera, en de
sleutel (onleesbaar gemaakt). Controleer daarbij de namen van de knoppen
hierboven. -->

Gebruik voortaan dit nieuwe account in je telefoonapp. Werkt een ouder
Smartschool-account in je app niet meer, dan mag je dat verwijderen.

> **Bewaar de sleutel nergens anders:** niet in een bestand, niet in een
> e-mail en niet op papier. Wie je wachtwoord en deze sleutel heeft, kan in
> jouw naam inloggen op Smartschool. Ben je de sleutel kwijt voor je hem in de
> extensie hebt ingevuld? Begin dan opnieuw bij punt 2. Je krijgt een nieuwe
> sleutel, die je ook weer in je telefoonapp zet.

## 3. De extensie installeren

1. Ga naar de
   [releasepagina](https://github.com/yvanvds/smartschool-mcp/releases/latest)
   en klik onder **Assets** op `smartschool-mcp.mcpb`, of download het bestand
   meteen:
   [smartschool-mcp.mcpb](https://github.com/yvanvds/smartschool-mcp/releases/latest/download/smartschool-mcp.mcpb).
   Download de extensie alleen van die releasepagina.
2. Dubbelklik op het gedownloade bestand (meestal in je map Downloads).
   Vraagt Windows met welke app je het bestand wilt openen? Kies dan
   **Claude**. Dat vraagt Windows alleen de eerste keer. Claude Desktop opent
   en toont de Smartschool-extensie. Klik op **Installeren** (*Install*).
3. Vul het formulier in:

   | Veld | Wat vul je in? |
   | --- | --- |
   | **Smartschool-adres** | Het adres van je school op Smartschool, bijvoorbeeld `school.smartschool.be`. Je mag het ook uit de adresbalk van je browser kopiëren. |
   | **Gebruikersnaam** | De gebruikersnaam waarmee je inlogt op Smartschool. |
   | **Wachtwoord** | Je wachtwoord voor Smartschool. |
   | **2FA-sleutel** (alleen met tweestapsverificatie) | De sleutel uit stap 2 (plak hem met Ctrl+V). Niet de code van zes cijfers. Spaties in de sleutel zijn geen probleem. Log je in met alleen je wachtwoord, laat dit veld dan leeg. |
   | **Downloadmap** (niet verplicht) | De map waarin Claude bestanden uit Smartschool bewaart. Zie hieronder. |
   | **Skore-beheer** (niet verplicht) | Alleen als je in Skore de rechten hebt voor puntenbeheer (Rapporten > Modellen en Puntenboeken), zoals een Skore-beheerder: zet het aan. Zie [Skore](#skore). De meeste leerkrachten en alle leerlingen laten het uit. |
   | **Aanwezigheden** (niet verplicht) | Alleen als je in Smartschool de halve-dagaanwezigheden van klassen registreert, zoals de afwezigheidsbeheerder of het leerlingensecretariaat: zet het aan. Zie [Aanwezigheden](#aanwezigheden). De meeste leerkrachten en alle leerlingen laten het uit. |

4. Sla het formulier op en zorg dat de extensie aan staat (ingeschakeld).

<!-- SCHERMAFBEELDING (#33): de releasepagina met smartschool-mcp.mcpb onder
Assets, het installatievenster van Claude Desktop en het formulier (zonder
echte gegevens). -->

Waarschuwt Windows of je virusscanner bij het downloaden of installeren? Lees
dan eerst [Windows of je virusscanner waarschuwt](#windows-of-je-virusscanner-waarschuwt).

### Welke downloadmap kies je?

Vraag je Claude om een bijlage of een Intradesk-bestand te openen of te
bewaren, dan zet de extensie het in de downloadmap.

- **Werk je met Cowork in Claude Desktop?** Kies dan een (tijdelijke) map in
  je Cowork-project. Claude kan de bestanden die het daar bewaart dan zelf
  openen: PDF's, scans, Word, Excel en afbeeldingen.
- **Laat je het veld leeg,** dan komen de bestanden in `Downloads\Smartschool`
  in je gebruikersmap. Claude zegt dan waar een bestand staat, zodat je het
  zelf kunt openen of in het gesprek kunt slepen.

De extensie verwijdert de bestanden die ze zelf bewaarde na 7 dagen (zie
[Bestanden bewaren](#bestanden-bewaren)).

### Later iets aanpassen

Je kunt alles later aanpassen in Claude Desktop, via **Instellingen →
Extensies → Smartschool** (*Settings → Extensions*). Herstart Claude Desktop
daarna.

**Claude Desktop herstarten:** sluit het helemaal af en open het opnieuw.
Klik om af te sluiten met de rechtermuisknop op het Claude-pictogram
rechtsonder in de taakbalk en kies **Afsluiten** (*Quit*), of gebruik in
Claude Desktop het menu **Bestand → Afsluiten** (*File → Exit*). Het venster
sluiten met het kruisje is niet altijd genoeg: Claude kan dan op de
achtergrond blijven draaien.

## 4. Testen

Open een nieuw gesprek in Claude Desktop en vraag:

> Werkt mijn Smartschool-verbinding?

Vraagt Claude Desktop of Claude de Smartschool-extensie mag gebruiken? Sta dat
toe. De eerste keer duurt het inloggen enkele seconden. Daarna onthoudt de
extensie je sessie.

Claude antwoordt met:

- of de verbinding werkt, en als wie je bent ingelogd;
- het adres van je school;
- je downloadmap, en of de extensie daar bestanden kan bewaren;
- de versie van de extensie, en of er een nieuwere is.

Werkt de verbinding niet, dan zegt Claude wat je moet aanpassen. Zie ook
[Problemen oplossen](#7-problemen-oplossen).

<!-- SCHERMAFBEELDING (#33): het antwoord op "Werkt mijn
Smartschool-verbinding?". -->

## 5. Wat kun je vragen?

Vraag het gewoon in je eigen woorden. Een paar voorbeelden:

### Berichten

- "Zoek mijn berichten van deze week over het oudercontact en vat ze samen."
- "Heb ik ongelezen berichten van de directie?"
- "Welke berichten in mijn postvak mag ik archiveren?"
  Claude stelt dan berichten voor. Pas als je zegt "Archiveer ze", verplaatst
  het ze naar je archief in Smartschool. Daar vind je ze terug.
- "Markeer de berichten van de directie van vorige week als gelezen."
  Claude leest een bericht voor jou zonder het als gelezen te markeren. Dat
  doet het pas als je het vraagt.
- "Zet een rode vlag op de berichten waar ik nog op moet antwoorden."
- "Gooi de nieuwsbrieven van vorige maand weg."
  Claude toont eerst welke berichten naar de prullenbak gaan, en wacht op
  jouw akkoord. Daarna vraagt Claude Desktop nog eens toestemming. De
  berichten komen in de prullenbak van Smartschool: zolang je die niet
  leegmaakt, kun je ze daar zelf terugzetten. Claude kan dat niet.
- "Beantwoord het bericht van An over de uitstap: ik ga graag mee."
  Claude toont eerst de tekst en de ontvangers, en wacht op jouw akkoord.
  Daarna vraagt Claude Desktop nog eens toestemming om te versturen. Kies daar
  liefst niet om het altijd toe te staan, dan blijft Claude Desktop het elke
  keer vragen. Het antwoord vertrekt vanuit jouw account, als antwoord op het
  oorspronkelijke bericht.
- "Stuur Sven Lamber een bericht: de toets van vrijdag gaat niet door."
  Claude zoekt eerst wie Sven Lamber is en toont de ontvangers (met hun
  klas), het onderwerp en de tekst, en wacht op jouw akkoord. Vindt het
  meer dan één Sven Lamber, of niemand met die naam, dan vraagt Claude wie
  je bedoelt: het kiest nooit zelf. Je kunt ook een groep kiezen, zoals een
  klas: dan krijgen alle leden het bericht. Daarna vraagt Claude Desktop nog
  eens toestemming om te versturen.
- "Open de bijlage van het bericht van de directie."

### Intradesk

- "Zoek op Intradesk het formulier voor een uitstap."
- "Wat staat er in de map Vergaderingen op Intradesk?"
- "Vat het verslag van de laatste personeelsvergadering op Intradesk samen."
- "Bewaar het formulier voor de uitstap van Intradesk."
- "Zet de brief voor de ouders die we net gemaakt hebben in de map Brieven
  op Intradesk."
  Claude zoekt eerst de map. Het toont welke bestanden (met hun naam en
  grootte) in welke map komen, en wacht op jouw akkoord. Daarna vraagt
  Claude Desktop nog eens toestemming. Iedereen die de map kan zien, ziet
  het bestand meteen. Claude kan alleen bestanden doorgeven die op je pc
  staan: je eigen bestanden, of wat Claude in je Cowork-project maakte. Een
  bestand groter dan 200 MB zet je zelf op Intradesk.
- "Maak op Intradesk in de map Informatica een map Toetsen 2026, met een
  weblink naar de oefensite."
  Ook een nieuwe map of een weblink komt er pas na jouw akkoord. Staat er in
  de map al iets met dezelfde naam, dan zet Claude er niets bij en vraagt
  het wat je wilt: Intradesk zou het nieuwe item anders zelf een andere naam
  geven, zoals `brief (1).docx`. In een map waar je niets mag toevoegen,
  zegt Claude dat ook.
- "Gooi de map Toetsen 2025 op Intradesk weg."
  Claude zoekt eerst de map en toont wat er naar de prullenbak van
  Intradesk gaat, met het pad. Een map gaat met alles erin naar de
  prullenbak. Pas na jouw akkoord verplaatst Claude ze; daarna vraagt Claude
  Desktop nog eens toestemming. Intradesk bewaart de prullenbak 30 dagen:
  tot dan zet je zelf iets terug vanuit de prullenbak in Intradesk. Claude
  kan niets terugzetten en niets voor altijd verwijderen.

### Planner

- "Wat staat er deze week in mijn planner?"
- "Toon de planner van 6WEWI1 voor volgende week."
  Claude zoekt eerst de planner van de klas. Daarin staan de lessen, toetsen
  en taken van alle leerkrachten van de klas, en elk lesuur van hun
  lessenrooster dat nog leeg is. Wil je alleen de toetsen en taken, zeg het
  dan erbij.
- "Wat geeft meneer Peeters op dinsdag?"
  Vindt Claude meer dan één persoon met die naam, dan vraagt het wie je
  bedoelt. Leerlingen en personeel staan door elkaar in de zoekresultaten.
- "Is lokaal 611 vrij woensdag het 3e uur?"
  Claude kent de uren van je school niet vanzelf: zeg erbij hoe laat dat uur
  begint, of laat Claude het afleiden uit je eigen planner.
- "Wat moeten de leerlingen meebrengen voor mijn les van morgen in 5WW1?"
  Claude leest dan de info van die les. De info voor leerlingen zien je
  leerlingen. De privé-info zien je leerlingen niet, maar collega's die de les
  kunnen zien, lezen ze wel.
- "Wanneer kan ik best een toets plannen in 6WEWI1?"
  Claude bekijkt welke toetsen en taken de klas de komende vier weken al
  heeft, van alle leerkrachten, en wanneer jij de klas hebt. Het stelt dan
  een paar momenten voor, en jij kiest. Heeft je school in de planner een
  grens gezet voor de werkbelasting van de klas, dan noemt Claude die ook.
- "Welke toetsen heeft 5WW1 volgende week?"
- "Vul mijn lessen informatica van volgende week in volgens dit plan: ..."
  Claude zoekt eerst je lege lesuren van volgende week. Het toont per lesuur
  de dag, het uur, de klas, het vak, en de titel en info die het wil
  invullen, en wacht op jouw akkoord. Daarna vraagt Claude Desktop per lesuur
  nog eens toestemming. Je leerlingen zien de titel en de info voor
  leerlingen meteen. Claude verandert alleen je eigen planner: de lessen van
  collega's raakt het niet aan.
- "Zet bij mijn les van dinsdag in 5WW1 dat ze hun rekenmachine moeten
  meebrengen."
  Claude past de titel, de info voor leerlingen of de privé-info van een
  les, toets of taak aan, na jouw akkoord. De nieuwe info vervangt de oude.
- "Maak mijn les van vrijdag het 3e uur weer leeg."
  De les verdwijnt met haar titel en info, en het lesuur is weer leeg. Dat
  kun je niet ongedaan maken: Claude vraagt eerst je akkoord.
- "Plan mijn lesfiches van JAAR 6, trimester 1 in mijn komende lessen
  informatica van 6A1, in volgorde."
  Claude zoekt je lesfiches met die labels en je lege lesuren, en stelt voor
  welke lesfiche in welk lesuur komt. Na jouw akkoord plant het ze, één per
  lesuur. De les krijgt de naam en de inhoud van de lesfiche. Alleen lessen
  kunnen zo: een lesfiche van een toets of taak niet.
- "Wat staat er in mijn lesfiche over recursie? Vat de bijlage samen."
  Claude zoekt de lesfiche en leest ze: de info voor leerlingen, je
  privé-info, de weblinks en de bijlagen, en wanneer je leerlingen die zien.
  Een bijlage leest Claude, of het bewaart ze in je downloadmap. Aan de
  lesfiche verandert niets.
- "Plan een kleine overhoring over hoofdstuk 3 in 6WEWI1, dinsdag het 3e
  uur."
  Claude zoekt dat lesuur in je planner en kijkt eerst welke toetsen en taken
  de klas al heeft. Het toont de klas, de dag en het uur, het soort toets, de
  titel en de info, en wacht op jouw akkoord. Je leerlingen zien de toets
  meteen in de planner. Claude kondigt de toets niet aan: dat doe je, als je
  wilt, zelf in Smartschool. Een toets plant Claude altijd in een van je
  eigen lesuren; heb je dat uur met twee klassen, zeg dan voor welke klas
  hij is.
- "Haal de toets van dinsdag in 6WEWI1 weg."
  Claude verplaatst je toets of taak naar de prullenbak van de planner, na
  jouw akkoord. Daar kun je ze in Smartschool nog 30 dagen terugzetten.

### Skore

Alleen met **Skore-beheer** aan, en alleen voor wie in Skore de rechten heeft
voor puntenbeheer: Rapporten > Modellen en Puntenboeken, zoals een
Skore-beheerder. De meeste leerkrachten en alle leerlingen hebben die rechten
niet. Zet je **Skore-beheer** aan zonder die rechten, dan zegt Claude dat je
account ze niet heeft; vraag ze dan aan de Smartschool-beheerder van je
school, of zet **Skore-beheer** weer uit.

- "Wie geeft wiskunde in 3B1?"
- "Welke vakken van 5WW1 hebben nog geen leerkracht?"
- "Aan welke vakken is mevrouw Dupré gekoppeld in 5WW1?"
- "Koppel mevrouw Dupré aan Project 2 van Eye4Skills in 5WW1."
  Claude zoekt de klas, het vak en de leerkracht op, toont wat het gaat
  koppelen, en koppelt pas na jouw akkoord. Daarna vraagt Claude Desktop
  nog eens toestemming. Het vak krijgt zo een nieuwe lesopdracht, met alle
  leerlingen van de klas. De leerkrachten die al aan het vak gekoppeld
  waren, blijven gekoppeld.
- "Wiskunde in 3B1 krijgt meneer Janssens in plaats van mevrouw Maes."
  Claude geeft de lesopdracht een andere leerkracht, na jouw akkoord. De
  lesopdracht en haar puntenboek blijven: alleen de leerkracht verandert.
  Werkt de huidige leerkracht voor dat vak met **Mijn lesgroepen**, dan
  verandert Claude niets: regel die groepen eerst zelf in Skore.
- "Met wie is het puntenboek Digitale vaardigheden van 5WW1 gedeeld?"
- "Deel het puntenboek Digitale vaardigheden van 5WW1 met de andere
  leerkrachten van de klas, om te lezen."
  Claude zoekt de klas, het vak en de lesopdracht van de titularis op (dat
  is het puntenboek), en de andere leerkrachten van de klas. Het toont welk
  puntenboek het met wie gaat delen, en deelt pas na jouw akkoord, met alle
  leerkrachten in één keer. Daarna vraagt Claude Desktop nog eens
  toestemming. Wie het puntenboek kan lezen of wijzigen, ziet de punten van
  de leerlingen erin. Een leerkracht die het al mocht wijzigen en het nu
  alleen mag lezen (of omgekeerd), krijgt de nieuwe toegang.
- "Stop het delen van dat puntenboek met meneer Peeters."

Claude verandert in Skore alleen iets na jouw akkoord: telkens voor één vak
van één klas, of voor één puntenboek. Loopt het delen bij een leerkracht
mis, dan stopt Claude daar en zegt het voor elke leerkracht wat er gebeurd
is. Een lesopdracht verwijderen, de leerlingen van een lesopdracht kiezen of
lesopdrachten importeren kan Claude niet: dat doe je zelf in Skore.

### Aanwezigheden

Alleen met **Aanwezigheden** aan, en alleen voor wie in Smartschool de
halve-dagaanwezigheden van klassen mag registreren, zoals de
afwezigheidsbeheerder of het leerlingensecretariaat. Het gaat om de
registratie per voormiddag en namiddag, die voor de overheid telt, niet om
de registratie per lesuur. De meeste leerkrachten en alle leerlingen hebben
die rechten niet. Zet je **Aanwezigheden** aan zonder die rechten, dan zegt
Claude dat je account ze niet heeft; vraag ze dan aan de
Smartschool-beheerder van je school, of zet **Aanwezigheden** weer uit.

- "Wie was er vanmorgen te laat in 1A?"
- "Wat staat er vandaag geregistreerd voor 3B1?"
- "De bus van lijn 5 was vanmorgen een kwartier te laat: zet Emma Janssens en
  Lotte Peeters uit 1A op te laat, met als motivatie 'bus lijn 5'."
  Claude zoekt de klas en de leerlingen op, toont wat het gaat registreren
  (de klas, de leerlingen, de halve dag, te laat en de motivatie), en
  registreert pas na jouw akkoord, voor alle leerlingen in één keer. Daarna
  vraagt Claude Desktop nog eens toestemming.
- "Zet Mila Claes vanmiddag op te laat zonder geldige reden."
- "Lotte Peeters was toch op tijd: zet haar weer op aanwezig."

Claude verandert alleen een halve dag waarop nog niets staat, of aanwezig of
te laat (met of zonder geldige reden). Een andere registratie, zoals een
afwezigheid die het secretariaat invulde, overschrijft Claude nooit: dan
verandert het voor niemand iets en zegt het welke leerling het betreft. Een
dag in de toekomst kan niet. Loopt het bij een leerling mis, dan stopt
Claude daar en zegt het voor elke leerling wat er gebeurd is. Na het
registreren leest Claude de klas opnieuw en zegt het wat er nu staat. Andere
codes (zoals ziek of een attest), het bevestigen van aanwezigheden en de
registratie per lesuur kan Claude niet: dat doe je zelf in Smartschool.

### Bestanden bewaren

Vraag je Claude om een bijlage of een Intradesk-bestand te openen of te
bewaren, dan zet de extensie het in je downloadmap. Staat die map in je
Cowork-project, dan opent Claude het bestand zelf. In een gewoon gesprek zegt
Claude waar het bestand staat: open het zelf, of sleep het in het gesprek.

> **Bewaarde bestanden verdwijnen na 7 dagen.** De extensie verwijdert de
> bestanden die ze zelf bewaarde 7 dagen later. Andere bestanden in die map
> raakt ze nooit aan, en een bewaard bestand dat jij intussen veranderd hebt,
> laat ze staan. Wil je een bestand houden, verplaats het dan of bewaar het
> ergens anders. Laat het bestandje `.smartschool-mcp-downloads.json` in die
> map staan: daarin houdt de extensie bij welke bestanden van haar zijn.

### Goed om te weten

- Claude leest een bericht zonder het als gelezen te markeren.
- De eerste zoekopdracht in een volle mailbox kan onvolledig zijn: per keer
  haalt de extensie de tekst van hoogstens 100 berichten op. Claude zegt het
  als niet alles doorzocht is; vraag het dan gewoon nog eens. Daarna gaat
  zoeken snel, want de extensie onthoudt de tekst (zie
  [Veiligheid en privacy](#8-veiligheid-en-privacy)).
- Op Intradesk zoekt de extensie op de **namen** van mappen en bestanden, niet
  in de tekst van de bestanden. De eerste keer maakt ze een lijst van alles op
  Intradesk. Dat duurt enkele minuten, en tot die lijst klaar is, kunnen
  resultaten onvolledig zijn; Claude zegt dat dan. De lijst wordt elke dag
  vernieuwd. Mist er iets nieuws, vraag Claude dan om de lijst te vernieuwen.
- Claude kan deze bestanden lezen: Word, Excel, PowerPoint, PDF (alleen de
  tekst: een ingescande PDF heeft geen tekst), tekstbestanden (`.txt`, `.csv`,
  `.md`), webpagina's en afbeeldingen.
- Niet: oude Office-bestanden (`.doc`, `.xls`, `.ppt`), bestanden met een
  wachtwoord, OpenDocument-bestanden (`.odt`, `.ods`, ...) en bestanden groter
  dan 25 MB. Vraag Claude zo'n bestand dan te bewaren (tot 200 MB) en open het
  zelf.
- De extensie werkt alleen met berichten, Intradesk, de planner, met
  **Skore-beheer** aan Skore, en met **Aanwezigheden** aan de
  halve-dagaanwezigheden. Andere onderdelen van Smartschool kent ze
  niet. Op Intradesk maakt ze mappen en weblinks, zet ze bestanden van je
  pc in een map en verplaatst ze mappen, bestanden en weblinks naar de
  prullenbak: iets hernoemen of naar een andere map verplaatsen, een nieuwe
  versie van een bestand zetten, iets uit de prullenbak terugzetten of voor
  altijd verwijderen kan ze niet. In Skore leest ze de klassen, vakken, leerkrachten en gedeelde
  puntenboeken, koppelt ze leerkrachten aan vakken en deelt ze puntenboeken:
  een lesopdracht verwijderen kan ze niet. In de
  planner
  verandert ze alleen je eigen planner: ze vult je lesuren in, plant toetsen
  en taken in je lesuren, past je eigen lessen, toetsen en taken aan, maakt
  lesuren weer leeg en verplaatst je toetsen en taken naar de prullenbak.
  Een toets of taak aankondigen, ze uit de prullenbak terugzetten of voor
  altijd verwijderen kan ze niet: dat doe je zelf in Smartschool. In de
  module Lesfiches leest ze je lesfiches alleen: ze verandert er niets in.
- Net na een wijziging in de planner (in Smartschool zelf of door Claude)
  kan het overzicht nog enkele seconden de oude toestand tonen. Een les of
  toets apart openen toont meteen de nieuwe.

## 6. Bijwerken naar een nieuwe versie

Eén keer per dag kijkt de extensie op GitHub of er een nieuwe versie is. Is
die er, dan meldt Claude dat in een antwoord, met het nieuwe versienummer, een
downloadlink naar `smartschool-mcp.mcpb` en in een paar woorden wat er nieuw
is. Sla je versies over, dan hoor je wat er nieuw is in elke versie die je
overslaat. Dat gebeurt één keer, niet bij elk antwoord. Ook "Werkt mijn
Smartschool-verbinding?" toont altijd of er een nieuwere versie is, met de
downloadlink en wat er nieuw is.

<!-- SCHERMAFBEELDING (#33): een antwoord van Claude met de melding dat er
een nieuwe versie is. -->

Zo werk je bij:

1. Klik op de downloadlink uit het antwoord van Claude: die downloadt
   `smartschool-mcp.mcpb` van de releasepagina (de link begint met
   `https://github.com/yvanvds/smartschool-mcp/releases/`). Geen
   downloadlink? Open dan de
   [releasepagina](https://github.com/yvanvds/smartschool-mcp/releases/latest)
   en download `smartschool-mcp.mcpb` (onder **Assets**).
2. Dubbelklik op het bestand. Claude Desktop installeert de nieuwe versie over
   de oude; volg wat het op het scherm vraagt.
3. Herstart Claude Desktop en vraag "Werkt mijn Smartschool-verbinding?".
   Controleer dat de verbinding werkt en dat de nieuwe versie draait.

**Je instellingen.** Vraagt Claude Desktop bij het bijwerken opnieuw om het
formulier, of meldt de test daarna dat er instellingen ontbreken? Vul ze dan
opnieuw in via **Instellingen → Extensies → Smartschool** en herstart Claude
Desktop. Heb je je 2FA-sleutel niet meer, stel dan je authenticator-app
opnieuw in zoals in [stap 2](#2-je-2fa-sleutel-opzoeken).

<!-- TE BEVESTIGEN (#30): bewaart Claude Desktop de ingevulde instellingen
als je een nieuwere .mcpb over een oudere installeert? Zodra dat bekend is:
schrijf hier wat er gebeurt, en schrap wat niet van toepassing is. -->

Wat de extensie onthield (je sessie, de tekst van doorzochte berichten, de
lijst van Intradesk) blijft bewaard.

## 7. Problemen oplossen

Werkt er iets niet, vraag dan eerst "Werkt mijn Smartschool-verbinding?".
Claude zegt wat er misloopt en wat je moet aanpassen. Je instellingen pas je
aan via **Instellingen → Extensies → Smartschool**; herstart Claude Desktop
daarna.

### Smartschool aanvaardt je gebruikersnaam of wachtwoord niet

- Controleer **Gebruikersnaam** en **Wachtwoord**. Veranderde je onlangs je
  Smartschool-wachtwoord, vul dan ook hier het nieuwe in.
- Kun je alleen inloggen via Microsoft of Google, dan werkt de extensie niet.

Na een geweigerd wachtwoord probeert de extensie het niet opnieuw tot je
Claude Desktop herstart. Pas dus eerst je gegevens aan en herstart dan pas:
te veel mislukte pogingen na elkaar kunnen je Smartschool-account blokkeren.

### De 2FA-sleutel is niet geldig

Dan staat bij **2FA-sleutel** iets anders dan de sleutel uit
[stap 2](#2-je-2fa-sleutel-opzoeken): vaak de code van zes cijfers uit je app,
of een tikfout. De sleutel bestaat alleen uit letters en de cijfers 2 tot 7;
spaties mogen. Vul de juiste sleutel in en herstart Claude Desktop. Zolang de
sleutel niet klopt, probeert de extensie niet in te loggen.

### Smartschool vraagt een 2FA-code, maar de 2FA-sleutel is leeg

Je account gebruikt tweestapsverificatie: na je wachtwoord vraagt Smartschool
een code uit een authenticator-app. Zoek je 2FA-sleutel op zoals in
[stap 2](#2-je-2fa-sleutel-opzoeken), vul hem in bij **2FA-sleutel** en
herstart Claude Desktop. Tot dan probeert de extensie niet opnieuw in te
loggen.

### Smartschool weigert de 2FA-code

- Controleer de **2FA-sleutel**: het moet de sleutel uit
  [stap 2](#2-je-2fa-sleutel-opzoeken) zijn.
- Controleer de klok van je pc. De codes hangen af van de juiste tijd. Open de
  Windows-instellingen, kies **Tijd en taal → Datum en tijd** en zet **Tijd
  automatisch instellen** aan. Klik eventueel op **Nu synchroniseren**.
- Stelde je tweestapsverificatie in Smartschool opnieuw in? Dan heb je een
  nieuwe sleutel: vul die in.

### Claude meldt een onverwachte fout

Probeer het over een ogenblik opnieuw. Blijft het gebeuren, herstart dan
Claude Desktop.

### Smartschool vraagt een geboortedatum, of een andere soort tweestapsverificatie

De extensie werkt alleen met een authenticator-app. Stel er een in zoals in
[stap 2](#2-je-2fa-sleutel-opzoeken), vul de sleutel in en herstart Claude
Desktop.

### Smartschool is niet bereikbaar

Controleer de internetverbinding van je pc, en controleer of
**Smartschool-adres** het adres van je school is, zoals
`school.smartschool.be`.

### Er ontbreken instellingen

Vul de velden in die Claude noemt en herstart Claude Desktop.

### De downloadmap is niet beschrijfbaar

Meldt de test dat de downloadmap niet beschrijfbaar is (in het Engels:
"Download folder: ... NOT writable"), dan kan de extensie daar geen bestanden
bewaren. Kies een andere map bij **Downloadmap** en herstart Claude Desktop.

### Claude kent Smartschool niet, of de extensie verschijnt niet

- Kijk bij **Instellingen → Extensies** of Smartschool er staat en aan staat.
- Herstart Claude Desktop helemaal (zie
  [Later iets aanpassen](#later-iets-aanpassen)).
- Opent dubbelklikken op `smartschool-mcp.mcpb` Claude Desktop niet? Open dan
  Claude Desktop, ga naar **Instellingen → Extensies** en installeer het
  bestand van daaruit: sleep het in het venster, of zoek bij de geavanceerde
  instellingen de knop om een extensie te installeren.
- Gebruik je een Claude-account van je school of organisatie? Dan kan de
  beheerder extensies uitgeschakeld hebben. Vraag het na.

### Windows of je virusscanner waarschuwt

Normaal waarschuwt Windows (SmartScreen) niet: `smartschool-mcp.mcpb` is
zelf geen programma, en je opent het met Claude Desktop. Het programma in de
extensie is wel niet digitaal ondertekend, dus Windows kent de maker niet.
Download de extensie daarom alleen van de
[releasepagina](https://github.com/yvanvds/smartschool-mcp/releases/latest).
Waarschuwt Windows of je virusscanner toch, of verdwijnt de extensie meteen
na het installeren? Klik dan niet zomaar verder, maar vraag eerst raad (zie
[Hulp nodig?](#10-hulp-nodig)).

## 8. Veiligheid en privacy

### Wat bewaart de extensie, en waar?

| Wat | Waar |
| --- | --- |
| Je instellingen: adres, gebruikersnaam, wachtwoord, 2FA-sleutel, downloadmap, Skore-beheer en Aanwezigheden | In Claude Desktop, op deze pc |
| Je Smartschool-sessie, zodat de extensie niet bij elke vraag opnieuw moet inloggen | `%USERPROFILE%\.cache\smartschool\<gebruikersnaam>\` |
| De tekst van de berichten die Claude doorzocht | `%USERPROFILE%\.cache\smartschool\<gebruikersnaam>\messages\<schooladres>\` |
| De lijst van Intradesk: namen en mappen, niet wat er in de bestanden staat (op een grote Intradesk zo'n 10 MB) | `%USERPROFILE%\.cache\smartschool\<gebruikersnaam>\intradesk\<schooladres>\index.json` |
| Wanneer de extensie het laatst naar een nieuwe versie keek, en wat ze vond | `%USERPROFILE%\.cache\smartschool\smartschool-mcp-update-check.json` |
| De bijlagen en Intradesk-bestanden die Claude bewaarde | Je downloadmap, 7 dagen lang |

`%USERPROFILE%` is je gebruikersmap, bijvoorbeeld `C:\Users\jan.peeters`.
Typ `%USERPROFILE%\.cache\smartschool` in de adresbalk van Verkenner om die
map te openen.

- **De tekst van je berichten, de lijst van Intradesk en de bewaarde
  bestanden zijn niet versleuteld.** Ze staan zoals ze zijn op je pc, in je
  Windows-profiel of in je downloadmap. Iedereen die op je Windows-account kan
  inloggen, en wie beheerder is van de pc, kan ze lezen. Staat je downloadmap
  in een Cowork-project, dan horen de bewaarde bestanden ook bij dat project.
- **Je mag alles in `%USERPROFILE%\.cache\smartschool` altijd verwijderen,**
  liefst met Claude Desktop afgesloten. De extensie logt dan opnieuw in en
  haalt opnieuw op wat ze nodig heeft.
- Bewaarde bestanden zijn persoonlijke gegevens of gegevens van de school.
  Ze verdwijnen na 7 dagen; verplaats wat je wilt houden.

### Je pc wordt je tweede factor

Tweestapsverificatie beschermt je account doordat je naast je wachtwoord iets
nodig hebt dat alleen jij hebt: je telefoon. De extensie bewaart je wachtwoord
én je 2FA-sleutel op je pc. Wie op je pc kan, heeft dus allebei. Zonder
tweestapsverificatie bewaart ze alleen je wachtwoord, en dan is dat genoeg om
in jouw naam in te loggen. Daarom:

- **Vergrendel je pc altijd als je wegloopt:** Windows-toets + L.
- Bescherm je Windows-account met een wachtwoord of een pincode.
- Installeer de extensie niet op een pc die je met anderen deelt, zoals de pc
  in een klaslokaal, en niet op een gedeeld Windows-account.
- Is je pc gestolen of kwijt? Verander dan je Smartschool-wachtwoord en stel
  je tweestapsverificatie opnieuw in, als je die gebruikt.

### Wat gaat er naar Claude?

- Vraag je Claude iets over een bericht, een bijlage of een document, dan
  geeft de extensie de inhoud daarvan aan Claude. Die gaat dan naar de servers
  van Anthropic, het bedrijf achter Claude, net zoals alles wat je zelf in het
  gesprek typt. Daar horen ook namen en gegevens van collega's, leerlingen en
  ouders bij.
- **Ga na of dat mag volgens het privacybeleid van je school,** en vraag het
  bij twijfel aan je directie of aan de privacyverantwoordelijke (DPO) van je
  school. Wees extra voorzichtig met gevoelige gegevens over leerlingen, zoals
  hun gezondheid, zorg of thuissituatie.
- Met **Aanwezigheden** aan gaan ook de aanwezigheden en afwezigheden van
  leerlingen naar Claude, met de motivatie die erbij staat. Ook dat zijn
  gegevens over leerlingen, en een afwezigheid of haar motivatie kan iets
  zeggen over hun gezondheid of thuissituatie.
- Kijk in de privacy-instellingen van je Claude-account wat er met je
  gesprekken mag gebeuren.
- Je wachtwoord en je 2FA-sleutel gaan nooit naar Claude: de extensie gebruikt
  ze alleen om in te loggen op Smartschool.

### Met wie praat de extensie?

- Alleen met Smartschool, en één keer per dag met GitHub, om te vragen wat de
  nieuwste versie is. Aan GitHub stuurt ze niets over jou of je school.
- De extensie handelt in jouw naam: een antwoord of een nieuw bericht
  vertrekt vanuit jouw account, en archiveren en weggooien verplaatsen jouw
  berichten. Claude vraagt je akkoord voordat het iets verstuurt of naar de
  prullenbak verplaatst. Met **Aanwezigheden** aan registreert ze te laat en
  aanwezig op jouw naam, telkens pas na jouw akkoord.

## 9. Verwijderen

1. Verwijder de extensie in Claude Desktop: **Instellingen → Extensies →
   Smartschool → Verwijderen** (*Uninstall*).
2. Sluit Claude Desktop af. Typ `%USERPROFILE%\.cache` in de adresbalk van
   Verkenner en verwijder daar de map `smartschool`. Daarin staan je sessie,
   de tekst van doorzochte berichten, de lijst van Intradesk en de
   update-controle.
3. Ruim je downloadmap op. Zonder extensie verwijdert niemand de bewaarde
   bestanden na 7 dagen. Liet je het veld **Downloadmap** leeg, verwijder dan
   de map `Downloads\Smartschool` in je gebruikersmap. Koos je zelf een map,
   verwijder daar dan de bestanden die Claude bewaarde en het bestandje
   `.smartschool-mcp-downloads.json`.
4. Wil je zeker zijn dat je 2FA-sleutel nergens meer gebruikt kan worden?
   Stel dan tweestapsverificatie in Smartschool opnieuw in
   ([stap 2](#2-je-2fa-sleutel-opzoeken)) en zet de nieuwe sleutel alleen in
   je telefoonapp.

Wat je verwijdert, gaat naar de Prullenbak. Maak die daarna leeg als je zeker
wilt zijn dat het van je pc weg is.

## 10. Hulp nodig?

Kom je er niet uit, of vind je een fout? Meld het op
[GitHub](https://github.com/yvanvds/smartschool-mcp/issues), of laat het de
maker, Yvan Vander Sanden, weten.

Zet nooit je wachtwoord, je 2FA-sleutel of berichten van anderen in een
melding of een schermafbeelding.
