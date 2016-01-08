# vROps Cluster Repair
A script that helps return the vRealize Operations cluster to a healthy state.

## Things it does:

- Cleanly shuts down all cluster services, which is good if the Admin UI is unresponsive.
- Backs up and removes malformed upgrade state files. You don't need them, and new updates may fail to parse them properly when they run. http://kb.vmware.com/kb/2120616
- Backs up and removes previous update, patch, and Management Pack files -- which can cause issues with future upgrades and cluster expansions if they remain.
- Backs up and removes large database blobs that may be lingering from a previous data migration, which can break future updates. http://kb.vmware.com/kb/2132479
- Backs up and alters the cluster state files to remove malformed data and set the cluster to a clean offline state. 
- Helps you check for time drift between the nodes, which is bad.
- Helps you check for latency issues between the nodes.
- Optionally backs up and clears out the alarms/alerts DB. Useful if a message is stuck in there.
- Optionally backs up and clears out the activities queue, which may be necessary if the script does not fix everything on the first go.
- Optionally disables IPv6 on your nodes, which is a good idea if you do not use IPv6 in your environment. 

## Things it does not do:

- Check for free disk space (planned for future release)
- Tell you if you are undersized (Planned for future release)
- Fix database corruption (may happen in future release)
- Identify miscellaneous configuration issues (may happen in future release)
- Make breakfast (I mean, I suppose it *could*... but you really shouldn't put food on your CPU heatsink)

## Instructions for use:

- Enable SSH on all your nodes.
  - Open a VM console session to the node.
  - Press ALT+F1 to get to a login prompt.
  - Log in as root.
    - If you have never logged in to the console before, the password is blank, and it will prompt you to change it.
  - Start the SSH service with `service sshd start`.
    - To make this change permanent, you can also type `chkconfig sshd on`.
- Transfer the script to the Master Node via your preferred SCP/SFTP client (such as WinSCP, Filezilla, etc)
  - A good place to put the file is /tmp/
  - You can also paste the text of the script into a new file using SSH and `vim`.
- Connect to the master node via your preferred SSH client (such as Putty or MobaXterm).
- Execute the script by typing `bash vrops-cluster-repair.bash`.
- Follow the prompts. The script is interactive and imbued with magic beard powers, let it be your guide.
- Verify that the UI comes up and that you are able to log in. It may take some time after the cluster has started.
  - If it comes up, rejoice!
  - If it errors out, [get mad](https://youtu.be/g8ufRnf2Exc)! ...then [file an issue](https://github.com/nakedhitman/vrops-cluster-repair/issues).
- ???
- Profit.

Please submit ideas for improving this script under [Issues](https://github.com/nakedhitman/vrops-cluster-repair/issues), tagged with [Feature Request] in the subject line.
