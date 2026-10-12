#!/bin/sh
T=/data/ShellCrash-tool
[ -d "$T/configs" ] || exit 1
mkdir -p "$T/jsons" "$T/yamls"
ln -sf /data/ShellCrash/configs/config.json "$T/jsons/config.json"
ln -sf /data/ShellCrash/configs/config.yaml "$T/yamls/config.yaml"
# Real executable, available in new and existing SSH sessions without an alias.
cat > /usr/bin/crash <<'LAUNCH'
#!/bin/sh
export CRASHDIR=/data/ShellCrash-tool
exec sh "$CRASHDIR/menu.sh" "$@"
LAUNCH
chmod 755 /usr/bin/crash

. /data/ShellCrash/ax5/core-env.sh
cfg="$T/configs/ShellCrash.cfg"
sed '/^crashcore=/d; /^core_v=/d; /^zip_type=/d; /^disoverride=/d' "$cfg" > "$cfg.new"
printf 'crashcore=%s\ncore_v=%s\nzip_type=tar.gz\ndisoverride=0\n' "$KIND" "$VERSION" >> "$cfg.new"
mv "$cfg.new" "$cfg"
if [ "$KIND" = meta ]; then
 command='/tmp/ShellCrash/CrashCore -d /tmp/ShellCrash -f /tmp/ShellCrash/config.yaml'
else
 command='/tmp/ShellCrash/CrashCore run -D /tmp/ShellCrash -c /data/ShellCrash/configs/config.json'
fi
printf 'BINDIR=/data/ShellCrash\nTMPDIR=/tmp/ShellCrash\nCOMMAND="%s"\n' "$command" > "$T/configs/command.env"
[ ! -f "$R/started" ] || cp "$R/started" "$R/crash_start_time"
