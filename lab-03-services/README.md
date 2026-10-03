# Lab 03: Services

## Overview

| | |
|---|---|
| **Goal** | Give a set of pods one stable address, see traffic spread across them, reach the app from outside the cluster, and debug a broken Service |
| **Runs on** | Docker Desktop's built-in Kubernetes, on my laptop |
| **Cost** | Free |
| **Time** | About 45 minutes |

In Lab 02, every replacement pod came back with a new name and a new IP address. Nothing could rely on reaching a particular pod. A **Service** solves that: it gives a group of pods one stable name and IP, finds the pods by their labels, and spreads traffic across whichever ones are running.

```
           Service "whoami"  (stable name and IP)
                 │  finds pods labelled app: whoami
     ┌───────────┼───────────┐
    Pod         Pod         Pod      ← these come and go
```

For this lab I used `traefik/whoami`, a small test app that replies with the name and IP of the pod that handled the request, so I could see exactly where each request went.

---

## Following along?

- I ran every command in **PowerShell** from `C:\kubernetes-labs`, using the terminal inside **VS Code**.
- Commands in `sh` boxes are run **inside a pod**, after starting a shell with `kubectl run ... -- sh`.
- Each command is in its own box. Run **one line at a time**.
- Boxes marked **What I saw** show my output. They are not commands to run.
- Pod names and IP addresses will differ on your machine.

See the [main README prerequisites](../README.md#prerequisites), and Labs [01](../lab-01-first-cluster) and [02](../lab-02-deployments) for the basics.

---

## The manifests

### `deployment.yaml`

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: whoami
  labels:
    app: whoami
spec:
  replicas: 3
  selector:
    matchLabels:
      app: whoami
  template:
    metadata:
      labels:
        app: whoami
    spec:
      containers:
        - name: whoami
          image: traefik/whoami:v1.10.1
          ports:
            - containerPort: 80
          resources:
            requests:
              cpu: "20m"
              memory: "16Mi"
            limits:
              cpu: "100m"
              memory: "32Mi"
```

### `service.yaml` (internal)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: whoami
spec:
  type: ClusterIP
  selector:
    app: whoami
  ports:
    - port: 80
      targetPort: 80
```

### `service-external.yaml` (reachable from my laptop)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: whoami-external
spec:
  type: LoadBalancer
  selector:
    app: whoami
  ports:
    - port: 8081
      targetPort: 80
```

| Part | Meaning |
|---|---|
| `selector` | Which pods receive the traffic: any pod labelled `app: whoami`. This is the only link between a Service and its pods |
| `port` | The port the Service listens on |
| `targetPort` | The port on the pods that traffic is forwarded to |
| `type: ClusterIP` | Reachable only inside the cluster |
| `type: LoadBalancer` | Reachable from outside. Docker Desktop publishes it on `localhost`; on AKS it creates an Azure Load Balancer with a public IP |

| Service type | Reachable from | Typical use |
|---|---|---|
| ClusterIP | Inside the cluster only | Databases, internal APIs |
| NodePort | A port between 30000 and 32767 on every node | Testing, or behind another load balancer |
| LoadBalancer | An external address | Public-facing applications |

I used port 8081 for the external Service rather than 8080, after the port clash I hit in Lab 01.

---

## How I did it

### Step 1: Deployed three pods

```powershell
kubectl apply -f lab-03-services\deployment.yaml
```

```powershell
kubectl get pods -o wide
```

**What I saw:**

```
NAME                      READY   STATUS    IP
whoami-64fc6984fb-msnxm   1/1     Running   10.1.0.36
whoami-64fc6984fb-rpgwx   1/1     Running   10.1.0.35
whoami-64fc6984fb-xkhb2   1/1     Running   10.1.0.37
```

### Step 2: Created the internal Service

```powershell
kubectl apply -f lab-03-services\service.yaml
```

```powershell
kubectl get service whoami
```

```
NAME     TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)   AGE
whoami   ClusterIP   10.103.142.176   <none>        80/TCP    36s
```

I checked which pods the Service had found:

```powershell
kubectl get endpointslices -l kubernetes.io/service-name=whoami
```

```
NAME           ADDRESSTYPE   PORTS   ENDPOINTS                       AGE
whoami-vbbxp   IPv4          80      10.1.0.35,10.1.0.36,10.1.0.37   52s
```

The endpoints were exactly my three pod IPs, matched through the `app: whoami` label.

### Step 3: Called the Service by name from inside the cluster

A ClusterIP Service only works inside the cluster, so I started a temporary pod to test from:

```powershell
kubectl run tmp --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- sh
```

`--rm` deletes the pod as soon as I exit. Kubernetes also warned that everything typed in the session is recorded in the container's logs, so a shell like this is no place for passwords.

Inside the pod:

```sh
for i in 1 2 3 4 5 6; do curl -s http://whoami | grep Hostname; done
```

**What I saw:**

```
Hostname: whoami-64fc6984fb-rpgwx
Hostname: whoami-64fc6984fb-xkhb2
Hostname: whoami-64fc6984fb-xkhb2
Hostname: whoami-64fc6984fb-rpgwx
Hostname: whoami-64fc6984fb-msnxm
Hostname: whoami-64fc6984fb-rpgwx
```

All three pods handled requests. The split was uneven because, by default, `kube-proxy` chooses a pod at random for each new connection rather than strictly taking turns; it evens out over many requests.

The full DNS name also worked:

```sh
curl -s http://whoami.default.svc.cluster.local | grep -E "Hostname|IP: 10"
```

```
Hostname: whoami-64fc6984fb-msnxm
IP: 10.1.0.36
```

The pattern is `<service>.<namespace>.svc.cluster.local`, answered by CoreDNS. Within the same namespace, the short name `whoami` is enough, in the same way that `DB_HOST: db` works in Docker Compose.

---

## Tests I carried out

### Test 1: A replaced pod does not affect the Service address

I deleted one of the pods:

```powershell
kubectl delete pod whoami-64fc6984fb-msnxm
```

| | Before | After |
|---|---|---|
| Pod IPs | 10.1.0.35, .36, .37 | 10.1.0.35, .37, **.39** |
| Service endpoints | .35, .36, .37 | .35, .37, **.39** |
| Service IP | 10.103.142.176 | **10.103.142.176** |

The Deployment replaced the pod with a new one on a new IP, and the Service updated its endpoints automatically. The Service's own address never changed, so anything calling `http://whoami` was unaffected.

### Test 2: Reaching the app from outside the cluster

```powershell
kubectl apply -f lab-03-services\service-external.yaml
```

```powershell
kubectl get services
```

```
NAME              TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
kubernetes        ClusterIP      10.96.0.1        <none>        443/TCP          40h
whoami            ClusterIP      10.103.142.176   <none>        80/TCP           4m51s
whoami-external   LoadBalancer   10.109.135.176   localhost     8081:30990/TCP   16s
```

The LoadBalancer Service was published on `localhost:8081`, with NodePort 30990 created underneath it automatically. The `kubernetes` Service is the cluster's own API server and is always present.

From PowerShell on my laptop:

```powershell
1..6 | ForEach-Object { curl.exe -s http://localhost:8081 | Select-String "Hostname" }
```

```
Hostname: whoami-64fc6984fb-rpgwx
Hostname: whoami-64fc6984fb-76cqk
Hostname: whoami-64fc6984fb-xkhb2
Hostname: whoami-64fc6984fb-rpgwx
Hostname: whoami-64fc6984fb-76cqk
Hostname: whoami-64fc6984fb-xkhb2
```

In a browser, refreshing http://localhost:8081 tended to show the same pod each time. The browser reuses one connection (keep-alive), and a Service balances connections rather than individual requests. `curl.exe` opens a new connection each time, which is why its requests were spread out.

### Test 3: A Service that silently sends traffic nowhere

To simulate a common real-world fault, I introduced a typo in the external Service's selector, changing `app: whoami` to `app: who-am-i`, and applied it.

**Symptom.** `curl.exe -s -m 5 http://localhost:8081` returned nothing.

**Investigation.** I worked through it in order:

```powershell
kubectl get pods
```

All three pods were `Running`, so the application was fine.

```powershell
kubectl get service whoami-external
```

The Service existed and was still published on `localhost:8081`.

```powershell
kubectl get endpointslices -l kubernetes.io/service-name=whoami-external
```

```
NAME                    ADDRESSTYPE   PORTS     ENDPOINTS   AGE
whoami-external-k4gqp   IPv4          <unset>   <unset>     3m1s
```

The Service had **no endpoints**, so it had no pods to send traffic to.

```powershell
kubectl describe service whoami-external | Select-String "Selector"
```

```
Selector:                 app=who-am-i
```

```powershell
kubectl get pods --show-labels
```

```
NAME                      READY   STATUS    LABELS
whoami-64fc6984fb-76cqk   1/1     Running   app=whoami,pod-template-hash=64fc6984fb
whoami-64fc6984fb-rpgwx   1/1     Running   app=whoami,pod-template-hash=64fc6984fb
whoami-64fc6984fb-xkhb2   1/1     Running   app=whoami,pod-template-hash=64fc6984fb
```

**Root cause.** The Service was looking for `app=who-am-i`, but the pods were labelled `app=whoami`. Nothing matched.

**Fix.** I corrected the selector, saved and re-applied:

```powershell
kubectl get endpointslices -l kubernetes.io/service-name=whoami-external
```

```
NAME                    ADDRESSTYPE   PORTS   ENDPOINTS                       AGE
whoami-external-k4gqp   IPv4          80      10.1.0.35,10.1.0.37,10.1.0.39   4m1s
```

The endpoints were back and requests were answered again.

**Lesson.** When a Service does not respond, check its endpoints first. Empty endpoints almost always mean the selector does not match the pod labels, or the pods are not ready. The `pod-template-hash` label is added automatically by the Deployment to tell its ReplicaSets' pods apart.

---

## Clean up

`kubectl delete` accepts a folder, so I removed everything the lab created in one command:

```powershell
kubectl delete -f lab-03-services
```

```
deployment.apps "whoami" deleted from default namespace
service "whoami-external" deleted from default namespace
service "whoami" deleted from default namespace
```

---

## Command reference

| Command | What it does |
|---|---|
| `kubectl get services` | Lists Services, their types, IPs and ports |
| `kubectl get endpointslices -l kubernetes.io/service-name=<name>` | Shows which pod IPs a Service is sending traffic to |
| `kubectl describe service <name>` | Shows a Service's selector, ports and details |
| `kubectl get pods --show-labels` | Shows pod labels, to compare with a Service's selector |
| `kubectl run tmp --rm -it --image=<image> --restart=Never -- sh` | Starts a temporary pod with a shell, deleted on exit |
| `curl.exe -s -m 5 <url>` | Calls a URL from PowerShell, giving up after 5 seconds |
| `kubectl delete -f <folder>` | Deletes everything defined in a folder of manifests |

## What I learned

- Pods are temporary and their IPs change. A Service gives them one stable name and address.
- A Service finds its pods purely by label. There is no other link between them, so a one-character typo in a selector breaks it silently.
- Services keep their list of endpoints up to date automatically as pods are replaced.
- Inside the cluster, Services are reachable by name through CoreDNS: `<service>.<namespace>.svc.cluster.local`.
- ClusterIP is for internal traffic, and LoadBalancer is for traffic from outside. On AKS, a LoadBalancer Service creates a real Azure Load Balancer.
- A Service balances connections, not requests, which is why a browser can appear to stick to one pod.
- When a Service does not respond, check its endpoints before anything else.