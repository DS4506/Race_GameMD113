
# Activity Tracking with Core Motion (SwiftUI, iOS 15+)

This project implements real‑time activity tracking using Core Motion. It displays steps, distance (native where available, estimated otherwise), accelerometer, and gyroscope data. It gives motivational feedback every 500 steps and warns after 30 minutes of inactivity.

## Build
1. Open `Race_GameMD113.xcodeproj` in Xcode.
2. Target iOS 15 or later.
3. In the target **Info** tab, add:
   - `Privacy - Motion Usage Description (NSMotionUsageDescription)` with a clear message.
   You can copy from `Race_GameMD113/Config/PrivacyInfo.plist`.
4. Build and run on a physical device.

> Notes: CMPedometer streams in the background while the app is suspended. Accelerometer and gyro updates are foreground only.

## Files
- `ContentView.swift` — UI, ViewModel, Motion & Pedometer services, inactivity logic, feedback, and haptics.
- `Race_GameMD113App.swift` — App entry.
- `Config/PrivacyInfo.plist` — Motion usage key sample.

## Extra Credit: Background
- `CMPedometer.startUpdates(from:)` continues in background. The app will accumulate steps even when not active. When reopened, values reflect progress. No additional background mode is required.
- If you need periodic refresh while in background, consider Push Notifications, Live Activities, or BGTaskScheduler to schedule work, noting that continuous accelerometer/gyro streaming is not permitted in the background.

## Milestones and Inactivity
- Milestone every 500 steps (edit `milestone` in `ActivityViewModel`).
- Inactivity warning after 30 minutes without motion (edit `inactivitySeconds`).

