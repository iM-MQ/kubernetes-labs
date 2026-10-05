variable "location" {
  description = "Azure region for the cluster. Sweden Central, because the free trial has no general-purpose VM sizes in either UK region"
  type        = string
  default     = "swedencentral"
}

variable "prefix" {
  description = "Short name used to build resource names"
  type        = string
  default     = "k8slab05"

  validation {
    condition     = can(regex("^[a-z0-9]{3,12}$", var.prefix))
    error_message = "The prefix must be 3 to 12 lowercase letters or numbers."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version, checked with az aks get-versions"
  type        = string
  default     = "1.36.4"
}

variable "node_count" {
  description = "Number of nodes in the system node pool"
  type        = number
  default     = 1

  validation {
    condition     = var.node_count == 1
    error_message = "This subscription has 4 vCPUs. One 2-vCPU node plus one surge node during upgrades uses all 4, so the node count must be 1."
  }
}

variable "node_size" {
  description = "VM size for the nodes"
  type        = string
  default     = "Standard_D2s_v5"
}

variable "tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default = {
    project    = "kubernetes-labs"
    lab        = "05"
    managed_by = "terraform"
  }
}