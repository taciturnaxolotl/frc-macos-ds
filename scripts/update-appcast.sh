#!/bin/bash
# Update the Sparkle appcast.xml with a new release
# Usage: ./update-appcast.sh VERSION TAG DMG_SIZE SPARKLE_SIGNATURE RELEASE_NOTES REPO

set -e

VERSION="$1"
TAG="$2"
DMG_SIZE="$3"
SPARKLE_SIGNATURE="$4"
RELEASE_NOTES="$5"
REPO="$6"

PUBDATE=$(date -R)
DMG_URL="https://github.com/${REPO}/releases/download/${TAG}/FRCMacDS-${VERSION}-macOS.dmg"

# Convert markdown release notes to HTML
RELEASE_NOTES_HTML=$(echo "$RELEASE_NOTES" | python3 -c "
import sys, re, html
md = sys.stdin.read().strip()
lines = []
in_list = False
for line in md.split('\n'):
    stripped = line.strip()
    if stripped.startswith('### '):
        if in_list: lines.append('</ul>'); in_list = False
        lines.append(f'<h3>{html.escape(stripped[4:])}</h3>')
    elif stripped.startswith('## '):
        if in_list: lines.append('</ul>'); in_list = False
        lines.append(f'<h2>{html.escape(stripped[3:])}</h2>')
    elif stripped.startswith('- '):
        if not in_list: lines.append('<ul>'); in_list = True
        content = stripped[2:]
        content = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', content)
        content = re.sub(r'\x60(.+?)\x60', r'<code>\1</code>', content)
        lines.append(f'  <li>{content}</li>')
    elif stripped == '':
        if in_list: lines.append('</ul>'); in_list = False
    else:
        if in_list: lines.append('</ul>'); in_list = False
        content = re.sub(r'\*\*(.+?)\*\*', r'<b>\1</b>', stripped)
        lines.append(f'<p>{content}</p>')
if in_list: lines.append('</ul>')
print('\n'.join(lines))
")

NEW_ITEM="    <item>
      <title>Version ${VERSION}</title>
      <pubDate>${PUBDATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[${RELEASE_NOTES_HTML}]]></description>
      <enclosure
        url=\"${DMG_URL}\"
        sparkle:edSignature=\"${SPARKLE_SIGNATURE}\"
        length=\"${DMG_SIZE}\"
        type=\"application/octet-stream\"
        sparkle:os=\"macos\"/>
    </item>"

APPCAST_FILE="docs/appcast.xml"

if [ -f "$APPCAST_FILE" ]; then
  # Insert the new item after <language>en</language>, before existing items
  python3 << PYEOF
appcast = open("$APPCAST_FILE").read()
marker = "<language>en</language>"
idx = appcast.find(marker)
if idx == -1:
    raise SystemExit("Error: could not find <language> tag in appcast.xml")
end = idx + len(marker)
new_item = """
$NEW_ITEM"""
result = appcast[:end] + new_item + appcast[end:]
open("$APPCAST_FILE", "w").write(result)
PYEOF
else
  cat > "$APPCAST_FILE" << APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>FRC Mac DS Updates</title>
    <link>https://taciturnaxolotl.github.io/frc-macos-ds/appcast.xml</link>
    <description>Most recent updates to FRC Mac DS</description>
    <language>en</language>
${NEW_ITEM}
  </channel>
</rss>
APPCAST_EOF
fi

echo "Appcast updated for version ${VERSION}"
