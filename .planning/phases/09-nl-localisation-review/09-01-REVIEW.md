# Phase 9 NL Localisation Review — Side-by-Side Sign-Off Document

**Generated:** 2026-06-21  **Status:** Human sign-off COMPLETE — 2026-06-21 (jnuyens, native Flemish/Dutch)

**Reviewer corrections applied (09-02):**
- `ui.ftue.night_hint`: "Tijd om te slapen. Loop naar het bed." → "Slapenstijd! Loop naar het bed."
- `ui.bed.too_early_prompt`: "Slapen is voor 's nachts" → "Overdag slapen we niet."
- All other sections approved as-is.

---

## Instructions for Reviewer

You are a native Flemish/Dutch speaker reviewing these translations.
For each section: read the EN string, check the NL translation, and note any changes.
Mark issues with `[CHANGE: new text]` or `[OK]` inline.

Register: informal (je/jij), kid-friendly, Flemish-first where a neutral exists.
Terminology: brick = "brick" (keep), stud = "stud" (keep), builder = "bouwer".

---

## Summary of AI Changes Applied

### Changes to locale/nl.po

1. **Header comment corrected** — was: `nop = stud` (wrong). Now: `stud = 'stud' (brand term, keep untranslated)` per D-03.
2. **ui.signin.age_checkbox filled** — was empty, now: "Ik ben 13 jaar of ouder." (informal register, D-02).
3. **ui.hud.mode.sandbox corrected** — was: "Creatief". Now: "Sandbox" (the game mode is literally called Sandbox; "Creatief" was ambiguous with world-select mode_creative label).
4. **44 missing bricks.* entries added** — axe, hammer, fishing_rod, compass, map, gold_ingot, coal, leather, string, wheat, sugar_cane, obsidian, furnace, bucket, sugar, bread, campfire, coal_block, bow, flint_and_steel, chestplate_iron, chestplate_leather, helmet_diamond, helmet_gold, nether_portal, raw_meat, sashimi, crafting_table_advanced, painting_small_1, painting_small_2, flower_pot, pot_red_flower, pot_blue_flower, pot_yellow_flower, pot_white_flower, pot_pink_flower, well, barrel, bookshelf, crate, chair_wood, anvil, table_wood.
5. **24 missing recipes.* entries added** — pickaxe_stone, pickaxe_iron, pickaxe_diamond, pickaxe_gold, shovel_stone, shovel_iron, shovel_diamond, shovel_gold, sword_diamond, stone_block, glass_block, furnace, bucket, bread, sugar, campfire, coal_block, bow, flint_and_steel, chestplate_iron, chestplate_leather, helmet_diamond, helmet_gold, nether_portal.
6. **5 missing ui.* entries added** — ui.builder.placed, ui.bed.picked_up, ui.crop.harvest_prompt, ui.title.customize, ui.mystery.orb.

### Changes to assets/profanity/wordlist_nl.txt

1. **3 typos fixed** — homseksueel -> homosexueel, smerla -> smeerlap, stomaak removed.
2. **10 false positives removed** — gore, ras, vent, vieze, vuil, waardeloos, prutsers, puffer, plasser, idioot.
3. **7 Flemish/Dutch coverage entries added** — eikel, godver, godverdomme, klere, klerezooi, tering, tyfus.

---

## Section 1: UI — Title Screen & Navigation

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| ui.title.tagline | Build. Survive. Play together. | Bouwen. Overleven. Spelen met vrienden. | |
| ui.title.continue_as | Continue as {username} | Doorgaan als {username} | |
| ui.title.continue | Continue | Verdergaan | |
| ui.title.sign_in | Sign in | Inloggen | |
| ui.title.create_account | Create account | Account aanmaken | |
| ui.title.continue_offline | Continue offline | Offline doorgaan | |
| ui.title.settings | Settings | Instellingen | |
| ui.title.customize | Customize Builder | Bouwer aanpassen | [AI added: new entry] |
| ui.deeplink.connecting | Connecting... | Verbinding maken... | |
| ui.deeplink.heading | Sign in to join your friend's world | Log in om mee te doen in de wereld van je vriend | [REVIEWER: "Log in" or "Meld je aan"? Flemish preference?] |
| ui.deeplink.body | Your friend is waiting. | Je vriend wacht op je. | |
| ui.deeplink.email_placeholder | Email | E-mail | |
| ui.deeplink.password_placeholder | Password | Wachtwoord | |
| ui.deeplink.sign_in | Sign in | Inloggen | |
| ui.deeplink.create_account | Create account | Account aanmaken | |
| ui.deeplink.joiner_tip | This is {friend}'s world. They have what you need to get started. | Dit is de wereld van {friend}. Zij hebben wat je nodig hebt om te beginnen. | [REVIEWER: "Zij hebben" — correct use of generic "zij" for unknown gender? Flemish may prefer "Ze hebben"] |
| ui.signin.back_to_title | Back to title | Terug naar het startscherm | [REVIEWER: truncation risk — 26 chars vs 13 EN] |

---

## Section 2: Avatar Creator

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| ui.avatar.title | Choose your builder | Kies je bouwer | |
| ui.avatar.section_skin | Skin | Huid | |
| ui.avatar.section_head | Head | Hoofd | |
| ui.avatar.section_body | Body | Lichaam | |
| ui.avatar.section_legs | Legs | Benen | |
| ui.avatar.section_hand | Hand | Hand | |
| ui.avatar.presets_label | Quick start | Snel starten | |
| ui.avatar.preset_1 | The Scout | De Verkenner | [REVIEWER: Scout -> Verkenner is fine, but "De Scout" might be more natural for gaming audience] |
| ui.avatar.preset_2 | The Builder | De Bouwer | |
| ui.avatar.preset_3 | The Explorer | De Ontdekkingsreiziger | [REVIEWER: truncation risk — 22 chars vs 12 EN. "De Verkenner" shorter, but preset_1 already uses Verkenner. Consider "De Avonturier"?] |
| ui.avatar.preset_4 | The Craftsperson | De Ambachtspersoon | |
| ui.avatar.preset_5 | The Adventurer | De Avonturier | |
| ui.avatar.preset_6 | The Wanderer | De Zwerver | |
| ui.avatar.preset_7 | The Creator | De Maker | |
| ui.avatar.preset_8 | The Survivor | De Overlevende | |
| ui.avatar.randomise | Randomise | Willekeurig | [REVIEWER: "Willekeurig" as button label is fine, but "Mix!" or "Verrassing" might be more playful for kids] |
| ui.avatar.shape_square | Square | Vierkant | |
| ui.avatar.shape_round | Round | Rond | |
| ui.avatar.shape_tall | Tall | Groot | [REVIEWER: "Groot" = big/large; "Lang" = tall. Consider changing to "Lang"] |
| ui.avatar.expr_neutral | Neutral | Neutraal | |
| ui.avatar.expr_happy | Happy | Blij | |
| ui.avatar.expr_cool | Cool | Cool | |
| ui.avatar.expr_surprised | Surprised | Verrast | |
| ui.avatar.expr_sleepy | Sleepy | Slaperig | |
| ui.avatar.accessory_none | None | Geen | |
| ui.avatar.accessory_backpack | Backpack | Rugzak | |
| ui.avatar.accessory_cape | Cape | Cape | |
| ui.avatar.shoes_none | None | Geen | |
| ui.avatar.shoes_boots | Boots | Laarzen | |
| ui.avatar.shoes_sneakers | Sneakers | Sneakers | |
| ui.avatar.hand_none | None | Geen | |
| ui.avatar.hand_pickaxe | Pickaxe | Houweel | |
| ui.avatar.hand_lantern | Lantern | Lantaarn | |
| ui.avatar.hand_flower | Flower | Bloem | |
| ui.avatar.hand_blank | Blank | Leeg | |
| ui.avatar.done | Done | Klaar | |
| ui.avatar.back | Back | Terug | |

---

## Section 3: World Select & New World

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| ui.world_select.title | Your Worlds | Jouw werelden | |
| ui.world_select.friends | Friends | Vrienden | |
| ui.world_select.settings_tooltip | Settings | Instellingen | |
| ui.world_select.new_world | New world | Nieuwe wereld | |
| ui.world_select.worlds_cap_error | Delete a world to create a new one | Verwijder een wereld om een nieuwe aan te maken | |
| ui.world_select.play | Play | Spelen | |
| ui.world_select.mode_creative | Creative | Creatief | |
| ui.world_select.mode_survival | Survival | Overleving | |
| ui.world_select.last_played_today | Today | Vandaag | |
| ui.world_select.last_played_yesterday | Yesterday | Gisteren | |
| ui.world_select.last_played_n_days_ago | {n} days ago | {n} dagen geleden | |
| ui.world_select.ctx_rename | Rename | Hernoemen | |
| ui.world_select.ctx_duplicate | Duplicate | Dupliceren | |
| ui.world_select.ctx_export | Export | Exporteren | |
| ui.world_select.ctx_delete | Delete | Verwijderen | |
| ui.world_select.delete_title | Delete world? | Wereld verwijderen? | |
| ui.world_select.delete_body | This world cannot be recovered. | Deze wereld kan niet worden hersteld. | |
| ui.world_select.delete_confirm | Delete | Verwijderen | |
| ui.world_select.delete_cancel | Cancel | Annuleren | |
| ui.world_select.empty_heading | No worlds yet | Nog geen werelden | |
| ui.world_select.empty_body | Create your first world to get started. | Maak je eerste wereld aan om te beginnen. | |
| ui.new_world.title | New world | Nieuwe wereld | |
| ui.new_world.name_label | World name | Wereldnaam | |
| ui.new_world.name_placeholder | My world | Mijn wereld | |
| ui.new_world.name_char_counter | {n}/24 | {n}/24 | |
| ui.new_world.name_error_empty | Please enter a world name. | Geef je wereld een naam. | |
| ui.new_world.name_error_profanity | Please choose a different name. | Kies een andere naam. | |
| ui.new_world.seed_label | Seed (optional) | Seed (optioneel) | |
| ui.new_world.seed_placeholder | Random | Willekeurig | |
| ui.new_world.seed_hint | Leave blank for a random seed. | Laat leeg voor een willekeurige seed. | |
| ui.new_world.mode_label | Mode | Modus | |
| ui.new_world.mode_survival | Survival | Overleving | |
| ui.new_world.mode_creative | Creative | Creatief | |
| ui.new_world.create | Create | Aanmaken | |
| ui.new_world.creating | Creating… | Aanmaken… | |
| ui.new_world.cancel | Cancel | Annuleren | |

---

## Section 4: FTUE

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| ui.ftue.step_1 | Open the chest — you'll need what's inside before nightfall. | Open de kist — je hebt wat daarin zit nodig voor het donker wordt. | |
| ui.ftue.step_2 | Aim at a tree block and hold to break it — hold the left mouse button (or tap-and-hold on touch). | Probeer een boom te kappen. Tik en houd een boomblok vast. | [REVIEWER: NL version is shorter and drops the mouse button detail. Is this OK or should it be more explicit?] |
| ui.ftue.step_3 | Press B to open your building blocks. You can place anything from your inventory into the world — try placing a wooden plank. | Je kunt alles in je inventaris terugplaatsen in de wereld. Probeer een houten plank te plaatsen. | [REVIEWER: NL drops the "Press B" hint. Should add: "Druk op B om je bouwblokken te openen."?] |
| ui.ftue.complete | That's it. The world is yours. | Dat is het. De wereld is van jou. | |
| ui.ftue.night_hint | Time to sleep. Walk to the bed. | Tijd om te slapen. Loop naar het bed. | |
| ui.ftue.progress_label | Step {n}/{total} | Stap {n}/{total} | |

---

## Section 5: HUD & In-World

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| ui.builder.place | Place | Plaatsen | |
| ui.builder.break | Break | Afbreken | |
| ui.builder.jump | Jump | Springen | |
| ui.builder.cant_place_there | Can't place there. | Daar kan je niet plaatsen. | |
| ui.builder.no_tool | Select a brick or tool from the hotbar. | Selecteer een brick of gereedschap uit de hotbar. | |
| ui.builder.placed | Placed! | Geplaatst! | [AI added: new entry] |
| ui.hotbar.slot_empty | Slot {n} — empty | Vak {n} — leeg | |
| ui.hotbar.slot_filled | Slot {n} — {brick_name} | Vak {n} — {brick_name} | |
| ui.hud.mode.survival | Survival | Overleving | |
| ui.hud.mode.sandbox | Sandbox | Sandbox | [AI changed: Creatief -> Sandbox — matches game mode name, avoids confusion with world-select creative label] |
| ui.camera.mode_fpv | First-person view | Eerste-persoonsperspectief | [REVIEWER: truncation risk — 26 chars vs 17 EN. Consider "Eerste-persoon"] |
| ui.camera.mode_chase | Third-person view | Derde-persoonsperspectief | [REVIEWER: similar truncation risk. Consider "Derde-persoon"] |
| ui.camera.toggle_hint | Press V to switch view | Druk op V om van perspectief te wisselen | [REVIEWER: truncation risk — 40 chars vs 22 EN] |
| ui.world.deep_dark_warning | Something stirs in the darkness. | Iets roert zich in het duister. | |
| ui.weather.rain_dance_summoned | The sky listens. Rain begins. | De lucht luistert. Het begint te regenen. | |
| ui.weather.sky_wont_listen_again_today | The sky won't listen again today. | De lucht luistert vandaag niet meer. | |
| ui.world.found_village | You found a village. | Je hebt een dorp gevonden. | |
| ui.world.found_temple | You found a temple. | Je hebt een tempel gevonden. | |
| ui.world.found_shipwreck | You found a shipwreck. | Je hebt een scheepswrak gevonden. | |
| ui.world.found_dungeon | You found a dungeon. | Je hebt een kerker gevonden. | |
| ui.world.found_mineshaft | You found a mineshaft. | Je hebt een mijnschacht gevonden. | |
| ui.world.items_dropped_nearby | {count} items nearby. | {count} voorwerpen in de buurt. | |
| ui.mystery.orb | A green orb streaks across the sky… leaving only questions. | Een groene bol schiet door de lucht… en laat alleen vragen achter. | [AI added: new entry] |
| ui.tool.worn_out | {tool_name} broke. | {tool_name} is kapot. | |
| ui.tool.durability_sr | Durability: {pct}% | Duurzaamheid: {pct}% | |
| ui.tool.dynamite_fuse_lit | Fuse lit — step back! | Lont aangestoken — stap achteruit! | [REVIEWER: truncation risk — 34 chars vs 21 EN] |
| ui.hp.bar_sr | Health: {hp} of 10 | Gezondheid: {hp} van 10 | |
| ui.hp.gained_tick | +{n} HP | +{n} HP | |
| ui.crop.harvest_prompt | Hold SHIFT to harvest | Houd SHIFT ingedrukt om te oogsten | [AI added: new entry — truncation risk: 34 chars vs 21 EN] |
| ui.bed.picked_up | Bed picked up | Bed opgeraapt | [AI added: new entry] |
| ui.bed.too_early_prompt | Sleep is for the night | Slapen is voor 's nachts | |
| ui.bed.sleep_prompt | Hold SHIFT to sleep | Houd SHIFT ingedrukt om te slapen | [REVIEWER: truncation risk — 33 chars vs 19 EN] |

---

## Section 6: Inventory, Crafting, Chest, Recipes

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| ui.inventory.open | Open inventory | Inventaris openen | |
| ui.inventory.close | Close inventory | Inventaris sluiten | |
| ui.inventory.title | Inventory | Inventaris | |
| ui.inventory.tab.inventory | Inventory | Inventaris | |
| ui.inventory.tab.recipes | Recipes | Recepten | |
| ui.inventory.cell.empty | Slot {row},{col} — empty | Vak {row},{col} — leeg | |
| ui.inventory.cell.filled | Slot {row},{col} — {item_name}, {count} | Vak {row},{col} — {item_name}, {count} | |
| ui.inventory.full | Inventory full. | Inventaris vol. | |
| ui.inventory.picked_up | +{count} {item_name} | +{count} {item_name} | |
| ui.crafting.inline.heading | Crafting (2 by 2) | Ambachtstafel (2 bij 2) | [REVIEWER: style note — "Ambachtstafel" is slightly verbose for inline 2x2; consider "Maken (2×2)" or keep as-is] |
| ui.item.eat | Eat | Eten | |
| ui.crafting.workbench.heading | Crafting (3 by 3) | Ambachtstafel (3 bij 3) | [REVIEWER: same as above] |
| ui.workbench.title | Workbench | Werkbank | |
| ui.workbench.open_prompt | Hold SHIFT to use workbench | Houd SHIFT ingedrukt om de werkbank te gebruiken | [REVIEWER: truncation risk — 48 chars vs 27 EN] |
| ui.chest.open_prompt | Hold SHIFT to open chest | Houd SHIFT ingedrukt om de kist te openen | [REVIEWER: truncation risk — 41 chars vs 24 EN] |
| ui.chest.locked_prompt | Locked — needs {key_name} | Op slot — heeft {key_name} nodig | |
| ui.chest.title_suffix | Chest | Kist | |
| ui.chest.your_inventory | Your inventory | Jouw inventaris | |
| ui.chest.tier.regular | Regular | Gewoon | |
| ui.chest.tier.bronze | Bronze | Brons | |
| ui.chest.tier.silver | Silver | Zilver | |
| ui.chest.tier.gold | Gold | Goud | |
| ui.chest.tier.diamond | Diamond | Diamant | |
| ui.strawberry.pickup_prompt | Pick strawberry | Aardbei pakken | |
| ui.death.headline | You died | Je bent gestorven | |
| ui.death.subtitle | Respawning at your bed… | Opnieuw spawnen bij je bed… | |
| ui.death.subtitle_spawn | Respawning at world spawn… | Opnieuw spawnen bij het beginpunt… | |
| ui.death.countdown | Respawning in {n}s | Opnieuw spawnen over {n}s | |
| ui.death_pile.sr | Your dropped items — walk through to collect | Jouw gevallen voorwerpen — loop erdoorheen om ze op te pakken | |
| ui.sleep.cancelled_unsafe | You can't sleep — too dangerous. | Je kunt niet slapen — het is te gevaarlijk. | |
| ui.hp.gained_tick | +{n} HP | +{n} HP | |
| chests.regular.name | Chest | Kist | |
| chests.bronze.name | Bronze chest | Bronzen kist | |
| chests.silver.name | Silver chest | Zilveren kist | |
| chests.gold.name | Gold chest | Gouden kist | |
| chests.diamond.name | Diamond chest | Diamanten kist | |
| chests.double_regular.name | Large chest | Grote kist | |
| items.key_bronze.name | Bronze key | Bronzen sleutel | |
| items.key_silver.name | Silver key | Zilveren sleutel | |
| items.key_gold.name | Gold key | Gouden sleutel | |
| items.key_diamond.name | Diamond key | Diamanten sleutel | [REVIEWER: truncation risk — 17 chars vs 11 EN] |
| ui.recipes.empty.title | No recipes yet | Nog geen recepten | |
| ui.recipes.empty.body | Gather ingredients or craft something at a workbench to start your recipe book. | Verzamel ingrediënten of maak iets bij een werkbank om je receptenboek te starten. | |
| ui.recipes.fill_grid | Auto-fill | Automatisch vullen | |

---

## Section 7: Multiplayer — Sign-in, Friends, Session, Invite, Join

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| ui.signin.title | Sign in to Cubicraftia | Inloggen bij Cubicraftia | |
| ui.signin.tab.signin | Sign in | Inloggen | |
| ui.signin.tab.create | Create account | Account aanmaken | |
| ui.signin.email_placeholder | Email address | E-mailadres | |
| ui.signin.password_placeholder | Password | Wachtwoord | |
| ui.signin.submit_signin | Sign in | Inloggen | |
| ui.signin.submit_create | Create account | Account aanmaken | |
| ui.signin.age_checkbox | I am 13 or older. | Ik ben 13 jaar of ouder. | [AI added: was empty] |
| ui.signin.apple | Sign in with Apple | Inloggen met Apple | |
| ui.signin.google | Sign in with Google | Inloggen met Google | |
| ui.signin.verification_notice | A verification link has been sent. You can play now — some features unlock after verification. | Er is een verificatielink verzonden. Je kunt nu spelen — sommige functies worden pas beschikbaar na verificatie. | |
| ui.signin.error_invalid_credentials | Incorrect email or password. | Onjuist e-mailadres of wachtwoord. | |
| ui.signin.error_email_taken | An account with that email already exists. | Er bestaat al een account met dat e-mailadres. | |
| ui.signin.error_network | Can't reach the server. Check your internet. | Kan de server niet bereiken. Controleer je internetverbinding. | |
| ui.signin.error_profanity_username | That username isn't allowed. Please choose another. | Die gebruikersnaam is niet toegestaan. Kies een andere naam. | |
| ui.signin.dob_label | Date of birth | Geboortedatum | |
| ui.signin.dob_day_placeholder | Day | Dag | |
| ui.signin.dob_month_placeholder | Month | Maand | |
| ui.signin.dob_year_placeholder | Year | Jaar | |
| ui.signin.dob_month_jan | January | Januari | |
| ui.signin.dob_month_feb | February | Februari | |
| ui.signin.dob_month_mar | March | Maart | |
| ui.signin.dob_month_apr | April | April | |
| ui.signin.dob_month_may | May | Mei | |
| ui.signin.dob_month_jun | June | Juni | |
| ui.signin.dob_month_jul | July | Juli | |
| ui.signin.dob_month_aug | August | Augustus | |
| ui.signin.dob_month_sep | September | September | |
| ui.signin.dob_month_oct | October | Oktober | |
| ui.signin.dob_month_nov | November | November | |
| ui.signin.dob_month_dec | December | December | |
| ui.signin.error_dob_incomplete | Please enter your date of birth. | Vul je geboortedatum in. | |
| ui.signin.error_dob_invalid | Please enter a valid date. | Vul een geldige datum in. | |
| ui.friends.title | Friends | Vrienden | |
| ui.friends.search_placeholder | Search by username… | Zoek op gebruikersnaam… | |
| ui.friends.search_empty | No builder found. | Geen bouwer gevonden. | |
| ui.friends.section_pending | Requests | Verzoeken | |
| ui.friends.section_list | Friends | Vrienden | |
| ui.friends.status_online | Online | Online | |
| ui.friends.status_in_world | Online · in {world_name} | Online · in {world_name} | |
| ui.friends.status_offline | Offline | Offline | |
| ui.friends.join | Join | Deelnemen | |
| ui.friends.accept | Accept | Accepteren | |
| ui.friends.decline | Decline | Weigeren | |
| ui.friends.empty_heading | No friends yet | Nog geen vrienden | |
| ui.friends.empty_body | Share an invite link from the pause menu to add friends. | Deel een uitnodigingslink via het pauzemenu om vrienden toe te voegen. | |
| ui.friends.unfriend | Unfriend | Vriend verwijderen | |
| ui.friends.block | Block | Blokkeren | |
| ui.friends.block_confirm | Block {username}? They won't be able to find you. | {username} blokkeren? Ze kunnen je niet meer vinden. | |
| ui.friends.block_confirm_action | Block | Blokkeren | |
| ui.friends.limit_reached | Friend list is full (50 max) | Vriendenlijst is vol (max. 50) | |
| ui.session.open_status | Open · {world_name} | Open · {world_name} | |
| ui.session.join_loading | Joining… | Deelnemen… | |
| ui.session.join_failed | Couldn't join — {reason}. Try again. | Kon niet deelnemen — {reason}. Probeer opnieuw. | |
| ui.invite.title | Invite a friend | Een vriend uitnodigen | |
| ui.invite.link_label | Invite link | Uitnodigingslink | |
| ui.invite.ttl_countdown | Expires in {hh_mm_ss} | Verloopt over {hh_mm_ss} | |
| ui.invite.copy | Copy link | Link kopiëren | |
| ui.invite.copied | Copied! | Gekopieerd! | |
| ui.invite.share | Share | Delen | |
| ui.invite.close | Close | Sluiten | |
| ui.invite.generating | Generating link… | Link aanmaken… | |
| ui.invite.error_network | Couldn't generate a link. Check your internet. | Kon geen link aanmaken. Controleer je internetverbinding. | |
| ui.invite.error_not_signed_in | Sign in to invite friends. | Log in om vrienden uit te nodigen. | |
| ui.invite.error_not_verified | Verify your email to send invites. | Verifieer je e-mailadres om uitnodigingen te sturen. | [REVIEWER: truncation risk — 52 chars vs 34 EN] |
| ui.join.heading | Joining {username}'s world… | Deelnemen aan de wereld van {username}… | |
| ui.join.status_connecting | Connecting… | Verbinding maken… | [REVIEWER: truncation risk — 17 chars vs 11 EN] |
| ui.join.status_loading | Loading world… | Wereld laden… | |
| ui.join.new_friends_toast | You and {username} are now friends. | Jij en {username} zijn nu vrienden. | |
| ui.join.error_session_full | The session is full. | De sessie is vol. | |
| ui.join.error_expired | The invite has expired. | De uitnodiging is verlopen. | |
| ui.join.error_connection | Connection failed — check your internet. | Verbinding mislukt — controleer je internetverbinding. | |
| ui.join.back | Back | Terug | |
| ui.join.error_unverified_session_age | This session is too old to join with an unverified account. Verify your email first. | Deze sessie is te oud om aan deel te nemen met een niet-geverifieerd account. Verifieer eerst je e-mailadres. | |

---

## Section 8: Multiplayer — Players Tab, Chat, Handover, Network

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| ui.players.tab_label | Players | Spelers | |
| ui.players.invite_action | Invite a friend | Een vriend uitnodigen | |
| ui.players.host_label | (Host) | (Host) | |
| ui.players.kick | Kick | Verwijderen | |
| ui.players.kick_confirm | Kick {username}? They can rejoin via invite. | {username} verwijderen? Ze kunnen via een uitnodiging terugkomen. | |
| ui.players.kick_confirm_action | Confirm kick | Bevestigen | |
| ui.players.kick_cancel | Cancel | Annuleren | |
| ui.players.freeze | Freeze | Bevriezen | |
| ui.players.unfreeze | Unfreeze | Ontdooien | |
| ui.players.rollback_warning | Restore the world to ~30 minutes ago. Affects everyone. | De wereld herstellen naar ~30 minuten geleden. Dit heeft gevolgen voor iedereen. | |
| ui.players.rollback_action | Roll back world | Wereld terugdraaien | |
| ui.players.rollback_confirm_title | Roll back world? | Wereld terugdraaien? | |
| ui.players.rollback_confirm_body | This restores everyone to the last automatic snapshot, about 30 minutes ago. All builds since then will be lost. | Dit herstelt iedereen naar de laatste automatische momentopname, ongeveer 30 minuten geleden. Alle bouw sindsdien gaat verloren. | |
| ui.players.rollback_confirm_action | Roll back | Terugdraaien | |
| ui.players.rollback_cancel | Cancel | Annuleren | |
| ui.players.laggy_label | Laggy | Laggy | |
| ui.players.settings_tab_label | Settings | Instellingen | |
| ui.chat.input_placeholder | Message… | Bericht… | |
| ui.chat.send | Send | Versturen | |
| ui.chat.open | Chat | Chat | |
| ui.chat.close | Close chat | Chat sluiten | |
| ui.chat.rate_limit_wait | Slow down — you can send another message in {n}s. | Rustig aan — je kunt over {n}s een nieuw bericht sturen. | |
| ui.chat.mute_player | Mute {username} | {username} dempen | |
| ui.chat.unmute_player | Unmute {username} | {username} dempen opheffen | [REVIEWER: truncation risk — 26 chars vs 17 EN. Consider "{username} afdempen"?] |
| ui.chat.report_message | Report message | Bericht melden | |
| ui.chat.filtered_message | [filtered] | [gefilterd] | |
| ui.handover.heading | Switching host — keeping the world… | Host wisselen — wereld blijft behouden… | |
| ui.handover.subtitle | Hold on a moment. | Even wachten. | |
| ui.handover.subtitle_slow | This is taking longer than expected… | Dit duurt langer dan verwacht… | |
| ui.netstatus.relay_badge | Relay | Relay | |

---

## Section 9: Safety & Moderation

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| ui.block.title | Block {username}? | {username} blokkeren? | |
| ui.block.body | They won't see you or your world. You won't see them. | Ze zien jou en je wereld niet meer. Jij ziet hen niet meer. | |
| ui.block.confirm_action | Block {username} | {username} blokkeren | |
| ui.block.cancel | Cancel | Annuleren | |
| ui.block.toast_blocked | You blocked {username}. | Je hebt {username} geblokkeerd. | |
| ui.report.title_player | Report {username} | {username} melden | |
| ui.report.title_message | Report this message | Dit bericht melden | |
| ui.report.subtitle_category | What's the problem? | Wat is het probleem? | |
| ui.report.category_harassment | Harassment or threats | Pesterij of bedreigingen | |
| ui.report.category_spam | Spam or fake content | Spam of neppe inhoud | |
| ui.report.category_cheating | Cheating | Valsspelen | |
| ui.report.category_csam | Child safety concern | Kinderveiligheidsprobleem | |
| ui.report.category_other | Something else | Iets anders | |
| ui.report.reason_placeholder | Add details (optional) | Details toevoegen (optioneel) | |
| ui.report.char_counter | {n}/500 | {n}/500 | |
| ui.report.context_label | Reported message and context: | Gemeld bericht en context: | |
| ui.report.next | Next | Volgende | |
| ui.report.back | Back | Terug | |
| ui.report.submit | Submit report | Melding indienen | |
| ui.report.cancel | Cancel | Annuleren | |
| ui.report.toast_submitted | Report submitted. Our team will review. | Melding ingediend. Ons team bekijkt het. | |
| ui.consent.title | Ask a parent to confirm | Vraag een ouder om te bevestigen | |
| ui.consent.body | You'll need a parent or guardian to approve your account before you can play with friends. Enter their email address and we'll send them a confirmation link. | Je hebt toestemming nodig van een ouder of voogd om met vrienden te spelen. Voer hun e-mailadres in en we sturen hen een bevestigingslink. | |
| ui.consent.parent_email_placeholder | Parent or guardian's email | E-mailadres van ouder of voogd | |
| ui.consent.send_link | Send link | Link versturen | |
| ui.consent.sending | Sending… | Versturen… | |
| ui.consent.why_label | Why am I seeing this? | Waarom zie ik dit? | |
| ui.consent.why_explanation | Cubicraftia asks players under 13 for a parent's permission before they can join sessions or chat with friends. Your parent's email is only used to send this confirmation — it is not stored after they confirm. | Cubicraftia vraagt spelers jonger dan 13 jaar om toestemming van een ouder voordat ze aan sessies mee kunnen doen of met vrienden kunnen chatten. Het e-mailadres van je ouder wordt alleen gebruikt om deze bevestiging te sturen — het wordt niet opgeslagen na de bevestiging. | |
| ui.consent.skip | Skip for now | Voorlopig overslaan | [REVIEWER: truncation risk — 19 chars vs 12 EN] |
| ui.consent.success_heading | Link sent! | Link verzonden! | |
| ui.consent.success_body | We sent a confirmation link to {parent_email}. Ask your parent to check their email and tap the link. | We hebben een bevestigingslink gestuurd naar {parent_email}. Vraag je ouder om hun e-mail te bekijken en op de link te tikken. | |
| ui.consent.done | Done | Klaar | |
| ui.consent.resend | Resend | Opnieuw versturen | |
| ui.consent.resent_toast | Sent again. | Opnieuw verzonden. | [REVIEWER: truncation risk — 18 chars vs 11 EN] |
| ui.consent.error_invalid_email | Please enter a valid email address. | Voer een geldig e-mailadres in. | |
| ui.consent.error_network | Could not send the email. Check your connection and try again. | Kon de e-mail niet versturen. Controleer je verbinding en probeer het opnieuw. | |
| ui.legal.terms_link | Terms of Use | Gebruiksvoorwaarden | [REVIEWER: truncation risk — 19 chars vs 12 EN. "Voorwaarden" shorter if space is tight] |
| ui.legal.privacy_link | Privacy Policy | Privacybeleid | |
| ui.legal.viewer_close | Close | Sluiten | |
| ui.legal.footer_version | Version: {hash} | Versie: {hash} | |
| ui.legal.agree_button | I agree | Ik ga akkoord | |
| ui.legal.english_only_notice | The following legal text is provided in English only. This is the binding version. | De volgende juridische tekst is alleen beschikbaar in het Engels. Dit is de bindende versie. | |
| ui.legal.reack_title | We updated our Terms of Use | We hebben onze Gebruiksvoorwaarden bijgewerkt | [REVIEWER: truncation risk — 45 chars vs 27 EN] |
| ui.legal.reack_body | Please review and accept the new terms to continue. | Bekijk en accepteer de nieuwe voorwaarden om door te gaan. | |
| ui.legal.reack_review | Review Terms | Voorwaarden bekijken | [REVIEWER: truncation risk — 20 chars vs 12 EN] |
| ui.legal.reack_signout | Sign out | Uitloggen | |
| ui.restricted.banner_label | Awaiting parent's confirmation — | Wacht op bevestiging van ouder — | |
| ui.restricted.resend_link | Resend email | E-mail opnieuw sturen | [REVIEWER: truncation risk — 21 chars vs 12 EN] |
| ui.restricted.join_blocked_title | Parental approval needed | Toestemming van ouder nodig | |
| ui.restricted.join_blocked_body | Your account needs a parent's approval before you can join sessions. Ask your parent to check their email. | Je account heeft toestemming van een ouder nodig voordat je aan sessies kunt deelnemen. Vraag je ouder om hun e-mail te bekijken. | |
| ui.restricted.join_blocked_resend | Resend email | E-mail opnieuw sturen | [REVIEWER: truncation risk — 21 chars vs 12 EN] |
| ui.restricted.join_blocked_cancel | Cancel | Annuleren | |
| ui.username.error_format | Username must be 3–20 characters. Letters, numbers, and underscore only. | Gebruikersnaam moet 3–20 tekens zijn. Alleen letters, cijfers en underscores. | |
| ui.username.error_taken | That username is taken. Try a different one. | Die gebruikersnaam is al in gebruik. Probeer een andere. | |
| ui.username.error_profanity | Please choose a different username. | Kies een andere gebruikersnaam. | |
| ui.username.error_reserved | That username is reserved. | Die gebruikersnaam is gereserveerd. | |
| ui.username.error_cooldown | You can change your username again in {n} days. | Je kunt je gebruikersnaam pas over {n} dagen weer wijzigen. | |
| ui.username.cooldown_label | Username change available in {n} days. | Gebruikersnaam wijzigen beschikbaar over {n} dagen. | |
| ui.username.inline_valid | (empty — intentional) | (empty — intentional) | EN is also empty; skip is correct |
| ui.friends.report | Report | Melden | |
| ui.chat.report_context_menu_item | Report this message | Dit bericht melden | |
| ui.nameplate.report_action | Report {username} | {username} melden | |
| ui.nameplate.block_action | Block {username} | {username} blokkeren | |

---

## Section 10: Settings

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| ui.settings.graphics.apply | Apply preset | Preset toepassen | |
| ui.settings.graphics.preset.auto | Auto | Auto | |
| ui.settings.graphics.preset.low | Low | Laag | |
| ui.settings.graphics.preset.medium | Medium | Middel | |
| ui.settings.graphics.preset.high | High | Hoog | |
| ui.settings.graphics.reset | Reset graphics to defaults | Grafische instellingen herstellen | |
| ui.settings.graphics.reset.confirm | Reset your graphics settings to the Auto preset? Custom render-distance and shadow overrides will be cleared. | Grafische instellingen terugzetten naar de auto-preset? Eigen weergaveafstand en schaduwopties worden gewist. | |
| ui.settings.graphics.reset.do | Reset | Herstellen | |
| ui.settings.iap.title | Brick Packs | Brick-pakketten | |
| ui.settings.iap.coming_later | Brick packs arrive in a later release. | Brick-pakketten komen in een latere versie. | |
| ui.settings.show_nameplates | Show player names | Spelernamen weergeven | |
| ui.settings.language_label | Language | Taal | |
| ui.settings.locale_en | English | English | |
| ui.settings.locale_nl | Nederlands | Nederlands | |
| ui.settings.legal_section_title | Legal | Juridisch | |
| ui.settings.terms_button | Terms of Use | Gebruiksvoorwaarden | [REVIEWER: truncation risk — 19 chars vs 12 EN] |
| ui.settings.privacy_button | Privacy Policy | Privacybeleid | |
| ui.settings.account_section_title | Account | Account | |
| ui.settings.account_username_label | Username: {current} | Gebruikersnaam: {current} | |
| ui.settings.account_change_username | Change username | Gebruikersnaam wijzigen | [REVIEWER: truncation risk — 23 chars vs 15 EN] |
| ui.settings.account_change_save | Save | Opslaan | |
| ui.settings.account_change_cancel | Cancel | Annuleren | |
| ui.settings.account_delete_button | Delete account | Account verwijderen | |
| ui.settings.account_delete_title | Delete your account? | Je account verwijderen? | |
| ui.settings.account_delete_body | Your account will be permanently deleted after 7 days. You can cancel during this time by signing back in. | Je account wordt na 7 dagen definitief verwijderd. Je kunt dit annuleren door in die tijd opnieuw in te loggen. | |
| ui.settings.account_delete_confirm | Delete account | Account verwijderen | |
| ui.settings.account_delete_cancel | Cancel | Annuleren | |
| ui.settings.account_delete_pending | Account deletion pending — cancels on {date}. | Verwijdering account in behandeling — wordt geannuleerd op {date}. | |
| ui.settings.account_delete_cancel_action | Cancel deletion | Verwijdering annuleren | |
| ui.about.title | About Cubicraftia | Over Cubicraftia | |
| ui.about.disclaimer | (legal — LEGO/Mojang allowlisted) | (legal — LEGO Groep/Mojang Studios names allowlisted per T-09-02) | Allowlisted: these legal strings intentionally name trademark holders |
| ui.about.version | Version {version} | Versie {version} | |
| ui.about.license | Licensed under GPL-3.0-or-later | Gelicentieerd onder GPL-3.0-or-later | |
| ui.first_launch.disclaimer | (legal — LEGO/Mojang allowlisted) | (legal — LEGO Groep/Mojang Studios names allowlisted per T-09-02) | Allowlisted |
| ui.first_launch.acknowledge | Got it | Begrepen | |
| ui.toast.graphics_adjusted | Graphics adjusted for performance. | Grafische instellingen aangepast voor prestaties. | |
| ui.settings.graphics_adjusted | Graphics adjusted for performance. | Grafische instellingen aangepast voor prestaties. | |
| ui.toast.feature_in_later_release | This feature arrives in a later release. | Deze functie komt in een latere versie. | |
| ui.device.unsupported | This device does not meet Cubicraftia's minimum requirements. The game may run slowly or crash. You can continue anyway, or pick another device. | Dit apparaat voldoet niet aan de minimumvereisten van Cubicraftia. Het spel kan traag zijn of crashen. Je kunt toch doorgaan of een ander apparaat gebruiken. | |
| ui.device.continue_anyway | Continue anyway | Toch doorgaan | |
| ui.device.quit | Quit | Stoppen | |
| ui.common.cancel | Cancel | Annuleren | |
| ui.common.done | Done | Klaar | |
| ui.common.back | Back | Terug | |
| ui.palette.category.all | All | Alles | |
| ui.palette.category.rectangular | Rectangular | Rechthoekig | |
| ui.palette.category.plates | Plates | Platen | |
| ui.palette.category.slopes | Slopes | Schuinvlakken | |
| ui.palette.category.tiles | Tiles | Tegels | |
| ui.palette.category.round | Round | Rond | |
| ui.palette.category.functional | Functional | Functioneel | |
| ui.palette.category.decorative | Decorative | Decoratief | |
| ui.palette.category.materials | Materials | Materialen | |
| ui.palette.category.accessories | Accessories | Accessoires | |
| ui.palette.category.mob_drops | Mob drops | Vijanddrops | |
| ui.palette.equip | Equip | Uitrusten | |
| ui.palette.open | Open brick palette | Brickpalet openen | |
| ui.palette.search_placeholder | Search bricks… | Bricks zoeken… | |
| ui.palette.search_empty_heading | No bricks found | Geen bricks gevonden | |
| ui.palette.search_empty_body | Try a different name or category. | Probeer een andere naam of categorie. | |
| ui.palette.colour.all | All colours | Alle kleuren | |
| ui.palette.tile.sr_label | {brick_name}, {colour_name} | {brick_name}, {colour_name} | |
| ui.palette.close | Close | Sluiten | |
| tools.pickaxe_wood.name | Wooden pickaxe | Houten houweel | |
| tools.pickaxe_stone.name | Stone pickaxe | Stenen houweel | |
| tools.pickaxe_iron.name | Iron pickaxe | IJzeren houweel | |
| tools.pickaxe_diamond.name | Diamond pickaxe | Diamanten houweel | |
| tools.shovel.name | Shovel | Schop | |
| tools.dynamite.name | Dynamite | Dynamiet | |
| tools.lantern_handheld.name | Lantern | Lantaarn | |
| items.food_cooked_generic.name | Cooked food | Gekookt eten | |
| items.food_tom_yum.name | Tom Yum spicy seafood soup | Tom Yum pittige zeevruchtensoep | |
| items.food_roasted_fish.name | Roasted fish | Geroosterde vis | |
| items.food_bread.name | Bread | Brood | |
| items.food_pie.name | Pie | Taart | |
| items.strawberry.name | Strawberry | Aardbei | |
| ui.friends.title_standalone | Friends | Vrienden | |

---

## Section 11: Brick Names

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| bricks.brick_1x1.name | 1×1 brick | 1×1 brick | brand term — keep as "brick" |
| bricks.brick_1x2.name | 1×2 brick | 1×2 brick | |
| bricks.brick_1x3.name | 1×3 brick | 1×3 brick | |
| bricks.brick_1x4.name | 1×4 brick | 1×4 brick | |
| bricks.brick_2x2.name | 2×2 brick | 2×2 brick | |
| bricks.brick_2x3.name | 2×3 brick | 2×3 brick | |
| bricks.brick_2x4.name | 2×4 brick | 2×4 brick | |
| bricks.plate_1x1.name | 1×1 plate | 1×1 plaat | |
| bricks.plate_1x2.name | 1×2 plate | 1×2 plaat | |
| bricks.plate_1x4.name | 1×4 plate | 1×4 plaat | |
| bricks.plate_2x2.name | 2×2 plate | 2×2 plaat | |
| bricks.plate_2x4.name | 2×4 plate | 2×4 plaat | |
| bricks.slope_1x1x1.name | 1×1×1 slope | 1×1×1 schuinvlak | |
| bricks.slope_1x2x1.name | 1×2×1 slope | 1×2×1 schuinvlak | |
| bricks.slope_1x2x2.name | 1×2×2 slope | 1×2×2 schuinvlak | |
| bricks.slope_2x2_corner.name | 2×2 corner slope | 2×2 hoekschuinvlak | |
| bricks.tile_1x1.name | 1×1 tile | 1×1 tegel | |
| bricks.tile_1x2.name | 1×2 tile | 1×2 tegel | |
| bricks.tile_2x2.name | 2×2 tile | 2×2 tegel | |
| bricks.round_1x1_brick.name | 1×1 round brick | 1×1 ronde brick | |
| bricks.round_2x2_brick.name | 2×2 round brick | 2×2 ronde brick | |
| bricks.round_1x1_plate.name | 1×1 round plate | 1×1 ronde plaat | |
| bricks.cylinder_1x1.name | 1×1 cylinder | 1×1 cilinder | |
| bricks.wheel.name | Wheel | Wiel | |
| bricks.door_1x4.name | Door | Deur | |
| bricks.window_1x2.name | Window | Raam | |
| bricks.trapdoor_2x2.name | Trapdoor | Luik | |
| bricks.workbench.name | Workbench | Werkbank | |
| bricks.chest_regular.name | Regular chest | Gewone kist | |
| bricks.flower.name | Flower | Bloem | |
| bricks.lantern.name | Lantern | Lantaarn | |
| bricks.torch.name | Torch | Fakkel | |
| bricks.ladder.name | Ladder | Ladder | |
| bricks.sign.name | Sign | Bord | |
| bricks.wood_log.name | Wood log | Boomstam | |
| bricks.wood_plank.name | Wood plank | Houten plank | |
| bricks.stone.name | Stone | Steen | |
| bricks.cobblestone.name | Cobblestone | Kassei | |
| bricks.copper_ore.name | Copper ore | Kopererts | |
| bricks.iron_ore.name | Iron ore | IJzererts | |
| bricks.diamond_ore.name | Diamond ore | Diamanterts | |
| bricks.sand.name | Sand | Zand | |
| bricks.glass.name | Glass | Glas | |
| bricks.pickaxe.name | Pickaxe | Houweel | |
| bricks.shovel.name | Shovel | Schop | |
| bricks.sword.name | Sword | Zwaard | |
| bricks.dynamite.name | Dynamite | Dynamiet | |
| bricks.lantern_handheld.name | Handheld lantern | Draagbare lantaarn | |
| bricks.bone.name | Bone | Bot | |
| bricks.slime_cube.name | Slime cube | Slijmkubus | |
| bricks.raw_meat.name | Raw meat | Rauw vlees | [AI added: new entry] |
| bricks.sashimi.name | Sashimi | Sashimi | [AI added: new entry] |
| bricks.gold_ingot.name | Gold ingot | Goudstaaf | [AI added: new entry] |
| bricks.coal.name | Coal | Steenkool | [AI added: new entry] |
| bricks.leather.name | Leather | Leer | [AI added: new entry] |
| bricks.string.name | String | Touw | [AI added: new entry] |
| bricks.wheat.name | Wheat | Tarwe | [AI added: new entry] |
| bricks.sugar_cane.name | Sugar cane | Suikerriet | [AI added: new entry] |
| bricks.obsidian.name | Obsidian | Obsidiaan | [AI added: new entry] |
| bricks.furnace.name | Furnace | Oven | [AI added: new entry] |
| bricks.bucket.name | Bucket | Emmer | [AI added: new entry] |
| bricks.sugar.name | Sugar | Suiker | [AI added: new entry] |
| bricks.bread.name | Bread | Brood | [AI added: new entry] |
| bricks.campfire.name | Campfire | Kampvuur | [AI added: new entry] |
| bricks.coal_block.name | Coal block | Steenkoolblok | [AI added: new entry] |
| bricks.bow.name | Bow | Boog | [AI added: new entry] |
| bricks.flint_and_steel.name | Flint and steel | Vuursteen en staal | [AI added: new entry] |
| bricks.chestplate_iron.name | Iron chestplate | IJzeren borstplaat | [AI added: new entry] |
| bricks.chestplate_leather.name | Leather chestplate | Leren borstplaat | [AI added: new entry] |
| bricks.helmet_diamond.name | Diamond helmet | Diamanten helm | [AI added: new entry] |
| bricks.helmet_gold.name | Gold helmet | Gouden helm | [AI added: new entry] |
| bricks.nether_portal.name | Portal | Portaal | [AI added: new entry] |
| bricks.axe.name | Axe | Bijl | [AI added: new entry] |
| bricks.hammer.name | Hammer | Hamer | [AI added: new entry] |
| bricks.fishing_rod.name | Fishing rod | Hengel | [AI added: new entry] |
| bricks.compass.name | Compass | Kompas | [AI added: new entry] |
| bricks.map.name | Map | Kaart | [AI added: new entry] |
| bricks.crafting_table_advanced.name | Advanced Workbench | Geavanceerde werkbank | [AI added: new entry] |
| bricks.painting_small_1.name | Painting (Mountain) | Schilderij (Berg) | [AI added: new entry] |
| bricks.painting_small_2.name | Painting (Night) | Schilderij (Nacht) | [AI added: new entry] |
| bricks.flower_pot.name | Flower Pot | Bloempot | [AI added: new entry] |
| bricks.pot_red_flower.name | Red Flower Pot | Rode bloempot | [AI added: new entry] |
| bricks.pot_blue_flower.name | Blue Flower Pot | Blauwe bloempot | [AI added: new entry] |
| bricks.pot_yellow_flower.name | Yellow Flower Pot | Gele bloempot | [AI added: new entry] |
| bricks.pot_white_flower.name | White Flower Pot | Witte bloempot | [AI added: new entry] |
| bricks.pot_pink_flower.name | Pink Flower Pot | Roze bloempot | [AI added: new entry] |
| bricks.well.name | Well | Waterput | [AI added: new entry] |
| bricks.barrel.name | Barrel | Ton | [AI added: new entry] |
| bricks.bookshelf.name | Bookshelf | Boekenkast | [AI added: new entry] |
| bricks.crate.name | Crate | Krat | [AI added: new entry] |
| bricks.chair_wood.name | Wooden Chair | Houten stoel | [AI added: new entry] |
| bricks.anvil.name | Anvil | Aambeeld | [AI added: new entry] |
| bricks.table_wood.name | Wooden Table | Houten tafel | [AI added: new entry] |

---

## Section 12: Recipe Names

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| recipes.wooden_plank.name | Wooden plank | Houten plank | |
| recipes.stick.name | Stick | Stok | |
| recipes.pickaxe_wood.name | Wooden pickaxe | Houten houweel | |
| recipes.shovel_wood.name | Wooden shovel | Houten schop | |
| recipes.sword_wood.name | Wooden sword | Houten zwaard | |
| recipes.dynamite.name | Dynamite | Dynamiet | |
| recipes.lantern.name | Lantern | Lantaarn | |
| recipes.torch.name | Torch | Fakkel | |
| recipes.ladder.name | Ladder | Ladder | |
| recipes.chest.name | Chest | Kist | |
| recipes.workbench.name | Workbench | Werkbank | |
| recipes.pickaxe_stone.name | Stone pickaxe | Stenen houweel | [AI added: new entry] |
| recipes.pickaxe_iron.name | Iron pickaxe | IJzeren houweel | [AI added: new entry] |
| recipes.pickaxe_diamond.name | Diamond pickaxe | Diamanten houweel | [AI added: new entry] |
| recipes.pickaxe_gold.name | Gold pickaxe | Gouden houweel | [AI added: new entry] |
| recipes.shovel_stone.name | Stone shovel | Stenen schop | [AI added: new entry] |
| recipes.shovel_iron.name | Iron shovel | IJzeren schop | [AI added: new entry] |
| recipes.shovel_diamond.name | Diamond shovel | Diamanten schop | [AI added: new entry] |
| recipes.shovel_gold.name | Gold shovel | Gouden schop | [AI added: new entry] |
| recipes.sword_diamond.name | Diamond sword | Diamanten zwaard | [AI added: new entry] |
| recipes.stone_block.name | Stone block | Steenblok | [AI added: new entry] |
| recipes.glass_block.name | Glass block | Glasblok | [AI added: new entry] |
| recipes.furnace.name | Furnace | Oven | [AI added: new entry] |
| recipes.bucket.name | Bucket | Emmer | [AI added: new entry] |
| recipes.bread.name | Bread | Brood | [AI added: new entry] |
| recipes.sugar.name | Sugar | Suiker | [AI added: new entry] |
| recipes.campfire.name | Campfire | Kampvuur | [AI added: new entry] |
| recipes.coal_block.name | Coal block | Steenkoolblok | [AI added: new entry] |
| recipes.bow.name | Bow | Boog | [AI added: new entry] |
| recipes.flint_and_steel.name | Flint and steel | Vuursteen en staal | [AI added: new entry] |
| recipes.chestplate_iron.name | Iron chestplate | IJzeren borstplaat | [AI added: new entry] |
| recipes.chestplate_leather.name | Leather chestplate | Leren borstplaat | [AI added: new entry] |
| recipes.helmet_diamond.name | Diamond helmet | Diamanten helm | [AI added: new entry] |
| recipes.helmet_gold.name | Gold helmet | Gouden helm | [AI added: new entry] |
| recipes.nether_portal.name | Portal | Portaal | [AI added: new entry] |

---

## Section 13: Other (creatures, chests, items, food)

| msgid | EN | NL (AI-corrected) | Notes |
|---|---|---|---|
| creatures.laser_penguin.name | Laser penguin | Laserpinguïn | |
| creatures.ghost.name | Ghost | Geest | |
| creatures.vampire.name | Vampire | Vampier | |
| creatures.bat_vampire.name | Vampire bat | Vampiervleermuis | |
| creatures.bat.name | Bat | Vleermuis | |
| creatures.cube_slime_large.name | Cube slime | Kubus-slijm | |
| creatures.cube_slime_medium.name | Cube slime | Kubus-slijm | |
| creatures.cube_slime_small.name | Cube slime | Kubus-slijm | |
| items.food_cooked_generic.name | Cooked food | Gekookt eten | |
| items.food_tom_yum.name | Tom Yum spicy seafood soup | Tom Yum pittige zeevruchtensoep | |
| items.food_roasted_fish.name | Roasted fish | Geroosterde vis | |
| items.food_bread.name | Bread | Brood | |
| items.food_pie.name | Pie | Taart | |
| items.strawberry.name | Strawberry | Aardbei | |
| chests.regular.name | Chest | Kist | |
| chests.bronze.name | Bronze chest | Bronzen kist | |
| chests.silver.name | Silver chest | Zilveren kist | |
| chests.gold.name | Gold chest | Gouden kist | |
| chests.diamond.name | Diamond chest | Diamanten kist | |
| chests.double_regular.name | Large chest | Grote kist | |
| items.key_bronze.name | Bronze key | Bronzen sleutel | |
| items.key_silver.name | Silver key | Zilveren sleutel | |
| items.key_gold.name | Gold key | Gouden sleutel | |
| items.key_diamond.name | Diamond key | Diamanten sleutel | [REVIEWER: truncation risk — 17 chars vs 11 EN] |

---

## Section 14: Profanity Wordlist Review

### Words Removed (false positives)

The following 10 words were removed from wordlist_nl.txt because they are common innocent Dutch/Flemish words that would block normal gaming chat:

| Word | Rationale |
|---|---|
| gore | Common adjective: "gore hekel" (strong dislike), "gore mist" (thick fog). Not profane in most contexts. |
| ras | Innocent in gaming/animal context (breed, race). Only slur when used as racial noun. |
| vent | Common noun: "kerel/vent" = guy/bloke. Completely innocent. |
| vieze | Common adjective for "dirty/gross". "Vieze plas" (dirty puddle) is not profane. |
| vuil | Common adjective: "vuile lucht" (dirty air/pollution). Too broad. |
| waardeloos | Common mild frustration: "wat een waardeloze zet". Not profane in Dutch. |
| prutsers | Mild: "bunglers/amateurs". Used in normal speech. |
| puffer | "Puffer jacket" or "one who puffs". No Dutch profanity meaning. |
| plasser | "One who pees". Very mild, used in children's books. Kid-safe. |
| idioot | Everyday word. "Wat een idioot" is common frustration, not profanity. |

### Typos Fixed

| Original | Corrected | Note |
|---|---|---|
| homseksueel | homosexueel | Spelling error |
| smerla | smeerlap | Common Flemish insult; "smerla" is not a real word |
| stomaak | (removed) | Not a real Dutch word; no clear intended replacement |

### Words Added (coverage gaps)

The following 7 entries were added to improve Flemish/Dutch profanity coverage:

| Word | Context |
|---|---|
| eikel | Very common Dutch/Flemish insult (literally "acorn", used as "jerk") |
| godver | Common Flemish oath (short form of godverdomme) |
| godverdomme | Very common Flemish oath, similar strength to "goddamn" |
| klere | Common Flemish profanity (disease-based, similar to kanker) |
| klerezooi | Compound: klere + zooi ("mess") — very common in Flemish gaming chat |
| tering | Common Dutch profanity (disease-based, tuberculosis) |
| tyfus | Dutch disease-based profanity (typhus), common in NL |

### Full Wordlist After Corrections

```
aars
anaal
anus
ballen
bitch
clitoris
cock
dikzak
doos
drol
drugshoer
eikel
etterbak
flikker
fokking
godver
godverdomme
hoer
homo
homofoob
homosexueel
huffter
hufter
jullie hoeren
kakhoofd
kanker
klere
klerezooi
klootzak
klote
kontgat
kut
kutkop
kutwijf
lul
lulhannes
mongool
moederneuker
nazi
neger
negers
neuk
neuken
pik
pikhoofd
piss
poep
poepkop
poepzak
prostituee
puta
reet
rotzak
schijt
schijtlul
slet
sloerie
smeerlap
snol
tering
tiet
tieten
trut
tyfus
wijf
zeikerd
zeiken
zeikneus
zuiger
```

**Total: 69 words (well under the 500-word T-05-P2 limit)**

---

## Section 15: Truncation Risk Flags

The following NL strings are more than 50% longer than their EN counterparts AND the EN string is more than 10 characters. These should be checked in-game to ensure they do not overflow UI bounds.

| msgid | EN (chars) | NL (chars) | Ratio | Recommendation |
|---|---|---|---|---|
| ui.camera.mode_fpv | 17 | 26 | 1.53 | "Eerste-persoon" would fit better |
| ui.camera.toggle_hint | 22 | 40 | 1.82 | "Druk V om te wisselen" if space is tight |
| ui.tool.dynamite_fuse_lit | 21 | 34 | 1.62 | Toast — likely OK if multiline |
| ui.workbench.open_prompt | 27 | 48 | 1.78 | Walk-up prompt — check in game |
| ui.chest.open_prompt | 24 | 41 | 1.71 | Walk-up prompt — check in game |
| ui.bed.sleep_prompt | 19 | 33 | 1.74 | Walk-up prompt — check in game |
| items.key_diamond.name | 11 | 17 | 1.55 | Item label — likely OK |
| ui.invite.error_not_verified | 34 | 52 | 1.53 | Error toast — check if wraps |
| ui.join.status_connecting | 11 | 17 | 1.55 | Status label — likely OK |
| ui.chat.unmute_player | 17 | 26 | 1.53 | Context menu item — check |
| ui.consent.skip | 12 | 19 | 1.58 | Button — check if truncated |
| ui.consent.resent_toast | 11 | 18 | 1.64 | Toast — likely OK |
| ui.legal.terms_link | 12 | 19 | 1.58 | Link — "Voorwaarden" if space tight |
| ui.legal.reack_title | 27 | 45 | 1.67 | Modal title — check if wraps correctly |
| ui.legal.reack_review | 12 | 20 | 1.67 | Button — consider "Bekijken" |
| ui.restricted.resend_link | 12 | 21 | 1.75 | Link — check in UI |
| ui.restricted.join_blocked_resend | 12 | 21 | 1.75 | Button — check in UI |
| ui.settings.terms_button | 12 | 19 | 1.58 | Settings button — check overflow |
| ui.settings.account_change_username | 15 | 23 | 1.53 | Settings label — likely OK |
| ui.avatar.preset_3 | 12 | 22 | 1.83 | Avatar preset name — check tile layout |
| ui.signin.back_to_title | 13 | 26 | 2.00 | Navigation link — check fits in header |
| ui.crop.harvest_prompt | 21 | 34 | 1.62 | Walk-up prompt — check in game |

**Note:** Single-word strings like "Plaatsen" (Place), "Springen" (Jump), "Herstellen" (Reset) are longer than EN due to Dutch morphology — this is normal and does not risk truncation in typical button/label contexts.
