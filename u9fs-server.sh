while true; do
    socat TCP4-LISTEN:5640,range=127.0.0.1/32 EXEC:"u9fs -D -a none -u `whoami`"
done
