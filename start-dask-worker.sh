#!/usr/bin/env bash

set -o errexit -o pipefail

source "${HOME}/.bash_profile"
source activate dask-distributed

if [ \( -n "${MARATHON_APP_ID-}" \) \
    -a \( -n "${MARATHON_APP_RESOURCE_CPUS-}" \) \
    -a \( -n "${MARATHON_APP_RESOURCE_MEM-}" \) \
    -a \( -n "${MARATHON_APP_RESOURCE_DISK-}" \) \
    -a \( -n "${MESOS_TASK_ID-}" \) -a \( -n "${HOST-}" \) \
    -a \( -n "${PORT_WORKER-}" \) -a \( -n "${PORT_NANNY-}" \) \
    -a \( -n "${PORT_BOKEH-}" \) ]
then
    VIP_PREFIX=$(python -c \
        "import os; print('.'.join(os.environ['MARATHON_APP_ID'].split('/')[1:-1]))" \
    )
    echo "DC/OS Named VIP Prefix: ${VIP_PREFIX}"

    NTHREADS=$(python -c \
        "import os,math; print(int(math.ceil(float(os.environ['MARATHON_APP_RESOURCE_CPUS']))))" \
    )
    echo "Dask Worker Threads: ${NTHREADS}"

    if [ -n "${DASK_FRAMEWORK_NAME-}" ]
    then
        FW_NAME="${DASK_FRAMEWORK_NAME}"
    else
        FW_NAME="marathon"
    fi

    # Set Dask Worker Memory Limit to be 80% of ${MARATHON_APP_RESOURCE_MEM}
    NBYTES=$(python -c \
        "import os; print(''.join([str(int(float(os.environ['MARATHON_APP_RESOURCE_MEM']) * 0.8)), 'e6']))" \
    )
    echo "Dask Worker Memory Limit in Bytes (1 Megabyte=1e6, 1 Gigabyte=1e9): ${NBYTES}"

    DASK_SCHEDULER="${VIP_PREFIX}.dask-scheduler.${FW_NAME}.l4lb.thisdcos.directory:8786"
    echo "Dask Scheduler: ${DASK_SCHEDULER}"

    # Set Dask Resources to enable sophisticated task placement on workers
    # https://distributed.readthedocs.io/en/latest/resources.html
    DASK_RESOURCES="CPUS=${MARATHON_APP_RESOURCE_CPUS}"
    DASK_RESOURCES="${DASK_RESOURCES} MEM=${MARATHON_APP_RESOURCE_MEM}"
    DASK_RESOURCES="${DASK_RESOURCES} DISK=${MARATHON_APP_RESOURCE_DISK}"
    if [ -n "${MARATHON_APP_RESOURCE_GPUS-}" ]
    then
        DASK_RESOURCES="${DASK_RESOURCES} GPUS=${MARATHON_APP_RESOURCE_GPUS}"
    fi
    echo "Dask Resources: ${DASK_RESOURCES}"

    dask-worker \
        --host "${HOST}" \
        --worker-port "${PORT_WORKER}" \
        --nanny-port "${PORT_NANNY}" \
        --bokeh-port "${PORT_BOKEH}" \
        --nthreads "${NTHREADS}" \
        --nprocs "1" \
        --name "${MESOS_TASK_ID}" \
        --memory-limit "${NBYTES}" \
        --local-directory "${MESOS_SANDBOX}" \
        --resources "${DASK_RESOURCES}" \
        --death-timeout "180" \
        "${DASK_SCHEDULER}"
        # --tls-ca-file "${MESOS_SANDBOX}/.ssl/ca-bundle.crt" \
        # --tls-cert "${MESOS_SANDBOX}/.ssl/scheduler.crt" \
        # --tls-key "${MESOS_SANDBOX}/.ssl/scheduler.key" \
        #
else
    dask-worker "$@"
fi
