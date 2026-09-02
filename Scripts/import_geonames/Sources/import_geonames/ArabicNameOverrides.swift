import Foundation

/// Arabic display names for cities GeoNames' own `alternateNamesV2` dump has
/// no usable `isolanguage == "ar"` row for. Applied over `ArabicNames.load`'s
/// result at the single lookup site in `main.swift`, so an override always
/// wins and the generated database stays the one source of truth for display
/// names — `City.displayName` keeps its single `nameArabic ?? name` fallback
/// rule, and `Resources/GeoNames/` is still never hand-edited.
///
/// **Scope rule.** Only cities that genuinely have an Arabic name. Every
/// entry below is in an Arabic-speaking country, where the Latin string
/// GeoNames carries is a transliteration of an Arabic toponym rather than the
/// endonym. A place with no Arabic exonym — Indonesian, Nigerian, Pakistani,
/// Turkish — is correctly left in Latin and must never be given an invented
/// Arabic spelling. The same reasoning covers the Dari/Pashto mistagging
/// `ArabicNames` documents for Afghan cities: the fix there is not to
/// transliterate them here.
///
/// **Confidence rule, and why this table is shorter than the gap.** 415
/// cities in Arabic-speaking countries currently carry no Arabic name; this
/// table covers 364 of them. The other 51 were left in Latin on purpose,
/// because an entry nobody is sure of is worse than a visible gap: a Latin
/// name reads as missing data, a wrong Arabic name reads as fact. Omitted, by
/// country: Somalia (23 — Somali endonyms in Latin script with no established
/// Arabic exonym, so the scope rule above applies to the whole country),
/// Morocco (11 — Amazigh toponyms whose conventional Arabic-script spelling
/// varies), Mauritania (7), Tunisia (4), Iraq (3 — two Kurdish, one whose
/// Latin string is too mangled to identify), Libya (2), Sudan (1, likewise
/// unidentifiable).
///
/// **Provenance, stated plainly.** Six entries are marked `attested
/// upstream`: GeoNames does carry an Arabic-script row for them, which
/// `ArabicNames` skips because the row is flagged historic, or is tagged as a
/// regional variety rather than `ar`. The rest are the standard Arabic
/// spelling of the named place, written here rather than taken from a
/// machine-readable source, because none exists for them — the full
/// `alternateNamesV2` dump was searched and holds no Arabic-script alternate
/// for any of them. That makes this table the one part of
/// `Resources/GeoNames/` not mechanically derived from upstream data, so **a
/// native-speaker review is still owed on it**, most of all on the Phase C
/// entries, where transliterating back from French-derived Latin is least
/// certain.
enum ArabicNameOverrides {
    static let table: [Int: String] = [
        // MARK: Phase A — Gulf, Iraq, and the Levant

        // United Arab Emirates (27)
        13118432: "الخليج التجاري", // Business Bay
        11048853: "مجمع دبي للاستثمار", // Dubai Investments Park
        8469668: "المدينة العالمية", // International City
        8476509: "المجاز", // Al Majaz
        13118424: "واحة دبي للسيليكون", // Dubai Silicon Oasis
        13118447: "مدينة محمد بن زايد", // Mohammed Bin Zayed City
        8541937: "دبي فستيفال سيتي", // Dubai Festival City
        6691091: "الكرامة", // Al Karama
        8469658: "الورقاء", // Al Warqaa
        13118438: "السجعة", // Al Sajaah
        290680: "طريف كلباء", // Ţarīf Kalbā
        13118421: "المطينة", // Al Muteena
        13118433: "القصيص 1", // Al Qusais 1
        291763: "كلباء", // Kalbā
        8541977: "مركز دبي المالي العالمي", // Dubai International Financial Centre
        292239: "دبا الحصن", // Dibba Al-Hisn
        13118431: "الفرجان", // Al Furjan
        8469811: "مدينة دبي للإنترنت", // Dubai Internet City
        6691096: "الوصل", // Al Wasl
        6691079: "الوحيدة", // Al Waheda
        13118437: "حلوان", // Halwan
        292991: "أبو هيل", // Abū Hayl
        13118422: "المزهر الأولى", // Al Mizhar First
        8469819: "الصفا", // Al Safa
        6691109: "قرية المعرفة", // Knowledge Village
        8469805: "مدينة دبي الرياضية", // Dubai Sports City
        13118448: "مدينة مصدر", // Masdar City

        // Iraq (6)
        13631407: "أبو الخصيب", // Abū al-Kahṣīb
        10303650: "سميل", // Simele
        387345: "أبو غرق", // Abu Gharaq, attested upstream
        91812: "سدة الهندية", // Saddat al Hindīyah, attested upstream
        99759: "الدجيل", // Ad Dujayl
        99439: "الفهود", // Nāḩiyat al Fuhūd

        // Jordan (2)
        6946409: "الكرك", // Karak City
        248803: "جديتا", // Judita, attested upstream

        // Lebanon (1)
        268743: "رأس بيروت", // Ra’s Bayrūt

        // Oman (4)
        286647: "صحم", // Şaḩam
        286293: "سفالة سمائل", // Sufālat Samā’il
        288721: "بدبد", // Bidbid
        288902: "بدية", // Badīyah

        // Palestine (5)
        284375: "بتير", // Battir
        281818: "شعفاط", // Shu‘fāţ
        284572: "عطروت", // ‘Aţārūt
        284446: "بلاطة", // Balāţah
        7870523: "شوكة الصوفي", // Shokat as-Sufi

        // Qatar (1)
        13512674: "لوسيل", // Lusail

        // Saudi Arabia (26)
        101760: "سلطانة", // Sulţānah
        101732: "عنيزة", // Unaizah
        110325: "الدوادمي", // Ad Dawādimī
        103369: "بيشة", // Qal‘at Bīshah
        12495725: "بارق", // Bariq
        103035: "رابغ", // Rābigh
        109253: "الليث", // Al Līth
        101313: "طريف", // Ţurayf
        104828: "مدينة الملك فيصل العسكرية", // King Faisal Military City
        109380: "الخفجي", // Al Khafjī
        102985: "رحيمة", // Raḩīmah
        101516: "تيماء", // Taymā’
        13631408: "حوطة بني تميم", // Ḥawṭah Banī Tamīm
        104716: "ليلى", // Laylá
        109306: "الخرمة", // Al Khurmah
        107744: "بدر حنين", // Badr Ḩunayn
        409682: "ثول", // Thuwal
        102451: "صامطة", // Şāmitah
        106102: "حقل", // Ḩaql
        108048: "السليل", // As Sulayyil
        101322: "تربة", // Turabah
        104578: "مهد الذهب", // Mahd adh Dhahab
        104923: "خليص", // Khulayş
        110059: "العقيق", // Al ‘Aqīq
        109915: "البطالية", // Al Baţţālīyah
        109059: "المنيزلة", // Al Munayzilah

        // Yemen (1)
        78751: "المخا", // Mocha, attested upstream

        // MARK: Phase B — Egypt

        // Egypt (41)
        353225: "مدينة نصر", // Madīnat an Naşr
        360890: "الخصوص", // Al Khuşūş
        353802: "كوم أمبو", // Kom Ombo
        353219: "مدينة السادس من أكتوبر", // 6th of October City
        355628: "إدكو", // Idkū, attested upstream
        361179: "الحوامدية", // Al Ḩawāmidīyah
        347907: "سنورس", // Sinnūris
        361473: "البدرشين", // Al Badrashayn
        362865: "أبو النمرس", // Abū an Numrus
        12640357: "الخارجة", // Al-Khārijah
        356000: "حوش عيسى", // Ḩawsh ‘Īsá
        360928: "الخانكة", // Al Khānkah
        352679: "مشتول السوق", // Mashtūl as Sūq
        358970: "بسيون", // Basyūn
        347542: "طامية", // Ţāmiyah
        353223: "مدينة السادات", // Madīnat as Sādāt
        355595: "إهناسيا المدينة", // Ihnāsyā al Madīnah
        362882: "أبو المطامير", // Abū al Maţāmīr
        355596: "إهناسية", // Ihnāsīyah
        358388: "دراو", // Darāw
        360464: "الواسطى", // Al Wāsiţah
        346201: "الزعفرانة", // Zaafarana
        361495: "العياط", // Al ‘Ayyāţ
        359541: "العين السخنة", // Al ‘Ayn as Sukhnah
        350207: "رأس غارب", // Ras Gharib
        347749: "سمسطا السلطاني", // Sumusţā as Sulţānī
        415561: "بدر", // Badr
        361405: "البصيلية بحري", // Al Başalīyah Baḩrī
        362028: "أبو صوير المحطة", // Abu Suweir-el-Mahatta
        433441: "بني سويف الجديدة", // Banī Suwayf al Jadīdah
        12640363: "الروضة", // Ar-Rawḍah
        354076: "كفر شكر", // Kafr Shukr
        13118928: "مدينة بني سويف الجديدة", // New Bani Sewif City
        421600: "بدر", // Badr
        374290: "حلايب", // Hala'ib
        359749: "أطفيح", // Aţfīḩ
        351766: "موط", // Mūţ
        12640381: "يوسف الصديق", // Yūsuf aṣ-Ṣiddīq
        434418: "الناصرية", // An Nāşirīyah
        12640359: "المنيا الجديدة", // Al-Minyā al-Jadīdah
        360159: "الرديسية قبلي", // Ar Radīsīyah Qiblī

        // MARK: Phase C — North and West Africa

        // Libya (12)
        2213618: "قصر بن غشير", // Qaşr Bin Ghashīr
        2210394: "تاجوراء", // Tājūrā’
        2219356: "السواني", // As Sawānī
        2210221: "ترهونة", // Tarhuna
        88562: "التاج", // At Tāj
        7602388: "شحات", // Shahhat
        2220153: "الأصابعة", // Al Aşābi‘ah
        2218983: "الزهراء", // Az Zahrā’
        2219591: "الناصرية", // An Nāşirīyah
        12687308: "وادي عتبة", // Wādī 'Utbah
        2219736: "القواسم", // Al Qawāsim
        2219471: "الرياينة", // Ar Rayāyinah

        // Morocco (127)
        2529013: "تمارة", // Temara
        10920963: "سلا الجديدة", // Salé Al Jadida
        10374934: "آيت ملول", // Ait Melloul
        2552615: "دار بوعزة", // Dar Bouazza
        2548880: "فاس البالي", // Fès al Bali
        2556272: "برشيد", // Berrechid
        2558470: "الخميسات", // Khemisset
        2545957: "إنزكان", // Inezgane
        2544001: "القصر الكبير", // Ksar El Kebir
        2530048: "تاوريرت", // Taourirt
        2554006: "بوسكورة", // Bouskoura
        2548830: "الفقيه بن صالح", // Al Fqih Ben Çalah
        10374906: "الدشيرة الجهادية", // Dchira El Jihadia
        2549979: "قلعة السراغنة", // El Kelaa des Srarhna
        2532945: "سيدي سليمان", // Sidi Slimane
        2548489: "جرسيف", // Guercif
        2539134: "أولاد تايمة", // Oulad Teïma
        2556018: "بن جرير", // Ben Guerir
        12718669: "ويسلان", // Ouislane
        2528659: "تيفلت", // Tiflet
        10375044: "القليعة", // Lqoliaa
        2537545: "صفرو", // Sefrou
        2548818: "الفنيدق", // Fnidek
        12718688: "سوق الأربعاء", // Souk El Arbaa
        2526488: "اليوسفية", // Youssoufia
        12718676: "لهراويين", // Lahraouyine
        2542987: "مرتيل", // Martil
        2560841: "عين حرودة", // Aïn Harrouda
        2532412: "سوق السبت أولاد النمة", // Souq Sebt Oulad Nemma
        2562055: "الصخيرات", // Skhirate
        2540810: "وزان", // Ouezzane
        2555519: "بن سليمان", // Benslimane
        2555882: "بني أنصار", // Beni Enzar
        2542898: "المضيق", // Mdiq
        2536074: "سيدي بنور", // Sidi Bennour
        2542227: "ميدلت", // Midelt
        2560939: "عين العودة", // Ain El Aouda
        2552292: "الدروة", // Ad Darwa
        2542013: "العروي", // Al Aaroui
        2544720: "قصبة تادلة", // Kasba Tadla
        12718663: "بجعد", // Bejaâd
        10797349: "سيدي الطيبي", // Sidi Taibi
        2545017: "جرادة", // Jerada
        2545069: "مريرت", // Mrirt
        2527915: "تنغير", // Tinghir
        2550806: "العيون", // El Aïoun
        2556657: "أزمور", // Azemmour
        2532394: "سوق أربعاء الغرب", // Souq Larb’a al Gharb
        2526452: "زاكورة", // Zagora
        2559217: "آيت أورير", // Ait Ourir
        2556570: "أزيلال", // Azilal
        2532822: "سيدي يحيى الغرب", // Sidi Yahia El Gharb
        2530155: "تاونات", // Taounate
        2553751: "بوزنيقة", // Bouznika
        12718675: "حد السوالم", // Had Soualem
        2550898: "إمزورن", // Imzouren
        2526435: "زايو", // Zaïo
        2557500: "أورير", // Aourir
        2550252: "الحاجب", // El Hajeb
        2537538: "زغنغان", // Zeghanghane
        2556076: "بن أحمد", // Ben Ahmed
        2527271: "تيط مليل", // Tit Mellil
        2542866: "مشرع بلقصيري", // Mechraa Bel Ksiri
        12718681: "العطاوية", // Laâttaouia
        12718684: "سيدي سليمان الشراعة", // Sidi Slimane Echcharaa
        2552317: "دمنات", // Demnate
        2549356: "أرفود", // Arfoud
        2555157: "بوعرفة", // Bouarfa
        2532421: "سوق الاثنين جرف الملحة", // Souk et Tnine Jorf el Mellah
        2542768: "المهدية", // Mehdya
        2560774: "عين تاوجطات", // Aïn Taoujdat
        8299790: "تامسنا", // Tamesna
        2553303: "شيشاوة", // Chichaoua
        2531480: "تاهلة", // Tahla
        11025266: "سبع عيون", // Sabaa Aiyoun
        2538059: "الريش", // Rich
        2542147: "ميسور", // Missour
        2526359: "زاوية الشيخ", // Zawyat ech Cheïkh
        2535530: "بوقنادل", // Bouknadel
        12718687: "عين العتيق", // Aïn Attig
        8504943: "تامنصورت", // Tamansourt
        2553382: "الشماعية", // Echemmaia Est
        2540180: "أولاد برحيل", // Oulad Barhil
        2555342: "بئر الجديد", // Bir Jdid
        2540207: "أولاد عياد", // Oulad Ayad
        2541210: "زاوية النواصر", // Zawyat an Nwaçer
        2537368: "كزناية", // Gueznaia
        2542826: "مديونة", // Mediouna
        12718664: "مولاي علي الشريف", // Moulay Ali Cherif
        2537469: "سلوان", // Selouane
        2571932: "أزلا", // Azla
        2546128: "إيمي نتانوت", // Imi-n-Tanout
        2533182: "سيدي رحال", // Sidi Rahal
        2548878: "فاس الجديد", // New Fes
        2538401: "رأس الماء", // Ras el Ma
        2526239: "ستي فاطمة", // Setti Fatma
        2549750: "القصيبة", // El Ksiba
        2558428: "المنصورية", // El Mansouria
        2561124: "أحفير", // Ahfir
        2550547: "البروج", // Al Brouj
        2546028: "إيموزار كندر", // Imouzzer Kandar
        2551147: "دوار تولال", // Douar Toulal
        2544821: "قرية با محمد", // Karia Ba Mohamed
        2538027: "الريصاني", // Reçani
        2529362: "طاطا", // Tata
        10958491: "بني بوعياش", // Bni Bouayach
        2558436: "بني يخلف", // Beni Yakhlef
        2557533: "أولوز", // Aoulouz
        2557019: "أسني", // Asni
        2549981: "قلعة مكونة", // Kelaat Mgouna
        2596460: "رباط الخير", // Ribat Al Khayr
        2530704: "تمللت", // Tamallalt
        2538573: "أوطاط الحاج", // Outat Oulad Al Haj
        2560922: "عين بني مطهر", // Aïn Beni Mathar
        12718686: "مرس الخير", // Mers El Kheir
        2536392: "سيدي علال البحراوي", // Sidi Allal El Bahraoui
        2543667: "لالة ميمونة", // Lalla Mimouna
        2554281: "بومية", // Boumia
        2550162: "الهرهورة", // El Harhoura
        2542230: "ميضار", // Midar
        2550985: "دريوش", // Driouch
        2556996: "أسا", // Assa
        2558052: "أمزميز", // Amizmiz
        2555504: "بن الطيب", // Ben Taieb
        2554594: "بويزكارن", // Bou Izakarn
        2539139: "أولاد الطيب", // Oulad Tayeb
        2561290: "أكلموس", // Aguelmous

        // Mauritania (3)
        2380670: "بوتلميت", // Boutilimitt
        2380066: "العيون", // El ’Ayoûn
        2378160: "مقطع لحجار", // Magṭa‘ Laḥjar

        // Sudan (41)
        364103: "ود مدني", // Wad Medani, attested upstream
        379302: "الجنينة", // El Geneina Fort
        379149: "المناقل", // Al Manāqil
        377108: "برام", // Burām
        376450: "الدلنج", // Dilling
        13132452: "أردمتا", // 'Ārdamatā
        372773: "كاس", // Kas
        370181: "مليط", // Mellit
        13132453: "شعيرية", // Sh'īarīah
        379427: "الحصاحيصا", // Al Hasaheisa
        380757: "أبو جبيهة", // Abu Jibeha
        373198: "كبكابية", // Kabkābīyah
        365641: "تلس", // Tullus
        379102: "المجلد", // Al Mijlad
        366846: "سنكات", // Sinkat
        371745: "كتم", // Kutum
        378271: "السوكي", // As Sūkī
        377962: "بابنوسة", // Babanūsah
        366426: "تندلتي", // Tandaltī
        13132450: "الفاو", // Al-Fāw
        379416: "الحواتة", // Al Ḩawātah
        370838: "ميورنو", // Maiurno
        367972: "رفاعة", // Rufā‘a
        13132451: "القطينة", // Al-Quṭaynah
        372386: "كنانة", // Kināna
        377690: "بربر", // Berber
        379535: "الفولة", // Al Fūlah
        13132448: "الدندر", // Ad-Dindar
        368230: "رهد البردي", // Rahad al Bardi
        380348: "أبو زبد", // Abū Zabad
        374866: "غبيش", // Ghubaysh
        12493849: "الجزيرة أبا", // Al Jazeera Aba
        13132449: "الفشقة", // Al-Fashaqah
        364621: "أم شوكة", // Umm Shawkah
        376332: "دوكة", // Doka
        371870: "كريمة", // Kuraymah
        379630: "البوقة", // El Bauga
        379014: "القطينة", // Al Qiţena
        379406: "الهلالية", // Al Hilāliyya
        377724: "بارا", // Bārah
        380151: "الدندر", // Ad Dindar

        // Tunisia (67)
        2473164: "سيدي حسين", // Sīdī Ḥusayn
        2467243: "ساقية الدائر", // Sakiet ed Daier
        11204413: "المروج", // El Mourouj
        2467242: "ساقية الزيت", // Sakiet ez Zit
        7870240: "رواد", // Rawad
        2473540: "المرسى", // La Marsa
        2473626: "الكرم", // Le Kram
        13132712: "التضامن", // Ettadhamen
        13132711: "دوار هيشر", // Douar Hicher
        2473499: "المحمدية", // La Mohammedia
        2464168: "وادي الليل", // Oued Lill
        2467920: "قربة", // Korba
        2467246: "سكانس", // Skanes
        2473483: "القلعة الكبرى", // Kelaa Kebira
        2473496: "المكنين", // Moknine
        2581754: "الديوانة", // Douane
        13132710: "المنيهلة", // Mnihla
        2468106: "قصر هلال", // Ksar Hellal
        2471055: "فوشانة", // Fouchana
        2464953: "سليمان", // Soliman
        2473639: "الجديدة", // Jedeïda
        2472833: "زويلة", // Zouila
        2473481: "القلعة الصغرى", // Kalaa Srira
        2473835: "العين", // El Ain
        2470579: "حمام سوسة", // Hammam Sousse
        2471637: "دار شعبان", // Dar Chabanne
        2473470: "قرمدة", // Gremda
        12037507: "بومهل البساتين", // Boumhel El Bassatine
        2469250: "منزل تميم", // Menzel Temime
        2586370: "الزهراء", // Ez Zahra
        2471287: "دوز", // Douz
        2473466: "القصر", // El Ksar
        2466698: "سيدي عابد", // Sidi Abid
        2469088: "ماطر", // Mateur
        2468925: "ميدون", // Midoun
        6692494: "برج السدرية", // Borj Cedria
        2467732: "رأس الجبل", // Rass el Djebel
        2467898: "قرمبالية", // Grombalia
        2473913: "أكودة", // Akouda
        12037388: "دندان", // Den Den
        2584420: "دار الحاج الطيب", // Dar el Haj Taïeb
        2469230: "مقرين", // Mégrine
        2468245: "قرطاج", // Carthage
        2464804: "تاكلسة", // Takelsa
        2469386: "مجاز الباب", // Medjez el Bab
        7870039: "وردانين", // Ouerdanine
        2473489: "المرناقية", // La Mornaghia
        2468561: "نفطة", // Nefta
        2473229: "الشابة", // Chebba
        2472722: "بني خيار", // Beni Khiar
        2473654: "الجم", // El Jem
        2473190: "الساحلين", // Sahline
        2464378: "أم العرائس", // Moularès
        2464522: "تينجة", // Tinja
        2463941: "زاوية سوسة", // Zaouiet Sousse
        2473531: "المطوية", // Métouia
        2464809: "تاجروين", // Tajerouine
        2469262: "منزل بوزلفة", // Mennzel Bou Zelfa
        2473876: "العالية", // El Alia
        2473420: "وردانين", // Ouardenine
        2464795: "تالة", // Thala
        2468329: "قلعة الأندلس", // Galaat el Andeless
        11204573: "الزهور", // Ezzouhour
        13132709: "شنني نحال", // Chenini Nahal
        2464860: "تبلبو", // Teboulbou
        13132708: "بمبلة والمنارة", // Bembla et Mnara
        2472724: "بني خلاد", // Beni Khalled
    ]
}
