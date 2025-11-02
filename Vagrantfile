
require "yaml"
vagrant_root = File.dirname(File.expand_path(__FILE__))
settings = YAML.load_file "#{vagrant_root}/settings.yaml"

IP_SECTIONS = settings["network"]["control_ip"].match(/^([0-9.]+\.)([^.]+)$/)
# First 3 octets including the trailing dot:
IP_NW = IP_SECTIONS.captures[0]
# Last octet excluding all dots:
IP_START = Integer(IP_SECTIONS.captures[1])
NUM_WORKER_NODES = settings["nodes"]["workers"]["count"]

# Check if OpenEBS Mayastor is enabled
MAYASTOR_ENABLED = settings["software"]["storage"] &&
                   settings["software"]["storage"]["openebs"] &&
                   settings["software"]["storage"]["openebs"]["networkpv"] &&
                   settings["software"]["storage"]["openebs"]["networkpv"]["mayastor"] &&
                   settings["software"]["storage"]["openebs"]["networkpv"]["mayastor"]["enabled"]

NUM_MAYASTOR_NODES = MAYASTOR_ENABLED && settings["nodes"]["mayastor"] ? settings["nodes"]["mayastor"]["count"] : 0

# Validate minimum mayastor nodes if OpenEBS Mayastor is enabled
if MAYASTOR_ENABLED && NUM_MAYASTOR_NODES < 3
  raise "ERROR: OpenEBS Mayastor requires at least 3 dedicated storage nodes for 3-way replication. Current count: #{NUM_MAYASTOR_NODES}. Please update settings.yaml -> nodes -> mayastor -> count to at least 3."
end

# Global VirtualBox optimizations (applies to all VMs)
VBOX_OPTIMIZE = settings["virtualbox"] && settings["virtualbox"]["optimize"] ? settings["virtualbox"]["optimize"] : false
VBOX_STORAGE_CONTROLLER = settings["virtualbox"] && settings["virtualbox"]["storage_controller"] ? settings["virtualbox"]["storage_controller"] : "sata"
VBOX_VM_FOLDER = settings["virtualbox"] && settings["virtualbox"]["vm_folder"] && !settings["virtualbox"]["vm_folder"].empty? ? settings["virtualbox"]["vm_folder"] : nil

# Change VirtualBox default machine folder if specified (affects OS disks location)
if VBOX_VM_FOLDER
  require 'fileutils'
  abs_vm_folder = File.expand_path(VBOX_VM_FOLDER)
  FileUtils.mkdir_p(abs_vm_folder) unless Dir.exist?(abs_vm_folder)

  # Save original VirtualBox default folder
  original_folder = `VBoxManage list systemproperties | grep "Default machine folder"`.strip.split(':').last.strip rescue nil

  # Set new default folder
  system("VBoxManage setproperty machinefolder \"#{abs_vm_folder}\"")

  puts "ℹ️  Changed VirtualBox VM folder to: #{abs_vm_folder}"
  puts "   ALL VMs and OS disks will be stored here"
  puts "   Original folder: #{original_folder}"

  # Register cleanup to restore original folder when done
  at_exit do
    if original_folder && !original_folder.empty?
      system("VBoxManage setproperty machinefolder \"#{original_folder}\"")
      puts "\nℹ️  Restored VirtualBox VM folder to: #{original_folder}"
    end
  end
end

Vagrant.configure("2") do |config|
  config.vm.provision "shell", env: { "IP_NW" => IP_NW, "IP_START" => IP_START, "NUM_WORKER_NODES" => NUM_WORKER_NODES, "NUM_MAYASTOR_NODES" => NUM_MAYASTOR_NODES }, inline: <<-SHELL
      apt-get update -y
      echo "$IP_NW$((IP_START)) controlplane" >> /etc/hosts
      for i in `seq 1 ${NUM_WORKER_NODES}`; do
        echo "$IP_NW$((IP_START+i)) node0${i}" >> /etc/hosts
      done
      for i in `seq 1 ${NUM_MAYASTOR_NODES}`; do
        echo "$IP_NW$((IP_START+NUM_WORKER_NODES+i)) storage0${i}" >> /etc/hosts
      done
  SHELL

  if `uname -m`.strip == "aarch64"
    config.vm.box = settings["software"]["box"] + "-arm64"
  else
    config.vm.box = settings["software"]["box"]
  end
  config.vm.box_check_update = true

  config.vm.define "controlplane" do |controlplane|
    controlplane.vm.hostname = "controlplane"
    controlplane.vm.network "private_network", ip: settings["network"]["control_ip"]
    # Shared containerd cache directory to persist images across vagrant destroy
    controlplane.vm.synced_folder "./containerd-cache/controlplane", "/var/lib/containerd-cache", create: true
    if settings["shared_folders"]
      settings["shared_folders"].each do |shared_folder|
        controlplane.vm.synced_folder shared_folder["host_path"], shared_folder["vm_path"]
      end
    end
    controlplane.vm.provider "virtualbox" do |vb|
        vb.cpus = settings["nodes"]["control"]["cpu"]
        vb.memory = settings["nodes"]["control"]["memory"]
        if settings["cluster_name"] and settings["cluster_name"] != ""
          vb.customize ["modifyvm", :id, "--groups", ("/" + settings["cluster_name"])]
        end

        # Apply global VirtualBox optimizations
        if VBOX_OPTIMIZE
          vb.customize ["modifyvm", :id, "--ioapic", "on"]
          vb.customize ["modifyvm", :id, "--paravirtprovider", "kvm"]
        end
    end
    controlplane.vm.provision "shell",
      env: {
        "DNS_SERVERS" => settings["network"]["dns_servers"].join(" "),
        "ENVIRONMENT" => settings["environment"],
        "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
        "KUBERNETES_VERSION_SHORT" => settings["software"]["kubernetes"][0..3],
        "OS" => settings["software"]["os"]
      },
      path: "scripts/common.sh"
    controlplane.vm.provision "shell",
      env: {
        "CALICO_VERSION" => settings["software"]["calico"],
        "CONTROL_IP" => settings["network"]["control_ip"],
        "POD_CIDR" => settings["network"]["pod_cidr"],
        "SERVICE_CIDR" => settings["network"]["service_cidr"]
      },
      path: "scripts/master.sh"
  end

  (1..NUM_WORKER_NODES).each do |i|

    config.vm.define "node0#{i}" do |node|
      node.vm.hostname = "node0#{i}"
      node.vm.network "private_network", ip: IP_NW + "#{IP_START + i}"
      # Shared containerd cache directory to persist images across vagrant destroy
      node.vm.synced_folder "./containerd-cache/node0#{i}", "/var/lib/containerd-cache", create: true
      if settings["shared_folders"]
        settings["shared_folders"].each do |shared_folder|
          node.vm.synced_folder shared_folder["host_path"], shared_folder["vm_path"]
        end
      end
      node.vm.provider "virtualbox" do |vb|
          vb.cpus = settings["nodes"]["workers"]["cpu"]
          vb.memory = settings["nodes"]["workers"]["memory"]
          if settings["cluster_name"] and settings["cluster_name"] != ""
            vb.customize ["modifyvm", :id, "--groups", ("/" + settings["cluster_name"])]
          end

          # Apply global VirtualBox optimizations
          if VBOX_OPTIMIZE
            vb.customize ["modifyvm", :id, "--ioapic", "on"]
            vb.customize ["modifyvm", :id, "--paravirtprovider", "kvm"]
          end
      end
      node.vm.provision "shell",
        env: {
          "DNS_SERVERS" => settings["network"]["dns_servers"].join(" "),
          "ENVIRONMENT" => settings["environment"],
          "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
          "KUBERNETES_VERSION_SHORT" => settings["software"]["kubernetes"][0..3],
          "OS" => settings["software"]["os"]
        },
        path: "scripts/common.sh"
      node.vm.provision "shell", path: "scripts/node.sh"

      # Only provision storage/dashboard on last worker if no mayastor nodes, otherwise on last mayastor node
      if NUM_MAYASTOR_NODES == 0 && i == NUM_WORKER_NODES
        # Check if any storage provider is enabled
        storage_enabled = settings["software"]["storage"] &&
                         ((settings["software"]["storage"]["longhorn"] && settings["software"]["storage"]["longhorn"]["enabled"]) ||
                          (settings["software"]["storage"]["openebs"] && settings["software"]["storage"]["openebs"]["networkpv"] && settings["software"]["storage"]["openebs"]["networkpv"]["mayastor"] && settings["software"]["storage"]["openebs"]["networkpv"]["mayastor"]["enabled"]) ||
                          (settings["software"]["storage"]["openebs"] && settings["software"]["storage"]["openebs"]["localpv"] && settings["software"]["storage"]["openebs"]["localpv"]["enabled"]))

        if storage_enabled
          node.vm.provision "shell", path: "scripts/storage.sh"
        end
        if settings["software"]["dashboard_helm"] and settings["software"]["dashboard_helm"] != ""
          node.vm.provision "shell", path: "scripts/dashboard.sh"
        end
      end
    end

  end

  # Dedicated Mayastor storage nodes (only created when storage_provider: openebs)
  (1..NUM_MAYASTOR_NODES).each do |i|

    config.vm.define "storage0#{i}" do |storage|
      storage.vm.hostname = "storage0#{i}"
      storage.vm.network "private_network", ip: IP_NW + "#{IP_START + NUM_WORKER_NODES + i}"
      # Shared containerd cache directory to persist images across vagrant destroy
      storage.vm.synced_folder "./containerd-cache/storage0#{i}", "/var/lib/containerd-cache", create: true
      if settings["shared_folders"]
        settings["shared_folders"].each do |shared_folder|
          storage.vm.synced_folder shared_folder["host_path"], shared_folder["vm_path"]
        end
      end
      storage.vm.provider "virtualbox" do |vb|
          vb.cpus = settings["nodes"]["mayastor"]["cpu"]
          vb.memory = settings["nodes"]["mayastor"]["memory"]
          if settings["cluster_name"] and settings["cluster_name"] != ""
            vb.customize ["modifyvm", :id, "--groups", ("/" + settings["cluster_name"])]
          end

          # Apply global VirtualBox optimizations
          if VBOX_OPTIMIZE
            vb.customize ["modifyvm", :id, "--ioapic", "on"]
            vb.customize ["modifyvm", :id, "--paravirtprovider", "kvm"]
          end

          # Storage controller configuration for additional Mayastor disk (from global settings)
          if VBOX_STORAGE_CONTROLLER == "virtio-scsi"
            # Create VirtIO-SCSI controller for Mayastor storage disk
            controller_name = "VirtIO SCSI"
            unless `VBoxManage showvminfo #{File.basename(Dir.pwd)}_storage0#{i}_* 2>&1`.include?(controller_name)
              vb.customize ["storagectl", :id, "--name", controller_name, "--add", "virtio-scsi", "--controller", "VirtIO-SCSI", "--portcount", 2, "--bootable", "on"]
            end
          else
            # Default SATA controller for storage disks
            controller_name = "SATA Controller"
          end

          # Additional disk for Mayastor storage pool
          disk_size = settings["nodes"]["mayastor"]["storage_disk"] * 1024  # Convert GB to MB
          # Disk file will be stored in the VM folder (controlled by vm_folder setting)
          if VBOX_VM_FOLDER
            # Use the configured VM folder
            disk_file = File.join(VBOX_VM_FOLDER, "vagrant-kubeadm-kubernetes", "storage0#{i}-disk.vdi")
          else
            # Fallback to project directory if vm_folder not set
            disk_file = "./storage0#{i}-disk.vdi"
          end
          vb.customize ["modifyvm", :id, "--boot1", "disk"]

          unless File.exist?(disk_file)
            vb.customize ["createhd", "--filename", disk_file, "--size", disk_size]

            # Apply disk optimizations (from global settings)
            if VBOX_OPTIMIZE
              vb.customize ["storageattach", :id, "--storagectl", controller_name, "--port", 1, "--device", 0,
                           "--type", "hdd", "--medium", disk_file,
                           "--nonrotational", "on",  # Mark as SSD for better I/O scheduling
                           "--discard", "on"]         # Enable TRIM/discard support
            else
              vb.customize ["storageattach", :id, "--storagectl", controller_name, "--port", 1, "--device", 0,
                           "--type", "hdd", "--medium", disk_file]
            end
          else
            # Disk already exists, just attach it
            vb.customize ["storageattach", :id, "--storagectl", controller_name, "--port", 1, "--device", 0,
                         "--type", "hdd", "--medium", disk_file]
          end
      end
      storage.vm.provision "shell",
        env: {
          "DNS_SERVERS" => settings["network"]["dns_servers"].join(" "),
          "ENVIRONMENT" => settings["environment"],
          "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
          "KUBERNETES_VERSION_SHORT" => settings["software"]["kubernetes"][0..3],
          "OS" => settings["software"]["os"]
        },
        path: "scripts/common.sh"
      storage.vm.provision "shell", path: "scripts/node.sh"

      # Only install the storage provider and dashboard after provisioning the last storage node
      if i == NUM_MAYASTOR_NODES
        # Check if any storage provider is enabled
        storage_enabled = settings["software"]["storage"] &&
                         ((settings["software"]["storage"]["longhorn"] && settings["software"]["storage"]["longhorn"]["enabled"]) ||
                          (settings["software"]["storage"]["openebs"] && settings["software"]["storage"]["openebs"]["networkpv"] && settings["software"]["storage"]["openebs"]["networkpv"]["mayastor"] && settings["software"]["storage"]["openebs"]["networkpv"]["mayastor"]["enabled"]) ||
                          (settings["software"]["storage"]["openebs"] && settings["software"]["storage"]["openebs"]["localpv"] && settings["software"]["storage"]["openebs"]["localpv"]["enabled"]))

        if storage_enabled
          storage.vm.provision "shell", path: "scripts/storage.sh"
        end
        if settings["software"]["dashboard_helm"] and settings["software"]["dashboard_helm"] != ""
          storage.vm.provision "shell", path: "scripts/dashboard.sh"
        end
      end
    end

  end
end 
