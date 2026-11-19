# Nina – body, measuring and the coach

Nina can work like a nutritionist who also measures you: a plan with phases and day types, a
morning weigh-in, the tape once a week, body fat every few weeks, and a short check-in every week
that looks at the numbers and – only when they call for it – proposes a small calorie change.
Training itself stays in your training app; Nina only needs to know what kind of day it is.

Everything here starts once a plan is set up (Settings → Goals & Plan → My Plan, or an import from
your AI, see [IMPORT.md](IMPORT.md)). Without a plan Nina is the diary it always was.

## What Nina never does

- **No automatic changes.** Calories, phases and reviews only change when you tap Apply, Start or
  a review choice – and every change shows a message with **Undo**.
- **No medical verdicts.** No "overweight", no diagnosis, no supplement advice. The only reference
  label is the usual guideline "waist-to-height under 0.5". Very low targets or very fast rates get
  a calm caution, nothing more.
- **No training plans.** Nina records the day type (Gym, Tennis, Rest …) and an optional 1–5
  rating of how training felt. Exercises, sets and recovery stay in your training app.
- **No Apple Health data in iCloud.** Weights from Apple Health count live (in the 7-day average,
  for example) but are never saved in Nina's data. See [HEALTH.md](HEALTH.md).

## Weighing in

- **When**: every morning, after the bathroom, before eating, drinking and training, in the same
  clothes (or none). Today shows a "Weigh in" pill until you have weighed in or the morning cutoff
  has passed; the morning reminder comes at your weigh-in time (07:00 unless you change it).
- **Morning weight**: the first weigh-in of the day before the morning cutoff (11:00 unless you
  change it). Later weigh-ins show as faint dots on the chart and are left out of every number.
- **7-day average**: the mean of the morning weights of the last 7 days. It needs at least 4
  mornings; until then Nina says how many more it needs. Day-to-day swings of half a kilo or more
  are normal (water, salt, carbs); the average evens them out.
- **Pace (kg a week)**: a straight line through the morning weights of the last 2–3 weeks. It counts
  once it spans at least 14 days with at least 10 mornings, and it never reaches back before the
  phase start, the last calorie change or the end of a pause.
- **Status**: the pace against the phase's range, with a small tolerance of 0.03 kg a week – *In
  range*, *Slower than planned*, *Faster than planned* or *Gathering data*. *Off track* only shows
  after two check-ins in a row outside the range on the same side.
- **Unusual readings**: a weigh-in far from your trend asks "Unusual reading – anything special?".
  A reason (salty, late meal, alcohol, travel, ill, period, refeed, poor sleep) keeps the dot on the
  chart but leaves it out of the pace. A number that looks like a typo asks "Did you mean …?".

## Measuring with the tape

The same conditions every time matter more than the exact spot. The measure sheet shows this
checklist – fully the first time, folded after that:

1. **Morning**, after the bathroom, **before eating or drinking**.
2. **Before training** – a pump adds 0.5–1 cm to arm, chest and thigh.
3. **Bare skin**, relaxed.
4. **Tape level** all the way round (use a mirror), **snug** without pressing in.
5. **Same spot, same side, same tape** each time.

| Site | Where |
|---|---|
| Waist | At the navel, relaxed, at the end of a normal breath out |
| Narrow waist | The narrowest point between the lowest rib and the hip bone (used instead of the waist for women) |
| Hip | The widest point over the buttocks, feet together |
| Chest | At nipple height (women: the fullest point), arms down, after breathing out |
| Arm | Relaxed upper arm, halfway between shoulder tip and elbow |
| Thigh | Halfway between the hip crease and the top of the kneecap – or your own mark, like "20 cm above the kneecap" |
| Neck | Just below the larynx, tape sloping slightly down at the front (needed for the tape estimate) |
| Calf, flexed arm | Optional extras |

- **One site per page**: after the guide, the time and the conditions, the measure sheet shows one
  site per page – a small drawing of where the tape goes, last time's value in grey and the change
  since then. Type the number, or tap **−** and **+** to move it by 0.1 cm (hold them to keep going);
  **Same as Last Time** fills in last time's value. **Next** goes to the next site (on iPhone and iPad
  you can also swipe), **Skip** leaves a site out, and **Done** on the last page saves everything,
  with Undo. The last page also shows the tape estimate of body fat.
- **Just one site**: on Progress → Body, tap a site's tile (Waist, Arm …) and then **Measure Waist**
  (or that site's name). The sheet opens with only that site – and the other side too when you
  measure both. The link `nina://measure?mode=waist` does the same, for example from a Shortcut; it
  takes any site (`waist`, `hip`, `chest`, `arm`, `arm_l`, `thigh`, `thigh_l`, `neck`, `calf` …), and
  `mode=weekly` or `mode=full` opens the weekly sites or the full set.
- **Side**: chosen once in My Plan → Measuring (right unless you change it). Left and right are kept
  apart and never mixed.
- **Readings**: a full set takes two readings per site and asks for a third when they differ by more
  than 0.5 cm; Nina saves their average (the middle one of three). The weekly waist takes one
  reading and asks for a second when it moved more than 1 cm since last time. A jump of more than
  3 cm within a week asks "Same spot as last time?" – it never blocks saving.
- **Conditions**: Nina notes by itself whether you measured in the morning before eating. Exceptions
  (after training, late heavy meal, salty food, alcohol yesterday, ill, period, not fasted) can be
  added. Only *standard* readings – morning, fasted, no exception – count for trends; the others
  show as hollow dots.
- **Real change or noise**: a careful tape measurement still varies a little. Changes smaller than
  about 1 cm (0.5 cm for arm and neck) read "no clear change".

## Body fat

- **Pick one method and repeat it** every 8 weeks under the same conditions (morning, fasted, same
  device). A smart scale is easy, a professional BIA or DEXA scan more exact.
- **Each method and each device is its own series**, never averaged with another. Changes are only
  worked out within a series; a new method says "new series – compare like with like".
- **Typical error** (body-fat points): DEXA ±1.5, Bod Pod ±2.5, professional BIA ±3, skinfolds ±3.5,
  tape estimate ±3.5, smart scale ±4–5. The charts draw these bands, and a lean-mass change smaller
  than the method's error reads "within measurement error".
- **Tape estimate**: worked out live from your tape values with the US Navy formula – waist and neck
  (women: narrow waist, hip and neck) plus your height. It is never saved as a value, so it always
  follows your latest tape. It needs your height and sex in Goals & Plan → Body & Calculator. With
  sex "Prefer not to say", Nina asks once whether to use the men's or the women's formula and then
  uses that choice everywhere (Body page, check-in, phase review).
- **Lean and fat mass**: body fat % × the mean of the morning weights from 3 days before to 3 days
  after that day.
  During a gain, part of a "lean" increase is water and glycogen from the extra carbs.

## The measuring schedule

Today's strip shows what is due, so you never have to remember it:

- **Weigh in**: every morning until the cutoff.
- **Waist** (the weekly sites): on the check-in weekday.
- **Full measurement** (every site) **plus body fat**: every 8 weeks on the check-in weekday, and
  also when the plan is set up (your starting point), when a phase starts or ends and when the
  review weight is reached. A full set counts as that week's waist too.
- An item 3 days late says "overdue 3 days" once, then waits quietly for the check-in. Missing a
  week never moves the weekday.

## Day types and daily checks

- **Day types** give each kind of day its own targets (calorie cycling): Gym on fixed weekdays,
  Tennis when you pick it (with "1 of 2 this week" as a hint, never a nag), Rest on every other
  day. Tap the chip on Today's summary to change today's type, or touch and hold a day in the week
  strip to plan ahead. Back to Schedule undoes a pick.
- **Daily checks** are what your plan names – a supplement, for example. They sit in the strip on
  Today: a tap ticks one off, touch and hold gives Not Today. Nina never suggests one.
- **Protein per meal**: with a minimum per meal set (or 0.4 g per kg of body weight), each meal
  header shows "32 / 35 g", filled once it's reached.

## The weekly check-in

- **When**: on the check-in weekday a card appears on Today after the morning weigh-in (or from
  the morning cutoff) and stays for 3 days. File → Weekly Check-in… on the Mac, + → Check-in on
  iPhone and iPad, any time.
- **Four short steps** (about two minutes):
  1. **Your week**: your 7-day average and its change and the mornings weighed. The pace is a bar:
     the shaded band is your phase's range, the dot is your pace this week.
  2. **Waist**: type it right there (Nina asks for a second reading when it moved more than 1 cm).
     Measured this morning already? Then the step is done. When a full set is due, **Full
     Measurement** takes your waist along with the other sites; your answers so far are kept.
  3. **How it went**: days logged and on plan, average calories against the targets of the day
     types you actually had, protein days and meals, fiber, water, checks; an optional 1–5 rating
     of hunger, energy, sleep, training, digestion, stress and mood, and a note.
  4. **Next week**: the verdict with its one reason and, only when the rules below call for it,
     a proposal.
- **Copy for My AI** (on the last step, and on a saved week): puts your plan, the last 4 weeks and
  your body numbers on the clipboard as plain text for your AI. Its answer is a settings block you
  import in Goals & Plan, with a preview and Undo (see [IMPORT.md](IMPORT.md)). Nina sends nothing
  anywhere.
- **The rules**, in order:
  1. **Enough data**: at least 14 days and 10 morning weigh-ins since the phase start (or the last
     change). Before that: "Gathering data – first adjustment check on …".
  2. **You followed the plan**: at least 80 % of the days logged, and the average intake within
     150 kcal of the average target. Otherwise: hit the targets this week first – no change.
  3. **In range**: keep it.
  4. **Outside the range**: a proposal only when the check-in before was outside on the same side
     too – one odd week never changes anything.
  5. **The step**: 100–150 kcal a day, the same for every day type, so their differences stay. While
     gaining it goes into carbs; while losing into carbs and some fat. Protein is never lowered.
  6. **Guard rails**: no new proposal within 14 days of a change; "faster than planned" is held for
     28 days after starting creatine (it binds water); a gain never goes more than 500 kcal above
     your measured maintenance; a cut never goes below a safe floor.
- **Your choice**: **Apply from Tomorrow** (one message with Undo), **Not Now**, or **Edit Step**.
  Past days keep the targets they had, so your history stays right.

## Phases and the review

- A **phase** has a goal (gain, maintain, lose), dates (an end can be "about"), a pace range, an
  optional review weight, target weight and body fat. A diet break is just a short maintain phase.
- **Pace range**: one slider with two handles in the phase sheet (0.05 to 1 kg a week, in steps of
  0.05) – drag the slow end and the fast end.
- **Body-fat ceiling** (optional, gain phases only): a body-fat percentage at which the phase should
  be reviewed. Nina compares it with your latest value of the body-fat method you track (the tape
  estimate counts). Leave it empty to switch it off.
- **Nothing switches by itself.** On the next phase's start date a card says "… starts today" with
  **Start**, **In a week** and Edit; the current phase runs on until you tap.
- **Review**: when the 7-day average (never a single weigh-in) reaches the review weight – or in a
  gain phase the waist grew by the limit you set (4 cm unless you change it), waist-to-height
  reached 0.5 or body fat reached your ceiling – a card asks for a review: where you stand since the start (weight, lean and fat
  mass, waist, arm, chest, how well you followed the plan), then **Keep going**, **Hold my weight**
  until the next phase, **Start** the next phase **now** or **Change the end date**. If no full
  measurement was done in the last two weeks, it offers one first. **Decide Later** asks again in
  7 days.
- **A maintenance bridge after a long gain**: when a gain phase has run for more than 12 weeks and a
  fat-loss phase comes next, the review (and the end of the phase) also offers **1 week at
  maintenance first** or **2 weeks at maintenance first**. Nina adds a short maintain phase from the
  switch day and moves the loss phase to start right after it – one message with Undo.
- **Pause** (holiday, ill): no checks, check-ins or coach reminders, and the paused days are left
  out of every average. Afterwards "Welcome back – weigh in tomorrow morning" restarts your average.

## Coach reminders

Settings → Reminders → Coach. All of them follow your plan and go away as soon as the task is done –
on any device.

| Reminder | When |
|---|---|
| Morning weigh-in | At your weigh-in time, until you've weighed in. Type your weight right in the notification (Weight…); on a day your weekly waist is due you can type it there too (Waist…). A number that looks wrong comes back as "Is that right?"; tap it to check in the sheet. Checks timed for breakfast come along with a "done" button. |
| Daily checks | At the check's time or meal – only for checks with Remind on in My Plan (Taken / Not today). |
| Evening before a full measurement | 20:00 the day before. |
| Weekly check-in | 18:00 on the check-in day, until it's done. |
| Phase start, end and review | 09:00 on the day, and once at your review weight. |

- Nothing before 06:00 or after 21:00, and only one before 10:00.
- **Your iPhone sends them** by default (your Apple Watch shows them too). On iPad and Mac they are
  off unless you switch on "Also on this iPad" / "Also on this Mac".
- **"Turn on coach reminders?"** is asked once per device, right after a plan is first set up (in
  My Plan or with an import). Your iPhone also asks when the plan arrives from another device.
  Changing a coach reminder in Settings → Reminders → Coach counts as the answer, so it never asks
  again.
- Pausing coaching pauses them; meal reminders stay.
