#!/system/bin/sh
#title=Hide maps
#author=ahmed-alnassif
#desc=Applies only the exact SUS_MAP targets listed in sus_maps.txt

PATH=/data/adb/ksu/bin:/data/data/com.termux/files/usr/bin:$PATH
SUSAF_COMMAND="${SUSAF_CLI_COMMAND:-SusAF}"

if "$SUSAF_COMMAND" --apply-sus-maps; then
	echo "[+] targeted map hiding applied successfully"
	echo "[*] only explicit sus_maps.txt entries were used"
else
	echo "[-] targeted map hiding apply failed"
	exit 1
fi
