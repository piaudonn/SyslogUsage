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

<img width="496" alt="image" src="https://github.com/user-attachments/assets/8eeeb7c1-acaf-4f21-8fdf-82fe32101329" />
