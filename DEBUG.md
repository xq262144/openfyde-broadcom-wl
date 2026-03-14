# DEBUG Notes

Date: 2026-03-13
Target: openFyde r126, kernel `5.4.275-22664-gca5ac6161115-dirty`
Device: Broadcom / Apple `14e4:43a0` (`BCM4360`)
Driver under test: Broadcom official `wl`

## Current known-good baseline

- `wl` loads on boot and binds to the PCI device.
- `lspci -nnk -d 14e4:43a0` shows `Kernel driver in use: wl`.
- `iw dev` shows `wlan0`.
- `rfkill` is not blocking Wi-Fi.

## What works

- Direct kernel-side scanning works:
  - `iw dev wlan0 scan` returns nearby APs reliably.
- A manual `iw scan` immediately makes the saved Shill Wi-Fi service visible again.
- With interface-level power management forced off:
  - `iwconfig wlan0 power off`
  - then a manual `iw scan`
  - the saved Shill Wi-Fi service stayed `Visible=true` and retained BSSID / strength for at least 30 seconds
- The saved network profile for the target SSID exists in Shill, and the profile contains a real passphrase entry.
  - This is not a "placeholder-only credentials" bug.

## What does not work

- Shill/WPA userspace scan path is unstable or broken:
  - `org.chromium.flimflam.Manager.RequestScan string:wifi` does not repopulate the visible Wi-Fi service list.
  - `wpa_cli -i wlan0 status`
  - `wpa_cli -i wlan0 scan`
  - `wpa_cli -i wlan0 scan_results`
  - `wpa_cli -i wlan0 list_networks`
  - All of the above timed out during debugging.
- After a direct `iw scan`, Shill marks the saved network as visible and strong again, but this does not stay stable.
- `dbus-send ... /service/0 org.chromium.flimflam.Service.Connect` returns success, and `LastConnected` updates, but:
  - `iw dev wlan0 link` still reports `Not connected`
  - `wlan0` stays `NO-CARRIER`
  - the service falls back to `idle`
  - visibility often drops back to `Visible=false`

## New high-signal findings from later tests

1. Power management is very likely involved in scan instability.
   - Baseline after boot:
     - `iwconfig wlan0` showed `Power Management:on`
   - After forcing `Power Management:off` and doing a manual scan:
     - the saved Wi-Fi service remained visible instead of immediately flipping back to `out-of-range`

2. Connection attempts are now strongly correlated with system instability.
   - I performed two controlled connect attempts after scan recovery.
   - In both cases:
     - `Service.Connect` returned success
     - the SSH session to the machine dropped
     - when I reconnected, system uptime showed the machine had rebooted unexpectedly
   - I did not issue `reboot` or `shutdown` in either case.

3. The machine also has unrelated but serious system-level instability indicators.
   - Repeated `EXT4-fs` corruption / block bitmap inconsistency errors on `sda3`
   - repeated `swap_management` crashes with ABRT
   - empty `/sys/fs/pstore` after reboot, so no direct panic artifact was available
   - This means not every crash can be attributed solely to `wl`

## Important observations

1. Driver and userspace are failing at different layers.
   - Kernel/driver side can scan.
   - Shill/WPA control path cannot reliably scan or maintain service visibility.

2. The symptom pattern points more to the `wl` + Shill/WPA integration path than to complete radio failure.
   - Strong evidence:
     - direct `iw scan` works
     - Shill scan requests do not
     - `wpa_cli` commands time out

3. Wireless Extensions are present.
   - `iwconfig wlan0` works.
   - This matters because Broadcom `wl` is historically more reliable with WEXT than with pure `nl80211` userspace.

4. Interface power management was enabled by default after boot.
   - `iwconfig wlan0` showed `Power Management:on`
   - I temporarily switched it to `off` once for testing.

## Actions performed during this session

These were the relevant state-changing actions. No intentional reboot command was executed.

1. Cleared old PCI driver confusion earlier and confirmed `wl` binding.
2. Triggered direct scans with:
   - `iw dev wlan0 scan`
3. Triggered Shill scans with:
   - `dbus-send --system --print-reply --dest=org.chromium.flimflam / org.chromium.flimflam.Manager.RequestScan string:wifi`
4. Attempted connection through Shill on the saved service:
   - `/service/0`
5. Restarted userspace components:
   - `restart wpasupplicant`
   - `restart shill`
6. Temporarily disabled interface-level Wi-Fi power management:
   - `iwconfig wlan0 power off`
7. Re-tested scan + connect after that.
8. Confirmed that with power management off, service visibility stayed stable for at least 30 seconds after manual scan.
9. Confirmed a second unexpected reboot occurred after another controlled connect attempt.

## Unexpected reboot

An unexpected reboot happened during debugging after the power-management-off test and a follow-up scan/connect retest.

What I did not do:

- I did not run `reboot`
- I did not run `shutdown`
- I did not intentionally unload critical system services beyond Wi-Fi userspace restarts

What I could confirm after reconnecting:

- The machine had rebooted recently; uptime was about 1 minute when I got back in.
- `wl` bound again automatically after boot.
- `wlan0` existed again after boot.
- `iwconfig wlan0` had reverted to `Power Management:on`.
- A second later connect test also led to another unexpected reboot.
- After the second reconnect, uptime again confirmed a fresh boot.

What I could not confirm:

- I did not find a clear kernel panic or oops trace in current logs.
- `/sys/fs/pstore` was empty after the reboot.
- So there is no direct crash artifact yet proving the exact reboot trigger.

## Most likely current hypothesis

Primary hypothesis:

- `wl` itself is sufficiently alive for direct scan, but the ChromeOS/openFyde Shill + `wpa_supplicant` control path is not stable with this driver on this platform.

Secondary contributing factor:

- Power-management behavior may be making the situation worse.

Additional system-level risk:

- The root/stateful storage shows ongoing filesystem corruption, which may independently destabilize the machine during aggressive network tests.

## Suggested next steps

1. Re-test with a controlled non-reboot flow:
   - disable Wi-Fi power management again
   - verify whether scan/connect improves before any other changes

2. Try a persistent `wl` power workaround:
   - add a modprobe option such as `nompc=1`
   - then reload `wl` in a controlled session
   - package an interface-level `iwconfig <iface> power off` hook so the setting survives module reloads / device reappearance

3. Avoid more repeated live connect attempts until system stability is addressed.
   - The last two connect attempts were both correlated with unexpected reboots.
   - Further connect tests should be treated as high risk on this machine.

4. If Shill/WPA still times out, test a WEXT-oriented workaround.
   - Because `iwconfig` works, WEXT is available.
   - A standalone WEXT-based connection path may work even if the default Shill/WPA path does not.

5. Investigate machine stability outside Wi-Fi.
   - The repeated `EXT4-fs` corruption on `sda3` is serious.
   - Running with a corrupted stateful partition can invalidate Wi-Fi conclusions.
   - This likely needs separate filesystem repair / integrity work before high-confidence driver validation.

6. Keep reboot out of the loop unless explicitly approved.
   - Future experiments should stay in:
     - userspace restart
     - interface power setting changes
     - controlled module reload

## New findings after deeper debugging

1. The saved Wi-Fi service path changed after reboot.
   - `/service/0` is now Ethernet.
   - The actual saved Wi-Fi network for the target SSID is `/service/2`.
   - Earlier tests against `/service/0` after reboot were therefore targeting the wrong service.

2. `wlan0` scanning and service visibility are usable when power management is forced off.
   - `iwconfig wlan0 power off`
   - `iw dev wlan0 scan`
   - After that, `/service/2` becomes:
     - `Visible=true`
     - `Connectable=true`
     - strong RSSI, valid BSSID

3. A controlled connect attempt against the correct service no longer rebooted the machine.
   - `dbus-send ... /service/2 org.chromium.flimflam.Service.Connect`
   - Machine stayed up.
   - `usb0` stayed up.
   - But Wi-Fi still failed after entering `association`.

4. The userspace failure mode is now very clear in logs.
   - `wpa_supplicant` repeatedly reports:
     - `CTRL-EVENT-SCAN-FAILED ret=-22`
   - `shill` drives the service into `Associating`, then times out:
     - `PendingTimeoutHandler`
     - `Failed to connect due to reason: unknown-failure`
   - After that, the saved service falls back to:
     - `Visible=false`
     - `Strength=0`
     - empty BSSID

5. Direct `wpa_cli` control is still broken.
   - Both `/run/wpa_supplicant` and `/var/run/wpa_supplicant` sockets time out.
   - `wpa_cli` exits with the same busy-loop warning seen earlier.

6. The likely root cause is a userspace interface mismatch, not a radio or PCI binding failure.
   - ChromiumOS `shill` creates Wi-Fi supplicant interfaces with `nl80211`.
   - Broadcom's hybrid `wl` driver is historically intended to work with `wext`.

7. A manual WEXT path was successfully validated on the target machine.
   - Steps:
     - temporarily disable Wi-Fi in shill
     - bring `wlan0` up
     - force `iwconfig wlan0 power off`
     - launch `wpa_supplicant -Dwext`
     - run `dhcpcd -4 -w wlan0`
   - Result:
     - `iw dev wlan0 link` showed:
       - connected to the target SSID
     - `wpa_supplicant` log showed:
       - `WPA: Key negotiation completed`
       - `CTRL-EVENT-CONNECTED`
     - `dhcpcd` successfully received a lease

8. Conclusion after the WEXT test.
   - `wl` can associate and obtain a DHCP lease on this machine.
   - The blocking issue is the stock openFyde / ChromiumOS `shill + wpa_supplicant(nl80211)` path, not the wl driver by itself.

## Additional kernel-side findings

1. The problem is not purely userspace.
   - Later `dmesg` inspection showed repeated kernel warnings in `cfg80211` while `wl` was active.

2. The first warning hits `__cfg80211_connect_result()`.
   - Timestamp:
     - `00:44:18`
   - Site:
     - `net/wireless/sme.c:768`
   - Context:
     - workqueue `cfg80211_event_work`
   - Meaning:
     - the `wl` cfg80211 glue is reporting a connect result in a state that `cfg80211` considers invalid.

3. The repeated warnings hit `cfg80211_roamed()`.
   - Timestamps:
     - repeated from `00:44:25` onward
   - Site:
     - `net/wireless/sme.c:985`
   - Call trace includes:
     - `wl_bss_roaming_done.isra.0 [wl]`
     - `wl_notify_roaming_status [wl]`
     - `wl_event_handler [wl]`
   - Meaning:
     - the `wl` driver is feeding invalid or inconsistent roam events into cfg80211.

4. This narrows the likely kernel issue.
   - The driver's cfg80211 glue layer in `wl_cfg80211_hybrid.c` is at least partially wrong for this `5.4` environment.
   - So even though WEXT can connect, the cfg80211 path is still internally unhealthy.

## DHCP / routing behavior seen during manual WEXT tests

1. Manual WEXT association succeeded.
   - `iw dev wlan0 link` showed `Connected`.
   - `wpa_supplicant` reported:
     - `WPA: Key negotiation completed`
     - `CTRL-EVENT-CONNECTED`

2. `dhcpcd` did receive and ACK a valid DHCP lease.
   - Example lease:
     - `192.0.2.10`
     - gateway `192.0.2.1`

3. But the address did not remain visible on `wlan0` when checked immediately afterward.
   - `ip addr show wlan0` still only showed IPv6 link-local.
   - A background `dhcpcd -4 -w wlan0` process remained running.

4. Because `usb0` also has network connectivity, a naive `ping -I wlan0 192.0.2.1` is not sufficient proof by itself unless `wlan0` really has its own IPv4 address and route.
   - Future validation should:
     - confirm `ip -4 addr show wlan0`
     - confirm route entries for `wlan0`
     - then use a source/interface-constrained ping

5. Next user-space validation should use `dhclient` instead of `dhcpcd`.
   - Rationale:
     - separate DHCP acquisition from the `dhcpcd` state machine and background behavior
     - reduce ambiguity when verifying whether the address was actually applied to `wlan0`

## Sensitive data note

- During debugging I confirmed that Shill has a real saved passphrase for the network profile.
- The actual credential is intentionally not copied into this document.

## Current validated WEXT state

1. The manual WEXT path now has a fully validated end-to-end success case.
   - `wlan0` came up with:
     - `192.0.2.10/24`
   - route table included:
     - `default via 192.0.2.1 metric 90`
     - `192.0.2.0/24 scope link src 192.0.2.10`
   - source-constrained gateway reachability worked:
     - `ping -I 192.0.2.10 192.0.2.1`

2. Once WLAN is really usable, the original jump-host SSH path may stop being the best control path.
   - In practice, debugging became easier by switching to:
     - `ssh root@<wlan_ip>`
   - Future sessions should be prepared for the original tunnel to become stale once `wlan0` owns a valid route.

## dhcpcd regression found during testing

1. `dhcpcd` is not a good fit for this workaround on this machine.
   - One leftover process:
     - `dhcpcd -4 -w wlan0`
   - became an orphan under PID 1 and spun at near 100% CPU.

2. This was user-space fallout from the manual test flow, not evidence that `wl` or stock `shill` itself was consuming CPU.
   - Killing the stray `dhcpcd` restored CPU to normal immediately.
   - The Wi-Fi connection itself remained up afterward.

3. Because of that, the helper pipeline was changed to use `dhclient` instead.
   - Future persistent or boot-time WEXT flows should avoid `dhcpcd` here.

## Practical severity assessment for current dmesg warnings

1. These warnings are real driver bugs, not cosmetic noise.
   - The repeated `cfg80211_roamed()` warnings are coming from the `wl` event thread itself.
   - The earlier `cfg80211_connect_result()` warning points to the same glue layer.

2. They are not an immediate blocker for the WEXT workaround.
   - The successful WEXT path proves the radio, WPA handshake, DHCP, and routed traffic can all work despite the warnings.

3. They are still serious for long-term health.
   - Repeated `WARNING` splats taint the kernel and indicate invalid cfg80211 state transitions.
   - They can plausibly contribute to instability if the system keeps exercising the cfg80211 path through roam/connect events.

4. Operational conclusion:
   - acceptable for a pragmatic “get Wi-Fi working” workaround
   - not acceptable as the final upstream-quality fix

## Boot-time autoconnect design direction

1. The stable path should not depend on `shill + nl80211`.
   - It should reuse the already-proven WEXT helper flow.

2. The intended persistent design is:
   - keep `wl nompc=1`
   - keep interface power management forced off
   - let `shill` start normally so D-Bus and stored credentials exist
   - then run a one-shot Upstart job that:
     - waits for `wlan0`
     - waits for `org.chromium.flimflam`
     - exits immediately if `wlan0` is already connected with IPv4
     - otherwise launches the WEXT helper

3. The Upstart job should be one-shot, not `respawn`.
   - A `respawn` design would reconnect-loop even after a successful association because the helper intentionally exits once the background `wpa_supplicant` and `dhclient` are established.

## Boot-time autoconnect installation status

1. The persistent helper set is now installed on the target machine.
   - `/usr/local/sbin/broadcom-wl-openfyde-post-up`
   - `/usr/local/sbin/broadcom-wl-openfyde-wext-connect`
   - `/usr/local/sbin/broadcom-wl-openfyde-wext-disconnect`
   - `/usr/local/sbin/broadcom-wl-openfyde-autoconnect`
   - `/usr/local/sbin/broadcom-wl-openfyde-dhclient-script`
   - `/usr/local/etc/broadcom-wl-openfyde.conf`
   - `/etc/init/broadcom-wl-openfyde-autoconnect.conf`
   - `/etc/udev/rules.d/99-broadcom-wl-openfyde.rules`

2. Installation was done with the root filesystem returned to read-only afterward.
   - Verified post-install mount state:
     - `/dev/loop0p3 on / type ext2 (ro,...)`

3. The installed config currently targets:
   - `SSID=YOUR_WIFI_SSID`
   - `IFACE=wlan0`

4. Non-disruptive validation succeeded.
   - `initctl list` shows:
     - `broadcom-wl-openfyde-autoconnect stop/waiting`
   - a manual `start broadcom-wl-openfyde-autoconnect` while Wi-Fi was already up did not tear down the current session
   - after the test, `wlan0` still held:
     - `192.0.2.10/24`
     - `default via 192.0.2.1 metric 90`

5. Full boot validation was completed later and succeeded.
   - after an approved reboot, the machine automatically reconnected to the target SSID
   - `broadcom-wl-openfyde-autoconnect.log` showed:
     - `autoconnect invoked`
     - `starting WEXT helper for the configured SSID`
     - `manual WEXT connection is up`
   - `wlan0` came back with:
     - `192.0.2.10/24`
     - `default via 192.0.2.1 metric 90`
   - `wpa_supplicant -Dwext` and `dhclient` process start times matched the autoconnect log timestamps

## Latest severity refinement for the cfg80211 warnings

1. The warnings are not currently flooding the live session anymore.
   - At `01:25 JST`, the newest matching messages were still the earlier ones:
     - latest `cfg80211_connect_result`: `00:44:18`
     - latest `cfg80211_roamed`: `00:46:27`

2. This is a useful distinction.
   - The cfg80211 path is clearly buggy.
   - But once the machine is running on the WEXT workaround, the system can stay online for an extended period without continuing to emit the same warnings.

3. Operationally this means:
   - current workaround is acceptable for practical use/testing
   - driver-side cfg80211 fixes are still required before calling the kernel-side integration healthy

## Why boot autoconnect still failed once installed

1. A later reboot showed the job did trigger, but it exited early.
   - uptime after reconnect was about 2 minutes
   - `dmesg` contained:
     - `init: broadcom-wl-openfyde-autoconnect main process (...) terminated with status 1`

2. This narrows the failure mode.
   - the Upstart job definition was loaded correctly
   - the trigger condition fired
   - the failure happened inside the helper, not in job registration

3. The strongest root-cause hypothesis is the boot-time execution environment.
   - manual `root` execution works
   - Upstart starts jobs with a much leaner environment than an interactive root shell
   - on this machine, important commands live in:
     - `/usr/sbin/iw`
     - `/usr/sbin/wpa_supplicant`
     - `/usr/local/sbin/dhclient`
     - `/usr/local/sbin/iwconfig`
   - the old helper version did not explicitly set `PATH`

4. A constrained-environment reproduction behaved consistently with that hypothesis.
   - running the autoconnect helper under a restricted `PATH` caused the active Wi-Fi session to drop
   - that is exactly the sort of failure expected if the helper can reach `dbus-send`/`ip`, but later fails on `wpa_supplicant` or `dhclient`

5. The helper set was then hardened locally.
   - explicit fixed `PATH` added to all relevant scripts
   - autoconnect changed to wait longer at boot
   - autoconnect changed to wait for saved Shill credentials before trying WEXT
   - autoconnect changed to log to:
     - `/mnt/stateful_partition/var/log/broadcom-wl-openfyde-autoconnect.log`
   - Upstart start condition moved later:
     - from `started shill`
     - to `(started shill and started ui)`

6. These hardened changes were later reinstalled remotely without rebooting.
   - helper/config files were copied back to the target machine
   - root filesystem was remounted `rw` only for installation, then `sync`ed and returned to `ro`
   - a manual `start broadcom-wl-openfyde-autoconnect` while Wi-Fi was already up produced the expected no-op log:
     - `interface already connected with IPv4, nothing to do`
   - a later approved reboot then confirmed the full boot path works end-to-end
