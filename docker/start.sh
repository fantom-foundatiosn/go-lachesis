#!/usr/bin/env bash
cd $(dirname $0)

set -e


. ./_params.sh

docker network inspect ${NETWORK} &>/dev/null || \
docker network create ${NETWORK}

. ./_sentry.sh


echo -e "\nStart $N nodes:\n"

for ((i=$N-1;i>=0;i-=1))
do
    NAME=node$i
    RPCP=$(($RPCP_BASE+$i))
    ACC=$(($i+1))

    docker inspect $name &>/dev/null || \
    docker run -d --rm \
	--net=${NETWORK} --name=${NAME} \
	--cpus=${LIMIT_CPU} --blkio-weight=${LIMIT_IO} \
	-p ${RPCP}:18545 \
	lachesis:${TAG} \
	--fakenet=${ACC}/$N \
	--port=5050 \
	--rpc --rpcaddr="0.0.0.0" --rpcport=18545 --rpccorsdomain="*" --rpcapi="eth,debug,admin,web3,net" \
	--ws --wsaddr="0.0.0.0" --wsport=18546 --wsorigins="*" --wsapi="eth,debug,admin,web3,personal,net" \
	--nousb --verbosity=5 --metrics \
	${SENTRY_DSN}
done

attach_and_exec() {
    local NAME=$1
    local CMD=$2

    for attempt in $(seq 20)
    do
        if (( attempt > 5 ));
        then
            echo "  - attempt ${attempt}: " >&2
        fi;

        res=$(docker exec -i ${NAME} /lachesis --exec "${CMD}" attach http://127.0.0.1:18545 2> /dev/null)
        if [ $? -eq 0 ]
        then
            echo $res
            return 0
        else
            sleep 2
        fi
    done
    echo "failed RPC connection to ${NAME}" >&2
    echo "try $0 again" >&2
    return 1
}

echo -e "\nConnect nodes to ring:\n"
for ((i=$N-1;i>=0;i-=1))
do
    j=$(((i+1) % N))

    echo " getting node$j address:"
    ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' node$j)
    enode=$(attach_and_exec node$j 'admin.nodeInfo.enode')
    enode=$(echo ${enode} | sed "s/127.0.0.1/${ip}/")
    echo "    p2p address = ${enode}"

    echo " connecting node$i to node$j:"
    res=$(attach_and_exec node$i "admin.addPeer(${enode})")
    echo "    result = ${res}"

done
