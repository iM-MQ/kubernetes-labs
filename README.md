# Kubernetes Labs

Hands-on labs learning **Kubernetes**, starting with a local cluster and working up to **Azure Kubernetes Service (AKS)** built with Terraform. Each lab is written up with the commands I ran, what I saw and the problems I hit along the way.

These labs follow on from my [Docker Asset Register](https://github.com/iM-MQ/docker-asset-register) and [Terraform Azure Labs](https://github.com/iM-MQ/terraform-azure-labs). They end with the same Asset Register application running on Kubernetes: [Lab 04](lab-04-asset-register) runs it on my local cluster with its PostgreSQL database, and [Lab 05](lab-05-aks) runs it on AKS built with Terraform.

**Requires:** Docker Desktop with Kubernetes enabled. See [Prerequisites](#prerequisites).

| Lab | Topic | Status |
|---|---|---|
| [01](lab-01-first-cluster) | A local cluster, pods, `kubectl` and the first YAML manifest | Complete ✅ |
| [02](lab-02-deployments) | Deployments: self-healing, scaling, drift, rolling updates and rollback | Complete ✅ |
| [03](lab-03-services) | Services: stable addresses, load balancing, external access and selector debugging | Complete ✅ |
| [04](lab-04-asset-register) | The Asset Register and PostgreSQL on Kubernetes: Secret, ConfigMap, PVC, init container and probes | Complete ✅ |
| [05](lab-05-aks) | Capstone: AKS built with Terraform, running the Asset Register, with a real troubleshooting investigation | Complete ✅ |

## What is Kubernetes?

Docker runs containers on one machine. **Kubernetes** runs containers across many machines and looks after them: it restarts containers that fail, keeps the requested number of copies running, rolls out new versions without downtime and gives each application a stable network address.

You describe what you want in YAML files, such as "three copies of this image, listening on port 5000", and Kubernetes continuously works to make the cluster match. It is the same desired-state idea as Terraform or Intune compliance policies.

```
docker run          one container on one machine
Docker Compose      several containers on one machine
Kubernetes          many containers across many machines, managed for you
AKS                 Kubernetes run by Azure, with the control plane managed for you
```

### Key terms

| Term | Meaning |
|---|---|
| **Cluster** | A set of machines (nodes) run by Kubernetes |
| **Node** | One machine in the cluster. On AKS, each node is a VM |
| **Control plane** | The brain of the cluster: stores the desired state and decides where things run |
| **Pod** | The smallest thing Kubernetes runs, a wrapper around one or more containers |
| **Deployment** | Keeps a set number of identical pods running and replaces any that fail |
| **Service** | A stable address in front of a group of pods |
| **Namespace** | A way of separating resources inside one cluster, similar to OUs in Active Directory |
| **Manifest** | A YAML file describing what you want in the cluster |
| **`kubectl`** | The command-line tool for talking to a cluster |

### Why organisations use it

| Benefit | What it means in practice |
|---|---|
| **Self-healing** | Failed containers are restarted or replaced automatically |
| **Scaling** | More copies can be added or removed with one change, or automatically based on load |
| **Zero-downtime updates** | New versions are rolled out gradually, and can be rolled back |
| **Consistency** | The same manifests run on a laptop, on AKS, EKS or GKE, or on-premises |
| **Efficient use of hardware** | The scheduler packs workloads onto nodes based on what each one needs |

### When it is not the right fit

Kubernetes adds real complexity. For a single small application, a simpler platform such as Azure Container Apps or App Service is often the better choice, which is what I used for the Azure deployment in [Terraform Lab 05](https://github.com/iM-MQ/terraform-azure-labs/tree/main/lab-05-capstone). Kubernetes earns its place when there are many services, teams or environments to run consistently.

## Practices followed

- Every resource is defined in a YAML manifest and applied with `kubectl apply`, rather than created by hand. The one exception is Secrets, which I create with `kubectl create secret` so the values are never written to a file
- Container images are pinned to specific versions, never `latest`
- Every container has CPU and memory requests and limits
- Secret values and kubeconfig files are never committed (see `.gitignore`)
- Resources are removed with the same file that created them

## Prerequisites

| Requirement | Version used | Purpose | Install (Windows) |
|---|---|---|---|
| Docker Desktop | 29.x | Runs containers and the local Kubernetes cluster | [docker.com/products/docker-desktop](https://www.docker.com/products/docker-desktop/) |
| Kubernetes in Docker Desktop | v1.36 | The local single-node cluster | Docker Desktop **Settings > Kubernetes > Enable Kubernetes** |
| `kubectl` | v1.36 | The Kubernetes command-line tool | Installed with Docker Desktop |
| Git | 2.x | Clones this repository | `winget install --id Git.Git -e` |
| VS Code | Latest (optional) | Editing YAML files | `winget install --id Microsoft.VisualStudioCode -e` |

### Check everything is ready

```powershell
kubectl version --client
```

```powershell
kubectl get nodes
```

The second command should show one node, `docker-desktop`, with status `Ready`.

**Running on an 8 GB laptop.** The local cluster uses around 1 to 2 GB of RAM on top of Docker Desktop. I close other heavy applications first, and turn Kubernetes off in Docker Desktop settings when I am not using it.