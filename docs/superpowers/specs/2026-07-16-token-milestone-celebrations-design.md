# Token Milestone Celebrations Design

## Goal

Add optional desktop celebration effects when today's CPA Usage Keeper Token count crosses significant milestones while the application is running. Celebrations should feel playful and meme-heavy without interrupting normal work.

## Scope

The feature supports:

- Milestones at 10M, 50M, and 100M Tokens.
- Additional milestones every 100M Tokens after 100M: 200M, 300M, 400M, and so on.
- Three selectable visual styles plus a random mode.
- Synchronized playback on every connected display.
- Optional sound, disabled by default.
- An effect preview action that does not change milestone tracking state.
- Abstract Chinese internet meme copy with occasional English phrases.
- Daily deduplication and no historical backfill.

The feature does not support user-authored thresholds, custom animation assets, custom meme text, cloud synchronization, notifications when the app was not running, or historical milestone playback.

## Settings

The settings window adds a “Token 里程碑彩蛋” section.

### Celebration Style

Available values:

- Off
- Cinematic Fireworks
- Top Achievement Notification
- Retro Game Achievement
- Random

The default is Off. Users must explicitly enable a fixed style or Random mode. Random mode selects one of the three styles independently for each milestone. All displays use the same selected style for one celebration.

### Sound

“播放彩蛋音效” is a separate toggle. It defaults to off. When enabled, one short sound plays per milestone regardless of the number of connected displays.

### Preview

The settings section includes a “预览效果” button.

- Preview is available whenever a visual style other than Off is selected, even before settings are saved.
- Preview uses a synthetic 50M Token milestone and built-in meme copy.
- Preview plays on every currently connected display using the selected style.
- Random mode chooses one style for the preview session and uses it on all displays.
- Preview follows the current sound toggle. Sound still plays only once.
- Preview never reads, updates, consumes, or persists real milestone tracker state.
- Repeated clicks while a preview is active are ignored.

## Milestone Rules

The tracker observes successful snapshots for the `today` range only.

### Startup and Reconfiguration

- The first valid Today snapshot after application startup establishes a baseline and never triggers a celebration.
- The first valid Today snapshot after a calendar-day change establishes the new day's baseline and never triggers a celebration.
- Changing the Keeper URL, authentication type, or credential establishes a new baseline and does not inherit milestone progress from the previous identity.
- Waking from sleep does not backfill milestones crossed while the application was not actively observing usage. The first post-wake snapshot becomes the new baseline.

### Threshold Detection

- Fixed milestones: 10,000,000; 50,000,000; 100,000,000 Tokens.
- Repeating milestones: every 100,000,000 Tokens after 100,000,000.
- A milestone triggers only when the previous observed value is below it and the new observed value is at or above it.
- If one refresh crosses multiple milestones, only the highest crossed milestone triggers.
- Each milestone may trigger only once per local calendar day.
- If usage decreases, the tracker treats it as a Keeper correction and updates the baseline without triggering or clearing already celebrated milestones.

### Persistence

The application stores only non-secret milestone state in preferences:

- Local calendar date.
- Last observed Today Token count.
- Milestones already celebrated that day.
- Identity fingerprint derived from the configured base URL and authentication type, without including or hashing the credential itself.

The stored state prevents duplicate celebrations after an ordinary app restart. A restart does not turn an already-reached milestone into a backfill event.

## Visual Styles

All styles use borderless transparent windows placed above ordinary application windows. They do not activate the application, take keyboard focus, or intercept mouse events.

### Cinematic Fireworks

- Duration: approximately 4.5 seconds.
- Full-display transparent overlay.
- Fireworks and particle bursts originate from multiple screen edges.
- Central milestone headline, supporting line, and one meme pill.
- Uses bright gold, electric blue, magenta, and white against a subtle darkened transparent field.

Example:

> 恭喜你成功烧掉 50M Token  
> 你的钱包沉默了，但你离 AI Native 更进一步。  
> GPU：我真的会谢。

### Top Achievement Notification

- Duration: approximately 5 seconds.
- A large dark translucent achievement card slides down near the top center.
- Confetti and small firework bursts remain close to the card.
- Least disruptive fixed visual style.

Example:

> 50M UNLOCKED  
> 又烧掉一座 Token 小山  
> AI Native +1，余额 -1。

### Retro Game Achievement

- Duration: approximately 4 seconds.
- Pixel-art styled achievement panel with block shadows, scan-line accents, and pixel fireworks.
- Includes a humorous progress bar or level label.

Example:

> ACHIEVEMENT UNLOCKED  
> TOKEN 蒸发术 · LV.50M  
> 预算没有消失，只是转化成了智能。

## Meme Copy

Copy is selected from built-in pools. The milestone number is inserted using compact formatting such as `10M`, `50M`, `100M`, or `1.2B`.

Tone requirements:

- Chinese-first internet humor.
- Abstract and self-aware.
- May tease budgets, wallets, GPUs, context windows, or productivity.
- Must not insult the user or use discriminatory, sexual, violent, or politically sensitive material.
- Avoid claims about real monetary loss when cost data is unavailable.

Example lines:

- 钱包已进入只读模式。
- Token 没有消失，只是转化成了智能。
- GPU 看见你已经开始冒汗。
- 上下文窗口：饱了。你的探索欲：还没。
- AI Native 进度 +1，预算条 -100。
- 今天的 Token，明天的生产力，后天的账单。
- Prompt 很短，账单很长。
- 不是 Token 多，是想法装不下。

One celebration selects a headline, supporting line, and optional meme badge. All displays show the same text.

## Architecture

### MilestoneTracker

A pure state machine that accepts identity, current date, and Today Token snapshots. It returns either no event or one `TokenMilestone` event. It owns threshold calculation, baseline handling, rollback handling, daily reset, and highest-crossed selection.

### MilestoneStateStore

Persists and restores the non-secret daily tracker state through application preferences. It exposes a focused interface independent of `UserDefaults` encoding details.

### CelebrationCoordinator

Receives milestone events, chooses the configured visual style and meme copy, creates one celebration session, and ensures sound plays only once. It ignores a new event while an existing celebration is active rather than stacking overlays.

It also exposes a separate preview operation that constructs a synthetic 50M session without calling or mutating `MilestoneTracker` or `MilestoneStateStore`.

### CelebrationWindowController

Reads `NSScreen.screens` at playback time and creates one transparent, borderless, non-activating, mouse-transparent window per screen. Every window receives the same session ID, style, milestone, text, and animation start time so playback remains synchronized.

Windows are destroyed after the style duration. Display connection or disconnection affects the next celebration and does not require live migration of an active effect.

### Celebration Views

Three isolated SwiftUI views implement the visual styles. Particle simulation uses SwiftUI Canvas and TimelineView with deterministic seeded randomness per celebration session. This keeps all displays visually consistent while avoiding a SpriteKit dependency.

### CelebrationSoundPlayer

Provides one short macOS system sound per celebration when enabled. It is called once by the coordinator, not by individual display windows.

### UsageRefreshModel Integration

After a successful Today refresh, `UsageRefreshModel` forwards the new snapshot and current identity to `MilestoneTracker`. Tracking failures never change refresh success state or menu bar data.

## Multi-Display Behavior

- Every currently connected display participates.
- Each display receives a full-screen overlay in its own coordinate space.
- All overlays use the same style, text, seed, and start timestamp.
- Windows use a level above ordinary app windows but below critical system alerts.
- Windows ignore mouse events and do not become key or main windows.
- The overlay must not move focus away from the user's active application.

## Interruption and Error Handling

- If celebration windows cannot be created, skip the failed display and continue on the others.
- If all windows fail, consume the milestone to avoid repeated attempts every refresh.
- If an animation is active when another milestone arrives, keep only the active celebration and mark the later milestone as celebrated. The app does not queue multiple full-screen effects.
- Missing cost data has no effect because milestones use Token count only.
- Invalid or unavailable Today snapshots do not update the tracker baseline.
- Disabling celebrations closes any active overlays and prevents further playback.
- Sound playback failure does not cancel visual playback.
- Preview failure is shown as a non-blocking settings error and does not alter saved settings.

## Testing

### Unit Tests

- First snapshot establishes a baseline without triggering.
- Crossing 10M, 50M, and 100M boundaries.
- Repeating 100M thresholds at 200M, 300M, and higher.
- Exact-boundary behavior.
- One refresh crossing multiple thresholds selects the highest.
- Restart state prevents duplicates and does not backfill.
- Calendar-day reset establishes a new baseline.
- Token rollback updates baseline without replay.
- Identity change establishes a new baseline.
- Random style selects one valid style for the entire session.
- Meme formatting inserts the correct compact milestone value.

### Window and Coordinator Tests

- Window count matches the supplied display list.
- All windows share style, text, seed, and start time.
- Overlay windows are transparent, non-activating, and mouse-transparent.
- Sound plays once for a multi-display celebration.
- A second milestone does not stack while a celebration is active.
- Disabling celebrations closes active overlays.
- Preview constructs a 50M session without reading or writing tracker state.
- Preview is disabled for Off and ignores repeated clicks while active.

### Manual Verification

- Test each visual style on one and multiple displays.
- Test the preview button for each style, Random mode, and sound enabled/disabled.
- Confirm no mouse or keyboard focus is captured.
- Confirm the overlay disappears after the documented duration.
- Confirm display scaling does not clip the headline or meme badge.
- Confirm sleep/wake and app restart do not generate backfill effects.
- Confirm real Keeper refreshes continue while an overlay is active.

## Completion Criteria

The feature is complete when celebrations are disabled by default; a user can select a style, preview it without changing milestone state, optionally enable sound, cross a Token milestone while the app is actively observing Today usage, and see one synchronized non-interactive celebration on every connected display without duplicate or historical playback.
