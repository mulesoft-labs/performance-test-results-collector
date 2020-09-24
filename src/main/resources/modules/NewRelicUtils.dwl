%dw 2.0
var NR_UI_MIN_TIME_WINDOW = 180

fun truncateSeconds( date ) = 
	floor((date as DateTime as Number)/60)*60
	
fun calculateAdjustedEndTime( tstart, tend ) = 
	if ((tend - tstart) < NR_UI_MIN_TIME_WINDOW)
		tend + NR_UI_MIN_TIME_WINDOW - (tend - tstart)
	else
		tend

fun adjustNewRelicTimeWindowIfNeeded( tstart, tend ) = {
	from: truncateSeconds(tstart) as DateTime,
	to: calculateAdjustedEndTime(truncateSeconds(tstart), truncateSeconds(tend)) as DateTime
}


fun buildNewRelicLink( app_id, tstart, tend ) = 
	if (app_id != null and tstart != null and tend != null)
		"https://rpm.newrelic.com/accounts/205337/applications/" ++ (app_id default "") ++ "?tw%5Bstart%5D=" ++ (tstart as DateTime as Number) ++ "&tw%5Bend%5D=" ++ (tend as DateTime as Number)
	else
		null
