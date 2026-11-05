#!/bin/bash
# Clear all icon caches so macOS shows the new AR-Ruler icon

echo "1. Quitting AR-Ruler (if running)..."
killall AR-Ruler 2>/dev/null || true

echo "2. Clearing icon services cache..."
rm -rf ~/Library/Caches/com.apple.iconservices.store 2>/dev/null || true
rm -rf /Library/Caches/com.apple.iconservices.store 2>/dev/null || true

echo "3. Restarting Dock and Finder..."
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

echo "4. Resetting Launch Services database (optional, may take a moment)..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user 2>/dev/null || true

echo "Done. Now:"
echo "  - In Xcode: Product → Clean Build Folder (Shift+Cmd+K)"
echo "  - Then: Product → Run (Cmd+R)"
echo "  - Remove AR-Ruler from Dock and re-add it if still stale"
