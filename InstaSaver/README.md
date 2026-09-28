# InstaSaver (iOS)

SwiftUI-app die foto's, video's, reels en carrousels van Instagram downloadt in de
hoogst beschikbare kwaliteit en ze **rechtstreeks in de Foto's-app** zet.

## Functies

- Plak een link (`/p/…`, `/reel/…`, `/reels/…`, `/tv/…` of een `instagram.com/share/…`-link),
  of gebruik de **Plak**-knop: de app begint meteen.
- **Eén foto/video** → wordt direct gedownload en in Foto's gezet.
- **Carrousel** → raster met miniaturen, resolutie en video-icoon per item. Alles staat
  standaard aan; tik om items (de)selecteren en kies *Download x van y*. Items worden in
  carrouselvolgorde opgeslagen.
- Optioneel **inloggen** (account-icoon rechtsboven) via Instagrams eigen loginpagina in een
  WebView. Handig als Instagram anonieme verzoeken blokkeert en nodig voor privé-accounts die
  je volgt. Cookies blijven alleen op het toestel.

## Hoe de maximale kwaliteit wordt verkregen

snapinsta.to (en vergelijkbare sites) doen server-side hetzelfde als deze app op het toestel:
ze vragen de post op bij Instagrams eigen web-API's en kiezen uit de lijst met encodes de
grootste. Instagram levert per post altijd meerdere versies (bijv. 150, 320, 640, 750, 1080 en
soms 1440 px breed). Het gaat erom de juiste lijst te lezen en de grootste te pakken:

| Bron | Foto | Video |
| --- | --- | --- |
| `api/v1/media/{id}/info/` (ingelogd) | `image_versions2.candidates` → grootste breedte×hoogte (originele upload-resolutie, tot 1440 px) | `video_versions` → grootste; plus `video_dash_manifest` |
| GraphQL `PolarisPostActionLoadPostQueryQuery` | `display_resources` → grootste `config_width×config_height` | `video_url` plus `dash_info.video_dash_manifest` |
| `?__a=1&__d=dis` | zoals v1 | zoals v1 |
| `embed/captioned` | `contextJSON` of grootste `srcset`-entry | uit `contextJSON` |

De app probeert deze bronnen in die volgorde (de eerste alleen als je bent ingelogd) en
gebruikt de eerste die resultaat geeft.

Extra's voor maximale kwaliteit:

- **Video via DASH**: Instagram levert de hoogste videoresolutie vaak alléén als losse
  DASH-streams (video zonder audio + audio). Als het manifest een hogere H.264/HEVC-resolutie
  bevat dan de progressieve MP4, downloadt de app beide streams en voegt ze zonder
  hercodering samen (`AVAssetExportPresetPassthrough`). Lukt dat niet, dan valt de app terug
  op de beste progressieve MP4.
- **Geen hercompressie**: bestanden gaan als origineel bestand naar Foto's via
  `PHAssetCreationRequest.addResource`, niet via `UIImage`.
- **JPEG i.p.v. WebP**: de CDN-aanvraag vraagt om JPEG zodat Foto's overal een compatibel
  origineel krijgt.
- CDN-URL's zijn ondertekend (`oh`/`oe`); ze worden daarom niet aangepast (dat geeft 403).

## Bouwen

Vereist Xcode 16 of nieuwer, iOS 17+.

1. Open `InstaSaver/InstaSaver.xcodeproj`.
2. Kies bij *Signing & Capabilities* je eigen team en pas zo nodig de bundle-ID
   (`com.example.instasaver`) aan.
3. Kies je iPhone en druk op Run. Bij de eerste download vraagt iOS toestemming om foto's toe
   te voegen.

## Onderhoud

Instagram wijzigt regelmatig zijn interne API's. Werkt ophalen niet meer:

- Log in via het account-scherm (lost de meeste blokkades/rate-limits op).
- Het GraphQL `doc_id` kan veranderd zijn: zoek het actuele ID in de netwerk-requests van
  instagram.com (verzoek naar `/graphql/query` met `PolarisPostActionLoadPostQueryQuery`) en
  vul het in onder *Account → Geavanceerd*. Leeg laten = standaardwaarde.

## Bestanden

| Bestand | Rol |
| --- | --- |
| `InstagramURLParser.swift` | link herkennen, shortcode → media-ID |
| `InstagramClient.swift` | Instagram-endpoints aanroepen (met fallbacks) |
| `MediaParser.swift` | JSON/DASH parsen en de hoogste kwaliteit kiezen |
| `MediaDownloader.swift` | downloaden en DASH-video+audio samenvoegen |
| `PhotoLibrarySaver.swift` | opslaan in Foto's |
| `DownloadViewModel.swift` | flow: ophalen → (kiezen) → downloaden |
| `ContentView.swift`, `CarouselPickerView.swift`, `AccountView.swift` | UI |

## Let op

Download alleen content waarvoor je toestemming hebt of die je voor eigen gebruik bewaart, en
respecteer de rechten van makers en de gebruiksvoorwaarden van Instagram.
