# Lab 02: Deployments, Self-Healing, Scaling and Rolling Updates

## Overview

| | |
|---|---|
| **Goal** | Run an app as a Deployment, then test self-healing, scaling, drift, a rolling update, a broken release and a rollback |
| **Runs on** | Docker Desktop's built-in Kubernetes, on my laptop |
| **Cost** | Free |
| **Time** | About 45 minutes |

In Lab 01, a pod I deleted stayed deleted. A **Deployment** fixes that: it keeps a set number of identical pods running, replaces any that fail, and changes versions gradually so the app stays up. In this lab I tested each of those behaviours, and also hit a real mistake during the rollback test, which turned out to be the most useful lesson.

```
Deployment  (what I write: "4 copies of nginx:1.28")
   └── ReplicaSet  (created for me: keeps the count right)
         ├── Pod
         ├── Pod
         ├── Pod
         └── Pod
```

---

## Following along?

- I ran every command in **PowerShell** from the `C:\kubernetes-labs` folder, using the terminal inside **VS Code**.
- Each command is in its own box. Run **one line at a time**.
- Boxes marked **What I saw** show my output. They are not commands to run.
- After editing a YAML file, **save it with Ctrl + S** and check the tab shows a cross, not a dot, before running `kubectl apply`. An unsaved edit caught me out in this lab.
- Pod names include random endings, so **yours will differ**. Use the names from your own `kubectl get pods` output.

See the [main README prerequisites](../README.md#prerequisites) for what to install, and [Lab 01](../lab-01-first-cluster) for the basics.

---

## The manifest

`deployment.yaml`, in its final state:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
  labels:
    app: web
spec:
  replicas: 4
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.28-alpine
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
| `kind: Deployment` | A Deployment rather than a single pod |
| `replicas` | How many copies to keep running. I started at 3 and changed it to 4 during the lab |
| `selector.matchLabels` | Tells the Deployment which pods belong to it: the ones labelled `app: web` |
| `template` | The blueprint for each pod, the same container spec as in Lab 01 |
| `template.metadata.labels` | The label put on each pod. It must match the selector, or the Deployment cannot find its own pods |

---

## How I did it

### Step 1: Created the Deployment

I started with `replicas: 3` and `image: nginx:1.27-alpine`.

```powershell
kubectl apply -f lab-02-deployments\deployment.yaml
```

```powershell
kubectl get deployment,replicaset,pods
```

**What I saw:**

```
NAME                  READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/web   3/3     3            3           7s

NAME                             DESIRED   CURRENT   READY   AGE
replicaset.apps/web-79b95cfcb8   3         3         3       7s

NAME                       READY   STATUS    RESTARTS   AGE
pod/web-79b95cfcb8-crh2m   1/1     Running   0          7s
pod/web-79b95cfcb8-kmpnt   1/1     Running   0          7s
pod/web-79b95cfcb8-x45vd   1/1     Running   0          7s
```

The names show how the layers connect. The ReplicaSet is named after the Deployment plus a hash of the pod template (`79b95cfcb8`), and each pod is named after the ReplicaSet plus a random ending. I only created the Deployment; Kubernetes created the rest.

---

## Tests I carried out

### Test 1: Self-healing

I deleted one of the pods:

```powershell
kubectl delete pod web-79b95cfcb8-crh2m
```

```powershell
kubectl get pods
```

**What I saw:**

```
NAME                   READY   STATUS    RESTARTS   AGE
web-79b95cfcb8-klp94   1/1     Running   0          7s
web-79b95cfcb8-kmpnt   1/1     Running   0          76s
web-79b95cfcb8-x45vd   1/1     Running   0          76s
```

A replacement, `klp94`, appeared within seconds, and the other two were untouched. The ReplicaSet's events confirmed it:

```powershell
kubectl describe replicaset web-79b95cfcb8 | Select-String "SuccessfulCreate"
```

```
Normal  SuccessfulCreate  91s   replicaset-controller  Created pod: web-79b95cfcb8-kmpnt
Normal  SuccessfulCreate  91s   replicaset-controller  Created pod: web-79b95cfcb8-x45vd
Normal  SuccessfulCreate  91s   replicaset-controller  Created pod: web-79b95cfcb8-crh2m
Normal  SuccessfulCreate  22s   replicaset-controller  Created pod: web-79b95cfcb8-klp94
```

Three pods created at the start, then a fourth after the deletion. This is exactly what did not happen with the standalone pod in Lab 01.

### Test 2: Scaling, and drift

First I changed `replicas: 3` to `replicas: 4` in the file and applied it. The Deployment went to `4/4`, and the change was recorded in the file.

Then I scaled from the command line, without changing the file:

```powershell
kubectl scale deployment web --replicas=6
```

Six pods were running. I then re-applied the file, which still said 4:

```powershell
kubectl apply -f lab-02-deployments\deployment.yaml
```

**What I saw:**

```
NAME                   READY   STATUS    RESTARTS   AGE
web-79b95cfcb8-f2cd9   1/1     Running   0          87s
web-79b95cfcb8-klp94   1/1     Running   0          3m27s
web-79b95cfcb8-kmpnt   1/1     Running   0          4m36s
web-79b95cfcb8-x45vd   1/1     Running   0          4m36s
```

The manual change was undone, and it was the two newest pods that were removed, while the long-running ones were kept. `kubectl scale` is useful in an emergency, but unless the file is updated too, the next `apply` reverses it. It is the same drift problem I tested in Terraform: the file is the source of truth.

### Test 3: A rolling update

I changed the image from `nginx:1.27-alpine` to `nginx:1.28-alpine` and applied the file, then watched the rollout:

```powershell
kubectl rollout status deployment web
```

**What I saw** (shortened):

```
Waiting for deployment "web" rollout to finish: 2 out of 4 new replicas have been updated...
Waiting for deployment "web" rollout to finish: 3 out of 4 new replicas have been updated...
Waiting for deployment "web" rollout to finish: 1 old replicas are pending termination...
Waiting for deployment "web" rollout to finish: 3 of 4 updated replicas are available...
deployment "web" successfully rolled out
```

```powershell
kubectl get replicasets
```

```
NAME             DESIRED   CURRENT   READY   AGE
web-75fcfbf44f   4         4         4       25s
web-79b95cfcb8   0         0         0       6m17s
```

The Deployment created a new ReplicaSet for the new version and moved the pods across gradually: start new pods, wait for them to be ready, then remove old ones. The old ReplicaSet was kept at 0 so the change could be rolled back.

```powershell
kubectl rollout history deployment web
```

```
REVISION  CHANGE-CAUSE
1         <none>
2         <none>
```

`CHANGE-CAUSE` was empty because I had not added a note to each change. In a team, an annotation such as `kubernetes.io/change-cause` would record why each revision was made.

### Test 4: A broken release and a rollback

I changed the image to a version that does not exist, `nginx:9.99-doesnotexist`, and applied it.

```powershell
kubectl rollout status deployment web --timeout=30s
```

```
Waiting for deployment "web" rollout to finish: 2 out of 4 new replicas have been updated...
error: timed out waiting for the condition
```

```powershell
kubectl get pods
```

**What I saw:**

```
NAME                   READY   STATUS             RESTARTS   AGE
web-57d6f997c9-4n6xg   0/1     ImagePullBackOff   0          42s
web-57d6f997c9-88b5p   0/1     ErrImagePull       0          42s
web-75fcfbf44f-hgwvq   1/1     Running            0          2m31s
web-75fcfbf44f-qd7cs   1/1     Running            0          2m31s
web-75fcfbf44f-tcdpw   1/1     Running            0          2m18s
```

The two new pods could not download the image, but three pods on the previous version kept running. Kubernetes only removes old pods once new ones are healthy, so a broken release stalled instead of taking the app down.

I rolled back:

```powershell
kubectl rollout undo deployment web
```

```
deployment.apps/web rolled back
```

Four healthy 1.28 pods were running again. See the next section for what went wrong straight afterwards.

---

## Issues I hit and how I fixed them

### The broken release came back after the rollback

**Symptom.** After the rollback had worked, I ran `kubectl apply` on the file and the broken pods returned:

```powershell
kubectl get deployment web -o jsonpath="{.spec.template.spec.containers[0].image}"
```

```
nginx:9.99-doesnotexist
```

```
web-57d6f997c9-46crl   0/1     ImagePullBackOff   0          2m52s
web-57d6f997c9-ds629   0/1     ImagePullBackOff   0          2m52s
```

**Root cause.** `rollout undo` changes the cluster but not my file. My file still said `9.99-doesnotexist`, because I had not saved the edit back to `1.28-alpine`, so applying it redeployed the broken version. Kubernetes had warned me about this during the rollback:

```
Warning: resource deployments/web was previously managed with 'kubectl apply'. Rolling back will not
update the kubectl.kubernetes.io/last-applied-configuration annotation, which may cause unexpected
behavior on future 'kubectl apply' operations.
```

**Fix.** I checked the file on disk rather than assuming:

```powershell
Select-String -Path lab-02-deployments\deployment.yaml -Pattern "image:"
```

Once it showed `nginx:1.28-alpine`, I applied it and confirmed the result:

```powershell
kubectl apply -f lab-02-deployments\deployment.yaml
```

```powershell
kubectl get pods
```

```
web-75fcfbf44f-49x25   1/1     Running   0          54s
web-75fcfbf44f-hgwvq   1/1     Running   0          7m31s
web-75fcfbf44f-qd7cs   1/1     Running   0          7m31s
web-75fcfbf44f-tcdpw   1/1     Running   0          7m18s
```

A final `apply` returned `deployment.apps/web unchanged`, confirming the file and the cluster matched.

**Lesson.** `rollout undo` is the quick fix during an incident, but the real fix is correcting the file. Otherwise the next person to run `apply` brings the problem straight back. The rolling update protected the app both times: three healthy pods kept serving throughout.

---

## Clean up

```powershell
kubectl delete -f lab-02-deployments\deployment.yaml
```

Deleting the Deployment removed both ReplicaSets and all the pods. The pods showed `Completed` for a moment, meaning nginx had exited cleanly on the stop signal, before disappearing.

---

## Command reference

| Command | What it does |
|---|---|
| `kubectl get deployment,replicaset,pods` | Shows all three layers at once |
| `kubectl delete pod <name>` | Deletes one pod (the Deployment replaces it) |
| `kubectl scale deployment <name> --replicas=<n>` | Changes the number of pods without editing the file |
| `kubectl rollout status deployment <name>` | Follows a rollout until it finishes |
| `kubectl rollout status deployment <name> --timeout=30s` | Gives up waiting after 30 seconds |
| `kubectl rollout history deployment <name>` | Lists the revisions |
| `kubectl rollout undo deployment <name>` | Rolls back to the previous revision |
| `kubectl get deployment <name> -o jsonpath="{...}"` | Shows a single value, such as the current image |
| `kubectl describe replicaset <name>` | Shows a ReplicaSet's details and events |

## What I learned

- A Deployment manages a ReplicaSet, which manages the pods. I only work with the Deployment, and the layers below are created, replaced and deleted for me.
- Self-healing comes from the ReplicaSet constantly comparing how many pods it wants with how many exist.
- Changes made from the command line are drift. The next `apply` of the file undoes them, so changes belong in the file.
- Rolling updates replace pods gradually and only continue when new pods are healthy, so a broken release stalls rather than causing an outage.
- `rollout undo` fixes the cluster, not the file. Correcting the file is part of the fix, not an afterthought.
- When a change does not behave as expected, check the file on disk rather than what I think I saved.