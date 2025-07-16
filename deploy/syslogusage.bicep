@description('The name of the custom table to be created in the Log Analytics workspace (without _CL).')
param customTableName string = 'SyslogCEFCustomUsage'

@description('The name of the log analytics workspace where the custom table will be created.')
param workspaceName string = 'wks'

@description('The name of the data collection rule (DCR).')
param dataCollectionRule string = 'DCR-CustomUsage'

@description('The name of the logic app creating the usage statistics.')
param logicAppName string = 'CustomUsage'

var workspaceResourceId = '/subscriptions/${subscription().subscriptionId}/resourcegroups/${resourceGroup().name}/providers/Microsoft.OperationalInsights/workspaces/${workspaceName}'
var webConnectionName = 'SyslogCEFCustomUsage-Connection'

resource workspaceName_customTableName_CL 'Microsoft.OperationalInsights/workspaces/tables@2023-09-01' = {
  name: '${workspaceName}/${customTableName}_CL'
  properties: {
    plan: 'Analytics'
    schema: {
      name: '${customTableName}_CL'
      columns: [
        {
          name: 'TimeGenerated'
          type: 'DateTime'
        }
        {
          name: 'StartTime'
          type: 'DateTime'
        }
        {
          name: 'EndTime'
          type: 'DateTime'
        }
        {
          name: 'DeviceVendor'
          type: 'String'
        }
        {
          name: 'DeviceProduct'
          type: 'String'
        }
        {
          name: 'Computer'
          type: 'String'
        }
        {
          name: 'CollectorHostName'
          type: 'String'
        }
        {
          name: 'Table'
          type: 'String'
        }
        {
          name: 'EPS'
          type: 'Real'
        }
        {
          name: 'Quantity'
          type: 'Real'
        }
      ]
    }
  }
}

resource dataCollectionRule_resource 'Microsoft.Insights/dataCollectionRules@2023-03-11' = {
  name: dataCollectionRule
  kind: 'Direct'
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    streamDeclarations: {
      'Custom-${customTableName}_CL': {
        columns: [
          {
            name: 'TimeGenerated'
            type: 'datetime'
          }
          {
            name: 'StartTime'
            type: 'datetime'
          }
          {
            name: 'EndTime'
            type: 'datetime'
          }
          {
            name: 'DeviceVendor'
            type: 'string'
          }
          {
            name: 'DeviceProduct'
            type: 'string'
          }
          {
            name: 'Computer'
            type: 'string'
          }
          {
            name: 'CollectorHostName'
            type: 'string'
          }
          {
            name: 'Table'
            type: 'string'
          }
          {
            name: 'Quantity'
            type: 'real'
          }
          {
            name: 'EPS'
            type: 'real'
          }
        ]
      }
    }
    dataSources: {}
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceResourceId
          name: 'TargetWorkspace'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Custom-${customTableName}_CL'
        ]
        destinations: [
          'TargetWorkspace'
        ]
      }
    ]
  }
}

resource webConnection 'Microsoft.Web/connections@2016-06-01' = {
  name: webConnectionName
  location: resourceGroup().location
  kind: 'V1'
  properties: {
    displayName: webConnectionName
    customParameterValues: {}
    parameterValueSet: {
      name: 'managedIdentityAuth'
    }
    api: {
      id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/${resourceGroup().location}/managedApis/azuremonitorlogs'
    }
  }
}

resource logicApp 'Microsoft.Logic/workflows@2017-07-01' = {
  name: logicAppName
  location: resourceGroup().location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        'Data Collection Endpoint URI': {
          defaultValue: dataCollectionRule_resource.properties.endpoints.logsIngestion
          type: 'String'
        }
        'DCR Immutable ID': {
          defaultValue: dataCollectionRule_resource.properties.immutableId
          type: 'String'
        }
        'Stream Name': {
          defaultValue: 'Custom-${customTableName}_CL'
          type: 'String'
        }
        'Subcription ID': {
          defaultValue: subscription().subscriptionId
          type: 'String'
        }
        'Resource Group Name': {
          defaultValue: resourceGroup().name
          type: 'String'
        }
        'Workspace Name': {
          defaultValue: workspaceName
          type: 'String'
        }
        '$connections': {
          defaultValue: {}
          type: 'Object'
        }
      }
      triggers: {
        Every_hour: {
          recurrence: {
            interval: 1
            frequency: 'Hour'
          }
          evaluatedRecurrence: {
            interval: 1
            frequency: 'Hour'
          }
          type: 'Recurrence'
        }
      }
      actions: {
        Get_the_starting_time: {
          runAfter: {}
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuremonitorlogs\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              query: 'union isfuzzy=true\n    (print LastTime = now() - 1h) ,\n    (${customTableName}_CL\n    | summarize LastTime = max(TimeGenerated))\n | summarize LastTime = max(LastTime)'
              timerangetype: '2'
              timerange: {
                relativeTimeRange: 'Last 48 hours'
              }
            }
            path: '/queryDataV2'
            queries: {
              subscriptions: '@parameters(\'Subcription ID\')'
              resourcegroups: '@parameters(\'Resource Group Name\')'
              resourcetype: 'Log Analytics Workspace'
              resourcename: '@parameters(\'Workspace Name\')'
            }
          }
        }
        Upload_usage: {
          runAfter: {
            Get_the_usage: [
              'Succeeded'
            ]
          }
          type: 'Http'
          inputs: {
            uri: '@{parameters(\'Data Collection Endpoint URI\')}/dataCollectionRules/@{parameters(\'DCR Immutable ID\')}/streams/@{parameters(\'Stream Name\')}?api-version=2023-01-01'
            method: 'POST'
            headers: {
              'Content-Type': 'application/json'
            }
            body: '@body(\'Get_the_usage\')?[\'value\']'
            authentication: {
              type: 'ManagedServiceIdentity'
              audience: 'https://monitor.azure.com'
            }
          }
          runtimeConfiguration: {
            contentTransfer: {
              transferMode: 'Chunked'
            }
          }
        }
        Get_the_usage: {
          runAfter: {
            Get_the_starting_time: [
              'Succeeded'
            ]
          }
          type: 'ApiConnection'
          inputs: {
            host: {
              connection: {
                name: '@parameters(\'$connections\')[\'azuremonitorlogs\'][\'connectionId\']'
              }
            }
            method: 'post'
            body: {
              query: 'let TimeReference = datetime(@{body(\'Get_the_starting_time\')?[\'value\']?[0][\'LastTime\']}) ;\nlet EndTimeReference = now();\n union isfuzzy=true (CommonSecurityLog \n| where TimeGenerated between (TimeReference .. EndTimeReference) \n| summarize Quantity = sum(_BilledSize / 1024 / 1024), EventCount = count() by DeviceVendor, DeviceProduct, Computer, CollectorHostName, Table=Type \n| extend TimeGenerated = now(), StartTime = TimeReference, EndTime = EndTimeReference, EPS = toreal(EventCount)/60/60), \n(Syslog \n| where TimeGenerated between (TimeReference .. EndTimeReference) \n| summarize Quantity = sum(_BilledSize / 1024 / 1024), EventCount = count() by Computer, CollectorHostName, Table=Type \n| extend TimeGenerated = now(), StartTime = TimeReference, EndTime = EndTimeReference, EPS = toreal(EventCount)/60/60)'
              timerangetype: '2'
              timerange: {
                relativeTimeRange: 'Last 7 days'
              }
            }
            path: '/queryDataV2'
            queries: {
              subscriptions: '@parameters(\'Subcription ID\')'
              resourcegroups: '@parameters(\'Resource Group Name\')'
              resourcetype: 'Log Analytics Workspace'
              resourcename: '@parameters(\'Workspace Name\')'
            }
          }
        }
      }
      outputs: {}
    }
    parameters: {
      '$connections': {
        value: {
          azuremonitorlogs: {
            id: '/subscriptions/${subscription().subscriptionId}/providers/Microsoft.Web/locations/eastus/managedApis/azuremonitorlogs'
            connectionId: webConnection.id
            connectionName: webConnectionName
            connectionProperties: {
              authentication: {
                type: 'ManagedServiceIdentity'
              }
            }
          }
        }
      }
    }
  }
}

resource dataCollectionRulePublisher 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataCollectionRule_resource.id, 'Monitoring Metrics Publisher')
  scope: dataCollectionRule_resource
  properties: {
    principalId: logicApp.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '3913510d-42f4-4e42-8a64-420c390055eb')
    principalType: 'ServicePrincipal'
  }
}
