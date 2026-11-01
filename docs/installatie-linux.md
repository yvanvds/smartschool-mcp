# Smartschool op Linux

Op Linux is er geen Claude Desktop-extensie en geen programma dat zichzelf
installeert. Je krijgt het programma zelf, `smartschool-mcp-linux-x64`, en
stelt het in je MCP-client in: Claude Code, of een andere client die een
lokale MCP-server (STDIO) kan starten. Daarna kan je dezelfde vragen stellen
als in Claude Desktop (zie [Wat kun je vragen?](installatie.md#5-wat-kun-je-vragen)).

Gebruik je Windows? Volg dan de [installatiegids voor Claude Desktop](installatie.md)
of de [installatiegids voor ChatGPT](installatie-chatgpt.md).

Lees zeker ook [Veiligheid en privacy](installatie.md#8-veiligheid-en-privacy)
in de gids voor Claude Desktop: wat daar staat, geldt ook op Linux.

## Inhoud

1. [Wat heb je nodig?](#1-wat-heb-je-nodig)
2. [Het programma downloaden](#2-het-programma-downloaden)
3. [Instellen in je MCP-client](#3-instellen-in-je-mcp-client)
4. [Testen](#4-testen)
5. [Bijwerken naar een nieuwe versie](#5-bijwerken-naar-een-nieuwe-versie)
6. [Waar staan de bestanden?](#6-waar-staan-de-bestanden)
7. [Verwijderen](#7-verwijderen)

## 1. Wat heb je nodig?

- Een Linux-pc met een x64-processor (Intel of AMD). Andere processors
  (zoals ARM) worden nog niet ondersteund.
- Een MCP-client die een lokale server kan starten, zoals Claude Code.
- Het adres van je school op Smartschool, je gebruikersnaam en je
  wachtwoord.
- Alleen met tweestapsverificatie: je 2FA-sleutel. Hoe je die vindt, staat
  in [Je 2FA-sleutel opzoeken](installatie.md#2-je-2fa-sleutel-opzoeken).

## 2. Het programma downloaden

Download `smartschool-mcp-linux-x64` van de
[releasepagina](https://github.com/yvanvds/smartschool-mcp/releases/latest)
(onder **Assets**), of meteen:
[smartschool-mcp-linux-x64](https://github.com/yvanvds/smartschool-mcp/releases/latest/download/smartschool-mcp-linux-x64).
Download het programma alleen van die releasepagina.

Zet het op een vaste plek en maak het uitvoerbaar, bijvoorbeeld in
`~/.local/bin`:

```
mkdir -p ~/.local/bin
mv ~/Downloads/smartschool-mcp-linux-x64 ~/.local/bin/smartschool-mcp
chmod +x ~/.local/bin/smartschool-mcp
```

Start je het programma zelf in een terminal, dan doet het niets: het zegt
alleen dat je het in je MCP-client moet instellen. Je MCP-client start het.

## 3. Instellen in je MCP-client

Je MCP-client start het programma als STDIO-server, zonder argumenten, met
je instellingen als omgevingsvariabelen:

| Omgevingsvariabele | Wat vul je in? |
| --- | --- |
| `SMARTSCHOOL_MAIN_URL` | Het adres van je school op Smartschool, bijvoorbeeld `school.smartschool.be`. |
| `SMARTSCHOOL_USERNAME` | De gebruikersnaam waarmee je inlogt op Smartschool. |
| `SMARTSCHOOL_PASSWORD` | Je wachtwoord voor Smartschool. |
| `SMARTSCHOOL_MFA` | Alleen met tweestapsverificatie: je 2FA-sleutel. Niet de code van zes cijfers. Laat hem anders weg. |
| `SMARTSCHOOL_DOWNLOAD_DIR` | Niet verplicht. De map voor bewaarde bestanden; zonder is het `~/Downloads/Smartschool`. |
| `SMARTSCHOOL_SKORE` | Niet verplicht: `true` voor [Skore-beheer](installatie.md#skore-beheer), met de rechten ervoor. |
| `SMARTSCHOOL_PRESENCE` | Niet verplicht: `true` voor [Aanwezigheden](installatie.md#aanwezigheden), met de rechten ervoor. |
| `SMARTSCHOOL_LVS` | Niet verplicht: `true` voor het [Leerlingvolgsysteem](installatie.md#leerlingvolgsysteem), als jij en je school dat willen. |

**Claude Code:** voeg de server toe met `claude mcp add` (vervang de
waarden door je eigen gegevens; laat `SMARTSCHOOL_MFA` weg zonder 2FA):

```
claude mcp add --scope user smartschool \
  --env SMARTSCHOOL_MAIN_URL=school.smartschool.be \
  --env SMARTSCHOOL_USERNAME=jan.peeters \
  --env SMARTSCHOOL_PASSWORD='je wachtwoord' \
  --env SMARTSCHOOL_MFA='je 2FA-sleutel' \
  -- ~/.local/bin/smartschool-mcp
```

**Een andere client** met een JSON-configuratie (zoals
`claude_desktop_config.json`) krijgt zo'n blok onder `mcpServers`, met het
volledige pad naar het programma:

```json
{
  "mcpServers": {
    "smartschool": {
      "command": "/home/jan/.local/bin/smartschool-mcp",
      "args": [],
      "env": {
        "SMARTSCHOOL_MAIN_URL": "school.smartschool.be",
        "SMARTSCHOOL_USERNAME": "jan.peeters",
        "SMARTSCHOOL_PASSWORD": "je wachtwoord",
        "SMARTSCHOOL_MFA": "je 2FA-sleutel"
      }
    }
  }
}
```

Je client bewaart je wachtwoord en je 2FA-sleutel dan onversleuteld in zijn
configuratiebestand. Zorg dat alleen jij dat bestand kan lezen
(`chmod 600 <bestand>`).

## 4. Testen

Herstart je MCP-client en vraag in een nieuw gesprek:

> Werkt mijn Smartschool-verbinding?

Het antwoord zegt of de verbinding werkt, of welke instelling ontbreekt of
niet klopt. Wat een melding betekent, staat bij
[Problemen oplossen](installatie.md#7-problemen-oplossen) in de gids voor
Claude Desktop.

## 5. Bijwerken naar een nieuwe versie

Is er een nieuwe versie, dan zegt het antwoord dat, met een downloadlink naar
`smartschool-mcp-linux-x64` en wat er nieuw is. Download het bestand, zet het
in de plaats van het oude programma (zelfde map en naam, bv.
`~/.local/bin/smartschool-mcp`), maak het weer uitvoerbaar met `chmod +x` en
herstart je MCP-client. Je instellingen blijven bewaard.

## 6. Waar staan de bestanden?

- Bewaarde bijlagen en Intradesk-bestanden: in `~/Downloads/Smartschool`, of
  in de map uit `SMARTSCHOOL_DOWNLOAD_DIR`. Het programma verwijdert de
  bestanden die het daar bewaarde na 7 dagen.
- Je sessie en de caches: in `~/.cache/smartschool`.

## 7. Verwijderen

Verwijder de server uit je MCP-client (in Claude Code:
`claude mcp remove --scope user smartschool`), verwijder het programma
(`rm ~/.local/bin/smartschool-mcp`) en de map `~/.cache/smartschool`.
