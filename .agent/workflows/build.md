---
description: Build the iOS application and verify for compilation errors
---

To build the project and check for errors, run the following command from the root directory:

// turbo
1. Run xcodebuild:
```bash
xcodebuild build -project Axilo.xcodeproj -scheme Axilo -destination 'generic/platform=iOS' -allowProvisioningUpdates
```

2. Review the output for any build errors or warnings.
