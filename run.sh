#!/bin/bash
# $Id: run.sh,v 1.5 2010-01-23 14:12:27 youd Exp $
#----------------------------------------------------------------------------

# Simple script to run a job.

PATH=.:/bin:/usr/bin

usage()
{
cat <<EOF
run.sh
---------

DESCRIPTION:

Run the GPE code on <NPROCS> processes either from the start or by doing a
restart from an existing run.

USAGE:

        run.sh [OPTIONS] <NPROCS>

OPTIONS:

        -r <directory>|--restart=<directory>
                    Do a restart of an existing run.  The directory where the
                    previous run exists must be given as an argument.  The
                    end_state.dat files are then copied to the new run
                    directory.

        -f|--force
                    If the script detects the existence of process directories
                    in the current directory, new process directories are not
                    created and the script aborts.  Use -f to force removal of
                    the existing process directories and create new ones.

        -h|--help
                    Show usage information.
EOF
}

# Get command line options
options=`getopt -o r:fh -l restart:,force,help -n run.sh -- "$@"`

# If no options, show the help
if [ $# == 0 ]; then
  usage
  exit 1
fi

eval set -- "$options"

FORCE=0
# Set parameters depending on options
while true
do
  case "$1" in
    -r|--restart) PREDIR=$2; shift 2;;
    -f|--force) FORCE=1; shift;;
    -h|--help) usage; exit 1;;
    --) shift ; break ;;
    *) echo "Invalid flag" ; exit 1 ;;
  esac
done

if [ $# -eq 0 ];
then
  usage
  exit 1
fi

NPROCS=$1
DIGITS=2
EXE=gpe
LOGFILE=log.txt

echo Going to run on $NPROCS processes.

for i in `seq -f "%0${DIGITS}g" 0 $(($NPROCS-1))`
do
  PROCDIR=proc$i
  if [ -d $PROCDIR ]; then
    if [ $FORCE -eq 0 ]; then
      echo WARNING: At least one process directory already exists - aborting.
      echo Use -f to force deletion of process directories.
      exit 1
    else
      rm -rf $PROCDIR
    fi
  fi
  mkdir $PROCDIR
done

if [ ! -z $PREDIR ]; then
  echo Going to do a restart from $PREDIR.
  for i in `seq -f "%0${DIGITS}g" 0 $(($NPROCS-1))`
  do
    PROCDIR=proc$i
    cp $PREDIR/$PROCDIR/end_state.dat end_state$i.dat
  done
fi

# Make directories in which to hold the PDFs and VCFs.
mkdir pdf vcf

echo Running job...
nohup /usr/bin/time -p mpiexec -n $NPROCS $EXE &> $LOGFILE &
