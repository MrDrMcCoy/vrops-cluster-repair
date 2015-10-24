# vrops-cluster-repair
A script that helps return the cluster to a healthy state.

## Things it does:

* Optionally clears out the alarms/alerts DB. Useful if a message is stuck in there.
* Archives malformed upgrade state files, which new updates will try to parse before they run. http://kb.vmware.com/kb/2120616
* Archives previous updates, patches and add-on Management Packs, which may cause issues if they still linger in your update queue.
* Archives large database blobs from a previous data migrations, which may choke the update process. http://kb.vmware.com/kb/2132479
* Alters the cluster state files to remove malformed data in them and set the cluster to a clean offline state. 
* Helps you check for time drift between the nodes, which is bad.
* Helps you check for latency issues between the nodes.
* It also has a disabled feature to clear out activities, which you can use in situations where a heavier hand is needed.

## Instructions for use:

* Enable SSH on all your nodes.
  * Open a VM console session to the node.
  * Press ALT+F1 to get to a console session.
  * Log in as root.
    * If you have never logged in to the console before, the password is blank, and it will prompt you to change it.
  * Start the SSH service with `service sshd start`.
    * To make this change permanent, you can also type `chkconfig sshd on`.
* Transfer the script to the Master Node via your preferred SCP/SFTP client (such as WinSCP, Filezilla, etc)
* Connect to the master node via your preferred SSH client (such as Putty or MobaXterm).
* Execute the script by typing `bash vrops-cluster-repair.bash` and follow the prompts.
  * If it does not detect all the nodes in your cluster, you should edit the file with `vim` and add them manually. There are comments in the file to guide you.

Please submit ideas for improving this script under Issues.
