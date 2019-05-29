#!/bin/bash
#------------------nanobot Pre-modification------------------------------------------------------------
cd RIC/test/ric_robot_suite
#------------------Build the robot suite---------------------------------------------------------------
docker build -t nanobot:latest -f docker/Dockerfile.nanobot .

#---------pre-create the log file directory- find the value from the values.yaml-----------------------
sudo chown -R cloudadmin /opt
mkdir -p /opt/ric/robot/log

kubectl create namespace rictest
kubectl create namespace ricxapp

#----------create ricplatform danmnet-------------------------------------------------------------------
cat <<!   | kubectl apply -f -
apiVersion: danm.k8s.io/v1
kind: DanmNet
metadata:
  name: default
  namespace: rictest
spec:
  NetworkID: flannel
  NetworkType: flannel
!

docker tag nanobot:latest registry.kube-system.svc.rec.io:5555/rictest/nanobot:latest
docker push registry.kube-system.svc.rec.io:5555/rictest/nanobot:latest
pwd
cd helm/nanobot
#--------edit the values.yaml file in the helm chart for nanobot to point to local registry--------------
values_files="$(find . -name values.yaml)"
for file in $values_files; do
  #sed -ri 's/^(\s*)(run\s*:\s*nanobot\s*$)/\1run: registry.kube-system.svc.rec.io:5555/rictest/nanobot/' "$file"
  sed -i 's/  domain: cluster.local/  domain: rec.io/' "$file"
  sed -i 's/     repository: .*$/     repository: registry.kube-system.svc.rec.io:5555/' "$file"
  sed -i 's/     name: test\/nanobot/     name: rictest\/nanobot/' "$file"
done


deployment_files="$(find . -name job-ric-robot-run.yaml)"
for file in $deployment_files; do
  sed -i "/restartPolicy: Never/s//&\\n\      nodeSelector:\n        nodename: caas_master1\n/" "$file"
done

#-------------------------add the helm chart to the repo-------------------------------------------------
cd ../
mkdir -p dist/packages
pkill helm
helm package -d dist/packages nanobot
helm serve --repo-path dist/packages &
sleep 2
helm repo update

#-----------------------install the helm chart-----------------------------------------------------------
helm install localric/nanobot --namespace rictest --name nanobot

nanobot_pod=$(kubectl get pods -n rictest -o go-template --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
sleep 10
kubectl logs $nanobot_pod -n rictest

#------------checking the status of the rictest pod--------------------------------------
command="$(kubectl get po --no-headers --namespace=rictest --field-selector status.phase=Completed 2> /dev/null)"
if [[ $command != "" ]]; then
  exit 1
fi
