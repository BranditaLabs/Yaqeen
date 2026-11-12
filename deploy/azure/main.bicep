// Yaqeen on Azure Container Apps (its own environment, or an existing shared one). Deployed by
// tools/deploy/azure.sh — run that, not this file directly: it generates/reads the secrets, builds
// the images and walks the stages (infra → apps → custom domains). See docs/OPERATIONS.md › Azure.
//
//   infra      ACR, Key Vault, Postgres, identities (+ VNet, Log Analytics, environment unless shared)
//   apps       api (public), admin (public), redis (VNet-internal TCP; own environment only),
//              migrate + purge (+ campaigns) jobs
//   domains    'none' → 'add' (hostnames, no cert) → 'bind' (managed certificates, SNI)

targetScope = 'resourceGroup'

@description('Environment name: staging | production.')
@allowed(['staging', 'production'])
param envName string = 'staging'
@description('Region of the shared services: identities, registry, Key Vault, logs, Postgres.')
param location string = resourceGroup().location
@description('Region of the Container Apps environment, its VNet and the apps/jobs (may differ: one environment per region on a Free Trial).')
param appsLocation string = location

@description('Resource id of an existing Container Apps environment to run in instead of creating one (staging on a Free Trial, which allows one environment per subscription). Its region must equal appsLocation.')
param existingEnvironmentId string = ''

@description('Run Redis (needs the VNet of an own environment). Without it the API keeps cache and rate limits in memory, so it runs as a single replica.')
param enableRedis bool = true

@description('Object id of whoever runs the deploy: gets Key Vault Secrets Officer to read/write the secrets.')
param deployerPrincipalId string
@allowed(['User', 'ServicePrincipal'])
param deployerPrincipalType string = 'User'

@description('false = infrastructure only (the first run, before any image exists).')
param deployApps bool = false
param apiImage string = ''
param adminImage string = ''
param redisImage string = ''

@description('Public hosts once DNS points here (docs/OPERATIONS.md › Azure › Custom domains).')
param apiHost string
param adminHost string
@description('Root-domain host for the website, cards and app links (e.g. yaqeenarabia.com), served by the API too; empty = they live on apiHost.')
param siteHost string = ''
@allowed(['none', 'add', 'bind'])
param domainMode string = 'none'

@description('Postgres disk; never below the live size (auto-grow only grows, and storage cannot shrink).')
param pgStorageGB int = 32

@description('Optional CIDRs allowed to reach the admin console (empty = open, still behind password + TOTP).')
param adminAllowedCidrs array = []

@description('Campaign dispatcher cron. Off in staging: it must never push to real users.')
param enableCampaigns bool = false

@description('Non-secret API settings layered over the defaults below (deploy/azure/<env>.env.json).')
param apiSettings object = {}
@description('Optional API secrets already in Key Vault, as [{ env: "SHOPIFY_ADMIN_TOKEN", secret: "env-shopify-admin-token" }].')
param extraSecrets array = []

@secure()
param pgPassword string
@secure()
param redisPassword string
@secure()
param jwtSecret string
@secure()
param adminJwtSecret string
@secure()
param adminSecretsKey string
@secure()
param backupSecretsKey string

var suffix = substring(uniqueString(resourceGroup().id), 0, 6)
var tags = { app: 'yaqeen', env: envName }
var isProd = envName == 'production'
var useShared = !empty(existingEnvironmentId)
var redisOn = enableRedis && !useShared
var envRg = useShared ? split(existingEnvironmentId, '/')[4] : resourceGroup().name
var envResourceName = useShared ? last(split(existingEnvironmentId, '/')) : 'cae-yaqeen-${envName}'

// ---------------------------------------------------------------- identity, registry, secrets

resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-yaqeen-${envName}'
  location: location
  tags: tags
}

// admin (public Next.js) and redis (third-party image) get their own identity: it can pull images and
// read only the Redis password — never the vault's other secrets (database, sealing keys, tokens).
resource identityEdge 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: 'id-yaqeen-${envName}-edge'
  location: location
  tags: tags
}

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: 'cryaqeen${envName}${suffix}'
  location: location
  tags: tags
  sku: { name: 'Basic' }
  properties: { adminUserEnabled: false }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-yaqeen-${take(envName, 4)}-${suffix}'
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: { family: 'A', name: 'standard' }
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: isProd ? 90 : 7
    // Production keeps deleted keys recoverable: losing BACKUP_SECRETS_KEY makes every backup unreadable.
    enablePurgeProtection: isProd ? true : null
  }
}

var roles = {
  acrPull: '7f951dda-4ed3-4680-a7ca-43fe172d538d'
  kvSecretsUser: '4633458b-17de-408a-b874-0445c86b69e6'
  kvSecretsOfficer: 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
}

resource identityAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, identity.id, roles.acrPull)
  scope: acr
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.acrPull)
  }
}

resource identityKvRead 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, identity.id, roles.kvSecretsUser)
  scope: kv
  properties: {
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.kvSecretsUser)
  }
}

resource edgeAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, identityEdge.id, roles.acrPull)
  scope: acr
  properties: {
    principalId: identityEdge.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.acrPull)
  }
}

resource deployerKv 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, deployerPrincipalId, roles.kvSecretsOfficer)
  scope: kv
  properties: {
    principalId: deployerPrincipalId
    principalType: deployerPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.kvSecretsOfficer)
  }
}

// ---------------------------------------------------------------- network, logs, environment

resource vnet 'Microsoft.Network/virtualNetworks@2023-11-01' = if (!useShared) {
  name: 'vnet-yaqeen-${envName}'
  location: appsLocation
  tags: tags
  properties: {
    addressSpace: { addressPrefixes: ['10.60.0.0/16'] }
    subnets: [
      {
        // Workload-profiles environments need a delegated subnet (≥ /27); VNet integration is
        // what lets Redis be reachable over internal TCP and nothing else.
        name: 'snet-apps'
        properties: {
          addressPrefix: '10.60.0.0/23'
          delegations: [{ name: 'apps', properties: { serviceName: 'Microsoft.App/environments' } }]
        }
      }
    ]
  }
}

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if (!useShared) {
  name: 'log-yaqeen-${envName}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
    workspaceCapping: { dailyQuotaGb: isProd ? -1 : 1 }
  }
}

resource cae 'Microsoft.App/managedEnvironments@2024-03-01' = if (!useShared) {
  name: envResourceName
  location: appsLocation
  tags: tags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: { customerId: law!.properties.customerId, sharedKey: law!.listKeys().primarySharedKey }
    }
    vnetConfiguration: { infrastructureSubnetId: vnet!.properties.subnets[0].id, internal: false }
    workloadProfiles: [{ name: 'Consumption', workloadProfileType: 'Consumption' }]
    zoneRedundant: false
  }
}

resource caeShared 'Microsoft.App/managedEnvironments@2024-03-01' existing = if (useShared) {
  name: envResourceName
  scope: resourceGroup(envRg)
}

var environmentId = useShared ? existingEnvironmentId : cae!.id

// ---------------------------------------------------------------- Postgres 16

resource pg 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: 'psql-yaqeen-${envName}-${suffix}'
  location: location
  tags: tags
  sku: isProd ? { name: 'Standard_D2ds_v5', tier: 'GeneralPurpose' } : { name: 'Standard_B1ms', tier: 'Burstable' }
  properties: {
    version: '16'
    administratorLogin: 'yqadmin'
    administratorLoginPassword: pgPassword
    storage: { storageSizeGB: pgStorageGB, autoGrow: 'Enabled' }
    backup: { backupRetentionDays: isProd ? 35 : 7, geoRedundantBackup: 'Disabled' }
    highAvailability: { mode: 'Disabled' }
    authConfig: { activeDirectoryAuth: 'Disabled', passwordAuth: 'Enabled' }
    // TLS is enforced by the server (require_secure_transport). Access: Azure-hosted clients only
    // (the rule below); production should move to private access in the VNet.
    network: { publicNetworkAccess: 'Enabled' }
  }
}

resource pgDb 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: pg
  name: 'yaqeen'
  properties: { charset: 'UTF8', collation: 'en_US.utf8' }
}

resource pgAzureClients 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: pg
  name: 'AllowAzureServices'
  properties: { startIpAddress: '0.0.0.0', endIpAddress: '0.0.0.0' }
}

// ---------------------------------------------------------------- Key Vault secrets

var redisHost = 'yaqeen-redis'
// Names are fixed at compile time (loops need that); the values line up by index.
var vaultSecretNames = [
  'pg-password'
  'redis-password'
  'jwt-secret'
  'admin-jwt-secret'
  'admin-secrets-key'
  'backup-secrets-key'
  'database-url'
  'redis-url'
]
var vaultSecretValues = [
  pgPassword
  redisPassword
  jwtSecret
  adminJwtSecret
  adminSecretsKey
  backupSecretsKey
  'postgres://yqadmin:${pgPassword}@${pg.properties.fullyQualifiedDomainName}:5432/${pgDb.name}?sslmode=require'
  'redis://:${redisPassword}@${redisHost}:6379'
]

resource kvSecrets 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [
  for (name, i) in vaultSecretNames: {
    parent: kv
    name: name
    properties: { value: vaultSecretValues[i], contentType: 'text/plain' }
  }
]

resource edgeRedisSecret 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(kv.id, identityEdge.id, 'redis-password')
  scope: kvSecrets[1] // redis-password
  properties: {
    principalId: identityEdge.properties.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.kvSecretsUser)
  }
}

// ---------------------------------------------------------------- apps

var registries = [{ server: acr.properties.loginServer, identity: identity.id }]
var edgeRegistries = [{ server: acr.properties.loginServer, identity: identityEdge.id }]
// Built from the name (not kv.properties) so it can be used inside loops.
var vaultUri = 'https://${kv.name}${environment().suffixes.keyvaultDns}/'

// The API's own secrets, then whatever optional integration secrets the owner has added to the vault.
var apiSecretEnv = concat(
  [
    { env: 'DATABASE_URL', secret: 'database-url' }
    { env: 'JWT_SECRET', secret: 'jwt-secret' }
    { env: 'ADMIN_JWT_SECRET', secret: 'admin-jwt-secret' }
    { env: 'ADMIN_SECRETS_KEY', secret: 'admin-secrets-key' }
    { env: 'BACKUP_SECRETS_KEY', secret: 'backup-secrets-key' }
  ],
  redisOn ? [{ env: 'REDIS_URL', secret: 'redis-url' }] : [],
  extraSecrets
)
var apiSecrets = [for s in apiSecretEnv: { name: s.secret, keyVaultUrl: '${vaultUri}secrets/${s.secret}', identity: identity.id }]

// deploy/k8s/config.yaml, adapted to this environment; deploy/azure/<env>.env.json overrides.
var apiDefaults = {
  NODE_ENV: 'production'
  LOG_LEVEL: 'info'
  CORS_ORIGINS: 'https://${adminHost}'
  HIJRI_REGION: 'EG'
  QF_ENV: 'production'
  SHOPIFY_API_VERSION: '2025-10'
  PG_POOL_MAX: '10'
  PG_STATEMENT_TIMEOUT_MS: '10000'
  RATE_LIMIT_PER_MIN: '300'
  MAX_EVENT_LOOP_DELAY_MS: '1000'
  SHUTDOWN_GRACE_MS: '15000'
  METRICS_PORT: '0'
  SENTRY_ENVIRONMENT: envName
  SENTRY_TRACES_SAMPLE_RATE: isProd ? '0' : '0.2'
  PUBLIC_PROFILE_BASE_URL: 'https://${empty(siteHost) ? apiHost : siteHost}'
}
// Empty REDIS_URL = in-memory cache and rate limits (the env default would point at localhost).
var redisOffEnv = redisOn ? {} : { REDIS_URL: '' }
var apiPlainEnv = [for e in items(union(apiDefaults, redisOffEnv, apiSettings)): { name: e.key, value: string(e.value) }]
var apiSecretVars = [for s in apiSecretEnv: { name: s.env, secretRef: s.secret }]
var apiEnv = concat(apiPlainEnv, apiSecretVars)

// The preceding 'add' deploy already put the hostnames on the apps; the apps then bind these.
module managedCerts 'certs.bicep' = if (domainMode == 'bind') {
  name: 'yaqeen-${envName}-certs'
  scope: resourceGroup(envRg)
  params: {
    environmentName: envResourceName
    location: appsLocation
    // A root domain can't have a CNAME: its certificate validates over HTTP (A record + asuid TXT).
    hosts: concat(
      [{ host: apiHost, validation: 'CNAME' }, { host: adminHost, validation: 'CNAME' }],
      empty(siteHost) ? [] : [{ host: siteHost, validation: 'HTTP' }]
    )
  }
  dependsOn: [cae]
}
var apiCertId = resourceId(subscription().subscriptionId, envRg, 'Microsoft.App/managedEnvironments/managedCertificates', envResourceName, 'cert-${replace(apiHost, '.', '-')}')
var siteCertId = resourceId(subscription().subscriptionId, envRg, 'Microsoft.App/managedEnvironments/managedCertificates', envResourceName, 'cert-${replace(siteHost, '.', '-')}')
var adminCertId = resourceId(subscription().subscriptionId, envRg, 'Microsoft.App/managedEnvironments/managedCertificates', envResourceName, 'cert-${replace(adminHost, '.', '-')}')

var apiDomains = domainMode == 'none' ? [] : concat(
  [domainMode == 'bind' ? { name: apiHost, bindingType: 'SniEnabled', certificateId: apiCertId } : { name: apiHost, bindingType: 'Disabled' }],
  empty(siteHost) ? [] : [domainMode == 'bind' ? { name: siteHost, bindingType: 'SniEnabled', certificateId: siteCertId } : { name: siteHost, bindingType: 'Disabled' }]
)
var adminDomains = domainMode == 'none' ? [] : [
  domainMode == 'bind'
    ? { name: adminHost, bindingType: 'SniEnabled', certificateId: adminCertId }
    : { name: adminHost, bindingType: 'Disabled' }
]

resource redis 'Microsoft.App/containerApps@2024-03-01' = if (deployApps && redisOn) {
  name: 'yaqeen-redis'
  location: appsLocation
  tags: tags
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identityEdge.id}': {} } }
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      // Reachable only inside the environment, at yaqeen-redis:6379, with a password.
      ingress: { external: false, transport: 'tcp', targetPort: 6379, exposedPort: 6379 }
      registries: edgeRegistries
      secrets: [{ name: 'redis-password', keyVaultUrl: '${vaultUri}secrets/redis-password', identity: identityEdge.id }]
    }
    template: {
      containers: [
        {
          name: 'redis'
          image: redisImage
          command: ['sh', '-c']
          // Cache, rate limits and job locks only: no persistence needed.
          args: ['exec redis-server --requirepass "$REDIS_PASSWORD" --save "" --appendonly no --maxmemory 192mb --maxmemory-policy allkeys-lru']
          env: [{ name: 'REDIS_PASSWORD', secretRef: 'redis-password' }]
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
        }
      ]
      scale: { minReplicas: 1, maxReplicas: 1 }
    }
  }
  dependsOn: [edgeAcrPull, edgeRedisSecret]
}

resource api 'Microsoft.App/containerApps@2024-03-01' = if (deployApps) {
  name: 'yaqeen-api'
  location: appsLocation
  tags: tags
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identity.id}': {} } }
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      // Only the HTTP port is exposed; METRICS_PORT stays 0 here (Azure Monitor collects instead).
      ingress: { external: true, targetPort: 4000, transport: 'auto', allowInsecure: false, customDomains: apiDomains }
      registries: registries
      secrets: apiSecrets
    }
    template: {
      containers: [
        {
          name: 'api'
          image: apiImage
          env: apiEnv
          resources: { cpu: json('0.5'), memory: '1Gi' }
          probes: [
            { type: 'Startup', httpGet: { path: '/health', port: 4000 }, initialDelaySeconds: 3, periodSeconds: 5, failureThreshold: 10 }
            { type: 'Liveness', httpGet: { path: '/health', port: 4000 }, periodSeconds: 15, failureThreshold: 4 }
            { type: 'Readiness', httpGet: { path: '/ready', port: 4000 }, periodSeconds: 5, failureThreshold: 2 }
          ]
        }
      ]
      scale: {
        minReplicas: isProd ? 2 : 1
        // Without Redis, cache and rate limits are per process: exactly one replica.
        maxReplicas: !redisOn ? 1 : (isProd ? 10 : 3)
        rules: [{ name: 'http', http: { metadata: { concurrentRequests: '100' } } }]
      }
    }
  }
  dependsOn: [identityAcrPull, identityKvRead, kvSecrets, redis, managedCerts]
}

resource admin 'Microsoft.App/containerApps@2024-03-01' = if (deployApps) {
  name: 'yaqeen-admin'
  location: appsLocation
  tags: tags
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${identityEdge.id}': {} } }
  properties: {
    environmentId: environmentId
    workloadProfileName: 'Consumption'
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 3000
        transport: 'auto'
        allowInsecure: false
        customDomains: adminDomains
        ipSecurityRestrictions: [for (cidr, i) in adminAllowedCidrs: { name: 'allow-${i}', action: 'Allow', ipAddressRange: cidr }]
      }
      registries: edgeRegistries
    }
    template: {
      containers: [
        {
          name: 'admin'
          image: adminImage
          env: [
            // Server-side calls to the API stay inside the environment.
            { name: 'API_URL', value: 'http://yaqeen-api' }
            { name: 'NEXT_TELEMETRY_DISABLED', value: '1' }
            { name: 'SENTRY_ENVIRONMENT', value: envName }
          ]
          resources: { cpu: json('0.25'), memory: '0.5Gi' }
          probes: [
            { type: 'Liveness', httpGet: { path: '/login', port: 3000 }, periodSeconds: 30, failureThreshold: 3 }
            { type: 'Readiness', httpGet: { path: '/login', port: 3000 }, periodSeconds: 10, failureThreshold: 3 }
          ]
        }
      ]
      scale: { minReplicas: isProd ? 1 : 0, maxReplicas: 2 }
    }
  }
  dependsOn: [edgeAcrPull, api, managedCerts]
}

// ---------------------------------------------------------------- jobs (deploy/k8s/jobs.yaml)

var jobs = concat(
  [
    { name: 'yaqeen-migrate', command: ['node', 'dist/db/migrate.js'], cron: '' }
    { name: 'yaqeen-purge', command: ['node', 'dist/jobs/purge-deleted.js'], cron: '17 1 * * *' }
  ],
  enableCampaigns && redisOn ? [{ name: 'yaqeen-campaigns', command: ['node', 'dist/jobs/campaign-dispatcher.js'], cron: '*/10 * * * *' }] : []
)

resource apiJobs 'Microsoft.App/jobs@2024-03-01' = [
  for j in (deployApps ? jobs : []): {
    name: j.name
    location: appsLocation
    tags: tags
    identity: { type: 'UserAssigned', userAssignedIdentities: { '${identity.id}': {} } }
    properties: {
      environmentId: environmentId
      workloadProfileName: 'Consumption'
      configuration: {
        triggerType: empty(j.cron) ? 'Manual' : 'Schedule'
        manualTriggerConfig: empty(j.cron) ? { parallelism: 1, replicaCompletionCount: 1 } : null
        scheduleTriggerConfig: empty(j.cron) ? null : { cronExpression: j.cron, parallelism: 1, replicaCompletionCount: 1 }
        replicaTimeout: 540
        replicaRetryLimit: 1
        registries: registries
        secrets: apiSecrets
      }
      template: {
        containers: [{ name: 'job', image: apiImage, command: j.command, env: apiEnv, resources: { cpu: json('0.5'), memory: '1Gi' } }]
      }
    }
    dependsOn: [identityAcrPull, identityKvRead, kvSecrets, redis]
  }
]

// ---------------------------------------------------------------- outputs

output acrName string = acr.name
output acrLoginServer string = acr.properties.loginServer
output keyVaultName string = kv.name
output environmentName string = envResourceName
output environmentResourceGroup string = envRg
output edgeIdentityPrincipalId string = identityEdge.properties.principalId
output environmentDefaultDomain string = useShared ? caeShared!.properties.defaultDomain : cae!.properties.defaultDomain
output domainVerificationId string = useShared ? caeShared!.properties.customDomainConfiguration.customDomainVerificationId : cae!.properties.customDomainConfiguration.customDomainVerificationId
output postgresHost string = pg.properties.fullyQualifiedDomainName
output postgresServerName string = pg.name
output apiFqdn string = deployApps ? api!.properties.configuration.ingress.fqdn : ''
output adminFqdn string = deployApps ? admin!.properties.configuration.ingress.fqdn : ''
