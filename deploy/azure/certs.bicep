// Free managed certificates for custom hostnames, created in the Container Apps environment's own
// resource group (which may be another group when the environment is shared). Used by main.bicep.

param environmentName string
param location string
param hosts array

resource env 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: environmentName
}

resource certs 'Microsoft.App/managedEnvironments/managedCertificates@2024-03-01' = [
  for host in hosts: {
    parent: env
    name: 'cert-${replace(host, '.', '-')}'
    location: location
    // The hostnames are already on the apps (the 'add' deploy); validation uses their CNAME records.
    properties: { subjectName: host, domainControlValidation: 'CNAME' }
  }
]
