#!/bin/bash

# Path fixes for unexpected environments
PATH=/bin:/usr/bin:/usr/local/bin:/usr/sbin:/opt/homebrew

## ###############
## Variables
## ###############
binfolder=/usr/local/bin
visudo_path=/private/etc/sudoers.d/battery
configfolder=$HOME/.battery
pidfile=$configfolder/battery.pid
logfile=$configfolder/battery.log
maintain_percentage_tracker_file=$configfolder/maintain.percentage
daemon_path=$HOME/Library/LaunchAgents/battery.plist

## ###############
## Housekeeping
## ###############

# Create config folder if needed
mkdir -p $configfolder

# create logfile if needed
touch $logfile

# Trim logfile if needed
logsize=$(stat -f%z "$logfile")
max_logsize_bytes=5000000
if (( logsize > max_logsize_bytes )); then
	tail -n 100 $logfile > $logfile
fi

# CLI help message
helpmessage="
Battery CLI utility v1.0.1

Usage:

  battery status
    output battery SMC status, % and time remaining

  battery logs LINES[integer, optional]
    output logs of the battery CLI and GUI
	eg: battery logs 100

  battery maintain LEVEL[1-100,stop]
    reboot-persistent battery level maintenance: turn off charging above, and on below a certain value
    eg: battery maintain 80
    eg: battery maintain stop

  battery charging SETTING[on/off]
    manually set the battery to (not) charge
    eg: battery charging on

  battery adapter SETTING[on/off]
    manually set the adapter to (not) charge even when plugged in
    eg: battery adapter off

  battery charge LEVEL[1-100]
    charge the battery to a certain percentage, and disable charging when that percentage is reached
    eg: battery charge 90

  battery discharge LEVEL[1-100]
    block power input from the adapter until battery falls to this level
    eg: battery discharge 90

  battery visudo
    instructions on how to make which utility exempt from sudo, highly recommended

  battery uninstall
    enable charging, remove the smc tool, and the battery script

"

# Visudo instructions
visudoconfig="
# Visudo settings for the battery utility installed from https://github.com/actuallymentor/battery
# intended to be placed in $visudo_path on a mac
Cmnd_Alias      BATTERYOFF = $binfolder/smc -k CH0B -w 02, $binfolder/smc -k CH0C -w 02, $binfolder/smc -k CH0B -r, $binfolder/smc -k CH0C -r
Cmnd_Alias      BATTERYON = $binfolder/smc -k CH0B -w 00, $binfolder/smc -k CH0C -w 00
Cmnd_Alias      DISCHARGEOFF = $binfolder/smc -k CH0I -w 00, $binfolder/smc -k CH0I -r
Cmnd_Alias      DISCHARGEON = $binfolder/smc -k CH0I -w 01, $binfolder/smc -k CHCR -r
ALL ALL = NOPASSWD: BATTERYOFF
ALL ALL = NOPASSWD: BATTERYON
ALL ALL = NOPASSWD: DISCHARGEOFF
ALL ALL = NOPASSWD: DISCHARGEON
"

# Get parameters
action=$1
setting=$2

## ###############
## Helpers
## ###############

function log() {

	echo -e "$(date +%D-%T) - $1"

}

#
# no AC present
function get_ac_online(){
	status=$( smc -k CHCE -r | awk '{print $6}' | sed s:\):: )
        if [[ "$status" == "00" ]]; then
                echo "offline"
        else
                echo "online"
        fi
}
# Re:discharging, we're using keys uncovered by @howie65: https://github.com/actuallymentor/battery/issues/20#issuecomment-1364540704
# CH0I seems to be the "disable the adapter" key
function enable_discharging() {
	log "🔽🪫 Enabling battery discharging"
	sudo smc -k CH0I -w 01
}

function disable_discharging() {
	log "🔼🪫 Disabling battery discharging"
	sudo smc -k CH0I -w 00
}

# Re:charging, Aldente uses CH0B https://github.com/davidwernhart/AlDente/blob/0abfeafbd2232d16116c0fe5a6fbd0acb6f9826b/AlDente/Helper.swift#L227
# but @joelucid uses CH0C https://github.com/davidwernhart/AlDente/issues/52#issuecomment-1019933570
# so I'm using both since with only CH0B I noticed sometimes during sleep it does trigger charging
function enable_charging() {
	log "🔌🔋 Enabling battery charging"
	sudo smc -k CH0B -w 00
	sudo smc -k CH0C -w 00
}

function disable_charging() {
	log "🔌🪫 Disabling battery charging"
	sudo smc -k CH0B -w 02
	sudo smc -k CH0C -w 02
}

function get_smc_charging_status() {
	hex_status=$( smc -k CH0B -r | awk '{print $4}' | sed s:\):: )
	if [[ "$hex_status" == "00" ]]; then
		echo "enabled"
	else
		echo "disabled"
	fi
}

function get_smc_discharging_status() {
	hex_status=$( smc -k CH0I -r | awk '{print $4}' | sed s:\):: )
	if [[ "$hex_status" == "0" ]]; then
		echo "not discharging"
	else
		echo "discharging"
	fi
}

function get_battery_percentage() {
	battery_percentage=`pmset -g batt | tail -n1 | awk '{print $3}' | sed s:\%\;::`
	echo "$battery_percentage"
}

function get_remaining_time() {
	time_remaining=`pmset -g batt | tail -n1 | awk '{print $5}'`
	echo "$time_remaining"
}

function get_maintain_percentage() {
	maintain_percentage=$( cat $maintain_percentage_tracker_file 2> /dev/null )
	echo "$maintain_percentage"
}



## ###############
## Actions
## ###############

# Help message
if [ -z "$action" ]; then
	echo -e "$helpmessage"
	exit 0
fi

# Visudo message
if [[ "$action" == "visudo" ]]; then
	echo -e "$visudoconfig" >> $configfolder/visudo.tmp
	sudo visudo -c -f $configfolder/visudo.tmp &> /dev/null
	if [ "$?" -eq "0" ]; then
		sudo cp $configfolder/visudo.tmp $visudo_path
		rm $configfolder/visudo.tmp
	fi
	sudo chmod 440 $visudo_path
	exit 0
fi

# Reinstall helper
if [[ "$action" == "--reinstall--" ]]; then
	echo "This will run curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash"
	if [[ ! "$setting" == "silent" ]]; then
		echo "Press any key to continue"
		read
	fi
	curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash
	exit 0
fi

# Update helper
if [[ "$action" == "--update--" ]]; then
	echo "This will run curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/update.sh | bash"
	if [[ ! "$setting" == "silent" ]]; then
		echo "Press any key to continue"
		read
	fi
	curl -sS https://raw.githubusercontent.com/actuallymentor/battery/main/update.sh | bash
	exit 0
fi

# Uninstall helper
if [[ "$action" == "uninstall" ]]; then

	if [[ ! "$setting" == "silent" ]]; then
		echo "This will enable charging, and remove the smc tool and battery script"
		echo "Press any key to continue"
		read
	fi
   	enable_charging
	disable_discharging
	battery remove_daemon
    sudo rm -v "$binfolder/smc" "$binfolder/battery"
	pkill -f "/usr/local/bin/battery.*"
    exit 0
fi

# Charging on/off controller
if [[ "$action" == "charging" ]]; then

	log "Setting $action to $setting"

	# Disable running daemon
	battery maintain stop

	# Set charging to on and off
	if [[ "$setting" == "on" ]]; then
		enable_charging
	elif [[ "$setting" == "off" ]]; then
		disable_charging
	fi

	exit 0

fi

# Discharge on/off controller
if [[ "$action" == "adapter" ]]; then

	log "Setting $action to $setting"

	# Disable running daemon
	battery maintain stop

	# Set charging to on and off
	if [[ "$setting" == "off" ]]; then
		enable_discharging
	elif [[ "$setting" == "on" ]]; then
		disable_discharging
	fi

	exit 0

fi

# Charging on/off controller
if [[ "$action" == "charge" ]]; then

	# Disable running daemon
	battery maintain stop

	# Disable charge blocker if enabled
	battery adapter on

	# Start charging
	battery_percentage=$( get_battery_percentage )
	log "Charging to $setting% from $battery_percentage%"
	enable_charging

	# Loop until battery percent is exceeded
	while [[ "$battery_percentage" -lt "$setting" ]]; do

		log "Battery at $battery_percentage%"
		caffeinate -i sleep 60
		battery_percentage=$( get_battery_percentage )

	done

	disable_charging
	log "Charging completed at $battery_percentage%"

	exit 0

fi

# Discharging on/off controller
if [[ "$action" == "discharge" ]]; then

	# Start charging
	battery_percentage=$( get_battery_percentage )
	log "Discharging to $setting% from $battery_percentage%"
	enable_discharging

	# Loop until battery percent is exceeded
	while [[ "$battery_percentage" -gt "$setting" ]]; do

		log "Battery at $battery_percentage% (target $setting%)"
		caffeinate -i sleep 60
		battery_percentage=$( get_battery_percentage )

	done

	disable_discharging
	log "Discharging completed at $battery_percentage%"

fi

# Maintain at level
if [[ "$action" == "maintain_synchronous" ]]; then

	TEMP_LIMIT=310

	# Recover old maintain status if old setting is found
	if [[ "$setting" == "recover" ]]; then

		# Before doing anything, log out environment details as a debugging trail
		log "Debug trail. User: $USER, config folder: $configfolder, logfile: $logfile, file called with 1: $1, 2: $2"

		maintain_percentage=$( cat $maintain_percentage_tracker_file 2> /dev/null )
		if [[ $maintain_percentage ]]; then
			log "Recovering maintenance percentage $maintain_percentage"
			setting=$( echo $maintain_percentage)
		else
			log "No setting to recover, exiting"
			exit 0
		fi
	fi


	is_discharging=$( get_smc_discharging_status )
	if [[  "$is_discharging" == "discharging" ]];then
		disable_discharging
	fi
	is_charging=$( get_smc_charging_status )
	if [[  "$is_charging" == "disabled" ]];then
		enable_charging
	fi

	# Before we start maintaining the battery level, first discharge to the target level
	# log "Triggering discharge to $setting before enabling charging limiter"
	# battery discharge "$setting"
	# log "Discharge pre battery-maintenance complete, continuing to battery maintenance loop"

	battery_percentage=$( get_battery_percentage )
	log "Charging to and maintaining at $setting% from $battery_percentage%"

	upper_limit=$setting
 	mid_limit=$(($setting-2))
	lower_limit=$(($setting-4))

	sail="off"
	# Loop until battery percent is exceeded
	while true; do

		# Keep track of status
		is_charging=$( get_smc_charging_status )
		is_discharging=$( get_smc_discharging_status )
		ac_on_line=$(get_ac_online)

		itemp=$(( $(ioreg -r -n AppleSmartBattery | grep '"Temperature"' | awk '{print $3}') - 2731))

		if [[ "$ac_on_line" == "offline" &&  "$is_discharging" == "not discharging"  ]];then
 
			log "Mode battery auto:: Chargeur: $ac_on_line"
			if [[  "$is_charging" == "disabled" ]];then
				enable_charging
			fi

		else

			if [[ "$battery_percentage" -gt "$upper_limit" ]]; then
				log "Charge above upper limit $upper_limit discharge force, battery temp $itemp/10 degC"
				if [[ "$is_discharging" == "not discharging" ]]; then
					enable_discharging
				fi

			elif [[ "$battery_percentage" -gt "$mid_limit" && "$battery_percentage" -le "$upper_limit" ]]; then

				log "Battery charge = $battery_percentage > $mid_limit et <= $upper_limit ==> inhibit charge, temp bat $itemp/10 degC"

				if [[ "$TEMP_LIMIT" -lt "$itemp" ]]; then
					if [[  "$is_discharging" == "not discharging" ]];then
						enable_discharging
					fi
				else
		    		## pas de decharge forcée

					if [[  "$is_discharging" == "discharging" ]];then
						disable_discharging
					fi

					# inhibit charging

					if [[  "$is_charging" == "enabled" ]];then
						disable_charging
					fi
				fi	
				sail="off"

			elif [[ "$sail" == "off" && "$battery_percentage" -ge "$lower_limit" && "$battery_percentage" -le "$mid_limit" ]];then

				log "Battery charge = $battery_percentage >= $lower_limit et <= $mid_limit ==> inhibit charge"

				if [[  "$is_discharging" == "discharging" ]];then
					disable_discharging
				fi
				if [[  "$is_charging" == "enabled" ]];then
					disable_charging
				fi
 			else

				if [[ "$TEMP_LIMIT" -le  "$itemp" ]]; then
				 
					log "Battery charge:  $battery_percentage < $lower_limit,"$TEMP_LIMIT" -ge  "$itemp" ==> inhibit charge"
					if [[  "$is_discharging" == "discharging" ]];then
						disable_discharging
					fi
					if [[  "$is_charging" == "enabled" ]];then
						disable_charging
					fi
				 	## otherwise auto (charge) and start (keep) sailing
				else
					if [[  "$is_discharging" == "discharging" ]];then
						disable_discharging
					fi
					if [[  "$is_charging" == "disabled" ]];then
						enable_charging
					fi
		    		if [[ "$sail"=="off" ]]; then
		    				sail="on"
					fi
					log "Battery charge:  $battery_percentage < $lower_limit ==> charge battery"
				fi

			fi
		fi

		sleep 60

		battery_percentage=$( get_battery_percentage )

	done

	exit 0
fi

# Asynchronous battery level maintenance
if [[ "$action" == "maintain" ]]; then

	# Kill old process silently
	if test -f "$pidfile"; then
		pid=$( cat "$pidfile" 2> /dev/null )
		kill $pid &> /dev/null
	fi

	if [[ "$setting" == "stop" ]]; then
		log "Killing running maintain daemons & enabling charging as default state"
		rm $pidfile 2> /dev/null
		rm $maintain_percentage_tracker_file 2> /dev/null
		battery remove_daemon
		enable_charging
		battery status
		exit 0
	fi

	# Start maintenance script
	log "Starting battery maintenance at $setting%"
	nohup battery maintain_synchronous $setting >> $logfile &

	# Store pid of maintenance process and setting
	echo $! > $pidfile
	pid=$( cat "$pidfile" 2> /dev/null )
	echo $setting > $maintain_percentage_tracker_file
	log "Maintaining battery at $setting%"

	# Enable the daemon that continues maintaining after reboot
	battery create_daemon

	exit 0

fi


# Status logger
if [[ "$action" == "status" ]]; then

	log "Battery at $( get_battery_percentage  )% ($( get_remaining_time ) remaining), smc charging $( get_smc_charging_status )"
	if test -f $pidfile; then
		maintain_percentage=$( cat $maintain_percentage_tracker_file 2> /dev/null )
		log "Your battery is currently being maintained at $maintain_percentage%"
	fi
	exit 0

fi

# Status logger in csv format
if [[ "$action" == "status_csv" ]]; then

	echo "$( get_battery_percentage  ),$( get_remaining_time ),$( get_smc_charging_status ),$( get_smc_discharging_status ),$( get_maintain_percentage )"

fi

# launchd daemon creator, inspiration: https://www.launchd.info/
if [[ "$action" == "create_daemon" ]]; then

	daemon_definition="
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
	<dict>
		<key>Label</key>
		<string>com.battery.app</string>
		<key>ProgramArguments</key>
		<array>
			<string>$binfolder/battery</string>
			<string>maintain_synchronous</string>
			<string>recover</string>
		</array>
		<key>StandardOutPath</key>
		<string>$logfile</string>
		<key>StandardErrorPath</key>
		<string>$logfile</string>
		<key>RunAtLoad</key>
		<true/>
	</dict>
</plist>
"

	mkdir -p "${daemon_path%/*}"
	echo "$daemon_definition" > "$daemon_path"

	exit 0

fi

# Remove daemon
if [[ "$action" == "remove_daemon" ]]; then

	rm $daemon_path 2> /dev/null
	exit 0

fi

# Display logs
if [[ "$action" == "logs" ]]; then

	amount="${2:-100}"

	echo -e "👾 Battery CLI logs:\n"
	tail -n $amount $logfile

	echo -e "\n🖥️  Battery GUI logs:\n"
	tail -n $amount "$configfolder/gui.log"

	echo -e "\n📁 Config folder details:\n"
	ls -lah $configfolder

	echo -e "\n⚙️  Battery data:\n"
	battery status
	battery | grep -E "v\d.*"

	exit 0

fi
