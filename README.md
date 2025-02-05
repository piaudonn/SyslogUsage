# 📚 Syslog Usage

The `Usage` table can be used to track ingestion volume per table in Log Analytics/Sentinel. However, it only does at the table level. If a table has more than one type of source or one type of data, one need to query the actual table to gather usage data at a more granular level.    
`Syslog` and `CommonSecurityLog` can get significantly large in large enterprise environment.  Using the Usage table is useful to understand the overall cost, but it fails at telling us which technology behind it is responsible for the ingestion and can hardly be used for monitoring.
The usual workaround is to gather the information directly from the Syslog table like for example:

```kql
CommonSecurityLog
| where TimeGenerated> ago(90d)
| summarize Quantity = sum(_BilledSize / 1024 / 1024) by DeviceVendor, DeviceProduct, Computer, CollectorHostName
```

Unfortunately, this approach will fail if the amount of data is too large. Forcing one to break down the query into multiple subquery per bucket of small time periods. This solution addresses this by creating a custom table `SyslogUsage_CL` (the name can be picked at deployment time) which has the same schema as the `Usage` table but with Syslog (and/or CEF) usage statistics.

![image](https://github.com/user-attachments/assets/8cd194de-ec52-4495-bc00-fb584b99695b)

The solution is composed of the following:
- A custom table to receive the ingestion (usage) statistics
- A Data Collection Endpoint (DCE) to ingest data into that table
- A Data Collection Rule (DCR) to receive data using the DCE
- A Logic App running on a recurrence trigger (set to 1 hour) to query the source table and send the statistics to the custom table through the DCR

To deploy it click here:

[![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fpiaudonn%2FSyslogUsage%2Frefs%2Fheads%2Fmain%2Fdeploy%2Fsyslogusage.json)

After you deployed it, you need to grant the System Managed Identity of the Logic App permissions to query the data from Log Analytics and to send data to the DCR. You can use this [script](/deploy/permissions.ps1) to configure them.  
