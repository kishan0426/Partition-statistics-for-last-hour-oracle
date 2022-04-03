#!/bin/bash

trap 'rm -rf /home/oracle/oratab_new /home/oracle/DBMS_STATS.sql' EXIT
#For logging purpose
_LOG_0()
{
echo "*************************************$1"
}

#Set the environment variables
_SET_ENV_1()
{
DBMS_STATS=/home/oracle/DBMS_STATS.sql
chmod -R 775 /home/oracle/DBMS_STATS.sql
cat /etc/oratab|grep -v '#'|grep -v '^$' > /home/oracle/oratab_new
while read x
   do
     IFS=':' read -r -a array <<< $x
                ORACLE_SID="${array[0]}"
                ORACLE_HOME="${array[1]}"
                echo $ORACLE_SID
                echo $ORACLE_HOME
                export PATH=$PATH:$ORACLE_HOME/bin
   done < /home/oracle/oratab_new
}

#View the existing auto partition created for last hour and append to a output file
_VIEW_PART_DETAILS_2()
{
$ORACLE_HOME/bin/sqlplus -S '/ as sysdba' << EOF >> log_for_reference
spool LAST_HOUR_PARTITION_DETAILS.dtl
--AUTO_PARTITION_DETAIL_FOR_SALES
set lines 200 pages 500
col owner for a20
col object_name for a20
col subobject_name for a20
set heading off
select to_char(SYSDATE,'yyyy-mm-dd hh:mi:ss') from dual;
set heading on
select owner,
       object_name,
       subobject_name,
       to_char(created,'DD-MON-YYYY HH24:MI:SS') as When
from dba_objects
where object_name='SALES_AUTO_LIST'
and
created >= SYSDATE - (1/24)
and
object_type = 'TABLE PARTITION'
and
owner not in ('SYS','SYSTEM')
order by created desc;
spool off
spool LAST_HOUR_AUTO_PART.dtl
--LAST_HOUR_AUTO_PART
set heading off
set feedback off
set lines 200 pages 500
col owner for a20
col object_name for a20
col subobject_name for a20
WITH xpart as
(
select OWNER,
           OBJECT_NAME,
           SUBOBJECT_NAME,
           CREATED
from dba_objects
where OWNER='TEST'
and
OBJECT_NAME='SALES_AUTO_LIST'
and
SUBOBJECT_NAME <> 'NULL'
)
select ''||do.OWNER||'.'
       ||do.OBJECT_NAME||'.'
       ||do.SUBOBJECT_NAME||''
from xpart do
inner join dba_tab_statistics dts on ( do.SUBOBJECT_NAME = dts.PARTITION_NAME )
where dts.STALE_STATS='YES'
or
do.created >= SYSDATE - (1/24);
spool off
exit;
EOF
}

#Form a gather stats script using the last hour partitions
_COLLECT_PART_STAT_DETAILS_3()
{
while read x;
   do
     IFS='.' read -r -a array <<< $x
     echo "EXEC DBMS_STATS.GATHER_TABLE_STATS(\
                                              ownname=>'"${array[0]}"',\
                                              tabname=>'"${array[1]}"',\
                                              partname=>'"${array[2]}"',\
                                              estimate_percent=>'10',\
                                              method_opt=>'for all indexed columns size skewonly',\
                                              granularity=>'ALL',\
                                              degree=>8,\
                                              cascade=>TRUE)"
   done < LAST_HOUR_AUTO_PART.dtl > $DBMS_STATS
}


#Gather stats only for last hour partitions irrespective of whether they are stale or not
_GATHER_STATS_4()
{
while true
   do
     if [ -s $DBMS_STATS ];
     then
         exit|$ORACLE_HOME/bin/sqlplus -S '/ as sysdba' @$DBMS_STATS
         cat /dev/null > $DBMS_STATS
     else
         _LOG_0 "*"
 echo "***No partitions created in last hour***"
         _LOG_0 "*"
         break
     fi
   done
}

_SET_ENV_1
_VIEW_PART_DETAILS_2
_COLLECT_PART_STAT_DETAILS_3
_GATHER_STATS_4