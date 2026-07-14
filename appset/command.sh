########################################### demo-08-ScalingDeploymentsUsingApplicationSets ##########################################################

##################################################
# 1. Prerequisites
# 2. Register the Dev Cluster with ArgoCD
# 3. Verify Both Clusters Are Known to ArgoCD
# 4. Create the ApplicationSet YAML
# 5. Apply the ApplicationSet
# 6. Watch ArgoCD Auto-Create the Applications
# 7. Verify Deployments on Both Clusters
# 8. Explore the ApplicationSet in the UI
# 9. Delete the ApplicationSet
##################################################

########################################
# 1. Prerequisites
########################################

# Don't record this, just check the prereqs

cd ~/Desktop/ArgoCD

# Make sure we are on the argocd management cluster
kubectl config use-context k3d-argocd-cluster
kubectl config current-context
# Should show: k3d-argocd-cluster

# Verify Argo CD is running
kubectl -n argocd get pods

# Keep port-forwarding running in a separate terminal tab:
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login to Argo CD CLI (open another terminal tab)
argocd login localhost:8080 --insecure

# Username: admin
# Password: <password>

# Check what apps currently exist
argocd app list

# There should be no apps running

########################################
# 2. Confirm that the Dev cluster is registered with ArgoCD
########################################

# Go to Settings -> Clusters

# Both clusters should be registered

in-cluster
dev-cluster

# This would have been added in the previous demos

########################################
# 3. Create and Register a new Canary cluster with ArgoCD
########################################

cat > canary-cluster-config.yaml <<EOF
apiVersion: k3d.io/v1alpha5
kind: Simple
metadata:
  name: loony-canary-cluster
servers: 1
agents: 2
options:
  k3s:
    extraArgs:
      - arg: --tls-san=$IP
        nodeFilters:
          - server:*
EOF

# Verify cluster setting
cat canary-cluster-config.yaml

# Create cluster
k3d cluster create loony-canary-cluster --config ./canary-cluster-config.yaml

# Verify cluster creation
kubectl cluster-info

# Show all contexts
kubectl config get-contexts -o name

# We should be working in the canary cluster
kubectl config current-context

# First fix the kubeconfig - k3d sets server IP to 0.0.0.0 by default.
# We need to replace it with the actual Mac IP so ArgoCD can reach the cluster.

# Take a look at the IP exposed by the canary cluster
nano ~/.kube/config 

# e.g server: https://0.0.0.0:55075

IP=`ifconfig en0 | grep inet | grep -v inet6 | awk '{print $2}'` && echo $IP

# Update the IP to use the external Mac IP address so the cluster is reachable from ArgoCD
kubectl config set-cluster k3d-loony-canary-cluster \
  --server=https://$IP:55075

# Verify address update
nano ~/.kube/config 


# Now add the canary cluster to ArgoCD
# --upsert is required if the cluster was previously registered
argocd cluster add k3d-loony-canary-cluster --name canary-cluster 

# This registers the dev cluster and creates a secret in the argocd namespace
# that the ApplicationSet controller uses to generate apps

########################################
# 3. Verify Both External Clusters Are Known to ArgoCD
########################################

argocd cluster list

# Should show 3 clusters including the original ArgoCD cluster

# Copy the SERVER URL for loony-dev-cluster and loony-canary-cluster

# - we need it in the next step

# Go to the ArgoCD UI and under Settings -> Clusters
# Show that we have 3 clusters

########################################
# 4. Verify that both clusters are added as destinations
########################################

# On the ArgoCD UI go to Settings -> Projects

# Select the loony-argocd project

# Add the canary cluster to the destination
# Namespace: default
# This project should now have two clusters as the destination


########################################
# 4. Create the ApplicationSet YAML
########################################

# We use the $IP variable from Section 2. 
# NOTE: Removed quotes from EOF so $IP is replaced with your real IP address.
# Make sure to change the ports for the clusters based on your ports

cat << EOF > nginx-appset.yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: nginx-appset
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - cluster: loony-canary-cluster
            url: https://$IP:55075
          - cluster: loony-dev-cluster
            url: https://$IP:63351
  template:
    metadata:
      name: 'nginx-{{cluster}}'
    spec:
      project: loony-argocd
      source:
        repoURL: https://github.com/Loony-User/loony-argocd-public-repo
        targetRevision: HEAD
        path: nginx_yaml_files
      destination:
        server: '{{url}}'
        namespace: default
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
EOF

# Inside nginx-appset.yaml (make sure these point to the right ports)
    - list:
        elements:
          - cluster: loony-canary-cluster
            url: https://$IP:55075
          - cluster: loony-dev-cluster
            url: https://$IP:63351

# Verify the file shows your ACTUAL IP (e.g., 10.216.x.x) and not just "$IP"
cat nginx-appset.yaml


########################################
# 5. Apply the ApplicationSet
########################################
# One kubectl apply → ArgoCD creates multiple Applications automatically

kubectl config use-context k3d-argocd-cluster

# NOTES:
# Kubernetes doesn't natively know what an "ApplicationSet" is (it only knows standard things like Pods and Services). A CRD (Custom Resource Definition) is like a "plugin" or a "schema definition." It tells Kubernetes: "Hey, if you see a resource of kind: ApplicationSet, here is what the structure should look like and how to handle it."

# Check if Kubernetes knows about the ApplicationSet CRDs
kubectl get crd applicationsets.argoproj.io

# Now apply your ApplicationSet
kubectl apply -f nginx-appset.yaml

# Verify the ApplicationSet was created
kubectl get applicationset -n argocd

# NAME          AGE
# nginx-appset  5s


########################################
# 6. Watch ArgoCD Auto-Create the Applications
########################################

# Immediately go to the UI -> Applications

# Show that there are two applications (one on each cluster)


# ArgoCD immediately generates one Application per list element

argocd app list

# You should see TWO applications created automatically:

# ONE ApplicationSet --> TWO Applications created automatically!

# Go to UI and show both apps: https://localhost:8080
# Both will show as Synced and Healthy

########################################
# 8. Explore the ApplicationSet in the UI
########################################

# Click on "nginx-loony-dev-cluster" application
# Click details
# Click on the nginx-loony-dev-cluster node
# Show it is deployed to the dev cluster
CLUSTER : dev-cluster (https://192.168.68.59:63351)

# Click on "nginx-loony-canary-cluster" application
# Click details
# Click on the nginx-loony-canary-cluster node
# Show it is deployed to the canary-cluster 
CLUSTER : canary-cluster (https://192.168.68.59:55075)
# Click back


########################################
# 7. Verify Deployments on Both Clusters
########################################
# Confirm nginx is actually running on both clusters

# Check nginx on the dev cluster
kubectl config use-context k3d-loony-dev-cluster
kubectl get all -n default

# Check nginx on the canary cluster
kubectl config use-context k3d-loony-canary-cluster
kubectl get all -n default


# Both clusters now have nginx deployed from the SAME single ApplicationSet!
# Adding more clusters = just adding more lines to the list

########################################
# 9. Delete the ApplicationSet
########################################
# Deleting the ApplicationSet also deletes all generated Applications

kubectl config use-context k3d-argocd-cluster

argocd appset delete nginx-appset -y

# Verify both applications are gone
argocd app list

# It will show apps terminating. Wait a moment and run again:
argocd app list

# Both nginx-lony-canary-cluster and nginx-loony-dev-cluster are now deleted

# Verify from the UI also
# Go to https://localhost:8080
# Applications page should be empty now



