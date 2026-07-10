#!/bin/bash
# Monta o Arix.app a partir do build do Swift Package.
set -e
cd "$(dirname "$0")"

echo "🔨 Compilando (release)..."
swift build -c release

APP="Arix.app"
BIN=".build/release/Arix"

echo "📦 Montando $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Arix"
cp Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Recursos do avatar (os que existirem).
for f in avatar.png avatar_mid.png avatar_open.png avatar_round.png avatar_fv.png avatar.riv; do
    [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/"
done

# Frameworks dinâmicos (RiveRuntime). O SPM extrai o xcframework em
# .build/artifacts/ — procura a fatia do macOS em todo o .build.
FRAMEWORK=$(find .build -type d -name "RiveRuntime.framework" -path "*macos*" -print -quit 2>/dev/null || true)
if [ -z "$FRAMEWORK" ]; then
    FRAMEWORK=$(find .build -type d -name "RiveRuntime.framework" -print -quit 2>/dev/null || true)
fi
if [ -n "$FRAMEWORK" ]; then
    echo "🧩 Incluindo $(basename "$FRAMEWORK") ($FRAMEWORK)"
    mkdir -p "$APP/Contents/Frameworks"
    cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Arix" 2>/dev/null || true
    codesign --force --sign - "$APP/Contents/Frameworks/RiveRuntime.framework" 2>/dev/null || true
else
    echo "ℹ️ RiveRuntime.framework não encontrado no .build (ok se o link for estático)."
fi

# Assinatura ad-hoc (suficiente para uso local).
codesign --force --deep --sign - "$APP"

echo ""
echo "✅ $APP criado."
echo "   As chaves de API devem estar em ~/.config/arix/config.json"
echo "   (copie com: mkdir -p ~/.config/arix && cp config.json ~/.config/arix/)"
echo "   Para instalar: mv Arix.app /Applications/"
