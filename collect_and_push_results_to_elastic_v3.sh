#!/bin/bash

# Usage
# ./collect_and_push_results_to_es_v2.sh [standard params] [test specific params]
#   Standard parameters:
#     --debug                 Print debug information for this script (set -x)
#     --sandbox               (-s) Sends the results to sandbana environment instead of production
#     --timestamp             Overrides default system timestamp. The format must be +'%Y-%m-%dT%H:%M:%SZ'
#     --start-time            Test start time
#     --end-time              Test end time
#     --category              Category (Exchange, FlowDesigner, ...)
#     --component             Component (VCS, mozart-config-repository, ...)
#     --test-case             Test case name
#     --threads               (Optional) Number of concurrent threads (users). If not present it will be extracted from the JMX file
#     --ramp-up-time          (Optional) Test ramp up period. If not present it will be extracted from the JMX file
#     --duration              (Optional) Test duration in seconds. If not present it will be extracted from the JMX file
#     --jmx-file              JMeter script file name
#     --tag                   Version tag of the component being tested (any identifier that allows to easily locate the deployed version of the component)
#     --jmeter-out            JMeter output file name
#     --summary-csv           SummaryReport.csv generated with the CMDRunner - Synthesis Report plugin
#     --jmeter-jtl            (Experimental) JMeter's JTL output file
#     --k8s-metrics           Kubernetes utilization metrics in CSV format per pod
#     --collect-sar-metrics   Flag to indicate that the script must collect and push sar metrics in the server.log file format
#     --dms-metrics           DMS metrics in CSV
#     --dms-metrics-host      DMS metrics per host in CSV
#     --dms-fanout            DMS fanout metrics per app in CSV
#     --sla-results           Results file of the SLAs compliance verification
#     --perfci                Push data to the PERFCI index even if the job's name doesn't end with _PERFCI
#
#   Test specific parameters (examples, could be anything that helps to characterize the scenario):
#     --Ppayload_size   Payload size in bytes
#     --Papis_published Number of APIs published for the test
#     ...
#
#    NOTE: Keep in mind that you must quote the custom string parameters, e.g.
#     --Ptest_description=\"This is the test description\"
#
#   It requires the following Hudson environment variables to be set:
#     $JOB_NAME (and $JOB_BASE_NAME in Jenkins)
#     $BUILD_NUMBER
#     $HUDSON_USER
#     $BUILD_TAG
#     $BUILD_URL
#     $NODE_NAME

# ------------------------------------------------------------
#    Global constants
# ------------------------------------------------------------

SECONDS=0

# set -x
BASEPATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# ------------------------------------------------------------
#    Functions
# ------------------------------------------------------------

# Is doesn't really parses the xml, it just does grep + sed
function get_xml_val () {
    echo "$(cat $2 | grep \"$1\" | head -1 | sed -e 's/.*>\(.*\)<.*/\1/')"
}

function quote_if_not_num () {
    testval=$1
    re='^-?[0-9]+([.][0-9]+)?$'
    if ! [[ $testval =~ $re ]] ; then
        echo "\"$testval\""
    else
        echo $testval
    fi
}

function get_url_param () {
    if [[ "$2" != "" ]]; then
        echo "$1=$2&"
    fi
}

# ------------------------------------------------------------
#    Script parameter processing
# ------------------------------------------------------------

timestamp=$(date -u +'%Y-%m-%dT%H:%M:%S')

test_specific_params_headers=
test_specific_params_values=
for param in "$@"; do
    #pname=${param%=*}
    IFS='=' read -r pname string <<< "$param"
    pvalue=${param#*=}

    case "$pname" in
        --debug)
            debug=1;;
        -s)
            sandbox=1;;
        --sandbox)
            sandbox=1;;
        --timestamp)
            timestamp=$pvalue;;
        --start-time)
            test_start_time=$pvalue;;
        --end-time)
            test_end_time=$pvalue;;
        --category)
            category="$pvalue";;
        --component)
            component="$pvalue";;
        --test-case)
            test_case="$pvalue";;
        --threads)
            threads=$pvalue;;
        --ramp-up-time)
            ramp_up_time=$pvalue;;
        --duration)
            duration=$pvalue;;
        --jmx-file)
            jmx_file=$pvalue;;
        --tag)
            tag="$pvalue";;
        --jmeter-out)
            jmeter_out=$pvalue;;
        --summary-csv)
            summary_csv=$pvalue;;
        --jmeter-jtl)
            jmeter_jtl=$pvalue;;
        --k8s-metrics)
            k8s_metrics=$pvalue;;
        --collect-sar-metrics)
            collect_sar_metrics=1;;
        --dms-metrics)
            dms_metrics=$pvalue;;
        --dms-metrics-host)
            dms_metrics_host=$pvalue;;
        --dms-fanout)
            dms_fanout=$pvalue;;
        --sla-results)
            sla_results=$pvalue;;
        --perfci)
            perfci=1;;
        *)
            if [[ "$pname" == --P* ]]; then
                pname=${pname#*--P}
                if [[ "$pname" != new_relic_monitoring* ]]; then
                    test_specific_params_headers="$test_specific_params_headers,$pname"
                    test_specific_params_values="$test_specific_params_values,$pvalue"
                    test_specific_params_json="$test_specific_params_json | . + {$pname: $( quote_if_not_num "$pvalue" ) }"
                fi
            fi
    esac
done

if [[ "$debug" != "" ]]; then
    set -x
fi

if [[ "$sandbox" != "" ]]; then
    elasticsearch_env="sandbana"
else
    elasticsearch_env="production"
fi

# ------------------------------------------------------------
#    Retrieve test operating parameters
# ------------------------------------------------------------

# From the JMeter script (JMX file)
if [ -f "$jmx_file" ]; then
    if [ -n "$(grep UltimateThreadGroup "$jmx_file")" ]; then # If the script uses the Ultimate Thread Group
        threads_tag="857857866"
        ramp_up_time_tag="-1986976289"
        duration_tag="-2112100268"
    else # If it uses the standard Thread Group
        threads_tag="ThreadGroup.num_threads"
        ramp_up_time_tag="ThreadGroup.ramp_time"
        duration_tag="ThreadGroup.duration"
    fi
    
    if [[ "$threads" == "" ]]; then
        threads=$(get_xml_val "$threads_tag" "$jmx_file")
    fi
    if [[ "$ramp_up_time" == "" ]]; then
        ramp_up_time=$(get_xml_val "$ramp_up_time_tag" $jmx_file)
    fi
    if [[ "$duration" == "" ]]; then
        duration=$(get_xml_val "$duration_tag" "$jmx_file")
    fi        
    loops=$(get_xml_val "LoopController.loops" "$jmx_file") # Both types of scripts have the loops on the same place
else
    echo "No JMX file, extracting info from script params (--threads, --ramp-up-time, --duration)"
fi

if [[ "$test_specific_params_json" != "" ]]; then
    echo {} | jq -c ". $test_specific_params_json" > custom_test_params.json
    custom_test_params='-Fcustom_test_params=@custom_test_params.json;type=application/json'
#    custom_test_params='-Fcustom_test_params='$( echo {} | jq -c ". $test_specific_params_json" )';type=application/json'
fi

if [[ "$summary_csv" != "" && -f "$summary_csv" ]]; then
    upload_summary_csv="-Fsummary_csv=@$summary_csv;type=application/csv"
fi
#FANOUT_FILE=$BASEPATH/../DMS_METRICS/VCS.stgx.fanout
#echo "Fanout file is: $FANOUT_FILE"

if [[ "$FANOUT_FILE" != "" && -f "$FANOUT_FILE" ]]; then
    upload_downstream_impact_csv="-Fdownstream_impact_csv=@$FANOUT_FILE;type=text/plain"
fi

#BUILD_TAG=hudson-VCS_PERFCI-438
#test_start_time="2018-11-06T21:41:13"
#test_end_time="2018-11-06T21:43:16"
#threads=10
#ramp_up_time=30
#duration=120
#NEW_RELIC_APP_ID=57841697

url_params="\
$( get_url_param build_tag $BUILD_TAG )\
$( get_url_param build_url $BUILD_URL )\
$( get_url_param test_start_time $test_start_time )\
$( get_url_param test_end_time $test_end_time )\
$( get_url_param category "$category" )\
$( get_url_param component "$component" )\
$( get_url_param test_case "$test_case" )\
$( get_url_param jmx_file "$jmx_file" )\
$( get_url_param tag "$tag" )\
$( get_url_param newrelic_app_id $NEW_RELIC_APP_ID )\
$( get_url_param threads $threads )\
$( get_url_param ramp_up_time $ramp_up_time )\
$( get_url_param duration $duration )\
$( get_url_param elasticsearch_env $elasticsearch_env )\
dummy=false" # To avoid the last &

collect_url=http://performance-test-results-collector.us-e1.cloudhub.io
#collect_url=http://localhost:8081

set -x
curl -s -XPOST -H "Content-Type: multipart/form-data" "$collect_url/api/collect?$url_params" "$custom_test_params" "$upload_summary_csv" "$upload_downstream_impact_csv"
set +x

duration=$SECONDS
echo "Perf test results collection completed in $(($duration / 60)) minutes and $(($duration % 60)) seconds."

# Generate replay_collect.sh
echo "Generating replay_collect.sh ..."
echo "#!/bin/bash" > replay_collect.sh
echo "curl -s -XPOST -H \"Content-Type: multipart/form-data\" \"$collect_url/api/collect?$url_params\" \"$custom_test_params\" \"$upload_summary_csv\" \"$upload_downstream_impact_csv\"" >> replay_collect.sh
chmod +x replay_collect.sh
