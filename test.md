Målarkitekturen för agenterna i Bambusa

25 okt. 2026
·
@Asgeir

Svensk version av det norska originalet. Tolv av fjorton beslut är fattade, och C, D och valet av jobbmotor avgörs tillsammans med utvecklaren.

Det här dokumentet beskriver arkitekturen som agenterna i Bambusa ska byggas på: vad den ska uppnå, vilka delar den har, hur arbete och information flödar och hur vi bygger den. Arbetet står i centrum: jobben som människor och agenter gör, och det som behövs för att göra dem rätt. Reglerna för data, risk och behörigheter ligger som skydd runt arbetet.

Sex principer bär arkitekturen: arbetet och tillståndet ligger utanför chatten, agenterna förankras i masterdata, autonomi förtjänas per jobb, kontrollerna ligger i kod och inte i prompten, siffrorna vi styr efter räknas i kod och inte av agenterna, och människorna behöver lika mycket insats som tekniken.

Dokumentet är en ritning, inte en låst specifikation. Vi bygger stabilt efter ritningen men flyttar en vägg när vi lär oss något på vägen. En ändring i arkitekturen föreslås med motivering, ägaren godkänner den, och varför står i beslutsloggen (D-028). Nummer som D-028, G-18 och A-011 hänvisar till registren i BOS-arkivet.

1. Målet
   Varje anställd har en agent som känner hela Bambusa och tar det tunga arbetet. Allt fler jobb utförs av agenter från början till slut. Människorna sätter målen, äger processerna och godkänner det som inte kan ångras.

Så här kan det se ut när det fungerar (exempel, inte en plan):

Kundtjänst. En dugnadsansvarig skriver till kundtjänst att varorna inte har kommit. Innan någon öppnar mejlet har agenten hittat beställningen (även när den ligger under en deltagare i en dugnad), kontrollerat med lagret och transportören om varorna har skickats och levererats, och lagt ett svarsutkast på rätt språk i ärendet. Den anställda läser, rättar och skickar från ärendetavlan. Senare kan fasta svar gå ut av sig själva där det är säkert.

Klubb-CS. Agenten går igenom alla pågående dugnader varje morgon, ser vilka som ligger efter och föreslår vem som bör få en påminnelse och vad den ska säga. Rådgivaren lägger tiden på samtalen.

Klubbförsäljning. Före mötet får säljaren ett kort om klubben: tidigare dugnader, omsättning, kontakter, öppna ärenden och mättnad i området. Efter mötet ligger anteckningar och uppföljning i HubSpot.

Ledning. ”Hur går säsongen mot budget i Sverige, och varför?” besvaras på några minuter, med definierade siffror och budget från siffermodellen i Connect och en förklaring av vad som driver avvikelsen. Agenten säger också till i god tid när mötena och avtalen i en försäljningsström inte räcker till målet.

Marknadsföring. Varje måndag finns en rapport från Meta, Google och Klaviyo med konkurrentkoll och förslag på åtgärder. Senare justerar agenten annonskampanjer själv inom en ram.

Ekonomi. Agenten kontrollerar om order är fakturerade, hittar fakturor som har fått påminnelse utan att betalas, hämtar fakturakopior till kunder och förbereder underlaget för avstämningen mellan bolagen, som redovisningskonsulterna gör.

Vi vet att det fungerar när vi kan mäta det:

sparad tid per vecka och roll

andel utkast som används utan ändring, och hur ofta en människa måste gripa in

fel som når kunden eller systemen

svarstid till kunder och klubbar

kostnad per lyckat jobb

hur stor del av varje jobb som görs med hjälp, med godkännande och helt av en agent

2. Arbetet först
   Agenterna byggs runt jobb, inte tvärtom. Ett jobb är en avgränsad uppgift med en utlösare, ett resultat och en definition av klart: ”svara på frågor om leverans”, ”förbereda klubbmöte”, ”följa upp dugnader som ligger efter”. Det är jobbet vi prioriterar, mäter och ger autonomi. Agenten är den som utför.

Varje jobb får ett jobbkort innan någon skriver en prompt. Arize kallar detta det billigaste tillförlitlighetsarbete som finns. Jobbkortet anger:

vad som utlöser jobbet (en händelse eller ett schema) och var det börjar, och vilka uppgifter det använder

vad som räknas som klart, var resultatet ska levereras, och vilken siffra jobbet ska flytta, när det har ett sådant mål

vilka verktyg det får använda, och vad som kräver godkännande

vad det får kosta

vilka testfall det måste klara

vem som äger det

Första utkastet till jobblistan, utifrån vad vi vet om rollerna i dag:

Roll

Jobb som troligen tar mest tid

System

Första hjälpen från en agent

Support och kundtjänst

Mejl och telefon om byte och retur, dugnader, faktura och betalning, leverans, inloggning i appen, B2B-order och uppföljning av leads

Gmail, telefon (Phonero), Slack, App Admin, WooCommerce, Centra, Nets Easy, Ongoing, nShift, PostNord, HubSpot, ekonomisystem, kalkylblad

Sortering av mejlen och svarsutkast i ärendetavlan med orderstatus och fakturakopia

Klubb-CS (alla länder)

Start, uppföljning och utvärdering av dugnader med hundratals deltagare

HubSpot, appen, Connect, videomöten

Daglig status per dugnad och förslag på påminnelser

Klubbförsäljning

Mötesbokning, möten, offert och kontrakt

HubSpot, Bambusamap, Oneflow

Mötesunderlag före, anteckningar och uppföljning efter

Backoffice och ekonomi

B2B-order, fakturering, avstämning mellan bolagen

Centra, ekonomisystem ×3, Connect

Fakturakontroll, fakturakopior, avvikelselistor

Ledning

Uppföljning av försäljning och budget, beslut

Connect, Drive, HubSpot

Svar på sifferfrågor, med förklaring

Marknadsföring

Rapportering, kampanjer, innehåll

Meta, Google, Klaviyo, HubSpot

Veckorapport med förslag

Tabellen är ett utkast, och var tiden går är inte mätt (G-15). Jobblistan gör den färdig och avgör den första skivan (kapitel 9). Arbetet sker på tre språk och har säsongstoppar i dugnad, som både mätningarna och kapaciteten måste ta hänsyn till. Inköp och lager hålls utanför tills den nya supply chain-chefen har bestämt arbetssättet (D-013).

För kundtjänst ger ärendena i kundtjänstassistenten (kapitel 9) en första bild. Till post@bambusa.no kommer det ungefär 15 riktiga förfrågningar per arbetsdag, och något fler mejl som inte behöver hanteras. Över hälften av förfrågningarna behövde uppslag i App Admin, och fyra av tio behövde tre eller fler system. I fyra av tio behövde assistenten fråga en människa, en tredjedel krävde en ändring i ett system, och minst en av fyra gick via en kollega.

Från att mejlet kom in tog det i median 2,4 timmar tills svaret var godkänt och 28 timmar tills ärendet var klart, och knappt hälften av utkasten skickades oförändrade. De siffrorna är utgångspunkten för mätningarna i kapitel 1, men andelen oförändrade utkast mäter kvaliteten, inte vad som kan bli automatiskt (beslut G). Underlaget är 192 förfrågningar till en inkorg från den 7 till den 24 oktober 2026, mest om digital dugnad i Norge. Siffrorna för kollegor och system är nedre gränser, och hur lång tid själva hanteringen tar är inte mätt.

Två förhållanden hos de anställda avgör ordningen. Det första: AI-kunskaperna antas vara låga, utom hos utvecklaren (A-011, inte mätt ännu), och källorna visar att små företag har svårast med den mänskliga sidan. Det första värdet bör därför komma från agenter som lägger färdigt arbete där människorna redan är, som ett utkast i mejltråden, en anteckning i HubSpot eller ett meddelande i Slack. Ingen behöver kunna ställa bra frågor för att ha nytta av det. Undantaget är kundtjänst, där ärendetavlan blir den nya arbetsplatsen. Därför måste det gå snabbare att arbeta där än i inkorgen i dag, även i mobilen, och användningen mäts från första dagen. Chatten med Bambusa-agenten kommer parallellt för dem som är redo. Det andra: det som inte är nedskrivet finns inte för en agent. Samtal och möten måste fortfarande loggas i HubSpot, som säljarna och kundtjänst gör i dag, annars lär agenterna aldrig känna kunderna så som de anställda gör. Med tiden kan agenten skriva loggen från en inspelning eller ett röstmeddelande, men inspelning och utskrift kräver en egen genomgång av dataskyddet.

3. Åtta modeller som arkitekturen vilar på
   En arkitektur som ska tåla många agenter behöver några få modeller som allt annat bygger på. Varje modell svarar på en fråga. Den har ett hem för definitionen och ett fast hem för varje slags tillstånd.

Modell

Frågan den svarar på

Hem

I dag

Mål

Vad försöker vi uppnå?

Mål i Git: en siffra från siffermodellen med nivå, period och ägare

Delvis: en KPI-uppsättning för dugnad är föreslagen och budgetarna ligger i kalkylblad, men inget är samlat där agenterna kan läsa det

Siffror

Vad betyder siffran, hur räknas den, och vad var den?

Definitioner och regler i Git; siffrorna räknas i kod i siffermodellen i Connect och sparas med historik

Delvis: en prototyp i ett eget projekt med 76 regler och runt 300 tester; Connect har några rapporter, men ingen siffermodell

Arbete

Vilka jobb finns, vem har dem nu, och hur långt har de kommit?

Jobbkort i Git, jobben i arbetsregistret i Connect, kundärendena i Connect och samtalen där de finns i dag

Delvis: samtalen finns i HubSpot och inkorgarna, men jobben är inte beskrivna, agentarbete har ingen plats, och det som beslutas i kundärendena har inget hem

Process

Hur flödar arbetet, och vem gör vad?

BPMN/DMN i Git

Finns för digital dugnad; traditionell dugnad är delvis kartlagd

Kunskap

Vad måste en agent veta för att göra jobbet rätt?

Git: det som styr agenterna, som policyer, regler, definitioner av siffror, tillvägagångssätt, systemkort, ordlista och exempel. Dokument och filer finns i Google Drive

Delvis: registren i BOS-arkivet

Entitet

Vem eller vad gäller ärendet, och i vilken roll, till exempel klubb, dugnad, deltagare, köpare, order, kolli eller faktura?

Identitetsgrafen i Connect: nycklar och kopplingar

Saknas: inget system äger kundidentiteten (G-18)

Agent

Vem utför, med vilken identitet och vilka behörigheter?

Agentkort i Git

Utkast finns

Förtroende

Hur mycket kan en agent göra på egen hand i varje jobb, och vad krävs för mer?

Autonominivå per jobb i Git, upprätthållen av kontrollagret

Utkast finns

Målen, siffrorna, arbetet och entiteterna är de modeller som gör agenterna användbara i vardagen. Målen ger riktning, och det är dem agenterna med tiden ska styra efter. Siffermodellen gör att människor och agenter räknar lika och ser samma siffror. Arbetsmodellen låter agenter och människor dela, lämna över och mäta arbete. Entitetsmodellen gör att alla agenter är överens om vem en kund är. Det som skiljer agenter som fungerar från demos är tillstånd utanför chatten och förankring i masterdata. L’Oréal använder egna agenter för beräkningar och för masterdata om produkt och geografi, och rapporterar att träffsäkerheten ökade från 90 till 99,9 procent.

4. Arkitekturen
   Arkitekturen har sju delar, och arbetet står i centrum. Figuren visar hur delarna hänger ihop, och siffrorna följer ett mejl till kundtjänst från början till slut.

Ett jobb från början till slut. En dugnadsansvarig skriver till kundtjänst att varorna till dugnaden inte har kommit. Kundtjänst arbetar från ärendetavlan i Connect.

Händelse. Mejlet kommer till en av funktionsadresserna, och Connect läser det direkt. Arbetsregistret skapar ett mottagningsjobb, eftersom ingen ännu vet vad mejlet gäller.

Mottagning. Koordinatorn läser mejlet och tar reda på vad det gäller: försäljningsströmmen (Klubb, Grupp, B2B eller DTC), och om det är leverans, byte, faktura eller något annat. Den använder ”Vem är detta?” för att hitta avsändaren och skapar ett deljobb om något måste kontrolleras först. Här blir det ett kundärende med jobbet ”svara på frågor om leverans”, och registret ger jobbet till kundagenten. Är ärendet oklart går det till en människa.

Kunskapen. Kundagenten läser jobbkortet, reglerna och exemplen för just det här jobbet.

Vem är detta? Verktyget ger kundagenten den dugnadsansvariga, klubben, dugnaden och ordern, även när ordern ligger under en deltagare och ingen har angett ordernummer.

Verktygslagret. Agenten läser i Ongoing om varorna har skickats från lagret, och hos transportören om de har levererats. ”Levererat” betyder levererat till klubben, inte till varje köpare, och i Danmark kan leveransen ofta inte bekräftas. Varje anrop går genom kontrollen, som prövar behörighet och regler och loggar anropet.

Utkast. Agenten lägger ett svarsutkast på rätt språk i ärendet i ärendetavlan, med länkar till det den har kontrollerat. Den kan skapa utkast men inte skicka.

Godkänna och utföra. Den anställda läser, rättar och skickar från ärendet, från funktionsadressen. Att skicka är godkännandet.

Utfall. Arbetsregistret noterar att svaret är skickat och hur mycket som ändrades. Ärendet har hela samtalet, och registret har bara länken till ärendet.

Lärande. Säger den anställda till om en regel blir det ett förslag direkt. Rättar de anställda ofta samma sak ser Kunskapsförvaltaren mönstret och tar fram ett förslag på bättre exempel eller regel. Processägaren godkänner, och nästa version går ut till alla agenter.

När du frågar själv går frågan direkt till din Bambusa-agent, som svarar med dina behörigheter. Ber du om något som har ett eget jobbkort, till exempel ett mejl till varje klubb som inte har beställt i år, lägger agenten in jobbet i arbetsregistret. Registret ger det till rätt specialist, och din agent följer upp det där. Frågar du ”vad väntar på mig?” hämtar den svaret från registret.

Delarna, en i taget:

Ytorna är platserna där jobbet möter människor och system, inte platserna där data ligger. De följer jobbet i tre steg. Fråga är där en anställd ber agenten om något: Connect och Slack, och senare kanske en sidopanel i webbläsaren. En sidopanel är en smal ruta vid sidan av Chrome som finns där oavsett vilken sida du har uppe, och den kan följa med dig in i HubSpot, Ongoing, Centra och de andra webbaserade systemen. Det finns medvetet få ingångar, och bakom alla finns samma agent med samma regler och logg. Jobb kan också starta utan att någon frågar, när arbetsregistret får en händelse. Godkänna sker där den anställda är: ett utkast godkänns genom att den anställda skickar det, från ärendetavlan eller från Gmail, och handlingar som agenten själv ska utföra kommer som en förfrågan i Slack eller i Connect. Oavsett var det sker loggas godkännandet i arbetsregistret, och det gäller exakt den handlingen. Connect ger överblicken, och för kundtjänst är ärendetavlan i Connect också arbetsplatsen (se Ärendetavlan). Utföra sker i systemet som jobbet gäller: ett utkast eller ett mejl i Gmail eller i ärendetavlan, en samtalslogg eller uppgift i HubSpot, ett dokument i Drive eller ett förslag i Connect. Det är agenten som utför, eller den anställda som skickar utkastet, och det bestäms per jobb. Vi bygger inte en egen agent inne i varje system, för då får vi många ingångar med olika regler och loggar. Kundvända ytor, som chatt på webbplatserna och svar utan en människa emellan, är ett senare steg med egna krav: kunden ska veta att det är en AI, och agenten måste tåla försök att lura den. Formulär med personlig länk är något annat: det finns ingen AI i dem, innehållet kommer från ärendet, och länken går ut. De kan därför tas i bruk så snart ett jobb behöver dem (kapitel 6).

Arbetsregistret håller och fördelar arbetet: jobben som agenterna gör och jobben som väntar på en människa, vart och ett med typ från jobbkortet och BPMN-steget, tillstånd, länk till det som jobbet gäller (tråden i Gmail, dealen i HubSpot, ordern eller kundärendet i Connect), godkännanden och utfall. Det som jobbet gäller, och dess status, ägs av systemet där det finns, och registret sparar länkar, inte kopior. Här ligger godkännandena, här lämnar agenten över till en människa, och här mäts varje jobb. Där agenten föreslår ett värde, som ärendetyp, lösning eller mottagare, sparas förslaget i registret bredvid värdet som människan till slut valde. Då mäts träffsäkerheten per beslut, och det är det beviset som autonomin skruvas upp efter. Överlämningen hamnar där människan redan arbetar, som i ärendetavlan, en uppgift i HubSpot eller ett meddelande i Slack. Visas ett jobb som en uppgift i HubSpot är registret sanningen, och jobbet stängs när uppgiften stängs. Mätningarna visas per jobb och roll, inte per anställd. Vem som godkände vad loggas för spårbarhet, inte för att bedöma den enskilda.

Agenterna är roller med agentkort, av tre slag, utöver de två kontrollrollerna (se nedan). Bambusa-agenten byggs och uppdateras en gång men körs i en egen session för varje anställd, med den anställdas inloggning och behörigheter. Den agerar som den anställda och ser det den anställda ser. Den minns samtalen och den anställdas arbetsvanor, som språk och om agenten ska göra utkast, men den anställda kan inte ha egna regler (se Minnet). Den styr allt den anställda ber om. Den gör det mesta själv, och när ett jobb har ett eget jobbkort lägger den in jobbet i arbetsregistret, som ger det till rätt specialist. Då görs jobbet likadant oavsett vem som ber om det, och specialisten får aldrig mer behörighet än den anställda har. Bambusa-agenten kan också dela upp en stor uppgift på tillfälliga underagenter i samma session. De ärver den anställdas behörigheter och loggen och behöver inget eget agentkort. Specialisterna har egen identitet och får bara de verktyg som jobbkorten ger dem (se nedan), och de startar också själva när arbetsregistret ger dem ett jobb, till exempel när ett mejl kommer in eller en dugnad släpar efter. Arbete som startar av sig självt fördelas av arbetsregistret enligt fasta regler när det är klart vad det är, och sorteras av koordinatorn när något måste läsas först. Koordinatorn är själv en specialist, med minst rättigheter av de agenter som arbetar med kunder (se nedan). En agent kan ändå skapa jobb: en vakt som går igenom dugnaderna varje morgon kan skapa ett uppföljningsjobb för varje dugnad som släpar efter (se Vakter). Ansvaret för jobben som vakten skapar ligger hos processägaren för processen. Specialisterna i figuren är exempel; de faktiska rollerna kommer från jobblistan. En ny agent skapas bara när den behöver andra behörigheter, en annan identitet eller en egen ägare. Annars blir det ett nytt jobbkort för en agent vi redan har. Därför finns det en kundagent med egna jobbkort för Klubb, Grupp, B2B, DTC och support, så länge behörigheterna är desamma. Förvaltarna arbetar med själva systemet, inte med kundarbete, och hör till lärandet i kontrollagret. Revisorn och regelverksrollen arbetar också med systemet, men oberoende av förvaltarna (se nedan).

Plattformen kör alla agenter: modellen, sessionerna, kodkörning och webbläsare, minne och spårning. Det är en plattform i EU (kapitel 8). Den kan bytas eftersom det mesta över och under den är vårt, och kapitel 8 säger vad vi binder oss till.

Kontrollen är styrningslagret (governance), och den står mellan agenterna och det de kan göra. Reglerna och behörigheterna skrivs på ett ställe, i Git, och används två gånger: agenterna läser reglerna för att förstå jobbet, och kontrollen upprätthåller de regler som aldrig får brytas. Datapolicyn är en av dessa regler. Den delar in data i fyra klasser (öppen, intern, personuppgifter och strängt skyddad) och säger vad varje klass får användas till. Den har också utlämningsregler: för varje meddelandetyp och mottagarroll säger de vilka fält mottagaren får se om andra personer. En deltagare får till exempel köparens namn och vilken sorts ärende det är, men aldrig köparens kontaktuppgifter eller detaljerna i ärendet. Reglerna upprätthålls i kod i mallarna och formulären, och det är dem golvet i kapitel 6 hänvisar till när personuppgifter delas. Strängt skyddade uppgifter, som personnummer, privatpersoners kontonummer, hälsouppgifter och lön, hämtar ingen agent från systemen, och verktygen håller dem utanför. Skriver någon sådana uppgifter själv i en förfrågan, döljs numren innan agenten läser den. Det som inte kan döljas används bara för att svara på den förfrågan och kopieras inte vidare. Kundärendet sparar meddelandet som det kom, som strängt skyddat när det innehåller sådana uppgifter, och agenterna ser bara den dolda versionen. Asgeir äger policyn. Anrop till våra verktyg går genom behörighetskontroll och logg, och skrivande handlingar utförs av vår egen kod, med godkännande där jobbkortet kräver det. Inbyggda verktyg på plattformen, som kodkörning och webbläsare, slås bara på där jobbkortet tillåter det. Varje körning har tak för antal steg och kostnad, och varje agent har en stoppknapp. Ingen agent får alla tre av dessa samtidigt utan att en människa godkänner: läsa det vi inte litar på, se personuppgifter och skicka något utanför huset eller ändra affärsdata i systemen, som order, betalningar, kundkort och avtal (Rule of Two). Att registrera arbete räknas inte: att skapa och koppla jobb och kundärenden, skriva anteckningar och utkast i ärendet, sätta etiketter och stänga reklam med en motivering. Det kan ångras och loggas. Ett beslut i ett kundärende räknas. Webben läses bara från länkar som en anställd själv ger och från sökresultat, aldrig från länkar i mejl, formulär eller filer från andra. Kontrollerna ligger i kod, inte i prompten, och ett godkännande gäller exakt den handling och de parametrar som godkändes, och bara så länge förutsättningarna det gavs på håller (se nedan). Release-manifestet styr vilka agenter, jobbkort och skills som är i drift. Lagret rymmer också lärandet. Fyra förvaltare tar hand om var sin del: Kunskapsförvaltaren om det agenterna ska veta, Processförvaltaren om processerna och metoden, Verktygsförvaltaren om verktygen och Dataförvaltaren om datan från systemen, även nycklarna och kopplingarna mellan dem. Förvaltarna läser loggen och testresultaten, föreslår förbättringar och tar fram själva ändringen som ett utkast, till exempel en ny skill med testfall. Ändringen måste klara testsviten, och en människa godkänner den innan den går ut. Ingen agent kan ge sig själv mer: agenterna kan inte ändra sina egna agentkort, jobbkort, behörigheter, autonomi eller budget, och förvaltarna kan inte godkänna sina egna förslag.

Grunden är det agenterna vet och har tillgång till: kunskapen i Git (ett versionsarkiv där varje ändring har ägare och historik) och verktygslagret (MCP, en öppen standard för hur agenter kopplar upp sig mot system) med flexibel läsning, de definierade siffrorna från siffermodellen (kapitel 7), fasta verktyg för handlingar, läsbehörighet till ekonomisystemen och tillgång till den enskildas e-post, kalender, Slack och Drive. Verktygslagret byggs en gång och har samma regler och samma logg för alla agenter, men varje agent får bara de verktyg som jobbkorten ger den. Ett av verktygen är ”Vem är detta?”, som använder identitetsgrafen (se nedan).

Systemen äger data och handlingar, som i dag. Kundärendena är ett nytt område i Connect, skilt från arbetsregistret (se Kundärendet).

Revisorn och regelverksrollen. Två roller i kontrollen kontrollerar oberoende av förvaltarna. De har bara läsbehörighet, rättar inget själva och rapporterar till ägaren.

Revisorn (en roll i kontrollen, inte bolagens revisor) kontrollerar att något är rätt: siffrorna mot källornas egen räkning, avstämningen mot bokföringen (kapitel 7) och förklaringarna mot koden. Kärnan är fasta avstämningar i kod, eftersom en agent som bara bedömer andra agenter delar deras blinda fläckar. Agenten läser avvikelserna och hittar förklaringen. Den körs varje månad, efter stora ändringar och när kontroller ger utslag.

Regelverksrollen kontrollerar att något är tillåtet och inom avtalen. Den håller ordning på lagar, avtal och andra yttre ramar, med källa, en mänsklig ägare och vilka processer och jobbkort de berör. Den säger till när något ändras, kontrollerar ändringar som berör personuppgifter, kunder, pengar, avtal eller autonomi innan de rullas ut, och förbereder ärenden för en jurist. Den ger inga juridiska råd och avgör ingenting.

Båda kommer när siffrorna tas i bruk, inte i den första skivan. Tillsammans med förvaltarna är detta en lätt version av de tre försvarslinjerna: de som gör och förbättrar arbetet, de som kontrollerar att det är tillåtet, och de som reviderar.

Så tar arbetsregistret emot arbete. Registret är en inkorg för arbete. Allt nytt landar i In, och bara det som är oklart går via koordinatorn.

Ett jobb av känd typ, med det som jobbkortet kräver, går direkt vidare till Redo. Det gäller de flesta händelserna från systemen, jobben som Bambusa-agenten lägger in och deljobben som specialisterna skapar under arbetets gång. Allt annat går till koordinatorn, som läser det, tar reda på vad och vem det gäller och fyller i jobbet, eller skickar ärendet till en människa.

Så blir koordinatorn ingen flaskhals, och inget jobb fördelas innan det är redo. Fasta regler fördelar jobben som är redo, och jobbmotorn följer varje jobb tills det är klart. Jobbkortet är receptet för en typ av jobb, och jobbet i registret är ett konkret ärende enligt det receptet. Väntar jobbet på något står det i Väntar med en frist, och ett svar, en händelse eller fristen väcker det igen.

Jobbmotorn (beslut H). Många jobb har flera steg och väntar på något: ett godkännande i Slack, ett svar från en klubb, en frist. Under tiden kan ett system låta bli att svara, eller en server kan starta om. Jobbmotorn för jobben vidare: den startar jobbet, ger stegen som kräver omdöme till en agent, väntar på godkännanden, även i flera dagar, försöker igen när något fallerar, och när en frist går ut påminner den, skickar jobbet till en människa eller stänger det, enligt jobbkortet.

Motorn minns var varje jobb är, så inget går förlorat. Att inget görs två gånger säkras av nyckeln i varje skrivande verktyg (se Handlingar som flyttar pengar eller varor). Agentplattformen kan inte göra detta själv. Den kan spara minne och filer mellan sessioner, men en session i Stockholm varar i högst åtta timmar, och plattformen fortsätter inte ett jobb av sig själv, håller inte frister och väntar inte på ett svar i flera dagar. Fasta flöden, som exportflödet, körs i samma motor.

Registret och motorn får inte bli två sanningar: antingen delar de databas, eller så äger motorn tillståndet och registret visar det. Det här är ingen BPMN-motor som Camunda. Motorn kör kod, och BPMN är fortfarande kartan.

Vakter: rutiner som går av sig själva. Vissa saker kan inte meddelas som en händelse, eftersom de gäller något som inte har hänt, som att en faktura inte har betalats. Någon måste leta efter det. En vakt är ett jobb som jobbmotorn startar enligt ett schema, till exempel varje morgon klockan sju, i stället för när något händer. Den har jobbkort och ägare som andra jobb. Den fasta vakten som håller koll på jobb som står stilla är också en vakt.

Vakten läser och registrerar. Den läser systemen genom verktygslagret och skapar en händelse i arbetsregistret för varje fynd. Arbetet görs av jobbet som händelsen startar, med godkännanden enligt jobbkortet. Därför kan en vakt gå av sig själv från första dagen.

Samma fynd blir inte ett nytt ärende varje dag. Varje fynd får en fast nyckel från det som det gäller, till exempel bolag och fakturanummer, och kopplas till ärendet som är öppet. När fyndet försvinner, till exempel för att fakturan är betald, blir det en händelse som kan stänga jobbet.

Gränsen är en regel med ägare. Vad som räknas som ett fynd står som en regel i Git, så att processägaren kan ändra den utan utvecklaren. Är reglerna olika per land har regeln en variant per land.

Vakten testas innan den slås på. Den går först i skuggläge och visar vad den skulle ha skapat. Ger den onormalt många träffar stannar den och varnar ägaren i stället för att skapa jobben. Fallerar den, eller svarar inte systemet, varnar den fasta vakten ägaren.

Nya vakter. En vakt på ett system som vi redan läser är ett nytt jobbkort och en regel, inte ny kod. En vakt på ett nytt system kräver först ett verktyg och ett systemkort från utvecklaren. Vem som helst kan be Bambusa-agenten om ett utkast, och processägaren godkänner vakten innan den går ut genom manifestet.

Personliga påminnelser kan den anställda skapa själv, till exempel att kontrollera varje fredag om en kund har betalat. De körs med den anställdas behörighet och ger bara besked till den anställda. En vakt som skapar arbete åt andra behöver jobbkort, ägare och godkännande.

Ett exempel: förfallna fakturor. Varje morgon läser vakten de öppna fakturorna i de tre ekonomisystemen. En faktura som har fått påminnelse och fortfarande inte är betald när gränsen är nådd blir ett jobb, eller kopplas till ärendet som redan är öppet. Agenten samlar fakturan, betalningarna, påminnelserna, öppna kundärenden och avtalen i HubSpot, och föreslår nästa steg: ny påminnelse, ett samtal, en avbetalningsplan, kreditering eller inkasso. Har kunden en öppen reklamation är det kanske inte ett betalningsärende alls. En människa bestämmer, eftersom det gäller pengar, och mot dugnader blir det aldrig automatiskt (kapitel 6). Vem som skickar påminnelser i dag, och från vilket system, klargörs innan vakten byggs, så att ingen kund får två påminnelser.

Vem orkestrerar, och hur samarbetar agenterna? Orkestreringen sker på fyra nivåer:

Det som kommer in: din Bambusa-agent tar emot det du ber om, och koordinatorn det som kommer av sig självt och måste förstås innan det kan fördelas, som ett mejl. Koordinatorn tar reda på vad ärendet gäller och vem det kommer från. Saknas något skapar den ett deljobb för att kontrollera. Sedan skapar den rätt jobb i registret, eller skickar ärendet till en människa när den är osäker.

Ett jobb: agenten som har jobbet. Jobbkortet anger målet och gränserna, inte varje steg. Inom gränserna väljer agenten själv vad den måste läsa, vilka skills den använder och när den måste fråga någon.

Allt arbete: arbetsregistret och jobbmotorn. De ser varje jobb från alla anställda och agenter, fördelar enligt fasta regler och ser till att inget blir liggande. Tillsammans med koordinatorn styr de flödet av arbete mellan agenterna. Själva fördelningen är kod, eftersom den ska ske likadant varje gång och kunna testas.

Mål och prioriteringar: människorna. Processägarna äger jobben, och ledningen väljer bland de förslag som agenterna lyfter.

Agenterna samarbetar genom tre saker de delar, inte genom att skicka godtyckliga förfrågningar till varandra:

Gemensam data. Ingen agent äger data. Alla läser genom samma verktygslager, enligt reglerna för varje dataklass. En marknadsagent som behöver ordersiffror eller vad en lead kostade hämtar dem själv från siffermodellen, och reglerna på servern kan ge den siffrorna utan kundlistorna.

Gemensamt arbete. Behöver en agent något som den inte själv har lov att göra, skapar den ett deljobb i arbetsregistret. Registret ger deljobbet till en agent eller en människa som kan göra det, och jobbmotorn låter huvudjobbet vänta tills svaret finns. Passar ingen jobbtyp går deljobbet till processägaren.

Gemensam kunskap. Skills och exempel ligger i Git och kan användas av alla agenter som har lov. Det är behörigheterna som skiljer agenterna åt, inte kunskapen.

Kravet på struktur följer autonomin. När en anställd är med kan Bambusa-agenten hjälpa till med det mesta, även det som inte är kartlagt. Det som ska gå utan en människa måste ha jobbkort, testfall och en ägare.

Vi behöver därför inte strukturera all kunskap innan agenterna kan hjälpa till. Strukturen växer där agenterna arbetar på egen hand: lärandeslingan ser var deljobb och eskaleringar upprepas och föreslår nya jobbkort eller behörigheter där.

Arbete utan jobbkort. Ber en anställd Bambusa-agenten att följa upp något skapar agenten ett jobb i arbetsregistret, och ett kundärende när det gäller en kund. Den frågar vad nästa steg är och när det ska vara gjort, och ägaren är den som bad om det, eller kundtjänst om ärendet lämnas över. Passar ett jobbkort följer jobbet det, och agenten föreslår stegen. Passar inget blir jobbet en manuell uppföljning: en människa äger det, nästa steg och fristen står på jobbet, och jobbmotorn påminner ägaren när fristen kommer. Agenten hjälper till enligt standardreglerna, och inget händer av sig självt utöver påminnelserna. Sådana jobb märks med vilken sorts arbete det är. Upprepas en typ föreslår förvaltarna ett jobbkort, med de steg som människorna faktiskt tog som utgångspunkt.

Vad alla agenter har gjort står i arbetsregistret och i kontrolloggen, och Connect visar överblicken per jobb och roll. Varje anställd har sin egen Bambusa-agent eftersom den agerar med den anställdas behörigheter: den läser din e-post och gör utkast i din inkorg. En gemensam agent för alla skulle ha behövt tillgång till allt, och ett enda fel eller ett försök att lura den i ett mejl skulle kunna nå allt.

Koordinatorn börjar smalt och får större mandat efter bevis, precis som andra agenter. Först sorterar den det som kommer in. Den markerar också ärenden som är brådskande eller innebär risk, som en adress som måste ändras innan paketet skickas, en kund som hänvisar till lagen eller en kund som hotar att byta leverantör. De visas överst i ärendetavlan. Senare kan den prioritera tvärs över kön, följa upp jobb som har fastnat och till slut planera utifrån målen, inom ett mandat från ledningen.

Koordinatorn läser mycket som inte går att lita på, som mejl från okända, och får därför minst rättigheter av de agenter som arbetar med kunder: den kan läsa, slå upp, skapa jobb och kundärenden, koppla meddelanden till öppna ärenden, markera ärenden som är brådskande eller innebär risk och stänga reklam och aviseringar som bara informerar, med en motivering, men inte skicka något utåt eller ändra något hos kunden. Den fördelar efter jobbtyp och roll, inte efter en bedömning av den enskilda anställda, vilket räknas som hög risk i AI-förordningen (AI Act). Hur ofta den sorterar rätt mäts på riktiga mejl i testsviten innan den tas i bruk.

”Vem är detta?” i praktiken. En köpare skriver att hon vill byta en vara hon köpte via en dugnad, utan ordernummer och utan att säga vilken dugnad. Verktyget kontrollerar först om avsändaren redan är kopplad till en order. Finns ingen koppling söker det i apporderna och webbutikerna på e-post, namn och telefon, och ger agenten träffarna med motivering.

Finns det en säker träff går jobbet vidare. Finns det flera möjliga lägger agenten fram dem för den anställda, och kunden tillfrågas bara när sökningen inte hittar något. När kopplingen är bekräftad sparas den med en fast nyckel som inte är e-postadressen, så att nästa agent eller anställd får svaret direkt. Nycklarna från källorna tar med källa och land, eftersom ordernummer bara är unika per webbutik och HubSpot-id:n bara per portal.

En felaktig träff är den största risken här, eftersom den kan skicka en kunds uppgifter till en annan. Därför går bara säkra träffar vidare utan en människa, och sökningen körs på servern, så att agenten ser träffarna och inte hela kundlistan. Var apporderna ligger, och vad Connect redan gör med kundmatchning, kontrollerar vi innan vi bygger (kapitel 9 och frågorna till utvecklaren i kapitel 11).

I dugnad är den fysiska och den ekonomiska ordern inte densamma. Köparordern finns inte i Ongoing, deltagarordern bär plockstatusen, kartong och pall har kollinummer, och samlingsordern ger fakturan. Verktyget ger därför tillbaka nivån och kedjan, från köparen via deltagaren och gruppen till kampanjen, samlingsordern och försändelsen, och inte bara ”en order”.

Roller är kopplingar i en kampanj, inte egenskaper hos personen. Kampanj är appens namn på en dugnad. Många kan kontakta oss om samma dugnad, så alla roller är definierade:

Dugnadsansvarig: den som har ansvaret för dugnaden i klubben eller organisationen. En kampanj kan ha flera.

Gruppledare, även kallad lagledare: den som leder en grupp, det vill säga deltagarna under en gruppledare. En grupp är inte försäljningsströmmen Grupp.

Deltagare: den som säljer i dugnaden.

Vårdnadshavare: den som har ansvaret för en deltagare under 18 år.

Köpare, även kallad stödköpare: den som köper något för att stödja dugnaden.

Mottagare av samlingsleveransen: den som tar emot varorna till dugnaden.

Kontoinnehavare: den som äger kontot som vinsten betalas ut till.

Bambusas egna roller, som kundtjänst och rådgivaren som följer upp dugnaden.

En person kan ha flera roller i samma kampanj, till exempel köpare, vårdnadshavare och gruppledare, och den som anmäler ett ärende är ofta en annan än kunden. Påstår avsändaren en roll, som dugnadsansvarig, säger verktyget om rollen är bekräftad mot registrerade kontaktuppgifter. En roll som inte är bekräftad ger inte tillgång till mer. Leveransadressen och kontonumret är fält på kampanjen, inte roller. Ett kontonummer som tillhör en privatperson är strängt skyddat, och kontonumret ändras bara av en människa, efter att kontoinnehavaren har bekräftats.

När ärendet tar dagar. En kund vill byta en vara, men vi vet inte vilken order det gäller. Så här går ärendet genom arkitekturen:

Koordinatorn skapar ett kundärende och ett ärendeförlopp för förfrågan och försöker hitta ordern med ”Vem är detta?”.

Hittar den ingen order gör kundagenten ett utkast som ber kunden om mer information, och den anställda skickar det. Jobbmotorn väntar på svaret och påminner om det inte kommer.

När kunden svarar kopplas svaret till det öppna förloppet och samma kundärende i stället för att bli ett nytt ärende, och sökningen körs igen med det kunden har berättat.

Kundagenten hittar varorna på ordern. Saknas något, som vilken vara kunden vill byta, vad den ska bytas mot eller vart den ska skickas, får kunden ett formulär att fylla i. Lagret i Ongoing kontrolleras innan agenten lovar något.

Den föreslår bytet enligt jobbkortet, och jobbkortets regel säger när bytesvaran skickas: direkt, när returen har skannats hos transportören, eller när lagret har tagit emot den. För strumpor lönar det sig ofta inte att få tillbaka varan, och då skickas bara bytesvaran.

Ska bytesvaran vänta på returen, väntar förloppet i flera dagar om det behövs, tills lagret meddelar att returen är mottagen. Bytet utförs med kommandot för byte (beslut M) när en människa har godkänt det, och precis innan bytesvaran skickas kontrolleras lagret och förutsättningarna igen. Ska byten senare gå utan en människa görs det av ett fast flöde enligt en regel, inte av agenten.

Är varan slut då, eller händer något som inte finns i kartan, går ärendet till en människa med ett förslag.

Fyra saker gör att detta tål verkligheten:

Ärendeförloppet håller ihop jobben. En förfrågan blir ett ärendeförlopp i arbetsregistret, med jobben, väntetiderna och fristerna i ordning, och jobbmotorn driver förloppet framåt. I kundtjänst hör varje förlopp till ett kundärende, som har meddelandena, vem som har ärendet, statusen och det som är beslutat om varor och pengar. Förloppet länkar till kundärendet. Statusen på kundärendet sätts av den som har ärendet, eller av en fast regel i jobbkortet, till exempel att ärendet stängs när kunden inte har svarat inom fristen.

Nya händelser kopplas först till öppna förlopp. Ett svar från kunden, en mottagen retur eller en betalning blir inte ett nytt ärende när den hör till ett som redan är öppet. Den kopplas på med fasta nycklar där de finns, som tråd-id eller ordernummer, och av koordinatorn när det är oklart. Jobbmotorn fortsätter där förloppet väntade.

Inget jobb väntar utan frist. Varje väntan har en frist och en regel för vad som händer när den går ut: påminna och vänta igen, låta kundtjänst ringa, eller stänga jobbet, och kundärendet när jobbkortet säger det. Regeln står i jobbkortet och BPMN-kartan, och jobbmotorn håller koll på tiden. Det vi väntar på utifrån, som spårning från PostNord, en status i Ongoing eller svar från en leverantör, kommer som en händelse, eller kontrolleras med jämna mellanrum när systemet inte meddelar själv. En fast vakt varnar ägaren om jobb som står stilla. Vilka system som kan meddela själva, och vad Connect redan hämtar, kontrollerar vi innan vi bygger.

Kartan och omdömet. BPMN-flödet för byte och retur, som ännu inte är kartlagt, blir kartan: den vanliga vägen och de kända avvikelserna. Agenten följer kartan där den passar och använder omdöme inom jobbkortets gränser där verkligheten avviker. Vi skriver inte rutiner för allt. Det som inte passar går till en människa, och svaren blir nya regler när de upprepas.

Kundärendet. Varje förfrågan till kundtjänst blir ett kundärende. Ärenden om retur, byte, reklamation eller något som saknas har dessutom tillstånd som inget av källsystemen håller: vad som är beslutat per paket och varför, om beslutet är kulans, vilken fas kampanjen var i, om ekonomi har valt förlust eller krav, numret på kreditfakturan, kopplingen från originalet till ersättningen och återbetalningen som är beställd. Kundärendet finns därför i Connect, som ett eget område skilt från arbetsregistret. Registret är arbetslistan för agenter och människor, medan kundärendet kan vara underlag för kreditfakturor och måste kunna följa bokföringens regler för arkivering. Det som beslutas per paket förs i dag för hand bredvid ordern, i kalkylbladet ”APP- Lager mangel og avvik”, med egna flikar för plockfel och brister och för varubyten. Kundärendet ska ersätta det när delen om varor och pengar är på plats.

Varje kundärende har sitt ärendeförlopp i arbetsregistret: kundärendet håller det som gäller kunden, och förloppet håller jobben. Anställda och agenter läser och ändrar kundärendet genom verktygslagret, med samma regler. Ett ärende kan vara klart för kunden och fortfarande öppet för ekonomi, som väljer förlust eller krav senare. HubSpot passar dåligt som hem för beslut om pengar, eftersom det har en portal per land och begränsad historik per fält. Kundärendet byggs i en enkel version med det första jobbet som svarar på kundförfrågningar, och delen om varor och pengar kommer med det första jobbet som behöver den.

Kundkontakt i alla kanaler. Kunder tar kontakt på funktionsadresserna, i den enskildas inkorg när de svarar på ett mejl eller en sekvens från HubSpot, och på telefon. Ärendet följer kunden, inte brevlådan. Varje anställd med kundkontakt kopplar själv sin inkorg till sin egen Bambusa-agent, samma agent som de pratar med i Connect och Slack. Agenten ser kundmejl in och ut, även det som skickas från HubSpot, eftersom det går genom Gmail, och hjälper till med utkast där den anställda arbetar. Funktionsadresserna kopplas till kundtjänstrollen och läses med en egen identitet, inte med en anställds inloggning, utom i det första testet (se nedan).

Det kunden behöver få löst eller levererat, som order, leverans, retur, faktura och reklamation, hör hemma i ett kundärende, oavsett vilken inkorg det kom till. Hur det blir ett ärende står under överlämning till kundtjänst. Uppstart, uppföljning och försäljning hör hemma i HubSpot, och agenten föreslår när ett samtal går från det ena till det andra.

Arbetet sker där det passar: i ärendetavlan, i Gmail, i HubSpot eller på telefon. Skickar den anställda en fakturakopia från Gmail efter ett telefonsamtal ser agenten det. I kundtjänst registrerar den ärendet själv, och hos andra föreslår den det (se nedan). Samtal loggas fortfarande i HubSpot.

Det som händer utanför ärendetavlan hör också till ärendet. Samtal som loggas i HubSpot kopplas till ärendet som länkar. Med ett klick kan den anställda koppla en tråd i Slack eller ett IT-ärende till ärendet, eller notera det den har gjort själv, till exempel i telefon eller i App Admin. När ett IT-ärende är löst blir det en händelse som väcker jobbet. Ber en kund om att bli uppringd blir det ett jobb för kundtjänstrollen, inte bara en avisering till den som har telefonen. Aviseringen måste därför komma till en funktionsadress eller som en händelse från Phonero.

Ärendet sparar meddelandena som hör till det, med dataklass och lagringstid, så att en kollega kan ta över även om tråden ligger i någon annans inkorg. Meddelandena och underlaget för kreditfakturor har var sin lagringstid, som datapolicyn sätter och Connect raderar efter. Kundärendena ägs av processägaren för kundtjänst, tills vidare Asgeir.

Ber någon om att få ut eller radera sina personuppgifter blir det en egen typ av kundärende med en tidsfrist, som enligt dataskyddsförordningen som huvudregel är en månad. Den som ansvarar för dataskyddet har ärendet, och identiteten på den som frågar bekräftas innan något lämnas ut eller raderas. Hur radering sker i varje system avgörs separat, som beslut D säger, och det som måste bevaras enligt bokföringsreglerna behålls så länge reglerna kräver.

Allt som väntar på någon är ett jobb i arbetsregistret. Ber en anställd agenten i Slack att en kollega ska kontrollera en order, blir det ett jobb för kollegan, och varje anställd ser sitt när de frågar agenten ”Vad väntar på mig?”.

I de anställdas egna inkorgar letar agenten bara efter kundmejl. Nyhetsbrev, aviseringar och privat e-post registreras inte.

Norge har egna regler för arbetsgivarens insyn i anställdas e-post. Därför kopplar den anställda själv sin inkorg till agenten, bara kundmejl som blir ett ärende sparas, och upplägget bedöms av en jurist i DPIA:n och diskuteras med de anställda innan fler än testarna tas med. HubSpot synkroniserar redan e-post från inkorgarna, så det är inte nytt i princip.

Ärendetavlan. Ärendetavlan (saksbordet på norska) i Connect visar alla kundärenden, oavsett vilken inkorg de kom från, och är kundtjänstens arbetsplats. De som arbetar med ärenden använder den, och de andra behöver den inte, eftersom agenten hjälper dem att lämna över ärendena. Från funktionsadresserna registreras varje mejl som kommer in, även det som Gmail har lagt i skräpposten, eftersom kundförfrågningar också kan hamna där. En ny förfrågan från en kund blir ett kundärende, och svar i en tråd kopplas till ärendet de hör till. Reklam och aviseringar som bara informerar stängs automatiskt med en motivering och ligger i en egen vy, så att sorteringen kan kontrolleras. En avisering som ska leda till arbete, till exempel att lagret har tagit emot en retur, blir en händelse på ärendet den hör till, eller ett nytt kundärende när inget är öppet. Det som står i aviseringen kontrolleras i källsystemet innan något görs. Det som inte gäller kunder, som fakturor från leverantörer, blir ett jobb för rätt person.

De anställda ser nya ärenden, egna ärenden och ärenden som väntar, med det som är brådskande eller innebär risk överst. I ärendet finns kunden, ordern, hela samtalet med bilagorna och agentens utkast. Under utkastet står det agenten har kontrollerat, med länkar, och det den inte kunde kontrollera, i samma form som på överlämningskortet (se nedan). Då går godkännandet snabbt, och den anställda vet vad den godkänner. Den anställda rättar utkastet eller väljer en mall eller ett formulär, och skickar från ärendet. Kundtjänst svarar från funktionsadressen, med den anställdas namn i signaturen. Då kommer kundens svar tillbaka till samma ärende och inte till personen, och en kollega kan ta över utan att något måste flyttas. Svarar någon ändå från Gmail, eller från HubSpot, som skickar genom Gmail, fångar agenten upp det och uppdaterar ärendet.

Att skicka från ärendet är det mänskliga godkännande som Rule of Two kräver. Ärendet sparar utkastet och det som skickades, och arbetsregistret sparar hur mycket som ändrades. Agenten läser bilder och bilagor från kunder som data, inte som instruktioner, och kan bifoga dokument i utkastet, som en fakturakopia eller en verifikation, även från kundens andra trådar och ärenden. Innan något skickas kontrolleras det i kod att mottagaren och varje bilaga hör till ärendet, att bilagorna är med och att ingen intern text följer med. Har en kollega skrivit i kundens tråd, till exempel vid en vidarebefordran, skickas svaret därför i en ny tråd. Ärendetavlan måste fungera bra i mobilen, även för att svara. När flera delar en adress tar de anställda nya ärenden från listan, och svaren hamnar hos den som äger ärendet. För andra roller lägger agenterna fortfarande utkast i den anställdas egen Gmail.

Överlämning till kundtjänst. För kundtjänst kan agenten registrera kundärenden på egen hand, eftersom det är deras jobb. Med kundtjänst menas teamet som arbetar från ärendetavlan, inte Klubb-CS. För alla andra bestämmer den anställda vad som blir ett kundärende, så bara mejl som den anställda själv väljer att skicka vidare hamnar i ärendet. När en tråd har lämnats över kopplas nya meddelanden i den till ärendet. Det finns tre sätt att lämna över, och alla hamnar i samma ärende:

Etikett i Gmail, huvudvägen. Den anställda sätter etiketten ”Till kundtjänst” på mejlet, på datorn eller i Gmail-appen. Agenten skapar ärendet med meddelandena som hör till och byter etiketten mot ärendenumret, så att den anställda ser att ärendet är taget.

Agenten föreslår. Ser agenten ett kundmejl som liknar ett kundärende, till exempel en fråga om en faktura, frågar den i Slack om kundtjänst ska ta det, och den anställda svarar med ett tryck. I början flyttar agenten ingenting på egen hand för dem som inte arbetar i kundtjänst, och att ändra det kräver en ny bedömning av dataskyddet och en ändring av beslut L.

Vidarebefordran till kundeservice@, reserven. Den fungerar för alla, även för dem som inte har kopplat sin inkorg till agenten. Koordinatorn ser att mejlet är vidarebefordrat från en anställd, hittar kunden och skapar ärendet, och det den anställda har skrivit blir en anteckning i ärendet.

Ärendet hamnar bland de nya ärendena hos kundtjänst, med vem som skickade det och kopplingen till kunden i HubSpot. Kundtjänst svarar kunden från funktionsadressen och säger att de har tagit över, och svarar kunden ändå den som skickade ärendet, kopplar agenten svaret till ärendet. Den som skickade ärendet kan följa det och får besked när det är löst. Det går åt båda hållen: kundtjänst kan skicka tillbaka ett ärende, eller göra om det till en uppgift i HubSpot när det gäller uppstart eller försäljning. Senare kan en knapp i Gmail med plats för en kommentar ersätta etiketten.

Vem som gör vad. Den anställdas Bambusa-agent läser etiketterna och skapar ärendet, föreslår överlämning och fångar upp svar i den anställdas inkorg. Koordinatorn läser funktionsadresserna och vidarebefordringarna, skapar och kopplar ärenden och stänger reklam. Kundagenten gör utkast och utför jobben i ärendet. Ett svar i samma tråd kopplas till ärendet med tråd-id:t, utan att en agent måste tolka det, och koordinatorn kopplar bara när det är oklart. En kund kan ha flera ärenden, och finns det redan ett öppet ärende för samma tråd används det.

I dag routas funktionsadresserna till en anställd i Gmail-administrationen. Det första testet av kundtjänstmejl körs i skuggläge på den inkorgen, med den anställdas egen inloggning och routningen på, medan kundtjänst arbetar som förut. Då läses bara mejl som har skickats till funktionsadresserna, även när de ligger i skräpposten. Tas utkasten i bruk innan routningen är avstängd, går svaren från ärendetavlan ändå från funktionsadressen. Innan fler anställda tas med kopplas funktionsbrevlådorna direkt till kundtjänstrollen och routningen stängs av, så att semester och byte av person inte kräver ändringar i Gmail-administrationen.

Handlingar som flyttar pengar eller varor. Ett av de dyraste felen är att göra något två gånger, som att återbetala samma paket två gånger. Att varje verktyg tål ett nytt försök räcker inte ensamt, eftersom samma återbetalning kan utlösas av en agent, av en anställd i Connect och av en anställd direkt i WooCommerce, Centra eller App Admin. Därför gäller fyra saker:

Ett kommando per handling, som att återbetala, kreditera, ändra en order eller skapa en ersättningsorder. Reglerna ligger i kommandot, och anställda och agenter använder samma kommando. En order med belopp, som en mellanskillnad vid byte, ger faktura automatiskt, och fakturan är en del av konsekvensen som godkänns.

Nyckeln som hindrar att något görs två gånger skapas av vad som görs och varför (kundärendet och beslutet i det, ordern, paketen och beloppet), aldrig av tidpunkten, och sparas före anropet. Ett nytt försök, även från en annan agent eller anställd, blir då inte en ny återbetalning, medan en ny ersättning för samma paket har ett eget beslut och en egen nyckel.

Återbetalningar och ändringar som görs direkt i systemen läses in, kopplas till kundärendet och stoppar jobb och godkännanden som väntar på samma sak.

Ett godkännande sparar förutsättningarna och konsekvensen det gavs på, som att varorna inte är plockade, att fakturan inte är skapad och vad kunden får tillbaka. Precis innan utförandet kontrolleras förutsättningarna igen, och har något ändrats krävs ett nytt godkännande med den nya konsekvensen. Samma mekanism används när en anställd behöver godkännande över sin beloppsgräns.

När någon är borta eller något stannar. Inget jobb ska fastna för att en person inte svarar. Det gäller även i den första versionen, även om vi då bara är några få:

Jobbet går till en roll, inte bara en person. Svarar inte personen inom fristen, till exempel på grund av semester, eskaleras jobbet till nästa i ledet: en annan i teamet, sedan chefen eller processägaren. Är det känt att personen är borta går jobbet direkt vidare. Jobbkortet anger vilka som står i ledet, och vakten ser till att inget blir liggande.

Slutar någon eller förlorar behörighet flyttas de öppna jobben till rollen. Jobb som behövde personens fullmakt väntar på nytt godkännande, och fel som beror på saknad behörighet försöks inte igen.

Ett jobb som avbryts stannar där det är. Loggen visar vad som är gjort, och jobbkortet anger om något måste rullas tillbaka.

Samma händelse två gånger blir ett jobb, eftersom varje händelse får en egen nyckel.

Samtalet måste ligga där rollen ser det. För kundtjänst ligger det i ärendetavlan, och svaren går från funktionsadressen, så att någon annan kan ta över. För andra roller ligger det i den första versionen i den enskildas inkorg.

Utredningar. Vissa ärenden handlar om vad som egentligen har hänt: en kund som har debiterats för en vara utan att få den, eller en klubb som anser att sponsorbeloppet är fel. Då skapar koordinatorn en utredning. En specialist med läsbehörighet hämtar det som behövs: betalningen hos betallösningen, ordern i appen, fakturan och utbetalningen i Tripletex och dealen i HubSpot.

Specialisten ställer upp vad varje system säger och var de skiljer sig åt. Beslutet fattas av en människa, eftersom det gäller pengar. En eventuell kontakt med redovisningsbyrån görs som ett utkast.

När agenten inte vet frågar den med sammanhang. Agenten slår först upp själv och frågar varken kunden eller den anställda om något den kan hitta i systemen. Den frågar en människa när den inte hittar ett säkert svar, när systemen säger emot varandra, när ärendet gäller pengar, priser, avtal eller personuppgifter, eller när ingen jobbtyp passar. Frågan kommer alltid i samma form, ett överlämningskort:

vad kunden vill

vad som är kontrollerat, och vad systemen visar, med länkar

var det finns oenighet eller något saknas

vilka val som finns, och vad agenten rekommenderar

Kortet går som ett deljobb till den som äger svaret, som ofta inte är den som har ärendet, till exempel ekonomi vid kreditering, sälj vid rabatt och pris, produkt vid frågor om varorna och processägaren när en regel saknas. Den som har ärendet ser att frågan väntar. Den som får kortet svarar där den redan arbetar, svaret sparas i förloppet, och jobbmotorn fortsätter. Upprepas samma fråga föreslår förvaltarna en regel, så att agenten klarar det själv nästa gång.

Samma kort används när en regel eller en definition måste bestämmas. Då visar det också konkreta exempel, med namngivna kunder, produkter och system, och vad varje val gör med siffrorna. Sådana frågor samlas i omgångar, eftersom ägarens tid är knapp.

Connect är ryggraden. Det mesta av det som är vårt finns i Connect: arbetsregistret, kundärendena, identitetsgrafen, siffermodellen, verktygslagret och chatten. Agentplattformen är hyrd. Därför behöver vi tidigt svar på vilket språk och ramverk Connect och Hivemind är skrivna i, var de körs och hur Hivemind kör jobb i dag (kapitel 11).

Connect är ändå inte röret för allt. Order går till ekonomisystemen via egna integrationer från leverantörer, utanför Connect (D-016).

Två sorters logg. Ordet logg betyder två saker här. Den ena är affärsloggen: samtal, möten och mejl som loggas i HubSpot, som säljare och kundtjänst gör i dag. Ett samtal är en händelse som kan bli ett jobb, till exempel att agenten skriver samtalsloggen från en inspelning eller ett röstmeddelande, och loggen levereras i HubSpot. Den andra är kontrolloggen: vad agenterna har gjort, med länk till godkännandet i arbetsregistret, och vad det kostade. Den ligger i kontrollagret och används för spårbarhet och lärande.

Fasta format, utbytbara delar. Det som blir dyrt att ändra senare är formaten mellan lagren: nycklarna för enheterna i beslut D, med källa och land, rollerna i en kampanj, formatet på ett ärendeförlopp, ett jobb och ett kundärende, jobbkortet, agentkortet, överlämningskortet, godkännandet med förutsättningar och konsekvens, nyckeln som hindrar att en handling görs två gånger, verktygens gränssnitt, mallarna och formulären, id:na i kunskapen, definitionen av en siffra och svarsformatet för den, regelformatet med vem som beslutade, när, varför och från och till när regeln gäller, och loggformatet. Dem gör vi noggrant från start och versionshanterar. Det som ändras snabbt, som modell, plattform och ytor, håller vi tunt. Ett exempel: OpenAI lade ner Assistants API i augusti 2026 och lägger ner Agent Builder den 30 november, samma år som de lanserade ett nytt Agents API. Det som ska överleva en leverantör, som tillstånd, godkännanden, processdefinitioner, definitionerna och historiken för siffror, testsviter och logg, måste ligga hos oss.

5. Så flödar informationen
   Fyra slingor, var och en med en ägare:

Arbetsslingan (ägare: processägaren för jobbet). En händelse, som ett mejl, en order, en leverans, en frist eller en fråga från en anställd, blir ett jobb i arbetsregistret, länkat till det den gäller. Agenten hämtar det den behöver från kunskapen, identitetsgrafen och systemen, gör ett utkast eller utför, och en människa godkänner där jobbkortet kräver det. Handlingen sker i systemet som äger den, och agenten läser systemet igen för att bekräfta att det blev rätt, innan jobbet stängs.

Lärandeslingan (ägare: processägarna; förvaltarna gör arbetet). Rättelser i utkast, avvisade förslag, flaggor från anställda och fel samlas på jobben. Säger en anställd till om en regel sparas det som ett förslag direkt och väntar inte på veckosammanfattningen. Gäller det bara det egna arbetssättet sparas det i den anställdas eget minne. Gäller det hur verksamheten arbetar går det som ett förslag till processägaren, så att en regel aldrig blir en personlig vana. Kunskapsförvaltaren hittar mönstren och föreslår ändringar i kunskapen, Verktygsförvaltaren i verktygen och Processförvaltaren i processerna. Ägaren godkänner, och den nya versionen går ut till alla agenter genom manifestet. Varje fel som når produktion blir ett nytt testfall. Detta är Governed Maintenance Protocol i drift.

Dataslingan (ägare: ägaren av källsystemet). Fel i data som agenterna hittar, som en dubbel kund, ett felaktigt pris eller ett lagersaldo som inte stämmer, flaggas till ägaren av systemet och rättas där. Agenten rättar aldrig fel i sitt eget minne; det rätta värdet ska stå i källan. Kan källan inte rättas, till exempel för att historiken är borta, skapas en dokumenterad regel eller överstyrning i siffermodellen, med vem, när och varför. Dataförvaltaren följer källorna: nya värden som ingen har placerat, kontroller som ger utslag, kontrollsiffror som glider och kopplingar mellan systemen som inte stämmer. Den föreslår ändringen med test och siffror före och efter. Ägaren av källsystemet beslutar om rättelser i källan, och siffrans ägare godkänner regler och överstyrningar i siffermodellen. Förfrågningar som beror på oss själva hör också hit: påminnelser till folk som har betalat, kvitton till fel person och autosvar på våra egna utskick. Koordinatorn markerar dem med orsak, och ägaren av systemet eller processen får dem samlade, med antal, så att orsaken kan tas bort. Inom Lean kallas det mesta av detta failure demand.

Styrningsslingan (ägare: ledningen). Målen ligger i kunskapen, och siffrorna kommer från siffermodellen i Connect, räknade från källsystemen (kapitel 7). Agenterna bevakar utvecklingen, lyfter avvikelser och förslag med motivering, förväntad effekt och ett datum för uppföljning, och ledningen väljer. Valen blir nytt arbete eller nya mål. Det är här ”agenterna styr företaget” börjar: som förslag med motivering, där beslutet fattas av en människa. Förslagen och svaren på dem loggas, så att förvaltarna kan föreslå ändringar i mål och policyer när mönstret är tydligt.

Var informationen finns:

Affärsdata finns i systemet som äger dem. Agenterna läser genom verktygslagret och sparar länkar, inte kopior. Undantagen är historiken i siffermodellen och meddelandena som hör till ett kundärende, båda styrda lager i Connect med ägare, dataklass och lagringstid (kapitel 4 och 7).

Jobben och godkännandena finns i arbetsregistret. Kundärendena finns i Connect, med det som beslutas om varor och pengar och en kopia av meddelandena som hör till dem, både från funktionsbrevlådorna och från de anställdas inkorgar. Andra samtal finns där de finns i dag.

Det som styr agenterna finns i Git med ägare och version: mål, policyer, regler, jobbkort, mallar och formulär, och exempel. Kunskap som bara gäller en period, som villkoren för en rabattkod eller ett besked om förseningar på lagret, har start, slut och ägare, och agenterna använder den inte efter slutdatumet. De anställda läser och redigerar det genom Connect. Ett dokument i Drive ändrar inte hur agenterna arbetar förrän ägaren har tagit in det i Git.

Dokument och filer finns i Google Drive: kalkylblad, broschyrer, bilder, ljud och video, och det kommer nya hela tiden. Agenterna arbetar direkt i Drive genom verktygslagret. De söker, läser, skapar och ändrar filer med den anställdas behörighet eller med den behörighet som jobbkortet ger. Ber du om ett nytt kalkylblad skapar agenten det i Drive. Kalkylblad som förs för hand bredvid ett system är dubbelregistrering. Innehållet får ett hem och en ägare, i systemet som äger det eller i kundärendet, och kalkylbladet fasas ut. Kalkylblad som själva är källan, som budgeten, läses in i siffermodellen (kapitel 7). Det som skickas till kunder, som broschyrer och villkor, läggs på en egen delad enhet där ägaren bara har gällande versioner, så att agenten inte skickar ett gammalt utkast. Drive kan också meddela när något nytt läggs i en mapp, till exempel nya produktbilder, och då blir det ett jobb. Innehållet i filerna är data för agenterna, inte instruktioner.

Vem som är vem finns i identitetsgrafen: nycklar och kopplingar, inte hela kundkort.

Den anställdas e-post, kalender och Slack läses med den anställdas behörighet när det behövs, och sparas inte, med undantag för kundmejl som blir en del av ett kundärende.

Allt agenterna minns har en ägare, en lagringstid och ett sätt att raderas på, och ingen agent har dolt minne om verksamheten. Hur minnet är uppbyggt står nedan.

BOS-arkivet, det gamla BOS-projektet, ligger som ett uppslagsverk i Git, märkt som inte gällande. Detsamma gäller prototypen av KPI-verktyget. Agenterna kan slå upp i dem men följer dem inte förrän innehållet har tagits in och godkänts (kapitel 9).

Minnet. Agenterna ska minnas bra, så att ingen behöver förklara samma sak två gånger. Det de minns ligger i fem lager, och varje lager ligger där det fungerar bäst:

Vad agenten minns

Var

Vem som ser det

Hur länge

Samtalet nu, med filer och svar

Själva samtalet

Den anställda

Medan samtalet pågår. Långa samtal sammanfattas, så att inget går förlorat

Tidigare samtal, vad den anställda arbetar med och hur den vill arbeta

Den anställdas eget minne, i minnestjänsten på plattformen

Bara den anställda

Tills den anställda raderar det, och senast när den slutar. Hela samtal sparas i 30 dagar

Vad som är gjort, vad som väntar och vad som är beslutat

Arbetsregistret och kundärendet

Alla som arbetar med jobbet eller ärendet

Enligt reglerna för jobbet och ärendet

Det alla agenter ska veta: regler, processer, produktkunskap och det vi har lärt oss

Kunskapen i Git

Alla agenter med behörighet

Tills ägaren ändrar det

Fakta om kunder, order, lager och siffror

Systemen och siffermodellen

Den som har behörighet

Så som systemet sparar dem

Så här upplevs det: På tisdagen ber en anställd agenten fortsätta med budgeten för Sverige. Agenten minns samtalet från måndagen och att den anställda ville ha siffrorna utan moms. Den hittar utkastet i Drive, hämtar siffrorna på nytt så att de är färska och använder reglerna i kunskapen. Ingenting behöver förklaras på nytt.

Fem regler gör att minnet håller i drift:

Fakta hämtas från källan varje gång. Minnet sparar sammanhanget och länkarna, inte kopior av order och kundkort. Annars svarar agenten med gårdagens status.

Den anställdas minne är den anställdas eget. Den anställda kan fråga ”Vad minns du om mig?” och rätta eller radera det. Ledningen läser det bara enligt samma regler som för arbetsgivarens insyn i e-post, och det används inte för att bedöma någon.

Det som gäller alla går till ägaren. Säger den anställda något som är en regel för alla frågar agenten om det bara ska minnas för den anställda eller föreslås som regel (se Lärandeslingan). Då sprids inte en persons misstag till alla agenter.

Kunduppgifter sparas i ärendet, inte i minnet. Minnet hänvisar till ärendet, så att en kund kan raderas på ett ställe, och strängt skyddade uppgifter sparas aldrig i minnet.

Det agenterna läser från andra blir aldrig en instruktion i minnet. Ett mejl från en okänd ska inte kunna plantera något som agenten följer senare. Därför har koordinatorn och specialisterna inget eget minne mellan jobben. Det de behöver veta följer jobbet och ärendet.

Sammanhanget följer också arbetet mellan agenterna. Ger Bambusa-agenten ett jobb till en specialist följer det som är kontrollerat och beslutat med jobbet, och svaret kommer tillbaka samma väg. Återkoppling från kunder om varorna följer samma mönster: det kunden sa ligger i ärendet, märkt med SKU, och det vi lär oss av det blir kunskap med en ägare. Det personliga minnet är det enda lagret som ligger hos plattformen. Byter vi plattform kan det flyttas eller byggas upp på nytt, medan allt annat redan ligger hos oss. Detta är beslut N.

6. Processmodellen som karta över arbetet
   BPMN/DMN ska inte bara dokumentera. Det blir kartan som agenterna arbetar efter, och platsen där kunskapen, arbetet och autonomin möts. Ett steg i ett flöde blir en jobbtyp när en agent ska utföra det eller hjälpa till, och då länkas steget med fasta id:n till:

jobbkortet: utlösare och indata, vad som är klart och var det levereras, verktyg, godkännande och budget

vem som utför: en roll eller ett agentkort

reglerna som gäller: BR-id och DMN-tabell. Där flera regler begränsar samma sak, som behörighet, godkännande eller delning, vinner den strängaste. Regler som klassificerar gäller var och en inom sitt område: en strumpa med hål efter tre månader är en reklamation inom fristen, även om fristen för att returnera har gått ut

data som steget läser och skriver, och systemet som äger dem (bindings)

tillvägagångssättet (skill) där det behövs, och exempel på bra arbete

testfallen som visar vad bra arbete är

autonomin som steget har nu, och ägaren som godkänner ändringar

Vid varje ändring bygger en automatisk kontroll (CI) en länkkatalog över alla id:n och länkar, och stoppar ändringar som bryter en länk. Agenterna frågar katalogen: ”vilken process gäller en retur från en grupp i Danmark?”, ”vilka regler gäller i det här steget?”, ”vem äger BR-012?”. Jobbet i arbetsregistret pekar på process och steg. Då får agenten rätt sammanhang utan att leta, och mätningarna hamnar på rätt steg. I dag är bara digital dugnad kartlagd fullt ut, så flödet för den första skivan kartläggs, med ägare, innan utkasten tas i bruk.

När något ändras. Katalogen visar också vad en ändring berör. Ändras en regel eller ett steg ser förvaltarna vilka jobbkort, skills och testfall som använder den, och ändringen går inte ut förrän de är uppdaterade eller kontrollerade. En ändring i verksamheten, som ett nytt pris, är en händelse. Flödet för prisändring anger vad som måste följa med, som offertmallar och säljmaterial, och jobbmotorn följer upp tills allt är gjort. Vi lägger in följderna i flödena där ändringar sker ofta, och bygger inte en egen karta över alla beroenden.

Beslut ändrar kunskapen där den finns. Ett beslut är en händelse som ändrar något som redan har ett hem. Det sparas en gång, där det används:

vad som är sant, och hur vi räknar: regeln eller definitionen av siffran

hur vi arbetar: processen

gränser, och vem som bestämmer: policyn

vad en agent får göra: jobbkortet, agentkortet eller autonomin

hur systemet är byggt: arkitekturens beslutslogg

ett enskilt ärende: ärendet självt, eller en dokumenterad överstyrning

Historiken säger vem som beslutade, när och varför, och från vilket datum beslutet gäller, även om det gäller bakåt i tiden. Godkännandet ligger i arbetsregistret. Jobbet är klart först när ändringen är gjord i allt som länkkatalogen visar att den berör, i en samlad ändring med tester, och ett beslut i ett enskilt ärende blir en regel när det upprepas.

Kunskapen ordnas i lager, från det som sällan ändras till det som ändras ofta: mål och policyer, med vem som äger vad (varför, var gränserna går och vem som bestämmer), processer och regler (vad som händer, och vad som alltid gäller) och tillvägagångssätt och exempel (hur, där det behövs). Definitionerna av siffror hör hemma bland reglerna, och systemkorten bland tillvägagångssätten. Ju bättre modellerna blir, desto mer klarar sig agenterna med mål, policyer och exempel, och desto färre detaljerade instruktioner behövs. Processförvaltaren tar fram och underhåller metoden och följer hur den bör utvecklas, men ändringarna godkänns av metodens ägare, Asgeir. Detta är beslut E.

Autonomin har två skruvar per jobb, inte en:

Vem väljer nästa steg? Ett fast flöde i kod där stegen är kända och stabila, en agent där jobbet kräver omdöme. Exportflödet är ett exempel på det första, en kundfråga på det andra.

Vad får jobbet göra? Läsa, föreslå, skriva i våra egna system eller skicka något utanför huset. Vad som blir automatiskt avgör processägaren per process när den byggs. Fasta meddelanden som ”ordern är skickad” och ”returen är godkänd” går från mallar i fasta flöden. Kundsvar som agenten skriver själv är utkast som en människa skickar, även när agenten har förtjänat förtroende. En agent som svarar på ett kundmejl läser något vi inte litar på, ser personuppgifter och skickar utanför huset, alla tre i Rule of Two. Vägen till automatiska svar är därför att agenten bara klassificerar förfrågan, och att ett fast flöde skickar en godkänd mall eller ett formulär till kontakten som är registrerad på den order förfrågan gäller, på den nivå mallen är gjord för, till exempel köparen på en köparorder och den dugnadsansvariga på en samlingsorder, inte till avsändaren. Då har ingen del alla tre, och ett försök att lura agenten kan i värsta fall ge den registrerade kontakten ett meddelande hon inte bad om. Ett golv gäller alltid: en agent fattar aldrig på egen hand beslut om pengar, priser, avtal eller om att lämna ut personuppgifter till andra. Sådant går genom fasta regler eller en människa, och för delning av personuppgifter är de fasta reglerna utlämningsreglerna i datapolicyn. När ett svar går ut utan att en människa har skickat det visar signaturen att det kommer från Bambusas digitala assistent, likadant i alla tre länder, och en jurist bekräftar upplägget innan det första sådana svaret går ut (beslut G).

Båda skruvarna sitter på steget, inte på agenten. De skruvas upp när processägaren anser att bevisen från testfallen och utfallen håller, ner automatiskt när felen ökar, och testas igen när modellen byts. Processägaren sätter också ett tak per steg, som bevisen inte kan skruva förbi. För vissa saker är taket att det aldrig ska ske automatiskt, eftersom det gäller relationen till kunden, inte om agenten är tillräckligt bra. Exempel är att meddela den dugnadsansvariga när en deltagare anmäler ett ärende, att skicka avvikelseöversikter till dugnaden som ingen har bett om, och att kräva pengar av dugnaden.

Mallar och formulär. Det som går ut från ett fast flöde går från en mall. Det vi behöver veta från en kund eller en dugnad hämtas med ett formulär, så att svaret kommer tillbaka strukturerat. En mall säger i vilken situation den används, vem som får den och vilka fält från ärendet den hämtar, och utlämningsreglerna avgör vilka fält mottagaren får se. Mallen hämtar fälten från ärendet, inte från agentens sammanfattning, så att meddelandet aldrig säger något annat än det som är beslutat. Mallar som skickas utan en människa hämtar bara fält från källsystemen, från fasta regler eller från en människa, aldrig text som en agent har skrivit. Agentens klassificering avgör bara vilken mall som används.

Ett formulär skickas med en personlig länk i en mall och ber om exakt det som saknas i ärendet, som leveransadress, vilka varor det gäller, en bild eller önskad lösning. Svaret kopplas till ärendet genom länken, utan att någon behöver tolka det, men det är fortfarande uppgifter från någon vi inte har verifierat. En agent kan välja ett formulär där den annars skulle ha bett om uppgifterna i fritext. Mallar och formulär är kunskap med ägare och en status per språk, och det som inte är kvalitetssäkrat på språket skickas inte automatiskt.

Utan jobbkort gäller standardregler. När en anställd ber om något som inte har ett jobbkort gäller detta, tills ett jobbkort säger något annat:

läsa och söka: fritt, inom den anställdas behörighet

skapa utkast och nya filer åt den anställda: fritt, eftersom det kan ångras

ändra data i systemen eller i gemensamma dokument: den anställda bekräftar varje handling

skicka något utanför huset: den anställda skickar själv

pengar, priser, avtal och delning av personuppgifter: golvet gäller

Fullmakten följer jobbet. Ett jobb görs för en anställd eller för en roll. Ber en anställd om det, får det och dess deljobb högst den anställdas behörighet. Startar det av en händelse, får det den behörighet som jobbkortet ger rollen, oavsett vilken agent som skapade det. Det gäller också när en specialist skickar ett deljobb vidare till en annan, och koordinatorn kan bara skapa jobb av de typer som mandatet tillåter.

Det bestående är grafen av id:n och länkar. BPMN är formatet för själva flödet och kan bytas om något bättre kommer, och Processförvaltaren håller koll på det. BPMN körs inte av en processmotor som Camunda, åtminstone inte nu. Stabila flöden blir kod, och koden körs i jobbmotorn (beslut H), så att den tål fel, omstarter och långa väntetider. Agenterna används där det behövs omdöme.

7. Siffermodellen: basen för styrningen
   Siffror är en egen modell (beslut K): definitionerna och reglerna ligger i Git, siffrorna räknas i kod i siffermodellen i Connect, och alla läser samma siffror. Prototypen av KPI-verktyget visade varför. Det svåra var inte att bygga, utan att bestämma vad som är sant för Bambusa, och analyser som agenter räknade ut själva hade flera felaktiga siffror var innan de kontrollerades mot källorna.

Definitionerna och reglerna. Varje definition av en siffra anger:

vad siffran visar, och beräkningen

vilket datum den räknas på

vilka urval som är tillåtna

om siffran kan summeras; snitt och andelar räknas som summa delat med summa

enhet och valuta

vad N är, och gränsen för lågt N

vad siffran jämförs med

källor, regler, kontroller och kända luckor

ägare och dataklass

Reglerna säger vad som är sant för Bambusa, till exempel vad en klubb är, när omsättning räknas och vad en ny kund är. Varje regel har id, text, varför, status, vem som beslutade och när, från när och till när den gäller och om den gäller bakåt i tiden, och länkar till koden och testerna som bygger den. Siffrorna anger vilka regler de använder, och länkkatalogen visar den andra vägen, så att inget behöver hållas lika på två ställen.

Beräkningen. Siffermodellen läser källsystemen, klassificerar och daterar underlaget enligt reglerna och räknar de definierade siffrorna i kod. Beräkningen testas mot facit. Budgeten och andra kalkylblad, som marknadsföringsarket, läses in enligt ett fast format och med version. Budgeten ligger på samma tidsaxel som omsättningen, och agenterna hämtar inte siffror från de här kalkylbladen direkt i Drive.

Definierade siffror och egna beräkningar. Definierade siffror kommer från siffermodellen. De är lika för alla, och det är de som används i varningar, till styrelsen och i beslut. Agenten citerar dem med datum, förklaring och kvalitet: lågt N, uppskattad andel, och ”–” där data saknas, aldrig 0.

När en fråga inte täcks kan agenten räkna själv på underlaget, som är färdigt klassificerat och daterat. Den säger att det är en egen beräkning, visar hur den räknade och stämmer av mot siffermodellen där de överlappar. En egen beräkning används inte i varningar, till styrelsen eller som underlag för beslut innan den är kontrollerad, och kommer samma fråga igen föreslår förvaltarna en ny definierad siffra.

Kontrollen upprätthåller skillnaden där den betyder mest: jobb som varnar, rapporterar till styrelsen eller ger underlag för beslut får bara verktyg som läser definierade siffror. I chatten måste agenten säga till när den räknar själv, och testsviten kontrollerar att den gör det. KPI-sidorna i Connect visar siffrorna från siffermodellen och räknar inte ut dem själva, så att människor och agenter ser samma siffror.

Historiken. Systemen sparar inte den historik som siffrorna behöver: HubSpot raderar steg och har begränsad historik per fält, och order kan öppnas och slutföras på nytt. Siffermodellen har därför ett styrt lager i Connect, med ägare, dataklass och lagringstid, som ett medvetet undantag från ”länkar, inte kopior”. Sammanställda siffror utan personuppgifter är intern data, medan underlaget på ordernivå får samma dataklass som källan och tar med nycklar, inte namn. Varje månad stängs med en ögonblicksbild, och ändringar i en stängd månad loggas med regeln som förklarar dem.

Bryggan till bokföringen. Omsättningen i siffermodellen räknas medvetet annorlunda än i bokföringen: när varorna har skickats, och utan försäljning mellan bolagen i koncernen. Siffrorna kontrolleras därför mot källornas egen räkning, och det är dessa kontrollerade siffror som är facit. Mot bokföringen går en egen brygga: en avstämning per bolag varje månad, där varje avvikelse är förklarad. Innan siffrorna används i styrelsen måste bryggan täcka alla tre bolagen.

Systemkorten. För varje system finns ett systemkort i kunskapen: vad systemet äger, vad fälten betyder, vilket datum som är vilket, nycklarna och fällorna. Exempel från prototypen: HubSpot har en portal per land med olika id:n, ordernummer i WooCommerce är bara unika per butik, en dugnad kan ha flera samlingsorder, och en månad som byrån inte har fört in i marknadsföringsarket är inte 0. Fällorna upptäcks under arbetets gång och kan inte listas i förväg. Varje fälla förs in med källa och datum och får ett test som fångar den nästa gång, på samma sätt som varje fel i drift blir ett nytt testfall. Det som alltid måste gälla läggs också i koden. Dataförvaltaren håller systemkorten aktuella, och ägaren av systemet godkänner.

Drivarkedjan. För varje försäljningsström (Klubb, Grupp, B2B och DTC) beskriver siffermodellen kedjan från aktivitet via avtal och leveranser till omsättning, med uppmätt konvertering, fördröjning och säsong. Konverteringen mäts, eftersom sannolikheterna per steg i HubSpot inte stämde i Sverige och Danmark. Kedjan hör till siffermodellen, målet för varje led till Mål och varningarna till styrningsslingan. Så kan en agent säga till i god tid när mötena och avtalen i en försäljningsström inte räcker till målet.

Varningar och förslag. Innan agenterna får varna för en signal testas den på historiska siffror: skulle den ha slagit till i tid, och hur ofta fel? Varje varning har ett tröskelvärde, ett minsta N och en ägare, och avvikelsen måste bestå en tid innan den skickas. Varningarna samlas som huvudregel i ett meddelande i veckan, och förslag får förväntad effekt och ett datum för uppföljning. Agenterna styr efter täckningsbidrag, inte enbart efter omsättning, men kostnaderna som behövs är inte samlade i dag, så vi börjar med omsättning och bruttomarginal.

Enskilda personer. Siffermodellen kan visa aktivitet och försäljning per säljare, som HubSpot gör i dag. Agenterna gör ändå inga varningar eller bedömningar om enskilda anställda förrän det är utrett juridiskt. Varningarna gäller team, land och försäljningsström.

KPI-verktyget och prototypen. KPI-verktyget byggs i Connect. Prototypen är ett uppslagsverk, som BOS-arkivet, och ett facit att testa mot. Arkitekturen säger vad varje lösning måste leverera: formaten, testerna och facit. Om koden från prototypen används vidare avgörs med utvecklaren. Varje siffra har en ägare, och tills ägarna är utsedda är det Asgeir, som har bestämt reglerna i prototypen.

8. Plattformen
   En agentplattform i EU för alla agenter, med Amazon Bedrock AgentCore i Stockholm som förstakandidat. Valet (beslut C) görs med utvecklaren och testerna nedan. En plattform ger ett ställe att drifta, logga och styra för en utvecklare, och nästan alla användbara agenter berör personuppgifter förr eller senare. Datapolicyn avgör vad varje dataklass får användas till, och plattformen är densamma för alla. Vi köper det som finns färdigt och bygger där det ger en verklig fördel. Plattformen, agentloopen och modellerna köper vi. Arbetsregistret, kundärendena, identitetsgrafen, siffermodellen, kunskapen och verktygslagret bygger vi, eftersom det är där Bambusa skiljer sig från alla andra.

Behov

Amazon Bedrock AgentCore

Googles agentplattform

Claude i EU

Ja, i egen region i Stockholm eller med EU-profiler som bara går till EU-regioner

Ja, nyare modeller via eu-multiregion

Färdig agentloop

Harness, i drift sedan juni 2026 och byggd på Strands; agenten definieras som konfiguration. Agent SDK kan också köras på AgentCore Runtime

ADK på Agent Runtime

Anthropics verktyg i modell-API:et

Inga serververktyg (webbsökning, web fetch, kodkörning), ingen MCP connector eller Skills

Webbsökning och webbläsarverktyg; inte kodkörning, web fetch, MCP connector eller Skills

Plattformens egna verktyg

Kodkörning, webbläsare och webbsökning; webbsökningen ligger i Irland

Inte undersökt

Den anställdas Google, Slack och HubSpot

Inbyggd inloggning per användare, i drift; kräver inloggning med JWT (ett signerat inloggningsbevis)

Delvis; Googles API för inloggning per användare är en förhandsversion som inte blir en färdig version (GA, allmänt tillgänglig), och Agent Identity rekommenderas i stället

Regler på varje verktygsanrop

Cedar-policy med logg, i drift sedan 3 mars 2026, för anrop genom Gateway

Agent Gateway

Godkännande

Loopen pausar och ger anropet till vår kod

Inte undersökt

Googles styrka är Gemini och Workspace. Gemini är bortvalt, och för en Claude-agent är Workspace-fördelen liten, eftersom vi ändå använder Gmail-, kalender- och Drive-API:erna med en intern inloggning. Harnessen kostar ingenting i sig. Kostnaden består av modellanvändning, som är den största posten och kostar 10 procent mer i egen region eller EU än med global routing, och av Runtime per processor- och minnestimme, Gateway per anrop, Memory per händelse, Policy per kontroll och Evaluations. Siffrorna mäts i testet, och budgetramen per månad sätts före den första skivan.

En tunn adapter översätter agentkorten och jobbkorten i Git till konfiguration för harnessen. Våra verktyg är MCP-servrar, skills följer formatet Agent Skills, och spårningen går i OpenTelemetry. Då kan plattformen bytas utan att resten måste byggas om. Behöver vi en egen agentloop senare kan harnessen exporteras till Strands-kod (Python), och export till Claude Agent SDK är aviserad. Annars väljs ramverket efter språket utvecklaren använder (Mastra för TypeScript, LangGraph för Python); båda kan köras på AgentCore Runtime med Claude i EU.

Något binder vi oss ändå till. Inloggning per användare (Identity) och reglerna per verktygsanrop (Cedar) är AWS-tjänster, och det är en medveten bindning. Reglerna skrivs i jobbkort och agentkort i Git och översätts till Cedar, så att de kan tas med vidare. Cedar ser bara anrop som går genom Gateway. Därför går alla våra verktyg den vägen, skrivande handlingar är vår egen kod med godkännande och logg, och agenter som ser personuppgifter läser webben genom ett eget verktyg som upprätthåller regeln om vilka länkar som får öppnas.

Plattformsvalet avgörs med två korta tester före den första skivan, med anonymiserade eller syntetiska ärenden. Ärendena väljs från jobblistan: de jobb vi ska göra först, och de svåra ärenden som skulle avslöja ett felaktigt val. Pseudonymiserade ärenden är fortfarande personuppgifter, och DPIA är inte gjord.

Jämförelse av agentloopen. Samma 50 ärenden från jobblistan körs på AgentCore-harnessen och på Agent SDK, båda på AgentCore Runtime i Stockholm, bakom samma Gateway, verktyg och inloggning, så att bara loopen skiljer. Poängschemat görs i förväg: rätt fakta, rätt regel, språk och ton, och om agenten eskalerar när den ska. Kostnad och svarstid mäts.

EU-test. Modellen körs i egen region i Stockholm, Memory med egna inställningar och Evaluations med egna utvärderare, så att inget går via London. AWS skriver att loggarna inte visar var AgentCore-tjänsterna behandlar data, så detta kontrolleras genom uppsättningen och inte i loggarna. I Stockholm körs Runtime bara som microVM:er.

Testerna ska också visa att inloggningen från Connect ger varje anställd sin egen behörighet, att Slack ger behörighet per användare genom AgentCore, att ett bakgrundsjobb kan skapa utkast i en anställds inkorg när den anställda inte är inloggad, att varje anställds minne fungerar från ett samtal till nästa och kan visas och raderas, och att Connect självt körs i EU. Fallerar något på plattformssidan är reserven en egen loop på AgentCore Runtime eller Googles plattform. Körs Connect utanför EU måste det flyttas innan personuppgifter går genom verktygslagret.

Jobbmotorn väljs i samma omgång (beslut H). Först kontrollerar vi med utvecklaren vad Hivemind gör med jobb i dag. Förstakandidaten är Lambda durable functions i Stockholm, i samma region och konto som agentplattformen: flödena är vanlig kod, ett jobb kan vänta upp till ett år, och väntetiden kostar nästan ingenting.

Är Connect en tjänst med Postgres i EU kan DBOS göra Connect självt till motorn, så att registret och motorn delar en databas. Step Functions är ett alternativ om visuell historik räknas mest, men vi väljer en motor för alla flöden (beslut H). Temporal har det största ekosystemet, och sedan oktober 2026 finns kopplingar till Strands och AgentCore, men de viktigaste är ännu inte färdiga versioner. Temporal Cloud har ingen region i Stockholm (närmast i EU är Frankfurt och Irland), och det blir en leverantör till, med eget personuppgiftsbiträdesavtal och mer att drifta än vi behöver nu. Temporal bedöms igen när kopplingen till AgentCore är färdig.

Motorn provas på det första jobbet som väntar och har frister. Oavsett val måste varje skrivande verktyg tåla nya försök, eftersom ingen motor hindrar att ett anrop till HubSpot, Gmail eller ekonomisystemet går två gånger.

Ytorna följer arbetet. Kundtjänstmejlen kommer i dag till funktionsadresserna post@bambusa.no och kundeservice@bambusa.no, som routas till en anställd. Funktionsbrevlådorna kopplas till kundtjänstrollen, och utkasten hamnar i ärendetavlan, där kundtjänst svarar och skickar. I det första testet läses de i inkorgen hos den anställda som får dem i dag (kapitel 4). Varje anställd med kundkontakt kopplar själv sin egen inkorg till agenten, som då ser kundmejl in och ut, gör utkast och hjälper till att lämna över kundärenden, med den anställdas egen inloggning (kapitel 4). Connect är platsen för chatt och överblick, eftersom vi styr streaming och inloggning där. Godkännanden kan också ges i Slack, eller genom att den anställda skickar ett utkast. Bambusa-agenten i Slack kommer som nummer två, på samma lösning. Ett Gmail-tillägg passar bäst som enkla knappar, för svarsutkast och för överlämning till kundtjänst med en kommentar. Som chatt passar det dåligt, eftersom det bara visar kort och har en tidsgräns på 30 sekunder. En sidopanel i webbläsaren, som följer den anställda in i de webbaserade systemen, bedöms när vi ser vilka system människorna arbetar i.

Anthropics Managed Agents är utanför kärnan tills vidare. Tjänsten är i beta, och Anthropics egen plattform kan bara köra modellanrop i USA eller globalt och lagra data i USA. Med egen sandlåda körs verktygen hos oss, men modellanrop och minne går fortfarande utanför EU. Det tjänsten ger (sandlåda, nätåtkomst, långa sessioner och schemaläggning) finns i EU i AgentCore. Den bedöms igen om den kommer till EU.

9. Metoden: så bygger vi utan att bygga fel
   Tre regler styr ordningen: välj den enklaste lösningen som gör jobbet, ge läsbehörighet före skrivbehörighet, och låt autonomin växa stegvis. För Bambusa blir det åtta steg, efter några förutsättningar.

Vi börjar i liten skala. Asgeir och en eller två anställda testar först, och ingen annan får tillgång ännu. Testet kan börja med syntetiska eller anonymiserade ärenden. Innan riktiga kunduppgifter går genom agenterna, även i skuggläge eller i ett test i den egna inkorgen, måste datapolicyn vara fastställd, en kort DPIA för den första skivan gjord och personuppgiftsbiträdesavtalet med plattformsleverantören på plats. Den grundliga DPIA:n görs när vi har erfarenhet av driften och senast innan en agent får skicka själv eller använda nya dataklasser. Innan fler anställda tas med diskuteras upplägget med dem. Allt arbete sker på Bambusas egna konton, inte på privata abonnemang. Arkitekturen, principerna och metoden ligger i Git före den första skivan, och jobbet i skivan har en namngiven ägare, Asgeir tills vidare (G-09).

Det gamla som uppslagsverk. Vi börjar rent i miljön som byggs för drift, och arkitekturen styr. Det gamla BOS-projektet fryses och kopieras in som ett arkiv, BOS-arkivet, märkt som inte gällande. Prototypen av KPI-verktyget (repot bambusa-kpi-tool) behandlas på samma sätt: reglerna, definitionerna och testerna tas in enligt metoden nedan, och siffrorna som den har kontrollerat mot källornas egen räkning blir facit. Från startdagen läggs ny kunskap bara in i det nya, så att vi inte får två ställen som båda lever. Agenterna kan slå upp i arkivet men följer det inte. Inget därifrån gäller förrän det är kontrollerat mot arkitekturen och godkänt, inte heller gamla regler, beslut eller fakta om Bambusa. Detta är förvaltarnas jobb: Kunskapsförvaltaren för kunskapen och Processförvaltaren för processerna. Tills förvaltarna finns som egna agenter gör Asgeir deras uppgifter med hjälp av Bambusa-agenten. Så tas något in:

Källan till sanning först. Det första vi tar in är översikten över var varje typ av data ska finnas (ett system, Git eller Drive) och vem som äger den. Fakta som finns i ett system länkas och kopieras inte.

Agenten föreslår, ägaren godkänner. När vi behöver något slår agenten upp i arkivet och svarar: ta in det som det är, ta in det med dessa ändringar, ta inte in det, eller osäker. Den visar alltid vad den har kontrollerat, och mot vad, eftersom ett ”det här ser bra ut” kan vara fel. Ägaren går in i detaljerna när agenten är osäker, eller när ägaren själv vill.

Noggrannheten följer risken. Ett faktum som agenten har kontrollerat mot systemet som äger det behöver bara ett snabbt ja. En regel eller ett steg som agenterna ska agera efter går ägaren igenom. Pengar, priser, avtal, personuppgifter och juridiska frågor gås alltid igenom fullt ut.

Innehåll och format hålls isär. Kunskapen om hur digital dugnad går till håller troligen, medan fälten i BPMN och var kartan lagras kan behöva ändras efter den nya arkitekturen. Agenten tar in innehållet och bygger det i det nya formatet.

Yttre ramar bekräftas, de beslutas inte på nytt. Vissa gamla beslut vilar på lag eller avtal, som momsstrukturen mellan bolagen eller avtal med kunder och leverantörer. De kontrolleras mot källan och tas in, men öppnas inte för nya val.

Intagsloggen. För varje sak står det vad agenten rekommenderade, vem som godkände och när, och var det finns nu. Då är det alltid tydligt vad som har tagits in.

Kunskapsarbetet kan börja så snart Git-repot och företagskontot finns, innan agentplattformen är byggd.

Kort jobblista. Asgeir skriver ner rollerna, händelserna som startar arbete och de viktigaste jobben, utifrån vad han vet. De anställda får några få frågor via mejl om vad de tar emot och lägger mest tid på. För varje jobb noterar vi systemen, dataklasserna och om handlingarna kan ångras. Listan ska vara tillräckligt bra för att välja den första skivan och bestämma vilka ärenden plattformstesterna ska använda, så att vi inte väljer fel. Vi tidsmäter inte ärendena. Volymerna per land (G-15), AI-kunskaperna per roll (G-22) och vilka system människorna arbetar i fylls i under arbetets gång, med intervjuer medan vi utvecklar.

Formaten först. Nycklarna för enheterna i beslut D, med rollerna i en kampanj, och formaten för ärendeförlopp, jobb, kundärende, jobbkort, agentkort, överlämningskort, godkännande, verktyg, mallar och formulär, kunskaps-id:n och logg, skrivs före koden, så långt den första skivan behöver dem. De versionshanteras, så att de kan ändras senare utan att något går sönder. Alla skrivande verktyg byggs så att ett nytt försök inte gör handlingen två gånger, med en nyckel som skapas av vad som görs och varför, inte av tidpunkten.

En genomgående skiva. Jobblistan avgör vilket jobb, och skivan testas först av Asgeir och en eller två anställda. Kandidaterna är två. Den ena är kundtjänst: svar på mejl om betalning, leveransavvikelser och inloggning i digital dugnad i Norge, tillsammans med sorteringen av inkorgen, med kundtjänstassistenten som redan är byggd i Claude som utgångspunkt. Den andra är daglig uppföljning av dugnader i Klubb-CS. De tre jobben i kundtjänst använder samma uppslag i App Admin, så åtkomsten dit klargörs först (kapitel 11). Väljs uppföljningen av dugnader kommer koordinatorn, kundärendet och ärendetavlan med nästa jobb. Det assistenten har lärt sig om svar och regler tas med, och assistenten avvecklas när jobbet i kundtjänst är i drift i Connect och Slack, så att vi inte får två spår. Assistenten heter själv Saksbordet, men den är inte samma sak som ärendetavlan i Connect (saksbordet på norska). Väljs kundtjänst skapar agenten utkast i en enkel version av ärendetavlan, där de anställda rättar och skickar. Skivan byggs tunt genom alla lager: händelse, jobb, agent, kunskap, identitet, verktyg, yta, logg och testfall. Innan vi bygger arbetsregistret och identitetsgrafen kontrollerar vi vad HubSpot och Connect redan gör med ärenden och kundmatchning. Skivan får en fast tidsram, och det som förenklas skrivs ner. Den körs först i skuggläge, där agenten skapar utkast som ingen ser och vi jämför med vad människorna faktiskt gjorde. Utkasten tas i bruk efter en mognadskontroll, med kontrollen i BOS-arkivet (D-024) som utgångspunkt.

Testsvit från riktiga ärenden. 50 till 100 gamla ärenden per jobb, med facit från dem som gör jobbet bäst. I kundtjänst är ärendena i kundtjänstassistenten utgångspunkten: många har ett godkännande från en människa, och utkasten ligger bredvid det som faktiskt skickades. De används när datapolicyn, den korta DPIA:n och personuppgiftsbiträdesavtalet är på plats, eller anonymiserade. Sviten ska också ha svåra ärenden, som byte utan ordernummer eller fel sponsorbelopp, där facit ofta är att agenten ska fråga en människa och ge rätt sammanhang. Varje release måste klara sviten, och varje fel som når produktion blir ett nytt testfall. I jobb med hög risk kontrolleras arbetet mot fasta regler och mot systemen, som rätt order, rätt mottagare och rätt belopp, innan en människa ser det. En agent som bara bedömer en annan agents arbete delar ofta samma blinda fläckar.

Veckovisa releaser genom manifestet, med logg över vad som ändrats och möjlighet att rulla tillbaka. En godkänd rättelse i kunskapen kan gå ut genom manifestet före nästa release när den klarar testsviten, så att de anställda ser att agenten lär sig.

Utöka jobb för jobb. De två nästa jobben hämtas från andra delar av företaget, till exempel mötesförberedelse i försäljning och veckorapport i marknadsföring, så att lagren prövas brett innan vi skalar upp. Kärnan byggs med den första skivan: arbetsregistret med jobbmotorn, identitetsnycklarna, verktygslagret och kontrollen. Koordinatorn, kundärendet och ärendetavlan byggs med det första jobbet som svarar på kundförfrågningar, och delen om varor och pengar med det första jobbet som behöver den. Siffermodellen byggs i ett eget spår. Andra gemensamma komponenter byggs först när tre jobb behöver dem.

Autonomi efter bevis. För varje jobb kommer processägaren i förväg överens om vad som krävs för nästa nivå, till exempel att agenten klassificerar rätt i en överenskommen andel av ärendena, över ett visst antal ärenden utan allvarliga fel, innan ett fast flöde får skicka mallen själv. Kundsvar som agenten skriver själv skickas alltid av en människa (beslut G). Nivån sänks automatiskt om felen ökar. Godkännanden samlas i omgångar, och mängden anpassas så att människorna faktiskt bedömer det de godkänner. Ett godkännande som ingen läser är autonomi med extra steg (D-024).

Utbildning och ägarskap från dag ett. En superanvändare per team, en kort utbildning per roll, en flaggknapp i varje yta (G-20) och mätning av användning per roll. Bambusa-agenten ska vara platsen där människorna använder AI i jobbet. Annars slutar det med många privata AI-verktyg vid sidan av, vilket källorna varnar för.

När vi bygger något nytt och stort, som KPI-verktyget, använder vi de delar vi har: en ägare och ett jobbkort för bygget, kunskapen i Git som specifikation, syntetiska eller tvättade data tills DPIA:n täcker det, acceptanstester med facit, revisorns kontroll innan det tas i bruk och utrullning genom manifestet. Koden i Connect byggs av utvecklaren med kodagenter, och agenterna som gör det dagliga arbetet ändrar den inte. Är kunskapen tillräckligt bra behöver byggarna ställa få frågor, och de som kommer ställs på överlämningskortet och blir regler där de används.

Så här ser den första versionen av varje byggsten ut, som vi ser det nu. Tabellen ändras när vi lär oss på vägen, och en byggsten byggs först när ett jobb behöver den:

Byggsten

Första versionen

Senare

Arbetsregistret

Ärendeförlopp och jobb för den första jobbtypen, med tillstånden in, redo, i arbete, väntar och klart

Fler jobbtyper, och överblick per jobb och roll i Connect

Kundärendet

Ärendetavlan i en enkel version med det första jobbet som svarar på kundförfrågningar: ärenden från funktionsadresserna, nya och egna ärenden med det brådskande överst, utkast som visar vad de bygger på, svar och utskick. Delen om varor och pengar kommer med det första jobbet som behöver den

Alla ärendetyper i alla försäljningsströmmar, överlämning från alla anställda och fördelning mellan flera i kundtjänst

Jobbmotorn

Ett flöde med väntan, frister och eskalering

Alla fasta flöden, även exportflödet

Vakterna

Den fasta vakten för jobb som står stilla, och de vakter som det första jobbet behöver, i skuggläge först

Nya vakter som jobbkort när ett jobb behöver dem, även på nya system

Koordinatorn

Sorterar alla mejl till funktionsadresserna, även skräpposten, markerar det som är brådskande och skapar jobben för det första mejljobbet

Prioriterar tvärs över, följer upp jobb som har fastnat och planerar

Bambusa-agenten

Asgeir och en eller två testare: chatt i Connect, och utkast i egen inkorg för mejl som inte går genom ärendetavlan

Alla anställda, Slack och kanske en sidopanel

Minnet

Samtalet och det personliga minnet för Asgeir och testarna, som de kan se och radera

Alla anställda

Specialisterna

Kundagenten med ett jobbkort

Fler jobbkort, och nya specialister när behörigheterna kräver det

Verktygslagret

Verktygen som det första jobbet behöver, och ”Vem är detta?” som sökning

Fler system, och sparade kopplingar i identitetsgrafen

Siffermodellen

Eget spår: reglerna, definitionerna och testerna från prototypen intagna, och de viktigaste siffrorna för dugnad räknade i Connect och kontrollerade mot facit

Drivarkedjor, varningar och bryggan till bokföringen i alla tre bolagen

Kontrollen

Behörighet, standardregler, logg, kostnadstak och stoppknapp

Mer autonomi per jobb efter bevis, och revisorn och regelverksrollen när siffrorna tas i bruk

Lärandet

Kunskapsförvaltaren sammanfattar varje vecka vad de anställda rättar i utkasten. Regler som de anställda säger till om blir förslag direkt. De andra förvaltarnas uppgifter gör Asgeir med Bambusa-agenten

Verktygsförvaltaren och Processförvaltaren som egna agenter, och Dataförvaltaren när siffrorna tas i bruk

Kunskapen

BPMN, regler och exempel för det första flödet, intagna från uppslagsverket och godkända

Fler flöden allteftersom jobben kommer

Ytorna

Ärendetavlan för kundtjänst, utkast i Gmail för andra, chatt i Connect och formulär med personlig länk när ett jobb behöver dem

Slack, en knapp i Gmail för överlämning och så småningom kundvända ytor

När en agent gör fel mot en kund. Jobbet stoppas med stoppknappen, och processägaren och den som ansvarar för dataskyddet underrättas. En människa kontaktar kunden. Felet rättas i källsystemet, orsaken hittas, och felet blir ett nytt testfall innan jobbet startar igen. Autonomin för jobbet bedöms på nytt. Har personuppgifter gått till fel mottagare bedöms det som en möjlig personuppgiftsincident. Den måste anmälas till tillsynsmyndigheten inom 72 timmar, om det inte är osannolikt att den medför en risk för dem det gäller.

Vad som kan få oss att bygga fel, och skyddet mot det:

Felriktning

Vad som händer

Skydd

Agenter före arbetsmodellen

Chattar som inte kan lämnas över, mätas eller få autonomi

Arbetsregistret från den första skivan

Integrationer per agent

Många halva kopplingar som måste byggas om

Ett verktygslager som alla agenter delar

Agenter som minns affärsdata

Dold och inaktuell sanning

Länkar, inte kopior; lärande blir kunskap

Agenter som glömmer

Folk måste förklara allt på nytt och slutar använda dem

Personligt minne, och sammanhanget följer jobbet och ärendet

Agenter som räknar siffrorna själva

Siffror som ser rätt ut men är fel, i varningar och till styrelsen

Definierade siffror från siffermodellen; egna beräkningar märks och kontrolleras

Automatisering av arbete som inte är mätt

Ingen vet om det hjälper

Jobblistan, och mätning i arbetsregistret från det första jobbet

Inlåsning i en leverantörs format

Ombyggnad när plattformarna byts

Öppna standarder och våra egna format

Väntan på perfekta data (G-18)

Vi kommer aldrig igång

”Vem är detta?” som verktyg från dag ett, med bättre implementation bakom efter hand

Glömma människorna

Ingen använder det

Agenter som kommer till arbetet, en ärendetavla som är snabbare än inkorgen, superanvändare och mätning av användning

För mycket styrning för tidigt

Tröghet och omvägar

Styrning per jobb, som skärps med autonomin

Allt vilar på en utvecklare (A-007)

Långsamma framsteg, genvägar och en ny sårbarhet

Köp plattformen, håll skivorna tunna, använd Claude Code i utvecklingen, lägg ut avgränsade delar och håll formaten i Git så att andra kan ta över

Fyra grindar håller riktningen: efter den första skivan (ja eller nej till plattform och lager), när KPI-verktyget är byggt (siffrorna från Connect, byggda utifrån kunskapen, stämmer med facit för samma månader, och varje avvikelse är förklarad), efter tre jobb (plan för att skala upp) och varje kvartal (arkitekturgenomgång med underlag från förvaltarna).

10. Besluten
    Fjorton beslut. Tolv är fattade. L och M fattades den 24 oktober 2026, då G också utvidgades och D fick med ordernivåerna och rollerna. Den 25 oktober utvidgades L med ärendetavlan och kundkontakt i alla kanaler och H med vakter, och N om minnet fattades. C, D och valet av motor i H avgörs med utvecklaren innan den första skivan byggs:

Beslut

Status

A

Arkitekturen byggs kring arbetet, med modellerna i kapitel 3 som fundament (Siffror tillkom med beslut K)

Beslutat

B

En kort jobblista är det första steget: roller, händelser och de viktigaste jobben, från Asgeir och några få frågor till de anställda. Den avgör den första skivan och vilka ärenden plattformstesterna använder, och kunskapen byggs vidare under arbetets gång

Beslutat i ändrad form

C

En gemensam agentplattform i EU för alla agenter, med AgentCore i Stockholm som förstakandidat. Agentloopen väljs med ett test: AgentCore-harnessen mot Agent SDK på samma plattform. Datapolicyn avgör vad varje dataklass får användas till, inte vilken plattform

Väntar på utvecklaren och testerna

D

Connect äger nycklarna och kopplingarna mellan systemen för klubbar och andra organisationer som har dugnader, dugnaderna (kampanjer i appen), grupperna i dugnaderna, kontaktpersoner, deltagare, köpare, B2B-kunder, DTC-kunder, order på alla nivåer, kollin, försändelser och fakturor, och ger var och en av dem en stabil nyckel som inte är e-postadressen. Ordet kund används som samlingsord för den som ärendet gäller. Ordrarna har två axlar, den fysiska (deltagarorder, kolli och försändelse) och den ekonomiska (köparorder, samlingsorder och faktura). Roller är kopplingar i en kampanj, inte egenskaper hos personen, även vårdnadshavare och vem som anmäler för någon annans räkning, och en påstådd roll bekräftas mot registrerade kontaktuppgifter. Nycklarna från källorna tar med källa och land. Vem som är master för personuppgifter, och hur radering går till, avgörs separat

Väntar på utvecklaren

E

Kunskapen ordnas i lager (mål och policyer, processer och regler, tillvägagångssätt och exempel), och Processförvaltaren tar fram och underhåller metoden, medan Asgeir äger den och godkänner ändringar

Beslutat

F

Arbetsregistret håller jobben för agenter och människor, samlade i ärendeförlopp, med godkännanden och utfall, och länkar till det som jobbet gäller. Statusen på det som jobbet gäller ägs av systemet där det finns, även för kundärendet i Connect, och mätningarna visas per jobb och roll, inte per anställd

Beslutat

G

Processägaren avgör per process vad som blir automatiskt, inom ett tak per steg som bevis inte kan skruva förbi. Fasta meddelanden och formulär skickas från mallar, av ett fast flöde eller av en anställd från ärendet. Kundsvar som agenten skriver själv skickas av en människa. Automatiska svar är mallar eller formulär som ett fast flöde skickar till kontakten som är registrerad på ordern, efter att agenten har klassificerat förfrågan. Golvet: en agent fattar aldrig på egen hand beslut om pengar, priser, avtal eller delning av personuppgifter, och delningen styrs av utlämningsregler i datapolicyn. Svar som går ut utan en människa signeras som från Bambusas digitala assistent i alla tre länder, efter juridisk kontroll. Utan jobbkort gäller standardregler: läsa och skapa utkast fritt, ändringar bekräftas av den anställda, och den anställda skickar själv

Beslutat, utvidgat den 24 oktober 2026

H

Jobb med flera steg eller väntetid körs i en gemensam, beständig jobbmotor som tål fel, omstarter och godkännanden som tar dagar. Inget jobb väntar utan frist, och jobbkortet säger vad som händer när fristen går ut. Fasta flöden, vakter som går enligt ett schema, och agentsteg går i samma motor, och registret och motorn delar sanning. Motorn väljs med utvecklaren, med Lambda durable functions i Stockholm som förstakandidat

Beslutat, utvidgat den 25 oktober 2026; valet av motor väntar på utvecklaren

I

En koordinator tar emot det som måste läsas innan det kan fördelas, som mejl, från det första jobbet som behöver det. Den tar reda på vad ärendet gäller och vem det kommer från, skapar rätt jobb och kundärenden, kopplar nya meddelanden till öppna ärenden, stänger reklam med en motivering och skickar det oklara till en människa. Den kan inte skicka ut något eller ändra något hos kunden, och mandatet utökas efter bevis

Beslutat

J

Vi börjar rent i miljön som byggs för drift, på Bambusas egna konton, och arkitekturen styr. Det gamla BOS-projektet fryses och blir ett uppslagsverk, BOS-arkivet, och innehåll därifrån tas in först efter att det har kontrollerats mot arkitekturen och godkänts

Beslutat

K

Siffror är en egen modell. Definitionerna och reglerna ligger i Git, och siffrorna räknas i kod i siffermodellen i Connect, från källsystemen, med historik och en brygga till bokföringen. Agenterna citerar definierade siffror och säger till när de räknar själva, och jobb som varnar, rapporterar till styrelsen eller ger underlag för beslut får bara definierade siffror. En dataförvaltare, en revisor och en regelverksroll kommer när siffrorna tas i bruk. Agenterna gör inga varningar eller bedömningar om enskilda anställda förrän det är utrett juridiskt

Beslutat

L

Kundärendet är ett eget område i Connect, skilt från arbetsregistret. Ärendet följer kunden, inte brevlådan: det kunden behöver få löst eller levererat hör hemma i ett ärende, oavsett vilken inkorg det kom till, med meddelandena, vem som har det, nästa steg och det som beslutas om varor och pengar, per paket. Varje anställd med kundkontakt kopplar sin inkorg till sin egen agent, och funktionsadresserna kopplas till kundtjänstrollen. Ärendetavlan visar alla kundärenden och är kundtjänstens arbetsplats. Andra anställda lämnar över med en etikett i Gmail, ett förslag från agenten eller vidarebefordran, och bestämmer själva vad som skickas. Uppstart, uppföljning och försäljning hör hemma i HubSpot. Anställda och agenter använder kundärendet genom verktygslagret med samma regler

Beslutat, utvidgat den 25 oktober 2026

M

Handlingar som flyttar pengar eller varor går genom ett kommando per handling, som anställda och agenter använder likadant. Nyckeln som hindrar att något görs två gånger skapas av vad som görs och varför, och handlingar som görs direkt i systemen kopplas till kundärendet. Ett godkännande sparar förutsättningarna och konsekvensen det gavs på, och krävs på nytt om de ändras före utförandet

Beslutat

N

Agenterna minns i fem lager: samtalet, den anställdas eget minne, jobben och ärendena, kunskapen i Git och källsystemen. Fakta om verksamheten hämtas från källan, och minnet håller sammanhanget och länkarna. Den anställdas minne är den anställdas eget och kan visas, rättas och raderas, kunduppgifter sparas i ärendet, och det som gäller alla går till ägaren. Koordinatorn och specialisterna har inget eget minne mellan jobben; det de behöver följer jobbet

Beslutat

Besluten förs in i beslutsloggen i Git när miljön är uppsatt. BOS-arkivet har fått en slutanteckning om att det är fryst, och att den här arkitekturen styr.

11. Nästa steg
    Nästa steg är jobblistan och ett samtal med utvecklaren. Samtidigt sätts Git-repot och ett företagskonto upp, så att kunskapsarbetet och intaget från uppslagsverket kan börja innan agentplattformen är byggd. Jobblistan avgör den första skivan och vilka ärenden plattformstesterna använder. Samtalet avgör D och var i Connect siffermodellen och kundärendena ska finnas. Därefter körs de två plattformstesterna i kapitel 8 med anonymiserade eller syntetiska ärenden, och tillsammans med samtalet avgör de C och valet av jobbmotor. Testerna och en kort genomgång av vad HubSpot och Connect redan gör med ärenden och kundmatchning visar hur mycket vi måste bygga själva. KPI-verktyget är ett eget spår: när Git-repot finns tas reglerna och definitionerna från prototypen in tidigt, direkt efter översikten över var data ska finnas, eftersom de är det mest mogna vi har, och verktyget byggs i Connect mot facit.

Frågor till utvecklaren. Svaren avgör D och var i Connect siffermodellen och kundärendena ska finnas, och tillsammans med testerna avgör de C och valet av jobbmotor:

Connect: vilket språk, ramverk och vilken databas det använder, och var det körs. Körs allt i EU?

Hivemind: vad det gör i dag, hur det kör jobb och fasta flöden som exportflödet, och vilka körningar som går enligt ett schema, som hämtningen från nShift.

Kunder och order: vad Connect redan gör med kundmatchning, var apporderna, deltagarna och rollerna finns, även vårdnadshavare, mottagaren av samlingsleveransen och kontoinnehavaren, om en kampanj kan ha flera dugnadsansvariga, och om nycklarna kan ta med källa och land. Ordernummer är bara unika per webbutik, HubSpot-id:n bara per portal, och en dugnad kan ha flera samlingsorder. I dugnad hänger ordrarna ihop på två axlar, den fysiska (deltagarorder, kolli och försändelse) och den ekonomiska (köparorder, samlingsorder och faktura). Var finns kopplingarna mellan dem i dag? Över hälften av förfrågningarna till kundtjänst behöver uppslag i App Admin (kapitel 2): kan agenterna läsa det de behöver genom Connect, eller behöver vi ett API från Last Friday, som sköter driften av appen?

Kundärendet: var i Connect det kan finnas, bredvid arbetsregistret, hur Connect kan läsa allt i funktionsbrevlådorna, även skräpposten, och skicka från dem, hur agenterna kan se etiketter och kundmejl i de anställdas inkorgar och fånga upp svar som skickats från Gmail, hur ärendetavlan kan fungera bra i mobilen, och hur ärendet kan använda kommandona för order (beslut M), till exempel genom ordermodulen som är planerad i Connect, när något ska skickas ut.

Händelser: vilka system som själva kan skicka besked när något händer, som Ongoing, PostNord, webbutikerna, Centra, appen, HubSpot, Slack och Phonero, och vad Connect redan hämtar.

Inloggning: om Connect kan föra vidare varje anställds egen inloggning till agenterna, och om ett bakgrundsjobb kan skapa utkast i en anställds inkorg.

Jobbmotorn: vad som passar bäst med Connect, Lambda durable functions, DBOS eller något annat, och om registret och motorn kan dela databas.

Siffermodellen: var i Connect siffermodellen och historiken kan finnas, hur beräkningarna kan köras varje natt, och hur Connect räknar omsättning per försäljningsström i dag. Prototypen är byggd i Python och DuckDB, med SQL-filer, ett register i YAML och runt 300 tester. Arkitekturen kräver bara formaten, testerna och facit, så om koden används vidare avgör vi tillsammans.

AWS: om vi har konto och erfarenhet där i dag.

Tid: hur mycket tid som kan avsättas för detta, och vilka delar som bör läggas ut.

Andra svar som saknas:

hur många deltagare som är under 18, per land, och en juridisk bedömning av vem som ska få meddelanden när deltagaren är minderårig

en budgetram per månad för modellanvändning och plattform

en juridisk bedömning av om AB och ApS är egna personuppgiftsansvariga, vilket troligen kräver ett personuppgiftsbiträdesavtal inom koncernen

vad personuppgiftsbiträdesavtalen med kunderna säger om nya underbiträden, och om kunderna måste informeras innan plattformen tas i bruk

en juridisk bedömning av om agenterna får göra varningar och bedömningar om enskilda anställda

en juridisk bedömning av att agenterna läser kundmejl i de anställdas egna inkorgar och har ett personligt minne per anställd, enligt reglerna om arbetsgivarens insyn i e-post, innan fler än testarna tas med

avstämning mot bokföringen i Sverige och Danmark; i dag är bara Norge avstämt

vem som skickar påminnelser om obetalda fakturor i dag, från vilket system och i vilket land

kostnaderna som behövs för täckningsbidrag per försäljningsström

var personalköp och gratisvaror ska registreras, och vem som äger dem. Det är två olika saker, men de förs i dag i samma kalkylblad. Gratisvaror, som varuprover, går både till B2B-kunder och till dugnader och måste kunna skiljas åt efter mottagare.

vem som äger återkopplingen om varorna, som i dag förs i kalkylbladet ”Bambusa Artikkel Feedback” och ska markeras i kundärendet (se Minnet)

Källor
Ramverk och rapporter:

Anthropic: The 2026 State of AI Agents Report (läst i PDF-versionen)

Anthropic: Building effective human-agent teams

Orchestra: AI Agent Architecture & Design Patterns

StackAI: The 2026 Guide to Agentic Workflow Architectures

OpenAI: Building agents

OpenAI: Agent Builder

OpenAI: Changelog

Arize: What Are AI Agents?

Mastra: AI Agent Architecture

LangGraph

Anthropic: Building Effective AI Agents

Plattform, ytor och regelverk, kontrollerat den 20 oktober 2026:

AgentCore harness är i drift

AgentCore harness: verktyg och godkännande

AgentCore: tjänster per region

AgentCore Identity: Google, Slack och HubSpot

Policy i AgentCore

Claude Sonnet 5.5 på Bedrock, med EU-profil

Claude på Vertex AI

Google: inloggning per användare för agenter (förhandsversion)

Gmail-tillägg: begränsningar

Slack: agenter

Slack: realtidssökning

AI-förordningen, förordning (EU) 2024/1689: artikel 50 och bilaga III

Mer om plattform och regelverk, kontrollerat den 20 och 21 oktober 2026:

Anthropic: Claude i Amazon Bedrock

Anthropic: datalagring och inferensgeografi

AgentCore harness

AgentCore: inferens över regioner

Policy i AgentCore är i drift (AWS, 3 mars 2026)

Gmail-tillägg: tidsgräns för anrop

AI Omnibus och artikel 50 (iubenda, 10 juli 2026)

KI-loven: AI-förordningen i Norge (Opsio)

Temporal: Temporal and AWS (13 oktober 2026)

Temporal Cloud: regioner

AgentCore harness: minne och filer mellan sessioner

AgentCore Runtime: livslängd för sessioner
