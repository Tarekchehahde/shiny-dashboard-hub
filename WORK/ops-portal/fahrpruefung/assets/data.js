/* DEKRA Klasse B — Stichworte für den Prüfer (Copilot Erfurt) */
window.FAHR = {
  meta: {
    title: "DEKRA — Praktische Prüfung",
    subtitle: "Copilot Erfurt · Stichworte für den Prüfer",
    school: "Copilot Fahrschule Erfurt",
    address: "Johannesstraße 167",
    classLabel: "Klasse B · PKW"
  },
  rules: [
    { label: "Regel", text: "Zeigen + sagen" },
    { label: "Stil", text: "kurz — keine Romane" },
    { label: "Unsicher", text: "„Ich prüfe das jetzt…“ und machen" },
    { label: "Fahrt", text: "Spiegel → Blinker → Schulterblick → Handeln" }
  ],
  /* HU-Prüfplakette Farben (6-Jahres-Zyklus) */
  plaketteColors: [
    { year: 2025, color: "#e85d04", name: "Orange", hexYear: "25" },
    { year: 2026, color: "#2563eb", name: "Blau", hexYear: "26" },
    { year: 2027, color: "#eab308", name: "Gelb", hexYear: "27" },
    { year: 2028, color: "#92400e", name: "Braun", hexYear: "28" },
    { year: 2029, color: "#ec4899", name: "Rosa", hexYear: "29" },
    { year: 2030, color: "#16a34a", name: "Grün", hexYear: "30" }
  ],
  sections: [
    {
      id: "reifen",
      num: "01",
      title: "Reifen",
      summary: "Profil, Beschädigung, Luftdruck",
      points: [
        { de: "Profiltiefe", tip: "mind. 1,6 mm — Verschleißanzeiger beachten", kw: true },
        { de: "Beschädigung", tip: "Risse, Beulen, Fremdkörper prüfen", kw: true },
        { de: "Luftdruck", tip: "Manometer; Sollwert bei uns neben der Türangel (Türholm)", kw: true },
        { de: "Profilmesser", tip: "in den Längsrillen messen", kw: true },
        { de: "Verschleißanzeiger", tip: "markiert die Mindesttiefe", kw: true },
        { de: "Solldruck", tip: "Aufkleber neben der Türangel / am Türscharnier — nicht am Tankdeckel", kw: true }
      ],
      say: "mind. 1,6 mm, Beschädigung, Druck — Sollwert an der Türangel."
    },
    {
      id: "reflektoren",
      num: "02",
      title: "Rückstrahler · Strahler",
      summary: "Prüfer sagt oft „Strahler“ — zeigen + sagen",
      points: [
        { de: "Strahler", tip: "meint Rückstrahler (Reflektoren) — nicht die Scheinwerfer", kw: true },
        { de: "Funktion", tip: "leuchten nicht selbst — werfen Licht anderer Fahrzeuge zurück", kw: true },
        { de: "Hinten", tip: "rot, vorhanden, sauber, unbeschädigt — zeigen + sagen", kw: true },
        { de: "Farbe", tip: "hinten rot · Seite gelb/orange · vorn weiß (falls vorhanden)", kw: true },
        { de: "Form", tip: "Pkw nicht dreieckig — Dreieck = Anhänger", kw: true },
        { de: "Lage", tip: "am Heck, oft in der Rückleuchte — mit Finger zeigen", kw: true }
      ],
      say: "Rückstrahler hinten — rot, vorhanden, sauber. Leuchten nicht selbst."
    },
    {
      id: "leuchten",
      num: "03",
      title: "Kontrollleuchten",
      summary: "Farben im Armaturenbrett",
      points: [
        { de: "ROT", tip: "STOP / Gefahr — anhalten. Handbremse, Öl, Bremse, Kühlmittel, Batterie", kw: true, dash: "red" },
        { de: "GELB", tip: "bald prüfen — Fahrt noch möglich. ABS, Motor, ESP, Reifendruck", kw: true, dash: "yellow" },
        { de: "BLAU", tip: "Fernlicht an", kw: true, dash: "blue" },
        { de: "GRÜN", tip: "Blinker / Licht ok", kw: true, dash: "green" }
      ],
      say: "Rot = STOP. Gelb = bald prüfen. Blau = Fernlicht. Grün = Blinker."
    },
    {
      id: "motorraum",
      num: "04",
      title: "Motorraum",
      summary: "Motor aus · zeigen + Name",
      points: [
        { de: "Motor aus!", tip: "vor dem Öffnen immer Motor aus", kw: true },
        { de: "Öl", tip: "Peilstab: raus → wischen → rein → MIN/MAX", kw: true },
        { de: "Kühlmittel", tip: "Behälter zeigen und nennen", kw: true },
        { de: "Bremsflüssigkeit", tip: "Behälter zeigen und nennen", kw: true },
        { de: "Waschwasser", tip: "Behälter zeigen und nennen", kw: true },
        { de: "Batterie", tip: "Lage zeigen", kw: true },
        { de: "Sicherungen", tip: "Sicherungskasten zeigen", kw: true }
      ],
      say: "wischen → rein → MIN/MAX."
    },
    {
      id: "sitz",
      num: "05",
      title: "Sitz · Spiegel · Gurt",
      summary: "Einstellen vor dem Start",
      points: [
        { de: "Sitz", tip: "Pedale voll durchtreten können", kw: true },
        { de: "Handgelenke", tip: "auf dem Lenkrad oben ablegen können", kw: true },
        { de: "Kopfstütze", tip: "Ohrhöhe", kw: true },
        { de: "Innenspiegel", tip: "Heckscheibe sichtbar", kw: true },
        { de: "Außenspiegel", tip: "Seite + Fahrbahn; Schulterblick", kw: true },
        { de: "Startfolge", tip: "Sitz → Spiegel → Gurt → Bremse → Gang → Handbremse", kw: true }
      ],
      say: "Sitz → Spiegel → Gurt → Bremse → Gang → Handbremse."
    },
    {
      id: "beleuchtung",
      num: "06",
      title: "Beleuchtung",
      summary: "Zündung an → schalten → zeigen + sagen",
      points: [
        { de: "Standlicht", tip: "vorn + hinten", kw: true },
        { de: "Abblendlicht", tip: "normales Fahren — vorn + hinten", kw: true },
        { de: "Fernlicht", tip: "blaue Leuchte im Cockpit", kw: true },
        { de: "Lichthupe", tip: "kurz blenden / signalisieren", kw: true },
        { de: "Blinker", tip: "links / rechts zeigen", kw: true },
        { de: "Warnblinker", tip: "beide Seiten gleichzeitig", kw: true },
        { de: "Bremslicht", tip: "hinten rot", kw: true },
        { de: "Rückfahrlicht", tip: "weiß hinten", kw: true },
        { de: "Nebelschluss", tip: "nur bei Sicht < 50 m", kw: true }
      ],
      say: "Abblendlicht — vorn + hinten."
    },
    {
      id: "nebel",
      num: "07",
      title: "Nebel",
      summary: "Wann Nebellicht erlaubt ist",
      points: [
        { de: "Nebelschluss", tip: "nur wenn Sichtweite < 50 m — sonst aus", kw: true },
        { de: "Nebelscheinwerfer", tip: "bei schlechter Sicht + Abblendlicht", kw: true }
      ],
      say: "nur unter 50 m."
    },
    {
      id: "bremse",
      num: "08",
      title: "Bremse & Lenkung",
      summary: "Fußbremse, Handbremse, Lenkhilfe",
      points: [
        { de: "Fußbremse", tip: "Pedal muss fest wirken", kw: true },
        { de: "Handbremse", tip: "rote Leuchte an; vor Start lösen", kw: true },
        { de: "Lenkspiel", tip: "möglichst gering", kw: true },
        { de: "Lenkhilfe", tip: "Lenkung fühlt sich leicht an", kw: true },
        { de: "Lenkradschloss", tip: "gesperrt wenn Schlüssel abgezogen", kw: true }
      ],
      say: "rote Leuchte — vor Start lösen."
    },
    {
      id: "wischer",
      num: "09",
      title: "Wischer · Hupe · Ende",
      summary: "Wischerstufen und Aussteigen",
      points: [
        { de: "Wischer", tip: "aus · Intervall · normal · schnell", kw: true },
        { de: "Waschwasser", tip: "Hebel → Wasser + Wischer", kw: true },
        { de: "Hupe", tip: "kurz zeigen / prüfen", kw: true },
        { de: "Fahrtende", tip: "parken → Gang + Handbremse → Motor aus", kw: true },
        { de: "Aussteigen", tip: "Spiegel + Schulterblick vor Türöffnen", kw: true }
      ],
      say: "Spiegel + Schulter — dann Tür."
    },
    {
      id: "plakette",
      num: "10",
      title: "Prüfplakette (HU)",
      summary: "Kreis ablesen · Frist bis Monatsende",
      points: [
        { de: "Lage", tip: "runde Plakette auf dem hinteren Kennzeichen", kw: true },
        { de: "Jahr", tip: "Zahl in der Mitte = Jahr der nächsten HU (z. B. 26 → 2026)", kw: true },
        { de: "Monat", tip: "Zahl oben = Fälligkeitsmonat — HU spätestens bis zum letzten Tag dieses Monats", kw: true },
        { de: "September?", tip: "nicht Anfang/Mitte — der ganze Monat gilt; Frist = 30. September (Monatsende)", kw: true },
        { de: "Farbe", tip: "Farbe kodiert ebenfalls das Jahr (6-Jahres-Zyklus)", kw: true },
        { de: "2 Monate", tip: "kein Extra-Zeitfenster für pünktliche HU — erst bei Überziehung: Bußgeld ab > 2 Monaten", kw: true },
        { de: "Überziehung", tip: "≤2 Mon. oft ohne Verwarnungsgeld · >2–4 Mon. 15 € · >4–8 Mon. 25 € · >8 Mon. 60 € + 1 Punkt", kw: true },
        { de: "Erweiterte HU", tip: "bei > 2 Monaten Überziehung: Ergänzungsuntersuchung (+ ca. 20 % Gebühr)", kw: true }
      ],
      say: "Oben = Monat (bis Monatsende), Mitte = Jahr."
    },
    {
      id: "fahrt",
      num: "11",
      title: "Während der Fahrt",
      summary: "Kreisverkehr, Vorfahrt, Autobahn",
      points: [
        { de: "Routine", tip: "Spiegel → Blinker → Schulterblick", kw: true },
        { de: "Kreisverkehr", tip: "warten → ohne Blinker rein → rechts raus blinken", kw: true },
        { de: "rechts vor links", tip: "Schilder beachten", kw: true },
        { de: "Fußgängerüberweg", tip: "früh bremsen, Blickkontakt", kw: true },
        { de: "Autobahn rein", tip: "Beschleunigungsspur nutzen — Tempo anpassen, dann einfädeln", kw: true },
        { de: "Autobahn raus", tip: "500 m rechte Spur · 3-Strich-Bake blinken · erst auf dem Verzögerungsstreifen bremsen", kw: true }
      ],
      say: "Spiegel → Blinker → Schulterblick."
    },
    {
      id: "grundfahrt",
      num: "12",
      title: "Grundfahraufgaben",
      summary: "3 von 5 werden geprüft",
      points: [
        { de: "Längseinparken", tip: "parallel zur Fahrbahn", kw: true },
        { de: "Quereinparken", tip: "seitlich / Box", kw: true },
        { de: "Umkehren", tip: "Wenden / Umkehren", kw: true },
        { de: "Rückwärts Einfahrt", tip: "rückwärts in Einfahrt", kw: true },
        { de: "Gefahrbremsung", tip: "kräftig und kontrolliert anhalten", kw: true }
      ],
      say: "3 von 5 — ruhig und klar ausführen."
    },
    {
      id: "safe",
      num: "13",
      title: "Safe Answers",
      summary: "Kurzantworten auswendig",
      points: [
        { de: "Reifen", tip: "mind. 1,6 mm, Beschädigung, Druck — Sollwert Türangel.", kw: true },
        { de: "Strahler", tip: "Rückstrahler hinten — rot, vorhanden, sauber. Leuchten nicht selbst.", kw: true },
        { de: "Leuchten", tip: "Rot = STOP. Gelb = bald prüfen. Blau = Fernlicht. Grün = Blinker.", kw: true },
        { de: "Öl", tip: "wischen → rein → MIN/MAX.", kw: true },
        { de: "Licht", tip: "Abblendlicht — vorn + hinten.", kw: true },
        { de: "Prüfplakette", tip: "Oben = Monat (bis Monatsende), Mitte = Jahr.", kw: true },
        { de: "Nebel", tip: "nur unter 50 m.", kw: true },
        { de: "Handbremse", tip: "rote Leuchte — vor Start lösen.", kw: true },
        { de: "Rot", tip: "Gefahr — ich halte an.", kw: true }
      ],
      say: "kurz antworten — keine Romane."
    }
  ]
};

/** Flashcards derived from sections */
window.FAHR.buildCards = function () {
  const cards = [];
  for (const s of FAHR.sections) {
    for (const p of s.points) {
      cards.push({
        id: s.id + ":" + p.de,
        section: s.title,
        sectionId: s.id,
        front: p.de,
        back: p.tip,
        kw: !!p.kw
      });
    }
    if (s.say) {
      cards.push({
        id: s.id + ":say",
        section: s.title,
        sectionId: s.id,
        front: "Safe Answer — " + s.title,
        back: s.say,
        kw: true,
        safe: true
      });
    }
  }
  return cards;
};

/**
 * Curated quiz items with explicit wrong answers (so choices stay distinct
 * and the correct option is truly randomized among A–D).
 */
window.FAHR.buildQuiz = function () {
  const items = [
    {
      section: "Reifen",
      q: "Was prüfst du am Reifen?",
      correct: "Profiltiefe, Beschädigung, Luftdruck",
      wrong: [
        "Nur den Felgendurchmesser",
        "Nur die Reifenmarke",
        "Nur den Reserverad-Ort"
      ]
    },
    {
      section: "Reifen",
      q: "Mindest-Profiltiefe?",
      correct: "mind. 1,6 mm",
      wrong: ["mind. 0,5 mm", "mind. 3,0 mm", "mind. 5,0 mm"]
    },
    {
      section: "Reifen",
      q: "Wo steht bei uns der Solldruck?",
      correct: "neben der Türangel / am Türholm",
      wrong: [
        "nur am Tankdeckel",
        "nur im Handschuhfach",
        "nur auf dem Ventil"
      ]
    },
    {
      section: "Motorraum",
      q: "Öl prüfen — richtige Reihenfolge?",
      correct: "raus → wischen → rein → MIN/MAX",
      wrong: [
        "nur rein und ablesen",
        "Motor heiß vollgas prüfen",
        "nur den Deckel öffnen"
      ]
    },
    {
      section: "Beleuchtung",
      q: "Abblendlicht — was sagst du?",
      correct: "vorn + hinten",
      wrong: ["nur vorn", "nur hinten weiß", "nur die blaue Leuchte"]
    },
    {
      section: "Beleuchtung",
      q: "Fernlicht — Kontrollleuchte?",
      correct: "blaue Leuchte",
      wrong: ["rote Leuchte", "grüne Leuchte", "gelbe Leuchte"]
    },
    {
      section: "Rückstrahler",
      q: "Prüfer sagt „Strahler“ — was meint er?",
      correct: "Rückstrahler (Reflektoren), nicht die Scheinwerfer",
      wrong: [
        "nur das Fernlicht",
        "nur die Nebelschlussleuchte",
        "nur die Hupe"
      ]
    },
    {
      section: "Rückstrahler",
      q: "Rückstrahler / Strahler — Safe Answer?",
      correct: "hinten rot, vorhanden, sauber — leuchten nicht selbst",
      wrong: [
        "weiß, nur bei Nebel",
        "gelb, nur bei Standlicht",
        "blau, nur auf Autobahn"
      ]
    },
    {
      section: "Rückstrahler",
      q: "Welche Farbe haben die Rückstrahler hinten?",
      correct: "rot",
      wrong: ["weiß", "gelb", "grün"]
    },
    {
      section: "Rückstrahler",
      q: "Dreieckige Rückstrahler — wo erlaubt?",
      correct: "am Anhänger, nicht am Pkw",
      wrong: [
        "nur am Pkw hinten",
        "nur vorn am Motorrad",
        "nur auf der Autobahn"
      ]
    },
    {
      section: "Fahrt",
      q: "Autobahn-Ausfahrt — wann bremsen?",
      correct: "erst auf dem Verzögerungsstreifen, nicht auf der Autobahn",
      wrong: [
        "am 1000-m-Schild hart bremsen",
        "an der 3-Strich-Bake auf der Autobahn",
        "erst in der Ausfahrtkurve"
      ]
    },
    {
      section: "Nebel",
      q: "Nebelschlussleuchte — wann?",
      correct: "nur unter 50 m Sicht",
      wrong: [
        "immer bei Regen",
        "immer auf der Autobahn",
        "nur bei Fernlicht"
      ]
    },
    {
      section: "Bremse",
      q: "Handbremse vor Start?",
      correct: "rote Leuchte — vor Start lösen",
      wrong: [
        "immer angezogen lassen",
        "nur im Neutral lösen",
        "Leuchte darf rot bleiben"
      ]
    },
    {
      section: "Kontrollleuchten",
      q: "Rote Kontrollleuchte bedeutet?",
      correct: "STOP / Gefahr — ich halte an",
      wrong: [
        "weiterfahren und später prüfen",
        "nur Fernlicht",
        "nur Blinker ok"
      ]
    },
    {
      section: "Kontrollleuchten",
      q: "Farben im Armaturenbrett — Safe Answer?",
      correct: "Rot = STOP. Gelb = bald prüfen. Blau = Fernlicht. Grün = Blinker.",
      wrong: [
        "Rot = nur Blinker, Grün = STOP",
        "Blau = Gefahr, Gelb = Fernlicht",
        "Alle Farben bedeuten anhalten"
      ]
    },
    {
      section: "Kontrollleuchten",
      q: "Gelbe Kontrollleuchte bedeutet?",
      correct: "bald prüfen — Fahrt noch möglich",
      wrong: [
        "sofort anhalten wie bei Rot",
        "Fernlicht an",
        "nur Handbremse"
      ]
    },
    {
      section: "Prüfplakette",
      q: "Prüfplakette — wo ist der Monat?",
      correct: "oben (12-Uhr-Position)",
      wrong: [
        "nur in der Mitte",
        "nur die Farbe unten",
        "nur auf dem Fahrzeugschein vorn"
      ]
    },
    {
      section: "Prüfplakette",
      q: "September auf der Plakette — bis wann HU?",
      correct: "spätestens bis Monatsende (30. September)",
      wrong: [
        "nur am 1. September",
        "nur in der Monatsmitte",
        "automatisch + 2 Monate Frist"
      ]
    },
    {
      section: "Prüfplakette",
      q: "Was bedeuten die „2 Monate“ bei der HU?",
      correct: "Bußgeld / erweiterte HU erst ab Überziehung > 2 Monate",
      wrong: [
        "du darfst immer 2 Monate früher kommen",
        "HU nur alle 2 Monate",
        "Plakette gilt nur 2 Monate"
      ]
    },
    {
      section: "Prüfplakette",
      q: "Prüfplakette — wo ist das Jahr?",
      correct: "Zahl in der Mitte (+ Farbe)",
      wrong: [
        "nur die Zahl ganz unten",
        "nur am vorderen Kennzeichen",
        "nur im Tankdeckel"
      ]
    },
    {
      section: "Prüfplakette",
      q: "Safe Answer zur Prüfplakette?",
      correct: "Oben = Monat (bis Monatsende), Mitte = Jahr",
      wrong: [
        "Oben = Jahr, Mitte = Monat",
        "Farbe = Monat, Mitte = Marke",
        "Nur die Farbe zählt, Zahlen egal"
      ]
    },
    {
      section: "Prüfplakette",
      q: "HU > 8 Monate überzogen — Strafe?",
      correct: "60 € und 1 Punkt in Flensburg",
      wrong: [
        "nur mündliche Verwarnung",
        "15 € ohne Punkt",
        "Führerschein weg sofort"
      ]
    },
    {
      section: "Fahrt",
      q: "Grundroutine beim Abbiegen?",
      correct: "Spiegel → Blinker → Schulterblick",
      wrong: [
        "nur blinken",
        "Hupe → Gas → Lenken",
        "nur Schulterblick ohne Spiegel"
      ]
    },
    {
      section: "Kreisverkehr",
      q: "Kreisverkehr — Blinken?",
      correct: "ohne Blinker rein, rechts raus blinken",
      wrong: [
        "immer links rein blinken",
        "nie blinken",
        "Warnblinker im Kreis"
      ]
    }
  ];
  return items;
};
