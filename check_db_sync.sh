#!/bin/bash

export PRIM=$1
export STNDBY=$2
export ORACLE_HOME=/apps/oracle/product/11.2.0.4/db_1
export USERNAME=sys
export PASSWD=`zcat /home/oracle/dba/control/.passwdfile.gz |grep -w "${USERNAME}"|grep -w "${PRIM}"| cut -d":" -f3 | head -1`

get_scn()
{
	STNDBY_SCN=$(${ORACLE_HOME}/bin/sqlplus -s ${USERNAME}/${PASSWD}@${STNDBY} as sysdba <<-"_EOF_"
	SET ECHO OFF NEWP 0 SPA 0 PAGES 0 FEED OFF HEAD OFF TRIMS ON TAB OFF
	col current_scn format 99999999999999;
	select current_scn from v$database;
	exit;
	_EOF_
	)
}

get_time()
{
	export STNDBY_TIME=$(${ORACLE_HOME}/bin/sqlplus -s ${USERNAME}/${PASSWD}@${PRIM} as sysdba <<-_EOF_
	SET ECHO OFF NEWP 0 SPA 0 PAGES 0 FEED OFF HEAD OFF TRIMS ON TAB OFF
	ALTER SESSION SET NLS_TIMESTAMP_FORMAT = 'DD-MON-YYYY HH:MI:SS PM';
	select scn_to_timestamp($STNDBY_SCN) from dual;
	exit;
	_EOF_
	)

	export PRIM_TIME=$(${ORACLE_HOME}/bin/sqlplus -s ${USERNAME}/${PASSWD}@${PRIM} as sysdba <<-"_EOF_"
	SET ECHO OFF NEWP 0 SPA 0 PAGES 0 FEED OFF HEAD OFF TRIMS ON TAB OFF
	col current_scn format 99999999999999;
	ALTER SESSION SET NLS_TIMESTAMP_FORMAT = 'DD-MON-YYYY HH:MI:SS PM';
	select scn_to_timestamp(current_scn) from v$database;
	exit;
	_EOF_
	)
	echo prim_time $PRIM_TIME
	echo stndby_time $STNDBY_TIME
}

check_variable()
{

	t1=`date -d "${STNDBY_TIME}" 2>: 1>:; echo $?`
	t2=`date -d "${PRIM_TIME}" 2>: 1>:; echo $?`

	if [[ $t1 -eq 0 && $t2 -eq 0 ]]
		then
			find_diff
			send_alert
		else
			export MAIL_LIST="support@team.com"
			echo -e "Unable to connect $STNDBY or $PRIM" | mail -s "$PRIM Dataguard Sync Alert" ${MAIL_LIST}
	fi			
	
}

find_diff()
{
	COMPARE=`${ORACLE_HOME}/bin/sqlplus -s ${USERNAME}/${PASSWD}@${PRIM} as sysdba <<-_EOF_
	SET ECHO OFF NEWP 0 SPA 0 PAGES 0 FEED OFF HEAD OFF TRIMS ON TAB OFF
	select extract(minute from diff) hrs from (
	select 
	to_timestamp('${PRIM_TIME}', 'dd-mon-yyyy hh:mi:ss.ff PM') -
	to_timestamp('${STNDBY_TIME}', 'dd-mon-yyyy hh:mi:ss.ff PM') diff
	from dual
	);
	exit;
	_EOF_`
}

send_alert()
{
	echo $COMPARE
	if [ $COMPARE -gt 60 ]
	then
		export MAIL_LIST="support@team.com"
		echo -e "$STNDBY is lagging from $PRIM by $COMPARE minutes." | mail -s "$PRIM Dataguard Sync Alert" ${MAIL_LIST}
	else
		exit 0;
	fi

}

get_scn
get_time
check_variable
