# Lab 01: A Local Cluster, Pods and the First Manifest

## Overview

| | |
|---|---|
| **Goal** | Set up a local Kubernetes cluster, understand what is running inside it, and run a pod both from the command line and from a YAML manifest |
| **Runs on** | Docker Desktop's built-in Kubernetes, on my laptop |
| **Cost** | Free |
| **Time** | About 45 minutes |

I started with a local cluster so I could learn the basics without paying for cloud resources, and rebuild everything quickly if I broke it. The main lesson of this lab turned out to be what a pod does **not** do on its own, which sets up Lab 02.

---

## Following along?

- I ran every command in **PowerShell**, mostly from the terminal inside **VS Code**.
- Each command is in its own box. Run **one line at a time**.
- Boxes marked **What I saw** show my output. They are not commands to run.
- YAML uses **spaces** for structure, never tabs. If VS Code underlines something in red, the indentation is usually off.

See the [main README prerequisites](../README.md#prerequisites) for what to install.

---

## How I did it

### Step 1: Turned on Kubernetes

In Docker Desktop I went to **Settings > Kubernetes**, ticked **Enable Kubernetes**, chose the **Kubeadm** cluster type and clicked **Apply & restart**. After a few minutes, Docker Desktop showed **Kubernetes running**.

I checked the command-line tool and the cluster:

```powershell
kubectl version --client
```

```powershell
kubectl get nodes
```

**What I saw:**

```
Client Version: v1.36.1

NAME             STATUS   ROLES           AGE     VERSION
docker-desktop   Ready    control-plane   2m12s   v1.36.1
```

One node, acting as the **control plane**. On a real cluster such as AKS, the control plane is separate from the worker nodes that run applications. Locally, one node does both.

### Step 2: Looked at what Kubernetes runs for itself

```powershell
kubectl get namespaces
```

```
NAME              STATUS   AGE
default           Active   3m7s
kube-node-lease   Active   3m7s
kube-public       Active   3m7s
kube-system       Active   3m7s
```

Namespaces keep resources separate, a bit like OUs in Active Directory. My own work goes in `default`.

```powershell
kubectl get pods -n kube-system
```

```
NAME                                     READY   STATUS    RESTARTS   AGE
coredns-589f44dc88-lwgtw                 1/1     Running   0          3m14s
coredns-589f44dc88-vp679                 1/1     Running   0          3m14s
etcd-docker-desktop                      1/1     Running   0          3m21s
kube-apiserver-docker-desktop            1/1     Running   0          3m21s
kube-controller-manager-docker-desktop   1/1     Running   0          3m21s
kube-proxy-v2jps                         1/1     Running   0          3m14s
kube-scheduler-docker-desktop            1/1     Running   0          3m21s
storage-provisioner                      1/1     Running   0          3m8s
vpnkit-controller                        1/1     Running   0          3m7s
```

Kubernetes runs its own components as containers:

| Component | What it does |
|---|---|
| `kube-apiserver` | The front door. Every `kubectl` command goes through it |
| `etcd` | The database holding the desired state of the cluster, similar in purpose to Terraform's state file |
| `kube-scheduler` | Decides which node each pod runs on |
| `kube-controller-manager` | Continuously compares desired state with reality and corrects any difference |
| `coredns` | Internal DNS. It runs two copies, so DNS survives one failing |
| `kube-proxy` | Sets up network rules on each node so traffic reaches the right pod |
| `storage-provisioner` | Creates storage when an application asks for it |
| `vpnkit-controller` | Specific to Docker Desktop: makes cluster apps reachable from Windows |

### Step 3: Ran a pod from the command line

```powershell
kubectl run hello --image=nginx:alpine
```

```powershell
kubectl get pods -o wide
```

**What I saw:**

```
NAME    READY   STATUS    RESTARTS   AGE   IP         NODE
hello   1/1     Running   0          33s   10.1.0.6   docker-desktop
```

The pod got its own IP address inside the cluster, and the scheduler placed it on `docker-desktop`.

```powershell
kubectl describe pod hello
```

The **Events** section at the bottom showed each step Kubernetes took:

```
Normal  Scheduled  default-scheduler  Successfully assigned default/hello to docker-desktop
Normal  Pulled     kubelet            Container image "nginx:alpine" already present on machine
Normal  Created    kubelet            Container created
Normal  Started    kubelet            Container started
```

The scheduler chose the node, and the **kubelet** (the agent on each node) ran the container. There was no `Pulling` step because I already had `nginx:alpine` from my Docker work. The description also showed `QoS Class: BestEffort`, meaning the pod had no CPU or memory limits at all.

| Docker | Kubernetes |
|---|---|
| `docker run` | `kubectl run` |
| `docker ps` | `kubectl get pods` |
| `docker inspect` | `kubectl describe pod` |
| `docker logs` | `kubectl logs` |
| `docker exec` | `kubectl exec` |

### Step 4: Deleted the pod

```powershell
kubectl delete pod hello
```

```powershell
kubectl get pods
```

```
No resources found in default namespace.
```

**The pod was gone and nothing replaced it.** A pod created on its own behaves like a container started with `docker run`: if it is deleted or its node fails, nothing brings it back. Self-healing comes from a **Deployment**, which is Lab 02. In practice, pods are almost never created directly.

### Step 5: Wrote the first manifest

Rather than creating things from the command line, I described the pod in a YAML file, `pod.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hello
  labels:
    app: hello
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
      ports:
        - containerPort: 80
      resources:
        requests:
          cpu: "50m"
          memory: "32Mi"
        limits:
          cpu: "200m"
          memory: "64Mi"
```

| Part | Meaning |
|---|---|
| `apiVersion` and `kind` | What type of object this is |
| `metadata` | Its name and labels. Labels are how Kubernetes finds groups of pods later |
| `spec` | The desired state |
| `image: nginx:1.27-alpine` | Pinned to a specific version rather than `latest` |
| `requests` | What the pod is guaranteed. The scheduler only places it on a node with this much free |
| `limits` | The most it may use. Exceeding the memory limit gets the container OOMKilled |

`50m` is 50 millicores (0.05 of a CPU) and `32Mi` is 32 mebibytes of memory.

```powershell
kubectl apply -f lab-01-first-cluster\pod.yaml
```

```powershell
kubectl get pods --show-labels
```

```
NAME    READY   STATUS              RESTARTS   AGE   LABELS
hello   0/1     ContainerCreating   0          11s   app=hello
```

It showed `ContainerCreating` briefly while it downloaded `nginx:1.27-alpine`, which I did not have yet, then moved to `Running`.

```powershell
kubectl describe pod hello | Select-String "QoS"
```

```
QoS Class:                   Burstable
```

With requests and limits set, the QoS class moved from `BestEffort` to `Burstable`, so Kubernetes gives the pod more protection when a node is under pressure.

### Step 6: Opened the pod in a browser

The pod's IP only exists inside the cluster, so I opened a temporary tunnel from my laptop:

```powershell
kubectl port-forward pod/hello 8080:80
```

This keeps running until stopped with **Ctrl + C**. My first attempt did not show nginx; see [Issues I hit](#issues-i-hit-and-how-i-fixed-them). Once that was fixed, http://localhost:8080 showed the **Welcome to nginx!** page served from the pod.

`port-forward` is only for testing. The permanent way to expose an app is a **Service**, covered in Lab 03.

### Step 7: Looked inside and cleaned up

```powershell
kubectl exec -it hello -- sh
```

Inside the pod, `hostname` returned `hello` and `/etc/os-release` showed Alpine Linux. I left with `exit`.

I removed the pod using the same file that created it:

```powershell
kubectl delete -f lab-01-first-cluster\pod.yaml
```

```
pod "hello" deleted from default namespace
```

---

## Issues I hit and how I fixed them

### The browser showed a different application

**Symptom.** After running `kubectl port-forward pod/hello 8080:80`, http://localhost:8080 showed my Docker **IT Asset Register** instead of the nginx welcome page.

**Investigation.** Three clues pointed away from Kubernetes: the page was the wrong application, the assets listed had been added days earlier during my Docker project, and the footer showed a Docker container ID rather than the pod name `hello`.

**Root cause.** My Docker Compose project uses `restart: unless-stopped`, so it started again automatically when Docker Desktop restarted to enable Kubernetes. It was already listening on `127.0.0.1:8080`, so my browser reached it instead of the tunnel.

**Fix.** I stopped the Compose project, which keeps the containers and data:

```powershell
cd C:\docker-lab\asset-register
```

```powershell
docker compose stop
```

Then I reopened the tunnel, and nginx loaded.

**Lesson.** Only one thing can listen on a port at a time. When something unexpected answers, check what else is using the port before assuming the new setup is broken. Stopping the Compose project also freed memory on my 8 GB laptop.

---

## Command reference

| Command | What it does |
|---|---|
| `kubectl get nodes` | Lists the nodes in the cluster |
| `kubectl get namespaces` | Lists namespaces |
| `kubectl get pods -n kube-system` | Lists pods in a specific namespace |
| `kubectl run <name> --image=<image>` | Runs a single pod from the command line |
| `kubectl get pods -o wide` | Lists pods with their IP and node |
| `kubectl get pods --show-labels` | Lists pods with their labels |
| `kubectl describe pod <name>` | Shows full details and events for a pod |
| `kubectl logs <name>` | Shows a container's output |
| `kubectl exec -it <name> -- sh` | Opens a shell inside a pod |
| `kubectl apply -f <file>` | Creates or updates resources to match a file |
| `kubectl delete -f <file>` | Removes the resources a file describes |
| `kubectl port-forward pod/<name> <local>:<pod>` | Opens a temporary tunnel to a pod for testing |

## What I learned

- A Kubernetes cluster is itself a set of containers: an API server, a state database, a scheduler and controllers that keep reality matching the desired state.
- A pod is the smallest unit Kubernetes runs, and on its own it is not self-healing. That is the job of a Deployment.
- Manifests are to Kubernetes what `.tf` files are to Terraform: the desired state written down, applied with one command and removed with the same file.
- Setting requests and limits matters. Without them a pod is `BestEffort` and can use as much as it likes.
- The **Events** section of `kubectl describe` is the first place to look when a pod does not behave as expected.
- When something unexpected answers on a port, check what else is already listening on it.

---

## References

Official documentation I used while building and testing this lab.

| What I did | Documentation |
|---|---|
| Enabled Kubernetes in Docker Desktop (Kubeadm) and checked the node | [Explore the Kubernetes view (Docker Desktop)](https://docs.docker.com/desktop/use-desktop/kubernetes/) |
| Ran my first Pod | [Pods](https://kubernetes.io/docs/concepts/workloads/pods/) |
| Wrote the Pod manifest (apiVersion, kind, metadata, spec) | [Objects In Kubernetes](https://kubernetes.io/docs/concepts/overview/working-with-objects/) |
| Set CPU and memory requests and limits | [Resource Management for Pods and Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) |
| Checked which QoS class the Pod was given | [Pod Quality of Service Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/) |
| Inspected and managed the Pod with kubectl | [kubectl Quick Reference](https://kubernetes.io/docs/reference/kubectl/quick-reference/) |