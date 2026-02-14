#!/bin/bash

NODE=$(hostname)
MARKER="/var/lib/ceph/reboot-pending"

### ------------------------------
### Common functions
### ------------------------------
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

    echo "Stopping local services..."
    stop_local_services
    check_services_stopped || { echo "ERROR: Services still running, aborting."; exit 1; }

    echo "Creating reboot marker..."
    mkdir -p "$(dirname $MARKER)"
    touch "$MARKER"

    echo "Pre-reboot tasks complete. Rebooting node now..."
    sleep 2
    reboot
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
if [[ -f "$MARKER" ]]; then
    post_reboot
else
    pre_reboot
fi
