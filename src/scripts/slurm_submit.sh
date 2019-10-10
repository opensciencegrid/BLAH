#!/bin/bash
#
# File:     slurm_submit.sh
# Author:   Jaime Frey (jfrey@cs.wisc.edu)
# Based on code by David Rebatto (david.rebatto@mi.infn.it)
#
# Description:
#   Submission script for SLURM, to be invoked by blahpd server.
#   Usage:
#     slurm_submit.sh -c <command> [-i <stdin>] [-o <stdout>] [-e <stderr>] [-w working dir] [-- command's arguments]
#
# Copyright (c) Members of the EGEE Collaboration. 2004. 
# Copyright (c) HTCondor Team, Computer Sciences Department,
#   University of Wisconsin-Madison, WI. 2015.
# 
# Licensed under the Apache License, Version 2.0 (the "License"); 
# you may not use this file except in compliance with the License. 
# You may obtain a copy of the License at 
# 
#     http://www.apache.org/licenses/LICENSE-2.0 
# 
# Unless required by applicable law or agreed to in writing, software 
# distributed under the License is distributed on an "AS IS" BASIS, 
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. 
# See the License for the specific language governing permissions and 
# limitations under the License.
#

. `dirname $0`/blah_common_submit_functions.sh

# Default values for configuration variables
slurm_std_storage=${slurm_std_storage:-/dev/null}
slurm_binpath=${slurm_binpath:-/usr/bin}

bls_parse_submit_options "$@"

bls_setup_all_files

# Write wrapper preamble
cat > $bls_tmp_file << end_of_preamble
#!/bin/bash
# SLURM job wrapper generated by `basename $0`
# on `/bin/date`
#
# stgcmd = $bls_opt_stgcmd
# proxy_string = $bls_opt_proxy_string
# proxy_local_file = $bls_proxy_local_file
#
# SLURM directives:
#SBATCH -o $slurm_std_storage
#SBATCH -e $slurm_std_storage
end_of_preamble

#local batch system-specific file output must be added to the submit file
bls_local_submit_attributes_file=${blah_libexec_directory}/slurm_local_submit_attributes.sh

# Handle queues and paritions (same thing in SLURM) (copied from PBS submit file)
[ -z "$bls_opt_queue" ] || grep -q "^#SBATCH --partition" $bls_tmp_file || echo "#SBATCH --partition=$bls_opt_queue" >> $bls_tmp_file

if [ "x$bls_opt_req_mem" != "x" ]
then
  # Different schedulers require different memory checks
  echo "#SBATCH --mem=${bls_opt_req_mem}" >> $bls_tmp_file
fi

# Simple support for multi-cpu attributes
if [[ $bls_opt_mpinodes -gt 1 ]] ; then
  echo "#SBATCH --nodes=1" >> $bls_tmp_file
  echo "#SBATCH --ntasks=1" >> $bls_tmp_file
  echo "#SBATCH --cpus-per-task=$bls_opt_mpinodes" >> $bls_tmp_file
fi

# Do the local and extra args after all #SBATCH commands, otherwise slurm ignores anything
# after a non-#SBATCH command
bls_set_up_local_and_extra_args

# Input and output sandbox setup.
# Assume all filesystems are shared.

bls_add_job_wrapper
bls_save_submit

###############################################################
# Submit the script
###############################################################

datenow=`date +%Y%m%d`
retry=0
MAX_RETRY=3
until [ $retry -eq $MAX_RETRY ] ; do
    jobID=$(${slurm_binpath}/sbatch $bls_tmp_file)
    retcode=$?
    if [ "$retcode" == "0" ] ; then
        break
    fi
    retry=$[$retry+1]
    sleep 10
done

if [ "$retcode" != "0" ] ; then
	rm -f $bls_tmp_file
	echo "Error from sbatch: $jobID" >&2
	exit 1
fi

# The job id is actually the first numbers in the string (slurm support)
jobID=`echo $jobID | awk 'match($0,/[0-9]+/){print substr($0, RSTART, RLENGTH)}'`
if [ "X$jobID" == "X" ]; then
	rm -f $bls_tmp_file
	echo "Error: job id missing" >&2
	echo Error # for the sake of waiting fgets in blahpd
	exit 1
fi

# Compose the blahp jobID ("slurm/" + datenow + pbs jobid)
blahp_jobID="slurm/`basename $datenow`/$jobID"

echo "BLAHP_JOBID_PREFIX$blahp_jobID"
  
bls_wrap_up_submit

exit $retcode
