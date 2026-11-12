// Free managed certificates for custom hostnames, created in the Container Apps environment's own
// resource group (which may be another group when the environment is shared). Used by main.bicep.

param environmentName string
param location string
@description('[{ host, validation: CNAME | HTTP }] — HTTP for a root domain (no CNAME possible there).')
param hosts array

resource env 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: environmentName
}

resource certs 'Microsoft.App/managedEnvironments/managedCertificates@2024-03-01' = [
  for h in hosts: {
    parent: env
    name: 'cert-${replace(h.host, '.', '-')}'
    location: location
    // The hostnames are already on the apps (the 'add' deploy); validation uses their DNS records.
    properties: { subjectName: h.host, domainControlValidation: h.validation }
  }
]
