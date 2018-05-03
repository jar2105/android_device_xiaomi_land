#! /vendor/bin/sh

# Disable ALMK
echo 0 > /sys/module/lowmemorykiller/parameters/enable_adaptive_lmk

# Configure_zram_parameters
zram_enable=`getprop ro.config.zram`
if [ "$zram_enable" == "true" ]; then
    echo 536870912 > /sys/block/zram0/disksize
    mkswap /dev/block/zram0
    swapon /dev/block/zram0 -p 32758
fi

# Set GPU Initial frequency
echo 4 > /sys/class/kgsl/kgsl-3d0/default_pwrlevel

# Setup VM
echo 20 > /proc/sys/vm/dirty_ratio
echo 10 > /proc/sys/vm/vfs_cache_pressure
echo 7759 > /proc/sys/vm/min_free_kbytes
