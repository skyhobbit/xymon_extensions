#!/usr/bin/ksh
#
# Title:   bb-roracle.sh
# Author:  initially from James Huff (c) 2001 bb-moracle.sh but bastardized by keith sebesta
# Date:    11th May 2004
# Purpose: Check the status of all ORACLE databases listed and report back to
#          the "Big Brother" display master.
#		dd/mm/yy
# History:
#	1.0	24/04/01  J.Huff	* Initial version - sorta
#	1.1	17/05/01  J.Huff	* Added extent test, moved configurations
#					to their own file
#	1.2	15/11/01  J.Huff	* Refer to change_log.txt for now on.
#	1.3	18/01/02  S.Skotte	* Added support for dbtab threshold-file
#	1.4	06/03/02  R.Herron	* Added support for wildcard (@) in dbtab
#		mm/dd/yy
#	2.0 	05/12/03  K.Sebesta	* Chopped to pieces to work with local and remote DBs
#	2.01	05/13/03  K.Sebesta	* Chopped more
#	2.02	05/16/03  K.Sebesta	* completed hacking
#	2.03	05/21/03  K.Sebesta	* applied Christopher White (c) 2002-2003 code
#	2.04	05/28/03  K.Sebesta	* redirected sqlplus output
#	2.04a	05/28/03  K.Sebesta	* remember to $RM file in FUNC_USER_CHECK
#	2.04b	05/28/03  K.Sebesta	* display better error message in FUNC_DATABASE_CHECK
#	2.04c	05/28/03  K.Sebesta	* change debug mode check
#	2.04d	05/28/03  K.Sebesta	* added missed ext_check color values
#	2.05	05/29/03  K.Sebesta	* implimented multithreading
#	2.05a	06/13/03  K.Sebesta	* added noglob to sqlplus functions
#	2.05b	11/04/03  K.Sebesta	* applied fixes supplied by Robert Herron
#	2.05c	05/05/04  K.Sebesta	* Removed some bogus code
#	2.05d	05/06/04  K.Sebesta	* added extents to ignore lists
#	2.05e	05/11/04  K.Sebesta	* added rollback segments SQL code from Stefan Skotte (sfs@steria.dk)
#	2.05f	05/17/04  K.Sebesta	* Removed some bogus code
#	2.06	08/31/04  K.Sebesta	* Added deadlock and invalid object checks
#	2.07	12/28/04  K.Sebesta	* Changed SQLPLUS=$ORACLE_HOME/bin/sqlplus for local database
#	2.08	04/14/05  K.Sebesta	* Changed TABLESPACE check to include auto extents
#					as suggested by pvaughan
#	2.09	06/08/05  K.Sebesta	* added showtable to tablespace check because tables may be to long for BB output
#	2.10	06/11/05  K.Sebesta	* moved tablescheck output to file because limited by array size
#	2.11	06/26/05  K.Sebesta	* Finally fixed the multiple references in dbtab file
#	2.12	06/27/05  K.Sebesta	* allowed lower values than defaults and cleaned up max extent func and bug in usercheck
#	2.13	08/23/05  K.Sebesta	* fixed library and paths when multiple oracle versions exist and we're configured wrong
#	2.14	08/29/05  K.Sebesta	* fixed overwrite of dev/null issue
#	2.15	02/07/06  Al.Winklmeier/K.Sebesta	* Added Processes and session check
#	2.16	04/05/06  K.Sebesta	* fixed machinedot issue
#       2.17    18/07/06  J.Brey        * modified for use with pdksh under linux and ksh93 with local extension, fixed some EOF Errors,
#                                       fixed invalid object checks for objects with a space in here name and type (Materialized Views)
#                                       fixed remote/local sids extraction from bb-roracle.ids (now we needs awk)
#       2.18    22/08/06  H.Studt       * added support for custom-named database tests (oradb) columns in bb-roracle.ids
#                                       fixed problem with ROLBAKPCT
#       2.19    29/08/06  H.Studt       * added support for a simple RAC cluster load-balancing tests
#                                       * added support for a statistics tests
#                                       fixed problem with EXTENTS tests
#                                       fixed problem with INVALID tests
#       2.20    03/11/06  N.Dorfsman    * added support for multiple listener names
#                                       fixed problem with full tablespace
#                                       fixed some issue with Solaris ksh
#	2.21	02/07/07  K.Sebesta	* Modified error/invalid logon checks
#					Updated EXTENTS test
#					Updated LISTENER to add default
#					Updated to use oracle default TNS_ADMIN for LOCAL listener check and not export vars
#
#       ToDo: - modify invalid object check, so he ignores some invalid objects under 10g ( see metalink id 314461.1 )
#             - modify deadlock check, so he ignores some permanent locks and make decisions between blocking locks, user locks and system locks.
#             - add check for pending transactions and distributed transactions (use view sys.DBA_2PC_PENDING)
#
# Disclaimer: This code carries no warranties expressed or implied.  If
#             you run it and it doesn't work as expected (up to and
#             including trashing your computer) then I will accept no
#             responsibility whatsoever.
# 
# REQUIREMENTS: The Oracle user provided to the script should be a user with 
# only connect and select any table privleges. All other privleges should be 
# revoked for security measures. For reasons that should be obvious, don't put 
# the username/password of a dba user in here- it'll work, but it's a
# bit like running BB itself as root. Even worse, don't use "system" or "sys" user, either. 
#
# KS: You may have to use the TNS_ADMIN variable to point to a tnsnames.ora file
#
################################################################
Version=2.21a
# Debug-Mode ? (y/Y/N)
[[ "$1" = "Y" ]] || [[ "$1" = "y" ]] && export DEBUG="$1" || export DEBUG="N"

# BBPROG SHOULD JUST CONTAIN THE NAME OF THIS FILE
export BBPROG="${0##*/}" # could use basename

################################################################
# TEST1: THIS WILL BECOME A COLUMN ON THE DISPLAY (system tests)
# TEST2: THIS WILL BECOME A COLUMN ON THE DISPLAY (database tests)
# IT SHOULD BE AS SHORT AS POSSIBLE TO SAVE SPACE...
# NOTE YOU CAN ALSO CREATE A HELP FILE FOR YOUR TEST
# WHICH SHOULD BE PUT IN www/help/$TEST?.html.  IT WILL
# BE LINKED INTO THE DISPLAY AUTOMATICALLY.
################################################################
export TEST1="orasys"	# local system status
export TEST2="oradb"	# data base status
MULTI_THREAD="Y"	# Enable multi-thread
[[ "$DEBUG" == "N" ]] || MULTI_THREAD="N" # set to no if debug is on
################################################################
# Check the files/Directories, and Debug output
################################################################
[[ "$BBHOME" = "" ]] && BBHOME=/usr/local/bb; export BBHOME
if [[ ! -d "$BBHOME" ]]; then 
	echo "$BBPROG: BBHOME is an invalid directory (BBHOME=$BBHOME)"
	exit 1
fi

# GET DEFINITIONS IF NEEDED (assume bbdef.sh is valid file)
[[ -z "$BBTMP" ]] && . $BBHOME/etc/bbdef.sh # INCLUDE STANDARD DEFINITIONS

# read oracle definitions
if [[ ! -r "$BBHOME/etc/bb-roracle.def" ]]; then 
	echo "$BBPROG: Unable to read $BBHOME/etc/bb-roracle.def file"
	exit 1
else
	. $BBHOME/etc/bb-roracle.def # INCLUDE ORACLE DEFINITIONS
fi

if [[ ! -f "$ORATAB" ]]; then 
	echo "$BBPROG: The ORATAB ($ORATAB) file does not exist"
	exit 1
fi

if [[ ! -d "$ORACLE_HOME" ]]; then 
	echo "$BBPROG: The default ORACLE_HOME Directory ($ORACLE_HOME) in $BBPROG does not exist"
	exit 1
fi

################################################################
put_header()
{
  echo ""
  echo "<br><br><FONT SIZE=+2><b>$1</b></FONT> ($2)<hr>"
}
 
put_footer()
{
  echo ""
  echo "<br><br><center><hr>`basename $BBPROG` <b>Version:</b> $Version</center>"
}                                                                                                                                                  
strspn ()
{
#    local IFS=
#    local result="${1%%[!${2}]*}"
#    echo ${#result}
    if [[ $2 = +(*$1*) ]]; then
        echo ${#2};
    else
        echo 0;
    fi
}

# load the notify values from the dbtab file
# requires ORACLE_SID and all the RED/YELLOW vars be defined
GetNotifyAtValues ()
{
[[ "$DEBUG" = "Y" ]] && set -xv

# check to see if a specific line exists for this database
#   if so, get values.  Otherwise check for wildcard instance name.
#   Else use defaults
local DEFAULT_THRESHOLDS="`$GREP "^@:DATABASE_DEFAULT:" $DBTAB|sort -t: -u -k 1,2`"
local CURRENT_THRESHOLDS="`$GREP "^${ORACLE_SID}:DATABASE_DEFAULT:" $DBTAB|sort -t: -u -k 1,2`"
#echo $DEFAULT_THRESHOLDS
#echo $CURRENT_THRESHOLDS

# parse specific values
if test -n "$CURRENT_THRESHOLDS"; then
	TBL_YELLOW=`echo $CURRENT_THRESHOLDS|cut -f 3 -d":"`
	TBL_RED=`echo $CURRENT_THRESHOLDS|cut -f 4 -d":"`
	EXT_YELLOW=`echo $CURRENT_THRESHOLDS|cut -f 5 -d":"`
	EXT_RED=`echo $CURRENT_THRESHOLDS|cut -f 6 -d":"`
	PINLIB_YELLOW=`echo $CURRENT_THRESHOLDS|cut -f 7 -d":"`
	PINLIB_RED=`echo $CURRENT_THRESHOLDS|cut -f 8 -d":"`
	SQLAREA_YELLOW=`echo $CURRENT_THRESHOLDS|cut -f 9 -d":"`
	SQLAREA_RED=`echo $CURRENT_THRESHOLDS|cut -f 10 -d":"`
	BLOCK_BUF_YELLOW=`echo $CURRENT_THRESHOLDS|cut -f 11 -d":"`
	BLOCK_BUF_RED=`echo $CURRENT_THRESHOLDS|cut -f 12 -d":"`
	MEMREQ_YELLOW=`echo $CURRENT_THRESHOLDS|cut -f 13 -d":"`
	MEMREQ_RED=`echo $CURRENT_THRESHOLDS|cut -f 14 -d":"`
	ROLBAK_YELLOW=`echo $CURRENT_THRESHOLDS|cut -f 15 -d":"`
	ROLBAK_RED=`echo $CURRENT_THRESHOLDS|cut -f 16 -d":"`
	SHOWTABLE=`echo $CURRENT_THRESHOLDS|cut -f 17 -d":"`
	PROCESSES_YELLOW=`echo $CURRENT_THRESHOLDS|cut -f 18 -d":"`
	PROCESSES_RED=`echo $CURRENT_THRESHOLDS|cut -f 19 -d":"`
	SESSIONS_YELLOW=`echo $CURRENT_THRESHOLDS|cut -f 20 -d":"`
	SESSIONS_RED=`echo $CURRENT_THRESHOLDS|cut -f 21 -d":"`
        STATISTICS_YELLOW=`echo $CURRENT_THRESHOLDS|cut -f 22 -d":"`
        STATISTICS_RED=`echo $CURRENT_THRESHOLDS|cut -f 23 -d":"`
        RAC_SESSIONS_PR_SERV=`echo $CURRENT_THRESHOLDS|cut -f 24 -d":"`
        RAC_SESSIONS_YELLOW=`echo $CURRENT_THRESHOLDS|cut -f 25 -d":"`
        RAC_SESSIONS_RED=`echo $CURRENT_THRESHOLDS|cut -f 26 -d":"`
        MIN_EXT=`echo $CURRENT_THRESHOLDS|cut -f 27 -d":"`
fi

# parse system default values
if [[ -n "$DEFAULT_THRESHOLDS" ]]; then
	[[ -z "$TBL_YELLOW" ]] && TBL_YELLOW=`echo $DEFAULT_THRESHOLDS|cut -f 3 -d":"`
	[[ -z "$TBL_RED" ]] && TBL_RED=`echo $DEFAULT_THRESHOLDS|cut -f 4 -d":"`
	[[ -z "$EXT_YELLOW" ]] && EXT_YELLOW=`echo $DEFAULT_THRESHOLDS|cut -f 5 -d":"`
	[[ -z "$EXT_RED" ]] && EXT_RED=`echo $DEFAULT_THRESHOLDS|cut -f 6 -d":"`
	[[ -z "$PINLIB_YELLOW" ]] && PINLIB_YELLOW=`echo $DEFAULT_THRESHOLDS|cut -f 7 -d":"`
	[[ -z "$PINLIB_RED" ]] && PINLIB_RED=`echo $DEFAULT_THRESHOLDS|cut -f 8 -d":"`
	[[ -z "$SQLAREA_YELLOW" ]] && SQLAREA_YELLOW=`echo $DEFAULT_THRESHOLDS|cut -f 9 -d":"`
	[[ -z "$SQLAREA_RED" ]] && SQLAREA_RED=`echo $DEFAULT_THRESHOLDS|cut -f 10 -d":"`
	[[ -z "$BLOCK_BUF_YELLOW" ]] && BLOCK_BUF_YELLOW=`echo $DEFAULT_THRESHOLDS|cut -f 11 -d":"`
	[[ -z "$BLOCK_BUF_RED" ]] && BLOCK_BUF_RED=`echo $DEFAULT_THRESHOLDS|cut -f 12 -d":"`
	[[ -z "$MEMREQ_YELLOW" ]] && MEMREQ_YELLOW=`echo $DEFAULT_THRESHOLDS|cut -f 13 -d":"`
	[[ -z "$MEMREQ_RED" ]] && MEMREQ_RED=`echo $DEFAULT_THRESHOLDS|cut -f 14 -d":"`
	[[ -z "$ROLBAK_YELLOW" ]] && ROLBAK_YELLOW=`echo $DEFAULT_THRESHOLDS|cut -f 15 -d":"`
	[[ -z "$ROLBAK_RED" ]] && ROLBAK_RED=`echo $DEFAULT_THRESHOLDS|cut -f 16 -d":"`
	[[ -z "$SHOWTABLE" ]] && SHOWTABLE=`echo $DEFAULT_THRESHOLDS|cut -f 17 -d":"`
	[[ -z "$PROCESSES_YELLOW" ]] && PROCESSES_YELLOW=`echo $DEFAULT_THRESHOLDS|cut -f 18 -d":"`
	[[ -z "$PROCESSES_RED" ]] && PROCESSES_RED=`echo $DEFAULT_THRESHOLDS|cut -f 19 -d":"`
	[[ -z "$SESSIONS_YELLOW" ]] && SESSIONS_YELLOW=`echo $DEFAULT_THRESHOLDS|cut -f 20 -d":"`
	[[ -z "$SESSIONS_RED" ]] && SESSIONS_RED=`echo $DEFAULT_THRESHOLDS|cut -f 21 -d":"`
        [[ -z "$STATISTICS_YELLOW" ]] && STATISTICS_YELLOW=`echo $DEFAULT_THRESHOLDS|cut -f 22 -d":"`
        [[ -z "$STATISTICS_RED" ]] && STATISTICS_RED=`echo $DEFAULT_THRESHOLDS|cut -f 23 -d":"`
        [[ -z "$RAC_SESSIONS_PR_SERV" ]] && RAC_SESSIONS_PR_SERV=`echo $DEFAULT_THRESHOLDS|cut -f 24 -d":"`
        [[ -z "$RAC_SESSIONS_YELLOW" ]] && RAC_SESSIONS_YELLOW=`echo $DEFAULT_THRESHOLDS|cut -f 25 -d":"`
        [[ -z "$RAC_SESSIONS_RED" ]] && RAC_SESSIONS_RED=`echo $DEFAULT_THRESHOLDS|cut -f 26 -d":"`
        [[ -z "$MIN_EXT" ]] && MIN_EXT=`echo $DEFAULT_THRESHOLDS|cut -f 27 -d":"`
fi
# force defaults
[[ -z "$TBL_YELLOW" ]] && TBL_YELLOW=94	# Default YELLOW value
[[ -z "$TBL_RED" ]] && TBL_RED=97	# Default RED value
[[ -z "$EXT_YELLOW" ]] && EXT_YELLOW="60"
[[ -z "$EXT_RED" ]] && EXT_RED="75"
[[ -z "$PINLIB_YELLOW" ]] && PINLIB_YELLOW="85"
[[ -z "$PINLIB_RED" ]] && PINLIB_RED="75"
[[ -z "$SQLAREA_YELLOW" ]] && SQLAREA_YELLOW="85"
[[ -z "$SQLAREA_RED" ]] && SQLAREA_RED="75"
[[ -z "$BLOCK_BUF_YELLOW" ]] && BLOCK_BUF_YELLOW="85"
[[ -z "$BLOCK_BUF_RED" ]] && BLOCK_BUF_RED="75"
[[ -z "$MEMREQ_YELLOW" ]] && MEMREQ_YELLOW="30"
[[ -z "$MEMREQ_RED" ]] && MEMREQ_RED="15"
[[ -z "$ROLBAK_YELLOW" ]] && ROLBAK_YELLOW="75"
[[ -z "$ROLBAK_RED" ]] && ROLBAK_RED="85"
[[ -z "$SHOWTABLE" ]] && SHOWTABLE="Y"
[[ -z "$PROCESSES_YELLOW" ]] && PROCESSES_YELLOW="99"
[[ -z "$PROCESSES_RED" ]] && PROCESSES_RED="99"
[[ -z "$SESSIONS_YELLOW" ]] && SESSIONS_YELLOW="99"
[[ -z "$SESSIONS_RED" ]] && SESSIONS_RED="99"
[[ -z "$STATISTICS_YELLOW" ]] && STATISTICS_YELLOW="8"
[[ -z "$STATISTICS_RED" ]] && STATISTICS_RED="15"
[[ -z "$RAC_SESSIONS_PR_SERV" ]] && RAC_SESSIONS_PR_SERV="40"
[[ -z "$RAC_SESSIONS_YELLOW" ]] && RAC_SESSIONS_YELLOW="10"
[[ -z "$RAC_SESSIONS_RED" ]] && RAC_SESSIONS_RED="5"
[[ -z "$MIN_EXT" ]] && MIN_EXT="50"
}

################################################################
# The check for ORACLE sids. (if desired)
################################################################
Sid_Check()
{
[[ "$DEBUG" = "Y" ]] && set -xv
#
# Check for changes in Oracle SIDS
#
# Check if SIDS in oratab and in LOCAL_SIDS match
# If not, probably a new database was set at startup / or removed from startup
local SIDS_STARTUP=`$EGREP -v '^#|^$' $ORATAB | $GREP ':Y' | cut -f1 -d: |$SORT -k 1 -u 2>/dev/null`
local ERR=0
for sid in $SIDS_STARTUP ;do
     ERR=1
     for orasid in $LOCAL_SIDS ;do
          if [[ "$orasid" = "$sid" ]] ; then
               ERR=0
               break
          fi
     done
     if [[ "$ERR" -eq 1 ]]; then
          break
     fi
done

#
# LOCAL_SIDS may have less than in SIDS_STARTUP, so do the reverse
#
if [[ "$ERR" -eq 0 ]]; then
	for orasid in $LOCAL_SIDS ;do
		ERR=1
		for sid in $SIDS_STARTUP ;do
		if [[ "$orasid" = "$sid" ]]; then
			ERR=0
			break
		fi
	done
	if [[ "$ERR" -eq 1 ]]; then
		break
	fi
	done
fi
if [[ "$ERR" -eq 1 ]]; then
	echo "$SPACER&red Instances specified in LOCAL_SIDS (${LOCAL_SIDS}) do not match those found in $ORATAB (`echo ${SIDS_STARTUP}`)"
	COLOR="red"
else
	echo "$SPACER&green Instances specified in LOCAL_SIDS (${LOCAL_SIDS}) match those found in $ORATAB"
fi
}

################################################################
# The check for the listener. (if desired)
################################################################
Listener_Check()
{
[[ "$DEBUG" = "Y" ]] && set -xv
$SORT -u $BBTMP/LISTENER.$$ | while read orahome name sid; do
#       exporting tns_admin may cause problems with remote connects
        local ORACLE_HOME=$orahome
        if [[ -x $ORACLE_HOME/bin/lsnrctl ]]; then
                TNS_ADMIN=$ORACLE_HOME/admin $ORACLE_HOME/bin/lsnrctl status $name | $GREP 'TNS-' > /dev/null 2>&1
                if [[ $? -ne 1 ]]; then
                        echo "$SPACER&red Listener $name DOWN"
                        echo ""
                        COLOR="red"
                else
                        echo "$SPACER&green Listener $name UP"
                        if [[ "$LISTENER_CHECK_VERBOSE" = "Y" ]]; then
                                put_header "Oracle Listener $sid ($name) Info" "$MACHINEDOTS" >> $BBTMP/LISTENER.verbose.$$
                                echo "<BLOCKQUOTE>" >> $BBTMP/LISTENER.verbose.$$
                                $ORACLE_HOME/bin/lsnrctl status $name >> $BBTMP/LISTENER.verbose.$$
                                # Added an FYI only TNSPING section
                                echo "" >> $BBTMP/LISTENER.verbose.$$
                                $ORACLE_HOME/bin/tnsping $sid 3 >> $BBTMP/LISTENER.verbose.$$
                                echo "</BLOCKQUOTE>" >> $BBTMP/LISTENER.verbose.$$
                        fi
                # COLOR NOT set here as it has been set to green already
                fi
        else
                echo "$SPACER&yellow Listener ($ORACLE_HOME/bin/lsnrctl) not found."
                [[ "$COLOR" != "red" ]] && COLOR="yellow"
        fi
done

$RM -f $BBTMP/LISTENER.$$
cat $BBTMP/LISTENER.verbose.$$
$RM -f $BBTMP/LISTENER.verbose.$$
}
################################################################
# LOCAL PROCS CHECK function
################################################################
function FUNC_PROCS_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv

local UPPROCS=""
local DOWNPROCS=""
local TMPFILE=$TEMPFILE.ProcCheck.${ORACLE_SID}
$RM -f $TMPFILE > /dev/null 2>&1
$PS > $TMPFILE
chmod 600 $TMPFILE
################################################################
# Check process outline (ps) to see if all automatically started
# databases are running.
# Make sure all processes to an SID are up
################################################################
for proc in $ORA_PROCS ;do
	$GREP "${proc}_${ORACLE_SID}" $TMPFILE > /dev/null 2>&1
        if [[ "$?" -eq 1 ]]; then
		DOWNPROCS="${DOWNPROCS} ${proc}"
               else
                    UPPROCS="${UPPROCS} ${proc}"
               fi
done
$RM -f $TMPFILE > /dev/null 2>&1

if [[ -n "$DOWNPROCS" ]]; then
	echo "<br>$SPACER&red Database ${ORACLE_SID} DOWN processes: ${DOWNPROCS}"
	[[ "$PROCS_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
	# Made to separate cases
fi
if [[ -n "$UPPROCS" ]]; then
	echo "<br>$SPACER&green Database ${ORACLE_SID} UP processes: ${UPPROCS}"
fi
echo "<br>"
}

################################################################
# DATABASE CHECK function
################################################################
function FUNC_DATABASE_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv
set -f # turn off globbing

DB_CHECK=`$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF 2>&1
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260
select '$ORACLE_SID is up' FROM dual
/
EOF
`
if [[ "$DB_CHECK" != "$ORACLE_SID is up" ]]; then
	echo "$SPACER&red Database check: ${ORACLE_SID} is down or in hung state"
        for line in $DB_CHECK
        do
		DB="$DB $line"
		[[ "$line" = "" ]] && break
	done
	[[ -n $DB ]] && DB_CHECK="$DB"	# move it to look good
	echo "<br>$DB_CHECK<br>"
	[[ "$DATABASE_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
else
	echo "$SPACER&green Database check: ${ORACLE_SID} is up"
fi
}

################################################################
# USER PROC count function
################################################################
function FUNC_USER_PROC_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv

local USER_COUNT=`${PS}|${GREP} ${ORACLE_SID}|${GREP} -v grep|${GREP} -v ora_|wc -l`
if [[ "$USER_COUNT" -ge 0 ]]; then
	echo "$SPACER$SPACERActive Oracle Users in ${ORACLE_SID}: ${USER_COUNT}"
fi
echo ""
}

################################################################
# USER CHECK function
################################################################
function FUNC_USER_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv

local TMPFILE=$TEMPFILE.UserCheck.${ORACLE_SID}
set -f # turn off globbing

echo "<pre>"
$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF > $TMPFILE 2>&1
set pagesize 0
set linesize 200
column username format A20 trunc
column osuser format A20 trunc
column machine format A20 trunc
column terminal format A20 trunc
select username "username", osuser "osuser", machine "machine", terminal "terminal" FROM v\$session
order by UPPER(osuser)
    , UPPER(machine)
    , UPPER(username)
    , UPPER(terminal)
      ;
exit; 
EOF

local temp=`$GREP -i "does not exist" $TMPFILE`
if [[ -z $temp ]] ; then
	echo "username             osuser               machine              term"
	echo ""
	$EGREP -v "SVRMGR|Copyright|Release|^\$" $TMPFILE
else
	echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
	[[ "$USER_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
fi

echo "</pre>"
$RM -f $TMPFILE > /dev/null 2>&1
}

################################################################
# TABLESPACE CHECK function (2.05b, 2.8, 2.9, 2.10)
################################################################
function FUNC_TABLESPACE_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv

local M_VAR
set -f # turn off globbing

$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF >$BBTMP/TABLESPACE.${ORACLE_SID}.$$ 2>&1 
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260
column name heading "TABLESPACE" format A25
column "SIZE (M)" format 99999990.9
column "USED (%)" format 990

select d.tablespace_name "TABLESPACE",
round(sum(d.bytes)/1048576,2) "SIZE (M)",
round((sum(d.bytes)-nvl(FREESPCE,0)) / (greatest(sum(d.maxbytes),sum(d.bytes))) * 100,0) "USED (%)",
max(AUTOEXTENSIBLE) AutoExtend
from dba_data_files d,
( SELECT sum(f.bytes) FREESPCE,
f.tablespace_name Tablespc
FROM dba_free_space f
GROUP BY f.tablespace_name)
WHERE d.tablespace_name = Tablespc (+)
group by d.tablespace_name,FREESPCE
order by 1 desc
/

EOF

set -A M_VAR `head -1 $BBTMP/TABLESPACE.${ORACLE_SID}.$$`
if [[ "${M_VAR[0]}" = "FROM" ]] || [[ "${M_VAR[0]}" = "Enter" ]] || [[ "${M_VAR[0]}" = "ERROR:" ]] || [[ -z "${M_VAR[0]}" ]]; then
	echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
	[[ "$TABLESPACE_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
	rm -f $BBTMP/TABLESPACE.${ORACLE_SID}.$$ > /dev/null 2>&1
	return
fi

#cat $BBTMP/TABLESPACE.${ORACLE_SID}.$$|while read inTables;do
while read inTables;do
	set -A M_VAR $inTables

	### Nice for debugging
#	echo "Tablespace name = ${M_VAR[0]}"
#	echo "Tablespace size = ${M_VAR[1]}"
#	echo "Tablespace used = ${M_VAR[2]}%"
#	echo "Tablespace autoextent = ${M_VAR[3]}%"

	local TABLESPACE_NAME=${M_VAR[0]}
	local MAX_TBL_SIZE=${M_VAR[1]}
	typeset -i TBL_USED=${M_VAR[2]}
	local AUTOEXTENT=${M_VAR[3]}
	#Normally red=97 yellow=94 

	# count number of occurances of this sid and object 
	# if 0 check for wildcard sid values for this object and load
	# if 1 load default values for this sid and object
	# if > 1 load default values for this sid and object from first occurance and spit out message
	# Else use defaults
	# (2.05b) - added : as tablename terminator in grep
	local CURRENT_THRESHOLDS=""
	local INdbtab="`${GREP} -c \"^${ORACLE_SID}:${TABLESPACE_NAME}:\" $DBTAB 2>&1`"

	case $INdbtab in
		0)  CURRENT_THRESHOLDS="`$GREP \"^@:${TABLESPACE_NAME}:\" $DBTAB`"
			;;
		1)  CURRENT_THRESHOLDS="`$GREP \"^${ORACLE_SID}:${TABLESPACE_NAME}:\" $DBTAB`"
			;;
		[2-999])  CURRENT_THRESHOLDS="`$GREP \"^${ORACLE_SID}:${TABLESPACE_NAME}:\" $DBTAB|sort -t: -u -k 1,2`"
			echo "Found multiple references to ${ORACLE_SID}:${TABLESPACE_NAME} in $DBTAB"
			;;
	esac

	# Check if warn-variable is zero
	if test -n "$CURRENT_THRESHOLDS"; then
		typeset -i RED=`echo "$CURRENT_THRESHOLDS"|cut -f 4 -d":"`
		typeset -i YELLOW=`echo "$CURRENT_THRESHOLDS"|cut -f 3 -d":"`
	else 						# added to fix bug 2.05e 
		typeset -i RED=${TBL_RED}		# added to fix bug 2.05e
		typeset -i YELLOW=${TBL_YELLOW}		# added to fix bug 2.05e
	fi

	if [[ "${TBL_USED}" -ge "$RED" ]]; then
		echo "<br>$SPACER&red Tablespace ${ORACLE_SID}:${TABLESPACE_NAME} totals ${MAX_TBL_SIZE}Mb and is <B><U><FONT COLOR="RED">${TBL_USED}%</FONT></U></B> used, AUTOEXTENSIBLE=$AUTOEXTENT"

		[[ "$TABLESPACE_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'

	elif [[ "${TBL_USED}" -ge "$YELLOW" ]]; then
		echo "<br>$SPACER&yellow Tablespace ${ORACLE_SID}:${TABLESPACE_NAME} totals ${MAX_TBL_SIZE}Mb and is <B><U><FONT COLOR="YELLOW">${TBL_USED}%</FONT></U></B> used, AUTOEXTENSIBLE=$AUTOEXTENT"

		[[ "$COLOR" != "red" ]] && COLOR="yellow"

	elif [[ "$SHOWTABLE" = "Y" ]] && [[ "$YELLOW" -gt 100 ]] || [[ "$RED" -gt 100 ]] && [[ "${TBL_USED}" -ge 100 ]]; then
		echo "<br>$SPACER&green Ignoring Table ${ORACLE_SID}:${TABLESPACE_NAME} totals ${MAX_TBL_SIZE}Mb and is <B><U><FONT COLOR="PURPLE">${TBL_USED}%</FONT></U></B> used, AUTOEXTENSIBLE=$AUTOEXTENT"
	elif [[ "$SHOWTABLE" = "Y" ]];then
		echo "<br>$SPACER&green Tablespace ${ORACLE_SID}:${TABLESPACE_NAME} totals ${MAX_TBL_SIZE}Mb and is <B>${TBL_USED}%</B> used, AUTOEXTENSIBLE=$AUTOEXTENT"
	elif [[ "${YELLOW}" -gt 100 ]] || [[ "${RED}" -gt 100 ]]; then # Lets just show it as Overridden
		echo "<br>$SPACER&green Overridden Table ${ORACLE_SID}:${TABLESPACE_NAME} totals ${MAX_TBL_SIZE}Mb and is <B><U><FONT COLOR="PURPLE">${TBL_USED}%</FONT></U></B> used, AUTOEXTENSIBLE=$AUTOEXTENT"
	fi
done < $BBTMP/TABLESPACE.${ORACLE_SID}.$$

rm -f $BBTMP/TABLESPACE.${ORACLE_SID}.$$ > /dev/null 2>&1
}

################################################################
# EXTENT CHECK function
################################################################
function FUNC_EXTENT_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv

# Inorder to allow overide values to be lower we must do this
# where (extents/max_extents)*100 >= 1
# instead of this
# where (extents/max_extents)*100 >= ${EXT_YELLOW}
set -f # turn off globbing
rm -f ${TEMPFILE}-extents

$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF > ${TEMPFILE}-extents 2>&1
set pagesize 0
set linesize 2048
set heading off
set feedback off
column USED format 999.99
select segment_name, (extents/max_extents)*100 USED, max_extents
FROM dba_segments
where (extents/max_extents)*100 >= 1
and max_extents != 0
order by USED DESC;
exit;
EOF

if [[ ! -s ${TEMPFILE}-extents ]]; then # no real need to remove blank extents file
	echo "<br>ERROR: Unable to create extents file for ${ORACLE_SID}"
	[[ "$EXTENT_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
	return
fi

local OBJECT_NAME=`$HEAD -1 ${TEMPFILE}-extents`
if [[ "${OBJECT_NAME}" = "FROM" ]] || [[ "${OBJECT_NAME}" = "ERROR:" ]]; then
        echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
        [[ "$EXTENT_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
        return
fi

local GOTONE=N
## echo "# GOTONE = '${GOTONE}'"

typeset -i EXTENT_PCT
local MAX_EXTENTS

while read OBJECT_NAME EXTENT_PCT MAX_EXTENTS ;do
### Nice for debugging
#	echo "Object name = ${OBJECT_NAME}"
#	echo "Object extent pct = ${EXTENT_PCT}"
#	echo "Object max extents = ${MAX_EXTENTS}"

	[[ $EXTENT_PCT -lt $MIN_EXT ]] && break # below the minimum value to check at this will speed things up

	# count number of occurances of this sid and object 
	# if 0 check for wildcard sid values for this object and load
	# if 1 load default values for this sid and object
	# if > 1 load default values for this sid and object from first occurance and spit out message
	# Else use defaults
	# (2.05b) - added : as tablename terminator in grep
	local CURRENT_THRESHOLDS=""
	local INdbtab="`${GREP} -c \"^${ORACLE_SID}:${OBJECT_NAME}:\" $DBTAB`"

	case $INdbtab in
		0)  CURRENT_THRESHOLDS="`$GREP \"^@:${OBJECT_NAME}:\" $DBTAB`"
		;;
		1)  CURRENT_THRESHOLDS="`$GREP \"^${ORACLE_SID}:${OBJECT_NAME}:\" $DBTAB`"
		;;
		[2-9999]) CURRENT_THRESHOLDS="`$GREP \"^${ORACLE_SID}:${OBJECT_NAME}:\" $DBTAB|sort -t: -u -k 1,2`"
			echo "Found multiple references to ${ORACLE_SID}:${OBJECT_NAME} in $DBTAB"
		;;
	esac

	# Check if warn-variable is zero
	if test -n "$CURRENT_THRESHOLDS"; then
		typeset -i RED=`echo "$CURRENT_THRESHOLDS"|cut -f 4 -d":"`
		typeset -i YELLOW=`echo "$CURRENT_THRESHOLDS"|cut -f 3 -d":"`
	else
		typeset -i RED=${EXT_RED}
		typeset -i YELLOW=${EXT_YELLOW}
	fi
	#Inorder to allow overide values to be lower we must do this
	if [[ "${EXTENT_PCT}" -lt ${YELLOW} ]] && [[ "${YELLOW}" -le 100 ]]; then
		continue #:

	elif [[ "${EXTENT_PCT}" -ge ${RED} ]]; then
		echo "<br>$SPACER&red Object ${ORACLE_SID}:${OBJECT_NAME} max extents are ${MAX_EXTENTS} with <B><U><FONT COLOR="RED">${EXTENT_PCT}%</FONT></U></B> used."
		[[ "$EXTENT_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
		GOTONE=Y

	elif [[ "${EXTENT_PCT}" -ge ${YELLOW} ]]; then
		echo "<br>$SPACER&yellow Object ${ORACLE_SID}:${OBJECT_NAME} max extents are ${MAX_EXTENTS} with <B><U><FONT COLOR="YELLOW">${EXTENT_PCT}%</FONT></U></B> used."
		[[ "$COLOR" != "red" ]] && COLOR="yellow"
		GOTONE=Y

	elif [[ "${YELLOW}" -gt 100 ]] || [[ "${RED}" -gt 100 ]]; then
		echo "<br>$SPACER&green Overridden (${YELLOW}:${RED}) Object ${ORACLE_SID}:${OBJECT_NAME} max extents are ${MAX_EXTENTS} with <B><U><FONT COLOR="PURPLE">${EXTENT_PCT}%</FONT></U></B> used."
		GOTONE=Y

	fi
done <${TEMPFILE}-extents
[[ "${GOTONE}" = "N" ]] && echo "<br>$SPACER&green No objects are exceeding extent thresholds. Extent test ok."
[[ "$DEBUG" != "Y" ]] && rm -f ${TEMPFILE}-extents
}


################################################################
# Check for shadow processes (LOCAL ONLY)
################################################################
function FUNC_SHADOW_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv
# Check if ORACLE shadow processes are running
local procname=oracle${ORACLE_SID}
local shadowprocs=`${PS}|${GREP} ${ORACLE_USER} | ${GREP} -i $procname | ${GREP} -v -i "LOCAL=NO" | ${GREP} -v grep`
#local shadowprocs=`$PS | $GREP "$ORACLE_USER" | $GREP -i $procname | $GREP -v -i "LOCAL=NO" | $GREP -v `basename $GREP``
if [[ "$shadowprocs" != "" ]]; then
	local ORASTATE="has"
	[[ "$COLOR" != "red" ]] && COLOR="yellow"
	local ORACOLOR=yellow
else
	local ORASTATE="does not have"
	local ORACOLOR=green
fi
echo "<br>$SPACER&${ORACOLOR} Database $ORACLE_SID $ORASTATE shadow entries "
}


################################################################
# Check for pin hit ratio
################################################################
function FUNC_PINLIB_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv
local M_VAR
set -f # turn off globbing

set -A M_VAR `$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF 2>&1
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260
col namespace heading 'Type' format a15
col pins heading 'Pins' format 999,999,999
col reloads heading 'Reloads' format 99,999,999
col pin_pct heading 'Pin|Percent' format 99,999.99
col pin_pctr heading 'Pin|PercentR' format 99,999
col action heading 'Recommended Action' format a30
select namespace,
reloads,
pins,
pins/(pins+reloads)*100 pin_pct,
pins/(pins+reloads)*100 pin_pctr
FROM v\\$librarycache
where namespace in ('SQLAREA', 'TABLE/PROCEDURE', 'BODY', 'TRIGGER')
and pins+reloads > 0
/
EOF
`

local VAR0=0
if [[ "${M_VAR[$VAR0]}" = "FROM" ]] || [[ "${M_VAR[0]}" = "ERROR:" ]]; then
	echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
	[[ "$PINLIB_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
	return
fi

local VAR1=1
local VAR2=2
local VAR3=3
local VAR4=4

local M_VAR_LEN=${#M_VAR[*]}
while [[ "$VAR0" -lt "$M_VAR_LEN" ]]; do
	### Nice for debugging
	#echo "Namespace name = ${M_VAR[$VAR0]}"
	#echo "Reloads = ${M_VAR[$VAR1]}"
	#echo "Pins = ${M_VAR[$VAR2]}"
	#echo "HIT_PCT = ${M_VAR[$VAR3]}%"

	local NAMESPACE_NAME=${M_VAR[$VAR0]}
	local RELOADS=${M_VAR[$VAR1]}
	local PINS=${M_VAR[$VAR2]}
	local HIT_PCT=${M_VAR[$VAR3]}
        local HIT_PCTR=${M_VAR[$VAR4]}

	#Normally red=97 yellow=94
	if [[ "${HIT_PCTR}" -lt "${PINLIB_RED}" ]]; then
		echo "<br>$SPACER&red Namespace ${ORACLE_SID}:${NAMESPACE_NAME} has ${RELOADS} reloads, ${PINS} pins and a <B><U><FONT COLOR="RED">${HIT_PCT}%</FONT></U></B> hit ratio."

		[[ "$PINLIB_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'

	elif [[ "${HIT_PCTR}" -lt "${PINLIB_YELLOW}" ]]; then
		echo "<br>$SPACER&yellow Namespace ${ORACLE_SID}:${NAMESPACE_NAME} has ${RELOADS} reloads, ${PINS} pins and a <B><U><FONT COLOR="YELLOW">${HIT_PCT}%</FONT></U></B> hit ratio."

		[[ "$COLOR" != "red" ]] && COLOR="yellow"
	else
		echo "<br>$SPACER&green Namespace ${ORACLE_SID}:${NAMESPACE_NAME} has ${RELOADS} reloads, ${PINS} pins and a <B>${HIT_PCT}%</B> hit ratio."
	fi

        ((VAR0=VAR0+5))
        ((VAR1=VAR1+5))
        ((VAR2+=5))
        ((VAR3+=5))
        ((VAR4+=5))
done
}

################################################################
# Check SQL AREA hit ratio
# (This could have been lumped with the previous test, but it was easier to
# put it here.  Probably should clean it up some day.
################################################################
function FUNC_SQLAREA_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv
local M_VAR
set -f # turn off globbing

set -A M_VAR `$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF 2>&1
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260
col get_pct heading 'Hit Ratio' format 999.99
col get_pctr heading 'Hit Ratio Round' format 999
col action heading 'Recommended Action' format a30
select gethitratio*100 get_pct,
        gethitratio*100 get_pctr
        FROM v\\$librarycache
        where namespace = 'SQL AREA'
/
EOF
`

local VAR0=0
local VAR1=1

if [[ "${M_VAR[$VAR0]}" = "FROM" ]] || [[ "${M_VAR[0]}" = "ERROR:" ]]; then
        echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
        [[ "$SQLAREA_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
        return
fi

local M_VAR_LEN=${#M_VAR[*]}
while [[ "$VAR0" -lt "$M_VAR_LEN" ]]; do
        ### Nice for debugging
        #echo "HITRATIO=${M_VAR[$VAR0]}"

        local HITRATIO=${M_VAR[$VAR0]}
        local HITRATIOR=${M_VAR[$VAR1]}

        #Normally red=75 yellow=85
        if [[ "${HITRATIOR}" -lt "${SQLAREA_RED}" ]]; then
		echo "<br>$SPACER&red Object ${ORACLE_SID}: Hit ratio for SQL AREA is <B><U><FONT COLOR="RED">${HITRATIO}%</FONT></U></B>.  Extremely low."

		[[ "$SQLAREA_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'

	elif [[ "${HITRATIOR}" -lt "${SQLAREA_YELLOW}" ]]; then
		echo "<br>$SPACER&yellow Object ${ORACLE_SID}: Hit ratio for SQL AREA is <B><U><FONT COLOR="YELLOW">${HITRATIO}%</FONT></U></B>.  Low."

		[[ "$COLOR" != "red" ]] && COLOR="yellow"

	else
		echo "<br>$SPACER&green Object ${ORACLE_SID}: Hit Ratio for SQL AREA is <B>${HITRATIO}%</B>.  Normal."
	fi
	((VAR0+=2))
	((VAR1+=2))
done
}


################################################################
# Check for Block buffer hit ratio
################################################################
function FUNC_BLOCK_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv
local M_VAR
set -f # turn off globbing

set -A M_VAR `$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF 2>&1
set pagesize 0
set linesize 2048
set heading off
set feedback off
col cnstnt_gets heading 'Consistent|Gets' format 9,999,999,999
col block_gets heading 'Block|Gets' format 9,999,999,999,999
col phys_reads heading 'Physical|Reads' format 999,999,999
col hit_ratio heading 'Hit|Ratio' format 999.9999999
col hit_ratior heading 'Hit|RatioR' format 999
col message heading 'Required Action' format a30
select  sum(decode(name,'consistent gets', value,0)) cnstnt_gets,
sum(decode(name,'db block gets', value,0)) block_gets,
sum(decode(name,'physical reads', value,0)) phys_reads,
(sum(decode(name,'consistent gets', value,0)) +
sum(decode(name,'db block gets', value,0)) -
sum(decode(name,'physical reads', value,0))) /
(sum(decode(name,'consistent gets', value,0)) +
sum(decode(name,'db block gets', value,0)) ) * 100 hit_ratio,
(sum(decode(name,'consistent gets', value,0)) +
sum(decode(name,'db block gets', value,0)) -
sum(decode(name,'physical reads', value,0))) /
(sum(decode(name,'consistent gets', value,0)) +
sum(decode(name,'db block gets', value,0)) ) * 100 hit_ratior
FROM v\\$sysstat
/
EOF
`

local VAR0=0
if [[ "${M_VAR[$VAR0]}" = "FROM" ]] || [[ "${M_VAR[0]}" = "ERROR:" ]]; then
        echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
        [[ "$BLOCK_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
        return
fi

local VAR1=1
local VAR2=2
local VAR3=3
local VAR4=4
local M_VAR_LEN=${#M_VAR[*]}
### Nice for debugging
#echo "CNSTNT_GETS = ${M_VAR[$VAR0]}"
#echo "BLOCK_GETS = ${M_VAR[$VAR1]}"
#echo "PHYS_READS = ${M_VAR[$VAR2]}"
#echo "BBUF_HIT_PCT = ${M_VAR[$VAR3]}"

local CNSTNT_GETS=${M_VAR[$VAR0]}
local BLOCK_GETS=${M_VAR[$VAR1]}
local PHYS_READS=${M_VAR[$VAR2]}
local BBUF_HIT_PCT=${M_VAR[$VAR3]}
local BBUF_HIT_PCTR=${M_VAR[$VAR4]}


#Normally red=75 yellow=85
if [[ "${BBUF_HIT_PCTR}" -lt "${BLOCK_BUF_RED}" ]]; then
	echo "<br>$SPACER&red Object ${ORACLE_SID}: Block Buffer Hit Ratio is <B><U><FONT COLOR="RED">${BBUF_HIT_PCT}%</FONT></U></B>.  Extremely low."

	[[ "$BLOCK_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'

elif [[ "${BBUF_HIT_PCTR}" -lt "${BLOCK_BUF_YELLOW}" ]]; then
	echo "<br>$SPACER&yellow Object ${ORACLE_SID}: Block Buffer Hit Ratio is <B><U><FONT COLOR="YELLOW">${BBUF_HIT_PCT}%</FONT></U></B>.  Low."

	[[ "$COLOR" != "red" ]] && COLOR="yellow"

else
	echo "<br>$SPACER&green Object ${ORACLE_SID}: Block Buffer Hit Ratio is <B>${BBUF_HIT_PCT}%</B>.  Normal."
fi
}


################################################################
# Check for Shared Memory
################################################################
function FUNC_MEMREQ_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv
local M_VAR
set -f # turn off globbing

set -A M_VAR `$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF 2>&1
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260

select round(free_space/1024), round(avg_free_size/1024), round(used_space/1024),
round(avg_used_size/1024), request_failures, round(last_failure_size/1024)
FROM v\\$shared_pool_reserved
/
EOF
`

if [[ "${M_VAR[0]}" = "FROM" ]] || [[ "${M_VAR[0]}" = "ERROR:" ]]; then
	echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
	[[ "$MEMREQ_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
	return
fi

local M_VAR_LEN=${#M_VAR[*]}
### Nice for debugging
#echo "ALL = ${M_VAR[*]}" >> /tmp/x
#echo "Free_Space = ${M_VAR[0]}" >> /tmp/x
#echo "Avg_Free_Space = ${M_VAR[1]}" >> /tmp/x
#echo "Used_Space = ${M_VAR[2]}" >> /tmp/x
#echo "Avg_Used_Space = ${M_VAR[3]}%" >> /tmp/x
#echo "Request Failures = ${M_VAR[4]}%" >> /tmp/x
#echo "Last_Failure_Size = ${M_VAR[5]}%" >> /tmp/x
#echo "----------------------------------------" >> /tmp/x
local FREE_SPACE=${M_VAR[0]}
local AVG_FREE_SPACE=${M_VAR[1]}
local USED_SPACE=${M_VAR[2]}
local AVG_USED_SPACE=${M_VAR[3]}
local REQ_FAILURES=${M_VAR[4]}
local LAST_FAIL_SIZE=${M_VAR[5]}

# Any failure is a bad thing
if [[ "$REQ_FAILURES" -gt 0 ]]; then
	echo "<br>$SPACER&red Database ${ORACLE_SID}: <B><U><FONT COLOR="RED">${REQ_FAILURES}</FONT></U></B> Request Failures, Last Failed size is <B><U><FONT COLOR="RED">${LAST_FAIL_SIZE}.</FONT></U></B>."
	[[ "$MEMREQ_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
else
	echo "<br>$SPACER&green Database ${ORACLE_SID}: No Request Failures."
fi

# get the lessor of free and average free
local CHECK_SPACE=`[[ $FREE_SPACE -gt $AVG_FREE_SPACE ]] && echo $AVG_FREE_SPACE || echo $FREE_SPACE `

# Check memory free space
#Normally red=15 yellow=30
if [[ "${CHECK_SPACE}" -le "${MEMREQ_RED}" ]]; then
	echo "<br>$SPACER&red Object ${ORACLE_SID}: Memory request free space <B><U><FONT COLOR="RED">${CHECK_SPACE}K</FONT></U></B>.  is extremely low."

	[[ "$MEMREQ_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'

elif [[ "${CHECK_SPACE}" -le "${MEMREQ_YELLOW}" ]]; then
	echo "<br>$SPACER&yellow Object ${ORACLE_SID}: Memory request free space <B><U><FONT COLOR="YELLOW">${CHECK_SPACE}K</FONT></U></B>.  is low."

	[[ "$COLOR" != "red" ]] && COLOR="yellow"
fi

echo "<br><br>$SPACER   Free Space is ${FREE_SPACE}K, AVG Free Space is ${AVG_FREE_SPACE}K, Used Space is ${USED_SPACE}K, AVG Used Space is ${AVG_USED_SPACE}K."
}

################################################################
# Check ROLLBACK ratio
# (This could have been lumped with the previous test, but it was easier to
# put it here.  Probably should clean it up some day.
################################################################
function FUNC_ROLBAK_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv
local M_VAR
set -f # turn off globbing

set -A M_VAR `$SQLPLUS -s $DB_USER/$DB_PASSWORD <<-EOF 2>&1
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260
column RBTYPE heading "Rollback Type"   format a30
column USAGE_PCT heading "Usage Percent"        format 999.99
column USAGE_PCTR heading "Usage Percent Round"        format 999

select a.ROLLBACK_TYPE RBTYPE, round((b.USED_KB / a.TOTAL_KB * 100),2) USAGE_PCT, b.USED_KB / a.TOTAL_KB * 100 USAGE_PCTR
from ( select sum(bytes)/1024 TOTAL_KB, decode(tablespace_name,'SYSTEM','SYSTEM','NON-SYSTEM')
ROLLBACK_TYPE from dba_data_files where tablespace_name in (select tablespace_name from dba_rollback_segs)
group by decode(tablespace_name,'SYSTEM','SYSTEM','NON-SYSTEM') ) a, ( select sum(bytes)/1024 USED_KB,
decode(tablespace_name,'SYSTEM','SYSTEM','NON-SYSTEM') ROLLBACK_TYPE from dba_extents
where tablespace_name in (select tablespace_name from dba_rollback_segs)
group by decode(tablespace_name,'SYSTEM','SYSTEM','NON-SYSTEM') ) b where a.ROLLBACK_TYPE = b.ROLLBACK_TYPE;
EOF
`

local VAR0=0
local VAR1=1
local VAR2=2
local M_VAR_LEN=${#M_VAR[*]}

if [[ "${M_VAR[$VAR0]}" = "FROM" ]] || [[ "${M_VAR[0]}" = "ERROR:" ]] || [[ "${M_VAR[$VAR0]}" = "where" ]] ; then
        echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
        [[ "$ROLBAK_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
        return
fi

while [[ "$VAR0" -lt "$M_VAR_LEN" ]]; do
        local ROLBAKTYPE=${M_VAR[$VAR0]}
        local ROLBAKPCT=${M_VAR[$VAR1]}
        local ROLBAKPCTR=${M_VAR[$VAR2]}

        #Normally red=85 yellow=75
        if [[ "${ROLBAKPCTR}" -ge "${ROLBAK_RED}" ]]; then
		echo "<br>$SPACER&red Object ${ORACLE_SID}:${ROLBAKTYPE} Rollback percentage is <B><U><FONT COLOR="RED">${ROLBAKPCT}%</FONT></U></B>.  Extremely High."

		[[ "$ROLBAK_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'

	elif [[ "${ROLBAKPCTR}" -ge "${ROLBAK_YELLOW}" ]]; then
		echo "<br>$SPACER&yellow Object ${ORACLE_SID}:${ROLBAKTYPE} Rollback percentage is <B><U><FONT COLOR="YELLOW">${ROLBAKPCT}%</FONT></U></B>.  Low."

		[[ "$COLOR" != "red" ]] && COLOR="yellow"

	else
		echo "<br>$SPACER&green Object ${ORACLE_SID}:${ROLBAKTYPE} Rollback percentage is <B>${ROLBAKPCT}%</B>.  Normal."
	fi

	((VAR0+=3))
	((VAR1+=3))
	((VAR2+=3))
done
}

################################################################
# Check for Users and Transactions (Dead Locks, et all)
################################################################
function FUNC_DEAD_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv
local M_VAR
set -f # turn off globbing

set -A M_VAR `$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF 2>&1
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260
set heading off
SELECT   SID, DECODE(BLOCK, 0, 'NO', 'YES' ) BLOCKER, DECODE(REQUEST, 0, 'NO','YES' ) WAITER
FROM     V\\$LOCK
WHERE    REQUEST > 0 OR BLOCK > 0
ORDER BY block DESC;
EOF
`

if [[ "${M_VAR[0]}" = "FROM" ]] || [[ "${M_VAR[0]}" = "ERROR:" ]]; then
	echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
	[[ "$INVOBJ_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
	return
fi
local VAR0=0 # sid
local VAR1=1 # blocking
local VAR2=2 # waiting
local M_VAR_LEN=${#M_VAR[*]}
while [[ "$VAR0" -lt "$M_VAR_LEN" ]]; do
	echo "<br>$SPACER&red <B><U><FONT COLOR="RED">SID ${VAR0}</FONT></U></B> Blocker ${VAR1} Requester ${VAR2}."
	[[ "$DEAD_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
        ((VAR0=VAR0+3))
        ((VAR1=VAR1+3))
        ((VAR2=VAR2+3))
done
if [[ ${VAR0} -eq 0 ]]; then
	echo "<br>$SPACER&green Database ${ORACLE_SID}: No deadlocks detected."
fi
}
################################################################
# Check for Invalid Database Objects
################################################################
function FUNC_INVOBJ_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv

# skip if we must
$GREP "^I:${ORACLE_SID}:@$" $DBTAB >/dev/null 2>&1
if [[ "$?" -eq 0 ]];then
	echo "<br>$SPACER&green Ignoring <B><U><FONT COLOR ="PURPLE">${Status}</FONT></U></B> all object tests in ${ORACLE_SID}."
	return
fi

rm -f ${TEMPFILE}-invalid

$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF > ${TEMPFILE}-invalid 2>&1
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260
set heading off
col OWNER heading 'Owner' format A12
col OBJECT_NAME heading 'Name' format a30
col OBJECT_TYPE heading 'Type' format a20
col STATUS heading 'Status' format a7
SELECT  OWNER, OBJECT_NAME, translate(OBJECT_TYPE,' ','_'), STATUS FROM DBA_OBJECTS
WHERE STATUS = 'INVALID' AND OBJECT_NAME not like 'BIN_%'
ORDER BY OWNER, OBJECT_TYPE, OBJECT_NAME;
EOF

local M_VAR
set -f # turn off globbing

set -A M_VAR ` cat ${TEMPFILE}-invalid `

if [[ "${M_VAR[0]}" = "FROM" ]] || [[ "${M_VAR[0]}" = "ERROR:" ]]; then
	echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
	[[ "$INVOBJ_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
	return
fi

local VAR0=0
local VAR1=1
local VAR2=2
local VAR3=3
local M_VAR_LEN=${#M_VAR[*]}
local GOTONE=N

[[ ! -s ${TEMPFILE}-invalid ]] && M_VAR_LEN=0

while [[ "$VAR0" -lt "$M_VAR_LEN" ]]; do

### Nice for debugging
#echo "M_VAR_LEN = ${M_VAR_LEN}"
#echo "OWNER = ${M_VAR[$VAR0]}"
#echo "OBJECT = ${M_VAR[$VAR1]}"
#echo "TYPE = ${M_VAR[$VAR2]}"
#echo "STATUS = ${M_VAR[$VAR3]}"

	Owner="${M_VAR[$VAR0]}"
	Object="${M_VAR[$VAR1]}"
	Type="${M_VAR[$VAR2]}"
	Status="${M_VAR[$VAR3]}"

        local INdbtab="`${GREP} \"^I:${ORACLE_SID}:${Type}:${Object}[ 	]*$\" $DBTAB >/dev/null 2>&1;echo $?`"

        if [[ $INdbtab -eq 1 ]];then
        	INdbtab="`${GREP} \"^I:${ORACLE_SID}:${Type}[ 	:]*$\" $DBTAB >/dev/null 2>&1;echo $?`"
	fi

        # Check if we are ignoring this object
        if [[ "$INdbtab" -eq 0 ]]; then
                echo "<br>$SPACER&green Ignoring <B><U><FONT COLOR ="PURPLE">${Status}</FONT></U></B> ${Type} ${Object} owned by ${Owner}."
        else
		echo "<br>$SPACER&red <B><U><FONT COLOR="RED">${Status}</FONT></U></B> ${Type} ${Object} owned by ${Owner}."
                GOTONE=Y

                [[ "$INVOBJ_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
        fi

        ((VAR0+=4))
        ((VAR1+=4))
        ((VAR2+=4))
        ((VAR3+=4))
done

[[ "${GOTONE}" = "N" ]] && echo "<br>$SPACER&green No invalid objects found. Invalid test ok."

[[ "$DEBUG" != "Y" ]] && rm -f ${TEMPFILE}-invalid
}

################################################################
# LOCAL PROCESSES CHECK function
################################################################
function FUNC_PROCESSES_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv
local V_VAR
set -f # turn off globbing
set -A V_VAR `$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF 2>&1
set pagesize 0
set linesize 2048
set heading off
set feedback off
column USED format 999.99
select  value from v\\$parameter where name = 'processes';
exit;
EOF
`

local C_VAR
set -f # turn off globbing
set -A C_VAR `$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF 2>&1
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260
column COUNT format 999
select count(*) from v\\$process;
exit;
EOF
`

if [[ "${V_VAR[0]}" = "select" ]]; then
    echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
    [[ "$PROCESSES_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
    return
fi

local LIMIT=${V_VAR[0]}
local COUNT=${C_VAR[0]}

local RATIO=$(($COUNT * 100 / $LIMIT))
#local RATIO=`echo " ( $COUNT *100 ) /$LIMIT " | bc`
#echo "LIMIT=${V_VAR[0]} COUNT=${C_VAR[0]} ratio $RATIO"
#echo "processes:red $PROCESSES_RED yellow $PROCESSES_YELLOW notify $PROCESSES_NOTIFY"

if [[ "${RATIO}" -gt "${PROCESSES_RED}" ]]; then
    echo "<br>$SPACER&red Object ${ORACLE_SID}: Process utilization is <B><U><FONT COLOR="RED">${RATIO}%</FONT></U></B>.  High."

    [[ "$PROCESSES_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'

elif [[ "${RATIO}" -gt "${PROCESSES_YELLOW}" ]]; then
    echo "<br>$SPACER&yellow Object ${ORACLE_SID}: Process utilization is <B><U><FONT COLOR="YELLOW">${RATIO}%</FONT></U></B>.  High."

    [[ "$COLOR" != "red" ]] && COLOR="yellow"
else
    echo "<br>$SPACER&green Object ${ORACLE_SID}: Process utilization is  <B>${RATIO}%</B>.  Normal. (${COUNT}:${LIMIT})"
fi
}

################################################################
# LOCAL SESSIONS CHECK function
################################################################
function FUNC_SESSIONS_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv
local V_VAR
set -f # turn off globbing
set -A V_VAR `$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF 2>&1
set pagesize 0
set linesize 2048
set heading off
set feedback off
column USED format 999.99
select  value from v\\$parameter where name = 'sessions';
exit;
EOF
`

local C_VAR
set -f # turn off globbing
set -A C_VAR `$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF 2>&1
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260
column COUNT format 999
select count(*) from v\\$session;
exit;
EOF
`

if [[ "${V_VAR[0]}" = "select" ]]; then
	echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
	[[ "$SESSIONS_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
	return
fi

local LIMIT=${V_VAR[0]}
local COUNT=${C_VAR[0]}
local RATIO=$(($COUNT * 100 / $LIMIT))
#local RATIO=`echo " ( $COUNT *100 ) /$LIMIT " | bc`
#echo "LIMIT=${V_VAR[0]} COUNT=${C_VAR[0]} ratio $RATIO"
#echo "sessions:red $SESSIONS_RED yellow $SESSIONS_YELLOW notify $SESSIONS_NOTIFY"

if [[ "${RATIO}" -gt "${SESSIONS_RED}" ]]; then
	echo "<br>$SPACER&red Object ${ORACLE_SID}: Sessions utilization is <B><U><FONT COLOR="RED">${RATIO}%</FONT></U></B>.  High."

	[[ "$SESSIONS_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'

elif [[ "${RATIO}" -gt "${SESSIONS_YELLOW}" ]]; then
	echo "<br>$SPACER&yellow Object ${ORACLE_SID}: Sessions utilization is <B><U><FONT COLOR="YELLOW">${RATIO}%</FONT></U></B>.  High."
	[[ "$COLOR" != "red" ]] && COLOR="yellow"
else
	echo "<br>$SPACER&green Object ${ORACLE_SID}: Sessions utilization is <B>${RATIO}%</B>.  Normal. (${COUNT}:${LIMIT})"
fi
}

#
################################################################
# LOCAL STATISTICS CHECK function
# Added 28/08/06 by Hans Christian Studt
################################################################
function FUNC_STATISTICS_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv

rm -f ${TEMPFILE}-stat

## echo "<pre>"

rm -f ${TEMPFILE}-stat2

$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF > ${TEMPFILE}-stat2 2>&1
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260
set heading off
col OWNER heading 'Owner' format A12
col OBJECT_NAME heading 'Name' format a30
col OBJECT_TYPE heading 'Type' format a20
col STATUS heading 'Status' format a7
col LDAYS heading 'LDAYS' format 99999
select
       'Index '
    || OWNER
    || '.'
    || INDEX_NAME
     , LAST_ANALYZED
     --- , round(mod(((sysdate-LAST_ANALYZED)*1000),1)*100) AS LDAYS
     , round ( sysdate - LAST_ANALYZED ) AS LDAYS
  from
       all_indexes
 where
     (
       ( sysdate - LAST_ANALYZED ) >= ${STATISTICS_YELLOW}
    or
       ( sysdate - LAST_ANALYZED ) >= ${STATISTICS_RED}
     )
   and
       ROWNUM <= 100
   --- and
       --- INDEX_NAME like 'D%'
UNION
select
       'Table '
    || OWNER
    || '.'
    || TABLE_NAME
     , LAST_ANALYZED
     --- , round(mod(((sysdate-LAST_ANALYZED)*1000),1)*100) AS LDAYS
     , round ( sysdate - LAST_ANALYZED ) AS LDAYS
  from
       all_tables
 where
     (
       ( sysdate - LAST_ANALYZED ) >= ${STATISTICS_YELLOW}
    or
       ( sysdate - LAST_ANALYZED ) >= ${STATISTICS_RED}
     )
   and
       ROWNUM <= 100
   --- and
       --- TABLE_NAME like 'D%'
--COL-- UNION
--COL-- select
--COL--        'Column '
--COL--     || OWNER
--COL--     || '.'
--COL--     || TABLE_NAME
--COL--     || '.'
--COL--     || COLUMN_NAME
--COL--      , LAST_ANALYZED
--COL--      , round ( sysdate - LAST_ANALYZED ) AS LDAYS
--COL--   from
--COL--        ALL_TAB_COLUMNS
--COL--  where
--COL--      (
--COL--        ( sysdate - LAST_ANALYZED ) >= ${STATISTICS_YELLOW}
--COL--     or
--COL--        ( sysdate - LAST_ANALYZED ) >= ${STATISTICS_RED}
--COL--      )
--COL--    and
--COL--        ROWNUM <= 100
--COL--    --- and
--COL--        --- TABLE_NAME like 'D%'
--COL--    --- and
--COL--        --- COLUMN_NAME like 'D%'
 order by
       3 ASC
     , 2 ASC
     , 1 DESC
       ;
EOF

## date
## ls -o ${TEMPFILE}-stat2
## cat   ${TEMPFILE}-stat2

local S_VAR
set -f # turn off globbing

set -A S_VAR ` cat ${TEMPFILE}-stat2 `

## date
## echo "# S_VAR[0] = '${S_VAR[0]}'"
## echo "# S_VAR[1] = '${S_VAR[1]}'"
## echo "# S_VAR[2] = '${S_VAR[2]}'"
## echo "# S_VAR[3] = '${S_VAR[3]}'"

### echo "# ORACLE_SID = '${ORACLE_SID}'"

  ## if [[ "${V_TOTUSR}" -gt "${R_MINUSR}" ]]
  ## then

local CNT_RED=0
local CNT_YEL=0

## echo "# STATISTICS_RED = '${STATISTICS_RED}'"
## echo "# STATISTICS_YELLOW = '${STATISTICS_YELLOW}'"

local VAR0=0
local VAR1=1
local VAR2=2
local VAR3=3
local S_VAR_LEN=${#S_VAR[*]}
local GOTONE=N

## echo "# S_VAR_LEN = '${S_VAR_LEN}'"

[[ "${S_VAR_LEN}" -gt "999" ]] && S_VAR_LEN=999

## echo "# S_VAR_LEN = '${S_VAR_LEN}'"

[[ ! -s ${TEMPFILE}-stat2 ]] && S_VAR_LEN=0

## echo "# S_VAR_LEN = '${S_VAR_LEN}'"

while [[ "$VAR0" -lt "$S_VAR_LEN" ]]; do

## echo "# VAR0,1,2,3 = '${VAR0}','${VAR1}','${VAR2}','${VAR3}'"

    local LTYPE=${S_VAR[VAR0]}
    local LNAME=${S_VAR[VAR1]}
    local LDATE=${S_VAR[VAR2]}
    local LDAYS=${S_VAR[VAR3]}

## echo "# LTYPE = '${LTYPE}'"
## echo "# LNAME = '${LNAME}'"
## echo "# LDATE = '${LDATE}'"
## echo "# LDAYS = '${LDAYS}'"

    if [[ "${LDAYS}" -ge "${STATISTICS_RED}" ]]; then
        GOTONE=Y
        ((CNT_RED+=1))
        if [[ "${CNT_RED}" -le "10" ]]; then
          echo "<br>$SPACER&red ${ORACLE_SID}: ${LTYPE} ${LNAME} was last analysed on ${LDATE} which is <B><U><FONT COLOR="RED">${LDAYS}</FONT></U></B> days ago.  Very Old. (>=${STATISTICS_RED})" >> ${TEMPFILE}-stat
        fi
        [[ "$STATISTICS_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'

    elif [[ "${LDAYS}" -ge "${STATISTICS_YELLOW}" ]]; then
        GOTONE=Y
        ((CNT_YEL+=1))
        if [[ "${CNT_YEL}" -le "10" ]]; then
          echo "<br>$SPACER&yellow ${ORACLE_SID}: ${LTYPE} ${LNAME} was last analysed on ${LDATE} which is <B><U><FONT COLOR="RED">${LDAYS}</FONT></U></B> days ago.  Quite Old. (>=${STATISTICS_YELLOW})" >> ${TEMPFILE}-stat
        fi
        [[ "$COLOR" != "red" ]] && COLOR="yellow"
    fi

  ((VAR0+=4))
  ((VAR1+=4))
  ((VAR2+=4))
  ((VAR3+=4))

done

## echo "</pre>"

if [[ "${GOTONE}" = "N" ]]; then
  echo "<br>$SPACER&green No statistics were analysed too long ago.  Normal. (${STATISTICS_YELLOW}:${STATISTICS_RED})" >> ${TEMPFILE}-stat
else
  if [[ "${CNT_RED}" -gt "0" ]]; then
    echo "<br>${CNT_RED} statistics were very old (RED)" >> ${TEMPFILE}-stat
  fi
  if [[ "${CNT_YEL}" -gt "0" ]]; then
    echo "<br>${CNT_YEL} statistics were guite old (YELLOW)" >> ${TEMPFILE}-stat
  fi
fi

cat ${TEMPFILE}-stat

[[ "$DEBUG" != "Y" ]] && rm -f ${TEMPFILE}-stat
[[ "$DEBUG" != "Y" ]] && rm -f ${TEMPFILE}-stat2

}

#
################################################################
# LOCAL RAC_SESSIONS CHECK function
# Added 28/08/06 by Hans Christian Studt
################################################################
function FUNC_RAC_SESSIONS_CHECK
{
[[ "$DEBUG" = "Y" ]] && set -xv

rm -f ${TEMPFILE}-rac

echo "<pre>"

rm -f ${TEMPFILE}-rac2

$SQLPLUS -s $DB_USER/$DB_PASSWORD <<EOF > ${TEMPFILE}-rac2 2>&1
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260
set heading off
col OWNER heading 'Owner' format A12
col OBJECT_NAME heading 'Name' format a30
col OBJECT_TYPE heading 'Type' format a20
col STATUS heading 'Status' format a7
select
       INST_NAME
  from v\$active_instances
 order by INST_NUMBER
       ;
EOF

local R_VAR
set -f # turn off globbing

set -A R_VAR ` cat ${TEMPFILE}-rac2 `

## date
## echo "# R_VAR[0] = '${R_VAR[0]}'"
## echo "# R_VAR[1] = '${R_VAR[1]}'"
## echo "# R_VAR[2] = '${R_VAR[2]}'"

## date
## echo "# R_VAR[0] = '${R_VAR[0]}'"
## echo "# R_VAR[1] = '${R_VAR[1]}'"
## echo "# R_VAR[2] = '${R_VAR[2]}'"

### echo "# ORACLE_SID = '${ORACLE_SID}'"

### echo "# RAC_SIDS = '${RAC_SIDS}'"

RAC_SIDS=` cat ${TEMPFILE}-rac2 `

### echo "# RAC_SIDS = '${RAC_SIDS}'"

local V_TOTUSR=0
local V_TOTSYS=0
local V_TOTUSRPCT=0
local V_TOTSYSPCT=0

local S_LIST=""

local R_CNT=0
local R_MINUSR=0

for RAC in ${RAC_SIDS}
do

  ### echo "# RAC = '${RAC}'"

  ((R_CNT+=1))

  ### echo "# R_CNT = '${R_CNT}'"
  ### date

  RAC_SRV=` echo "${RAC}" | cut -d: -f1 `
  RAC_SID=` echo "${RAC}" | cut -d: -f2 `

  ### echo "# RAC_SRV = '${RAC_SRV}'"
  ### echo "# RAC_SID = '${RAC_SID}'"

  local V_VAR

  set -f # turn off globbing
  set -A V_VAR `$SQLPLUS -s $DB_USER/$DB_PASSWORD@$RAC_SID <<EOF 2>&1
set feedback off
set pagesize 0
set trimspool on
ttitle off
btitle off
set verify off
set linesize 260
column COUNT format 999
select count(*) from v\\$session
 where
   not
     (
       UPPER(osuser)     like 'DEAMON'
    or
       UPPER(osuser)     like 'ORACLE'
     )
       ;
select count(*) from v\\$session
 where
     (
       UPPER(osuser)     like 'DEAMON'
    or
       UPPER(osuser)     like 'ORACLE'
     )
      ;
exit;
EOF
`

### echo "# V_VAR[0] = '${V_VAR[0]}'"
### echo "# V_VAR[1] = '${V_VAR[1]}'"
### echo "# V_VAR[2] = '${V_VAR[2]}'"

  if [[ "${V_VAR[0]}" = "select" ]]; then
        echo "<br>ERROR: invalid permissions for user (${DB_USER}) in ${ORACLE_SID}"
        [[ "$RAC_SESSIONS_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'
        return
  fi

  local V_USR=${V_VAR[0]}
  local V_SYS=${V_VAR[1]}
  local V_SES=$(( V_USR + V_SYS ))

### echo "# V_USR = '${V_USR}'"
### echo "# V_SYS = '${V_SYS}'"
### echo "# V_SES = '${V_SES}'"

  local R_MINUSR=$(( R_MINUSR + RAC_SESSIONS_PR_SERV ))

### echo "# R_MINUSR = '${R_MINUSR}'"

  local V_TOTUSR=$(( V_TOTUSR + V_USR ))
  local V_TOTSYS=$(( V_TOTSYS + V_SYS ))
  local V_TOTSES=$(( V_TOTSES + V_SES ))

### echo "# V_TOTUSR = '${V_TOTUSR}'"
### echo "# V_TOTSYS = '${V_TOTSYS}'"
### echo "# V_TOTSES = '${V_TOTSES}'"

  local S_LIST="${S_LIST} ${V_VAR[0]} ${V_VAR[1]}"

### echo "# S_LIST = '${S_LIST}'"

done

if [[ "${R_CNT}" -gt "0" ]]
then
  local V_USRFAI=$(( ( V_TOTUSR + R_CNT - 1 ) / R_CNT ))
  local V_SESFAI=$(( ( V_TOTSES + R_CNT - 1 ) / R_CNT ))
fi

### echo "# V_USRFAI = '${V_USRFAI}'"
### echo "# V_SESFAI = '${V_SESFAI}'"

### echo "# R_MINUSR = '${R_MINUSR}'"
### date

local VAR0=0
local VAR1=1

set -A V_VAR ` echo ${S_LIST} `

echo "                       User              Fair      All              Fair"
echo "Server:Instance    sessions  Procent    share sessions  Procent    share"
echo "------------------ -------- -------- -------- -------- -------- --------"

for RAC in $RAC_SIDS
do

### echo "# RAC = '${RAC}'"

  RAC_SRV=` echo "${RAC}" | cut -d: -f1 `
  RAC_SID=` echo "${RAC}" | cut -d: -f2 `

  ### echo "# RAC_SRV = '${RAC_SRV}'"
  ### echo "# RAC_SID = '${RAC_SID}'"

  local V_USR=${V_VAR[VAR0]}
  local V_SYS=${V_VAR[VAR1]}
  local V_SES=$(( V_USR + V_SYS ))

### echo "# V_USR = '${V_USR}'"
### echo "# V_SYS = '${V_SYS}'"
### echo "# V_SES = '${V_SES}'"

  local V_USRPCT=$(( ( V_USR * 100 ) / V_TOTUSR ))
  local V_SESPCT=$(( ( V_SES * 100 ) / V_TOTSES ))

### echo "# V_USRPCT = '${V_USRPCT}'"
### echo "# V_SESPCT = '${V_SESPCT}'"

  local V_USRFAIPCT=$(( ( V_USR * 100 ) / V_USRFAI ))
  local V_SESFAIPCT=$(( ( V_SES * 100 ) / V_SESFAI ))

### echo "# V_USRFAIPCT = '${V_USRFAIPCT}'"
### echo "# V_SESFAIPCT = '${V_SESFAIPCT}'"

  local V_TOTUSRPCT=$(( V_TOTUSRPCT + V_USRPCT ))
  local V_TOTSESPCT=$(( V_TOTSESPCT + V_SESPCT ))

### echo "# V_TOTUSRPCT = '${V_TOTUSRPCT}'"
### echo "# V_TOTSESPCT = '${V_TOTSESPCT}'"

  echo "${RAC} ${V_USR} ${V_USRPCT} ${V_USRFAIPCT} ${V_SES} ${V_SESPCT} ${V_SESFAIPCT}"  \
| awk '{ printf("%-18.18s %8d %6d %% %6d %% %8d %6d %% %6d %%\n", $1,$2,$3,$4,$5,$6,$7) }'

  if [[ "${V_TOTUSR}" -gt "${R_MINUSR}" ]]
  then

    local LIMIT=${V_TOTUSR}
    local COUNT=${V_USR}
    local RATIO=$(($COUNT * 100 / $LIMIT))

    if [[ "${RATIO}" -lt "${RAC_SESSIONS_RED}" ]]; then
        echo "<br>$SPACER&red Object ${ORACLE_SID}: RAC Sessions utilization on ${RAC} is <B><U><FONT COLOR="RED">${RATIO}%</FONT></U></B>.  Very Low. (<${RAC_SESSIONS_RED})" >> ${TEMPFILE}-rac

        [[ "$RAC_SESSIONS_NOTIFY" = "N" ]] && [[ "$COLOR" != "red" ]] && COLOR="yellow" || COLOR='red'

    elif [[ "${RATIO}" -lt "${RAC_SESSIONS_YELLOW}" ]]; then
        echo "<br>$SPACER&yellow Object ${ORACLE_SID}: RAC Sessions utilization on ${RAC} is <B><U><FONT COLOR="YELLOW">${RATIO}%</FONT></U></B>.  Low. (<${RAC_SESSIONS_YELLOW})" >> ${TEMPFILE}-rac
        [[ "$COLOR" != "red" ]] && COLOR="yellow"
    else
        echo "<br>$SPACER&green Object ${ORACLE_SID}: RAC Sessions utilization on ${RAC} is <B>${RATIO}%</B>.  Normal. (>=${RAC_SESSIONS_YELLOW})" >> ${TEMPFILE}-rac
    fi

  else
    echo "<br>$SPACER&green Object ${ORACLE_SID}: Not enough user sessions to check RAC load-balancing.  Normal. (${V_TOTUSR}:${R_MINUSR})" >> ${TEMPFILE}-rac
  fi

  ((VAR0+=2))
  ((VAR1+=2))

done

echo "================== ======== ======== ======== ======== ======== ========"

  echo "total  ${V_TOTUSR} ${V_TOTUSRPCT} ${V_USRFAI} ${V_TOTSES} ${V_TOTSESPCT} ${V_SESFAI}"  \
| awk '{ printf("%-18.18s %8d %6d %% ses %4d %8d %6d %% ses %4d\n", $1,$2,$3,$4,$5,$6,$7) }'

echo "</pre>"

cat ${TEMPFILE}-rac 2>/dev/null

[[ "$DEBUG" != "Y" ]] && rm -f ${TEMPFILE}-rac
[[ "$DEBUG" != "Y" ]] && rm -f ${TEMPFILE}-rac2

}

#
################################################################
# Check database status
################################################################
function FUNC_STATUS_CHECK 
{
[[ "$DEBUG" = "Y" ]] && set -xv

local ORACLE_SID
local DB_CHECK
local DB_USER
local DB_PASSWORD

local Tests
local TestType

typeset -l Tests	# all lowercase for strspn
typeset -u TestType	# all uppercase for later comparisions

local COLOR=green	# start off as green

local TEMPFILE=$BBTMP/$BBPROG.$$.$1
local SIDTEMPFILE=$2.TEMP
echo "" > $TEMPFILE # leave these here
echo "</pre>" >> $TEMPFILE

#read the log-as-hostname and input file
$GREP "${1}$" ${2} >${SIDTEMPFILE} # put into file for shell compatibility
while read input ;do
	set -- bogus $input
	shift # get past bogus
	NumFields=$#
	# should never happen
	[[ $NumFields -lt 5 ]] && continue	# gotta enter all fields
	Tests=$5
	# should never set NotifyAs to $MACHINE because we already set it
	[[ $NumFields -gt 5 ]] && NotifyAs=${6} || NotifyAs=$MACHINE # set correct notify host,domain,xxx
	TestType=$1

#	determine what tests to do
	[[ `strspn 'a' ${Tests}` -gt 0 ]] && [[ "$TestType" = "LOCAL" ]] && local PROCS_CHECK="Y" || local PROCS_CHECK="N"
	[[ `strspn 'b' ${Tests}` -gt 0 ]] && local DATABASE_CHECK="Y" || local DATABASE_CHECK="N"
	[[ `strspn 'c' ${Tests}` -gt 0 ]] && [[ "$TestType" = "LOCAL" ]] && local USER_PROC_CHECK="Y" || local USER_PROC_CHECK="N"
	[[ `strspn 'd' ${Tests}` -gt 0 ]] && local USER_CHECK="Y" || local USER_CHECK="N"
	[[ `strspn 'e' ${Tests}` -gt 0 ]] && local TABLESPACE_CHECK="Y" || local TABLESPACE_CHECK="N"
	[[ `strspn 'f' ${Tests}` -gt 0 ]] && local EXTENT_CHECK="Y" || local EXTENT_CHECK="N"
	[[ `strspn 'g' ${Tests}` -gt 0 ]] && [[ "$TestType" = "LOCAL" ]] && local SHADOW_CHECK="Y" || local SHADOW_CHECK="N"
	[[ `strspn 'h' ${Tests}` -gt 0 ]] && local PINLIB_CHECK="Y" || local PINLIB_CHECK="N"
	[[ `strspn 'i' ${Tests}` -gt 0 ]] && local SQLAREA_CHECK="Y" || local SQLAREA_CHECK="N"
	[[ `strspn 'j' ${Tests}` -gt 0 ]] && local BLOCK_CHECK="Y" || local BLOCK_CHECK="N"
	[[ `strspn 'k' ${Tests}` -gt 0 ]] && local MEMREQ_CHECK="Y" || local MEMREQ_CHECK="N"
	[[ `strspn 'l' ${Tests}` -gt 0 ]] && local ROLBAK_CHECK="Y" || local ROLBAK_CHECK="N"
	[[ `strspn 'm' ${Tests}` -gt 0 ]] && local INVOBJ_CHECK="Y" || local INVOBJ_CHECK="N"
	[[ `strspn 'n' ${Tests}` -gt 0 ]] && local DEAD_CHECK="Y" || local DEAD_CHECK="N"
	[[ `strspn 'o' ${Tests}` -gt 0 ]] && local PROCESSES_CHECK="Y" || local PROCESSES_CHECK="N"
	[[ `strspn 'p' ${Tests}` -gt 0 ]] && local SESSIONS_CHECK="Y" || local SESSIONS_CHECK="N"
        [[ `strspn 'q' ${Tests}` -gt 0 ]] && local STATISTICS_CHECK="Y" || local STATISTICS_CHECK="N"
        [[ `strspn 'r' ${Tests}` -gt 0 ]] && local RAC_SESSIONS_CHECK="Y" || local RAC_SESSIONS_CHECK="N"

#	and if we should notify	
	[[ `strspn 'A' ${5}` -gt 0 ]] && local PROCS_NOTIFY="Y" || local PROCS_NOTIFY="N"
	[[ `strspn 'B' ${5}` -gt 0 ]] && local DATABASE_NOTIFY="Y" || local DATABASE_NOTIFY="N"
	[[ `strspn 'C' ${5}` -gt 0 ]] && local USER_PROC_NOTIFY="Y" || local USER_PROC_NOTIFY="N"
	[[ `strspn 'D' ${5}` -gt 0 ]] && local USER_NOTIFY="Y" || local USER_NOTIFY="N"
	[[ `strspn 'E' ${5}` -gt 0 ]] && local TABLESPACE_NOTIFY="Y" || local TABLESPACE_NOTIFY="N"
	[[ `strspn 'F' ${5}` -gt 0 ]] && local EXTENT_NOTIFY="Y" || local EXTENT_NOTIFY="N"
	[[ `strspn 'G' ${5}` -gt 0 ]] && local SHADOW_NOTIFY="Y" || local SHADOW_NOTIFY="N"
	[[ `strspn 'H' ${5}` -gt 0 ]] && local PINLIB_NOTIFY="Y" || local PINLIB_NOTIFY="N"
	[[ `strspn 'I' ${5}` -gt 0 ]] && local SQLAREA_NOTIFY="Y" || local SQLAREA_NOTIFY="N"
	[[ `strspn 'J' ${5}` -gt 0 ]] && local BLOCK_NOTIFY="Y" || local BLOCK_NOTIFY="N"
	[[ `strspn 'K' ${5}` -gt 0 ]] && local MEMREQ_NOTIFY="Y" || local MEMREQ_NOTIFY="N"
	[[ `strspn 'L' ${5}` -gt 0 ]] && local ROLBAK_NOTIFY="Y" || local ROLBAK_NOTIFY="N"
	[[ `strspn 'M' ${5}` -gt 0 ]] && local INVOBJ_NOTIFY="Y" || local INVOBJ_NOTIFY="N"
	[[ `strspn 'N' ${5}` -gt 0 ]] && local DEAD_NOTIFY="Y" || local DEAD_NOTIFY="N"
	[[ `strspn 'O' ${5}` -gt 0 ]] && local PROCESSES_NOTIFY="Y" || local PROCESSES_NOTIFY="N"
	[[ `strspn 'P' ${5}` -gt 0 ]] && local SESSIONS_NOTIFY="Y" || local SESSIONS_NOTIFY="N"
        [[ `strspn 'Q' ${5}` -gt 0 ]] && local STATISTICS_NOTIFY="Y" || local STATISTICS_NOTIFY="N"
        [[ `strspn 'R' ${5}` -gt 0 ]] && local RAC_SESSIONS_NOTIFY="Y" || local RAC_SESSIONS_NOTIFY="N"

	ORACLE_SID=$2
	DB_USER=$3
	DB_PASSWORD=$4
	DB_CHECK=""

	# Warning thresholds (overridden by $DBTAB file)
	local TBL_RED TBL_YELLOW
	local EXT_RED EXT_YELLOW
	local ROLBAK_RED ROLBAK_YELLOW
	local MEMREQ_RED MEMREQ_YELLOW
	################################################################
	# updates from Christopher White (c) 2002-2003
	################################################################
	local PINLIB_RED PINLIB_YELLOW
	local SQLAREA_RED SQLAREA_YELLOW
	local BLOCK_BUF_RED BLOCK_BUF_YELLOW
	################################################################
	local SHOWTABLE
	typeset -u SHOWTABLE

	GetNotifyAtValues # get the notify at values for this sid

if [[ "$DEBUG" = "Y" ]] || [[ "$DEBUG" = "y" ]]; then
	echo "TEMPFILE=$TEMPFILE"
	echo "**************************************************"
	echo "ORACLE_SID			= $ORACLE_SID"
	echo "Test Type			= $TestType"
	echo "Notify as machine		= $NotifyAs"
	echo "DATABASE_CHECK - notify	= $DATABASE_CHECK - $DATABASE_NOTIFY"
	echo "USER_PROC_CHECK - notify	= $USER_PROC_CHECK - $USER_PROC_NOTIFY"
	echo "USER_CHECK - notify		= $USER_CHECK - $USER_NOTIFY"
	echo "TABLESPACE_CHECK - notify	= $TABLESPACE_CHECK - $TABLESPACE_NOTIFY"
	echo "EXTENT_CHECK - notify		= $EXTENT_CHECK - $EXTENT_NOTIFY"
	echo "SHADOW_CHECK - notify		= $SHADOW_CHECK - $SHADOW_NOTIFY"
	echo "PINLIB_CHECK - notify		= $PINLIB_CHECK - $PINLIB_NOTIFY"
	echo "SQLAREA_CHECK - notify		= $SQLAREA_CHECK - $SQLAREA_NOTIFY"
	echo "BLOCK_CHECK - notify		= $BLOCK_CHECK - $BLOCK_NOTIFY"
	echo "MEMREQ_CHECK - notify		= $MEMREQ_CHECK - $MEMREQ_NOTIFY"
	echo "ROLBAK_CHECK - notify		= $ROLBAK_CHECK - $ROLBAK_NOTIFY"
	echo "INVOBJ_CHECK - notify		= $INVOBJ_CHECK - $INVOBJ_NOTIFY"
	echo "DEAD_CHECK - notify		= $DEAD_CHECK - $DEAD_NOTIFY"
	echo "PROCESSES_CHECK - notify		= $PROCESSES_CHECK - $PROCESSES_NOTIFY"
	echo "SESSIONS_CHECK - notify		= $SESSIONS_CHECK - $SESSIONS_NOTIFY"
        echo "STATISTICS_CHECK - notify         = $STATISTICS_CHECK - $STATISTICS_NOTIFY"
        echo "RAC_SESSIONS_CHECK - notify       = $RAC_SESSIONS_CHECK - $RAC_SESSIONS_NOTIFY"
	echo "TBL_YELLOW - TBL_RED		= ${TBL_YELLOW} - ${TBL_RED}"
	echo "EXT_YELLOW - EXT_RED		= ${EXT_YELLOW} - ${EXT_RED}"
	echo "PINLIB_YELLOW - PINLIB_RED	= ${PINLIB_YELLOW} - ${PINLIB_RED}"
	echo "SQLAREA_YELLOW - SQLAREA_RED	= ${SQLAREA_YELLOW} - ${SQLAREA_RED}"
	echo "BLOCK_BUF_YELLOW - BLOCK_BUF_RED	= ${BLOCK_BUF_YELLOW} - ${BLOCK_BUF_RED}"
	echo "MEMREQ_YELLOW - MEMREQ_RED	= ${MEMREQ_YELLOW} - ${MEMREQ_RED}"
	echo "ROLBAK_YELLOW - ROLBAK_RED	= ${ROLBAK_YELLOW} - ${ROLBAK_RED}"
	echo "INVOBJ_YELLOW - INVOBJ_RED	= ${INVOBJ_YELLOW} - ${INVOBJ_RED}"
	echo "DEAD_YELLOW - DEAD_RED		= ${DEAD_YELLOW} - ${DEAD_RED}"
	echo "PROCESSES_YELLOW - PROCESSES_RED	= ${PROCESSES_YELLOW} - ${PROCESSES_RED}"
	echo "SESSIONS_YELLOW - SESSIONS_RED	= ${SESSIONS_YELLOW} - ${SESSIONS_RED}"
        echo "STATISTICS_YELLOW - STATISTICS_RED = ${STATISTICS_YELLOW} - ${STATISTICS_RED}"
        echo "RAC_SESSIONS_YELLOW - RAC_SESSIONS_RED = ${RAC_SESSIONS_YELLOW} - ${RAC_SESSIONS_RED}"
        echo "MIN_EXT - MIN_EXT 		= ${MIN_EXT}"
	echo "SHOWTABLE = 			= ${SHOWTABLE}"
fi

	if [[ "$TestType" = "LOCAL" ]]; then
		# Since all the LOCAL sids are processed in one call this function
		# can ignore the exports oracles from any other processes
		# v1.4-RHerron - Determine proper ORACLE_HOME value from ORATAB
		#   and set other environment variables as appropriate.
		# if ORATAB file (often times /etc/oratab) exists otherwise use
		#   defaults from bb-roracle_def.sh

		if [[ -f $ORATAB ]]; then
			#if [[ `${GREP} -c "${ORACLE_SID}:" ${ORATAB}` -gt 0 ]]
			# Determing ORACLE_HOME from ORATAB file
			ORACLE_HOME=`${GREP} "${ORACLE_SID}:" ${ORATAB} | cut -f2 -d:`
			export SQLPLUS="$ORACLE_HOME/bin/sqlplus"
			#echo $ORACLE_HOME ${ORACLE_SID} ${ORATAB} ${SQLPLUS}
		fi

                if [[ -z $ORACLE_HOME ]]; then
                        # Use DFT_ORACLE_HOME specified in bb-roracle_def.sh
                        ORACLE_HOME=$DFT_ORACLE_HOME
                        export SQLPLUS="$ORACLE_HOME/bin/sqlplus"
                fi
    		ORACLE_SID=$ORACLE_SID ;export ORACLE_SID
		# Set remainder of env variable dependent on ORACLE_HOME
		ORAENV="$ORACLE_HOME/bin/oraenv"; export ORAENV
		# ORACLE_PATH=$ORACLE_HOME/xxx # export ORACLE_PATH
		if [[ `echo $PATH | $EGREP -c "(^|:)$ORACLE_HOME/bin($|:)"` -eq 0 ]]; then
			PATH=$ORACLE_HOME/bin:${SAVE_PATH}
		fi
		if [[ `echo $LD_LIBRARY_PATH | $EGREP -c "(^|:)$ORACLE_HOME/lib($|:)"` -eq 0 ]]; then
			LD_LIBRARY_PATH="${ORACLE_HOME}/lib:${SAVE_LIB}" 
		fi
		ORA_LIBPATH="$ORACLE_HOME/lib";export ORA_LIBPATH # legacy
		SHLIB_PATH="${ORA_LIBPATH}" ;export SHLIB_PATH
		echo "" >> $TEMPFILE
		# check the local processes
		put_header "Process Check" "$ORACLE_SID" >> $TEMPFILE
		if [[ "$PROCS_CHECK" = "Y" ]]; then
			FUNC_PROCS_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear Database process test disabled" >> $TEMPFILE
		fi
	else
		DB_PASSWORD=$DB_PASSWORD@$ORACLE_SID
	fi

	# check the databases
	if [[ "$DATABASE_CHECK" = "Y" ]]; then
		put_header "Database Checks" "$ORACLE_SID" >> $TEMPFILE
		FUNC_DATABASE_CHECK >> $TEMPFILE
	else
		[[ "$TestType" = "REMOTE" ]] && put_header "Database Checks" "$ORACLE_SID" >> $TEMPFILE
		echo "<br>$SPACER&clear Database checks: Disabled" >> $TEMPFILE
	fi

	if [[ "$DB_CHECK" != "$ORACLE_SID is up" ]]; then
		local easy="check disabled since db is down or check is disabled"
		[[ "$USER_PROC_CHECK" = "Y" ]] && echo "<br>$SPACER&red User process $easy"  >> $TEMPFILE
		[[ "$USER_CHECK" = "Y" ]] && echo "<br>$SPACER&red User $easy"  >> $TEMPFILE
		[[ "$TABLESPACE_CHECK" = "Y" ]] && echo "<br>$SPACER&red Tablespace $easy"  >> $TEMPFILE
                [[ "$EXTENT_CHECK" = "Y" ]] && echo "<br>$SPACER&red Extent $easy"  >> $TEMPFILE
                [[ "$SHADOW_CHECK" = "Y" ]] && echo "<br>$SPACER&red Shadow entries $easy" >> $TEMPFILE
                [[ "$PINLIB_CHECK" = "Y" ]] && echo "<br>$SPACER&red Pin hit ratio $easy" >> $TEMPFILE
                [[ "$SQLAREA_CHECK" = "Y" ]] && echo "<br>$SPACER&red SQL Area hit ratio $easy" >> $TEMPFILE
                [[ "$BLOCK_CHECK" = "Y" ]] && echo "<br>$SPACER&red Block buffer hit ratio $easy" >> $TEMPFILE
                [[ "$MEMREQ_CHECK" = "Y" ]] && echo "<br>$SPACER&red Shared Memory $easy" >> $TEMPFILE
                [[ "$ROLBAK_CHECK" = "Y" ]] && echo "<br>$SPACER&red RollBack $easy" >> $TEMPFILE
                [[ "$INVOBJ_CHECK" = "Y" ]] && echo "<br>$SPACER&red Invalid Object $easy" >> $TEMPFILE
                [[ "$DEAD_CHECK" = "Y" ]] && echo "<br>$SPACER&red Deadlock $easy" >> $TEMPFILE
                [[ "$PROCESSES_CHECK" = "Y" ]] && echo "<br>$SPACER&red Processes $easy" >> $TEMPFILE
                [[ "$SESSIONS_CHECK" = "Y" ]] && echo "<br>$SPACER&red Session $easy" >> $TEMPFILE
                [[ "$STATISTICS_CHECK" = "Y" ]] && echo "<br>$SPACER&red Statistics $easy" >> $TEMPFILE
                [[ "$RAC_SESSIONS_CHECK" = "Y" ]] && echo "<br>$SPACER&red RAC Session $easy" >> $TEMPFILE
	else
                if [[ "$RAC_SESSIONS_CHECK" = "Y" ]]; then
                        put_header "RAC Session Check" "$ORACLE_SID" >> $TEMPFILE
                        FUNC_RAC_SESSIONS_CHECK >> $TEMPFILE
                else
                        echo "<br>$SPACER&clear RAC Session check: Disabled" >> $TEMPFILE
                fi

		# check the Users count
		if [[ "$USER_PROC_CHECK" = "Y" ]] ; then # testtype is prechecked to be local
			put_header "User Count Check" "$ORACLE_SID" >> $TEMPFILE
			FUNC_USER_PROC_CHECK >> $TEMPFILE
		elif [[ "$TestType" = "LOCAL" ]]; then
			echo "<br>$SPACER&clear User count check: Disabled" >> $TEMPFILE
		fi
		
		# check the Users active
		if [[ "$USER_CHECK" = "Y" ]]; then
			put_header "User Check" "$ORACLE_SID" >> $TEMPFILE
			FUNC_USER_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear User check: Disabled" >> $TEMPFILE
		fi
		
		# check the TABLESPACE
		if [[ "$TABLESPACE_CHECK" = "Y" ]]; then
			put_header "Tablespace Check" "$ORACLE_SID)(Show greens $SHOWTABLE" >> $TEMPFILE
        		FUNC_TABLESPACE_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear Tablespace check: Disabled" >> $TEMPFILE
		fi
		
		if [[ "$EXTENT_CHECK" = "Y" ]]; then
			put_header "Extent Check" "$ORACLE_SID" >> $TEMPFILE
        		FUNC_EXTENT_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear Extent check: Disabled" >> $TEMPFILE
		fi
		
		if [[ "$SHADOW_CHECK" = "Y" ]] ; then # testtype is prechecked to be local
			put_header "Oracle Shadow Processes" "$ORACLE_SID" >> $TEMPFILE
		elif [[ "$TestType" = "LOCAL" ]]; then
			echo "<br>$SPACER&clear Shadow check: Disabled" >> $TEMPFILE
		fi

		if [[ "$PINLIB_CHECK" = "Y" ]]; then
			put_header "PIN hit ratio for lib cache Check" "$ORACLE_SID" >> $TEMPFILE
        		FUNC_PINLIB_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear Pin Hit Ratio check: Disabled" >> $TEMPFILE
		fi

		if [[ "$SQLAREA_CHECK" = "Y" ]]; then
			put_header "SQL Area Hit Ratio Check" "$ORACLE_SID" >> $TEMPFILE
        		FUNC_SQLAREA_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear Sql Area Hit Ratio check: Disabled" >> $TEMPFILE
		fi

		if [[ "$BLOCK_CHECK" = "Y" ]]; then
			put_header "Block Buffer Hit Ratio Check" "$ORACLE_SID" >> $TEMPFILE
        		FUNC_BLOCK_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear Block Buffer Hit Ratio check: Disabled" >> $TEMPFILE
		fi

		if [[ "$MEMREQ_CHECK" = "Y" ]]; then
			put_header "Shared Memory Check" "$ORACLE_SID" >> $TEMPFILE
        		FUNC_MEMREQ_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear Shared Memory check: Disabled" >> $TEMPFILE
		fi

		if [[ "$ROLBAK_CHECK" = "Y" ]]; then
			put_header "RollBack Check" "$ORACLE_SID" >> $TEMPFILE
        		FUNC_ROLBAK_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear RollBack check: Disabled" >> $TEMPFILE
		fi

		if [[ "$INVOBJ_CHECK" = "Y" ]]; then
			put_header "Invalid Object Check" "$ORACLE_SID" >> $TEMPFILE
        		FUNC_INVOBJ_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear Invalid Object check: Disabled" >> $TEMPFILE
		fi

		if [[ "$DEAD_CHECK" = "Y" ]]; then
			put_header "Deadlock Check" "$ORACLE_SID" >> $TEMPFILE
        		FUNC_DEAD_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear Deadlock check: Disabled" >> $TEMPFILE
		fi

		if [[ "$PROCESSES_CHECK" = "Y" ]]; then
			put_header "Processes Check" "$ORACLE_SID" >> $TEMPFILE
        		FUNC_PROCESSES_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear Processes check: Disabled" >> $TEMPFILE
		fi

		if [[ "$SESSIONS_CHECK" = "Y" ]]; then
			put_header "Session Check" "$ORACLE_SID" >> $TEMPFILE
        		FUNC_SESSIONS_CHECK >> $TEMPFILE
		else
			echo "<br>$SPACER&clear Session check: Disabled" >> $TEMPFILE
		fi

                if [[ "$STATISTICS_CHECK" = "Y" ]]; then
                        put_header "Statistics Check" "$ORACLE_SID" >> $TEMPFILE
                        FUNC_STATISTICS_CHECK >> $TEMPFILE
                else
                        echo "<br>$SPACER&clear Statistics check: Disabled" >> $TEMPFILE
                fi
       	fi
done < ${SIDTEMPFILE}
$RM -f ${SIDTEMPFILE} >/dev/null 2>&1

put_footer >> $TEMPFILE
if [[ "$DEBUG" = "Y" ]] || [[ "$DEBUG" = "y" ]]; then
	echo	$BB $BBDISP "status $NotifyAs.$TEST2 $COLOR `$DATE` `cat $TEMPFILE`"
	$DATE
	echo "End of Oracle tests for $ORACLE_SID"
	echo "**************************************************"
fi

# send this message
if [[ "$DEBUG" = "Y" ]]; then
        echo "Send this Message: "$BB $BBDISP "status $NotifyAs${TEST2} $COLOR `$DATE` `cat $TEMPFILE`"
fi
$BB $BBDISP "status $NotifyAs.$TEST2 $COLOR `$DATE` `cat $TEMPFILE`"
$RM -f $TEMPFILE >/dev/null 2>&1
}

################################################################
# Definitions and Temporary locations
################################################################
COLOR=green	# start off as green
TEMPFILE=$BBTMP/$BBPROG.$$; export TEMPFILE
SIDFILE=$BBTMP/SIDS.$$; export SIDFILE
$RM -f $TEMPFILE $SIDFILE >/dev/null 2>&1
echo "" > $TEMPFILE # blank line
: > $SIDFILE # empty file

#------------------- MAIN PROGRAM ------------------------------
################################################################
# load up local sids from file
################################################################
# use echo to strip some spaces
#LOCAL_SIDS=$(echo `$GREP -i "^[ 	]*LOCAL" $UPFILE|tr -s "[:space:]" " "|cut -d " " -f 2|$SORT -k 1 -u 2>/dev/null`)
[[ "$DEBUG" = "Y" ]] && set -xv
LOCAL_SIDS=$($GREP -i "^[	 ]*LOCAL" $UPFILE|$AWK '{print $2}'|tr -s "[:space:]" " ")

# rearrage order of sid/listener to allow test/set of default listener later
# remove dup/blank listeners and log-as-host fields(may be a '-' for the local hostname)?
$GREP -i "^[	 ]*LOCAL" $UPFILE|$AWK '{printf ("%s %s\n",$2,$7)}' |while read sid listener
do
        if [[ -f $ORATAB ]]; then
                # Determing ORACLE_HOME from ORATAB file
                ORACLE_H=`${GREP} "^$sid:" ${ORATAB} | cut -f2 -d:`
        fi

        if [[ -z $ORACLE_H ]]; then
                # Use DFT_ORACLE_HOME specified in bb-roracle_def.sh
                ORACLE_H=$DFT_ORACLE_HOME
        fi
	[[ -z "$listener" ]] && listener=LISTENER	# set as default?
        echo "$ORACLE_H $listener $sid" >> $BBTMP/LISTENER.$$
done


if [[ "$DEBUG" = "y" ]] || [[ "$DEBUG" = "Y" ]]; then
set +xv
	# load up remote sids from file
	#REMOTE_SIDS=$(echo `$GREP -i "^[ 	]*REMOTE" $UPFILE|tr -s "[:space:]" " "|cut -d " " -f 2|$SORT -k 1 -u 2>/dev/null`)
	REMOTE_SIDS=$($GREP -i "^[ 	]*REMOTE" $UPFILE|$AWK '{print $2}'|tr -s "[:space:]" " ")
	echo ""
	echo "**************************************************"
	echo "ORACLE TESTER started"
	$DATE
	echo ""
	echo "LISTENER_CHECK		= $LISTENER_CHECK"
	echo "LISTENER_CHECK_VERBOSE	= $LISTENER_CHECK_VERBOSE"
        echo "LISTENER_NAMES		= $(echo `cat $BBTMP/LISTENER.$$|cut -d " " -f 2|sort -u -k 1`)"
	echo "DATABASE_CHECK		= $DATABASE_CHECK"
	echo "SIDS_CHECK		= $SIDS_CHECK"
	echo "LOCAL_SIDS		= $(echo $LOCAL_SIDS)"
	echo "REMOTE_SIDS		= $(echo $REMOTE_SIDS)"
set -xv
fi

################################################################
# LOCAL MACHINE CHECKS
################################################################
# The check for ORACLE sids. (if desired)
################################################################
if [[ "$SIDS_CHECK" = "Y" ]]; then
	put_header "Oracle Instance Check" "$MACHINEDOTS" >> $TEMPFILE
	Sid_Check >> $TEMPFILE
else
	echo "$SPACER&clear SIDS test disabled" >> $TEMPFILE
fi

################################################################
# The check for the listener. (if desired)
################################################################
if [[ "$LISTENER_CHECK" = "Y" ]]; then
	put_header "Oracle Listener Check" "$MACHINEDOTS" >> $TEMPFILE
	Listener_Check >> $TEMPFILE
else
	echo "$SPACER&clear Listener test disabled" >> $TEMPFILE
fi

################################################################
# send this initial message
################################################################
put_footer >> $TEMPFILE
# if no status requested don't send anything
[[ "$SIDS_CHECK" = "Y" ]] || [[ "$LISTENER_CHECK" = "Y" ]] && $BB $BBDISP "status $MACHINEDOTS.$TEST1 $COLOR `$DATE` `cat $TEMPFILE`"
$RM -f $TEMPFILE >/dev/null 2>&1 # done with this TEMPFILE

################################################################
# check databases. (if desired)
################################################################
if [[ "$DATABASE_CHECK" = "Y" ]]; then
	SAVE_PATH=$PATH
	SAVE_LIB=$LD_LIBRARY_PATH
	# make sure its only 6 fields long - append MACHINE to blank lines
	($EGREP -i "^[ 	]*LOCAL|^[ 	]*REMOTE" $UPFILE|while read line;do
	        set -- $line	# it may have a - for notify-host so check
	        if [[ ${#} -eq 5 ]] || [[ ${#} -gt 5 ]] && [[ ${6} == "-" ]] ; then
	        	echo $1 $2 $3 $4 $5 $MACHINEDOTS
	        elif [[ ${#} -gt 5 ]]; then
	        	echo "$1 $2 $3 $4 $5 $6"
	        fi
	        done) > $SIDFILE
       
	[[ "$DEBUG" = "Y" ]] && cat $SIDFILE

	# get the unique notify as lines and pass to the status check function
	$SORT -k 6 -u $SIDFILE|cut -d " " -f 6|while read NotifyID;do
		# call to check SIDS
		if [[ "$MULTI_THREAD" = "Y" ]]; then
			FUNC_STATUS_CHECK $NotifyID $SIDFILE &
		else
			FUNC_STATUS_CHECK $NotifyID $SIDFILE
		fi
	done
	wait # wait for them all
fi
$RM -f $SIDFILE >/dev/null 2>&1
exit 0
