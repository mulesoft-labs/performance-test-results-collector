%dw 2.0
fun buildLogMessage ( step, status, message, errorDetailedDescription ) = 
{
	timestamp: now() as String {format: "YYYY-MM-dd'T'HH:mm:ss"},
	step: step,
	status: status,
	(message: message) if (message != null),
	(error_detailed_description: errorDetailedDescription) if (errorDetailedDescription != null),
}

fun buildSuccessLogMessage ( step, message ) = buildLogMessage(step, "ok", message, null)
fun buildFailureLogMessage ( step, message, errorDetailedDescription ) = buildLogMessage(step, "failed", message, errorDetailedDescription)