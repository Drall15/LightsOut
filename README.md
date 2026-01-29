<div align="center">
<a href="https://github.com/AlonX2/LightsOut/releases/"><img src="https://github.com/user-attachments/assets/2007db73-5485-4296-9205-e9626ff3ac81" width="128" height="165" alt="LightsOut" align="center"/></a>

<h2>LightsOut</h2>
<p><b>Forever free</b> menubar utility to disable any monitor with a simple button press - No more cable fidgeting or using bloated apps!</p>
<a href="https://github.com/AlonX2/LightsOut/releases/download/v1.1.0/LightsOut.dmg"><img src="https://user-images.githubusercontent.com/37590873/219133640-8b7a0179-20a7-4e02-8887-fbbd2eaad64b.png" width="180" alt="Download for macOS"/></a><br/>
<sub><b>The <a href="https://github.com/AlonX2/LightsOut/releases/">latest app version</a> requires macOS Ventura, Sonoma or Sequoia.<br>
</div>
<hr>
<div align="center">
  <h4>Well they do say a picture is worth a thousand words, and in this case leaves little room for more storytelling:</h4>
  <img src="https://github.com/user-attachments/assets/29cd8438-68cd-449e-bbaa-12b2e6458c51" alt="Very cool screenshot" align="center"/>
</div>

## Features

- **Disable Any Display**: Turn off any connected monitor with a single click
- **Two Disable Methods**: Choose between full disconnection or mirror+gamma (for displays that don't support disconnection)
- **Auto-Restore Built-in Display**: When external monitors are disconnected and the internal display is disabled, it will automatically re-enable after 5 seconds to prevent being stuck with a black screen

## Development

### Requirements

- macOS 13.5 (Ventura) or later
- Xcode 16.1 or later
- Swift 5

### Building

1. Clone the repository:
   ```bash
   git clone https://github.com/AlonX2/LightsOut.git
   cd LightsOut
   ```

2. Open in Xcode:
   ```bash
   open LightsOut.xcodeproj
   ```

3. Build the project (⌘B)

### Running Tests

The project includes unit tests for the display management logic, including the auto-restore feature.

#### From Command Line

```bash
# Run all tests
xcodebuild test -project LightsOut.xcodeproj -scheme LightsOut -destination 'platform=macOS'

# Run tests without code signing (useful for CI/CD)
xcodebuild test -project LightsOut.xcodeproj -scheme LightsOut -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

#### From Xcode

1. Open `LightsOut.xcodeproj` in Xcode
2. Select the `LightsOut` scheme
3. Press ⌘U or go to Product → Test

### Test Coverage

The test suite includes:

- **DisplayInfoTests**: Tests for display model initialization, equality, and hashability
- **AutoRestoreTests**: Tests for the auto-restore logic conditions
- **AutoRestoreTimerTests**: Tests for timer scheduling and cancellation behavior
- **DisplayStateManagementTests**: Tests for display collection handling and state preservation
