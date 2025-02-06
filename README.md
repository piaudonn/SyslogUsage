# 📚 Syslog Usage

The `Usage` table can be used to track ingestion volume per table in Log Analytics/Sentinel. However, it only does at the table level. If a table has more than one type of source or one type of data, one need to query the actual table to gather usage data at a more granular level.    
`Syslog` and `CommonSecurityLog` can get significantly large in large enterprise environment.  Using the Usage table is useful to understand the overall cost, but it fails at telling us which technology behind it is responsible for the ingestion and can hardly be used for monitoring.
The usual workaround is to gather the information directly from the Syslog table like for example:

```kql
CommonSecurityLog
| where TimeGenerated> ago(90d)
| summarize Quantity = sum(_BilledSize / 1024 / 1024) by DeviceVendor, DeviceProduct, Computer, CollectorHostName
```

Unfortunately, this approach will fail if the amount of data is too large. Forcing one to break down the query into multiple subquery per bucket of small time periods. This solution addresses this by creating a custom table `SyslogUsage_CL` (the name can be picked at deployment time) which has the same schema as the `Usage` table but with Syslog (and/or CEF) usage statistics. It also calcualtes an average EPS for the hour per line.

![image](https://github.com/user-attachments/assets/8cd194de-ec52-4495-bc00-fb584b99695b)

The solution is composed of the following:
- A custom table to receive the ingestion (usage) statistics
- A Data Collection Endpoint (DCE) to ingest data into that table
- A Data Collection Rule (DCR) to receive data using the DCE
- A Logic App running on a recurrence trigger (set to 1 hour) to query the source table and send the statistics to the custom table through the DCR

To deploy it click here:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fpiaudonn%2FSyslogUsage%2Frefs%2Fheads%2Fmain%2Fdeploy%2Fsyslogusage.json)

After you deployed it, you need to grant the System Managed Identity of the Logic App permissions to query the data from Log Analytics and to send data to the DCR. You can use this [script](/deploy/permissions.ps1) to configure them.  

## Logic App structure

This is the Logic App the solution deploys:

<img width="133" alt="image" src="https://github.com/user-attachments/assets/712b2f90-1757-4dee-b045-e16ed318b933" />

- **Every hour** is the recurrence trigger that runs every hour since the time of the deployment.
- **Get the starting time** this steps runs with the system managed identity. It executes the following query:
```kql
union isfuzzy=true
    (print LastTime = now() - 1h) ,
    (SyslogCustomUsage_CL
    | summarize LastTime = max(TimeGenerated))
 | summarize LastTime = max(LastTime)
```
Where `SyslogCustomUsage_CL` is the name of the custom table you chose at installation time. If the table exist we look at the last time we ingested statistics for the starting point of this execution. Else, if that's the very first time the Logic App runs, we use `now() - 1h` as a starting point. 
- **Get the usage** is calculating the ingestion statistic by DeviceVendor, DeviceProduct, Computer and CollectorHostName. The result is expressed in MBytes (like for the Usage table) in the column `Quantity`:
 ```kql
let TimeReference = datetime(@{body('Get_the_starting_time')?['value']?[0]['LastTime']}) ;
let EndTimeReference = now(); 
union isfuzzy=true (CommonSecurityLog
| where TimeGenerated between (TimeReference .. EndTimeReference)
| summarize Quantity = sum(_BilledSize / 1024 / 1024), EventCount = count() by DeviceVendor, DeviceProduct, Computer, CollectorHostName, Table=Type
| extend TimeGenerated = now(), StartTime = TimeReference, EndTime = EndTimeReference, EPS = toreal(EventCount)/60/60),
(Syslog
| where TimeGenerated between (TimeReference .. EndTimeReference)
| summarize Quantity = sum(_BilledSize / 1024 / 1024), EventCount = count() by Computer, CollectorHostName, Table = Type
| extend TimeGenerated = now(), StartTime = TimeReference, EndTime = EndTimeReference, EPS = toreal(EventCount)/60/60)
```
Where `datetime(@{body('Get_the_starting_time')?['value']?[0]['LastTime']})` is the starting time we determine in the previous step.
- **Upload usage** this steps is also running with the system managed identity. It ingest the calculated usage statistics into the custom table using the DCR created at installation.


