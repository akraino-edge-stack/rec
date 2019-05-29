#!/bin/bash
#------------------------Pre-Modification----------------------------------------------------
mkdir RIC
cd RIC

#---------Clone the repo and perform the steps customize the deployment and values files------
git clone https://gerrit.o-ran-sc.org/r/it/dep
#run the localize script
cd /home/cloudadmin/RIC/dep
git checkout 189c974169043e89fa216df5ca638fb550e041e4
cat <<EOF >runric_env.sh

#!/bin/bash
################################################################################
#   Copyright (c) 2019 AT&T Intellectual Property.                             #
#   Copyright (c) 2019 Nokia.                                                  #
#                                                                              #
#   Licensed under the Apache License, Version 2.0 (the "License");            #
#   you may not use this file except in compliance with the License.           #
#   You may obtain a copy of the License at                                    #
#                                                                              #
#       http://www.apache.org/licenses/LICENSE-2.0                             #
#                                                                              #
#   Unless required by applicable law or agreed to in writing, software        #
#   distributed under the License is distributed on an "AS IS" BASIS,          #
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
#   See the License for the specific language governing permissions and        #
#   limitations under the License.                                             #
################################################################################


# customize the following repo info to local infrastructure
export __RICENV_SET__='1'
export __RUNRICENV_GERRIT_HOST__='gerrit-o-ran-sc.org'
export __RUNRICENV_GERRIT_IP__='34.215.66.175'_

export __RUNRICENV_DOCKER_HOST__='rancodev'
export __RUNRICENV_DOCKER_IP__='127.0.0.1'
export __RUNRICENV_DOCKER_PORT__='5555'
export __RUNRICENV_DOCKER_USER__='docker'
export __RUNRICENV_DOCKER_PASS__='docker'

export __RUNRICENV_HELMREPO_HOST__='chart-repo.kube-system.svc.rec.io'
export __RUNRICENV_HELMREPO_PORT__='8088/charts'
export __RUNRICENV_HELMREPO_IP__='127.0.0.1'
export __RUNRICENV_HELMREPO_USER__='helm'
export __RUNRICENV_HELMREPO_PASS__='helm'
EOF

source runric_env.sh
./localize.sh

cd generated/ricplt
deployment_files="$(find . -name deployment.yaml)"
for file in $deployment_files; do
  sed -i '/restartPolicy/d' "$file"
done

#------------------Delete the nodeport and privileges lines----------------------------------------
sed -ri 's/^(\s*)(type\s*:\s*NodePort\s*$)/\1type: ClusterIP/' appmgr/charts/appmgr/values.yaml
sed -ri 's/^(\s*)(type\s*:\s*NodePort\s*$)/\1type: ClusterIP/' e2mgr/charts/e2mgr/values.yaml
deployment_files="$(find . -name deployment.yaml)"
for file in $deployment_files; do
  sed -i '/privileged: true/d' "$file"
done

#------------------Edit the appmgr file including the path of the ca certificate-------------------
cp /etc/openssl/ca.pem preric/resources/helmrepo.crt
sed -i '/hostAliases:/,/system.svc.rec.io"/d' appmgr/charts/appmgr/templates/deployment.yaml

#-----------------Update tiller container name-----------------------------------------------------
sed -ri 's/^(\s*)("tiller-service"\s*:\s*"tiller-deploy"\s*$)/\1"tiller-service": "tiller"/' appmgr/charts/appmgr/values.yaml

#-----------------Change the repo location to rec.io----------------------------------------------
values_files="$(find . -name values.yaml)"
for file in $values_files; do
  sed -i 's,rancodev:5555,registry.kube-system.svc.rec.io:5555/ric,g' "$file"
done

#-----------------Change the repo location to rec.io---------------------------------------------
requirements_files="$(find . -name requirements.yaml)"
for file in $requirements_files; do
  sed -i 's,local,localric,g' "$file"
done

sed -i 's,rancodev:5555,rancodev,g' ./prepull.sh
sed -i 's/docker logout/#/' ./prepull.sh
sed -i 's/docker login/#/' ./prepull.sh

#!/bin/bash
#-----------------Installation--------------------------------------------------------------------
#--------------Reloading docker images-----------------------------------------------------------
echo "docker" | sh ./prepull.sh

#retag scripts
for i in  \
"xapp-manager:latest" \
"e2mgr:1.0.0" \
"e2:1.0.0"  \
"rtmgr:0.0.2"  \
"redis-standalone:latest"
do
echo $i
docker tag  rancodev/${i} registry.kube-system.svc.rec.io:5555/ric/${i}
docker push  registry.kube-system.svc.rec.io:5555/ric/${i}
done

#-------------create ricplatform namespace------------------------------------------------------
kubectl create namespace ricplatform

#create ricplatform danmnet
cat <<!   | kubectl apply -f -
apiVersion: danm.k8s.io/v1
kind: DanmNet
metadata:
  name: default
  namespace: ricplatform
spec:
  NetworkID: flannel
  NetworkType: flannel
!

#------------run ric_install script-----------------------------------------------------------
sed -i 's,http://127.0.0.1:8879,http://127.0.0.1:8879/charts,g' "ric_install.sh"
sed -i 's,local,localric,g' "ric_install.sh"

bash -x ./ric_install.sh
#-------------checking the output-------------------------------------------------------------
command="$(kubectl get po --no-headers --namespace=ricplatform --field-selector status.phase!=Running 2> /dev/null)"
if [[ $command != "" ]]; then
  exit 1
fi
