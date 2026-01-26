#!/bin/sh

cleanup() {
    if [ ! -z "$PID" ]; then kill $PID 2>/dev/null; fi
    rm -f /tmp/raw.dump
    echo ""
    echo "Exiting."
    exit 0
}
trap cleanup INT TERM

stty -F /dev/ttyS0 19200 raw -echo -hupcl min 1 time 0

echo "=========================================="
echo "    SMART PLUG MONITOR (Adaptive V)       "
echo "=========================================="

while true; do
    rm -f /tmp/raw.dump

    cat /dev/ttyS0 > /tmp/raw.dump &
    PID=$!

    sleep 1

    printf ":01V\n" > /dev/ttyS0
    sleep 2

    printf ":01I\n" > /dev/ttyS0
    sleep 4

    kill $PID 2>/dev/null
    wait $PID 2>/dev/null

    CLEAN_DATA=$(cat /tmp/raw.dump | tr -cd '\40-\176')

    SAFE_DATA=$(echo "$CLEAN_DATA" | sed 's/\$01I/|/')

    RAW_V=$(echo "$SAFE_DATA" | cut -d'|' -f1 | tr -d -c 0-9 | awk '{l=length($0); if(l>6) print substr($0, l-5); else print $0}')
    RAW_I=$(echo "$SAFE_DATA" | cut -d'|' -f2 | tr -d -c 0-9 | head -c 6)

    echo "----------------------------------------"
    echo "RAW DATA: $CLEAN_DATA"

    if [ ${#RAW_V} -ge 5 ] && [ ${#RAW_I} -gt 0 ]; then
        VOLTS=$(awk "BEGIN {if($RAW_V > 99999) printf \"%.2f\", $RAW_V/1000; else printf \"%.2f\", $RAW_V/100}")
        AMPS=$(awk "BEGIN {printf \"%.3f\", $RAW_I/10000}")
        WATTS=$(awk "BEGIN {printf \"%.2f\", $VOLTS * $AMPS}")

        echo "VOLTAGE : $VOLTS V"
        echo "CURRENT : $AMPS A"
        echo "POWER   : $WATTS W"
    else
        echo "WARNING : Frame Skipped!"
    fi
done
