# $Id: ulimit_hack.sh,v 1.2 2006-11-21 15:57:52 n8049290 Exp $
#----------------------------------------------------------------------------

#!/bin/sh

ulimit -s unlimited
./gpe
