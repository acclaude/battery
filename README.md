# Battery charge limiter for M1 Mac devices

This tool makes it possible to keep a chronically plugged in M1 Macbook at `80%` battery, since that will prolong the longevity of the battery. It is free and open-source and will remain that way.

> Want to know if this tool does anything or is just a placebo? Read [this excellent article](https://batteryuniversity.com/article/bu-808-how-to-prolong-lithium-based-batteries). TL;DR: keep your battery cool, keep it at 80% when plugged in, and discharge it as shallowly as feasible.

### Requirements

This is an app for M1 Macs. It will not work on non-M1 macs. Do you have an older Mac? Consider the free version of the [Al Dente](https://apphousekitchen.com/) software package. It is a good alternative and has a premium version with many more features.

### Installation

- Option 3: command-line only installation 

The first time you open the app, it will ask for your administator password so it can install the needed components. Please note that the app:

A COMPLETER

---


## 🖥 Command-line version


The CLI is used for managing the battery charging status for M1 Macs. Can be used to enable/disable the Macbook from charging the battery when plugged into power.

read setup.sh 

### Usage

Example usage:

```shell
# This will enable charging when your battery dips under 80, and disable it when it exceeds 80
battery maintain 80
```

For help, run `battery` without parameters:

```
Battery CLI utility v1.0.1

Usage:

  battery status
    output battery SMC status, % and time remaining

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

  battery update
    update the battery utility to the latest version

  battery reinstall
    reinstall the battery utility to the latest version (reruns the installation script)

  battery uninstall
    enable charging, remove the smc tool, and the battery script
```

## "It's not working"

```
sudo rm -rf ~/.battery
binfolder=/usr/local/bin
sudo rm -v "$binfolder/smc" "$binfolder/battery"
```

