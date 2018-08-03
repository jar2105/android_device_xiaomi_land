#! /vendor/bin/sh

target=`getprop ro.board.platform`

MemTotalStr=`cat /proc/meminfo | grep MemTotal`
MemTotal=${MemTotalStr:16:8}

ProductName=`getprop ro.product.name`
low_ram=`getprop ro.config.low_ram`
soc_id=`cat /sys/devices/soc0/soc_id`
hw_platform=`cat /sys/devices/soc0/hw_platform`

function configure_memory_parameters() {

    arch_type=`uname -m`

    # Read adj series and set adj threshold for PPR and ALMK.
    # This is required since adj values change from framework to framework.
    adj_series=`cat /sys/module/lowmemorykiller/parameters/adj`
    adj_1="${adj_series#*,}"
    set_almk_ppr_adj="${adj_1%%,*}"

    # PPR and ALMK should not act on HOME adj and below.
    # Normalized ADJ for HOME is 6. Hence multiply by 6
    # ADJ score represented as INT in LMK params, actual score can be in decimal
    # Hence add 6 considering a worst case of 0.9 conversion to INT (0.9*6).
    # For uLMK + Memcg, this will be set as 6 since adj is zero.
    set_almk_ppr_adj=$(((set_almk_ppr_adj * 6) + 6))
    echo $set_almk_ppr_adj > /sys/module/lowmemorykiller/parameters/adj_max_shift
    echo $set_almk_ppr_adj > /sys/module/process_reclaim/parameters/min_score_adj

    # Set other memory parameters
    echo 1 > /sys/module/process_reclaim/parameters/enable_process_reclaim
    echo 70 > /sys/module/process_reclaim/parameters/pressure_max
    echo 30 > /sys/module/process_reclaim/parameters/swap_opt_eff
    echo 10 > /sys/module/process_reclaim/parameters/pressure_min
    echo 1024 > /sys/module/process_reclaim/parameters/per_swap_size

    echo 0 > /sys/module/lowmemorykiller/parameters/enable_adaptive_lmk

    # Set ZCache parameters
    echo 3 > /sys/module/zcache/parameters/clear_percent
    echo 30 > /sys/module/zcache/parameters/max_pool_percent

    # Configure_zram_parameters
	zram_enable=`getprop ro.config.zram`
    if [ "$zram_enable" == "true" ]; then
	echo 536870912 > /sys/block/zram0/disksize
        mkswap /dev/block/zram0
        swapon /dev/block/zram0 -p 32758
    fi

    SWAP_ENABLE_THRESHOLD=1048576
    swap_enable=`getprop ro.vendor.qti.config.swap`

    # Enable swap initially only for 1 GB targets
    if [ "$MemTotal" -le "$SWAP_ENABLE_THRESHOLD" ] && [ "$swap_enable" == "true" ]; then
        # Static swiftness
        echo 1 > /proc/sys/vm/swap_ratio_enable
        echo 70 > /proc/sys/vm/swap_ratio

        # Swap disk - 200MB size
        if [ ! -f /data/system/swap/swapfile ]; then
            dd if=/dev/zero of=/data/system/swap/swapfile bs=1m count=200
        fi
        mkswap /data/system/swap/swapfile
        swapon /data/system/swap/swapfile -p 32758
    fi
}

# Start Host based Touch processing
case "$hw_platform" in
	"MTP" | "Surf" | "RCM" )
		bootmode=`getprop ro.bootmode`
		if [ "charger" != $bootmode ]; then
			start hbtp
		fi
	;;
esac

# Apply Scheduler and Governor settings for 8937

# HMP scheduler (big.Little cluster related) settings
echo 3 > /proc/sys/kernel/sched_window_stats_policy
echo 3 > /proc/sys/kernel/sched_ravg_hist_size
echo 20000000 > /proc/sys/kernel/sched_ravg_window
echo 9 > /proc/sys/kernel/sched_upmigrate_min_nice
echo 85 > /proc/sys/kernel/sched_spill_load
echo 85 > /proc/sys/kernel/sched_upmigrate
echo 55 > /proc/sys/kernel/sched_downmigrate
echo 1 > /proc/sys/kernel/sched_boost

# Disable sched_boost in 8937
echo 0 > /proc/sys/kernel/sched_boost

# HMP Task packing settings
echo 20 > /proc/sys/kernel/sched_small_task
echo 30 > /sys/devices/system/cpu/cpu0/sched_mostly_idle_load
echo 30 > /sys/devices/system/cpu/cpu1/sched_mostly_idle_load
echo 30 > /sys/devices/system/cpu/cpu2/sched_mostly_idle_load
echo 30 > /sys/devices/system/cpu/cpu3/sched_mostly_idle_load
echo 30 > /sys/devices/system/cpu/cpu4/sched_mostly_idle_load
echo 30 > /sys/devices/system/cpu/cpu5/sched_mostly_idle_load
echo 30 > /sys/devices/system/cpu/cpu6/sched_mostly_idle_load
echo 30 > /sys/devices/system/cpu/cpu7/sched_mostly_idle_load

echo 3 > /sys/devices/system/cpu/cpu0/sched_mostly_idle_nr_run
echo 3 > /sys/devices/system/cpu/cpu1/sched_mostly_idle_nr_run
echo 3 > /sys/devices/system/cpu/cpu2/sched_mostly_idle_nr_run
echo 3 > /sys/devices/system/cpu/cpu3/sched_mostly_idle_nr_run
echo 3 > /sys/devices/system/cpu/cpu4/sched_mostly_idle_nr_run
echo 3 > /sys/devices/system/cpu/cpu5/sched_mostly_idle_nr_run
echo 3 > /sys/devices/system/cpu/cpu6/sched_mostly_idle_nr_run
echo 3 > /sys/devices/system/cpu/cpu7/sched_mostly_idle_nr_run

for devfreq_gov in /sys/class/devfreq/qcom,mincpubw*/governor
do
	echo "cpufreq" > $devfreq_gov
done

for devfreq_gov in /sys/class/devfreq/soc:qcom,cpubw/governor
do
	echo "bw_hwmon" > $devfreq_gov
	for cpu_io_percent in /sys/class/devfreq/soc:qcom,cpubw/bw_hwmon/io_percent
	do
		echo 20 > $cpu_io_percent
	done
	for cpu_guard_band in /sys/class/devfreq/soc:qcom,cpubw/bw_hwmon/guard_band_mbps
	do
		echo 30 > $cpu_guard_band
	done
done

for gpu_bimc_io_percent in /sys/class/devfreq/soc:qcom,gpubw/bw_hwmon/io_percent
do
	echo 40 > $gpu_bimc_io_percent
done

# Disable thermal core_control to update interactive gov and core_ctl settings
echo 0 > /sys/module/msm_thermal/core_control/enabled

# Enable governor for perf cluster
echo 1 > /sys/devices/system/cpu/cpu0/online
echo "interactive" > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
echo 19000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/above_hispeed_delay
echo 85 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/go_hispeed_load
echo 20000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/timer_rate
echo 960000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/hispeed_freq
echo 0 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/io_is_busy
echo "45 960000:85" > /sys/devices/system/cpu/cpu0/cpufreq/interactive/target_loads
echo 40000 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/min_sample_time
echo 422400 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq
echo 1497600 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq

# Enable governor for power cluster
echo 1 > /sys/devices/system/cpu/cpu4/online
echo "interactive" > /sys/devices/system/cpu/cpu4/cpufreq/scaling_governor
echo 39000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/above_hispeed_delay
echo 85 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/go_hispeed_load
echo 40000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/timer_rate
echo 768000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/hispeed_freq
echo 0 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/io_is_busy
echo "45 768000:85" > /sys/devices/system/cpu/cpu4/cpufreq/interactive/target_loads
echo 40000 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/min_sample_time
echo 345600 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_min_freq
echo 1209600 > /sys/devices/system/cpu/cpu4/cpufreq/scaling_max_freq

# Set GPU Initial frequency
echo 4 > /sys/class/kgsl/kgsl-3d0/default_pwrlevel

# Setup VM
echo 20 > /proc/sys/vm/dirty_ratio
echo 10 > /proc/sys/vm/vfs_cache_pressure
echo 7759 > /proc/sys/vm/min_free_kbytes

# Set swappiness
echo 5 > /proc/sys/vm/swappiness

# Disable L2-GDHS low power modes
echo N > /sys/module/lpm_levels/system/pwr/pwr-l2-gdhs/idle_enabled
echo N > /sys/module/lpm_levels/system/pwr/pwr-l2-gdhs/suspend_enabled
echo N > /sys/module/lpm_levels/system/perf/perf-l2-gdhs/idle_enabled
echo N > /sys/module/lpm_levels/system/perf/perf-l2-gdhs/suspend_enabled

# Bring up all cores online
echo 1 > /sys/devices/system/cpu/cpu1/online
echo 1 > /sys/devices/system/cpu/cpu2/online
echo 1 > /sys/devices/system/cpu/cpu3/online
echo 1 > /sys/devices/system/cpu/cpu4/online
echo 1 > /sys/devices/system/cpu/cpu5/online
echo 1 > /sys/devices/system/cpu/cpu6/online
echo 1 > /sys/devices/system/cpu/cpu7/online

# Enable low power modes
echo 0 > /sys/module/lpm_levels/parameters/sleep_disabled

# Enable sched guided freq control
echo 1 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/use_sched_load
echo 1 > /sys/devices/system/cpu/cpu0/cpufreq/interactive/use_migration_notif
echo 1 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/use_sched_load
echo 1 > /sys/devices/system/cpu/cpu4/cpufreq/interactive/use_migration_notif
echo 50000 > /proc/sys/kernel/sched_freq_inc_notify
echo 50000 > /proc/sys/kernel/sched_freq_dec_notify

# Disable core control
echo 1 > /sys/devices/system/cpu/cpu0/core_ctl/disable
echo 1 > /sys/devices/system/cpu/cpu4/core_ctl/disable

# Enable dynamic clock gating
echo 1 > /sys/module/lpm_levels/lpm_workarounds/dynamic_clock_gating

# Set Memory parameters
configure_memory_parameters


emmc_boot=`getprop ro.boot.emmc`
case "$emmc_boot"
	in "true")
		chown -h system /sys/devices/platform/rs300000a7.65536/force_sync
		chown -h system /sys/devices/platform/rs300000a7.65536/sync_sts
		chown -h system /sys/devices/platform/rs300100a7.65536/force_sync
		chown -h system /sys/devices/platform/rs300100a7.65536/sync_sts
	;;
esac


# Change adj level and min_free_kbytes setting for lowmemory killer to kick in
echo 128 > /sys/block/mmcblk0/bdi/read_ahead_kb
echo 128 > /sys/block/mmcblk0/queue/read_ahead_kb
echo 128 > /sys/block/mmcblk1/bdi/read_ahead_kb
echo 128 > /sys/block/mmcblk1/queue/read_ahead_kb
echo 128 > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb
echo 128 > /sys/block/mmcblk0rpmb/queue/read_ahead_kb
setprop sys.post_boot.parsed 1

low_ram_enable=`getprop ro.config.low_ram`
if [ "$low_ram_enable" != "true" ]; then
	start gamed
fi

# Let kernel know our image version/variant/crm_version
if [ -f /sys/devices/soc0/select_image ]; then
	image_version="10:"
	image_version+=`getprop ro.build.id`
	image_version+=":"
	image_version+=`getprop ro.build.version.incremental`
	image_variant=`getprop ro.product.name`
	image_variant+="-"
	image_variant+=`getprop ro.build.type`
	oem_version=`getprop ro.build.version.codename`
	echo 10 > /sys/devices/soc0/select_image
	echo $image_version > /sys/devices/soc0/image_version
	echo $image_variant > /sys/devices/soc0/image_variant
	echo $oem_version > /sys/devices/soc0/image_crm_version
fi

# Parse misc partition path and set property
misc_link=$(ls -l /dev/block/bootdevice/by-name/misc)
real_path=${misc_link##*>}
setprop persist.vendor.mmi.misc_dev_path $real_path
