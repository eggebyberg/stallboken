# Stallboken Eggebyberg

Bokningstavla för stallet: boka hästar, bocka av sysslor och fodring, gemensam anteckningsbok och gruppchatt med foton. Bara inbjudna ryttare kan logga in.

- **Appen:** `index.html` (publiceras med GitHub Pages)
- **Databas och inloggning:** Supabase
- **Inbjudningar:** Supabase Edge Function `invite`

## Filer

| Fil | Vad den gör |
|---|---|
| `index.html` | Hela appen i en fil |
| `supabase/01_databas.sql` | Skapar tabeller, säkerhetsregler och fotolagring |
| `supabase/02_gor_mig_till_admin.sql` | Gör ditt konto till admin |
| `supabase/functions/invite/index.ts` | Skickar inbjudningar och tar bort ryttare (bara admin) |

## Uppsättning

1. **Databasen:** kör `01_databas.sql` i Supabase → SQL Editor.
2. **Inbjudningsfunktionen:** Supabase → Edge Functions → Deploy a new function → Via Editor. Döp den till `invite`, klistra in `index.ts` och tryck Deploy. Öppna funktionen → Details och stäng av **Verify JWT with legacy secret** (funktionen kontrollerar själv att anroparen är admin).
3. **Inloggningsadresser:** Authentication → URL Configuration
   - Site URL: `https://ORGANISATION.github.io/stallboken/`
   - Redirect URLs: lägg till samma adress
4. **Bara inbjudna:** Authentication → Sign In / Providers → stäng av **Allow new users to sign up**.
5. **E-post:** Authentication → Emails → SMTP Settings → slå på Custom SMTP (Gmail: host `smtp.gmail.com`, port `465`, användare = Gmail-adressen, lösenord = applösenordet).
6. **Ditt eget konto:** Authentication → Users → Add user → Create new user (e-post + lösenord, bocka i Auto Confirm). Kör sedan `02_gor_mig_till_admin.sql` med din e-post.
7. **Publicera:** GitHub → repot → Settings → Pages → Deploy from a branch → `main` / `(root)`.

## Säkerhet

Den publika nyckeln i `index.html` får synas. Allt skydd sitter i databasens regler: utan inloggning kommer man inte åt något. Den hemliga nyckeln (`service_role`/`secret`) ska aldrig läggas i koden.
