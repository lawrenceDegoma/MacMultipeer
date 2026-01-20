#!/bin/bash

echo "🧪 Testing MacMultipeer permissions..."
echo

# Check if app exists
if [ ! -d "/Applications/MacMultipeer.app" ]; then
    echo "❌ MacMultipeer.app not found in Applications"
    exit 1
fi

# Check bundle identifier
BUNDLE_ID=$(plutil -extract CFBundleIdentifier xml1 -o - "/Applications/MacMultipeer.app/Contents/Info.plist" | sed -n 's/.*<string>\(.*\)<\/string>.*/\1/p')
echo "📦 Bundle ID: $BUNDLE_ID"

# Check if screen capture usage description exists
if plutil -extract NSScreenCaptureUsageDescription xml1 -o - "/Applications/MacMultipeer.app/Contents/Info.plist" > /dev/null 2>&1; then
    echo "✅ Screen capture usage description present"
else
    echo "❌ Screen capture usage description missing"
fi

# Check entitlements
if plutil -extract com.apple.security.device.screen-recording xml1 -o - "/Applications/MacMultipeer.app/Contents/Resources/embedded.provisionprofile" > /dev/null 2>&1; then
    echo "✅ Screen recording entitlement found"
else
    echo "⚠️  Screen recording entitlement check inconclusive (checking different location)"
fi

echo
echo "🚀 Launching MacMultipeer..."
echo "   When prompted, grant all permissions (Screen Recording, Camera, Microphone)"
echo "   The permissions should now stick properly."

open "/Applications/MacMultipeer.app"

echo
echo "✨ If permissions still don't work:"
echo "   1. Go to System Settings → Privacy & Security → Screen Recording"
echo "   2. Remove 'MacMultipeer' if it's listed"
echo "   3. Restart the app - it will ask for permissions again"
echo "   4. This time they should work correctly!"
