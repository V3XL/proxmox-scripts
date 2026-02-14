#!/bin/bash

NODE=$(hostname)
MARKER="/var/lib/ceph/reboot-pending"

### ------------------------------
### Common functions
### ------------------------------

mark_osds_out_for_node(){
    local NODE="$1"
    local OSDS
    OSDS=$(ceph osd tree -f json | jq -r --arg host "$NODE" '
      .nodes[] | select(.type=="host" and .name==$host) | .children[]
    ' | xargs)
    echo "OSDs on $NODE: $OSDS"
    for osd in $OSDS; do
        echo "Marking OSD $osd out"
        ceph osd out $osd
    done
}

check_osds_out() {
    local NODE="$1"
    local ALL_OUT=0
    local OSDS
    OSDS=$(ceph osd tree -f json | jq -r --arg host "$NODE" '
      .nodes[] | select(.type=="host" and .name==$host) | .children[]
    ' | xargs)
    for osd in $OSDS; do
        REWEIGHT=$(ceph osd tree -f json | jq -r --argjson id "$osd" '.nodes[] | select(.id==$id) | .reweight')
        if [[ "$REWEIGHT" != "0" ]]; then
            echo "OSD $osd is not fully out (reweight: $REWEIGHT)"
            ALL_OUT=1
        fi
    done
    ((ALL_OUT==0))
}

wait_for_osds_out() {
    local NODE="$1"
    local TIMEOUT="${2:-60}"
    local INTERVAL=5
    local elapsed=0
    while (( elapsed < TIMEOUT )); do
        if check_osds_out "$NODE"; then
            echo "All OSDs confirmed out for $NODE."
            return 0
        fi
        echo "Waiting for OSDs to be out..."
        sleep $INTERVAL
        (( elapsed += INTERVAL ))
    done
    echo "Timeout reached: some OSDs still not out!"
    return 1
}

stop_local_services(){
    systemctl stop pve-cluster
    systemctl stop ceph.target
    systemctl stop frr
}

check_services_stopped() {
    local services=("pve-cluster" "ceph.target" "frr")
    local running=0
    for svc in "${services[@]}"; do
        if systemctl is-active --quiet "$svc"; then
            echo "Service $svc is still running"
            running=1
        fi
    done
    return $running
}

has_guests() {
    local NODE="$1"
    local CT_COUNT VM_COUNT
    CT_COUNT=$(pvesh get /nodes/"$NODE"/lxc -o json | jq length)
    VM_COUNT=$(pvesh get /nodes/"$NODE"/qemu -o json | jq length)
    (( CT_COUNT > 0 || VM_COUNT > 0 ))
}

migrate_all_guests() {
    local NODE="$1"
    echo "Migrating guests from $NODE with dynamic load balancing..."
    # LXC containers
    pvesh get /nodes/$NODE/lxc -o json | jq -r '.[] | select(.mp0 == null) | .vmid' | while read CTID; do
        TARGET=$(pvesh get /nodes -o json | jq -r --arg node "$NODE" '.[] | select(.node != $node) | "\(.node) \(.maxmem - .mem)"' \
                 | sort -k2 -nr | tail -n1 | awk '{print $1}')
        [[ -z "$TARGET" ]] && echo "No target for CT $CTID" && continue
        echo "Migrating CT $CTID -> $TARGET"
        pct migrate "$CTID" "$TARGET" --online
    done
    # QEMU VMs
    pvesh get /nodes/$NODE/qemu -o json | jq -r '.[].vmid' | while read VMID; do
        TARGET=$(pvesh get /nodes -o json | jq -r --arg node "$NODE" '.[] | select(.node != $node) | "\(.node) \(.maxmem - .mem)"' \
                 | sort -k2 -nr | tail -n1 | awk '{print $1}')
        [[ -z "$TARGET" ]] && echo "No target for VM $VMID" && continue
        echo "Migrating VM $VMID -> $TARGET"
        qm migrate "$VMID" "$TARGET" --online
    done
}

### ------------------------------
### Pre-reboot tasks
### ------------------------------
pre_reboot() {
    echo "Starting safe reboot procedure for $NODE"

    echo "Enabling Ceph maintenance flags (noout + norebalance)..."
    ceph osd set noout
    ceph osd set norebalance

    if has_guests "$NODE"; then
        echo "Migrating all guests from $NODE..."
        migrate_all_guests "$NODE"
    else
        echo "No guests remaining on $NODE."
    fi

    echo "Marking OSDs as out for node $NODE..."
    mark_osds_out_for_node "$NODE"
    wait_for_osds_out "$NODE" || { echo "ERROR: OSDs not fully out, aborting."; exit 1; }

    echo "Stopping local services..."
    stop_local_services
    check_services_stopped || { echo "ERROR: Services still running, aborting."; exit 1; }

    echo "Creating reboot marker..."
    mkdir -p "$(dirname $MARKER)"
    touch "$MARKER"

    echo "Pre-reboot tasks complete. You may now reboot the node safely."
}

### ------------------------------
### Post-reboot tasks
### ------------------------------
post_reboot() {
    [[ -f "$MARKER" ]] || { echo "Reboot marker not found, skipping post-reboot tasks."; exit 0; }

    echo "Post-reboot: removing Ceph maintenance flags..."
    ceph osd unset noout
    ceph osd unset norebalance

    echo "Cleaning up reboot marker..."
    rm -f "$MARKER"

    echo "Post-reboot tasks complete."
}

### ------------------------------
### Main
### ------------------------------
case "$1" in
    --pre)
        pre_reboot
        ;;
    --post)
        post_reboot
        ;;
    *)
        echo "Usage: $0 --pre|--post"
        exit 1
        ;;
esac
