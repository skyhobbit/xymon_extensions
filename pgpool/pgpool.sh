#!/bin/sh

RESULT="green"
IPADDRESS="127.0.0.1"
sudo -u app /usr/local/pgsql/bin/psql -t -h $IPADDRESS -p 9999 -c 'show pool_nodes' postgres > /tmp/pgpool.txt


if [ -s /tmp/pgpool.txt ] ; then

STATUS2=`cat /tmp/pgpool.txt | perl -ane 'print $F[6]."\n"' | grep '2' | wc -l`

if [ "$STATUS2" -ne 2 ] ; then
      RESULT="red"
      NOTE="STATUS not 2"
fi

PRIMARY=`cat /tmp/pgpool.txt | perl -ane 'print $F[10]."\n"' | grep 'primary' | wc -l`

if [ "$PRIMARY" -ne 1 ] ; then
      RESULT="red"
fi

STANDBY=`cat /tmp/pgpool.txt | perl -ane 'print $F[10]."\n"' | grep 'standby' | wc -l`

if [ "$STANDBY" -ne 1 ] ; then
    RESULT="red"
fi

$BB $BBDISP "status $MACHINE.pgpool $RESULT `LANG=C;date`
show pool_nodes
`cat /tmp/pgpool.txt`
"

fi

exit 0
