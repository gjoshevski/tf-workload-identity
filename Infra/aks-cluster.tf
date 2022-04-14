resource "random_pet" "prefix" {}

provider "azurerm" {
  features {}
}

data "azurerm_client_config" "current" {
}

resource "azurerm_resource_group" "default" {
  name     = "${random_pet.prefix.id}-rg"
  location = "West US 2"

  tags = {
    environment = "Demo"
  }
}

resource "azurerm_kubernetes_cluster" "default" {
  name                = "${random_pet.prefix.id}-aks"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  dns_prefix          = "${random_pet.prefix.id}-k8s"
  oidc_issuer_enabled = true

  default_node_pool {
    name            = "default"
    node_count      = 1
    vm_size         = "Standard_D2_v5"
    os_disk_size_gb = 30
  }

  identity {
    type = "SystemAssigned"
  }


  tags = {
    environment = "Demo"
  }
}

## Storage
/*
resource "azurerm_storage_account" "default" {
  name                     = replace("${random_pet.prefix.id}", "-", "")
  resource_group_name      = azurerm_resource_group.default.name
  location                 = azurerm_resource_group.default.location
  account_tier             = "Standard"
  account_replication_type = "GRS"

  tags = {
    environment = "staging"
  }
}

resource "azurerm_storage_container" "default" {
  name                  = "${random_pet.prefix.id}-blob"
  storage_account_name  = azurerm_storage_account.default.name
  container_access_type = "private"
}
*/


## AD App 

provider "azuread" {
}

data "azuread_client_config" "current" {}

resource "azuread_application" "directory_role_app" {
  display_name = "${random_pet.prefix.id}-app"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "directory_role_app" {
  application_id = azuread_application.directory_role_app.application_id
  use_existing   = true
}

resource "azuread_application_federated_identity_credential" "directory_role_app" {
  application_object_id = azuread_application.directory_role_app.object_id
  display_name          = "kubernetes-federated-credential"
  description           = "Kubernetes service account federated credential"
  audiences             = ["api://AzureADTokenExchange"]
  subject               = "system:serviceaccount:default:workload-identity-sa" #TODO: this is hardcoded
  issuer                = azurerm_kubernetes_cluster.default.oidc_issuer_url
}


## Deployment

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.default.kube_config.0.host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.cluster_ca_certificate)

  }
}

resource "helm_release" "azure-workload-identity" {
  name             = "azure-workload-identity"
  repository       = "https://azure.github.io/azure-workload-identity/charts"
  chart            = "workload-identity-webhook"
  namespace        = "azure-workload-identity-system"
  create_namespace = true

  set {
    name  = "azureTenantID"
    value = data.azuread_client_config.current.tenant_id
  }

}


provider "kubernetes" {
  host = azurerm_kubernetes_cluster.default.kube_config.0.host

  client_certificate     = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.cluster_ca_certificate)
}

resource "kubernetes_service_account_v1" "sa" {
  metadata {
    name      = "workload-identity-sa"
    namespace = "default"
    annotations = {
      "azure.workload.identity/client-id" : azuread_application.directory_role_app.application_id
    }
    labels = {
      "azure.workload.identity/use" = "true"
    }

  }
}

resource "kubernetes_deployment" "app" {
  depends_on = [
    null_resource.docker_push
  ]
  metadata {
    name = "app-example"
    labels = {
      test = "MyExampleApp"
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        test = "MyExampleApp"
      }
    }

    template {
      metadata {
        labels = {
          test = "MyExampleApp"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.sa.metadata[0].name
        container {
          image = "${azurerm_container_registry.acr.login_server}/app:latest"
          name  = "app"
          port {
            container_port = 3000
          }
          env {
            name  = "AZURE_SUBSCRIPTION_ID"
            value = data.azurerm_client_config.current.subscription_id
          }
          env {
            name  = "AZURE_SERVICE_PRINCIPAL_OBJECT_ID"
            value = azuread_service_principal.directory_role_app.object_id
          }
          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }

        }
      }
    }
  }
}


resource "kubernetes_service" "app" {
  metadata {
    name = "app-example"
  }

  spec {
    type = "LoadBalancer"
    selector = {
      test = "MyExampleApp"
    }
    session_affinity = "ClientIP"
    port {
      port        = 80
      target_port = 3000
    }
  }
}
