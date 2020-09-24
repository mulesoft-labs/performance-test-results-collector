# performance-test-results-collector

performance test results collector mule application

To reduce the shell clutter, number of integration points and number of API calls with DMS V1 application, test results collector has been developed with DMS V2.
It also contains logic to collect metrics from NewRelic (Using DMS v2) and posting into Elastic search.

# Retirement

Retired this application from performance automation As NewRelic has rich API's now to reduce the orchestration. However, Keeping this repo in mulesoft labs for future reference.

# Repo

- It contains Mule app for deployment
- [Shell script][1] to invoke this application.
- [Performance WIKI][2]


[1]:https://github.com/mulesoft-labs/performance-test-results-collector/blob/master/collect_and_push_results_to_elastic_v3.sh
[2]:https://wiki.corp.mulesoft.com/pages/viewpage.action?spaceKey=PERF&title=Perf+Utility+Mule+Applications
