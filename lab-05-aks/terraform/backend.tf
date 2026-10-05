terraform {
  backend "azurerm" {
    resource_group_name  = "rg-tfstate-uks"
    storage_account_name = "sttfstateb4jrjb"
    container_name       = "tfstate"
    key                  = "k8s-lab05-aks.tfstate"
  }
}