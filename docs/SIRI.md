# Nina – Siri, Shortcuts, controls and the coach widget

Everything here works without opening Nina first. Nothing needs setting up: Siri knows the
phrases as soon as Nina is installed, and the controls and widgets are in the usual galleries.

## Say it to Siri

Siri understands these in English and in German (whatever language Siri speaks on the device).
"Nina" is always part of the phrase.

| What | English | German |
|---|---|---|
| Log food (the same text as quick add: "2 eggs and a toast") | "Log food in Nina" | "Essen in Nina eintragen" |
| A glass of water (your glass size) | "Log water in Nina" | "Wasser in Nina eintragen" |
| What's left today | "How many calories are left in Nina" | "Wie viele Kalorien habe ich noch in Nina" |
| Weigh-in in kg | "Log weight in Nina" | "Gewicht in Nina eintragen" |
| Today's day type | "Today is a Tennis day in Nina" | "Heute ist ein Tennistag in Nina" |
| Tick off a daily check | "Mark Creatine done in Nina" | "Creatine in Nina abhaken" |

- **Day types and checks** are the ones in your plan (My Plan), said with the name they have there.
  Siri learns the names when Nina opens after a change; a day type also works as "Tennis day" or
  "Tennistag". "Back to Schedule" lets the plan's schedule pick the day type again.
- **Weight**: Siri asks "How much do you weigh, in kilograms?" – say "74,2" or "74.2". It goes
  through the same check as the weigh-in sheet: more than 3 kg from your 7-day average asks
  "Save it anyway?", and something like "742" offers 74.2 kg instead. Outside 25–300 kg nothing is
  saved.
- **What Siri answers** stays English (Nina's texts are English); only the phrases you say have a
  German version.
- When Nina is open, a Siri request shows the usual message with **Undo**.

## Shortcuts and the Action button

All of the above are actions in the Shortcuts app (search "Nina"), plus three that open Nina:
**Open Log Food**, **Open Weigh-In** and **Add a Glass of Water**. On an iPhone with an Action
button: Settings → Action Button → Controls → Nina → *Log Food*, *Weigh In* or *Add Water* – or
choose Shortcut → Nina → *Log Water* to add a glass without opening the app.

## Controls (Control Center and Lock Screen, iPhone)

Open Control Center → tap **+** (top left) → **Add a Control** → search "Nina":

| Control | What it does |
|---|---|
| Log Food | Opens Nina at Log Food for the meal that fits the time |
| Weigh In | Opens Nina at the weigh-in |
| Add Water | Opens Nina and adds a glass of water (Undo in the message) |

On the Lock Screen: touch and hold it → **Customize** → Lock Screen → tap one of the two buttons
at the bottom → choose a Nina control.

## The coach widget (iPhone)

Touch and hold the Home Screen → **Edit** → **Add Widget** → Nina → **Coach** (small or medium),
or on the Lock Screen → Customize → the widget row → Nina → Coach.

It shows:
- the **day type** with today's calories ("🏋️ Gym · 2,500 kcal"),
- the **7-day average** and the **weekly rate** with the status words ("+0.15 kg/wk · In range",
  green, orange or red like in the app),
- **Weigh in** until the morning cutoff of your plan, as long as there's no morning weigh-in,
- the **next measurement** ("Waist · today", "Full measurement · Thu"),
- the **checks** still open today (the medium widget lists them; a tap ticks one off in Nina).

A tap opens the right place: the weigh-in, the measurement, the check, or the Body page. Without a
plan the widget offers "Set up your plan in Nina". It changes to the next day by itself at the
time your day starts (Settings → Day starts at).

**Privacy**: the widget's numbers come from a small file on this iPhone only (never in iCloud and
not in device backups), because the 7-day average can include weigh-ins from Apple Health. The
weight is hidden on the Lock Screen while the iPhone is locked.

## Links

The widget and the controls use Nina's links, which also work in your own Shortcuts ("Open URL"):
`nina://weigh`, `nina://measure?mode=weekly` (or `full`, `assessment`), `nina://check/<id>`,
`nina://daytype/<id>`, `nina://progress`, `nina://plan`, `nina://add`, `nina://water`.

## German phrases and the app language

So that Siri can understand German phrases, Nina now tells iOS that it supports German as well as
English. Nina's own screens stay English, but on an iPhone, iPad or Mac set to German, the parts
the system draws for Nina follow German (for example "Abbrechen" in system dialogs, the photo
picker, and dates written as "Mo., 10. Nov."). To have everything in English: Settings → Apps →
Nina → Language → English.
