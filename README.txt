REALITY: FELONY — WEB RPG BUILD 0.5
==================================

FILES
-----
index.html                 The self-contained browser game (logo / coin art embedded).
SUPABASE_SETUP.sql         Tables, profile trigger, RLS policies, and co-op rooms.
README_REALITY_FELONY_BUILD_05.txt  This guide.

OFFLINE / LOCAL PLAY
--------------------
1. Open index.html in a modern browser, or deploy it to GitHub Pages.
2. On first entry, the device receives 300 Gilt Shards once, then choose:
   - RANDOM: generate and save an ID immediately. It is locked against editing until
     the player spends 1,300 Gilt Shards to unlock it.
   - DESIGN NOW: open Create ID and press SAVE TO ID when finished.
3. Local wallet and ID data are saved in localStorage on that browser/device.

SUPABASE AUTH + CLOUD SAVE + LEADERBOARD + CO-OP
------------------------------------------------
1. Create a Supabase project.
2. In Supabase Dashboard > SQL Editor, run all of SUPABASE_SETUP.sql.
3. In Project Settings > API, copy the Project URL and the public anon/publishable key.
   Do NOT use a service_role/secret key in the public website.
4. Deploy index.html over HTTPS, open the game, press ACCOUNT / SIGN IN, paste the URL and
   public key, press CONNECT, then create an account or sign in.
5. Email confirmation may be enabled in Supabase Auth. If enabled, confirm the address
   before signing in.
6. Once signed in, the game downloads profile and saved IDs; changes are synchronized to
   rf_profiles and rf_player_ids. The public Top 50 leaderboard is ordered by Gilt Shards,
   with deepest Dungeon floor as a tie-breaker.
7. For Co-op PvE, both players need accounts. One creates a room and shares the room code;
   the second joins. The clients synchronize shared boss HP/logs by polling the Supabase row. Joining an existing room goes through a database function so a guest cannot take over the host slot.

DUNGEON RULES IN THIS BUILD
---------------------------
- 99 sequential floors; each next boss is generated with randomized name, attack type,
  Coin count, effects, stagger threshold and a randomized x2 / x1 / x0.5 resistance set.
- Boss HP and strength scale from the selected ID and floor depth.
- Voluntary exit pays 45 Gilt Shards per cleared floor.
- Defeat pays 45 Gilt Shards per cleared floor and deducts 35% of the wallet balance.
- Clearing floor 99 settles the entire run without the defeat penalty.

10 ADDITIONAL STATUS EFFECTS
----------------------------
Helpful: Tái Tạo (regen), Hộ Thể (ward), Tập Trung (focus), Cuồng Nộ (fury),
Nhanh Nhẹn (haste).
Harmful: Suy Yếu (weaken), Dễ Vỡ (fragile), Trói Buộc (bind), Ăn Mòn (corrode),
Đánh Dấu (mark).
These can be assigned to the trait or Skill 1–3; Skill 4 defense does not accept effects.

IMPORTANT LIMITATIONS
---------------------
- Supabase cannot connect until you enter your own Project URL/key and run the SQL file.
- Internet access is needed for Supabase JS/Auth/cloud functions. Local combat and storage remain
  available if the CDN or backend is unavailable.
- Co-op is a prototype. It uses browser-side damage calculation and polling; it is not a
  server-authoritative competitive game. The SQL policies isolate each user's ID records, but
  Gilt Shards are still client-updatable and therefore not cheat-proof.
- This is a static HTML prototype, not a production MMO backend. Test with two real accounts
  and two browser sessions before public promotion.
