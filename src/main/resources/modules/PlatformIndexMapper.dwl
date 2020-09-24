%dw 2.0
/*
 * ================================
 *     Misc util functions
 * ================================
 */
fun to_float_safe(value) =
	if (value != null)
		1.0 * (value as Number)
	else
		value

/*
 * ================================
 *     Intermediate mappings
 * ================================
 */
fun mapTestParams(config) = {
	scn_test_start_time: config.test_start_time,
	scn_test_end_time: config.test_end_time,
	scn_category: config.category,
	scn_component: config.component,
	scn_test_case: config.test_case,
	scn_jmx_file: config.jmx_file,
	scn_tag: config.tag,
	scn_threads: config.threads,
	scn_ramp_up_time: config.ramp_up_time,
	scn_duration: config.duration
}
 
fun mapCustomTestParams(customTestParams) = 
	customTestParams mapObject(value, key) -> {
		("scn_custom_" ++ key): value
	}
 
fun mapJMeterSummary(timestamp, jmeterSummary) = {
	timestamp: timestamp,
	test_label: jmeterSummary.Label,
	test_cnt_samples: jmeterSummary.'# Samples' as Number,
	test_cnt_errors: round((jmeterSummary.'# Samples' as Number) * (jmeterSummary.'Error %' as Number {format: ".00%"})) as Number,
	test_error_pct: jmeterSummary.'Error %' as Number {format: ".00%"},
	test_avg_response_time_ms: to_float_safe(jmeterSummary.Average),
	test_min_response_time_ms: to_float_safe(jmeterSummary.Min),
	test_max_response_time_ms: to_float_safe(jmeterSummary.Max),
	test_90pctl_response_time_ms: to_float_safe(jmeterSummary.'90% Line'),
	test_stddev_response_time_ms: to_float_safe(jmeterSummary.'Std. Dev.'),
	test_avg_throughput_tps: to_float_safe(jmeterSummary.Throughput),
	test_avg_network_received_kbs: to_float_safe(jmeterSummary.'Received KB/sec'),
	test_avg_network_sent_kbs: to_float_safe(jmeterSummary.'Avg. Bytes')
}

/*
 * ================================
 *     Final mappings
 * ================================
 */
fun mapCiBuildInfo(config, decomposedBuildTag, rawCiBuildInfo, wholeTestMonNewRelicLink) = {
	timestamp: (rawCiBuildInfo.timestamp/1000) as DateTime,
	scn_job_name: decomposedBuildTag.job_name,
	scn_full_job_name: decomposedBuildTag.full_job_name,
	scn_build_number: rawCiBuildInfo.number,
	scn_hudson_user: rawCiBuildInfo.actions..userId[0],
	scn_job: decomposedBuildTag.job,
	scn_build_tag: config.build_tag,
	scn_build_url: rawCiBuildInfo.url,
	scn_node_name: rawCiBuildInfo.builtOn,
	scn_newrelic_app_id: config.newrelic_app_id,
	mon_newrelic_link: wholeTestMonNewRelicLink
}

fun mapSummarizedTestResults(ciBuildInfo, monNewRelicLink, testParams, customTestParams, jmeterSummaryTotal, dmsSummarizedAppMetrics) = 
	if (jmeterSummaryTotal != null)
		((ciBuildInfo default {}) - "timestamp" - "mon_newrelic_link") ++
		({ mon_newrelic_link: monNewRelicLink }) ++
		(testParams default {}) ++ 
		(customTestParams default {}) ++ 
		jmeterSummaryTotal ++ 
		((dmsSummarizedAppMetrics default {}) - "mon_nr_timestamp")
	else
		null	

fun mapDetailedTestResults(ciBuildInfo, testParams, customTestParams, jmeterSummaryDetail) = 
	(jmeterSummaryDetail default []) map (
		((ciBuildInfo default {}) - "timestamp" - "mon_newrelic_link") ++ 
		(testParams default {}) ++ 
		(customTestParams default {}) ++
		$
	)

fun mapDmsNewRelicMetrics(ciBuildInfo, monNewRelicLink, testParams, customTestParams, dmsNewRelicMetrics) =
	(dmsNewRelicMetrics default []) map (
		((ciBuildInfo default {}) - "timestamp" - "mon_newrelic_link") ++
		({ mon_newrelic_link: monNewRelicLink }) ++
		(testParams default {}) ++ 
		(customTestParams default {}) ++ 
		($ mapObject (value, key) -> {
			(if (key as String == 'mon_nr_timestamp')
				(("timestamp"): value)
			else
				((key): value)
			)
		})
	)