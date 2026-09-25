# GTO Trainer

A personal iPhone practice trainer modeled on GTO Wizard's Practice mode, limited to
**6-max cash, NL25, 100bb, chip EV**. It has no daily hand limit.

## Features

- **Drill setup** with the same tabs as GTO Wizard's *New drill* dialog:
  - **Game**: preflop action (Any, RFI, vs Open, vs Raise-Call, vs 3bet, vs 4bet, vs 5bet), hero position,
    opponent position, relative position (IP/OOP), and alternating positions.
  - **Hands**: a 13×13 grid you can tap to pick hands, plus a *From / To %* strength slider. For example,
    `0–30` gives you only the top 30% of hands, and `0–100` gives you every hand, 10-3o included.
  - **Modes**: game mode (Full hand, Preflop only, Spot), difficulty (Standard, Grouped, Simple), pause
    after (Off, Mistake, Action), game speed, auto new hand, RNG mode, timebank (7/15/25s), and session
    length (20–420 hands).
  - **Display**: hints, quick results, hero strategy, hero range, opponent range, and hand info.
  - Drills can be saved and relaunched from the home screen. Some presets are included.
- **Table**: a 6-max table with you at the bottom. Opponents play by sampling from the strategy's
  frequencies, and action buttons use GTO Wizard-style colors.
- **Grading** of every decision: **Best / Correct / Inaccuracy / Wrong / Blunder**, with the EV loss in bb,
  the frequency of each option, and (preflop) the full 13×13 strategy grid with your hand highlighted.
- **Session summary**: GTO score (−100…100%), accuracy, total EV loss, EV loss per hand, results, grade
  distribution, and a hand list you can sort by biggest mistakes. Each hand opens in a step-by-step review.
- **Stats tab**: all-time stats broken down by preflop spot, street and position, plus session history.
  Everything is stored on the device.

## Install on your iPhone with Xcode

1. You need a Mac with **Xcode 16 or later** and a free Apple ID.
2. Open `GTOTrainer.xcodeproj`.
3. Select the **GTOTrainer** target → *Signing & Capabilities*:
   - Tick *Automatically manage signing* and choose your **Team** (your Apple ID; add it under
     Xcode → Settings → Accounts if needed).
   - Change the **Bundle Identifier** to something unique, e.g. `com.<yourname>.gtotrainer`.
4. Plug in your iPhone (or pair it over Wi-Fi), select it as the run destination, and press **Run** (⌘R).
5. The first time, on the phone go to *Settings → General → VPN & Device Management*, trust your developer
   certificate, and enable *Developer Mode* if iOS asks you to.

With a free Apple ID the app has to be re-installed from Xcode every 7 days. A paid developer account
extends that to a year.

## How the strategy works (and its limits)

GTO Wizard grades you against large precomputed solver databases. Those can't be shipped in this app, so:

- **Preflop** uses hand-authored 6-max 100bb ranges for every RFI, vs-open, vs-3bet, vs-4bet and vs-5bet node
  (`TrainerCore/Sources/TrainerCore/PreflopCharts.swift`). They are close to published solver outputs but are
  **approximations**. You can paste in your own ranges using the compact notation
  (`"TT+,A5s-A2s,KJo+,76s:0.5"`, where `:0.5` means a 50% frequency). Preflop EV loss is **estimated** from how far
  the hand is from where the chart uses that action.
- **Postflop** runs a live model on the phone. It tracks both players' ranges through the hand, estimates each
  option's chip EV with Monte Carlo equity (fold equity, equity against the calling range, and equity
  realization), and turns those EVs into mixed frequencies. It plays and grades sensibly, but it is **not a
  solver**. Use it for practice, not as ground truth.
- To keep every flop heads-up, a player facing an open plus a cold call can only squeeze or fold, and cold
  players facing a 3bet fold.
- Rake: 5% capped at 4bb ($1), no flop, no drop. Opens are 2.5bb (3bb from the SB).

## Project layout

```
GTOTrainer.xcodeproj         iOS app project (Xcode 16 folder-synced groups)
GTOTrainer/                  SwiftUI app (views, view model, persistence, assets)
TrainerCore/                 Swift package: cards, evaluator, equity, charts, engine, grading
  Sources/TrainerCore/       compiled directly into the app target as well
  Tests/TrainerCoreTests/    unit tests (run with `swift test` in TrainerCore/)
```

The engine is plain Swift with no UIKit or SwiftUI, so you can test it on any machine:

```
cd TrainerCore && swift test -c release -Xswiftc -enable-testing
```
