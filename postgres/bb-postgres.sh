#!/bin/sh
# Local customizations.
#
## install dir
LANG=en; export LANG
BIN_BASE=/usr/local/pgsql; export BIN_BASE

## executable to search for with ps
POSTGRES_DAEMON=postmaster; export POSTGRES_DAEMON

## full path to executable
POSTGRES_DAEMON_FULL=$BIN_BASE/bin/$POSTGRES_DAEMON; export POSTGRES_DAEMON_FULL

## full path to executable
POSTGRES_CLIENT_FULL=$BIN_BASE/bin/psql; export POSTGRES_CLIENT_FULL

## database, password, etc., for simple query
POSTGRES_AUTH="-U database password"; export POSTGRES_AUTH

# Initialize variables
#
COLOR="green"; export COLOR
LINE=""; export LINE
TEMPFILE=/tmp/bb-postgres.$$; export TEMPFILE

# Check to see if the client exists and can connect to the daemon using a simple query.
#
if test -x $POSTGRES_CLIENT_FULL
then
	$POSTGRES_CLIENT_FULL $POSTGRES_AUTH -F '' -tc "select 'DATE',now()" | $GREP -v grep | $GREP 'DATE' | awk '{print $2 "@" $3 " " $4}'> /tmp/bb-postgres$$.date
	if test $? -ne 0
	then
		LINE="${LINE}<BR>Postgres Client: DOWN "; export LINE
		COLOR="red"; export COLOR
	else
	    TMSTMP=`cat /tmp/bb-postgres$$.date`; export TMSTMP
	    rm -f /tmp/bb-postgres$$.date
	fi
else
	LINE="${LINE}<BR>Postgres Client: Binary Missing ($POSTGRES_CLIENT_FULL) "; export LINE
	COLOR="yellow"; export COLOR
fi

# If there is a fatal error, then call the pager
#
if test "$COLOR" = "red"
then
	if test "$DFPAGE" = "Y"		# CALL THE PAGER
	then
		$BB $BBPAGE "page ${MACHIP} $LINE"
	fi
fi

# If there were no errors, then put a friendly message out
#
if test "$LINE" = ""
then
	LINE="<BR>Postgres Daemon and Client are OK.<BR>Client reports timestamp of $TMSTMP."; export LINE
fi

# Send a status update to the big brother display unit
#
$BB $BBDISP "status $MACHINE.postgres $COLOR `date` $LINE"
