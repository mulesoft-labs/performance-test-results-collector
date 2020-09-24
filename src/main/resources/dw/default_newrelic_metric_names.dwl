%dw 2.0
output application/json
var defaultMetricNames = ["WebTransaction", "External/all", "Datastore/all", "Errors/all", "CPU/User Time", "CPU/User/Utilization", "Memory/Physical"]
// var extendedMetricNames = defaultMetricNames ++ ["CPU/System Time","CPU/System/Utilization", "Memory/Heap/Free", "Memory/Heap/Used", "Memory/NonHeap/Used", "Memory/Heap/Max"]
---
defaultMetricNames reduce (metric, acc = {}) -> acc ++ { "names[]": metric }