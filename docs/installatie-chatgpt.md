# Smartschool in ChatGPT

Met Smartschool voor ChatGPT werkt de ChatGPT-app op je Windows-pc met je
Smartschool-account. Je vraagt het gewoon in een gesprek:

- **Berichten:** bekijken, lezen, doorzoeken, samenvatten, als gelezen of
  ongelezen markeren, een gekleurde vlag geven, archiveren, naar de
  prullenbak verplaatsen, beantwoorden en nieuwe berichten versturen. Een
  bericht vertrekt, en een bericht gaat naar de prullenbak, pas nadat jij het
  goedgekeurd hebt.
- **Intradesk:** documenten zoeken op naam, mappen bekijken en bestanden
  lezen.
- **Bestanden bewaren:** bijlagen en Intradesk-bestanden op je pc zetten, zodat
  ChatGPT of jijzelf ze kan openen.

Het is hetzelfde programma als de Smartschool-extensie voor Claude Desktop,
maar je installeert het anders. Gebruik je Claude Desktop, volg dan de
[installatiegids voor Claude Desktop](installatie.md).

Deze gids legt uit hoe je Smartschool in ChatGPT installeert, test, gebruikt,
bijwerkt en weer verwijdert. Lees zeker ook
[Veiligheid en privacy](#8-veiligheid-en-privacy) voor je begint.

Smartschool voor ChatGPT is niet officieel: het is niet gemaakt door
Smartschool of OpenAI en er ook niet mee verbonden.

## Inhoud

1. [Wat heb je nodig?](#1-wat-heb-je-nodig)
2. [Je 2FA-sleutel opzoeken](#2-je-2fa-sleutel-opzoeken) (alleen met
   tweestapsverificatie)
3. [Installeren](#3-installeren)
4. [Testen](#4-testen)
5. [Wat kun je vragen?](#5-wat-kun-je-vragen)
6. [Bijwerken naar een nieuwe versie](#6-bijwerken-naar-een-nieuwe-versie)
7. [Problemen oplossen](#7-problemen-oplossen)
8. [Veiligheid en privacy](#8-veiligheid-en-privacy)
9. [Verwijderen](#9-verwijderen)
10. [Hulp nodig?](#10-hulp-nodig)

## 1. Wat heb je nodig?

- **Een Windows-pc** die alleen jij gebruikt, met je eigen Windows-account.
- **De ChatGPT-app voor Windows**, uit de Microsoft Store. Smartschool werkt
  niet in ChatGPT in je browser: ChatGPT moet het programma op je pc kunnen
  starten.
- **Een betalend ChatGPT-abonnement:** Plus of Pro, of een account van je
  school (Business, Edu of Enterprise). Gebruik Smartschool voor ChatGPT niet
  met een gratis account. ChatGPT leest dan je berichten en documenten, en
  daar staan vaak gevoelige gegevens over leerlingen in (zie
  [Veiligheid en privacy](#8-veiligheid-en-privacy)).
- **Een Smartschool-account waarmee je inlogt met een gebruikersnaam en een
  wachtwoord.** Kun je alleen inloggen via Microsoft of Google, dan werkt het
  niet.
- **Tweestapsverificatie met een authenticator-app** op je telefoon, zoals
  Microsoft Authenticator of Google Authenticator, als je account
  tweestapsverificatie gebruikt. Voor leerkrachten is dat zo. Log je in met
  alleen je wachtwoord, zonder code uit een app, zoals de meeste leerlingen?
  Dan heb je geen authenticator-app nodig.

## 2. Je 2FA-sleutel opzoeken

**Alleen als je tweestapsverificatie gebruikt.** Vraagt Smartschool na je
wachtwoord geen code uit een app, zoals bij de meeste leerlingen? Sla deze
stap dan over en laat `SMARTSCHOOL_MFA` in stap 3 weg.

Smartschool logt zelf voor je in, ook met de code van zes cijfers uit je
authenticator-app. Daarvoor heeft het de **2FA-sleutel** nodig: de geheime
sleutel waarmee je app de codes maakt. Dat is een lange reeks letters en
cijfers, niet de code van zes cijfers.

Hoe je die sleutel vindt, staat in de installatiegids voor Claude Desktop:
[Je 2FA-sleutel opzoeken](installatie.md#2-je-2fa-sleutel-opzoeken). Het gaat
precies zo. Waar die gids zegt dat je de sleutel in het formulier van de
extensie invult, vul je hem hier in bij `SMARTSCHOOL_MFA` (zie stap 3).

## 3. Installeren

Je installeert in drie delen: eerst zorg je dat OpenAI niet traint met je
gesprekken, dan zet je het programma op je pc, en daarna voeg je het toe in
ChatGPT.

### Eerst: OpenAI niet laten trainen met je gesprekken

Vraag je ChatGPT iets over een bericht, een bijlage of een document, dan gaat
de inhoud daarvan naar OpenAI, het bedrijf achter ChatGPT. Daar staan vaak
gevoelige gegevens over leerlingen in: namen, punten, zorg, gezondheid, de
thuissituatie. Zorg er daarom vóór je Smartschool toevoegt voor dat OpenAI je
gesprekken niet gebruikt om zijn modellen te verbeteren:

1. Open in ChatGPT **Instellingen** en zoek het gegevensbeheer (*Data
   controls*).
2. Zet **Het model verbeteren voor iedereen** (*Improve the model for
   everyone*) uit.

Werk je met een ChatGPT-account van je school (Business, Edu of Enterprise),
dan traint OpenAI standaard niet met je gesprekken. Vraag bij twijfel aan wie
dat account beheert hoe het bij jullie ingesteld is.

<!-- TE BEVESTIGEN (#50): waar staat deze instelling in de ChatGPT-app voor
Windows, en hoe heten het menu en de schakelaar in het Nederlands? Pas de
namen hierboven aan. Niet in de gratis versie: kijk na in een betalend
account. (Het installatievenster noemt alleen de Engelse naam.) -->

### Het programma op je pc zetten

1. Ga naar de
   [releasepagina](https://github.com/yvanvds/smartschool-mcp/releases/latest)
   en klik onder **Assets** op `smartschool-mcp.exe`, of download het bestand
   meteen:
   [smartschool-mcp.exe](https://github.com/yvanvds/smartschool-mcp/releases/latest/download/smartschool-mcp.exe).
   Download het alleen van die releasepagina.
2. Dubbelklik op het gedownloade bestand (meestal in je map Downloads).
3. Windows toont waarschijnlijk **Windows heeft uw pc beschermd**: het
   programma is niet digitaal ondertekend, dus Windows kent de maker niet.
   Klik op **Meer info** en dan op **Toch uitvoeren**. Doe dat alleen voor het
   bestand van de releasepagina.
4. Een venster zet het programma op een vaste plek op je pc:

   `%LOCALAPPDATA%\Programs\smartschool-mcp\smartschool-mcp.exe`

   Het venster toont het volledige pad, bijvoorbeeld
   `C:\Users\jan.peeters\AppData\Local\Programs\smartschool-mcp\smartschool-mcp.exe`,
   en zet het ook op je klembord. Laat het venster open: het toont ook wat je
   in ChatGPT invult.

Het gedownloade bestand in Downloads heb je daarna niet meer nodig; je mag het
verwijderen.

<!-- TE BEVESTIGEN (#40): wat toont SmartScreen bij het dubbelklikken op het
gedownloade smartschool-mcp.exe, en waarschuwt het opnieuw als ChatGPT het
geïnstalleerde programma start? Beschrijf hier wat de collega ziet. -->

<!-- SCHERMAFBEELDING (#33): de SmartScreen-melding en het venster van de
installatie. -->

### Smartschool toevoegen in ChatGPT

1. Open de ChatGPT-app en ga naar **Instellingen**. Kies onder
   **Integraties** voor **Plug-ins**, en dan het tabblad **MCP's**.
2. Kies **Toevoegen** en dan **Aangepaste MCP-server maken**.
3. Vul het formulier in:

   | Veld | Wat vul je in? |
   | --- | --- |
   | **Naam** | `smartschool` |
   | Type | **STDIO**, als ChatGPT het vraagt. |
   | **Opdracht om op te starten** | Het pad uit het venster: plak het met Ctrl+V. |
   | **Argumenten** | Niets. Laat dit leeg. |
   | **Omgevingsvariabelen** | Vijf regels, zie hieronder. |

4. Voeg bij **Omgevingsvariabelen** deze regels toe, met **Omgevingsvariabele
   toevoegen**. Typ bij **Sleutel** precies de naam uit de eerste kolom, in
   hoofdletters en met de lage streepjes, en bij **Waarde** je eigen gegevens:

   | Sleutel | Waarde |
   | --- | --- |
   | `SMARTSCHOOL_MAIN_URL` | Het adres van je school op Smartschool, bijvoorbeeld `school.smartschool.be`. Je mag het ook uit de adresbalk van je browser kopiëren. |
   | `SMARTSCHOOL_USERNAME` | De gebruikersnaam waarmee je inlogt op Smartschool. |
   | `SMARTSCHOOL_PASSWORD` | Je wachtwoord voor Smartschool. |
   | `SMARTSCHOOL_MFA` | Alleen met tweestapsverificatie: je 2FA-sleutel uit [stap 2](#2-je-2fa-sleutel-opzoeken). Niet de code van zes cijfers. Spaties in de sleutel zijn geen probleem. Log je in met alleen je wachtwoord, laat deze regel dan weg. |
   | `SMARTSCHOOL_DOWNLOAD_DIR` | Niet verplicht. De map waarin ChatGPT bestanden uit Smartschool bewaart, bijvoorbeeld `C:\Users\jan.peeters\Documents\Smartschool`. Laat je deze regel weg, dan is het `Downloads\Smartschool` in je gebruikersmap. |

   Laat **Doorgifte van omgevingsvariabele** leeg.
5. Bewaar, en herstart ChatGPT (zie hieronder).

Een verkeerd getypte sleutel, zoals `SMARTSCHOOL_MAINURL` zonder het tweede
lage streepje, telt niet: dan ontbreekt die instelling. De test in
[stap 4](#4-testen) zegt het als je een sleutel verkeerd typte.

<!-- SCHERMAFBEELDING (#33): het formulier Aangepaste MCP-server maken,
ingevuld zonder echte gegevens. -->

### Later iets aanpassen

Je past alles later aan in ChatGPT, via **Instellingen → Plug-ins →
MCP's → smartschool**. Herstart ChatGPT daarna.

**ChatGPT herstarten:** toont ChatGPT na het bewaren een knop om opnieuw te
starten, klik er dan op. Anders sluit je ChatGPT helemaal af en open je het
opnieuw.

<!-- TE BEVESTIGEN (#40): start ChatGPT de server na het bewaren zelf
opnieuw, of toont het een knop (Herstarten)? Blijft ChatGPT na het sluiten
van het venster op de achtergrond draaien? -->

## 4. Testen

Open een nieuwe chat in de ChatGPT-app en vraag:

> Werkt mijn Smartschool-verbinding?

Vraagt ChatGPT of het Smartschool mag gebruiken? Sta dat toe. De eerste keer
duurt het inloggen enkele seconden. Daarna onthoudt Smartschool voor ChatGPT
je sessie.

ChatGPT antwoordt met:

- of de verbinding werkt, en als wie je bent ingelogd;
- het adres van je school;
- je downloadmap, en of daar bestanden bewaard kunnen worden;
- de versie, en of er een nieuwere is.

Werkt de verbinding niet, dan zegt ChatGPT wat je moet aanpassen. Zie ook
[Problemen oplossen](#7-problemen-oplossen).

<!-- TE BEVESTIGEN (#40): werkt het in elke nieuwe chat, of alleen in een
chat met Codex of in een project? -->

## 5. Wat kun je vragen?

Hetzelfde als in Claude Desktop: zie
[Wat kun je vragen?](installatie.md#5-wat-kun-je-vragen) in de gids voor
Claude Desktop. Wat daar over Claude staat, geldt hier voor ChatGPT. Een paar
verschillen:

- **Berichten versturen en weggooien.** ChatGPT toont eerst de tekst en de
  ontvangers, of de berichten die naar de prullenbak gaan, en wacht op jouw
  akkoord. Daarna vraagt de app nog eens toestemming. Kies daar niet om het
  altijd toe te staan. Zet ChatGPT ook niet op **volledige toegang**
  (*Full access*): dan vraagt de app nergens meer toestemming voor.
- **Afbeeldingen.** Een afbeelding van Intradesk (`.png`, `.jpg`) kan ChatGPT
  niet altijd bekijken. Vraag dan om het bestand te bewaren, en open het
  zelf.
- **Lange documenten.** Van een heel lang document leest ChatGPT soms maar
  een deel. Vraag dan naar een bepaald deel, of bewaar het bestand en open het
  zelf.

## 6. Bijwerken naar een nieuwe versie

Eén keer per dag kijkt Smartschool voor ChatGPT op GitHub of er een nieuwe
versie is. Is die er, dan meldt ChatGPT dat in een antwoord, met het nieuwe
versienummer, een downloadlink naar `smartschool-mcp.exe` en in een paar
woorden wat er nieuw is. Sla je versies over, dan hoor je wat er nieuw is in
elke versie die je overslaat. Ook "Werkt mijn Smartschool-verbinding?" toont
altijd of er een nieuwere versie is, met de downloadlink en wat er nieuw is.

Zo werk je bij:

1. Klik op de downloadlink uit het antwoord: die downloadt
   `smartschool-mcp.exe` van de releasepagina (de link begint met
   `https://github.com/yvanvds/smartschool-mcp/releases/`). Geen
   downloadlink? Open dan de
   [releasepagina](https://github.com/yvanvds/smartschool-mcp/releases/latest)
   en download `smartschool-mcp.exe` (onder **Assets**).
2. Dubbelklik erop, zoals bij [Installeren](#3-installeren). Het zet de nieuwe
   versie over de oude, ook als ChatGPT open staat.
3. Herstart ChatGPT en vraag "Werkt mijn Smartschool-verbinding?". Controleer
   dat de verbinding werkt en dat de nieuwe versie draait.

Je instellingen in ChatGPT blijven bewaard, en ook wat Smartschool voor
ChatGPT onthield (je sessie, de tekst van doorzochte berichten, de lijst van
Intradesk).

## 7. Problemen oplossen

Werkt er iets niet, vraag dan eerst "Werkt mijn Smartschool-verbinding?".
ChatGPT zegt wat er misloopt en wat je moet aanpassen. Je instellingen pas je
aan via **Instellingen → Plug-ins → MCP's → smartschool**; herstart ChatGPT
daarna.

Meldt de test een probleem met je wachtwoord, je 2FA-sleutel, het adres of de
downloadmap? Dan helpt
[Problemen oplossen](installatie.md#7-problemen-oplossen) in de gids voor
Claude Desktop. Lees daar "Claude Desktop herstarten" als "ChatGPT
herstarten", en zoek de instelling bij de sleutel in deze tabel:

| In de gids voor Claude Desktop | Sleutel in ChatGPT |
| --- | --- |
| **Smartschool-adres** | `SMARTSCHOOL_MAIN_URL` |
| **Gebruikersnaam** | `SMARTSCHOOL_USERNAME` |
| **Wachtwoord** | `SMARTSCHOOL_PASSWORD` |
| **2FA-sleutel** | `SMARTSCHOOL_MFA` |
| **Downloadmap** | `SMARTSCHOOL_DOWNLOAD_DIR` |

### Een sleutel is verkeerd getypt

De test zegt bijvoorbeeld dat `"SMARTSCHOOL_MAINURL" is set, but that is not
the name of a setting: probably SMARTSCHOOL_MAIN_URL`. Pas dan bij
**Omgevingsvariabelen** de **Sleutel** aan naar de naam die ChatGPT noemt, en
herstart ChatGPT.

### ChatGPT kent Smartschool niet

- Kijk bij **Instellingen → Plug-ins → MCP's** of smartschool er staat en aan
  staat.
- Controleer **Opdracht om op te starten**: het moet het volledige pad naar
  `smartschool-mcp.exe` zijn. Dubbelklik nog eens op het gedownloade bestand:
  het venster toont het pad opnieuw.
- Herstart ChatGPT helemaal.
- Gebruik je een ChatGPT-account van je school of organisatie? Dan kan de
  beheerder eigen MCP-servers uitgeschakeld hebben. Vraag het na.

### Windows of je virusscanner waarschuwt

Het programma is niet digitaal ondertekend, dus Windows kent de maker niet.
Daarom toont Windows bij het dubbelklikken **Windows heeft uw pc beschermd**
(zie [Installeren](#3-installeren)). Download het programma alleen van de
[releasepagina](https://github.com/yvanvds/smartschool-mcp/releases/latest).
Waarschuwt je virusscanner, of verdwijnt het programma meteen na het
installeren? Klik dan niet zomaar verder, maar vraag eerst raad (zie
[Hulp nodig?](#10-hulp-nodig)).

## 8. Veiligheid en privacy

Wat Smartschool voor ChatGPT op je pc bewaart (je sessie, de tekst van
doorzochte berichten, de lijst van Intradesk, de bewaarde bestanden), en hoe
je pc je tweede factor wordt, staat in
[Veiligheid en privacy](installatie.md#8-veiligheid-en-privacy) in de gids
voor Claude Desktop. Het geldt hier net zo. Voor ChatGPT komt daar dit bij.

### Je instellingen staan niet versleuteld op je pc

ChatGPT bewaart wat je in het formulier invult, dus ook je wachtwoord en je
2FA-sleutel, zoals het is in
`%USERPROFILE%\.codex\config.toml`. Dat bestand is niet versleuteld:

- Iedereen die op je Windows-account kan inloggen, en wie beheerder is van de
  pc, kan het lezen.
- ChatGPT zelf kan in principe bestanden op je pc lezen, ook dat bestand.
  Vraag ChatGPT nooit om dat bestand te openen of te tonen.
- Zet het bestand nooit in een gedeelde map, een e-mail of een melding.

Het programma zelf staat in
`%LOCALAPPDATA%\Programs\smartschool-mcp\smartschool-mcp.exe`.

### Wat gaat er naar ChatGPT?

- Vraag je ChatGPT iets over een bericht, een bijlage of een document, dan
  geeft Smartschool voor ChatGPT de inhoud daarvan aan ChatGPT. Die gaat dan
  naar de servers van OpenAI, het bedrijf achter ChatGPT, net zoals alles wat
  je zelf in het gesprek typt. Daar horen ook namen en gegevens van collega's,
  leerlingen en ouders bij.
- **Ga na of dat mag volgens het privacybeleid van je school,** en vraag het
  bij twijfel aan je directie of aan de privacyverantwoordelijke (DPO) van je
  school. Wees extra voorzichtig met gevoelige gegevens over leerlingen, zoals
  hun gezondheid, zorg of thuissituatie.
- Gebruik daarom alleen een betalend abonnement, en laat OpenAI niet trainen
  met je gesprekken (zie
  [Eerst: OpenAI niet laten trainen met je gesprekken](#eerst-openai-niet-laten-trainen-met-je-gesprekken)).
  Ook dan gaan de gegevens naar OpenAI: ga dus nog altijd na of dat mag
  volgens het privacybeleid van je school.
- Je wachtwoord en je 2FA-sleutel geeft Smartschool voor ChatGPT nooit aan
  ChatGPT: het gebruikt ze alleen om in te loggen op Smartschool.

## 9. Verwijderen

1. Verwijder Smartschool in ChatGPT: **Instellingen → Plug-ins → MCP's →
   smartschool → De-installeren**.
2. Sluit ChatGPT af. Typ `%LOCALAPPDATA%\Programs` in de adresbalk van
   Verkenner en verwijder daar de map `smartschool-mcp`.
3. Verwijder ook wat Smartschool voor ChatGPT onthield en bewaarde, zoals in
   stap 2 tot 4 van [Verwijderen](installatie.md#9-verwijderen) in de gids
   voor Claude Desktop: de map `%USERPROFILE%\.cache\smartschool`, je
   downloadmap en eventueel een nieuwe 2FA-sleutel.

<!-- TE BEVESTIGEN (#40): haalt De-installeren de omgevingsvariabelen
(wachtwoord, 2FA-sleutel) echt uit %USERPROFILE%\.codex\config.toml? -->

## 10. Hulp nodig?

Kom je er niet uit, of vind je een fout? Meld het op
[GitHub](https://github.com/yvanvds/smartschool-mcp/issues), of laat het de
maker, Yvan Vander Sanden, weten.

Zet nooit je wachtwoord, je 2FA-sleutel, je `config.toml` of berichten van
anderen in een melding of een schermafbeelding.
